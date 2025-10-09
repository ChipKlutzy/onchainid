import { isHex } from "viem";
import { createServer, type IssuerConfig } from "./server.js";

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required env var ${name}`);
  return value;
}

function loadConfig(): IssuerConfig {
  const privateKey = requiredEnv("ISSUER_PRIVATE_KEY");
  if (!isHex(privateKey) || privateKey.length !== 66) {
    throw new Error("ISSUER_PRIVATE_KEY must be a 32-byte hex private key (0x + 64 hex chars)");
  }
  return {
    privateKey,
    kycTopic: BigInt(process.env.KYC_TOPIC ?? "1"),
    rpcUrl: process.env.ISSUER_RPC_URL,
    port: Number(process.env.PORT ?? "8787"),
    allowedOrigin: process.env.ALLOWED_ORIGIN ?? "*",
  };
}

const config = loadConfig();

// The key is intentionally never logged.
createServer(config).listen(config.port, () => {
  console.log(`[issuer-api] listening on http://127.0.0.1:${config.port} (KYC topic ${config.kycTopic})`);
});
