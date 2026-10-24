import {
  type AcervoItemKey,
  type AcervoState,
  acervoHref,
  formatCount,
  formatItemKey,
  parseAcervoState,
  parseItemKey,
  pluralize,
} from "./acervo.ts";
import { STORAGE_BATCH_MAX, copyStorageFailureFromError } from "./copy-storage.ts";

/**
 * WHERE-05B — mover exemplares em lote a partir da galeria de Meu acervo
 * (regras puras, sem rede; testadas em `acervo-move.test.ts`).
 *
 * Escrita única: `set_physical_cards_storage` (5024), uma chamada, até 500
 * exemplares. O navegador só conhece CHAVES de item (variante + idioma) e o
 * escopo da galeria; os exemplares são resolvidos no servidor, com a sessão
 * do usuário (RLS), reproduzindo os filtros POR EXEMPLAR da 5220:
 *   - idioma: `language_id` do código;
 *   - coleção: o exemplar tem alocação nessa coleção; "sem coleção": nenhuma;
 *   - local: `storage_container_id` igual; "sem local": nulo;
 *   - tudo combinado por AND. Busca e Set só decidem QUAIS itens aparecem.
 *
 * Decisões (CONTRACT CLOSEOUT-01): D1 teto 500 exemplares; D2 só exemplares
 * que atendem aos filtros ativos; D3 seleção sobrevive à paginação e é limpa
 * quando o escopo muda; D4 "selecionar esta página", sem seleção global;
 * D6 revalidação antes da escrita (token do plano); D7 exemplares de coleções
 * arquivadas podem ser movidos.
 */

/** D1 — teto de exemplares numa operação (o mesmo da 5024). */
export const MOVE_COPIES_MAX = STORAGE_BATCH_MAX;
/** Teto de cartas (chaves) numa seleção — nunca mais chaves que exemplares possíveis. */
export const MOVE_KEYS_MAX = STORAGE_BATCH_MAX;
/**
 * Teto de exemplares CANDIDATOS lidos antes do filtro de coleção (que exige a
 * leitura das alocações). Acima disso a resolução não é tentada: `too_large`
 * (fail-closed) — nunca um conjunto truncado.
 */
export const MOVE_CANDIDATES_MAX = 2000;
/** Pares (variante, idioma) por consulta — mantém a URL do PostgREST curta. */
export const MOVE_PAIR_CHUNK = 40;
/** Linhas por página de leitura (abaixo do teto padrão de 1000 do PostgREST). */
export const MOVE_READ_PAGE = 1000;
/** Ids por consulta de alocações (`in.(…)`). */
export const MOVE_ID_CHUNK = 100;

// ---------------------------------------------------------------------------
// Escopo da galeria
// ---------------------------------------------------------------------------

export type MoveScope = Pick<AcervoState, "query" | "setCode" | "languageCode" | "collection" | "storage">;

/** Escopo = busca, Set, idioma, coleção e local. Ordem, página e detalhe não contam. */
export function scopeOf(state: AcervoState): MoveScope {
  return {
    query: state.query,
    setCode: state.setCode,
    languageCode: state.languageCode,
    collection: state.collection,
    storage: state.storage,
  };
}

/**
 * Assinatura canônica do escopo — a mesma serialização da URL (`acervoHref`),
 * sem ordem, página e detalhe. Duas galerias com o mesmo recorte têm a mesma
 * assinatura; qualquer filtro ou busca diferente muda a assinatura.
 */
export function scopeSignature(scope: MoveScope): string {
  const href = acervoHref({ ...scope, sort: "recentes", page: 1, detail: null });
  const query = href.indexOf("?");
  return query < 0 ? "" : href.slice(query + 1);
}

/**
 * Escopo vindo do navegador → escopo canônico, ou `null` se não for canônico
 * (qualquer parâmetro estranho, inválido ou fora de ordem é recusado: o
 * servidor só aceita o que ele mesmo serializaria).
 */
export function scopeFromSignature(raw: unknown): MoveScope | null {
  if (typeof raw !== "string" || raw.length > 400) return null;
  const params: Record<string, string> = {};
  for (const [name, value] of new URLSearchParams(raw)) {
    if (name in params) return null;
    params[name] = value;
  }
  const scope = scopeOf(parseAcervoState(params));
  return scopeSignature(scope) === raw ? scope : null;
}

// ---------------------------------------------------------------------------
// Chaves (o que o navegador envia)
// ---------------------------------------------------------------------------

