import { BookOpen, Layers } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTable, DataTableCell, DataTableHead, DataTableHeadCell, DataTableHeadRow, DataTableRow } from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getRelatorioCoberturaVariantes } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const TITULO = "Cobertura de Card Variant";
const SUBTITULO = "Cards com pelo menos uma Card Variant cadastrada, por Coleção.";
const COLUNAS = 4;

/**
 * Relatório "Cobertura de Card Variant" (Central de Relatórios) — primeiro
 * incremento técnico do bloco Card Variant (ADR-028, Query 2135,
 * 2026-08-14). Uma linha por Coleção, direto de
 * catalog_card_set_variant_coverage — mesmo layout já aprovado do relatório
 * "Cobertura Geral" (`cobertura-geral/page.tsx`), sem seletor, tabela
 * cruzando todas as Coleções de uma vez. Percentual = cardsComVariante /
 * cardsCadastradas, calculado aqui (não em SQL), mesmo padrão dos demais
 * relatórios de cobertura.
 *
 * Esta tela é só leitura — não cria nem edita nenhuma Card Variant (ADR-028:
 * escrita continua exclusiva de administradores, ainda sem CRUD
 * implementado; usuários finais nunca criam/alteram variantes).
 */
export default async function RelatorioCoberturaVariantesPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const itens = await getRelatorioCoberturaVariantes(supabase);

  const totalCadastradas = itens.reduce((soma, item) => soma + item.cardsCadastradas, 0);
  const totalComVariante = itens.reduce((soma, item) => soma + item.cardsComVariante, 0);
  const totalSemVariante = itens.reduce((soma, item) => soma + item.cardsSemVariante, 0);
  const percentualGeral = totalCadastradas > 0 ? Math.round((totalComVariante / totalCadastradas) * 100) : 0;

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <Layers className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
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
                  <DataTableHeadCell align="center">Cadastradas</DataTableHeadCell>
                  <DataTableHeadCell align="center">Com Variant</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-6 last:pr-6 print:pr-0 print:last:pr-0">
                    Cobertura
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {itens.map((item, index) => {
                  const percentual =
                    item.cardsCadastradas > 0 ? Math.round((item.cardsComVariante / item.cardsCadastradas) * 100) : 0;
                  return (
                    <DataTableRow key={item.cardSetId} className={cn(index % 2 === 1 && "bg-[#F7F5ED]")}>
                      <DataTableCell className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0">
                        {item.cardSetCode} — {item.cardSetName}
                      </DataTableCell>
                      <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                        {formatNumber(item.cardsCadastradas)}
                      </DataTableCell>
                      <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                        {formatNumber(item.cardsComVariante)}
                      </DataTableCell>
                      <DataTableCell
                        align="center"
                        className="py-1.5 pr-6 text-xs font-medium tabular-nums text-neutral-900 last:pr-6 print:pr-0 print:last:pr-0"
                      >
                        {percentual}%
                      </DataTableCell>
                    </DataTableRow>
                  );
                })}
                <tr className="border-t-2 border-neutral-400 bg-[#F0EEE3] font-semibold">
                  <DataTableCell className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0">Total</DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totalCadastradas)}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totalComVariante)}
                  </DataTableCell>
                  <DataTableCell
                    align="center"
                    className="py-1.5 pr-6 text-xs tabular-nums text-neutral-900 last:pr-6 print:pr-0 print:last:pr-0"
                  >
                    {percentualGeral}%
                  </DataTableCell>
                </tr>
              </tbody>
            </DataTable>
          )}

          {itens.length > 0 && (
            <p className="px-6 pb-4 text-xs text-muted-foreground print:px-0">
              {formatNumber(totalSemVariante)} Cards ainda sem nenhuma Card Variant cadastrada, na soma de todas as
              Coleções.
            </p>
          )}

          <RelatorioRodape />
        </RelatorioFolha>
      </PageContainer>
    </AppShell>
  );
}
