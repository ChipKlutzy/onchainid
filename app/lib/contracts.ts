import { getAddress } from "viem";

/** Contract addresses — fill from `forge script` output or Anvil deploy. See README demo script. */
export function envAddr(key: string): `0x${string}` | undefined {
  const v = process.env[key];
  if (!v) return undefined;
  try {
    return getAddress(v);
  } catch {
    return undefined;
  }
}

type Addr = `0x${string}` | undefined;

export const ADDRESSES = {
  idFactory: envAddr("NEXT_PUBLIC_ID_FACTORY") as Addr,
  claimIssuer: envAddr("NEXT_PUBLIC_CLAIM_ISSUER") as Addr,
  identityRegistry: envAddr("NEXT_PUBLIC_IDENTITY_REGISTRY") as Addr,
  compliantToken: envAddr("NEXT_PUBLIC_COMPLIANT_TOKEN") as Addr,
  compliance: envAddr("NEXT_PUBLIC_COMPLIANCE") as Addr,
};

export const KYC_TOPIC_DEFAULT = BigInt(
  process.env.NEXT_PUBLIC_KYC_TOPIC ?? "1",
);

/** Minimal ABIs matching the Foundry contracts in ../contracts. */
export const idFactoryAbi = [
  {
    type: "function",
    name: "createIdentity",
    stateMutability: "nonpayable",
    inputs: [
      { name: "salt", type: "bytes32" },
      { name: "managementKey", type: "bytes" },
    ],
    outputs: [{ name: "identity", type: "address" }],
  },
  {
    type: "function",
    name: "computeAddress",
    stateMutability: "view",
    inputs: [
      { name: "salt", type: "bytes32" },
      { name: "managementKey", type: "bytes" },
    ],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "event",
    name: "IdentityDeployed",
    inputs: [
      { name: "identity", type: "address", indexed: true },
      { name: "salt", type: "bytes32", indexed: true },
      { name: "managementKey", type: "address", indexed: true },
    ],
  },
] as const;

export const identityAbi = [
  {
    type: "function",
    name: "addClaim",
    stateMutability: "nonpayable",
    inputs: [
      { name: "topic", type: "uint256" },
      { name: "scheme", type: "uint256" },
      { name: "issuer", type: "address" },
      { name: "signature", type: "bytes" },
      { name: "data", type: "bytes" },
      { name: "uri", type: "string" },
    ],
    outputs: [{ name: "claimId", type: "bytes32" }],
  },
  {
    type: "function",
    name: "getClaimIds",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bytes32[]" }],
  },
  {
    type: "function",
    name: "verifyClaim",
    stateMutability: "view",
    inputs: [{ name: "claimId", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

export const claimIssuerAbi = [
  {
    type: "function",
    name: "signer",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "isClaimValid",
    stateMutability: "view",
    inputs: [
      { name: "identity", type: "address" },
      { name: "topic", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "signature", type: "bytes" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

export const identityRegistryAbi = [
  {
    type: "function",
    name: "registerIdentity",
    stateMutability: "nonpayable",
    inputs: [
      { name: "wallet", type: "address" },
      { name: "identity", type: "address" },
      { name: "country", type: "uint16" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "isVerified",
    stateMutability: "view",
    inputs: [{ name: "wallet", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "identity",
    stateMutability: "view",
    inputs: [{ name: "wallet", type: "address" }],
    outputs: [{ name: "", type: "address" }],
  },
] as const;

export const compliantTokenAbi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "transfer",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export const complianceAbi = [
  {
    type: "function",
    name: "canTransfer",
    stateMutability: "view",
    inputs: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;
