import type { SupabaseClient } from "@supabase/supabase-js";
import { type AcervoItemKey, type AcervoState, toItemsRpcParams } from "./acervo.ts";
import type { AddLanguage } from "./acervo-add.ts";

/**
 * Leituras de Meu acervo (MY-INVENTORY-IMPLEMENTATION-01) — contrato das
 * funções propostas 5159–5162. Todas exigem sessão (`auth.uid()`), resolvem o
 * dono no servidor e expõem só o necessário para exibir as cartas do próprio
 * usuário. A fronteira de autorização é o banco, não esta camada.
 *
 * Mesmo padrão de `lib/pokedex/queries.ts`: falha de leitura devolve `null`
 * (a página mostra o estado de erro, nunca uma lista vazia enganosa) e a
 * causa vai para o log do servidor, sem dados do usuário.
 */

export type AcervoSummary = {
  totalCopies: number;
  distinctItems: number;
  distinctSets: number;
  duplicateCopies: number;
};

export type AcervoItem = {
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
  /** Exemplares do item que atendem aos filtros por exemplar (5220 `copies_count`). */
  copiesCount: number;
  /** Todos os exemplares do item no acervo, sem filtro algum (5220 `copies_owned`). */
  copiesOwned: number;
  lastAddedAt: string;
  imagePath: string | null;
};

/**
 * Página da galeria. `totalGroups` = itens distintos que atendem aos filtros
 * (`total_count`, paginação); `totalCopies` = exemplares correspondentes em
 * TODAS as páginas (`total_copies`, 5220) — nunca a soma desta página.
 */
export type AcervoItemsPage = { items: AcervoItem[]; totalGroups: number; totalCopies: number };

export type AcervoFilterOption = { value: string; label: string; count: number };

export type AcervoFilterOptions = {
  sets: AcervoFilterOption[];
  languages: AcervoFilterOption[];
  collections: AcervoFilterOption[];
};

export type AcervoCopy = {
  physicalCardId: string;
  copyNumber: number;
  addedAt: string;
  /** Coleção do exemplar (WHERE-03: para mostrar o local padrão dela, só como referência). */
  collectionId: string | null;
  collectionName: string | null;
  storageName: string | null;
};

export type AcervoItemDetail = {
  item: Omit<AcervoItem, "copiesCount" | "copiesOwned" | "lastAddedAt">;
  copiesTotal: number;
  copies: AcervoCopy[];
};

type SummaryRow = { total_copies: number | string; distinct_items: number | string; distinct_sets: number | string; duplicate_copies: number | string };

export async function getAcervoSummary(supabase: SupabaseClient): Promise<AcervoSummary | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_inventory_summary");
  const row = (data as SummaryRow[] | null)?.[0];
  if (error || !row) {
    logAcervoReadFailure("get_my_inventory_summary", startedAt, error);
    return null;
  }
  return {
    totalCopies: Number(row.total_copies),
    distinctItems: Number(row.distinct_items),
    distinctSets: Number(row.distinct_sets),
    duplicateCopies: Number(row.duplicate_copies),
  };
}

type ItemRow = {
  card_variant_id: string;
  language_code: string;
  language_name: string | null;
  card_name: string;
  collector_number: string;
  collector_total: number | null;
  card_set_code: string;
  card_set_name: string;
  is_default_variant: boolean;
  variant_label: string | null;
  copies_count: number;
  copies_owned: number;
  last_added_at: string;
  image_path: string | null;
  total_count: number | string;
  total_copies: number | string;
};

type ItemCore = Omit<ItemRow, "copies_count" | "copies_owned" | "last_added_at" | "total_count" | "total_copies">;

function toItem(row: ItemCore & { copies_count?: number; copies_owned?: number; last_added_at?: string }): AcervoItem {
  const copiesCount = Number(row.copies_count ?? 0);
  return {
    cardVariantId: row.card_variant_id,
    languageCode: row.language_code,
    languageName: row.language_name ?? row.language_code,
    cardName: row.card_name,
    collectorNumber: row.collector_number,
    collectorTotal: row.collector_total,
    cardSetCode: row.card_set_code,
    cardSetName: row.card_set_name,
    isDefaultVariant: row.is_default_variant,
    variantLabel: row.variant_label,
    copiesCount,
    // Sem a coluna (não deveria ocorrer pós-5220), o possuído nunca fica abaixo do filtrado.
    copiesOwned: Math.max(Number(row.copies_owned ?? copiesCount), copiesCount),
    lastAddedAt: row.last_added_at ?? "",
    imagePath: row.image_path,
  };
}

