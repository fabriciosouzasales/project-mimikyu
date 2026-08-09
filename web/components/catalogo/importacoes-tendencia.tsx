"use client";

import { Info } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import type { ImportacaoPipeline, ImportacaoRow } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Título de cada card — pedido explícito de Fabrício (2026-08-09, rodada de
 * ajuste): "IMPORTAÇÕES DE CARTAS" (plural) para o pipeline CARTAS e
 * "IMPORTAÇÃO DE IMAGENS" (singular) para IMAGENS — mantido exatamente como
 * pedido, mesmo com a assimetria singular/plural entre os dois.
 */
const PIPELINE_TITLE: Record<ImportacaoPipeline, string> = {
  CARTAS: "Importações de Cartas",
  IMAGENS: "Importação de Imagens",
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

/** Altura máxima (px) da coluna mais alta do gráfico — mesma lógica de escala de um sparkline/bar chart compacto. */
const CHART_HEIGHT_PX = 56;
/** Altura mínima (px) de um segmento com contagem > 0, para não desaparecer visualmente quando o total do período é muito maior. */
const MIN_SEGMENT_PX = 2;

const MES_ABREVIADO = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

type Semana = {
  key: string;
  /** Segunda-feira da semana — usada para ordenação cronológica e para o título completo do popover. */
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

/** Título completo do popover ao clicar numa barra — "04–10 de ago" (segunda a domingo), cruzando o mês quando necessário. */
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
 * percentual à direita, barras empilhadas compactas abaixo, popover ao
 * clicar numa barra). Confirmado com Fabrício que "dois gráficos" significa
 * um gráfico por pipeline (Cartas, Imagens), cada um com barras empilhadas
 * verde (sucesso)/vermelho (falha) — não um único gráfico combinado.
 *
 * Sem biblioteca de gráficos no projeto (nenhuma em `package.json`) — mesma
 * escolha já feita para a barra de cobertura por idioma do hub de Card Set
 * (`card-sets/[code]/page.tsx`): `div`s com Tailwind, sem SVG/Canvas.
 * Precisou virar Client Component (`"use client"`) por causa do estado do
 * popover — `ImportacoesTendencia`/`PipelineTendenciaCard` continuam
 * recebendo os dados já prontos via prop, nenhuma busca própria.
 *
 * Eixo X trocado de quinzenal para semanal (2026-08-09, pedido de Fabrício)
 * — semana calendário ISO (segunda a domingo), não uma janela rolante de 7
 * dias a partir de uma data arbitrária. Barras sem cantos arredondados — só
 * o popover em si mantém `rounded`, como no modelo de referência.
 */
export function ImportacoesTendencia({ importacoes }: { importacoes: ImportacaoRow[] }) {
  const porPipeline: Record<ImportacaoPipeline, ImportacaoRow[]> = { CARTAS: [], IMAGENS: [] };
  for (const item of importacoes) {
    porPipeline[item.pipeline].push(item);
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <PipelineTendenciaCard pipeline="CARTAS" importacoes={porPipeline.CARTAS} />
      <PipelineTendenciaCard pipeline="IMAGENS" importacoes={porPipeline.IMAGENS} />
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

  const [aberto, setAberto] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Fecha o popover ao clicar fora do gráfico — mesmo comportamento esperado
  // do modelo de referência (widget de erros do Supabase).
  useEffect(() => {
    if (!aberto) return;
    function handleClickFora(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setAberto(null);
      }
    }
    document.addEventListener("mousedown", handleClickFora);
    return () => document.removeEventListener("mousedown", handleClickFora);
  }, [aberto]);

  return (
    <Card density="compact">
      <CardContent density="compact" className="space-y-4 pt-4">
        <div className="flex items-center justify-between">
          <span className="inline-flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            <Info className="h-3.5 w-3.5" aria-hidden="true" />
            {PIPELINE_TITLE[pipeline]}
          </span>
          <span className="inline-flex items-center gap-1.5 text-xs tabular-nums text-muted-foreground">
            {totalGeral > 0 && <span className="h-2 w-2 shrink-0 bg-destructive" aria-hidden="true" />}
            {totalGeral > 0 ? `${percentualFalha.toFixed(1)}% de falhas` : "sem execuções"}
          </span>
        </div>

        {semanas.length === 0 ? (
          <p className="py-4 text-center text-xs text-muted-foreground">Nenhuma execução concluída neste pipeline.</p>
        ) : (
          <div ref={containerRef} className="space-y-1.5">
            <div className="flex items-end gap-1.5" style={{ height: CHART_HEIGHT_PX }}>
              {semanas.map((semana) => {
                const sucessoPx =
                  semana.sucesso > 0 ? Math.max(MIN_SEGMENT_PX, (semana.sucesso / maiorTotal) * CHART_HEIGHT_PX) : 0;
                const falhaPx =
                  semana.falha > 0 ? Math.max(MIN_SEGMENT_PX, (semana.falha / maiorTotal) * CHART_HEIGHT_PX) : 0;
                const estaAberto = aberto === semana.key;
                return (
                  <div key={semana.key} className="relative flex h-full w-6 shrink-0 flex-col-reverse">
                    <button
                      type="button"
                      onClick={() => setAberto((atual) => (atual === semana.key ? null : semana.key))}
                      aria-expanded={estaAberto}
                      className="flex h-full w-full flex-col-reverse focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <div className="w-full" style={{ height: sucessoPx, backgroundColor: COR_SUCESSO }} />
                      <div className="w-full bg-destructive" style={{ height: falhaPx }} />
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
                              <span className="h-2 w-2 shrink-0 bg-destructive" aria-hidden="true" />
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
                <span key={semana.key} className="w-6 shrink-0 text-center text-[9px] leading-tight tabular-nums text-muted-foreground">
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
