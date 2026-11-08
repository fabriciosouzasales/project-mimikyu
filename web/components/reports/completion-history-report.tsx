"use client";

import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { progressPercentText } from "@/lib/colecoes/colecoes";
import type { ChecklistKind } from "@/lib/reports/collection-checklist";
import {
  COMPLETION_HISTORY_NOTES,
  COMPLETION_HISTORY_TITLE,
  type CompletionChange,
  type CompletionGap,
  type CompletionReport,
  changeFacts,
  changeTitleText,
  changeWhenText,
  completionEntries,
  dayText,
  gapNoticeText,
  gapText,
  ofText,
  positionsText,
  readAtText,
  signed,
  signedPp,
  sinceLastClosingText,
} from "@/lib/reports/completion-history";
import type { CompletionHistoryCollection } from "@/lib/reports/completion-history-queries";
import { CompletionHistoryChart } from "./completion-history-chart";

export { COMPLETION_HISTORY_TITLE };

const N = new Intl.NumberFormat("pt-BR");
/** Altura do gráfico: tela (desktop/celular) e impressão (1ª folha, abaixo dos indicadores). */
const CHART_HEIGHT = { screen: 248, print: 300 } as const;

/**
 * V1-14 R2-F (B2) — folha "Evolução da completude" (D7 v1.63 §4n, D10/D11). Só apresenta o que o núcleo
 * (`completion-history.ts`) entregou: completude atual canônica (5332/5188), fechamentos registrados
 * (5358), lacunas e mudanças observadas. Nenhuma regra de completude, nenhum valor estimado.
 *
 * - Tela: desktop com indicadores e gráfico lado a lado e a lista abaixo; celular com indicadores
 *   empilhados, gráfico em largura total e a lista em cartões.
 * - Estados: sem fechamento ainda; um único fechamento; sem mudanças desde o início; lacunas.
 * - Impressão (D11): cabeçalho institucional repetido (`<thead>` externo); indicadores e gráfico
 *   (instância estática de largura A4, escala de cinza) só na 1ª folha; mudanças e lacunas a partir
 *   da 2ª, com os títulos das colunas repetidos; rodapé "Página X de Y" da casca.
 */
