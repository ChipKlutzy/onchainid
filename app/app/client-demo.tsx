"use client";

import { useEffect, useState } from "react";
import { Providers } from "./providers";
import { Demo } from "./demo";

// wagmi/react-query only initialize in the browser. During SSR/prerender we
// render a static fallback so `next build` never executes wallet code on the
// server (avoids next/dynamic CSR-manifest flakes on incremental rebuilds).
export function ClientDemo() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  if (!mounted) return <p>Loading wallet demo…</p>;
  return (
    <Providers>
      <Demo />
    </Providers>
  );
}
