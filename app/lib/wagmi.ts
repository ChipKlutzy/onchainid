"use client";

import { http, createConfig } from "wagmi";
import { anvil, sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

const anvilRpc = process.env.NEXT_PUBLIC_ANVIL_RPC ?? "http://127.0.0.1:8545";
const sepoliaRpc = process.env.NEXT_PUBLIC_SEPOLIA_RPC;

export const wagmiConfig = createConfig({
  chains: sepoliaRpc ? [anvil, sepolia] : [anvil],
  connectors: [injected()],
  transports: {
    [anvil.id]: http(anvilRpc),
    [sepolia.id]: http(sepoliaRpc ?? "https://rpc.sepolia.org"),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
