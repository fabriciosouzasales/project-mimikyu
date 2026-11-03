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

/**
 * W2 (Set padrão): cartas com pelo menos uma variante na Lista de desejos, a partir do
 * mapa carta → variantes da leitura em lote (`get_my_wishlist_state_by_card`). `null`
 * (leitura falhou) continua `null` — a grade não mostra marcador que não funciona.
 */
export function wishedCardIds(map: ReadonlyMap<string, ReadonlySet<string>> | null): ReadonlySet<string> | null {
  if (!map) return null;
  const cards = new Set<string>();
  for (const [card, variants] of map) {
    const id = normalizeId(card);
    if (id && variants.size > 0) cards.add(id);
  }
  return cards;
}

/**
 * W3 (Master Set): acabamento de uma posição. A posição é (carta, acabamento); a de
 * carta secreta não tem acabamento e aceita qualquer um (regra de 5198) — `ANY_FINISH`.
 */
export const ANY_FINISH = "*";

/** Chave de acabamento da posição: id do tipo de acabamento, ou `ANY_FINISH` quando `null`. Valor inválido = `null`. */
export function wishFinishKey(variantTypeId: string | null | undefined): string | null {
  if (variantTypeId === null || variantTypeId === undefined) return ANY_FINISH;
  return normalizeId(variantTypeId);
}

/** Valor de acabamento vindo do cliente (atributo do marcador): `ANY_FINISH` ou um id válido. */
export function parseFinishKey(value: unknown): string | null {
  if (value === ANY_FINISH) return ANY_FINISH;
  return normalizeId(value);
}

/** Chave da posição (carta + acabamento) na marcação da grade do Master Set. */
export function wishPositionKey(cardId: string, finishKey: string): string {
  return `${cardId.toLowerCase()}|${finishKey}`;
}

/**
 * Linhas de `get_my_wishlist_state_by_card_finish` (5348) → posições marcadas. Um
 * desejo marca a posição do acabamento DA VARIANTE desejada e a posição de carta
 * secreta da carta (que aceita qualquer acabamento). Nunca marca outro acabamento.
 */
export function toWishedPositionKeys(
  rows: readonly { card_id?: unknown; variant_type_id?: unknown; card_variant_id?: unknown; entry_id?: unknown }[],
): Set<string> {
  const keys = new Set<string>();
  for (const row of rows) {
    const cardId = normalizeId(row?.card_id);
    if (!cardId || !normalizeId(row?.card_variant_id) || !normalizeId(row?.entry_id)) continue;
    keys.add(wishPositionKey(cardId, ANY_FINISH));
    const finish = normalizeId(row?.variant_type_id);
    if (finish) keys.add(wishPositionKey(cardId, finish));
  }
  return keys;
}

/**
 * Linhas de `get_catalog_card_variants_for_finish` (5348) → opções COMPATÍVEIS com a
 * posição. Defesa em profundidade: mesmo que o banco devolva outra coisa, uma variante
 * de outro acabamento (ou sem acabamento numa posição de acabamento) nunca é oferecida.
 */
export function parseFinishVariantOptions(rows: unknown, finishKey: string): WishVariantOption[] | null {
  if (!Array.isArray(rows)) return null;
  const compatible =
    finishKey === ANY_FINISH
      ? rows
      : rows.filter((raw) => normalizeId((raw as Record<string, unknown> | null)?.variant_type_id) === finishKey);
  return parseVariantOptions(compatible);
}

// ---------------------------------------------------------------------------
// W4 — Pokédex (lacuna L3): cartas de uma espécie para a escolha explícita
// ---------------------------------------------------------------------------

/** Página da escolha de carta por espécie (5349 aceita 1..60). */
export const SPECIES_CARDS_PAGE_SIZE = 24;

export type SpeciesWishCard = {
  cardId: string;
  name: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  setCode: string | null;
  setName: string | null;
  imagePathPt: string | null;
  imagePathEn: string | null;
  activeVariants: number;
};

export type SpeciesWishCardsPage = { items: SpeciesWishCard[]; total: number };

