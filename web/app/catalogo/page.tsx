import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelDescription, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { EstadoDoCatalogo } from "@/components/catalogo/estado-do-catalogo";
import { CardSetsTable } from "@/components/catalogo/card-sets-table";
import { Distribuicoes } from "@/components/catalogo/distribuicoes";
import { AtividadeRecente } from "@/components/catalogo/atividade-recente";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import {
  getAtividadeRecente,
  getCardSetsOverview,
  getDistribuicaoPorRaridade,
  getEstadoDoCatalogo,
} from "@/lib/catalogo/queries";

/**
 * Visão Geral do Catálogo Editorial — módulo admin-only (ADR-022).
 *
 * Linguagem visual em validação (2026-07-26, restrita a este módulo):
 * Card Sets é o bloco dominante (mais espaço, primeiro na leitura); Estado
 * do Catálogo vira uma faixa leve de contexto, não mais 4 cards do mesmo
 * peso; Cartas por Raridade e Atividade Recente ficam mais discretos, numa
 * coluna secundária — ritmo visual desequilibrado de propósito, não um
 * grid uniforme (ajuste pedido por Fabrício).
 */
export default async function CatalogoVisaoGeralPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial");
  if (denied) return denied;

  const [estado, cardSets, distribuicao, atividades] = await Promise.all([
    getEstadoDoCatalogo(supabase),
    getCardSetsOverview(supabase),
    getDistribuicaoPorRaridade(supabase),
    getAtividadeRecente(supabase),
  ]);

  return (
    <AppShell title="Catálogo editorial">
      <div className="mx-auto max-w-6xl space-y-4">
        <h1 className="font-heading text-xl font-medium text-foreground">Visão geral do catálogo</h1>

        <EstadoDoCatalogo estado={estado} />

        <div className="grid gap-4 lg:grid-cols-3">
          <Panel className="lg:col-span-2">
            <PanelHeader>
              <PanelTitle>Card Sets</PanelTitle>
              <PanelDescription>Clique em um Card Set para ver o detalhe.</PanelDescription>
            </PanelHeader>
            <PanelContent>
              <CardSetsTable cardSets={cardSets} />
            </PanelContent>
          </Panel>

          <div className="flex flex-col gap-4">
            <Panel>
              <PanelHeader>
                <PanelTitle>Cartas por raridade</PanelTitle>
              </PanelHeader>
              <PanelContent>
                <Distribuicoes distribuicao={distribuicao} />
              </PanelContent>
            </Panel>

            <Panel>
              <PanelHeader>
                <PanelTitle>Atividade recente</PanelTitle>
              </PanelHeader>
              <PanelContent>
                <AtividadeRecente atividades={atividades} />
              </PanelContent>
            </Panel>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
