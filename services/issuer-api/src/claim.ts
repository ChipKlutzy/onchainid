import {
  encodeAbiParameters,
  hashMessage,
  keccak256,
  parseAbiParameters,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount, type PrivateKeyAccount } from "viem/accounts";

/** Topic 1 = KYC/AML, per the ONCHAINID convention used by the contracts. */
export const KYC_TOPIC = 1n;

const CLAIM_ABI_PARAMS = parseAbiParameters("address, uint256, bytes");
const CLAIM_ID_PARAMS = parseAbiParameters("address, uint256");

export interface SignedClaim {
  identity: Address;
  topic: bigint;
  scheme: bigint;
  data: Hex;
  uri: string;
  issuer: Address;
  signature: Hex;
  /** keccak256(abi.encode(identity, topic, data)) */
  digest: Hex;
  /** EIP-191 prefixed digest actually signed (matches ClaimIssuer.ethSignedDigest) */
  ethSignedDigest: Hex;
  /** keccak256(abi.encode(issuer, topic)) */
  claimId: Hex;
}

/** keccak256(abi.encode(identity, topic, data)) — matches ClaimIssuer.claimDigest. */
export function claimDigest(identity: Address, topic: bigint, data: Hex): Hex {
  return keccak256(encodeAbiParameters(CLAIM_ABI_PARAMS, [identity, topic, data]));
}

/** EIP-191 personal-message hash of the claim digest — ClaimIssuer.ethSignedDigest. */
export function ethSignedDigest(identity: Address, topic: bigint, data: Hex): Hex {
  return hashMessage({ raw: claimDigest(identity, topic, data) });
}

/** keccak256(abi.encode(issuer, topic)) — matches Identity.sol claimId. */
export function claimIdOf(issuer: Address, topic: bigint): Hex {
  return keccak256(encodeAbiParameters(CLAIM_ID_PARAMS, [issuer, topic]));
}

/**
 * Sign a claim with the issuer account. The signature is an EIP-191 personal
 * signature over the 32-byte claim digest, so it validates against
 * `ClaimIssuer.isClaimValid(identity, topic, data, signature)`.
 */
export async function signClaim(
  account: PrivateKeyAccount,
  input: { identity: Address; topic: bigint; data: Hex; scheme?: bigint; uri?: string },
): Promise<SignedClaim> {
  const { identity, topic, data } = input;
  const digest = claimDigest(identity, topic, data);
  const signature = await account.signMessage({ message: { raw: digest } });
  return {
    identity,
    topic,
    scheme: input.scheme ?? 1n,
    data,
    uri: input.uri ?? "",
    issuer: account.address,
    signature,
    digest,
    ethSignedDigest: hashMessage({ raw: digest }),
    claimId: claimIdOf(account.address, topic),
  };
}

/** Build an issuer account from a hex private key (never logged or persisted). */
export function accountFromKey(privateKey: Hex): PrivateKeyAccount {
  return privateKeyToAccount(privateKey);
}

/** Recover the signer of an EIP-191 signature over a claim digest. */
export async function recoverClaimSigner(
  identity: Address,
  topic: bigint,
  data: Hex,
  signature: Hex,
): Promise<Address> {
  const { recoverMessageAddress } = await import("viem");
  return recoverMessageAddress({ message: { raw: claimDigest(identity, topic, data) }, signature });
}
