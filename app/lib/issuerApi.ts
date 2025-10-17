import type { Hex } from "viem";

export const ISSUER_API_URL = process.env.NEXT_PUBLIC_ISSUER_API_URL ?? "";
export const issuerApiConfigured = ISSUER_API_URL.length > 0;

export interface IssuerApiClaim {
  identity: string;
  topic: string;
  scheme: string;
  data: string;
  uri: string;
  issuer: `0x${string}`;
  signature: Hex;
  digest: Hex;
  ethSignedDigest: Hex;
  claimId: Hex;
}

export interface SignClaimInput {
  identity: `0x${string}`;
  topic: bigint;
  data: Hex;
  uri?: string;
}

/**
 * Ask the offchain issuer service (services/issuer-api) to sign a KYC claim.
 * The returned signature validates against ClaimIssuer.isClaimValid when the
 * on-chain ClaimIssuer.signer is the returned `issuer` address.
 */
export async function requestClaimSignature(input: SignClaimInput): Promise<IssuerApiClaim> {
  if (!issuerApiConfigured) {
    throw new Error("NEXT_PUBLIC_ISSUER_API_URL is not set");
  }
  const base = ISSUER_API_URL.replace(/\/$/, "");
  const res = await fetch(`${base}/v1/claims/sign`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      identity: input.identity,
      topic: input.topic.toString(),
      data: input.data,
      uri: input.uri ?? "",
    }),
  });
  const json: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    const detail =
      json && typeof json === "object" && "error" in json
        ? String((json as { error: unknown }).error)
        : `HTTP ${res.status}`;
    throw new Error(`issuer-api: ${detail}`);
  }
  return json as IssuerApiClaim;
}
