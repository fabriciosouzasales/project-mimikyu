-- ============================================================================
-- Query 2232 — SEED dos 122 Edition Context External Mappings
-- Status: PROPOSTA — PROPOSAL ONLY · Versao 2.1
-- Mandato: EDITION-CONTEXT-AXIS-EDITORIAL-VOCABULARY-02
--          + EDITION-CONTEXT-AXIS-BATCH2-GAME-CODE-CORRECTION-01 (v2.1)
--
-- v2.1 — GAME CANONICO + PREFLIGHT FAIL-LOUD
--   Esta seed carregava DUAS ocorrencias de `code = 'PTCG'` (PASSO 2), code
--   que NAO EXISTE: os Games reais sao 'LORCANA' e 'POKEMON'. Nao chegou a ser
--   executada — o STOP na 2230 a bloqueou.
--
--   DIFERENCA IMPORTANTE EM RELACAO A 2230/2231: aqui o Game nao vinha de um
--   CROSS JOIN LATERAL, e sim de uma SUBQUERY ESCALAR. Subquery escalar sem
--   linha devolve NULL, nao conjunto vazio. Logo o modo de falha nao seria
--   "0 linhas em silencio" — seria `null value in column "game_id" violates
--   not-null constraint`, disparado pela constraint da tabela, sem gate
--   nomeado e sem dizer QUAL referencia faltou. Fail-loud por acidente de
--   constraint, nao por desenho.
--
--   CORRECAO: os dois literais passam a 'POKEMON', e o PASSO 0 ganha um
--   preflight que prova Game E asset_source ANTES do primeiro write, com
--   excecao nomeada por referencia. A seed deixa de depender de violacao de
--   NOT NULL para detectar referencia ausente.
--
--   O guard M0 (one-shot) e anterior e permanece INTOCADO, na frente de tudo.
--   Corpus INTOCADO: 122 mappings, 108 GLOBAL / 14 SCOPED, GUARD H2, gates
--   M1-M6 e a normalizacao seguem byte a byte iguais a v2.0.
--
--   117 tokens de origem -> 122 linhas de mapping
--   (os SCOPED geram uma linha por Set: set-logo 3, platinum 4, mfb 6, base2 1)
--
--   GLOBAL ............. 108
--   SOURCE_SET_SCOPED .. 14
--
-- GUARD H2 PRESERVADO INTEGRALMENTE: 'SET-LOGO' so existe escopado a
-- dp1 / swsh9 / svp — NUNCA GLOBAL. As 379 rows de EX7-EX10 pertencem ao eixo
-- FINISH e nao tem mapping aqui; as 4 de SV3/SV4 seguem INDETERMINATE.
--
-- raw_field: somente 'stamp' e 'subtype'. 'foil' e impossivel por
-- ck_cecem_raw_field (2207) — o gate M3 abaixo prova isso no proprio seed.
-- ============================================================================

-- ============================================================================
-- SEMÂNTICA DE REAPLICAÇÃO — **ONE-SHOT, RECUSA FAIL-LOUD** (opção B)
-- Declarada em MAPPING-LIFECYCLE-CORRECTION-02, item 3.
--
-- ESTE SEED NÃO É IDEMPOTENTE, E ISSO É DELIBERADO.
--
-- POR QUE NÃO IDEMPOTENTE — razão técnica, não preferência:
--   Tornar o INSERT do cabeçalho idempotente exigiria `ON CONFLICT` com
--   inferência de índice. Mas a 2207 v3.0+ tem DOIS índices parciais
--   distintos e mutuamente exclusivos:
--       uq_cecem_active_global  WHERE external_set_id IS NULL     AND is_active
--       uq_cecem_active_scoped  WHERE external_set_id IS NOT NULL AND is_active
--   Um único `ON CONFLICT (...) WHERE ...` só consegue inferir UM deles. As
--   108 linhas GLOBAL e as 14 SCOPED caem em índices diferentes, então o
--   statement teria de ser partido em dois só para simular idempotência de
--   um seed de fundação que roda UMA vez, no Batch 2, sobre tabela vazia.
--
-- O QUE MUDA EM RELAÇÃO AO COMPORTAMENTO ANTERIOR:
--   Antes, reaplicar produzia `unique_violation` cru vindo do índice — um
--   acidente que *parecia* proteção, e que só apareceria DEPOIS de já ter
--   escrito parte das linhas. Agora existe o gate M0: a recusa é EXPLÍCITA,
--   NOMEADA e anterior a qualquer escrita. O mandato proíbe "comportamento
--   acidental por unique_violation"; é exatamente isso que M0 elimina.
--
-- COMO CORRIGIR UM MAPPING DEPOIS DO SEED: não é reexecutar este arquivo.
--   É o fluxo editorial da 2207 v4.0 — aposentar o ativo (TRUE -> FALSE) e
--   criar um mapping novo, na mesma transação. Ver bloco LIFECYCLE da 2207.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 0 ---
-- M0 — RECUSA EXPLÍCITA DE REAPLICAÇÃO (fail-loud, ANTES de qualquer write).
DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM public.card_edition_context_external_mapping;
    IF v_n <> 0 THEN
        RAISE EXCEPTION
          'SEED_MAP_ALREADY_APPLIED (M0): a tabela ja contem % mapping(s) — ativos e/ou historicos. Este seed e ONE-SHOT e recusa reaplicacao deliberadamente. Para corrigir um mapping, aposente o ativo (is_active = FALSE) e crie um novo; nunca reexecute este arquivo.', v_n;
    END IF;
