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
  type LinkItem,
  linkItems,
  isCollectionId,
  isSetCode,
  normalizeCollectionName,
  type StorageOption,
} from "@/lib/colecoes/colecoes";
import { COLLECTION_MANAGE_ENABLED, type CopyGroup, copiesInCollection, sameCollectorNumber } from "@/lib/colecoes/collection-manage";
import { getMyPokedexPositions, getMyStorageLocations, getPokedexGenerationOptions } from "@/lib/colecoes/colecoes-queries";
import { getAcervoFilterOptions, getAcervoItems } from "@/lib/colecoes/acervo-queries";
import {
  FREE_COVER_CODE_ENABLED,
  FREE_COVER_UPLOAD_ENABLED,
  FREE_SELECTION_MAX,
  type GroupCopy,
  isCoverCode,
  isCoverPath,
  normalizeCoverCode,
  PICKER_PAGE_SIZE,
  type PickerGroup,
  normalizeCopyIds,
} from "@/lib/colecoes/free-collection";
import { LIBRARY_REORDER_ENABLED } from "@/lib/colecoes/library-order";
import {
  type CompletionObjective,
  MASTER_SET_ADD_FROM_ACERVO_ENABLED,
  MASTER_SET_LINK_BATCH_SIZE,
  MASTER_SET_OBJECTIVE_ENABLED,
  MAX_FINISHES,
  type MasterSetLinkCandidate,
  isPositionKey,
  parseMasterSetLinkCandidates,
  pickLinkCopies,
  OUT_OF_SCOPE_PAGE_SIZE,
  type OutOfScopePage,
  POSITION_COPIES_LIMIT,
  type PositionCopy,
  parseOutOfScope,
  parsePositionCopies,
  type ObjectiveFailure,
  type ObjectivePreview,
  type ObjectiveState,
  classifyObjectiveFailure,
  isCompletionObjective,
  initialSelection,
  isFinishId,
  parseObjectiveOptions,
  parsePreview,
} from "@/lib/colecoes/master-set";
import {
  type GenerationOption,
  MAX_GENERATIONS,
  POKEDEX_COLLECTION_ENABLED,
  type PokedexFailure,
  type PokedexFilter,
  type PokedexPositionsPage,
  classifyPokedexFailure,
} from "@/lib/colecoes/pokedex";
import {
  type BulkPreviewItem,
  LINK_CANDIDATES_PAGE_SIZE,
  LINK_QUERY_MAX,
  type LinkFailure,
  type LinkScope,
  type PokedexLinkCandidate,
  type PokedexPositionCopy,
  classifyLinkFailure,
  normalizeBulkIds,
  parseBulkPreview,
  parsePokedexLinkCandidates,
  parsePokedexPositionCopies,
} from "@/lib/colecoes/pokedex-link";
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
// Criar Coleção livre (CT-01 estendido, Query 5175 — LIVE)
// ---------------------------------------------------------------------------

/**
 * Coleção livre: curadoria aberta, sem Set e sem progresso (C-20). Mesmas
 * garantias de `createCollectionFromSet` (transação única, idempotência,
 * D-A), decididas pelo banco em `create_my_free_collection` (Query 5175, no
 * LIVE desde 2026-10-17, validada por 5832 v1.1 25/25). Única porta de criação
 * da Coleção livre.
 *
 * Código opcional (5179/5180, atrás de `FREE_COVER_CODE_ENABLED`): gravado
 * logo depois da criação, por `set_my_collection_cover_code` — idempotente,
 * então um novo envio do mesmo pedido reaproveita a coleção (5175) e regrava
 * o mesmo código. Se só o código falhar, a coleção existe e o resultado traz
 * `codeSaved: false` para a interface avisar; o código pode ser definido
 * depois, na página da coleção.
 */
