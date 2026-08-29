import type { MockStorageContainer } from "@/app/experimental/collection-space/mock-data";

/**
 * Presença física de cada Storage Container mockado — Rodada UX-01.1
 * (materialidade/escala/composição, pedido de Fabrício, 2026-08-28).
 *
 * Substitui o tratamento "card com ícone" da Rodada UX-01 (aprovada
 * estruturalmente, reprovada visualmente: "ainda parecem cards/retângulos
 * em perspectiva"). Cada tipo agora é uma silhueta própria — proporção
 * real, camada de espessura (o objeto "tem lado"), luz/sombra dedicada —
 * reconhecível sem ler texto. Nome/contagem saíram do objeto e passaram a
 * viver na legenda do carrossel (`collection-space-view.tsx`): o objeto em
 * si só carrega material, não rótulo.
 *
 * Só CSS (gradientes, `clip-path`, `box-shadow`, `filter: drop-shadow`) —
 * nenhuma dependência nova, nenhum asset de imagem (por instrução
 * explícita desta rodada).
 */

export const CONTAINER_DIMENSIONS: Record<
  MockStorageContainer["type"],
  { widthRem: number; widthRemLg: number; aspect: number }
> = {
  // Proporção de um binder real visto de 3/4: mais alto que largo.
  binder: { widthRem: 10, widthRemLg: 15, aspect: 0.72 },
  // ETB: caixa quase cúbica, levemente mais larga que alta.
  etb: { widthRem: 11.5, widthRemLg: 15.5, aspect: 1.05 },
  // Storage box de gradação: caixa baixa e larga.
  "storage-box": { widthRem: 13.5, widthRemLg: 18, aspect: 1.55 },
  // Deck box: estojo estreito e alto.
  "deck-box": { widthRem: 6, widthRemLg: 8, aspect: 0.42 },
};

/** Mesmo matiz de --nav-gold/--primary (app/globals.css) — friso dourado como assinatura MMKYU nos objetos, não decoração aleatória. */
const GOLD = "40 70% 62%";

function baseGradient(hue: number) {
  return `linear-gradient(160deg, hsl(${hue} 42% 27%) 0%, hsl(${hue} 34% 15%) 55%, hsl(${hue} 46% 7%) 100%)`;
}

const RIM_SHADOW =
  "inset 0 1px 0 hsl(0 0% 100% / 0.14), inset 0 -1px 0 hsl(0 0% 0% / 0.45), inset 1px 0 0 hsl(0 0% 100% / 0.06), inset -1px 0 0 hsl(0 0% 0% / 0.35)";

const SHEEN = "linear-gradient(125deg, hsl(0 0% 100% / 0.16) 0%, transparent 32%)";

export function StorageContainerVisual({ container }: { container: MockStorageContainer }) {
  const { type, accentHue: hue } = container;

  if (type === "binder") return <BinderObject hue={hue} />;
  if (type === "deck-box") return <DeckBoxObject hue={hue} />;
  return <BoxObject hue={hue} variant={type} />;
}

