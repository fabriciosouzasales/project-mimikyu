import type { Metadata } from "next";
import { CollectionSpaceView } from "@/components/experimental/collection-space/collection-space-view";

/**
 * Rota experimental, fora da IA oficial — spike "Visual Collection Space"
 * (pedido de Fabrício, 2026-08-28). Deliberadamente FORA de `AppShell`
 * (sem sidebar/header administrativo): a direção de produto registrada em
 * `docs/domain-modeling/collections/checkpoint-2026-08-28.md` (Seção 7)
 * pede uma experiência client-facing premium, não uma página de backoffice.
 *
 * `noindex` porque é rota de spike, não um destino de produto — não deve
 * aparecer em nenhum índice/navegação nem ser tratada como IA definitiva.
 * Nome de rota/segmento ("experimental/collection-space") é deliberadamente
 * provisório: não resolve a colisão de nomenclatura com "Coleções"
 * (`/catalogo/card-sets`), só evita colidir com ela por ora.
 */
export const metadata: Metadata = {
  title: "Collection Space (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function CollectionSpaceExperimentalPage() {
  return <CollectionSpaceView />;
}
