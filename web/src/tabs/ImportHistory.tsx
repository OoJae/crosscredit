import {useState} from 'react';
import type {Address} from 'viem';
import {formatEther} from 'viem';
import {usePublicClient, useWriteContract} from 'wagmi';
import {ADDRESSES, SOURCES, creditcoinCC3} from '../config';
import {registryAbi} from '../abis';
import {useSourceHistory, useIngestedEvents, useAttestedHeight, useProfile, useTier} from '../hooks';
import {fetchBatchProof, dryRunBatch, MAX_BATCH_SIZE} from '../prover';
import {Card, Button, Banner, Spinner, ExplorerLink, TierPill, readableError} from '../components/ui';

/** The steps a user watches while their history is proven. */
type Stage =
  | {phase: 'idle'}
  | {phase: 'proving'; detail: string}
  | {phase: 'signing'}
  | {phase: 'confirming'; hash: string}
  | {phase: 'done'; hash: string; count: number; gasUsed: bigint}
  | {phase: 'error'; message: string};

export default function ImportHistory({address, canWrite}: {address: Address; canWrite: boolean}) {
  const client = usePublicClient({chainId: creditcoinCC3.id});
  const {data: source, isLoading} = useSourceHistory(address);
  const {data: ingested, refetch: refetchIngested} = useIngestedEvents(address);
  const {data: attestedHeight} = useAttestedHeight();
  const {refetch: refetchProfile} = useProfile(address);
  const {data: tier, refetch: refetchTier} = useTier(address);
  const {writeContractAsync} = useWriteContract();

  const [stage, setStage] = useState<Stage>({phase: 'idle'});

  // A query id is derived from (chainKey, blockHeight, txIndex), so it identifies one *source*
  // transaction. Counting distinct Creditcoin transactions instead would report "1" for a
  // nine-event batch, which reads as if almost nothing had been verified.
  const importedTxCount = new Set(ingested?.map((e) => e.queryId)).size;
  // How many Creditcoin transactions it actually took — 1 for a batch, N for proof-by-proof.
  const cc3TxCount = new Set(ingested?.map((e) => e.cc3TxHash)).size;
  const sourceTxHashes = [...new Set((source ?? []).map((e) => e.txHash))];
  const alreadyProven = ingested !== undefined && ingested.length > 0;

  // Only transactions Creditcoin has attested can be proven at all.
  const provable = (source ?? []).filter(
    (e) => attestedHeight !== undefined && e.blockNumber <= attestedHeight,
  );
  const provableTxHashes = [...new Set(provable.map((e) => e.txHash))];
  const waitingOnAttestation = sourceTxHashes.length - provableTxHashes.length;

  const pending = alreadyProven ? [] : provableTxHashes;
  const batch = pending.slice(0, MAX_BATCH_SIZE);

  async function runImport() {
    if (client === undefined) return;
    try {
      setStage({phase: 'proving', detail: 'Requesting one shared continuity proof…'});
      const args = await fetchBatchProof(batch);

      setStage({
        phase: 'proving',
        detail: `Checking the proof against the precompile (free) — ${args.heights.length} transactions, ${args.continuityProof.roots.length} shared roots…`,
      });
      // Free pre-flight: the verify view runs the same checks as the real call, so nobody is ever
      // asked to sign a transaction that cannot succeed.
      await dryRunBatch(client, args);

      setStage({phase: 'signing'});
      const hash = await writeContractAsync({
        address: ADDRESSES.registry,
        abi: registryAbi,
        functionName: 'executeBatch',
        args: [
          // ACTION_GENERIC. `action` is a declared hint only — the registry routes on each proven
          // log's own emitter and topic0 — and `Generic` (0) is the sole valid enum member, so
          // anything else reverts with `UnknownAction`. This passed 1 (a stale value from when
          // actions were per-event), which made every batch import from the UI revert.
          args.sourceTxHashes.map(() => 0),
          BigInt(args.chainKey),
          args.heights,
          args.encodedTransactions,
          args.merkleProofs,
          args.continuityProof,
        ],
      });

      setStage({phase: 'confirming', hash});
      const receipt = await client.waitForTransactionReceipt({hash});
      if (receipt.status !== 'success') throw new Error('the transaction reverted on Creditcoin');

      setStage({phase: 'done', hash, count: batch.length, gasUsed: receipt.gasUsed});
      void refetchIngested();
      void refetchProfile();
      void refetchTier();
    } catch (error) {
      setStage({phase: 'error', message: readableError(error)});
    }
  }

  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <Card
        className="lg:col-span-3"
        title="Credit sources this registry reads"
        subtitle="Each row is an (chainKey, contract) pair the registry will accept proofs for. Dispatch is driven by the emitter and topic0 of each proven log — never by anything the caller declares."
      >
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-[11px] uppercase tracking-wider text-ash">
              <tr className="border-b border-ink-600">
                <th className="pb-2 pr-4 font-medium">Chain</th>
                <th className="pb-2 pr-4 font-medium">Protocol</th>
                <th className="pb-2 pr-4 font-medium">Contract</th>
                <th className="pb-2 font-medium">Raises borrowing capacity?</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-ink-700/60">
              {SOURCES.map((src) => (
                <tr key={`${src.chainKey}-${src.address}`} className="text-vellum">
                  <td className="py-2 pr-4">
                    <span className="rounded bg-ink-900 px-1.5 py-0.5 font-mono text-xs text-ash ring-1 ring-ink-600">
                      {src.chain}
                    </span>
                  </td>
                  <td className="py-2 pr-4">{src.name}</td>
                  <td className="py-2 pr-4 font-mono text-xs text-ash">
                    {src.address.slice(0, 10)}…
                  </td>
                  <td className="py-2 text-xs">
                    {src.raisesCapacity ? (
                      <span className="text-emerald-300/90">Yes — {src.note}</span>
                    ) : (
                      <span className="text-ash">No — {src.note}</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-3 max-w-3xl text-xs leading-relaxed text-ash">
          The split in the last column is the whole design. Our own LoanBook is permissionless and
          escrows nothing, so anyone can manufacture a perfect record on it for the price of gas —
          it earns a tier, never a credit line. Aave and Sparklend had real third-party capital at
          risk, so only they can raise the amount you may borrow above what you post. Mainnet
          imports run one proof per event: real history spans years, and the prover rejects a batch
          wider than 1,000 blocks.
        </p>
      </Card>

      <Card
        className="lg:col-span-2"
        title="History on Ethereum Sepolia"
        subtitle="Facts that exist on another chain. Creditcoin knows nothing about them until they are proven."
      >
        {isLoading ? (
          <Spinner label="Scanning Sepolia…" />
        ) : sourceTxHashes.length === 0 ? (
          <p className="text-sm text-ash">
            No LoanBook activity for this address. Pick one of the demo borrowers above to see a
            seeded history.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-[11px] uppercase tracking-wider text-ash">
                <tr className="border-b border-ink-600">
                  <th className="pb-2 pr-4 font-medium">Event</th>
                  <th className="pb-2 pr-4 font-medium">Amount</th>
                  <th className="pb-2 pr-4 font-medium">Block</th>
                  <th className="pb-2 font-medium">Sepolia transaction</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-ink-700/60">
                {(source ?? []).map((event) => (
                  <tr key={`${event.txHash}-${event.kind}`} className="text-vellum">
                    <td className="py-2 pr-4">
                      {event.kind}
                      {event.onTime === false && (
                        <span className="ml-2 rounded bg-rose-500/15 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-rose-300">
                          late
                        </span>
                      )}
                      {event.onTime === true && (
                        <span className="ml-2 rounded bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-emerald-300">
                          on time
                        </span>
                      )}
                    </td>
                    <td className="py-2 pr-4 font-mono text-xs">{formatEther(event.amount)} ETH</td>
                    <td className="py-2 pr-4 font-mono text-xs text-ash">
                      {event.blockNumber.toString()}
                    </td>
                    <td className="py-2">
                      <ExplorerLink chain="sepolia" type="tx" hash={event.txHash} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card title="Prove it to Creditcoin" subtitle="One transaction. One signature.">
        <div className="space-y-4">
          <div className="space-y-1.5 text-sm">
            <Row label="Events on Sepolia" value={String(source?.length ?? 0)} />
            <Row label="Transactions to prove" value={String(sourceTxHashes.length)} />
            <Row label="Already verified" value={String(importedTxCount)} />
            {waitingOnAttestation > 0 && (
              <Row
                label="Awaiting attestation"
                value={String(waitingOnAttestation)}
                tone="warn"
              />
            )}
          </div>

          {alreadyProven ? (
            <Banner tone="success">
              <div className="space-y-1">
                <div>
                  This history is already on Creditcoin — {importedTxCount} source transaction
                  {importedTxCount === 1 ? '' : 's'} verified in {cc3TxCount} Creditcoin
                  transaction{cc3TxCount === 1 ? '' : 's'}, current tier{' '}
                  <TierPill tier={Number(tier ?? 0)} />.
                </div>
                <div className="text-xs opacity-80">
                  Re-importing would revert against the replay guard, which is the point: one
                  source transaction can move a score exactly once.
                </div>
              </div>
            </Banner>
          ) : batch.length === 0 ? (
            <Banner tone="info">
              {waitingOnAttestation > 0
                ? 'Waiting for Creditcoin to attest these Sepolia blocks. That takes about 8–10 minutes after the transaction lands.'
                : 'Nothing to import for this address.'}
            </Banner>
          ) : (
            <>
              <p className="text-xs text-ash">
                {batch.length} transaction{batch.length === 1 ? '' : 's'} will be verified against a{' '}
                <strong className="text-vellum">single shared continuity proof</strong> — the
                precompile walks back to an attested block once instead of {batch.length} times.
                {pending.length > MAX_BATCH_SIZE &&
                  ` ${pending.length - MAX_BATCH_SIZE} more will need a second batch (the limit is ${MAX_BATCH_SIZE}).`}
              </p>
              <Button
                disabled={!canWrite || (stage.phase !== 'idle' && stage.phase !== 'error')}
                onClick={() => void runImport()}
              >
                {canWrite ? `Import ${batch.length} events in one transaction` : 'Connect a wallet to import'}
              </Button>
            </>
          )}

          {stage.phase === 'proving' && <Spinner label={stage.detail} />}
          {stage.phase === 'signing' && <Spinner label="Waiting for your signature…" />}
          {stage.phase === 'confirming' && <Spinner label="Verifying on Creditcoin…" />}
          {stage.phase === 'error' && <Banner tone="error">{stage.message}</Banner>}
          {stage.phase === 'done' && (
            <Banner tone="success">
              <div className="space-y-1">
                <div className="font-semibold">
                  {stage.count} events verified in one transaction.
                </div>
                <div className="text-xs opacity-80">
                  {stage.gasUsed.toLocaleString()} gas —{' '}
                  {Math.round(Number(stage.gasUsed) / stage.count).toLocaleString()} per event,
                  against roughly 433,000 proving them one at a time.
                </div>
                <ExplorerLink chain="cc3" type="tx" hash={stage.hash} />
              </div>
            </Banner>
          )}

          <p className="border-t border-ink-600 pt-3 text-[11px] leading-relaxed text-ash">
            No oracle signs off on this, and no bridge custodies anything. Creditcoin&rsquo;s
            block-prover precompile checks a Merkle inclusion proof and a chain-continuity proof
            itself, inside the same transaction that acts on the result.
          </p>
        </div>
      </Card>
    </div>
  );
}

function Row({label, value, tone}: {label: string; value: string; tone?: 'warn'}) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <span className="text-ash">{label}</span>
      <span className={`font-mono tabular-nums ${tone === 'warn' ? 'text-assay' : 'text-vellum'}`}>
        {value}
      </span>
    </div>
  );
}
