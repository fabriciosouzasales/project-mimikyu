-- ===========================================================================
-- Query 2842 — CLASSIFICADOR SEMÂNTICO DAS 1.642 (read-only)
-- v2.0 — PARTIÇÃO VERSIONADA + RESÍDUO CLASSIFICADO POR EVIDÊNCIA.
--        GATE DE RECONCILIAÇÃO **NÃO FECHA**. STOP com unidades nominais.
-- ===========================================================================
-- Mandato: EDITION-CONTEXT-AXIS-SEMANTIC-PARTITION-EVIDENCE-02
--
-- ---------------------------------------------------------------------------
-- O QUE MUDOU DA v1.0 PARA A v2.0
-- ---------------------------------------------------------------------------
-- 1. REMOVIDA a seção "RESTRIÇÃO ADICIONAL DESCOBERTA" (111 − 94 = 17 tokens).
--    Ela era uma premissa normativa indevida. Token externo NÃO é
--    necessariamente 1:1 com trait canônico: um trait pode ser alimentado por
--    mais de um token de origem, e um token pode não virar trait nenhum. A
--    aritmética 111/94/17 não restringe nada e não volta a aparecer aqui.
--
-- 2. As regras deixam de ser heurísticas de forma (`LIKE '%ERROR%'`,
--    "subtype não-nulo") e passam a ser ÂNCORAS DOCUMENTAIS NOMINAIS. As
--    regras R3/R4 da v1.0 foram REMOVIDAS — não tinham âncora.
--
-- 3. O `set-logo` residual (9 rows fora de EX7–EX10) deixa de ser bloco único:
--    é provado por row/Set (RECORTE 2).
--
-- 4. O resíduo passa a ser classificado por UNIDADE DE EVIDÊNCIA
--    `(raw_field, normalized_token)` — RECORTE 4 — e o que não tem evidência
--    é devolvido nominalmente, não absorvido por fallback.
--
-- ---------------------------------------------------------------------------
-- RESULTADO MEDIDO — LEIA ANTES DE USAR
-- ---------------------------------------------------------------------------
--   | Grupo           |  Alvo | Classificado por evidência |    Δ |
--   |-----------------|------:|---------------------------:|-----:|
--   | FINISH          |   442 |                        420 |  −22 |
--   | PRINTING        |    70 |                          0 |  −70 |
--   | EDITION_CONTEXT | 1.069 |                        807 | −262 |
--   | INDETERMINATE   |    61 |                     **61** |  **0** ✅
--   | NÃO RESOLVIDO   |     — |                        354 |      |
--   | TOTAL           | 1.642 |                      1.642 |    0 |
--
-- INDETERMINATE fecha EXATAMENTE (57 + 4 = 61) — e fecha por evidência
-- independente, não por aritmética: os 57 vêm do HOLD-MANIFEST H3 e os 4 vêm
-- do RECORTE 2 abaixo, cada um com Set nominal. Nenhum dos dois foi calibrado.
--
-- Os outros três grupos NÃO fecham, e a diferença (22 + 70 + 262 = 354) é
-- exatamente o conjunto de rows cujas unidades de evidência não têm destino
-- em nenhum artefato versionado. Elas estão listadas uma a uma no RECORTE 4,
-- classe `C_SEM_ANCORA`. Conforme o mandato, **nenhuma regra foi inventada
-- para cobrir essa diferença**.
--
-- ---------------------------------------------------------------------------
-- A LACUNA ESTRUTURAL PERMANECE: PRINTING = 0
-- ---------------------------------------------------------------------------
-- O eixo de Impressão roda ANTES do eixo 3 (`2176`, depois `2211`). Token com
-- mapping de Printing ATIVO é consumido e sai do residual. Medido no LIVE:
-- das 1.642, **1.641 têm `printing_state = RESOLVED_NO_PRINTING`** e 1 tem
-- `RESOLVED_WITH_PROFILE`.
--
-- Para existirem 70 linhas de natureza PRINTING neste universo, o critério
-- original teve de classificar como tiragem tokens **sem mapping de Impressão**
-- — decisão editorial que não está em nenhum artefato. O dado não distingue
-- "token de tiragem sem mapping" de "token de contexto sem mapping".
--
-- A v1.0 registrou que PRE-RELEASE 49 + WINNER 19 + W-PROMO 1 +
-- 1ST-EDITION-SCRATCH-ERROR 1 = 70 exato. Isso continua sendo **coincidência
-- aritmética sem âncora**, e por isso NÃO virou regra aqui. Anotação adicional
-- da v2.0: `W-PROMO` tem destino EDITION_CONTEXT já aprovado
-- (`CHANNEL_WOTC_PROMO`, MIGRATION-MAP-365), o que enfraquece a combinação —
-- mais uma razão para não adotá-la.
--
-- ---------------------------------------------------------------------------
-- GARANTIA DE LEITURA
-- ---------------------------------------------------------------------------
-- SELECTs e CTEs apenas. Zero DML · DDL · DO · TEMP · CALL · SELECT-INTO.
-- BEGIN/ROLLBACK preservados, zero COMMIT. Mesmo preflight da `2841` v2.0.
-- ===========================================================================

BEGIN;

