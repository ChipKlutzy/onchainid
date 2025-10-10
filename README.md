# ONCHAINID Portfolio — Ethereum / ERC-3643

A self-contained portfolio track built on the ONCHAINID model (ERC-734 key
management + ERC-735 claims) and a minimal ERC-3643 permissioned-token stack.

## Contents

| Area | Path | What it is |
|---|---|---|
| Identity core | `contracts/Identity.sol` | ERC-734 keys + ERC-735 claims |
| Factory | `contracts/IdFactory.sol` | Deterministic CREATE2 identity deploy |
| Claim issuer | `contracts/ClaimIssuer.sol` | Signed KYC claims (EIP-191), rotation |
| Compliance | `contracts/compliance/` | Claim topics, trusted issuers, registry, `isVerified` (verifies claim signatures on-chain), modular rules |
| Token | `contracts/token/CompliantToken.sol` | ERC-20 whose transfers require verification + compliance |
| Tests | `tests/` | Foundry test suite (42 tests, incl. TS↔Solidity cross-check) |
| Deploy | `scripts/` | `Deploy.s.sol` (P1+P2), `DeployRWA.s.sol` (P3) |
| Issuer API | `services/issuer-api/` | Offchain signer: issues KYC claims matching `ClaimIssuer` |
| Dapp | `app/` | Next.js + wagmi/viem explorer (`app/README.md`) |

## Build & test

```bash
forge build
forge test          # 42 tests
```

Deploy scripts read keys from the environment (`DEPLOYER_PRIVATE_KEY`,
`INITIAL_CLAIM_SIGNER`, `TRUSTED_ISSUER`, `ALLOWED_COUNTRY`). No key material is
stored in this repo; use throwaway local keys for Anvil and never commit a real
key or a `.env` file.

## Local demo

```bash
anvil &
# deploy contracts, then:
cd app && npm install && npm run dev
```

See `app/README.md` for the full click-through demo (identity → claim → verify →
mint → gated transfer).

> Sepolia deployment is intentionally gated behind review; do not broadcast
> without explicit approval.
