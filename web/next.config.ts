import type { NextConfig } from "next";

// Fundação do frontend (Etapa 0) — Project Mimikyu.
// Nenhuma configuração experimental é ativada sem necessidade comprovada (AP-004/AP-006).
const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Convergência Pendências -> Mapeamentos de Cartas (2026-08-27): a tela
  // foi aposentada e absorvida por /pricing/mapeamentos-cartas. Redirect
  // temporário (307, não permanent) por decisão explícita de Fabrício —
  // promover a 308 depois de confirmado que nada mais depende do link antigo.
  async redirects() {
    return [
      {
        source: "/pricing/pendencias",
        destination: "/pricing/mapeamentos-cartas",
        permanent: false,
      },
    ];
  },
};

export default nextConfig;
