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
  onTime: number;
  late: number;
  loansOpened: number;
  loansClosed: number;
  firstSeen: bigint;
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
      const [opened, repaid, collateral] = await Promise.all([
        client!.getContractEvents({
          address: ADDRESSES.loanBook,
          abi: loanBookAbi,
          eventName: 'LoanOpened',
          args: {borrower: address!},
          fromBlock: LOANBOOK_DEPLOY_BLOCK,
        }),
        client!.getContractEvents({
          address: ADDRESSES.loanBook,
          abi: loanBookAbi,
          eventName: 'RepaymentMade',
          args: {borrower: address!},
          fromBlock: LOANBOOK_DEPLOY_BLOCK,
        }),
        client!.getContractEvents({
          address: ADDRESSES.loanBook,
          abi: loanBookAbi,
          eventName: 'CollateralAdded',
          args: {borrower: address!},
          fromBlock: LOANBOOK_DEPLOY_BLOCK,
        }),
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
