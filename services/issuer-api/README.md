# issuer-api — offchain ONCHAINID claim issuer

A tiny HTTP service that signs KYC (topic 1) claims so they validate against
`contracts/ClaimIssuer.sol`. The signature is an EIP-191 personal signature over
`keccak256(abi.encode(identity, topic, data))` — byte-for-byte what
`ClaimIssuer.ethSignedDigest` / `isClaimValid` expect.

## Run

```bash
cd services/issuer-api
npm install
cp .env.example .env       # set ISSUER_PRIVATE_KEY (throwaway local key)
npm run dev                # http://127.0.0.1:8787
```

Keys come from the environment only; the private key is never logged or
persisted, and `.env` is gitignored.

The dapp calls this API from the browser, so responses include CORS headers.
Set `ALLOWED_ORIGIN` to the dapp origin (default `http://localhost:3000`; use
`*` only for local demos). `OPTIONS` preflight returns `204`.

## Endpoints

`GET /health` → `{ ok, issuer, kycTopic, issueEnabled }`

`POST /v1/claims/sign`
```json
{ "identity": "0x…", "topic": 1, "data": "0xabcd", "uri": "ipfs://…" }
```
→ `{ identity, topic, scheme, data, uri, issuer, signature, digest, ethSignedDigest, claimId }`

`POST /v1/claims/issue` (requires `ISSUER_RPC_URL`) — signs, then broadcasts
`Identity.addClaim(topic, scheme, issuer, signature, data, uri)` from the signer
EOA (authorized because `msg.sender == issuer`) and returns `txHash`.

## Verify against the contract

The returned `signature` validates via
`ClaimIssuer.isClaimValid(identity, topic, data, signature)` when the contract's
`signer` is this service's `issuer` address. `IdentityRegistry` treats the
**ClaimIssuer contract** as the trusted issuer and re-checks the signature in
`isVerified`, so a claim must carry a genuine issuer signature to pass.

## Test

```bash
npm test          # node:test — digest/EIP-191 format, recovery, validation
npm run typecheck
```