END $$;

-- M0-BIS — PREFLIGHT DE REFERENCIAS OBRIGATORIAS (v2.1), tambem ANTES de
-- qualquer write. Sao DUAS referencias, e cada uma aborta com excecao propria
-- para que a mensagem diga qual faltou.
--
-- Sem este bloco, Game ou asset_source ausente viraria `game_id`/
-- `asset_source_id` NULL (subquery escalar) e a falha apareceria como violacao
-- de NOT NULL — correta, porem muda: sem dizer que o problema e a referencia.
-- Com >1 linha, a subquery escalar levantaria "more than one row returned",
-- igualmente opaco. Os dois casos passam a ser nomeados aqui.
DO $$
DECLARE v_game INT; v_src INT;
BEGIN
    SELECT COUNT(*) INTO v_game FROM public.game         WHERE code = 'POKEMON';
    IF v_game <> 1 THEN
        RAISE EXCEPTION 'SEED_GAME_REFERENCE (2232): esperado EXATAMENTE 1 Game com code=''POKEMON'', encontrado %. Abortado antes de qualquer escrita — sem isso a falha apareceria como violacao de NOT NULL em game_id.', v_game;
    END IF;

    SELECT COUNT(*) INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_src <> 1 THEN
        RAISE EXCEPTION 'SEED_SOURCE_REFERENCE (2232): esperado EXATAMENTE 1 asset_source com code=''TCGDEX'', encontrado %. Abortado antes de qualquer escrita — sem isso a falha apareceria como violacao de NOT NULL em asset_source_id.', v_src;
    END IF;
END $$;

CREATE TEMP TABLE seed_ec_map (
    raw_field TEXT, normalized_token TEXT, external_set_id TEXT, trait_code TEXT
) ON COMMIT DROP;

