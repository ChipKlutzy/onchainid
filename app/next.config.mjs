/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Demo dapp is run via `next start`, not a traced standalone container.
  // Works around a Next 14 collect-build-traces ENOENT on .nft.json entries.
  outputFileTracing: false,
};

export default nextConfig;
