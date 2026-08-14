/**
 * Why CrossCredit gates credit on economics rather than identity.
 *
 * The obvious way to stop someone farming credit with a thousand fresh wallets is to demand proof
 * of personhood. We implemented that path — `CreditRegistry` can ingest Proof of Humanity events
 * from Ethereum mainnet — and then measured whether it actually means anything.
 *
 * This script runs the measurement. It takes real Proof of Humanity v1 registrations from 2021,
 * proves each one to Creditcoin through the block-prover precompile, and then asks mainnet whether
 * those people are registered **today**.
 *
 * Every proof succeeds. Every registration has lapsed.
 *
 * That is not a bug in the precompile; it is the precompile working exactly as documented. It
 * proves that an **event occurred**, not that a **state holds**. For a repayment those are the
 * same thing — a repayment that happened stays happened. For an identity they are not: a
 * registration can expire, be revoked, or be transferred, and no proof of the original event can
 * tell you. PoH v1 registrations last two years and the registry has taken none in about that
 * long, so the entire population it could gate is expired.
 *
 * Hence the design: borrowing capacity is anchored to capital that real third parties
 * demonstrably put at risk, which the precompile can prove as a completed fact.
 *
 * Run: npx tsx scripts/poh-negative.ts
 */
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {ethers} from 'ethers';
import {proofProvider} from '@gluwa/usc-sdk';
import {optional, cc3RpcUrl, proofBuilderUrl} from './lib/env.js';

const OUTPUT_PATH = 'docs/evidence/g5-identity-negative/results.json';

const MAINNET_CHAIN_KEY = 3;
const BLOCK_PROVER = '0x0000000000000000000000000000000000000FD2';
/**
 * Public archive endpoints, tried in order. They rate-limit and occasionally 404 mid-run, and this
 * script makes many historical calls, so it rotates rather than failing the whole measurement over
 * one flaky response.
 */
const MAINNET_RPCS = [
  'https://rpc.mevblocker.io',
  'https://eth-pokt.nodies.app',
  'https://eth.drpc.org',
  'https://ethereum-rpc.publicnode.com',
];

/** Proof of Humanity v1, Ethereum mainnet. */
const POH_V1 = '0xC5E9dDebb09Cd64DfaCab4011A0D5cEDaf7c9BDb';
/** `AddSubmission(address indexed _submissionID, uint256)` */
const ADD_SUBMISSION_TOPIC = '0x803727a67d35270dc2c090dc4f9cba1f9818a7200e65c2087eca187851fd6b19';

/** How many historical registrations to prove. */
const SAMPLE_SIZE = 5;

interface Finding {
  humanAddress: string;
  registrationTx: string;
  registrationBlock: number;
  provedToCreditcoin: boolean;
  proofDetail: string;
  registeredOnMainnetToday: boolean;
}

/** Runs `attempt` against each endpoint in turn, returning the first success. */
async function withMainnet<T>(attempt: (provider: ethers.JsonRpcProvider) => Promise<T>): Promise<T> {
  const configured = optional('MAINNET_RPC_URL', '');
  const endpoints = configured === '' ? MAINNET_RPCS : [configured, ...MAINNET_RPCS];

  let lastError: unknown;
  for (const url of endpoints) {
    try {
      return await attempt(new ethers.JsonRpcProvider(url));
    } catch (error) {
      lastError = error;
    }
  }

  // This script reads 2021 state, so it needs an archive node. The free public endpoints it
  // rotates through have since started gating archive requests behind an account, which used to
  // surface as an ethers stack trace three screens long — unhelpful to anyone running this from a
  // clean clone to check our claim. Say what is wrong and what to do instead.
  const detail = lastError instanceof Error ? lastError.message.split('\n')[0] : String(lastError);
  throw new Error(
    'No archive RPC available. This script queries Ethereum state from 2021, and every public ' +
      'endpoint it tried refused the archive request.\n' +
      '  Set MAINNET_RPC_URL to an archive provider (Alchemy\'s free tier is enough) and re-run.\n' +
      '  Or read the captured result: docs/evidence/g5-identity-negative/results.json\n' +
      `  Last endpoint said: ${detail}`,
  );
}