-- ===========================================================================
-- RECORTE 1 — PARTIÇÃO VERSIONADA, LINHA A LINHA
-- ===========================================================================
-- Cinco regras, cada uma com âncora documental nominal. Precedência total e
-- declarada. O que nenhuma regra alcança sai como `C_SEM_ANCORA` — que NÃO é
-- uma natureza, é a confissão de que a evidência acabou ali.
--
--  V1  foil-programa .............. 57 → INDETERMINATE   HOLD-MANIFEST H3 + CHECK 2207
--  V2  set-logo em EX7–EX10 ...... 379 → FINISH          HOLD-MANIFEST H2 + README §7
--  V3A set-logo DP1/SWSH9/SVP ...... 5 → EDITION_CONTEXT README §7
--  V3B set-logo demais Sets ........ 4 → INDETERMINATE   ausência em README §7
--  V4  DECK_PLAYER ............... 709 → EDITION_CONTEXT 2841 R1.A/R3 + slugify.mjs
--  V5  foil-only (não-programa) ... 41 → FINISH          SEED-COVERAGE S7 + MIGRATION-MAP-365
--  V6  token com destino EC no 365  93 → EDITION_CONTEXT MIGRATION-MAP-365
--      C_SEM_ANCORA ............... 354 → (devolvido)
-- ===========================================================================
WITH a AS (
  SELECT r.id AS row_id, cs.code AS set_code, r.raw_data,
         sig.residual_type, sig.residual_foil, sig.residual_subtype,
         sig.residual_stamp, sig.printing_state
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
    JOIN public.card_set   cs ON cs.id = j.card_set_id
    JOIN public.expansion  e  ON e.id  = cs.expansion_id
    JOIN public.asset_source s ON s.code = j.source
    CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, e.game_id, s.id) sig
   WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
     AND r.persistence_status = 'PENDING'
     AND r.validation_status  = 'NEEDS_REVIEW'
),
-- Os 38 tokens DECK_PLAYER. Derivados, não digitados: forma de nome próprio
-- menos o VOCABULÁRIO DE DOMÍNIO explícito (evento, canal, programa,
-- colocação, campanha, erro físico). A forma só encurta a lista; o que exclui
-- é a lista nominal abaixo, que é decisão editorial já registrada.
dp_tokens AS (
  SELECT DISTINCT x AS token
    FROM a, LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) x
   WHERE x ~* '^[a-z]+(-[a-z]+)+$' AND x !~ '[0-9]'
     AND x NOT IN ('SET-LOGO','PRE-RELEASE','NO-E-READER','COUNTDOWN-CALENDAR',
     'MISSING-EXPANSION-SYMBOL','NATIONAL-CHAMPIONSHIPS','STATE-CHAMPIONSHIPS',
     'CITY-CHAMPIONSHIPS','REGIONAL-CHAMPIONSHIPS','BLUE-BORDER','COMIC-CON',
     'QUARTER-FINALIST','SEMI-FINALIST','TOP-SIXTEEN','TOP-THIRTY-TWO','TRICK-OR-TRADE',
     'PLAYER-REWARDS-PROGRAM','POP-TOURNAMENT','THANK-YOU','PEELABLE-DITTO','ASIA-PROMO',
     'DISTRIBUTOR-MEETING','GEN-CON','STADIUM-CHALLENGE','JAPANESE-BACK','NO-HOLO-ERROR',
     'PHANPHY-ERROR','RARITY-ERROR','D-EDITION-ERROR','DESTINY-DEOXYS','EB-GAMES',
     'GAMES-EXPO','INQUEST-GAMER','KRAZE-CLUB','NINTENDO-WORLD','PIKACHU-TAIL',
     'POKE-BALL-LEAGUE','POKEMON-ROCKS-AMERICA','PROFESSOR-PROGRAM','W-PROMO',
     'WIZARD-WORLD-CHICAGO','WIZARD-WORLD-PHILADELPHIA','D-INK-DOT-ERROR',
     'ENERGY-SYMBOL-ERROR','GOLD-BORDER','MISSING-RETREAT-COST','SHIFTED-ENERGY-COST',
     'TEXT-ERROR','POKEMON-DAY','10TH-ANNIVERSARY')
),
-- Tokens cujo destino EDITION_CONTEXT já está APROVADO em MIGRATION-MAP-365.
-- Cada um aparece lá com um `code` de destino nominal. Não é inferência por
-- substring: é a MESMA grafia de origem, com destino já decidido para o
-- universo B, aplicada ao universo A.
anchor_ec AS (
  SELECT * FROM (VALUES
    ('STAFF',                  'ROLE_STAFF'),
    ('REGIONAL-CHAMPIONSHIPS', 'EVENT_REGIONALS'),
    ('PLAYER-REWARDS-PROGRAM', 'PROGRAM_PLAYER_REWARDS'),
    ('GAMESTOP',               'CHANNEL_GAMESTOP'),
    ('EB-GAMES',               'CHANNEL_EB_GAMES'),
    ('W-PROMO',                'CHANNEL_WOTC_PROMO'),
    ('PROFESSOR-PROGRAM',      'PROGRAM_PROFESSOR'),
    ('WORLDS-2004',            'EVENT_WORLDS_2004'),
    ('WORLDS-2005',            'EVENT_WORLDS_2005'),
    ('WORLDS-2007',            'EVENT_WORLDS_2007'),
    ('WORLDS-2008',            'EVENT_WORLDS_2008'),
    ('WORLDS-2009',            'EVENT_WORLDS_2009'),
    ('WORLDS-2010',            'EVENT_WORLDS_2010'),
    ('TOP-SIXTEEN',            'PLACEMENT_*'),
    ('TOP-THIRTY-TWO',         'PLACEMENT_*'),
    ('SEMI-FINALIST',          'PLACEMENT_*'),
    ('QUARTER-FINALIST',       'PLACEMENT_*'),
    ('FINALIST',               'PLACEMENT_*')
  ) AS t(token, destino)
),
cls AS (
  SELECT a.*,
    CASE
      WHEN COALESCE(a.residual_foil IN ('LEAGUE','PLAYER-REWARD','PROFESSOR-PROGRAM'), FALSE)
        THEN 'V1_FOIL_PROGRAMA'
      WHEN 'SET-LOGO' = ANY(COALESCE(a.residual_stamp,'{}'))
           AND a.set_code IN ('EX7','EX8','EX9','EX10')        THEN 'V2_SET_LOGO_EX_ERA'
      WHEN 'SET-LOGO' = ANY(COALESCE(a.residual_stamp,'{}'))
           AND a.set_code IN ('DP1','SWSH9','SVP')             THEN 'V3A_SET_LOGO_DOCUMENTADO'
      WHEN 'SET-LOGO' = ANY(COALESCE(a.residual_stamp,'{}'))   THEN 'V3B_SET_LOGO_SEM_DOC'
      WHEN EXISTS (SELECT 1 FROM LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) t
                    WHERE t IN (SELECT token FROM dp_tokens))  THEN 'V4_DECK_PLAYER'
      WHEN a.residual_subtype IS NULL
           AND cardinality(COALESCE(a.residual_stamp,'{}')) = 0
           AND a.residual_foil IS NOT NULL                     THEN 'V5_FOIL_ONLY'
      WHEN EXISTS (SELECT 1 FROM LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) t
                    WHERE t IN (SELECT token FROM anchor_ec))  THEN 'V6_EC_ANCORADO_365'
      ELSE 'C_SEM_ANCORA'
    END AS reason_code
  FROM a
)
SELECT
  cls.row_id,
  cls.set_code,
  COALESCE(cls.residual_type,'')  || '|' || COALESCE(cls.residual_foil,'')  || '|' ||
  COALESCE(cls.residual_subtype,'') || '|' ||
  COALESCE(array_to_string(cls.residual_stamp,'+'),'')                  AS raw_signature,
  CASE cls.reason_code
    WHEN 'V1_FOIL_PROGRAMA'          THEN 'INDETERMINATE'
    WHEN 'V2_SET_LOGO_EX_ERA'        THEN 'FINISH'
    WHEN 'V3A_SET_LOGO_DOCUMENTADO'  THEN 'EDITION_CONTEXT'
    WHEN 'V3B_SET_LOGO_SEM_DOC'      THEN 'INDETERMINATE'
    WHEN 'V4_DECK_PLAYER'            THEN 'EDITION_CONTEXT'
    WHEN 'V5_FOIL_ONLY'              THEN 'FINISH'
    WHEN 'V6_EC_ANCORADO_365'        THEN 'EDITION_CONTEXT'
    ELSE                                  '(NAO RESOLVIDO)'
  END                                                                   AS natureza,
  cls.reason_code,
  CASE cls.reason_code
    WHEN 'V1_FOIL_PROGRAMA'
      THEN 'HOLD-MANIFEST H3: foil in (LEAGUE,PLAYER-REWARD,PROFESSOR-PROGRAM). '
           || 'raw_field=foil esta fora do CHECK de 2207 (blocker B3), logo nenhum '
           || 'mapping de Edition Context pode ser semeado para eles — nem por engano.'
    WHEN 'V2_SET_LOGO_EX_ERA'
      THEN 'HOLD-MANIFEST H2 + README secao 7: reverse+set-logo em EX7(95) EX8(95) '
           || 'EX9(89) EX10(100)=379 pertencem ao eixo FINISH; alvo canonico e da '
           || 'frente SET-LOGO-EX-ERA-FINISH-01. Edition Context nao as absorve.'
    WHEN 'V3A_SET_LOGO_DOCUMENTADO'
      THEN 'README secao 7: "DP1 / SWSH9 / SVP (44 materializadas + 5 staging): '
           || 'documentados -> EDITION_CONTEXT, dentro do escopo". Corroborado pelo '
           || 'guard H2 de 2232: set-logo so tem mapping escopado a dp1/swsh9/svp.'
    WHEN 'V3B_SET_LOGO_SEM_DOC'
      THEN 'Set fora da lista documentada do README secao 7 e fora do guard H2 de '
           || '2232 — nenhum mapping de set-logo pode existir para este Set. Sem '
           || 'documentacao fisica, permanece UNKNOWN/HOLD.'
    WHEN 'V4_DECK_PLAYER'
      THEN 'Token de nome proprio em raw_field=stamp, aridade 1, fora do vocabulario '
           || 'de dominio. 38 tokens / 709 rows, 100% stamp (2841 RECORTE 1.A e 3); '
           || 'os mesmos 38 slugs sem colisao de editorial/slugify.mjs.'
    WHEN 'V5_FOIL_ONLY'
      THEN 'Pendencia residual e exclusivamente raw_field=foil. SEED-COVERAGE S7: '
           || 'mapping de Edition Context aceita apenas raw_field in (stamp,subtype); '
           || 'foil e impossivel por CHECK. MIGRATION-MAP-365 confirma que token de '
           || 'foil e vocabulario de Finish (COSMOS -> COSMOS_HOLO/COSMOS_REVERSE).'
    WHEN 'V6_EC_ANCORADO_365'
      THEN 'Token possui destino EDITION_CONTEXT ja aprovado em MIGRATION-MAP-365, '
           || 'com a mesma grafia de origem. Ver coluna destino_ec do RECORTE 4.'
    ELSE 'SEM ANCORA. Nenhum artefato versionado decide o eixo deste token. '
         || 'Devolvido nominalmente no RECORTE 4 — NAO absorvido por fallback.'
  END                                                                   AS evidencia,
  CASE cls.reason_code
    WHEN 'C_SEM_ANCORA' THEN 'NENHUMA'
    WHEN 'V4_DECK_PLAYER' THEN 'ALTA'
    ELSE 'ALTA'
  END                                                                   AS confidence,
  cls.printing_state
