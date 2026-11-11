"use client";

import { useState } from "react";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { cardFrontUrl } from "@/lib/colecoes/acervo";
import type { ChecklistReportCollection } from "@/lib/reports/checklist-queries";
import { checklistFinishLegend } from "@/lib/reports/collection-checklist";
import { PrintImageGate } from "./print-image-gate";
import {
  MISSING_SCREEN_FILTERS,
  type MissingCardsReport,
  type MissingGroup,
  type MissingLine,
  type MissingScreenFilter,
  missingAvailabilityText,
  missingFinishText,
  missingGroupsForScreen,
  missingHeaderLine,
  missingPrintPairs,
} from "@/lib/reports/missing-cards";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
export const MISSING_TITLE = "Cartas faltantes";
/** Miniaturas imediatas até este nº de linhas; acima, sob demanda (só na tela — a impressão não tem miniaturas). */
const EAGER_IMAGES_MAX = 60;

/**
 * V1-14 R2-B — folha "Cartas faltantes" (D7 v1.42 §4j). Mesma folha institucional dos relatórios
 * contextuais (rodapé "Página X de Y" pela casca).
 *
 * - Cabeçalho institucional em TODAS as páginas impressas: `<thead>` da tabela externa (mecanismo
 *   homologado na R1-H); KPIs só na 1ª página (no corpo).
 * - TELA: filtros Todas · No acervo · Sem exemplar disponível (só a visualização), grupos com
 *   miniatura original (`card-front`, sem transformação), número, nome, acabamentos faltantes com a
 *   disponibilidade de cada um; responsiva (uma coluna no celular, duas a partir de `sm`).
 * - IMPRESSÃO: sempre o conjunto completo (o filtro da tela não se aplica), cartões de checklist
 *   em duas colunas com a miniatura canônica (12 × 16,8 mm, preparada pelo botão Imprimir), caixa vazia para marcação manual (no Master Set, uma caixa por
 *   acabamento = uma por posição); título do grupo no `<thead>` de cada grupo (repete na quebra);
 *   cartões indivisíveis; legenda das siglas e notas.
 */
