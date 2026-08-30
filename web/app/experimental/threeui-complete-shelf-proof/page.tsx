import type { Metadata } from "next";
import { Scene } from "@/components/experimental/threeui-complete-shelf-proof/scene";

/**
 * Rota experimental, fora da IA oficial — FASE 1 (PROVA DE FIDELIDADE) do
 * pedido de Fabrício de 2026-08-29 sobre o componente ThreeUI
 * `CompleteShelfLandingPage`. Ver doc-comment de `scene.tsx` para o
 * detalhamento da verificação de fonte (Fase 0) e da pendência de
 * ambiente (instalação do pacote precisa ser feita por Fabrício — o
 * sandbox do agente não tem acesso ao registry do npm).
 *
 * `noindex` — rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "ThreeUI Complete Shelf — Prova de Fidelidade (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function ThreeUICompleteShelfProofPage() {
  return <Scene />;
}