FROM cls
ORDER BY cls.reason_code, cls.set_code, cls.row_id;


-- ===========================================================================
-- RECORTE 2 — SET-LOGO RESIDUAL: PROVA POR ROW E POR SET
-- ===========================================================================
-- Correção obrigatória 2 do mandato: as 9 rows fora de EX7–EX10 NÃO podem ser
-- classificadas em bloco. Abaixo, cada uma com `row_id`, Set e a linha de
-- documentação que decide seu destino.
--
-- MEDIDO NO LIVE (read-only), 9 rows, todas com assinatura `REVERSE|||SET-LOGO`:
--
--   | Set    | rows | Evidência                                  | Natureza        |
--   |--------|-----:|--------------------------------------------|-----------------|
--   | DP1    |    4 | README §7 — documentado, dentro do escopo   | EDITION_CONTEXT |
--   | SWSH9  |    1 | README §7 — documentado, dentro do escopo   | EDITION_CONTEXT |
--   | SV3    |    2 | ausente do README §7 e do guard H2 de 2232  | INDETERMINATE   |
--   | SV4    |    2 | ausente do README §7 e do guard H2 de 2232  | INDETERMINATE   |
--
--   Σ documentadas = 5   ·   Σ sem documentação = 4
--
-- A soma 5 bate exatamente com o "+ 5 staging" que o README §7 escreve ao lado
-- de "44 materializadas" para DP1 · SWSH9 · SVP — e os Sets medidos são os
-- mesmos (SVP não tem staging pendente). Isto é CONFIRMAÇÃO da evidência
-- textual pelo dado, não fechamento aritmético: o critério é "consta ou não
-- consta do README §7", e ele foi aplicado Set a Set antes de somar.
-- ===========================================================================
WITH a AS (
  SELECT r.id AS row_id, cs.code AS set_code, r.raw_data,
         sig.residual_type, sig.residual_foil, sig.residual_subtype, sig.residual_stamp
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
    JOIN public.card_set   cs ON cs.id = j.card_set_id
    JOIN public.expansion  e  ON e.id  = cs.expansion_id
    JOIN public.asset_source s ON s.code = j.source
    CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, e.game_id, s.id) sig
   WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
     AND r.persistence_status = 'PENDING'
     AND r.validation_status  = 'NEEDS_REVIEW'
)
SELECT
  row_id, set_code,
  COALESCE(residual_type,'') || '|' || COALESCE(residual_foil,'') || '|' ||
  COALESCE(residual_subtype,'') || '|' ||
  COALESCE(array_to_string(residual_stamp,'+'),'')                      AS raw_signature,
  raw_data,
  CASE WHEN set_code IN ('DP1','SWSH9','SVP') THEN 'EDITION_CONTEXT'
       ELSE 'INDETERMINATE' END                                         AS natureza,
  CASE WHEN set_code IN ('DP1','SWSH9','SVP') THEN 'V3A_SET_LOGO_DOCUMENTADO'
       ELSE 'V3B_SET_LOGO_SEM_DOC' END                                  AS reason_code,
  CASE WHEN set_code IN ('DP1','SWSH9','SVP')
       THEN 'README secao 7: DP1/SWSH9/SVP (44 materializadas + 5 staging) '
            || 'documentados -> EDITION_CONTEXT, dentro do escopo'
       ELSE 'Set nao consta do README secao 7 nem do guard H2 de 2232 '
            || '(external_set_id in dp1/swsh9/svp) — sem documentacao fisica' END AS evidencia,
  'ALTA'::TEXT                                                          AS confidence
