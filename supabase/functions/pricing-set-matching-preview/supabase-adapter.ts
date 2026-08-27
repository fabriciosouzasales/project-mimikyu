// Project Mimikyu — supabase/functions/pricing-set-matching-preview/supabase-adapter.ts
// Implementação real (Supabase) de SetMatchingPreviewPort — só leituras, mesmo client de
// service role usado por import-card-variants/index.ts após a fronteira de identidade já
// ter sido validada (ver index.ts). As 3 queries espelham exatamente os critérios de
// elegibilidade/cobertura já normativos na migration 3950
// (admin_list_pricing_set_mappings/get_pricing_admin_overview) — nenhum critério novo
// inventado aqui.

// deno-lint-ignore no-explicit-any
type SupabaseClientLike = any;

import type { EligibleCardSetInfo, ExistingSetMappingInfo, SetMatchingPreviewPort } from "./port.ts";

export function buildSetMatchingPreviewSupabaseAdapter(
  supabase: SupabaseClientLike,
): SetMatchingPreviewPort {
  return {
    async findCardSet(cardSetId: string): Promise<EligibleCardSetInfo | null> {
      // Mesmo join de admin_list_pricing_set_mappings (migration 3950): card_set ->
      // expansion -> game, para resolver g.code sem depender de nenhuma coluna
      // game_id direta em card_set (não existe — ver introspecção desta rodada).
      const { data, error } = await supabase
        .from("card_set")
        .select("id, code, name, release_date, expansion:expansion_id(game:game_id(code))")
        .eq("id", cardSetId)
        .maybeSingle();

      if (error || !data) return null;

      const gameCode = data.expansion?.game?.code ?? null;
      if (!gameCode) return null;

      return {
        id: data.id as string,
        code: data.code as string,
        name: data.name as string,
        releaseDate: (data.release_date as string | null) ?? null,
        gameCode: gameCode as string,
      };
    },

    async findActivePricingSource(code: string): Promise<{ id: string; code: string } | null> {
      const { data, error } = await supabase
        .from("pricing_source")
        .select("id, code")
        .eq("code", code)
        .eq("is_active", true)
        .maybeSingle();

      if (error || !data) return null;
      return { id: data.id as string, code: data.code as string };
    },

    async findExistingSetMapping(
      cardSetId: string,
      pricingSourceId: string,
    ): Promise<ExistingSetMappingInfo | null> {
      const { data, error } = await supabase
        .from("pricing_set_mapping")
        .select("match_status, external_set_id, external_set_name, last_checked_at")
        .eq("card_set_id", cardSetId)
        .eq("pricing_source_id", pricingSourceId)
        .maybeSingle();

      if (error || !data) return null;
      return {
        matchStatus: data.match_status as string,
        externalSetId: (data.external_set_id as string | null) ?? null,
        externalSetName: (data.external_set_name as string | null) ?? null,
        lastCheckedAt: (data.last_checked_at as string | null) ?? null,
      };
    },
  };
}
