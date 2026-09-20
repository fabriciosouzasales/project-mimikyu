-- ===========================================================================
-- Query 2841 — EXTRAÇÃO DO CORPUS EDITORIAL DO EIXO 3
-- v2.0 — ESTRITAMENTE READ-ONLY
-- ===========================================================================
-- Mandato: EDITION-CONTEXT-AXIS-EDITORIAL-CORPUS-EXTRACTION-01-REV01
--
-- ---------------------------------------------------------------------------
-- POR QUE A v1.0 FOI REPROVADA
-- ---------------------------------------------------------------------------
-- O preflight estrito reprovou a v1.0 em duas condições:
--
--   1. `CREATE TEMP VIEW _a_rows` — é criação de objeto, e é DDL. Que seja
--      temporária e desfeita no ROLLBACK não muda a categoria.
--   2. `DO $pre$ … $pre$` — bloco procedural. O conteúdo era inofensivo, mas
--      a condição é sobre a FORMA. Um preflight que aprova um `DO` porque
--      "esse `DO` específico é inofensivo" deixa de ser preflight.
--
-- v2.0 elimina as duas. O arquivo passa a ser SEIS SELECTs e nada mais.
--
-- ---------------------------------------------------------------------------
-- AS DUAS SUBSTITUIÇÕES
-- ---------------------------------------------------------------------------
--   · A TEMP VIEW virou a CTE `a_rows`, REPETIDA em cada recorte que a usa.
--     A duplicação de texto é deliberada e foi autorizada: o custo é uma
--     reavaliação por recorte, e o ganho é que nenhum objeto nasce.
--
--   · A precondição virou EVIDÊNCIA RETORNADA pelo RECORTE 0. Em vez de
--     abortar, ela devolve `true`/`false` numa coluna. Se a função de
--     roteamento não existir, o RECORTE 0 diz isso explicitamente e os
--     recortes seguintes falham no parser — visível, nunca silencioso.
--
-- ---------------------------------------------------------------------------
-- GARANTIA DE LEITURA
-- ---------------------------------------------------------------------------
-- Zero INSERT · UPDATE · DELETE · MERGE · TRUNCATE · CREATE · ALTER · DROP ·
-- GRANT · REVOKE · CALL · SELECT-INTO · DO · SET CONSTRAINTS · SET ROLE.
-- BEGIN/ROLLBACK preservados. Zero COMMIT.
--
-- `internal.compute_variant_residual_signature` é `STABLE` — função de
-- leitura pura, sem efeito colateral.
-- ===========================================================================

BEGIN;

-- ===========================================================================
-- RECORTE 0 — PRECONDIÇÃO COMO EVIDÊNCIA
-- ===========================================================================
-- Substitui o bloco `DO` da v1.0. Não aborta: RELATA. A leitura correta do
-- resultado é responsabilidade de quem executa, e é por isso que este recorte
-- vem primeiro na saída.
-- ===========================================================================
SELECT
    'RECORTE_0_PRECONDICAO'                                                  AS recorte,
    to_regprocedure('internal.compute_variant_residual_signature(jsonb,uuid,uuid)')
        IS NOT NULL                                                          AS fn_residual_existe,
    to_regclass('public.catalog_variant_import_row')  IS NOT NULL            AS tbl_staging_existe,
    to_regclass('public.catalog_variant_import_job')  IS NOT NULL            AS tbl_job_existe,
    to_regclass('public.card_variant')                IS NOT NULL            AS tbl_variant_existe,
    current_database()                                                       AS banco,
    current_user                                                             AS papel,
    now()                                                                    AS medido_em;


-- ===========================================================================
-- RECORTE 1.A — CORPUS DE TOKENS DO UNIVERSO A          >>> DESTRAVA E1 <<<
-- ===========================================================================
-- O residual PÓS-PRINTING é o que sobra para o eixo 3 disputar com Finish.
-- Cada token distinto é UM candidato a trait. A classificação por família e o
-- veredito "isto é contexto de edição" são EDITORIAIS — este recorte entrega
-- o corpus, não a decisão.
-- ===========================================================================
WITH a_rows AS (
    SELECT r.id            AS row_id,
           cs.code         AS set_code,
           sig.residual_subtype,
           sig.residual_stamp,
           sig.printing_state
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
tokens AS (
    SELECT a.set_code, 'subtype'::TEXT AS raw_field, a.residual_subtype AS token
      FROM a_rows a
     WHERE a.residual_subtype IS NOT NULL AND btrim(a.residual_subtype) <> ''
    UNION ALL
    SELECT a.set_code, 'stamp'::TEXT, x
      FROM a_rows a, LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) x
)
SELECT 'RECORTE_1A_TOKENS_A'                                        AS recorte,
       t.raw_field,
       t.token,
       count(*)                                                     AS rows_a,
       count(DISTINCT t.set_code)                                   AS sets_distintos,
       string_agg(DISTINCT t.set_code, ',' ORDER BY t.set_code)      AS sets_observados,
       -- Sinal OBJETIVO de escopo. Token presente em um único Set é candidato
       -- a SOURCE_SET_SCOPED; em vários, candidato a GLOBAL. A decisão
       -- continua editorial — isto é o sinal, não o veredito.
       CASE WHEN count(DISTINCT t.set_code) = 1 THEN 'CANDIDATO_SCOPED'
            ELSE 'CANDIDATO_GLOBAL' END                             AS sinal_escopo
  FROM tokens t
 GROUP BY t.raw_field, t.token
 ORDER BY count(*) DESC, t.raw_field, t.token;


