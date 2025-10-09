import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import type { Server } from "node:http";
import { createServer } from "../src/server.js";

// Ephemeral, unfunded test-only key. Sandbox use only; controls no assets.
const TEST_PK = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const ORIGIN = "http://localhost:3000";

let server: Server;
let base = "";

before(async () => {
  server = createServer({
    privateKey: TEST_PK,
    kycTopic: 1n,
    port: 0,
    allowedOrigin: ORIGIN,
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", () => resolve()));
  const addr = server.address();
  const port = typeof addr === "object" && addr ? addr.port : 0;
  base = `http://127.0.0.1:${port}`;
});

after(() => {
  server.close();
});

test("OPTIONS preflight returns 204 with CORS headers", async () => {
  const res = await fetch(`${base}/v1/claims/sign`, { method: "OPTIONS" });
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("access-control-allow-origin"), ORIGIN);
  assert.match(res.headers.get("access-control-allow-methods") ?? "", /POST/);
  assert.match(res.headers.get("access-control-allow-headers") ?? "", /content-type/);
});

test("POST /v1/claims/sign returns CORS header + signature", async () => {
  const res = await fetch(`${base}/v1/claims/sign`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      identity: "0x00000000000000000000000000000000000000A1",
      data: "0xabcd",
    }),
  });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("access-control-allow-origin"), ORIGIN);
  const json = (await res.json()) as Record<string, unknown>;
  assert.equal(json.topic, "1");
  assert.match(String(json.signature), /^0x[0-9a-f]+$/);
  assert.match(String(json.issuer), /^0x[0-9a-fA-F]{40}$/);
});

test("GET /health reports issueEnabled=false without rpc", async () => {
  const res = await fetch(`${base}/health`);
  const json = (await res.json()) as Record<string, unknown>;
  assert.equal(json.ok, true);
  assert.equal(json.kycTopic, "1");
  assert.equal(json.issueEnabled, false);
});
