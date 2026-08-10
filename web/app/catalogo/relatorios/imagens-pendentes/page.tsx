import { BookOpen, ImageOff } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTable, DataTableCell, DataTableHead, DataTableHeadCell, DataTableHeadRow, DataTableRow } from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getRelatorioImagensPendentes } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const TITULO = "Imagens pendentes por Coleção";
const SUBTITULO = "Coleções com Cartas cadastradas sem imagem canônica em nenhum idioma ativo.";
const COLUNAS = 4;

/**
 * Relatório "Imagens pendentes por Coleção" (Central de Relatórios, V1
 * aprovada por Fabrício, 2026-08-09) — Coleções com pelo menos uma Carta
 * cadastrada sem imagem canônica em nenhum idioma ativo
 * (`cards_cadastradas - cards_com_imagem_algum_idioma > 0`,
 * `catalog_card_set_metrics`). Sem seletor — tabela cruzando todas as
 * Coleções de uma vez.
 *
 * Visual alinhado à baseline do Checklist por Coleção (2026-08-09, ver
 * `cartas-pendentes/page.tsx` para o detalhamento do padrão: `RelatorioFolha`
 * + `RelatorioCabecalho` dentro do `<thead>` da `DataTable`, `PageHeader`
 * com `print:hidden`).
 *
 * Linha de totais (2026-08-09, mesmo dia, rodada seguinte) — somatório de
 * Cadastradas/Com imagem/Sem imagem, mesmo padrão de `qualidade/page.tsx` e
 * `cobertura-geral/page.tsx`.
 */
export default async function RelatorioImagensPendentesPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const itens = await getRelatorioImagensPendentes(supabase);

  const totais = itens.reduce(
    (acc, item) => ({
      cardsCadastradas: acc.cardsCadastradas + item.cardsCadastradas,
      cardsComImagem: acc.cardsComImagem + item.cardsComImagem,
      cardsSemImagem: acc.cardsSemImagem + item.cardsSemImagem,
    }),
    { cardsCadastradas: 0, cardsComImagem: 0, cardsSemImagem: 0 },
  );

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <ImageOff className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
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
                  title="Nenhuma Coleção com pendência de imagem"
                  description="Todas as Cartas cadastradas têm imagem canônica em pelo menos um idioma ativo."
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
                  <DataTableHeadCell align="center">Cadastradas</DataTableHeadCell>
                  <DataTableHeadCell align="center">Com imagem</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-6 last:pr-6 print:pr-0 print:last:pr-0">
                    Sem imagem
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
                      {formatNumber(item.cardsCadastradas)}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-500">
                      {formatNumber(item.cardsComImagem)}
                    </DataTableCell>
                    <DataTableCell
                      align="center"
                      className="py-1.5 pr-6 text-xs font-medium tabular-nums text-neutral-900 last:pr-6 print:pr-0 print:last:pr-0"
                    >
                      {formatNumber(item.cardsSemImagem)}
                    </DataTableCell>
                  </DataTableRow>
                ))}
                <tr className="border-t-2 border-neutral-400 bg-[#F0EEE3] font-semibold">
                  <DataTableCell className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0">Total</DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totais.cardsCadastradas)}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totais.cardsComImagem)}
                  </DataTableCell>
                  <DataTableCell
                    align="center"
                    className="py-1.5 pr-6 text-xs tabular-nums text-neutral-900 last:pr-6 print:pr-0 print:last:pr-0"
                  >
                    {formatNumber(totais.cardsSemImagem)}
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
