"use client";

import { useEffect, useRef, useState } from "react";
import * as echarts from "echarts/core";
import { SVGRenderer } from "echarts/renderers";
import type { EChartsCoreOption } from "echarts/core";
import { useTheme } from "next-themes";

/**
 * Fundação técnica do Apache ECharts no MMKYU Collector (ADR-033,
 * 2026-08-23) — wrapper interno único e fino em torno de `echarts.init()`.
 * Decisão explícita de Fabrício: nenhum wrapper React de terceiros
 * (`echarts-for-react` avaliado e descartado), para manter controle direto
 * sobre lifecycle, resize, tema e renderer, sem depender de convenções de
 * um pacote não mantido pela Apache Foundation.
 *
 * Responsabilidades deste componente (e só estas — "wrapper deve ser fino",
 * pedido explícito):
 * - Inicializar/`dispose()` a instância no lugar certo do ciclo de vida do
 *   React (nenhuma instância órfã sobrevive à navegação entre páginas).
 * - Resize via `ResizeObserver` no próprio container (não `window.resize` —
 *   o container pode mudar de tamanho sem a janela mudar, ex.: sidebar
 *   colapsando).
 * - `SVGRenderer` fixo — nunca `CanvasRenderer` (default do ECharts sem
 *   renderer registrado). SVG não borra ao imprimir/ampliar; nosso volume de
 *   dados (dezenas a poucas centenas de pontos por série, telas
 *   administrativas) não se aproxima da escala onde canvas traria vantagem
 *   real de performance.
 * - Trocar de tema light/dark, sincronizado com `next-themes` (mesmo padrão
 *   de `useTheme()`/`resolvedTheme` já usado em `BrandLogo`/`BrandMark`).
 *   ECharts não troca tema numa instância já criada — só recriando a
 *   instância — então a troca de tema aqui dispara `dispose()` + reinit.
 * - Ler as cores diretamente das CSS custom properties do design system
 *   (`--foreground`/`--muted-foreground`/`--border`/`--surface`, definidas
 *   em `app/globals.css`) via `getComputedStyle`, em vez de duplicar valores
 *   de tokens dentro deste arquivo — o tema do gráfico nunca fica
 *   dessincronizado do resto do produto por esquecimento de atualização
 *   manual. `printSafe` (mesma convenção já usada no gráfico SVG manual que
 *   este componente substitui) troca para uma paleta `neutral-*` fixa,
 *   independente do tema ativo — necessário porque toda folha impressa do
 *   Pricing Admin precisa ficar correta mesmo disparada a partir do tema
 *   escuro.
 * - Acessibilidade mínima: `role="img"` + `aria-label` obrigatório — mesmo
 *   padrão do `<svg>` que este componente substitui.
 *
 * Responsabilidade que este componente **não** tem — decisão deliberada de
 * ADR-033 ("evitar bundle integral do ECharts"): registrar tipos de série
 * (`LineChart`, `BarChart`, ...) ou componentes (`GridComponent`,
 * `TooltipComponent`, `LegendComponent`, `DataZoomComponent`, ...) via
 * `echarts.use([...])`. Isso é responsabilidade de cada componente
 * consumidor específico (ex.: o futuro gráfico de Histórico de Preço),
 * importando só o que a sua própria `option` usa. Se este wrapper
 * registrasse tudo previamente, qualquer tela que usasse `MMKYUChart` pagaria
 * pelo bundle de todos os tipos de gráfico já usados em qualquer lugar do
 * produto — o oposto do que "imports seletivos" significa. Só o
 * `SVGRenderer` é registrado aqui, porque é genuinamente universal (todo
 * gráfico do produto usa o mesmo renderer, por decisão do ADR).
 */
echarts.use([SVGRenderer]);

const PRINT_TOKENS = {
  textColor: "#171717",
  mutedColor: "#737373",
  borderColor: "#d4d4d4",
  surfaceColor: "#ffffff",
  // Aproximações hex de `--primary`/`--primary-ink` (claro) de
  // `app/globals.css` — só usadas como fallback estático de impressão/SSR;
  // em runtime, `readLiveTokens()` lê o valor exato via CSS custom property.
  // Adicionados na rodada de identidade visual do gráfico (2026-08-23):
  // `primaryInkColor` é o dourado já pensado pelo design system para uso
  // como cor de CONTEÚDO (texto/linha), não de superfície — ver nota em
  // `app/globals.css` sobre `--primary-ink`.
  primaryColor: "#dca54b",
  primaryInkColor: "#8c5d1d",
} as const;

/**
 * Largura fixa (px) de qualquer gráfico renderizado em modo impressão — ver
 * nota completa junto ao `echarts.init()` de `MMKYUChart` abaixo. Deriva de
 * `@page { size: A4; margin: 10mm }` (`app/globals.css`): 210mm - 2×10mm =
 * 190mm de área imprimível ÷ 25.4 × 96px/polegada ≈ 718px. Se o `@page`
 * mudar de margem/tamanho um dia, este valor precisa acompanhar.
 */
const PRINT_CHART_WIDTH_PX = 718;

