/**
 * Phase 0 verification: snapshot which source chains CC3 actually supports, and prove
 * their attestors are live rather than merely registered.
 *
 * The committed output (docs/evidence/supported-chains.json) is law for the rest of the
 * build: no contract may hardcode a chainKey that does not appear there. `chainKey` is a
 * Creditcoin-internal id and is NOT the EVM chainId — on CC3 testnet, chainKey 1 is
 * Ethereum Sepolia, while on mainnet the same key means Ethereum Mainnet.
 *
 * Run: npm run check:chains
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {chainInfo} from '@gluwa/usc-sdk';
import {cc3RpcUrl} from './lib/env.js';

const OUTPUT_PATH = 'docs/evidence/supported-chains.json';

interface ChainSnapshot {
  chainKey: number;
  chainId: number;
  /** Raw value from the precompile — hex-encoded bytes, despite what the SDK docstring shows. */
  chainName: string;
  /** `chainName` decoded to UTF-8, e.g. "Sepolia ethereum". */
  chainNameDecoded: string;
  chainEncoding: number;
  attestationGenesisHeight: number;
  latestAttested: {height: number; hash: string; isAttestation: boolean; exists: boolean};
}

/**
 * The ChainInfo precompile returns `chainName` as hex-encoded bytes (`0x5365706f...`), not the
 * plain string the SDK's own example comment suggests. Decode it so the evidence file is
 * human-auditable, but keep the raw value alongside it.
 */
function decodeChainName(raw: string): string {
  try {
    return ethers.toUtf8String(raw);
  } catch {
    return raw;
  }
}

async function main(): Promise<void> {
  const rpcUrl = cc3RpcUrl();
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const infoProvider = new chainInfo.PrecompileChainInfoProvider(provider);

  const network = await provider.getNetwork();
  const cc3Block = await provider.getBlockNumber();

  console.log(`CC3 RPC          ${rpcUrl}`);
  console.log(`CC3 chainId      ${network.chainId}`);
  console.log(`CC3 block height ${cc3Block}`);
  console.log(`ChainInfo precompile ${chainInfo.CHAIN_INFO_PRECOMPILE_ADDRESS}\n`);

  const chains = await infoProvider.getSupportedChains();

  // Registration alone does not mean a chain is usable. Pull each chain's latest attested
  // height too — if attestations are frozen, proofs for recent blocks will never generate,
  // and we would rather discover that here than during a live demo.
  const snapshots: ChainSnapshot[] = [];
  for (const chain of chains) {
    const [latestAttested, attestationGenesisHeight] = await Promise.all([
      infoProvider.getLatestAttestedHeightAndHash(chain.chainKey),
      infoProvider.getAttestationGenesisHeight(chain.chainKey),
    ]);
    snapshots.push({
      ...chain,
      chainNameDecoded: decodeChainName(chain.chainName),
      attestationGenesisHeight,
      latestAttested,
    });
  }

  console.table(
    snapshots.map((s) => ({
      chainKey: s.chainKey,
      chainId: s.chainId,
      name: s.chainNameDecoded,
      encoding: s.chainEncoding,
      latestAttestedHeight: s.latestAttested.exists ? s.latestAttested.height : '— none —',
    })),
  );

  const payload = {
    capturedAt: new Date().toISOString(),
    rpc: rpcUrl,
    cc3ChainId: Number(network.chainId),
    cc3BlockHeight: cc3Block,
    chainInfoPrecompile: chainInfo.CHAIN_INFO_PRECOMPILE_ADDRESS,
    chains: snapshots,
  };

  mkdirSync(dirname(OUTPUT_PATH), {recursive: true});
  writeFileSync(
    OUTPUT_PATH,
    // BigInts appear in ethers return values; JSON.stringify throws on them by default.
    `${JSON.stringify(payload, (_key, value: unknown) => (typeof value === 'bigint' ? value.toString() : value), 2)}\n`,
  );
  console.log(`\n✓ wrote ${OUTPUT_PATH}`);

  const unattested = snapshots.filter((s) => !s.latestAttested.exists);
  if (unattested.length > 0) {
    console.warn(
      `⚠ ${unattested.length} supported chain(s) have no attestations yet: ` +
        unattested.map((s) => `${s.chainName} (key ${s.chainKey})`).join(', '),
    );
  }
}

main().catch((error: unknown) => {
  console.error('✗ check-chains failed:', error);
  process.exitCode = 1;
});