function BinderObject({ hue }: { hue: number }) {
  const spinePct = 16;
  return (
    <div className="relative h-full w-full" style={{ filter: "drop-shadow(0 26px 34px rgba(0,0,0,0.55))" }}>
      {/* Bloco de páginas — espessura + textura de borda de papel, atrás da capa. */}
      <div
        className="absolute rounded-[10px]"
        style={{
          top: 5,
          left: `calc(${spinePct}% + 4px)`,
          right: -7,
          bottom: -9,
          backgroundImage: "repeating-linear-gradient(to bottom, hsl(40 22% 84%) 0px 2px, hsl(34 14% 66%) 2px 3px)",
        }}
        aria-hidden
      />
      {/* Capa — face principal. */}
      <div
        className="absolute rounded-[10px]"
        style={{
          top: 0,
          left: `${spinePct}%`,
          right: 0,
          bottom: 0,
          backgroundImage: `${SHEEN}, ${baseGradient(hue)}`,
          boxShadow: RIM_SHADOW,
        }}
        aria-hidden
      >
        {/* Placa debossada — único grafismo do objeto, sem nome/contagem. */}
        <div
          className="absolute left-[12%] top-[10%] h-[9%] w-[42%] rounded-sm"
          style={{ boxShadow: "inset 0 1.5px 3px rgba(0,0,0,0.55), inset 0 -1px 0 hsl(0 0% 100% / 0.06)" }}
        />
      </div>
      {/* Lombada — mecanismo de argolas sugerido por 3 marcas. */}
      <div
        className="absolute rounded-l-[10px]"
        style={{
          top: 0,
          bottom: 0,
          left: 0,
          width: `${spinePct}%`,
          background: `linear-gradient(90deg, hsl(${hue} 30% 9%), hsl(${hue} 34% 14%))`,
          boxShadow: "inset -2px 0 4px rgba(0,0,0,0.5)",
        }}
        aria-hidden
      >
        {[28, 50, 72].map((top) => (
          <span
            key={top}
            className="absolute left-1/2 h-[6%] w-[46%] -translate-x-1/2 rounded-full"
            style={{ top: `${top}%`, background: "hsl(0 0% 0% / 0.4)", boxShadow: "inset 0 1px 1px rgba(0,0,0,0.6)" }}
          />
        ))}
      </div>
    </div>
  );
}

function BoxObject({ hue, variant }: { hue: number; variant: "etb" | "storage-box" }) {
  const lidPct = variant === "etb" ? 24 : 16;
  return (
    <div className="relative h-full w-full" style={{ filter: "drop-shadow(0 24px 32px rgba(0,0,0,0.55))" }}>
      {/* Espessura — lateral/base em sombra, atrás da face frontal (o objeto "tem lado"). */}
      <div
        className="absolute rounded-md"
        style={{ top: 7, left: 7, right: -9, bottom: -10, background: `hsl(${hue} 28% 8%)` }}
        aria-hidden
      />
      {/* Face frontal. */}
      <div
        className="absolute overflow-hidden rounded-md"
        style={{ inset: 0, backgroundImage: `${SHEEN}, ${baseGradient(hue)}`, boxShadow: RIM_SHADOW }}
      >
        {/* Tampa — tom mais claro, separada por friso dourado (assinatura MMKYU). */}
        <div
          className="absolute inset-x-0 top-0"
          style={{
            height: `${lidPct}%`,
            background: `linear-gradient(180deg, hsl(${hue} 40% 32%), hsl(${hue} 36% 24%))`,
            borderBottom: `2px solid hsl(${GOLD} / 0.55)`,
          }}
        />
        {/* Frisos horizontais — sugerem estrutura de caixa de gradação/armazenamento. */}
        {variant === "storage-box" && (
          <div
            className="absolute inset-x-0 bottom-0"
            style={{
              top: `${lidPct}%`,
              opacity: 0.14,
              backgroundImage: "repeating-linear-gradient(to bottom, hsl(0 0% 100% / 0.6) 0 1px, transparent 1px 11px)",
            }}
          />
        )}
      </div>
    </div>
  );
}

function DeckBoxObject({ hue }: { hue: number }) {
  return (
    <div className="relative h-full w-full" style={{ filter: "drop-shadow(0 20px 26px rgba(0,0,0,0.55))" }}>
      <div
        className="absolute rounded-md"
        style={{ top: 5, left: 5, right: -6, bottom: -7, background: `hsl(${hue} 28% 8%)` }}
        aria-hidden
      />
      <div
        className="absolute overflow-hidden rounded-md"
        style={{ inset: 0, backgroundImage: `${SHEEN}, ${baseGradient(hue)}`, boxShadow: RIM_SHADOW }}
      >
        {/* Aba triangular do estojo — silhueta de friction-lid. */}
        <div
          className="absolute left-1/2 top-0 -translate-x-1/2"
          style={{
            width: "62%",
            height: "20%",
            clipPath: "polygon(50% 100%, 0 0, 100% 0)",
            background: `hsl(${hue} 44% 34%)`,
            borderBottom: `2px solid hsl(${GOLD} / 0.55)`,
          }}
        />
      </div>
    </div>
  );
}
