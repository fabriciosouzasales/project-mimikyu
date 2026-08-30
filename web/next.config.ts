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
  // THREEUI-PROOF-01 (2026-08-29): o bundle compilado de @designcodeio/threeui
  // (ex.: lib-dist/shaders/gallery/Gallery.js) embute imagens como
  // `new URL("data:image/webp;base64,...")`. O webpack 5 detecta esse padrão
  // e tenta criar um asset module `asset/inline` automaticamente, mas herda
  // uma opção `filename` da configuração global de asset generator do
  // Next.js — que só é válida para `asset/resource`, não `asset/inline`.
  // Isso quebra o schema do Asset Modules Plugin (bug conhecido do webpack,
  // ver issues #15934/#16063). Como esses data: URIs já são o asset final
  // (não precisam de resolução de arquivo), desligamos o parsing automático
  // de `new URL()` como asset module só para os arquivos desse pacote —
  // não altera o comportamento de asset import do resto do projeto.
  webpack(config) {
    config.module.rules.push({
      test: /node_modules[\\/]@designcodeio[\\/]threeui[\\/].*\.js$/,
      parser: { url: false },
    });
    return config;
  },
};

export default nextConfig;