INSERT INTO seed_ec_map (raw_field, normalized_token, external_set_id, trait_code) VALUES
    ('subtype', 'BLUE-BORDER', 'mfb', 'ARTWORK_MFB_BLUE_BORDER'),
    ('stamp', 'POKEBALL', 'mfb', 'ARTWORK_MFB_POKE_BALL'),
    ('stamp', 'SET-LOGO', 'dp1', 'ARTWORK_SET_LOGO'),
    ('stamp', 'SET-LOGO', 'swsh9', 'ARTWORK_SET_LOGO'),
    ('stamp', 'SET-LOGO', 'svp', 'ARTWORK_SET_LOGO'),
    ('stamp', '10TH-ANNIVERSARY', NULL, 'CAMPAIGN_10TH_ANNIVERSARY'),
    ('stamp', '25TH-CELEBRATION', NULL, 'CAMPAIGN_25TH_ANNIVERSARY'),
    ('stamp', 'COUNTDOWN-CALENDAR', NULL, 'CAMPAIGN_COUNTDOWN_CALENDAR'),
    ('stamp', 'DESTINY-DEOXYS', NULL, 'CAMPAIGN_DESTINY_DEOXYS'),
    ('stamp', '1ST-MOVIE', NULL, 'CAMPAIGN_FIRST_MOVIE'),
    ('stamp', '1ST-MOVIE-INVERTED', NULL, 'CAMPAIGN_FIRST_MOVIE_INVERTED'),
    ('stamp', 'HORIZONS', NULL, 'CAMPAIGN_HORIZONS'),
    ('stamp', 'PLATINUM', 'dp4', 'CAMPAIGN_PLATINUM'),
    ('stamp', 'PLATINUM', 'dp5', 'CAMPAIGN_PLATINUM'),
    ('stamp', 'PLATINUM', 'dp6', 'CAMPAIGN_PLATINUM'),
    ('stamp', 'PLATINUM', 'dp7', 'CAMPAIGN_PLATINUM'),
    ('stamp', 'POKEMON-4-EVER', NULL, 'CAMPAIGN_POKEMON_4EVER'),
    ('stamp', '30TH-POKEDAY', NULL, 'CAMPAIGN_POKEMON_DAY_30TH'),
    ('stamp', 'POKEMON-TOGETHER', NULL, 'CAMPAIGN_POKEMON_TOGETHER'),
    ('stamp', 'THANK-YOU', NULL, 'CAMPAIGN_THANK_YOU'),
    ('stamp', 'TRICK-OR-TRADE', NULL, 'CAMPAIGN_TRICK_OR_TRADE'),
    ('stamp', 'ASIA-2023-24', NULL, 'CHANNEL_ASIA_2023_24'),
    ('stamp', 'ASIA-PROMO', NULL, 'CHANNEL_ASIA_PROMO'),
    ('stamp', 'EB-GAMES', NULL, 'CHANNEL_EB_GAMES'),
    ('subtype', 'GOLD-BORDER', 'base2', 'CHANNEL_FRUIT_ROLLS'),
    ('stamp', 'GAMESTOP', NULL, 'CHANNEL_GAMESTOP'),
    ('stamp', 'INQUEST-GAMER', NULL, 'CHANNEL_INQUEST_GAMER'),
    ('stamp', 'KRAZE-CLUB', NULL, 'CHANNEL_KRAZE_CLUB'),
    ('stamp', 'MCDONALDS', NULL, 'CHANNEL_MCDONALDS'),
    ('stamp', 'BULBASAUR', 'mfb', 'CHANNEL_MFB_DECK_BULBASAUR'),
    ('stamp', 'CHARMANDER', 'mfb', 'CHANNEL_MFB_DECK_CHARMANDER'),
    ('stamp', 'PIKACHU', 'mfb', 'CHANNEL_MFB_DECK_PIKACHU'),
    ('stamp', 'SQUIRTLE', 'mfb', 'CHANNEL_MFB_DECK_SQUIRTLE'),
    ('stamp', 'POKEMON-CENTER', NULL, 'CHANNEL_POKEMON_CENTER'),
    ('stamp', 'POKEMON-CENTER-NY', NULL, 'CHANNEL_POKEMON_CENTER_NY'),
    ('stamp', 'SCRYE', NULL, 'CHANNEL_SCRYE'),
    ('stamp', 'W-PROMO', NULL, 'CHANNEL_WOTC_PROMO'),
    ('stamp', 'WOTC', NULL, 'CHANNEL_WOTC_PROMO'),
    ('stamp', 'AKIRA-MIYAZAKI', NULL, 'DECK_PLAYER_AKIRA_MIYAZAKI'),
    ('stamp', 'CHASE-MOLONEY', NULL, 'DECK_PLAYER_CHASE_MOLONEY'),
    ('stamp', 'CHRISTOPHER-KAN', NULL, 'DECK_PLAYER_CHRISTOPHER_KAN'),
    ('stamp', 'CHRIS-FULOP', NULL, 'DECK_PLAYER_CHRIS_FULOP'),
    ('stamp', 'CURRAN-HILL', NULL, 'DECK_PLAYER_CURRAN_HILL'),
    ('stamp', 'DAVID-COHEN', NULL, 'DECK_PLAYER_DAVID_COHEN'),
    ('stamp', 'DYLAN-LEFAVOUR', NULL, 'DECK_PLAYER_DYLAN_LEFAVOUR'),
    ('stamp', 'GABRIEL-FERNANDEZ', NULL, 'DECK_PLAYER_GABRIEL_FERNANDEZ'),
    ('stamp', 'GUSTAVO-WADA', NULL, 'DECK_PLAYER_GUSTAVO_WADA'),
    ('stamp', 'HIROKI-YANO', NULL, 'DECK_PLAYER_HIROKI_YANO'),
    ('stamp', 'IGOR-COSTA', NULL, 'DECK_PLAYER_IGOR_COSTA'),
    ('stamp', 'JASON-KLACZYNSKI', NULL, 'DECK_PLAYER_JASON_KLACZYNSKI'),
    ('stamp', 'JASON-MARTINEZ', NULL, 'DECK_PLAYER_JASON_MARTINEZ'),
    ('stamp', 'JEREMY-MARON', NULL, 'DECK_PLAYER_JEREMY_MARON'),
    ('stamp', 'JEREMY-SCHARFF-KIM', NULL, 'DECK_PLAYER_JEREMY_SCHARFF_KIM'),
    ('stamp', 'JESSE-PARKER', NULL, 'DECK_PLAYER_JESSE_PARKER'),
    ('stamp', 'JIMMY-BALLARD', NULL, 'DECK_PLAYER_JIMMY_BALLARD'),
    ('stamp', 'JUN-HASEBE', NULL, 'DECK_PLAYER_JUN_HASEBE'),
    ('stamp', 'KEVIN-NGUYEN', NULL, 'DECK_PLAYER_KEVIN_NGUYEN'),
    ('stamp', 'MICHAEL-GONZALEZ', NULL, 'DECK_PLAYER_MICHAEL_GONZALEZ'),
    ('stamp', 'MICHAEL-PRAMAWAT', NULL, 'DECK_PLAYER_MICHAEL_PRAMAWAT'),
    ('stamp', 'MISKA-SAARI', NULL, 'DECK_PLAYER_MISKA_SAARI'),
    ('stamp', 'MYCHAEL-BRYAN', NULL, 'DECK_PLAYER_MYCHAEL_BRYAN'),
    ('stamp', 'PAUL-ATANASSOV', NULL, 'DECK_PLAYER_PAUL_ATANASSOV'),
    ('stamp', 'REED-WEICHLER', NULL, 'DECK_PLAYER_REED_WEICHLER'),
    ('stamp', 'ROSS-CAWTHORN', NULL, 'DECK_PLAYER_ROSS_CAWTHORN'),
    ('stamp', 'SAKUYA-OTA', NULL, 'DECK_PLAYER_SAKUYA_OTA'),
    ('stamp', 'SHAO-TONG-YEN', NULL, 'DECK_PLAYER_SHAO_TONG_YEN'),
    ('stamp', 'SHUTO-ITAGAKI', NULL, 'DECK_PLAYER_SHUTO_ITAGAKI'),
    ('stamp', 'STEPHEN-SILVESTRO', NULL, 'DECK_PLAYER_STEPHEN_SILVESTRO'),
    ('stamp', 'TAKASHI-YONEDA', NULL, 'DECK_PLAYER_TAKASHI_YONEDA'),
    ('stamp', 'TOM-ROOS', NULL, 'DECK_PLAYER_TOM_ROOS'),
    ('stamp', 'TRISTAN-ROBINSON', NULL, 'DECK_PLAYER_TRISTAN_ROBINSON'),
    ('stamp', 'TSUBASA-NAKAMURA', NULL, 'DECK_PLAYER_TSUBASA_NAKAMURA'),
    ('stamp', 'TSUGUYOSHI-YAMATO', NULL, 'DECK_PLAYER_TSUGUYOSHI_YAMATO'),
    ('stamp', 'YUKA-FURUSAWA', NULL, 'DECK_PLAYER_YUKA_FURUSAWA'),
    ('stamp', 'YUTA-KOMATSUDA', NULL, 'DECK_PLAYER_YUTA_KOMATSUDA'),
    ('stamp', 'ZACHARY-BOKHARI', NULL, 'DECK_PLAYER_ZACHARY_BOKHARI'),
    ('stamp', 'CHICAGO-2009', NULL, 'EVENT_CHICAGO_2009'),
    ('stamp', 'CITY-CHAMPIONSHIPS', NULL, 'EVENT_CITIES'),
    ('stamp', 'COMIC-CON', NULL, 'EVENT_COMIC_CON'),
    ('stamp', 'DISTRIBUTOR-MEETING', NULL, 'EVENT_DISTRIBUTOR_MEETING'),
    ('stamp', 'GAMES-EXPO', NULL, 'EVENT_GAMES_EXPO'),
    ('stamp', 'GEN-CON', NULL, 'EVENT_GEN_CON'),
    ('stamp', 'GYM-CHALLENGE', NULL, 'EVENT_GYM_CHALLENGE'),
    ('stamp', 'INTERNATIONAL-CHAMPIONSHIP-EUROPE', NULL, 'EVENT_INTERNATIONALS_EUROPE'),
    ('stamp', 'INTERNATIONAL-CHAMPIONSHIP-NORTH-AMERICA', NULL, 'EVENT_INTERNATIONALS_NORTH_AMERICA'),
    ('stamp', 'NATIONAL-CHAMPIONSHIPS', NULL, 'EVENT_NATIONALS'),
    ('stamp', 'NINTENDO-WORLD', NULL, 'EVENT_NINTENDO_WORLD'),
    ('stamp', 'ORIGINS', NULL, 'EVENT_ORIGINS'),
    ('stamp', 'ORIGINS-2008', NULL, 'EVENT_ORIGINS_2008'),
    ('stamp', 'POKEMON-DAY', NULL, 'EVENT_POKEMON_DAY'),
    ('stamp', 'POKEMON-ROCKS-AMERICA', NULL, 'EVENT_POKEMON_ROCKS_AMERICA'),
    ('stamp', 'POKETOUR-99', NULL, 'EVENT_POKETOUR_99'),
    ('stamp', 'POP-TOURNAMENT', NULL, 'EVENT_POP_TOURNAMENT'),
    ('stamp', 'PRE-RELEASE', NULL, 'EVENT_PRERELEASE'),
    ('stamp', 'REGIONAL-CHAMPIONSHIPS', NULL, 'EVENT_REGIONALS'),
    ('stamp', 'STADIUM-CHALLENGE', NULL, 'EVENT_STADIUM_CHALLENGE'),
    ('stamp', 'STATE-CHAMPIONSHIPS', NULL, 'EVENT_STATES'),
    ('stamp', 'WIZARD-WORLD-CHICAGO', NULL, 'EVENT_WIZARD_WORLD_CHICAGO'),
    ('stamp', 'WIZARD-WORLD-PHILADELPHIA', NULL, 'EVENT_WIZARD_WORLD_PHILADELPHIA'),
    ('stamp', 'WORLDS-2004', NULL, 'EVENT_WORLDS_2004'),
    ('stamp', 'WORLDS-2005', NULL, 'EVENT_WORLDS_2005'),
    ('stamp', 'WORLDS-2007', NULL, 'EVENT_WORLDS_2007'),
    ('stamp', 'WORLDS-2008', NULL, 'EVENT_WORLDS_2008'),
    ('stamp', 'WORLDS-2009', NULL, 'EVENT_WORLDS_2009'),
    ('stamp', 'WORLDS-2010', NULL, 'EVENT_WORLDS_2010'),
    ('stamp', 'WORLDS-2023', NULL, 'EVENT_WORLDS_2023'),
    ('stamp', 'WORLDS-2024', NULL, 'EVENT_WORLDS_2024'),
    ('stamp', 'WORLDS-2025', NULL, 'EVENT_WORLDS_2025'),
    ('stamp', 'FINALIST', NULL, 'PLACEMENT_FINALIST'),
    ('stamp', 'QUARTER-FINALIST', NULL, 'PLACEMENT_QUARTER_FINALIST'),
    ('stamp', 'SEMI-FINALIST', NULL, 'PLACEMENT_SEMI_FINALIST'),
    ('stamp', 'TOP-SIXTEEN', NULL, 'PLACEMENT_TOP_16'),
    ('stamp', 'TOP-THIRTY-TWO', NULL, 'PLACEMENT_TOP_32'),
    ('stamp', 'TOP-EIGHT', NULL, 'PLACEMENT_TOP_8'),
    ('stamp', 'WINNER', NULL, 'PLACEMENT_WINNER'),
    ('stamp', 'LEAGUE', NULL, 'PROGRAM_LEAGUE'),
    ('stamp', 'POKE-BALL-LEAGUE', NULL, 'PROGRAM_LEAGUE_POKE_BALL'),
    ('stamp', 'ULTRA-BALL-LEAGUE', NULL, 'PROGRAM_LEAGUE_ULTRA_BALL'),
    ('stamp', 'PLAYER-REWARDS-PROGRAM', NULL, 'PROGRAM_PLAYER_REWARDS'),
    ('stamp', 'PLAYER-REWARD', NULL, 'PROGRAM_PLAYER_REWARDS'),
    ('stamp', 'PROFESSOR-PROGRAM', NULL, 'PROGRAM_PROFESSOR'),
    ('stamp', 'STAFF', NULL, 'ROLE_STAFF');

