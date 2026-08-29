/**
 * Carta mock original — spike "Binder-First", Rodada BINDER-VIS-02 (pedido
 * de Fabrício, 2026-08-28: "remova os blocos de cor, use um pequeno
 * conjunto de imagens de cartas/mock assets realistas"). Criaturas e nomes
 * são inteiramente inventados (sem qualquer semelhança com Pokémon ou outra
 * IP de terceiros) — o objetivo é só testar como uma carta com layout real
 * (moldura, nome, HP, arte, ataque, selo de raridade) se comporta dentro de
 * um bolso, não avaliar arte de produto real. SVG inline, sem asset
 * externo, sem dependência nova.
 */

export interface MockCardData {
  id: string;
  name: string;
  hp: number;
  hue: number;
  attack: string;
  damage: number;
  rarity: "N" | "RH" | "H";
  energy: "flame" | "drop" | "leaf" | "bolt" | "stone" | "wing";
}

function EnergyGlyph({ energy, hue }: { energy: MockCardData["energy"]; hue: number }) {
  const fill = `hsl(${hue} 70% 88%)`;
  switch (energy) {
    case "flame":
      return <path d="M50 30 C56 42 44 46 50 58 C40 54 38 42 50 30 Z" fill={fill} />;
    case "drop":
      return <path d="M50 30 C60 44 60 56 50 60 C40 56 40 44 50 30 Z" fill={fill} />;
    case "leaf":
      return <path d="M34 50 C34 36 66 36 66 50 C66 60 34 60 34 50 Z" fill={fill} />;
    case "bolt":
      return <path d="M54 28 L40 54 L48 54 L44 72 L62 46 L52 46 Z" fill={fill} />;
    case "stone":
      return <circle cx="50" cy="50" r="16" fill={fill} />;
    case "wing":
      return <path d="M28 54 C40 34 60 34 72 54 C58 50 42 50 28 54 Z" fill={fill} />;
  }
}

/**
 * Face de uma carta mock, proporção 5:7 (mesma do bolso). `holo` adiciona um
 * véu de foil diagonal multicolor (mix-blend-mode) — só efeito visual, sem
 * imagem real.
 */
export function MockCardFace({ card }: { card: MockCardData }) {
  const { name, hp, hue, attack, damage, rarity, energy } = card;
  return (
    <svg viewBox="0 0 100 140" className="h-full w-full" style={{ display: "block" }} role="img" aria-label={`${name}, carta mock`}>
      <defs>
        <linearGradient id={`art-${card.id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor={`hsl(${hue} 60% 58%)`} />
          <stop offset="100%" stopColor={`hsl(${hue} 55% 32%)`} />
        </linearGradient>
        {rarity !== "N" && (
          <linearGradient id={`holo-${card.id}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="hsla(280,90%,70%,0.35)" />
            <stop offset="35%" stopColor="hsla(190,90%,65%,0.28)" />
            <stop offset="65%" stopColor="hsla(50,90%,65%,0.3)" />
            <stop offset="100%" stopColor="hsla(330,90%,65%,0.32)" />
          </linearGradient>
        )}
      </defs>

      {/* Moldura colorida. */}
      <rect x="1" y="1" width="98" height="138" rx="6" fill={`hsl(${hue} 55% 34%)`} />
      {/* Miolo (cartolina). */}
      <rect x="5" y="5" width="90" height="130" rx="4" fill="hsl(40 28% 94%)" />

      {/* Barra de nome. */}
      <rect x="5" y="5" width="90" height="14" rx="4" fill={`hsl(${hue} 45% 52%)`} />
      <rect x="5" y="13" width="90" height="6" fill={`hsl(${hue} 45% 52%)`} />
      <text x="10" y="15" fontFamily="Arial, sans-serif" fontSize="7" fontWeight="700" fill="hsl(0 0% 100% / 0.95)">
        {name}
      </text>
      <text x="90" y="15" fontFamily="Arial, sans-serif" fontSize="6.5" fontWeight="700" fill="hsl(0 0% 100% / 0.9)" textAnchor="end">
        HP {hp}
      </text>

      {/* Ícone de energia. */}
      <circle cx="13" cy="27" r="8" fill={`hsl(${hue} 60% 40%)`} stroke="hsl(0 0% 100% / 0.4)" strokeWidth="0.6" />
      <g transform="translate(-37 -23)">
        <EnergyGlyph energy={energy} hue={hue} />
      </g>

      {/* Área de arte — silhueta abstrata, não figurativa. */}
      <rect x="8" y="22" width="84" height="66" rx="3" fill={`url(#art-${card.id})`} />
      <ellipse cx="50" cy="58" rx="24" ry="18" fill="hsl(0 0% 100% / 0.16)" />
      <circle cx="42" cy="53" r="3.2" fill="hsl(0 0% 8% / 0.55)" />
      <circle cx="58" cy="53" r="3.2" fill="hsl(0 0% 8% / 0.55)" />

      {/* Tarja de ataque. */}
      <rect x="8" y="92" width="84" height="16" rx="2" fill="hsl(40 20% 88%)" />
      <text x="12" y="102.5" fontFamily="Arial, sans-serif" fontSize="6" fontWeight="600" fill="hsl(30 30% 20%)">
        {attack}
      </text>
      <text x="88" y="102.5" fontFamily="Arial, sans-serif" fontSize="6.5" fontWeight="700" fill="hsl(30 30% 20%)" textAnchor="end">
        {damage}
      </text>

      {/* Linhas de texto de regra (placeholder, não palavras reais). */}
      <rect x="8" y="111" width="76" height="2.2" rx="1" fill="hsl(30 15% 70%)" />
      <rect x="8" y="116" width="60" height="2.2" rx="1" fill="hsl(30 15% 78%)" />

      {/* Rodapé — número/selo genérico. */}
      <text x="10" y="132" fontFamily="Arial, sans-serif" fontSize="5" fill="hsl(30 15% 45%)">
        {card.id.slice(0, 3).toUpperCase()} · 01/60
      </text>

      {/* Selo de raridade (N/RH/H) — mesmo padrão de badge das referências. */}
      <circle cx="90" cy="125" r="7" fill="hsl(0 0% 12% / 0.85)" stroke="hsl(0 0% 100% / 0.3)" strokeWidth="0.6" />
      <text x="90" y="127.5" fontFamily="Arial, sans-serif" fontSize="5.5" fontWeight="700" fill="hsl(0 0% 100% / 0.9)" textAnchor="middle">
        {rarity}
      </text>

      {/* Véu holo — só nas raridades RH/H. */}
      {rarity !== "N" && (
        <rect x="1" y="1" width="98" height="138" rx="6" fill={`url(#holo-${card.id})`} style={{ mixBlendMode: "overlay" }} />
      )}
    </svg>
  );
}