/**
 * Linhas de `get_catalog_cards_for_species` (5349) → página. Defesa em profundidade:
 * carta sem variante ativa nunca entra (não haveria ação válida para ela).
 */
export function parseSpeciesCardsPage(rows: unknown): SpeciesWishCardsPage | null {
  if (!Array.isArray(rows)) return null;
  const items: SpeciesWishCard[] = [];
  let total = 0;
  const text = (value: unknown) => (typeof value === "string" && value.trim() !== "" ? value.trim() : null);
  for (const raw of rows) {
    const row = raw as Record<string, unknown> | null;
    const cardId = normalizeId(row?.card_id);
    const variants = Number(row?.active_variant_count);
    if (!row || !cardId || !Number.isInteger(variants) || variants < 1) continue;
    const count = Number(row.total_count);
    if (Number.isFinite(count) && count > total) total = count;
    const collectorTotal = Number(row.collector_total);
    items.push({
      cardId,
      name: text(row.card_name) ?? "Carta",
      collectorNumber: text(row.collector_number),
      collectorTotal: Number.isInteger(collectorTotal) && collectorTotal > 0 ? collectorTotal : null,
      setCode: text(row.card_set_code),
      setName: text(row.card_set_name),
      imagePathPt: text(row.image_path_pt),
      imagePathEn: text(row.image_path_en),
      activeVariants: variants,
    });
  }
  return { items, total: Math.max(total, items.length) };
}

/** Junta páginas sem repetir carta (releituras e cliques duplos não duplicam a grade). */
export function appendSpeciesCards(current: readonly SpeciesWishCard[], next: readonly SpeciesWishCard[]): SpeciesWishCard[] {
  const seen = new Set(current.map((card) => card.cardId));
  return [...current, ...next.filter((card) => !seen.has(card.cardId))];
}

