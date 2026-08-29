/**
 * Capa fechada do Binder — spike "Binder-First" (pedido de Fabrício,
 * 2026-08-28). Referência: fotos de binders físicos com zíper enviadas no
 * pedido — capa rígida/semi-rígida em PU/leather-like, zíper contornando 3
 * bordas (topo, direita, base — a esquerda é a lombada), costura aparente,
 * cantos arredondados, logo debossado central, lombada com dobra (Z-fold)
 * visível de lado. Só CSS (gradientes, `box-shadow`, `clip-path`/SVG inline,
 * borda tracejada deslocada) — nenhum asset de imagem, nenhuma dependência
 * nova.
 *
 * Exporta `LEATHER_HUE`/`GOLD`/`leatherSurface` para `binder-pages.tsx`
 * reaproveitar o mesmo material ao construir a "casca" de continuidade do
 * miolo (mesma identidade capa↔páginas — Rodada BINDER-VIS-02, ponto 2:
 * "no estado aberto, parte da capa/espessura externa deve continuar
 * perceptível").
 *
 * Escala aumentada na Rodada BINDER-VIS-02 (ponto 1: "o Binder fechado deve
 * ser o protagonista da viewport") — de `min(58vw, 300px)` para uma largura
 * que também respeita a altura disponível (`min(78vw, 58dvh)`), evitando
 * que o objeto estoure a viewport em telas baixas/paisagem.
 */

export const LEATHER_HUE = 26;
/** Mesmo matiz de --nav-gold/--primary (app/globals.css) — puxador e friso, não decoração aleatória. */
export const GOLD = "40 70% 62%";

const SPINE_PCT = 12;

export function leatherSurface(hue: number) {
  return [
    // Grão cruzado, opacidade muito baixa — textura de couro sem asset.
    "repeating-linear-gradient(115deg, hsl(0 0% 100% / 0.035) 0px, hsl(0 0% 100% / 0.035) 1px, transparent 1px, transparent 3px)",
    "repeating-linear-gradient(25deg, hsl(0 0% 0% / 0.06) 0px, hsl(0 0% 0% / 0.06) 1px, transparent 1px, transparent 4px)",
    "linear-gradient(125deg, hsl(0 0% 100% / 0.1) 0%, transparent 30%)",
    `linear-gradient(155deg, hsl(${hue} 34% 22%) 0%, hsl(${hue} 28% 13%) 55%, hsl(${hue} 38% 6%) 100%)`,
  ].join(", ");
}

function zipperTeeth(vertical: boolean) {
  const angle = vertical ? "180deg" : "90deg";
  return `repeating-linear-gradient(${angle}, hsl(38 24% 70%) 0px, hsl(38 24% 70%) 1.5px, hsl(30 12% 26%) 1.5px, hsl(30 12% 26%) 3px)`;
}

