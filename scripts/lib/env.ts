/**
 * Typed, fail-fast access to the `.env` values every script and the worker share.
 *
 * Reading config through here (rather than touching `process.env` directly) means a
 * missing key fails at startup with a name, instead of surfacing later as an opaque
 * ethers error mid-way through a live testnet run.
 */
import 'dotenv/config';

/** Reads a required variable, throwing a named error when it is absent or blank. */
export function required(key: string): string {
  const value = process.env[key];
  if (value === undefined || value.trim() === '') {
    throw new Error(`Missing required env var ${key} — copy .env.example to .env and fill it in.`);
  }
  return value.trim();
}

/** Reads an optional variable, falling back to `fallbackValue`. */
export function optional(key: string, fallbackValue: string): string {
  const value = process.env[key];
  return value === undefined || value.trim() === '' ? fallbackValue : value.trim();
}

/** Reads a required variable and parses it as a base-10 integer. */
export function requiredInt(key: string): number {
  const raw = required(key);
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isInteger(parsed)) {
    throw new Error(`Env var ${key} must be an integer, got "${raw}".`);
  }
  return parsed;
}

/** Creditcoin CC3 testnet RPC. Defaults to the public endpoint. */
export const cc3RpcUrl = (): string =>
  optional('CC3_RPC_URL', 'https://rpc.cc3-testnet.creditcoin.network');

/** Hosted Attestcoin proof builder API. */
export const proofBuilderUrl = (): string =>
  optional('PROOF_BUILDER_URL', 'https://prover.cc3-testnet.creditcoin.network');
