/**
 * CrossCredit Oracle Worker.
 *
 * Watches `LoanBook` on Ethereum Sepolia, proves each transaction to Creditcoin through the
 * Attestcoin Protocol, and submits it to `CreditRegistry` — so the borrower signs exactly once,
 * on Sepolia, and their reputation appears on Creditcoin without them doing anything else.
 *
 *   backfill  Replay history from a block (or a single transaction) and stop.
 *   watch     Follow the chain head indefinitely.
 *
 * Run:
 *   npm run worker:backfill -- --from-block 11482838
 *   npm run worker:backfill -- --tx 0xabc...
 *   npm run worker:watch
 */
import {ethers} from 'ethers';
import loanBookArtifact from '../contracts/out/LoanBook.sol/LoanBook.json' with {type: 'json'};
import registryArtifact from '../contracts/out/CreditRegistry.sol/CreditRegistry.json' with {type: 'json'};
import {loadConfig, POLL_INTERVAL_MS, type WorkerConfig} from './config.js';
import {loadState, isSubmitted, recordSubmitted, recordFailure, saveState, type WorkerState} from './state.js';
import {scanEvents, groupByTransaction, type SourceEvent} from './scan.js';
import {fetchProof, submitProof, describe} from './prove.js';

function abiOf(artifact: unknown): ethers.InterfaceAbi {
  return (artifact as {abi: ethers.InterfaceAbi}).abi;
}

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/** Proves one source transaction and applies it on Creditcoin. Idempotent by source tx hash. */
async function processTransaction(
  config: WorkerConfig,
  registry: ethers.Contract,
  state: WorkerState,
  event: SourceEvent,
): Promise<boolean> {
  if (isSubmitted(state, event.txHash)) {
    console.log(`· skip (already verified) ${event.txHash.slice(0, 18)}…`);
    return false;
  }

  console.log(`\n▸ ${event.eventName} in block ${event.blockNumber}`);
  console.log(`  source tx        ${event.txHash}`);

  try {
    const args = await fetchProof(config, event.txHash, event.blockNumber);
    const receipt = await submitProof(registry, args);

    recordSubmitted(state, {
      sourceTxHash: event.txHash,
      cc3TxHash: receipt.hash,
      cc3Block: receipt.blockNumber,
      gasUsed: receipt.gasUsed.toString(),
      at: new Date().toISOString(),
    });

    const score = (await registry['scoreOf']!(event.borrower)) as bigint;
    const tier = ['Bronze', 'Silver', 'Gold', 'Platinum'][
      Number((await registry['tierOf']!(event.borrower)) as bigint)
    ];
    console.log(`  ★ ${event.borrower} → score ${score}, tier ${tier}`);
    return true;
  } catch (error) {
    const reason = describe(error);
    // A replayed query is the replay guard working, not a fault — record it so the worker stops
    // retrying, and carry on.
    if (reason.includes('Query already processed')) {
      console.log('  · already ingested on Creditcoin (replay guard) — recording and moving on');
      recordFailure(state, event.txHash, 'already processed on chain');
      return false;
    }
    console.error(`  ✗ ${reason}`);
    recordFailure(state, event.txHash, reason);
    return false;
  }
}

async function main(): Promise<void> {
  const mode = process.argv[2] ?? 'watch';
  const config = loadConfig();

  const loanBook = new ethers.Contract(config.loanBookAddress, abiOf(loanBookArtifact), config.sourceProvider);
  const registry = new ethers.Contract(config.registryAddress, abiOf(registryArtifact), config.wallet);

  const head = await config.sourceProvider.getBlockNumber();
  console.log('CrossCredit Oracle Worker');
  console.log(`  mode        ${mode}`);
  console.log(`  LoanBook    ${config.loanBookAddress} (Sepolia)`);
  console.log(`  Registry    ${config.registryAddress} (CC3)`);
  console.log(`  chainKey    ${config.chainKey}`);
  console.log(`  source head ${head}`);

  const flagIndex = process.argv.indexOf('--from-block');
  const explicitFrom = flagIndex !== -1 ? Number.parseInt(process.argv[flagIndex + 1] ?? '', 10) : NaN;
  const state = loadState(Number.isInteger(explicitFrom) ? explicitFrom : head);
  if (Number.isInteger(explicitFrom)) state.cursorBlock = explicitFrom;

  // Single-transaction mode: prove exactly one tx, which is what the demo drives.
  const txIndex = process.argv.indexOf('--tx');
  if (txIndex !== -1) {
    const txHash = process.argv[txIndex + 1];
    if (txHash === undefined) throw new Error('--tx requires a transaction hash');
    const receipt = await config.sourceProvider.getTransactionReceipt(txHash);
    if (receipt === null) throw new Error(`transaction ${txHash} not found on the source chain`);

    const parsed = receipt.logs
      .map((log) => loanBook.interface.parseLog({topics: [...log.topics], data: log.data}))
      .find((entry) => entry !== null);

    await processTransaction(config, registry, state, {
      txHash,
      blockNumber: receipt.blockNumber,
      eventName: parsed?.name ?? 'Unknown',
      borrower: (parsed?.args['borrower'] as string | undefined) ?? ethers.ZeroAddress,
    });
    return;
  }

  if (mode === 'backfill') {
    console.log(`\nBackfilling blocks ${state.cursorBlock}..${head}`);
    const events = groupByTransaction(await scanEvents(loanBook, state.cursorBlock, head));
    console.log(`Found ${events.length} transaction(s) carrying LoanBook events.`);

    let verified = 0;
    for (const event of events) {
      if (await processTransaction(config, registry, state, event)) verified += 1;
    }

    state.cursorBlock = head + 1;
    saveState(state);
    console.log(`\n✓ backfill complete — ${verified} newly verified on Creditcoin`);
    return;
  }

  console.log('\nWatching for new LoanBook activity. Ctrl-C to stop.\n');
  for (;;) {
    try {
      const latest = await config.sourceProvider.getBlockNumber();
      if (latest >= state.cursorBlock) {
        const events = groupByTransaction(await scanEvents(loanBook, state.cursorBlock, latest));
        for (const event of events) {
          await processTransaction(config, registry, state, event);
        }
        state.cursorBlock = latest + 1;
        saveState(state);
      }
    } catch (error) {
      console.error(`✗ poll failed, backing off: ${describe(error)}`);
      await sleep(POLL_INTERVAL_MS * 2);
      continue;
    }
    await sleep(POLL_INTERVAL_MS);
  }
}

main().catch((error: unknown) => {
  console.error('✗ worker failed:', error);
  process.exitCode = 1;
});
