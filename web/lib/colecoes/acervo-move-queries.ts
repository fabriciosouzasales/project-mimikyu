import { createHash } from "node:crypto";
import type { AcervoItemKey } from "./acervo.ts";
import {
  type CandidateCopy,
  MOVE_CANDIDATES_MAX,
  MOVE_COPIES_MAX,
  MOVE_ID_CHUNK,
  MOVE_PAIR_CHUNK,
  MOVE_READ_PAGE,
  type MoveFailure,
  type MovePlan,
  type MoveScope,
  buildMovePlan,
  chunk,
  moveFailureFromWrite,
  pairOrFilter,
  planTokenSource,
} from "./acervo-move.ts";
import { binderPositionBlock, parseBinderImpact } from "./binder-location.ts";

/**
 * WHERE-05B — resolução no servidor do conjunto de exemplares a mover e
 * execução revalidada (sem `"use server"`: chamado pelas actions de
 * `app/colecoes/acervo/actions.ts`; testado com cliente falso em
 * `acervo-move-queries.test.ts`).
 *
 * Todas as leituras usam o cliente com a sessão do usuário (RLS select-own em
 * `inventory`, `physical_card`, `collection_allocation` e `storage_container`)
 * e, além disso, filtram explicitamente pelo inventário do chamador — o mesmo
 * recorte da 5220. Nenhuma leitura confia no limite de linhas do PostgREST:
 * cada consulta pede `count: 'exact'`, pagina por `id` e só é aceita quando o
 * número de linhas lidas é igual à contagem. Acima do teto, `too_large`
 * (fail-closed): um conjunto truncado nunca chega à escrita.
 */

/** Superfície mínima do cliente Supabase usada aqui (permite o cliente falso nos testes). */
type QueryResult = { data: unknown; error: { code?: string; message?: string } | null; count?: number | null };
type Query = PromiseLike<QueryResult> & {
  select(columns: string, options?: { count?: "exact" }): Query;
  eq(column: string, value: string): Query;
  is(column: string, value: null): Query;
  in(column: string, values: readonly string[]): Query;
  or(filter: string): Query;
  order(column: string, options?: { ascending?: boolean }): Query;
  range(from: number, to: number): Query;
  limit(count: number): Query;
};
export type MoveClient = {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null }; error: unknown }> };
  from(table: string): Query;
  rpc(fn: string, args?: Record<string, unknown>): PromiseLike<QueryResult>;
};

export type MoveRequest = {
  keys: AcervoItemKey[];
  scope: MoveScope;
  scopeSignature: string;
  target: string | null;
};

export type MovePreview = {
  token: string;
  targetId: string | null;
  targetName: string | null;
  /** Exemplares abrangidos (S), incluindo os que já estão no destino. */
  total: number;
  toMove: number;
  atTarget: number;
  fromOther: number;
  fromNone: number;
  unresolvedKeys: string[];
  perKey: Record<string, number>;
  /**
   * BINDER-PHYSICAL-LOCATION (5249, D3): dos que vão mudar, quantos estão num
   * bolso do fichário digital (sairão dele, com a confirmação desta prévia) e
   * quantos estão em bolso fixado (impedem a mudança até destravar).
   */
  binderPositioned: number;
  binderLocked: number;
};

type Fail = { ok: false; reason: MoveFailure };
type Options = { pageSize?: number };

export function planToken(source: string): string {
  return `v1:${createHash("sha256").update(source).digest("hex")}`;
}

/**
 * Lê todas as linhas de uma consulta, página a página, exigindo completude.
 * `cap`: contagem acima disso → `too_large` sem ler o resto.
 */
async function readAll<T>(build: () => Query, cap: number, pageSize: number): Promise<{ ok: true; rows: T[] } | Fail> {
  const rows: T[] = [];
  let expected: number | null = null;
  // A próxima página começa no que de fato chegou (o servidor pode devolver
  // menos linhas que o pedido — `max-rows` do PostgREST): nunca pula linhas.
  while (expected === null || rows.length < expected) {
    const from = rows.length;
    const { data, error, count } = await build().range(from, from + pageSize - 1);
    if (error || !Array.isArray(data) || typeof count !== "number") return { ok: false, reason: "unavailable" };
    if (expected === null) {
      if (count > cap) return { ok: false, reason: "too_large" };
      expected = count;
    } else if (count !== expected) {
      // O conjunto mudou durante a leitura: não há leitura completa e coerente.
      return { ok: false, reason: "unavailable" };
    }
    if (data.length === 0 && rows.length < expected) return { ok: false, reason: "unavailable" };
    rows.push(...(data as T[]));
    if (rows.length > expected) return { ok: false, reason: "unavailable" };
  }
  return { ok: true, rows };
}

