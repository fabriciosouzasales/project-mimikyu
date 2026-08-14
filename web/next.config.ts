import type { NextConfig } from "next";

// Fundação do frontend (Etapa 0) — Project Mimikyu.
// Nenhuma configuração experimental é ativada sem necessidade comprovada (AP-004/AP-006).
const nextConfig: NextConfig = {
  reactStrictMode: true,

  // Workaround de bundler (2026-08-14) — ver `docs/log.md` para o incidente
  // completo. O bundle Edge do middleware falha em produção na Vercel com
  // `ReferenceError: __dirname is not defined`, originado dentro do próprio
  // `next/server` (barrel eager de `userAgent` → `next/dist/compiled/ua-parser-js`,
  // que referencia `__dirname` só como metadado de asset-base do ncc, nunca
  // lido em runtime por essa lib). Causa confirmada como estrutural ao
  // pacote `next` (vercel/next.js#53968), não corrigida em nenhuma versão
  // 15.x — upgrade de versão descartado como fix; substituição estática de
  // `__dirname` restrita à compilação Edge é a correção mínima.
  webpack: (config, { nextRuntime, webpack }) => {
    if (nextRuntime === "edge") {
      config.plugins.push(
        new webpack.DefinePlugin({
          __dirname: JSON.stringify(""),
        }),
      );
    }
    return config;
  },
};

export default nextConfig;
