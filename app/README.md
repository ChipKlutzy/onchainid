# ONCHAINID Portfolio Dapp (OPE-11)

Next.js (TS, app router) + wagmi/viem identity explorer + compliance demo.
Anvil-first; Sepolia via env. No secrets committed.

## Prereqs

- Node 20+, `anvil`, `forge`, a browser wallet (MetaMask / Rabby) or Anvil key import.
- Contracts P1–P3 already built (`forge build` green at repo root).
- **Issuer API running** (`services/issuer-api`) — the dapp requests KYC-claim
  signatures from it instead of signing in the browser. Set
  `NEXT_PUBLIC_ISSUER_API_URL` to its URL.

## 1. Start Anvil

```bash
anvil
```

## 2. Deploy contracts (repo root)

```bash
# P1+P2 — use a throwaway Anvil key (local test only, never real funds)
DEPLOYER_PRIVATE_KEY=0xYOUR_ANVIL_TEST_KEY \
INITIAL_CLAIM_SIGNER=<anvil-account-1-address> \
forge script scripts/Deploy.s.sol --rpc-url anvil --broadcast

# P3 (TRUSTED_ISSUER = ClaimIssuer.signer or the demo wallet; ALLOWED_COUNTRY e.g. 42)
DEPLOYER_PRIVATE_KEY=0xYOUR_ANVIL_TEST_KEY \
TRUSTED_ISSUER=<anvil-account-1-address> \
ALLOWED_COUNTRY=42 \
forge script scripts/DeployRWA.s.sol --rpc-url anvil --broadcast
```

Copy the printed addresses into `app/.env.local` (see `.env.example`):

```bash
cp app/.env.example app/.env.local
# edit NEXT_PUBLIC_ID_FACTORY / CLAIM_ISSUER / IDENTITY_REGISTRY / COMPLIANT_TOKEN / COMPLIANCE
# set NEXT_PUBLIC_ISSUER_API_URL to the running issuer-api (default http://127.0.0.1:8787)
```

> Issuer model: the offchain service (`services/issuer-api`) holds the signing
> key; its address is the `ClaimIssuer.signer`. Deploy with
> `INITIAL_CLAIM_SIGNER` = the API signer address (`GET /health` → `issuer`),
> and `TRUSTED_ISSUER` = the deployed **ClaimIssuer contract** address (the
> trusted issuer the IdentityRegistry verifies). The dapp requests a signature
> from the API and writes the claim with `issuer = ClaimIssuer`; `isVerified`
> re-checks the signature on-chain, so naming the issuer without a valid
> signature cannot pass. Keys live only in the service env and your shell —
> never in files.

## 3. Run the dapp

```bash
cd app
npm install
npm run dev    # http://localhost:3000
npm run build  # acceptance: must be green (script pins NODE_ENV=production;
               # the agent harness exports NODE_ENV=development, which breaks
               # Next prerender — do not remove the pin)
```

## 4. Click-through demo (happy path)

1. **Connect wallet** (Anvil demo key). Confirm section 0 shows all 5 contract addresses.
2. **Deploy identity** — section 1 → `createIdentity`. Note the predicted address
   auto-fills the identity field.
3. **Issue KYC claim** — section 2 → `Request signature from issuer API`, then
   `Identity.addClaim`. Badge flips to `VALID pass`.
4. **Register** — section 3 → `registerIdentity(wallet, identity, 42)`. Badge flips
   to `isVerified PASS`.
5. **Mint/transfer** — section 4 → `mint(to=self)`, then transfer to a second
   verified wallet. Balance updates; log shows confirmations.
6. **Fail demo** — transfer to an unverified address: tx reverts with
   `ReceiverNotVerified` (FAIL in the log). Freeze or switch to a
   non-allowlisted country for `TransferBlockedByCompliance`.

## Sepolia via env

```bash
# Deploy (requires board approval + SecurityEngineer review gate per epic)
forge script scripts/Deploy.s.sol --rpc-url sepolia --broadcast --verify
forge script scripts/DeployRWA.s.sol --rpc-url sepolia --broadcast --verify
# Then in app/.env.local: set NEXT_PUBLIC_SEPOLIA_RPC + Sepolia addresses, restart.
```

Never commit `.env.local` or keys.