export async function createFreeCollection(input: {
  idempotencyKey: string;
  name: string;
  storageContainerId: string | null;
  coverCode?: string | null;
}): Promise<({ ok: true; codeSaved: boolean } & CreateResult) | Fail> {
  const name = typeof input?.name === "string" ? normalizeCollectionName(input.name) : null;
  const coverCode = FREE_COVER_CODE_ENABLED ? normalizeCoverCode(input?.coverCode) : null;
  if (
    !isUuid(input?.idempotencyKey) ||
    name === null ||
    coverCode === "invalid" ||
    (input.storageContainerId !== null && !isUuid(input.storageContainerId))
  ) {
    return { ok: false, reason: "invalid" };
  }

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_my_free_collection", {
    p_idempotency_key: input.idempotencyKey,
    p_name: name,
    p_storage_container_id: input.storageContainerId,
  });
  const row = Array.isArray(data)
    ? (data[0] as { collection_id?: string; storage_container_created?: boolean; replayed?: boolean } | undefined)
    : undefined;
  if (error || !row || !isCollectionId(row.collection_id)) {
    return fail("create_my_free_collection", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  console.info(
    JSON.stringify({
      scope: "colecoes.create",
      kind: "free",
      ms: Date.now() - startedAt,
      outcome: row.replayed ? "REPLAY" : "CREATED",
      storageCreated: row.storage_container_created === true,
    }),
  );
  let codeSaved = true;
  if (coverCode) {
    const saved = await writeCoverCode(supabase, row.collection_id, coverCode);
    codeSaved = saved.ok;
  }
  revalidatePath(COLECOES_PATH);
  return {
    ok: true,
    collectionId: row.collection_id,
    href: collectionHref(row.collection_id),
    storageCreated: row.storage_container_created === true,
    replayed: row.replayed === true,
    codeSaved,
  };
}

// ---------------------------------------------------------------------------
// Vincular "1 de cada" (D-C) — revisão
// ---------------------------------------------------------------------------

export type LinkReview = {
  /** Cartas diferentes que podem entrar (uma de cada, R3). */
  total: number;
  /** As cartas da escolha (até 500 por vez), com arte — o colecionador marca quais entram. */
  items: LinkItem[];
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
  if (candidates.items.length === 0) return { ok: true, total: 0, items: [], choices: [] };

  const groups = await readAvailableGroups(supabase, input.setCode);
  if (!groups.ok) return groups;

  return {
    ok: true,
    total: candidates.total,
    items: linkItems(candidates.items, groups.items),
    choices: findAlternatives(candidates.items, groups.items),
  };
}

// ---------------------------------------------------------------------------
// Vincular "1 de cada" — confirmação
// ---------------------------------------------------------------------------

export type LinkOverride = { cardId: string; collectorNumber: string; cardVariantId: string; languageCode: string };

/**
 * Vincula um exemplar de cada carta ESCOLHIDA (`cardIds`) que ainda falta. Os
 * candidatos são lidos de novo no servidor (estado atual, não o da revisão):
 * só entram os que continuam faltando E foram marcados pelo colecionador; as
 * escolhas de versão só valem para essas cartas. Lotes de até 500
 * (teto de 5046); a cada lote a leitura recomeça, então repetir o envio não
 * vincula duas vezes — o que já entrou deixa de ser candidato.
 *
 * Nunca "todas as repetidas": a primeira experiência é só "1 de cada" (D-C).
 */
export async function linkOneOfEach(input: {
  collectionId: string;
  cardIds: string[];
  overrides: LinkOverride[];
}): Promise<{ ok: true; linked: number } | { ok: false; reason: CollectionFailure; linked: number }> {
  if (
    !isCollectionId(input?.collectionId) ||
    !Array.isArray(input.cardIds) ||
    input.cardIds.length === 0 ||
    input.cardIds.length > LINK_BATCH_SIZE ||
    !input.cardIds.every((id) => isUuid(id)) ||
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
  const wanted = new Set(input.cardIds);
  let linked = 0;

  // Cada volta lê o estado atual; o teto de voltas só protege contra laço infinito.
  for (let round = 0; round < 10; round += 1) {
    const candidates = await readCandidates(supabase, input.collectionId);
    if (!candidates.ok) return finish(candidates.reason);
    // Só as cartas marcadas; as demais continuam fora (e no acervo).
    const chosen = candidates.items.filter((candidate) => wanted.has(candidate.cardId));
    if (chosen.length === 0) break;

    const ids: string[] = [];
    for (const candidate of chosen) {
      const override = overrides.get(candidate.cardId);
      if (override && override.collectorNumber === candidate.collectorNumber) {
        const chosenCopy = await pickFreeCopy(supabase, override);
        if (!chosenCopy.ok) return finish(chosenCopy.reason);
        // A escolha do usuário nunca é trocada em silêncio: sem exemplar livre
        // daquela opção, o acervo mudou desde a revisão — pede nova revisão.
        if (!chosenCopy.physicalCardId) return finish("already_linked");
        ids.push(chosenCopy.physicalCardId);
        overrides.delete(candidate.cardId);
      } else {
        ids.push(candidate.physicalCardId);
      }
      wanted.delete(candidate.cardId);
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
    if (candidates.items.length < LINK_BATCH_SIZE || wanted.size === 0) break;
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
// Coleção livre — "Adicionar cartas do meu acervo" (5159 + 5162 + 5046)
// ---------------------------------------------------------------------------

export type PickerPage = {
  groups: PickerGroup[];
  totalGroups: number;
  /** Sets do acervo para o filtro — só na primeira página, quando pedido. */
  sets: { value: string; label: string }[] | null;
};

const PICKER_SET_CODE = /^[A-Za-z0-9.-]{1,32}$/;

/**
 * Cartas do próprio acervo para escolher (5159). "Só disponíveis" lista os
 * grupos com exemplares fora de qualquer coleção (`p_without_collection`) e
 * conta só esses exemplares; senão, o acervo inteiro — para o colecionador
 * ver onde estão as cartas que não podem entrar. Só leitura.
 */
export async function browseAcervoForCollection(input: {
  collectionId: string;
  query: string;
  setCode: string | null;
  availableOnly: boolean;
  page: number;
  withSets: boolean;
}): Promise<({ ok: true } & PickerPage) | Fail> {
  const query = typeof input?.query === "string" ? input.query.trim().slice(0, 100) : "";
  if (
    !isCollectionId(input?.collectionId) ||
    (input.setCode !== null && !PICKER_SET_CODE.test(String(input.setCode))) ||
    typeof input.availableOnly !== "boolean" ||
    !Number.isInteger(input.page) ||
    input.page < 1 ||
    input.page > 2000
  ) {
    return { ok: false, reason: "invalid" };
  }
  const supabase = await createClient();
  const [items, options] = await Promise.all([
    getAcervoItems(supabase, {
      query: query === "" ? null : query,
      setCode: input.setCode,
      languageCode: null,
      collection: input.availableOnly ? { kind: "none" } : { kind: "all" },
      sort: "recentes",
      page: input.page,
      detail: null,
    }),
    input.withSets && input.page === 1 ? getAcervoFilterOptions(supabase) : Promise.resolve(null),
  ]);
  if (items === null) return { ok: false, reason: "unavailable" };
  return {
    ok: true,
    totalGroups: items.totalGroups,
    groups: items.items.slice(0, PICKER_PAGE_SIZE).map((item) => ({
      cardVariantId: item.cardVariantId,
      languageCode: item.languageCode,
      languageName: item.languageName,
      cardName: item.cardName,
      collectorNumber: item.collectorNumber,
      collectorTotal: item.collectorTotal,
      cardSetCode: item.cardSetCode,
      cardSetName: item.cardSetName,
      isDefaultVariant: item.isDefaultVariant,
      variantLabel: item.variantLabel,
      imagePath: item.imagePath,
      copies: item.copiesCount,
    })),
    sets: options ? options.sets.map((option) => ({ value: option.value, label: option.label })) : null,
  };
}

const LANGUAGE_CODE = /^[a-z]{2,3}(-[A-Z]{2})?$/;

/**
 * Exemplares de uma carta do acervo (5162), cada um com a coleção em que está
 * (ou nenhuma). Grupo alheio ou inexistente → lista vazia (o banco não
 * distingue). Só leitura.
 */
export async function readGroupCopies(input: {
  cardVariantId: string;
  languageCode: string;
}): Promise<{ ok: true; copies: GroupCopy[] } | Fail> {
  if (!isUuid(input?.cardVariantId) || typeof input.languageCode !== "string" || !LANGUAGE_CODE.test(input.languageCode)) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_inventory_item_copies", {
    p_card_variant_id: input.cardVariantId,
    p_language_code: input.languageCode,
  });
  if (error || !Array.isArray(data)) return fail("get_my_inventory_item_copies", startedAt, error ?? { code: "BAD_SHAPE" });
  const rows = data as {
    physical_card_id: string;
    copy_number: number;
    added_at: string;
    storage_name: string | null;
    collection_id: string | null;
    collection_name: string | null;
  }[];
  return {
    ok: true,
    copies: rows.map((row) => ({
      physicalCardId: row.physical_card_id,
      copyNumber: Number(row.copy_number),
      addedAt: row.added_at,
      storageName: row.storage_name,
      collectionId: row.collection_id ?? null,
      collectionName: row.collection_name ?? null,
    })),
  };
}

/**
 * "Selecionar todas": as cartas disponíveis (fora de qualquer coleção) que
 * atendem à busca/Set atuais, com os exemplares de cada uma — para a interface
 * marcar tudo de uma vez. Só leitura (5159 com `p_without_collection` + 5162
 * por carta, até 6 em paralelo). Para no teto da seleção (500 exemplares):
 * `truncated` avisa que existe mais. Nada é vinculado aqui.
 */
export async function collectAvailableCopies(input: {
  query: string;
  setCode: string | null;
}): Promise<({ ok: true; entries: { group: PickerGroup; copies: GroupCopy[] }[]; truncated: boolean }) | Fail> {
  const query = typeof input?.query === "string" ? input.query.trim().slice(0, 100) : "";
  if (input?.setCode !== null && !PICKER_SET_CODE.test(String(input?.setCode))) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();

  const groups: PickerGroup[] = [];
  let freeCopies = 0;
  let truncated = false;
  for (let page = 1; page <= 20; page += 1) {
    const items = await getAcervoItems(supabase, {
      query: query === "" ? null : query,
      setCode: input.setCode,
      languageCode: null,
      collection: { kind: "none" },
      sort: "recentes",
      page,
      detail: null,
    });
    if (items === null) return { ok: false, reason: "unavailable" };
    for (const item of items.items) {
      if (freeCopies >= FREE_SELECTION_MAX) {
        truncated = true;
        break;
      }
      groups.push({
        cardVariantId: item.cardVariantId,
        languageCode: item.languageCode,
        languageName: item.languageName,
        cardName: item.cardName,
        collectorNumber: item.collectorNumber,
        collectorTotal: item.collectorTotal,
        cardSetCode: item.cardSetCode,
        cardSetName: item.cardSetName,
        isDefaultVariant: item.isDefaultVariant,
        variantLabel: item.variantLabel,
        imagePath: item.imagePath,
        copies: item.copiesCount,
      });
      freeCopies += item.copiesCount;
    }
    if (truncated || page * PICKER_PAGE_SIZE >= items.totalGroups) {
      if (!truncated && freeCopies > FREE_SELECTION_MAX) truncated = true;
      break;
    }
  }
  if (freeCopies > FREE_SELECTION_MAX) truncated = true;

  const entries: { group: PickerGroup; copies: GroupCopy[] }[] = [];
  const concurrency = 6;
  for (let index = 0; index < groups.length; index += concurrency) {
    const slice = groups.slice(index, index + concurrency);
    const results = await Promise.all(
      slice.map((group) => readGroupCopies({ cardVariantId: group.cardVariantId, languageCode: group.languageCode })),
    );
    for (let j = 0; j < slice.length; j += 1) {
      const result = results[j];
      const group = slice[j];
      if (!result || !group) continue;
      if (!result.ok) return result;
      entries.push({ group, copies: result.copies });
    }
  }
  console.info(JSON.stringify({ scope: "colecoes.collect_free", ms: Date.now() - startedAt, groups: entries.length, truncated }));
  return { ok: true, entries, truncated };
}

/**
 * Vincula os exemplares escolhidos e revisados a uma Coleção livre — UMA
 * chamada a 5046 (até 500): ou todos entram, ou nenhum. Exemplar que já está
 * em qualquer coleção faz o banco recusar o pedido inteiro, sem mover nada
 * (`already_linked`); a interface relê e pede nova revisão. Nenhuma carta muda
 * de lugar físico e nenhuma coleção ganha Set ou progresso.
 */
export async function linkCopiesToCollection(input: {
  collectionId: string;
  physicalCardIds: string[];
}): Promise<{ ok: true; linked: number } | Fail> {
  const ids = normalizeCopyIds(input?.physicalCardIds, FREE_SELECTION_MAX);
  if (!isCollectionId(input?.collectionId) || ids === null) return { ok: false, reason: "invalid" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("allocate_physical_cards_to_collection", {
    p_collection_id: input.collectionId,
    p_physical_card_ids: ids,
  });
  if (error || !Array.isArray(data)) return fail("allocate_physical_cards_to_collection", startedAt, error ?? { code: "BAD_SHAPE" });

  console.info(JSON.stringify({ scope: "colecoes.link_free", ms: Date.now() - startedAt, requested: ids.length, linked: data.length }));
  revalidatePath(COLECOES_PATH, "layout");
  revalidatePath(ACERVO_PATH);
  return { ok: true, linked: data.length };
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

// ---------------------------------------------------------------------------
// Capa enviada da Coleção livre (proposta 5176–5178 — NÃO no LIVE)
// ---------------------------------------------------------------------------

/**
 * Aponta a placa da Coleção livre para um arquivo já enviado pelo próprio
 * colecionador ao bucket privado `collection-cover` (ou remove, com `null`).
 * Dono, pasta, existência do arquivo e "só Coleção livre" são conferidos por
 * `set_my_collection_cover_logo` (5178). Devolve o caminho anterior para o
 * cliente apagar o arquivo antigo só depois da troca gravada.
 * Controlada por `FREE_COVER_UPLOAD_ENABLED` (5176–5178 no LIVE desde 2026-10-18).
 */
export async function setCollectionCoverLogo(input: {
  collectionId: string;
  path: string | null;
}): Promise<{ ok: true; path: string | null; previousPath: string | null } | Fail> {
  if (!FREE_COVER_UPLOAD_ENABLED) return { ok: false, reason: "unavailable" };
  if (!isCollectionId(input?.collectionId) || (input.path !== null && !isCoverPath(input.path))) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_collection_cover_logo", {
    p_collection_id: input.collectionId,
    p_path: input.path,
  });
  const row = Array.isArray(data) ? (data[0] as { cover_logo_path?: string | null; previous_path?: string | null } | undefined) : undefined;
  if (error || !row) return fail("set_my_collection_cover_logo", startedAt, error ?? { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.cover_logo", ms: Date.now() - startedAt, cleared: input.path === null }));
  revalidatePath(COLECOES_PATH, "layout");
  return {
    ok: true,
    path: row.cover_logo_path ?? null,
    previousPath: isCoverPath(row.previous_path) ? row.previous_path : null,
  };
}

// ---------------------------------------------------------------------------
// Código opcional da Coleção livre (5179–5180 no LIVE desde 2026-10-18)
// ---------------------------------------------------------------------------

/**
 * Define (ou remove, com vazio/`null`) o Código da Coleção livre. Formato,
 * dono e "só Coleção livre" são conferidos por `set_my_collection_cover_code`
 * (5180). Controlada por `FREE_COVER_CODE_ENABLED`.
 */
export async function setCollectionCoverCode(input: {
  collectionId: string;
  code: string | null;
}): Promise<{ ok: true; code: string | null } | Fail> {
  if (!FREE_COVER_CODE_ENABLED) return { ok: false, reason: "unavailable" };
  const code = normalizeCoverCode(input?.code);
  if (!isCollectionId(input?.collectionId) || code === "invalid") return { ok: false, reason: "invalid" };
  const supabase = await createClient();
  const saved = await writeCoverCode(supabase, input.collectionId, code);
  if (!saved.ok) return saved;
  revalidatePath(COLECOES_PATH, "layout");
  return saved;
}

// ---------------------------------------------------------------------------
// Ordem da Biblioteca (5181–5183 no LIVE desde 2026-10-18)
// ---------------------------------------------------------------------------

/**
 * Grava a nova posição de UMA coleção, ancorada na vizinha: "depois de"
 * (`afterId`) ou, na primeira posição de uma página, "antes de" (`beforeId`).
 * `move_my_collection` (5183) confere dono, renumera a Biblioteca e é
 * idempotente — repetir o mesmo movimento não muda nada. Controlada por
 * `LIBRARY_REORDER_ENABLED`.
 */
export async function moveCollectionInLibrary(input: {
  collectionId: string;
  afterId: string | null;
  beforeId: string | null;
}): Promise<{ ok: true; position: number } | Fail> {
  if (!LIBRARY_REORDER_ENABLED) return { ok: false, reason: "unavailable" };
  const afterId = input?.afterId ?? null;
  const beforeId = input?.beforeId ?? null;
  if (
    !isCollectionId(input?.collectionId) ||
    (afterId === null) === (beforeId === null) ||
    (afterId !== null && !isCollectionId(afterId)) ||
    (beforeId !== null && !isCollectionId(beforeId)) ||
    afterId === input.collectionId ||
    beforeId === input.collectionId
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("move_my_collection", {
    p_collection_id: input.collectionId,
    p_after_collection_id: afterId,
    p_before_collection_id: beforeId,
  });
  if (error || typeof data !== "number") return fail("move_my_collection", startedAt, error ?? { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.library_order", ms: Date.now() - startedAt, position: data }));
  revalidatePath(COLECOES_PATH);
  return { ok: true, position: data };
}

// ---------------------------------------------------------------------------
// Gerenciar a coleção (COLLECTION-MANAGEMENT-RECOVERY-01) — contratos no LIVE
// ---------------------------------------------------------------------------

export type CardCopiesQuery =
  | { kind: "group"; collectionId: string; cardVariantId: string; languageCode: string }
  | { kind: "set_card"; collectionId: string; setCode: string; collectorNumber: string };

const COLLECTOR_NUMBER = /^[A-Za-z0-9-]{1,20}$/;

/**
 * Os exemplares de UMA carta que estão nesta coleção, agrupados por versão +
 * idioma. Só leitura: 5162 (exemplares do grupo, cada um com sua coleção) e —
 * numa coleção de Set, onde a grade mostra a carta e não a versão — 5159 com
 * `p_collection_id` para achar as versões dessa carta na coleção. Exemplares
 * livres ou de outra coleção são descartados aqui e nunca viram retiráveis.
 */
export async function readCardCopiesInCollection(input: CardCopiesQuery): Promise<{ ok: true; groups: CopyGroup[] } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();

  let targets: { cardVariantId: string; languageCode: string; collectorNumber: string | null }[];
  if (input.kind === "group") {
    if (!isUuid(input.cardVariantId) || typeof input.languageCode !== "string" || !LANGUAGE_CODE.test(input.languageCode)) {
      return { ok: false, reason: "invalid" };
    }
    targets = [{ cardVariantId: input.cardVariantId, languageCode: input.languageCode, collectorNumber: null }];
  } else if (input.kind === "set_card") {
    if (!isSetCode(input.setCode) || typeof input.collectorNumber !== "string" || !COLLECTOR_NUMBER.test(input.collectorNumber)) {
      return { ok: false, reason: "invalid" };
    }
    const { data, error } = await supabase.rpc("get_my_inventory_items", {
      p_search: input.collectorNumber,
      p_card_set_code: input.setCode,
      p_language_code: null,
      p_collection_id: input.collectionId,
      p_without_collection: false,
      p_sort: "SET_NUMBER",
      p_limit: 96,
      p_offset: 0,
    });
    if (error || !Array.isArray(data)) return fail("get_my_inventory_items", startedAt, error ?? { code: "BAD_SHAPE" });
    targets = (data as InventoryRow[])
      .filter((row) => sameCollectorNumber(row.collector_number, input.collectorNumber))
      .map((row) => ({ cardVariantId: row.card_variant_id, languageCode: row.language_code, collectorNumber: row.collector_number }));
  } else {
    return { ok: false, reason: "invalid" };
  }

  const results = await Promise.all(
    targets.slice(0, 24).map((target) =>
      supabase.rpc("get_my_inventory_item_copies", { p_card_variant_id: target.cardVariantId, p_language_code: target.languageCode }),
    ),
  );
  const groups: CopyGroup[] = [];
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index];
    const target = targets[index];
    if (!result || !target) continue;
    if (result.error || !Array.isArray(result.data)) {
      return fail("get_my_inventory_item_copies", startedAt, result.error ?? { code: "BAD_SHAPE" });
    }
    const rows = (result.data as CopyDetailRow[]).filter(
      (row) => target.collectorNumber === null || sameCollectorNumber(row.collector_number, target.collectorNumber),
    );
    const first = rows[0];
    if (!first) continue;
    const copies = copiesInCollection(
      rows.map((row) => ({
        physicalCardId: row.physical_card_id,
        copyNumber: Number(row.copy_number),
        addedAt: row.added_at,
        storageName: row.storage_name,
        collectionId: row.collection_id ?? null,
      })),
      input.collectionId,
    );
    if (copies.length === 0) continue;
    groups.push({
      cardVariantId: target.cardVariantId,
      languageCode: target.languageCode,
      languageName: first.language_name ?? target.languageCode,
      variantLabel: first.variant_label,
      isDefaultVariant: first.is_default_variant === true,
      copies,
    });
  }
  console.info(JSON.stringify({ scope: "colecoes.manage_read", ms: Date.now() - startedAt, kind: input.kind, groups: groups.length }));
  return { ok: true, groups };
}

/**
 * Tira UM exemplar desta coleção (N14) — `5047`, com um único id. O banco
 * confere dono, coleção ativa e que o exemplar está NESTA coleção (senão não
 * remove nada). Só o vínculo some: a carta continua no acervo, o registro
 * físico e o local ficam como estão, e nenhuma outra coleção muda.
 */
export async function unlinkCopyFromCollection(input: {
  collectionId: string;
  physicalCardId: string;
}): Promise<{ ok: true } | Fail> {
  if (!COLLECTION_MANAGE_ENABLED) return { ok: false, reason: "unavailable" };
  if (!isCollectionId(input?.collectionId) || !isUuid(input.physicalCardId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("deallocate_physical_cards_from_collection", {
    p_collection_id: input.collectionId,
    p_physical_card_ids: [input.physicalCardId],
  });
  if (error || !Array.isArray(data) || data.length !== 1) {
    return fail("deallocate_physical_cards_from_collection", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  console.info(JSON.stringify({ scope: "colecoes.unlink", ms: Date.now() - startedAt, removed: data.length }));
  revalidatePath(COLECOES_PATH, "layout");
  revalidatePath(ACERVO_PATH);
  return { ok: true };
}

/**
 * Ajustes → Onde guardo: o local padrão atual da coleção (RLS select-own) e os
 * locais do próprio acervo. Só leitura.
 */
export async function readCollectionStorage(input: {
  collectionId: string;
}): Promise<{ ok: true; storageId: string | null; locations: StorageOption[] } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const [current, locations] = await Promise.all([
    supabase.from("collection").select("default_storage_container_id").eq("id", input.collectionId).maybeSingle(),
    getMyStorageLocations(supabase),
  ]);
  if (current.error) return fail("collection.default_storage", startedAt, current.error);
  if (!current.data) return { ok: false, reason: "not_found" };
  if (locations === null) return { ok: false, reason: "unavailable" };
  const storageId = (current.data as { default_storage_container_id: string | null }).default_storage_container_id;
  return { ok: true, storageId: isUuid(storageId) ? storageId : null, locations };
}

/**
 * Troca o local padrão da COLEÇÃO — `5036`. Dono, coleção ativa e local do
 * próprio acervo são conferidos pelo banco. Nenhum exemplar muda de lugar:
 * o local de cada carta continua o que era (NS-13).
 */
export async function setCollectionStorage(input: {
  collectionId: string;
  storageContainerId: string;
}): Promise<{ ok: true; storageId: string } | Fail> {
  if (!COLLECTION_MANAGE_ENABLED) return { ok: false, reason: "unavailable" };
  if (!isCollectionId(input?.collectionId) || !isUuid(input.storageContainerId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_collection_default_storage", {
    p_collection_id: input.collectionId,
    p_storage_container_id: input.storageContainerId,
  });
  const row = Array.isArray(data) ? (data[0] as { default_storage_container_id?: string } | undefined) : undefined;
  if (error || !row || !isUuid(row.default_storage_container_id)) {
    return fail("set_collection_default_storage", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  console.info(JSON.stringify({ scope: "colecoes.default_storage", ms: Date.now() - startedAt }));
  revalidatePath(COLECOES_PATH, "layout");
  return { ok: true, storageId: row.default_storage_container_id };
}

// ---------------------------------------------------------------------------
// Ajustes → Objetivo: Set padrão ↔ Master Set (MASTER-SET-FRONTEND-PHASE-01)
// ---------------------------------------------------------------------------

type ObjectiveFail = { ok: false; reason: ObjectiveFailure };

/**
 * Política atual (RLS select-own em `collection`) e as opções de acabamento
 * do Set (5191) com as contagens do banco. Só leitura. Coleção alheia ou
 * inexistente → `not_found` (o banco não distingue).
 */
export async function readCollectionObjective(input: {
  collectionId: string;
}): Promise<({ ok: true } & ObjectiveState) | ObjectiveFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const [current, options] = await Promise.all([
    supabase.from("collection").select("completion_policy").eq("id", input.collectionId).maybeSingle(),
    supabase.rpc("get_my_master_set_finish_options", { p_collection_id: input.collectionId }),
  ]);
  if (current.error) return objectiveFail("collection.completion_policy", startedAt, current.error);
  const policy = (current.data as { completion_policy?: unknown } | null)?.completion_policy;
  if (!isCompletionObjective(policy)) return { ok: false, reason: "not_found" };
  if (options.error || !Array.isArray(options.data)) {
    return objectiveFail("get_my_master_set_finish_options", startedAt, options.error ?? { code: "BAD_SHAPE" });
  }
  const parsed = parseObjectiveOptions(options.data);
  console.info(JSON.stringify({ scope: "colecoes.objective_read", ms: Date.now() - startedAt, finishes: parsed.finishes.length }));
  return { ok: true, policy, ...parsed };
}

/**
 * Prévia obrigatória antes de confirmar (5192, STABLE — não grava nada). Mesma
 * validação da gravação: o que a prévia aceita, 5194/5195 gravam igual.
 */
export async function previewCollectionObjective(input: {
  collectionId: string;
  finishIds: string[];
}): Promise<{ ok: true; preview: ObjectivePreview } | ObjectiveFail> {
  const ids = normalizeFinishIds(input?.finishIds);
  if (!isCollectionId(input?.collectionId) || ids === null) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_my_master_set_finishes", {
    p_collection_id: input.collectionId,
    p_variant_type_ids: ids,
  });
  const preview = Array.isArray(data) ? parsePreview(data[0]) : null;
  if (error || !preview) return objectiveFail("preview_my_master_set_finishes", startedAt, error ?? { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.objective_preview", ms: Date.now() - startedAt, finishes: ids.length }));
  return { ok: true, preview };
}

export type ObjectiveChange =
  | { kind: "to_standard" }
  | { kind: "activate"; finishIds: string[] | null }
  | { kind: "replace"; finishIds: string[] };

/**
 * Grava a mudança de objetivo — UMA chamada:
 * - `to_standard` → 5081 (acabamentos ficam guardados para restaurar);
 * - `activate` → 5194 (lista, ou NULL para restaurar a seleção guardada);
 * - `replace` → 5195 (edição em Master Set; mesmo conjunto = zero escrita).
 * Todas são idempotentes, conferem dono e coleção ativa no banco e nunca
 * tocam exemplares, vínculos, locais ou fichário. Controlada por
 * `MASTER_SET_OBJECTIVE_ENABLED`.
 */
export async function saveCollectionObjective(input: {
  collectionId: string;
  change: ObjectiveChange;
}): Promise<{ ok: true; policy: CompletionObjective; total: number | null; satisfied: number | null } | ObjectiveFail> {
  if (!MASTER_SET_OBJECTIVE_ENABLED) return { ok: false, reason: "disabled" };
  const change = input?.change;
  if (!isCollectionId(input?.collectionId) || !change) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();

  if (change.kind === "to_standard") {
    const { data, error } = await supabase.rpc("set_collection_completion_policy_to_standard_set", {
      p_collection_id: input.collectionId,
    });
    const row = Array.isArray(data) ? (data[0] as { completion_policy?: unknown } | undefined) : undefined;
    if (error || row?.completion_policy !== "STANDARD_SET") {
      return objectiveFail("set_collection_completion_policy_to_standard_set", startedAt, error ?? { code: "BAD_SHAPE" });
    }
    return objectiveSaved("to_standard", startedAt, { policy: "STANDARD_SET", total: null, satisfied: null });
  }

  if (change.kind === "activate" || change.kind === "replace") {
    // `activate` com `null` = restaurar a seleção guardada; qualquer lista é validada.
    let ids: string[] | null = null;
    if (change.kind === "replace" || change.finishIds !== null) {
      ids = normalizeFinishIds(change.finishIds);
      if (ids === null) return { ok: false, reason: "invalid" };
    }
    const fn = change.kind === "activate" ? "set_collection_completion_policy_to_master_set" : "replace_master_set_finishes";
    const { data, error } = await supabase.rpc(fn, { p_collection_id: input.collectionId, p_variant_type_ids: ids });
    const row = Array.isArray(data)
      ? (data[0] as { total_positions?: unknown; satisfied_positions?: unknown } | undefined)
      : undefined;
    if (error || !row) return objectiveFail(fn, startedAt, error ?? { code: "BAD_SHAPE" });
    return objectiveSaved(change.kind, startedAt, {
      policy: "MASTER_SET",
      total: Number(row.total_positions ?? 0),
      satisfied: Number(row.satisfied_positions ?? 0),
    });
  }

  return { ok: false, reason: "invalid" };
}

/**
 * Criar já como Master Set (MASTER-SET-CREATE-01): logo depois de
 * `createCollectionFromSet`, ativa o objetivo com a seleção inicial da
 * interface — Padrão + Holográfica + Holográfica Reversa entre as que existem
 * no Set (`initialSelection`, a mesma de Ajustes). Lê as opções do Set (5191) e
 * grava com 5194 — os dois contratos já no LIVE, sem migration nova.
 *
 * Não é atômico com a criação: se esta etapa falhar, a coleção fica em Set
 * padrão (estado válido) e a interface oferece repetir só a ativação. 5194 é
 * idempotente (repetir a mesma lista nunca duplica nem falha).
 */
export async function activateMasterSetOnCreate(input: {
  collectionId: string;
}): Promise<{ ok: true; total: number; finishes: number } | ObjectiveFail> {
  if (!MASTER_SET_OBJECTIVE_ENABLED) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const options = await supabase.rpc("get_my_master_set_finish_options", { p_collection_id: input.collectionId });
  if (options.error || !Array.isArray(options.data)) {
    return objectiveFail("get_my_master_set_finish_options", startedAt, options.error ?? { code: "BAD_SHAPE" });
  }
  const ids = normalizeFinishIds(initialSelection(parseObjectiveOptions(options.data).finishes));
  if (ids === null) return { ok: false, reason: "empty_objective" };
  const { data, error } = await supabase.rpc("set_collection_completion_policy_to_master_set", {
    p_collection_id: input.collectionId,
    p_variant_type_ids: ids,
  });
  const row = Array.isArray(data) ? (data[0] as { total_positions?: unknown } | undefined) : undefined;
  if (error || !row) return objectiveFail("set_collection_completion_policy_to_master_set", startedAt, error ?? { code: "BAD_SHAPE" });
  const saved = objectiveSaved("activate_on_create", startedAt, {
    policy: "MASTER_SET" as const,
    total: Number(row.total_positions ?? 0),
    satisfied: null,
  });
  return { ok: true, total: saved.total, finishes: ids.length };
}

// ---------------------------------------------------------------------------
// Grade do Master Set (MASTER-SET-FRONTEND-PHASE-02) — leituras sob demanda
// ---------------------------------------------------------------------------

/**
 * Exemplares da coleção fora do objetivo (5196), uma página por vez — a
 * seção recolhível só lê quando o colecionador abre. Só leitura: nada é
 * removido, desvinculado ou alterado.
 */
export async function readMasterSetOutOfScope(input: {
  collectionId: string;
  offset: number;
}): Promise<({ ok: true } & OutOfScopePage) | Fail> {
  if (!isCollectionId(input?.collectionId) || !Number.isInteger(input.offset) || input.offset < 0 || input.offset > 100_000) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_master_set_out_of_scope_copies", {
    p_collection_id: input.collectionId,
    p_limit: OUT_OF_SCOPE_PAGE_SIZE,
    p_offset: input.offset,
  });
  if (error || !Array.isArray(data)) return fail("get_my_master_set_out_of_scope_copies", startedAt, error ?? { code: "BAD_SHAPE" });
  return { ok: true, ...parseOutOfScope(data) };
}

/**
 * Exemplares livres do acervo que satisfazem UMA posição — Query 5199
 * (LIVE e canônica desde 2026-10-18). Controlada por
 * `MASTER_SET_ADD_FROM_ACERVO_ENABLED`; desligada, nada é chamado. Só
 * leitura: quem vincula é `linkCopiesToCollection` (5046).
 */
export async function readMasterSetPositionCopies(input: {
  collectionId: string;
  cardId: string;
  variantTypeId: string | null;
}): Promise<({ ok: true; items: PositionCopy[]; total: number }) | Fail> {
  if (!MASTER_SET_ADD_FROM_ACERVO_ENABLED) return { ok: false, reason: "unavailable" };
  if (
    !isCollectionId(input?.collectionId) ||
    !isUuid(input.cardId) ||
    (input.variantTypeId !== null && !isUuid(input.variantTypeId))
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_master_set_position_copies", {
    p_collection_id: input.collectionId,
    p_card_id: input.cardId,
    p_variant_type_id: input.variantTypeId,
    p_limit: POSITION_COPIES_LIMIT,
    p_offset: 0,
  });
  if (error || !Array.isArray(data)) return fail("get_my_master_set_position_copies", startedAt, error ?? { code: "BAD_SHAPE" });
  return { ok: true, ...parsePositionCopies(data) };
}

// ---------------------------------------------------------------------------
// Master Set — "Adicionar cartas" em lote (5200 + 5046)
// ---------------------------------------------------------------------------

/**
 * Revisão: um exemplar livre do acervo por posição ainda faltante (5200 — LIVE e
 * canônica desde 2026-10-18). Só leitura. Controlada por
 * `MASTER_SET_ADD_FROM_ACERVO_ENABLED`; desligada, nada é chamado.
 */
export async function reviewMasterSetLink(input: {
  collectionId: string;
}): Promise<({ ok: true; total: number; items: MasterSetLinkCandidate[] }) | Fail> {
  if (!MASTER_SET_ADD_FROM_ACERVO_ENABLED) return { ok: false, reason: "unavailable" };
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const supabase = await createClient();
  const read = await readMasterSetLinkCandidates(supabase, input.collectionId);
  if (!read.ok) return read;
  return { ok: true, total: read.total, items: read.items };
}

/**
 * Vincula as posições MARCADAS que continuam faltando. Os candidatos são
 * relidos no servidor (estado atual, não o da revisão) a cada lote de até 500
 * (teto da 5046); posição já atendida no meio do caminho simplesmente não
 * entra, e reenviar o mesmo pedido não vincula duas vezes — a 5046 recusa
 * exemplar já vinculado e a releitura já não o devolve.
 */
export async function linkMasterSetPositions(input: {
  collectionId: string;
  positionKeys: string[];
}): Promise<{ ok: true; linked: number } | { ok: false; reason: CollectionFailure; linked: number }> {
  if (!MASTER_SET_ADD_FROM_ACERVO_ENABLED) return { ok: false, reason: "unavailable", linked: 0 };
  if (
    !isCollectionId(input?.collectionId) ||
    !Array.isArray(input.positionKeys) ||
    input.positionKeys.length === 0 ||
    input.positionKeys.length > MASTER_SET_LINK_BATCH_SIZE ||
    !input.positionKeys.every((key) => isPositionKey(key))
  ) {
    return { ok: false, reason: "invalid", linked: 0 };
  }

  const startedAt = Date.now();
  const supabase = await createClient();
  const wanted = new Set(input.positionKeys.map((key) => key.toLowerCase()));
  let linked = 0;

  // Cada volta lê o estado atual; o teto de voltas só protege contra laço infinito.
  for (let round = 0; round < 10 && wanted.size > 0; round += 1) {
    const candidates = await readMasterSetLinkCandidates(supabase, input.collectionId);
    if (!candidates.ok) return finish(candidates.reason);
    const ids = pickLinkCopies(candidates.items, wanted);
    if (ids.length === 0) break;
    for (const candidate of candidates.items) if (wanted.has(candidate.key)) wanted.delete(candidate.key);

    const { data, error } = await supabase.rpc("allocate_physical_cards_to_collection", {
      p_collection_id: input.collectionId,
      p_physical_card_ids: ids,
    });
    if (error || !Array.isArray(data)) {
      const failed = fail("allocate_physical_cards_to_collection", startedAt, error ?? { code: "BAD_SHAPE" });
      return finish(failed.reason);
    }
    linked += data.length;
    // Menos que um lote cheio = não há posição marcada além desta leitura.
    if (candidates.items.length < MASTER_SET_LINK_BATCH_SIZE) break;
  }

  return finish(null);

  function finish(reason: CollectionFailure | null) {
    console.info(JSON.stringify({ scope: "colecoes.master_set_link", ms: Date.now() - startedAt, linked, outcome: reason ?? "OK" }));
    if (linked > 0) {
      revalidatePath(COLECOES_PATH, "layout");
      revalidatePath(ACERVO_PATH);
    }
    return reason ? { ok: false as const, reason, linked } : { ok: true as const, linked };
  }
}

async function readMasterSetLinkCandidates(
  supabase: Awaited<ReturnType<typeof createClient>>,
  collectionId: string,
): Promise<{ ok: true; items: MasterSetLinkCandidate[]; total: number } | Fail> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_master_set_link_candidates", {
    p_collection_id: collectionId,
    p_limit: MASTER_SET_LINK_BATCH_SIZE,
  });
  if (error || !Array.isArray(data)) return fail("get_my_master_set_link_candidates", startedAt, error ?? { code: "BAD_SHAPE" });
  return { ok: true, ...parseMasterSetLinkCandidates(data) };
}

function objectiveSaved<T extends { policy: CompletionObjective; total: number | null; satisfied: number | null }>(
  kind: string,
  startedAt: number,
  result: T,
): { ok: true } & T {
  console.info(JSON.stringify({ scope: "colecoes.objective_save", kind, ms: Date.now() - startedAt }));
  // Título, progresso e Biblioteca vêm do servidor.
  revalidatePath(COLECOES_PATH, "layout");
  return { ok: true, ...result };
}

/** Lista de acabamentos pronta para o banco: 1..64 uuids distintos, ou `null`. */
function normalizeFinishIds(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_FINISHES) return null;
  if (!value.every((id) => isFinishId(id))) return null;
  const ids = [...new Set(value.map((id: string) => id.toLowerCase()))];
  return ids.length === value.length ? ids : null;
}

function objectiveFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): ObjectiveFail {
  const reason = classifyObjectiveFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.objective", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

type CopyDetailRow = {
  physical_card_id: string;
  copy_number: number;
  added_at: string;
  storage_name: string | null;
  collection_id: string | null;
  collector_number: string;
  language_name: string | null;
  variant_label: string | null;
  is_default_variant: boolean | null;
};

// ---- internos ----

async function writeCoverCode(
  supabase: Awaited<ReturnType<typeof createClient>>,
  collectionId: string,
  code: string | null,
): Promise<{ ok: true; code: string | null } | Fail> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("set_my_collection_cover_code", {
    p_collection_id: collectionId,
    p_code: code,
  });
  if (error || (data !== null && !isCoverCode(data))) {
    return fail("set_my_collection_cover_code", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  console.info(JSON.stringify({ scope: "colecoes.cover_code", ms: Date.now() - startedAt, cleared: data === null }));
  return { ok: true, code: data };
}

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

// ---------------------------------------------------------------------------
// Completar a Pokédex (POKEDEX-PKX-02) — contratos 5201–5204, LIVE e canônicos
// ---------------------------------------------------------------------------

type PokedexFail = { ok: false; reason: PokedexFailure };

const GENERATION_CODE = /^[A-Z0-9_]{1,40}$/;

function normalizeGenerationCodes(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_GENERATIONS) return null;
  const codes = [...new Set(value)];
  return codes.every((code) => typeof code === "string" && GENERATION_CODE.test(code)) ? (codes as string[]) : null;
}

function pokedexFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): PokedexFail {
  const reason = classifyPokedexFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.pokedex", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/** Motivo da Pokédex → motivo do painel de criação (mesma tradução de mensagens). */
function toCollectionFailure(reason: PokedexFailure): CollectionFailure {
  switch (reason) {
    case "not_authenticated":
    case "storage_required":
    case "storage_invalid":
    case "conflict":
    case "invalid":
    case "generation_unavailable":
    case "pokedex_unavailable":
      return reason;
    case "not_found":
      return "not_found";
    default:
      return "unavailable";
  }
}

/**
 * Criação → gerações catalogadas da Pokédex Nacional (5201 sem coleção). Só
 * leitura; a interface marca todas por padrão (decisão do proprietário).
 */
export async function readPokedexCreationOptions(): Promise<{ ok: true; options: GenerationOption[] } | PokedexFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  const supabase = await createClient();
  const options = await getPokedexGenerationOptions(supabase, null);
  if (options === null) return { ok: false, reason: "unavailable" };
  return { ok: true, options };
}

/**
 * Cria a coleção "Completar a Pokédex" — UMA chamada à 5202 (transação única
 * no banco: local padrão quando necessário, coleção com escopo EXPLÍCITO de
 * gerações e registro de idempotência). Mesma chave + mesmo pedido devolve a
 * mesma coleção (`replayed`), nunca duas. Gerações catalogadas depois nunca
 * entram sozinhas (C-02). Não toca cartas.
 */
export async function createPokedexCollection(input: {
  idempotencyKey: string;
  name: string;
  generationCodes: string[];
  storageContainerId: string | null;
}): Promise<({ ok: true } & CreateResult) | Fail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "unavailable" };
  const name = typeof input?.name === "string" ? normalizeCollectionName(input.name) : null;
  const codes = normalizeGenerationCodes(input?.generationCodes);
  if (
    !isUuid(input?.idempotencyKey) ||
    name === null ||
    codes === null ||
    (input.storageContainerId !== null && !isUuid(input.storageContainerId))
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_my_pokedex_collection", {
    p_idempotency_key: input.idempotencyKey,
    p_name: name,
    p_generation_codes: codes,
    p_storage_container_id: input.storageContainerId,
  });
  const row = Array.isArray(data)
    ? (data[0] as { collection_id?: string; storage_container_created?: boolean; replayed?: boolean } | undefined)
    : undefined;
  if (error || !row || !isCollectionId(row.collection_id)) {
    const failed = pokedexFail("create_my_pokedex_collection", startedAt, error ?? { code: "BAD_SHAPE" });
    return { ok: false, reason: toCollectionFailure(failed.reason) };
  }
  console.info(
    JSON.stringify({
      scope: "colecoes.create",
      kind: "pokedex",
      ms: Date.now() - startedAt,
      outcome: row.replayed ? "REPLAY" : "CREATED",
      generations: codes.length,
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

/** Ajustes → gerações: seleção atual e conquistadas por geração (5201 com coleção). Só leitura. */
export async function readPokedexGenerations(input: {
  collectionId: string;
}): Promise<{ ok: true; options: GenerationOption[] } | PokedexFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const supabase = await createClient();
  const options = await getPokedexGenerationOptions(supabase, input.collectionId);
  if (options === null) return { ok: false, reason: "unavailable" };
  // Coleção alheia, inexistente ou que não é Pokédex: a 5201 não marca nada.
  if (!options.some((option) => option.selected === true)) return { ok: false, reason: "not_found" };
  return { ok: true, options };
}

/**
 * Ajustes → grava as gerações — UMA chamada à 5203 (lista explícita,
 * idempotente: mesma lista = nada gravado). Nunca move, apaga ou desvincula
 * exemplar; o progresso devolvido é o do banco para o novo escopo.
 */
export async function savePokedexGenerations(input: {
  collectionId: string;
  generationCodes: string[];
}): Promise<{ ok: true; codes: string[]; total: number; satisfied: number; changed: boolean } | PokedexFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  const codes = normalizeGenerationCodes(input?.generationCodes);
  if (!isCollectionId(input?.collectionId) || codes === null) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_pokedex_generations", {
    p_collection_id: input.collectionId,
    p_generation_codes: codes,
  });
  const row = Array.isArray(data)
    ? (data[0] as { generation_codes?: unknown; total_positions?: unknown; satisfied_positions?: unknown; changed?: unknown } | undefined)
    : undefined;
  if (error || !row) return pokedexFail("set_my_pokedex_generations", startedAt, error ?? { code: "BAD_SHAPE" });
  const saved = Array.isArray(row.generation_codes) ? row.generation_codes.filter((code): code is string => typeof code === "string") : codes;
  console.info(
    JSON.stringify({ scope: "colecoes.pokedex_generations", ms: Date.now() - startedAt, generations: saved.length, changed: row.changed === true }),
  );
  if (row.changed === true) revalidatePath(COLECOES_PATH, "layout");
  return {
    ok: true,
    codes: saved,
    total: Number(row.total_positions ?? 0),
    satisfied: Number(row.satisfied_positions ?? 0),
    changed: row.changed === true,
  };
}

