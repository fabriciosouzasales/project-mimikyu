import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelHeader, PanelTitle, PanelDescription } from "@/components/catalogo/panel";
import { CardSetsTable } from "@/components/catalogo/card-sets-table";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getCardSetsOverview } from "@/lib/catalogo/queries";

/**
 * Destino dedicado dos Card Sets — mesmo dado e mesma tabela já usados no
 * bloco "Card Sets" da Visão Geral (`getCardSetsOverview` + `CardSetsTable`).
 * Reaproveitado sem duplicar lógica: aqui ele é o conteúdo principal da
 * página, não um bloco entre outros.
 */
export default async function CardSetsPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Card Sets");
  if (denied) return denied;

  const cardSets = await getCardSetsOverview(supabase);

  return (
    <AppShell title="Card Sets">
      <div className="mx-auto max-w-6xl space-y-4">
        <h1 className="font-heading text-xl font-medium text-foreground">Card Sets</h1>

        <Panel>
          <PanelHeader>
            <PanelTitle>Card Sets cadastrados</PanelTitle>
            <PanelDescription>Clique em um Card Set para ver o detalhe.</PanelDescription>
          </PanelHeader>
          <PanelContent>
            <CardSetsTable cardSets={cardSets} />
          </PanelContent>
        </Panel>
      </div>
    </AppShell>
  );
}
