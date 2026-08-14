import {defineChain} from 'viem';
import {sepolia} from 'wagmi/chains';
import {http, createConfig} from 'wagmi';
import {injected} from 'wagmi/connectors';

/**
 * Creditcoin CC3 testnet.
 *
 * Deliberately declares **no** `contracts.multicall3`. CC3 has no Multicall3 deployed, and viem
 * hard-fails against a declared-but-absent one; leaving it out lets `useReadContracts` fall back
 * to parallel individual reads. JSON-RPC array batching is enabled instead, which CC3 supports.
 *
 * Note CC3 blocks omit `mixHash` (it runs Frontier, the Substrate EVM layer). That breaks tools
 * which deserialize blocks into a strict schema — it broke `forge script` for us — but viem never
 * reads the field and does no runtime validation, so it is a non-issue here.
 */
export const creditcoinCC3 = defineChain({
  id: 102031,
  name: 'Creditcoin CC3 Testnet',
  nativeCurrency: {name: 'Testnet CTC', symbol: 'tCTC', decimals: 18},
  rpcUrls: {default: {http: ['https://rpc.cc3-testnet.creditcoin.network']}},
  blockExplorers: {
    default: {
      name: 'Blockscout',
      url: 'https://creditcoin-testnet.blockscout.com',
      apiUrl: 'https://creditcoin-testnet.blockscout.com/api',
    },
  },
  testnet: true,
});

export const wagmiConfig = createConfig({
  chains: [creditcoinCC3, sepolia],
  connectors: [injected()],
  transports: {
    [creditcoinCC3.id]: http('https://rpc.cc3-testnet.creditcoin.network', {batch: true}),
    // A public endpoint on purpose. Vite inlines VITE_* values into the bundle, so shipping our
    // Alchemy key would publish it — and Sepolia reads here are a few hundred blocks.
    [sepolia.id]: http('https://ethereum-sepolia-rpc.publicnode.com', {batch: true}),
  },
});

declare module 'wagmi' {
  interface Register {
    config: typeof wagmiConfig;
  }
}

/** Deployed contracts. Mirrors `deployments.json` at the repo root. */
export const ADDRESSES = {
  /** Sepolia — the credit-history source. */
  loanBook: '0x07AdA5C60dFbe5C3A7dC48081B0fa70E14c6d41D',
  /** CC3 — the Attestcoin Smart Contract. Reads Sepolia *and* Ethereum mainnet. */
  registry: '0x4C4381dB68a1cAAE46a2E6CFc2f667ad22Dddf81',
  /** CC3 — soulbound tier badge. */
  sbt: '0x326F8806cBd5ABF413889BfAc0A6622a0AEddD18',
  /** CC3 — tier-priced lending, capped by demonstrated capacity. */
  pool: '0xf27877faC13244a4ad959E83cD9E5a15d919029C',
  /** CC3 — the borrowable asset. */
  tusd: '0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051',
  /** Creditcoin's native block-prover precompile. */
  blockProver: '0x0000000000000000000000000000000000000FD2',
} as const;

/** Block LoanBook was deployed at — CC3's `eth_getLogs` times out over wide spans. */
export const LOANBOOK_DEPLOY_BLOCK = 11_486_250n;
/**
 * Block the current `CreditRegistry` was deployed at, established by binary search on
 * `eth_getCode` rather than by hand.
 *
 * Every `getContractEvents` call below starts here, because CC3's `eth_getLogs` times out over
 * wide spans. That makes this constant load-bearing and silently dangerous: set it even slightly
 * **too high** and the UI shows an empty event table and no score history for every borrower, with
 * no error — the reads succeed and return nothing. A hand-typed value of 5,305,700 did exactly
 * that, 22 blocks above the registry and 78 above its first ingest.
 */
export const REGISTRY_DEPLOY_BLOCK = 5_307_511n;

