-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-21
-- (Incremento de Atualizacao Diaria JustTCG, item D). Validada em BEGIN/ROLLBACK antes da
-- aplicacao real; validacao funcional pos-aplicacao (exclusao mutua nos dois sentidos,
-- tipos nao relacionados preservados, contagens de mappings/identidades/produtos/
-- observacoes inalteradas, advisors) registrada no relatorio desta rodada.
--
-- Contexto: decisao fechada 9 do Incremento de Atualizacao Diaria JustTCG ("CARD_SYNC e
-- PRICE_REFRESH ativos para a mesma pricing_source_id devem ser mutuamente exclusivos").
-- Ate esta migration, a unica garantia de concorrencia sobre pricing_source_id era a Query
-- 3907 (ux_pricing_sync_run_active_price_per_source_type) -- unica POR (pricing_source_id,
-- run_type). Isso impede dois CARD_SYNC simultaneos da mesma fonte, e dois PRICE_REFRESH
-- simultaneos da mesma fonte, mas NAO impede um CARD_SYNC e um PRICE_REFRESH ativos ao
-- mesmo tempo para a mesma fonte (chaves diferentes: (id, 'CARD_SYNC') x
-- (id, 'PRICE_REFRESH') nunca colidem entre si nesse indice).
--
-- Esta migration fecha essa lacuna com um SEGUNDO indice unico parcial, desta vez chaveado
-- SOMENTE por pricing_source_id (run_type fica de fora da chave) e restrito aos dois
-- run_types em jogo (CARD_SYNC, PRICE_REFRESH). Com os dois indices juntos:
--   3907 (source_id, run_type)                         -> nunca dois CARD_SYNC da mesma fonte
--                                                          nunca dois PRICE_REFRESH da mesma fonte
--   3926 (source_id) WHERE run_type IN (CARD_SYNC, PRICE_REFRESH) -> nunca um CARD_SYNC e um
--                                                          PRICE_REFRESH da mesma fonte ao
--                                                          mesmo tempo (em qualquer ordem de
--                                                          chegada -- o INSERT que chega
--                                                          depois sempre recebe 23505,
--                                                          independente de qual dos dois
--                                                          run_types tentou entrar primeiro).
--
-- SET_DISCOVERY e FX_REFRESH ficam FORA do filtro WHERE desta migration -- nunca bloqueados
-- por este indice, preservando exatamente o escopo da decisao 9 ("CARD_SYNC e
-- PRICE_REFRESH", nenhum outro par). FX_REFRESH tambem nunca usa pricing_source_id
-- (usa fx_source_code, Query 3905) -- nem entraria neste filtro mesmo sem a restricao
-- explicita de run_type.
--
-- Estados ativos: RECEIVED e PROCESSING -- mesmo conjunto ja usado pelas Queries 3907/3070.
-- Filtro pricing_source_id IS NOT NULL preservado por simetria com 3907, ainda que
-- redundante em teoria (CARD_SYNC/PRICE_REFRESH sempre gravam pricing_source_id) -- nao
-- indexar um NULL aqui tambem evita qualquer ambiguidade de NULLS DISTINCT.
--
-- Nenhum indice existente e removido ou alterado (3907 preservado integralmente -- ainda
-- necessario para impedir dois CARD_SYNC ou dois PRICE_REFRESH simultaneos da mesma fonte,
-- caso em que esta nova migration sozinha nao bastaria).

CREATE UNIQUE INDEX ux_pricing_sync_run_mutual_excl_card_sync_price_refresh
  ON public.pricing_sync_run (pricing_source_id)
  WHERE status IN ('RECEIVED', 'PROCESSING')
    AND run_type IN ('CARD_SYNC', 'PRICE_REFRESH')
    AND pricing_source_id IS NOT NULL;