/**
 * Resolve o conjunto S de exemplares das chaves selecionadas no escopo da
 * galeria e monta o plano + token. Não grava nada.
 */
export async function resolveMoveSet(
  supabase: MoveClient,
  request: MoveRequest,
  options: Options = {},
): Promise<{ ok: true; plan: MovePlan; preview: MovePreview } | Fail> {
  const pageSize = options.pageSize ?? MOVE_READ_PAGE;
  const { data: auth } = await supabase.auth.getUser();
  const userId = auth?.user?.id;
  if (!userId) return { ok: false, reason: "not_authenticated" };

  // Destino vigente, do próprio usuário (RLS select-own).
  let targetName: string | null = null;
  if (request.target !== null) {
    const { data, error } = await supabase.from("storage_container").select("id, name").eq("id", request.target).limit(2);
    if (error || !Array.isArray(data)) return { ok: false, reason: "unavailable" };
    const row = (data as { id: string; name: string }[])[0];
    if (!row || data.length !== 1) return { ok: false, reason: "storage_gone" };
    targetName = row.name;
  }

  // Inventário do chamador (o mesmo recorte da 5220).
  const inventory = await supabase.from("inventory").select("id").eq("owner_user_id", userId).limit(2);
  if (inventory.error || !Array.isArray(inventory.data) || inventory.data.length > 1) return { ok: false, reason: "unavailable" };
  const inventoryId = (inventory.data as { id: string }[])[0]?.id ?? null;

  // Idioma: código → id pela leitura do colecionador (5164); `language` é admin-only.
  const languages = await supabase.rpc("get_registrable_languages");
  if (languages.error || !Array.isArray(languages.data)) return { ok: false, reason: "unavailable" };
  const languageIdByCode = new Map<string, string>();
  for (const row of languages.data as { language_id?: unknown; code?: unknown }[]) {
    if (typeof row.code === "string" && typeof row.language_id === "string") languageIdByCode.set(row.code, row.language_id);
  }

  const pairs = request.keys
    .filter((key) => !request.scope.languageCode || key.languageCode === request.scope.languageCode)
    .map((key) => ({ cardVariantId: key.cardVariantId, languageId: languageIdByCode.get(key.languageCode) }))
    .filter((pair): pair is { cardVariantId: string; languageId: string } => typeof pair.languageId === "string");

  // Sem filtro de coleção, S = candidatos: passar de 500 já é `too_large`.
  const withCollection = request.scope.collection.kind !== "all";
  let remaining = withCollection ? MOVE_CANDIDATES_MAX : MOVE_COPIES_MAX;
  const candidates: CandidateCopy[] = [];
  if (inventoryId !== null) {
    for (const group of chunk(pairs, MOVE_PAIR_CHUNK)) {
      const filter = pairOrFilter(group);
      const storage = request.scope.storage;
      const read = await readAll<{ id: string; card_variant_id: string; language_id: string; storage_container_id: string | null }>(
        () => {
          let query = supabase
            .from("physical_card")
            .select("id, card_variant_id, language_id, storage_container_id", { count: "exact" })
            .eq("inventory_id", inventoryId)
            .or(filter);
          if (storage.kind === "location") query = query.eq("storage_container_id", storage.id);
          if (storage.kind === "none") query = query.is("storage_container_id", null);
          return query.order("id", { ascending: true });
        },
        remaining,
        pageSize,
      );
      if (!read.ok) return read;
      remaining -= read.rows.length;
      for (const row of read.rows) {
        candidates.push({
          id: row.id,
          cardVariantId: row.card_variant_id,
          languageId: row.language_id,
          storageContainerId: row.storage_container_id,
        });
      }
    }
  }

  // Filtro de coleção: alocação de cada candidato (0..1 por exemplar, UNIQUE).
  let allocationByCopy: Map<string, string> | null = null;
  if (withCollection) {
    allocationByCopy = new Map();
    for (const ids of chunk(candidates.map((c) => c.id), MOVE_ID_CHUNK)) {
      const read = await readAll<{ physical_card_id: string; collection_id: string }>(
        () =>
          supabase
            .from("collection_allocation")
            .select("physical_card_id, collection_id", { count: "exact" })
            .in("physical_card_id", ids)
            .order("physical_card_id", { ascending: true }),
        ids.length,
        pageSize,
      );
      if (!read.ok) return read.reason === "too_large" ? { ok: false, reason: "unavailable" } : read;
      for (const row of read.rows) allocationByCopy.set(row.physical_card_id, row.collection_id);
    }
  }

  const plan = buildMovePlan({
    keys: request.keys,
    languageIdByCode,
    candidates,
    allocationByCopy,
    scope: request.scope,
    target: request.target,
  });
  if (plan.copies.length > MOVE_COPIES_MAX) return { ok: false, reason: "too_large" };
  if (plan.copies.length === 0) return { ok: false, reason: "empty" };

  // D3: quantos dos que vão mudar estão em bolsos do fichário digital (5249, só leitura).
  let binderPositioned = 0;
  let binderLocked = 0;
  if (plan.toMove.length > 0) {
    const impactRead = await supabase.rpc("preview_my_physical_cards_binder_impact", {
      p_physical_card_ids: plan.toMove,
      p_storage_container_id: request.target,
    });
    const impact = impactRead.error ? null : parseBinderImpact(impactRead.data);
    if (!impact) return { ok: false, reason: "unavailable" };
    binderPositioned = impact.positioned;
    binderLocked = impact.locked;
  }

  const token = planToken(
    planTokenSource({ target: request.target, scopeSignature: request.scopeSignature, keys: request.keys, copies: plan.copies }),
  );
  return {
    ok: true,
    plan,
    preview: {
      token,
      targetId: request.target,
      targetName,
      total: plan.copies.length,
      toMove: plan.toMove.length,
      atTarget: plan.atTarget,
      fromOther: plan.fromOther,
      fromNone: plan.fromNone,
      unresolvedKeys: plan.unresolvedKeys,
      perKey: plan.perKey,
      binderPositioned,
      binderLocked,
    },
  };
}

