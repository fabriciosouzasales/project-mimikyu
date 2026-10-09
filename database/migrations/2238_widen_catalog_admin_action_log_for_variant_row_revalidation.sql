/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2238 - Widen Catalog Admin Action Log for Variant Row Revalidation
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE — 2026-10-09, via apply_migration (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg. Ledger: 20261009231911 / 2238_widen_catalog_admin_action_log_for_variant_row_revalidation
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: NEEDS-REVIEW-REVALIDATION-01 (frente VARIANT-DISPLAY-SEMANTICS-01,
              experiência editorial das NEEDS_REVIEW)

-------------------------------------------------------------------------------
Descrição resumida
-------------------------------------------------------------------------------
Contrato de auditoria para a reavaliação de linhas de staging de Card Variant
(Query 2239). Estritamente aditivo:

    action  + CARD_VARIANT_IMPORT_ROWS_REVALIDATED            -> 32
    ramo    CATALOG_VARIANT_IMPORT_JOB passa a aceitar também
            CARD_VARIANT_IMPORT_ROWS_REVALIDATED              -> 13 ramos
    entity_type: inalterado (CATALOG_VARIANT_IMPORT_JOB já existe) -> 13

Simetria deliberada com o par já existente do import de Cartas:
(CATALOG_IMPORT_JOB, CATALOG_IMPORT_ROWS_REVALIDATED).

-------------------------------------------------------------------------------
GUARD — baseline verificado SEMANTICAMENTE em tempo de execução
-------------------------------------------------------------------------------
Baseline documental: estado terminal da Query 2188 / canônica 2010 v2.0
(31 actions / 13 entity_types / 13 ramos).

O guard não confia nesse baseline. Para cada uma das três CHECK ele:
  1. extrai TODO literal citado na definição real (universo candidato =
     baseline ∪ literais encontrados ∪ valor novo);
  2. avalia a expressão REAL da CHECK (pg_get_expr) sobre esse universo via
     EXECUTE — quem decide o que é aceito é o Postgres;
  3. exige igualdade EXATA de conjunto com o baseline: nada falta, nada sobra,
     e o valor/par novo ainda NÃO é aceito.
Mesma técnica semântica da 2185 v1.3 / 2188 (nunca contagem de literais),
generalizada para as listas planas.

Se o guard disparar: NÃO relaxar. Recapturar o estado real, reescrever as três
CHECK como superconjunto estrito e só então executar.

-------------------------------------------------------------------------------
Pré-requisitos
-------------------------------------------------------------------------------
- Query 2010 v2.0 (canônica) / 2188 (último widen conhecido, LIVE).

Impacto no frontend: web/lib/catalogo/log-atualizacoes-labels.ts precisa do
rótulo da nova action (senão /catalogo/log-atualizacoes exibe o enum cru).
Entregue no mesmo pacote (ver README da proposta).
===============================================================================
*/

BEGIN;

DO $guard$
DECLARE
    c_actions TEXT[] := ARRAY[
        'GAME_CREATED','GAME_UPDATED','GAME_DELETED',
        'EXPANSION_CREATED','EXPANSION_UPDATED','EXPANSION_DELETED',
        'CARD_SET_CREATED','CARD_SET_UPDATED','CARD_SET_DELETED',
        'CARD_CREATED','CARD_UPDATED','CARD_DEACTIVATED','CARD_REACTIVATED',
        'CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED','CATALOG_IMPORT_ROWS_REVALIDATED',
        'RARITY_CREATED','RARITY_UPDATED',
        'RARITY_EXTERNAL_MAPPING_CREATED','RARITY_EXTERNAL_MAPPING_UPDATED',
        'CARD_ASSET_MANUAL_IMPORT_COMPLETED','CARD_VARIANT_IMPORT_CONFIRMED',
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
        'CARD_VARIANT_TYPE_CREATED','CARD_VARIANT_TYPE_UPDATED',
        'CARD_VARIANT_TYPE_DEACTIVATED','CARD_VARIANT_TYPE_REACTIVATED',
        'CARD_PRIMARY_SPECIES_RESOLVED','CARD_PRIMARY_SPECIES_CORRECTED',
        'CARD_PRINTING_EXTERNAL_MAPPING_CREATED','CARD_PRINTING_PROFILE_CREATED'];
    c_entities TEXT[] := ARRAY[
        'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
        'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
        'CARD_PRIMARY_SPECIES','CARD_PRINTING_EXTERNAL_MAPPING','CARD_PRINTING_PROFILE'];
    c_new_action TEXT := 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED';

    v_action_expr TEXT;
    v_entity_expr TEXT;
    v_match_expr  TEXT;
    v_all_defs    TEXT;
    v_lits        TEXT[];
    v_uni_a       TEXT[];
    v_uni_e       TEXT[];
    v_accepted    TEXT[];
    v_missing     BIGINT;
    v_extra       BIGINT;
    v_ok          BOOLEAN;
BEGIN
    SELECT max(pg_get_expr(c.conbin, c.conrelid)) FILTER (WHERE c.conname = 'ck_catalog_admin_action_log_action_valid'),
           max(pg_get_expr(c.conbin, c.conrelid)) FILTER (WHERE c.conname = 'ck_catalog_admin_action_log_entity_type_valid'),
           max(pg_get_expr(c.conbin, c.conrelid)) FILTER (WHERE c.conname = 'ck_catalog_admin_action_log_action_entity_match')
      INTO v_action_expr, v_entity_expr, v_match_expr
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass;

    IF v_action_expr IS NULL OR v_entity_expr IS NULL OR v_match_expr IS NULL THEN
        RAISE EXCEPTION 'WIDEN_2238_CHECKS_NOT_FOUND: uma das três CHECK de catalog_admin_action_log não existe. STOP.';
    END IF;

    -- Universo candidato: baseline ∪ todo literal citado nas três CHECK ∪ novo.
    v_all_defs := v_action_expr || ' ' || v_entity_expr || ' ' || v_match_expr;
    SELECT coalesce(array_agg(DISTINCT m[1]), '{}') INTO v_lits
      FROM regexp_matches(v_all_defs, '''([A-Z][A-Z_]*)''', 'g') AS m;

    SELECT array_agg(DISTINCT x) INTO v_uni_a FROM unnest(c_actions || v_lits || c_new_action) x;
    SELECT array_agg(DISTINCT x) INTO v_uni_e FROM unnest(c_entities || v_lits) x;

    -- (A) CHECK de action: aceito == baseline (exato).
    EXECUTE format('SELECT coalesce(array_agg(action ORDER BY action), ''{}'') FROM unnest($1) AS t(action) WHERE (%s)', v_action_expr)
       INTO v_accepted USING v_uni_a;
    IF NOT (v_accepted @> c_actions AND c_actions @> v_accepted) THEN
        RAISE EXCEPTION 'WIDEN_2238_ACTION_DRIFT: o conjunto aceito pela CHECK real de action difere do baseline 31. Aceito: %. STOP — recapturar.', v_accepted;
    END IF;

    -- (B) CHECK de entity_type: aceito == baseline (exato).
    EXECUTE format('SELECT coalesce(array_agg(entity_type ORDER BY entity_type), ''{}'') FROM unnest($1) AS t(entity_type) WHERE (%s)', v_entity_expr)
       INTO v_accepted USING v_uni_e;
    IF NOT (v_accepted @> c_entities AND c_entities @> v_accepted) THEN
        RAISE EXCEPTION 'WIDEN_2238_ENTITY_DRIFT: o conjunto aceito pela CHECK real de entity_type difere do baseline 13. Aceito: %. STOP — recapturar.', v_accepted;
    END IF;

    -- (C) Matriz de pares: aceitos == baseline (exato), sobre o produto
    --     cartesiano do universo inteiro.
    EXECUTE format($q$
        WITH expected(entity_type, action) AS (VALUES
            ('GAME','GAME_CREATED'),('GAME','GAME_UPDATED'),('GAME','GAME_DELETED'),
            ('EXPANSION','EXPANSION_CREATED'),('EXPANSION','EXPANSION_UPDATED'),('EXPANSION','EXPANSION_DELETED'),
            ('CARD_SET','CARD_SET_CREATED'),('CARD_SET','CARD_SET_UPDATED'),('CARD_SET','CARD_SET_DELETED'),
            ('CARD_SET','CARD_ASSET_MANUAL_IMPORT_COMPLETED'),
            ('CARD','CARD_CREATED'),('CARD','CARD_UPDATED'),('CARD','CARD_DEACTIVATED'),('CARD','CARD_REACTIVATED'),
            ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_JOB'),('CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED'),
            ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_ROWS_REVALIDATED'),
            ('RARITY','RARITY_CREATED'),('RARITY','RARITY_UPDATED'),
            ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_CREATED'),
            ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_UPDATED'),
            ('CATALOG_VARIANT_IMPORT_JOB','CARD_VARIANT_IMPORT_CONFIRMED'),
            ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'),
            ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_CREATED'),('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_UPDATED'),
            ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_DEACTIVATED'),('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_REACTIVATED'),
            ('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_RESOLVED'),('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_CORRECTED'),
            ('CARD_PRINTING_EXTERNAL_MAPPING','CARD_PRINTING_EXTERNAL_MAPPING_CREATED'),
            ('CARD_PRINTING_PROFILE','CARD_PRINTING_PROFILE_CREATED')
        ),
        grid AS (
            SELECT e.v AS entity_type, a.v AS action,
                   EXISTS (SELECT 1 FROM expected x WHERE x.entity_type = e.v AND x.action = a.v) AS is_expected
              FROM unnest($1::text[]) e(v) CROSS JOIN unnest($2::text[]) a(v)
        )
        SELECT count(*) FILTER (WHERE is_expected AND NOT coalesce((%1$s), false)),
               count(*) FILTER (WHERE NOT is_expected AND coalesce((%1$s), false))
          FROM grid
    $q$, v_match_expr) INTO v_missing, v_extra USING v_uni_e, v_uni_a;

    IF v_missing <> 0 OR v_extra <> 0 THEN
        RAISE EXCEPTION 'WIDEN_2238_MATCH_DRIFT: matriz de pares real difere do baseline (faltam %, sobram %). STOP — recapturar pg_get_expr() e reescrever como superconjunto estrito.', v_missing, v_extra;
    END IF;

    -- (D) Nenhuma linha já gravada fica descoberta.
    EXECUTE format('SELECT NOT EXISTS (SELECT 1 FROM public.catalog_admin_action_log WHERE NOT ((%s) AND (%s) AND (%s)))',
                   v_action_expr, v_entity_expr, v_match_expr) INTO v_ok;
    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'WIDEN_2238_EXISTING_ROWS_UNCOVERED: há linhas gravadas fora das CHECK atuais. STOP.';
    END IF;

    -- (E) O par novo ainda não pode existir (redundância/conflito com outra frente).
    IF c_new_action = ANY (c_actions) THEN
        RAISE EXCEPTION 'WIDEN_2238_INTERNAL: baseline já contém a action nova.';
    END IF;
END;
$guard$;

-- ACTION — 31 preservados + 1 = 32.
ALTER TABLE public.catalog_admin_action_log DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;
ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
    CHECK (
        action IN (
            'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
            'EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED',
            'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
            'CARD_CREATED', 'CARD_UPDATED',
            'CARD_DEACTIVATED', 'CARD_REACTIVATED',
            'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED',
            'RARITY_CREATED', 'RARITY_UPDATED',
            'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED',
            'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
            'CARD_VARIANT_IMPORT_CONFIRMED',
            'CARD_VARIANT_IMPORT_ROWS_REVALIDATED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED',
            'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
            'CARD_PRINTING_PROFILE_CREATED'
        )
    );

-- ENTITY_TYPE — inalterado (13). Não é recriada.

-- ACTION × ENTITY_TYPE — 13 ramos; o ramo CATALOG_VARIANT_IMPORT_JOB ganha 1 action.
ALTER TABLE public.catalog_admin_action_log DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;
ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match
    CHECK (
        (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED'))
        OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED'))
        OR (entity_type = 'CARD_SET' AND action IN (
                'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED', 'CARD_ASSET_MANUAL_IMPORT_COMPLETED'
            ))
        OR (entity_type = 'CARD' AND action IN (
                'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
            ))
        OR (entity_type = 'CATALOG_IMPORT_JOB' AND action IN (
                'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED'
            ))
        OR (entity_type = 'RARITY' AND action IN ('RARITY_CREATED', 'RARITY_UPDATED'))
        OR (entity_type = 'RARITY_EXTERNAL_MAPPING' AND action IN (
                'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED'
            ))
        OR (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND action IN (
                'CARD_VARIANT_IMPORT_CONFIRMED', 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED'
            ))
        OR (entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' AND action = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED')
        OR (entity_type = 'CARD_VARIANT_TYPE' AND action IN (
                'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
                'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED'
            ))
        OR (entity_type = 'CARD_PRIMARY_SPECIES' AND action IN (
                'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED'
            ))
        OR (entity_type = 'CARD_PRINTING_EXTERNAL_MAPPING' AND action = 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
        OR (entity_type = 'CARD_PRINTING_PROFILE' AND action = 'CARD_PRINTING_PROFILE_CREATED')
    );

COMMIT;

-- ============================================================================
-- Resultado esperado: 2 DROP + 2 ADD CONSTRAINT. Estado final:
--   32 actions / 13 entity_types / 13 ramos (CATALOG_VARIANT_IMPORT_JOB com 2).
--
-- Como validar (Query 2843, Seção 1):
SELECT conname, pg_get_constraintdef(oid) LIKE '%CARD_VARIANT_IMPORT_ROWS_REVALIDATED%' AS tem_action_nova
  FROM pg_constraint
 WHERE conrelid = 'public.catalog_admin_action_log'::regclass
   AND conname IN ('ck_catalog_admin_action_log_action_valid',
                   'ck_catalog_admin_action_log_action_entity_match')
 ORDER BY conname;
-- Esperado: 2 linhas, ambas tem_action_nova = true.
-- ============================================================================
