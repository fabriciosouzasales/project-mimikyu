"use client";

import type { CSSProperties } from "react";
import { Check } from "lucide-react";
import { RaritySymbol } from "@/components/catalogo/rarity-symbol";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import type { ChecklistKind } from "@/lib/reports/collection-checklist";
import {
  RARITY_DISTRIBUTION_NOTES,
  RARITY_DISTRIBUTION_TITLE,
  type RarityBand,
  type RarityDistributionReport,
  bandAriaText,
  bandBarPercent,
  bandComplete,
  bandLabel,
  bandMissingText,
  bandOfText,
  bandPercentText,
  overallPercentText,
  rarityDistributionIncompleteText,
} from "@/lib/reports/rarity-distribution";
import type { RarityDistributionCollection } from "@/lib/reports/rarity-distribution-queries";

export { RARITY_DISTRIBUTION_TITLE };

const N = new Intl.NumberFormat("pt-BR");

/**
 * A folha é papel branco também no tema escuro: o símbolo oficial (`RaritySymbol`, tons por token)
 * recebe aqui os valores CLAROS dos tokens que usa, para não sair claro sobre branco.
 */
const PAPER_TOKENS = { "--foreground": "36 10% 10%", "--muted-foreground": "40 8% 42%", "--primary-ink": "35 66% 33%" } as CSSProperties;

/**
 * V1-14 R2-G — folha "Distribuição por raridade" (D7 v1.67 §4o). Só apresenta o que o núcleo
 * (`rarity-distribution.ts`) entregou: totais canônicos (5332), uma linha por raridade presente no
 * objetivo, na ordem do catálogo, e a conferência. Nenhuma regra de completude aqui.
 *
 * - Desktop e impressão: UMA tabela em que cada linha traz o símbolo, o nome, a barra de progresso e
 *   os números (Satisfeitas · Esperadas · Faltantes · %), com a linha de total — barra e tabela sem
 *   repetir a mesma informação em dois lugares.
 * - Celular: um cartão por raridade (nome e % acima da barra, "X de Y · faltam N" abaixo).
 * - Impressão (§2): cabeçalho institucional repetido; barras legíveis em cinza (preenchimento escuro
 *   sólido sobre trilho contornado); incompleto → a casca bloqueia a impressão.
 */
