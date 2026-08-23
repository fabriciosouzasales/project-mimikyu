"use client";

import { Info } from "lucide-react";
import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import type { ImportacaoPipeline, ImportacaoRow } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Título de cada card — pedido explícito de Fabrício (2026-08-09, rodada de
 * ajuste): "IMPORTAÇÕES DE CARTAS" (plural) para o pipeline CARTAS e
 * "IMPORTAÇÃO DE IMAGENS" (singular) para IMAGENS — mantido exatamente como
 * pedido, mesmo com a assimetria singular/plural entre os dois.
 * `VARIANTES` (2026-08-16) segue a forma plural de CARTAS, também pedido
 * explícito de Fabrício ("IMPORTAÇÕES DE VARIANTES").
 */
const PIPELINE_TITLE: Record<ImportacaoPipeline, string> = {
  CARTAS: "Importações de Cartas",
  IMAGENS: "Importação de Imagens",
  VARIANTES: "Importações de Variantes",
};

/**
 * Cor exata pedida por Fabrício (2026-08-09) para a barra de sucesso —
 * `#3FCF8E`, mais clara/esverdeada que o token `--success` do design system
 * (`hsl(142 71% 40%)` ≈ `#1EAE53`). Deliberadamente hardcoded só aqui, não
 * alterado no token global: mudar `--success` afetaria `StateBadge`,
 * `AtividadeRecente` e outros usos de sucesso no app, fora do escopo deste
 * pedido (só este gráfico).
 */
const COR_SUCESSO = "#3FCF8E";

/**
 * Fix (2026-08-23) — mesmo bug já corrigido em `pricing-sync-run-chart.tsx`
 * (fix v3.6.1): `bg-destructive` (classe Tailwind ligada ao token
 * `--destructive`) rendia quase invisível no modo escuro, porque
 * `--destructive` no tema escuro (`6 64% 20%`) é um "wash" de fundo quase
 * preto, desenhado para conviver com `--destructive-foreground` claro por
 * cima (badges/alerts) — nunca para ser pintado sozinho como barra/ponto
 * sólido. Corrigido com a mesma técnica: literal HSL fixo (o valor de
 * `--destructive` no tema CLARO), idêntico nos dois temas, contraste ~3:1
 * contra `--surface` escuro (era ~1,2:1).
 */
const COR_FALHA = "hsl(10 80% 44%)";

/** Altura máxima (px) da coluna mais alta do gráfico — mesma lógica de escala de um sparkline/bar chart compacto. */
const CHART_HEIGHT_PX = 56;
/** Altura mínima (px) de um segmento com contagem > 0, para não desaparecer visualmente quando o total do período é muito maior. */
const MIN_SEGMENT_PX = 2;

const MES_ABREVIADO = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

type Semana = {
  key: string;
  /** Segunda-feira da semana — usada para ordenação cronológica e para o título completo do tooltip. */
  inicio: Date;
  /** Rótulo compacto do eixo X ("04/08"). */
  label: string;
  sucesso: number;
  falha: number;
};

/**
 * `status` já resolvido ("COMPLETED"/"COMPLETED_WITH_ERRORS"/"FAILED"/...) de
 * `ImportacaoRow`, mesmo vocabulário de `asset_import_run`/`catalog_import_job`
 * usado em `importacoes-table.tsx`. Classificação binária pedida por
 * Fabrício (sucesso vs. falha, sem meio-termo): `COMPLETED` é a única
 * classificada como sucesso; `FAILED`/`COMPLETED_WITH_ERRORS` como falha
 * (qualquer falha, parcial ou total). Status não-terminais
 * (`RUNNING`/`PENDING`/`STAGED`/`CONFIRMING`/`RECEIVED`/`PROCESSING`) e
 * `CANCELLED` ficam de fora — "importações realizadas" pressupõe execução
 * concluída, não em andamento nem abortada deliberadamente.
 */