export function CompletionHistorySheet({
  collection,
  kind,
  report,
  logoUrl,
  issuedAt,
  readAtMs,
}: {
  collection: CompletionHistoryCollection;
  kind: ChecklistKind;
  report: CompletionReport;
  logoUrl: string | null;
  issuedAt: string;
  readAtMs: number;
}) {
  const identity = collection.cardSetCode ? `${collection.cardSetCode} · ${collection.cardSetName ?? collection.name}` : collection.name;
  const kindText = kind === "MASTER_SET" ? "Master Set" : "Set padrão";
  const tracking = report.trackingSince ? `Acompanhando desde ${dayText(report.trackingSince)}` : "Acompanhamento a partir do próximo fechamento";
  const cabecalho = (
    <RelatorioCabecalho
      titulo={COMPLETION_HISTORY_TITLE}
      identificacaoColecao={identity}
      colecaoLogoUrl={logoUrl}
      subtitulo={`${kindText}${collection.archived ? " · arquivada" : ""} · ${tracking} · Emitido em ${issuedAt}`}
    />
  );
  const { now } = report;
  const since = report.first ? dayText(report.first.day) : null;
  const gapNotice = gapNoticeText(report);
  const sinceLast = sinceLastClosingText(report);
  const entries = completionEntries(report);

  return (
    <RelatorioFolha>
      <div className="px-4 sm:px-6 print:px-0">
        <table className="w-full" style={{ borderCollapse: "collapse" }}>
          <thead>
            <tr>
              <th className="p-0 text-left font-normal">
                <div className="-mx-4 sm:-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td className="p-0 align-top">
                {/* Marco do acompanhamento (D2/D3): sempre visível. */}
                <dl className="flex flex-wrap gap-x-6 gap-y-1 pb-3 pt-1 text-[11px] leading-snug text-neutral-600" style={{ breakInside: "avoid" }}>
                  <div className="flex gap-1.5">
                    <dt className="text-neutral-500">Acompanhando desde</dt>
                    <dd className="font-semibold tabular-nums text-neutral-900">{report.trackingSince ? dayText(report.trackingSince) : "o próximo fechamento"}</dd>
                  </div>
                  <div className="flex gap-1.5">
                    <dt className="text-neutral-500">Último fechamento</dt>
                    <dd className="font-semibold tabular-nums text-neutral-900">
                      {report.lastCoveredDay ? dayText(report.lastCoveredDay) : "ainda nenhum"}
                      {report.lastClosing && report.lastCoveredDay === report.lastClosing.day ? (
                        <span className="ml-1 font-normal text-neutral-500">· {readAtText(report.lastClosing.capturedAt)}</span>
                      ) : null}
                    </dd>
                  </div>
                </dl>

                {gapNotice ? (
                  <p className="mb-3 rounded-md border border-neutral-200 bg-neutral-50 px-3 py-2 text-[11px] text-neutral-700" role="note" style={{ breakInside: "avoid" }}>
                    {gapNotice}
                  </p>
                ) : null}

                <div className="grid grid-cols-1 gap-3 pb-3 sm:grid-cols-[13.5rem_minmax(0,1fr)] print:grid-cols-1" style={{ breakInside: "avoid" }}>
                  <section aria-label="Indicadores da evolução da completude" className="grid grid-cols-1 content-start gap-2 print:grid-cols-3">
                    <Indicator label="Completude atual" value={progressPercentText(now.satisfied, now.total)} note={`${ofText(now.satisfied, now.total)} · agora`} emphasis />
                    <Indicator
                      label="Variação desde o início"
                      value={report.delta ? `${signed(report.delta.satisfied)} ${Math.abs(report.delta.satisfied) === 1 ? "posição" : "posições"}` : "—"}
                      note={report.delta && since ? `${signedPp(report.delta.pp)} · desde ${since}` : "Começa no primeiro fechamento"}
                    />
                    <Indicator
                      label="Total esperado"
                      value={positionsText(now.total)}
                      note={report.delta && since ? (report.delta.total === 0 ? `Sem variação desde ${since}` : `${signed(report.delta.total)} desde ${since}`) : "Posições do objetivo, agora"}
                    />
                  </section>

                  <ChartArea report={report} readAtMs={readAtMs} />
                </div>

                {sinceLast ? <p className="-mt-1 pb-3 text-[10.5px] text-neutral-600">{sinceLast}</p> : null}

                {report.state === "no_history" ? null : (
                  <section aria-labelledby="r2f-changes" className="pt-1 print:[break-before:page]">
                    <h3 id="r2f-changes" className="pb-1.5 font-heading text-[13px] font-bold text-neutral-900">
                      Mudanças registradas
                    </h3>
                    {!report.hasChanges && since ? <p className="pb-2 text-[11px] text-neutral-600">Sem mudanças desde {since}.</p> : null}

                    {/* Desktop/tablet e impressão: tabela. */}
                    <table className="hidden w-full text-left text-[10.5px] sm:table print:table print:text-[9.5px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
                      <colgroup>
                        <col style={{ width: "34%" }} />
                        <col />
                        <col style={{ width: "4.5rem" }} />
                        <col style={{ width: "4.5rem" }} />
                        <col style={{ width: "3.5rem" }} />
                      </colgroup>
                      <thead>
                        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
                          <DataTableHeadCell className="bg-neutral-50">Quando</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2">Observado</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2 text-right">Satisfeitas</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2 text-right">Total</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2 text-right last:pr-2">%</DataTableHeadCell>
                        </DataTableHeadRow>
                      </thead>
                      <tbody>
                        {entries.map((entry, index) =>
                          entry.change ? <ChangeRow key={entry.key} change={entry.change} index={index} /> : entry.gap ? <GapRow key={entry.key} gap={entry.gap} /> : null,
                        )}
                      </tbody>
                    </table>

                    {/* Celular: cartões. */}
                    <ul className="grid grid-cols-1 gap-2 sm:hidden print:hidden" aria-label="Mudanças registradas e dias sem registro">
                      {entries.map((entry) => (
                        <li key={entry.key}>{entry.change ? <ChangeCard change={entry.change} /> : entry.gap ? <GapCard gap={entry.gap} /> : null}</li>
                      ))}
                    </ul>
                  </section>
                )}

                <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                  {COMPLETION_HISTORY_NOTES.map((note) => (
                    <li key={note}>{note}</li>
                  ))}
                </ul>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <RelatorioRodape />
    </RelatorioFolha>
  );
}

function ChartArea({ report, readAtMs }: { report: CompletionReport; readAtMs: number }) {
  if (report.state === "no_history") {
    return (
      <StateMessage
        title="O acompanhamento começa no fechamento desta noite."
        text="A cada dia, logo depois da meia-noite, a completude desta coleção é registrada. A evolução aparece a partir dos próximos fechamentos; nada é reconstruído antes disso."
      />
    );
  }
  if (report.state === "single") {
    return (
      <StateMessage
        title="A evolução aparece a partir do próximo fechamento."
        text={`Primeiro fechamento registrado em ${dayText(report.trackingSince!)}: ${ofText(report.first!.satisfied, report.first!.total)} satisfeitas.`}
      />
    );
  }
  return (
    <figure className="m-0 min-w-0 rounded-md border border-neutral-200 px-2 pb-2 pt-1 print:border-0 print:px-0">
      <div className="print:hidden">
        <CompletionHistoryChart report={report} nowMs={readAtMs} height={CHART_HEIGHT.screen} />
      </div>
      <div className="hidden print:block">
        <CompletionHistoryChart report={report} nowMs={readAtMs} height={CHART_HEIGHT.print} print />
      </div>
      <Legend />
    </figure>
  );
}

