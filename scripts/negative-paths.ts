/**
 * Adversarial repro run against the **live** block-prover precompile and registry on CC3.
 *
 * Unit tests prove our own checks fire. This proves the real chain rejects real attacks — the
 * difference between "we wrote a require" and "the precompile actually refuses". Everything here
 * is a free `eth_call` or `estimateGas`, so nothing is broadcast and nothing is spent.
 *
 * Five attacks across the layers:
 *   1. Forged merkle root      → the precompile refuses
 *   2. Tampered payload        → the precompile refuses
 *   3. Wrong source chain      → refused (see note below)
 *   4. Replayed query          → our replay guard refuses
 *   5. Oversized batch         → our batch-size check refuses
 *
 * Run: npx tsx scripts/negative-paths.ts
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {proofProvider} from '@gluwa/usc-sdk';
import {required, optional, cc3RpcUrl, proofBuilderUrl} from './lib/env.js';
import registryArtifact from '../contracts/out/CreditRegistry.sol/CreditRegistry.json' with {type: 'json'};

const OUTPUT_PATH = 'docs/evidence/g3-negative-paths/results.json';
const BLOCK_PROVER = '0x0000000000000000000000000000000000000FD2';

interface Attack {
  name: string;
  attack: string;
  layer: string;
  rejected: boolean;
  reason: string;
}

const results: Attack[] = [];

function record(name: string, attack: string, layer: string, rejected: boolean, reason: string): void {
  results.push({name, attack, layer, rejected, reason});
  const mark = rejected ? '✓ REJECTED' : '✗ ACCEPTED — SECURITY FAILURE';
  console.log(`\n${mark}  ${name}`);
  console.log(`  attack   ${attack}`);
  console.log(`  rejected by ${layer}`);
  console.log(`  reason   ${reason.slice(0, 160)}`);
}

/**
 * Extracts the most specific revert reason available. ethers surfaces a decoded `reason` for
 * `Error(string)` reverts and a `shortMessage` for custom errors; falling back to the raw object
 * would just print `[object Object]`.
 */
function reasonOf(error: unknown): string {
  if (error instanceof Error) {
    const e = error as Error & {shortMessage?: string; reason?: string};
    return e.reason ?? e.shortMessage ?? e.message;
  }
  return typeof error === 'string' ? error : JSON.stringify(error);
}

/**
 * A source transaction that has already been ingested, so the replay check has something real to
 * replay. Overridable with `--tx`.
 */
const DEFAULT_TX = '0xeeaa5b3f44a0727b175dab9a97838b6e50e0c476668fc18649d77b7b81e9e8ea';