FROM a
WHERE 'SET-LOGO' = ANY(COALESCE(residual_stamp,'{}'))
  AND set_code NOT IN ('EX7','EX8','EX9','EX10')
ORDER BY natureza DESC, set_code, row_id;


-- ===========================================================================
-- RECORTE 3 — GATE DE RECONCILIAÇÃO
-- ===========================================================================
-- Compara o classificado por evidência com o baseline semântico aceito.
-- **NÃO FECHA por desenho.** As rows sem âncora aparecem como grupo próprio —
-- não foram distribuídas entre os grupos para forçar o fechamento.
-- ===========================================================================
WITH a AS (
  SELECT r.id AS row_id, cs.code AS set_code,
         sig.residual_foil, sig.residual_subtype, sig.residual_stamp
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
    JOIN public.card_set   cs ON cs.id = j.card_set_id
    JOIN public.expansion  e  ON e.id  = cs.expansion_id
    JOIN public.asset_source s ON s.code = j.source
    CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, e.game_id, s.id) sig
   WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
     AND r.persistence_status = 'PENDING'
     AND r.validation_status  = 'NEEDS_REVIEW'
),
dp_tokens AS (
  SELECT DISTINCT x AS token
    FROM a, LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) x
   WHERE x ~* '^[a-z]+(-[a-z]+)+$' AND x !~ '[0-9]'
     AND x NOT IN ('SET-LOGO','PRE-RELEASE','NO-E-READER','COUNTDOWN-CALENDAR',
     'MISSING-EXPANSION-SYMBOL','NATIONAL-CHAMPIONSHIPS','STATE-CHAMPIONSHIPS',
     'CITY-CHAMPIONSHIPS','REGIONAL-CHAMPIONSHIPS','BLUE-BORDER','COMIC-CON',
     'QUARTER-FINALIST','SEMI-FINALIST','TOP-SIXTEEN','TOP-THIRTY-TWO','TRICK-OR-TRADE',
     'PLAYER-REWARDS-PROGRAM','POP-TOURNAMENT','THANK-YOU','PEELABLE-DITTO','ASIA-PROMO',
     'DISTRIBUTOR-MEETING','GEN-CON','STADIUM-CHALLENGE','JAPANESE-BACK','NO-HOLO-ERROR',
     'PHANPHY-ERROR','RARITY-ERROR','D-EDITION-ERROR','DESTINY-DEOXYS','EB-GAMES',
     'GAMES-EXPO','INQUEST-GAMER','KRAZE-CLUB','NINTENDO-WORLD','PIKACHU-TAIL',
     'POKE-BALL-LEAGUE','POKEMON-ROCKS-AMERICA','PROFESSOR-PROGRAM','W-PROMO',
     'WIZARD-WORLD-CHICAGO','WIZARD-WORLD-PHILADELPHIA','D-INK-DOT-ERROR',
     'ENERGY-SYMBOL-ERROR','GOLD-BORDER','MISSING-RETREAT-COST','SHIFTED-ENERGY-COST',
     'TEXT-ERROR','POKEMON-DAY','10TH-ANNIVERSARY')
),
anchor_ec AS (
  SELECT unnest(ARRAY['STAFF','REGIONAL-CHAMPIONSHIPS','PLAYER-REWARDS-PROGRAM',
    'GAMESTOP','EB-GAMES','W-PROMO','PROFESSOR-PROGRAM','WORLDS-2004','WORLDS-2005',
    'WORLDS-2007','WORLDS-2008','WORLDS-2009','WORLDS-2010','TOP-SIXTEEN',
    'TOP-THIRTY-TWO','SEMI-FINALIST','QUARTER-FINALIST','FINALIST']) AS token
),
c AS (
  SELECT CASE
    WHEN COALESCE(residual_foil IN ('LEAGUE','PLAYER-REWARD','PROFESSOR-PROGRAM'), FALSE)
      THEN 'INDETERMINATE'
    WHEN 'SET-LOGO' = ANY(COALESCE(residual_stamp,'{}'))
         AND set_code IN ('EX7','EX8','EX9','EX10')            THEN 'FINISH'
    WHEN 'SET-LOGO' = ANY(COALESCE(residual_stamp,'{}'))
         AND set_code IN ('DP1','SWSH9','SVP')                 THEN 'EDITION_CONTEXT'
    WHEN 'SET-LOGO' = ANY(COALESCE(residual_stamp,'{}'))       THEN 'INDETERMINATE'
    WHEN EXISTS (SELECT 1 FROM LATERAL unnest(COALESCE(residual_stamp,'{}'::TEXT[])) t
                  WHERE t IN (SELECT token FROM dp_tokens))    THEN 'EDITION_CONTEXT'
    WHEN residual_subtype IS NULL
         AND cardinality(COALESCE(residual_stamp,'{}')) = 0
         AND residual_foil IS NOT NULL                         THEN 'FINISH'
    WHEN EXISTS (SELECT 1 FROM LATERAL unnest(COALESCE(residual_stamp,'{}'::TEXT[])) t
                  WHERE t IN (SELECT token FROM anchor_ec))    THEN 'EDITION_CONTEXT'
    ELSE 'NAO_RESOLVIDO' END AS natureza
  FROM a
),
m AS (
  SELECT count(*) FILTER (WHERE natureza='FINISH')          AS finish,
         count(*) FILTER (WHERE natureza='PRINTING')        AS printing,
         count(*) FILTER (WHERE natureza='EDITION_CONTEXT') AS edition_context,
         count(*) FILTER (WHERE natureza='INDETERMINATE')   AS indeterminate,
         count(*) FILTER (WHERE natureza='NAO_RESOLVIDO')   AS nao_resolvido,
         count(*)                                           AS total
    FROM c
)
SELECT g.grupo, g.alvo, g.medido, g.medido - g.alvo AS delta,
       (g.medido = g.alvo) AS bate
  FROM m,
  LATERAL (VALUES
    ('1_FINISH',          442,   m.finish),
    ('2_PRINTING',         70,   m.printing),
    ('3_EDITION_CONTEXT',1069,   m.edition_context),
    ('4_INDETERMINATE',    61,   m.indeterminate),
    ('5_NAO_RESOLVIDO',     0,   m.nao_resolvido),
    ('6_TOTAL',          1642,   m.total)
  ) AS g(grupo, alvo, medido)
 ORDER BY g.grupo;


