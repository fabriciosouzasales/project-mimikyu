"use client";

import * as echarts from "echarts/core";
import { LineChart } from "echarts/charts";
import { GridComponent, TooltipComponent, LegendComponent, DataZoomComponent } from "echarts/components";
import type { EChartsCoreOption } from "echarts/core";
import { MMKYUChart, useChartTokens } from "@/components/charts/mmkyu-chart";
import type { PricingReportFxStatus } from "@/lib/pricing/queries";

/**
 * Gráfico de Histórico de Preço — Apache ECharts (ADR-033, 2026-08-23),
 * substitui por completo o SVG manual anterior (v1-v3, ver histórico em
 * `docs/log.md`). Fase 3 do incremento aprovado por Fabrício.
 *
 * Imports seletivos deste gráfico especificamente — `LineChart` (único tipo
 * de série usado aqui), `GridComponent`/`TooltipComponent`/`LegendComponent`/
 * `DataZoomComponent` (únicos componentes usados). O `SVGRenderer` já é
 * registrado globalmente por `MMKYUChart` — não repetido aqui. Nenhum outro
 * gráfico do produto paga pelo custo destes módulos: cada tela registra só o
 * que a própria `option` usa (ver comentário de `mmkyu-chart.tsx`).
 *
 * MVP entregue (Fase 3): uma série por combinação fonte+variante; tooltip
 * rico com data/preço/variante/fonte/moeda por ponto; crosshair com rótulo
 * formatado nos dois eixos; ponto ativo (destaque de série no hover);
 * legenda interativa com show/hide por clique; último preço identificável
 * via rótulo no fim da linha (quando ≤4 séries, mesmo limite do gráfico
 * anterior — acima disso o rótulo lotaria a área útil); zoom/pan por
 * interação direta (`dataZoom: 'inside'`, sem slider visual — pedido
 * explícito de Fabrício "não adicionar slider visual nesta primeira
 * versão"); responsivo e com tema light/dark via `MMKYUChart`; SVG também
 * para impressão (`printSafe`, mesma convenção já usada no componente
 * anterior — cores fixas independente do tema ativo no clique de Imprimir).
 * Eixo Y sempre começa em zero — mesma decisão de design herdada do gráfico
 * anterior (nunca corta a base, evita exagerar visualmente uma variação
 * pequena).
 *
 * v2 (2026-08-23, migration 3948, aprovado por Fabrício) — plota
 * `priceDisplay` (já convertido para a moeda do relatório, taxa PTAX na data
 * de cada observação — nunca a cotação atual) em vez do `price` nativo por
 * ponto. `currency` deixa de ser fallback e passa a ser a moeda de exibição
 * de todo o gráfico (todo ponto plotado já está nela). Pontos sem conversão
 * disponível (`fxStatus` `FX_RATE_UNAVAILABLE`/`UNSUPPORTED_CONVERSION`) são
 * excluídos do traçado — "não inventar valor convertido" (pedido explícito
 * de Fabrício) — e contados numa nota abaixo do gráfico, nunca somem
 * silenciosamente. Preço nativo (`price`/`currencyCode`) some do traçado
 * principal mas continua disponível no tooltip como contexto secundário
 * quando o ponto foi de fato convertido.
 *
 * v3 (2026-08-23, rodada de refinamento visual "componente premium",
 * aprovada por Fabrício — "o problema agora não é estrutura de página, é
 * acabamento do componente analítico") — rodada exclusiva de acabamento,
 * sem tocar RPC/backend/layout de página:
 * - Eixo Y formatado na moeda selecionada (pt-BR, sem casas decimais
 *   desnecessárias) via `formatAxisTick`.
 * - Eixo X sem repetição visual de datas: `minInterval` de 1 dia +
 *   `axisLabel.hideOverlap` (a densidade maior/menor por período de
 *   30/90/180/365 dias já é o comportamento nativo do eixo `time` do
 *   ECharts — não precisou de lógica própria).
 * - Grid horizontal sutil (opacidade menor no dark, via `useChartTokens`),
 *   grid vertical removido.
 * - Paleta de série própria, fora da faixa de matiz do dourado de marca —
 *   nunca a paleta default do ECharts. (Revisada na v4, ver nota abaixo.)
 * - Crosshair de linha única (vertical), sem o rótulo pesado padrão do
 *   ECharts — a data já aparece no cabeçalho do tooltip.
 * - Tooltip redesenhado: cabeçalho de data, preço com maior peso, variante
 *   e fonte como contexto, preço nativo como nota secundária só quando
 *   `fxStatus === 'CONVERTED'`. Único elemento do gráfico que usa `hsl(var(
 *   --token))` diretamente no CSS — é o único elemento renderizado como
 *   `<div>` real (não SVG), então CSS custom properties resolvem
 *   corretamente e ficam sempre em sincronia com o tema ativo sem precisar
 *   de nenhum token JS. Todo o resto (eixo/legenda/crosshair/linhas) é
 *   desenhado pelo `SVGRenderer` como atributo de apresentação — não
 *   interpreta `var()`, por isso usa as cores já resolvidas de
 *   `useChartTokens` (`mmkyu-chart.tsx`).
 * - Legenda com `inactiveColor` explícito (estado desabilitado
 *   perceptível) e rótulo "Variante · Fonte" com nome de fonte humanizado
 *   (nunca o código técnico, ex. "JustTCG" em vez de "JUSTTCG" — computado
 *   em `preco-por-carta-report.tsx`, `humanizeSourceCode`).
 * - Último preço (`endLabel`) com offset vertical heurístico
 *   (`planEndLabelOffsets`) quando dois valores finais ficam muito
 *   próximos — nunca esconde um rótulo, só afasta.
 * - Pontos em repouso menores, com anel na cor da superfície; hover amplia
 *   e destaca a série ativa, as demais reduzem opacidade sem sumir.
 *
 * v4 (2026-08-23, rodada cirúrgica de identidade visual, aprovada por
 * Fabrício — "as cores das linhas e dos marcadores ainda não conversam com a
 * identidade visual do produto... hoje parecem genéricas demais") — troca
 * SOMENTE a paleta de série e o acabamento dos marcadores; tooltip,
 * crosshair, endLabel, resumo de variação e pills de período NÃO foram
 * tocados (fora de escopo explícito desta rodada):
 * - A paleta fixa/theme-independent da v3 (`SERIES_COLORS`, azul/verde/
 *   rosa/roxo/laranja/ciano) foi substituída por `buildSeriesPalette(tokens)`
 *   — série principal derivada de `tokens.primaryInkColor` (mesmo token
 *   `--primary-ink` que o design system já usa quando dourado precisa
 *   funcionar como cor de conteúdo, não de superfície), séries seguintes em
 *   tons "joia sofisticada" (petróleo/bronze/ameixa) com par claro/escuro
 *   próprio, escolhidos para harmonizar com o dourado sem repetir sua
 *   matiz. Paleta agora reage ao tema automaticamente via `useChartTokens`.
 * - Marcadores com anel mais espesso em repouso (`borderWidth: 2`, era 1.5)
 *   e leve glow na própria cor da série no hover/emphasis (`shadowBlur: 10`)
 *   — único realce extra, sutil, sem introduzir cor nova.
 *
 * v5 (2026-08-23, segunda rodada cirúrgica, aprovada por Fabrício —
 * referência visual anexada: linha fina, marcador discreto, grid quase
 * ausente) — refina linhas/marcadores/grid/legenda; tooltip, crosshair,
 * endLabel, pills e resumo por série continuam fora de escopo:
 * - Marcador invertido: a v4 preenchia o centro com a própria cor da série
 *   (`tokens.primaryInkColor` no claro é um âmbar profundo — pequeno demais
 *   para ler como "dourado", lia como "centro escuro", exatamente a queixa
 *   de Fabrício). Agora o anel é que carrega a cor da série — visível e
 *   inequívoco — e o centro é `tokens.surfaceColor` (claro/sutil). No hover,
 *   inverte: centro vira a cor cheia da série (leitura de "expansão"), anel
 *   passa a `surfaceColor`, com glow leve na cor da série.
 * - Marcador menor em repouso (`symbolSize: 4.5`, era 6) — mais discreto,
 *   deixa a linha como protagonista (pedido explícito).
 * - Linha com curvatura um pouco maior (`smooth: 0.3`, era 0.22) para leitura
 *   mais premium, ainda sem distorcer os pontos reais.
 * - Grid horizontal mais discreto (opacidade reduzida em ambos os temas,
 *   traço tracejado em vez de sólido) e `splitNumber: 4` (era o padrão do
 *   ECharts, 5) — menos linhas, hierarquia "dado em primeiro plano".
 * - Linha do eixo X com opacidade reduzida (infraestrutura em segundo
 *   plano); rótulos do eixo Y com leve espaçamento de letras.
 * - Legenda com indicador maior (`itemWidth/Height: 10`) e mais respiro
 *   entre itens (`itemGap: 22`) — melhor integração com a paleta refinada.
 *
 * v6 (2026-08-23, terceira rodada cirúrgica, aprovada por Fabrício) — dois
 * ajustes independentes, escopo ainda restrito a linhas/marcadores/grid:
 * - Fundo da área de plotagem com degredê sutil (`grid.backgroundColor`,
 *   gradiente linear vertical) — profundidade discreta sem prejudicar
 *   leitura de linhas/labels/tooltip. Só a área útil do gráfico, nunca a
 *   página. Ver comentário junto a `grid` em `buildOption`.
 * - Paleta de série trocada de dourado/petróleo/bronze/ameixa (v4) para
 *   verde/vermelho — pedido explícito de Fabrício: "usar as mesmas cores já
 *   usadas nos gráficos de barras do sistema", não mais uma paleta
 *   proprietária MMKYU. Ver `COR_SUCESSO`/`COR_FALHA` abaixo.
 *
 * v7 (2026-08-23, P0 de impressão, aprovado por Fabrício) — a folha impressa
 * de Preço por Carta chegou visualmente quebrada (gráfico não ocupava a área,
 * legenda com paginação "1/2"/setas, eixos cortados, grande espaço vazio).
 * Causa raiz identificada e corrigida em dois pontos, não só CSS:
 * - `mmkyu-chart.tsx`: `RelatorioFolha` monta com `hidden print:block` — o
 *   container do gráfico já existe no DOM com `display: none` no instante em
 *   que `echarts.init()` roda, então a instância trava dimensões 0×0 (ou
 *   fallback arbitrário) e nunca corrige sozinha (`ResizeObserver` não
 *   dispara em elementos sem caixa de layout). Fix: listener de
 *   `window.beforeprint` chamando `chart.resize()` — o navegador já aplicou
 *   o CSS de impressão nesse ponto, então o container tem dimensões reais.
 *   Ver comentário completo em `mmkyu-chart.tsx`.
 * - Este arquivo: `buildOption` passa a derivar um `printOption` do MESMO
 *   dataset (nenhuma RPC/agregação nova) quando `opts.printSafe` — tooltip/
 *   axisPointer removidos (`{ show: false }`), legenda `type: "scroll"` (com
 *   paginação) vira `type: "plain"` + `selectedMode: false` (nunca pagina,
 *   sem clique de show/hide), `dataZoom` omitido por completo, `animation:
 *   false` (evita capturar o snapshot de impressão no meio da transição de
 *   entrada). Séries/cores/eixos/legenda/último preço continuam os mesmos —
 *   só a camada de interação muda.
 */