/** Chaves `<variante>.<idioma>` distintas e válidas (1 a 500), ou `null`. */
export function normalizeMoveKeys(raw: unknown): AcervoItemKey[] | null {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MOVE_KEYS_MAX) return null;
  const seen = new Map<string, AcervoItemKey>();
  for (const value of raw) {
    if (typeof value !== "string") return null;
    const key = parseItemKey(value);
    if (!key) return null;
    seen.set(formatItemKey(key), key);
  }
  return [...seen.values()];
}

export function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/** Filtro PostgREST `or=(…)` com os pares EXATOS (variante E idioma) — nunca o produto cartesiano. */
export function pairOrFilter(pairs: readonly { cardVariantId: string; languageId: string }[]): string {
  return pairs.map((p) => `and(card_variant_id.eq.${p.cardVariantId},language_id.eq.${p.languageId})`).join(",");
}

// ---------------------------------------------------------------------------
// Plano
// ---------------------------------------------------------------------------

export type CandidateCopy = {
  id: string;
  cardVariantId: string;
  languageId: string;
  storageContainerId: string | null;
};

export type MovePlan = {
  /** Exemplares abrangidos (S), ordenados por id — inclui os que já estão no destino. */
  copies: CandidateCopy[];
  /** Ids a gravar (S menos os que já estão no destino), ordenados. */
  toMove: string[];
  atTarget: number;
  /** Dos que vão mudar: quantos saem de outro local / quantos não tinham local. */
  fromOther: number;
  fromNone: number;
  /** Chaves selecionadas sem nenhum exemplar abrangido agora (salvaguarda 1). */
  unresolvedKeys: string[];
  /** Exemplares abrangidos por chave (para a prévia). */
  perKey: Record<string, number>;
};

/**
 * Aplica os filtros por exemplar da 5220 sobre os candidatos já lidos e monta
 * o plano. Defesa em profundidade: a consulta já filtrou pares e local, mas o
 * plano confere de novo — um candidato fora do escopo nunca entra em S.
 *
 * `allocationByCopy` só é exigido com filtro de coleção: id do exemplar →
 * id da coleção (ausente = sem coleção).
 */
export function buildMovePlan(input: {
  keys: readonly AcervoItemKey[];
  languageIdByCode: ReadonlyMap<string, string>;
  candidates: readonly CandidateCopy[];
  allocationByCopy: ReadonlyMap<string, string> | null;
  scope: MoveScope;
  target: string | null;
}): MovePlan {
  const { keys, languageIdByCode, scope, target } = input;
  const scopeLanguageId = scope.languageCode ? (languageIdByCode.get(scope.languageCode) ?? null) : null;
  const keyByPair = new Map<string, string>();
  for (const key of keys) {
    const languageId = languageIdByCode.get(key.languageCode);
    if (!languageId) continue;
    if (scope.languageCode && key.languageCode !== scope.languageCode) continue;
    keyByPair.set(`${key.cardVariantId}|${languageId}`, formatItemKey(key));
  }

  const perKey: Record<string, number> = {};
  const byId = new Map<string, CandidateCopy>();
  for (const copy of input.candidates) {
    const key = keyByPair.get(`${copy.cardVariantId.toLowerCase()}|${copy.languageId}`);
    if (!key) continue;
    if (scope.languageCode && copy.languageId !== scopeLanguageId) continue;
    if (scope.storage.kind === "location" && copy.storageContainerId !== scope.storage.id) continue;
    if (scope.storage.kind === "none" && copy.storageContainerId !== null) continue;
    if (scope.collection.kind !== "all") {
      if (!input.allocationByCopy) continue; // sem a leitura de alocações, nada entra (fail-closed)
      const collectionId = input.allocationByCopy.get(copy.id);
      if (scope.collection.kind === "none" && collectionId !== undefined) continue;
      if (scope.collection.kind === "collection" && collectionId !== scope.collection.id) continue;
    }
    if (byId.has(copy.id)) continue;
    byId.set(copy.id, copy);
    perKey[key] = (perKey[key] ?? 0) + 1;
  }

  const copies = [...byId.values()].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const moving = copies.filter((copy) => copy.storageContainerId !== target);
  return {
    copies,
    toMove: moving.map((copy) => copy.id),
    atTarget: copies.length - moving.length,
    fromOther: moving.filter((copy) => copy.storageContainerId !== null).length,
    fromNone: moving.filter((copy) => copy.storageContainerId === null).length,
    unresolvedKeys: keys.map(formatItemKey).filter((key) => !perKey[key]).sort(),
    perKey,
  };
}

/**
 * Linha canônica do token do plano (o servidor aplica SHA-256 e prefixa
 * `v1:`). Cobre destino, escopo, chaves e cada exemplar COM seu local atual:
 * exemplar a mais, a menos ou movido por outra via entre a prévia e a
 * confirmação muda o token → `plan_changed`. Sem segredo e sem persistência:
 * o token não autoriza nada, só prova que o conjunto não mudou.
 */