/** Próximo offset da escolha, ou `null` quando já carregou tudo. */
export function nextSpeciesCardsOffset(loaded: number, total: number): number | null {
  return loaded < total ? loaded : null;
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

// ---------------------------------------------------------------------------
// W5 — Fichário: qual carta/variante cada bolso pode desejar
// ---------------------------------------------------------------------------

/** O mínimo de um bolso (5223) que a decisão precisa — sem acoplar ao tipo do Fichário. */
export type BinderWishSlotInput = {
  state: string;
  present: { cardVariantId?: string | null } | null;
  presentCardId: string | null;
  expectedCardId: string | null;
  expectedCardVariantId?: string | null;
  expectedVariantTypeId?: string | null;
};

/**
 * Alvo do marcador de um bolso (V1-11 W5). Nunca inventa carta:
 * - bolso OCUPADO → a variante exata do exemplar que está nele (inclusive quando ele
 *   diverge da reserva: o marcador fala da carta que aparece no bolso);
 * - bolso RESERVADO e vazio → a reserva, na granularidade dela: variante exata
 *   (`variant`), carta + acabamento (`position`, escolha restrita ao acabamento — 5348)
 *   ou só a carta (`position` com `"*"`, qualquer acabamento);
 * - bolso vazio, com imagem, ou sem referência legível → nenhum alvo (`null`).
 * O desejo nunca é ligado ao bolso: o alvo só diz O QUE desejar.
 */
export type BinderWishTarget =
  | { kind: "variant"; variantId: string; cardId: string | null; key: string }
  | { kind: "position"; cardId: string; finish: string; key: string };

const OCCUPIED_STATES = new Set(["OCCUPIED_MATCH", "OCCUPIED_UNPLANNED", "OCCUPIED_MISMATCH"]);

export function binderWishTarget(slot: BinderWishSlotInput): BinderWishTarget | null {
  if (OCCUPIED_STATES.has(slot.state)) {
    const variantId = normalizeId(slot.present?.cardVariantId);
    if (!variantId) return null;
    return { kind: "variant", variantId, cardId: normalizeId(slot.presentCardId), key: `v:${variantId}` };
  }
  if (slot.state !== "RESERVED_EMPTY") return null;
  const cardId = normalizeId(slot.expectedCardId);
  if (!cardId) return null;
  const variantId = normalizeId(slot.expectedCardVariantId);
  if (variantId) return { kind: "variant", variantId, cardId, key: `v:${variantId}` };
  const finish = normalizeId(slot.expectedVariantTypeId) ?? ANY_FINISH;
  return { kind: "position", cardId, finish, key: `p:${wishPositionKey(cardId, finish)}` };
}

/** Uma leitura agregada para os bolsos carregados: variantes e cartas, sem repetição. */
export function binderWishReadPlan(slots: Iterable<BinderWishSlotInput>): { variantIds: string[]; cardIds: string[] } {
  const variantIds = new Set<string>();
  const cardIds = new Set<string>();
  for (const slot of slots) {
    const target = binderWishTarget(slot);
    if (!target) continue;
    if (target.kind === "variant") variantIds.add(target.variantId);
    else cardIds.add(target.cardId);
  }
  return { variantIds: [...variantIds], cardIds: [...cardIds] };
}

/** Estado lido do marcador (`null` = ainda não lido ou leitura falhou → sem marcador). */
export function binderWishState(
  target: BinderWishTarget,
  state: { variants: ReadonlySet<string>; positions: ReadonlySet<string>; known: ReadonlySet<string> },
): boolean | null {
  if (!state.known.has(target.key)) return null;
  return target.kind === "variant" ? state.variants.has(target.variantId) : state.positions.has(wishPositionKey(target.cardId, target.finish));
}

/** O alvo foi coberto por uma leitura bem-sucedida com estes ids? */
export function binderWishTargetCovered(target: BinderWishTarget, variantIds: ReadonlySet<string>, cardIds: ReadonlySet<string>): boolean {
  return target.kind === "variant" ? variantIds.has(target.variantId) : cardIds.has(target.cardId);
}

// ---------------------------------------------------------------------------
// W6 — Filtros da Lista de desejos (5350)
// ---------------------------------------------------------------------------

export const WISHLIST_PATH = "/colecoes/lista-de-desejos";
/** Teto da busca (5350 recusa acima disso). */
export const WISHLIST_SEARCH_MAX = 100;
/** Valor de idioma "qualquer idioma" no contrato (5350) — nunca um idioma específico. */
export const ANY_LANGUAGE = "*";

export type WishlistOwnershipFilter = "OWNED" | "NOT_OWNED";

/**
 * Ordenação (W6, 5351) — a mesma do Meu acervo: "Mais recentes" (padrão) ou "Set e número".
 * Não é filtro: não conta em "Filtros · N", não vira chip e sobrevive a "Limpar filtros".
 */
export type WishlistSort = "recentes" | "set";

/**
 * Filtros combináveis (W6). Card Set pela identidade canônica (`card_set_id`), nunca
 * pelo código nem pela Expansion; idioma é o DO DESEJO (`"*"` = "qualquer idioma").
 */
export type WishlistFilters = {
  query: string | null;
  cardSetId: string | null;
  rarityId: string | null;
  language: string | null;
  ownership: WishlistOwnershipFilter | null;
  sort: WishlistSort;
};

export const NO_WISHLIST_FILTERS: WishlistFilters = {
  query: null,
  cardSetId: null,
  rarityId: null,
  language: null,
  ownership: null,
  sort: "recentes",
};

/** Parâmetros da URL (pt-BR): q, set, raridade, idioma (qualquer|código), acervo (tenho|falta), ordem (set). */
const OWNERSHIP_PARAM: Readonly<Record<string, WishlistOwnershipFilter>> = { tenho: "OWNED", falta: "NOT_OWNED" };
const OWNERSHIP_PARAM_OF: Readonly<Record<WishlistOwnershipFilter, string>> = { OWNED: "tenho", NOT_OWNED: "falta" };

function firstParam(value: string | string[] | undefined): string | null {
  const raw = Array.isArray(value) ? value[0] : value;
  return typeof raw === "string" ? raw : null;
}

/** URL → filtros válidos; valor inválido é ignorado (nunca vira erro nem outro filtro). */
export function parseWishlistFilters(params: Record<string, string | string[] | undefined>): WishlistFilters {
  const q = firstParam(params.q)?.trim() ?? "";
  const idioma = firstParam(params.idioma)?.trim() ?? "";
  const acervo = firstParam(params.acervo)?.trim().toLowerCase() ?? "";
  const ordem = firstParam(params.ordem)?.trim().toLowerCase() ?? "";
  return {
    query: q ? q.slice(0, WISHLIST_SEARCH_MAX) : null,
    cardSetId: normalizeId(firstParam(params.set)),
    rarityId: normalizeId(firstParam(params.raridade)),
    language: idioma === "qualquer" ? ANY_LANGUAGE : normalizeLanguageCode(idioma),
    ownership: OWNERSHIP_PARAM[acervo] ?? null,
    sort: ordem === "set" ? "set" : "recentes",
  };
}

export function hasActiveWishlistFilters(filters: WishlistFilters): boolean {
  return Boolean(filters.query || filters.cardSetId || filters.rarityId || filters.language || filters.ownership);
}

export function activeWishlistFilterCount(filters: WishlistFilters): number {
  return [filters.query, filters.cardSetId, filters.rarityId, filters.language, filters.ownership].filter(Boolean).length;
}

/** Filtros (+ página) → URL. Página 1 e filtros vazios ficam fora (URL limpa). */
export function wishlistHref(filters: WishlistFilters, page = 1): string {
  const params = new URLSearchParams();
  if (filters.query) params.set("q", filters.query);
  if (filters.cardSetId) params.set("set", filters.cardSetId);
  if (filters.rarityId) params.set("raridade", filters.rarityId);
  if (filters.language) params.set("idioma", filters.language === ANY_LANGUAGE ? "qualquer" : filters.language);
  if (filters.ownership) params.set("acervo", OWNERSHIP_PARAM_OF[filters.ownership]);
  if (filters.sort === "set") params.set("ordem", "set");
  if (page > 1) params.set("pagina", String(page));
  const query = params.toString();
  return query ? `${WISHLIST_PATH}?${query}` : WISHLIST_PATH;
}

/**
 * Argumentos da 5350/5351 (o banco recebe só valores já validados). `p_sort` só vai quando a
 * ordem não é a padrão: "Mais recentes" continua funcionando mesmo antes da 5351 no LIVE.
 */
export function wishlistFilterArgs(filters: WishlistFilters): {
  p_search: string | null;
  p_card_set_id: string | null;
  p_rarity_id: string | null;
  p_language: string | null;
  p_ownership: WishlistOwnershipFilter | null;
  p_sort?: "SET_NUMBER";
} {
  return {
    p_search: filters.query,
    p_card_set_id: filters.cardSetId,
    p_rarity_id: filters.rarityId,
    p_language: filters.language,
    p_ownership: filters.ownership,
    ...(filters.sort === "set" ? { p_sort: "SET_NUMBER" as const } : {}),
  };
}

/** Precisa da leitura filtrada (5350/5351)? Filtro ativo ou ordem diferente da padrão. */
export function needsFilteredWishlistRead(filters: WishlistFilters): boolean {
  return hasActiveWishlistFilters(filters) || filters.sort !== "recentes";
}

/** Mesma URL sem nenhum filtro, mantendo a ordenação escolhida ("Limpar filtros"). */
export function clearedWishlistFilters(filters: WishlistFilters): WishlistFilters {
  return { ...NO_WISHLIST_FILTERS, sort: filters.sort };
}

export type WishlistFilterOption = { value: string; label: string; detail: string | null; count: number };

/** Só opções presentes na lista do usuário (5350), cada uma com a contagem de desejos. */
export type WishlistFilterOptions = {
  cardSets: WishlistFilterOption[];
  rarities: WishlistFilterOption[];
  languages: WishlistFilterOption[];
  ownership: WishlistFilterOption[];
};

/** Linhas de `get_my_wishlist_filter_options` → opções ordenadas. `null` = fora do contrato. */
export function parseWishlistFilterOptions(data: unknown): WishlistFilterOptions | null {
  if (!Array.isArray(data)) return null;
  const buckets: Record<string, { sort: number; option: WishlistFilterOption }[]> = {
    CARD_SET: [],
    RARITY: [],
    LANGUAGE: [],
    OWNERSHIP: [],
  };
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row || typeof row.kind !== "string" || !(row.kind in buckets)) continue;
    const count = Number(row.entry_count);
    if (!Number.isFinite(count) || count < 1) continue;
    let value: string | null = null;
    if (row.kind === "CARD_SET" || row.kind === "RARITY") value = normalizeId(row.option_value);
    else if (row.kind === "LANGUAGE") value = row.option_value === ANY_LANGUAGE ? ANY_LANGUAGE : normalizeLanguageCode(row.option_value);
    else if (row.option_value === "OWNED" || row.option_value === "NOT_OWNED") value = row.option_value;
    if (!value) continue;
    const label =
      row.kind === "LANGUAGE"
        ? wishLanguageLabel(value === ANY_LANGUAGE ? null : value)
        : row.kind === "OWNERSHIP"
          ? ownershipFilterLabel(value as WishlistOwnershipFilter)
          : text(row.label);
    if (!label) continue;
    const sort = Number(row.sort_key);
    buckets[row.kind]?.push({
      sort: Number.isFinite(sort) ? sort : Number.MAX_SAFE_INTEGER,
      option: { value, label, detail: text(row.detail), count: Math.floor(count) },
    });
  }
  const ordered = (list: { sort: number; option: WishlistFilterOption }[]) =>
    list.sort((a, b) => a.sort - b.sort || a.option.label.localeCompare(b.option.label, "pt-BR")).map((item) => item.option);
  return {
    cardSets: ordered(buckets.CARD_SET ?? []),
    rarities: ordered(buckets.RARITY ?? []),
    languages: ordered(buckets.LANGUAGE ?? []),
    ownership: ordered(buckets.OWNERSHIP ?? []),
  };
}

