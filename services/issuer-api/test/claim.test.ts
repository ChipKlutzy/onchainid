import assert from "node:assert/strict";
import { test } from "node:test";
import { encodeAbiParameters, encodePacked, hashMessage, keccak256, parseAbiParameters, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  claimDigest,
  claimIdOf,
  ethSignedDigest,
  recoverClaimSigner,
  signClaim,
} from "../src/claim.js";
import { BadRequest, parseClaimBody, serializeClaim } from "../src/server.js";

// Ephemeral, unfunded test-only key. Sandbox use only; controls no assets.
const TEST_PK = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as Hex;
const account = privateKeyToAccount(TEST_PK);
const IDENTITY = "0x00000000000000000000000000000000000000A1" as Address;
const DATA = "0xabcd" as Hex;
const TOPIC = 1n;

test("claimDigest matches abi.encode(identity, topic, data)", () => {
  const expected = keccak256(
    encodeAbiParameters(parseAbiParameters("address, uint256, bytes"), [IDENTITY, TOPIC, DATA]),
  );
  assert.equal(claimDigest(IDENTITY, TOPIC, DATA), expected);
});

test("ethSignedDigest matches the contract's EIP-191 formula", () => {
  const digest = claimDigest(IDENTITY, TOPIC, DATA);
  const expected = keccak256(
    encodePacked(["string", "bytes32"], ["\x19Ethereum Signed Message:\n32", digest]),
  );
  assert.equal(ethSignedDigest(IDENTITY, TOPIC, DATA), expected);
  assert.equal(hashMessage({ raw: digest }), expected);
});

test("signed claim recovers to the issuer address", async () => {
  const claim = await signClaim(account, { identity: IDENTITY, topic: TOPIC, data: DATA });
  assert.equal(claim.issuer, account.address);
  assert.equal(claim.signature.length, 132); // 65 bytes hex
  const recovered = await recoverClaimSigner(IDENTITY, TOPIC, DATA, claim.signature);
  assert.equal(recovered.toLowerCase(), account.address.toLowerCase());
});

test("claimId equals keccak256(abi.encode(issuer, topic))", async () => {
  const claim = await signClaim(account, { identity: IDENTITY, topic: TOPIC, data: DATA });
  assert.equal(claim.claimId, claimIdOf(account.address, TOPIC));
});

test("tampered data does not recover to issuer", async () => {
  const claim = await signClaim(account, { identity: IDENTITY, topic: TOPIC, data: DATA });
  const recovered = await recoverClaimSigner(IDENTITY, TOPIC, "0xabce" as Hex, claim.signature);
  assert.notEqual(recovered.toLowerCase(), account.address.toLowerCase());
});

test("parseClaimBody validates identity and normalizes fields", () => {
  const parsed = parseClaimBody({ identity: IDENTITY, data: DATA }, TOPIC);
  assert.equal(parsed.identity, IDENTITY);
  assert.equal(parsed.topic, TOPIC);
  assert.equal(parsed.scheme, 1n);
  assert.equal(parsed.data, DATA);
});

test("parseClaimBody rejects bad identity and non-hex data", () => {
  assert.throws(() => parseClaimBody({ identity: "not-an-address" }, TOPIC), BadRequest);
  assert.throws(() => parseClaimBody({ identity: IDENTITY, data: "zzz" }, TOPIC), BadRequest);
});

test("serializeClaim stringifies bigints", async () => {
  const claim = await signClaim(account, { identity: IDENTITY, topic: TOPIC, data: DATA });
  const json = serializeClaim(claim);
  assert.equal(json.topic, "1");
  assert.equal(json.scheme, "1");
  assert.equal(typeof json.signature, "string");
});
