import { acervoHref, formatCount, pluralize } from "./acervo.ts";

/**
 * "Meus locais" (WHERE-02) — regras puras da gestão de locais físicos.
 *
 * Contratos 5212–5219 no LIVE desde 2026-10-21 (canônicos em database/schema/).
 * Este módulo fixa a linguagem e a validação da interface, espelhando
 * exatamente as regras do banco (nome 1–60 após aparar, tipo opcional,
 * exclusão só de local vazio e que não seja local padrão de coleção). O banco
 * reconfere tudo; aqui só se responde cedo e se fala a língua do colecionador.
 * Nenhum termo técnico (Storage Container, Inventory, códigos) chega à tela.
 */

/** Rota de "Meus locais" (WHERE-02). */
export const LOCAIS_PATH = "/colecoes/locais";

/** Mesmo limite de `chk_storage_container_name` (5213) e de 5216/5217. */
export const STORAGE_NAME_MAX = 60;

/** Nome aparado; `null` quando vazio ou acima do limite (a interface explica). */
export function normalizeStorageName(input: string): string | null {
  const name = input.trim();
  if (name.length === 0 || name.length > STORAGE_NAME_MAX) return null;
  return name;
}

/** Um local como devolvido por `get_my_storage_locations` (5219). */
export type StorageLocation = {
  id: string;
  name: string;
  kindCode: string | null;
  kindLabel: string | null;
  cardCount: number;
  defaultCollectionCount: number;
  canDelete: boolean;
};

export type StorageSummary = {
  totalCards: number;
  locatedCards: number;
  unlocatedCards: number;
  locationCount: number;
};

/** Converte uma linha da 5219 (snake_case) — `null` se o formato não bate. */
export function toStorageLocation(row: Record<string, unknown>): StorageLocation | null {
  const id = row.storage_container_id;
  const name = row.name;
  const cardCount = Number(row.card_count);
  const defaults = Number(row.default_collection_count);
  if (typeof id !== "string" || typeof name !== "string" || !Number.isFinite(cardCount) || !Number.isFinite(defaults)) {
    return null;
  }
  return {
    id,
    name,
    kindCode: typeof row.kind_code === "string" ? row.kind_code : null,
    kindLabel: typeof row.kind_label === "string" ? row.kind_label : null,
    cardCount,
    defaultCollectionCount: defaults,
    canDelete: row.can_delete === true,
  };
}

/** "Nenhum exemplar" / "1 exemplar" / "1.248 exemplares". */
export function storageCardCountLabel(count: number): string {
  return count === 0 ? "Nenhum exemplar" : pluralize(count, "exemplar", "exemplares");
}

/** Linha de apoio do local: tipo (se houver) · quantidade. */
export function storageLocationFacts(location: Pick<StorageLocation, "kindLabel" | "cardCount">): string {
  const count = storageCardCountLabel(location.cardCount);
  return location.kindLabel ? `${location.kindLabel} · ${count}` : count;
}

/** Por que um local não pode ser excluído agora (mesma regra da 5218). */
export type StorageDeleteBlock = "has_cards" | "collection_default";

export function storageDeleteBlock(
  location: Pick<StorageLocation, "cardCount" | "defaultCollectionCount">,
): StorageDeleteBlock | null {
  if (location.cardCount > 0) return "has_cards";
  if (location.defaultCollectionCount > 0) return "collection_default";
  return null;
}

export function storageDeleteBlockMessage(
  block: StorageDeleteBlock,
  location: Pick<StorageLocation, "cardCount" | "defaultCollectionCount">,
): string {
  if (block === "has_cards") {
    return `Este local guarda ${storageCardCountLabel(location.cardCount).toLowerCase()}. Para excluí-lo, ele precisa estar vazio.`;
  }
  const n = location.defaultCollectionCount;
  const which = n === 1 ? "de uma coleção" : `de ${formatCount(n)} coleções`;
  return `Este é o local padrão ${which}. Troque o local padrão em Ajustes da coleção antes de excluir.`;
}

/** Falhas que as funções 5216–5219 comunicam por código. */
export type StorageFailure =
  | "not_authenticated"
  | "invalid_name"
  | "invalid_kind"
  | "idempotency_reused"
  | "not_found"
  | "has_cards"
  | "collection_default"
  | "in_use"
  | "unavailable";

