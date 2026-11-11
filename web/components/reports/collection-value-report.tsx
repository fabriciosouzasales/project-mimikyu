"use client";

import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import {
  type CollectionValueLine,
  type CollectionValueReport,
  collectionValueAllocatedText,
  collectionValueCollectorText,
  collectionValueCoverageText,
  collectionValueLanguageText,
  collectionValueLineText,
  collectionValueNotes,
  collectionValueObservedText,
  collectionValuePriceFlags,
  collectionValueTotalText,
  collectionValueUnitText,
  collectionValueUnpricedText,
  collectionValueVariantText,
} from "@/lib/reports/collection-value";
import type { CollectionValueCollection, CollectionValueKind } from "@/lib/reports/collection-value-queries";
import { PrintImageGate } from "./print-image-gate";

export const COLLECTION_VALUE_TITLE = "Valor estimado";
const COLLECTION_VALUE_KIND_TEXT: Record<CollectionValueKind, string> = {
  STANDARD_SET: "Set padrão",
  MASTER_SET: "Master Set",
  POKEDEX: "Pokédex",
  FREE: "Coleção livre",
};
/** Miniaturas imediatas até este nº de linhas na tela; acima, sob demanda. */
const EAGER_IMAGES_MAX = 60;
const COLUMNS = 4;
/**
 * E4 — impressão A4 (`@page mmkyu-relatorio`: margens 10/10/14/10 mm → área útil 190 × 273 mm).
 * Linhas de altura FIXA em mm (nunca estimativa de fonte): miniatura de 9 × 12,6 mm (proporção da
 * carta 63:88) e linha de 13,5 mm (miniatura + 0,9 mm de respiro). Estimativa a confirmar na
 * homologação: ≈ 16–17 linhas por folha, ≈ 14–15 na 1ª (indicadores).
 */
export const COLLECTION_VALUE_PRINT_THUMB_MM = { width: 9, height: 12.6 } as const;
export const COLLECTION_VALUE_PRINT_ROW_MM = 13.5;

const N = new Intl.NumberFormat("pt-BR");
const plural = (n: number, one: string, many: string) => `${N.format(n)} ${n === 1 ? one : many}`;

/**
 * V1-14 R2-E — folha "Valor estimado dos exemplares alocados" (D7 v1.59 §4m). E3: TELA (desktop e
 * celular). A folha só apresenta o que o núcleo financeiro (E1/E2, `collection-value.ts`) entregou —
 * linhas já ordenadas, valores em centavos, estados A/B/C, indicadores e notas; nenhum cálculo
 * financeiro aqui.
 *
 * - Desktop: tabela financeira (Carta · Qtd. · Referência NM · Valor), valores à direita, algarismos
 *   tabulares; grupos sem cotação e com preço indisponível num bloco final rotulado "fora da soma".
 * - Celular: cartões de uma coluna, "quantidade × unitário = valor", sinais em texto.
 * - Provisório (falha técnica de preço) e incompleto (integridade) identificados na folha e nos totais.
 * - IMPRESSÃO (E4): cabeçalho institucional repetido (`<thead>` da tabela externa); indicadores só na
 *   1ª folha; tabela própria de impressão com os títulos das colunas no `<thead>` (repetem em cada
 *   folha), linhas de altura fixa indivisíveis, miniaturas originais preparadas pelo mecanismo da R1-G
 *   (`PrintImageGate`), total e notas no fim; sem caixa de marcação. A tela não muda: as partes de
 *   tela recebem só `print:hidden`.
 */
