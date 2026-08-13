/**
 * Seeds realistic credit history into the deployed `LoanBook` on Sepolia.
 *
 * This produces the raw material for the whole demo: the events the Oracle Worker proves to
 * Creditcoin, and the history the batch-import screen ingests in a single transaction.
 *
 * Two borrowers, because one address cannot demonstrate both ends of the tier system —
 * Platinum requires zero late repayments:
 *
 *   Borrower A (the demo wallet)  3 loans, ~10 events, every repayment on time  → reaches Platinum
 *   Borrower B (generated, funded from A)  1 loan repaid late                   → tier contrast
 *
 * Borrower A's events are deliberately emitted back to back so they land inside one ~1000-block
 * window. That is not cosmetic: the block-prover precompile's batch path requires all proofs in
 * a batch to share a continuity proof spanning at most `MAX_BATCH_RANGE` (1000) blocks. If the
 * seeding drifted outside that window, "import my whole history in one transaction" would become
 * impossible to demo.
 *
 * Idempotent: re-running appends fresh history rather than corrupting existing state, and every
 * transaction hash is recorded to docs/evidence/seeded-history.json for the worker to consume.
 *
 * Run: npx tsx scripts/seed-history.ts
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {required} from './lib/env.js';
import loanBookArtifact from '../contracts/out/LoanBook.sol/LoanBook.json' with {type: 'json'};

const OUTPUT_PATH = 'docs/evidence/seeded-history.json';

/** Testnet-scaled. See docs/SCORING.md — ScoreLib's thresholds are calibrated to these. */
const PRINCIPAL = ethers.parseEther('0.002');
const HALF_PRINCIPAL = ethers.parseEther('0.001');
const COLLATERAL = ethers.parseEther('0.003');

/** Long enough that every Borrower A repayment is comfortably on time. */
const LONG_DURATION = 30n * 24n * 60n * 60n;
/** Short enough that Borrower B's loan can actually go late inside one seeding run. */
const SHORT_DURATION = 60n;
/** Funds Borrower B for ~4 transactions at Sepolia gas, plus the repayment itself. */
const BORROWER_B_FUNDING = ethers.parseEther('0.01');

interface SeededEvent {
  borrower: string;
  event: string;
  loanId: number | null;
  amountWei: string;
  onTime: boolean | null;
  txHash: string;
  blockNumber: number;
}

const events: SeededEvent[] = [];

function abiOf(artifact: unknown): ethers.InterfaceAbi {
  return (artifact as {abi: ethers.InterfaceAbi}).abi;
}

/** Sends a transaction, waits for it, and records every LoanBook event it produced. */
async function record(
  label: string,
  borrower: string,
  iface: ethers.Interface,
  send: () => Promise<ethers.ContractTransactionResponse>,
): Promise<ethers.ContractTransactionReceipt> {
  const tx = await send();
  const receipt = await tx.wait();
  if (receipt === null) throw new Error(`${label}: transaction ${tx.hash} produced no receipt`);
  if (receipt.status !== 1) throw new Error(`${label}: transaction ${tx.hash} reverted`);

  for (const log of receipt.logs) {
    const parsed = iface.parseLog({topics: [...log.topics], data: log.data});
    if (parsed === null) continue;

    events.push({
      borrower,
      event: parsed.name,
      loanId: parsed.args['loanId'] === undefined ? null : Number(parsed.args['loanId'] as bigint),
      amountWei: String((parsed.args['amount'] ?? parsed.args['principal'] ?? 0n) as bigint),
      onTime: parsed.args['onTime'] === undefined ? null : Boolean(parsed.args['onTime']),
      txHash: receipt.hash,
      blockNumber: receipt.blockNumber,
    });
    console.log(
      `  ✓ ${parsed.name.padEnd(16)} block ${receipt.blockNumber}  ${receipt.hash.slice(0, 18)}…`,
    );
  }
  return receipt;
}

/** Reads the loanId out of a LoanOpened log rather than assuming a counter value. */
function loanIdFrom(receipt: ethers.ContractTransactionReceipt, iface: ethers.Interface): bigint {
  for (const log of receipt.logs) {
    const parsed = iface.parseLog({topics: [...log.topics], data: log.data});
    if (parsed?.name === 'LoanOpened') return parsed.args['loanId'] as bigint;
  }
  throw new Error('No LoanOpened event found in receipt');
}

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

