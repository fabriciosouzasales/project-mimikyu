"use client";

import { Heart } from "lucide-react";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import type { ChecklistKind } from "@/lib/reports/collection-checklist";
import { type FavoriteReportLine, collectorText, favoritedAtText } from "@/lib/reports/favorites-report";
import { type SetFavoritesReport, setFavoriteOwnershipText, setFavoriteReferenceText, setFavoritesTotalText } from "@/lib/reports/set-favorites";
import type { SetFavoritesCollection } from "@/lib/reports/set-favorites-queries";
import { PrintImageGate } from "./print-image-gate";

export const SET_FAVORITES_TITLE = "Cartas favoritas do Card Set";
/** Miniaturas imediatas até este nº de favoritas na tela; acima, sob demanda. */
const EAGER_IMAGES_MAX = 60;
/**
 * Impressão (ajuste da homologação, 2026-11-07): linhas de altura fixa — Nº 3,6 + nome 4,6 +
 * posse 3,8 + referência 3,8 + data 3,8 = 19,6 mm — e miniatura com essa mesma altura, base alinhada
 * a "Favoritada em": 14 × 19,6 mm (19,6 × 63/88 ≈ 14,0 — proporção da carta).
 */
export const SET_FAVORITES_PRINT_TEXT_MM = 3.6 + 4.6 + 3.8 + 3.8 + 3.8;
export const SET_FAVORITES_PRINT_THUMB_MM = { width: 14, height: 19.6 } as const;

const N = new Intl.NumberFormat("pt-BR");
const formatCount = (n: number) => N.format(n);
const plural = (n: number, one: string, many: string) => `${N.format(n)} ${n === 1 ? one : many}`;
const shareText = (part: number, total: number) => (total <= 0 ? "—" : part === total ? "100%" : `${Math.floor((part / total) * 100)}%`);

/**
 * V1-14 R2-D — folha "Cartas favoritas do Card Set" (D7 §4l). Curadoria pessoal: todas as cartas
 * favoritas do titular deste Card Set, numa lista única (sem filtros nem grupos), na ordem do Set.
 * Favorito ≠ desejo ≠ posse ≠ completude.
 *
 * - Cabeçalho institucional em TODAS as páginas impressas (`<thead>` da tabela externa — mecanismo
 *   homologado na R1-H/R2-B/R2-C); KPIs só na 1ª página.
 * - TELA: cartões com miniatura original, Nº/total, nome, posse no acervo, referência NM e data;
 *   coração discreto; responsiva (uma coluna no celular).
 * - IMPRESSÃO: todas as favoritas, cartões em duas colunas (padrão R2-B/R2-C), miniatura de
 *   12 × 16,8 mm preparada pelo mecanismo da R1-G, SEM caixa de marcação (D6), altura variável,
 *   cartões indivisíveis.
 */