/** Legenda em texto + formas (não depende de cor — D11). */
function Legend() {
  const item = "inline-flex items-center gap-1.5";
  return (
    <figcaption className="flex flex-wrap gap-x-4 gap-y-1 px-1 pt-1 text-[9.5px] text-neutral-600">
      <span className={item}>
        <svg width="18" height="8" aria-hidden="true">
          <path d="M1 6 H9 V2 H17" fill="none" stroke="#8c5d1d" strokeWidth="2" />
        </svg>
        Posições satisfeitas (por fechamento)
      </span>
      <span className={item}>
        <svg width="18" height="8" aria-hidden="true">
          <path d="M1 4 H17" fill="none" stroke="#8a8a8a" strokeWidth="1.25" strokeDasharray="4 3" />
        </svg>
        Total esperado
      </span>
      <span className={item}>
        <svg width="10" height="10" aria-hidden="true">
          <path d="M5 0.5 L9.5 5 L5 9.5 L0.5 5 Z" fill="#171717" />
        </svg>
        Mudança de objetivo ou situação
      </span>
      <span className={item}>
        <svg width="10" height="10" aria-hidden="true">
          <circle cx="5" cy="5" r="3.6" fill="#fff" stroke="#8c5d1d" strokeWidth="1.8" />
        </svg>
        Agora (ao vivo, ainda não é fechamento)
      </span>
      <span className={item}>
        <svg width="18" height="8" aria-hidden="true">
          <path d="M1 4 H6 M12 4 H17" fill="none" stroke="#8c5d1d" strokeWidth="2" />
        </svg>
        Interrupção = dias sem registro
      </span>
    </figcaption>
  );
}

function CausesLine({ change }: { change: CompletionChange }) {
  if (change.kind === "start" || change.causes.length === 0) return null;
  return <span className="block text-[9.5px] font-medium text-neutral-800">{change.causes.map((c) => c.text).join(" · ")}</span>;
}

function ChangeRow({ change, index }: { change: CompletionChange; index: number }) {
  return (
    <tr className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED" }}>
      <td className="py-1.5 pl-2 pr-2 align-top">
        <span className="block font-semibold text-neutral-900">{changeWhenText(change)}</span>
        <span className="block text-[9px] text-neutral-500">{readAtText(change.capturedAt)}</span>
      </td>
      <td className="px-2 py-1.5 align-top">
        <span className="block text-neutral-700">{changeTitleText(change)}</span>
        {change.kind === "start" ? null : <span className="block text-[9.5px] text-neutral-600">{changeFacts(change).join(" · ")}</span>}
        <CausesLine change={change} />
      </td>
      <td className="px-2 py-1.5 text-right align-top font-semibold tabular-nums text-neutral-900">{N.format(change.satisfied)}</td>
      <td className="px-2 py-1.5 text-right align-top tabular-nums text-neutral-700">{N.format(change.total)}</td>
      <td className="px-2 py-1.5 text-right align-top tabular-nums text-neutral-700">{progressPercentText(change.satisfied, change.total)}</td>
    </tr>
  );
}

function GapRow({ gap }: { gap: CompletionGap }) {
  return (
    <tr className="border-t border-neutral-100">
      <td colSpan={5} className="px-2 py-1.5 text-[10px] italic text-neutral-600" style={{ backgroundImage: "repeating-linear-gradient(135deg, #fafafa 0 6px, #f1f1f1 6px 7px)" }}>
        {gapText(gap)} — sem valor; nada é estimado
      </td>
    </tr>
  );
}

function ChangeCard({ change }: { change: CompletionChange }) {
  return (
    <div className="rounded-md border border-neutral-200 bg-white px-3 py-2">
      <p className="flex items-baseline justify-between gap-2">
        <span className="text-xs font-semibold text-neutral-900">{changeWhenText(change)}</span>
        <span className="shrink-0 text-xs font-semibold tabular-nums text-neutral-900">{progressPercentText(change.satisfied, change.total)}</span>
      </p>
      <p className="text-[10px] text-neutral-500">
        {changeTitleText(change)} · {readAtText(change.capturedAt)}
      </p>
      <p className="mt-1 text-[11px] text-neutral-800">{changeFacts(change).join(" · ")}</p>
      {change.kind !== "start" ? <p className="text-[10px] text-neutral-600">{ofText(change.satisfied, change.total)} satisfeitas</p> : null}
      <CausesLine change={change} />
    </div>
  );
}

function GapCard({ gap }: { gap: CompletionGap }) {
  return (
    <div className="rounded-md border border-dashed border-neutral-300 bg-neutral-50 px-3 py-2 text-[11px] text-neutral-600">
      {gapText(gap)}
      <span className="block text-[10px] text-neutral-500">Sem valor; nada é estimado.</span>
    </div>
  );
}

function StateMessage({ title, text }: { title: string; text: string }) {
  return (
    <div className="flex min-h-[10rem] flex-col items-center justify-center rounded-md border border-dashed border-neutral-300 px-6 py-6 text-center" role="status">
      <p className="text-sm font-semibold text-neutral-900">{title}</p>
      <p className="mt-2 max-w-md text-xs text-neutral-600">{text}</p>
    </div>
  );
}

function Indicator({ label, value, note, emphasis = false }: { label: string; value: string; note?: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
      {note ? <p className="text-[9px] leading-snug text-neutral-500">{note}</p> : null}
    </div>
  );
}
