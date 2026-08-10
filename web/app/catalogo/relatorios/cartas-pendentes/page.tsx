import { BookOpen, FileText } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTable, DataTableCell, DataTableHead, DataTableHeadCell, DataTableHeadRow, DataTableRow } from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getRelatorioCartasPendentes } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const TITULO = "Cartas pendentes por Coleção";
const SUBTITULO = "Coleções com Cartas ainda não cadastradas frente ao tamanho oficial do Set.";
const COLUNAS = 4;

/**
 * Relatório "Cartas pendentes por Coleção" (Central de Relatórios, V1
 * aprovada por Fabrício, 2026-08-09) — uma linha por Coleção com
 * `cards_pendentes_cadastro > 0` (`catalog_card_set_metrics`, Query
 * 2123/2124), mesma definição já usada em "Saúde do catálogo" na Visão
 * Geral, agora detalhada por Coleção em vez de só a contagem agregada.
 * Sem seletor — é uma tabela cruzando todas as Coleções de uma vez.
 *
 * Visual alinhado à baseline do Checklist por Coleção (2026-08-09, mesmo
 * dia, rodada seguinte — Fabrício aprovou o Checklist e pediu que os outros
 * 5 relatórios adotassem o mesmo cabeçalho/identidade/tipografia/margens):
 * `RelatorioFolha` (folha A4) + `RelatorioCabecalho` (logo Mimikyu, sem logo
 * de Coleção — este relatório cruza todas de uma vez, não faz sentido
 * mostrar uma logo específica) dentro do próprio `<thead>` da `DataTable`,
 * junto com a linha de cabeçalho de coluna já existente — as duas linhas
 * ficam no mesmo `<thead>` e repetem juntas em toda página impressa, caso a
 * tabela cresça o bastante para fragmentar em mais de uma folha. `PageHeader`
 * (chrome só de tela) ganhou `print:hidden`, que faltava antes desta rodada.
 */
export default async function RelatorioCartasPendentesPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const itens = await getRelatorioCartasPendentes(supabase);

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>{TITULO}</PageTitle>
            </div>
            <PageDescription>{SUBTITULO}</PageDescription>
          </PageHeading>
          <RelatorioPrintButton />
        </PageHeader>

        <RelatorioFolha>
          {itens.length === 0 ? (
            <>
              <RelatorioCabecalho titulo={TITULO} subtitulo={SUBTITULO} />
              <div className="px-6 print:px-0">
                <EmptyState
                  title="Nenhuma Coleção com pendência de cadastro"
                  description="Todas as Coleções catalogadas têm o total de Cartas esperado."
                />
              </div>
            </>
          ) : (
            <DataTable>
              <DataTableHead>
                <tr>
                  <th colSpan={COLUNAS} className="p-0 text-left font-normal">
                    <RelatorioCabecalho titulo={TITULO} subtitulo={SUBTITULO} />
                  </th>
                </tr>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="pl-6 print:pl-0">Coleção</DataTableHeadCell>
                  <DataTableHeadCell align="center">Total esperado</DataTableHeadCell>
                  <DataTableHeadCell align="center">Cadastradas</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-6 last:pr-6 print:pr-0 print:last:pr-0">
                    Pendentes
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {itens.map((item, index) => (
                  <DataTableRow key={item.cardSetId} className={cn(index % 2 === 1 && "bg-[#F7F5ED]")}>
                    <DataTableCell className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0">
                      {item.cardSetCode} — {item.cardSetName}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                      {formatNumber(item.totalSetSize)}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                      {formatNumber(item.cardsCadastradas)}
                    </DataTableCell>
                    <DataTableCell
                      align="center"
                      className="py-1.5 pr-6 text-xs font-medium tabular-nums text-neutral-900 last:pr-6 print:pr-0 print:last:pr-0"
                    >
                      {formatNumber(item.cardsPendentes)}
                    </DataTableCell>
                  </DataTableRow>
                ))}
              </tbody>
            </DataTable>
          )}

          <RelatorioRodape />
        </RelatorioFolha>
      </PageContainer>
    </AppShell>
  );
}