-- ===========================================================================
-- RECORTE 4 — UNIDADES DE EVIDÊNCIA DO RESÍDUO  (objetivo da rodada)
-- ===========================================================================
-- Unidade = `(raw_field, normalized_token)`. O Set entra como dimensão medida
-- (`n_sets`, `sets`), nunca como premissa: nenhuma semântica é assumida global.
--
-- Classes:
--   A_ANCORADO ..... destino já aprovado em artefato versionado → classificado
--   C_SEM_ANCORA ... nenhum artefato decide o eixo → DEVOLVIDO, não absorvido
--
-- As 54 unidades `C_SEM_ANCORA` (354 rows) são o payload do STOP. Elas se
-- agrupam em quatro perfis — descritivos, NÃO regras, porque nenhum deles tem
-- artefato que decida o eixo:
--
--   (a) campanha/canal/evento sem destino escrito ..... 25TH-CELEBRATION 50,
--       MCDONALDS 24, COUNTDOWN-CALENDAR 24, PRE-RELEASE 35, POKEMON-DAY 9,
--       TRICK-OR-TRADE 6, COMIC-CON 5, …
--   (b) colocação/campeonato sem destino escrito ...... CITY/NATIONAL/STATE-
--       CHAMPIONSHIPS 6+6+6, WINNER 19, POP-TOURNAMENT 3, …
--   (c) artwork de estampa (Set MFB) .................. BULBASAUR 12,
--       CHARMANDER 12, PIKACHU 12, SQUIRTLE 12, POKEBALL 8, BLUE-BORDER 8
--   (d) erro/variação física em `subtype` ............. NO-E-READER 41,
--       MISSING-EXPANSION-SYMBOL 16, PEELABLE-DITTO 3, *-ERROR 9, …
--
-- O perfil (d) é o mais provável candidato a FINISH e o perfil (b) a
-- EDITION_CONTEXT — mas "provável" não é evidência, e transformar qualquer um
-- dos quatro em regra seria exatamente a substring-heurística que o mandato
-- proíbe. Por isso saem com `confidence = NENHUMA`.
-- ===========================================================================
WITH a AS (
  SELECT r.id AS row_id, cs.code AS set_code,
         sig.residual_type, sig.residual_foil, sig.residual_subtype, sig.residual_stamp
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
    JOIN public.card_set   cs ON cs.id = j.card_set_id
    JOIN public.expansion  e  ON e.id  = cs.expansion_id
    JOIN public.asset_source s ON s.code = j.source
    CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, e.game_id, s.id) sig
   WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
     AND r.persistence_status = 'PENDING'
     AND r.validation_status  = 'NEEDS_REVIEW'
),
dp_tokens AS (
  SELECT DISTINCT x AS token
    FROM a, LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) x
   WHERE x ~* '^[a-z]+(-[a-z]+)+$' AND x !~ '[0-9]'
     AND x NOT IN ('SET-LOGO','PRE-RELEASE','NO-E-READER','COUNTDOWN-CALENDAR',
     'MISSING-EXPANSION-SYMBOL','NATIONAL-CHAMPIONSHIPS','STATE-CHAMPIONSHIPS',
     'CITY-CHAMPIONSHIPS','REGIONAL-CHAMPIONSHIPS','BLUE-BORDER','COMIC-CON',
     'QUARTER-FINALIST','SEMI-FINALIST','TOP-SIXTEEN','TOP-THIRTY-TWO','TRICK-OR-TRADE',
     'PLAYER-REWARDS-PROGRAM','POP-TOURNAMENT','THANK-YOU','PEELABLE-DITTO','ASIA-PROMO',
     'DISTRIBUTOR-MEETING','GEN-CON','STADIUM-CHALLENGE','JAPANESE-BACK','NO-HOLO-ERROR',
     'PHANPHY-ERROR','RARITY-ERROR','D-EDITION-ERROR','DESTINY-DEOXYS','EB-GAMES',
     'GAMES-EXPO','INQUEST-GAMER','KRAZE-CLUB','NINTENDO-WORLD','PIKACHU-TAIL',
     'POKE-BALL-LEAGUE','POKEMON-ROCKS-AMERICA','PROFESSOR-PROGRAM','W-PROMO',
     'WIZARD-WORLD-CHICAGO','WIZARD-WORLD-PHILADELPHIA','D-INK-DOT-ERROR',
     'ENERGY-SYMBOL-ERROR','GOLD-BORDER','MISSING-RETREAT-COST','SHIFTED-ENERGY-COST',
     'TEXT-ERROR','POKEMON-DAY','10TH-ANNIVERSARY')
),
anchor_ec AS (
  SELECT * FROM (VALUES
    ('STAFF','ROLE_STAFF'),('REGIONAL-CHAMPIONSHIPS','EVENT_REGIONALS'),
    ('PLAYER-REWARDS-PROGRAM','PROGRAM_PLAYER_REWARDS'),('GAMESTOP','CHANNEL_GAMESTOP'),
    ('EB-GAMES','CHANNEL_EB_GAMES'),('W-PROMO','CHANNEL_WOTC_PROMO'),
    ('PROFESSOR-PROGRAM','PROGRAM_PROFESSOR'),('WORLDS-2004','EVENT_WORLDS_2004'),
    ('WORLDS-2005','EVENT_WORLDS_2005'),('WORLDS-2007','EVENT_WORLDS_2007'),
    ('WORLDS-2008','EVENT_WORLDS_2008'),('WORLDS-2009','EVENT_WORLDS_2009'),
    ('WORLDS-2010','EVENT_WORLDS_2010'),('TOP-SIXTEEN','PLACEMENT_*'),
    ('TOP-THIRTY-TWO','PLACEMENT_*'),('SEMI-FINALIST','PLACEMENT_*'),
    ('QUARTER-FINALIST','PLACEMENT_*'),('FINALIST','PLACEMENT_*')
  ) AS t(token, destino)
),
-- Resíduo = 1.642 menos V1..V4. Fica com 488 rows.
res AS (
  SELECT * FROM a
   WHERE NOT COALESCE(residual_foil IN ('LEAGUE','PLAYER-REWARD','PROFESSOR-PROGRAM'), FALSE)
     AND NOT ('SET-LOGO' = ANY(COALESCE(residual_stamp,'{}')))
     AND NOT EXISTS (SELECT 1 FROM LATERAL unnest(COALESCE(residual_stamp,'{}'::TEXT[])) t
                      WHERE t IN (SELECT token FROM dp_tokens))
),
unidades AS (
  SELECT row_id, set_code, 'subtype'::TEXT AS raw_field, residual_subtype AS token,
         COALESCE(residual_type,'') || '|' || COALESCE(residual_foil,'') || '|' ||
         COALESCE(residual_subtype,'') || '|' ||
         COALESCE(array_to_string(residual_stamp,'+'),'') AS raw_signature
    FROM res WHERE residual_subtype IS NOT NULL
  UNION ALL
  SELECT row_id, set_code, 'stamp', x,
         COALESCE(residual_type,'') || '|' || COALESCE(residual_foil,'') || '|' ||
         COALESCE(residual_subtype,'') || '|' ||
         COALESCE(array_to_string(residual_stamp,'+'),'')
    FROM res, LATERAL unnest(COALESCE(residual_stamp,'{}'::TEXT[])) x
  UNION ALL
  SELECT row_id, set_code, 'foil', residual_foil,
         COALESCE(residual_type,'') || '|' || COALESCE(residual_foil,'') || '|' ||
         COALESCE(residual_subtype,'') || '|' ||
         COALESCE(array_to_string(residual_stamp,'+'),'')
    FROM res WHERE residual_foil IS NOT NULL
)
SELECT
  u.raw_field,
  u.token,
  count(DISTINCT u.row_id)                                   AS rows,
  count(DISTINCT u.set_code)                                 AS n_sets,
  string_agg(DISTINCT u.set_code, ',' ORDER BY u.set_code)   AS sets,
  string_agg(DISTINCT u.raw_signature, ' ; ')                AS raw_signatures,
  CASE WHEN u.raw_field = 'foil'          THEN 'FINISH'
       WHEN ae.token IS NOT NULL          THEN 'EDITION_CONTEXT'
       ELSE '(NAO RESOLVIDO)' END                            AS natureza,
  CASE WHEN u.raw_field = 'foil'          THEN 'ALTA'
       WHEN ae.token IS NOT NULL          THEN 'ALTA'
       ELSE 'NENHUMA' END                                    AS confidence,
  CASE WHEN u.raw_field = 'foil'          THEN 'V5_FOIL_ONLY'
       WHEN ae.token IS NOT NULL          THEN 'V6_EC_ANCORADO_365'
       ELSE 'C_SEM_ANCORA' END                               AS reason_code,
  CASE WHEN u.raw_field = 'foil'
         THEN 'SEED-COVERAGE S7: Edition Context aceita apenas raw_field in '
              || '(stamp,subtype); foil e impossivel por CHECK de 2207. '
              || 'MIGRATION-MAP-365 trata token de foil como vocabulario de Finish.'
       WHEN ae.token IS NOT NULL
         THEN 'MIGRATION-MAP-365, destino aprovado: ' || ae.destino
       ELSE 'Nenhum artefato versionado decide o eixo deste token. '
            || 'Requer decisao editorial nominal.' END        AS evidencia,
  ae.destino                                                  AS destino_ec