/** "Mostrar mais" da grade: a próxima página da 5204, com o mesmo filtro. Só leitura. */
export async function loadMorePokedexPositions(input: {
  collectionId: string;
  filter: PokedexFilter;
  generation: string | null;
  offset: number;
}): Promise<{ ok: true; page: PokedexPositionsPage } | PokedexFail> {
  const filter = input?.filter;
  if (
    !isCollectionId(input?.collectionId) ||
    (filter !== "todas" && filter !== "tenho" && filter !== "faltam") ||
    (input.generation !== null && !(typeof input.generation === "string" && GENERATION_CODE.test(input.generation))) ||
    !Number.isInteger(input.offset) ||
    input.offset < 0 ||
    input.offset > 100_000
  ) {
    return { ok: false, reason: "invalid" };
  }
  const supabase = await createClient();
  const page = await getMyPokedexPositions(supabase, input.collectionId, filter, input.generation, input.offset);
  if (page === null) return { ok: false, reason: "unavailable" };
  return { ok: true, page };
}

// ---------------------------------------------------------------------------
// Pokédex — vincular cartas às posições (POKEDEX-PKX-03)
// Novos: 5208 (candidatos), 5209 (vinculados), 5210 (vincular um), 5211 (prévia
// do lote) — PROPOSTA, não executados no LIVE. Reutilizados: 5046 (lote), 6124
// (retirar o vínculo), 6125 (representante), 5047 (tirar da coleção, ação
// `unlinkCopyFromCollection` acima).
// ---------------------------------------------------------------------------

