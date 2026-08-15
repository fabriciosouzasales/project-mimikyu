"use client";

import { Info } from "lucide-react";
import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import type { LogAtualizacoesResumoSemanalItem } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

type Categoria = "CADASTRO" | "ALTERACAO" | "EXCLUSAO";

const CATEGORIA_TITULO: Record<Categoria, string> = {
  CADASTRO: "Cadastro",
  ALTERACAO: "Alteração",
  EXCLUSAO: "Exclusão",
};

/**
 * Cor única para as 3 categorias — ajuste de Fabrício (2026-08-09, revisão
 * pós-V1): a decisão original (tokens `bg-primary`/`bg-warning`/
 * `bg-destructive`, um por categoria) ficou visualmente pesada; substituída
 * por `#3FCF8E`, a mesma cor já usada por `ImportacoesTendencia`
 * (`COR_SUCESSO`) — não é mais "cor nova introduzida só para este gráfico"
 * como o comentário anterior registrava, é reuso da cor que já existe em
 * outro ponto do app. Aplicada via `style` inline (mesmo padrão de
 * `ImportacoesTendencia`), não classe Tailwind, porque não é um token do
 * design system.
 */
const COR_BARRA = "#3FCF8E";

const CHART_HEIGHT_PX = 56;
const MIN_SEGMENT_PX = 2;
/** Reduzida de 12 para 10 semanas — ajuste de Fabrício (2026-08-09, revisão pós-V1), junto com a redução de largura das barras, para deixar os 3 gráficos menos pesados visualmente. */
const JANELA_SEMANAS = 10;
/**
 * Largura da barra em si — 18px, 25% menor que os 24px (`w-6`) da V1
 * original, mesmo ajuste de Fabrício acima. A COLUNA que contém a barra
 * (`flex-1`, ver render) sempre ocupa a largura total disponível do card,
 * dividida em partes iguais entre as semanas — correção de um bug visual
 * relatado por Fabrício logo após a V1.1: com coluna de largura fixa, o
 * eixo inteiro (barras + rótulos) ficava encolhido à esquerda do card,
 * sobrando um vão vazio à direita em vez de respeitar a margem simétrica do
 * `CardContent`.
 */
const COLUNA_LARGURA_PX = 18;

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
 * As `JANELA_SEMANAS` semanas fixas da janela (mais antiga → mais recente)
 * — sempre as mesmas mostradas, com ou sem evento em cada uma. Janela fixa
 * aprovada por Fabrício (2026-08-09, decisão 3; reduzida de 12 para 10 no
 * mesmo dia, ajuste pós-V1), diferente da janela variável de
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
 * sem biblioteca de gráficos, tooltip ao passar o mouse), mas cada card
 * mostra uma única categoria com uma única cor (não empilhado), e a janela
 * é sempre as
 * mesmas `JANELA_SEMANAS` semanas fixas — não varia com o volume de dado
 * disponível.
 */
export function LogAtualizacoesResumo({ resumo }: { resumo: LogAtualizacoesResumoSemanalItem[] }) {
  const semanas = buildJanelaFixa();
  const porCategoria = new Map<string, number>();
  for (const item of resumo) {
    porCategoria.set(`${item.weekStart}|${item.category}`, item.totalCount);
  }

  // Auditoria de responsividade (2026-08-14, achado real de Fabrício em
  // desktop/notebook estreito): o grid pulava direto de 1 para 3 colunas em
  // `sm` (640px) — sem passo intermediário, a área útil (descontada a
  // sidebar de duas colunas) já fica abaixo da largura mínima que os 3
  // cards + seus mini-gráficos precisam bem antes de qualquer viewport
  // "mobile". `md:grid-cols-2 xl:grid-cols-3` intercala um estágio de 2
  // colunas para notebook/desktop estreito — 3 colunas só a partir de
  // desktop realmente largo.
  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
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

  /**
   * Tooltip ao passar o mouse — ajuste de Fabrício (2026-08-09, mesmo dia):
   * a V1 original abria ao clicar (mesmo padrão de `ImportacoesTendencia`,
   * com listener de "clicar fora" para fechar); trocado para hover
   * (`onMouseEnter`/`onMouseLeave`), com `onFocus`/`onBlur` equivalentes no
   * `<button>` para manter a mesma informação acessível via teclado. Sem
   * `containerRef`/listener de clique fora — não fazem mais sentido num
   * tooltip que fecha sozinho ao tirar o mouse/foco.
   */
  const [aberto, setAberto] = useState<number | null>(null);

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

        {/*
          Auditoria de responsividade (2026-08-14): as 10 colunas semanais
          tinham largura mínima FIXA em pixels (`COLUNA_LARGURA_PX`, no
          `<button>`/barra) dentro de um `flex-1` que nunca deixava o item
          encolher abaixo do conteúdo (piso automático do flexbox,
          `min-width: auto`) — quando o card ficava mais estreito que essa
          soma, o conteúdo estourava a própria caixa e era cortado
          silenciosamente pelo `overflow-hidden` da raiz do AppShell
          (necessário para o layout `h-dvh`), em vez de encolher ou rolar.
          Uma primeira tentativa com `overflow-x-auto` + compensação de
          margem para não cortar o tooltip aumentou a altura do card
          incorretamente (a margem negativa não neutraliza a herdada de
          `space-y-4` do `CardContent`, que tem especificidade maior — CSS
          não some assim) — revertida.
          Correção final: `min-w-0` na coluna (remove o piso automático do
          flexbox) + `width: min(COLUNA_LARGURA_PX, 100%)` na barra (CSS
          `min()`) — a barra continua com exatamente
          `COLUNA_LARGURA_PX` sempre que a coluna tiver espaço de sobra
          (o caso de hoje, em qualquer largura confortável, pixel a pixel
          idêntico ao anterior), e só encolhe de verdade quando a coluna
          fica mais estreita que isso — nunca estoura, nunca precisa de
          scroll, nunca corta o tooltip.
        */}
        <div className="space-y-1.5">
          <div className="flex items-end gap-1.5" style={{ height: CHART_HEIGHT_PX }}>
            {semanas.map((semana, index) => {
              const valor = contagens[index] ?? 0;
              const px = valor > 0 ? Math.max(MIN_SEGMENT_PX, (valor / maior) * CHART_HEIGHT_PX) : 0;
              const estaAberto = aberto === index;
              return (
                <div
                  key={toKey(semana)}
                  className="relative flex h-full min-w-0 flex-1 flex-col-reverse items-center"
                  onMouseEnter={() => setAberto(index)}
                  onMouseLeave={() => setAberto(null)}
                >
                  <button
                    type="button"
                    onFocus={() => setAberto(index)}
                    onBlur={() => setAberto(null)}
                    aria-expanded={estaAberto}
                    className="flex h-full flex-col-reverse items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    style={{ width: `min(${COLUNA_LARGURA_PX}px, 100%)` }}
                  >
                    <div style={{ height: px, width: "100%", backgroundColor: COR_BARRA }} />
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
                className="min-w-0 flex-1 overflow-hidden whitespace-nowrap text-center text-[9px] leading-tight tabular-nums text-muted-foreground"
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