export function ownershipFilterLabel(value: WishlistOwnershipFilter): string {
  return value === "OWNED" ? "Já no acervo" : "Fora do Acervo";
}

export type WishlistFilterChip = { key: Exclude<keyof WishlistFilters, "sort">; label: string; href: string };

/** Filtros ativos → chips (cada um remove só o próprio filtro e volta à página 1). */
export function wishlistFilterChips(filters: WishlistFilters, options: WishlistFilterOptions | null): WishlistFilterChip[] {
  const chips: WishlistFilterChip[] = [];
  const without = (key: Exclude<keyof WishlistFilters, "sort">) => wishlistHref({ ...filters, [key]: null });
  const nameOf = (list: WishlistFilterOption[] | undefined, value: string) => list?.find((option) => option.value === value)?.label;
  if (filters.query) chips.push({ key: "query", label: `Busca: “${filters.query}”`, href: without("query") });
  if (filters.cardSetId) {
    chips.push({ key: "cardSetId", label: `Set: ${nameOf(options?.cardSets, filters.cardSetId) ?? "selecionado"}`, href: without("cardSetId") });
  }
  if (filters.rarityId) {
    chips.push({ key: "rarityId", label: `Raridade: ${nameOf(options?.rarities, filters.rarityId) ?? "selecionada"}`, href: without("rarityId") });
  }
  if (filters.language) {
    chips.push({
      key: "language",
      label: `Idioma: ${wishLanguageLabel(filters.language === ANY_LANGUAGE ? null : filters.language)}`,
      href: without("language"),
    });
  }
  if (filters.ownership) chips.push({ key: "ownership", label: ownershipFilterLabel(filters.ownership), href: without("ownership") });
  return chips;
}

/** Contagem do resultado filtrado, sempre do conjunto inteiro (total da 5350), nunca da página. */
export function wishlistResultSummary(total: number, format: (n: number) => string = String): string {
  if (total === 0) return "Nenhum desejo encontrado";
  return total === 1 ? "1 desejo encontrado" : `${format(total)} desejos encontrados`;
}
