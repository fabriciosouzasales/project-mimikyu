"use server";

import { revalidatePath } from "next/cache";
import { ACERVO_PATH } from "@/lib/colecoes/acervo";
import {
  ADD_MAX_QUANTITY,
  type AddFailure,
  type AddVariant,
  type PreviewResult,
  type RegisterItem,
  type RegisterResult,
  classifyFailure,
  confirmCardsRequest,
  confirmSetRequest,
  isUuid,
  parsePreview,
  parseRegister,
  previewCardsRequest,
  previewSetRequest,
  validRegisterItems,
} from "@/lib/colecoes/acervo-add";
import { COLECOES_PATH } from "@/lib/colecoes/colecoes";
import { type CopyStorageFailure, copyStorageFailureFromError, normalizeStorageBatch } from "@/lib/colecoes/copy-storage";
import { MOVE_COPIES_MAX, type MoveFailure, normalizeMoveKeys, scopeFromSignature } from "@/lib/colecoes/acervo-move";
import {
  type ExecuteResult,
  type MoveClient,
  type MovePreview,
  type MoveRequest,
  executeMove,
  resolveMoveSet,
} from "@/lib/colecoes/acervo-move-queries";
import { LOCAIS_PATH } from "@/lib/colecoes/storage-locations";
import { createClient } from "@/lib/supabase/server";

/**
 * Meu acervo — ações de cadastro (MY-INVENTORY-ACTIONS-01).
 *
 * Só chamam RPCs já implantadas no LIVE, com a sessão do usuário (cookies) —
 * nunca `service_role`. Nenhuma regra de domínio é repetida aqui: dono,
 * variante ativa, idioma, teto, fingerprint (TOCTOU) e idempotência são
 * decididos pelo banco. Esta camada só valida o formato para responder cedo,
 * monta os envelopes fechados e traduz o resultado.
 *
 * Idempotência: a chave vem do cliente, gerada uma vez por revisão aprovada e
 * reaproveitada em toda nova tentativa da MESMA confirmação — repetir (clique
 * duplo, timeout, rede) devolve REPLAY, nunca cartas em dobro.
 */

type Fail = { ok: false; reason: AddFailure };

