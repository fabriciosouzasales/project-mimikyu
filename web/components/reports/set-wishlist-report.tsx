"use client";

import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import type { ChecklistKind } from "@/lib/reports/collection-checklist";
import type { SetWishlistReport } from "@/lib/reports/set-wishlist";
import type { SetWishlistCollection } from "@/lib/reports/set-wishlist-queries";
import { type WishReportLine, wishCollectorText, wishCoverageText, wishOwnershipText, wishValueText, wishVariantText, wishedAtText } from "@/lib/reports/wishlist-report";
import { PrintImageGate } from "./print-image-gate";

export const SET_WISHLIST_TITLE = "Cartas desejadas do Card Set";
/** Miniaturas imediatas até este nº de desejos na tela; acima, sob demanda. */
const EAGER_IMAGES_MAX = 60;
/** Miniatura impressa — o padrão homologado da R2-B (12 × 16,8 mm, proporção 63:88). */
export const SET_WISH_PRINT_THUMB_MM = { width: 12, height: 16.8 } as const;

const N = new Intl.NumberFormat("pt-BR");
const formatCount = (n: number) => N.format(n);
const plural = (n: number, one: string, many: string) => `${N.format(n)} ${n === 1 ? one : many}`;

/**
 * V1-14 R2-C — folha "Cartas desejadas do Card Set" (D7 v1.48 §4k). Seleção contextual da Lista de
 * Desejos pelo Card Set da coleção — não é completude nem lista de faltantes (C-94, C-211).
 *
 * - Cabeçalho institucional em TODAS as páginas impressas (`<thead>` da tabela externa — mecanismo
 *   homologado na R1-H/R2-B); KPIs só na 1ª página.
 * - LISTA ÚNICA (`WISHLIST PRESENTATION SIMPLIFICATION-01`): todos os desejos do Set na ordem
 *   canônica "Set e número", sem filtro nem agrupamento por posse; a situação no acervo (os quatro
 *   estados C-213, em texto) é informação de cada cartão.
 * - TELA: cartões com miniatura original, número/total, nome, variante · idioma, situação,
 *   referência NM e data; responsiva (uma coluna no celular).
 * - IMPRESSÃO: todos os desejos, no padrão de cartões da R2-B (duas colunas, miniatura de
 *   12 × 16,8 mm preparada pelo mecanismo da R1-G, caixa de 5 mm); altura variável; cartões
 *   indivisíveis.
 */
export function SetWishlistSheet({
  collection,
  kind,
  report,
  logoUrl,
  issuedAt,
}: {
  collection: SetWishlistCollection;
  kind: ChecklistKind;
  report: SetWishlistReport;
  logoUrl: string | null;
  issuedAt: string;
}) {
  const identity = collection.cardSetCode ? `${collection.cardSetCode} · ${collection.cardSetName ?? collection.name}` : collection.name;
  const kindText = kind === "MASTER_SET" ? "Master Set" : "Set padrão";
  const cabecalho = (
    <RelatorioCabecalho
      titulo={SET_WISHLIST_TITLE}
      identificacaoColecao={identity}
      colecaoLogoUrl={logoUrl}
      subtitulo={`${kindText} · ${plural(report.entryCount, "desejo", "desejos")} · ${plural(report.cardCount, "carta", "cartas")} · Emitido em ${issuedAt}`}
    />
  );
  const eager = report.entryCount <= EAGER_IMAGES_MAX;
  const valueText = wishValueText(report.value, formatBrl);

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full" style={{ borderCollapse: "collapse" }}>
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
                  <StateMessage
                    title="Nenhum desejo deste Card Set na sua Lista de Desejos."
                    text="Quando você marcar como desejada uma carta deste Set (na Pesquisa, no Acervo, na coleção ou no fichário), ela aparece aqui."
                  />
                ) : (
                  <>
                    <section aria-label="Indicadores dos desejos do Card Set" className="grid grid-cols-2 gap-2 pb-3 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
                      <Indicator label="Desejos" value={formatCount(report.entryCount)} note="variante + idioma desejados" emphasis />
                      <Indicator label="Cartas distintas" value={formatCount(report.cardCount)} note="deste Card Set" />
                      <Indicator label="Variantes distintas" value={formatCount(report.variantCount)} note="cada uma conta uma vez no valor" />
                      <Indicator label="Referência NM" value={valueText} note={wishCoverageText(report.value)} />
                    </section>

                    <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2 print:hidden" aria-label="Desejos deste Card Set">
                      {report.lines.map((line) => (
                        <ScreenCard key={line.entryId} line={line} eager={eager} />
                      ))}
                    </ul>

                    {/* Impressão com miniaturas: mecanismo da R1-G (só pendentes de carregamento, 6 simultâneas, progresso; Ctrl+P com pendência imprime aviso). */}
                    <div className="hidden print:block">
                      <PrintImageGate>
                        <PrintList lines={report.lines} />
                      </PrintImageGate>
                    </div>

                    <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                      <li>
                        Desejos da sua Lista de Desejos cuja carta pertence a este Card Set (reimpressões em outros Sets não entram). Desejo não é
                        carta faltante para completar a coleção: esta lista não usa as posições da coleção.
                      </li>
                      <li>
                        Todos os desejos do Set aparecem, qualquer que seja a situação. Situação no acervo: considera todo o seu acervo, não só os
                        exemplares desta coleção. &ldquo;Já no acervo&rdquo; = mesma variante no idioma desejado (desejo em qualquer idioma: qualquer
                        exemplar da variante).
                      </li>
                      <li>
                        Referência NM = soma de uma referência de mercado Near Mint por variante distinta da lista (a mesma variante em dois idiomas conta
                        uma vez; inclui desejos já no acervo). &ldquo;Sem cotação&rdquo; fica fora da soma, nunca zero. Indicação de mercado, não custo de
                        aquisição.
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

function referenceText(line: WishReportLine): string {
  if (line.reference.kind === "priced") return formatBrl(line.reference.brl);
  return line.reference.kind === "unavailable" ? "Indisponível" : "Sem cotação";
}

function ScreenCard({ line, eager }: { line: WishReportLine; eager: boolean }) {
  return (
    <li className="flex items-start gap-3 rounded-md border border-neutral-200 px-2 py-1.5">
      <span aria-hidden="true" className="h-[56px] w-[40px] shrink-0 overflow-hidden rounded-[3px] border border-neutral-200 bg-neutral-100">
        {line.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador (mesma regra das demais miniaturas)
          <img src={line.imageUrl} alt="" width={40} height={56} loading={eager ? "eager" : "lazy"} decoding="async" className="h-full w-full object-cover" />
        ) : null}
      </span>
      <WishDetails line={line} />
    </li>
  );
}

