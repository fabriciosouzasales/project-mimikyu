import type { Metadata } from "next";
import { CollectionLibraryVisualView } from "@/components/experimental/collection-library-visual-01/collection-library-visual-view";

/**
 * Rota experimental, fora da IA oficial — COLLECTION-LIBRARY-VISUAL-01
 * (pedido de Fabrício, 2026-08-29), sucessora direta de
 * COLLECTION-GALLERY-SPIKE-01 (Premium Grid/List venceu o spike de
 * comparação — ver `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md`, seções 4 e 11).
 *
 * Objetivo único: elevar visualmente o Premium Grid aprovado sem transformar
 * a tela em dashboard administrativo — "biblioteca digital premium de
 * Binders", não "cards contendo Binders". Deliberadamente fora de
 * `AppShell`, mesmo padrão dos demais spikes em `app/experimental/`.
 *
 * `noindex` porque é rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "Collection-Library-Visual-01 (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function CollectionLibraryVisual01Page() {
  return <CollectionLibraryVisualView />;
}