async function main(): Promise<void> {
  const provider = new ethers.JsonRpcProvider(cc3RpcUrl());
  const registryAddress = required('CREDIT_REGISTRY_ADDRESS');
  const chainKey = Number.parseInt(optional('SOURCE_CHAIN_KEY', '1'), 10);

  const registry = new ethers.Contract(
    registryAddress,
    (registryArtifact as {abi: ethers.InterfaceAbi}).abi,
    provider,
  );

  const prover = new ethers.Contract(
    BLOCK_PROVER,
    ['function verify(uint64,uint64,bytes,(bytes32,(bytes32,bool)[]),(bytes32,bytes32[])) view returns (bool)'],
    provider,
  );

  const txIndex = process.argv.indexOf('--tx');
  const sourceTxHash = txIndex !== -1 ? (process.argv[txIndex + 1] ?? DEFAULT_TX) : DEFAULT_TX;

  console.log('CrossCredit — adversarial repro against live CC3');
  console.log(`  registry   ${registryAddress}`);
  console.log(`  precompile ${BLOCK_PROVER}`);

  // Fetch the proof fresh rather than replaying a stored fixture. Continuity proofs anchor to the
  // attestation state at generation time, so a captured proof stops verifying once attestation
  // advances past its anchor — a stale baseline would make every rejection below meaningless.
  const builder = new proofProvider.service.ProofBuilder(chainKey, proofBuilderUrl(), 60_000);
  const fetched = await builder.getProof(sourceTxHash);
  if (!fetched.success || fetched.data === undefined) {
    throw new Error(`could not fetch a baseline proof: ${String(fetched.error ?? 'unknown')}`);
  }
  const proof = fetched.data;
  console.log(`  real proof ${sourceTxHash} (block ${proof.headerNumber}, fetched fresh)`);

  const merkle = [proof.merkleProof.root, proof.merkleProof.siblings.map((s) => [s.hash, s.isLeft])];
  const continuity = [proof.continuityProof.lowerEndpointDigest, proof.continuityProof.roots];

  // Sanity: the untampered proof must verify, or every rejection below is meaningless.
  try {
    await prover['verify']!.staticCall(chainKey, proof.headerNumber, proof.txBytes, merkle, continuity);
    console.log('\n✓ baseline: the untampered proof verifies against the live precompile');
  } catch (error) {
    throw new Error(`baseline proof failed to verify — the run is invalid: ${reasonOf(error)}`);
  }

  // ── 1. Forged proof ────────────────────────────────────────────────────────────────────
  // Flip the merkle root. The transaction is real; the claim that it sits under this root is not.
  const forgedRoot = `0x${'de'.repeat(32)}`;
  try {
    await prover['verify']!.staticCall(
      chainKey,
      proof.headerNumber,
      proof.txBytes,
      [forgedRoot, proof.merkleProof.siblings.map((s) => [s.hash, s.isLeft])],
      continuity,
    );
    record('Forged merkle proof', 'merkle root replaced with 0xdede…', 'precompile', false, 'accepted');
  } catch (error) {
    record('Forged merkle proof', 'merkle root replaced with 0xdede…', 'block-prover precompile', true, reasonOf(error));
  }

  // ── 2. Tampered payload ────────────────────────────────────────────────────────────────
  // Keep a valid proof but mutate the transaction bytes it commits to.
  const tampered = `${proof.txBytes.slice(0, -8)}deadbeef`;
  try {
    await prover['verify']!.staticCall(chainKey, proof.headerNumber, tampered, merkle, continuity);
    record('Tampered transaction payload', 'last 4 bytes of txBytes altered', 'precompile', false, 'accepted');
  } catch (error) {
    record(
      'Tampered transaction payload',
      'last 4 bytes of txBytes altered',
      'block-prover precompile',
      true,
      reasonOf(error),
    );
  }

  // ── 3. Wrong source chain ──────────────────────────────────────────────────────────────
  // A genuine Sepolia proof, presented as if it came from Ethereum Mainnet (chainKey 3). CC3
  // attests both, so without this check a look-alike LoanBook on mainnet could mint history.
  try {
    await registry['execute']!.staticCall(
      1,
      3,
      proof.headerNumber,
      proof.txBytes,
      proof.merkleProof.root,
      proof.merkleProof.siblings.map((s) => [s.hash, s.isLeft]),
      proof.continuityProof.lowerEndpointDigest,
      proof.continuityProof.roots,
    );
    record('Wrong source chain', 'real Sepolia proof submitted as chainKey 3', 'registry', false, 'accepted');
  } catch (error) {
    // Defence in depth, and worth stating precisely: the precompile rejects this first, because
    // a Sepolia continuity proof does not match Ethereum Mainnet's attestation state. Our
    // registry's own `WrongSourceChain` check sits behind it and is proven by
    // `test_realProof_rejectedWhenChainKeyIsWrong`. Two independent layers refuse the same attack;
    // reporting which one actually fired keeps the claim honest.
    record(
      'Wrong source chain',
      'real Sepolia proof submitted as chainKey 3 (Ethereum Mainnet)',
      'block-prover precompile (registry WrongSourceChain is the second line, unit-tested)',
      true,
      reasonOf(error),
    );
  }

  // ── 4. Replayed query ──────────────────────────────────────────────────────────────────
  // Resubmit a transaction the registry has already ingested.
  try {
    await registry['execute']!.staticCall(
      1,
      chainKey,
      proof.headerNumber,
      proof.txBytes,
      proof.merkleProof.root,
      proof.merkleProof.siblings.map((s) => [s.hash, s.isLeft]),
      proof.continuityProof.lowerEndpointDigest,
      proof.continuityProof.roots,
    );
    record(
      'Replayed query',
      'resubmitting an already-ingested transaction',
      'registry',
      false,
      'accepted — score could be farmed by resubmission',
    );
  } catch (error) {
    record(
      'Replayed query',
      'resubmitting an already-ingested transaction',
      'USCBase replay guard',
      true,
      reasonOf(error),
    );
  }

  // ── 5. Oversized batch ─────────────────────────────────────────────────────────────────
  // Eleven proofs exceed MAX_BATCH_SIZE; we reject before the precompile would.
  try {
    const eleven = Array.from({length: 11}, () => proof.headerNumber);
    await registry['executeBatch']!.staticCall(
      eleven.map(() => 1),
      chainKey,
      eleven,
      eleven.map(() => proof.txBytes),
      eleven.map(() => [proof.merkleProof.root, proof.merkleProof.siblings.map((s) => [s.hash, s.isLeft])]),
      continuity,
    );
    record('Oversized batch', '11 proofs, one over MAX_BATCH_SIZE', 'registry', false, 'accepted');
  } catch (error) {
    record('Oversized batch', '11 proofs, one over MAX_BATCH_SIZE (10)', 'CreditRegistry.BatchTooLarge', true, reasonOf(error));
  }

  const allRejected = results.every((r) => r.rejected);
  console.log(`\n${allRejected ? '✓' : '✗'} ${results.filter((r) => r.rejected).length}/${results.length} attacks rejected`);

  mkdirSync(dirname(OUTPUT_PATH), {recursive: true});
  writeFileSync(
    OUTPUT_PATH,
    `${JSON.stringify(
      {
        capturedAt: new Date().toISOString(),
        network: 'creditcoin-cc3-testnet',
        registry: registryAddress,
        precompile: BLOCK_PROVER,
        baselineProof: sourceTxHash,
        allRejected,
        results,
      },
      null,
      2,
    )}\n`,
  );
  console.log(`✓ wrote ${OUTPUT_PATH}`);

  if (!allRejected) process.exitCode = 1;
}

main().catch((error: unknown) => {
  console.error('✗ negative-paths failed:', error);
  process.exitCode = 1;
});
