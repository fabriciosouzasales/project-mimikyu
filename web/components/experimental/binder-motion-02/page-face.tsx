import type { BinderPageData } from "@/app/experimental/binder-spike/mock-data";
import { LEATHER_HUE } from "@/components/experimental/binder-spike/binder-cover";
import { BinderSlot } from "@/components/experimental/binder-spike/binder-slot";
import { cn } from "@/lib/utils";

/**
 * Face de UMA página do BINDER-MOTION-02. Reaproveita sem edição o
 * `BinderSlot` (bolso) validado em BINDER-VIS-02 e o mesmo material de
 * "folha de cima" já usado em `binder-pages.tsx` (mesmos tokens
 * `LEATHER_HUE`/gradientes/box-shadow) — mas como peça ISOLADA (uma folha,
 * não duas fixas lado a lado), porque a mecânica de dobradiça/virada exige
 * cada folha como elemento independente que gira sozinho. `binder-pages.tsx`
 * (duas páginas fixas) não foi tocado nem redesenhado — continua servindo
 * o miolo estático do Binder-First/BINDER-VIS-02 tal como aprovado.
 *
 * `isVerso`: quando true, sobrepõe uma hachura diagonal muito sutil — o
 * verso da folha física deve ser perceptível como "o outro lado da folha",
 * mesmo quando o conteúdo (cartas) por si só já distingue frente/verso.
 */
export function PageFace({
  page,
  side,
  isVerso = false,
}: {
  page: BinderPageData;
  side: "left" | "right";
  isVerso?: boolean;
}) {
  return (
    <div
      className={cn("relative h-full w-full overflow-hidden p-3 sm:p-4", side === "left" ? "rounded-l-lg" : "rounded-r-lg")}
      style={{
        background: `linear-gradient(${side === "left" ? "100deg" : "260deg"}, hsl(${LEATHER_HUE} 14% 11%) 0%, hsl(${LEATHER_HUE} 18% 6%) 100%)`,
        boxShadow: [
          side === "left" ? "inset -26px 0 30px -22px rgba(0,0,0,0.85)" : "inset 26px 0 30px -22px rgba(0,0,0,0.85)",
          side === "left" ? "inset 3px 0 0 hsl(0 0% 100% / 0.05)" : "inset -3px 0 0 hsl(0 0% 100% / 0.05)",
          "inset 0 2px 6px rgba(0,0,0,0.4)",
        ].join(", "),
      }}
    >
      <div className="grid grid-cols-3 gap-2 sm:gap-2.5">
        {page.slots.map((slot) => (
          <BinderSlot key={slot.id} slot={slot} />
        ))}
      </div>
      {isVerso && (
        <div
          className="pointer-events-none absolute inset-0"
          style={{
            backgroundImage:
              "repeating-linear-gradient(115deg, hsl(0 0% 100% / 0.025) 0px, hsl(0 0% 100% / 0.025) 2px, transparent 2px, transparent 10px)",
          }}
          aria-hidden
        />
      )}
    </div>
  );
}

/** Painel de "fim do binder" — mostrado no lugar de uma PageFace quando não há próximo spread. */
export function EndOfBinderFace({ side }: { side: "left" | "right" }) {
  return (
    <div
      className={cn(
        "relative flex h-full w-full items-center justify-center overflow-hidden",
        side === "left" ? "rounded-l-lg" : "rounded-r-lg",
      )}
      style={{ background: `hsl(${LEATHER_HUE} 16% 7%)` }}
    >
      <p className="text-[11px] uppercase tracking-[0.18em] text-white/25">Fim do binder</p>
    </div>
  );
}
