/**
 * Meu acervo — regras puras de apresentação e URL (MY-INVENTORY-IMPLEMENTATION-01).
 *
 * Sem React, sem Supabase, sem rede: tudo aqui é testável com
 * `node --experimental-strip-types --test lib/colecoes/acervo.test.ts`.
 *
 * Estado da tela vive na URL (mesmo modelo da Pokédex): `?q=`, `?set=`,
 * `?idioma=`, `?colecao=` (id ou `sem`), `?ordem=` (`recentes` | `set`),
 * `?pagina=` e `?carta=` (detalhe aberto: `<card_variant_id>.<idioma>`).
 * Link editado à mão nunca vira erro: valor inválido cai no padrão.
 */

export const ACERVO_PATH = "/colecoes/acervo";
export const ACERVO_PAGE_SIZE = 48;
/** Espelha o limite da função SQL 5159 (INVALID_SEARCH acima disso). */
export const ACERVO_QUERY_MAX_LENGTH = 100;
/** Espelha o teto de offset da 5159 (100.000 / 48 ≈ 2083 páginas). */
const MAX_PAGE = 2000;

export type AcervoSort = "recentes" | "set";

export type AcervoCollectionFilter = { kind: "all" } | { kind: "none" } | { kind: "collection"; id: string };

export type AcervoState = {
  query: string | null;
  setCode: string | null;
  languageCode: string | null;
  collection: AcervoCollectionFilter;
  sort: AcervoSort;
  page: number;
  /** Grupo aberto no painel de detalhe. */
  detail: AcervoItemKey | null;
};

export type AcervoItemKey = { cardVariantId: string; languageCode: string };

type Params = Record<string, string | string[] | undefined>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** language.code (190/192): "pt-BR", "en", "ja"… */
const LANGUAGE_CODE = /^[a-z]{2,3}(-[A-Z]{2})?$/;
/** card_set.code: letras, números, ponto e hífen (ex.: "me2", "sv3pt5", "swshp"). */
const SET_CODE = /^[A-Za-z0-9.-]{1,32}$/;

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export function parseAcervoState(params: Params): AcervoState {
  const rawQuery = first(params.q)?.trim().slice(0, ACERVO_QUERY_MAX_LENGTH) ?? "";
  const rawSet = first(params.set)?.trim() ?? "";
  const rawLanguage = first(params.idioma)?.trim() ?? "";
  const rawCollection = first(params.colecao)?.trim() ?? "";
  const rawPage = first(params.pagina) ?? "";
  const rawSort = first(params.ordem) ?? "";

  const collection: AcervoCollectionFilter =
    rawCollection === "sem"
      ? { kind: "none" }
      : UUID.test(rawCollection)
        ? { kind: "collection", id: rawCollection.toLowerCase() }
        : { kind: "all" };

  const pageNumber = /^\d{1,4}$/.test(rawPage) ? Number(rawPage) : 1;

  return {
    query: rawQuery === "" ? null : rawQuery,
    setCode: SET_CODE.test(rawSet) ? rawSet : null,
    languageCode: LANGUAGE_CODE.test(rawLanguage) ? rawLanguage : null,
    collection,
    sort: rawSort === "set" ? "set" : "recentes",
    page: Math.min(Math.max(pageNumber, 1), MAX_PAGE),
    detail: parseItemKey(first(params.carta)),
  };
}

/** `<uuid>.<idioma>` → chave do grupo; qualquer outra forma → `null`. */
export function parseItemKey(raw: string | undefined): AcervoItemKey | null {
  if (!raw) return null;
  const dot = raw.indexOf(".");
  if (dot <= 0) return null;
  const id = raw.slice(0, dot);
  const lang = raw.slice(dot + 1);
  if (!UUID.test(id) || !LANGUAGE_CODE.test(lang)) return null;
  return { cardVariantId: id.toLowerCase(), languageCode: lang };
}

export function formatItemKey(key: AcervoItemKey): string {
  return `${key.cardVariantId}.${key.languageCode}`;
}

/** Algum filtro que reduz o conjunto (busca, Set, idioma, coleção). Ordem e página não contam. */
export function hasActiveFilters(state: AcervoState): boolean {
  return state.query !== null || state.setCode !== null || state.languageCode !== null || state.collection.kind !== "all";
}

/**
 * URL canônica da tela. Parâmetros no padrão não aparecem; mudar filtro ou
 * ordem volta à página 1 (quem chama passa `page` só para paginar).
 */