echarts.use([LineChart, GridComponent, TooltipComponent, LegendComponent, DataZoomComponent]);

export type PriceHistoryPoint = {
  observedAt: string;
  /** Preço bruto na moeda nativa da fonte (ex.: USD) — mantido só como contexto (tooltip). */
  price: number;
  /** Moeda nativa do ponto — mantida só como contexto. */
  currencyCode: string;
  /**
   * Preço já convertido para a moeda de exibição do relatório (migration
   * 3948) — `null` quando `fxStatus` não é `NATIVE`/`CONVERTED`. É este o
   * valor plotado; pontos com `null` são filtrados antes de chegar à série.
   */
  priceDisplay: number | null;
  fxStatus: PricingReportFxStatus;
};

export type PriceHistorySeries = {
  /** Rótulo composto "Variante · Fonte" (fonte já humanizada) — pronto para exibição (legenda/tooltip). */
  label: string;
  /** Fonte já humanizada (ex.: "JustTCG") — nunca o código técnico bruto (`JUSTTCG`). */
  sourceCode: string;
  variantLabel: string;
  points: PriceHistoryPoint[];
};

/**
 * Paleta de série "verde/vermelho do sistema" (rodada 2026-08-23, pedido
 * explícito de Fabrício: "usar nas séries do gráfico as mesmas cores que já
 * usamos nos gráficos de barras do sistema... não inventar novas
 * tonalidades"). Substitui a paleta dourado/petróleo/bronze/ameixa da v4 —
 * abandono deliberado da identidade proprietária MMKYU nas linhas em favor
 * de consistência cromática com o resto do módulo Pricing.
 *
 * `COR_SUCESSO`/`COR_FALHA` são os MESMOS literais fixos hex/HSL já usados
 * em `importacoes-tendencia.tsx`, `log-atualizacoes-resumo.tsx`,
 * `pricing-sync-run-chart.tsx` e `pricing-coverage-trend-chart.tsx` — não
 * tokens do design system (`--success`/`--destructive` têm tonalidades
 * diferentes; `--destructive` no escuro em particular é um "wash" quase
 * preto pensado para fundo de badge, não para preenchimento sólido — ver
 * nota de contraste em `pricing-sync-run-chart.tsx`). Por isso são fixos,
 * iguais nos dois temas, exatamente como nos outros gráficos de barra do
 * sistema — já comprovadamente legíveis em claro e escuro.
 *
 * Só 2 cores, por pedido explícito ("não inventar novas tonalidades"); uma
 * 3ª/4ª série (se existir) repete o ciclo via `% length` no ponto de uso.
 */
