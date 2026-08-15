/**
 * Capture the block-prover precompile's OWN batch-size ceiling, directly, with no registry
 * in between.
 *
 * The docs state the cap of 10; our registry enforces it early with a legible `BatchTooLarge`
 * (see `negative-paths.ts`, attack 5), which means the precompile's native refusal never appears
 * in any of our on-chain evidence. This script bypasses the registry and staticCalls the
 * precompile's batch `verifyAndEmit` overload with 10 and then 11 copies of one valid,
 * freshly-fetched proof:
 *
 *   10 → verifies (duplicates are the registry's concern, not the prover's)
 *   11 → reverts inside the precompile's SCALE decoding — the message is the artifact
 *
 * Everything is a free `eth_call`; nothing is broadcast.
 *
 * Run: npx tsx scripts/probe-batch-ceiling.ts
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {proofProvider} from '@gluwa/usc-sdk';
import {optional, cc3RpcUrl, proofBuilderUrl} from './lib/env.js';

const OUTPUT_PATH = 'docs/evidence/precompile-batch-ceiling/results.json';
const BLOCK_PROVER = '0x0000000000000000000000000000000000000FD2';

/** The single-ingest benchmark transaction — ingested history, so the proof is fetchable. */
const DEFAULT_TX = '0x290f52826a71a27ee78f3653fb914952d4825295908438ce60fbbac8f6acc90e';

function reasonOf(error: unknown): string {
  if (error instanceof Error) {
    const shortMessage = (error as {shortMessage?: string}).shortMessage;
    const revert = (error as {revert?: {args?: unknown[]}}).revert;
    if (revert?.args?.length) return String(revert.args[0]);
    return shortMessage ?? error.message;
  }
  return typeof error === 'string' ? error : JSON.stringify(error);
}

async function main(): Promise<void> {
  const provider = new ethers.JsonRpcProvider(cc3RpcUrl());
  const chainKey = Number.parseInt(optional('SOURCE_CHAIN_KEY', '1'), 10);

  const prover = new ethers.Contract(
    BLOCK_PROVER,
    [
      'function verifyAndEmit(uint64,uint64[],bytes[],(bytes32,(bytes32,bool)[])[],(bytes32,bytes32[])) returns (bool)',
    ],
    provider,
  );

  const txArg = process.argv.indexOf('--tx');
  const sourceTxHash = txArg !== -1 ? (process.argv[txArg + 1] ?? DEFAULT_TX) : DEFAULT_TX;

  console.log('CrossCredit — probing the precompile batch ceiling, no registry in between');
  console.log(`  precompile ${BLOCK_PROVER}`);

  const builder = new proofProvider.service.ProofBuilder(chainKey, proofBuilderUrl(), 60_000);
  const fetched = await builder.getProof(sourceTxHash);
  if (!fetched.success || fetched.data === undefined) {
    throw new Error(`could not fetch a proof: ${String(fetched.error ?? 'unknown')}`);
  }
  const proof = fetched.data;
  console.log(`  real proof ${sourceTxHash} (block ${proof.headerNumber}, fetched fresh)`);

  const merkle = [proof.merkleProof.root, proof.merkleProof.siblings.map((s) => [s.hash, s.isLeft])];
  const continuity = [proof.continuityProof.lowerEndpointDigest, proof.continuityProof.roots];

  const results: Array<{size: number; verified: boolean; reason: string}> = [];

  for (const size of [10, 11]) {
    const heights = Array.from({length: size}, () => proof.headerNumber);
    const txs = heights.map(() => proof.txBytes);
    const proofs = heights.map(() => merkle);
    try {
      await prover['verifyAndEmit']!.staticCall(chainKey, heights, txs, proofs, continuity);
      results.push({size, verified: true, reason: 'verified'});
      console.log(`\n✓ ${size} proofs: the precompile verifies the batch`);
    } catch (error) {
      const reason = reasonOf(error);
      results.push({size, verified: false, reason});
      console.log(`\n✗ ${size} proofs: reverted inside the precompile`);
      console.log(`  reason  ${reason}`);
    }
  }

  const ceilingShown =
    results[0]?.verified === true && results[1]?.verified === false;
  if (!ceilingShown) {
    console.log('\n⚠ the 10-pass/11-revert boundary did NOT reproduce — do not cite this run');
  } else {
    console.log('\n✓ ceiling confirmed at the precompile itself: 10 verifies, 11 reverts');
  }

  mkdirSync(dirname(OUTPUT_PATH), {recursive: true});
  writeFileSync(
    OUTPUT_PATH,
    `${JSON.stringify(
      {
        capturedAt: new Date().toISOString(),
        network: 'creditcoin-cc3-testnet',
        precompile: BLOCK_PROVER,
        method: 'direct staticCall of the batch verifyAndEmit overload, registry bypassed',
        sourceTxHash,
        sourceBlock: proof.headerNumber,
        ceilingShown,
        results,
      },
      null,
      2,
    )}\n`,
  );
  console.log(`✓ wrote ${OUTPUT_PATH}`);
}

main().catch((error: unknown) => {
  console.error(reasonOf(error));
  process.exit(1);
});