type LinkFail = { ok: false; reason: LinkFailure };

function linkFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): LinkFail {
  const reason = classifyLinkFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.pokedex_link", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

function linkWritten(kind: string, startedAt: number, extra: Record<string, unknown> = {}) {
  console.info(JSON.stringify({ scope: "colecoes.pokedex_link", kind, ms: Date.now() - startedAt, ...extra }));
  revalidatePath(COLECOES_PATH, "layout");
  revalidatePath(ACERVO_PATH);
}

/**
 * Painel da posição → exemplares que podem entrar (5208). `SPECIES` = mesma
 * espécie (vínculo normal); `ACERVO` = outra carta do acervo, com busca, para
 * a exceção. Livres ou nesta coleção sem posição; nunca de outra coleção. Só
 * leitura.
 */
export async function readPokedexLinkCandidates(input: {
  collectionId: string;
  positionId: string;
  scope: LinkScope;
  query: string;
  offset: number;
}): Promise<{ ok: true; items: PokedexLinkCandidate[]; total: number } | LinkFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  const query = typeof input?.query === "string" ? input.query.trim().slice(0, LINK_QUERY_MAX) : "";
  if (
    !isCollectionId(input?.collectionId) ||
    !isUuid(input.positionId) ||
    (input.scope !== "SPECIES" && input.scope !== "ACERVO") ||
    !Number.isInteger(input.offset) ||
    input.offset < 0 ||
    input.offset > 10_000
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_pokedex_link_candidates", {
    p_collection_id: input.collectionId,
    p_pokedex_position_id: input.positionId,
    p_scope: input.scope,
    p_query: input.scope === "ACERVO" && query !== "" ? query : null,
    p_limit: LINK_CANDIDATES_PAGE_SIZE,
    p_offset: input.offset,
  });
  if (error || !Array.isArray(data)) return linkFail("get_my_pokedex_link_candidates", startedAt, error ?? { code: "BAD_SHAPE" });
  return { ok: true, ...parsePokedexLinkCandidates(data) };
}