const COR_SUCESSO = "#3FCF8E";
const COR_FALHA = "hsl(10 80% 44%)";

function buildSeriesPalette(): string[] {
  return [COR_SUCESSO, COR_FALHA];
}
const MAX_SERIES_WITH_END_LABEL = 4;
const MAX_POINTS_WITH_SYMBOL = 60;
/** Fração do range visível do eixo Y abaixo da qual dois rótulos de "último preço" são tratados como em risco de colisão — ver `planEndLabelOffsets`. */
const END_LABEL_COLLISION_THRESHOLD = 0.07;
const END_LABEL_OFFSET_STEP_PX = 13;

const dateAxisFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit" });
const dateTooltipFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

function formatMoney(value: number, currencyCode: string): string {
  if (!currencyCode) return value.toFixed(2);
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode, maximumFractionDigits: 2 }).format(
      value,
    );
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

/**
 * Formata um tick do eixo Y — moeda selecionada, locale pt-BR, sem casas
 * decimais desnecessárias (item 2 do refinamento visual): ticks inteiros
 * (ex. "R$ 100") não ganham ",00"; ticks fracionários (cartas de baixo
 * valor, ex. bulk a "R$ 0,30") mostram 2 casas. Arredonda antes de checar
 * "é inteiro" porque o cálculo interno de ticks do ECharts pode devolver
 * valores como `99.99999999998`.
 */