export async function listCardVariantsForAdd(
  cardId: string,
): Promise<{ ok: true; variants: AddVariant[] } | Fail> {
  if (!isUuid(cardId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_catalog_card_variants_for_picker", { p_card_id: cardId });
  if (error || !Array.isArray(data)) {
    return fail("get_catalog_card_variants_for_picker", startedAt, error);
  }
  const variants = (data as { card_variant_id: string; is_default_variant: boolean; variant_label: string | null }[]).map(
    (row) => ({ id: row.card_variant_id, label: row.variant_label, isDefault: row.is_default_variant }),
  );
  return { ok: true, variants };
}

/**
 * Card Set por código → id. Usa a pesquisa pública de cartas (`search_cards`,
 * ADR-030), que devolve o id do Set de cada carta; uma linha basta.
 */
export async function resolveCardSetForAdd(setCode: string): Promise<{ ok: true; cardSetId: string } | Fail> {
  const code = typeof setCode === "string" ? setCode.trim().slice(0, 50) : "";
  if (!code) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("search_cards", {
    p_query: null,
    p_card_id: null,
    p_card_set_code: code,
    p_category_code: null,
    p_rarity_code: null,
    p_limit: 1,
    p_offset: 0,
  });
  if (error || !Array.isArray(data)) return fail("search_cards", startedAt, error);
  const cardSetId = (data as { card_set_id?: string }[])[0]?.card_set_id;
  if (!isUuid(cardSetId)) return { ok: false, reason: "set_empty" };
  return { ok: true, cardSetId };
}

export async function previewAddCards(items: RegisterItem[]): Promise<{ ok: true; preview: PreviewResult } | Fail> {
  if (!validRegisterItems(items)) return { ok: false, reason: "invalid" };
  return preview(previewCardsRequest(items));
}

export async function confirmAddCards(input: {
  idempotencyKey: string;
  fingerprint: string;
  items: RegisterItem[];
}): Promise<{ ok: true; result: RegisterResult } | Fail> {
  if (!isUuid(input?.idempotencyKey) || !validFingerprint(input.fingerprint) || !validRegisterItems(input.items)) {
    return { ok: false, reason: "invalid" };
  }
  return register(
    "register_physical_cards_bulk",
    confirmCardsRequest(input.idempotencyKey, input.fingerprint, input.items),
  );
}

export async function previewAddSet(input: {
  cardSetId: string;
  languageId: string;
}): Promise<{ ok: true; preview: PreviewResult } | Fail> {
  if (!isUuid(input?.cardSetId) || !isUuid(input.languageId)) return { ok: false, reason: "invalid" };
  return preview(previewSetRequest(input.cardSetId, input.languageId));
}

export async function confirmAddSet(input: {
  idempotencyKey: string;
  fingerprint: string;
  cardSetId: string;
  languageId: string;
}): Promise<{ ok: true; result: RegisterResult } | Fail> {
  if (
    !isUuid(input?.idempotencyKey) ||
    !validFingerprint(input.fingerprint) ||
    !isUuid(input.cardSetId) ||
    !isUuid(input.languageId)
  ) {
    return { ok: false, reason: "invalid" };
  }
  return register(
    "register_card_set_bulk",
    confirmSetRequest(input.idempotencyKey, input.fingerprint, input.cardSetId, input.languageId),
  );
}

/**
 * Remove um exemplar cadastrado por engano (INVENTORY-REMOVE-COPY-01, Query
 * 5165). Correção de cadastro — não é saída de propriedade (venda, troca).
 * O banco só remove exemplar do próprio usuário e sem coleção; exemplar
 * alheio ou já removido devolve `false` (idempotente, não enumera).
 */
export async function removeMyCopy(physicalCardId: string): Promise<{ ok: true; removed: boolean } | Fail> {
  if (!isUuid(physicalCardId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("remove_my_physical_card", { p_physical_card_id: physicalCardId });
  if (error || typeof data !== "boolean") return fail("remove_my_physical_card", startedAt, error ?? { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "acervo.remove", ms: Date.now() - startedAt, removed: data }));
  revalidatePath(ACERVO_PATH);
  return { ok: true, removed: data };
}

/**
 * Aumentar a quantidade de exemplares de um grupo (INVENTORY-COPY-QUANTITY-01)
 * = registrar N exemplares novos da mesma variante e idioma pelo contrato B1
 * já no LIVE. Revisão e confirmação na mesma chamada: o banco continua
 * decidindo tudo (dono, variante ativa, teto) e o fingerprint protege contra
 * mudança entre as duas etapas. A chave de idempotência vem do cliente, uma por
 * quantidade escolhida — repetir a mesma confirmação devolve REPLAY.
 */
export async function addMyCopies(input: {
  idempotencyKey: string;
  cardVariantId: string;
  languageId: string;
  quantity: number;
}): Promise<{ ok: true; result: RegisterResult } | Fail> {
  const items: RegisterItem[] = [
    { card_variant_id: input?.cardVariantId, language_id: input?.languageId, quantity: input?.quantity },
  ];
  if (!isUuid(input?.idempotencyKey) || !validRegisterItems(items)) return { ok: false, reason: "invalid" };
  const reviewed = await preview(previewCardsRequest(items));
  if (!reviewed.ok) return reviewed;
  if (!reviewed.preview.ok || !reviewed.preview.fingerprint) {
    return { ok: false, reason: blockedReason(reviewed.preview) };
  }
  return register(
    "register_physical_cards_bulk",
    confirmCardsRequest(input.idempotencyKey, reviewed.preview.fingerprint, items),
  );
}

/**
 * Diminuir a quantidade = remover exemplares escolhidos (correção de cadastro,
 * mesma regra da lixeira: só exemplar do próprio usuário e fora de coleção).
 * Um por vez, em ordem; para no primeiro erro e informa quantos saíram.
 * Repetir é seguro: exemplar já removido conta como "não removido", sem erro.
 */
export async function removeMyCopies(
  physicalCardIds: string[],
): Promise<{ ok: true; removed: number } | { ok: false; reason: AddFailure; removed: number }> {
  if (
    !Array.isArray(physicalCardIds) ||
    physicalCardIds.length === 0 ||
    physicalCardIds.length > ADD_MAX_QUANTITY ||
    new Set(physicalCardIds).size !== physicalCardIds.length ||
    !physicalCardIds.every((id) => isUuid(id))
  ) {
    return { ok: false, reason: "invalid", removed: 0 };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  let removed = 0;
  for (const id of physicalCardIds) {
    const { data, error } = await supabase.rpc("remove_my_physical_card", { p_physical_card_id: id });
    if (error || typeof data !== "boolean") {
      const failed = fail("remove_my_physical_card", startedAt, error ?? { code: "BAD_SHAPE" });
      if (removed > 0) revalidatePath(ACERVO_PATH);
      return { ok: false, reason: failed.reason, removed };
    }
    if (data) removed += 1;
  }
  console.info(JSON.stringify({ scope: "acervo.remove", ms: Date.now() - startedAt, requested: physicalCardIds.length, removed }));
  revalidatePath(ACERVO_PATH);
  return { ok: true, removed };
}

// ---- internos ----

function blockedReason(reviewed: PreviewResult): AddFailure {
  const code = reviewed.issues[0]?.code ?? "";
  return classifyFailure("22023", code);
}

function validFingerprint(value: unknown): value is string {
  return typeof value === "string" && value.trim() !== "" && value.length <= 512;
}

async function preview(request: object): Promise<{ ok: true; preview: PreviewResult } | Fail> {
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_bulk_operation", { p_request: request });
  if (error) return fail("preview_bulk_operation", startedAt, error);
  const parsed = parsePreview(data);
  if (!parsed) return fail("preview_bulk_operation", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, preview: parsed };
}

async function register(
  fn: "register_physical_cards_bulk" | "register_card_set_bulk",
  request: object,
): Promise<{ ok: true; result: RegisterResult } | Fail> {
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, { p_request: request });
  if (error) return fail(fn, startedAt, error);
  const parsed = parseRegister(data);
  if (!parsed) return fail(fn, startedAt, { code: "BAD_SHAPE" });
  console.info(
    JSON.stringify({ scope: "acervo.add", fn, ms: Date.now() - startedAt, outcome: parsed.replay ? "REPLAY" : "CREATED", created: parsed.createdCount }),
  );
  revalidatePath(ACERVO_PATH);
  return { ok: true, result: parsed };
}

function fail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): Fail {
  const reason = classifyFailure(error?.code, error?.message);
  // Sem dados do usuário: só função, duração, código e a classe do erro.
  console.error(JSON.stringify({ scope: "acervo.add", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

// ---------------------------------------------------------------------------
// WHERE-03 — localização física dos exemplares (5024)
// ---------------------------------------------------------------------------

/**
 * Guarda (ou tira de local) exemplares do próprio acervo — `set_physical_cards_storage`
 * (5024, canônica). Local não nulo atribui/move; `null` limpa ("Sem localização
 * definida"). 1 a 500 exemplares; atômica (um exemplar alheio → nada muda);
 * idempotente por estado. Dono do local e dos exemplares conferidos pelo banco.
 *
 * Só muda `physical_card.storage_container_id`: coleção, variante, idioma,
 * condição e quantidade ficam como estão. A confirmação explícita (NS-13) é
 * feita na interface antes desta chamada.
 */
export async function setMyCopiesStorage(input: {
  physicalCardIds: string[];
  storageContainerId: string | null;
}): Promise<{ ok: true; updated: number; storageContainerId: string | null } | { ok: false; reason: CopyStorageFailure }> {
  const ids = normalizeStorageBatch(input?.physicalCardIds);
  if (ids === null) {
    const tooMany = Array.isArray(input?.physicalCardIds) && input.physicalCardIds.length > 500;
    return { ok: false, reason: tooMany ? "too_many" : "invalid" };
  }
  const target = input.storageContainerId ?? null;
  if (target !== null && !isUuid(target)) return { ok: false, reason: "storage_gone" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_physical_cards_storage", {
    p_storage_container_id: target,
    p_physical_card_ids: ids,
  });
  if (error || !Array.isArray(data)) {
    const reason = copyStorageFailureFromError(error);
    // Sem dados do usuário: só função, duração, código e a classe do erro.
    console.error(JSON.stringify({ scope: "colecoes.write", fn: "set_physical_cards_storage", ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
    if (reason === "storage_gone" || reason === "copies_gone") revalidatePath(ACERVO_PATH);
    return { ok: false, reason };
  }
  console.info(
    JSON.stringify({ scope: "colecoes.copy_storage", ms: Date.now() - startedAt, requested: ids.length, updated: data.length, clear: target === null }),
  );
  // Nome do local aparece no detalhe do acervo, nas coleções e nas contagens de Meus locais.
  revalidatePath(ACERVO_PATH);
  revalidatePath(LOCAIS_PATH);
  revalidatePath(COLECOES_PATH, "layout");
  return { ok: true, updated: data.length, storageContainerId: target };
}

// ---------------------------------------------------------------------------
// WHERE-05B — mover exemplares em lote a partir da galeria (5024, sem RPC nova)
// ---------------------------------------------------------------------------

/**
 * O navegador envia só CHAVES de item (`<variante>.<idioma>`), o escopo
 * canônico da galeria e o destino — nunca ids de exemplar. O servidor resolve
 * os exemplares com a sessão do usuário (RLS + inventário do chamador),
 * reproduzindo os filtros por exemplar da 5220, com leituras completas
 * (`count: 'exact'` + paginação) e teto de 500 (fail-closed `too_large`).
 * Ver `lib/colecoes/acervo-move.ts` e `acervo-move-queries.ts`.
 */
type MoveInput = { keys: string[]; scope: string; target: string | null };

function parseMoveInput(input: MoveInput): MoveRequest | null {
  const keys = normalizeMoveKeys(input?.keys);
  const scope = scopeFromSignature(input?.scope);
  const target = input?.target ?? null;
  if (!keys || !scope || (target !== null && !isUuid(target))) return null;
  return { keys, scope, scopeSignature: input.scope, target: target === null ? null : target.toLowerCase() };
}

// O cliente do servidor é um SupabaseClient completo; `MoveClient` descreve só
// a superfície usada (from/select/eq/is/in/or/order/range/limit, rpc, auth).
async function moveClient(): Promise<MoveClient> {
  return (await createClient()) as unknown as MoveClient;
}

/** Prévia: resolve o conjunto e devolve contagens + token. Não grava nada. */
export async function previewMyCopiesMove(input: MoveInput): Promise<{ ok: true; preview: MovePreview } | { ok: false; reason: MoveFailure }> {
  const request = parseMoveInput(input);
  if (!request) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const result = await resolveMoveSet(await moveClient(), request);
  console.info(
    JSON.stringify({
      scope: "acervo.move",
      step: "preview",
      ms: Date.now() - startedAt,
      keys: request.keys.length,
      outcome: result.ok ? "OK" : result.reason,
      total: result.ok ? result.preview.total : null,
      unresolved: result.ok ? result.preview.unresolvedKeys.length : null,
    }),
  );
  return result.ok ? { ok: true, preview: result.preview } : result;
}

/**
 * Confirmação: revalida (token + quantidade confirmada) e faz UMA chamada à
 * 5024. Nunca repete a escrita sozinha; resultado sem resposta → `unknown`.
 */
export async function moveMyCopies(input: MoveInput & { planToken: string; expectedCount: number }): Promise<ExecuteResult> {
  const request = parseMoveInput(input);
  const token = input?.planToken;
  const expected = input?.expectedCount;
  if (
    !request ||
    typeof token !== "string" ||
    !/^v1:[0-9a-f]{64}$/.test(token) ||
    !Number.isInteger(expected) ||
    expected < 0 ||
    expected > MOVE_COPIES_MAX
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const result = await executeMove(await moveClient(), { ...request, planToken: token, expectedCount: expected });
  // Sem dados do usuário: só duração, contagens e a classe do resultado.
  console.info(
    JSON.stringify({
      scope: "acervo.move",
      step: "confirm",
      ms: Date.now() - startedAt,
      keys: request.keys.length,
      expected,
      outcome: result.ok ? "OK" : result.reason,
      updated: result.ok ? result.updated : null,
      clear: request.target === null,
    }),
  );
  if (result.ok || result.reason === "unknown" || result.reason === "plan_changed" || result.reason === "storage_gone") {
    // Sucesso ou incerteza: as leituras do acervo, de Meus locais e das coleções podem ter mudado.
    revalidatePath(ACERVO_PATH);
    revalidatePath(LOCAIS_PATH);
    revalidatePath(COLECOES_PATH, "layout");
  }
  return result;
}