-- ===========================================================================
-- RECORTE 1.B — ASSINATURAS RESIDUAIS COMPLETAS DE A     >>> DESTRAVA E3 <<<
-- ===========================================================================
-- Cada assinatura distinta é um candidato a profile, e o conjunto de tokens
-- que a compõe É a composição exata. Só linhas com Printing TERMINAL entram:
-- com o eixo 1 indeterminado o residual não é confiável.
-- ===========================================================================
WITH a_rows AS (
    SELECT r.id            AS row_id,
           cs.code         AS set_code,
           sig.residual_subtype,
           sig.residual_stamp,
           sig.printing_state
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
SELECT 'RECORTE_1B_ASSINATURAS_A'                                    AS recorte,
       COALESCE(a.residual_subtype,'')                               AS residual_subtype,
       COALESCE(array_to_string(a.residual_stamp,'+'),'')             AS residual_stamp,
       CASE WHEN COALESCE(a.residual_subtype,'') <> '' THEN 1 ELSE 0 END
         + cardinality(COALESCE(a.residual_stamp,'{}'::TEXT[]))       AS aridade,
       count(*)                                                       AS rows_a,
       count(DISTINCT a.set_code)                                     AS sets_distintos,
       string_agg(DISTINCT a.set_code, ',' ORDER BY a.set_code)       AS sets,
       (array_agg(a.row_id ORDER BY a.row_id))[1:3]                   AS exemplos_row_id
  FROM a_rows a
 WHERE a.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
 GROUP BY 2, 3, 4
 ORDER BY count(*) DESC, 2, 3;


-- ===========================================================================
-- RECORTE 2 — UNIVERSO B: as legacy READY_STRUCTURAL
-- ===========================================================================
-- B tem 100% de lineage (`resulting_variant_id`), então o `raw_data` original
-- é alcançável. O `code` do Variant Type legado é CONTAMINADO e NÃO é fonte
-- semântica — aparece aqui só como rastro, jamais como origem do trait.
-- ===========================================================================
SELECT 'RECORTE_2_UNIVERSO_B'                                        AS recorte,
       cvt.code                                                      AS legacy_variant_type_contaminado,
       count(*)                                                      AS rows_b,
       count(DISTINCT cs.code)                                       AS sets_distintos,
       string_agg(DISTINCT cs.code, ',' ORDER BY cs.code)            AS sets,
       (array_agg(r.raw_data ORDER BY r.id))[1]                      AS exemplo_raw_data,
       (array_agg(r.id ORDER BY r.id))[1:3]                          AS exemplos_row_id
  FROM public.card_variant cv
  JOIN public.card_variant_type cvt ON cvt.id = cv.variant_type_id
  JOIN public.card c   ON c.id  = cv.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
  JOIN public.catalog_variant_import_row r ON r.resulting_variant_id = cv.id
 WHERE cv.printing_profile_id IS NULL
 GROUP BY cvt.code
 ORDER BY count(*) DESC, cvt.code;


-- ===========================================================================
-- RECORTE 3 — CANDIDATOS A DECK_PLAYER                   >>> DESTRAVA E2 <<<
-- ===========================================================================
-- Heurística de LOCALIZAÇÃO, não de classificação: tokens com forma de nome
-- próprio (dois ou mais componentes, sem dígitos). O resultado é uma lista
-- PARA UM HUMANO OLHAR — "isto é um jogador" é decisão editorial, e o
-- RECORTE 1.A traz o universo inteiro para conferência cruzada.
-- ===========================================================================
WITH a_rows AS (
    SELECT cs.code AS set_code,
           sig.residual_subtype,
           sig.residual_stamp
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
tokens AS (
    SELECT a.set_code, 'subtype'::TEXT AS raw_field, a.residual_subtype AS token
      FROM a_rows a
     WHERE a.residual_subtype IS NOT NULL
    UNION ALL
    SELECT a.set_code, 'stamp'::TEXT, x
      FROM a_rows a, LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) x
)
SELECT 'RECORTE_3_DECK_PLAYER_CANDIDATOS'                            AS recorte,
       t.token                                                       AS source_value,
       t.raw_field,
       count(*)                                                      AS rows_a,
       string_agg(DISTINCT t.set_code, ',' ORDER BY t.set_code)       AS sets
  FROM tokens t
 WHERE t.token IS NOT NULL
   AND t.token ~ '^[a-z]+(-[a-z]+)+$'
   AND t.token !~ '[0-9]'
 GROUP BY t.token, t.raw_field
 ORDER BY count(*) DESC, t.token;


-- ===========================================================================
-- RECORTE 4 — CONTROLE + MATERIALIDADE DOS HOLD
-- ===========================================================================
-- Confere as contagens que as rodadas anteriores fixaram (A=1.069, B=365) e
-- mede especificamente `league` e `player-reward`, os dois HOLD_EDITORIAL
-- registrados. Se as contagens divergirem, a baseline mudou e o vocabulário
-- terá de ser derivado de novo — nunca adaptar em silêncio.
-- ===========================================================================
WITH a_rows AS (
    SELECT r.id AS row_id,
           cs.code AS set_code,
           sig.residual_subtype,
           sig.residual_stamp,
           sig.printing_state
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
tokens AS (
    SELECT a.row_id, a.set_code, a.residual_subtype, a.residual_stamp,
           'subtype'::TEXT AS raw_field, a.residual_subtype AS token
      FROM a_rows a
     WHERE a.residual_subtype IS NOT NULL
    UNION ALL
    SELECT a.row_id, a.set_code, a.residual_subtype, a.residual_stamp,
           'stamp'::TEXT, x
      FROM a_rows a, LATERAL unnest(COALESCE(a.residual_stamp,'{}'::TEXT[])) x
),
totais AS (
    SELECT count(*) AS a_total,
           count(*) FILTER (
               WHERE printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
           ) AS a_printing_terminal
      FROM a_rows
),
b_total AS (
    SELECT count(*) AS n
      FROM public.card_variant cv
     WHERE cv.printing_profile_id IS NULL
       AND EXISTS (SELECT 1 FROM public.catalog_variant_import_row r
                    WHERE r.resulting_variant_id = cv.id)
),
hold AS (
    SELECT t.token,
           t.raw_field,
           count(DISTINCT t.row_id)                                  AS rows_a,
           string_agg(DISTINCT t.set_code, ',' ORDER BY t.set_code)   AS sets,
           count(DISTINCT (COALESCE(t.residual_subtype,'') || '|' ||
                           COALESCE(array_to_string(t.residual_stamp,'+'),''))) AS assinaturas_distintas
      FROM tokens t
     WHERE t.token IN ('league','player-reward')
     GROUP BY t.token, t.raw_field
)
SELECT 'RECORTE_4_CONTROLE'                     AS recorte,
       h.token,
       h.raw_field,
       h.rows_a,
       round(100.0 * h.rows_a / NULLIF(tt.a_total, 0), 2) AS pct_sobre_a,
       h.sets,
       h.assinaturas_distintas                  AS profiles_afetados,
       CASE WHEN h.assinaturas_distintas = 1 THEN 'ISOLADO' ELSE 'RECORRENTE' END AS padrao,
       tt.a_total                               AS a_medido,
       tt.a_printing_terminal                   AS a_printing_terminal,
       bt.n                                     AS b_medido,
       1069                                     AS a_esperado,
       365                                      AS b_esperado,
       (tt.a_total = 1069)                      AS a_bate,
       (bt.n = 365)                             AS b_bate
  FROM totais tt
  CROSS JOIN b_total bt
  LEFT JOIN hold h ON TRUE
 ORDER BY h.token NULLS LAST, h.raw_field;

ROLLBACK;

-- ===========================================================================
-- O QUE FAZER COM A SAÍDA
-- ===========================================================================
--   1. Exportar os recortes 1.A, 1.B, 2 e 3 como CSV.
--   2. Colar em `editorial/edition-context-vocabulary.csv`, preenchendo as
--      colunas EDITORIAIS (family, code, name, name_pt_br, scope, status).
--   3. As colunas MECÂNICAS já vêm prontas — não editar à mão.
--   4. Rodar `editorial/slugify.mjs --from-csv` para gerar os
--      `DECK_PLAYER_<SLUG>` e detectar colisões.
--   5. Só então 2230/2231/2232 podem ser preenchidos.
-- ===========================================================================