export function MissingCardsSheet({
  collection,
  report,
  logoUrl,
  issuedAt,
}: {
  collection: ChecklistReportCollection;
  report: MissingCardsReport;
  logoUrl: string | null;
  issuedAt: string;
}) {
  const [filter, setFilter] = useState<MissingScreenFilter>("all");
  const identity = collection.cardSetCode ? `${collection.cardSetCode} · ${collection.cardSetName ?? collection.name}` : collection.name;
  const cabecalho = (
    <RelatorioCabecalho
      ajusteCelular
      titulo={MISSING_TITLE}
      identificacaoColecao={identity}
      colecaoLogoUrl={logoUrl}
      subtitulo={missingHeaderLine(report, issuedAt)}
    />
  );
  const isMaster = report.kind === "MASTER_SET";
  const legend = isMaster ? checklistFinishLegend(report.groups.flatMap((g) => g.lines.flatMap((l) => l.finishes.map((f) => f.label)))) : [];
  const eager = report.groups.reduce((n, g) => n + g.lines.length, 0) <= EAGER_IMAGES_MAX;

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <thead>
            <tr>
              <th className="p-0 text-left font-normal">
                <div className="-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr style={{ breakInside: "auto", pageBreakInside: "auto" }}>
              <td className="p-0 align-top">
                {report.state === "empty" ? (
                  <StateMessage title="Este objetivo ainda não tem posições." text="Quando o Set tiver cartas no catálogo, as posições aparecem aqui." />
                ) : report.state === "complete" ? (
                  <StateMessage
                    positive
                    title="Coleção completa!"
                    text={`Todas as ${new Intl.NumberFormat("pt-BR").format(report.summary.total)} posições do objetivo estão na coleção — nenhuma carta faltante.`}
                  />
                ) : (
                  <>
                    <section aria-label="Indicadores das cartas faltantes" className="grid grid-cols-2 gap-2 pb-3 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
                      <Indicator
                        label="Faltam"
                        value={formatCount(report.missingPositions)}
                        note={isMaster ? `de ${formatCount(report.summary.total)} posições · ${plural(report.pendingCards, "carta", "cartas")}` : `de ${formatCount(report.summary.total)} posições`}
                        emphasis
                      />
                      <Indicator label="Completo" value={report.summary.percentText} note={`${formatCount(report.summary.owned)} na coleção`} />
                      <Indicator label="No acervo" value={formatCount(report.availablePositions)} note="disponíveis para alocar" />
                      <Indicator label="Sem exemplar disponível" value={formatCount(report.unavailablePositions)} note="sem cópia livre identificada" />
                    </section>

                    {/* Filtros: só a TELA; a impressão sempre traz o conjunto completo. */}
                    <div role="group" aria-label="Filtrar cartas faltantes" className="mb-3 flex flex-wrap gap-2 print:hidden">
                      {MISSING_SCREEN_FILTERS.map((option) => (
                        <button
                          key={option.value}
                          type="button"
                          aria-pressed={filter === option.value}
                          onClick={() => setFilter(option.value)}
                          className={`min-h-9 rounded-full border px-3 text-xs font-medium transition-colors ${filter === option.value ? "border-primary bg-primary/10 text-neutral-900" : "border-neutral-200 text-neutral-600 hover:border-neutral-300"}`}
                        >
                          {option.label}
                        </button>
                      ))}
                    </div>

                    <div className="print:hidden">
                      {missingGroupsForScreen(report.groups, filter).map((group) => (
                        <ScreenGroup key={group.id} group={group} isMaster={isMaster} eager={eager} />
                      ))}
                    </div>

                    {/*
                      Impressão com miniaturas (PRINT CARD THUMBNAILS-02): o MESMO mecanismo da R1-G — imagens
                      originais do bucket `card-front` (mesmo endereço da tela, cache do navegador; nenhuma
                      transformação), sob demanda, preparadas pelo botão Imprimir (`preparePrintImages`: só as
                      pendentes, no máximo 6 simultâneas, progresso real, 30 s por imagem). O `PrintImageGate`
                      envolve só a parte impressa: com miniatura pendente ou com falha, Ctrl+P imprime o aviso no
                      lugar dos cartões — nunca cartões com quadro vazio por carregamento pendente.
                    */}
                    <div className="hidden print:block">
                      <PrintImageGate>
                        {report.groups.map((group) => (
                          <PrintGroup key={group.id} group={group} isMaster={isMaster} />
                        ))}
                      </PrintImageGate>
                    </div>

                    <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                      {legend.length > 0 ? (
                        <li>
                          Acabamentos: {legend.map((entry) => `${entry.code} = ${entry.label}`).join(" · ")}.
                        </li>
                      ) : null}
                      <li>
                        Mesma regra do Checklist de completude: faltante = posição do objetivo sem exemplar alocado a esta coleção; contagens sempre por
                        posição{isMaster ? " (carta + acabamento; acabamentos da mesma carta aparecem juntos numa linha)" : ""}.
                      </li>
                      <li>
                        &ldquo;No acervo&rdquo;: há exemplar livre — fora de qualquer coleção — que atende a posição; o mesmo exemplar livre pode aparecer
                        também no relatório de outra coleção. &ldquo;Sem exemplar disponível&rdquo;: nenhuma cópia livre identificada — a carta pode estar
                        alocada em outra coleção. Retrato do momento da leitura; nada é alterado.
                      </li>
                    </ul>
                  </>
                )}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <RelatorioRodape />
    </RelatorioFolha>
  );
}

function ScreenGroup({ group, isMaster, eager }: { group: MissingGroup; isMaster: boolean; eager: boolean }) {
  const available = group.id === "available";
  return (
    <section className="mb-4" aria-label={group.title}>
      <h3 className={`mb-2 flex items-baseline gap-2 border-l-4 pl-2 text-[12px] font-semibold text-neutral-900 ${available ? "border-l-primary" : "border-l-neutral-300"}`}>
        {group.title}
        <span className="font-normal text-neutral-500">· {plural(group.positions, "posição", "posições")}</span>
      </h3>
      <ul className="grid grid-cols-[minmax(0,1fr)] gap-2 sm:grid-cols-2">
        {group.lines.map((line) => (
          <ScreenLine key={line.key} line={line} isMaster={isMaster} available={available} eager={eager} />
        ))}
      </ul>
    </section>
  );
}

