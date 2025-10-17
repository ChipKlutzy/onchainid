"use client";

import { useMemo, useState } from "react";
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import {
  encodeAbiParameters,
  encodePacked,
  keccak256,
  parseEther,
  zeroAddress,
  type Hex,
} from "viem";
import {
  ADDRESSES,
  KYC_TOPIC_DEFAULT,
  claimIssuerAbi,
  complianceAbi,
  compliantTokenAbi,
  idFactoryAbi,
  identityAbi,
  identityRegistryAbi,
} from "../lib/contracts";
import {
  ISSUER_API_URL,
  issuerApiConfigured,
  requestClaimSignature,
} from "../lib/issuerApi";

function Badge({ ok, label }: { ok: boolean | null; label: string }) {
  const bg = ok === null ? "#555" : ok ? "#137333" : "#a50e0e";
  return (
    <span
      style={{
        background: bg,
        color: "#fff",
        borderRadius: 999,
        padding: "2px 10px",
        fontSize: 12,
        fontWeight: 700,
      }}
    >
      {label}
    </span>
  );
}

function Section(props: { n: string; title: string; children: React.ReactNode }) {
  return (
    <section
      style={{
        border: "1px solid #ddd",
        borderRadius: 12,
        padding: 16,
        marginTop: 16,
      }}
    >
      <h2 style={{ margin: "0 0 8px", fontSize: 18 }}>
        {props.n}. {props.title}
      </h2>
      {props.children}
    </section>
  );
}

