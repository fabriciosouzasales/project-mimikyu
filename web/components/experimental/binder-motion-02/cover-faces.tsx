import { GOLD, LEATHER_HUE, leatherSurface } from "@/components/experimental/binder-spike/binder-cover";

/**
 * Faces da capa do BINDER-MOTION-02 — reaproveitam os tokens de material já
 * validados em `binder-cover.tsx` (`leatherSurface`/`GOLD`/`LEATHER_HUE`),
 * mas dimensionadas para preencher o palco inteiro (largura das duas
 * páginas juntas), não o formato estreito do objeto fechado do
 * Binder-First. Isso é deliberado: o palco do miolo permanece
 * espacialmente estável do início ao fim (zero redimensionamento/translação
 * — só a capa gira sobre ele), o que é o ponto central desta rodada
 * ("o Binder deve permanecer percebido como um único objeto"). A capa
 * fechada aqui não é uma cópia 1:1 do objeto fechado do Binder-First — é a
 * mesma linguagem de material (couro/zíper/logo) composta na proporção do
 * palco aberto.
 */

export function CoverFaceFront() {
  return (
    <div
      className="relative h-full w-full overflow-hidden rounded-[22px]"
      style={{
        backgroundImage: leatherSurface(LEATHER_HUE),
        boxShadow: ["inset 0 1px 0 hsl(0 0% 100% / 0.12)", "inset 0 -3px 10px hsl(0 0% 0% / 0.5)"].join(", "),
        border: "1px solid hsl(0 0% 0% / 0.4)",
      }}
    >
      <div
        className="pointer-events-none absolute rounded-[18px]"
        style={{ inset: 14, border: "1.5px dashed hsl(38 30% 68% / 0.24)" }}
        aria-hidden
      />
      <div className="absolute inset-0 flex items-center justify-center" aria-hidden>
        <svg width="12%" viewBox="0 0 48 48" fill="none">
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
      <div
        className="absolute right-[1.2%] top-[6%] h-5 w-[9px] rounded-[2px]"
        style={{
          background: `linear-gradient(160deg, hsl(${GOLD}), hsl(40 50% 38%))`,
          boxShadow: "0 2px 3px rgba(0,0,0,0.5), inset 0 1px 0 hsl(0 0% 100% / 0.35)",
        }}
        aria-hidden
      />
    </div>
  );
}

export function CoverFaceBack() {
  return (
    <div
      className="relative h-full w-full overflow-hidden rounded-[22px]"
      style={{
        backgroundImage: leatherSurface(LEATHER_HUE + 4),
        boxShadow: "inset 0 0 40px rgba(0,0,0,0.5)",
        border: "1px solid hsl(0 0% 0% / 0.35)",
      }}
    >
      <div
        className="pointer-events-none absolute inset-[6%] rounded-[14px]"
        style={{ border: `1px solid hsl(${GOLD} / 0.15)`, boxShadow: "inset 0 0 24px rgba(0,0,0,0.35)" }}
        aria-hidden
      />
    </div>
  );
}