function ScreenLine({ line, isMaster, available, eager }: { line: MissingLine; isMaster: boolean; available: boolean; eager: boolean }) {
  const src = cardFrontUrl(SUPABASE_URL, line.imagePath);
  return (
    <li className={`flex items-center gap-3 rounded-md border px-2 py-1.5 ${available ? "border-primary/40 bg-primary/5" : "border-neutral-200"}`}>
      <span aria-hidden="true" className="h-[56px] w-[40px] shrink-0 overflow-hidden rounded-[3px] border border-neutral-200 bg-neutral-100">
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador de imagens (mesma regra das demais miniaturas)
          <img src={src} alt="" width={40} height={56} loading={eager ? "eager" : "lazy"} decoding="async" className="h-full w-full object-cover" />
        ) : null}
      </span>
      <span className="min-w-0 flex-1 leading-snug">
        <span className="block text-[11px] text-neutral-900">
          <span className="tabular-nums text-neutral-500">{line.number || "—"}</span> <span className="font-semibold">{line.name}</span>
        </span>
        {isMaster ? (
          <span className="mt-0.5 flex flex-wrap gap-1">
            {line.finishes.map((finish) => (
              <span
                key={finish.key}
                title={`${finish.label} · ${missingAvailabilityText(finish.available)}`}
                className={`rounded-full border px-1.5 text-[10px] ${finish.available > 0 ? "border-primary/50 text-neutral-900" : "border-neutral-200 text-neutral-600"}`}
              >
                {missingFinishText(finish)}
                {finish.available > 0 ? <span className="text-neutral-500"> · {finish.available} livre{finish.available === 1 ? "" : "s"}</span> : null}
              </span>
            ))}
          </span>
        ) : (
          <span className="block text-[10px] text-neutral-500">{missingAvailabilityText(line.available)}</span>
        )}
      </span>
    </li>
  );
}

/**
 * Impressão (PREMIUM PRINT REDESIGN-01): por grupo, CARTÕES de checklist em duas colunas
 * equilibradas (pares em ordem de leitura). Estrutura de tabela mantida de propósito — é o
 * mecanismo homologado de paginação: o `<thead>` do grupo (título + nº de posições) se repete na
 * quebra e nunca fica isolado no pé da página, e cada par de cartões é uma linha indivisível
 * (`.relatorio-folha tr { break-inside: avoid }`), então nenhum cartão se parte.
 * Cartão: caixa de marcação confortável, número, nome em destaque; no Master Set, cada acabamento
 * faltante com a PRÓPRIA caixa (uma posição = uma caixa), sigla e nome por extenso.
 */