// Tipo explícito (`string` por campo), não `typeof PRINT_TOKENS` — `PRINT_TOKENS`
// é `as const` (tipos literais, ex.: `"#171717"`) só para servir de fallback
// tipado; `readLiveTokens()` devolve cores calculadas em runtime
// (`hsl(...)` ou o próprio fallback), nunca os literais exatos, então o
// tipo de retorno precisa ser `string` — bug pré-existente da Fase 2
// (ADR-033) que só apareceu agora porque nenhum incremento anterior tinha
// rodado `npm run typecheck` completo depois dela.
type ChartTokens = {
  textColor: string;
  mutedColor: string;
  borderColor: string;
  surfaceColor: string;
  primaryColor: string;
  primaryInkColor: string;
};

/**
 * Lê as cores do design system diretamente das CSS custom properties já
 * resolvidas no `<html>` (definidas em `app/globals.css`, formato `H S% L%`
 * sem o wrapper `hsl()` — mesma convenção usada pelo Tailwind em todo o
 * projeto). `document.documentElement` já reflete o tema correto no momento
 * em que este componente monta: o script de `next-themes` aplica a classe
 * `dark` antes da pintura, evitando flash de tema errado.
 */
function readLiveTokens(): ChartTokens {
  if (typeof window === "undefined") return PRINT_TOKENS;
  const styles = getComputedStyle(document.documentElement);
  const read = (name: string, fallback: string) => {
    const raw = styles.getPropertyValue(name).trim();
    return raw ? `hsl(${raw})` : fallback;
  };
  return {
    textColor: read("--foreground", PRINT_TOKENS.textColor),
    mutedColor: read("--muted-foreground", PRINT_TOKENS.mutedColor),
    borderColor: read("--border", PRINT_TOKENS.borderColor),
    surfaceColor: read("--surface", PRINT_TOKENS.surfaceColor),
    primaryColor: read("--primary", PRINT_TOKENS.primaryColor),
    primaryInkColor: read("--primary-ink", PRINT_TOKENS.primaryInkColor),
  };
}

/**
 * Tema ECharts derivado dos tokens — só estrutura (eixo, grade, tooltip,
 * legenda, texto), nunca paleta de série: cada gráfico consumidor define
 * suas próprias cores de série na `option` (ex.: `SERIES_COLORS`), porque a
 * paleta certa depende do número/semântica das séries de cada tela, não é
 * um dado do design system global.
 */
function buildTheme(tokens: ChartTokens) {
  return {
    textStyle: { color: tokens.textColor },
    title: { textStyle: { color: tokens.textColor } },
    legend: { textStyle: { color: tokens.mutedColor } },
    tooltip: {
      backgroundColor: tokens.surfaceColor,
      borderColor: tokens.borderColor,
      textStyle: { color: tokens.textColor },
    },
    categoryAxis: {
      axisLine: { lineStyle: { color: tokens.borderColor } },
      axisTick: { lineStyle: { color: tokens.borderColor } },
      axisLabel: { color: tokens.mutedColor },
      splitLine: { lineStyle: { color: tokens.borderColor } },
    },
    valueAxis: {
      axisLine: { lineStyle: { color: tokens.borderColor } },
      axisTick: { lineStyle: { color: tokens.borderColor } },
      axisLabel: { color: tokens.mutedColor },
      splitLine: { lineStyle: { color: tokens.borderColor, opacity: 0.5 } },
    },
    // `timeAxis` estava ausente (bug silencioso desde a Fase 2) — todo
    // gráfico com `xAxis: { type: 'time' }` (ex.: Histórico de Preço) ficava
    // sem tema aplicado nesse eixo, caindo no default do ECharts em vez das
    // cores do design system. Espelha `valueAxis` (mesma semântica
    // estrutural). Descoberto na rodada de refinamento visual (2026-08-23).
    timeAxis: {
      axisLine: { lineStyle: { color: tokens.borderColor } },
      axisTick: { lineStyle: { color: tokens.borderColor } },
      axisLabel: { color: tokens.mutedColor },
      splitLine: { lineStyle: { color: tokens.borderColor, opacity: 0.5 } },
    },
  };
}

/**
 * Tokens de cor resolvidos, expostos para consumidores que precisam de
 * controle determinístico sobre a própria `option` (ex.: crosshair/tooltip/
 * eixo do Histórico de Preço) em vez de depender só do objeto de tema
 * interno do `echarts.init()` — o merge de tema do ECharts é confiável para
 * as chaves estruturais simples (`textStyle`, `valueAxis`, ...) já cobertas
 * por `buildTheme()`, mas não é o mecanismo certo para estilizar elementos
 * mais específicos de um gráfico (crosshair, linhas de grade seletivas,
 * texto inativo de legenda) — esses ficam mais previsíveis definidos direto
 * na `option` do consumidor, com as cores certas já resolvidas em mãos.
 * Mesmo `resolvedTheme`/lifecycle de leitura que `MMKYUChart` usa
 * internamente — não duplica lógica, só a expõe.
 */
