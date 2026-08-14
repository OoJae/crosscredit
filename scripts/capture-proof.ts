/**
 * Captures a real Attestcoin proof for an already-attested source transaction and saves it as a
 * test fixture.
 *
 * Why this exists: proofs are the one input we cannot invent. `EvmV1Decoder` parses a bespoke
 * encoding of an Ethereum transaction + receipt, and a hand-written `bytes` blob would prove
 * nothing about whether our decoding is correct. A captured proof gives us
 *   - real `txBytes` to unit-test the registry's decode-and-validate chain against, and
 *   - a golden proof replayable against the live precompile's `verify` **view** in a fork test.
 *
 * It is free to run: the source block is already attested, so the prover serves from cache, and
 * `verify` is a view call that costs no gas.
 *
 * Run: npx tsx scripts/capture-proof.ts <txHash> [outputPath]
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {proofProvider} from '@gluwa/usc-sdk';
import {optional, proofBuilderUrl} from './lib/env.js';

const DEFAULT_OUTPUT = 'contracts/test/fixtures/g0-proof.json';

// The SDK's default HTTP timeout is 10s, which we have already seen expire against a cold
// prover cache. Proof payloads can be large, so allow considerably longer.
const PROVER_TIMEOUT_MS = 60_000;

/**
 * Creditcoin attests two source chains. Sepolia carries our own LoanBook; Ethereum mainnet
 * carries the real DeFi history that actually matters, and needs an archive RPC because the
 * transactions we prove can be years old.
 */
const CHAINS: Record<number, {name: string; rpcEnv: string; fallbackRpc: string}> = {
  1: {
    name: 'Ethereum Sepolia',
    rpcEnv: 'SEPOLIA_RPC_URL',
    fallbackRpc: 'https://ethereum-sepolia-rpc.publicnode.com',
  },
  3: {
    name: 'Ethereum Mainnet',
    rpcEnv: 'MAINNET_RPC_URL',
    // Serves archive eth_getLogs without a key, which most public endpoints refuse.
    fallbackRpc: 'https://rpc.mevblocker.io',
  },
};

async function main(): Promise<void> {
  const txHash = process.argv[2];
  const outputPath = process.argv[3] ?? DEFAULT_OUTPUT;

  if (txHash === undefined || !/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
    throw new Error('Usage: npx tsx scripts/capture-proof.ts <txHash> [outputPath] [--chain-key N]');
  }

  const keyFlag = process.argv.indexOf('--chain-key');
  const chainKey =
    keyFlag === -1
      ? Number.parseInt(optional('SOURCE_CHAIN_KEY', '1'), 10)
      : Number.parseInt(process.argv[keyFlag + 1] ?? '1', 10);

  const chain = CHAINS[chainKey];
  if (chain === undefined) throw new Error(`unknown chainKey ${chainKey}`);
  const sourceRpc = new ethers.JsonRpcProvider(optional(chain.rpcEnv, chain.fallbackRpc));

  const tx = await sourceRpc.getTransaction(txHash);
  if (tx === null) throw new Error(`Transaction ${txHash} not found on the source chain`);
  if (tx.blockNumber === null) throw new Error(`Transaction ${txHash} is not yet mined`);

  const receipt = await sourceRpc.getTransactionReceipt(txHash);

  console.log(`tx        ${txHash}`);
  console.log(`block     ${tx.blockNumber}`);
  console.log(`status    ${receipt?.status === 1 ? 'success' : 'FAILED'}`);
  console.log(`chainKey  ${chainKey} (${chain.name})`);
  console.log(`logs      ${receipt?.logs.length ?? 0}`);

  const builder = new proofProvider.service.ProofBuilder(chainKey, proofBuilderUrl(), PROVER_TIMEOUT_MS);
  console.log('\nfetching proof…');

  // getProof returns a ProofResult envelope — {success, data, error} — not the proof itself.
  // Unwrap it here so the fixture holds the proof fields the contract's execute() consumes.
  const result = await builder.getProof(txHash);
  if (!result.success || result.data === undefined) {
    throw new Error(`Prover rejected the request: ${String(result.error ?? 'unknown error')}`);
  }
  const proof = result.data;
  console.log('✓ proof fetched');
  console.log(`  headerNumber   ${proof.headerNumber}`);
  console.log(`  txBytes        ${proof.txBytes.length} chars`);
  console.log(`  merkle sibs    ${proof.merkleProof.siblings.length}`);
  console.log(`  continuity     ${proof.continuityProof.roots.length} roots`);

  const payload = {
    capturedAt: new Date().toISOString(),
    note: 'Real Attestcoin proof captured from the live CC3 testnet prover. Test fixture only.',
    sourceTxHash: txHash,
    sourceBlockNumber: tx.blockNumber,
    sourceReceiptStatus: receipt?.status ?? null,
    emittedBy: receipt?.to ?? null,
    logCount: receipt?.logs.length ?? 0,
    chainKey,
    chainName: chain.name,
    proof,
  };

  mkdirSync(dirname(outputPath), {recursive: true});
  writeFileSync(
    outputPath,
    `${JSON.stringify(payload, (_key, value: unknown) => (typeof value === 'bigint' ? value.toString() : value), 2)}\n`,
  );

  console.log(`\n✓ wrote ${outputPath}`);
}

main().catch((error: unknown) => {
  console.error('✗ capture-proof failed:', error);
  process.exitCode = 1;
});
