// Project Mimikyu — Edge Function: import-card-assets
// Database Service — extraído do index.ts monolítico (Sprint B2.4.1 — CONFIRMADO CONCLUÍDO).
// index.ts passa a apenas orquestrar; este arquivo concentra o acesso a
// asset_import_run / card_set / card via ctx.supabaseAdmin.
// Ver docs/06-pipeline-importacao.md, "Sprint B2.4.1", para o contexto completo.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Card, CardSet, ImportRun } from "../types.ts";

export async function findImportRun(
  supabase: SupabaseClient,
  runCode: string,
): Promise<ImportRun | null> {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select("*")
    .eq("run_code", runCode)
    .maybeSingle();

  if (error) {
    console.error("Failed to read asset_import_run:", error);
    throw new Error("IMPORT_RUN_QUERY_FAILED");
  }

  return data as ImportRun | null;
}

export async function findCardSet(
  supabase: SupabaseClient,
  cardSetId: string,
): Promise<CardSet | null> {
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
    console.error("Failed to read card_set:", error);
    throw new Error("CARD_SET_QUERY_FAILED");
  }

  return data as CardSet | null;
}

export async function listCards(
  supabase: SupabaseClient,
  cardSetId: string,
): Promise<Card[]> {
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
    .order("collector_order", { ascending: true });

  if (error) {
    console.error("Failed to read cards:", error);
    throw new Error("CARDS_QUERY_FAILED");
  }

  return (data ?? []) as Card[];
}
