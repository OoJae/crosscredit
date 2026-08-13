import {useState} from 'react';
import {isAddress, type Address} from 'viem';
import {useAccount, useConnect, useDisconnect, useSwitchChain} from 'wagmi';
import {creditcoinCC3, DEMO_BORROWERS, ADDRESSES} from './config';
import Dashboard from './tabs/Dashboard';
import ImportHistory from './tabs/ImportHistory';
import Borrow from './tabs/Borrow';
import {ExplorerLink} from './components/ui';

const TABS = [
  {id: 'dashboard', label: 'Dashboard'},
  {id: 'import', label: 'Import history'},
  {id: 'borrow', label: 'Borrow'},
] as const;
type TabId = (typeof TABS)[number]['id'];

export default function App() {
  const {address: connected, chainId, isConnected} = useAccount();
  const {connect, connectors} = useConnect();
  const {disconnect} = useDisconnect();
  const {switchChain} = useSwitchChain();

  const [tab, setTab] = useState<TabId>('dashboard');
  // Read-only by default: a judge should see the whole product without a wallet or any testnet
  // funds. Connecting only adds the ability to sign.
  const [viewing, setViewing] = useState<Address>(DEMO_BORROWERS[0].address as Address);
  const [input, setInput] = useState('');

  const onRightChain = chainId === creditcoinCC3.id;
  // Writing requires a connected wallet, on CC3, acting for itself — you cannot import someone
  // else's history into their account from your wallet.
  const canWrite = isConnected && onRightChain && connected?.toLowerCase() === viewing.toLowerCase();

  return (
    <div className="min-h-screen">
      <header className="border-b border-ink-600 bg-ink-800/60 backdrop-blur">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-5 py-4">
          <div>
            <h1 className="text-lg font-bold tracking-tight text-slate-100">CrossCredit</h1>
            <p className="text-xs text-slate-500">
              Portable credit reputation, verified across chains on Creditcoin
            </p>
          </div>

          <div className="flex items-center gap-2">
            {isConnected && !onRightChain && (
              <button
                onClick={() => switchChain({chainId: creditcoinCC3.id})}
                className="rounded-lg bg-amber-500/90 px-3 py-2 text-xs font-semibold text-ink-900 hover:bg-amber-400"
              >
                Switch to Creditcoin CC3
              </button>
            )}
            {isConnected ? (
              <button
                onClick={() => disconnect()}
                className="rounded-lg border border-ink-600 px-3 py-2 font-mono text-xs text-slate-300 hover:border-slate-500"
              >
                {connected?.slice(0, 6)}…{connected?.slice(-4)}
              </button>
            ) : (
              <button
                onClick={() => connectors[0] !== undefined && connect({connector: connectors[0]})}
                className="rounded-lg bg-sky-500 px-3 py-2 text-xs font-semibold text-ink-900 hover:bg-sky-400"
              >
                Connect wallet
              </button>
            )}
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl space-y-5 px-5 py-6">
        <section className="rounded-xl border border-ink-600 bg-ink-800 p-5">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-widest text-slate-400">
                Viewing borrower
              </h2>
              <p className="mt-1 font-mono text-sm text-slate-200">{viewing}</p>
              <p className="mt-1 text-xs text-slate-500">
                No wallet needed to look around — everything below is read from live testnet.
              </p>
            </div>
            <form
              className="flex gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                if (isAddress(input)) setViewing(input);
              }}
            >
              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="0x… any address"
                className="w-64 rounded-lg border border-ink-600 bg-ink-900 px-3 py-2 font-mono text-xs text-slate-200 outline-none focus:border-sky-500"
              />
              <button
                type="submit"
                disabled={!isAddress(input)}
                className="rounded-lg border border-ink-600 px-3 py-2 text-xs text-slate-300 hover:border-slate-500 disabled:text-slate-600"
              >
                View
              </button>
            </form>
          </div>

          <div className="mt-4 flex flex-wrap gap-2">
            {DEMO_BORROWERS.map((b) => (
              <button
                key={b.address}
                onClick={() => setViewing(b.address as Address)}
                className={`rounded-lg border px-3 py-2 text-left text-xs transition ${
                  viewing.toLowerCase() === b.address.toLowerCase()
                    ? 'border-sky-500/60 bg-sky-500/10 text-slate-100'
                    : 'border-ink-600 text-slate-400 hover:border-slate-500'
                }`}
              >
                <div className="font-semibold">{b.label}</div>
                <div className="text-slate-500">{b.note}</div>
              </button>
            ))}
            {isConnected && connected !== undefined && (
              <button
                onClick={() => setViewing(connected)}
                className={`rounded-lg border px-3 py-2 text-left text-xs transition ${
                  viewing.toLowerCase() === connected.toLowerCase()
                    ? 'border-sky-500/60 bg-sky-500/10 text-slate-100'
                    : 'border-ink-600 text-slate-400 hover:border-slate-500'
                }`}
              >
                <div className="font-semibold">Your wallet</div>
                <div className="font-mono text-slate-500">
                  {connected.slice(0, 10)}…{connected.slice(-6)}
                </div>
              </button>
            )}
          </div>

          {isConnected && !canWrite && onRightChain && (
            <p className="mt-3 text-xs text-amber-300/80">
              You are viewing another borrower. Switch to &ldquo;Your wallet&rdquo; to import
              history, mint a badge or borrow.
            </p>
          )}
        </section>

        <nav className="flex gap-1 rounded-xl border border-ink-600 bg-ink-800 p-1">
          {TABS.map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition ${
                tab === t.id ? 'bg-ink-600 text-slate-100' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {t.label}
            </button>
          ))}
        </nav>

        {tab === 'dashboard' && <Dashboard address={viewing} canWrite={canWrite} />}
        {tab === 'import' && <ImportHistory address={viewing} canWrite={canWrite} />}
        {tab === 'borrow' && <Borrow address={viewing} canWrite={canWrite} />}
      </main>

      <footer className="mx-auto max-w-6xl px-5 pb-10 pt-4 text-xs text-slate-600">
        <div className="flex flex-wrap gap-x-5 gap-y-1 border-t border-ink-700 pt-4">
          <span>
            Registry <ExplorerLink chain="cc3" type="address" hash={ADDRESSES.registry}>
              {ADDRESSES.registry.slice(0, 10)}…
            </ExplorerLink>
          </span>
          <span>
            LoanBook (Sepolia){' '}
            <ExplorerLink chain="sepolia" type="address" hash={ADDRESSES.loanBook}>
              {ADDRESSES.loanBook.slice(0, 10)}…
            </ExplorerLink>
          </span>
          <a
            href="https://github.com/OoJae/crosscredit"
            target="_blank"
            rel="noreferrer"
            className="text-sky-400/70 hover:text-sky-400"
          >
            Source on GitHub
          </a>
        </div>
        <p className="mt-3 max-w-3xl leading-relaxed">
          Testnet only. Credit history is proven from Ethereum Sepolia to Creditcoin CC3 by the
          Attestcoin Protocol&rsquo;s native block-prover precompile — a Merkle inclusion proof plus
          a chain-continuity proof, verified inside a single Creditcoin block. No oracle operator,
          no bridge multisig.
        </p>
      </footer>
    </div>
  );
}