export function SetFavoritesSheet({
  collection,
  kind,
  report,
  logoUrl,
  issuedAt,
}: {
  collection: SetFavoritesCollection;
  kind: ChecklistKind;
  report: SetFavoritesReport;
  logoUrl: string | null;
  issuedAt: string;
}) {
  const identity = collection.cardSetCode ? `${collection.cardSetCode} · ${collection.cardSetName ?? collection.name}` : collection.name;
  const kindText = kind === "MASTER_SET" ? "Master Set" : "Set padrão";
  const cabecalho = (
    <RelatorioCabecalho
      ajusteCelular
      titulo={SET_FAVORITES_TITLE}
      identificacaoColecao={identity}
      colecaoLogoUrl={logoUrl}
      subtitulo={`${kindText} · ${plural(report.cardCount, "carta favorita", "cartas favoritas")} · Emitido em ${issuedAt}`}
    />
  );
  const eager = report.cardCount <= EAGER_IMAGES_MAX;
  const coverage = report.pricesUnavailable ? "preços indisponíveis agora" : `${formatCount(report.pricedCount)} de ${plural(report.cardCount, "carta cotada", "cartas cotadas")} (${shareText(report.pricedCount, report.cardCount)})`;

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
                  <StateMessage
                    title="Nenhuma carta favorita deste Card Set."
                    text="Quando você marcar com o coração uma carta deste Set (na Pesquisa, no Acervo ou na coleção), ela aparece aqui."
                  />
                ) : (
                  <>
                    <section aria-label="Indicadores das favoritas do Card Set" className="grid grid-cols-2 gap-2 pb-3 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
                      <Indicator label="Cartas favoritas" value={formatCount(report.cardCount)} note="deste Card Set" emphasis />
                      <Indicator label="No acervo" value={`${formatCount(report.ownedCount)} de ${formatCount(report.cardCount)}`} note="com pelo menos 1 exemplar" />
                      <Indicator label="Exemplares no acervo" value={formatCount(report.ownedCopies)} note="todas as variantes e idiomas" />
                      <Indicator label="Referência NM" value={setFavoritesTotalText(report, formatBrl)} note={coverage} />
                    </section>

                    <ul className="grid grid-cols-[minmax(0,1fr)] gap-2 sm:grid-cols-2 print:hidden" aria-label="Cartas favoritas deste Card Set">
                      {report.lines.map((line) => (
                        <ScreenCard key={line.cardId} line={line} eager={eager} pricesUnavailable={report.pricesUnavailable} />
                      ))}
                    </ul>

                    {/* Impressão com miniaturas: mecanismo da R1-G (só pendentes de carregamento, 6 simultâneas, progresso; Ctrl+P com pendência imprime aviso). */}
                    <div className="hidden print:block">
                      <PrintImageGate>
                        <PrintList lines={report.lines} pricesUnavailable={report.pricesUnavailable} />
                      </PrintImageGate>
                    </div>

                    <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                      <li>
                        Suas cartas favoritas cuja carta pertence a este Card Set (reimpressões em outros Sets não entram), todas, qualquer que seja a
                        posse. Favorito é a sua curadoria da carta: não é desejo de compra, não é posse e não é carta faltante para completar a coleção.
                      </li>
                      <li>
                        No acervo: exemplares de todo o seu acervo (todas as variantes e idiomas da carta), não só os desta coleção.
                      </li>
                      <li>
                        Referência NM = referência geral de mercado Near Mint da carta, uma vez por carta (nunca multiplicada por exemplares); a soma é
                        das cartas cotadas. &ldquo;Sem cotação&rdquo; fica fora da soma, nunca zero. Não é patrimônio, valor de revenda nem custo de
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

/**
 * Tela: as cinco linhas têm altura FIXA (Nº 14 + nome 16 + posse 14 + referência 14 + data 14 =
 * 72 px), para a miniatura ter exatamente a altura do bloco — do "Nº" à base de "Favoritada em" —
 * sem depender do tamanho natural da imagem. O nome fica numa linha (reticências; nome completo no
 * `title`). Impressão: o mesmo conteúdo, com a tipografia homologada (altura variável).
 */
export const SET_FAVORITES_SCREEN_TEXT_PX = 14 + 16 + 14 + 14 + 14; // 72
/** Miniatura da tela: 52 × 72 px (72 × 63/88 ≈ 51,5 — proporção da carta). */
export const SET_FAVORITES_SCREEN_THUMB_PX = { width: 52, height: SET_FAVORITES_SCREEN_TEXT_PX } as const;

function FavoriteDetails({ line, pricesUnavailable, print = false }: { line: FavoriteReportLine; pricesUnavailable: boolean; print?: boolean }) {
  const reference = setFavoriteReferenceText(line, pricesUnavailable, formatBrl);
  // Altura fixa por linha (tela em px, impressão em mm) para a miniatura ter exatamente a altura do bloco.
  const row = print ? "h-[3.8mm] leading-[3.8mm] truncate" : "h-[14px] leading-[14px] truncate";
  return (
    <span className="block min-w-0 flex-1">
      <span className={`block tabular-nums text-neutral-500 ${print ? "h-[3.6mm] truncate text-[9.5px] font-medium uppercase leading-[3.6mm] tracking-wide" : `text-[10px] ${row}`}`}>Nº {collectorText(line)}</span>
      <span className={`block font-semibold text-neutral-900 ${print ? "h-[4.6mm] truncate text-[12.5px] leading-[4.6mm]" : "h-[16px] truncate text-[12px] leading-[16px]"}`} title={print ? undefined : line.name}>
        {line.name}
      </span>
      <span className={`block text-[10.5px] text-neutral-700 ${row}`}>{setFavoriteOwnershipText(line.ownedCopies)}</span>
      <span className={`block text-[10.5px] text-neutral-900 ${row}`}>
        <span className="font-semibold">Referência NM: </span>
        <span className={line.referenceBrl !== null && !pricesUnavailable ? "tabular-nums" : "italic text-neutral-500"}>{reference}</span>
      </span>
      <span className={`block text-[10px] text-neutral-500 ${row}`}>Favoritada em {favoritedAtText(line.favoritedAt)}</span>
    </span>
  );
}

function ScreenCard({ line, eager, pricesUnavailable }: { line: FavoriteReportLine; eager: boolean; pricesUnavailable: boolean }) {
  return (
    <li className="relative flex items-start gap-3 rounded-md border border-neutral-200 py-1.5 pl-2 pr-6">
      {/* Miniatura com a altura exata do bloco de texto (72 px) e a largura da proporção da carta (52 px). */}
      <span
        aria-hidden="true"
        data-set-favorites-screen-thumb=""
        className="relative shrink-0 overflow-hidden rounded-[3px] border border-neutral-200 bg-neutral-100"
        style={{ width: SET_FAVORITES_SCREEN_THUMB_PX.width, height: SET_FAVORITES_SCREEN_THUMB_PX.height }}
      >
        {line.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador (mesma regra das demais miniaturas)
          <img src={line.imageUrl} alt="" width={52} height={72} loading={eager ? "eager" : "lazy"} decoding="async" className="absolute inset-0 h-full w-full object-cover" />
        ) : null}
      </span>
      <FavoriteDetails line={line} pricesUnavailable={pricesUnavailable} />
      <Heart aria-hidden="true" className="absolute right-2 top-1.5 h-3.5 w-3.5 text-rose-400" />
    </li>
  );
}

