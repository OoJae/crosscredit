/**
 * Proves a **real Ethereum mainnet transaction** into CrossCredit's registry on Creditcoin.
 *
 * This is the script that answers "who was the lender?". Our own `LoanBook` on Sepolia has none —
 * anyone can open a loan with a self-declared principal and repay it to nobody — so history from
 * it is cheap to manufacture. An Aave repayment cannot be faked: Aave's pool is a real
 * counterparty whose capital was genuinely at risk, and the borrower is named in an indexed topic
 * of a log inside a transaction Creditcoin's precompile verified for itself.
 *
 * Ingestion is permissionless. The borrower is read from the proven log, never from `msg.sender`,
 * so anyone can import anyone's public history — and nobody can import it *as* themselves.
 *
 * Run:
 *   npx tsx scripts/prove-mainnet.ts <mainnetTxHash>
 *   npx tsx scripts/prove-mainnet.ts --find-aave    # locate a recent attested Aave repayment
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {proofProvider} from '@gluwa/usc-sdk';
import {required, optional, cc3RpcUrl, proofBuilderUrl} from './lib/env.js';
import registryArtifact from '../contracts/out/CreditRegistry.sol/CreditRegistry.json' with {type: 'json'};

const OUTPUT_PATH = 'docs/evidence/g5-mainnet-credit/results.json';

/** Creditcoin-internal id for Ethereum mainnet. Not the EVM chain id. */
const MAINNET_CHAIN_KEY = 3;

/** Serves archive `eth_getLogs` without an API key, which most public endpoints refuse. */
const MAINNET_RPC_FALLBACK = 'https://rpc.mevblocker.io';

const AAVE_V3_POOL = '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2';
const AAVE_REPAY_TOPIC = '0xa534c8dbe71f871f9f3530e97a74601fea17b426cae02e1c5aee42c96c784051';

const PROVER_TIMEOUT_MS = 60_000;

async function attestedHeight(): Promise<number> {
  const response = await fetch(`${proofBuilderUrl()}/api/v1/attested-height/${MAINNET_CHAIN_KEY}`);
  const json = (await response.json()) as {attestedHeight: number};
  return json.attestedHeight;
}

/**
 * Finds a recent Aave V3 repayment that Creditcoin has already attested.
 *
 * @remarks
 * Only searches below the attested height — the prover cannot serve a proof for a block it has
 * not yet seen attested, so anything newer would simply fail.
 */
async function findRecentAaveRepay(provider: ethers.JsonRpcProvider): Promise<string[]> {
  const attested = await attestedHeight();
  const logs = await provider.getLogs({
    address: AAVE_V3_POOL,
    topics: [AAVE_REPAY_TOPIC],
    fromBlock: attested - 400,
    toBlock: attested - 10,
  });

  console.log(`Found ${logs.length} attested Aave V3 repayments in the last 400 blocks:\n`);
  for (const log of logs.slice(0, 8)) {
    const borrower = ethers.getAddress(`0x${log.topics[2]!.slice(-40)}`);
    console.log(`  block ${log.blockNumber}  borrower ${borrower}`);
    console.log(`    ${log.transactionHash}`);
  }
  return logs.map((l) => l.transactionHash);
}