/** Creditcoin-internal id for Sepolia. Not the EVM chainId — see docs/evidence/supported-chains.json. */
export const SOURCE_CHAIN_KEY = 1;
/** Creditcoin-internal id for **Ethereum mainnet**. CC3 attests it, so real history is readable. */
export const MAINNET_CHAIN_KEY = 3;

/**
 * Credit sources the registry will accept, by `(chainKey, emitter)`.
 *
 * The distinction that matters is the last column: our own `LoanBook` has no lender, so its history
 * is self-reported and can never unlock undercollateralized credit. Aave and Sparklend had real
 * third-party capital at risk, so only they raise demonstrated capacity.
 */
export const SOURCES = [
  {
    chainKey: 1,
    chain: 'Sepolia',
    name: 'CrossCredit LoanBook',
    address: '0x07AdA5C60dFbe5C3A7dC48081B0fa70E14c6d41D',
    raisesCapacity: false,
    note: 'Self-reported — no lender, so it is capped below Platinum',
  },
  {
    chainKey: 3,
    chain: 'Ethereum',
    name: 'Aave V3 Pool',
    address: '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2',
    raisesCapacity: true,
    note: 'Real counterparty capital — Repay, Borrow, LiquidationCall',
  },
  {
    chainKey: 3,
    chain: 'Ethereum',
    name: 'Sparklend Pool',
    address: '0xC13e21B648A5Ee794902342038FF3aDAB66BE987',
    raisesCapacity: true,
    note: 'Aave V3 fork — identical event signatures',
  },
  {
    chainKey: 3,
    chain: 'Ethereum',
    name: 'ENS Registrar',
    address: '0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547',
    raisesCapacity: false,
    note: 'Sunk cost — expiry enforced at ingest',
  },
] as const;

export const PROVER_URL = 'https://prover.cc3-testnet.creditcoin.network';

export const EXPLORERS = {
  sepolia: 'https://sepolia.etherscan.io',
  cc3: 'https://creditcoin-testnet.blockscout.com',
} as const;

export const TIER_NAMES = ['Bronze', 'Silver', 'Gold', 'Platinum'] as const;
export type TierName = (typeof TIER_NAMES)[number];

/** Tailwind classes per tier, matching the on-chain SVG palette. */
export const TIER_STYLES: Record<number, {text: string; ring: string; bg: string}> = {
  0: {text: 'text-bronze', ring: 'ring-bronze/40', bg: 'bg-bronze/10'},
  1: {text: 'text-silver', ring: 'ring-silver/40', bg: 'bg-silver/10'},
  2: {text: 'text-gold', ring: 'ring-gold/40', bg: 'bg-gold/10'},
  3: {text: 'text-platinum', ring: 'ring-platinum/50', bg: 'bg-platinum/10'},
};

/**
 * Borrowers seeded on Sepolia, offered as one-click examples so a judge can see the whole product
 * without a wallet or any testnet funds.
 */
export const DEMO_BORROWERS = [
  {
    label: 'Platinum — real Ethereum mainnet history',
    address: '0x76f30e3f75437fB862B8D2C4D80a671bCeBA5b1A',
    note: '5 genuine Aave V3 repayments. Never touched Creditcoin.',
    real: true,
  },
  {
    label: 'Silver — a 2024 repayment, aged on-chain',
    address: '0xe57D6C07d7DA0066AAC9BaF186CbC298fB57dd00',
    note: 'One proof from Oct 2024 — 22 months of history maxes the age term',
    real: true,
  },
  {
    label: 'Silver — imported in one batch',
    address: '0xaA2871B057D80D92606f0a3eFa84f175F73b55d5',
    note: '9 events verified in a single transaction',
    real: false,
  },
  {
    label: 'Silver — imported proof by proof',
    address: '0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6',
    note: '9 separate verifications, same result as one batch',
    real: false,
  },
  {
    label: 'Bronze — one late repayment',
    address: '0xB82dC3F27d4b72FaF7594C7724Cf43B47FF4b52e',
    note: 'the penalty, on live testnet',
    real: false,
  },
] as const;
