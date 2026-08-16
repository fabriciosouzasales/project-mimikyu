import { BookOpen, LayoutDashboard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { VisaoGeralStats } from "@/components/catalogo/visao-geral-stats";
import { CardSetsTable } from "@/components/catalogo/card-sets-table";
import { AtividadeRecente } from "@/components/catalogo/atividade-recente";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageSection, PageTitle } from "@/components/ui/page";
import { getAtividadeRecente, getCardSetsOverview, getEstadoDoCatalogo } from "@/lib/catalogo/queries";

/**
 * Visão Geral do Catálogo Editorial — módulo admin-only (ADR-022).
 *
 * Alinhada ao padrão introduzido em Jogos (2026-07-31, aprovado por
 * Fabrício para replicar aqui): título via `PageHeader`/`PageTitle` (era um
 * `<h1>` solto), indicadores via `StatCard`/`StatsRow` (`VisaoGeralStats`,
 * substitui `EstadoDoCatalogo`), Card Sets e Atividade recente migradas de
 * `Panel` para `Card` com busca/filtro integrado e cabeçalho destacado —
 * ver `card-sets-table.tsx`/`atividade-recente.tsx`.
 *
 * Hierarquia da página (revisão 2026-08-08, pedido de Fabrício): 1. Estado
 * do catálogo — KPIs, Cobertura por idioma e Saúde do catálogo, tudo dentro
 * de `VisaoGeralStats`; 2. Coleções; 3. Atividade recente. O bloco "Cartas
 * por raridade" (gráfico de distribuição, via `Distribuicoes`/
 * `getDistribuicaoPorRaridade()`) foi removido desta página — é uma análise
 * de distribuição sem contexto operacional aqui, e fica reservado como
 * candidato à futura Central de Relatórios (Módulo Gerencial, `ROADMAP.md`,
 * Trilha 4). Nem o componente `Distribuicoes` nem `getDistribuicaoPorRaridade()`
 * foram removidos do repositório — só deixaram de ser chamados nesta tela,
 * disponíveis para reuso quando a Central de Relatórios for implementada.
 * Substitui a ordem anterior (2026-07-31): indicadores, gráfico de Cartas
 * por raridade, tabela de Card Sets, Atividade recente.
 *
 * Ícones (2026-07-31, padronização iniciada em Expansões): esta tela tem
 * DOIS títulos distintos, cada um com seu próprio ícone — o breadcrumb do
 * `AppShell` mostra "Catálogo editorial" (nível de módulo, `BookOpen`,
 * mesmo ícone da seção no menu principal) enquanto o `PageTitle` da própria
 * página mostra "Visão Geral" (item "Gerencial" do submenu, `LayoutDashboard`).
 *
 * A arquitetura cromática testada aqui como prova visual isolada
 * ("onyx-preview", 3 rodadas, 2026-08-16, ver `docs/log.md`) foi aprovada e
 * promovida a BASELINE de todas as páginas internas — `chromeVariant`/
 * `preview` foram removidos (não são mais opcionais, `AppShell` sempre
 * aplica o mesmo tratamento). Esta página não passa mais nenhuma prop
 * especial de tema.
 */
export default async function CatalogoVisaoGeralPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const [estado, cardSets, atividades] = await Promise.all([
    getEstadoDoCatalogo(supabase),
    getCardSetsOverview(supabase),
    // 50 (era 8): a tabela de Atividade recente agora pagina 10 por vez
    // (`atividade-recente.tsx`) — precisa de mais do que uma página de
    // dados para a paginação ter algo a mostrar.
    getAtividadeRecente(supabase, 50),
  ]);

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <LayoutDashboard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Visão Geral</PageTitle>
            </div>
            <PageDescription>Indicadores gerais e navegação rápida para as Coleções do catálogo.</PageDescription>
          </PageHeading>
        </PageHeader>

        <VisaoGeralStats estado={estado} />

        <PageSection title="Coleções" description="Clique em uma Coleção para ver o detalhe.">
          <CardSetsTable cardSets={cardSets} />
        </PageSection>

        <PageSection title="Atividade recente" description="Últimas execuções de importação — Cartas e Imagens.">
          <AtividadeRecente atividades={atividades} />
        </PageSection>
      </PageContainer>
    </AppShell>
  );
}
