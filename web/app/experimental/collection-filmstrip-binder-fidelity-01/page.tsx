import type { Metadata } from "next";
import { CollectionFilmstripBinderFidelityView } from "@/components/experimental/collection-filmstrip-binder-fidelity-01/collection-filmstrip-binder-fidelity-view";

/**
 * Rota experimental, fora da IA oficial — COLLECTION-FILMSTRIP-BINDER-
 * FIDELITY-01, pedido de Fabrício de 2026-08-29: antes de finalizar a
 * fidelidade do Filmstrip como Signature View, decidir visualmente QUAL
 * conteúdo deve ocupar o retrato do card — o Binder puro (A), a carta de
 * destaque pura (B), ou o Binder com a arte da carta como cover treatment
 * (C, hipótese principal de Fabrício). Ver doc-comment de
 * `collection-filmstrip-binder-fidelity-view.tsx` para o detalhamento
 * completo.
 *
 * `noindex` — rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "Collection Filmstrip Binder Fidelity 01 (experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function CollectionFilmstripBinderFidelity01Page() {
  return <CollectionFilmstripBinderFidelityView />;
}
