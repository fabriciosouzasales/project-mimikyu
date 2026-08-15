import { Copy } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarVariantesView } from "@/components/catalogo/importar-variantes-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetsForVariantes } from "@/lib/catalogo/queries";

/**
 * Importar Variantes (Incremento 4, ADR-028) — grupo "Operações" do menu do
 * Catálogo (`nav-config.ts`), mesmo padrão estrutural de
 * `/catalogo/importar-cartas/page.tsx`: `?cardSetId=` resolve a Coleção
 * selecionada a partir da URL, o fluxo inteiro (Analisar → progresso →
 * Revisão → Confirmação) vive em estado de componente cliente dentro de
 * `ImportarVariantesView`, sem nenhum redirect no meio (mesmo motivo já
 * documentado lá: `redirect()` remontaria a página do zero e destruiria o
 * progresso visível).
 *
 * `key={selectedCardSet?.id}` reseta `useAnalyzeVariantsJob` ao trocar de
 * Coleção pelo combobox — mesma correção de bug real já aplicada em
 * `ImportarCartasView` (ver comentário lá).
 */
export default async function ImportarVariantesPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSetId?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Importar Variantes", Copy);
  if (denied) return denied;

  const { cardSetId } = await searchParams;

  const cardSets = await getCardSetsForVariantes(supabase);
  const selectedCardSet = cardSetId ? (cardSets.find((cardSet) => cardSet.id === cardSetId) ?? null) : null;

  return (
    <AppShell title="Importar Variantes" icon={Copy}>
      <PageContainer>
        <ImportarVariantesView key={selectedCardSet?.id ?? "none"} cardSets={cardSets} selectedCardSet={selectedCardSet} />
      </PageContainer>
    </AppShell>
  );
}
