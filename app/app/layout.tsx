import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "ONCHAINID Portfolio — Identity Explorer + Compliance Demo",
  description:
    "Connect wallet, deploy identity via IdFactory, issue KYC claim, register, verify, mint/transfer CompliantToken.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", margin: 0 }}>
        <main style={{ maxWidth: 900, margin: "0 auto", padding: 24 }}>
          <h1 style={{ fontSize: 24, marginBottom: 4 }}>
            ONCHAINID Portfolio — Identity Explorer + Compliance Demo
          </h1>
          <p style={{ color: "#555", marginTop: 0 }}>
            Anvil-first. Point <code>app/.env.local</code> at your{" "}
            <code>forge script</code> deployment (see README demo script).
          </p>
          {children}
        </main>
      </body>
    </html>
  );
}
