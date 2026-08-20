-- 3922_reconcile_11_pricing_set_mapping_manual_correspondence
--
-- Reconciliacao final de 11 pricing_set_mapping para JUSTTCG, a pedido explicito de
-- Fabricio, sem nenhuma nova chamada a API nesta rodada. As 11 correspondencias abaixo
-- foram fornecidas diretamente por Fabricio (conhecimento previo do catalogo JustTCG,
-- fora desta sessao) e sao aplicadas aqui como decisao manual explicita, nao como
-- resultado do matching automatico (classifyCardMatch()/SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE).
--
-- BASEP verificado por introspecao local antes da escrita desta migration: nome real
-- "Wizards Black Star Promos", set_type=PROMO, release_date=1999-01-09, expansao "Colecao
-- Basica" -- confirma tratar-se do Set promocional da era Wizards/WotC, autorizando o
-- mapeamento wotc-promo-pokemon / WotC Promo conforme condicao do pedido.
--
-- Todos os 11 Card Sets locais confirmados sem pricing_set_mapping previo para JUSTTCG
-- (existing_mapping = null para os 11, verificado antes da escrita).
--
-- match_method = 'MANUAL_SET_RECONCILIATION' -- distinto dos metodos automaticos do
-- conector, sinaliza explicitamente que a correspondencia veio de decisao manual/externa,
-- nao de heuristica de release_date ou numero de colecao.
--
-- confirmed_at: nao setado explicitamente no INSERT -- a trigger
-- set_pricing_mapping_confirmed_at_authority() (migration 3920, BEFORE INSERT OR UPDATE,
-- ja aplicada a pricing_set_mapping) atribui confirmed_at = now() do servidor
-- automaticamente para toda linha nova com match_status = 'CONFIRMED'.
-- confirmed_by = fe316458-49dd-44e1-aac0-f4b7604ef8f2 (unico admin_user real do projeto,
-- mesmo UUID ja usado em todos os runs CARD_SYNC/MANUAL do Incremento P14).
--
-- Idempotencia: ON CONFLICT (card_set_id, pricing_source_id) DO NOTHING, usando o indice
-- unico incondicional uq_pricing_set_mapping_card_set_source (um mapping por Set x Fonte,
-- para sempre) -- reaplicacao real nao insere nenhuma linha nova e nunca altera uma linha
-- ja existente (nunca um UPDATE aqui, apenas INSERT condicional).
--
-- Escopo estrito: somente pricing_set_mapping. Nenhuma tabela de carta, produto ou
-- observacao de preco e tocada por esta migration. Nenhuma chamada a JustTCG.
--
-- CONFIRMADO EXECUTADO em producao (Supabase MCP apply_migration) em 2026-08-19. Testado
-- em BEGIN/ROLLBACK antes da aplicacao real (6 verificacoes: 11 insercoes, reaplicacao
-- real = 0 linhas, zero duplicidade, 11/11 CONFIRMED, confirmed_at atribuido pelo servidor
-- em todas, zero linha afetada em card/pricing_product/pricing_observation). Verificado
-- pos-aplicacao real: 11/11 CONFIRMED, confirmed_by correto em todas, confirmed_at setado
-- pelo servidor em todas, total pricing_set_mapping 34 -> 45, zero linha afetada em
-- card/pricing_product/pricing_observation (7429/36800/36984 inalterados).