function formatAxisTick(value: number, currency: string): string {
  const rounded = Math.round(value * 100) / 100;
  const fractionDigits = Number.isInteger(rounded) ? 0 : 2;
  try {
    return new Intl.NumberFormat("pt-BR", {
      style: "currency",
      currency,
      minimumFractionDigits: fractionDigits,
      maximumFractionDigits: fractionDigits,
    }).format(rounded);
  } catch {
    return formatMoney(rounded, currency);
  }
}

/**
 * Dado por ponto na série ECharts — carrega os campos extras que o
 * tooltip/endLabel precisam (variante/fonte + preço nativo de contexto),
 * além do par `[timestamp, priceDisplay]` que o eixo `time` exige. Todo
 * ponto aqui já foi filtrado para ter `priceDisplay !== null` — o valor
 * plotado está sempre na moeda de exibição do relatório (`displayCurrency`).
 */
type ChartPointDatum = {
  value: [number, number];
  sourceCode: string;
  variantLabel: string;
  priceNative: number;
  currencyNative: string;
  fxStatus: PricingReportFxStatus;
};

/**
 * Subconjunto de `useChartTokens()` que este gráfico consome — evita importar
 * o tipo completo só para anotar um parâmetro. `primaryInkColor` (usado na
 * v4, quando a paleta de série era derivada do token de marca) removido na
 * v6 — a paleta passou a ser verde/vermelho fixo (`buildSeriesPalette`),
 * sem dependência de tokens de cor.
 */
type ChartColorTokens = {
  textColor: string;
  mutedColor: string;
  borderColor: string;
  surfaceColor: string;
  isDark: boolean;
};

/**
 * Heurística de offset vertical para rótulos de "último preço" (item 9 do
 * refinamento visual) — quando o último valor de duas ou mais séries fica
 * muito próximo (dentro de `END_LABEL_COLLISION_THRESHOLD` do range de
 * valores visíveis), a série mais alta mantém offset zero e as demais
 * recebem um deslocamento vertical incremental — nunca lateral, nunca
 * escondendo o rótulo. É uma aproximação: opera sobre os valores dos dados,
 * não sobre pixels renderizados (esta função não tem acesso ao sistema de
 * coordenadas que o ECharts calcula internamente) — mas é suficiente para o
 * volume típico de séries desta tela (`MAX_SERIES_WITH_END_LABEL`).
 */
function planEndLabelOffsets(lastValues: (number | null)[]): number[] {
  const offsets = lastValues.map(() => 0);
  const finiteValues = lastValues.filter((v): v is number => v !== null);
  if (finiteValues.length < 2) return offsets;

  const range = Math.max(...finiteValues) - Math.min(...finiteValues, 0) || Math.max(...finiteValues) || 1;
  const threshold = range * END_LABEL_COLLISION_THRESHOLD;

  const order = lastValues
    .map((v, i) => ({ v, i }))
    .filter((x): x is { v: number; i: number } => x.v !== null)
    .sort((a, b) => b.v - a.v);

  for (let k = 1; k < order.length; k++) {
    const prev = order[k - 1];
    const cur = order[k];
    if (prev && cur && Math.abs(prev.v - cur.v) < threshold) {
      offsets[cur.i] = (offsets[prev.i] ?? 0) + END_LABEL_OFFSET_STEP_PX;
    }
  }
  return offsets;
}