const CODE_TO_FAILURE: Record<string, StorageFailure> = {
  not_authenticated: "not_authenticated",
  INVALID_NAME: "invalid_name",
  INVALID_KIND: "invalid_kind",
  INVALID_REQUEST: "unavailable",
  IDEMPOTENCY_KEY_REUSED: "idempotency_reused",
  INVENTORY_NOT_FOUND: "unavailable",
  STORAGE_NOT_FOUND: "not_found",
  STORAGE_HAS_CARDS: "has_cards",
  STORAGE_IS_COLLECTION_DEFAULT: "collection_default",
  STORAGE_IN_USE: "in_use",
};

/** Lê o código da mensagem do erro do PostgREST (`message` = código da função). */
export function storageFailureFromError(error: { message?: string | null } | null | undefined): StorageFailure {
  const code = error?.message?.trim() ?? "";
  return CODE_TO_FAILURE[code] ?? "unavailable";
}

export function storageFailureMessage(reason: StorageFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "invalid_name":
      return `Dê um nome ao local, com até ${STORAGE_NAME_MAX} caracteres.`;
    case "invalid_kind":
      return "Esse tipo de local não está disponível. Escolha outro.";
    case "idempotency_reused":
      return "Não foi possível concluir. Recarregue a página e tente de novo.";
    case "not_found":
      return "Esse local não existe mais. A lista foi atualizada.";
    case "has_cards":
      return "Este local guarda exemplares. Para excluí-lo, ele precisa estar vazio.";
    case "collection_default":
      return "Este é o local padrão de uma coleção. Troque o local padrão em Ajustes da coleção antes de excluir.";
    case "in_use":
      return "Este local acabou de ser usado. Nada foi excluído — confira a lista.";
    case "unavailable":
      return "Não foi possível concluir agora. Nada foi alterado — tente novamente.";
  }
}

// ---------------------------------------------------------------------------
// Interface "Meus locais" (WHERE-02 FRONTEND IMPLEMENTATION-01)
// ---------------------------------------------------------------------------

/** Um tipo de local ativo (`storage_container_kind`, 5212). O rótulo vem do banco. */
export type StorageKind = { code: string; label: string };

/** Mesmo formato dos códigos de 5212 (maiúsculas, dígitos e `_`). */
const KIND_CODE = /^[A-Z][A-Z0-9_]{0,39}$/;

export function isStorageKindCode(value: unknown): value is string {
  return typeof value === "string" && KIND_CODE.test(value);
}

/** Converte uma linha de `storage_container_kind` — `null` se o formato não bate. */
export function toStorageKind(row: Record<string, unknown>): StorageKind | null {
  const code = row.code;
  const label = row.label;
  if (!isStorageKindCode(code) || typeof label !== "string" || label.trim() === "") return null;
  return { code, label: label.trim() };
}

/** Converte a linha de `get_my_storage_summary` (5219) — `null` se o formato não bate. */
export function toStorageSummary(row: Record<string, unknown> | null | undefined): StorageSummary | null {
  if (!row) return null;
  const totalCards = Number(row.total_cards);
  const locatedCards = Number(row.located_cards);
  const unlocatedCards = Number(row.unlocated_cards);
  const locationCount = Number(row.location_count);
  if (![totalCards, locatedCards, unlocatedCards, locationCount].every((n) => Number.isInteger(n) && n >= 0)) return null;
  return { totalCards, locatedCards, unlocatedCards, locationCount };
}

/**
 * Opções do campo "Tipo" ao editar: os tipos ativos e, se o local já usa um
 * tipo que saiu da lista (inativo), esse tipo também — a 5217 aceita manter o
 * tipo atual, e a tela nunca mostra um código no lugar do rótulo.
 */
export function kindOptionsFor(
  kinds: readonly StorageKind[],
  current: Pick<StorageLocation, "kindCode" | "kindLabel"> | null,
): StorageKind[] {
  if (!current?.kindCode || kinds.some((kind) => kind.code === current.kindCode)) return [...kinds];
  return [...kinds, { code: current.kindCode, label: current.kindLabel ?? "Tipo atual" }];
}