function classificarResultado(status: string): "sucesso" | "falha" | null {
  if (status === "COMPLETED") return "sucesso";
  if (status === "FAILED" || status === "COMPLETED_WITH_ERRORS") return "falha";
  return null;
}

/** Segunda-feira da semana ISO que contém `date` (semana calendário, não janela rolante de 7 dias a partir de uma data arbitrária). */
function inicioDaSemana(date: Date): Date {
  const dia = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const diaSemana = dia.getDay(); // 0 = domingo … 6 = sábado
  const deslocamento = diaSemana === 0 ? -6 : 1 - diaSemana;
  dia.setDate(dia.getDate() + deslocamento);
  return dia;
}

/** Rótulo compacto do eixo X: dia/mês de início da semana (segunda-feira) — "04/08". */
function semanaLabel(inicio: Date): string {
  const dia = String(inicio.getDate()).padStart(2, "0");
  const mes = String(inicio.getMonth() + 1).padStart(2, "0");
  return `${dia}/${mes}`;
}

/** Título completo do tooltip ao passar o mouse numa barra — "04–10 de ago" (segunda a domingo), cruzando o mês quando necessário. */
function semanaTituloCompleto(inicio: Date): string {
  const fim = new Date(inicio);
  fim.setDate(fim.getDate() + 6);
  const mesInicio = MES_ABREVIADO[inicio.getMonth()];
  if (inicio.getMonth() === fim.getMonth()) {
    return `${inicio.getDate()}–${fim.getDate()} de ${mesInicio}`;
  }
  const mesFim = MES_ABREVIADO[fim.getMonth()];
  return `${inicio.getDate()} ${mesInicio} – ${fim.getDate()} ${mesFim}`;
}

function agruparPorSemana(importacoes: ImportacaoRow[]): Semana[] {
  const buckets = new Map<string, Semana>();
  for (const item of importacoes) {
    const resultado = classificarResultado(item.status);
    if (!resultado) continue;
    const inicio = inicioDaSemana(new Date(item.createdAt));
    const key = inicio.getTime().toString();
    let bucket = buckets.get(key);
    if (!bucket) {
      bucket = { key, inicio, label: semanaLabel(inicio), sucesso: 0, falha: 0 };
      buckets.set(key, bucket);
    }
    bucket[resultado] += 1;
  }
  return [...buckets.values()].sort((a, b) => a.inicio.getTime() - b.inicio.getTime());
}

/**
 * Duas mini tendências (Cartas/Imagens) lado a lado, entre o título
 * "Histórico de importações" e a tabela — pedido de Fabrício (2026-08-09),
 * modelo de referência anexado (widget de erros do Supabase: rótulo +
 * percentual à direita, barras empilhadas compactas abaixo, tooltip ao
 * passar o mouse numa barra — ajustado de "ao clicar" para "ao passar o
 * mouse" no mesmo dia, ver `PipelineTendenciaCard` abaixo). Confirmado com
 * Fabrício que "dois gráficos" significa
 * um gráfico por pipeline (Cartas, Imagens), cada um com barras empilhadas
 * verde (sucesso)/vermelho (falha) — não um único gráfico combinado.
 *
 * Sem biblioteca de gráficos no projeto (nenhuma em `package.json`) — mesma
 * escolha já feita para a barra de cobertura por idioma do hub de Card Set
 * (`card-sets/[code]/page.tsx`): `div`s com Tailwind, sem SVG/Canvas.
 * Precisou virar Client Component (`"use client"`) por causa do estado do
 * tooltip — `ImportacoesTendencia`/`PipelineTendenciaCard` continuam
 * recebendo os dados já prontos via prop, nenhuma busca própria.
 *
 * Eixo X trocado de quinzenal para semanal (2026-08-09, pedido de Fabrício)
 * — semana calendário ISO (segunda a domingo), não uma janela rolante de 7
 * dias a partir de uma data arbitrária. Barras sem cantos arredondados — só
 * o tooltip em si mantém `rounded`, como no modelo de referência.
 *
 * Terceiro card VARIANTES (2026-08-16) — `PIPELINES` substitui os dois
 * `<PipelineTendenciaCard>` explícitos por um `.map()` sobre a lista de
 * pipelines conhecidos, só para não repetir o componente 3x; não é uma
 * generalização para pipelines futuros (arbitrários), continua sendo uma
 * lista fixa de 3 valores literais, mesma decisão de escopo de
 * `ImportacaoPipeline`. Grid ajustado de `sm:grid-cols-2` para também ter
 * `lg:grid-cols-3`: 1 coluna em mobile, 2 em tablet (o 3º card quebra para a
 * linha de baixo, sozinho — comportamento natural do grid, não tratado à
 * parte), 3 em desktop amplo.
 */