export function RarityDistributionSheet({
  collection,
  kind,
  report,
  logoUrl,
  issuedAt,
}: {
  collection: RarityDistributionCollection;
  kind: ChecklistKind;
  report: RarityDistributionReport;
  logoUrl: string | null;
  issuedAt: string;
}) {
  const identity = collection.cardSetCode ? `${collection.cardSetCode} · ${collection.cardSetName ?? collection.name}` : collection.name;
  const kindText = kind === "MASTER_SET" ? "Master Set" : "Set padrão";
  const raritiesText = `${N.format(report.rarityCount)} ${report.rarityCount === 1 ? "raridade" : "raridades"}`;
  const incomplete = rarityDistributionIncompleteText(report.incompleteReason);
  const empty = report.expected === 0 && report.bands.length === 0;
  const allComplete = report.complete && report.bands.length > 0 && report.bands.every(bandComplete);

  return (
    <RelatorioFolha>
      <div className="px-4 sm:px-6 print:px-0">
        <table className="w-full" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <thead>
            <tr>
              <th className="p-0 text-left font-normal">
                <div className="-mx-4 sm:-mx-6 print:mx-0">
                  <RelatorioCabecalho
                    ajusteCelular
                    titulo={RARITY_DISTRIBUTION_TITLE}
                    identificacaoColecao={identity}
                    colecaoLogoUrl={logoUrl}
                    subtitulo={`${kindText} · ${N.format(report.expected)} posições · ${raritiesText} · Emitido em ${issuedAt}`}
                  />
                </div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td className="p-0 align-top">
                {incomplete ? (
                  <p className="mb-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-[11px] font-medium text-amber-900" role="status">
                    {incomplete}
                  </p>
                ) : null}

                <section aria-label="Indicadores da coleção" className="grid grid-cols-2 gap-2 pb-4 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
                  <Indicator label="Completude geral" value={overallPercentText(report)} note={`${N.format(report.satisfied)} de ${N.format(report.expected)} posições`} emphasis />
                  <Indicator label="Esperadas" value={N.format(report.expected)} note="posições do objetivo" />
                  <Indicator label="Satisfeitas" value={N.format(report.satisfied)} note="com exemplar alocado" />
                  <Indicator label="Faltantes" value={N.format(report.missing)} note={report.missing === 0 && report.expected > 0 ? "coleção completa" : "posições a completar"} />
                </section>

                {empty ? (
                  <StateMessage title="Esta coleção ainda não tem posições no objetivo." text="Quando o objetivo tiver posições, a distribuição por raridade aparece aqui. Nada foi alterado." />
                ) : (
                  <section aria-labelledby="r2g-bands" style={PAPER_TOKENS}>
                    <div className="flex items-baseline justify-between gap-3 pb-2">
                      <h3 id="r2g-bands" className="font-heading text-[13px] font-bold text-neutral-900">
                        Por raridade
                      </h3>
                      <p className="text-[10px] text-neutral-500">{allComplete ? "Todas as raridades completas" : "Ordem oficial do catálogo"}</p>
                    </div>

                    {/* Desktop e impressão: barra + números na mesma linha. */}
                    <table className="hidden w-full text-left text-[11px] sm:table print:table print:text-[9.5px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
                      <colgroup>
                        <col style={{ width: "32%" }} />
                        <col />
                        <col style={{ width: "4.75rem" }} />
                        <col style={{ width: "4.5rem" }} />
                        <col style={{ width: "4.75rem" }} />
                        <col style={{ width: "3.25rem" }} />
                      </colgroup>
                      <thead>
                        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
                          <DataTableHeadCell className="bg-neutral-50">Raridade</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2">Progresso</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2 text-right">Satisfeitas</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2 text-right">Esperadas</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2 text-right">Faltantes</DataTableHeadCell>
                          <DataTableHeadCell className="bg-neutral-50 px-2 text-right last:pr-2">%</DataTableHeadCell>
                        </DataTableHeadRow>
                      </thead>
                      <tbody>
                        {report.bands.map((band) => (
                          <BandRow key={band.key} band={band} />
                        ))}
                      </tbody>
                      <tfoot>
                        <tr className="border-t-2 border-neutral-300">
                          <td className="py-2 pl-2 pr-2 font-semibold text-neutral-900">Total</td>
                          <td className="px-2 py-2">
                            <Bar band={{ satisfied: report.sumSatisfied, expected: report.sumExpected }} strong />
                          </td>
                          <td className="px-2 py-2 text-right font-semibold tabular-nums text-neutral-900">{N.format(report.sumSatisfied)}</td>
                          <td className="px-2 py-2 text-right font-semibold tabular-nums text-neutral-900">{N.format(report.sumExpected)}</td>
                          <td className="px-2 py-2 text-right font-semibold tabular-nums text-neutral-900">{N.format(report.sumExpected - report.sumSatisfied)}</td>
                          <td className="px-2 py-2 text-right font-bold tabular-nums text-neutral-900">{bandPercentText({ satisfied: report.sumSatisfied, expected: report.sumExpected })}</td>
                        </tr>
                      </tfoot>
                    </table>

                    {/* Celular: um cartão por raridade, sem rolagem horizontal. */}
                    <ul className="grid grid-cols-[minmax(0,1fr)] gap-2 sm:hidden print:hidden" aria-label="Posições por raridade">
                      {report.bands.map((band) => (
                        <li key={band.key}>
                          <BandCard band={band} />
                        </li>
                      ))}
                    </ul>
                    <div className="mt-2 flex items-baseline justify-between gap-2 rounded-md border border-neutral-200 px-3 py-2 text-xs sm:hidden print:hidden">
                      <span className="font-semibold text-neutral-900">Total</span>
                      <span className="tabular-nums text-neutral-700">
                        {N.format(report.sumSatisfied)} de {N.format(report.sumExpected)} ·{" "}
                        <span className="font-semibold text-neutral-900">{bandPercentText({ satisfied: report.sumSatisfied, expected: report.sumExpected })}</span>
                      </span>
                    </div>
                  </section>
                )}

                <ul className="mt-4 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                  {RARITY_DISTRIBUTION_NOTES.map((note) => (
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

function RarityName({ band }: { band: RarityBand }) {
  return (
    <span className="flex min-w-0 items-center gap-2">
      <span className="flex w-7 shrink-0 justify-center" aria-hidden="true">
        {band.symbolCode ? <RaritySymbol symbolCode={band.symbolCode} className="h-2.5 w-2.5" /> : <span className="h-1.5 w-1.5 rounded-full border border-neutral-400" />}
      </span>
      <span className={`min-w-0 truncate font-semibold ${band.kind === "unresolved" ? "italic text-neutral-600" : "text-neutral-900"}`} title={bandLabel(band)}>
        {band.label}
        {band.detail ? <span className="ml-1 font-normal text-neutral-500">· {band.detail}</span> : null}
      </span>
    </span>
  );
}

/**
 * Barra de progresso: trilho neutro, preenchimento dourado MMKYU (impressão: tom escuro sólido sobre
 * trilho contornado, legível em cinza). Largura por `transform` (sem reflow); sem animação.
 */
function Bar({ band, strong = false, label }: { band: Pick<RarityBand, "satisfied" | "expected">; strong?: boolean; label?: string }) {
  const percent = bandBarPercent(band);
  const complete = band.expected > 0 && band.satisfied === band.expected;
  return (
    <div
      className={`relative w-full overflow-hidden rounded-full bg-neutral-200/80 print:border print:border-neutral-400 print:bg-white ${strong ? "h-3" : "h-2.5"}`}
      role={label ? "meter" : undefined}
      aria-valuemin={label ? 0 : undefined}
      aria-valuemax={label ? 100 : undefined}
      aria-valuenow={label ? percent : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <div
        className="absolute inset-y-0 left-0 w-full origin-left rounded-full print:!bg-neutral-700"
        style={{ transform: `scaleX(${percent / 100})`, backgroundColor: complete ? "#b8862f" : "#dca54b" }}
      />
    </div>
  );
}

function BandRow({ band }: { band: RarityBand }) {
  const complete = bandComplete(band);
  return (
    <tr className="border-t border-neutral-100">
      <td className="py-2 pl-2 pr-2 align-middle">
        <RarityName band={band} />
      </td>
      <td className="px-2 py-2 align-middle">
        <Bar band={band} label={bandAriaText(band)} />
      </td>
      <td className="px-2 py-2 text-right align-middle font-semibold tabular-nums text-neutral-900">{N.format(band.satisfied)}</td>
      <td className="px-2 py-2 text-right align-middle tabular-nums text-neutral-700">{N.format(band.expected)}</td>
      <td className="px-2 py-2 text-right align-middle tabular-nums">
        {complete ? (
          <span className="inline-flex items-center gap-1 font-semibold text-primary-ink">
            <Check className="h-3 w-3" aria-hidden="true" />
            Completa
          </span>
        ) : (
          <span className="text-neutral-700">{N.format(band.missing)}</span>
        )}
      </td>
      <td className="px-2 py-2 text-right align-middle font-semibold tabular-nums text-neutral-900">{bandPercentText(band)}</td>
    </tr>
  );
}

function BandCard({ band }: { band: RarityBand }) {
  const complete = bandComplete(band);
  return (
    <div className="rounded-md border border-neutral-200 bg-white px-3 py-2.5">
      <div className="flex items-center justify-between gap-3 pb-1.5 text-xs">
        <RarityName band={band} />
        <span className="shrink-0 font-semibold tabular-nums text-neutral-900">{bandPercentText(band)}</span>
      </div>
      <Bar band={band} label={bandAriaText(band)} />
      <p className="flex items-center justify-between gap-2 pt-1.5 text-[11px] tabular-nums text-neutral-600">
        <span>
          {bandOfText(band)} {band.expected === 1 ? "posição" : "posições"}
        </span>
        {complete ? (
          <span className="inline-flex items-center gap-1 font-semibold text-primary-ink">
            <Check className="h-3 w-3" aria-hidden="true" />
            Completa
          </span>
        ) : (
          <span>{bandMissingText(band)}</span>
        )}
      </p>
    </div>
  );
}

function StateMessage({ title, text }: { title: string; text: string }) {
  return (
    <div className="my-4 rounded-lg border border-dashed border-neutral-300 px-6 py-8 text-center" role="status">
      <p className="text-sm font-semibold text-neutral-900">{title}</p>
      <p className="mt-2 text-xs text-neutral-600">{text}</p>
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