/** Há algo a salvar? Nome inválido nunca conta como mudança. */
export function storageEditChanged(
  location: Pick<StorageLocation, "name" | "kindCode">,
  draftName: string,
  draftKind: string | null,
): boolean {
  const name = normalizeStorageName(draftName);
  if (name === null) return false;
  return name !== location.name || (draftKind || null) !== (location.kindCode ?? null);
}

/** Selo do local que é local padrão de coleções (preferência, não localização — NS-15). */
export function storageDefaultLabel(count: number): string | null {
  if (count <= 0) return null;
  return count === 1 ? "Local padrão de 1 coleção" : `Local padrão de ${formatCount(count)} coleções`;
}

/**
 * Quantas silhuetas de carta a pilha decorativa do local mostra: 0 (vazio),
 * 1 (até 9), 2 (até 99), 3 (100 ou mais). Só leitura visual — o número exato
 * está sempre escrito ao lado.
 */
export function storageStackTier(cardCount: number): 0 | 1 | 2 | 3 {
  if (cardCount <= 0) return 0;
  if (cardCount < 10) return 1;
  if (cardCount < 100) return 2;
  return 3;
}

/** Frase de sucesso, sempre lembrando que nenhuma carta mudou de lugar. */
export function storageSuccessMessage(
  action: "created" | "renamed" | "updated" | "deleted",
  name: string,
): string {
  switch (action) {
    case "created":
      return `“${name}” foi criado. Nenhuma carta foi colocada nele automaticamente.`;
    case "renamed":
    case "updated":
      return `“${name}” foi atualizado. Nenhuma carta mudou de lugar.`;
    case "deleted":
      return `“${name}” foi excluído. Nenhuma carta foi movida ou apagada.`;
  }
}

// ---------------------------------------------------------------------------
// Central de organização física (STORAGE LOCATIONS UX REDESIGN-01)
// ---------------------------------------------------------------------------

/**
 * Participação com UMA casa decimal (L2-01): arredondada para o décimo mais
 * próximo, em pt-BR. Nunca "100,0%" se a parte é menor que o todo (fica em
 * 99,9%) e nunca "0,0%" se há alguma coisa (vira "<0,1%" no texto). `null`
 * quando o todo é zero.
 */
export function shareTenths(part: number, whole: number): number | null {
  if (whole <= 0) return null;
  const p = Math.min(Math.max(part, 0), whole);
  let tenths = Math.round((p * 1000) / whole);
  if (tenths >= 1000 && p < whole) tenths = 999;
  return tenths;
}

const ONE_DECIMAL = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

function tenthsText(tenths: number, part: number): string {
  if (tenths === 0 && part > 0) return "<0,1%";
  return `${ONE_DECIMAL.format(tenths / 10)}%`;
}

/**
 * Percentual de organização: exemplares com local ÷ exemplares no acervo — as
 * duas contagens da MESMA leitura (5219 `get_my_storage_summary`), uma casa
 * decimal (4.009 / 4.062 → 98,7%). Acervo vazio → `null` (sem porcentagem).
 */
export function organizationShare(summary: Pick<StorageSummary, "totalCards" | "locatedCards">): number | null {
  const tenths = shareTenths(summary.locatedCards, summary.totalCards);
  return tenths === null ? null : tenths / 10;
}

/** "98,7%" / "—" (acervo vazio). */
export function organizationShareText(summary: Pick<StorageSummary, "totalCards" | "locatedCards">): string {
  const tenths = shareTenths(summary.locatedCards, summary.totalCards);
  return tenths === null ? "—" : tenthsText(tenths, summary.locatedCards);
}

/** Frase da faixa de organização pendente; `null` quando não há nada pendente. */
export function pendingOrganizationText(unlocatedCards: number): string | null {
  if (unlocatedCards <= 0) return null;
  return unlocatedCards === 1 ? "1 exemplar aguarda organização." : `${formatCount(unlocatedCards)} exemplares aguardam organização.`;
}

/** Ação da coluna de organização: "Organizar 53 exemplares" / "Organizar 1 exemplar". */
export function organizeLabel(unlocatedCards: number): string {
  return unlocatedCards === 1 ? "Organizar 1 exemplar" : `Organizar ${formatCount(unlocatedCards)} exemplares`;
}

/**
 * Agrupa itens já em ordem de Set (5220 `SET_NUMBER`) por Card Set, mantendo a
 * ordem — para o painel do local mostrar as cartas por Set.
 */