/** Impressão: lista única em cartões de duas colunas (padrão R2-B/R2-C), pares em ordem de leitura; cada par indivisível. Sem caixa de marcação (D6). */
function PrintList({ lines, pricesUnavailable }: { lines: readonly FavoriteReportLine[]; pricesUnavailable: boolean }) {
  const pairs: [FavoriteReportLine, FavoriteReportLine | null][] = [];
  for (let i = 0; i < lines.length; i += 2) pairs.push([lines[i] as FavoriteReportLine, lines[i + 1] ?? null]);
  return (
    <table className="mt-2 w-full text-left" style={{ borderCollapse: "separate", borderSpacing: "3mm 1.8mm", tableLayout: "fixed" }} data-set-favorites-print-list="">
      <colgroup>
        <col style={{ width: "50%" }} />
        <col style={{ width: "50%" }} />
      </colgroup>
      <tbody>
        {pairs.map(([left, right]) => (
          <tr key={left.cardId} style={{ breakInside: "avoid" }}>
            <td className="p-0 align-top">
              <PrintCard line={left} pricesUnavailable={pricesUnavailable} />
            </td>
            <td className="p-0 align-top">{right ? <PrintCard line={right} pricesUnavailable={pricesUnavailable} /> : null}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function PrintCard({ line, pricesUnavailable }: { line: FavoriteReportLine; pricesUnavailable: boolean }) {
  return (
    <div className="relative flex items-start gap-2 rounded-md border border-neutral-300 py-[1.8mm] pl-2 pr-5" style={{ breakInside: "avoid" }} data-set-favorites-print-card="">
      <span
        className="shrink-0 overflow-hidden rounded-[1mm] border border-neutral-200 bg-neutral-100"
        style={{ width: `${SET_FAVORITES_PRINT_THUMB_MM.width}mm`, height: `${SET_FAVORITES_PRINT_THUMB_MM.height}mm` }}
      >
        {line.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador (mesma regra das demais miniaturas)
          <img src={line.imageUrl} alt="" width={120} height={168} loading="lazy" decoding="async" className="h-full w-full object-cover" />
        ) : (
          <span className="flex h-full w-full items-center justify-center px-0.5 text-center text-[6.5px] leading-tight text-neutral-500">Sem imagem no catálogo</span>
        )}
      </span>
      <FavoriteDetails line={line} pricesUnavailable={pricesUnavailable} print />
      <Heart aria-hidden="true" className="absolute right-[1.8mm] top-[1.8mm] h-3 w-3 text-rose-400" />
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
