/**
 * Lista de desejos (V1-11 W1) — regras puras.
 *
 * Contrato (wishlist-product-contract.md v1.1; C-91–C-102, C-210–C-219; Queries
 * 5345–5347, propostas): o desejo é de uma VARIANTE, com idioma opcional (`null` =
 * qualquer idioma), pertence só ao usuário (identidade por `auth.uid()` no banco — o
 * cliente nunca envia `user_id`), é binário e não tem vínculo com coleção, fichário ou
 * posição. Posse, preço, carta e Set são derivados na leitura.
 *
 * Nas grades (Acervo, Pesquisa) o marcador representa a VARIANTE: marcado = há pelo
 * menos um desejo dessa variante; marcar inclui "qualquer idioma"; desmarcar remove os
 * desejos dessa variante. A máquina de intenção (otimista, uma gravação por vez, última
 * intenção vence) é a mesma dos favoritos (P6/V1-10), sem alterá-la.
 */

import {
  type FavoriteEntry,
  type FavoriteOutcome,
  initialFavoriteEntry,
  settleFavorite,
  toggleFavorite,
} from "../pokedex/favorites.ts";
import { chunkIds, normalizeId } from "../favorites/card-favorites.ts";

export { chunkIds, normalizeId, initialFavoriteEntry as initialWishEntry };
export type WishEntry = FavoriteEntry;
export type WishOutcome = FavoriteOutcome;

// ---------------------------------------------------------------------------
// Idioma e posse
// ---------------------------------------------------------------------------

/** Código de idioma aceito (`pt-BR`, `en`…) ou `null` = qualquer idioma. */
export function normalizeLanguageCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.trim();
  return /^[a-z]{2}(-[A-Z]{2})?$/.test(code) ? code : null;
}

const LANGUAGE_LABEL: Readonly<Record<string, string>> = { "pt-BR": "Português", en: "Inglês" };

/** Rótulo do idioma do desejo. Vazio = "Qualquer idioma" (C-92), nunca "nenhum". */
export function wishLanguageLabel(code: string | null): string {
  if (code === null) return "Qualquer idioma";
  return LANGUAGE_LABEL[code] ?? code;
}

export type WishOwnership = "SAME_VARIANT_LANGUAGE" | "SAME_VARIANT_OTHER_LANGUAGE" | "OTHER_VARIANT" | "NONE";

const OWNERSHIP: readonly WishOwnership[] = ["SAME_VARIANT_LANGUAGE", "SAME_VARIANT_OTHER_LANGUAGE", "OTHER_VARIANT", "NONE"];

function toOwnership(value: unknown): WishOwnership {
  return typeof value === "string" && (OWNERSHIP as readonly string[]).includes(value) ? (value as WishOwnership) : "NONE";
}

/**
 * Selo de posse (C-213) na linguagem do colecionador. `null` = não tem (sem selo — a
 * ausência não precisa de rótulo). Nunca sugere remoção automática.
 */