-- ---------------------------------------------------------------- PASSO 1 ---
DO $$
DECLARE v_n INT; v_g INT; v_s INT; v_dup INT; v_orf TEXT; v_bad INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM seed_ec_map;
    IF v_n <> 122 THEN RAISE EXCEPTION 'SEED_MAP_COUNT: esperado 122, obtido %.', v_n; END IF;

    -- M3 — ZERO mapping de foil/type/size. Dominio fechado.
    SELECT COUNT(*) INTO v_bad FROM seed_ec_map WHERE raw_field NOT IN ('stamp','subtype');
    IF v_bad <> 0 THEN RAISE EXCEPTION 'SEED_MAP_RAW_FIELD_FORBIDDEN: % linhas fora de stamp/subtype.', v_bad; END IF;

    SELECT COUNT(*) FILTER (WHERE external_set_id IS NULL),
           COUNT(*) FILTER (WHERE external_set_id IS NOT NULL) INTO v_g, v_s FROM seed_ec_map;
    IF v_g <> 108 OR v_s <> 14 THEN
        RAISE EXCEPTION 'SEED_MAP_SCOPE_SPLIT: esperado 108 GLOBAL / 14 SCOPED, obtido % / %.', v_g, v_s; END IF;

    -- H2 — set-logo NUNCA global, e somente nos tres Sets documentados.
    IF EXISTS (SELECT 1 FROM seed_ec_map WHERE normalized_token='SET-LOGO' AND external_set_id IS NULL) THEN
        RAISE EXCEPTION 'SEED_MAP_SET_LOGO_GLOBAL (H2): set-logo nao pode ser GLOBAL.'; END IF;
    IF EXISTS (SELECT 1 FROM seed_ec_map WHERE normalized_token='SET-LOGO'
                AND external_set_id NOT IN ('dp1','swsh9','svp')) THEN
        RAISE EXCEPTION 'SEED_MAP_SET_LOGO_SCOPE (H2): Set fora de dp1/swsh9/svp.'; END IF;

    -- chave unica por (raw_field, token, escopo).
    SELECT COUNT(*) INTO v_dup FROM (
        SELECT raw_field, normalized_token, COALESCE(external_set_id,'~') e
          FROM seed_ec_map GROUP BY 1,2,3 HAVING COUNT(*)>1) d;
    IF v_dup <> 0 THEN RAISE EXCEPTION 'SEED_MAP_DUPLICATE: % chaves repetidas.', v_dup; END IF;

    SELECT string_agg(DISTINCT trait_code, ', ') INTO v_orf FROM seed_ec_map s
     WHERE NOT EXISTS (SELECT 1 FROM public.card_edition_context_trait t WHERE t.code = s.trait_code);
    IF v_orf IS NOT NULL THEN RAISE EXCEPTION 'SEED_MAP_TRAIT_ORPHAN: %.', v_orf; END IF;

    -- escopo declarado tem Set real na fonte.
    SELECT string_agg(DISTINCT external_set_id, ', ') INTO v_orf FROM seed_ec_map s
     WHERE s.external_set_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.card_set_external_reference r
          JOIN public.asset_source a ON a.id=r.asset_source_id AND a.code='TCGDEX'
         WHERE r.external_set_id = s.external_set_id);
    IF v_orf IS NOT NULL THEN RAISE EXCEPTION 'SEED_MAP_SET_UNKNOWN: %.', v_orf; END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- CORRIGIDO EM MAPPING-LIFECYCLE-CORRECTION-01.
