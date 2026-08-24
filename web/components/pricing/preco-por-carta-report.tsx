import { ImageOff, LineChart, Package, Triangle } from "lucide-react";
import Link from "next/link";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { Card } from "@/components/ui/card";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { StateBadge } from "@/components/catalogo/state-badge";
import { PriceHistoryChart, type PriceHistorySeries } from "@/components/pricing/price-history-chart";
import { PrecoPorCartaPeriodoFiltro } from "@/components/pricing/preco-por-carta-filtros";
import { cn } from "@/lib/utils";
import type { PricingReportCard, PricingReportCurrency } from "@/lib/pricing/queries";

const TITULO_IMPRESSAO = "Preço por Carta";
const SUBTITULO_IMPRESSAO = "Preço atual por fonte/variante e série temporal de uma Carta específica.";

// Mesmo mapa de `card-price-summary.tsx` (P12) — duplicado deliberadamente,
// não importado de lá: mesma decisão já registrada em
// `lib/pesquisa/format.ts` ("pequena duplicação de funções puras,
// preferível a acoplar" dois módulos que evoluem por pedidos diferentes de
// Fabrício). Rótulos técnicos nunca chegam à tela (pedido de Fabrício,
// 2026-08-18).
const PRINTING_LABEL_PT: Record<string, string> = {
  Normal: "Normal",
  Holofoil: "Holográfica",
  "Reverse Holofoil": "Holográfica reversa",
  Unlimited: "Ilimitada",
  "Unlimited Holofoil": "Ilimitada Holográfica",
  "1st Edition": "1ª Edição",
  "1st Edition Holofoil": "1ª Edição Holográfica",
};

const FX_STATUS_LABEL: Record<string, string> = {
  NATIVE: "Moeda nativa da fonte",
  CONVERTED: "Convertido",
  FX_RATE_UNAVAILABLE: "Câmbio indisponível",
  UNSUPPORTED_CONVERSION: "Conversão não suportada",
};

// Mesmo mapa de `historico-execucoes-table.tsx` (`SOURCE_CODE_LABEL`) —
// duplicado deliberadamente, mesma razão de `PRINTING_LABEL_PT` acima:
// "código técnico nunca chega à tela". Usado no gráfico/legenda/resumo de
// variação do Histórico de Preço (rodada de refinamento visual, 2026-08-23).
const SOURCE_CODE_LABEL: Record<string, string> = {
  JUSTTCG: "JustTCG",
};

function humanizeSourceCode(code: string): string {
  return SOURCE_CODE_LABEL[code] ?? code;
}

const dateFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

function translatePrintingLabel(label: string): string {
  return PRINTING_LABEL_PT[label] ?? label;
}

function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

function formatCollectorNumber(report: PricingReportCard): string {
  return `${report.card.collectorNumber.padStart(3, "0")}/${
    report.card.collectorTotal != null ? String(report.card.collectorTotal).padStart(3, "0") : "???"
  }`;
}

/** Detalhe de câmbio de uma linha de preço — `null` quando a fonte já cota na moeda selecionada (nada a explicar). */
function describeFxDetail(price: PricingReportCard["currentPrices"][number]): string | null {
  if (price.fxStatus === "NATIVE") return null;
  if (price.fxStatus === "CONVERTED" && price.fxRate !== null) {
    return `${formatMoney(price.priceNative, price.currencyNative)} · câmbio ${price.fxRate.toFixed(4)}`;
  }
  return FX_STATUS_LABEL[price.fxStatus] ?? price.fxStatus;
}

/** Observação mais recente entre as fontes com cotação — puro cálculo em cima do que já veio no RPC, nenhum fetch novo. */
function getLastObservedAt(prices: PricingReportCard["currentPrices"]): Date | null {
  if (prices.length === 0) return null;
  return new Date(Math.max(...prices.map((p) => new Date(p.observedAt).getTime())));
}

