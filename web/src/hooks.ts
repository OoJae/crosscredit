import {useQuery} from '@tanstack/react-query';
import {usePublicClient, useReadContract} from 'wagmi';
import type {Address, Hex} from 'viem';
import {registryAbi, sbtAbi, poolAbi, loanBookAbi, EVENT_SIGS} from './abis';
import {
  ADDRESSES,
  LOANBOOK_DEPLOY_BLOCK,
  REGISTRY_DEPLOY_BLOCK,
  creditcoinCC3,
  SOURCE_CHAIN_KEY,
} from './config';
import {fetchAttestedHeight} from './prover';
import {sepolia} from 'wagmi/chains';

const cc3 = {chainId: creditcoinCC3.id} as const;

export interface Profile {
  totalRepaidWei: bigint;
  totalCollateralWei: bigint;
  demonstratedCapacityWei: bigint;
  onTime: number;
  late: number;
  mainnetRepayments: number;
  liquidations: number;
  loansOpened: number;
  loansClosed: number;
  firstSeen: bigint;
  oldestActivity: bigint;
  identityExpiry: bigint;
  score: number;
}

/** The borrower's verified credit profile, straight from the registry. */
export function useProfile(address: Address | undefined) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.registry,
    abi: registryAbi,
    functionName: 'profileOf',
    args: address === undefined ? undefined : [address],
    query: {enabled: address !== undefined},
  });
}

/**
 * The live tier. Read separately rather than derived from the score, because Platinum also
 * requires `late == 0` — a borrower can clear 700 points with a default on record and still be
 * Gold, so score alone cannot tell you the tier.
 */
export function useTier(address: Address | undefined) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.registry,
    abi: registryAbi,
    functionName: 'tierOf',
    args: address === undefined ? undefined : [address],
    query: {enabled: address !== undefined},
  });
}

/**
 * The borrower's demonstrated capacity — what actually gates undercollateralized borrowing.
 *
 * A tier is earned from history; this is earned only from repaying **real third-party capital** on
 * mainnet. A wallet can hold Platinum and still have zero capacity, in which case it gets the
 * Platinum rate on a fully collateralized loan and no discount at all. See `docs/THREAT_MODEL.md`.
 */
export function useDemonstratedCapacity(address: Address | undefined) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.registry,
    abi: registryAbi,
    functionName: 'demonstratedCapacityOf',
    args: address === undefined ? undefined : [address],
    query: {enabled: address !== undefined},
  });
}

/**
 * Collateral the pool will actually demand, read from the pool rather than recomputed.
 *
 * @remarks
 * Deriving this in the UI as `amount * collateralRatioBps / 10_000` looks right and is wrong: the
 * tier ratio is only applied up to `demonstratedCapacityWei`, and everything beyond it is fully
 * collateralized. The UI did exactly that, so a Platinum wallet with no real mainnet history was
 * quoted 85% and its borrow reverted for insufficient collateral — while also misrepresenting the
 * one mechanism the product is built on. There is one source of truth and it is the contract.
 */
export function useCollateralRequired(address: Address | undefined, amount: bigint) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.pool,
    abi: poolAbi,
    functionName: 'collateralRequired',
    args: address === undefined ? undefined : [address, amount],
    query: {enabled: address !== undefined},
  });
}

/** How much of a given borrow would actually be undercollateralized, after the capacity cap. */
export function useUndercollateralizedPortion(address: Address | undefined, amount: bigint) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.pool,
    abi: poolAbi,
    functionName: 'undercollateralizedPortion',
    args: address === undefined ? undefined : [address, amount],
    query: {enabled: address !== undefined},
  });
}

export function useBadgeToken(address: Address | undefined) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.sbt,
    abi: sbtAbi,
    functionName: 'tokenOf',
    args: address === undefined ? undefined : [address],
    query: {enabled: address !== undefined},
  });
}

export interface BadgeMetadata {
  name: string;
  description: string;
  image: string;
  attributes: {trait_type: string; value: string | number}[];
}

/**
 * Decodes the fully on-chain badge metadata.
 *
 * @remarks
 * `tokenURI` returns `data:application/json;base64,…` whose `image` is itself a base64 SVG data
 * URI. Rendered with `<img src={…}>`, never inlined into the DOM: an `<img>`-sourced SVG is
 * sandboxed by the renderer — scripts and external references are inert — whereas inlining a
 * contract-controlled string would put it inside our origin.
 */
