/**
 * Lista de desejos — faltantes em lote (V1-11 W7) — regras puras.
 *
 * Contrato (wishlist-product-contract.md §4.1/§4.2): a prévia separa *inclusões diretas*,
 * *já na lista* e *exigem escolha*; nada vira desejo sem seleção e confirmação; as
 * ambíguas nunca recebem variante presumida; o lote é idempotente; idioma sempre
 * "qualquer" (C-92). Nenhum desejo guarda vínculo com a coleção (C-211).
 *
 * Granularidade da posição:
 * - Set padrão → a CARTA: candidatas = todas as variantes ativas da carta;
 * - Master Set → carta + ACABAMENTO: candidatas = só as variantes ativas daquele acabamento;
 *   posição de carta secreta (sem acabamento) aceita qualquer acabamento (regra de 5198).
 */

import {
  ANY_FINISH,
  type WishVariantOption,
  normalizeId,
  wishPositionKey,
} from "./wishlist.ts";

/** Teto do lote — o mesmo das leituras de posição (≤ 500) e da 5352. */
export const BULK_WISH_LIMIT = 500;

export type BulkScope = "set" | "master";

/** Posição faltante, como a coleção a mostra. `finishKey`: só Master Set (id do acabamento ou `ANY_FINISH`). */
export type BulkPosition = {
  key: string;
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  imagePath: string | null;
  finishKey: string | null;
  finishLabel: string | null;
  isSecret: boolean;
};

export type CatalogVariant = WishVariantOption & { cardId: string; variantTypeId: string | null };

/**
 * - `direct`: exatamente uma variante candidata — entra com um clique (se marcada);
 * - `choose`: mais de uma — só entra depois da escolha explícita;
 * - `wished`: a posição já tem desejo na lista (mesma regra do marcador da grade);
 * - `none`: nenhuma variante ativa candidata — não há o que desejar.
 */
export type BulkItemState = "direct" | "choose" | "wished" | "none";

export type BulkItem = BulkPosition & { state: BulkItemState; options: WishVariantOption[] };

/** Linhas de `get_catalog_card_variants_for_cards` (5352) → carta → variantes (na ordem recebida). */
export function parseCatalogVariantsByCard(rows: unknown): Map<string, CatalogVariant[]> | null {
  if (!Array.isArray(rows)) return null;
  const map = new Map<string, CatalogVariant[]>();
  for (const raw of rows) {
    const row = raw as Record<string, unknown> | null;
    const cardId = normalizeId(row?.card_id);
    const variantId = normalizeId(row?.card_variant_id);
    if (!row || !cardId || !variantId) continue;
    const label = typeof row.variant_label === "string" && row.variant_label.trim() !== "" ? row.variant_label.trim() : "Variante";
    const list = map.get(cardId) ?? [];
    if (list.some((variant) => variant.variantId === variantId)) continue;
    list.push({ cardId, variantId, label, isDefault: row.is_default_variant === true, variantTypeId: normalizeId(row.variant_type_id) });
    map.set(cardId, list);
  }
  return map;
}

/**
 * Variantes candidatas da posição. Set: todas as da carta. Master Set: só as do
 * acabamento da posição (nunca outro acabamento); secreta: todas.
 */
export function candidateVariants(position: BulkPosition, variantsByCard: ReadonlyMap<string, readonly CatalogVariant[]>): WishVariantOption[] {
  const all = variantsByCard.get(position.cardId.toLowerCase()) ?? [];
  const compatible =
    position.finishKey === null || position.finishKey === ANY_FINISH ? all : all.filter((variant) => variant.variantTypeId === position.finishKey);
  return compatible.map(({ variantId, label, isDefault }) => ({ variantId, label, isDefault }));
}

/** Já está na lista? Set: a carta tem algum desejo. Master Set: a posição (carta + acabamento) está marcada. */
export function positionWished(position: BulkPosition, wishedCards: ReadonlySet<string> | null, wishedPositions: ReadonlySet<string> | null): boolean {
  if (position.finishKey === null) return wishedCards?.has(position.cardId.toLowerCase()) ?? false;
  return wishedPositions?.has(wishPositionKey(position.cardId, position.finishKey)) ?? false;
}

export function classifyBulkItem(options: readonly WishVariantOption[], wished: boolean): BulkItemState {
  if (wished) return "wished";
  if (options.length === 0) return "none";
  return options.length === 1 ? "direct" : "choose";
}

export function buildBulkItems(
  positions: readonly BulkPosition[],
  variantsByCard: ReadonlyMap<string, readonly CatalogVariant[]>,
  wished: { cards: ReadonlySet<string> | null; positions: ReadonlySet<string> | null },
): BulkItem[] {
  return positions.map((position) => {
    const options = candidateVariants(position, variantsByCard);
    return { ...position, options, state: classifyBulkItem(options, positionWished(position, wished.cards, wished.positions)) };
  });
}

