/** Minimal ABI for the flows this service touches. Matches ../contracts. */
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
] as const;
