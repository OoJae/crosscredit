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
 *   - `RepaymentMade` kept its pre-`payer` signature after LoanBook v2.
 *
 * A wrong ABI does not throw. It decodes garbage, or silently matches nothing.
 *
 * @remarks
 * The signatures are parsed straight out of the source text rather than imported. Importing the
 * module would drag `viem` into this script, and `viem` lives in `web/node_modules` — so the check
 * passed locally and failed in CI, where the root job installs only the root dependencies. Reading
 * the file also means we validate the bytes that actually ship.
 *
 * Run: npm run check:abi
 */
import {readFileSync} from 'node:fs';
import {Interface, type InterfaceAbi} from 'ethers';

const ABI_SOURCE = 'web/src/abis.ts';

interface Target {
  label: string;
  /** The exported const in `abis.ts`. */
  binding: string;
  artifact: string;
}

const TARGETS: Target[] = [
  {label: 'CreditRegistry', binding: 'registryAbi', artifact: 'contracts/out/CreditRegistry.sol/CreditRegistry.json'},
  {label: 'CreditTierSBT', binding: 'sbtAbi', artifact: 'contracts/out/CreditTierSBT.sol/CreditTierSBT.json'},
  {label: 'LendingPool', binding: 'poolAbi', artifact: 'contracts/out/LendingPool.sol/LendingPool.json'},
  {label: 'LoanBook', binding: 'loanBookAbi', artifact: 'contracts/out/LoanBook.sol/LoanBook.json'},
];

/** Pulls the quoted human-readable ABI entries out of one `parseAbi([...])` block. */
function declaredEntries(source: string, binding: string): string[] {
  const start = source.indexOf(`export const ${binding} = parseAbi([`);
  if (start === -1) throw new Error(`${ABI_SOURCE}: no export named "${binding}"`);
  const end = source.indexOf(']);', start);
  if (end === -1) throw new Error(`${ABI_SOURCE}: unterminated parseAbi for "${binding}"`);

  return [...source.slice(start, end).matchAll(/'((?:[^'\\]|\\.)*)'/g)]
    .map((match) => match[1] ?? '')
    .filter((entry) => /^(function|event|error|struct)\s/.test(entry));
}

/**
 * Maps `struct Name { t a; u b; }` to the tuple `(t,u)` a signature would use.
 *
 * @remarks
 * Structs nest — `MerkleProof` holds a `MerkleProofEntry[]` — so a single pass leaves a struct
 * name embedded inside another tuple and every comparison against it fails. Expansion therefore
 * runs to a fixed point.
 */
function structTuples(entries: string[]): Map<string, string> {
  const tuples = new Map<string, string>();

  for (const entry of entries) {
    const match = /^struct\s+(\w+)\s*\{(.*)\}$/.exec(entry);
    if (match === null) continue;
    const fields = (match[2] ?? '')
      .split(';')
      .map((field) => field.trim())
      .filter(Boolean)
      .map((field) => field.split(/\s+/)[0] ?? '');
    tuples.set(match[1] ?? '', `(${fields.join(',')})`);
  }

  // Substitute struct names inside tuples until nothing changes. Bounded by the number of structs,
  // so a cyclic definition (which Solidity rejects anyway) cannot spin here.
  for (let pass = 0; pass <= tuples.size; ++pass) {
    let changed = false;
    for (const [name, tuple] of tuples) {
      const expanded = tuple.replace(/\b([A-Z]\w*)\b/g, (token) => tuples.get(token) ?? token);
      if (expanded !== tuple) {
        tuples.set(name, expanded);
        changed = true;
      }
    }
    if (!changed) break;
  }

  return tuples;
}

/** Reduces one declaration to `name(type,type)` with structs expanded and names stripped. */
function canonical(entry: string, tuples: Map<string, string>): {kind: string; name: string; sig: string} | null {
  const match = /^(function|event|error)\s+(\w+)\s*\((.*?)\)\s*(?:view|pure|payable|nonpayable)?\s*(?:returns\s*\(.*\))?$/s.exec(
    entry,
  );
  if (match === null) return null;

  const [, kind = '', name = '', params = ''] = match;
  const types = splitParams(params).map((param) => {
    const bare = param.trim().replace(/\b(indexed|calldata|memory|storage)\b/g, '').trim();
    const type = bare.split(/\s+/)[0] ?? '';
    const suffix = type.endsWith('[]') ? '[]' : '';
    const base = suffix === '' ? type : type.slice(0, -2);
    return (tuples.get(base) ?? base) + suffix;
  });

  return {kind, name, sig: `${name}(${types.join(',')})`};
}

/** Splits a parameter list on commas that are not inside brackets. */
function splitParams(params: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let current = '';
  for (const char of params) {
    if (char === '(' || char === '[') depth += 1;
    if (char === ')' || char === ']') depth -= 1;
    if (char === ',' && depth === 0) {
      out.push(current);
      current = '';
      continue;
    }
    current += char;
  }
  if (current.trim() !== '') out.push(current);
  return out;
}

function compiledSignatures(artifactPath: string): Map<string, Set<string>> {
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf8')) as {abi: InterfaceAbi};
  const iface = new Interface(artifact.abi);
  const byName = new Map<string, Set<string>>();

  const add = (name: string, signature: string): void => {
    const existing = byName.get(name) ?? new Set<string>();
    existing.add(signature);
    byName.set(name, existing);
  };

  iface.forEachFunction((f) => add(f.name, f.format('sighash')));
  iface.forEachEvent((e) => add(e.name, e.format('sighash')));
  iface.forEachError((e) => add(e.name, e.format('sighash')));
  return byName;
}

function main(): void {
  const source = readFileSync(ABI_SOURCE, 'utf8');
  const problems: string[] = [];
  let checked = 0;

  for (const target of TARGETS) {
    const entries = declaredEntries(source, target.binding);
    const tuples = structTuples(entries);
    const compiled = compiledSignatures(target.artifact);

    for (const entry of entries) {
      const parsed = canonical(entry, tuples);
      if (parsed === null) continue;
      checked += 1;

      const candidates = compiled.get(parsed.name);
      if (candidates === undefined) {
        problems.push(`${target.label}: ${parsed.kind} "${parsed.name}" does not exist on the contract`);
        continue;
      }
      if (!candidates.has(parsed.sig)) {
        problems.push(
          `${target.label}: ${parsed.kind} "${parsed.sig}" does not match the contract, which has ` +
            [...candidates].map((c) => `"${c}"`).join(' or '),
        );
      }
    }
  }

  if (problems.length > 0) {
    console.error(`✗ ${ABI_SOURCE} has drifted from the compiled contracts:\n`);
    for (const problem of problems) console.error(`  ${problem}`);
    console.error('\nA wrong ABI does not throw — it decodes garbage or matches nothing.');
    process.exitCode = 1;
    return;
  }

  console.log(`✓ ${ABI_SOURCE} matches the compiled contracts — ${checked} declarations checked`);
}

main();
