import type { RealCardData } from "@/app/experimental/binder-nav-01/mock-data";
import { cn } from "@/lib/utils";

/**
 * Face de carta com artwork REAL — teste pontual do BINDER-NAV-01 (pedido de
 * Fabrício, 2026-08-28: "um teste com imagens das cartas da coleção ME2").
 * Lê imagens já publicadas no bucket público `card-front` do Supabase
 * (`card`/`card_asset`, idioma pt-BR, Card Set ME2 "Fogo Fantasmagórico") —
 * URLs fixas montadas em `mock-data.ts`, sem query em runtime, sem
 * persistência, sem lógica de domínio nova.
 *
 * `<img>` simples (não `next/image`) — spike isolado, sem necessidade de
 * configurar `remotePatterns` em `next.config.ts` (arquivo compartilhado)
 * por causa de um teste visual pontual.
 *
 * CARD-DETAIL-01 (2026-08-29) — ganhou a prop opcional `fit`. Dentro do
 * bolso do Binder o padrão continua `"cover"` (preenche 100% do slot,
 * cortando o excedente — requisito da rodada anterior). O Card Detail
 * (`card-detail-modal.tsx`) pede explicitamente "preservar proporção real"
 * da carta na imagem grande — por isso passa `fit="contain"`, que nunca
 * corta a arte. Callers existentes (`binder-slot-full.tsx`) não passam a
 * prop e continuam com o comportamento antigo, sem nenhuma mudança visual.
 */
export function RealCardFace({ card, fit = "cover" }: { card: RealCardData; fit?: "cover" | "contain" }) {
  return (
    <img
      src={card.imageUrl}
      alt={card.name}
      className={cn("h-full w-full", fit === "cover" ? "object-cover" : "object-contain")}
      loading="lazy"
      draggable={false}
    />
  );
}