--
-- A 2207 v3.0 admite HISTÓRICO: o mesmo token pode ter N linhas inativas +
-- no máximo 1 ativa. O JOIN da versão anterior casava por
-- (raw_field, normalized_token, external_set_id) e NÃO filtrava is_active —
-- sob histórico ele associaria os traits a TODOS os mappings daquele token,
-- inclusive os INATIVOS e SELADOS. Resultado determinístico: o GUARD B da
-- 2207 abortaria com EDITION_CONTEXT_MAPPING_COMPOSITION_SEALED. O seed
-- falharia — fail-loud, mas por defeito próprio, não por dado ruim.
--
-- Além disso `mm.game_id` não era amarrado a nada: o JOIN dependia de existir
-- um único Game. Passa a ser explícito.
--
-- Contrato desta seed: ela opera SOBRE O MAPPING ATIVO que ela mesma acabou
-- de criar ou reconhecer — nunca sobre histórico. Determinístico porque
-- uq_cecem_active_global / uq_cecem_active_scoped garantem no máximo UM ativo
-- por identidade: o JOIN abaixo não tem como casar duas linhas.
WITH ctx AS (
    SELECT (SELECT id FROM public.game         WHERE code = 'POKEMON') AS game_id,
           (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')  AS asset_source_id
)
INSERT INTO public.card_edition_context_external_mapping
    (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
SELECT c.game_id, c.asset_source_id, s.external_set_id, s.raw_field, s.normalized_token
  FROM seed_ec_map s CROSS JOIN ctx c;

INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
SELECT mm.id, t.id, mm.game_id
  FROM seed_ec_map s
  CROSS JOIN LATERAL (
      SELECT (SELECT id FROM public.game         WHERE code = 'POKEMON') AS game_id,
             (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')  AS asset_source_id
  ) c
  JOIN public.card_edition_context_external_mapping mm
    ON  mm.game_id         = c.game_id
    AND mm.asset_source_id = c.asset_source_id
    AND mm.raw_field       = s.raw_field
    AND mm.normalized_token = s.normalized_token
    AND mm.external_set_id IS NOT DISTINCT FROM s.external_set_id
    AND mm.is_active                      -- << nunca tocar histórico selado
  JOIN public.card_edition_context_trait t
    ON t.code = s.trait_code AND t.game_id = mm.game_id;

-- ---------------------------------------------------------------- PASSO 3 ---
-- FORÇA O SELO DEFERIDO A DISPARAR AGORA (BATCH1-RUNTIME-CORRECTION-02).
-- trg_cecem_seal (2207 v2.0) é CONSTRAINT TRIGGER DEFERRABLE INITIALLY
-- DEFERRED. Sem esta linha, os gates M4/M5 abaixo leriam traits_signature
-- ainda NULL nos 122 e o seed passaria por engano OU abortaria por engano,
-- dependendo do gate. Mesma nota da 2231, PASSO 3.
-- Se qualquer mapping estiver sem vínculo,
-- EDITION_CONTEXT_EXTERNAL_MAPPING_EMPTY_COMPOSITION aborta AQUI.
SET CONSTRAINTS ALL IMMEDIATE;

-- C1/C3 — COBERTURA DO CORPUS CANONICO: as 1.085 rows EDITION_CONTEXT.
DO $$
DECLARE v_n INT; v_foil INT; v_desc TEXT; v_null INT; v_mis INT; v_dup INT;
BEGIN
    -- CONTAGEM SOBRE OS ATIVOS (MAPPING-LIFECYCLE-CORRECTION-01). A 2207 v3.0
    -- admite histórico inativo; o corpus canônico são os 122 ATIVOS. Contar
    -- todas as linhas passaria a medir "ativos + histórico", que não é o
    -- contrato desta seed.
    SELECT COUNT(*) INTO v_n FROM public.card_edition_context_external_mapping
     WHERE is_active;
    IF v_n <> 122 THEN RAISE EXCEPTION 'SEED_MAP_POSTCHECK: esperado 122 ativos, obtido %.', v_n; END IF;

    -- M6 (NOVO) — no máximo UM ativo por identidade, nos dois escopos.
    -- Redundante com uq_cecem_active_global / uq_cecem_active_scoped, e é
    -- essa redundância que se quer: se o índice não existir (DDL incompleto),
    -- o seed detecta aqui em vez de deixar passar.
    SELECT COUNT(*) INTO v_dup FROM (
        SELECT game_id, asset_source_id, raw_field, normalized_token, external_set_id
          FROM public.card_edition_context_external_mapping
         WHERE is_active
         GROUP BY 1,2,3,4,5 HAVING COUNT(*) > 1) d;
    IF v_dup <> 0 THEN
        RAISE EXCEPTION 'SEED_MAP_MULTIPLE_ACTIVE (M6): % identidades com mais de um mapping ativo.', v_dup;
    END IF;

    -- M4 (NOVO, BATCH1-RUNTIME-CORRECTION-02) — 122/122 SELADOS.
    -- É este gate que impede a divergência SQL x Edge: a Edge lê SOMENTE
    -- mapping.traits_signature e trata NULL como composicao vazia
    -- (NEEDS_REVIEW_INVALID_EC_MAPPING). Um unico NULL aqui significa que
    -- aquele mapping resolveria no SQL e falharia na Edge.
    --
    -- ESCOPO DELIBERADO: M4 e M5 varrem TODAS as linhas, ativas E inativas —
    -- NAO filtrar por is_active aqui. Um mapping historico continua selado, e
    -- seu selo continua tendo que corresponder a sua propria N:N. Restringir
    -- a is_active enfraqueceria a invariante sem ganho nenhum. Apenas a
    -- CONTAGEM de 122 (acima) e M6 e que sao sobre os ativos.
    SELECT COUNT(*) INTO v_null FROM public.card_edition_context_external_mapping
     WHERE traits_signature IS NULL;
    IF v_null <> 0 THEN
        RAISE EXCEPTION 'SEED_MAP_SIGNATURE_UNSEALED (M4): % mappings sem selo. A Edge os leria como composicao vazia.', v_null;
    END IF;

    -- M5 (NOVO) — o selo corresponde EXATAMENTE a N:N, para os 122.
    -- Garante que SQL (2211) e Edge recebem a MESMA composicao: a 2211 faz
    -- COALESCE(traits_signature, ARRAY(SELECT ... FROM N:N ORDER BY trait_id))
    -- e a Edge le traits_signature. Se os dois lados sao identicos, os dois
    -- caminhos sao equivalentes por construcao.
    SELECT COUNT(*) INTO v_mis
      FROM public.card_edition_context_external_mapping m
     WHERE m.traits_signature IS DISTINCT FROM ARRAY(
             SELECT t.trait_id FROM public.card_edition_context_external_mapping_trait t
              WHERE t.mapping_id = m.id ORDER BY t.trait_id);
    IF v_mis <> 0 THEN
        RAISE EXCEPTION 'SEED_MAP_SIGNATURE_MISMATCH_NN (M5): % mappings com selo divergente da N:N.', v_mis;
    END IF;

    -- M3 no BANCO: zero mapping de foil (reforca ck_cecem_raw_field).
    SELECT COUNT(*) INTO v_foil FROM public.card_edition_context_external_mapping
     WHERE raw_field NOT IN ('stamp','subtype');
    IF v_foil <> 0 THEN RAISE EXCEPTION 'SEED_MAP_FOIL_PRESENT: %.', v_foil; END IF;

    -- C1 — todo token do corpus EC tem mapping aplicavel.
    -- HOLD: PIKACHU-TAIL fica FORA por decisao versionada (SOURCE_CONTRADICTION,
    -- BASEP). Ele NAO pertence ao corpus EC e por isso nao aparece aqui.
    WITH a AS (
      SELECT cs.code AS set_code, r.raw_data, sig.residual_foil, sig.residual_subtype, sig.residual_stamp
        FROM public.catalog_variant_import_row r
        JOIN public.catalog_variant_import_job j ON j.id=r.job_id
        JOIN public.card_set cs ON cs.id=j.card_set_id
        JOIN public.expansion e ON e.id=cs.expansion_id
        JOIN public.asset_source s2 ON s2.code=j.source
        CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data,e.game_id,s2.id) sig
       WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
         AND r.persistence_status='PENDING' AND r.validation_status='NEEDS_REVIEW'),
    ec AS (SELECT * FROM a
       WHERE NOT COALESCE(residual_foil IN ('LEAGUE','PLAYER-REWARD','PROFESSOR-PROGRAM'),FALSE)
         AND NOT ('SET-LOGO'=ANY(COALESCE(residual_stamp,'{}')) AND set_code NOT IN ('DP1','SWSH9','SVP'))
         AND NOT (residual_subtype IS NULL AND cardinality(COALESCE(residual_stamp,'{}'))=0 AND residual_foil IS NOT NULL)
         AND NOT COALESCE(residual_subtype IN ('NO-E-READER','MISSING-EXPANSION-SYMBOL','JAPANESE-BACK',
             'NO-HOLO-ERROR','PHANPHY-ERROR','RARITY-ERROR','D-INK-DOT-ERROR','ENERGY-SYMBOL-ERROR',
             'MISSING-RETREAT-COST','SHIFTED-ENERGY-COST','TEXT-ERROR','PEELABLE-DITTO'),FALSE)
         AND NOT ('1ST-EDITION-SCRATCH-ERROR'=ANY(COALESCE(residual_stamp,'{}')))
         AND NOT ('D-EDITION-ERROR'=ANY(COALESCE(residual_stamp,'{}')))
         AND NOT ('PIKACHU-TAIL'=ANY(COALESCE(residual_stamp,'{}')))),
    tok AS (
      SELECT set_code,'subtype'::TEXT rf, residual_subtype t FROM ec WHERE residual_subtype IS NOT NULL
      UNION ALL SELECT set_code,'stamp', x FROM ec, LATERAL unnest(COALESCE(residual_stamp,'{}'::TEXT[])) x)
    SELECT string_agg(DISTINCT k.rf||':'||k.t, ', ') INTO v_desc
      FROM tok k
     WHERE NOT EXISTS (
        SELECT 1 FROM public.card_edition_context_external_mapping mm
          LEFT JOIN public.card_set_external_reference r2 ON r2.external_set_id = mm.external_set_id
          LEFT JOIN public.card_set cs2 ON cs2.id = r2.card_set_id
         WHERE mm.raw_field = k.rf AND mm.normalized_token = k.t AND mm.is_active
           AND (mm.external_set_id IS NULL OR cs2.code = k.set_code));
    IF v_desc IS NOT NULL THEN
        RAISE EXCEPTION 'SEED_EC_COVERAGE_GAP (C1): tokens do corpus sem mapping aplicavel: %.', v_desc; END IF;

    RAISE NOTICE 'SEED 2232 OK — 122 mappings SELADOS (M4/M5), 1.085/1.085 rows EC cobertas, zero foil, H2 intacto.';
END $$;

-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
COMMIT;