async function main(): Promise<void> {
  const provider = new ethers.JsonRpcProvider(required('SEPOLIA_RPC_URL'));
  const walletA = new ethers.Wallet(required('DEPLOYER_PRIVATE_KEY'), provider);
  const loanBookAddress = required('LOANBOOK_ADDRESS');

  const abi = abiOf(loanBookArtifact);
  const iface = new ethers.Interface(abi);
  const bookA = new ethers.Contract(loanBookAddress, abi, walletA);

  const startBlock = await provider.getBlockNumber();
  console.log(`LoanBook   ${loanBookAddress}`);
  console.log(`Borrower A ${walletA.address}`);
  console.log(`Balance    ${ethers.formatEther(await provider.getBalance(walletA.address))} ETH`);
  console.log(`Block      ${startBlock}\n`);

  // ── Borrower A: a clean record. Three loans, every repayment on time. ──────────────────
  console.log('Borrower A — loan 1 (open, two on-time part-payments, closes)');
  const r1 = await record('loan1 open', walletA.address, iface, () =>
    bookA['openLoan']!(PRINCIPAL, LONG_DURATION) as Promise<ethers.ContractTransactionResponse>,
  );
  const loan1 = loanIdFrom(r1, iface);
  await record('loan1 repay 1/2', walletA.address, iface, () =>
    bookA['repay']!(loan1, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>,
  );
  await record('loan1 repay 2/2', walletA.address, iface, () =>
    bookA['repay']!(loan1, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>,
  );

  console.log('\nBorrower A — loan 2 (open, collateral, on-time full repayment)');
  const r2 = await record('loan2 open', walletA.address, iface, () =>
    bookA['openLoan']!(PRINCIPAL, LONG_DURATION) as Promise<ethers.ContractTransactionResponse>,
  );
  const loan2 = loanIdFrom(r2, iface);
  await record('collateral', walletA.address, iface, () =>
    bookA['addCollateral']!({value: COLLATERAL}) as Promise<ethers.ContractTransactionResponse>,
  );
  await record('loan2 repay', walletA.address, iface, () =>
    bookA['repay']!(loan2, {value: PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>,
  );

  console.log('\nBorrower A — loan 3 (open, two on-time part-payments, closes)');
  const r3 = await record('loan3 open', walletA.address, iface, () =>
    bookA['openLoan']!(PRINCIPAL, LONG_DURATION) as Promise<ethers.ContractTransactionResponse>,
  );
  const loan3 = loanIdFrom(r3, iface);
  await record('loan3 repay 1/2', walletA.address, iface, () =>
    bookA['repay']!(loan3, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>,
  );
  await record('loan3 repay 2/2', walletA.address, iface, () =>
    bookA['repay']!(loan3, {value: HALF_PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>,
  );

  const aEvents = events.length;
  const aBlocks = events.map((e) => e.blockNumber);
  const aSpan = Math.max(...aBlocks) - Math.min(...aBlocks);
  console.log(`\nBorrower A: ${aEvents} events spanning ${aSpan} blocks`);
  if (aEvents > 10) {
    console.warn(`⚠ ${aEvents} events exceeds the batch limit of 10 — the demo must split them.`);
  }
  if (aSpan >= 1000) {
    console.warn(`⚠ span ${aSpan} exceeds MAX_BATCH_RANGE (1000) — single-batch import impossible.`);
  }

  // ── Borrower B: one late repayment, to prove the penalty is real on live testnet. ──────
  console.log('\nBorrower B — funding a fresh wallet');
  const walletB = ethers.Wallet.createRandom().connect(provider);
  console.log(`Borrower B ${walletB.address}`);
  const funding = await walletA.sendTransaction({to: walletB.address, value: BORROWER_B_FUNDING});
  await funding.wait();
  console.log(`  ✓ funded with ${ethers.formatEther(BORROWER_B_FUNDING)} ETH`);

  const bookB = new ethers.Contract(loanBookAddress, abi, walletB);
  console.log(`\nBorrower B — loan with a ${SHORT_DURATION}s deadline, repaid LATE`);
  const rb = await record('loanB open', walletB.address, iface, () =>
    bookB['openLoan']!(PRINCIPAL, SHORT_DURATION) as Promise<ethers.ContractTransactionResponse>,
  );
  const loanB = loanIdFrom(rb, iface);

  // Wait past the deadline so the contract itself stamps onTime=false. The flag has to come
  // from the source chain's own clock — the registry has no way to second-guess it.
  const waitMs = Number(SHORT_DURATION) * 1000 + 15_000;
  console.log(`  waiting ${waitMs / 1000}s for the deadline to pass…`);
  await sleep(waitMs);

  const lateReceipt = await record('loanB repay LATE', walletB.address, iface, () =>
    bookB['repay']!(loanB, {value: PRINCIPAL}) as Promise<ethers.ContractTransactionResponse>,
  );
  const lateEvent = events.find((e) => e.txHash === lateReceipt.hash && e.event === 'RepaymentMade');
  if (lateEvent?.onTime !== false) {
    throw new Error('Borrower B repayment was recorded as on time — the late path was not seeded.');
  }
  console.log('  ✓ confirmed onTime=false');

  // ── Evidence ───────────────────────────────────────────────────────────────────────────
  const payload = {
    capturedAt: new Date().toISOString(),
    network: 'ethereum-sepolia',
    chainId: 11155111,
    loanBook: loanBookAddress,
    borrowers: {
      A: {address: walletA.address, role: 'clean history — all on time, targets Platinum'},
      B: {address: walletB.address, role: 'one late repayment — tier contrast'},
    },
    batchConstraints: {
      maxBatchSize: 10,
      maxBatchRange: 1000,
      borrowerAEventCount: aEvents,
      borrowerABlockSpan: aSpan,
      borrowerAFitsSingleBatch: aEvents <= 10 && aSpan < 1000,
    },
    events,
  };

  mkdirSync(dirname(OUTPUT_PATH), {recursive: true});
  writeFileSync(OUTPUT_PATH, `${JSON.stringify(payload, null, 2)}\n`);

  console.log(`\n✓ ${events.length} events seeded`);
  console.log(`✓ wrote ${OUTPUT_PATH}`);
  console.log(`\nEtherscan: https://sepolia.etherscan.io/address/${loanBookAddress}#events`);
}

main().catch((error: unknown) => {
  console.error('✗ seed-history failed:', error);
  process.exitCode = 1;
});
