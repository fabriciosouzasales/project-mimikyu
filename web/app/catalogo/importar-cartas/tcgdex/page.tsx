import { Globe } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarTcgdexView } from "@/components/catalogo/importar-tcgdex-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetsSemCartas } from "@/lib/catalogo/queries";
import { autoMatchTcgdexSet } from "@/lib/catalogo/tcgdex-lookup";

/**
 * Passos "Selecionar fonte TCGdex" + "Analisar" do fluxo do Ciclo 2
 * (ADR-024). Ajuste de Fabrício (2026-08-01): o administrador nunca digita
 * o external_set_id — o sistema localiza automaticamente o Set
 * correspondente na TCGdex a partir do nome da Coleção (ver
 * lib/catalogo/tcgdex-lookup.ts); só em ambiguidade ou nenhuma
 * correspondência é oferecida uma busca manual, ainda por nome.
 */
export default async function ImportarViaTcgdexPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSetId?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Importar via TCGdex", Globe);
  if (denied) return denied;

  const { cardSetId } = await searchParams;
  const cardSets = await getCardSetsSemCartas(supabase);
  const selectedCardSet = cardSetId ? (cardSets.find((cs) => cs.id === cardSetId) ?? null) : null;
  const matchResult = selectedCardSet ? await autoMatchTcgdexSet(selectedCardSet.name) : null;

  return (
    <AppShell title="Importar via TCGdex" icon={Globe}>
      <PageContainer>
        <ImportarTcgdexView cardSets={cardSets} selectedCardSet={selectedCardSet} matchResult={matchResult} />
      </PageContainer>
    </AppShell>
  );
}
