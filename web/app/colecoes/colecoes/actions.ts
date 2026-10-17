"use server";

import { revalidatePath } from "next/cache";
import { resolveCardSetForAdd } from "@/app/colecoes/acervo/actions";
import { ACERVO_PATH } from "@/lib/colecoes/acervo";
import { isUuid } from "@/lib/colecoes/acervo-add";
import { type BinderFinish, isBinderFinish } from "@/lib/colecoes/binder-finish";
import {
  COLECOES_PATH,
  type CollectionFailure,
  LINK_BATCH_SIZE,
  type LinkCandidate,
  type LinkChoice,
  type LinkOption,
  chunk,
  classifyCollectionFailure,
  collectionHref,
  findAlternatives,
  isCollectionId,
  isSetCode,
  normalizeCollectionName,
} from "@/lib/colecoes/colecoes";
import { createClient } from "@/lib/supabase/server";

/**
 * Minhas coleções — ações (MY-COLLECTIONS-FRONTEND-01).
 *
 * Só chamam contratos já implantados no LIVE, com a sessão do usuário
 * (cookies) — nunca `service_role`. Nenhuma regra de domínio é repetida aqui:
 * dono, local (D-A), Set, idempotência (CT-01) e exclusividade do vínculo
 * (5046, UNIQUE(physical_card_id)) são decididos pelo banco. Esta camada só
 * valida o formato, monta os parâmetros e traduz o resultado.
 *
 * Vincular uma carta a uma coleção é uma relação lógica: nenhuma carta muda
 * de lugar físico e nenhum local é atribuído a carta alguma (NS-13, C-26).
 */

type Fail = { ok: false; reason: CollectionFailure };

// ---------------------------------------------------------------------------
// Criar coleção a partir de um Set (CT-01)
// ---------------------------------------------------------------------------

export type CreateResult = {
  collectionId: string;
  href: string;
  storageCreated: boolean;
  replayed: boolean;
};

/**
 * A chave de idempotência vem do cliente, gerada uma vez por envio do
 * formulário e reaproveitada em toda nova tentativa do MESMO envio — clique
 * duplo, timeout ou rede devolvem a mesma coleção (`replayed`), nunca duas.
 */
