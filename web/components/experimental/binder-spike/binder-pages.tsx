import type { BinderPageData } from "@/app/experimental/binder-spike/mock-data";
import { cn } from "@/lib/utils";
import { GOLD, LEATHER_HUE, leatherSurface } from "./binder-cover";
import { BinderSlot } from "./binder-slot";

/**
 * Miolo aberto do Binder — Rodada BINDER-VIS-02 (2026-08-28). Reescrito
 * sobre a Rodada 1 para responder ao ponto 2 do pedido ("continuidade
 * física"): o miolo não é mais renderizado sozinho — ele vive dentro de uma
 * "casca" de couro (mesmo `leatherSurface`/`LEATHER_HUE` da capa fechada),
 * com a mesma borda arredondada e um friso dourado no perímetro. É essa
 * casca, não as páginas, que carrega o `viewTransitionName` — o navegador
 * faz o objeto de couro fechado morfar para este objeto de couro aberto
 * (maior, com uma margem visível de "capa" ao redor das páginas), o que
 * transmite que o miolo pertence ao mesmo objeto.
 *
 * Cada página agora tem: 2 folhas "fantasma" empilhadas atrás (espessura de
 * papel, ponto 3), curvatura sugerida por um brilho de borda que escurece
 * em direção ao vinco central, e cantos arredondados só no lado externo
 * (o lado do vinco fica reto, como uma folha real presa na lombada).
 */
export function BinderPages({
  pages,
  viewTransitionName,
}: {
  pages: BinderPageData[];
  viewTransitionName?: string;
}) {
  return (
    <div
      className="relative mx-auto w-full max-w-4xl overflow-hidden rounded-[22px]"
      style={{
        viewTransitionName,
        backgroundImage: leatherSurface(LEATHER_HUE),
        boxShadow: [
          "inset 0 1px 0 hsl(0 0% 100% / 0.1)",
          "inset 0 -2px 10px hsl(0 0% 0% / 0.5)",
          "0 40px 60px -20px rgba(0,0,0,0.65)",
        ].join(", "),
        border: `1px solid hsl(${GOLD} / 0.18)`,
        padding: "clamp(10px, 2.4vw, 22px)",
      }}
    >
      <div className="relative flex" style={{ perspective: "2000px" }}>
        {pages.map((page, i) => {
          const isLeft = i === 0;
          return (
            <div
              key={page.id}
              className="relative flex-1"
              style={{
                transform: `rotateY(${isLeft ? 2 : -2}deg)`,
                transformOrigin: isLeft ? "right center" : "left center",
              }}
            >
              {/* Folhas fantasma — espessura de papel empilhado atrás da folha de cima. */}
              <div
                className={cn("absolute inset-0", isLeft ? "rounded-l-lg" : "rounded-r-lg")}
                style={{ transform: "translate(2px, 3px)", background: `hsl(${LEATHER_HUE} 10% 4%)` }}
                aria-hidden
              />
              <div
                className={cn("absolute inset-0", isLeft ? "rounded-l-lg" : "rounded-r-lg")}
                style={{ transform: "translate(1px, 1.5px)", background: `hsl(${LEATHER_HUE} 12% 6%)` }}
                aria-hidden
              />

              {/* Folha de cima — fundo de página real (tecido/PVC escuro), cantos externos arredondados, lado do vinco reto. */}
              <div
                className={cn("relative overflow-hidden p-3 sm:p-4", isLeft ? "rounded-l-lg" : "rounded-r-lg")}
                style={{
                  background: `linear-gradient(${isLeft ? "100deg" : "260deg"}, hsl(${LEATHER_HUE} 14% 11%) 0%, hsl(${LEATHER_HUE} 18% 6%) 100%)`,
                  boxShadow: [
                    // Curvatura — escurece progressivamente em direção ao vinco (lado interno).
                    isLeft ? "inset -26px 0 30px -22px rgba(0,0,0,0.85)" : "inset 26px 0 30px -22px rgba(0,0,0,0.85)",
                    // Brilho sutil na borda externa — a folha "levanta" levemente ali.
                    isLeft ? "inset 3px 0 0 hsl(0 0% 100% / 0.05)" : "inset -3px 0 0 hsl(0 0% 100% / 0.05)",
                    "inset 0 2px 6px rgba(0,0,0,0.4)",
                  ].join(", "),
                }}
              >
                <div className="grid grid-cols-3 gap-2 sm:gap-2.5">
                  {page.slots.map((slot) => (
                    <BinderSlot key={slot.id} slot={slot} />
                  ))}
                </div>
              </div>
            </div>
          );
        })}

        {/* Lombada/vinco central — mesma cor de couro da lombada da capa fechada, não só uma sombra genérica. */}
        <div
          className="pointer-events-none absolute inset-y-[-4%] left-1/2 w-5 -translate-x-1/2"
          style={{
            background: `linear-gradient(90deg, transparent, hsl(${LEATHER_HUE} 20% 4%) 35%, hsl(${LEATHER_HUE} 20% 4%) 65%, transparent)`,
            boxShadow: "0 0 16px 4px rgba(0,0,0,0.5)",
          }}
          aria-hidden
        />
      </div>
    </div>
  );
}