FROM unidades u
LEFT JOIN anchor_ec ae ON ae.token = u.token AND u.raw_field = 'stamp'
GROUP BY u.raw_field, u.token, ae.token, ae.destino
ORDER BY (CASE WHEN u.raw_field='foil' OR ae.token IS NOT NULL THEN 0 ELSE 1 END),
         count(DISTINCT u.row_id) DESC, u.token;

ROLLBACK;

-- ===========================================================================
-- STOP — O QUE FALTA, NOMINALMENTE
-- ===========================================================================
-- Conforme o item de RECONCILIAÇÃO FINAL do mandato: o gate não fecha, e o que
-- segue são SOMENTE as unidades divergentes/não resolvidas. Nenhuma regra foi
-- recalibrada para atingir os números.
--
-- FECHOU:
--   · INDETERMINATE = 61  (V1 57 + V3B 4) — exato, por evidência independente.
--
-- NÃO FECHOU — 354 rows em 54 unidades, distribuídas assim pelo alvo:
--   · FINISH ............ faltam  22  (420 de 442)
--   · PRINTING .......... faltam  70  (  0 de  70)
--   · EDITION_CONTEXT ... faltam 262  (807 de 1.069)
--                                ----
--                                 354
--
-- CORREÇÃO (UNRESOLVED-01): a redação anterior desta seção somava grandezas
-- de naturezas diferentes — "74 subtype" + "70 PRINTING" + "280 outras" = 424,
-- e não 354. Os números corretos, com a decomposição disjunta provada, estão
-- em `UNRESOLVED-354-PARTITION.md`. Resumo do que mudou:
--
--   · o grupo de `subtype` tem **82** rows, não 74 (74 era só a parte SEM
--     stamp; as unidades já listadas aqui sempre somaram 82);
--   · o "70" NÃO É UM GRUPO DE ROWS — é o déficit do alvo PRINTING
--     (alvo 70 − medido 0). Não tem pertinência definida;
--   · "280" é o conjunto com stamp, que intersecta o de subtype em 8 rows.
--
--   Partição disjunta e exaustiva (soma 354):
--     P1 subtype puro 73 · P2 subtype+foil 1 · P3 subtype+stamp 8 ·
--     P4 stamp+foil 8 · P5 stamp puro 264
--
-- ---------------------------------------------------------------------------
-- SUPERADO POR `SEMANTIC-PARTITION-DECISIONS-54.md` (FINAL-DECISION-01)
-- ---------------------------------------------------------------------------
-- As 354 rows / 54 unidades foram DECIDIDAS. As duas perguntas abaixo estão
-- respondidas — e a (2) estava mal formulada:
--
--   (1) O eixo de `subtype` de erro/variação impressa É **PRINTING**. Não era
--       pergunta em aberto: o vocabulário de Printing já aprovado no LIVE
--       (`card_printing_trait`, Queries 2169/2201) decide literalmente —
--       `EVOLUTION_BOX_ERROR` é "erro de chapa … variedade de tiragem
--       catalogada", `GLOSSY_STOCK` é "característica de tiragem, NÃO de
--       acabamento". 11 unidades / 70 rows → PRINTING.
--
--   (2) A "regra de PRINTING sem mapping ativo" nunca precisou ser inventada:
--       bastava ler os mappings de Printing existentes em `raw_field=subtype`
--       (SHADOWLESS, UNLIMITED, AOKI-ERROR, EVOLUTION-BOX-ERROR, GLOSSY, …).
--       PRINTING passou de 0 para **72** por precedente puro.
--
-- Resultado das 354: EDITION_CONTEXT 278 · PRINTING 72 · FINISH 3 ·
-- HOLD_EDITORIAL 1. Zero rows com conflito de natureza.
--
-- Reconciliação das 1.642: FINISH 423 (−19) · PRINTING 72 (+2) ·
-- EDITION_CONTEXT 1.085 (+16) · INDETERMINATE 61 (0) · HOLD 1 · TOTAL 1.642.
-- NÃO fecha; ver §4 daquele documento para a atribuição da divergência.
--
-- O texto abaixo é preservado como registro do estado anterior.
-- ---------------------------------------------------------------------------
--
-- Duas decisões de Fabrício destravam o resto. São independentes:
--
-- (1) O EIXO DE `subtype` PARA VARIAÇÃO FÍSICA / ERRO DE IMPRESSÃO.
--     82 rows, 14 unidades (NO-E-READER 41, MISSING-EXPANSION-SYMBOL 16,
--     BLUE-BORDER 8, PEELABLE-DITTO 3, JAPANESE-BACK 2, NO-HOLO-ERROR 2,
--     PHANPHY-ERROR 2, RARITY-ERROR 2, GOLD-BORDER 1, D-INK-DOT-ERROR 1,
--     ENERGY-SYMBOL-ERROR 1, MISSING-RETREAT-COST 1, SHIFTED-ENERGY-COST 1,
--     TEXT-ERROR 1). Destas, 8 (BLUE-BORDER, em MFB) carregam também stamp.
--     `subtype` É elegível a Edition Context (S7), então a resposta NÃO é
--     estrutural: alguém precisa decidir se "erro de impressão" é acabamento
--     (FINISH) ou contexto (EDITION_CONTEXT).
--
-- (2) A REGRA DE PRINTING SEM MAPPING ATIVO.
--     O alvo pede 70 rows. Medido: o conjunto MAIS AMPLO de unidades com
--     semântica plausível de tiragem no não-resolvido soma **68** — nunca 70.
--     A combinação da v1.0 só chegava a 70 porque contava PRE-RELEASE = 49,
--     mas 14 dessas 49 carregam token ancorado e já são EDITION_CONTEXT,
--     sobrando 35; e contava W-PROMO = 1, que tem destino EC aprovado
--     (`CHANNEL_WOTC_PROMO`). A coincidência aritmética está FALSIFICADA.
--     Ver `UNRESOLVED-354-PARTITION.md` §3.
--
-- Sobreposição medida entre (1) e (2): **ZERO**. Nenhuma row candidata a
-- tiragem carrega `subtype`. As duas decisões não competem pelas mesmas rows.
-- ===========================================================================
