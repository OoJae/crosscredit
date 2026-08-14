/**
 * Batch proof assembly — importing a whole credit history in one Creditcoin transaction.
 *
 * The saving comes from the shared continuity proof: verifying a foreign block means walking back
 * to a block Creditcoin has attested, and a batch does that walk once instead of once per proof.
 * The precompile caps a batch at 10 proofs whose source blocks fall inside a 1000-block window.
 */
import {ethers} from 'ethers';
import {proofProvider} from '@gluwa/usc-sdk';
import {PROVER_TIMEOUT_MS, type WorkerConfig} from './config.js';
import {describe} from './prove.js';

/**
 * Confirmed by probing the live CC3 precompile rather than read from the SDK, which has no such
 * constant: ten proofs pass the size gate, eleven revert with
 * `heights: Value is too large for length`.
 */
export const MAX_BATCH_SIZE = 10;

/** The precompile requires every source block in a batch to sit inside this window. */
export const MAX_BATCH_RANGE = 1000;

export interface BatchArgs {
  chainKey: number;
  /** Index-aligned with `sourceTxHashes` — the order we submit in, and the order results map back. */
  heights: number[];
  encodedTransactions: string[];
  merkleProofs: {root: string; siblings: {hash: string; isLeft: boolean}[]}[];
  continuityProof: {lowerEndpointDigest: string; roots: string[]};
  sourceTxHashes: string[];
}

/**
 * Fetches one shared-continuity proof covering several source transactions.
 *
 * @param config Worker configuration.
 * @param txHashes Source transactions to prove. At most {MAX_BATCH_SIZE}.
 *
 * @remarks
 * `getBatchProof` returns `Map<height, Map<txIndex, entry>>` rather than arrays, and iterates in
 * ascending height then txIndex — **not** the order the hashes were passed in. Flattening
 * positionally would therefore silently mis-attribute proofs to transactions whenever two land in
 * different blocks. Each entry carries its own `txHash`, so we key on that and rebuild the arrays
 * in the caller's order, then assert nothing was dropped.
 */
export async function fetchBatchProof(config: WorkerConfig, txHashes: string[]): Promise<BatchArgs> {
  if (txHashes.length === 0) throw new Error('cannot build a batch proof for zero transactions');
  if (txHashes.length > MAX_BATCH_SIZE) {
    throw new Error(`batch of ${txHashes.length} exceeds MAX_BATCH_SIZE ${MAX_BATCH_SIZE}`);
  }

  const builder = new proofProvider.service.ProofBuilder(
    config.chainKey,
    config.proofBuilderUrl,
    PROVER_TIMEOUT_MS,
  );

  const result = await builder.getBatchProof(txHashes);
  // The proof layer returns envelopes and never throws, unlike the prover layer which always does.
  if (!result.success || result.data === undefined) {
    throw new Error(`prover rejected batch: ${String(result.error ?? 'unknown error')}`);
  }
  const data = result.data;

  // Flatten the nested map, indexing by the transaction hash each entry reports for itself.
  const byTxHash = new Map<string, {height: number; txBytes: string; merkleProof: BatchArgs['merkleProofs'][number]}>();
  for (const [height, perIndex] of data.merkleProofs.entries()) {
    for (const entry of perIndex.values()) {
      byTxHash.set(entry.txHash.toLowerCase(), {
        height,
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
  };

  for (const txHash of txHashes) {
    const entry = byTxHash.get(txHash.toLowerCase());
    // A silent drop would shift every later proof onto the wrong transaction, so fail loudly.
    if (entry === undefined) throw new Error(`prover returned no proof for ${txHash}`);
    args.heights.push(entry.height);
    args.encodedTransactions.push(entry.txBytes);
    args.merkleProofs.push(entry.merkleProof);
    args.sourceTxHashes.push(txHash);
  }

  const span = Math.max(...args.heights) - Math.min(...args.heights);
  if (span >= MAX_BATCH_RANGE) {
    throw new Error(`batch spans ${span} blocks, exceeding MAX_BATCH_RANGE ${MAX_BATCH_RANGE}`);
  }

  console.log(
    `  ✓ batch proof     ${args.heights.length} transactions, ${span}-block span, ` +
      `${data.continuityProof.roots.length} shared continuity roots`,
  );
  return args;
}

/**
 * Dry-runs a batch against the precompile's `verify` view before spending anything.
 *
 * @remarks
 * Free, and it shares every validation step with the emit path — size, array parity, merkle
 * inclusion and continuity — so a passing dry-run means the only remaining failure modes are our
 * own registry checks. Well worth one `eth_call` before committing a transaction.
 *
 * @returns True when the precompile accepts the batch.
 */
export async function dryRunBatch(config: WorkerConfig, args: BatchArgs): Promise<boolean> {
  const prover = new ethers.Contract(
    '0x0000000000000000000000000000000000000FD2',
    [
      'function verify(uint64,uint64[],bytes[],(bytes32,(bytes32,bool)[])[],(bytes32,bytes32[])) view returns (bool)',
    ],
    config.cc3Provider,
  );

  try {
    const ok = (await prover['verify']!.staticCall(
      args.chainKey,
      args.heights,
      args.encodedTransactions,
      args.merkleProofs.map((p) => [p.root, p.siblings.map((s) => [s.hash, s.isLeft])]),
      [args.continuityProof.lowerEndpointDigest, args.continuityProof.roots],
    )) as boolean;
    console.log('  ✓ dry run         precompile accepts the batch (free staticCall)');
    return ok;
  } catch (error) {
    // Failure here is always a revert, never a `false` return.
    console.error(`  ✗ dry run failed  ${describe(error)}`);
    return false;
  }
}