function buildOption(
  series: PriceHistorySeries[],
  opts: { displayCurrency: string; printSafe: boolean; tokens: ChartColorTokens },
): EChartsCoreOption {
  const { tokens } = opts;
  const showEndLabel = series.length <= MAX_SERIES_WITH_END_LABEL;
  const palette = buildSeriesPalette();

  const sortedPerSeries = series.map((s) =>
    [...s.points].sort((a, b) => new Date(a.observedAt).getTime() - new Date(b.observedAt).getTime()),
  );
  const lastValues = sortedPerSeries.map((pts) => pts[pts.length - 1]?.priceDisplay ?? null);
  const endLabelOffsets = planEndLabelOffsets(lastValues);

  // Tipado via cast no limite de composição da `option`: a `data` de cada
  // série carrega campos extras (`sourceCode`/`variantLabel`/preço nativo)
  // além do par `[timestamp, priceDisplay]` — forma oficialmente suportada
  // pelo ECharts ("data como objeto"), mas mais específica do que a
  // declaração de tipos da biblioteca prevê por padrão. `npm run typecheck`
  // (local, ver nota em `mmkyu-chart.tsx`/ADR-033) é o validador final deste
  // contrato.
  const echartsSeries = series.map((s, i) => {
    const color = palette[i % palette.length];
    const sorted = sortedPerSeries[i] ?? [];
    const data: ChartPointDatum[] = sorted.map((p) => ({
      value: [new Date(p.observedAt).getTime(), p.priceDisplay as number],
      sourceCode: s.sourceCode,
      variantLabel: s.variantLabel,
      priceNative: p.price,
      currencyNative: p.currencyCode,
      fxStatus: p.fxStatus,
    }));

    return {
      id: s.label,
      name: s.label,
      type: "line",
      data,
      color,
      // Smooth um pouco maior (era 0.22) — curva mais elegante, ainda
      // monotônica em x (nunca "estoura" acima/abaixo de pontos vizinhos); a
      // interpolação spline do ECharts sempre passa exatamente pelos pontos
      // reais, nunca desloca o dado em si.
      smooth: 0.3,
      smoothMonotone: "x",
      symbol: "circle",
      // Aumentado de 4.5 para 7 (pedido de Fabrício, rodada seguinte) — mais
      // presença visual em repouso, ainda sem virar uma bolinha cheia
      // competindo com o traçado (anel colorido + centro em `surfaceColor`).
      symbolSize: 7,
      showSymbol: sorted.length <= MAX_POINTS_WITH_SYMBOL,
      // Anel na cor da série + centro branco fixo (pedido explícito de
      // Fabrício — não mais `tokens.surfaceColor`, que no escuro não é
      // branco; aqui é literal, independente do tema). A linha continua
      // acompanhando a cor da série via `lineStyle.color` abaixo.
      itemStyle: { color: "#ffffff", borderColor: color, borderWidth: 1.75, shadowBlur: 0 },
      // `color` explícito aqui (não só no nível de série) — bug encontrado
      // numa rodada anterior: com `lineStyle` sem `color` próprio, o traçado
      // renderizava esbranquiçado em vez de herdar `color` do nível de série
      // (canal visual não resolvia como esperado para `SVGRenderer`).
      // Corrigido fixando a cor explicitamente em cada estado.
      lineStyle: { width: 2.75, color },
      emphasis: {
        focus: "series",
        scale: 1.5,
        lineStyle: { width: 3.25, color },
        // Hover inverte o marcador (fill vira a cor cheia da série, anel
        // volta a ser branco) — lê como "expansão" clara — com um glow
        // sutil na própria cor da série, sem introduzir cor nova.
        itemStyle: { color, borderColor: "#ffffff", borderWidth: 2, shadowColor: color, shadowBlur: 8 },
      },
      // Séries não-ativas no hover reduzem opacidade de forma discreta —
      // nunca somem por completo (item 5 da rodada anterior: "reduzir
      // discretamente", não esconder).
      blur: {
        lineStyle: { opacity: 0.35 },
        itemStyle: { opacity: 0.35 },
      },
      endLabel: showEndLabel
        ? {
            show: true,
            formatter: (params: { data?: ChartPointDatum }) =>
              params.data ? formatMoney(params.data.value[1], opts.displayCurrency) : "",
            fontSize: 10,
            fontWeight: 700,
            color,
            // Rótulo do último ponto passa a ficar ACIMA do marcador, não mais
            // à direita (pedido explícito de Fabrício, 2026-08-23) —
            // `align: "center"` centraliza o texto na mesma posição x do
            // marcador (offset x volta a 0, era 8 — deslocamento horizontal
            // que empurrava o rótulo para a direita); `verticalAlign: "bottom"`
            // ancora a base do texto no ponto de offset, então ele "cresce"
            // para cima a partir dali, sem sobrepor o marcador. O offset
            // vertical negativo (era usado para empilhar rótulos colidentes
            // *abaixo* uns dos outros) agora empilha *acima*, mesma lógica de
            // `planEndLabelOffsets`, só invertida de sinal — ver nota no
            // `grid.top` abaixo sobre o espaço extra reservado.
            align: "center",
            verticalAlign: "bottom",
            offset: [0, -(12 + (endLabelOffsets[i] ?? 0))],
          }
        : undefined,
    };
  }) as EChartsCoreOption["series"];

  return {
    color: palette,
    // Sem animação de entrada no print (P0 de impressão, 2026-08-23) — o
    // `window.print()` pode capturar o snapshot da folha no meio da
    // transição de entrada do ECharts (traçado "desenhando" da esquerda para
    // a direita, marcadores em fade-in), rendendo elementos parcialmente
    // desenhados/"soltos". Sem custo nenhum: numa folha estática a animação
    // nunca é vista de qualquer forma.
    animation: !opts.printSafe,
    grid: {
      left: 8,
      // Reduzido de 96 para 28 (pedido de Fabrício, 2026-08-23: "aumente a
      // largura do gráfico alinhado com os cards abaixo") — os 96px eram
      // reservados para o rótulo do último preço quando ele ficava à
      // direita do marcador; agora que o rótulo fica acima e centralizado
      // (`align: "center"`), só precisa de uma margem pequena para não
      // cortar a metade do texto que ultrapassa o x do último ponto. O
      // resultado é a área de plotagem esticando quase até a borda direita
      // do card, alinhada com "Preços atuais" abaixo.
      right: showEndLabel ? 28 : 16,
      // Aumentado de 20 para 34 — o rótulo do último ponto agora fica acima
      // do marcador (pedido de Fabrício, 2026-08-23), então precisa de
      // espaço vertical livre acima da série de maior valor para não ser
      // cortado pelo topo do grid.
      top: showEndLabel ? 34 : 20,
      bottom: 46,
      containLabel: true,
      // Degradê sutil na área de plotagem (rodada v6, referência visual
      // anexada por Fabrício) — `show: true` é obrigatório para o ECharts
      // pintar `backgroundColor`, senão a propriedade é ignorada; `border
      // Width: 0` evita a caixa cinza que o grid desenharia por padrão ao
      // ficar visível. Gradiente linear vertical, bem sutil (opacidade ≤
      // 0.05) para não competir com linhas/labels/tooltip — só a área útil
      // do gráfico, nunca a página.
      //
      // Sentido invertido na rodada seguinte (2026-08-23, pedido explícito
      // de Fabrício) — era topo tingido → base transparente; agora é topo
      // transparente → base tingida (stops trocados de posição).
      show: true,
      borderWidth: 0,
      backgroundColor: {
        type: "linear",
        x: 0,
        y: 0,
        x2: 0,
        y2: 1,
        colorStops: tokens.isDark
          ? [
              { offset: 0, color: "rgba(255,255,255,0)" },
              { offset: 1, color: "rgba(255,255,255,0.05)" },
            ]
          : [
              { offset: 0, color: "rgba(0,0,0,0)" },
              { offset: 1, color: "rgba(0,0,0,0.035)" },
            ],
      },
    },
    xAxis: {
      type: "time",
      // Piso de 1 dia entre ticks — corrige o bug de "datas repetidas
      // visualmente" (múltiplos ticks caindo no mesmo dia civil, formatados
      // de forma idêntica por só mostrarem dia/mês). A densidade menor em
      // janelas maiores (90/180/365d) já é o comportamento nativo do eixo
      // `time` do ECharts, sem lógica própria adicional.
      minInterval: 3600 * 1000 * 24,
      axisLabel: {
        formatter: (value: number) => dateAxisFormatter.format(value),
        hideOverlap: true,
        color: tokens.mutedColor,
        margin: 12,
      },
      // Opacidade reduzida (rodada v5) — a linha do eixo é infraestrutura,
      // não deve competir visualmente com o traçado das séries.
      axisLine: { lineStyle: { color: tokens.borderColor, opacity: tokens.isDark ? 0.35 : 0.5 } },
      axisTick: { show: false },
      // Grid vertical ausente (item 4) — o traçado das séries já comunica a
      // progressão temporal, linhas verticais só adicionavam ruído.
      splitLine: { show: false },
    },
    yAxis: {
      type: "value",
      min: 0,
      // Menos linhas de grade (era o padrão do ECharts, 5) — hierarquia
      // "dado em primeiro plano, malha em segundo" (rodada v5).
      splitNumber: 4,
      axisLabel: {
        formatter: (value: number) => formatAxisTick(value, opts.displayCurrency),
        color: tokens.mutedColor,
        fontSize: 11,
      },
      // Sem linha/tick de eixo — só os rótulos e as linhas de grade
      // horizontal comunicam a escala (padrão de gráfico de mercado, menos
      // "planilha").
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: {
        // Tracejado + opacidade bem baixa (era sólido, 0.4/0.16) — grid quase
        // ausente, só o suficiente para orientar a leitura sem "engessar"
        // (referência visual anexada por Fabrício nesta rodada).
        lineStyle: {
          color: tokens.borderColor,
          opacity: tokens.isDark ? 0.1 : 0.22,
          type: "dashed",
        },
      },
    },
    // Tooltip/crosshair — só existem no modo interativo (P0 de impressão,
    // 2026-08-23). Removidos por completo quando `printSafe`: são recursos
    // 100% dependentes de mouse (`trigger: "axis"` + `axisPointer` só fazem
    // sentido reagindo a hover), sem equivalente útil numa folha estática —
    // manter o bloco ligado não quebrava nada por si só, mas ia contra o
    // pedido explícito de Fabrício de um `printOption` derivado sem qualquer
    // feature dependente de mouse.
    tooltip: opts.printSafe
      ? { show: false }
      : {
          trigger: "axis",
          axisPointer: {
            // Crosshair de linha única (vertical) — sem o rótulo/eixo pesado
            // padrão do ECharts (`type: 'cross'` antigo): a data já aparece no
            // cabeçalho do próprio tooltip, então o rótulo do axisPointer fica
            // redundante e mais pesado do que precisa.
            type: "line",
            lineStyle: { color: tokens.mutedColor, width: 1, type: "solid" },
            label: { show: false },
          },
          // Único bloco deste gráfico usando `hsl(var(--token))` diretamente —
          // o tooltip do ECharts é sempre um `<div>` real no DOM (mesmo com
          // `SVGRenderer` no canvas do gráfico), então CSS custom properties
          // resolvem pela cascata normal e acompanham o tema automaticamente,
          // sem depender de `useChartTokens`.
          backgroundColor: "hsl(var(--surface))",
          borderColor: "hsl(var(--border))",
          borderWidth: 1,
          padding: [10, 12],
          // `transitionDuration: 0` (padrão do ECharts é 0.4s) — o tooltip
          // animava `left`/`top` a cada novo ponto do eixo. Combinado com o
          // `box-shadow`/`border-radius` do `extraCssText`, um frame capturado
          // no meio dessa transição (ou mesmo só durante o hover normal) lê
          // como texto "borrado", relatado por Fabrício. Sem a transição, o
          // tooltip salta direto para a posição final — texto sempre nítido.
          transitionDuration: 0,
          extraCssText:
            "border-radius:10px;box-shadow:0 12px 28px -10px hsl(var(--foreground) / 0.28), 0 4px 10px -4px hsl(var(--foreground) / 0.16);-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;text-rendering:optimizeLegibility;",
          textStyle: { color: "hsl(var(--foreground))", fontSize: 12 },
          formatter: (params: unknown) => {
            const list = Array.isArray(params) ? params : [params];
            if (list.length === 0) return "";
            const rows = list
              .map((p) => {
                const item = p as { data?: ChartPointDatum; marker?: string };
                if (!item.data) return "";
                // Preço nativo só aparece como contexto secundário quando de
                // fato houve conversão (CONVERTED) — em NATIVE seria idêntico
                // ao valor principal, então omitido ("só quando útil").
                const nativeHint =
                  item.data.fxStatus === "CONVERTED"
                    ? `<div style="color:hsl(var(--muted-foreground));font-size:10.5px;margin-top:1px;">${formatMoney(
                        item.data.priceNative,
                        item.data.currencyNative,
                      )} · convertido por PTAX</div>`
                    : "";
                return `<div style="padding:4px 0;">
                  <div style="display:flex;align-items:baseline;justify-content:space-between;gap:16px;">
                    <span style="color:hsl(var(--muted-foreground));font-size:11px;">${item.marker ?? ""}${item.data.variantLabel} · ${item.data.sourceCode}</span>
                    <span style="font-weight:700;font-size:13px;color:hsl(var(--foreground));">${formatMoney(item.data.value[1], opts.displayCurrency)}</span>
                  </div>
                  ${nativeHint}
                </div>`;
              })
              .join('<div style="height:1px;background:hsl(var(--border));margin:1px 0;"></div>');
            const first = list[0] as { data?: ChartPointDatum };
            const dateLabel = first.data ? dateTooltipFormatter.format(first.data.value[0]) : "";
            return `<div style="min-width:180px;">
              <div style="font-size:10px;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;color:hsl(var(--muted-foreground));margin-bottom:4px;">${dateLabel}</div>
              ${rows}
            </div>`;
          },
        },
    // Legenda — `type: "scroll"` (interativa, com paginação/setas quando o
    // conteúdo não cabe) vira `type: "plain"` no print (P0 de impressão,
    // 2026-08-23): nunca pagina, desenha todos os itens de uma vez —
    // condição segura aqui porque `MAX_SERIES_WITH_END_LABEL`/o volume
    // típico desta tela (1-2 séries) sempre cabe numa linha. `selectedMode:
    // false` desliga o clique de mostrar/esconder série — não existe
    // interação possível numa folha impressa, então a legenda também não
    // deve dar essa impressão visualmente (sem cursor de "clicável").
    legend: opts.printSafe
      ? {
          type: "plain",
          bottom: 0,
          icon: "circle",
          itemWidth: 10,
          itemHeight: 10,
          itemGap: 22,
          textStyle: { color: tokens.mutedColor, fontSize: 12 },
          selectedMode: false,
        }
      : {
          type: "scroll",
          bottom: 0,
          icon: "circle",
          // Indicador maior + mais respiro entre itens (era 8/16) — melhor
          // integração com a paleta refinada, leitura mais premium (rodada v5).
          itemWidth: 10,
          itemHeight: 10,
          itemGap: 22,
          textStyle: { color: tokens.mutedColor, fontSize: 12 },
          // Estado desabilitado (série oculta por clique) claramente diferente
          // do estado ativo — sem depender só de opacidade sutil.
          inactiveColor: tokens.borderColor,
          pageIconColor: tokens.mutedColor,
          pageTextStyle: { color: tokens.mutedColor },
        },
    // `dataZoom` (zoom/pan por scroll/drag) é feature 100% de mouse — omitido
    // por completo no print (P0 de impressão, 2026-08-23), nunca só
    // desabilitado (`disabled: true` ainda registraria os handlers).
    dataZoom: opts.printSafe ? undefined : [{ type: "inside", throttle: 50 }],
    series: echartsSeries,
  };
}