export function acervoHref(state: Partial<AcervoState>): string {
  const params = new URLSearchParams();
  if (state.query) params.set("q", state.query);
  if (state.setCode) params.set("set", state.setCode);
  if (state.languageCode) params.set("idioma", state.languageCode);
  if (state.collection?.kind === "none") params.set("colecao", "sem");
  if (state.collection?.kind === "collection") params.set("colecao", state.collection.id);
  if (state.sort === "set") params.set("ordem", "set");
  if (state.page && state.page > 1) params.set("pagina", String(state.page));
  if (state.detail) params.set("carta", formatItemKey(state.detail));
  const search = params.toString();
  return search ? `${ACERVO_PATH}?${search}` : ACERVO_PATH;
}

/** Estado da galeria sem o detalhe (para fechar o painel voltando à mesma lista). */
export function withoutDetail(state: AcervoState): AcervoState {
  return { ...state, detail: null };
}

/** Parâmetros da 5159 a partir do estado. */
export function toItemsRpcParams(state: AcervoState) {
  return {
    p_search: state.query,
    p_card_set_code: state.setCode,
    p_language_code: state.languageCode,
    p_collection_id: state.collection.kind === "collection" ? state.collection.id : null,
    p_without_collection: state.collection.kind === "none",
    p_sort: state.sort === "set" ? "SET_NUMBER" : "RECENT",
    p_limit: ACERVO_PAGE_SIZE,
    p_offset: (state.page - 1) * ACERVO_PAGE_SIZE,
  };
}

export function totalPages(totalGroups: number): number {
  return Math.max(1, Math.ceil(totalGroups / ACERVO_PAGE_SIZE));
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

export function formatCount(value: number): string {
  return new Intl.NumberFormat("pt-BR").format(value);
}

/** "1 carta" / "1.248 cartas" — linguagem do colecionador, nunca "registros". */
export function pluralize(value: number, singular: string, plural: string): string {
  return `${formatCount(value)} ${value === 1 ? singular : plural}`;
}

/** Número de colecionador: "025/094" quando há total impresso; senão só o número. */
export function formatCollectorNumber(number: string, total: number | null): string {
  if (total === null || total <= 0) return number;
  const width = String(total).length;
  const padded = /^\d+$/.test(number) ? number.padStart(width, "0") : number;
  return `${padded}/${String(total).padStart(width, "0")}`;
}

/** Nome do idioma para o colecionador (o banco guarda o nome; aqui só o fallback). */
export function languageLabel(code: string, name: string | null): string {
  if (name && name.trim() !== "") return name;
  return code;
}

/**
 * Etiqueta da variante na galeria: só quando NÃO é a padrão (decisão de UX
 * aprovada). Rótulo vazio também não vira etiqueta.
 */
export function variantTag(isDefault: boolean, label: string | null): string | null {
  if (isDefault) return null;
  const trimmed = label?.trim() ?? "";
  return trimmed === "" ? null : trimmed;
}

/** Frase do resultado da busca/filtro ("12 cartas diferentes"). */
export function resultSummary(totalGroups: number): string {
  return totalGroups === 1 ? "1 carta diferente" : `${formatCount(totalGroups)} cartas diferentes`;
}

// ---------------------------------------------------------------------------
// Imagem
// ---------------------------------------------------------------------------

export const CARD_FRONT_BUCKET = "card-front";
/** Formato gravado pelo pipeline de imagens: `<set>/<idioma>/<arquivo>.<ext>` (verificado no LIVE). */
const CARD_FRONT_PATH = /^[a-z0-9][a-z0-9.-]*\/[A-Za-z][A-Za-z-]*\/[A-Za-z0-9][A-Za-z0-9._-]*\.(webp|png|jpe?g)$/;

/**
 * URL pública da frente da carta. Só caminhos no formato do pipeline viram
 * URL (defesa contra valor inesperado); o resto vira `null` e a interface
 * mostra a moldura sem imagem. Bucket público (Seed 895) — sem round-trip.
 */
export function cardFrontUrl(baseUrl: string | undefined, path: string | null | undefined): string | null {
  if (!baseUrl || !path || !CARD_FRONT_PATH.test(path) || path.includes("..")) return null;
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  return `${baseUrl.replace(/\/+$/, "")}/storage/v1/object/public/${CARD_FRONT_BUCKET}/${encoded}`;
}

/** Quantas imagens do topo da grade carregam com prioridade (o restante é lazy). */
export const PRIORITY_CARD_COUNT = 6;
