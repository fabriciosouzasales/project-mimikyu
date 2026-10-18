/**
 * Coleção livre — regras puras de apresentação e de seleção
 * (FREE-COLLECTION-FRONTEND-COMPLETION-01).
 *
 * Sem React, sem Supabase, sem rede: testável com
 * `node --experimental-strip-types --test lib/colecoes/free-collection.test.ts`.
 *
 * Contratos reutilizados (todos no LIVE, nenhum novo): R1 `get_my_collections`
 * (5168/5173) para o resumo, 5159 `get_my_inventory_items` para as cartas da
 * coleção e do acervo, 5162 `get_my_inventory_item_copies` para os exemplares
 * de cada carta e 5046 `allocate_physical_cards_to_collection` para vincular.
 * Nenhuma regra de domínio mora aqui: dono, Game, exclusividade do vínculo
 * (uma carta física em no máximo uma coleção) e o caráter atômico de cada
 * chamada são decididos pelo banco. Esta camada só decide o que a interface
 * oferece e como fala.
 */

import { COLECOES_PATH } from "./colecoes.ts";

/** Página da galeria da coleção (5159 aceita até 96). */
export const FREE_ITEMS_PAGE_SIZE = 48;
/** Página do seletor do acervo. */
export const PICKER_PAGE_SIZE = 48;
/**
 * Teto da seleção por confirmação = teto de 5046 por chamada. Uma confirmação
 * vira UMA chamada: ou todos os exemplares entram, ou nenhum (5046 é
 * fail-closed e atômica) — nunca um meio-termo silencioso.
 */
export const FREE_SELECTION_MAX = 500;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_PAGE = 2000;

type Params = Record<string, string | string[] | undefined>;

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

// ---------------------------------------------------------------------------
// Tipo da coleção
// ---------------------------------------------------------------------------

/**
 * Coleção livre = curadoria aberta, sem referência a Set (C-20). R1 devolve
 * `completion_policy = NONE` e nenhum Set; o universo é vazio por definição.
 */
export function isFreeCollection(summary: { completionPolicy: string | null; cardSetCode: string | null }): boolean {
  return summary.completionPolicy === "NONE" && summary.cardSetCode === null;
}

// ---------------------------------------------------------------------------
// Capa enviada pelo colecionador (FREE-COLLECTION-COVER-LOGO-01)
// ---------------------------------------------------------------------------

/**
 * Imagem própria na placa do fichário da Coleção livre. Contratos no LIVE
 * desde 2026-10-18 (`database/schema/5176`–`5178`; harness 5833 v1.2
 * 25/25 PASS). Ligada localmente para a homologação no navegador —
 * publicar (commit/deploy) só depois dessa homologação funcional e visual.
 */
export const FREE_COVER_UPLOAD_ENABLED = true;
export const COVER_BUCKET = "collection-cover";
/** Mesmo limite do bucket (5176). */
export const COVER_MAX_BYTES = 1024 * 1024;
export const COVER_EXTENSION_BY_MIME: Readonly<Record<string, string>> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
};

const COVER_PATH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$/;

/** Mesmo formato do CHECK de 5177: `<dono>/<coleção>/<uuid>.<ext>`. */
export function isCoverPath(value: unknown): value is string {
  return typeof value === "string" && COVER_PATH.test(value);
}

/** Caminho novo para um envio; `null` se o tipo não for aceito. */
export function buildCoverPath(userId: string, collectionId: string, mime: string, fileId: string): string | null {
  const extension = COVER_EXTENSION_BY_MIME[mime];
  if (!extension) return null;
  const path = `${userId.toLowerCase()}/${collectionId.toLowerCase()}/${fileId.toLowerCase()}.${extension}`;
  return isCoverPath(path) ? path : null;
}

/** Validação do arquivo antes de enviar (o bucket reconfere). */
export function checkCoverFile(file: { type: string; size: number }): "ok" | "type" | "size" | "empty" {
  if (!COVER_EXTENSION_BY_MIME[file.type]) return "type";
  if (file.size <= 0) return "empty";
  if (file.size > COVER_MAX_BYTES) return "size";
  return "ok";
}

/** Chave do logo da placa: o do Set, ou a imagem enviada (Coleção livre). */
export function plateLogoKey(collection: { cardSetLogoPath: string | null; coverLogoPath?: string | null }): string | null {
  return collection.cardSetLogoPath ?? collection.coverLogoPath ?? null;
}

// ---------------------------------------------------------------------------
// Código opcional da Coleção livre (FREE-COLLECTION-COVER-CODE-01)
// ---------------------------------------------------------------------------