/** Painel da posição → exemplares vinculados, representante primeiro (5209). Só leitura. */
export async function readPokedexPositionCopies(input: {
  collectionId: string;
  positionId: string;
}): Promise<{ ok: true; items: PokedexPositionCopy[]; total: number } | LinkFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isUuid(input.positionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_pokedex_position_copies", {
    p_collection_id: input.collectionId,
    p_pokedex_position_id: input.positionId,
  });
  if (error || !Array.isArray(data)) return linkFail("get_my_pokedex_position_copies", startedAt, error ?? { code: "BAD_SHAPE" });
  return { ok: true, ...parsePokedexPositionCopies(data) };
}

/**
 * Vincula UM exemplar à posição — UMA chamada à 5210 (alocação 5046 + vínculo
 * 6119/6122 na mesma transação). `confirmException = false` só aceita carta da
 * mesma espécie; `true` é a exceção, que o usuário confirmou depois de ver o
 * aviso. Nunca move exemplar de outra coleção ou de outra posição. Repetir é
 * inofensivo (mesmo vínculo).
 */
export async function linkPokedexCopy(input: {
  collectionId: string;
  positionId: string;
  physicalCardId: string;
  confirmException: boolean;
}): Promise<{ ok: true; basis: "SPECIES_MATCH" | "USER_OVERRIDE"; satisfied: number; total: number } | LinkFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  if (
    !isCollectionId(input?.collectionId) ||
    !isUuid(input.positionId) ||
    !isUuid(input.physicalCardId) ||
    typeof input.confirmException !== "boolean"
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("link_my_pokedex_copy", {
    p_collection_id: input.collectionId,
    p_pokedex_position_id: input.positionId,
    p_physical_card_id: input.physicalCardId,
    p_confirm_exception: input.confirmException,
  });
  const row = Array.isArray(data)
    ? (data[0] as { assignment_basis?: unknown; satisfied_positions?: unknown; total_positions?: unknown; allocated_now?: unknown } | undefined)
    : undefined;
  if (error || !row || (row.assignment_basis !== "SPECIES_MATCH" && row.assignment_basis !== "USER_OVERRIDE")) {
    return linkFail("link_my_pokedex_copy", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  linkWritten("link", startedAt, { basis: row.assignment_basis, allocatedNow: row.allocated_now === true });
  return {
    ok: true,
    basis: row.assignment_basis,
    satisfied: Number(row.satisfied_positions ?? 0),
    total: Number(row.total_positions ?? 0),
  };
}

/**
 * Retira o exemplar DESTA POSIÇÃO (6124) — ele continua na coleção, sem
 * posição, e pode ser colocado em outra. Não é "tirar da coleção" (5047).
 */
export async function removePokedexLink(input: {
  collectionId: string;
  physicalCardId: string;
}): Promise<{ ok: true } | LinkFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isUuid(input.physicalCardId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("remove_pokedex_position_assignment", { p_physical_card_id: input.physicalCardId });
  if (error || !Array.isArray(data) || data.length !== 1) {
    return linkFail("remove_pokedex_position_assignment", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  linkWritten("unlink_position", startedAt);
  return { ok: true };
}

/** Escolhe a carta representante da posição (6125). Troca a anterior, se houver. */
export async function setPokedexRepresentative(input: {
  collectionId: string;
  allocationId: string;
}): Promise<{ ok: true } | LinkFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isUuid(input.allocationId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_pokedex_position_primary_representative", {
    p_collection_allocation_id: input.allocationId,
  });
  const row = Array.isArray(data) ? (data[0] as { collection_id?: unknown } | undefined) : undefined;
  if (error || !row || row.collection_id !== input.collectionId) {
    return linkFail("set_pokedex_position_primary_representative", startedAt, error ?? { code: "BAD_SHAPE" });
  }
  linkWritten("representative", startedAt);
  return { ok: true };
}

/** Lote → prévia: um exemplar livre sugerido por Pokémon que falta (5211). Só leitura. */
export async function readPokedexBulkPreview(input: {
  collectionId: string;
  generation: string | null;
}): Promise<{ ok: true; items: BulkPreviewItem[]; missingTotal: number; total: number } | LinkFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  if (
    !isCollectionId(input?.collectionId) ||
    (input.generation !== null && !(typeof input.generation === "string" && GENERATION_CODE.test(input.generation)))
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_pokedex_bulk_link_preview", {
    p_collection_id: input.collectionId,
    p_generation_code: input.generation,
  });
  if (error || !Array.isArray(data)) return linkFail("get_my_pokedex_bulk_link_preview", startedAt, error ?? { code: "BAD_SHAPE" });
  return { ok: true, ...parseBulkPreview(data) };
}

/**
 * Lote → confirma os exemplares marcados — UMA chamada à 5046 (até 500, tudo
 * ou nada); a 6119 cria os vínculos da mesma espécie na mesma transação. Nunca
 * faz vínculo excepcional. Exemplar que mudou de lugar depois da prévia faz o
 * banco recusar o pedido inteiro (`already_linked`), sem mover nada.
 */
export async function linkPokedexBulk(input: {
  collectionId: string;
  physicalCardIds: string[];
}): Promise<{ ok: true; linked: number } | LinkFail> {
  if (!POKEDEX_COLLECTION_ENABLED) return { ok: false, reason: "disabled" };
  const ids = normalizeBulkIds(input?.physicalCardIds);
  if (!isCollectionId(input?.collectionId) || ids === null) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("allocate_physical_cards_to_collection", {
    p_collection_id: input.collectionId,
    p_physical_card_ids: ids,
  });
  if (error || !Array.isArray(data)) return linkFail("allocate_physical_cards_to_collection", startedAt, error ?? { code: "BAD_SHAPE" });
  linkWritten("bulk", startedAt, { requested: ids.length, linked: data.length });
  return { ok: true, linked: data.length };
}
