/**
 * Seeds a fresh borrower whose history is left **un-imported**, so the batch demo has something
 * real to import on camera.
 *
 * Borrower A's history is already on Creditcoin, which makes it useless for demonstrating "import
 * my whole credit history in one transaction" — re-importing it would just hit the replay guard.
 * Borrower C exists to be imported live: a Bronze wallet with nothing on Creditcoin, whose entire
 * Sepolia record gets verified in a single batched transaction and jumps straight to Platinum.
 *
 * The composition deliberately mirrors Borrower A's (3 loans, 5 on-time repayments, 1 collateral
 * deposit = 9 events) because that profile scores exactly 710 under `ScoreLib`, and 9 fits inside
 * the precompile's 10-proof `MAX_BATCH_SIZE` with a slot to spare.
 *
 * Run: npx tsx scripts/seed-borrower-c.ts
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {required} from './lib/env.js';
import loanBookArtifact from '../contracts/out/LoanBook.sol/LoanBook.json' with {type: 'json'};

const OUTPUT_PATH = 'docs/evidence/borrower-c-history.json';

const PRINCIPAL = ethers.parseEther('0.002');
const HALF_PRINCIPAL = ethers.parseEther('0.001');
const COLLATERAL = ethers.parseEther('0.003');
/** Long enough that every repayment is comfortably on time — Platinum requires zero late. */
const LONG_DURATION = 30n * 24n * 60n * 60n;
/** Covers 9 transactions of gas plus 0.009 ETH of repayments and collateral. */
const FUNDING = ethers.parseEther('0.03');

interface SeededEvent {
  event: string;
  loanId: number | null;
  amountWei: string;
  onTime: boolean | null;
  txHash: string;
  blockNumber: number;
}

async function main(): Promise<void> {
  const provider = new ethers.JsonRpcProvider(required('SEPOLIA_RPC_URL'));
  const funder = new ethers.Wallet(required('DEPLOYER_PRIVATE_KEY'), provider);
  const loanBookAddress = required('LOANBOOK_ADDRESS');

  const abi = (loanBookArtifact as {abi: ethers.InterfaceAbi}).abi;
  const iface = new ethers.Interface(abi);

  const borrowerC = ethers.Wallet.createRandom().connect(provider);
  console.log(`LoanBook   ${loanBookAddress}`);
  console.log(`Borrower C ${borrowerC.address}`);
  console.log(`Funder     ${funder.address} (${ethers.formatEther(await provider.getBalance(funder.address))} ETH)\n`);

  const funding = await funder.sendTransaction({to: borrowerC.address, value: FUNDING});
  await funding.wait();
  console.log(`✓ funded Borrower C with ${ethers.formatEther(FUNDING)} ETH\n`);

  const book = new ethers.Contract(loanBookAddress, abi, borrowerC);
  const events: SeededEvent[] = [];

  async function record(label: string, send: () => Promise<ethers.ContractTransactionResponse>): Promise<ethers.ContractTransactionReceipt> {
    const tx = await send();
    const receipt = await tx.wait();
    if (receipt === null) throw new Error(`${label}: no receipt`);
    if (receipt.status !== 1) throw new Error(`${label}: reverted`);

    for (const log of receipt.logs) {
      const parsed = iface.parseLog({topics: [...log.topics], data: log.data});
      if (parsed === null) continue;
      events.push({
        event: parsed.name,
        loanId: parsed.args['loanId'] === undefined ? null : Number(parsed.args['loanId'] as bigint),
        amountWei: String((parsed.args['amount'] ?? parsed.args['principal'] ?? 0n) as bigint),
        onTime: parsed.args['onTime'] === undefined ? null : Boolean(parsed.args['onTime']),
        txHash: receipt.hash,
        blockNumber: receipt.blockNumber,
      });
      console.log(`  ✓ ${parsed.name.padEnd(16)} block ${receipt.blockNumber}`);
    }
    return receipt;
  }

  function loanIdFrom(receipt: ethers.ContractTransactionReceipt): bigint {
    for (const log of receipt.logs) {
      const parsed = iface.parseLog({topics: [...log.topics], data: log.data});
      if (parsed?.name === 'LoanOpened') return parsed.args['loanId'] as bigint;
    }
    throw new Error('no LoanOpened in receipt');
  }

  console.log('Loan 1 — open, two on-time part-payments, closes');
  const r1 = await record('open1', () => book['openLoan']!(PRINCIPAL, LONG_DURATION) as Promise<ethers.ContractTransactionResponse>);
  const loan1 = loanIdFrom(r1);
  await record('repay1a', () => book['repay']!(loan1, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>);
  await record('repay1b', () => book['repay']!(loan1, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>);

  console.log('\nLoan 2 — open, collateral, on-time full repayment');
  const r2 = await record('open2', () => book['openLoan']!(PRINCIPAL, LONG_DURATION) as Promise<ethers.ContractTransactionResponse>);
  const loan2 = loanIdFrom(r2);
  await record('collateral', () => book['addCollateral']!({value: COLLATERAL}) as Promise<ethers.ContractTransactionResponse>);
  await record('repay2', () => book['repay']!(loan2, {value: PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>);

  console.log('\nLoan 3 — open, two on-time part-payments, closes');
  const r3 = await record('open3', () => book['openLoan']!(PRINCIPAL, LONG_DURATION) as Promise<ethers.ContractTransactionResponse>);
  const loan3 = loanIdFrom(r3);
  await record('repay3a', () => book['repay']!(loan3, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>);
  await record('repay3b', () => book['repay']!(loan3, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>);

  const blocks = events.map((e) => e.blockNumber);
  const span = Math.max(...blocks) - Math.min(...blocks);
  const txHashes = [...new Set(events.map((e) => e.txHash))];

  console.log(`\n${events.length} events across ${txHashes.length} transactions, spanning ${span} blocks`);
  if (txHashes.length > 10) console.warn(`⚠ ${txHashes.length} transactions exceeds MAX_BATCH_SIZE (10)`);
  if (span >= 1000) console.warn(`⚠ span ${span} exceeds the 1000-block continuity range`);

  const payload = {
    capturedAt: new Date().toISOString(),
    purpose: 'Un-imported history for the batch-verification demo. Do NOT import except on camera.',
    network: 'ethereum-sepolia',
    loanBook: loanBookAddress,
    borrower: {
      address: borrowerC.address,
      // Test-only, generated for this demo and funded with faucet ETH.
      privateKey: borrowerC.privateKey,
    },
    expected: {score: 710, tier: 'Platinum', onTime: 5, late: 0, loansClosed: 3},
    batchConstraints: {
      maxBatchSize: 10,
      maxBatchRange: 1000,
      transactionCount: txHashes.length,
      blockSpan: span,
      fitsSingleBatch: txHashes.length <= 10 && span < 1000,
    },
    txHashes,
    events,
  };

  mkdirSync(dirname(OUTPUT_PATH), {recursive: true});
  writeFileSync(OUTPUT_PATH, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(`✓ wrote ${OUTPUT_PATH}`);
  console.log(`\nBatch-import with:\n  npm run worker:batch -- --borrower ${borrowerC.address}`);
}

main().catch((error: unknown) => {
  console.error('✗ seed-borrower-c failed:', error);
  process.exitCode = 1;
});