function groupHistoryBySeries(history: PricingReportCard["history"]): PriceHistorySeries[] {
  const bySeries = new Map<string, PriceHistorySeries>();
  for (const point of history) {
    const variantLabel = translatePrintingLabel(point.printingLabel);
    const sourceLabel = humanizeSourceCode(point.pricingSourceCode);
    // "Variante · Fonte" — mesma ordem já usada no resumo de variação abaixo
    // do gráfico e pedida explicitamente para legenda/tooltip na rodada de
    // refinamento visual (2026-08-23).
    const label = `${variantLabel} · ${sourceLabel}`;
    const key = `${point.pricingSourceId}-${point.printingLabel}`;
    let series = bySeries.get(key);
    if (!series) {
      series = { label, sourceCode: sourceLabel, variantLabel, points: [] };
      bySeries.set(key, series);
    }
    series.points.push({
      observedAt: point.observedAt,
      price: point.price,
      currencyCode: point.currencyCode,
      priceDisplay: point.priceDisplay,
      fxStatus: point.fxStatus,
    });
  }
  return Array.from(bySeries.values());
}

type SeriesDelta = {
  label: string;
  sourceCode: string;
  variantLabel: string;
  currencyCode: string;
  first: number;
  last: number;
  pct: number;
};

/**
 * Variação (inicial → final, percentual) por série no período exibido —
 * Fase 4 do incremento ECharts (ADR-033, 2026-08-23), calculada só em cima de
 * `history`/`chartSeries` já carregado no frontend, sem RPC/fetch novo.
 * Substitui a antiga `computeSingleSeriesDelta` (que só cobria o caso de
 * exatamente 1 série): agora toda série com 2+ pontos ganha sua própria
 * variação, "sem misturar variantes" — pedido explícito de Fabrício. Séries
 * com menos de 2 pontos são omitidas (nada a comparar), nunca aparecem como
 * "0%" — omitir é mais honesto do que inventar uma variação sem base.
 *
 * v2 (2026-08-23, migration 3948, aprovado por Fabrício) — passa a usar
 * `priceDisplay` (já convertido para `currency`, taxa PTAX na data de cada
 * ponto) em vez do `price` nativo. Pontos sem conversão disponível
 * (`priceDisplay === null` — `FX_RATE_UNAVAILABLE`/`UNSUPPORTED_CONVERSION`)
 * são excluídos do cálculo de primeiro/último ponto, pela mesma razão de
 * "nada a comparar" já aplicada a séries curtas — nunca mistura nativo com
 * convertido na mesma variação. `currency` (fixo, `report.currency`) é o
 * mesmo para toda a série já que todo ponto plotável está na mesma moeda de
 * exibição.
 */
function computeSeriesDeltas(chartSeries: PriceHistorySeries[], currency: PricingReportCurrency): SeriesDelta[] {
  const deltas: SeriesDelta[] = [];
  for (const series of chartSeries) {
    const plottable = series.points.filter((p) => p.priceDisplay !== null);
    const sorted = [...plottable].sort((a, b) => new Date(a.observedAt).getTime() - new Date(b.observedAt).getTime());
    if (sorted.length < 2) continue;
    const first = sorted[0];
    const last = sorted[sorted.length - 1];
    if (!first || !last || first.priceDisplay === null || last.priceDisplay === null) continue;
    const pct = first.priceDisplay !== 0 ? ((last.priceDisplay - first.priceDisplay) / first.priceDisplay) * 100 : 0;
    deltas.push({
      label: series.label,
      sourceCode: series.sourceCode,
      variantLabel: series.variantLabel,
      currencyCode: currency,
      first: first.priceDisplay,
      last: last.priceDisplay,
      pct,
    });
  }
  return deltas;
}