export function useBadgeMetadata(tokenId: bigint | undefined) {
  const {data: uri, ...rest} = useReadContract({
    ...cc3,
    address: ADDRESSES.sbt,
    abi: sbtAbi,
    functionName: 'tokenURI',
    args: tokenId === undefined || tokenId === 0n ? undefined : [tokenId],
    query: {enabled: tokenId !== undefined && tokenId !== 0n},
  });

  const prefix = 'data:application/json;base64,';
  let metadata: BadgeMetadata | null = null;
  if (typeof uri === 'string' && uri.startsWith(prefix)) {
    try {
      metadata = JSON.parse(atob(uri.slice(prefix.length))) as BadgeMetadata;
    } catch {
      metadata = null;
    }
  }
  return {metadata, ...rest};
}

export function usePoolQuote(address: Address | undefined) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.pool,
    abi: poolAbi,
    functionName: 'quote',
    args: address === undefined ? undefined : [address],
    query: {enabled: address !== undefined},
  });
}

export function useActiveLoan(address: Address | undefined) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.pool,
    abi: poolAbi,
    functionName: 'loans',
    args: address === undefined ? undefined : [address],
    query: {enabled: address !== undefined},
  });
}

export function useTotalOwed(address: Address | undefined) {
  return useReadContract({
    ...cc3,
    address: ADDRESSES.pool,
    abi: poolAbi,
    functionName: 'totalOwed',
    args: address === undefined ? undefined : [address],
    query: {enabled: address !== undefined},
  });
}

/** All four tiers' terms, for the comparison table. */
export function useAllTerms() {
  const client = usePublicClient({chainId: creditcoinCC3.id});
  return useQuery({
    queryKey: ['allTerms'],
    enabled: client !== undefined,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const tiers = [0, 1, 2, 3] as const;
      return Promise.all(
        tiers.map(async (tier) => {
          const [collateralRatioBps, aprBps, maxBorrow] = await client!.readContract({
            address: ADDRESSES.pool,
            abi: poolAbi,
            functionName: 'termsFor',
            args: [tier],
          });
          return {tier, collateralRatioBps, aprBps, maxBorrow};
        }),
      );
    },
  });
}

export interface IngestedEvent {
  kind: string;
  queryId: Hex;
  loanId: bigint;
  cc3TxHash: Hex;
  blockNumber: bigint;
}

/** Credit events already verified on Creditcoin for this borrower. */
export function useIngestedEvents(address: Address | undefined) {
  const client = usePublicClient({chainId: creditcoinCC3.id});
  return useQuery({
    queryKey: ['ingested', address],
    enabled: client !== undefined && address !== undefined,
    refetchInterval: 15_000,
    queryFn: async (): Promise<IngestedEvent[]> => {
      const logs = await client!.getContractEvents({
        address: ADDRESSES.registry,
        abi: registryAbi,
        eventName: 'HistoryEventIngested',
        args: {borrower: address!},
        // CC3's eth_getLogs times out over wide spans, so start from the deploy block.
        fromBlock: REGISTRY_DEPLOY_BLOCK,
        toBlock: 'latest',
      });
      return logs.map((log) => ({
        kind: EVENT_SIGS[log.args.eventSig as keyof typeof EVENT_SIGS] ?? 'Unknown',
        queryId: log.args.queryId!,
        loanId: log.args.loanId ?? 0n,
        cc3TxHash: log.transactionHash,
        blockNumber: log.blockNumber,
      }));
    },
  });
}

/** The score's history, which makes the climb to Platinum visible rather than just stated. */
export function useScoreHistory(address: Address | undefined) {
  const client = usePublicClient({chainId: creditcoinCC3.id});
  return useQuery({
    queryKey: ['scoreHistory', address],
    enabled: client !== undefined && address !== undefined,
    refetchInterval: 15_000,
    queryFn: async () => {
      const logs = await client!.getContractEvents({
        address: ADDRESSES.registry,
        abi: registryAbi,
        eventName: 'ScoreUpdated',
        args: {borrower: address!},
        fromBlock: REGISTRY_DEPLOY_BLOCK,
        toBlock: 'latest',
      });
      return logs.map((log) => ({
        score: Number(log.args.newScore ?? 0),
        tier: Number(log.args.tier ?? 0),
        txHash: log.transactionHash,
      }));
    },
  });
}

