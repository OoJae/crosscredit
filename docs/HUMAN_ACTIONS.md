# Human actions checklist (operator)

Things only you can do. Ordered by urgency — **1–3 are the critical path for Gate G0.**

## Demo wallet

Test-only wallet, generated Aug 13 2026 with `cast wallet new`:

```
0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6
```

Private key lives in `.env` (`DEPLOYER_PRIVATE_KEY`) only. `.env` is gitignored.
**This key was printed to a terminal — it is permanently test-only. Never send real funds to it.**

---

## 1. tCTC faucet (CC3 testnet gas) — DAILY

- [ ] Join the Creditcoin Discord: <https://discord.gg/Gu43zTfmtc>
- [ ] Go to the `token-faucet` channel
- [ ] Run: `/faucet address:0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6`
- [ ] Bot replies "CTC faucet submitted" → then "CTC Faucet successful" in a thread

✅ **Done — funded with 10,000 tCTC.** Worth topping up occasionally as insurance, but no longer
urgent: the "100 tCTC ≈ 9 queries" line in Gluwa's README is stale. A real bridge transaction
measures ~393k gas at 0.5 gwei ≈ **0.0002 CTC**, so the current balance covers effectively
unlimited iteration.

## 2. Sepolia ETH (source-chain gas)

- [ ] Google Cloud faucet: <https://cloud.google.com/application/web3/faucet/ethereum/sepolia>
- [ ] or Alchemy: <https://www.alchemy.com/faucets/ethereum-sepolia> (needs free account)
- [ ] or pk910 PoW faucet (no account, just mines in-browser): <https://sepolia-faucet.pk910.de>
- [ ] Target: **≥ 0.1 SepoliaETH** — we need enough for LoanBook deploy + ~10 seeded loan events

## 3. Sepolia RPC key

- [ ] Free account at Alchemy or Infura → create an Ethereum **Sepolia** app
- [ ] Copy the HTTPS URL and give it to me → goes in `.env` as `SEPOLIA_RPC_URL`

Public Sepolia RPCs rate-limit hard during the 10-event seeding script, which would make the
batch-verification demo flaky. Worth the two minutes.

## 4. Hackathon registration

- [ ] Register: <https://dorahacks.io/hackathon/buidl-ctc-2026-fall/detail>
      (note: the URL in our original notes was wrong — this is the real one)
- [ ] Screenshot the submission form fields → drop into `docs/evidence/`
- [ ] Ask in `#buidl-ctc-qna`: the page prose says the deadline is **Sep 6, 23:59 ET** but the
      platform countdown is configured to **Sep 6, 04:59 UTC (00:59 ET)** — a ~23h gap.
      Get it reconciled. We target **Sep 4** internally regardless.

## 5. Kickoff AMA — Aug 18, 07:00 ET

- [ ] Register: <https://luma.com/buidlctc-fall26-ama> — **registration is subject to host
      approval, so do this early**
- [ ] Question to ask (visibility with judges + resolves a real unknown):
      *"For batch `verifyAndEmit` — the docs give MAX_BATCH_SIZE 10 within a MAX_BATCH_RANGE of
      1000 blocks. The SDK's block_prover ABI also exposes a batch `verify` view variant; is that
      live on CC3 testnet, or is `verifyAndEmit` the only supported batch path?"*

## 6. MetaMask networks (needed by Phase 4, optional now)

- [ ] Creditcoin CC3 Testnet — RPC `https://rpc.cc3-testnet.creditcoin.network`,
      chainId **102031**, symbol tCTC, explorer `https://creditcoin-testnet.blockscout.com`
- [ ] Ethereum Sepolia — chainId 11155111 (built into MetaMask)

---

## Where the build stops without you

Everything in Track A (scaffold, ground-truth lock, toolchain, `check-chains.ts`, vendoring,
GitHub push) runs without any funding. **Gate G0 — the hello-bridge proof round-trip — is hard
blocked** until `cast balance` shows a non-zero balance on *both* Sepolia and CC3. Phase 1
(LoanBook TDD against local mocks) can also proceed unfunded if faucets stay dry.
