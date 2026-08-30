import type { Metadata } from "next";
import { Scene } from "@/components/experimental/mmkyu-shelf-adaptation-v1/scene";

/**
 * Rota experimental, fora da IA oficial — MMKYU SHELF ADAPTATION V1, pedido
 * de Fabrício de 2026-08-29: primeira adaptação visual do baseline
 * `CompleteShelfLandingPage` (ThreeUI) para representar Collections/Binders
 * do MMKYU. Ver doc-comment de `scene.tsx` para o detalhamento completo
 * (source ownership, o que mudou, o que foi preservado).
 *
 * A rota irmã `/experimental/threeui-complete-shelf-proof` continua de pé,
 * sem alteração, para comparação lado a lado com o baseline authored.
 *
 * `noindex` — rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "MMKYU Shelf Adaptation V1 (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function MmkyuShelfAdaptationV1Page() {
  return <Scene />;
}
