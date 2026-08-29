import type { BinderSlotData } from "@/app/experimental/binder-spike/mock-data";
import { MockCardFace } from "./mock-card-face";

/**
 * Bolso individual do miolo do Binder — Rodada BINDER-VIS-02 (2026-08-28).
 * Refino sobre a Rodada 1: vazio não deve ler como "placeholder de UI" —
 * precisa de aro de PVC, abertura perceptível no topo (onde a carta entra)
 * e a página por trás visível através do plástico. Ocupado usa
 * `MockCardFace` (carta mock com layout real) em vez de bloco de cor, com o
 * mesmo reflexo de plástico por cima. Puramente decorativo, sem lógica
 * funcional (sem clique, sem drag, sem dado real).
 */

const SHEEN =
  "linear-gradient(115deg, hsl(0 0% 100% / 0.2) 0%, transparent 32%, transparent 68%, hsl(0 0% 100% / 0.06) 100%)";

export function BinderSlot({ slot }: { slot: BinderSlotData }) {
  return (
    <div
      className="relative aspect-[5/7] overflow-hidden rounded-[4px]"
      style={{
        background: slot.filled ? "hsl(0 0% 3% / 0.4)" : "hsl(0 0% 0% / 0.32)",
        boxShadow: [
          // Aro de PVC — highlight superior-esquerdo, sombra inferior-direita (bisel de plástico).
          "inset 1px 1px 0 hsl(0 0% 100% / 0.14)",
          "inset -1px -1px 0 hsl(0 0% 0% / 0.4)",
          "inset 0 3px 7px rgba(0,0,0,0.55)",
        ].join(", "),
      }}
    >
      {/* Backing da página visível através do bolso vazio — textura muito sutil, não um "fundo de UI". */}
      {!slot.filled && (
        <div
          className="pointer-events-none absolute inset-[10%]"
          style={{
            backgroundImage:
              "repeating-linear-gradient(0deg, hsl(0 0% 100% / 0.03) 0px, hsl(0 0% 100% / 0.03) 1px, transparent 1px, transparent 6px)",
          }}
          aria-hidden
        />
      )}

      {slot.filled && slot.card && (
        <div className="absolute inset-[4%] top-[3%] overflow-hidden rounded-[2px]" style={{ boxShadow: "0 2px 5px rgba(0,0,0,0.45)" }}>
          <MockCardFace card={slot.card} />
        </div>
      )}

      {/* Abertura do bolso — linha clara perto do topo, onde a carta é inserida. */}
      <div
        className="pointer-events-none absolute inset-x-0 top-[7%] h-[2px]"
        style={{ background: "hsl(0 0% 100% / 0.16)" }}
        aria-hidden
      />

      {/* Reflexo do plástico do bolso — por cima do conteúdo, vende "dentro do bolso". */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{ backgroundImage: SHEEN, opacity: slot.filled ? 0.35 : 0.75 }}
        aria-hidden
      />
      {/* Contorno externo do bolso — perceptível mesmo vazio. */}
      <div className="pointer-events-none absolute inset-0 rounded-[4px]" style={{ boxShadow: "inset 0 0 0 1px hsl(0 0% 100% / 0.1)" }} aria-hidden />
    </div>
  );
}
