import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { VisaoGeralStats } from "@/components/catalogo/visao-geral-stats";
import { CardSetsTable } from "@/components/catalogo/card-sets-table";
import { Distribuicoes } from "@/components/catalogo/distribuicoes";
import { AtividadeRecente } from "@/components/catalogo/atividade-recente";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageSection, PageTitle } from "@/components/ui/page";
import {
  getAtividadeRecente,
  getCardSetsOverview,
  getDistribuicaoPorRaridade,
  getEstadoDoCatalogo,
} from "@/lib/catalogo/queries";

/**
 * Visão Geral do Catálogo Editorial — módulo admin-only (ADR-022).
 *
 * Alinhada ao padrão introduzido em Jogos (2026-07-31, aprovado por
 * Fabrício para replicar aqui): título via `PageHeader`/`PageTitle` (era um
 * `<h1>` solto), indicadores via `StatCard`/`StatsRow` (`VisaoGeralStats`,
 * substitui `EstadoDoCatalogo`), Card Sets e Atividade recente migradas de
 * `Panel` para `Card` com busca/filtro integrado e cabeçalho destacado —
 * ver `card-sets-table.tsx`/`atividade-recente.tsx`. `Panel` permanece só
 * em Cartas por raridade (gráfico, não tabela).
 *
 * Ordem da página (ajuste 2026-07-31, pedido de Fabrício): pilha única, sem
 * mais grid de 3 colunas — indicadores, gráfico de Cartas por raridade,
 * tabela de Card Sets, Atividade recente (log), nessa sequência. Substitui
 * o layout anterior (2026-07-26) que colocava Card Sets como bloco
 * dominante ao lado de uma coluna secundária com Raridade + Atividade.
 */
export default async function CatalogoVisaoGeralPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial");
  if (denied) return denied;

  const [estado, cardSets, distribuicao, atividades] = await Promise.all([
    getEstadoDoCatalogo(supabase),
    getCardSetsOverview(supabase),
    getDistribuicaoPorRaridade(supabase),
    // 50 (era 8): a tabela de Atividade recente agora pagina 10 por vez
    // (`atividade-recente.tsx`) — precisa de mais do que uma página de
    // dados para a paginação ter algo a mostrar.
    getAtividadeRecente(supabase, 50),
  ]);

  return (
    <AppShell title="Catálogo editorial">
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <PageTitle>Visão Geral</PageTitle>
            <PageDescription>Indicadores gerais e navegação rápida para os Card Sets do catálogo.</PageDescription>
          </PageHeading>
        </PageHeader>

        <VisaoGeralStats estado={estado} />

        <Panel>
          <PanelHeader>
            <PanelTitle>Cartas por raridade</PanelTitle>
          </PanelHeader>
          <PanelContent>
            <Distribuicoes distribuicao={distribuicao} />
          </PanelContent>
        </Panel>

        <PageSection title="Card Sets" description="Clique em um Card Set para ver o detalhe.">
          <CardSetsTable cardSets={cardSets} />
        </PageSection>

        <PageSection title="Atividade recente" description="Últimas execuções de importação de imagens.">
          <AtividadeRecente atividades={atividades} />
        </PageSection>
      </PageContainer>
    </AppShell>
  );
}