INSERT INTO public.pricing_set_mapping (
  card_set_id,
  pricing_source_id,
  external_set_id,
  external_set_name,
  match_status,
  match_method,
  match_evidence,
  confirmed_by,
  last_checked_at
)
VALUES
  (
    'e2725cef-ca8a-4ebe-b20d-07d3f1c9a056', -- BASEP
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'wotc-promo-pokemon',
    'WotC Promo',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'BASEP',
      'nome_local', 'Wizards Black Star Promos',
      'set_type_local', 'PROMO',
      'data_local', '1999-01-09',
      'external_set_id', 'wotc-promo-pokemon',
      'external_set_name', 'WotC Promo',
      'fundamento', 'Nome local "Wizards Black Star Promos" + set_type PROMO + release_date 1999-01-09 confirmam via introspecao local, antes da escrita desta migration, tratar-se do Set promocional da era Wizards/WotC. Correspondencia fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    '6e292d9d-8ff0-4ca6-ad57-1fc0c83ef4fe', -- SWSH4.5
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'shining-fates-pokemon',
    'Shining Fates',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'SWSH4.5',
      'nome_local', 'Destinos Brilhante',
      'data_local', '2021-02-19',
      'external_set_id', 'shining-fates-pokemon',
      'external_set_name', 'Shining Fates',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    '052b793d-7cd7-4ccc-b196-6676199f11b3', -- CEL25
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'celebrations-pokemon',
    'Celebrations',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'CEL25',
      'nome_local', 'Celebracao 25 Anos',
      'data_local', '2021-10-08',
      'external_set_id', 'celebrations-pokemon',
      'external_set_name', 'Celebrations',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    'd34c6947-ac21-4397-9332-a0d6bddbb927', -- SV1
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'sv01-scarlet-violet-base-set-pokemon',
    'SV01: Scarlet & Violet Base Set',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'SV1',
      'nome_local', 'Escarlate e Violeta',
      'data_local', '2023-03-31',
      'external_set_id', 'sv01-scarlet-violet-base-set-pokemon',
      'external_set_name', 'SV01: Scarlet & Violet Base Set',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    '4aa12397-fe3c-4ae3-95ba-63a17123a48a', -- SVE
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'sve-scarlet-violet-energies-pokemon',
    'SVE: Scarlet & Violet Energies',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'SVE',
      'nome_local', 'Energias Escarlate e Violeta',
      'data_local', '2023-03-31',
      'external_set_id', 'sve-scarlet-violet-energies-pokemon',
      'external_set_name', 'SVE: Scarlet & Violet Energies',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    'f205e51c-e69b-4018-8e06-c1fa129464f3', -- SVP
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'sv-scarlet-violet-promo-cards-pokemon',
    'SV: Scarlet & Violet Promo Cards',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'SVP',
      'nome_local', 'SVP Black Star Promos',
      'data_local', '2023-03-31',
      'external_set_id', 'sv-scarlet-violet-promo-cards-pokemon',
      'external_set_name', 'SV: Scarlet & Violet Promo Cards',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    'd0abafb8-67b9-47d4-93b2-1d80634f1423', -- SV10.5B
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'sv-black-bolt-pokemon',
    'SV: Black Bolt',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'SV10.5B',
      'nome_local', 'Raio Preto',
      'data_local', '2025-07-18',
      'external_set_id', 'sv-black-bolt-pokemon',
      'external_set_name', 'SV: Black Bolt',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    'f018db26-19c3-405b-a60a-bcb58f098f41', -- SV10.5W
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'sv-white-flare-pokemon',
    'SV: White Flare',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'SV10.5W',
      'nome_local', 'Fogo Branco',
      'data_local', '2025-07-18',
      'external_set_id', 'sv-white-flare-pokemon',
      'external_set_name', 'SV: White Flare',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    '5c106d7c-c001-4f09-85c6-087c6ed0a925', -- MEP
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'me-mega-evolution-promo-pokemon',
    'ME: Mega Evolution Promo',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'MEP',
      'nome_local', 'MEP Black Star Promos',
      'data_local', '2025-09-26',
      'external_set_id', 'me-mega-evolution-promo-pokemon',
      'external_set_name', 'ME: Mega Evolution Promo',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    '7392ec29-77c9-4c7a-990a-778eb8856f62', -- GYM1
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'gym-heroes-pokemon',
    'Gym Heroes',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'GYM1',
      'nome_local', 'Lideres de Ginasio',
      'data_local', '2000-08-14',
      'external_set_id', 'gym-heroes-pokemon',
      'external_set_name', 'Gym Heroes',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  ),
  (
    'e4fb2112-6ddd-4f40-a9d1-89bb6231ac74', -- MEE
    '1ffe42af-7b16-4406-88c8-ad2d57dde6f9',
    'mee-mega-evolution-energies-pokemon',
    'MEE: Mega Evolution Energies',
    'CONFIRMED',
    'MANUAL_SET_RECONCILIATION',
    jsonb_build_object(
      'codigo_local', 'MEE',
      'nome_local', 'Energias Megaevolucao',
      'data_local', '2025-09-25',
      'external_set_id', 'mee-mega-evolution-energies-pokemon',
      'external_set_name', 'MEE: Mega Evolution Energies',
      'fundamento', 'Correspondencia comprovada, fornecida por Fabricio, sem nova chamada a API nesta rodada.',
      'chamada_justtcg_nesta_rodada', false
    ),
    'fe316458-49dd-44e1-aac0-f4b7604ef8f2',
    now()
  )
ON CONFLICT (card_set_id, pricing_source_id) DO NOTHING;
