/**
 * Valor do Fichário (BINDER-VALUE, 05d v2.74, D1–D9) — regras puras, sem banco.
 *
 * O cálculo financeiro é o da R2-E, sem regra nova: `buildCollectionValueReport`
 * (centavos, estados A cotada / B sem cotação / C indisponível, total `null`
 * sem nenhuma cotada — nunca R$ 0). Este módulo só:
 *  - resume o relatório para o cartão compacto do Centro de Controle (D8) — sem
 *    linhas, sem ids, sem nada além do que o cartão mostra;
 *  - formata os textos com o vocabulário do fichário (D5/D8);
 *  - decide quando reaproveitar ou reler o resultado (D4).
 */
import { formatObservedDate } from "../pricing/variant-pricing.ts";
import { type CollectionValueIncompleteReason, type CollectionValueReport, formatCents } from "../reports/collection-value.ts";

/** Resumo enviado ao navegador (cálculo feito no servidor, uma vez). */
export type BinderValueSummary = {
  /** `empty` = nenhum exemplar nos bolsos (D5). */
  state: "empty" | "ready";
  /** Soma das cotadas (A), em centavos; `null` sem nenhuma cotada. */
  totalCents: number | null;
  /** Exemplares nos bolsos (Σ das quantidades lidas). */
  copies: number;
  pricedCopies: number;
  /** B — leitura feita, sem referência válida. */
  unpricedCopies: number;
  /** C — o preço não pôde ser lido agora (falha técnica). */
  unavailableCopies: number;
  /** Há C: valor parcial. */
  provisional: boolean;
  /** Totais conferidos (Σ = `total_copies` = `filled_count`, sem repetição). */
  complete: boolean;
  incompleteReason: CollectionValueIncompleteReason;
  /** Exemplares cotados cuja referência tem mais de 14 dias. */
  staleCopies: number;
  /** Exemplares cotados pela referência geral da carta (não da variante). */
  generalCopies: number;
  observedFrom: string | null;
  observedTo: string | null;
};

/** Resume o relatório da R2-E para o cartão (contagens de sinais por exemplar; nenhum valor novo). */
export function summarizeBinderValue(report: CollectionValueReport): BinderValueSummary {
  let staleCopies = 0;
  let generalCopies = 0;
  for (const line of report.lines) {
    if (line.state !== "priced") continue;
    if (line.stale) staleCopies += line.copies;
    if (line.generalCardPrice) generalCopies += line.copies;
  }
  return {
    state: report.state,
    totalCents: report.totalCents,
    copies: report.copies,
    pricedCopies: report.pricedCopies,
    unpricedCopies: report.unpricedCopies,
    unavailableCopies: report.unavailableCopies,
    provisional: report.provisional,
    complete: report.complete,
    incompleteReason: report.incompleteReason,
    staleCopies,
    generalCopies,
    observedFrom: report.observedFrom,
    observedTo: report.observedTo,
  };
}

// ---------------------------------------------------------------------------
// Textos (D5/D8). Formatação de valores já calculados — nenhum cálculo financeiro.

const count = new Intl.NumberFormat("pt-BR");

/** Valor em destaque: nunca R$ 0 sem cotação; parcial explícito com C. */
export function binderValueTotalText(s: Pick<BinderValueSummary, "totalCents" | "provisional">): string {
  if (s.totalCents === null) return s.provisional ? "Indisponível" : "Sem cotação";
  return formatCents(s.totalCents);
}

/** Cobertura (D8): "X de Y cartas cotadas". */
export function binderValueCoverageText(s: Pick<BinderValueSummary, "pricedCopies" | "copies">): string {
  return `${count.format(s.pricedCopies)} de ${count.format(s.copies)} ${s.copies === 1 ? "carta cotada" : "cartas cotadas"}`;
}

/** Proporção cotada para a barra de cobertura (0–100, inteiro; 0 sem cartas). */
export function binderValueCoveragePercent(s: Pick<BinderValueSummary, "pricedCopies" | "copies">): number {
  if (s.copies <= 0) return 0;
  return Math.max(0, Math.min(100, Math.floor((s.pricedCopies * 100) / s.copies)));
}

/** Datas das referências usadas (só cotadas). */
export function binderValueObservedText(s: Pick<BinderValueSummary, "observedFrom" | "observedTo">): string | null {
  const from = formatObservedDate(s.observedFrom);
  const to = formatObservedDate(s.observedTo);
  if (!from || !to) return null;
  return from === to ? `Preços de ${from}` : `Preços de ${from} a ${to}`;
}

/** Avisos curtos, na ordem de importância. Nunca só cor. */
export function binderValueNotices(s: BinderValueSummary): string[] {
  const out: string[] = [];
  if (!s.complete) out.push(binderValueIncompleteText(s.incompleteReason));
  if (s.unavailableCopies > 0)
    out.push(
      `${count.format(s.unavailableCopies)} ${s.unavailableCopies === 1 ? "carta ficou" : "cartas ficaram"} sem preço por uma falha temporária — valor parcial.`,
    );
  if (s.unpricedCopies > 0)
    out.push(`${count.format(s.unpricedCopies)} ${s.unpricedCopies === 1 ? "carta sem cotação fica" : "cartas sem cotação ficam"} fora da soma.`);
  if (s.staleCopies > 0) out.push(`${count.format(s.staleCopies)} ${s.staleCopies === 1 ? "referência tem" : "referências têm"} mais de 14 dias.`);
  return out;
}

export function binderValueIncompleteText(reason: CollectionValueIncompleteReason): string {
  return reason === "too_large"
    ? "Fichário grande demais para somar aqui — valor não definitivo."
    : "Os totais não fecharam (o fichário pode ter mudado durante a leitura) — valor não definitivo.";
}

/** Nota curta obrigatória (D8). */
export const BINDER_VALUE_NOTE = "Considera só os bolsos ocupados por cartas deste fichário, de qualquer coleção ou sem coleção.";

/** Nota metodológica (D3), em uma frase. */
export const BINDER_VALUE_METHOD = "Quantidade × referência NM de cada variante, em reais. Não reflete a condição física das cartas nem é garantia de revenda.";

// ---------------------------------------------------------------------------
// Reaproveitamento (D4): lido sob demanda, reaproveitado enquanto o conjunto de
// exemplares nos bolsos for o mesmo e a referência não estiver velha.

/** Depois disso, reabrir a seção relê (preços podem ter sido atualizados). */
export const BINDER_VALUE_REUSE_MS = 30 * 60 * 1000;

export type BinderValueCacheEntry = { setKey: string; readAt: number; summary: BinderValueSummary };

/**
 * `true` quando é preciso ler de novo: sem resultado, conjunto dos bolsos mudou
 * (`setKey` diferente — qualquer escrita que possa ter colocado, retirado ou
 * substituído carta) ou resultado mais velho que `BINDER_VALUE_REUSE_MS`.
 * Resultado incompleto ou parcial nunca é reaproveitado.
 */
export function binderValueNeedsRead(entry: BinderValueCacheEntry | undefined, setKey: string, now: number): boolean {
  if (!entry) return true;
  if (entry.setKey !== setKey) return true;
  if (!entry.summary.complete || entry.summary.provisional) return true;
  return now - entry.readAt > BINDER_VALUE_REUSE_MS || now < entry.readAt;
}

/** Chave do conjunto físico nos bolsos (contagem + versão das escritas que mudam o conjunto). */
export function binderValueSetKey(filled: number, pocketSetVersion: number): string {
  return `${filled}:${pocketSetVersion}`;
}
