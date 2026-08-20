-- 3921_correct_legacy_ext_teste_mapping_bulbasaur_me1
--
-- Saneamento pontual do mapping legado com external_card_id='ext-teste' (Bulbasaur #001,
-- Set ME1/me01-mega-evolution-pokemon). Origem: placeholder de teste com match_evidence
-- vazio e match_method inexistente no codigo atual ('reconfirmacao_legitima'), identificado
-- no fechamento tecnico do P14.4.4 (2026-08-19/20). external_card_id canonico comprovado
-- por consulta real e controlada a GET /v1/cards (3 requisicoes, Set ME1 ja CONFIRMED,
-- collector_number normalizado '001'->'1', deduplicacao por external_card_id): candidato
-- unico "pokemon-me01-mega-evolution-bulbasaur-001-132-common", consistente com o padrao
-- de nomenclatura das demais cartas confirmadas do mesmo Set.
--
-- Escopo estrito: 1 unica linha (id/card_id/pricing_source_id/external_card_id='ext-teste'
-- no WHERE). Preserva confirmed_at/confirmed_by (nao tocados no SET; a trigger
-- set_pricing_mapping_confirmed_at_authority da migration 3920 preserva OLD.confirmed_at
-- automaticamente pois match_status permanece CONFIRMED) e todos os 7 produtos/14
-- observacoes ja existentes (pricing_product/pricing_observation nao sao tocados aqui).
-- Guarda idempotente: uma segunda aplicacao nao encontra mais external_card_id='ext-teste'
-- nesta linha e afeta 0 linhas (confirmado por reaplicacao real pos-migration).
--
-- CONFIRMADO EXECUTADO em producao (Supabase MCP apply_migration) em 2026-08-20. Testado
-- em BEGIN/ROLLBACK antes da aplicacao real (6 verificacoes, todas OK). Validacao
-- pos-aplicacao (10 itens): 1 linha corrigida, zero duplicidade, 7 produtos/14
-- observacoes preservados, zero orfaos, preco disponivel via get_cards_pricing_summary
-- sob role authenticated (has_pricing=true), trigger 3920 continua governando
-- confirmed_at, reaplicacao real = 0 linhas afetadas.

UPDATE public.pricing_card_mapping
SET
  external_card_id = 'pokemon-me01-mega-evolution-bulbasaur-001-132-common',
  external_card_name = 'Bulbasaur - 001/132',
  match_method = 'SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE',
  match_evidence = jsonb_build_object(
    'external_set_id', 'me01-mega-evolution-pokemon',
    'collector_number_local', '001',
    'collector_number_normalizado', '1',
    'candidato_unico_comprovado', 'pokemon-me01-mega-evolution-bulbasaur-001-132-common',
    'requisicoes_utilizadas', 3,
    'total_cartas_no_set_externo', 227,
    'motivo_corretivo', 'Saneamento do mapping legado ext-teste (placeholder de teste, match_evidence vazio, match_method inexistente no codigo atual). ID canonico comprovado por consulta real a GET /v1/cards, filtrando Set ME1 ja CONFIRMED (me01-mega-evolution-pokemon) + collector_number normalizado, com deduplicacao por external_card_id -- candidato unico.',
    'external_card_id_anterior', 'ext-teste',
    'external_card_name_anterior', 'Nome Teste',
    'match_method_anterior', 'reconfirmacao_legitima'
  ),
  last_checked_at = now(),
  updated_at = now()
WHERE id = 'e6b0e7ed-389d-4748-8a4c-794167618c7c'
  AND card_id = '4decef57-4998-4db3-ae37-7faee5fa9a58'
  AND pricing_source_id = '1ffe42af-7b16-4406-88c8-ad2d57dde6f9'
  AND match_status = 'CONFIRMED'
  AND external_card_id = 'ext-teste';