/**
 * Widest span we ask a public endpoint for in one `eth_getLogs`. Chosen to sit under the smallest
 * cap we have seen in the wild rather than at the largest we could get away with.
 */
const LOG_WINDOW = 9_000n;

/**
 * Splits deploy-block-to-head into windows the endpoint will accept.
 *
 * @remarks
 * Returned as ranges rather than as a generic fetch helper on purpose: viem infers each event's
 * `args` type from a *literal* `eventName`, so funnelling all three through one parameterised
 * function widens them into a union and loses `principal`, `amount` and `onTime`.
 */
function logWindows(head: bigint): {fromBlock: bigint; toBlock: bigint}[] {
  const ranges: {fromBlock: bigint; toBlock: bigint}[] = [];
  for (let from = LOANBOOK_DEPLOY_BLOCK; from <= head; from += LOG_WINDOW) {
    const to = from + LOG_WINDOW - 1n;
    ranges.push({fromBlock: from, toBlock: to > head ? head : to});
  }
  return ranges;
}

export interface SourceEvent {
  kind: string;
  txHash: Hex;
  blockNumber: bigint;
  loanId: bigint | null;
  amount: bigint;
  onTime: boolean | null;
}

/**
 * The borrower's raw history on Sepolia — the facts that can be proven, whether or not they have
 * been yet.
 */
export function useSourceHistory(address: Address | undefined) {
  const client = usePublicClient({chainId: sepolia.id});
  return useQuery({
    queryKey: ['sourceHistory', address],
    enabled: client !== undefined && address !== undefined,
    staleTime: 30_000,
    queryFn: async (): Promise<SourceEvent[]> => {
      // Paginated, not because the history is large but because the WINDOW grows: the span from
      // the LoanBook deploy block to Sepolia's head widens by ~7,200 blocks a day, and public
      // endpoints reject `eth_getLogs` past a fixed range (commonly 10k-50k). An unpaginated query
      // therefore works for a week or two and then starts failing on its own, with no code change
      // — which would have taken the demo down around Aug 21, before the submission date.
      const head = await client!.getBlockNumber();
      const windows = logWindows(head);
      const base = {address: ADDRESSES.loanBook, abi: loanBookAbi, args: {borrower: address!}} as const;

      const [opened, repaid, collateral] = await Promise.all([
        Promise.all(
          windows.map((w) => client!.getContractEvents({...base, eventName: 'LoanOpened', ...w})),
        ).then((p) => p.flat()),
        Promise.all(
          windows.map((w) => client!.getContractEvents({...base, eventName: 'RepaymentMade', ...w})),
        ).then((p) => p.flat()),
        Promise.all(
          windows.map((w) => client!.getContractEvents({...base, eventName: 'CollateralAdded', ...w})),
        ).then((p) => p.flat()),
      ]);

      const events: SourceEvent[] = [
        ...opened.map((l) => ({
          kind: 'Loan opened',
          txHash: l.transactionHash,
          blockNumber: l.blockNumber,
          loanId: l.args.loanId ?? null,
          amount: l.args.principal ?? 0n,
          onTime: null,
        })),
        ...repaid.map((l) => ({
          kind: 'Repayment',
          txHash: l.transactionHash,
          blockNumber: l.blockNumber,
          loanId: l.args.loanId ?? null,
          amount: l.args.amount ?? 0n,
          onTime: l.args.onTime ?? null,
        })),
        ...collateral.map((l) => ({
          kind: 'Collateral added',
          txHash: l.transactionHash,
          blockNumber: l.blockNumber,
          loanId: null,
          amount: l.args.amount ?? 0n,
          onTime: null,
        })),
      ];

      return events.sort((a, b) => Number(a.blockNumber - b.blockNumber));
    },
  });
}

/** How far Creditcoin has attested Sepolia. Anything newer cannot be proven yet. */
export function useAttestedHeight() {
  return useQuery({
    queryKey: ['attestedHeight', SOURCE_CHAIN_KEY],
    queryFn: () => fetchAttestedHeight(),
    refetchInterval: 30_000,
  });
}