/**
 * Código opcional da placa/foil da Coleção livre. Contratos no LIVE desde
 * 2026-10-18 (`database/schema/5179`–`5180`; harness 5834 21/21 PASS).
 * Ligado localmente para a homologação no navegador — publicar
 * (commit/deploy) só depois dessa homologação funcional e visual.
 */
export const FREE_COVER_CODE_ENABLED = true;
/** Mesmo formato do CHECK de 5179 e da validação de 5180. */
export const COVER_CODE_MIN = 2;
export const COVER_CODE_MAX = 6;
const COVER_CODE = /^[A-Z0-9]{2,6}$/;

/**
 * Normaliza o que o colecionador digitou: espaços nas pontas fora,
 * maiúsculas. Vazio = sem código (o campo é opcional). Devolve `"invalid"`
 * fora do formato — o banco reconfere (5180).
 */
export function normalizeCoverCode(raw: string | null | undefined): string | null | "invalid" {
  const value = (raw ?? "").trim().toUpperCase();
  if (value === "") return null;
  return COVER_CODE.test(value) ? value : "invalid";
}

/** Limpa a digitação ao vivo: só letras e números, maiúsculas, até 6. */
export function sanitizeCoverCodeInput(raw: string): string {
  return raw
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, COVER_CODE_MAX);
}

export function isCoverCode(value: unknown): value is string {
  return typeof value === "string" && COVER_CODE.test(value);
}

/** Código da placa: o do Set (coleção de Set) ou o escolhido (Coleção livre). */
export function plateCode(collection: { cardSetCode: string | null; coverCode?: string | null }): string | null {
  return collection.cardSetCode ?? collection.coverCode ?? null;
}

// ---------------------------------------------------------------------------
// URL
// ---------------------------------------------------------------------------

export const ADD_PARAM = "adicionar";

export function parseFreePage(params: Params): number {
  const raw = first(params.pagina) ?? "";
  const page = /^\d{1,4}$/.test(raw) ? Number(raw) : 1;
  return Math.min(Math.max(page, 1), MAX_PAGE);
}

/** `?adicionar=1` abre o seletor ao chegar (vindo da criação). */
export function wantsPicker(params: Params): boolean {
  return first(params[ADD_PARAM]) === "1";
}

export function freeCollectionHref(id: string, options: { page?: number; openPicker?: boolean } = {}): string {
  const params = new URLSearchParams();
  if (options.page && options.page > 1) params.set("pagina", String(options.page));
  if (options.openPicker) params.set(ADD_PARAM, "1");
  const search = params.toString();
  return `${COLECOES_PATH}/${id}${search ? `?${search}` : ""}`;
}

