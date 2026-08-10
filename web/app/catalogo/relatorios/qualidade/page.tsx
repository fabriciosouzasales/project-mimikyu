import { BookOpen, ShieldCheck } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTable, DataTableCell, DataTableHead, DataTableHeadCell, DataTableHeadRow, DataTableRow } from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getRelatorioQualidadeCatalogo } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const TITULO = "Qualidade do Catálogo";
const SUBTITULO = "Cadastro, imagem e cartas inativas — visão detalhada por Coleção, todas em uma tabela.";
const COLUNAS = 7;

/**
 * Relatório "Qualidade do Catálogo" (Central de Relatórios, V1 aprovada por
 * Fabrício, 2026-08-09) — uma linha por Coleção (TODAS, não só as com
 * pendência), cruzando as mesmas três lacunas estruturais já mostradas de
 * forma agregada em "Saúde do catálogo" na Visão Geral: pendência de
 * cadastro, pendência de imagem e cartas inativas. Único dos 6 relatórios
 * sem especificação prévia registrada — definição confirmada por Fabrício
 * antes da implementação, via pergunta direta.
 *
 * Visual alinhado à baseline do Checklist por Coleção (2026-08-09, ver
 * `cartas-pendentes/page.tsx` para o detalhamento do padrão).
 */
export default async function RelatorioQualidadePage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const itens = await getRelatorioQualidadeCatalogo(supabase);

  const totais = itens.reduce(
    (acc, item) => ({
      totalSetSize: acc.totalSetSize + item.totalSetSize,
      cardsCadastradas: acc.cardsCadastradas + item.cardsCadastradas,
      cardsPendentes: acc.cardsPendentes + item.cardsPendentes,
      cardsComImagem: acc.cardsComImagem + item.cardsComImagem,
      cardsSemImagem: acc.cardsSemImagem + item.cardsSemImagem,
      cardsInativas: acc.cardsInativas + item.cardsInativas,
    }),
    { totalSetSize: 0, cardsCadastradas: 0, cardsPendentes: 0, cardsComImagem: 0, cardsSemImagem: 0, cardsInativas: 0 },
  );

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer width="wide">
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <ShieldCheck className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
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
                <EmptyState title="Nenhuma Coleção catalogada" />
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
                  <DataTableHeadCell align="center">Pendentes</DataTableHeadCell>
                  <DataTableHeadCell align="center">Com imagem</DataTableHeadCell>
                  <DataTableHeadCell align="center">Sem imagem</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-6 last:pr-6 print:pr-0 print:last:pr-0">
                    Inativas
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
                    <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                      {formatNumber(item.cardsPendentes)}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                      {formatNumber(item.cardsComImagem)}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                      {formatNumber(item.cardsSemImagem)}
                    </DataTableCell>
                    <DataTableCell
                      align="center"
                      className="py-1.5 pr-6 text-xs tabular-nums text-neutral-500 last:pr-6 print:pr-0 print:last:pr-0"
                    >
                      {formatNumber(item.cardsInativas)}
                    </DataTableCell>
                  </DataTableRow>
                ))}
                <tr className="border-t-2 border-neutral-400 bg-[#F0EEE3] font-semibold">
                  <DataTableCell className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0">Total</DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totais.totalSetSize)}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totais.cardsCadastradas)}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totais.cardsPendentes)}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totais.cardsComImagem)}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totais.cardsSemImagem)}
                  </DataTableCell>
                  <DataTableCell
                    align="center"
                    className="py-1.5 pr-6 text-xs tabular-nums text-neutral-900 last:pr-6 print:pr-0 print:last:pr-0"
                  >
                    {formatNumber(totais.cardsInativas)}
                  </DataTableCell>
                </tr>
              </tbody>
            </DataTable>
          )}

          <RelatorioRodape />
        </RelatorioFolha>
      </PageContainer>
    </AppShell>
  );
}