const PIPELINES = ["CARTAS", "IMAGENS", "VARIANTES"] as const;

export function ImportacoesTendencia({ importacoes }: { importacoes: ImportacaoRow[] }) {
  const porPipeline: Record<ImportacaoPipeline, ImportacaoRow[]> = { CARTAS: [], IMAGENS: [], VARIANTES: [] };
  for (const item of importacoes) {
    porPipeline[item.pipeline].push(item);
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {PIPELINES.map((pipeline) => (
        <PipelineTendenciaCard key={pipeline} pipeline={pipeline} importacoes={porPipeline[pipeline]} />
      ))}
    </div>
  );
}

function PipelineTendenciaCard({
  pipeline,
  importacoes,
}: {
  pipeline: ImportacaoPipeline;
  importacoes: ImportacaoRow[];
}) {
  const semanas = agruparPorSemana(importacoes);
  const totalSucesso = semanas.reduce((soma, s) => soma + s.sucesso, 0);
  const totalFalha = semanas.reduce((soma, s) => soma + s.falha, 0);
  const totalGeral = totalSucesso + totalFalha;
  const percentualFalha = totalGeral > 0 ? (totalFalha / totalGeral) * 100 : 0;
  const maiorTotal = Math.max(1, ...semanas.map((s) => s.sucesso + s.falha));

  /**
   * Tooltip ao passar o mouse — ajuste de Fabrício (2026-08-09): a V1
   * original abria ao clicar, com listener de "clicar fora" para fechar
   * (modelo de referência: widget de erros do Supabase); trocado para hover
   * (`onMouseEnter`/`onMouseLeave`), com `onFocus`/`onBlur` equivalentes no
   * `<button>` para manter a mesma informação acessível via teclado. Sem
   * `containerRef`/listener de clique fora — não fazem mais sentido num
   * tooltip que fecha sozinho ao tirar o mouse/foco. Mesmo ajuste aplicado
   * em `LogAtualizacoesResumo` no mesmo dia.
   */
  const [aberto, setAberto] = useState<string | null>(null);

  return (
    <Card density="compact">
      <CardContent density="compact" className="space-y-4 pt-4">
        <div className="flex items-center justify-between">
          <span className="inline-flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            <Info className="h-3.5 w-3.5" aria-hidden="true" />
            {PIPELINE_TITLE[pipeline]}
          </span>
          <span className="inline-flex items-center gap-1.5 text-xs tabular-nums text-muted-foreground">
            {totalGeral > 0 && (
              <span className="h-2 w-2 shrink-0" style={{ backgroundColor: COR_FALHA }} aria-hidden="true" />
            )}
            {totalGeral > 0 ? `${percentualFalha.toFixed(1)}% de falhas` : "sem execuções"}
          </span>
        </div>

        {semanas.length === 0 ? (
          <p className="py-4 text-center text-xs text-muted-foreground">Nenhuma execução concluída neste pipeline.</p>
        ) : (
          // Auditoria de responsividade (2026-08-14, mesmo achado de
          // `LogAtualizacoesResumo`, componente-irmão): aqui o número de
          // colunas é dinâmico (sem janela fixa), então a largura mínima do
          // gráfico cresce sem limite conforme o histórico de importações
          // aumenta — sujeito a estourar mesmo em desktop largo, não só em
          // viewport estreito. Uma primeira tentativa com `overflow-x-auto` +
          // compensação de margem para não cortar o tooltip aumentou a altura
          // do card incorretamente (a margem negativa não neutraliza a
          // herdada de `space-y-4` do `CardContent`, que tem especificidade
          // maior) — revertida.
          // Correção final: diferente de `LogAtualizacoesResumo`, aqui a
          // barra/botão já usa `w-full` (relativo à coluna) — só a coluna em
          // si tinha `shrink-0` (nunca encolhe) sem `min-w-0` (piso
          // automático do flexbox no conteúdo). Removendo `shrink-0` e
          // adicionando `min-w-0`, a coluna volta ao comportamento padrão do
          // flexbox (`flex-shrink: 1`) e agora consegue encolher de verdade
          // quando o total de semanas não cabe — sem alterar a largura de
          // 24px (`w-6`) quando há espaço de sobra, o caso de hoje.
          <div className="space-y-1.5">
            <div className="flex items-end gap-1.5" style={{ height: CHART_HEIGHT_PX }}>
              {semanas.map((semana) => {
                const sucessoPx =
                  semana.sucesso > 0 ? Math.max(MIN_SEGMENT_PX, (semana.sucesso / maiorTotal) * CHART_HEIGHT_PX) : 0;
                const falhaPx =
                  semana.falha > 0 ? Math.max(MIN_SEGMENT_PX, (semana.falha / maiorTotal) * CHART_HEIGHT_PX) : 0;
                const estaAberto = aberto === semana.key;
                return (
                  <div
                    key={semana.key}
                    className="relative flex h-full w-6 min-w-0 shrink flex-col-reverse"
                    onMouseEnter={() => setAberto(semana.key)}
                    onMouseLeave={() => setAberto(null)}
                  >
                    <button
                      type="button"
                      onFocus={() => setAberto(semana.key)}
                      onBlur={() => setAberto(null)}
                      aria-expanded={estaAberto}
                      className="flex h-full w-full flex-col-reverse focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <div className="w-full" style={{ height: sucessoPx, backgroundColor: COR_SUCESSO }} />
                      <div className="w-full" style={{ height: falhaPx, backgroundColor: COR_FALHA }} />
                    </button>

                    {estaAberto && (
                      <div className="absolute bottom-full left-1/2 z-10 mb-2 w-40 -translate-x-1/2 rounded-md border border-border bg-surface p-3 text-left shadow-panel">
                        <p className="mb-2 text-xs font-medium text-foreground">{semanaTituloCompleto(semana.inicio)}</p>
                        <div className="space-y-1.5">
                          <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="inline-flex items-center gap-1.5 text-muted-foreground">
                              <span className="h-2 w-2 shrink-0" style={{ backgroundColor: COR_SUCESSO }} aria-hidden="true" />
                              Sucesso
                            </span>
                            <span className="tabular-nums text-foreground">{formatNumber(semana.sucesso)}</span>
                          </div>
                          <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="inline-flex items-center gap-1.5 text-muted-foreground">
                              <span className="h-2 w-2 shrink-0" style={{ backgroundColor: COR_FALHA }} aria-hidden="true" />
                              Falha
                            </span>
                            <span className="tabular-nums text-foreground">{formatNumber(semana.falha)}</span>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            <div className="flex gap-1.5">
              {semanas.map((semana) => (
                <span
                  key={semana.key}
                  className="w-6 min-w-0 shrink overflow-hidden whitespace-nowrap text-center text-[9px] leading-tight tabular-nums text-muted-foreground"
                >
                  {semana.label}
                </span>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