async function main(): Promise<void> {
  const mainnetRpc = new ethers.JsonRpcProvider(optional('MAINNET_RPC_URL', MAINNET_RPC_FALLBACK));

  if (process.argv.includes('--find-aave')) {
    await findRecentAaveRepay(mainnetRpc);
    return;
  }

  const txHash = process.argv[2];
  if (txHash === undefined || !/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
    throw new Error('Usage: npx tsx scripts/prove-mainnet.ts <mainnetTxHash> | --find-aave');
  }

  const cc3 = new ethers.JsonRpcProvider(cc3RpcUrl());
  const wallet = new ethers.Wallet(required('DEPLOYER_PRIVATE_KEY'), cc3);
  const registryAddress = required('CREDIT_REGISTRY_ADDRESS');
  const registry = new ethers.Contract(
    registryAddress,
    (registryArtifact as {abi: ethers.InterfaceAbi}).abi,
    wallet,
  );

  console.log('CrossCredit — proving real Ethereum mainnet history to Creditcoin\n');
  console.log(`  mainnet tx  ${txHash}`);
  console.log(`  registry    ${registryAddress} (CC3)`);

  const receipt = await mainnetRpc.getTransactionReceipt(txHash);
  if (receipt === null) throw new Error('transaction not found on Ethereum mainnet');

  // Identify the borrower from the log itself, exactly as the contract will.
  const aaveLog = receipt.logs.find(
    (l) => l.address.toLowerCase() === AAVE_V3_POOL.toLowerCase() && l.topics[0] === AAVE_REPAY_TOPIC,
  );
  if (aaveLog === undefined) throw new Error('no Aave V3 Repay event in that transaction');
  const borrower = ethers.getAddress(`0x${aaveLog.topics[2]!.slice(-40)}`);
  const decoded = ethers.AbiCoder.defaultAbiCoder().decode(['uint256', 'bool'], aaveLog.data);
  const amount = decoded[0] as bigint;

  console.log(`  block       ${receipt.blockNumber}`);
  console.log(`  borrower    ${borrower}`);
  console.log(`  repaid      ${amount} (reserve units)`);
  console.log(`  logs in tx  ${receipt.logs.length} — from several unrelated protocols\n`);

  const before = (await registry['profileOf']!(borrower)) as {score: bigint; mainnetRepayments: bigint};
  console.log(`  score before: ${before.score}  (mainnet repayments: ${before.mainnetRepayments})`);

  const attested = await attestedHeight();
  if (receipt.blockNumber > attested) {
    throw new Error(`block ${receipt.blockNumber} is not attested yet (attested height ${attested})`);
  }

  const builder = new proofProvider.service.ProofBuilder(
    MAINNET_CHAIN_KEY,
    proofBuilderUrl(),
    PROVER_TIMEOUT_MS,
  );
  const result = await builder.getProof(txHash);
  if (!result.success || result.data === undefined) {
    throw new Error(`prover rejected the request: ${String(result.error ?? 'unknown')}`);
  }
  const proof = result.data;
  console.log(
    `  ✓ proof       ${proof.merkleProof.siblings.length} merkle siblings, ` +
      `${proof.continuityProof.roots.length} continuity roots`,
  );

  const call = [
    0, // action is a hint only; dispatch is driven by the log's emitter and topic0
    MAINNET_CHAIN_KEY,
    proof.headerNumber,
    proof.txBytes,
    proof.merkleProof.root,
    proof.merkleProof.siblings,
    proof.continuityProof.lowerEndpointDigest,
    proof.continuityProof.roots,
  ] as const;

  let gasLimit = 2_000_000n;
  try {
    const estimated = await registry['execute']!.estimateGas(...call);
    gasLimit = (estimated * 140n) / 100n;
  } catch (error) {
    console.warn(`  ! gas estimation failed, using floor: ${String(error)}`);
  }

  const tx = (await registry['execute']!(...call, {gasLimit})) as ethers.ContractTransactionResponse;
  console.log(`  → submitted   ${tx.hash}`);
  const cc3Receipt = await tx.wait();
  if (cc3Receipt === null || cc3Receipt.status !== 1) throw new Error('the Creditcoin transaction reverted');

  console.log(`  ✓ verified on CC3 block #${cc3Receipt.blockNumber} (gas ${cc3Receipt.gasUsed})`);

  const after = (await registry['profileOf']!(borrower)) as {score: bigint; mainnetRepayments: bigint};
  const capacity = (await registry['demonstratedCapacityOf']!(borrower)) as bigint;
  const tier = ['Bronze', 'Silver', 'Gold', 'Platinum'][Number((await registry['tierOf']!(borrower)) as bigint)];

  console.log(`\n  ★ ${borrower}`);
  console.log(`    score ${before.score} → ${after.score}, tier ${tier}`);
  console.log(`    mainnet repayments: ${after.mainnetRepayments}`);
  console.log(`    demonstrated capacity: ${capacity}`);
  console.log('\n  This address has never interacted with Creditcoin. Its creditworthiness was');
  console.log('  established entirely from a transaction it made on Ethereum, proven here.');

  const payload = {
    capturedAt: new Date().toISOString(),
    claim: 'A real Ethereum mainnet Aave V3 repayment, verified by Creditcoin and turned into credit history.',
    mainnetTx: txHash,
    mainnetBlock: receipt.blockNumber,
    borrower,
    logsInTransaction: receipt.logs.length,
    creditcoinTx: cc3Receipt.hash,
    creditcoinBlock: cc3Receipt.blockNumber,
    gasUsed: cc3Receipt.gasUsed.toString(),
    proof: {
      chainKey: MAINNET_CHAIN_KEY,
      merkleSiblings: proof.merkleProof.siblings.length,
      continuityRoots: proof.continuityProof.roots.length,
    },
    scoreBefore: Number(before.score),
    scoreAfter: Number(after.score),
    tierAfter: tier,
    demonstratedCapacityWei: capacity.toString(),
  };

  mkdirSync(dirname(OUTPUT_PATH), {recursive: true});
  writeFileSync(OUTPUT_PATH, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(`\n✓ wrote ${OUTPUT_PATH}`);
}

main().catch((error: unknown) => {
  console.error('✗ prove-mainnet failed:', error);
  process.exitCode = 1;
});
