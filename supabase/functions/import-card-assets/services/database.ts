// Project Mimikyu — Edge Function: import-card-assets
// Database Service — CONFIRMADO DEPLOYADO no Sprint B3.3, junto com index.ts v1.3.0
// e o novo services/tcgdex.ts (ver docs/06-pipeline-importacao.md, "Sprint B3.3").
//
// Reescrito por completo no Sprint B3.1 (ganhou `findCardSetExternalReference`)
// e corrigido no Sprint B3.2: o import de `SupabaseClient` de
// "@supabase/supabase-js" foi removido porque esse pacote não está mapeado no
// `deno.json` da função (só há entradas para "@supabase/functions-js" e
// "@supabase/server") — o deploy real chegou a falhar por causa desse import
// (erro de bundling: "Relative import path ... not in import map"). Como este
// arquivo nunca cria um cliente Supabase (recebe sempre um já pronto via
// `ctx.supabaseAdmin`), não precisa do tipo concreto — `supabase: any` é uma
// escolha deliberada e temporária, até a arquitetura estabilizar (plano futuro
// registrado: gerar `database.types.ts` via `supabase gen types typescript` e
// trocar `any` por `SupabaseClient<Database>`).

export async function findImportRun(
  supabase: any,
  runCode: string,
) {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select(`
      id,
      run_code,
      asset_source_id,
      card_set_id,
      status,
      created_at
    `)
    .eq("run_code", runCode)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("IMPORT_RUN_QUERY_FAILED");
  }

  return data;
}

export async function findCardSet(
  supabase: any,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card_set")
    .select(`
      id,
      expansion_id,
      code,
      name,
      set_type,
      release_order,
      release_date,
      base_set_size,
      total_set_size
    `)
    .eq("id", cardSetId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_QUERY_FAILED");
  }

  return data;
}

export async function findCardSetExternalReference(
  supabase: any,
  cardSetId: string,
  assetSourceId: string,
) {
  const { data, error } = await supabase
    .from("card_set_external_reference")
    .select(`
      id,
      external_set_id,
      source_url
    `)
    .eq("card_set_id", cardSetId)
    .eq("asset_source_id", assetSourceId)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_EXTERNAL_REFERENCE_QUERY_FAILED");
  }

  return data;
}

export async function listCards(
  supabase: any,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card")
    .select(`
      id,
      card_set_id,
      rarity_id,
      category_id,
      collector_number,
      collector_total,
      collector_order,
      name
    `)
    .eq("card_set_id", cardSetId)
    .order("collector_order", {
      ascending: true,
    });

  if (error) {
    console.error(error);
    throw new Error("CARDS_QUERY_FAILED");
  }

  return data ?? [];
}

// Sprint B3.13 — Incremento 1 (CONFIRMADO CONCLUÍDO no Sprint B3.15: 188/188
// registros para a ME1). `card`/`card_variant` já estão populadas (ver
// docs/05-modelo-de-dados.md) — este incremento NUNCA insere em `card`,
// apenas localiza a carta já existente e popula `card_external_reference`.
//
// Nota real (Sprint B3.15): a primeira execução falhou com
// `permission denied for table card_external_reference` — GRANT ausente
// para `service_role`, mesmo gap já visto em `card_set_external_reference`
// (Query 250). Corrigido pela Query 253. Ver docs/06-pipeline-importacao.md,
// "Sprint B3.15".

/**
 * Carrega todas as cartas de uma coleção em um único SELECT e monta um
 * Map<collector_number, card_id> — lookup em memória O(1), evita uma consulta
 * por carta durante o loop de importação.
 */
export async function listCardsMap(
  supabase: any,
  cardSetId: string,
) {
  const cards = await listCards(
    supabase,
    cardSetId,
  );

  return new Map<string, string>(
    cards.map((card: any) => [
      card.collector_number,
      card.id,
    ]),
  );
}

/**
 * Cria ou atualiza uma referência externa da carta (card_external_reference).
 * Idempotente via ON CONFLICT (card_id, asset_source_id) DO UPDATE — uma
 * reexecução nunca duplica registros. Retorna o registro persistido.
 */
export async function upsertCardExternalReference(
  supabase: any,
  payload: {
    card_id: string;
    asset_source_id: string;
    external_card_id: string;
    external_set_id: string;
    source_number: string;
    source_url: string;
    image_source_url: string;
    metadata: any;
    is_active: boolean;
  },
) {
  const record = {
    ...payload,
    updated_at: new Date().toISOString(),
  };

  const { data, error } = await supabase
    .from("card_external_reference")
    .upsert(record, {
      onConflict: "card_id,asset_source_id",
    })
    .select()
    .single();

  if (error) {
    console.error(
      "UPSERT ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `CARD_EXTERNAL_REFERENCE_UPSERT_FAILED: ${error.message}`,
    );
  }

  return data;
}