export function planTokenSource(input: {
  target: string | null;
  scopeSignature: string;
  keys: readonly AcervoItemKey[];
  copies: readonly CandidateCopy[];
}): string {
  const keys = input.keys.map(formatItemKey).sort().join(",");
  const copies = input.copies
    .map((copy) => `${copy.id}:${copy.storageContainerId ?? "-"}`)
    .sort()
    .join(",");
  return ["v1", input.target ?? "-", input.scopeSignature, keys, copies].join("|");
}

// ---------------------------------------------------------------------------
// Falhas
// ---------------------------------------------------------------------------

export type MoveFailure =
  | "not_authenticated"
  | "invalid"
  | "empty"
  | "too_large"
  | "storage_gone"
  | "plan_changed"
  | "unresolved"
  | "binder_locked"
  | "unavailable"
  | "unknown";

/**
 * Erro da 5024 → falha da operação. Um erro com código SQLSTATE veio do banco
 * e a função é atômica: nada foi gravado. Sem código (rede, timeout, resposta
 * sem forma) não dá para saber → `unknown` — refazer a prévia, nunca repetir.
 */
export function moveFailureFromWrite(error: { code?: string | null; message?: string | null } | null | undefined): MoveFailure {
  const fromDb = typeof error?.code === "string" && /^[0-9A-Z]{5}$/.test(error.code);
  const reason = copyStorageFailureFromError(error);
  switch (reason) {
    case "not_authenticated":
      return "not_authenticated";
    case "storage_gone":
      return "storage_gone";
    case "copies_gone":
      return "plan_changed";
    case "too_many":
      return "too_large";
    case "invalid":
      return "invalid";
    case "binder_positioned":
      return "plan_changed";
    case "binder_locked":
      return "binder_locked";
    case "unavailable":
      return fromDb ? "unavailable" : "unknown";
  }
}

export function moveFailureMessage(reason: MoveFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "invalid":
      return "Não foi possível entender a seleção. Selecione as cartas de novo.";
    case "empty":
      return "Nenhum exemplar das cartas selecionadas atende aos filtros agora. Nada foi alterado.";
    case "too_large":
      return `A seleção passa de ${formatCount(MOVE_COPIES_MAX)} exemplares. Desmarque algumas cartas ou use um filtro mais específico. Nada foi alterado.`;
    case "storage_gone":
      return "Esse local não existe mais. Escolha outro destino. Nada foi alterado.";
    case "plan_changed":
      return "Seu acervo mudou desde a prévia. Confira a nova prévia antes de confirmar. Nada foi alterado.";
    case "unresolved":
      return "Algumas cartas selecionadas não têm mais exemplares neste recorte. Revise a seleção antes de confirmar.";
    case "binder_locked":
      return "Há exemplar num bolso fixado do fichário digital. Solte o cadeado no fichário antes de mover — nada foi alterado.";
    case "unavailable":
      return "Não foi possível mover agora. Nada foi alterado — tente novamente.";
    case "unknown":
      return "Não conseguimos confirmar se a mudança foi gravada. Refaça a prévia para conferir onde os exemplares estão — não repita às cegas.";
  }
}

// ---------------------------------------------------------------------------
// Textos
// ---------------------------------------------------------------------------

export function moveSelectionSummary(cards: number, copies: number): string {
  return `${pluralize(cards, "carta", "cartas")} · ${pluralize(copies, "exemplar", "exemplares")}`;
}

export function moveConfirmTitle(count: number, targetName: string | null): string {
  const what = pluralize(count, "exemplar", "exemplares");
  return targetName === null ? `Remover a localização de ${what}?` : `Mover ${what} para “${targetName}”?`;
}

export function moveConfirmAction(count: number, targetName: string | null): string {
  return targetName === null
    ? `Remover localização de ${pluralize(count, "exemplar", "exemplares")}`
    : `Mover ${pluralize(count, "exemplar", "exemplares")}`;
}

export function moveSuccessMessage(count: number, targetName: string | null, atTarget: number): string {
  const what = pluralize(count, "exemplar", "exemplares");
  const main =
    targetName === null
      ? `${what} ${count === 1 ? "ficou" : "ficaram"} sem localização definida.`
      : `${what} ${count === 1 ? "movido" : "movidos"} para “${targetName}”.`;
  const already = atTarget > 0 ? ` ${pluralize(atTarget, "já estava", "já estavam")} lá.` : "";
  return `${main}${already} Nenhuma carta mudou de coleção.`;
}