export function freeTotalPages(totalGroups: number, pageSize: number = FREE_ITEMS_PAGE_SIZE): number {
  return Math.max(1, Math.ceil(totalGroups / pageSize));
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

export type FreeHeroSource = {
  cardVariantId: string;
  languageCode: string;
  cardName: string;
  cardSetCode: string;
  collectorNumber: string;
  collectorTotal: number | null;
  imagePath: string | null;
};

/** Forma aceita pelo leque do hero (mesmo componente das coleções de Set). */
export type FreeHeroCard = {
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  imagePath: string | null;
  isSatisfied: true;
};

/**
 * As cartas mais recentes da coleção, uma por carta (a mesma carta em outro
 * idioma ou versão não repete no leque), só as que têm imagem. Tudo aqui é
 * posse real — não existe carta "faltante" numa Coleção livre.
 */
export function freeHeroCards(items: readonly FreeHeroSource[], max = 5): FreeHeroCard[] {
  const cards: FreeHeroCard[] = [];
  const seen = new Set<string>();
  for (const item of items) {
    if (cards.length >= max) break;
    if (!item.imagePath) continue;
    const identity = `${item.cardSetCode.toLowerCase()}#${item.collectorNumber}`;
    if (seen.has(identity)) continue;
    seen.add(identity);
    cards.push({
      cardId: `${item.cardVariantId}.${item.languageCode}`,
      cardName: item.cardName,
      collectorNumber: item.collectorNumber,
      collectorTotal: item.collectorTotal,
      imagePath: item.imagePath,
      isSatisfied: true,
    });
  }
  return cards;
}

/**
 * Quantos Sets a coleção reúne — só quando a página contém TODAS as cartas da
 * coleção (somar uma página parcial mostraria um número errado). Senão `null`
 * e a interface simplesmente não mostra o número.
 */
export function distinctSetCount(items: readonly { cardSetCode: string }[], totalGroups: number): number | null {
  if (totalGroups <= 0 || items.length < totalGroups) return null;
  return new Set(items.map((item) => item.cardSetCode.toLowerCase())).size;
}

// ---------------------------------------------------------------------------
// Exemplares e seleção
// ---------------------------------------------------------------------------

/** Um grupo do acervo: mesma carta, mesma versão, mesmo idioma. */
export type PickerGroup = {
  cardVariantId: string;
  languageCode: string;
  languageName: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  isDefaultVariant: boolean;
  variantLabel: string | null;
  imagePath: string | null;
  /** Exemplares contados pela leitura (livres, quando a lista é "só disponíveis"). */
  copies: number;
};

export type GroupCopy = {
  physicalCardId: string;
  copyNumber: number;
  addedAt: string;
  storageName: string | null;
  collectionId: string | null;
  collectionName: string | null;
};

/** Livre = fora de qualquer coleção; "here" = já nesta; "elsewhere" = em outra coleção. */
export type CopyStatus = "free" | "here" | "elsewhere";

export function groupKey(group: Pick<PickerGroup, "cardVariantId" | "languageCode">): string {
  return `${group.cardVariantId}.${group.languageCode}`;
}

export function copyStatus(copy: Pick<GroupCopy, "collectionId">, collectionId: string): CopyStatus {
  if (copy.collectionId === null) return "free";
  return copy.collectionId.toLowerCase() === collectionId.toLowerCase() ? "here" : "elsewhere";
}

export type CopyCounts = { free: number; here: number; elsewhere: number };

export function countCopies(copies: readonly GroupCopy[], collectionId: string): CopyCounts {
  const counts: CopyCounts = { free: 0, here: 0, elsewhere: 0 };
  for (const copy of copies) counts[copyStatus(copy, collectionId)] += 1;
  return counts;
}

/** Exemplares livres, do mais antigo ao mais novo (a ordem do acervo). */
export function freeCopies(copies: readonly GroupCopy[], collectionId: string): GroupCopy[] {
  return copies
    .filter((copy) => copyStatus(copy, collectionId) === "free")
    .sort((a, b) => a.copyNumber - b.copyNumber);
}

export type SelectionEntry = { group: PickerGroup; ids: string[] };
/** Seleção por grupo; os ids estão sempre na ordem em que entraram. */
export type Selection = Readonly<Record<string, SelectionEntry>>;

export function selectionCount(selection: Selection): number {
  let total = 0;
  for (const entry of Object.values(selection)) total += entry.ids.length;
  return total;
}

export function selectionIds(selection: Selection): string[] {
  const ids: string[] = [];
  for (const entry of Object.values(selection)) ids.push(...entry.ids);
  return ids;
}

/** Cartas diferentes na seleção (variante e idioma diferentes contam como cartas diferentes, como no acervo). */
export function selectionGroupCount(selection: Selection): number {
  return Object.values(selection).filter((entry) => entry.ids.length > 0).length;
}

function withEntry(selection: Selection, key: string, entry: SelectionEntry | null): Selection {
  const next: Record<string, SelectionEntry> = { ...selection };
  if (entry === null || entry.ids.length === 0) delete next[key];
  else next[key] = entry;
  return next;
}

export type SelectionChange =
  | { ok: true; selection: Selection }
  | { ok: false; reason: "none_free" | "limit" | "not_free" };

/**
 * Mais um exemplar desta carta: o livre mais antigo ainda não escolhido.
 * Nunca escolhe exemplar que já está em alguma coleção.
 */
export function addNextCopy(
  selection: Selection,
  group: PickerGroup,
  copies: readonly GroupCopy[],
  collectionId: string,
  max: number = FREE_SELECTION_MAX,
): SelectionChange {
  const key = groupKey(group);
  const current = selection[key]?.ids ?? [];
  const next = freeCopies(copies, collectionId).find((copy) => !current.includes(copy.physicalCardId));
  if (!next) return { ok: false, reason: "none_free" };
  if (selectionCount(selection) >= max) return { ok: false, reason: "limit" };
  return { ok: true, selection: withEntry(selection, key, { group, ids: [...current, next.physicalCardId] }) };
}

/** Um exemplar a menos desta carta (o último escolhido). */
export function removeLastCopy(selection: Selection, key: string): Selection {
  const entry = selection[key];
  if (!entry) return selection;
  return withEntry(selection, key, { group: entry.group, ids: entry.ids.slice(0, -1) });
}

export function removeGroup(selection: Selection, key: string): Selection {
  return withEntry(selection, key, null);
}

/** Marca ou desmarca um exemplar específico; só exemplares livres podem entrar. */
export function toggleCopy(
  selection: Selection,
  group: PickerGroup,
  copies: readonly GroupCopy[],
  physicalCardId: string,
  collectionId: string,
  max: number = FREE_SELECTION_MAX,
): SelectionChange {
  const key = groupKey(group);
  const current = selection[key]?.ids ?? [];
  if (current.includes(physicalCardId)) {
    return { ok: true, selection: withEntry(selection, key, { group, ids: current.filter((id) => id !== physicalCardId) }) };
  }
  const copy = copies.find((candidate) => candidate.physicalCardId === physicalCardId);
  if (!copy || copyStatus(copy, collectionId) !== "free") return { ok: false, reason: "not_free" };
  if (selectionCount(selection) >= max) return { ok: false, reason: "limit" };
  return { ok: true, selection: withEntry(selection, key, { group, ids: [...current, physicalCardId] }) };
}

/** Todos os livres desta carta (até o teto); mantém os já escolhidos. */
export function selectAllFree(
  selection: Selection,
  group: PickerGroup,
  copies: readonly GroupCopy[],
  collectionId: string,
  max: number = FREE_SELECTION_MAX,
): { selection: Selection; limited: boolean } {
  const key = groupKey(group);
  const current = selection[key]?.ids ?? [];
  const room = Math.max(0, max - (selectionCount(selection) - current.length));
  const wanted = [...current];
  for (const copy of freeCopies(copies, collectionId)) {
    if (!wanted.includes(copy.physicalCardId)) wanted.push(copy.physicalCardId);
  }
  const ids = wanted.slice(0, room);
  return { selection: withEntry(selection, key, { group, ids }), limited: ids.length < wanted.length };
}

/**
 * "Selecionar todas": todos os exemplares livres de várias cartas de uma vez,
 * na ordem recebida, mantendo o que já estava escolhido e parando no teto.
 * `limited` avisa quando sobrou exemplar livre fora da seleção.
 */
export function selectAllFromGroups(
  selection: Selection,
  entries: readonly { group: PickerGroup; copies: readonly GroupCopy[] }[],
  collectionId: string,
  max: number = FREE_SELECTION_MAX,
): { selection: Selection; added: number; limited: boolean } {
  let next = selection;
  let limited = false;
  const before = selectionCount(selection);
  for (const entry of entries) {
    const result = selectAllFree(next, entry.group, entry.copies, collectionId, max);
    next = result.selection;
    if (result.limited) limited = true;
  }
  return { selection: next, added: selectionCount(next) - before, limited };
}

/**
 * Depois de reler os exemplares (o acervo pode ter mudado em outra aba ou
 * numa tentativa anterior que chegou ao banco): tira da seleção o que deixou
 * de estar livre e conta o motivo. Nada é trocado em silêncio.
 */
export function reconcileSelection(
  selection: Selection,
  key: string,
  copies: readonly GroupCopy[],
  collectionId: string,
): { selection: Selection; here: number; elsewhere: number; gone: number } {
  const entry = selection[key];
  if (!entry) return { selection, here: 0, elsewhere: 0, gone: 0 };
  const byId = new Map(copies.map((copy) => [copy.physicalCardId, copy]));
  const kept: string[] = [];
  let here = 0;
  let elsewhere = 0;
  let gone = 0;
  for (const id of entry.ids) {
    const copy = byId.get(id);
    if (!copy) gone += 1;
    else {
      const status = copyStatus(copy, collectionId);
      if (status === "free") kept.push(id);
      else if (status === "here") here += 1;
      else elsewhere += 1;
    }
  }
  return { selection: withEntry(selection, key, { group: entry.group, ids: kept }), here, elsewhere, gone };
}

// ---------------------------------------------------------------------------
// Validação do envio
// ---------------------------------------------------------------------------

/** Ids prontos para 5046: uuids, sem repetição, 1..teto. `null` = pedido inválido. */
export function normalizeCopyIds(raw: unknown, max: number = FREE_SELECTION_MAX): string[] | null {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > max) return null;
  const ids: string[] = [];
  const seen = new Set<string>();
  for (const value of raw) {
    if (typeof value !== "string" || !UUID.test(value)) return null;
    const id = value.toLowerCase();
    if (seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

/** Rótulo da versão no seletor: "Versão padrão" ou o nome da variante. */
export function versionLabel(isDefault: boolean, label: string | null): string {
  if (isDefault) return "Versão padrão";
  const trimmed = label?.trim() ?? "";
  return trimmed === "" ? "Outra versão" : trimmed;
}

/** Onde está um exemplar que não pode ser escolhido. */
export function copyStatusLabel(status: CopyStatus, collectionName: string | null): string {
  if (status === "free") return "Disponível";
  if (status === "here") return "Já está nesta coleção";
  return collectionName ? `Em «${collectionName}»` : "Em outra coleção";
}
