import { BookOpen, PieChart } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTable, DataTableCell, DataTableHead, DataTableHeadCell, DataTableHeadRow, DataTableRow } from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getRelatorioCoberturaGeral } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const TITULO = "Cobertura Geral";
const SUBTITULO = "Cobertura de imagem por Coleção e idioma, em uma única tabela.";
const COLUNAS = 5;

/** Mesmo mapa de nomes de idioma já usado em `visao-geral-stats.tsx`/`importar-imagens`. */
const LANGUAGE_DISPLAY_NAME: Record<string, string> = {
  en: "Inglês",
  "pt-BR": "Português",
};

/**
 * Relatório "Cobertura Geral" (Central de Relatórios, V1 aprovada por
 * Fabrício, 2026-08-09) — uma linha por (Coleção, idioma ativo), de
 * `catalog_card_set_image_coverage`, percentual = cardsComImagem /
 * cardsCadastradas (mesma fórmula já usada na Visão Geral e no hub de Card
 * Set, nunca uma segunda definição). Sem seletor — tabela cruzando todas as
 * Coleções de uma vez.
 *
 * Visual alinhado à baseline do Checklist por Coleção (2026-08-09, ver
 * `cartas-pendentes/page.tsx` para o detalhamento do padrão).
 */
export default async function RelatorioCoberturaGeralPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const itens = await getRelatorioCoberturaGeral(supabase);

  // Soma literal das linhas exibidas (pedido de Fabrício) — cada linha é um
  // par (Coleção, idioma), então uma Coleção com 2 idiomas ativos entra 2x
  // no somatório de `cardsCadastradas` (é o mesmo valor de
  // `catalog_card_set_metrics` repetido por linha de idioma, não um valor
  // por idioma). O percentual geral resultante responde "de todas as
  // combinações (Carta, idioma) possíveis nesta tabela, quantas têm
  // imagem" — não "quantas Cartas distintas têm imagem em algum idioma"
  // (esse número já existe em "Imagens pendentes por Coleção").
  const totalCadastradas = itens.reduce((soma, item) => soma + item.cardsCadastradas, 0);
  const totalComImagem = itens.reduce((soma, item) => soma + item.cardsComImagem, 0);
  const percentualGeral = totalCadastradas > 0 ? Math.round((totalComImagem / totalCadastradas) * 100) : 0;

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <PieChart className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
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
                {/* Cor literal, não token (2026-08-23, fix reportado por Fabrício):
                    `DataTableHeadRow` usa `text-muted-foreground`/`bg-surface-muted`
                    por padrão — tokens que mudam com o tema do app. Mas
                    `RelatorioFolha` é fundo branco fixo independente de dark
                    mode (ver docstring de `relatorio-folha.tsx`); herdar o
                    token fazia o cabeçalho ficar acastanhado/oliva quando o
                    app estava em dark mode, em vez do cinza neutro do
                    padrão. Mesma correção replicada nos outros 5 relatórios
                    da Central e em `preco-por-carta-report.tsx`.

                    Fix 2 (mesmo dia): fundo estava na `tr`, mas Fabrício
                    reportou só metade do cabeçalho ficando cinza na
                    impressão — `background-color` em `<tr>` não é confiável
                    entre navegadores no modelo de borda "separate" (gaps
                    entre `th` mostram o fundo da tabela, não da linha). Fix
                    robusto: `bg-neutral-50` em CADA `th`, não na `tr`. */}
                <DataTableHeadRow className="border-neutral-200 text-neutral-500">
                  <DataTableHeadCell className="bg-neutral-50 pl-6 print:pl-0">Coleção</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="bg-neutral-50">
                    Idioma
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="bg-neutral-50">
                    Cadastradas
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="bg-neutral-50">
                    Com imagem
                  </DataTableHeadCell>
                  <DataTableHeadCell
                    align="center"
                    className="bg-neutral-50 pr-6 last:pr-6 print:pr-0 print:last:pr-0"
                  >
                    Cobertura
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {itens.map((item, index) => {
                  const percentual =
                    item.cardsCadastradas > 0 ? Math.round((item.cardsComImagem / item.cardsCadastradas) * 100) : 0;
                  return (
                    <DataTableRow key={`${item.cardSetId}-${item.languageCode}`} className={cn(index % 2 === 1 && "bg-[#F7F5ED]")}>
                      <DataTableCell className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0">
                        {item.cardSetCode} — {item.cardSetName}
                      </DataTableCell>
                      <DataTableCell align="center" className="py-1.5 text-xs text-neutral-500">
                        {LANGUAGE_DISPLAY_NAME[item.languageCode] ?? item.languageCode}
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
                        {percentual}%
                      </DataTableCell>
                    </DataTableRow>
                  );
                })}
                <tr className="border-t-2 border-neutral-400 bg-[#F0EEE3] font-semibold">
                  <DataTableCell colSpan={2} className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0">
                    Total
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totalCadastradas)}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1.5 text-xs tabular-nums text-neutral-900">
                    {formatNumber(totalComImagem)}
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

          <RelatorioRodape />
        </RelatorioFolha>
      </PageContainer>
    </AppShell>
  );
}
