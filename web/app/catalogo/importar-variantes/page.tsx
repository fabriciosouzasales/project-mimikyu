import { Copy } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarVariantesView } from "@/components/catalogo/importar-variantes-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetForVariantesById, getCardSetsForVariantes } from "@/lib/catalogo/queries";

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
 * `ImportarCartasView` (ver comentário lá). Precisamente por isso, manter
 * `selectedCardSet` estável quando o job simplesmente termina é essencial —
 * ver fallback abaixo.
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
  let selectedCardSet = cardSetId ? (cardSets.find((cardSet) => cardSet.id === cardSetId) ?? null) : null;

  // Fallback (fechamento de UX pós-confirmação, 2026-08-15): `cardSetId` veio
  // na URL mas a Coleção não está mais entre as pendentes — típico logo após
  // uma confirmação bem-sucedida zerar `cardsSemVariante`. Sem isso,
  // `selectedCardSet` cairia para `null`, o `key` abaixo mudaria de
  // `cardSetId` para `"none"` e `ImportarVariantesView` remontaria do zero,
  // apagando o resumo final que acabou de ser exibido — a tela "resetava
  // sozinha" na visão do usuário. Só dispara neste caso específico (a lista
  // pendente já veio carregada acima); não é um round-trip a mais no
  // caminho comum de seleção via combobox.
  if (cardSetId && !selectedCardSet) {
    selectedCardSet = await getCardSetForVariantesById(supabase, cardSetId);
  }

  return (
    <AppShell title="Importar Variantes" icon={Copy}>
      <PageContainer>
        <ImportarVariantesView key={selectedCardSet?.id ?? "none"} cardSets={cardSets} selectedCardSet={selectedCardSet} />
      </PageContainer>
    </AppShell>
  );
}
