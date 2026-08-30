import type { Metadata } from "next";
import { CollectionWaveSpikeView } from "@/components/experimental/collection-wave-spike-01/collection-wave-spike-view";

/**
 * Rota experimental, fora da IA oficial — COLLECTION-WAVE-SPIKE-01, pedido
 * de Fabrício de 2026-08-29: testar Character Wave (ThreeUI) como modo
 * Signature View de "Minhas Collections", comparado com o Premium Grid já
 * aprovado como modo operacional. Ampliado no mesmo dia com um terceiro
 * modo, Character Carousel/Filmstrip (modelo base da família, sem
 * `variant` explícito), para comparação de três vias — e, em seguida, com
 * suporte Light/Dark (reaproveita o `next-themes` já usado no app). Ver
 * doc-comment de `collection-wave-spike-view.tsx` para o detalhamento
 * completo.
 *
 * `noindex` — rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "Collection Wave Spike 01 (experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function CollectionWaveSpike01Page() {
  return <CollectionWaveSpikeView />;
}
