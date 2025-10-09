import {
  createPublicClient,
  createWalletClient,
  encodeFunctionData,
  http,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { identityAbi } from "./abi.js";
import { claimIdOf } from "./claim.js";

export interface IssueResult {
  identity: Address;
  txHash: Hex;
  claimId: Hex;
}

/**
 * Broadcast `Identity.addClaim(...)` from the issuer EOA. `Identity.addClaim`
 * authorizes the call when msg.sender == issuer, so the signing key doubles as
 * the submitting key. Requires the EOA to hold gas and the identity to exist.
 */
export async function addClaimOnIdentity(args: {
  rpcUrl: string;
  privateKey: Hex;
  identity: Address;
  topic: bigint;
  scheme: bigint;
  signature: Hex;
  data: Hex;
  uri: string;
}): Promise<IssueResult> {
  const account = privateKeyToAccount(args.privateKey);
  const transport = http(args.rpcUrl);
  const wallet = createWalletClient({ account, transport });
  const publicClient = createPublicClient({ transport });

  const calldata = encodeFunctionData({
    abi: identityAbi,
    functionName: "addClaim",
    args: [args.topic, args.scheme, account.address, args.signature, args.data, args.uri],
  });

  const txHash = await wallet.sendTransaction({ to: args.identity, data: calldata, chain: null });
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  if (receipt.status !== "success") {
    throw new Error(`addClaim reverted on-chain: ${txHash}`);
  }
  return { identity: args.identity, txHash, claimId: claimIdOf(account.address, args.topic) };
}