export function useChartTokens(printSafe = false): ChartTokens & { isDark: boolean } {
  const { resolvedTheme } = useTheme();
  const [tokens, setTokens] = useState<ChartTokens>(PRINT_TOKENS);

  useEffect(() => {
    setTokens(printSafe ? PRINT_TOKENS : readLiveTokens());
  }, [printSafe, resolvedTheme]);

  return { ...tokens, isDark: !printSafe && resolvedTheme === "dark" };
}

export type MMKYUChartProps = {
  /** Objeto `option` do ECharts — cada consumidor tipa/monta o seu, este wrapper não interpreta o conteúdo. */
  option: EChartsCoreOption;
  /** Descrição textual do gráfico para leitor de tela — obrigatório, sem valor padrão. */
  ariaLabel: string;
  className?: string;
  /** Altura do container em px (número) ou qualquer valor CSS válido (string). */
  height?: number | string;
  /**
   * `true` na folha de impressão — paleta `neutral-*` fixa, nunca
   * dependente do tema ativo no momento do clique em Imprimir. Mesma
   * convenção do `printSafe` do gráfico SVG manual anterior.
   */
  printSafe?: boolean;
  /** `setOption(option, { notMerge })` — `true` (default) substitui a option inteira; evita resíduo de séries/eixos de uma option anterior estruturalmente diferente. */
  notMerge?: boolean;
};

export function MMKYUChart({
  option,
  ariaLabel,
  className,
  height = 260,
  printSafe = false,
  notMerge = true,
}: MMKYUChartProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<ReturnType<typeof echarts.init> | null>(null);
  const { resolvedTheme } = useTheme();

  // Cria/recria a instância quando o container monta ou o tema muda —
  // ECharts não permite trocar tema in-place, só via novo `init()`.
  // `dispose()` no cleanup garante zero instância órfã ao navegar/desmontar.
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const tokens = printSafe ? PRINT_TOKENS : readLiveTokens();

    // Correção do P0 de impressão (2026-08-23, v2 — a v1 com `beforeprint` +
    // `chart.resize()` não foi suficiente: evidência real de Fabrício mostrou
    // o gráfico ainda espremido numa faixa estreita mesmo com o listener
    // ativo). Causa raiz confirmada: toda folha imprimível (`RelatorioFolha`)
    // monta com `hidden print:block` — o container já existe no DOM com
    // `display: none` no instante de `echarts.init()`. `chart.resize()` sem
    // argumentos SEMPRE volta a medir `container.clientWidth/Height` — e essa
    // medição só é confiável depois que o navegador aplicou `@media print` E
    // já processou um ciclo de layout, algo que `beforeprint` não garante de
    // forma consistente entre navegadores (a ordem exata layout-vs-evento é
    // uma zona cinzenta da spec, na prática flutua).
    //
    // Fix definitivo: para instância de impressão, `echarts.init()` recebe
    // largura/altura EXPLÍCITAS (`opts.width`/`opts.height`) — o ECharts usa
    // esse valor diretamente, nunca mede o container, então `display: none`
    // deixa de importar. Largura fixa deriva de `@page { size: A4; margin:
    // 10mm }` (`app/globals.css`) — 210mm - 2×10mm = 190mm de área imprimível
    // (`RelatorioFolha` remove seu padding horizontal em print, `print:px-0`,
    // então o gráfico ocupa essa largura inteira), convertidos por 96px/pol.
    // (unidade de referência CSS para layout, a mesma que o navegador usa
    // para paginar a impressão, independente da resolução física da
    // impressora/PDF): 190 ÷ 25.4 × 96 ≈ 718px. Consequência arquitetural:
    // instância de impressão não observa/redimensiona depois de criada —
    // dimensão fixa e determinística é o objetivo (item 2 do pedido de
    // Fabrício: "não depender de ResizeObserver durante impressão"), não uma
    // omissão. A instância interativa não muda em nada — continua 100%
    // responsiva via `ResizeObserver`, como sempre foi.
    const chart = printSafe
      ? echarts.init(container, buildTheme(tokens), {
          renderer: "svg",
          width: PRINT_CHART_WIDTH_PX,
          height: typeof height === "number" ? height : undefined,
        })
      : echarts.init(container, buildTheme(tokens), { renderer: "svg" });
    chartRef.current = chart;

    if (printSafe) {
      return () => {
        chart.dispose();
        chartRef.current = null;
      };
    }

    const resizeObserver = new ResizeObserver(() => chart.resize());
    resizeObserver.observe(container);

    return () => {
      resizeObserver.disconnect();
      chart.dispose();
      chartRef.current = null;
    };
  }, [printSafe, resolvedTheme, height]);

  // Aplica a option atual — roda tanto quando `option`/`notMerge` mudam
  // (instância existente, sem recriar) quanto logo após a instância ser
  // (re)criada pelo efeito acima (mesmas dependências de tema/printSafe),
  // para nunca deixar uma instância nova sem `option` aplicada.
  useEffect(() => {
    chartRef.current?.setOption(option, { notMerge });
  }, [option, notMerge, printSafe, resolvedTheme]);

  return (
    <div
      ref={containerRef}
      role="img"
      aria-label={ariaLabel}
      className={className}
      style={{ height, width: "100%" }}
    />
  );
}
