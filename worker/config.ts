/**
 * Worker configuration, resolved once at startup so a missing value fails immediately with a
 * name rather than surfacing mid-run as an opaque ethers error.
 */
import {ethers} from 'ethers';
import {required, optional, cc3RpcUrl, proofBuilderUrl} from '../scripts/lib/env.js';

/**
 * Alchemy's free tier rejects `eth_getLogs` spanning more than 10 blocks. Scanning has to be
 * paginated at or below that width; a naive full-range query fails outright rather than
 * degrading.
 */
export const LOG_SCAN_CHUNK = 10;

/**
 * The SDK's default HTTP timeout is 10s, which already expired against a cold prover cache
 * during Gate G0 — and it governs the attested-height poll, not just proof fetches.
 */
export const PROVER_TIMEOUT_MS = 60_000;

/** How often watch mode looks for new source-chain blocks. */
export const POLL_INTERVAL_MS = 15_000;

/**
 * Floor for the CC3 submission gas limit. A verified ingest measured ~400k during G0, while the
 * Gluwa examples' fallback (`21000 + roots*5000 + 20000`) computes ~70k — roughly 20x too low,
 * which would broadcast a doomed transaction whenever estimation fails.
 */
export const GAS_LIMIT_FLOOR = 900_000n;

/** Multiplier applied to a successful gas estimate, as a percentage. */
export const GAS_BUFFER_PERCENT = 140n;

export interface WorkerConfig {
  sourceProvider: ethers.JsonRpcProvider;
  cc3Provider: ethers.JsonRpcProvider;
  wallet: ethers.Wallet;
  loanBookAddress: string;
  registryAddress: string;
  chainKey: number;
  proofBuilderUrl: string;
}

export function loadConfig(): WorkerConfig {
  const sourceProvider = new ethers.JsonRpcProvider(required('SEPOLIA_RPC_URL'));
  const cc3Provider = new ethers.JsonRpcProvider(cc3RpcUrl());

  return {
    sourceProvider,
    cc3Provider,
    wallet: new ethers.Wallet(required('DEPLOYER_PRIVATE_KEY'), cc3Provider),
    loanBookAddress: ethers.getAddress(required('LOANBOOK_ADDRESS')),
    registryAddress: ethers.getAddress(required('CREDIT_REGISTRY_ADDRESS')),
    chainKey: Number.parseInt(optional('SOURCE_CHAIN_KEY', '1'), 10),
    proofBuilderUrl: proofBuilderUrl(),
  };
}
