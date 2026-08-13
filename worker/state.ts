/**
 * Durable worker state.
 *
 * Gluwa's reference workers keep their block cursor in a local variable initialised to the
 * current chain head, so a restart silently skips every event that occurred while they were down
 * and there is no way to replay history. Persisting the cursor and the set of already-submitted
 * transactions makes the worker restartable and the demo re-runnable, which matters when the
 * thing being demonstrated is a borrower's *complete* history.
 */
import {existsSync, readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';

const STATE_PATH = 'worker/state.json';

export interface SubmittedRecord {
  /** Source-chain transaction that was proven. */
  sourceTxHash: string;
  /** Creditcoin transaction that verified it. */
  cc3TxHash: string;
  cc3Block: number;
  gasUsed: string;
  at: string;
}

export interface WorkerState {
  /** Next source-chain block to scan from. */
  cursorBlock: number;
  /** Source tx hashes already verified on Creditcoin, keyed for O(1) idempotency checks. */
  submitted: Record<string, SubmittedRecord>;
  /** Source tx hashes that failed permanently, so a poison event cannot wedge the loop. */
  failed: Record<string, string>;
}

export function loadState(fromBlock: number): WorkerState {
  if (!existsSync(STATE_PATH)) {
    return {cursorBlock: fromBlock, submitted: {}, failed: {}};
  }
  const parsed = JSON.parse(readFileSync(STATE_PATH, 'utf8')) as Partial<WorkerState>;
  return {
    cursorBlock: parsed.cursorBlock ?? fromBlock,
    submitted: parsed.submitted ?? {},
    failed: parsed.failed ?? {},
  };
}

export function saveState(state: WorkerState): void {
  mkdirSync(dirname(STATE_PATH), {recursive: true});
  writeFileSync(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`);
}

/** True when this source transaction has already been verified on Creditcoin. */
export function isSubmitted(state: WorkerState, txHash: string): boolean {
  return state.submitted[txHash] !== undefined;
}

export function recordSubmitted(state: WorkerState, record: SubmittedRecord): void {
  state.submitted[record.sourceTxHash] = record;
  saveState(state);
}

export function recordFailure(state: WorkerState, txHash: string, reason: string): void {
  state.failed[txHash] = reason;
  saveState(state);
}
