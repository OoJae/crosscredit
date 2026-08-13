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
  loanBook: '0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c',
  /** CC3 — the Attestcoin Smart Contract. */
  registry: '0xB5F3B44113A31B07508464de39d7ddd939184B2c',
  /** CC3 — soulbound tier badge. */
  sbt: '0x96a68DBe0cC9BD13E92B4730eFfE531F63f4B2F6',
  /** CC3 — tier-priced lending. */
  pool: '0xA37a9338b17c20917046E29F23D9d8F796a5FDAb',
  /** CC3 — the borrowable asset. */
  tusd: '0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051',
  /** Creditcoin's native block-prover precompile. */
  blockProver: '0x0000000000000000000000000000000000000FD2',
} as const;

/** Block LoanBook was deployed at — CC3's `eth_getLogs` times out over wide spans. */
export const LOANBOOK_DEPLOY_BLOCK = 11_482_838n;
/** Block CreditRegistry was deployed at. */
export const REGISTRY_DEPLOY_BLOCK = 5_304_900n;

/** Creditcoin-internal id for Sepolia. Not the EVM chainId — see docs/evidence/supported-chains.json. */
export const SOURCE_CHAIN_KEY = 1;

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
    label: 'Platinum — imported in one batch',
    address: '0x8C04C28894BADcE63d1F00f356AbB126983522Cf',
    note: '9 events verified in a single transaction',
  },
  {
    label: 'Platinum — imported proof by proof',
    address: '0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6',
    note: '11 separate verifications, same result',
  },
  {
    label: 'Bronze — one late repayment',
    address: '0x04163f60FA50519D86AeFB8e450312bAD76CA0B6',
    note: 'the penalty, on live testnet',
  },
] as const;