export function groupBySet<T extends { cardSetCode: string; cardSetName: string; copiesCount?: number }>(
  items: readonly T[],
): Array<{ code: string; name: string; items: T[]; cards: number; copies: number }> {
  const groups: Array<{ code: string; name: string; items: T[]; cards: number; copies: number }> = [];
  for (const item of items) {
    let last = groups[groups.length - 1];
    if (!last || last.code !== item.cardSetCode) {
      last = { code: item.cardSetCode, name: item.cardSetName, items: [], cards: 0, copies: 0 };
      groups.push(last);
    }
    last.items.push(item);
    last.cards += 1;
    last.copies += item.copiesCount ?? 0;
  }
  return groups;
}

/** "1 carta · 1 exemplar" / "30 cartas · 55 exemplares" — carta = identidade (variante + idioma); exemplar = unidade física. */
export function cardsCopiesLabel(cards: number, copies: number): string {
  return `${pluralize(cards, "carta", "cartas")} · ${pluralize(copies, "exemplar", "exemplares")}`;
}

/**
 * Raridade na prévia da carta (CONTEXTUAL UX-02): o nome canônico do catálogo
 * (`rarity.name` pelo `rarity_code` da 5220) — nunca inferido da imagem, do
 * número ou da aparência. Sem código → "Não cadastrada"; catálogo indisponível
 * ou código fora dele → "Indisponível no momento" (honesto, sem inventar).
 */
export function previewRarityLabel(code: string | null, names: Readonly<Record<string, string>> | null): string {
  if (!code) return "Não cadastrada";
  const name = names?.[code]?.trim();
  return name ? name : "Indisponível no momento";
}

/** Identidade física de uma carta do acervo: variante exata + idioma (a mesma do Meu acervo e da pesquisa reversa). */
export type CardIdentity = { cardVariantId: string; languageCode: string };

/**
 * Filtro contextual do painel (origem "Encontrar carta"): só a identidade
 * exata pesquisada — mesma variante E mesmo idioma; nunca pelo nome. Devolve
 * a linha do local (quantidade = exemplares DESTE local) ou `null`.
 */
export function findLocatedItem<T extends CardIdentity>(items: readonly T[], focus: CardIdentity): T | null {
  const id = focus.cardVariantId.toLowerCase();
  return items.find((item) => item.cardVariantId.toLowerCase() === id && item.languageCode === focus.languageCode) ?? null;
}

export type LocationSort = "name" | "most" | "least";
/** Filtro de tipo: todos, um código do catálogo ou "sem tipo". */
export type LocationKindFilter = "all" | "none" | string;

export const LOCATION_SORT_OPTIONS: ReadonlyArray<{ value: LocationSort; label: string }> = [
  { value: "name", label: "Nome (A–Z)" },
  { value: "most", label: "Mais exemplares" },
  { value: "least", label: "Menos exemplares" },
];

const NAME_ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });

/** Texto para busca: sem acento, minúsculo, espaços normalizados. */
export function searchKey(value: string): string {
  return value.normalize("NFD").replace(/[̀-ͯ]/g, "").toLocaleLowerCase("pt-BR").replace(/\s+/g, " ").trim();
}

/**
 * Tipos oferecidos no filtro (facetas da coluna lateral, Conceito B): só os que
 * aparecem nos locais do colecionador (rótulo do banco, ordem do catálogo de
 * tipos) e "Sem tipo definido" quando houver local sem tipo — nenhum tipo
 * artificial. Cada faceta traz quantos locais e quantos exemplares guarda; a
 * soma dos exemplares das facetas (sem "Todos") é o total com local definido
 * (5219: cada exemplar localizado está em exatamente um local).
 */