export async function createCollectionFromSet(input: {
  idempotencyKey: string;
  setCode: string;
  name: string;
  storageContainerId: string | null;
}): Promise<({ ok: true } & CreateResult) | Fail> {
  const name = typeof input?.name === "string" ? normalizeCollectionName(input.name) : null;
  if (
    !isUuid(input?.idempotencyKey) ||
    !isSetCode(input.setCode) ||
    name === null ||
    (input.storageContainerId !== null && !isUuid(input.storageContainerId))
  ) {
    return { ok: false, reason: "invalid" };
  }

  const resolved = await resolveCardSetForAdd(input.setCode);
  if (!resolved.ok) return { ok: false, reason: resolved.reason === "set_empty" ? "set_empty" : "unavailable" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_my_card_set_collection", {
    p_idempotency_key: input.idempotencyKey,
    p_card_set_id: resolved.cardSetId,
    p_name: name,
    p_storage_container_id: input.storageContainerId,
  });
  const row = Array.isArray(data)
    ? (data[0] as { collection_id?: string; storage_container_created?: boolean; replayed?: boolean } | undefined)
    : undefined;
  if (error || !row || !isCollectionId(row.collection_id)) {
    return fail("create_my_card_set_collection", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  console.info(
    JSON.stringify({
      scope: "colecoes.create",
      ms: Date.now() - startedAt,
      outcome: row.replayed ? "REPLAY" : "CREATED",
      storageCreated: row.storage_container_created === true,
    }),
  );
  revalidatePath(COLECOES_PATH);
  return {
    ok: true,
    collectionId: row.collection_id,
    href: collectionHref(row.collection_id),
    storageCreated: row.storage_container_created === true,
    replayed: row.replayed === true,
  };
}

// ---------------------------------------------------------------------------
// Vincular "1 de cada" (D-C) — revisão
// ---------------------------------------------------------------------------

export type LinkReview = {
  /** Cartas diferentes que entram (uma de cada, R3). */
  total: number;
  /** Cartas com mais de uma opção no acervo (outra variante ou idioma). */
  choices: LinkChoice[];
};

type CandidateRow = {
  physical_card_id: string;
  card_id: string;
  collector_number: string;
  card_name: string;
  language_code: string | null;
  total_count: number | string;
};

type InventoryRow = {
  card_variant_id: string;
  language_code: string;
  language_name: string | null;
  collector_number: string;
  is_default_variant: boolean;
  variant_label: string | null;
  copies_count: number;
  image_path: string | null;
};

/**
 * Lê o que entraria (R3) e quais cartas têm alternativas no acervo — grupos
 * de variante/idioma ainda fora de coleção, do mesmo Set (5159 com
 * `p_without_collection`). Só leitura: nada é gravado aqui.
 */
export async function reviewLinkOneOfEach(input: {
  collectionId: string;
  setCode: string;
}): Promise<({ ok: true } & LinkReview) | Fail> {
  if (!isCollectionId(input?.collectionId) || !isSetCode(input.setCode)) return { ok: false, reason: "invalid" };
  const supabase = await createClient();

  const candidates = await readCandidates(supabase, input.collectionId);
  if (!candidates.ok) return candidates;
  if (candidates.items.length === 0) return { ok: true, total: 0, choices: [] };

  const groups = await readAvailableGroups(supabase, input.setCode);
  if (!groups.ok) return groups;

  return {
    ok: true,
    total: candidates.total,
    choices: findAlternatives(candidates.items, groups.items),
  };
}

// ---------------------------------------------------------------------------
// Vincular "1 de cada" — confirmação
// ---------------------------------------------------------------------------

export type LinkOverride = { cardId: string; collectorNumber: string; cardVariantId: string; languageCode: string };

/**
 * Vincula um exemplar de cada carta que ainda falta. Os candidatos são lidos
 * de novo no servidor (estado atual, não o da revisão) e as escolhas do
 * usuário só valem para cartas que continuam faltando. Lotes de até 500
 * (teto de 5046); a cada lote a leitura recomeça, então repetir o envio não
 * vincula duas vezes — o que já entrou deixa de ser candidato.
 *
 * Nunca "todas as repetidas": a primeira experiência é só "1 de cada" (D-C).
 */
export async function linkOneOfEach(input: {
  collectionId: string;
  overrides: LinkOverride[];
}): Promise<{ ok: true; linked: number } | { ok: false; reason: CollectionFailure; linked: number }> {
  if (
    !isCollectionId(input?.collectionId) ||
    !Array.isArray(input.overrides) ||
    input.overrides.length > LINK_BATCH_SIZE ||
    !input.overrides.every(
      (override) =>
        isUuid(override?.cardId) &&
        isUuid(override.cardVariantId) &&
        typeof override.languageCode === "string" &&
        /^[a-z]{2,3}(-[A-Z]{2})?$/.test(override.languageCode) &&
        typeof override.collectorNumber === "string",
    )
  ) {
    return { ok: false, reason: "invalid", linked: 0 };
  }

  const startedAt = Date.now();
  const supabase = await createClient();
  const overrides = new Map(input.overrides.map((override) => [override.cardId, override]));
  let linked = 0;

  // Cada volta lê o estado atual; o teto de voltas só protege contra laço infinito.
  for (let round = 0; round < 10; round += 1) {
    const candidates = await readCandidates(supabase, input.collectionId);
    if (!candidates.ok) return finish(candidates.reason);
    if (candidates.items.length === 0) break;

    const ids: string[] = [];
    for (const candidate of candidates.items) {
      const override = overrides.get(candidate.cardId);
      if (override && override.collectorNumber === candidate.collectorNumber) {
        const chosen = await pickFreeCopy(supabase, override);
        if (!chosen.ok) return finish(chosen.reason);
        // A escolha do usuário nunca é trocada em silêncio: sem exemplar livre
        // daquela opção, o acervo mudou desde a revisão — pede nova revisão.
        if (!chosen.physicalCardId) return finish("already_linked");
        ids.push(chosen.physicalCardId);
        overrides.delete(candidate.cardId);
      } else {
        ids.push(candidate.physicalCardId);
      }
    }

    for (const batch of chunk(ids, LINK_BATCH_SIZE)) {
      const { data, error } = await supabase.rpc("allocate_physical_cards_to_collection", {
        p_collection_id: input.collectionId,
        p_physical_card_ids: batch,
      });
      if (error || !Array.isArray(data)) {
        const failed = fail("allocate_physical_cards_to_collection", startedAt, error ?? { code: "BAD_SHAPE" });
        return finish(failed.reason);
      }
      linked += data.length;
    }
    if (candidates.items.length < LINK_BATCH_SIZE) break;
  }

  return finish(null);

  function finish(reason: CollectionFailure | null) {
    console.info(JSON.stringify({ scope: "colecoes.link", ms: Date.now() - startedAt, linked, outcome: reason ?? "OK" }));
    if (linked > 0) {
      revalidatePath(COLECOES_PATH, "layout");
      revalidatePath(ACERVO_PATH);
    }
    return reason ? { ok: false as const, reason, linked } : { ok: true as const, linked };
  }
}

// ---------------------------------------------------------------------------
// Renomear coleção (contrato existente 5035 `update_collection_metadata`)
// ---------------------------------------------------------------------------

/**
 * Troca só o nome. A 5035 grava nome E descrição juntos (descrição nula =
 * apagar), então a descrição atual é lida antes (RLS select-own) e reenviada
 * sem mudança; se essa leitura falhar, nada é gravado. Coleção alheia ou
 * arquivada é recusada pelo próprio banco. Repetir o envio é inofensivo
 * (mesmo resultado).
 */
export async function renameCollection(input: {
  collectionId: string;
  name: string;
}): Promise<{ ok: true; name: string } | Fail> {
  const name = typeof input?.name === "string" ? normalizeCollectionName(input.name) : null;
  if (!isCollectionId(input?.collectionId) || name === null) return { ok: false, reason: "invalid" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const current = await supabase.from("collection").select("description").eq("id", input.collectionId).maybeSingle();
  if (current.error) return fail("collection.description", startedAt, current.error);
  if (!current.data) return { ok: false, reason: "not_found" };

  const { data, error } = await supabase.rpc("update_collection_metadata", {
    p_collection_id: input.collectionId,
    p_name: name,
    p_description: (current.data as { description: string | null }).description,
  });
  const row = Array.isArray(data) ? (data[0] as { name?: string } | undefined) : undefined;
  if (error || !row?.name) return fail("update_collection_metadata", startedAt, error ?? { code: "BAD_SHAPE" });

  console.info(JSON.stringify({ scope: "colecoes.rename", ms: Date.now() - startedAt }));
  revalidatePath(COLECOES_PATH, "layout");
  return { ok: true, name: row.name };
}

// ---------------------------------------------------------------------------
// Cor do fichário (proposta 2026-10-17-collection-cover-finish — NÃO no LIVE)
// ---------------------------------------------------------------------------

/**
 * Grava o acabamento escolhido. Depende da RPC proposta
 * `set_my_collection_cover_finish` (5172). A interface só oferece o seletor
 * quando R1 já devolve `cover_finish` (sinal de que a proposta foi aplicada);
 * se mesmo assim a função não existir, o erro volta como "indisponível" e
 * nada muda.
 */
export async function setCollectionCoverFinish(input: {
  collectionId: string;
  finish: string;
}): Promise<{ ok: true; finish: BinderFinish } | Fail> {
  if (!isCollectionId(input?.collectionId) || !isBinderFinish(input.finish)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_collection_cover_finish", {
    p_collection_id: input.collectionId,
    p_finish: input.finish,
  });
  if (error || !isBinderFinish(data)) return fail("set_my_collection_cover_finish", startedAt, error ?? { code: "BAD_SHAPE" });
  revalidatePath(COLECOES_PATH, "layout");
  return { ok: true, finish: data };
}

// ---- internos ----

async function readCandidates(
  supabase: Awaited<ReturnType<typeof createClient>>,
  collectionId: string,
): Promise<{ ok: true; items: LinkCandidate[]; total: number } | Fail> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_collection_link_candidates", {
    p_collection_id: collectionId,
    p_limit: LINK_BATCH_SIZE,
  });
  if (error || !Array.isArray(data)) return fail("get_my_collection_link_candidates", startedAt, error ?? { code: "BAD_SHAPE" });
  const rows = data as CandidateRow[];
  return {
    ok: true,
    total: rows[0] ? Number(rows[0].total_count) : 0,
    items: rows.map((row) => ({
      physicalCardId: row.physical_card_id,
      cardId: row.card_id,
      collectorNumber: row.collector_number,
      cardName: row.card_name,
      languageCode: row.language_code,
    })),
  };
}