function WishDetails({ line, print = false }: { line: WishReportLine; print?: boolean }) {
  return (
    <span className="block min-w-0 flex-1 leading-snug">
      <span className={`block tabular-nums text-neutral-500 ${print ? "text-[9.5px] font-medium uppercase tracking-wide" : "text-[10px]"}`}>Nº {wishCollectorText(line)}</span>
      <span className={`block font-semibold text-neutral-900 ${print ? "text-[12.5px]" : "text-[12px]"}`}>{line.cardName}</span>
      <span className="block text-[10.5px] text-neutral-700">
        {wishVariantText(line) || "Variante"}
        {line.variantAvailable ? null : <span className="font-medium text-neutral-900"> · Indisponível no catálogo</span>}
      </span>
      <span className="block text-[10.5px] text-neutral-700">{wishOwnershipText(line.ownership)}</span>
      <span className="block text-[10.5px] text-neutral-900">
        <span className="font-semibold">Referência NM: </span>
        <span className={line.reference.kind === "priced" ? "tabular-nums" : "italic text-neutral-500"}>{referenceText(line)}</span>
      </span>
      <span className="block text-[10px] text-neutral-500">Desejado em {wishedAtText(line.wishedAt)}</span>
    </span>
  );
}

/** Impressão: lista única em cartões de duas colunas (padrão R2-B), pares em ordem de leitura; cada par indivisível. */
function PrintList({ lines }: { lines: readonly WishReportLine[] }) {
  const pairs: [WishReportLine, WishReportLine | null][] = [];
  for (let i = 0; i < lines.length; i += 2) pairs.push([lines[i] as WishReportLine, lines[i + 1] ?? null]);
  return (
    <table className="mt-2 w-full text-left" style={{ borderCollapse: "separate", borderSpacing: "3mm 1.8mm", tableLayout: "fixed" }} data-set-wish-print-list="">
      <colgroup>
        <col style={{ width: "50%" }} />
        <col style={{ width: "50%" }} />
      </colgroup>
      <tbody>
        {pairs.map(([left, right]) => (
          <tr key={left.entryId} style={{ breakInside: "avoid" }}>
            <td className="p-0 align-top">
              <PrintCard line={left} />
            </td>
            <td className="p-0 align-top">{right ? <PrintCard line={right} /> : null}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function PrintCard({ line }: { line: WishReportLine }) {
  return (
    <div className="flex items-start gap-2 rounded-md border border-neutral-300 px-2 py-[1.8mm]" style={{ breakInside: "avoid" }} data-set-wish-print-card="">
      <span
        className="shrink-0 overflow-hidden rounded-[1mm] border border-neutral-200 bg-neutral-100"
        style={{ width: `${SET_WISH_PRINT_THUMB_MM.width}mm`, height: `${SET_WISH_PRINT_THUMB_MM.height}mm` }}
      >
        {line.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador (mesma regra das demais miniaturas)
          <img src={line.imageUrl} alt="" width={120} height={168} loading="lazy" decoding="async" className="h-full w-full object-cover" />
        ) : (
          <span className="flex h-full w-full items-center justify-center px-0.5 text-center text-[6.5px] leading-tight text-neutral-500">Sem imagem no catálogo</span>
        )}
      </span>
      <span aria-hidden="true" data-check-box="lg" className="inline-block h-[5mm] w-[5mm] shrink-0 rounded-[3px] border-[1.5px] border-neutral-500 bg-white" />
      <WishDetails line={line} print />
    </div>
  );
}

function StateMessage({ title, text }: { title: string; text: string }) {
  return (
    <div className="my-6 rounded-lg border border-neutral-200 px-6 py-8 text-center" style={{ breakInside: "avoid" }}>
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
