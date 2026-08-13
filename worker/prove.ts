/**
 * Attestation waiting, proof fetching, and submission to the Creditcoin registry.
 *
 * This is the heart of the worker: the four steps that turn a Sepolia transaction into a verified
 * fact inside a Creditcoin contract, and the only place the Attestcoin SDK is touched.
 */
import {ethers} from 'ethers';
import {proofProvider} from '@gluwa/usc-sdk';
import {GAS_BUFFER_PERCENT, GAS_LIMIT_FLOOR, PROVER_TIMEOUT_MS, type WorkerConfig} from './config.js';

/**
 * The shape the block-prover precompile needs, flattened out of the SDK's proof object exactly as
 * Gluwa's `utils/index.ts` does it.
 */
export interface ExecuteArgs {
  chainKey: number;
  height: number;
  encodedTransaction: string;
  merkleRoot: string;
  siblings: {hash: string; isLeft: boolean}[];
  lowerEndpointDigest: string;
  continuityRoots: string[];
}

/** Declared intent accompanying a proof. Unattested, so the registry validates but never trusts it. */
export const ACTION_REPAYMENT_MADE = 1;

/**
 * Waits until the source block is attested, then fetches its proof.
 *
 * @param config Worker configuration.
 * @param txHash Source-chain transaction to prove.
 * @param blockNumber Block containing it.
 */
export async function fetchProof(
  config: WorkerConfig,
  txHash: string,
  blockNumber: number,
): Promise<ExecuteArgs> {
  const builder = new proofProvider.service.ProofBuilder(
    config.chainKey,
    config.proofBuilderUrl,
    PROVER_TIMEOUT_MS,
  );

  // Sepolia attestation measures ~8-10 minutes. Polling every 15s with a generous ceiling
  // matches the reference examples; the wait is free and idempotent, so a timeout just means
  // running again later.
  await builder.waitUntilHeightAttested(config.chainKey, blockNumber, 15_000, 1_200_000);
  console.log(`  ✓ attested        block ${blockNumber} on chainKey ${config.chainKey}`);

  // getProof returns a {success, data, error} envelope rather than the proof itself.
  const result = await builder.getProof(txHash);
  if (!result.success || result.data === undefined) {
    throw new Error(`prover rejected ${txHash}: ${String(result.error ?? 'unknown error')}`);
  }
  const proof = result.data;
  console.log(
    `  ✓ proof fetched   ${proof.merkleProof.siblings.length} merkle siblings, ` +
      `${proof.continuityProof.roots.length} continuity roots`,
  );

  return {
    chainKey: proof.chainKey,
    height: proof.headerNumber,
    encodedTransaction: proof.txBytes,
    merkleRoot: proof.merkleProof.root,
    siblings: proof.merkleProof.siblings,
    lowerEndpointDigest: proof.continuityProof.lowerEndpointDigest,
    continuityRoots: proof.continuityProof.roots,
  };
}

/**
 * Submits a proof to `CreditRegistry.execute`, where the precompile verifies it and the registry
 * validates and applies it — all inside one Creditcoin block.
 *
 * @returns The mined Creditcoin receipt.
 */
export async function submitProof(
  registry: ethers.Contract,
  args: ExecuteArgs,
): Promise<ethers.ContractTransactionReceipt> {
  const call = [
    ACTION_REPAYMENT_MADE,
    args.chainKey,
    args.height,
    args.encodedTransaction,
    args.merkleRoot,
    args.siblings,
    args.lowerEndpointDigest,
    args.continuityRoots,
  ] as const;

  let gasLimit = GAS_LIMIT_FLOOR;
  try {
    const estimated = (await registry['execute']!.estimateGas(...call));
    const buffered = (estimated * GAS_BUFFER_PERCENT) / 100n;
    gasLimit = buffered > GAS_LIMIT_FLOOR ? buffered : GAS_LIMIT_FLOOR;
  } catch (error) {
    const reason = describe(error);

    // When estimation surfaces a *deterministic* revert, broadcasting anyway just burns gas on a
    // transaction that cannot succeed. The Gluwa examples fall into exactly this trap: their
    // fallback fires on any estimation failure and sends a doomed transaction. Bail out instead
    // and let the caller record it.
    if (reason.includes('Query already processed')) {
      throw new Error('Query already processed');
    }

    // Otherwise estimation failure is not proof of failure — pallet-evm does not reliably
    // propagate precompile revert reasons during estimation. Fall back to a floor sized from the
    // ~400k a real ingest costs, not the examples' formula, which computes ~70k.
    console.warn(`  ! gas estimation failed, using floor ${GAS_LIMIT_FLOOR}: ${reason}`);
  }

  const tx = (await registry['execute']!(...call, {gasLimit})) as ethers.ContractTransactionResponse;
  console.log(`  → submitted       ${tx.hash}`);

  const receipt = await tx.wait();
  if (receipt === null) throw new Error(`no receipt for ${tx.hash}`);
  // Gate on the outcome, never on an exit code or a resolved promise: Gluwa's own submit script
  // exits 0 on failure, and a mined transaction can still have reverted.
  if (receipt.status !== 1) throw new Error(`Creditcoin transaction ${tx.hash} reverted`);

  console.log(`  ✓ verified on CC3 block #${receipt.blockNumber} (gas ${receipt.gasUsed})`);
  return receipt;
}

export function describe(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