export function PriceHistoryChart({
  series,
  printSafe = false,
  currency,
  height = 240,
}: {
  series: PriceHistorySeries[];
  /** `true` na folha de impressão — cores fixas, nunca dependentes do tema ativo. */
  printSafe?: boolean;
  /** Moeda de exibição do relatório (`report.currency`) — todo ponto plotado já vem convertido para ela (migration 3948). */
  currency: string;
  height?: number;
}) {
  // Tokens de cor resolvidos (light/dark/print) — hook precisa ser chamado
  // sempre, antes de qualquer retorno antecipado abaixo.
  const tokens = useChartTokens(printSafe);

  // Só pontos com conversão disponível (`priceDisplay !== null`) entram no
  // traçado — "não inventar valor convertido" (pedido explícito de
  // Fabrício). Pontos descartados são contados abaixo, nunca somem
  // silenciosamente.
  const plottable = series
    .map((s) => ({ ...s, points: s.points.filter((p) => p.priceDisplay !== null) }))
    .filter((s) => s.points.length > 0);
  if (plottable.length === 0) return null;

  const option = buildOption(plottable, { displayCurrency: currency, printSafe, tokens });
  const unavailableCount = series.reduce((acc, s) => acc + s.points.filter((p) => p.priceDisplay === null).length, 0);

  return (
    <div>
      <MMKYUChart
        option={option}
        printSafe={printSafe}
        height={height}
        ariaLabel="Gráfico de histórico de preço no período selecionado, com tooltip detalhado por ponto (data, preço, variante, fonte e moeda) — os valores também estão disponíveis na tabela ao lado."
      />
      {unavailableCount > 0 && (
        <p className={printSafe ? "mt-1 text-[9px] text-neutral-500" : "mt-1 text-[11px] text-muted-foreground"}>
          {unavailableCount} {unavailableCount === 1 ? "ponto" : "pontos"} do período sem taxa de câmbio disponível na data —
          não {unavailableCount === 1 ? "plotado" : "plotados"}.
        </p>
      )}
    </div>
  );
}
