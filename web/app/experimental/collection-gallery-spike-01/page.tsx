import type { Metadata } from "next";
import { CollectionGallerySpikeView } from "@/components/experimental/collection-gallery-spike-01/collection-gallery-spike-view";

/**
 * Rota experimental, fora da IA oficial — COLLECTION-GALLERY-SPIKE-01
 * (pedido de Fabrício, 2026-08-29), sucessor direto do discovery técnico
 * COLLECTION-GALLERY-01 (React Bits Circular Gallery vs. Depth Carousel vs.
 * Premium Grid/List — ver `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md`, seções 3 e
 * 4, e a skill `mmkyu-frontend-experience`).
 *
 * Objetivo único: decidir, por spike visual, se a experiência de Collection
 * Gallery agrega valor sobre um Premium Grid/List operacional — sem
 * instalar GSAP/Motion/OGL nesta rodada. Deliberadamente fora de
 * `AppShell`, mesmo padrão dos demais spikes em `app/experimental/`.
 *
 * `noindex` porque é rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "Collection-Gallery-Spike-01 (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function CollectionGallerySpike01Page() {
  return <CollectionGallerySpikeView />;
}