export function BinderCover({ viewTransitionName }: { viewTransitionName?: string }) {
  return (
    <div
      className="relative"
      style={{
        width: "clamp(240px, min(80vw, 58dvh), 480px)",
        aspectRatio: "0.72",
        viewTransitionName,
        filter: "drop-shadow(0 46px 50px rgba(0,0,0,0.6))",
      }}
    >
      {/* Lombada — dobra em Z sugerida por listras verticais finas, mais escura que a capa. */}
      <div
        className="absolute rounded-l-xl"
        style={{
          top: 3,
          bottom: -7,
          left: 0,
          width: `${SPINE_PCT}%`,
          backgroundImage: `repeating-linear-gradient(90deg, hsl(${LEATHER_HUE} 24% 9%) 0px, hsl(${LEATHER_HUE} 24% 9%) 3px, hsl(${LEATHER_HUE} 28% 14%) 3px, hsl(${LEATHER_HUE} 28% 14%) 4px)`,
          boxShadow: "inset -3px 0 6px rgba(0,0,0,0.55)",
        }}
        aria-hidden
      />
      {/* Espessura traseira (offset atrás-e-deslocada) — o objeto "tem lado", mesma técnica validada em UX-01.1. */}
      <div
        className="absolute rounded-xl"
        style={{ top: 5, left: `${SPINE_PCT}%`, right: -7, bottom: -9, background: `hsl(${LEATHER_HUE} 20% 5%)` }}
        aria-hidden
      />
      {/* Capa frontal. */}
      <div
        className="absolute overflow-hidden rounded-xl"
        style={{
          top: 0,
          left: `${SPINE_PCT}%`,
          right: 0,
          bottom: 0,
          backgroundImage: leatherSurface(LEATHER_HUE),
          boxShadow: [
            "inset 0 1px 0 hsl(0 0% 100% / 0.12)",
            "inset 0 -3px 8px hsl(0 0% 0% / 0.5)",
            "inset 1px 0 0 hsl(0 0% 100% / 0.05)",
          ].join(", "),
          border: "1px solid hsl(0 0% 0% / 0.4)",
        }}
      >
        {/* Costura — tracejado deslocado da borda real, contornando os 4 lados da capa. */}
        <div className="pointer-events-none absolute rounded-lg" style={{ inset: 9, border: "1.5px dashed hsl(38 30% 68% / 0.26)" }} aria-hidden />

        {/* Zíper — topo, direita e base (a esquerda é a lombada). */}
        <div
          className="pointer-events-none absolute inset-x-4 top-[7px] h-[3px] rounded-full"
          style={{ backgroundImage: zipperTeeth(false), boxShadow: "0 1px 1px rgba(0,0,0,0.5)" }}
          aria-hidden
        />
        <div
          className="pointer-events-none absolute inset-y-4 right-[6px] w-[3px] rounded-full"
          style={{ backgroundImage: zipperTeeth(true), boxShadow: "0 0 1px rgba(0,0,0,0.5)" }}
          aria-hidden
        />
        <div
          className="pointer-events-none absolute inset-x-4 bottom-[7px] h-[3px] rounded-full"
          style={{ backgroundImage: zipperTeeth(false), boxShadow: "0 -1px 1px rgba(0,0,0,0.5)" }}
          aria-hidden
        />
        {/* Puxador do zíper. */}
        <div
          className="absolute right-[2px] top-[9%] h-4 w-[10px] rounded-[2px]"
          style={{
            background: `linear-gradient(160deg, hsl(${GOLD}), hsl(40 50% 38%))`,
            boxShadow: "0 2px 3px rgba(0,0,0,0.5), inset 0 1px 0 hsl(0 0% 100% / 0.35)",
          }}
          aria-hidden
        />

        {/* Logo debossado — glifo simples, relevo pressionado via stroke escuro + highlight de 1px. */}
        <div className="absolute inset-0 flex items-center justify-center" aria-hidden>
          <svg width="32%" viewBox="0 0 48 48" fill="none">
            <path
              d="M24 4 L40 12 V26 C40 34 33 41 24 44 C15 41 8 34 8 26 V12 Z"
              fill={`hsl(${LEATHER_HUE} 24% 10%)`}
              stroke="hsl(0 0% 0% / 0.55)"
              strokeWidth="1"
            />
            <path
              d="M24 4 L40 12 V26 C40 34 33 41 24 44 C15 41 8 34 8 26 V12 Z"
              fill="none"
              stroke="hsl(0 0% 100% / 0.12)"
              strokeWidth="0.75"
              transform="translate(0.5 -0.5)"
            />
          </svg>
        </div>

        {/* Bolso frontal pequeno (porta-cartão) — detalhe visto na referência (binder teal). */}
        <div
          className="absolute rounded-[3px]"
          style={{
            right: "9%",
            bottom: "7%",
            width: "20%",
            aspectRatio: "0.7",
            background: "hsl(0 0% 0% / 0.3)",
            boxShadow: "inset 0 1px 2px rgba(0,0,0,0.6), inset 0 0 0 1px hsl(0 0% 100% / 0.07)",
          }}
          aria-hidden
        />
      </div>
    </div>
  );
}