export function Demo() {
  const { address, isConnected, chain } = useAccount();
  const { connect, connectors, isPending: connectPending } = useConnect();
  const { disconnect } = useDisconnect();

  const [salt, setSalt] = useState<Hex>(
    "0x0000000000000000000000000000000000000000000000000000000000000001",
  );
  const [identity, setIdentity] = useState<`0x${string}` | "">("");
  const [country, setCountry] = useState("42");
  const [claimData, setClaimData] = useState<Hex>("0xabcd");
  const [signature, setSignature] = useState<Hex | "">("");
  const [apiIssuer, setApiIssuer] = useState<`0x${string}` | "">("");
  const [requesting, setRequesting] = useState(false);
  const [transferTo, setTransferTo] = useState("");
  const [amount, setAmount] = useState("100");
  const [log, setLog] = useState<string[]>([]);

  const push = (m: string) => setLog((l) => [...l.slice(-19), m]);

  const managementKey = useMemo(
    () =>
      address
        ? encodeAbiParameters([{ type: "address" }], [address])
        : ("0x" as Hex),
    [address],
  );

  const { data: predicted } = useReadContract({
    address: ADDRESSES.idFactory,
    abi: idFactoryAbi,
    functionName: "computeAddress",
    args:
      ADDRESSES.idFactory && address
        ? [salt, managementKey]
        : undefined,
    query: { enabled: Boolean(ADDRESSES.idFactory && address) },
  });

  const { data: issuerSigner } = useReadContract({
    address: ADDRESSES.claimIssuer,
    abi: claimIssuerAbi,
    functionName: "signer",
    query: { enabled: Boolean(ADDRESSES.claimIssuer) },
  });

  const walletAddr = (address ?? zeroAddress) as `0x${string}`;
  const identityAddr = (identity || predicted || zeroAddress) as `0x${string}`;

  const { data: verified } = useReadContract({
    address: ADDRESSES.identityRegistry,
    abi: identityRegistryAbi,
    functionName: "isVerified",
    args: address ? [walletAddr] : undefined,
    query: {
      enabled: Boolean(ADDRESSES.identityRegistry && address),
      refetchInterval: 5000,
    },
  });

  const { data: claimValid } = useReadContract({
    address: ADDRESSES.claimIssuer,
    abi: claimIssuerAbi,
    functionName: "isClaimValid",
    args:
      ADDRESSES.claimIssuer && identityAddr !== zeroAddress && signature
        ? [identityAddr, KYC_TOPIC_DEFAULT, claimData, signature as Hex]
        : undefined,
    query: {
      enabled: Boolean(
        ADDRESSES.claimIssuer &&
          identityAddr !== zeroAddress &&
          signature,
      ),
    },
  });

  const { data: balance } = useReadContract({
    address: ADDRESSES.compliantToken,
    abi: compliantTokenAbi,
    functionName: "balanceOf",
    args: address ? [walletAddr] : undefined,
    query: {
      enabled: Boolean(ADDRESSES.compliantToken && address),
      refetchInterval: 5000,
    },
  });

  const { data: gateOk } = useReadContract({
    address: ADDRESSES.compliance,
    abi: complianceAbi,
    functionName: "canTransfer",
    args: address ? [zeroAddress, walletAddr] : undefined,
    query: {
      enabled: Boolean(ADDRESSES.compliance && address),
      refetchInterval: 5000,
    },
  });

  const write = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: write.data });

  const need = (v: string | undefined, name: string) => {
    if (!v) {
      push(`MISSING ${name} — set it in app/.env.local (see README).`);
      return false;
    }
    return true;
  };

  async function deployIdentity() {
    if (!need(ADDRESSES.idFactory, "NEXT_PUBLIC_ID_FACTORY")) return;
    if (!address) return push("Connect a wallet first.");
    try {
      const h = await write.writeContractAsync({
        address: ADDRESSES.idFactory!,
        abi: idFactoryAbi,
        functionName: "createIdentity",
        args: [salt, managementKey],
      });
      push(`createIdentity sent: ${h}`);
      if (predicted && predicted !== zeroAddress) setIdentity(predicted);
    } catch (e) {
      push(`createIdentity FAILED: ${(e as Error).message.slice(0, 300)}`);
    }
  }

  /** Request a KYC-claim signature from the offchain issuer service
   *  (services/issuer-api) instead of signing in the browser. The service holds
   *  the issuer key; the browser only receives the public signature. */
  async function requestSignature() {
    if (!issuerApiConfigured)
      return push("Set NEXT_PUBLIC_ISSUER_API_URL in app/.env.local (see .env.example).");
    const target = identityAddr;
    if (!target || target === zeroAddress)
      return push("Deploy/predict an identity first.");
    setRequesting(true);
    try {
      const claim = await requestClaimSignature({
        identity: target,
        topic: KYC_TOPIC_DEFAULT,
        data: claimData,
      });
      setSignature(claim.signature);
      setApiIssuer(claim.issuer);
      push(`Issuer API signed KYC claim for ${target} (signer ${claim.issuer}).`);
      if (issuerSigner && claim.issuer.toLowerCase() !== issuerSigner.toLowerCase())
        push(
          `NOTE: API issuer ≠ ClaimIssuer.signer (${issuerSigner}); isClaimValid will FAIL. Deploy with INITIAL_CLAIM_SIGNER = API issuer.`,
        );
    } catch (e) {
      push(`issuer API FAILED: ${(e as Error).message.slice(0, 300)}`);
    } finally {
      setRequesting(false);
    }
  }

  async function addClaimOnIdentity() {
    if (!need(identityAddr, "identity")) return;
    if (!signature) return push("Request a signature first (step 2).");
    // The claim's issuer is the ClaimIssuer contract (the trusted issuer the
    // IdentityRegistry verifies against), not the API signer address.
    const issuerArg = ADDRESSES.claimIssuer;
    if (!issuerArg) return push("MISSING NEXT_PUBLIC_CLAIM_ISSUER (see .env.example).");
    try {
      const h = await write.writeContractAsync({
        address: identityAddr,
        abi: identityAbi,
        functionName: "addClaim",
        args: [
          KYC_TOPIC_DEFAULT,
          BigInt(1),
          issuerArg,
          signature as Hex,
          claimData,
          "",
        ],
      });
      push(`Identity.addClaim sent (issuer ${issuerArg}): ${h}`);
    } catch (e) {
      push(`addClaim FAILED: ${(e as Error).message.slice(0, 300)}`);
    }
  }

  async function register() {
    if (!need(ADDRESSES.identityRegistry, "NEXT_PUBLIC_IDENTITY_REGISTRY"))
      return;
    if (!address) return;
    try {
      const h = await write.writeContractAsync({
        address: ADDRESSES.identityRegistry!,
        abi: identityRegistryAbi,
        functionName: "registerIdentity",
        args: [walletAddr, identityAddr, Number(country)],
      });
      push(`registerIdentity sent: ${h}`);
    } catch (e) {
      push(`registerIdentity FAILED: ${(e as Error).message.slice(0, 300)}`);
    }
  }

  async function mint() {
    if (!need(ADDRESSES.compliantToken, "NEXT_PUBLIC_COMPLIANT_TOKEN")) return;
    if (!address) return;
    try {
      const h = await write.writeContractAsync({
        address: ADDRESSES.compliantToken!,
        abi: compliantTokenAbi,
        functionName: "mint",
        args: [walletAddr, parseEther(amount || "0")],
      });
      push(`mint sent: ${h}`);
    } catch (e) {
      push(`mint FAILED (expected until verified): ${(e as Error).message.slice(0, 300)}`);
    }
  }

  async function transfer() {
    if (!need(ADDRESSES.compliantToken, "NEXT_PUBLIC_COMPLIANT_TOKEN")) return;
    if (!transferTo) return push("Enter a recipient address.");
    try {
      const h = await write.writeContractAsync({
        address: ADDRESSES.compliantToken!,
        abi: compliantTokenAbi,
        functionName: "transfer",
        args: [transferTo as `0x${string}`, parseEther(amount || "0")],
      });
      push(`transfer sent: ${h}`);
    } catch (e) {
      push(`transfer FAILED: ${(e as Error).message.slice(0, 300)}`);
    }
  }

  const claimIdPreview = useMemo(() => {
    const issuer = ADDRESSES.claimIssuer;
    if (!issuer || identityAddr === zeroAddress) return "";
    try {
      return keccak256(
        encodePacked(
          ["bytes", "bytes"],
          [
            encodeAbiParameters([{ type: "address" }], [issuer]),
            encodeAbiParameters([{ type: "uint256" }], [KYC_TOPIC_DEFAULT]),
          ],
        ),
      );
    } catch {
      return "";
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identityAddr]);

  return (
    <div>
      <Section n="0" title="Connect wallet">
        {isConnected ? (
          <div>
            <div>
              Connected <code>{address}</code> on chain{" "}
              <code>{chain?.id}</code>
            </div>
            <button onClick={() => disconnect()}>Disconnect</button>
          </div>
        ) : (
          <div>
            {connectors.map((c) => (
              <button
                key={c.uid}
                disabled={connectPending}
                onClick={() => connect({ connector: c })}
                style={{ marginRight: 8 }}
              >
                Connect {c.name}
              </button>
            ))}
          </div>
        )}
        <div style={{ marginTop: 8, fontSize: 13 }}>
          <div>IdFactory: <code>{ADDRESSES.idFactory ?? "— unset —"}</code></div>
          <div>ClaimIssuer: <code>{ADDRESSES.claimIssuer ?? "— unset —"}</code> (signer: <code>{issuerSigner ?? "…"}</code>)</div>
          <div>IdentityRegistry: <code>{ADDRESSES.identityRegistry ?? "— unset —"}</code></div>
          <div>CompliantToken: <code>{ADDRESSES.compliantToken ?? "— unset —"}</code></div>
          <div>Compliance: <code>{ADDRESSES.compliance ?? "— unset —"}</code></div>
          <div>Issuer API: <code>{ISSUER_API_URL || "— unset —"}</code></div>
        </div>
      </Section>

      <Section n="1" title="Deploy identity via IdFactory">
        <label>
          Salt (bytes32):{" "}
          <input
            value={salt}
            onChange={(e) => setSalt(e.target.value as Hex)}
            style={{ width: 420 }}
          />
        </label>
        <div style={{ marginTop: 8 }}>
          <button onClick={deployIdentity} disabled={write.isPending}>
            createIdentity
          </button>
          <span style={{ marginLeft: 12 }}>
            Predicted: <code>{predicted ?? "…"}</code>
          </span>
        </div>
        <label style={{ display: "block", marginTop: 8 }}>
          Identity address (auto-filled from prediction, editable):{" "}
          <input
            value={identity}
            placeholder={typeof predicted === "string" ? predicted : ""}
            onChange={(e) => setIdentity(e.target.value as `0x${string}`)}
            style={{ width: 420 }}
          />
        </label>
      </Section>

      <Section n="2" title="Issue KYC claim via issuer API">
        <div>
          Claim data (hex):{" "}
          <input
            value={claimData}
            onChange={(e) => setClaimData(e.target.value as Hex)}
            style={{ width: 200 }}
          />
        </div>
        <div style={{ marginTop: 8 }}>
          <button onClick={requestSignature} disabled={requesting}>
            Request signature from issuer API
          </button>
          <span style={{ marginLeft: 12 }}>
            <Badge ok={claimValid ?? null} label={claimValid ? "VALID pass" : claimValid === false ? "VALID fail" : "not checked"} />
          </span>
        </div>
        <div style={{ marginTop: 8, fontSize: 13 }}>
          <div>Issuer API: <code>{ISSUER_API_URL || "— unset —"}</code></div>
          <div>API signer: <code>{apiIssuer || "—"}</code></div>
          <div>Claim issuer (contract): <code>{ADDRESSES.claimIssuer ?? "— unset —"}</code></div>
          <div>Signature: <code style={{ wordBreak: "break-all" }}>{signature || "—"}</code></div>
          <div>claimId preview (issuer, topic): <code>{claimIdPreview || "—"}</code></div>
        </div>
        <div style={{ marginTop: 8 }}>
          <button onClick={addClaimOnIdentity} disabled={write.isPending}>
            Identity.addClaim (as manager)
          </button>
        </div>
      </Section>

      <Section n="3" title="Register in IdentityRegistry">
        <label>
          Country (uint16):{" "}
          <input
            value={country}
            onChange={(e) => setCountry(e.target.value)}
            style={{ width: 80 }}
          />
        </label>
        <div style={{ marginTop: 8 }}>
          <button onClick={register} disabled={write.isPending}>
            registerIdentity(wallet, identity, country)
          </button>
          <span style={{ marginLeft: 12 }}>
            <Badge ok={verified ?? null} label={verified ? "isVerified PASS" : verified === false ? "isVerified FAIL" : "not checked"} />
          </span>
        </div>
      </Section>

      <Section n="4" title="Mint / transfer CompliantToken">
        <div>
          Balance: <code>{balance?.toString() ?? "…"}</code> · compliance canTransfer(0→you):{" "}
          <Badge ok={gateOk ?? null} label={gateOk ? "PASS" : gateOk === false ? "FAIL" : "—"} />
        </div>
        <label>
          Amount (ether):{" "}
          <input value={amount} onChange={(e) => setAmount(e.target.value)} style={{ width: 100 }} />
        </label>
        <div style={{ marginTop: 8 }}>
          <button onClick={mint} disabled={write.isPending}>mint(to=self)</button>
        </div>
        <label style={{ display: "block", marginTop: 8 }}>
          Transfer to:{" "}
          <input value={transferTo} onChange={(e) => setTransferTo(e.target.value)} style={{ width: 420 }} placeholder="0x…" />
        </label>
        <div style={{ marginTop: 8 }}>
          <button onClick={transfer} disabled={write.isPending}>transfer</button>
        </div>
        <p style={{ fontSize: 13 }}>
          Unverified recipients revert <code>ReceiverNotVerified</code>; frozen /
          non-allowlisted recipients revert <code>TransferBlockedByCompliance</code> —
          both surface as FAIL in the log below.
        </p>
      </Section>

      <Section n="5" title="Activity log">
        <div>Last tx: <code>{write.data ?? "—"}</code> · status: <code>{receipt.isLoading ? "confirming…" : receipt.isSuccess ? "confirmed" : write.error ? "error" : "idle"}</code></div>
        {write.error && (
          <div style={{ color: "#a50e0e", fontSize: 13 }}>
            {(write.error as Error).message.slice(0, 500)}
          </div>
        )}
        <pre
          style={{
            background: "#111",
            color: "#eee",
            padding: 12,
            borderRadius: 8,
            maxHeight: 240,
            overflow: "auto",
            fontSize: 12,
          }}
        >
          {log.length ? log.join("\n") : "— no activity yet —"}
        </pre>
      </Section>
    </div>
  );
}
