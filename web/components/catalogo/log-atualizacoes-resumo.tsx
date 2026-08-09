"use client";

import { Info } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import type { LogAtualizacoesResumoSemanalItem } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

type Categoria = "CADASTRO" | "ALTERACAO" | "EXCLUSAO";

const CATEGORIA_TITULO: Record<Categoria, string> = {
  CADASTRO: "Cadastro",
  ALTERACAO: "Alteração",
  EXCLUSAO: "Exclusão",
};

/** Cores por categoria — decisão explícita de Fabrício (2026-08-09): tokens já usados em outros pontos do app (nunca cor nova introduzida só para este gráfico, ao contrário do #3FCF8E de ImportacoesTendencia). */
const CATEGORIA_COR_CLASSE: Record<Categoria, string> = {
  CADASTRO: "bg-primary",
  ALTERACAO: "bg-warning",
  EXCLUSAO: "bg-destructive",
};

const CHART_HEIGHT_PX = 56;
const MIN_SEGMENT_PX = 2;
const JANELA_SEMANAS = 12;

const MES_ABREVIADO = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

/**
 * Segunda-feira da semana ISO que contém `date` — mesmo algoritmo de
 * `inicioDaSemana()` (`importacoes-tendencia.tsx`), duplicado aqui
 * deliberadamente: o projeto ainda não tem um util compartilhado para essa
 * conta, e os dois componentes evoluíram em pedidos separados de Fabrício.
 */
function inicioDaSemana(date: Date): Date {
  const dia = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const diaSemana = dia.getDay();
  const deslocamento = diaSemana === 0 ? -6 : 1 - diaSemana;
  dia.setDate(dia.getDate() + deslocamento);
  return dia;
}

function semanaLabel(inicio: Date): string {
  const dia = String(inicio.getDate()).padStart(2, "0");
  const mes = String(inicio.getMonth() + 1).padStart(2, "0");
  return `${dia}/${mes}`;
}

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

function toKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * As 12 semanas fixas da janela (mais antiga → mais recente) — sempre as
 * mesmas 12 mostradas, com ou sem evento em cada uma. Janela fixa aprovada
 * por Fabrício (2026-08-09, decisão 3), diferente da janela variável de
 * `ImportacoesTendencia` (que só mostra semanas com dado real).
 */
function buildJanelaFixa(): Date[] {
  const hoje = inicioDaSemana(new Date());
  const semanas: Date[] = [];
  for (let i = JANELA_SEMANAS - 1; i >= 0; i--) {
    const semana = new Date(hoje);
    semana.setDate(semana.getDate() - i * 7);
    semanas.push(semana);
  }
  return semanas;
}

/**
 * 3 gráficos semanais (Cadastro/Alteração/Exclusão), topo de
 * /catalogo/log-atualizacoes — escopo V1 aprovado por Fabrício (2026-08-09).
 * Mesma linguagem visual de `ImportacoesTendencia` (barras via div/Tailwind,
 * sem biblioteca de gráficos, popover ao clicar), mas cada card mostra uma
 * única categoria com uma única cor (não empilhado), e a janela é sempre as
 * mesmas 12 semanas fixas — não varia com o volume de dado disponível.
 */
export function LogAtualizacoesResumo({ resumo }: { resumo: LogAtualizacoesResumoSemanalItem[] }) {
  const semanas = buildJanelaFixa();
  const porCategoria = new Map<string, number>();
  for (const item of resumo) {
    porCategoria.set(`${item.weekStart}|${item.category}`, item.totalCount);
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
      {(["CADASTRO", "ALTERACAO", "EXCLUSAO"] as const).map((categoria) => (
        <CategoriaResumoCard key={categoria} categoria={categoria} semanas={semanas} porCategoria={porCategoria} />
      ))}
    </div>
  );
}

function CategoriaResumoCard({
  categoria,
  semanas,
  porCategoria,
}: {
  categoria: Categoria;
  semanas: Date[];
  porCategoria: Map<string, number>;
}) {
  const contagens = semanas.map((semana) => porCategoria.get(`${toKey(semana)}|${categoria}`) ?? 0);
  const total = contagens.reduce((soma, valor) => soma + valor, 0);
  const maior = Math.max(1, ...contagens);

  const [aberto, setAberto] = useState<number | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (aberto === null) return;
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
            {CATEGORIA_TITULO[categoria]}
          </span>
          <span className="text-xs tabular-nums text-muted-foreground">
            {formatNumber(total)} nas últimas {JANELA_SEMANAS} semanas
          </span>
        </div>

        <div ref={containerRef} className="space-y-1.5">
          <div className="flex items-end gap-1.5" style={{ height: CHART_HEIGHT_PX }}>
            {semanas.map((semana, index) => {
              const valor = contagens[index] ?? 0;
              const px = valor > 0 ? Math.max(MIN_SEGMENT_PX, (valor / maior) * CHART_HEIGHT_PX) : 0;
              const estaAberto = aberto === index;
              return (
                <div key={toKey(semana)} className="relative flex h-full w-6 shrink-0 flex-col-reverse">
                  <button
                    type="button"
                    onClick={() => setAberto((atual) => (atual === index ? null : index))}
                    aria-expanded={estaAberto}
                    className="flex h-full w-full flex-col-reverse focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  >
                    <div className={cn("w-full", CATEGORIA_COR_CLASSE[categoria])} style={{ height: px }} />
                  </button>

                  {estaAberto && (
                    <div className="absolute bottom-full left-1/2 z-10 mb-2 w-36 -translate-x-1/2 rounded-md border border-border bg-surface p-3 text-left shadow-panel">
                      <p className="mb-1.5 text-xs font-medium text-foreground">{semanaTituloCompleto(semana)}</p>
                      <p className="text-xs tabular-nums text-muted-foreground">
                        {formatNumber(valor)} {valor === 1 ? "operação" : "operações"}
                      </p>
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          <div className="flex gap-1.5">
            {semanas.map((semana) => (
              <span
                key={toKey(semana)}
                className="w-6 shrink-0 text-center text-[9px] leading-tight tabular-nums text-muted-foreground"
              >
                {semanaLabel(semana)}
              </span>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
