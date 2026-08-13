/**
 * Source-chain event discovery.
 *
 * Every LoanBook event in a block range is collected and grouped by transaction, because the
 * registry ingests a whole transaction per proof — one proof covers every credit event that
 * transaction emitted, and proving the same transaction twice is replay-blocked by design.
 */
import {ethers} from 'ethers';
import {LOG_SCAN_CHUNK} from './config.js';

export interface SourceEvent {
  txHash: string;
  blockNumber: number;
  eventName: string;
  borrower: string;
}

/**
 * Scans `[fromBlock, toBlock]` for LoanBook events, paginating so no single `eth_getLogs` call
 * exceeds the provider's range limit.
 *
 * @param contract LoanBook, connected to a source-chain provider.
 * @param fromBlock Inclusive start block.
 * @param toBlock Inclusive end block.
 */
export async function scanEvents(
  contract: ethers.Contract,
  fromBlock: number,
  toBlock: number,
): Promise<SourceEvent[]> {
  const found: SourceEvent[] = [];

  for (let start = fromBlock; start <= toBlock; start += LOG_SCAN_CHUNK) {
    const end = Math.min(start + LOG_SCAN_CHUNK - 1, toBlock);
    const logs = await contract.queryFilter('*', start, end);

    for (const log of logs) {
      if (!('fragment' in log) || log.fragment === undefined) continue;
      const args = (log).args;
      found.push({
        txHash: log.transactionHash,
        blockNumber: log.blockNumber,
        eventName: (log).fragment.name,
        borrower: (args['borrower'] as string | undefined) ?? ethers.ZeroAddress,
      });
    }
  }

  return found;
}

/**
 * Collapses events into the unit the registry actually consumes: one entry per source
 * transaction, since a single proof carries every credit event that transaction emitted.
 */
export function groupByTransaction(events: SourceEvent[]): SourceEvent[] {
  const seen = new Set<string>();
  const unique: SourceEvent[] = [];
  for (const event of events) {
    if (seen.has(event.txHash)) continue;
    seen.add(event.txHash);
    unique.push(event);
  }
  return unique;
}