export function kindFilterOptions(
  locations: readonly Pick<StorageLocation, "kindCode" | "kindLabel" | "cardCount">[],
  kinds: readonly StorageKind[],
): Array<{ value: LocationKindFilter; label: string; count: number; copies: number }> {
  const groups = new Map<string, { label: string; count: number; copies: number }>();
  let untyped = 0;
  let untypedCopies = 0;
  let allCopies = 0;
  for (const l of locations) {
    allCopies += l.cardCount;
    if (!l.kindCode) {
      untyped += 1;
      untypedCopies += l.cardCount;
      continue;
    }
    const entry = groups.get(l.kindCode);
    if (entry) {
      entry.count += 1;
      entry.copies += l.cardCount;
    } else {
      groups.set(l.kindCode, { label: l.kindLabel ?? kinds.find((k) => k.code === l.kindCode)?.label ?? "Tipo atual", count: 1, copies: l.cardCount });
    }
  }
  const rank = (code: string) => {
    const i = kinds.findIndex((k) => k.code === code);
    return i < 0 ? Number.MAX_SAFE_INTEGER : i;
  };
  const typed = [...groups.entries()]
    .sort(([a, x], [b, y]) => rank(a) - rank(b) || NAME_ORDER.compare(x.label, y.label))
    .map(([code, v]) => ({ value: code as LocationKindFilter, label: v.label, count: v.count, copies: v.copies }));
  return [
    { value: "all", label: "Todos os locais", count: locations.length, copies: allCopies },
    ...typed,
    ...(untyped > 0 ? [{ value: "none" as LocationKindFilter, label: "Sem tipo definido", count: untyped, copies: untypedCopies }] : []),
  ];
}

/**
 * Código que o colecionador já escreve no começo do nome ("F001 - Fichário
 * Coleção ME1", "ETB002.5 - Heróis Excelsos", "BX001 - Card Box Vermelha").
 * Só APRESENTAÇÃO, nada persistido: letras maiúsculas (1–4) + um dígito +
 * letras/dígitos/pontos, seguidos de hífen ou travessão e do resto do nome.
 * Sem esse padrão inequívoco → sem código (nunca inventado); o nome completo
 * continua sendo a identidade do local.
 */
export function splitLocationCode(name: string): { code: string | null; title: string } {
  const match = /^([A-Z]{1,4}\d[A-Za-z0-9.]*)\s+[-–—]\s+(\S.*)$/.exec(name.trim());
  if (!match) return { code: null, title: name };
  return { code: match[1] as string, title: (match[2] as string).trim() };
}

/**
 * Participação de um local no acervo físico (L2-01): exemplares do local ÷
 * exemplares no acervo, uma casa decimal ("14,2%", "<0,1%"); vazio → `null`.
 * A barra da linha usa EXATAMENTE este denominador (`acervoShareWidth`).
 */
export function acervoShareText(count: number, totalCards: number): string | null {
  if (count <= 0) return null;
  const tenths = shareTenths(count, totalCards);
  return tenths === null ? null : tenthsText(tenths, count);
}

/** Largura da barra (0–100) na escala completa do acervo — o mesmo denominador do percentual. */
export function acervoShareWidth(count: number, totalCards: number): number {
  if (count <= 0 || totalCards <= 0) return 0;
  return Math.min(100, (count * 100) / totalCards);
}

/** Busca (nome), filtro de tipo e ordem — tudo sobre a lista já lida (5219), sem nova consulta. */
export function exploreLocations<T extends Pick<StorageLocation, "name" | "kindCode" | "kindLabel" | "cardCount" | "id">>(
  locations: readonly T[],
  options: { query: string; kind: LocationKindFilter; sort: LocationSort },
): T[] {
  const q = searchKey(options.query);
  const filtered = locations.filter((l) => {
    if (options.kind === "none" && l.kindCode) return false;
    if (options.kind !== "all" && options.kind !== "none" && l.kindCode !== options.kind) return false;
    return q === "" || searchKey(l.name).includes(q);
  });
  const byName = (a: T, b: T) => NAME_ORDER.compare(a.name, b.name) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  return [...filtered].sort((a, b) =>
    options.sort === "most" ? b.cardCount - a.cardCount || byName(a, b) : options.sort === "least" ? a.cardCount - b.cardCount || byName(a, b) : byName(a, b),
  );
}

/** Conteúdo de um local no Meu acervo (WHERE-04: `?local=<id>`, filtro no banco pela 5220). */
export function locationAcervoHref(id: string): string {
  return acervoHref({ storage: { kind: "location", id } });
}

/** Exemplares sem localização no Meu acervo (WHERE-04: `?local=sem`). */
export const UNLOCATED_ACERVO_HREF = acervoHref({ storage: { kind: "none" } });
