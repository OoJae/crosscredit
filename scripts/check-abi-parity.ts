/**
 * Fails if `web/src/abis.ts` has drifted from the compiled contracts.
 *
 * The frontend's ABI is hand-written, so the web build has no dependency on a gitignored Foundry
 * artifact directory. That trade-off cost us three defects at once, two of them invisible:
 *
 *   - `HistoryEventIngested` was declared without its `uint64 chainKey`. viem derives the topic0
 *     filter from the signature, so the app filtered on a hash the registry never emits and the
 *     verified-events table read as "this borrower has no history" for every borrower. No error.
 *   - `UnregisteredSource` was declared where the contract defines `SourceNotRegistered`, so that
 *     revert could never decode into a readable reason.
 *   - `CreditProfile` had to be widened by hand every time the struct changed.
 *
 * A wrong ABI does not throw. It decodes garbage, or silently matches nothing. This compares every
 * function selector and event topic0 in the hand-written file against the compiled artifact, which
 * is the only source of truth either side can agree on.
 *
 * Run: npx tsx scripts/check-abi-parity.ts
 */
import {readFileSync} from 'node:fs';
import {id, Interface, type InterfaceAbi} from 'ethers';
import {registryAbi, sbtAbi, poolAbi, loanBookAbi} from '../web/src/abis.js';

interface Target {
  label: string;
  artifact: string;
  abi: readonly unknown[];
}

const TARGETS: Target[] = [
  {
    label: 'CreditRegistry',
    artifact: 'contracts/out/CreditRegistry.sol/CreditRegistry.json',
    abi: registryAbi,
  },
  {label: 'CreditTierSBT', artifact: 'contracts/out/CreditTierSBT.sol/CreditTierSBT.json', abi: sbtAbi},
  {label: 'LendingPool', artifact: 'contracts/out/LendingPool.sol/LendingPool.json', abi: poolAbi},
  {label: 'LoanBook', artifact: 'contracts/out/LoanBook.sol/LoanBook.json', abi: loanBookAbi},
];

/** Every selector/topic0 the compiled contract actually exposes, by name. */
function compiledSignatures(artifactPath: string): Map<string, Set<string>> {
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf8')) as {abi: InterfaceAbi};
  const iface = new Interface(artifact.abi);
  const byName = new Map<string, Set<string>>();

  const add = (name: string, signature: string): void => {
    const existing = byName.get(name) ?? new Set<string>();
    existing.add(signature);
    byName.set(name, existing);
  };

  iface.forEachFunction((fragment) => add(fragment.name, fragment.format('sighash')));
  iface.forEachEvent((fragment) => add(fragment.name, fragment.format('sighash')));
  iface.forEachError((fragment) => add(fragment.name, fragment.format('sighash')));

  return byName;
}

function check(target: Target): string[] {
  const compiled = compiledSignatures(target.artifact);
  const iface = new Interface(target.abi as InterfaceAbi);
  const problems: string[] = [];

  const verify = (kind: string, name: string, signature: string): void => {
    const candidates = compiled.get(name);
    if (candidates === undefined) {
      problems.push(`${target.label}: ${kind} "${name}" does not exist on the contract`);
      return;
    }
    if (!candidates.has(signature)) {
      problems.push(
        `${target.label}: ${kind} "${signature}" (${id(signature).slice(0, 10)}) does not match the ` +
          `contract, which has ${[...candidates].map((c) => `"${c}"`).join(' or ')}`,
      );
    }
  };

  iface.forEachFunction((f) => verify('function', f.name, f.format('sighash')));
  iface.forEachEvent((e) => verify('event', e.name, e.format('sighash')));
  iface.forEachError((e) => verify('error', e.name, e.format('sighash')));

  return problems;
}

function main(): void {
  const problems = TARGETS.flatMap((target) => check(target));

  if (problems.length > 0) {
    console.error('✗ web/src/abis.ts has drifted from the compiled contracts:\n');
    for (const problem of problems) console.error(`  ${problem}`);
    console.error('\nA wrong ABI does not throw — it decodes garbage or matches nothing.');
    process.exitCode = 1;
    return;
  }

  const counted = TARGETS.map((t) => {
    const iface = new Interface(t.abi as InterfaceAbi);
    let n = 0;
    iface.forEachFunction(() => ++n);
    iface.forEachEvent(() => ++n);
    iface.forEachError(() => ++n);
    return `${t.label} (${n})`;
  });

  console.log(`✓ web ABI matches the compiled contracts — ${counted.join(', ')}`);
}

main();