function PrintGroup({ group, isMaster }: { group: MissingGroup; isMaster: boolean }) {
  const pairs = missingPrintPairs(group.lines);
  const available = group.id === "available";
  return (
    <table className="mt-4 w-full text-left" style={{ borderCollapse: "separate", borderSpacing: "3mm 1.8mm", tableLayout: "fixed" }} data-missing-print-group={group.id}>
      <colgroup>
        <col style={{ width: "50%" }} />
        <col style={{ width: "50%" }} />
      </colgroup>
      <thead>
        <tr style={{ breakAfter: "avoid" }}>
          <th colSpan={2} className="p-0 text-left font-normal">
            <div className={`flex items-baseline justify-between border-b pb-1 ${available ? "border-primary" : "border-neutral-300"}`}>
              <span className="text-[12.5px] font-semibold text-neutral-900">
                <span aria-hidden="true" className={`mr-2 inline-block h-2.5 w-2.5 rounded-full align-middle ${available ? "bg-primary" : "bg-neutral-400"}`} />
                {group.title}
              </span>
              <span className="text-[10px] tabular-nums text-neutral-500">{plural(group.positions, "posição", "posições")}</span>
            </div>
          </th>
        </tr>
      </thead>
      <tbody>
        {pairs.map(([left, right]) => (
          <tr key={left.key} style={{ breakInside: "avoid" }}>
            <td className="p-0 align-top">
              <PrintCard line={left} isMaster={isMaster} />
            </td>
            <td className="p-0 align-top">{right ? <PrintCard line={right} isMaster={isMaster} /> : null}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Caixa vazia para marcação à mão (tamanho confortável na principal; menor por acabamento). */
function CheckBox({ size }: { size: "lg" | "sm" }) {
  return (
    <span
      aria-hidden="true"
      data-check-box={size}
      className={`inline-block shrink-0 rounded-[3px] border-[1.5px] border-neutral-500 bg-white ${size === "lg" ? "h-[5mm] w-[5mm]" : "h-[3.6mm] w-[3.6mm]"}`}
    />
  );
}

/**
 * Miniatura impressa (PRINT DENSITY CORRECTION-03): 12 × 16,8 mm (proporção da carta, 63:88) —
 * reconhecível sem dominar o cartão. Cartão do Set padrão ≈ 21 mm (miniatura + 2 mm de respiro);
 * no Master Set cresce só com a lista de acabamentos (sem altura fixa).
 */
export const PRINT_THUMB_MM = { width: 12, height: 16.8 } as const;

function PrintCard({ line, isMaster }: { line: MissingLine; isMaster: boolean }) {
  const src = cardFrontUrl(SUPABASE_URL, line.imagePath);
  return (
    <div className="flex items-start gap-2 rounded-md border border-neutral-300 px-2 py-[1.8mm]" style={{ breakInside: "avoid" }} data-missing-print-card="">
      <span
        className="shrink-0 overflow-hidden rounded-[1mm] border border-neutral-200 bg-neutral-100"
        style={{ width: `${PRINT_THUMB_MM.width}mm`, height: `${PRINT_THUMB_MM.height}mm` }}
        data-missing-print-thumb=""
      >
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador (mesma regra das demais miniaturas)
          <img src={src} alt="" width={120} height={168} loading="lazy" decoding="async" className="h-full w-full object-cover" />
        ) : (
          // Sem imagem canônica: o quadro diz isso (nunca omitido em silêncio).
          <span className="flex h-full w-full items-center justify-center px-0.5 text-center text-[6.5px] leading-tight text-neutral-500">Sem imagem no catálogo</span>
        )}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-start gap-2">
          {/* Set padrão: uma posição = a caixa do cartão. Master Set: a caixa é de cada acabamento (abaixo). */}
          {isMaster ? null : <CheckBox size="lg" />}
          <div className="min-w-0">
            <p className="text-[9.5px] font-medium uppercase tracking-wide tabular-nums text-neutral-500">Nº {line.number || "—"}</p>
            <p className="text-[12.5px] font-semibold leading-snug text-neutral-900">{line.name}</p>
          </div>
        </div>
        {isMaster ? (
          <ul className="mt-1 flex flex-col gap-[0.8mm]" aria-label="Acabamentos faltantes">
            {line.finishes.map((finish) => (
              <li key={finish.key} className="flex items-center gap-1.5 text-[10.5px] leading-tight text-neutral-800" data-missing-print-finish="">
                <CheckBox size="sm" />
                {finish.code ? (
                  <span>
                    <span className="font-semibold">{finish.code}</span> <span className="text-neutral-600">{finish.label}</span>
                  </span>
                ) : (
                  <span className="font-semibold">{finish.label}</span>
                )}
              </li>
            ))}
          </ul>
        ) : null}
      </div>
    </div>
  );
}

function StateMessage({ title, text, positive = false }: { title: string; text: string; positive?: boolean }) {
  return (
    <div className={`my-6 rounded-lg border px-6 py-8 text-center ${positive ? "border-primary/50 bg-primary/5" : "border-neutral-200"}`} style={{ breakInside: "avoid" }}>
      <p className="text-sm font-semibold text-neutral-900">{title}</p>
      <p className="mt-2 text-xs text-neutral-600">{text}</p>
    </div>
  );
}

function Indicator({ label, value, note, emphasis = false }: { label: string; value: string; note?: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="truncate text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="truncate font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
      {note ? <p className="truncate text-[9px] leading-snug text-neutral-500">{note}</p> : null}
    </div>
  );
}

const N = new Intl.NumberFormat("pt-BR");
const formatCount = (n: number) => N.format(n);
const plural = (n: number, one: string, many: string) => `${N.format(n)} ${n === 1 ? one : many}`;