/**
 * Relatório "Preço por Carta" (Bloco 5, migration 3943) — puramente
 * apresentacional: recebe o contrato já pronto de
 * `admin_get_pricing_report_card` mais `imageUrl`/`cardSetLogoUrl` (leituras
 * pontuais já resolvidas em `page.tsx`), nenhuma agregação/cálculo além de
 * formatação e da variação de período por série (nunca mistura variantes,
 * ver `computeSeriesDeltas`). Estados sem cotação (preço atual e histórico)
 * são sinalizados separadamente — a ausência de uma fonte nunca vira "zero"
 * nem some silenciosamente da lista.
 *
 * v3 (2026-08-23, recomposição visual "relatório premium" aprovada por
 * Fabrício, depois de v2 ter sido considerada insuficiente — "não quero
 * microajustes") — mudança estrutural, não só tipográfica: Hero, Preços e
 * Histórico deixam de ser 3 `Card`s soltos e viram 3 seções de um único
 * `Card`, separadas por `border-t` (parecem partes do mesmo relatório, não
 * módulos colados). A lista de preços deixa de ser uma `DataTable` com
 * cabeçalho de colunas e vira uma lista de "cotação" (sem header, Preço com
 * o maior peso tipográfico, Variante como identificação secundária logo
 * acima, Fonte/câmbio/Data como metadado menor) — mesma decisão de não
 * escolher um "preço principal" único, só uma hierarquia de leitura por
 * linha.
 *
 * v4 (2026-08-23, recomposição "Carta | Histórico de Preço" aprovada por
 * Fabrício, pós-migração para Apache ECharts/ADR-033) — a primeira dobra
 * deixa de ser um Hero alto (imagem + texto) seguido, bem abaixo, por um
 * gráfico isolado, e vira uma única faixa em grid de duas colunas: Carta
 * (~30%) | Histórico de Preço (~70%) — "CARTA | EVOLUÇÃO DE MERCADO" já na
 * primeira dobra, sem vazio lateral. Logo do Set sai da área principal (só
 * segue existindo no cabeçalho da folha impressa, via
 * `PrecoPorCartaPrintFolha`/`RelatorioCabecalho` — não removida do produto,
 * só desta área). Os presets de período (30/90/180/365) saem da barra de
 * filtros do topo (`preco-por-carta-filtros.tsx`) e passam a viver no
 * cabeçalho do gráfico (`PrecoPorCartaPeriodoFiltro`) — controle da análise,
 * não do formulário de busca. "Preços atuais" continua como seção própria,
 * agora em segunda linha de largura total (não fundida com o gráfico —
 * pedido explícito: fotografia do valor agora vs. comportamento no período
 * são conceitos diferentes).
 *
 * v5 (2026-08-23) — "Última observação" sai do bloco de identificação da
 * carta (redundante: Histórico de Preço já comunica temporalidade, tooltip
 * do gráfico mostra datas, e cada linha de "Preços atuais" já tem sua
 * própria data). Removida sem substituição — o espaço só compacta o bloco,
 * não ganha outro dado. `getLastObservedAt` continua em uso por
 * `PrecoPorCartaPrintFolha` (folha impressa não foi tocada neste pedido).
 */
