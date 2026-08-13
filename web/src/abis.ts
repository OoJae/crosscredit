import {parseAbi} from 'viem';

/**
 * Minimal ABI fragments for the functions and events the UI touches.
 *
 * Hand-written rather than imported from `contracts/out/`, so the web build has no dependency on
 * a Foundry artifact directory that is gitignored and absent on a clean checkout. The trade-off is
 * that these must be kept in step with the contracts; `contracts/test/LoanBook.t.sol` pins the
 * event signatures, and any change to them is already a cross-chain breaking change that demands
 * a coordinated update.
 */

export const registryAbi = parseAbi([
  // The credit profile, returned as a named struct rather than the flat tuple `profiles()` gives.
  'struct CreditProfile { uint256 totalRepaidWei; uint256 totalCollateralWei; uint32 onTime; uint32 late; uint32 loansOpened; uint32 loansClosed; uint64 firstSeen; uint16 score; }',
  'function profileOf(address borrower) view returns (CreditProfile)',
  'function scoreOf(address borrower) view returns (uint16)',
  'function tierOf(address borrower) view returns (uint8)',
  'function processedQueries(bytes32 queryId) view returns (bool)',
  'function MAX_BATCH_SIZE() view returns (uint256)',
  'function SOURCE_CHAIN_KEY() view returns (uint64)',
  'function LOANBOOK() view returns (address)',
  'function paused() view returns (bool)',

  // Batch verification — the whole-history import.
  'struct MerkleProofEntry { bytes32 hash; bool isLeft; }',
  'struct MerkleProof { bytes32 root; MerkleProofEntry[] siblings; }',
  'struct ContinuityProof { bytes32 lowerEndpointDigest; bytes32[] roots; }',
  'function executeBatch(uint8[] actions, uint64 chainKey, uint64[] heights, bytes[] encodedTransactions, MerkleProof[] merkleProofs, ContinuityProof sharedContinuityProof) returns (bool)',

  'event HistoryEventIngested(address indexed borrower, bytes32 indexed queryId, bytes32 eventSig, uint256 loanId)',
  'event ScoreUpdated(address indexed borrower, uint16 oldScore, uint16 newScore, uint8 tier)',
  'event LoanClosed(address indexed borrower, uint256 indexed loanId)',

  // Typed errors, so a failed simulation surfaces a real reason rather than a hex blob.
  'error WrongSourceChain(uint64 expected, uint64 received)',
  'error SourceTransactionFailed(uint8 receiptStatus)',
  'error UnsupportedTransactionType(uint8 txType)',
  'error NoRecognisedEvents()',
  'error UnknownAction(uint8 action)',
  'error EmptyBatch()',
  'error BatchTooLarge(uint256 size, uint256 maximum)',
  'error BatchLengthMismatch()',
  'error QueryAlreadyProcessed(bytes32 queryId)',
]);

export const sbtAbi = parseAbi([
  'function sync(address borrower) returns (uint256)',
  'function tokenOf(address borrower) view returns (uint256)',
  'function tierOfToken(uint256 tokenId) view returns (uint8)',
  'function tierOfBadge(address borrower) view returns (uint8)',
  'function tokenURI(uint256 tokenId) view returns (string)',
  'function locked(uint256 tokenId) view returns (bool)',
  'event TierSynced(address indexed borrower, uint256 indexed tokenId, uint8 previousTier, uint8 newTier)',
]);

export const poolAbi = parseAbi([
  'struct Terms { uint16 collateralRatioBps; uint16 aprBps; uint256 maxBorrow; }',
  'function quote(address borrower) view returns (uint8 tier, Terms terms)',
  'function termsFor(uint8 tier) view returns (uint16 collateralRatioBps, uint16 aprBps, uint256 maxBorrow)',
  'function collateralRequired(address borrower, uint256 amount) view returns (uint256)',
  'function loans(address borrower) view returns (uint256 principal, uint256 collateral, uint64 openedAt, uint8 tierAtOrigination, bool active)',
  'function totalOwed(address borrower) view returns (uint256)',
  'function interestDue(address borrower) view returns (uint256)',
  'function borrow(uint256 amount) payable',
  'function repay()',
  'function paused() view returns (bool)',
  'error LoanAlreadyOpen(address borrower)',
  'error NoActiveLoan(address borrower)',
  'error InsufficientCollateral(uint256 supplied, uint256 required)',
  'error ExceedsTierLimit(uint256 requested, uint256 maximum)',
  'error InsufficientLiquidity(uint256 requested, uint256 available)',
]);

export const loanBookAbi = parseAbi([
  'event LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate)',
  'event RepaymentMade(uint256 indexed loanId, address indexed borrower, uint256 amount, bool onTime, uint64 timestamp)',
  'event CollateralAdded(address indexed borrower, uint256 amount)',
]);

export const erc20Abi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)',
]);

/**
 * The precompile's batch `verify` view. Free to call, and it runs the same size, parity, inclusion
 * and continuity checks as the emit path — so it is a perfect pre-flight before asking anyone to
 * sign a million-gas transaction.
 */
export const blockProverAbi = parseAbi([
  'struct MerkleProofEntry { bytes32 hash; bool isLeft; }',
  'struct MerkleProof { bytes32 root; MerkleProofEntry[] siblings; }',
  'struct ContinuityProof { bytes32 lowerEndpointDigest; bytes32[] roots; }',
  'function verify(uint64 chainKey, uint64[] heights, bytes[] encodedTransactions, MerkleProof[] merkleProofs, ContinuityProof sharedContinuityProof) view returns (bool)',
]);

/** topic0 of each LoanBook event, so ingested history can be labelled without a second lookup. */
export const EVENT_SIGS = {
  '0x0d7f8e19afd65be70c0b9ff46dab1702a44ca0e8fcd33448375d7c2690e5866b': 'Loan opened',
  '0x7d64aa0e099ec7ce5a5e95941014b245cf86dd8cd1115dd1ee421d8ec4d04206': 'Repayment',
  '0x7dba1be544024070cd5eebfa8bdd80a8b198cea8058c7d3cc1f8dd36e41ab2f7': 'Collateral added',
} as const;