export function CollectionValueSheet({
  collection,
  kind,
  report,
  logoUrl,
  issuedAt,
}: {
  collection: CollectionValueCollection;
  kind: CollectionValueKind;
  report: CollectionValueReport;
  logoUrl: string | null;
  issuedAt: string;
}) {
  const identity = collection.cardSetCode ? `${collection.cardSetCode} · ${collection.cardSetName ?? collection.name}` : collection.name;
  const kindText = COLLECTION_VALUE_KIND_TEXT[kind];
  // Pokédex e Coleção livre reúnem vários Card Sets (F2-1): a ordem é por Set e, dentro dele, pelo número.
  const orderText = kind === "POKEDEX" || kind === "FREE" ? "na ordem dos Sets" : "na ordem do Set";
  const cabecalho = (
    <RelatorioCabecalho
      ajusteCelular
      titulo="Valor estimado dos exemplares alocados"
      identificacaoColecao={identity}
      colecaoLogoUrl={logoUrl}
      subtitulo={`${kindText} · ${plural(report.copies, "exemplar alocado", "exemplares alocados")} · Emitido em ${issuedAt}`}
    />
  );
  const eager = report.lines.length <= EAGER_IMAGES_MAX;
  const priced = report.lines.filter((line) => line.state === "priced");
  const outside = report.lines.filter((line) => line.state !== "priced");
  const allocated = collectionValueAllocatedText(report);
  const unpriced = collectionValueUnpricedText(report);
  const totalText = collectionValueTotalText(report);
  // Total incompleto nunca aparece como definitivo.
  const qualifier = !report.complete ? "não definitivo — relatório incompleto" : report.provisional ? "parcial — preço indisponível em parte dos itens" : null;
  const notes = collectionValueNotes({
    masterSet: kind === "MASTER_SET",
    pokedex: kind === "POKEDEX",
    free: kind === "FREE",
    observedFrom: report.observedFrom,
    observedTo: report.observedTo,
  });

  return (
    <RelatorioFolha>
      <div className="px-4 sm:px-6 print:px-0">
        <table className="w-full" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
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
                {report.state === "empty" ? (
                  <StateMessage
                    title="Nenhum exemplar alocado a esta coleção."
                    text="Quando você alocar exemplares do seu acervo a esta coleção, o valor estimado deles aparece aqui. Nada foi alterado."
                  />
                ) : (
                  <>
                    {qualifier ? <StatusBanner complete={report.complete} /> : null}

                    <section aria-label="Indicadores do valor estimado" className="grid grid-cols-1 gap-2 pb-3 pt-1 sm:grid-cols-3 print:grid-cols-3" style={{ breakInside: "avoid" }}>
                      <Indicator label="Valor estimado" value={totalText} note={qualifier ?? collectionValueCoverageText(report)} emphasis warn={qualifier !== null} />
                      <Indicator label="Exemplares alocados" value={allocated.value} note={allocated.note} />
                      <Indicator label="Sem cotação" value={unpriced.value} note={unpriced.note} />
                    </section>
                    {qualifier ? <p className="-mt-1 pb-3 text-[10px] text-neutral-500">{collectionValueCoverageText(report)}</p> : null}

                    {report.lines.length > 0 ? (
                      <>
                        {/* Desktop/tablet: tabela financeira. */}
                        <table className="hidden w-full text-left text-[10px] sm:table print:hidden" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
                          <colgroup>
                            <col />
                            <col style={{ width: "3.5rem" }} />
                            <col style={{ width: "9rem" }} />
                            <col style={{ width: "7rem" }} />
                          </colgroup>
                          <thead>
                            <DataTableHeadRow className="border-neutral-200 text-neutral-500">
                              <DataTableHeadCell className="bg-neutral-50">Carta</DataTableHeadCell>
                              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                                Qtd.
                              </DataTableHeadCell>
                              <DataTableHeadCell className="bg-neutral-50 px-2 text-right">Referência NM</DataTableHeadCell>
                              <DataTableHeadCell className="bg-neutral-50 px-2 text-right last:pr-2">Valor</DataTableHeadCell>
                            </DataTableHeadRow>
                          </thead>
                          <tbody>
                            {priced.map((line, index) => (
                              <ValueRow key={`${line.cardVariantId}.${line.languageCode}`} line={line} index={index} eager={eager} />
                            ))}
                            {outside.length > 0 ? (
                              <>
                                <tr>
                                  <td colSpan={COLUMNS} className="border-t border-neutral-200 bg-neutral-50 px-2 py-1.5 text-[10px] font-semibold text-neutral-700">
                                    Fora da soma · {plural(outside.length, "item", "itens")} sem cotação ou com preço indisponível, {orderText}
                                  </td>
                                </tr>
                                {outside.map((line, index) => (
                                  <ValueRow key={`${line.cardVariantId}.${line.languageCode}`} line={line} index={index} eager={eager} />
                                ))}
                              </>
                            ) : null}
                            <tr className="border-t-2 border-neutral-300">
                              <td className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">
                                Valor estimado
                                <span className="ml-1 font-normal text-neutral-500">· {collectionValueCoverageText(report)}</span>
                                {qualifier ? <span className="ml-1 font-medium text-amber-800">· {qualifier}</span> : null}
                              </td>
                              <td className="px-2 py-1.5 text-center font-semibold tabular-nums text-neutral-900">{N.format(report.copies)}</td>
                              <td />
                              <td className="px-2 py-1.5 text-right font-bold tabular-nums text-neutral-900">{totalText}</td>
                            </tr>
                          </tbody>
                        </table>

                        {/* Celular: cartões de uma coluna, sem rolagem horizontal. */}
                        <ul className="grid grid-cols-[minmax(0,1fr)] gap-2 sm:hidden print:hidden" aria-label="Exemplares alocados e valor estimado">
                          {report.lines.map((line, index) => {
                            const startsOutside = line.state !== "priced" && (index === 0 || report.lines[index - 1]?.state === "priced");
                            return (
                              <li key={`${line.cardVariantId}.${line.languageCode}`} className="grid grid-cols-[minmax(0,1fr)] gap-2">
                                {startsOutside ? (
                                  <p className="pt-2 text-[11px] font-semibold text-neutral-700">
                                    Fora da soma · {plural(outside.length, "item", "itens")} sem cotação ou com preço indisponível
                                  </p>
                                ) : null}
                                <MobileCard line={line} eager={eager} />
                              </li>
                            );
                          })}
                        </ul>
                        <div className="mt-2 rounded-md border border-neutral-200 px-3 py-2 sm:hidden print:hidden">
                          <p className="flex items-baseline justify-between gap-2 text-xs font-semibold text-neutral-900">
                            <span>Valor estimado</span>
                            <span className="tabular-nums">{totalText}</span>
                          </p>
                          <p className="text-[10px] text-neutral-500">{qualifier ?? collectionValueCoverageText(report)}</p>
                        </div>

                        {/* Impressão: tabela própria (miniaturas preparadas pelo mecanismo da R1-G; com pendência, Ctrl+P imprime só o aviso). */}
                        <div className="hidden print:block">
                          <PrintImageGate>
                            <PrintTable priced={priced} outside={outside} copies={report.copies} totalText={totalText} coverage={collectionValueCoverageText(report)} orderText={orderText} />
                          </PrintImageGate>
                        </div>
                      </>
                    ) : null}

                    <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                      {notes.map((note) => (
                        <li key={note}>{note}</li>
                      ))}
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

/**
 * Tabela de impressão: títulos das colunas no `<thead>` (o navegador os repete em cada folha), linhas
 * de altura fixa em mm e indivisíveis, valores à direita com algarismos tabulares, faixa "Fora da
 * soma" presa à linha seguinte, total no fim. Mesmos dados e textos da tela (nenhum cálculo).
 */
function PrintTable({
  priced,
  outside,
  copies,
  totalText,
  coverage,
  orderText,
}: {
  priced: readonly CollectionValueLine[];
  outside: readonly CollectionValueLine[];
  copies: number;
  totalText: string;
  coverage: string;
  orderText: string;
}) {
  return (
    <table className="w-full text-left text-[9px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }} data-collection-value-print-table="">
      <colgroup>
        <col />
        <col style={{ width: "13mm" }} />
        <col style={{ width: "36mm" }} />
        <col style={{ width: "28mm" }} />
      </colgroup>
      <thead>
        <tr className="border-b border-neutral-300 text-[8.5px] font-semibold uppercase tracking-wide text-neutral-500" style={{ breakInside: "avoid" }}>
          <th className="bg-neutral-50 px-1.5 py-1 text-left font-semibold">Carta</th>
          <th className="bg-neutral-50 px-1.5 py-1 text-center font-semibold">Qtd.</th>
          <th className="bg-neutral-50 px-1.5 py-1 text-right font-semibold">Referência NM</th>
          <th className="bg-neutral-50 px-1.5 py-1 text-right font-semibold">Valor</th>
        </tr>
      </thead>
      <tbody>
        {priced.map((line, index) => (
          <PrintRow key={`${line.cardVariantId}.${line.languageCode}`} line={line} index={index} />
        ))}
        {outside.length > 0 ? (
          <tr style={{ breakInside: "avoid", breakAfter: "avoid" }} data-collection-value-print-outside="">
            <td colSpan={COLUMNS} className="border-t border-neutral-200 bg-neutral-50 px-1.5 py-1 text-[9px] font-semibold text-neutral-700">
              Fora da soma · {plural(outside.length, "item", "itens")} sem cotação ou com preço indisponível, {orderText}
            </td>
          </tr>
        ) : null}
        {outside.map((line, index) => (
          <PrintRow key={`${line.cardVariantId}.${line.languageCode}`} line={line} index={index} />
        ))}
        <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
          <td className="py-1.5 pl-1.5 pr-1.5 font-semibold text-neutral-900">
            Valor estimado
            <span className="ml-1 font-normal text-neutral-500">· {coverage}</span>
          </td>
          <td className="px-1.5 py-1.5 text-center font-semibold tabular-nums text-neutral-900">{N.format(copies)}</td>
          <td />
          <td className="px-1.5 py-1.5 text-right font-bold tabular-nums text-neutral-900">{totalText}</td>
        </tr>
      </tbody>
    </table>
  );
}

function PrintRow({ line, index }: { line: CollectionValueLine; index: number }) {
  return (
    <tr
      className="border-t border-neutral-100"
      style={{ height: `${COLLECTION_VALUE_PRINT_ROW_MM}mm`, breakInside: "avoid", pageBreakInside: "avoid", backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED" }}
      data-collection-value-print-row=""
    >
      <td className="overflow-hidden py-0 pl-1.5 pr-1.5 align-middle">
        <span className="flex items-center gap-2">
          <span
            aria-hidden="true"
            className="flex shrink-0 items-center justify-center overflow-hidden rounded-[0.8mm] border border-neutral-200 bg-neutral-100"
            style={{ width: `${COLLECTION_VALUE_PRINT_THUMB_MM.width}mm`, height: `${COLLECTION_VALUE_PRINT_THUMB_MM.height}mm` }}
          >
            {line.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador (mesma regra das demais miniaturas)
              <img src={line.imageUrl} alt="" width={90} height={126} loading="lazy" decoding="async" className="h-full w-full object-cover" />
            ) : (
              <span className="px-0.5 text-center text-[5.5px] leading-tight text-neutral-500">Sem imagem no catálogo</span>
            )}
          </span>
          <span className="min-w-0 leading-snug">
            <span className="block truncate text-[11px] font-semibold text-neutral-900">{line.cardName}</span>
            <span className="block truncate text-[8.5px] text-neutral-600">{identityText(line)}</span>
          </span>
        </span>
      </td>
      <td className="px-1.5 py-0 text-center align-middle text-[10px] tabular-nums text-neutral-900">{N.format(line.copies)}</td>
      <td className="px-1.5 py-0 text-right align-middle leading-snug">
        <ReferenceCell line={line} />
      </td>
      <td
        className={`px-1.5 py-0 text-right align-middle text-[10px] font-semibold tabular-nums ${line.state === "unavailable" ? "text-amber-800" : line.state === "priced" ? "text-neutral-900" : "text-neutral-400"}`}
      >
        {collectionValueLineText(line)}
      </td>
    </tr>
  );
}

function Thumb({ line, eager }: { line: CollectionValueLine; eager: boolean }) {
  return (
    <span aria-hidden="true" className="flex h-[56px] w-[40px] shrink-0 items-center justify-center overflow-hidden rounded-[3px] border border-neutral-200 bg-neutral-100">
      {line.imageUrl ? (
        // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador de imagens (mesma regra dos demais relatórios)
        <img src={line.imageUrl} alt="" width={40} height={56} loading={eager ? "eager" : "lazy"} decoding="async" className="h-full w-full object-cover" />
      ) : (
        <span className="px-0.5 text-center text-[7px] leading-tight text-neutral-400">Sem imagem</span>
      )}
    </span>
  );
}

function identityText(line: CollectionValueLine): string {
  return [collectionValueCollectorText(line), collectionValueVariantText(line), collectionValueLanguageText(line)].join(" · ");
}

function ReferenceCell({ line }: { line: CollectionValueLine }) {
  const flags = collectionValuePriceFlags(line);
  const observed = collectionValueObservedText(line);
  const tone = line.state === "unavailable" ? "text-amber-800" : line.state === "unpriced" ? "text-neutral-500" : "text-neutral-900";
  return (
    <>
      <span className={`block font-semibold tabular-nums ${tone}`}>{collectionValueUnitText(line)}</span>
      {observed ? <span className="block text-[8.5px] text-neutral-500">{observed}</span> : null}
      {flags.length > 0 ? <span className="block text-[8.5px] font-medium text-neutral-700">{flags.join(" · ")}</span> : null}
    </>
  );
}

function ValueRow({ line, index, eager }: { line: CollectionValueLine; index: number; eager: boolean }) {
  return (
    <tr className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED" }}>
      <td className="py-1 pl-1 pr-2 align-middle">
        <span className="flex items-center gap-2.5">
          <Thumb line={line} eager={eager} />
          <span className="min-w-0 leading-snug">
            <span className="block truncate text-[11px] font-semibold text-neutral-900" title={line.cardName}>
              {line.cardName}
            </span>
            <span className="block text-[9px] text-neutral-500">{identityText(line)}</span>
          </span>
        </span>
      </td>
      <td className="px-2 py-1 text-center align-middle tabular-nums text-neutral-900">{N.format(line.copies)}</td>
      <td className="px-2 py-1 text-right align-middle">
        <ReferenceCell line={line} />
      </td>
      <td className={`px-2 py-1 text-right align-middle font-semibold tabular-nums ${line.state === "unavailable" ? "text-amber-800" : line.state === "priced" ? "text-neutral-900" : "text-neutral-400"}`}>
        {collectionValueLineText(line)}
      </td>
    </tr>
  );
}

function MobileCard({ line, eager }: { line: CollectionValueLine; eager: boolean }) {
  const flags = collectionValuePriceFlags(line);
  const observed = collectionValueObservedText(line);
  const quantity = plural(line.copies, "exemplar", "exemplares");
  return (
    <div className="flex gap-3 rounded-md border border-neutral-200 bg-white px-3 py-2">
      <Thumb line={line} eager={eager} />
      <div className="min-w-0 flex-1 leading-snug">
        <p className="truncate text-xs font-semibold text-neutral-900">{line.cardName}</p>
        <p className="text-[10px] text-neutral-500">{identityText(line)}</p>
        {line.state === "priced" ? (
          <p className="mt-1 text-[11px] tabular-nums text-neutral-800">
            {N.format(line.copies)} × {collectionValueUnitText(line)} = <span className="font-semibold text-neutral-900">{collectionValueLineText(line)}</span>
          </p>
        ) : (
          <p className={`mt-1 text-[11px] ${line.state === "unavailable" ? "font-medium text-amber-800" : "text-neutral-600"}`}>
            {quantity} · {collectionValueUnitText(line)} · fora da soma
          </p>
        )}
        {observed || flags.length > 0 ? <p className="text-[9.5px] text-neutral-500">{[observed, ...flags].filter(Boolean).join(" · ")}</p> : null}
      </div>
    </div>
  );
}

function StatusBanner({ complete }: { complete: boolean }) {
  return (
    <p className="mb-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-[11px] font-medium text-amber-900" role="status">
      {complete
        ? "Valor parcial: parte das referências de preço não pôde ser lida agora. Os itens afetados aparecem como “Preço indisponível”."
        : "Relatório incompleto: os totais não fecharam durante a leitura. Os valores abaixo não são definitivos."}
    </p>
  );
}

function StateMessage({ title, text }: { title: string; text: string }) {
  return (
    <div className="my-6 rounded-lg border border-neutral-200 px-6 py-8 text-center">
      <p className="text-sm font-semibold text-neutral-900">{title}</p>
      <p className="mt-2 text-xs text-neutral-600">{text}</p>
    </div>
  );
}

function Indicator({ label, value, note, emphasis = false, warn = false }: { label: string; value: string; note?: string; emphasis?: boolean; warn?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
      {note ? <p className={`text-[9px] leading-snug ${warn ? "font-medium text-amber-800" : "text-neutral-500"}`}>{note}</p> : null}
    </div>
  );
}