export function PrecoPorCartaReport({ report, imageUrl }: { report: PricingReportCard; imageUrl: string | null }) {
  const chartSeries = groupHistoryBySeries(report.history);
  const seriesDeltas = computeSeriesDeltas(chartSeries, report.currency);

  return (
    <Card className="overflow-hidden">
      {/* Primeira área — Carta | Histórico de Preço, grid no desktop;
          empilha em mobile (carta primeiro, depois o gráfico).
          v6 (2026-08-23): `lg:gap-4` (era `gap-6`) — menos espaço lateral
          entre a carta e o gráfico, pedido explícito para "ampliar o
          tamanho da carta".
          v7 (2026-08-23) — coluna esquerda deixa de ser `minmax(0,30%)`
          (percentual do container, independente do conteúdo) e vira
          `280px` fixo — a largura real da carta (imagem `max-w-[260px]` +
          folga). Com percentual, em telas largas a coluna sobrava bem mais
          que os 260px da imagem, deixando um vão morto entre a carta e o
          início do gráfico; como a coluna direita já é `1fr`, apertar a
          esquerda no tamanho real do conteúdo empurra esse espaço sobrando
          direto para o gráfico — "zerar o espaço vazio" pedido por
          Fabrício, sem precisar mexer no gráfico em si. */}
      <div className="grid gap-5 p-4 sm:p-6 lg:grid-cols-[280px_1fr] lg:gap-4">
        {/* Coluna esquerda — bloco da carta. v6: nome/Set migram para o
            topo (acima da imagem, pedido explícito de Fabrício); imagem
            maior (era `max-w-[200px]`); condição/moeda + CTA continuam
            abaixo da carta. */}
        <div className="space-y-2.5">
          <div className="space-y-0.5 text-center sm:text-left">
            {!report.card.isActive && (
              <div className="flex justify-center sm:justify-start">
                <StateBadge tone="muted">Inativa</StateBadge>
              </div>
            )}
            <h2 className="text-xl font-bold leading-tight text-foreground">{report.card.name}</h2>
            <p className="text-xs text-muted-foreground">
              {report.card.cardSetName} ({report.card.cardSetCode}) · {formatCollectorNumber(report)}
            </p>
          </div>

          <div className="mx-auto w-44 sm:mx-0 sm:w-full sm:max-w-[260px]">
            {imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element -- URL pública do bucket card-front, dimensão variável por Card Set
              <img
                src={imageUrl}
                alt={report.card.name}
                className="aspect-[63/88] w-full rounded-lg border border-border object-cover shadow-subtle"
              />
            ) : (
              <div className="flex aspect-[63/88] w-full flex-col items-center justify-center gap-1.5 rounded-lg border border-dashed border-border bg-surface-muted text-muted-foreground">
                <ImageOff className="h-6 w-6" aria-hidden="true" />
                <span className="text-[10px]">Sem imagem</span>
              </div>
            )}
          </div>

          <div className="space-y-1.5 text-center sm:text-left">
            <div className="flex flex-wrap items-center justify-center gap-x-3 gap-y-1 text-xs text-muted-foreground sm:justify-start">
              <span>
                Condição <span className="font-medium text-foreground">{report.condition.name}</span>
              </span>
              <span>
                Moeda <span className="font-medium text-foreground">{report.currency}</span>
              </span>
            </div>

            <Link
              href={`/pricing/relatorios/valor-por-set?set=${report.card.cardSetId}`}
              className="inline-flex items-center gap-1 pt-1 text-xs font-medium text-primary-ink hover:underline"
            >
              <Package className="h-3 w-3" aria-hidden="true" />
              Ver valor do Set {report.card.cardSetCode}
            </Link>
          </div>
        </div>

        {/* Coluna direita — Histórico de Preço, elemento analítico
            principal da tela. Período migrou para cá (ver v4 acima):
            cabeçalho do gráfico concentra título + presets, sem repetir
            controle em duas áreas. Resumo por série (Fase 4) fica logo
            abaixo, visualmente preso ao gráfico — não é uma terceira seção. */}
        <div className="min-w-0">
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-1.5">
              <LineChart className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
              <p className="text-sm font-semibold text-foreground">Histórico de Preço</p>
              <span className="text-xs text-muted-foreground">· últimos {report.historyDays} dias</span>
            </div>
            <PrecoPorCartaPeriodoFiltro historyDays={report.historyDays} />
          </div>
          {chartSeries.length === 0 ? (
            <EmptyState title="Sem histórico no período selecionado" description="Amplie o período ou aguarde novas observações." />
          ) : (
            <>
              <PriceHistoryChart series={chartSeries} currency={report.currency} height={320} />
              {seriesDeltas.length > 0 && (
                // Faixa analítica compacta (item 10 do refinamento visual,
                // 2026-08-23) — não é mais uma "tabela burocrática": hierarquia
                // agora é preço atual (maior peso) → variação % → variação
                // absoluta → variante/fonte (contexto, menor peso). O valor
                // inicial (`d.first`) deixou de ser exibido isoladamente —
                // continua implícito na variação absoluta/percentual, sem
                // perder informação.
                <div className="mt-3 divide-y divide-border/70 overflow-hidden rounded-lg border border-border/70 bg-surface-muted/40">
                  {seriesDeltas.map((d) => {
                    const deltaAbs = d.last - d.first;
                    const tone = d.pct > 0 ? "text-success" : d.pct < 0 ? "text-destructive" : "text-muted-foreground";
                    return (
                      <div key={d.label} className="flex items-center justify-between gap-3 px-3 py-2 text-xs">
                        <span className="min-w-0 truncate text-muted-foreground">
                          {d.variantLabel} <span className="opacity-70">· {d.sourceCode}</span>
                        </span>
                        <span className="flex shrink-0 items-baseline gap-2.5 tabular-nums">
                          <span className="text-sm font-semibold text-foreground">{formatMoney(d.last, d.currencyCode)}</span>
                          {/* Pill de variação (2026-08-23, pedido explícito de
                              Fabrício com referência visual anexada): triângulo
                              sólido + fundo tintado na cor da série, mesmas
                              cores `success`/`destructive` já usadas em
                              `badge.tsx`/`state-badge.tsx` — não inventa nova
                              paleta. Sem variação real (pct === 0, caso raro)
                              cai para o texto neutro anterior, sem pill nem
                              triângulo — não há "alta" nem "queda" pra indicar. */}
                          {d.pct !== 0 ? (
                            <span
                              className={cn(
                                "inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 font-semibold leading-none",
                                d.pct > 0
                                  ? "border-success/40 bg-success/10 text-success"
                                  : "border-destructive/40 bg-destructive/10 text-destructive dark:text-destructive-foreground",
                              )}
                            >
                              <Triangle
                                className={cn("h-2 w-2 shrink-0", d.pct < 0 && "rotate-180")}
                                fill="currentColor"
                                strokeWidth={0}
                                aria-hidden="true"
                              />
                              {d.pct > 0 ? "+" : ""}
                              {d.pct.toFixed(1)}%
                            </span>
                          ) : (
                            <span className={cn("font-semibold", tone)}>{d.pct.toFixed(1)}%</span>
                          )}
                          <span className={cn("hidden font-medium sm:inline", tone)}>
                            {deltaAbs > 0 ? "+" : ""}
                            {formatMoney(deltaAbs, d.currencyCode)}
                          </span>
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* Segunda área — Preços atuais, largura total. Lista de "cotação",
          sem cabeçalho de colunas: Preço com o maior peso tipográfico,
          Variante identifica, Fonte/câmbio/Data são metadado — hierarquia
          fixa pedida por Fabrício (1. Variante, 2. Preço, 3. Fonte/moeda
          nativa, 4. câmbio, 5. data), inalterada desde v3. */}
      <div className="border-t border-border/70 p-4 sm:p-6">
        <div className="mb-1.5 flex items-center justify-between">
          <p className="text-sm font-semibold text-foreground">Preços atuais</p>
          {report.currentPrices.length > 0 && (
            <span className="text-xs text-muted-foreground">
              {report.currentPrices.length} {report.currentPrices.length === 1 ? "cotação" : "cotações"}
            </span>
          )}
        </div>
        {report.currentPrices.length === 0 ? (
          <EmptyState
            title="Sem cotação disponível"
            description={`Nenhuma fonte tem preço confirmado para ${report.condition.name} em ${report.currency}.`}
          />
        ) : (
          <ul className="divide-y divide-border/70">
            {report.currentPrices.map((price, index) => {
              const fxDetail = describeFxDetail(price);
              return (
                <li
                  key={`${price.pricingSourceId}-${price.printingLabel}-${index}`}
                  className="flex items-center justify-between gap-4 py-2.5"
                >
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-foreground">{translatePrintingLabel(price.printingLabel)}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {price.pricingSourceCode}
                      {fxDetail ? ` · ${fxDetail}` : ""}
                    </p>
                  </div>
                  <div className="shrink-0 text-right">
                    {price.priceDisplay !== null ? (
                      <p className="text-xl font-bold tabular-nums text-foreground">
                        {formatMoney(price.priceDisplay, report.currency)}
                      </p>
                    ) : (
                      <p className="text-sm font-normal text-muted-foreground">Sem cotação em {report.currency}</p>
                    )}
                    <p className="text-[11px] text-muted-foreground">{dateFormatter.format(new Date(price.observedAt))}</p>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </Card>
  );
}

/**
 * Folha imprimível de "Preço por Carta" — requisito transversal da Central
 * de Relatórios (2026-08-22): mesmo mecanismo já adotado nos 8 relatórios do
 * Catálogo Editorial (`RelatorioFolha`/`RelatorioCabecalho`/`RelatorioRodape`,
 * `window.print()` via `RelatorioPrintButton` no `PageHeader`), sem CSS de
 * impressão paralelo. Fica `hidden print:block` — nunca aparece na tela, só
 * no preview/saída de impressão — enquanto o dashboard interativo
 * (`PrecoPorCartaReport`) recebe `print:hidden` no ponto de uso
 * (`page.tsx`). Consome o mesmo `report`/`imageUrl`/`cardSetLogoUrl` já
 * resolvidos para a tela — nenhuma chamada extra, então a impressão reflete
 * exatamente condição/moeda/período selecionados no momento do clique em
 * Imprimir. Reaproveita os mesmos helpers de formatação de
 * `PrecoPorCartaReport` (nenhuma duplicação de lógica de apresentação).
 *
 * v3 (2026-08-23) — espelha a mesma reestruturação em seções da tela
 * (identificação/preços/histórico com divisores, sem virar 3 componentes
 * separados) e ganha a mesma variação de período no cabeçalho do gráfico,
 * calculada com o mesmo helper — nenhuma solução paralela de cálculo.
 */
export function PrecoPorCartaPrintFolha({
  report,
  imageUrl,
  cardSetLogoUrl,
}: {
  report: PricingReportCard;
  imageUrl: string | null;
  cardSetLogoUrl: string | null;
}) {
  const chartSeries = groupHistoryBySeries(report.history);
  const identificacaoCarta = `${report.card.name} · ${formatCollectorNumber(report)}`;
  const lastObservedAt = getLastObservedAt(report.currentPrices);
  const seriesDeltas = computeSeriesDeltas(chartSeries, report.currency);

  return (
    <div className="hidden print:block">
      <RelatorioFolha>
        <RelatorioCabecalho
          titulo={TITULO_IMPRESSAO}
          subtitulo={SUBTITULO_IMPRESSAO}
          identificacaoColecao={identificacaoCarta}
          colecaoLogoUrl={cardSetLogoUrl}
        />

        <div className="space-y-3 px-6 pb-6 print:px-0">
          <div className="flex items-center gap-3 border-b border-neutral-200 pb-2">
            {imageUrl && (
              // eslint-disable-next-line @next/next/no-img-element -- folha impressa, sem otimização Next Image
              <img
                src={imageUrl}
                alt={report.card.name}
                className="aspect-[63/88] w-16 shrink-0 rounded border border-neutral-300 object-cover"
              />
            )}
            <div className="min-w-0 flex-1 space-y-0.5">
              {/* Logo do Set já aparece no cabeçalho compartilhado (`RelatorioCabecalho`,
                  prop `colecaoLogoUrl`) — não duplicado aqui. Ordem de identificação
                  pedida por Fabrício (2026-08-23): nome em destaque primeiro, depois
                  número da carta, depois o Set — Condição/Moeda/Histórico/Última
                  observação continuam por último, inalterados. */}
              <p className="text-sm font-semibold text-neutral-900">{report.card.name}</p>
              <span className="block text-[10px] text-neutral-500">{formatCollectorNumber(report)}</span>
              <span className="block text-[10px] text-neutral-500">
                {report.card.cardSetName} ({report.card.cardSetCode})
                {!report.card.isActive ? " · Inativa" : ""}
              </span>
              <span className="block text-[10px] text-neutral-500">
                Condição {report.condition.name} · Moeda {report.currency} · Histórico {report.historyDays} dias
                {lastObservedAt ? ` · Última observação ${dateFormatter.format(lastObservedAt)}` : ""}
              </span>
            </div>
          </div>

          {report.currentPrices.length === 0 ? (
            <p className="text-xs text-neutral-500">
              Nenhuma fonte tem preço confirmado para {report.condition.name} em {report.currency}.
            </p>
          ) : (
            // Padronizado nos primitives `DataTable` (2026-08-23, pedido de
            // Fabrício, mesmo modelo já aprovado em "Cobertura Geral" —
            // `cobertura-geral/page.tsx`): cabeçalho uppercase/tracking-wide
            // com rótulos centralizados (exceto a 1ª coluna, que segue o
            // sentido natural de leitura à esquerda — mesmo padrão do
            // modelo) e zebra striping (`bg-[#F7F5ED]` nas linhas ímpares)
            // em vez da tabela crua anterior, sem esse tratamento.
            <DataTable className="text-[10px]">
              <DataTableHead>
                {/* Fundo na `tr` sozinho não é confiável em impressão (browsers
                    variam em como pintam o fundo da linha atrás dos gaps entre
                    `th` no modelo de borda "separate") — bug real reportado por
                    Fabrício (2026-08-23): só metade do cabeçalho ficava cinza.
                    Fix robusto: `bg-neutral-50` em CADA `th`, não na `tr`. */}
                <DataTableHeadRow className="border-neutral-200 text-[9px] text-neutral-500">
                  <DataTableHeadCell className="bg-neutral-50 py-1">Fonte</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                    Variante
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                    Preço ({report.currency})
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                    Câmbio
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                    Observado em
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {report.currentPrices.map((price, index) => (
                  <DataTableRow
                    key={`${price.pricingSourceId}-${price.printingLabel}-${index}`}
                    className={cn("border-neutral-100", index % 2 === 1 && "bg-[#F7F5ED]")}
                  >
                    <DataTableCell className="py-1 font-medium text-neutral-900">
                      {price.pricingSourceCode}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-neutral-700">
                      {translatePrintingLabel(price.printingLabel)}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 font-medium text-neutral-900">
                      {price.priceDisplay !== null ? (
                        formatMoney(price.priceDisplay, report.currency)
                      ) : (
                        <span className="font-normal text-neutral-500">Sem cotação em {report.currency}</span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-neutral-700">
                      {FX_STATUS_LABEL[price.fxStatus] ?? price.fxStatus}
                      {price.fxStatus === "CONVERTED" && price.fxRate !== null && (
                        <span className="block text-[9px] text-neutral-500">
                          {formatMoney(price.priceNative, price.currencyNative)} · taxa {price.fxRate.toFixed(4)}
                          {price.fxRateDate ? ` (${dateFormatter.format(new Date(price.fxRateDate))})` : ""}
                        </span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-neutral-700">
                      {dateFormatter.format(new Date(price.observedAt))}
                    </DataTableCell>
                  </DataTableRow>
                ))}
              </tbody>
            </DataTable>
          )}

          <div className="space-y-1.5 border-t border-neutral-200 pt-2">
            <p className="text-[10px] font-medium text-neutral-700">Histórico de Preço — últimos {report.historyDays} dias</p>
            {chartSeries.length === 0 ? (
              <p className="text-[10px] text-neutral-500">Sem histórico no período selecionado.</p>
            ) : (
              <>
                {/* Altura aumentada de 180 para 260 (pedido de Fabrício,
                    2026-08-23) — a folha tinha espaço vertical de sobra
                    abaixo do conteúdo; largura continua fixa via
                    `PRINT_CHART_WIDTH_PX` em `mmkyu-chart.tsx`. */}
                <PriceHistoryChart series={chartSeries} printSafe currency={report.currency} height={260} />
                {seriesDeltas.length > 0 && (
                  // Mesma hierarquia da tela (item 10 do refinamento visual,
                  // 2026-08-23): preço atual → variação % → variação absoluta
                  // → variante/fonte. Valor inicial isolado removido, mesma
                  // razão da tela. Padronizado no mesmo `DataTable` da tabela
                  // acima (cabeçalho adicionado — antes não tinha nenhum).
                  <DataTable className="text-[10px]">
                    <DataTableHead>
                      <DataTableHeadRow className="border-neutral-200 text-[9px] text-neutral-500">
                        <DataTableHeadCell className="bg-neutral-50 py-1">Variante</DataTableHeadCell>
                        <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                          Preço ({report.currency})
                        </DataTableHeadCell>
                        <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                          Variação
                        </DataTableHeadCell>
                        <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                          Δ ({report.currency})
                        </DataTableHeadCell>
                      </DataTableHeadRow>
                    </DataTableHead>
                    <tbody>
                      {seriesDeltas.map((d, index) => {
                        const deltaAbs = d.last - d.first;
                        return (
                          <DataTableRow key={d.label} className={cn("border-neutral-100", index % 2 === 1 && "bg-[#F7F5ED]")}>
                            <DataTableCell className="py-1 text-neutral-700">
                              {d.variantLabel} <span className="text-neutral-500">· {d.sourceCode}</span>
                            </DataTableCell>
                            <DataTableCell align="center" className="py-1 font-medium text-neutral-900">
                              {formatMoney(d.last, d.currencyCode)}
                            </DataTableCell>
                            <DataTableCell align="center" className="py-1 font-medium text-neutral-900">
                              {d.pct > 0 ? "+" : ""}
                              {d.pct.toFixed(1)}%
                            </DataTableCell>
                            <DataTableCell align="center" className="py-1 text-neutral-500">
                              {deltaAbs > 0 ? "+" : ""}
                              {formatMoney(deltaAbs, d.currencyCode)}
                            </DataTableCell>
                          </DataTableRow>
                        );
                      })}
                    </tbody>
                  </DataTable>
                )}
              </>
            )}
          </div>
        </div>

        <RelatorioRodape />
      </RelatorioFolha>
    </div>
  );
}
