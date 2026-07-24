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
