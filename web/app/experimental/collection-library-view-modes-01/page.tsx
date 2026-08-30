import type { Metadata } from "next";
import { CollectionLibraryViewModesView } from "@/components/experimental/collection-library-view-modes-01/collection-library-view-modes-view";

/**
 * Rota experimental, fora da IA oficial — COLLECTION-LIBRARY-VIEW-MODES-01,
 * pedido de Fabrício de 2026-08-29: consolidação final da frente visual da
 * Collection Library. Encerra a exploração de padrões (Premium Grid,
 * Character Wave, Character Carousel/Filmstrip, Complete Shelf, Hero Card/
 * Hero Artwork) numa decisão fechada de três modos oficiais de
 * visualização — Lista, Cards, Carrossel — todos representando a MESMA
 * Collection com o mesmo núcleo de informação (Binder, nome, código,
 * progresso), variando só densidade/apresentação. Ver doc-comment de
 * `collection-library-view-modes-view.tsx` para o detalhamento completo.
 *
 * `noindex` — rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "Collection Library View Modes 01 (experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function CollectionLibraryViewModes01Page() {
  return <CollectionLibraryViewModesView />;
}