/** Grupos do acervo (variante + idioma) do Set, só exemplares sem coleção. Até 10 páginas de 96. */
async function readAvailableGroups(
  supabase: Awaited<ReturnType<typeof createClient>>,
  setCode: string,
): Promise<{ ok: true; items: (LinkOption & { collectorNumber: string })[] } | Fail> {
  const startedAt = Date.now();
  const items: (LinkOption & { collectorNumber: string })[] = [];
  const pageSize = 96;
  for (let page = 0; page < 10; page += 1) {
    const { data, error } = await supabase.rpc("get_my_inventory_items", {
      p_search: null,
      p_card_set_code: setCode,
      p_language_code: null,
      p_collection_id: null,
      p_without_collection: true,
      p_sort: "SET_NUMBER",
      p_limit: pageSize,
      p_offset: page * pageSize,
    });
    if (error || !Array.isArray(data)) return fail("get_my_inventory_items", startedAt, error ?? { code: "BAD_SHAPE" });
    for (const row of data as InventoryRow[]) {
      items.push({
        collectorNumber: row.collector_number,
        cardVariantId: row.card_variant_id,
        languageCode: row.language_code,
        languageName: row.language_name ?? row.language_code,
        variantLabel: row.variant_label,
        isDefaultVariant: row.is_default_variant,
        copies: Number(row.copies_count ?? 0),
        imagePath: row.image_path,
      });
    }
    if (data.length < pageSize) break;
  }
  return { ok: true, items };
}

/**
 * Um exemplar livre (sem coleção) do grupo escolhido, conferindo que o grupo
 * é a mesma carta (número de colecionador). Sem exemplar livre entre os
 * devolvidos → `null` (quem chama pede nova revisão).
 */
async function pickFreeCopy(
  supabase: Awaited<ReturnType<typeof createClient>>,
  override: LinkOverride,
): Promise<{ ok: true; physicalCardId: string | null } | Fail> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_inventory_item_copies", {
    p_card_variant_id: override.cardVariantId,
    p_language_code: override.languageCode,
  });
  if (error || !Array.isArray(data)) return fail("get_my_inventory_item_copies", startedAt, error ?? { code: "BAD_SHAPE" });
  const rows = data as { physical_card_id: string; collector_number: string; collection_name: string | null }[];
  const free = rows.find((row) => row.collector_number === override.collectorNumber && row.collection_name === null);
  return { ok: true, physicalCardId: free?.physical_card_id ?? null };
}

function fail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): Fail {
  const reason = classifyCollectionFailure(error?.code, error?.message);
  // Sem dados do usuário: só função, duração, código e a classe do erro.
  console.error(JSON.stringify({ scope: "colecoes.write", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}
