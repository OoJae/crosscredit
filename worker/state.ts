/**
 * Durable worker state.
 *
 * Gluwa's reference workers keep their block cursor in a local variable initialised to the
 * current chain head, so a restart silently skips every event that occurred while they were down
 * and there is no way to replay history. Persisting the cursor and the set of already-submitted
 * transactions makes the worker restartable and the demo re-runnable, which matters when the
 * thing being demonstrated is a borrower's *complete* history.
 */
import {existsSync, readFileSync, writeFileSync, mkdirSync, renameSync, copyFileSync} from 'node:fs';
import {dirname} from 'node:path';

const STATE_PATH = 'worker/state.json';
const TEMP_PATH = `${STATE_PATH}.tmp`;
const PREV_PATH = `${STATE_PATH}.prev`;

/**
 * Bumped whenever the state's meaning changes in a way that makes an older file wrong rather than
 * merely incomplete — a new registry address being the obvious case, since `submitted` is what
 * makes the worker skip a transaction and a fresh registry has verified nothing.
 */
const STATE_VERSION = 2;

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
  /** Schema version; a mismatch discards the file rather than half-trusting it. */
  version: number;
  /** Registry the `submitted` set was verified against. */
  registry: string;
  /** Next source-chain block to scan from. */
  cursorBlock: number;
  /** Source tx hashes already verified on Creditcoin, keyed for O(1) idempotency checks. */
  submitted: Record<string, SubmittedRecord>;
  /** Source tx hashes that failed permanently, so a poison event cannot wedge the loop. */
  failed: Record<string, string>;
}

/**
 * Loads state, discarding anything that belongs to a different registry or schema.
 *
 * @param fromBlock Where to start when there is no usable state.
 * @param registry The registry this run will submit to.
 *
 * @remarks
 * The registry check is the important one. `submitted` is consulted to skip transactions, and a
 * newly deployed registry has consumed no query ids at all — so carrying the old set forward makes
 * the worker skip the entire history and import nothing, silently and successfully. That is a
 * genuinely confusing failure, and it happens on every redeploy.
 *
 * A corrupt file (a crash mid-write, before writes were atomic) falls back to `.prev` and then to
 * a clean slate, loudly. Re-importing is idempotent — the registry's replay guard is the real
 * backstop — so the safe direction is always to forget rather than to guess.
 */
export function loadState(fromBlock: number, registry: string): WorkerState {
  const fresh = (): WorkerState => ({
    version: STATE_VERSION,
    registry,
    cursorBlock: fromBlock,
    submitted: {},
    failed: {},
  });

  for (const path of [STATE_PATH, PREV_PATH]) {
    if (!existsSync(path)) continue;

    let parsed: Partial<WorkerState>;
    try {
      parsed = JSON.parse(readFileSync(path, 'utf8')) as Partial<WorkerState>;
    } catch {
      console.warn(`  ! ${path} is unreadable — ignoring it`);
      continue;
    }

    if (parsed.version !== STATE_VERSION) {
      console.warn(`  ! ${path} is schema v${String(parsed.version ?? 1)}, expected v${STATE_VERSION} — starting clean`);
      return fresh();
    }
    if (parsed.registry?.toLowerCase() !== registry.toLowerCase()) {
      console.warn(`  ! ${path} belongs to registry ${parsed.registry ?? 'unknown'} — starting clean for ${registry}`);
      return fresh();
    }

    return {
      version: STATE_VERSION,
      registry,
      cursorBlock: parsed.cursorBlock ?? fromBlock,
      submitted: parsed.submitted ?? {},
      failed: parsed.failed ?? {},
    };
  }

  return fresh();
}

/**
 * Writes state atomically.
 *
 * @remarks
 * `writeFileSync` truncates before it writes, so a crash mid-write left a half-written file that
 * threw on the next `JSON.parse` and wedged the worker permanently. Writing to a temp file and
 * renaming is atomic on POSIX, and the previous good file is kept as a fallback.
 */
export function saveState(state: WorkerState): void {
  mkdirSync(dirname(STATE_PATH), {recursive: true});
  if (existsSync(STATE_PATH)) copyFileSync(STATE_PATH, PREV_PATH);
  writeFileSync(TEMP_PATH, `${JSON.stringify(state, null, 2)}\n`);
  renameSync(TEMP_PATH, STATE_PATH);
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