export type ExecuteResult =
  | { ok: true; updated: number; atTarget: number; targetName: string | null }
  | { ok: false; reason: "plan_changed"; preview: MovePreview }
  | Fail;

/**
 * Confirmação (D6): revalida tudo e só então faz UMA chamada à 5024.
 *   1. resolve S de novo (≤ 500, leituras completas);
 *   2. chaves sem exemplar → `unresolved` (salvaguarda 1: nunca excluir em silêncio);
 *   3. token diferente ou quantidade a gravar diferente da confirmada →
 *      `plan_changed` com a nova prévia (o conjunto não cresce nem muda em silêncio);
 *   4. nada a gravar → sucesso com 0 (idempotente: confirmação repetida não regrava);
 *   5. impacto no fichário digital diferente do confirmado → `plan_changed`;
 *      bolso fixado → `binder_locked` (nada é gravado);
 *   6. `set_physical_cards_storage` (sobrecarga 5249) com exatamente os ids de
 *      `toMove` e a confirmação de tirar do bolso só se a prévia mostrou isso.
 * Nunca repete a escrita sozinha. Janela residual entre (1) e (5) aceita (D6):
 * a 5024 ainda confere dono e atomicidade.
 */
export async function executeMove(
  supabase: MoveClient,
  request: MoveRequest & { planToken: string; expectedCount: number; expectedUnplace: number },
  options: Options = {},
): Promise<ExecuteResult> {
  const resolved = await resolveMoveSet(supabase, request, options);
  // `empty` aqui = todos os exemplares saíram do recorte desde a prévia: nada a gravar.
  if (!resolved.ok) return resolved;
  const { plan, preview } = resolved;
  if (preview.unresolvedKeys.length > 0) return { ok: false, reason: "unresolved" };
  if (preview.token !== request.planToken || plan.toMove.length !== request.expectedCount) {
    return { ok: false, reason: "plan_changed", preview };
  }
  if (plan.toMove.length === 0) return { ok: true, updated: 0, atTarget: plan.atTarget, targetName: preview.targetName };
  if (preview.binderLocked > 0) return { ok: false, reason: "binder_locked" };
  if (preview.binderPositioned !== request.expectedUnplace) return { ok: false, reason: "plan_changed", preview };

  let result: QueryResult;
  try {
    result = await supabase.rpc("set_physical_cards_storage", {
      p_storage_container_id: request.target,
      p_physical_card_ids: plan.toMove,
      p_unplace_from_binder: preview.binderPositioned > 0,
    });
  } catch {
    return { ok: false, reason: "unknown" };
  }
  if (result.error) {
    const block = binderPositionBlock(result.error);
    // Posição criada depois da prévia (sem confirmação) → refazer a prévia; cadeado → destravar.
    if (block === "confirm_required") return { ok: false, reason: "plan_changed" };
    if (block === "locked") return { ok: false, reason: "binder_locked" };
    return { ok: false, reason: moveFailureFromWrite(result.error) };
  }
  if (!Array.isArray(result.data)) return { ok: false, reason: "unknown" };
  return { ok: true, updated: result.data.length, atTarget: plan.atTarget, targetName: preview.targetName };
}
