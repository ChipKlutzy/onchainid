import { createServer as createHttpServer, type IncomingMessage, type ServerResponse } from "node:http";
import { isAddress, isHex, getAddress, type Address, type Hex } from "viem";
import { accountFromKey, signClaim, type SignedClaim } from "./claim.js";
import { addClaimOnIdentity } from "./issue.js";

export interface IssuerConfig {
  privateKey: Hex;
  kycTopic: bigint;
  /** When set, enables POST /v1/claims/issue (broadcasts addClaim). */
  rpcUrl?: string;
  port: number;
  /** CORS origin allowed to call this API (dapp origin, or "*" for local demo). */
  allowedOrigin: string;
}

interface ClaimRequestBody {
  identity?: string;
  topic?: string | number;
  scheme?: string | number;
  data?: string;
  uri?: string;
}

function toBigInt(value: string | number | undefined, fallback: bigint): bigint {
  if (value === undefined) return fallback;
  return BigInt(value);
}

/** Pure parse+validate of an inbound claim request. Throws Error with a 400 message. */
export function parseClaimBody(body: ClaimRequestBody, defaultTopic: bigint) {
  if (!body.identity || !isAddress(body.identity)) {
    throw new BadRequest("identity must be a valid EVM address");
  }
  const data = (body.data ?? "0x") as Hex;
  if (!isHex(data)) throw new BadRequest("data must be hex (e.g. 0xabcd)");
  const topic = toBigInt(body.topic, defaultTopic);
  const scheme = toBigInt(body.scheme, 1n);
  return {
    identity: getAddress(body.identity) as Address,
    topic,
    scheme,
    data,
    uri: body.uri ?? "",
  };
}

export class BadRequest extends Error {}

/** Serialize a SignedClaim for JSON (bigints -> strings). */
export function serializeClaim(claim: SignedClaim) {
  return {
    identity: claim.identity,
    topic: claim.topic.toString(),
    scheme: claim.scheme.toString(),
    data: claim.data,
    uri: claim.uri,
    issuer: claim.issuer,
    signature: claim.signature,
    digest: claim.digest,
    ethSignedDigest: claim.ethSignedDigest,
    claimId: claim.claimId,
  };
}

async function readJson(req: IncomingMessage): Promise<ClaimRequestBody> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  if (chunks.length === 0) return {};
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw) as ClaimRequestBody;
  } catch {
    throw new BadRequest("body must be valid JSON");
  }
}

function send(res: ServerResponse, status: number, payload: unknown) {
  const body = JSON.stringify(payload);
  res.writeHead(status, { "content-type": "application/json" });
  res.end(body);
}

export function createServer(config: IssuerConfig) {
  const account = accountFromKey(config.privateKey);

  return createHttpServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    res.setHeader("access-control-allow-origin", config.allowedOrigin);
    res.setHeader("access-control-allow-methods", "GET,POST,OPTIONS");
    res.setHeader("access-control-allow-headers", "content-type");
    res.setHeader("vary", "origin");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    try {
      if (req.method === "GET" && url.pathname === "/health") {
        return send(res, 200, {
          ok: true,
          issuer: account.address,
          kycTopic: config.kycTopic.toString(),
          issueEnabled: Boolean(config.rpcUrl),
        });
      }

      if (req.method === "POST" && url.pathname === "/v1/claims/sign") {
        const parsed = parseClaimBody(await readJson(req), config.kycTopic);
        const claim = await signClaim(account, parsed);
        return send(res, 200, serializeClaim(claim));
      }

      if (req.method === "POST" && url.pathname === "/v1/claims/issue") {
        if (!config.rpcUrl) {
          return send(res, 409, { error: "ISSUER_RPC_URL is not configured" });
        }
        const parsed = parseClaimBody(await readJson(req), config.kycTopic);
        const claim = await signClaim(account, parsed);
        const result = await addClaimOnIdentity({
          rpcUrl: config.rpcUrl,
          privateKey: config.privateKey,
          identity: claim.identity,
          topic: claim.topic,
          scheme: claim.scheme,
          signature: claim.signature,
          data: claim.data,
          uri: claim.uri,
        });
        return send(res, 200, { ...serializeClaim(claim), txHash: result.txHash });
      }

      return send(res, 404, { error: "not found" });
    } catch (error) {
      if (error instanceof BadRequest) return send(res, 400, { error: error.message });
      const message = error instanceof Error ? error.message : String(error);
      return send(res, 500, { error: message });
    }
  });
}
