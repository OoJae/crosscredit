import type {Address, Hex, PublicClient} from 'viem';
import {ADDRESSES, PROVER_URL, SOURCE_CHAIN_KEY} from './config';
import {blockProverAbi} from './abis';

/**
 * Browser client for Creditcoin's hosted proof builder.
 *
 * Deliberately plain `fetch` rather than `@gluwa/usc-sdk`. The SDK's single-proof call returns the
 * API response completely untransformed, so it adds nothing here — while importing it would pull
 * ethers v6 in alongside viem (two ABI coders in one bundle) and reach for `process.env`, which
 * does not exist in a browser build.
 *
 * CORS is open on the prover (`access-control-allow-origin: *`, `GET,POST,OPTIONS`), which is what
 * makes a backend-free frontend possible at all.
 */

/** Precompile limits, both confirmed by probing the live chain rather than read from a doc. */
export const MAX_BATCH_SIZE = 10;
export const MAX_BATCH_RANGE = 1000;

export interface MerkleProofJson {
  root: Hex;
  siblings: {hash: Hex; isLeft: boolean}[];
}

export interface ContinuityProofJson {
  lowerEndpointDigest: Hex;
  roots: Hex[];
}

interface BatchProofResponse {
  chainKey: number;
  fromHeader: number;
  toHeader: number;
  continuityProof: ContinuityProofJson;
  /** Keyed by block height, then by transaction index within that block. */
  merkleProofs: Record<string, Record<string, {txHash: string; txBytes: Hex; merkleProof: MerkleProofJson}>>;
  cached: boolean;
  generatedAt: string;
}

/** Batch arguments, index-aligned with the transaction hashes that produced them. */
export interface BatchArgs {
  chainKey: number;
  heights: bigint[];
  encodedTransactions: Hex[];
  merkleProofs: MerkleProofJson[];
  continuityProof: ContinuityProofJson;
  sourceTxHashes: string[];
  blockSpan: number;
}

/** How far Creditcoin has attested the source chain. Nothing past this can be proven yet. */
export async function fetchAttestedHeight(chainKey = SOURCE_CHAIN_KEY): Promise<bigint> {
  const response = await fetch(`${PROVER_URL}/api/v1/attested-height/${chainKey}`);
  if (!response.ok) throw new Error(`prover returned ${response.status} for attested height`);
  const json = (await response.json()) as {attestedHeight?: number};
  if (json.attestedHeight === undefined) throw new Error('prover has no attested height cached yet');
  return BigInt(json.attestedHeight);
}

/**
 * Fetches one shared-continuity proof covering several source transactions.
 *
 * @remarks
 * The response nests proofs as `{height: {txIndex: entry}}` and iterates ascending height then
 * index — **not** the order the hashes were sent. Flattening positionally would silently attach
 * the wrong proof to a transaction whenever two land in different blocks, which for us would mean
 * crediting the wrong borrower. Every entry names its own `txHash`, so that is what we key on, and
 * we fail loudly if the prover returns fewer proofs than we asked for.
 */
export async function fetchBatchProof(
  txHashes: string[],
  chainKey = SOURCE_CHAIN_KEY,
): Promise<BatchArgs> {
  if (txHashes.length === 0) throw new Error('nothing to prove');
  if (txHashes.length > MAX_BATCH_SIZE) {
    throw new Error(`${txHashes.length} transactions exceeds the batch limit of ${MAX_BATCH_SIZE}`);
  }

  const response = await fetch(`${PROVER_URL}/api/v1/proof-batch-by-tx/${chainKey}`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(txHashes),
  });
  if (!response.ok) throw new Error(`prover returned ${response.status} for the batch proof`);
  const data = (await response.json()) as BatchProofResponse;

  const byTxHash = new Map<string, {height: bigint; txBytes: Hex; merkleProof: MerkleProofJson}>();
  for (const [height, perIndex] of Object.entries(data.merkleProofs)) {
    for (const entry of Object.values(perIndex)) {
      byTxHash.set(entry.txHash.toLowerCase(), {
        height: BigInt(height),
        txBytes: entry.txBytes,
        merkleProof: entry.merkleProof,
      });
    }
  }

  const args: BatchArgs = {
    chainKey: data.chainKey,
    heights: [],
    encodedTransactions: [],
    merkleProofs: [],
    continuityProof: data.continuityProof,
    sourceTxHashes: [],
    blockSpan: 0,
  };

  for (const txHash of txHashes) {
    const entry = byTxHash.get(txHash.toLowerCase());
    if (entry === undefined) throw new Error(`the prover returned no proof for ${txHash}`);
    args.heights.push(entry.height);
    args.encodedTransactions.push(entry.txBytes);
    args.merkleProofs.push(entry.merkleProof);
    args.sourceTxHashes.push(txHash);
  }

  const numeric = args.heights.map(Number);
  args.blockSpan = Math.max(...numeric) - Math.min(...numeric);
  if (args.blockSpan >= MAX_BATCH_RANGE) {
    throw new Error(
      `history spans ${args.blockSpan} blocks, over the ${MAX_BATCH_RANGE}-block limit for one shared proof`,
    );
  }

  return args;
}

/**
 * Asks the precompile whether it would accept this batch, without spending anything.
 *
 * @remarks
 * The `verify` view shares every validation step with the transaction path — size, array parity,
 * merkle inclusion, continuity — so a pass means the only thing left that can fail is our own
 * registry's checks. Running it before the wallet prompt means a user is never asked to sign a
 * million-gas transaction that cannot succeed.
 */
export async function dryRunBatch(client: PublicClient, args: BatchArgs): Promise<void> {
  await client.readContract({
    address: ADDRESSES.blockProver as Address,
    abi: blockProverAbi,
    functionName: 'verify',
    args: [
      BigInt(args.chainKey),
      args.heights,
      args.encodedTransactions,
      args.merkleProofs,
      args.continuityProof,
    ],
  });
}