export type BulkCounts = { direct: number; choose: number; wished: number; none: number };

export function bulkCounts(items: readonly BulkItem[]): BulkCounts {
  const counts: BulkCounts = { direct: 0, choose: 0, wished: 0, none: 0 };
  for (const item of items) counts[item.state] += 1;
  return counts;
}

/**
 * Seleção: posição → variante escolhida. Posição direta marcada guarda a única variante;
 * posição com escolha marcada sem variante guarda `null` (ainda pendente). Posições
 * `wished`/`none` nunca entram.
 */
export type BulkSelection = ReadonlyMap<string, string | null>;

export function toggleBulkItem(selection: BulkSelection, item: BulkItem): Map<string, string | null> {
  const next = new Map(selection);
  if (next.has(item.key)) {
    next.delete(item.key);
    return next;
  }
  if (item.state === "direct") next.set(item.key, item.options[0]?.variantId ?? null);
  else if (item.state === "choose") next.set(item.key, null);
  return next;
}

/** Escolher a variante de uma posição ambígua marca a posição. Variante fora das opções é ignorada. */
export function chooseBulkVariant(selection: BulkSelection, item: BulkItem, variantId: string | null): Map<string, string | null> {
  const next = new Map(selection);
  if (item.state !== "choose") return next;
  if (variantId === null) {
    next.delete(item.key);
    return next;
  }
  if (!item.options.some((option) => option.variantId === variantId)) return next;
  next.set(item.key, variantId);
  return next;
}

/** "Marcar todas as diretas": nunca marca ambíguas (variante não é presumida). */
export function selectAllDirect(selection: BulkSelection, items: readonly BulkItem[]): Map<string, string | null> {
  const next = new Map(selection);
  for (const item of items) if (item.state === "direct" && item.options[0]) next.set(item.key, item.options[0].variantId);
  return next;
}

export type BulkPlan = {
  /** Variantes a gravar (distintas, nunca vazias). */
  variantIds: string[];
  /** Posições marcadas e prontas. */
  ready: number;
  /** Posições marcadas que ainda esperam a escolha da variante. */
  pendingChoice: number;
};

/** O que a confirmação grava. Só considera itens elegíveis presentes na lista. */
export function bulkPlan(items: readonly BulkItem[], selection: BulkSelection): BulkPlan {
  const variants = new Set<string>();
  let ready = 0;
  let pendingChoice = 0;
  for (const item of items) {
    if (!selection.has(item.key) || (item.state !== "direct" && item.state !== "choose")) continue;
    const variantId = selection.get(item.key) ?? null;
    if (variantId === null || !item.options.some((option) => option.variantId === variantId)) {
      pendingChoice += 1;
      continue;
    }
    ready += 1;
    variants.add(variantId);
  }
  return { variantIds: [...variants], ready, pendingChoice };
}

export type BulkAddOutcome = "CREATED" | "EXISTING" | "UNAVAILABLE";

export type BulkAddSummary = {
  created: number;
  existing: number;
  unavailable: number;
  /** Pedidas sem linha de resposta — nunca contadas como sucesso. */
  missing: number;
  /** Tudo o que foi pedido está na lista agora (criado ou já existia). */
  complete: boolean;
};

/** Linhas de `add_my_wishlist_entries` (5352) × variantes pedidas → resumo honesto. */
export function summarizeBulkAdd(requested: readonly string[], rows: unknown): BulkAddSummary | null {
  if (!Array.isArray(rows)) return null;
  const wanted = new Set(requested.map((id) => id.toLowerCase()));
  const seen = new Map<string, BulkAddOutcome>();
  for (const raw of rows) {
    const row = raw as Record<string, unknown> | null;
    const variantId = normalizeId(row?.card_variant_id);
    const outcome = row?.outcome;
    if (!variantId || !wanted.has(variantId) || seen.has(variantId)) continue;
    if (outcome === "CREATED" || outcome === "EXISTING") {
      if (!normalizeId(row?.entry_id)) continue;
      seen.set(variantId, outcome);
    } else if (outcome === "UNAVAILABLE") {
      seen.set(variantId, outcome);
    }
  }
  let created = 0;
  let existing = 0;
  let unavailable = 0;
  for (const outcome of seen.values()) {
    if (outcome === "CREATED") created += 1;
    else if (outcome === "EXISTING") existing += 1;
    else unavailable += 1;
  }
  const missing = wanted.size - seen.size;
  return { created, existing, unavailable, missing, complete: unavailable === 0 && missing === 0 };
}

/** Frase do resultado, na linguagem do colecionador. */
export function bulkAddHeadline(summary: BulkAddSummary & { notMissing?: number }): string {
  const { created } = summary;
  if (created === 0) return summary.complete && !summary.notMissing ? "Tudo já estava na sua Lista de desejos" : "Nenhum desejo novo foi incluído";
  return created === 1 ? "1 desejo incluído na sua Lista" : `${created} desejos incluídos na sua Lista`;
}

