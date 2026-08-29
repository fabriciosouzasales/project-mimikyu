import type { Metadata } from "next";
import { BinderSpikeView } from "@/components/experimental/binder-spike/binder-spike-view";

/**
 * Rota experimental, fora da IA oficial — spike "Binder-First" (pedido de
 * Fabrício, 2026-08-28). Sucede o "Visual Collection Space"
 * (`/experimental/collection-space`, preservado intacto como prova técnica
 * encerrada — não é mais a direção de baseline visual). Deliberadamente
 * fora de `AppShell`: mesma direção de produto de UX-01 (experiência
 * client-facing premium, não backoffice).
 *
 * `noindex` porque é rota de spike, não destino de produto.
 */
export const metadata: Metadata = {
  title: "Binder-First (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function BinderSpikeExperimentalPage() {
  return <BinderSpikeView />;
}