export async function getAcervoItems(supabase: SupabaseClient, state: AcervoState): Promise<AcervoItemsPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_inventory_items", toItemsRpcParams(state));
  if (error || !data) {
    logAcervoReadFailure("get_my_inventory_items", startedAt, error);
    return null;
  }
  const rows = data as ItemRow[];
  const first = rows[0];
  return {
    items: rows.map(toItem),
    totalGroups: first ? Number(first.total_count) : 0,
    totalCopies: first ? Number(first.total_copies) : 0,
  };
}

type OptionRow = { kind: "SET" | "LANGUAGE" | "COLLECTION"; value: string; label: string; item_count: number | string; sort_order: number };

export async function getAcervoFilterOptions(supabase: SupabaseClient): Promise<AcervoFilterOptions | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_inventory_filter_options");
  if (error || !data) {
    logAcervoReadFailure("get_my_inventory_filter_options", startedAt, error);
    return null;
  }
  const rows = [...(data as OptionRow[])].sort((a, b) => a.sort_order - b.sort_order);
  const pick = (kind: OptionRow["kind"]) =>
    rows.filter((row) => row.kind === kind).map((row) => ({ value: row.value, label: row.label, count: Number(row.item_count) }));
  return { sets: pick("SET"), languages: pick("LANGUAGE"), collections: pick("COLLECTION") };
}

type CopyRow = ItemCore & {
  copies_total: number;
  physical_card_id: string;
  copy_number: number;
  added_at: string;
  collection_id: string | null;
  collection_name: string | null;
  storage_name: string | null;
};

/**
 * Detalhe de um grupo. `undefined` = grupo inexistente ou de outro usuário
 * (zero linhas — o banco não distingue os dois casos, de propósito);
 * `null` = falha de leitura.
 */
export async function getAcervoItemDetail(
  supabase: SupabaseClient,
  key: AcervoItemKey,
): Promise<AcervoItemDetail | null | undefined> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_inventory_item_copies", {
    p_card_variant_id: key.cardVariantId,
    p_language_code: key.languageCode,
  });
  if (error || !data) {
    logAcervoReadFailure("get_my_inventory_item_copies", startedAt, error);
    return null;
  }
  const rows = data as CopyRow[];
  const first = rows[0];
  if (!first) return undefined;
  // copiesCount e lastAddedAt são campos de galeria, ausentes no detalhe.
  const { copiesCount, copiesOwned, lastAddedAt, ...item } = toItem(first);
  return {
    item,
    copiesTotal: Number(first.copies_total),
    copies: rows.map((row) => ({
      physicalCardId: row.physical_card_id,
      copyNumber: row.copy_number,
      addedAt: row.added_at,
      collectionId: row.collection_id ?? null,
      collectionName: row.collection_name,
      storageName: row.storage_name,
    })),
  };
}

type LanguageRow = { language_id: string; code: string; name: string; language_order: number };

/**
 * Idiomas aceitos no cadastro de cartas — os ids que as RPCs de registro
 * exigem (INVENTORY-LANGUAGE-READ-01, Query 5164 `get_registrable_languages`).
 *
 * `public.language` continua sob a RLS do Catálogo Editorial (ADR-022); esta
 * leitura estreita (SECURITY DEFINER, só idiomas ativos, sem colunas
 * administrativas) é o único caminho do colecionador. Falha ou função ausente
 * → lista vazia: a página não mostra ações de adicionar, que não funcionariam
 * sem idioma.
 */
export async function getAddLanguages(supabase: SupabaseClient): Promise<AddLanguage[]> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_registrable_languages");
  if (error || !Array.isArray(data)) {
    logAcervoReadFailure("get_registrable_languages", startedAt, error);
    return [];
  }
  return toAddLanguages(data as LanguageRow[]);
}

export function toAddLanguages(rows: readonly LanguageRow[]): AddLanguage[] {
  return rows
    .filter((row) => typeof row.language_id === "string" && typeof row.code === "string" && typeof row.name === "string")
    .map((row) => ({ id: row.language_id, code: row.code, name: row.name }));
}

function logAcervoReadFailure(fn: string, startedAt: number, error: { code?: string; message?: string } | null) {
  console.error(
    JSON.stringify({
      scope: "acervo.read",
      fn,
      ms: Date.now() - startedAt,
      code: error?.code ?? "NO_DATA",
      // A mensagem do PostgREST não carrega dados do usuário (só o nome do erro SQL).
      message: error?.message ?? null,
    }),
  );
}
