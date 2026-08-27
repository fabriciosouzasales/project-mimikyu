// Project Mimikyu — supabase/functions/pricing-set-matching-preview/port.ts
// Porta de leitura local para o preview de correspondência de Set (P16.3) — mesmo padrão
// de _shared/pricing-justtcg-refresh/set-refresh-port.ts: uma interface mínima, só com os
// 3 acessos de dado que core.ts realmente precisa, para permitir testar core.ts 100%
// offline com um fake em memória (ver .test.ts). NENHUM método de escrita nesta interface —
// é estruturalmente impossível a core.ts persistir nada através desta porta (Seção 6 do
// pedido de Fabrício: "a Edge Function é READ + external API only").

export type EligibleCardSetInfo = {
  id: string;
  code: string;
  name: string;
  // ISO YYYY-MM-DD ou null (Set sem release_date cadastrada — hoje nenhum caso real, mas a
  // coluna é nullable no schema físico; tratado como NOT_FOUND por core.ts, nunca como erro).
  releaseDate: string | null;
  gameCode: string;
};

export type ExistingSetMappingInfo = {
  matchStatus: string; // CONFIRMED | PENDING | NOT_FOUND | REJECTED (os 4 status reais da tabela)
  externalSetId: string | null;
  externalSetName: string | null;
  lastCheckedAt: string | null;
};

export interface SetMatchingPreviewPort {
  // Resolve o Card Set pelo id, já com o código do Jogo (via expansion->game) — mesmo join
  // usado por admin_list_pricing_set_mappings (migration 3950). `null` = Set inexistente.
  findCardSet(cardSetId: string): Promise<EligibleCardSetInfo | null>;
  // Resolve a fonte de preço pelo código, só entre fontes ATIVAS (is_active=true) — mesmo
  // critério de "fonte aplicável" da migration 3950. `null` = fonte ausente ou inativa.
  findActivePricingSource(code: string): Promise<{ id: string; code: string } | null>;
  // `null` = nenhuma linha em pricing_set_mapping para este Set+fonte (equivalente ao
  // UNMAPPED sintético da migration 3950).
  findExistingSetMapping(
    cardSetId: string,
    pricingSourceId: string,
  ): Promise<ExistingSetMappingInfo | null>;
}