export function ownershipLabel(ownership: WishOwnership): string | null {
  switch (ownership) {
    case "SAME_VARIANT_LANGUAGE":
      return "Já no acervo";
    case "SAME_VARIANT_OTHER_LANGUAGE":
      return "No acervo em outro idioma";
    case "OTHER_VARIANT":
      return "Você tem outra variante";
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Estado em lote (marcação de grade)
// ---------------------------------------------------------------------------

/** Linhas de `get_my_wishlist_state_by_variant` → variantes com pelo menos um desejo. */
export function toWishedVariantSet(rows: readonly { card_variant_id?: unknown; entry_id?: unknown }[]): Set<string> {
  const set = new Set<string>();
  for (const row of rows) {
    const variantId = normalizeId(row?.card_variant_id);
    if (variantId && normalizeId(row?.entry_id)) set.add(variantId);
  }
  return set;
}

/** Linhas de `get_my_wishlist_state_by_card` → carta → variantes desejadas. */
export function toWishedByCardMap(
  rows: readonly { card_id?: unknown; card_variant_id?: unknown; entry_id?: unknown }[],
): Map<string, Set<string>> {
  const map = new Map<string, Set<string>>();
  for (const row of rows) {
    const cardId = normalizeId(row?.card_id);
    const variantId = normalizeId(row?.card_variant_id);
    if (!cardId || !variantId || !normalizeId(row?.entry_id)) continue;
    const set = map.get(cardId) ?? new Set<string>();
    set.add(variantId);
    map.set(cardId, set);
  }
  return map;
}

/** Ids dos desejos de uma variante (para desmarcar na grade). */
export function entryIdsOfVariant(rows: readonly { card_variant_id?: unknown; entry_id?: unknown }[], variantId: string): string[] {
  const out: string[] = [];
  for (const row of rows) {
    const entryId = normalizeId(row?.entry_id);
    if (entryId && normalizeId(row?.card_variant_id) === variantId) out.push(entryId);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Escolha explícita de variante (C-212)
// ---------------------------------------------------------------------------

export type WishVariantOption = { variantId: string; label: string; isDefault: boolean };

/** Linhas de `get_catalog_card_variants_for_picker` (5163) → opções, na ordem recebida. */
export function parseVariantOptions(rows: unknown): WishVariantOption[] | null {
  if (!Array.isArray(rows)) return null;
  const out: WishVariantOption[] = [];
  for (const raw of rows) {
    const row = raw as Record<string, unknown> | null;
    const variantId = normalizeId(row?.card_variant_id);
    if (!row || !variantId) continue;
    const label = typeof row.variant_label === "string" && row.variant_label.trim() !== "" ? row.variant_label.trim() : "Variante";
    out.push({ variantId, label, isDefault: row.is_default_variant === true });
  }
  return out;
}

/**
 * O que o marcador de uma CARTA faz (Pesquisa): com uma única variante ativa a
 * inclusão é direta; com mais de uma, só pela escolha explícita; sem nenhuma, a ação
 * não existe. Nunca se presume variante.
 */
export function cardWishMode(options: readonly WishVariantOption[]): "direct" | "choose" | "none" {
  if (options.length === 0) return "none";
  return options.length === 1 ? "direct" : "choose";
}

// ---------------------------------------------------------------------------
// Página "Lista de desejos"
// ---------------------------------------------------------------------------

export type WishlistEntry = {
  entryId: string;
  cardVariantId: string;
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  variantLabel: string | null;
  variantAvailable: boolean;
  languageCode: string | null;
  ownership: WishOwnership;
  imagePathPt: string | null;
  imagePathEn: string | null;
  wishedAt: string;
};

export type WishlistPage = { entries: WishlistEntry[]; totalCount: number };

/** Tamanho da página (5346 aceita 1..100). */
export const WISHLIST_PAGE_SIZE = 60;

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

/** Linhas de `get_my_wishlist` → página. `null` = resposta fora do contrato. */
export function parseWishlistPage(data: unknown): WishlistPage | null {
  if (!Array.isArray(data)) return null;
  const entries: WishlistEntry[] = [];
  let totalCount = 0;
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row) continue;
    const entryId = normalizeId(row.entry_id);
    const cardVariantId = normalizeId(row.card_variant_id);
    const cardId = normalizeId(row.card_id);
    const cardName = text(row.card_name);
    const wishedAt = text(row.wished_at);
    if (!entryId || !cardVariantId || !cardId || !cardName || !wishedAt) continue;
    const total = Number(row.total_count);
    if (Number.isFinite(total) && total > totalCount) totalCount = Math.floor(total);
    const collectorTotal = row.collector_total === null || row.collector_total === undefined ? null : Number(row.collector_total);
    entries.push({
      entryId,
      cardVariantId,
      cardId,
      cardName,
      collectorNumber: text(row.collector_number) ?? "",
      collectorTotal: collectorTotal !== null && Number.isFinite(collectorTotal) ? collectorTotal : null,
      cardSetCode: text(row.card_set_code) ?? "",
      cardSetName: text(row.card_set_name) ?? "",
      variantLabel: text(row.variant_label),
      // Só `true` explícito conta como disponível: na dúvida, sinaliza (C-214).
      variantAvailable: row.variant_available === true,
      languageCode: normalizeLanguageCode(row.language_code),
      ownership: toOwnership(row.ownership),
      imagePathPt: text(row.image_path_pt),
      imagePathEn: text(row.image_path_en),
      wishedAt,
    });
  }
  return { entries, totalCount: Math.max(totalCount, entries.length) };
}

// ---------------------------------------------------------------------------
// Indicadores (C-216 / LDM-206)
// ---------------------------------------------------------------------------

export type WishlistSummary = {
  entryCount: number;
  variantCount: number;
  pricedVariantCount: number;
  /** BRL; `null` quando nenhuma variante distinta tem cotação. */
  totalBrl: number | null;
};

/**
 * Lê a resposta da 5347 (uma linha). Contagens inteiras ≥ 0 com priced ≤ variantes ≤
 * desejos (e variantes > 0 sempre que houver desejo); total finito ≥ 0 ou nulo, nulo
 * exatamente quando priced = 0. Qualquer outra forma → `null` (o painel mostra "—").
 */
export function parseWishlistSummary(data: unknown): WishlistSummary | null {
  const row = Array.isArray(data) ? (data.length === 1 ? data[0] : null) : data;
  if (!row || typeof row !== "object") return null;
  const record = row as Record<string, unknown>;
  const toInt = (value: unknown) => {
    const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
    return Number.isInteger(n) && n >= 0 ? n : null;
  };
  const entryCount = toInt(record.entry_count);
  const variantCount = toInt(record.variant_count);
  const pricedVariantCount = toInt(record.priced_variant_count);
  if (entryCount === null || variantCount === null || pricedVariantCount === null) return null;
  if (pricedVariantCount > variantCount || variantCount > entryCount || (entryCount > 0 && variantCount === 0)) return null;
  const rawTotal = record.total_brl;
  let totalBrl: number | null = null;
  if (rawTotal !== null && rawTotal !== undefined) {
    const n = typeof rawTotal === "number" ? rawTotal : typeof rawTotal === "string" ? Number(rawTotal) : NaN;
    if (!Number.isFinite(n) || n < 0) return null;
    totalBrl = n;
  }
  if ((pricedVariantCount === 0) !== (totalBrl === null)) return null;
  return { entryCount, variantCount, pricedVariantCount, totalBrl };
}

export type WishlistKpi = {
  key: "reference_value" | "entries" | "variants";
  /** Já formatado; `null` = sem dado — exibir "—", nunca zero. */
  value: string | null;
  name: string;
  hint: string;
  lead?: boolean;
};

/**
 * Painel da página: valor de referência (lead; uma referência NM por VARIANTE
 * DISTINTA, cobertura sobre variantes distintas), desejos (variante + idioma) e
 * variantes distintas. Sem cobertura: "—", nunca "R$ 0". O valor é indicação de
 * mercado, não preço-alvo nem patrimônio.
 */
export function wishlistKpis(input: {
  summary: WishlistSummary | null;
  /** Total da página (fallback da contagem quando o resumo falha). */
  fallbackEntryCount: number;
  format: (value: number) => string;
  formatMoney: (value: number) => string;
}): WishlistKpi[] {
  const { summary, fallbackEntryCount, format, formatMoney } = input;
  const entryCount = summary?.entryCount ?? fallbackEntryCount;
  const reference: WishlistKpi = (() => {
    const base = { key: "reference_value" as const, name: "Valor de referência", lead: true };
    if (summary === null) return { ...base, value: null, hint: "indisponível agora" };
    if (summary.variantCount === 0) return { ...base, value: null, hint: "lista vazia" };
    const noun = summary.variantCount === 1 ? "variante" : "variantes";
    const coverage = `${format(summary.pricedVariantCount)} de ${format(summary.variantCount)} ${noun} com cotação`;
    if (summary.totalBrl === null) return { ...base, value: null, hint: coverage };
    return { ...base, value: formatMoney(summary.totalBrl), hint: coverage };
  })();
  return [
    reference,
    { key: "entries", value: format(entryCount), name: entryCount === 1 ? "Desejo" : "Desejos", hint: "variante e idioma" },
    {
      key: "variants",
      value: summary === null ? null : format(summary.variantCount),
      name: summary?.variantCount === 1 ? "Variante" : "Variantes",
      hint: summary === null ? "indisponível agora" : "distintas na lista",
    },
  ];
}

// ---------------------------------------------------------------------------
// Máquina de intenção por variante (a da P6, chaveada por UUID)
// ---------------------------------------------------------------------------

export type WishSend = { variantId: string; value: boolean };
export type WishStep = { entry: WishEntry; send: WishSend | null };

export function toggleWish(variantId: string, entry: WishEntry): WishStep {
  const step = toggleFavorite(0, entry);
  return { entry: step.entry, send: step.send ? { variantId, value: step.send.value } : null };
}

export function settleWish(variantId: string, entry: WishEntry, outcome: WishOutcome): WishStep & { reverted: boolean } {
  const step = settleFavorite(0, entry, outcome);
  return { entry: step.entry, send: step.send ? { variantId, value: step.send.value } : null, reverted: step.reverted };
}

// ---------------------------------------------------------------------------
// Resultado das Server Actions e textos
// ---------------------------------------------------------------------------

export type WishFailureReason =
  | "not_authenticated"
  | "invalid"
  | "variant_unavailable"
  | "multiple_entries"
  | "unavailable"
  | "failed";

/**
 * Desmarcar a VARIANTE numa grade (CORRECTION-02): o marcador representa a variante,
 * mas a lista pode ter mais de um desejo dela (idiomas diferentes, C-99). Um clique só
 * remove quando há exatamente UM desejo; com mais de um, nada é removido e a pessoa é
 * levada à Lista de desejos para escolher qual sai — nunca uma exclusão agregada
 * silenciosa. Sem desejo: nada a remover (idempotente).
 */
export function variantRemovalPlan(entryIds: readonly string[]): "none" | "remove" | "blocked" {
  if (entryIds.length === 0) return "none";
  return entryIds.length === 1 ? "remove" : "blocked";
}

export type SetWishResult = { ok: true; wished: boolean } | { ok: false; reason: WishFailureReason };

/** SQLSTATE/código do banco → motivo exibível (sem detalhe técnico). */
export function wishFailureReason(code: string | null | undefined): WishFailureReason {
  switch (code) {
    case "28000":
    case "42501":
      return "not_authenticated";
    case "22023":
      return "invalid";
    case "P0002":
      return "variant_unavailable";
    case "PGRST202":
      return "unavailable";
    default:
      return "failed";
  }
}

/**
 * Nome acessível do marcador. Constante (o estado vai em `aria-pressed`): "Lista de
 * desejos: Pikachu · Holográfica". Inclui a variante quando conhecida (§8).
 */
export function wishToggleLabel(cardName: string, variantLabel: string | null): string {
  return variantLabel ? `Lista de desejos: ${cardName} · ${variantLabel}` : `Lista de desejos: ${cardName}`;
}

export function wishAnnouncement(name: string, wished: boolean): string {
  return wished ? `${name} adicionada à lista de desejos.` : `${name} removida da lista de desejos.`;
}

/** Mensagem inline de falha (STD-004): o que aconteceu e o que fazer. */
export function wishErrorMessage(name: string, reason: WishFailureReason): string {
  switch (reason) {
    case "not_authenticated":
      return `Sua sessão expirou. Entre novamente para atualizar a lista de desejos.`;
    case "variant_unavailable":
      return `${name} não está disponível no catálogo agora. Nada foi alterado.`;
    case "multiple_entries":
      return `${name} está na sua lista em mais de um idioma. Nada foi removido — escolha qual desejo sai na Lista de desejos.`;
    case "unavailable":
      return "A lista de desejos está indisponível no momento. Tente novamente mais tarde.";
    case "invalid":
    case "failed":
    default:
      return `Não foi possível atualizar ${name} na lista de desejos. Nada foi alterado — tente novamente.`;
  }
}

/** Página pedida na URL (`?pagina=`) → número válido (1 por padrão). */
export function parsePageParam(value: string | string[] | undefined): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const page = Number(raw);
  return Number.isInteger(page) && page >= 1 && page <= 1000 ? page : 1;
}

// ---------------------------------------------------------------------------
// HOMOLOGATION-04 — reconciliação da página e da escolha de variante
// ---------------------------------------------------------------------------

/**
 * Defeito A: o que a grade da Lista de desejos mostra entre a confirmação de uma
 * remoção/“Desfazer” e a releitura do servidor. `hidden` = ids cuja exclusão o banco já
 * confirmou; `restored` = desejos recriados pelo “Desfazer” (id novo) que a página ainda
 * não releu. Nunca duplica (o id do servidor vence) e nunca mostra um id oculto.
 */
export function visibleWishlistEntries<T extends { entryId: string }>(
  server: readonly T[],
  hidden: ReadonlySet<string>,
  restored: readonly T[],
): T[] {
  const serverIds = new Set(server.map((entry) => entry.entryId));
  const extra = restored.filter((entry) => !serverIds.has(entry.entryId) && !hidden.has(entry.entryId));
  return [...extra, ...server.filter((entry) => !hidden.has(entry.entryId))];
}

/**
 * Defeito B: estado da variante na escolha depois que a gravação responde. Sucesso →
 * o valor devolvido pelo servidor; falha → o último estado PERSISTIDO (nunca o otimista).
 */
export function settleChooserWished(
  persisted: ReadonlySet<string>,
  variantId: string,
  outcome: WishOutcome,
): Set<string> {
  const next = new Set(persisted);
  if (!outcome.ok) return next;
  if (outcome.value) next.add(variantId);
  else next.delete(variantId);
  return next;
}

// ---------------------------------------------------------------------------
// TOAST UX CORRECTION-07 — fechamento automático do aviso "saiu da lista"
// ---------------------------------------------------------------------------

/** Prazo do aviso de sucesso com "Desfazer". Erros nunca fecham sozinhos. */
export const WISH_SUCCESS_NOTICE_MS = 8000;

export type DismissClock = {
  now: () => number;
  set: (fn: () => void, ms: number) => unknown;
  clear: (handle: unknown) => void;
};

const realClock: DismissClock = {
  now: () => Date.now(),
  set: (fn, ms) => setTimeout(fn, ms),
  clear: (handle) => clearTimeout(handle as ReturnType<typeof setTimeout>),
};

/**
 * Temporizador do aviso: `start` (re)inicia o prazo inteiro (nova remoção = prazo novo,
 * nunca dois avisos); `pause`/`resume` guardam o tempo restante (hover/foco);
 * `cancel` desarma de vez (fechar, Desfazer, desmontar). Nunca dispara depois de
 * cancelado nem duas vezes.
 */
export function createDismissTimer(onDismiss: () => void, delayMs: number, clock: DismissClock = realClock) {
  let handle: unknown = null;
  let remaining = delayMs;
  let startedAt = 0;
  let active = false;
  let paused = false;

  const clear = () => {
    if (handle !== null) clock.clear(handle);
    handle = null;
  };
  const arm = (ms: number) => {
    clear();
    startedAt = clock.now();
    remaining = ms;
    handle = clock.set(() => {
      handle = null;
      if (!active) return;
      active = false;
      onDismiss();
    }, ms);
  };

  return {
    start() {
      active = true;
      paused = false;
      arm(delayMs);
    },
    pause() {
      if (!active || paused) return;
      paused = true;
      remaining = Math.max(0, remaining - (clock.now() - startedAt));
      clear();
    },
    resume() {
      if (!active || !paused) return;
      paused = false;
      arm(remaining);
    },
    cancel() {
      active = false;
      paused = false;
      clear();
    },
  };
}
