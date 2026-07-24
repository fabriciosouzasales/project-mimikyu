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