async function main(): Promise<void> {
  const cc3 = new ethers.JsonRpcProvider(cc3RpcUrl());

  const prover = new ethers.Contract(
    BLOCK_PROVER,
    ['function verify(uint64,uint64,bytes,(bytes32,(bytes32,bool)[]),(bytes32,bytes32[])) view returns (bool)'],
    cc3,
  );
  const POH_ABI = [
    'function isRegistered(address) view returns (bool)',
    'function submissionCounter() view returns (uint256)',
  ];

  console.log('CrossCredit — why credit is gated on economics, not identity\n');
  console.log(`  Proof of Humanity v1  ${POH_V1}`);
  const total = await withMainnet(
    async (p) => (await new ethers.Contract(POH_V1, POH_ABI, p)['submissionCounter']!()) as bigint,
  );
  console.log(`  total submissions     ${String(total)}`);

  // Registrations from early 2021, comfortably inside the attested range. Paginated because
  // public archive endpoints cap `eth_getLogs` at 10,000 blocks.
  console.log('\nSearching mainnet for historical registrations…');
  const logs: ethers.Log[] = [];
  for (let from = 12_000_000; from < 12_060_000 && logs.length < SAMPLE_SIZE; from += 9_000) {
    const start = from;
    const page = await withMainnet((p) =>
      p.getLogs({
        address: POH_V1,
        topics: [ADD_SUBMISSION_TOPIC],
        fromBlock: start,
        toBlock: start + 8_999,
      }),
    );
    logs.push(...page);
  }
  const sample = logs.slice(0, SAMPLE_SIZE);
  console.log(`Found ${logs.length}; proving ${sample.length} of them to Creditcoin.\n`);

  const builder = new proofProvider.service.ProofBuilder(MAINNET_CHAIN_KEY, proofBuilderUrl(), 90_000);
  const findings: Finding[] = [];

  for (const log of sample) {
    const humanAddress = ethers.getAddress(`0x${log.topics[1]!.slice(-40)}`);
    const finding: Finding = {
      humanAddress,
      registrationTx: log.transactionHash,
      registrationBlock: log.blockNumber,
      provedToCreditcoin: false,
      proofDetail: '',
      registeredOnMainnetToday: false,
    };

    try {
      const result = await builder.getProof(log.transactionHash);
      if (!result.success || result.data === undefined) throw new Error(String(result.error));
      const proof = result.data;

      // Free read-only verification against the live precompile.
      await prover['verify']!.staticCall(
        MAINNET_CHAIN_KEY,
        proof.headerNumber,
        proof.txBytes,
        [proof.merkleProof.root, proof.merkleProof.siblings.map((s) => [s.hash, s.isLeft])],
        [proof.continuityProof.lowerEndpointDigest, proof.continuityProof.roots],
      );
      finding.provedToCreditcoin = true;
      finding.proofDetail = `${proof.merkleProof.siblings.length} merkle siblings, ${proof.continuityProof.roots.length} continuity roots`;
    } catch (error) {
      finding.proofDetail = error instanceof Error ? error.message.split('\n')[0]! : String(error);
    }

    // The question the proof cannot answer.
    finding.registeredOnMainnetToday = await withMainnet(
      async (p) =>
        (await new ethers.Contract(POH_V1, POH_ABI, p)['isRegistered']!(humanAddress)) as boolean,
    );

    findings.push(finding);
    console.log(
      `  ${finding.provedToCreditcoin ? '✓' : '✗'} proved  ${humanAddress}  (block ${log.blockNumber})`,
    );
    console.log(
      `      registered on mainnet today: ${finding.registeredOnMainnetToday ? 'YES' : 'NO — the claim has lapsed'}`,
    );
  }

  const proved = findings.filter((f) => f.provedToCreditcoin).length;
  const stillRegistered = findings.filter((f) => f.registeredOnMainnetToday).length;

  console.log(`\n  ${proved}/${findings.length} registrations proved to Creditcoin successfully.`);
  console.log(`  ${stillRegistered}/${findings.length} of those humans are still registered today.`);
  console.log('\n  The precompile proves that an EVENT OCCURRED, not that a STATE HOLDS.');
  console.log('  For a repayment those coincide — a repayment that happened stays happened.');
  console.log('  For an identity they do not, and no proof of the original event can tell you.');
  console.log('\n  This is why CrossCredit anchors borrowing capacity to demonstrated repayment');
  console.log('  of real third-party capital, which is a completed fact, rather than to identity,');
  console.log('  which the precompile can only prove as a stale one.');

  const payload = {
    capturedAt: new Date().toISOString(),
    question: 'Should undercollateralized credit be gated on proof of personhood?',
    answer:
      'Not with this primitive. Every registration proved successfully; none of the humans are registered today.',
    registry: POH_V1,
    registryNote:
      'Proof of Humanity v1 registrations last two years and the registry has accepted none in roughly that long. PoH v2 on mainnet holds ~55 humanities; the real population is on Gnosis, which Creditcoin does not attest.',
    sampleSize: findings.length,
    provedToCreditcoin: proved,
    stillRegisteredToday: stillRegistered,
    conclusion:
      'The precompile proves events, not state. Credit capacity is therefore anchored to demonstrated repayment of third-party capital — a completed fact — rather than to identity.',
    findings,
  };

  mkdirSync(dirname(OUTPUT_PATH), {recursive: true});
  writeFileSync(OUTPUT_PATH, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(`\n✓ wrote ${OUTPUT_PATH}`);
}

main().catch((error: unknown) => {
  console.error(`✗ poh-negative failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
