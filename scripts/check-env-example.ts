/**
 * Guard: .env.example must ship the CURRENT deployed addresses.
 *
 * This block has gone stale after a redeploy twice — first pointing at the Phase 3
 * single-source contracts, then at the pre-flash-loan-guard generation, which is *paused*.
 * Both times a fresh clone silently ran `negative-paths` and the app against a registry the
 * documentation no longer describes. The failure is invisible locally because everyone with a
 * working checkout has a real `.env`; only judges get the example.
 *
 * deployments.json is the single source of truth; this diffs the example against it.
 */
import {readFileSync} from 'node:fs';

const deployments = JSON.parse(readFileSync('deployments.json', 'utf8')) as {
  networks: Record<string, {contracts: Record<string, {address: string}>}>;
};

const sepolia = deployments.networks['ethereum-sepolia']!.contracts;
const cc3 = deployments.networks['creditcoin-cc3-testnet']!.contracts;

const expected: Record<string, string> = {
  LOANBOOK_ADDRESS: sepolia['LoanBook']!.address,
  CREDIT_REGISTRY_ADDRESS: cc3['CreditRegistry']!.address,
  TIER_SBT_ADDRESS: cc3['CreditTierSBT']!.address,
  LENDING_POOL_ADDRESS: cc3['LendingPool']!.address,
  TUSD_ADDRESS: cc3['TUSD']!.address,
};

const example = readFileSync('.env.example', 'utf8');
const failures: string[] = [];

for (const [key, want] of Object.entries(expected)) {
  const match = example.match(new RegExp(`^${key}=(0x[0-9a-fA-F]{40})$`, 'm'));
  if (!match) {
    failures.push(`${key}: missing from .env.example (expected ${want})`);
  } else if (match[1]!.toLowerCase() !== want.toLowerCase()) {
    failures.push(`${key}: .env.example has ${match[1]}, deployments.json says ${want}`);
  }
}

if (failures.length > 0) {
  console.error('✗ .env.example is stale against deployments.json:');
  for (const f of failures) console.error(`    ${f}`);
  console.error('  A fresh clone would run against the wrong (possibly paused) contracts.');
  process.exit(1);
}

console.log(`✓ .env.example matches deployments.json — ${Object.keys(expected).length} addresses checked`);