// ---------------------------------------------------------------------------
// FIX-03 — confirmação revalidada no servidor
// ---------------------------------------------------------------------------

/** O que o navegador envia na confirmação: só a posição e a variante escolhida. Nada de elegibilidade. */
export type BulkSelectionRequest = { positionKey: string; variantId: string };

/**
 * Destino de cada posição pedida, decidido contra a prévia RECALCULADA no servidor:
 * - `accepted`: ainda falta e a variante está entre as candidatas da posição;
 * - `already_wished`: a posição ganhou desejo desde a prévia (outra aba) — "já existia";
 * - `not_missing`: a posição foi preenchida (ou não pertence às faltantes da coleção);
 * - `invalid_variant`: variante fora das candidatas (inclui acabamento incompatível no Master Set);
 * - `duplicate`: posição repetida no pedido (só a primeira conta).
 */
export type BulkPositionOutcome = "accepted" | "already_wished" | "not_missing" | "invalid_variant" | "duplicate";

export type BulkConfirmationPlan = {
  /** Variantes a gravar (distintas). */
  variantIds: string[];
  outcomes: { positionKey: string; outcome: BulkPositionOutcome }[];
};

/** Limite de tamanho de uma chave de posição vinda do navegador (uuid + ":" + uuid/"secreta"). */
const MAX_POSITION_KEY = 80;

/** Pedido do navegador → pedidos bem formados; `null` = pedido malformado (nada é gravado). */
export function parseBulkSelectionRequests(raw: unknown): BulkSelectionRequest[] | null {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > BULK_WISH_LIMIT) return null;
  const out: BulkSelectionRequest[] = [];
  for (const entry of raw) {
    const row = entry as Record<string, unknown> | null;
    const positionKey = typeof row?.positionKey === "string" ? row.positionKey.trim().toLowerCase() : "";
    const variantId = normalizeId(row?.variantId);
    if (!positionKey || positionKey.length > MAX_POSITION_KEY || !variantId) return null;
    out.push({ positionKey, variantId });
  }
  return out;
}

/**
 * Cruza o pedido com as posições faltantes recalculadas no servidor (mesma classificação da
 * prévia). A elegibilidade nunca vem do navegador: só a posição e a variante escolhida, e as duas
 * precisam bater com o estado atual da coleção autorizada.
 */
export function resolveBulkConfirmation(freshItems: readonly BulkItem[], requests: readonly BulkSelectionRequest[]): BulkConfirmationPlan {
  const byKey = new Map(freshItems.map((item) => [item.key.toLowerCase(), item]));
  const seen = new Set<string>();
  const variants = new Set<string>();
  const outcomes: BulkConfirmationPlan["outcomes"] = [];
  for (const request of requests) {
    const key = request.positionKey.toLowerCase();
    if (seen.has(key)) {
      outcomes.push({ positionKey: key, outcome: "duplicate" });
      continue;
    }
    seen.add(key);
    const item = byKey.get(key);
    if (!item) {
      outcomes.push({ positionKey: key, outcome: "not_missing" });
      continue;
    }
    if (item.state === "wished") {
      outcomes.push({ positionKey: key, outcome: "already_wished" });
      continue;
    }
    const variantId = request.variantId.toLowerCase();
    if ((item.state !== "direct" && item.state !== "choose") || !item.options.some((option) => option.variantId === variantId)) {
      outcomes.push({ positionKey: key, outcome: "invalid_variant" });
      continue;
    }
    variants.add(variantId);
    outcomes.push({ positionKey: key, outcome: "accepted" });
  }
  return { variantIds: [...variants], outcomes };
}

export type BulkConfirmationSummary = BulkAddSummary & {
  /** Posições que ganharam desejo desde a prévia (contam como "já existia"). */
  alreadyWished: number;
  /** Posições preenchidas desde a prévia — ignoradas, nada gravado. */
  notMissing: number;
  /** Posições recusadas (variante fora das candidatas ou pedido repetido) — nada gravado. */
  rejected: number;
};

/** Resultado final: gravação (por variante) + o que o servidor recusou ou ignorou (por posição). */
export function summarizeBulkConfirmation(plan: BulkConfirmationPlan, add: BulkAddSummary | null): BulkConfirmationSummary {
  const count = (outcome: BulkPositionOutcome) => plan.outcomes.filter((entry) => entry.outcome === outcome).length;
  const base = add ?? { created: 0, existing: 0, unavailable: 0, missing: 0, complete: true };
  const rejected = count("invalid_variant") + count("duplicate");
  return {
    ...base,
    alreadyWished: count("already_wished"),
    notMissing: count("not_missing"),
    rejected,
    complete: base.complete && rejected === 0,
  };
}