// Sprint B3.18 — Incremento 2 (Download de Imagens), teste controlado com uma
// única carta. CONFIRMADO DEPLOYADO; execução ainda NÃO confirmada — bloqueada
// por um terceiro caso real do mesmo gap de GRANT já visto nas Queries 250/253
// (desta vez em `language`, descoberto pelo erro real `LANGUAGE_QUERY_FAILED`
// nos logs da Edge Function). Ver docs/06-pipeline-importacao.md, "Sprint
// B3.18", para o contexto completo.
//
// Nota arquitetural real, confirmada nesta revisão por auditoria direta de
// `information_schema.columns`: `card_asset` NÃO tem uma coluna
// `card_external_reference_id` — a relação final é
// `card_id`+`asset_type_id`+`language_id`+`storage_bucket_id`.
// `card_external_reference` é apenas a fonte de importação (de onde vêm
// `image_source_url`/`external_card_id`), não participa do relacionamento
// final do ativo.

/**
 * Localiza um idioma pelo código editorial (ex.: `en`, `pt-BR`).
 */
export async function findLanguageByCode(
  supabase: any,
  code: string,
) {
  const { data, error } = await supabase
    .from("language")
    .select(`
      id,
      code,
      name
    `)
    .eq("code", code)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("LANGUAGE_QUERY_FAILED");
  }

  return data;
}

/**
 * Localiza um tipo de ativo da carta pelo código (ex.: `CARD_FRONT`).
 */
export async function findCardAssetTypeByCode(
  supabase: any,
  code: string,
) {
  const { data, error } = await supabase
    .from("card_asset_type")
    .select(`
      id,
      code,
      name
    `)
    .eq("code", code)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_ASSET_TYPE_QUERY_FAILED");
  }

  return data;
}

/**
 * Localiza o bucket cadastrado no catálogo interno `storage_bucket`. O
 * `code` deve corresponder ao nome do bucket físico no Supabase Storage —
 * `storage_bucket` é um catálogo de metadados, não o bucket físico em si.
 */
export async function findStorageBucketByCode(
  supabase: any,
  code: string,
) {
  const { data, error } = await supabase
    .from("storage_bucket")
    .select(`
      id,
      code,
      name,
      description,
      storage_provider,
      bucket_order,
      is_public,
      is_active
    `)
    .eq("code", code)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("STORAGE_BUCKET_QUERY_FAILED");
  }

  return data;
}

type CardAssetPayload = {
  card_id: string;
  asset_type_id: string;
  source_code: string | null;
  source_reference: string | null;
  storage_path: string | null;
  external_url: string | null;
  mime_type: string | null;
  file_extension: string | null;
  file_size_bytes: number | null;
  width_pixels: number | null;
  height_pixels: number | null;
  checksum_sha256: string | null;
  is_primary: boolean;
  asset_order: number;
  is_active: boolean;
  language_id: string;
  storage_bucket_id: string;
};

/**
 * Cria ou atualiza o ativo da carta (`card_asset`).
 *
 * A localização do registro existente usa a chave natural
 * `card_id`+`asset_type_id`+`language_id`+`storage_bucket_id`, em vez de um
 * `UPSERT` com `onConflict` — mantém o processamento idempotente sem
 * depender de um nome de constraint `UNIQUE` presumido, ainda não confirmado
 * para esta tabela.
 */
export async function upsertCardAsset(
  supabase: any,
  payload: CardAssetPayload,
) {
  const { data: existing, error: findError } = await supabase
    .from("card_asset")
    .select("id")
    .eq("card_id", payload.card_id)
    .eq("asset_type_id", payload.asset_type_id)
    .eq("language_id", payload.language_id)
    .eq("storage_bucket_id", payload.storage_bucket_id)
    .eq("is_active", true)
    .maybeSingle();

  if (findError) {
    console.error(
      "CARD ASSET FIND ERROR:",
      JSON.stringify(findError, null, 2),
    );
    throw new Error(
      `CARD_ASSET_QUERY_FAILED: ${findError.message}`,
    );
  }

  const record = {
    ...payload,
    updated_at: new Date().toISOString(),
  };

  if (existing) {
    const { data, error } = await supabase
      .from("card_asset")
      .update(record)
      .eq("id", existing.id)
      .select()
      .single();

    if (error) {
      console.error(
        "CARD ASSET UPDATE ERROR:",
        JSON.stringify(error, null, 2),
      );
      throw new Error(
        `CARD_ASSET_UPDATE_FAILED: ${error.message}`,
      );
    }

    return data;
  }

  const { data, error } = await supabase
    .from("card_asset")
    .insert(record)
    .select()
    .single();

  if (error) {
    console.error(
      "CARD ASSET INSERT ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `CARD_ASSET_INSERT_FAILED: ${error.message}`,
    );
  }

  return data;
}
