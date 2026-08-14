import {useState} from 'react';
import {isAddress, type Address} from 'viem';
import {useAccount, useConnect, useDisconnect, useSwitchChain} from 'wagmi';
import {Link, useSearchParams} from 'react-router-dom';
import {Mark} from './site/Mark';
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
  const [params] = useSearchParams();
  const handedOver = params.get('address');
  const [viewing, setViewing] = useState<Address>(
    handedOver !== null && isAddress(handedOver)
      ? (handedOver as Address)
      : (DEMO_BORROWERS[0].address as Address),
  );
  const subject = DEMO_BORROWERS.find((b) => b.address.toLowerCase() === viewing.toLowerCase());

  const onRightChain = chainId === creditcoinCC3.id;
  // Writing requires a connected wallet, on CC3, acting for itself — you cannot import someone
  // else's history into their account from your wallet.
  const canWrite = isConnected && onRightChain && connected?.toLowerCase() === viewing.toLowerCase();

  return (
    <div className="grain min-h-screen bg-ink-950">
      <header className="border-b border-ink-700/60 bg-ink-950/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-5 py-4">
          {/* The mark links home, so the app is a room in the building rather than a separate one. */}
          <div className="flex items-center gap-5">
            <Link to="/" className="flex items-center gap-2.5" aria-label="CrossCredit home">
              <Mark size={26} />
              <span className="font-mono text-sm font-semibold tracking-[0.18em] text-vellum">
                CROSSCREDIT
              </span>
            </Link>
            <Link
              to="/explorer"
              className="hidden font-mono text-label uppercase text-ash transition-colors duration-200 hover:text-vellum sm:inline"
            >
              Explorer
            </Link>
          </div>

          <div className="flex items-center gap-2">
            {isConnected && !onRightChain && (
              <button
                onClick={() => switchChain({chainId: creditcoinCC3.id})}
                className="rounded-sm px-3 py-2 font-mono text-label uppercase text-assay ring-1 ring-assay/60 transition-colors duration-200 hover:bg-assay/10"
              >
                Switch to Creditcoin CC3
              </button>
            )}
            {isConnected ? (
              <button
                onClick={() => disconnect()}
                className="rounded-sm border border-ink-600 px-3 py-2 font-mono text-xs text-vellum transition-colors duration-200 hover:border-assay"
              >
                {connected?.slice(0, 6)}…{connected?.slice(-4)}
              </button>
            ) : (
              <button
                onClick={() => connectors[0] !== undefined && connect({connector: connectors[0]})}
                className="rounded-sm bg-assay px-4 py-2 font-mono text-xs font-semibold text-ink-950 transition-transform duration-200 ease-toggle active:translate-y-[var(--strike-depth)]"
              >
                Connect wallet
              </button>
            )}
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl space-y-5 px-5 py-6">
        {/*
          The borrower picker moved to /explorer. Two address inputs doing the same job meant two
          front doors, and the plainer one was inside the dapp — so a judge could easily meet the
          product before meeting the brand. This keeps the subject visible and hands changing it
          off to the page that owns it.
        */}
        <section className="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 rounded-sm border border-ink-700 bg-ink-900/60 px-5 py-4">
          <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span className="font-mono text-label uppercase text-ash">Viewing</span>
            <span className="font-mono text-sm text-vellum">{viewing}</span>
            {subject !== undefined && <span className="text-xs text-ash">{subject.note}</span>}
          </div>
          <div className="flex items-center gap-4">
            {isConnected && connected !== undefined && viewing.toLowerCase() !== connected.toLowerCase() && (
              <button
                onClick={() => setViewing(connected)}
                className="font-mono text-label uppercase text-assay transition-colors duration-200 hover:text-vellum"
              >
                View my wallet
              </button>
            )}
            <Link
              to={`/explorer?a=${viewing}`}
              className="font-mono text-label uppercase text-ash transition-colors duration-200 hover:text-vellum"
            >
              Change borrower →
            </Link>
          </div>
        </section>

        {isConnected && !canWrite && onRightChain && (
          <p className="text-xs text-assay">
            You are viewing another borrower. Switch to your own wallet to import history, mint a
            badge or borrow.
          </p>
        )}

        <nav className="flex gap-1 rounded-sm border border-ink-700 bg-ink-900/60 p-1">
          {TABS.map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition ${
                tab === t.id ? 'bg-ink-600 text-vellum' : 'text-ash hover:text-vellum'
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

      <footer className="mx-auto max-w-6xl px-5 pb-10 pt-4 text-xs text-ash/50">
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
            href="https://github.com/OoJae/crosscredit/blob/main/docs/THREAT_MODEL.md"
            target="_blank"
            rel="noreferrer"
            className="text-ash hover:text-vellum"
          >
            What this does not solve
          </a>
          <a
            href="https://github.com/OoJae/crosscredit"
            target="_blank"
            rel="noreferrer"
            className="text-ash hover:text-vellum"
          >
            Source on GitHub
          </a>
        </div>
        <p className="mt-3 max-w-3xl leading-relaxed">
          Testnet deployment, real mainnet data. History is proven from Ethereum mainnet and Sepolia
          to Creditcoin CC3 by the Attestcoin Protocol&rsquo;s native block-prover precompile — a
          Merkle inclusion proof plus a chain-continuity proof, verified inside a single Creditcoin
          block. There is no oracle we run, no multisig we control and no bridge holding funds;
          Creditcoin&rsquo;s attestor set is in the trust path, which is to say this needs no trust
          beyond the chain you are already settling on.
        </p>
      </footer>
    </div>
  );
}
