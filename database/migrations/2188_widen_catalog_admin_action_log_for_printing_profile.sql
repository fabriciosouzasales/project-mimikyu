/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2188 - Widen Catalog Admin Action Log for Printing Profile
Versão......: 1.0
Status......: MIGRATION / CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-13
Executado...: 2026-09-13, via apply_migration (MCP Supabase), projeto
              qjfutqujxrbzgrtkpgkg. Ledger: 20260913234544 /
              2188_widen_catalog_admin_action_log_for_printing_profile
Reclassif..: 2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01
Canônica....: o estado TERMINAL das três CHECK vive em
              database/schema/2010_create_catalog_admin_action_log.sql v2.0
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-10 /
              FIRST-EDITION-PROFILE-IMPLEMENTATION-01 / GATE-A-STAGING-01 (§1)

-------------------------------------------------------------------------------
Descrição resumida
-------------------------------------------------------------------------------
Cria contrato próprio de auditoria para a criação de Perfil de Impressão:
+1 action, +1 entity_type, +1 ramo de action_entity_match.

    action      + CARD_PRINTING_PROFILE_CREATED   -> 31
    entity_type + CARD_PRINTING_PROFILE           -> 13
    ramo        + CARD_PRINTING_PROFILE -> aquela action -> 13

Nenhuma outra action/entity nova. Estritamente aditivo.

-------------------------------------------------------------------------------
POR QUE UMA ENTITY PRÓPRIA
-------------------------------------------------------------------------------
catalog_admin_action_log tem três domínios FECHADOS — action, entity_type e o
casamento action × entity_type. Reusar CARD_PRINTING_EXTERNAL_MAPPING para
registrar a criação de um PERFIL seria guardar a identidade da entidade fora
da coluna que existe para guardar a identidade da entidade: são tabelas
diferentes (card_printing_profile vs card_printing_external_mapping), ciclos
de vida diferentes (perfil é selado e imutável; mapping é superseded) e
entity_id de domínios diferentes.

É a mesma decisão, pelo mesmo motivo, que a Query 2185 tomou ao recusar o
reuso de CARD_VARIANT_TYPE_EXTERNAL_MAPPING para o eixo de Impressão.

-------------------------------------------------------------------------------
UMA ÚNICA ACTION — E POR QUÊ
-------------------------------------------------------------------------------
Só CARD_PRINTING_PROFILE_CREATED. NÃO se acrescenta _UPDATED, _DEACTIVATED
nem _REACTIVATED:

- a composição de um Perfil é IMUTÁVEL após o selo (Query 2168,
  enforce_printing_profile_composition_immutable) — não existe, nem pode
  existir, uma RPC que a altere;
- não há hoje nenhuma função administrativa que desative ou reative Perfil.

Ampliar o domínio do log com pares que nenhuma função pode produzir seria
dívida gratuita: permissão sem caminho de exercício. Quando (e se) essas
operações existirem, um novo widen aditivo as acrescenta.

-------------------------------------------------------------------------------
BASELINE — E POR QUE ELE É VERIFICADO EM TEMPO DE EXECUÇÃO
-------------------------------------------------------------------------------
Baseline documental: estado final da Query 2185 (promovida em
database/migrations/), 30 actions / 12 entity_types / 12 ramos.

O GUARD abaixo NÃO confia no baseline documental. Ele lê o estado real no
instante da execução — pg_get_constraintdef() para as duas listas planas e
pg_get_expr() para a matriz de pares — e ABORTA se o contrato vigente não for
exatamente o conhecido, nos DOIS sentidos:

  - algo que este arquivo conhece sumiu     -> deixaria de ser aditivo;
  - algo que este arquivo desconhece existe -> o DROP + ADD o destruiria.

Premissa envelhece; guard não. Técnica idêntica à da Query 2185 v1.3, incluindo
a avaliação SEMÂNTICA da terceira CHECK (nunca contagem de literais — ver o
bloco B-11 daquela Query: 'CATALOG_IMPORT_JOB' é ao mesmo tempo entity_type e
action, e qualquer prova por contagem textual aborta contra o contrato
CORRETO).

Se o guard disparar: NÃO relaxar. Recapturar o estado real, reescrever as três
listas como superconjunto estrito do que existe, e só então executar.

-------------------------------------------------------------------------------
Pré-requisitos
-------------------------------------------------------------------------------
- Query 2010 - Create Catalog Admin Action Log Table (criação original; NÃO
  reflete o estado atual das três CHECKs).
- Query 2185 - último widen conhecido (LIVE, promovido).
- Query 2166/2167/2168 - Card Printing Profile, composição e guards (entidade
  auditada).

Impacto no frontend: web/lib/catalogo/log-atualizacoes-labels.ts precisa do
rótulo do novo entity_type e da nova action — sem isso a tela
/catalogo/log-atualizacoes exibe o enum técnico cru (incidente de 2026-08-16).
Fora do escopo desta rodada de staging; registrar no GATE-B.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial (2026-09-13).** Aditiva sobre o baseline da Query
        2185 (30/12/12). Guard anti-drift com prova semântica da matriz de
        pares, herdado da 2185 v1.3. Ainda NÃO EXECUTADA. |
===============================================================================
*/

BEGIN;

-- =========================================================================
-- GUARD — o estado real precisa ser EXATAMENTE o baseline conhecido.
-- Fail-closed nos dois sentidos (nada falta / nada sobra).
-- =========================================================================
DO $guard$
DECLARE
    v_action_def TEXT;
    v_entity_def TEXT;
    v_match_def  TEXT;
    v_missing    TEXT;
    v_extra      TEXT;
    v_expr       TEXT;
    v_sql        TEXT;
    v_missing_pairs INTEGER;
    v_extra_pairs   INTEGER;
    v_ok         BOOLEAN;
BEGIN
    SELECT pg_get_constraintdef(c.oid) INTO v_action_def
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_action_valid';

    SELECT pg_get_constraintdef(c.oid) INTO v_entity_def
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_entity_type_valid';

    SELECT pg_get_constraintdef(c.oid) INTO v_match_def
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_action_entity_match';

    IF v_action_def IS NULL OR v_entity_def IS NULL OR v_match_def IS NULL THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_CHECKS_NOT_FOUND: uma das TRÊS CHECKs de catalog_admin_action_log não existe (action=%, entity=%, match=%). STOP — reauditar antes de qualquer DDL.',
            (v_action_def IS NOT NULL), (v_entity_def IS NOT NULL), (v_match_def IS NOT NULL);
    END IF;

    -- (A) Os 30 actions do baseline 2185 precisam TODOS estar presentes.
    --     Casamento do LITERAL QUOTED COMPLETO, nunca substring nua (F-10).
    SELECT string_agg(a, ', ' ORDER BY a) INTO v_missing
      FROM (VALUES
            ('GAME_CREATED'),('GAME_UPDATED'),('GAME_DELETED'),
            ('EXPANSION_CREATED'),('EXPANSION_UPDATED'),('EXPANSION_DELETED'),
            ('CARD_SET_CREATED'),('CARD_SET_UPDATED'),('CARD_SET_DELETED'),
            ('CARD_CREATED'),('CARD_UPDATED'),('CARD_DEACTIVATED'),('CARD_REACTIVATED'),
            ('CATALOG_IMPORT_JOB'),('CATALOG_IMPORT_CONFIRMED'),('CATALOG_IMPORT_ROWS_REVALIDATED'),
            ('RARITY_CREATED'),('RARITY_UPDATED'),
            ('RARITY_EXTERNAL_MAPPING_CREATED'),('RARITY_EXTERNAL_MAPPING_UPDATED'),
            ('CARD_ASSET_MANUAL_IMPORT_COMPLETED'),('CARD_VARIANT_IMPORT_CONFIRMED'),
            ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'),
            ('CARD_VARIANT_TYPE_CREATED'),('CARD_VARIANT_TYPE_UPDATED'),
            ('CARD_VARIANT_TYPE_DEACTIVATED'),('CARD_VARIANT_TYPE_REACTIVATED'),
            ('CARD_PRIMARY_SPECIES_RESOLVED'),('CARD_PRIMARY_SPECIES_CORRECTED'),
            ('CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
      ) AS known(a)
     WHERE position('''' || a || '''' IN v_action_def) = 0;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_BASELINE_DRIFT: a CHECK real de action não contém: %. Esta Query deixaria de ser aditiva. STOP — recapturar pg_get_constraintdef() e reescrever as listas como superconjunto estrito.', v_missing;
    END IF;

    -- (B) Os 12 entity_types do baseline 2185.
    SELECT string_agg(e, ', ' ORDER BY e) INTO v_missing
      FROM (VALUES
            ('GAME'),('EXPANSION'),('CARD_SET'),('CARD'),('CATALOG_IMPORT_JOB'),
            ('RARITY'),('RARITY_EXTERNAL_MAPPING'),('CATALOG_VARIANT_IMPORT_JOB'),
            ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING'),('CARD_VARIANT_TYPE'),
            ('CARD_PRIMARY_SPECIES'),('CARD_PRINTING_EXTERNAL_MAPPING')
      ) AS known(e)
     WHERE position('''' || e || '''' IN v_entity_def) = 0;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_BASELINE_DRIFT: a CHECK real de entity_type não contém: %. STOP — mesma instrução acima.', v_missing;
    END IF;

    -- (C) e (D) IGUALDADE DE CONJUNTO, não apenas inclusão. As duas listas
    -- são PLANAS (uma única coluna), então extração textual é exata aqui —
    -- não existe papel sintático a confundir, que é o defeito (B-11) que
    -- impede usar esta técnica na terceira CHECK.
    SELECT string_agg(DISTINCT t, ', ' ORDER BY t) INTO v_extra
      FROM (SELECT (regexp_matches(v_action_def, '''([A-Z][A-Z_]*)''', 'g'))[1] AS t) AS found
     WHERE t NOT IN (
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
            'CARD_PRINTING_EXTERNAL_MAPPING_CREATED');

    IF v_extra IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_ACTION_UNKNOWN: a CHECK real de action aceita valor(es) que este staging desconhece: %. Sobrescrevê-la removeria esse contrato. STOP — incorporar antes de executar.', v_extra;
    END IF;

    SELECT string_agg(DISTINCT t, ', ' ORDER BY t) INTO v_extra
      FROM (SELECT (regexp_matches(v_entity_def, '''([A-Z][A-Z_]*)''', 'g'))[1] AS t) AS found
     WHERE t NOT IN (
            'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
            'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES','CARD_PRINTING_EXTERNAL_MAPPING');

    IF v_extra IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_ENTITY_UNKNOWN: a CHECK real de entity_type aceita valor(es) que este staging desconhece: %. STOP — mesma instrução acima.', v_extra;
    END IF;

    -- Prova direta e independente: nenhum par já gravado pode ficar de fora.
    IF EXISTS (
        SELECT 1 FROM public.catalog_admin_action_log l
         WHERE position('''' || l.action || '''' IN v_action_def) = 0
            OR position('''' || l.entity_type || '''' IN v_entity_def) = 0
    ) THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_EXISTING_ROWS_UNCOVERED: existem linhas gravadas cujo action/entity_type não aparece na CHECK atual. Estado inconsistente. STOP.';
    END IF;

    -- =====================================================================
    -- ANTI-DRIFT DA TERCEIRA CHECK — PROVA SEMÂNTICA (técnica da 2185 v1.3)
    --
    -- Permissão NÃO EXERCIDA também é contrato: outra frente pode ter
    -- liberado um par novo sem que nenhuma linha o tenha usado, e o
    -- DROP + ADD abaixo o destruiria em silêncio.
    --
    -- pg_get_expr(conbin, conrelid) devolve a expressão real com as colunas
    -- `entity_type` e `action` NÃO qualificadas; ela é avaliada via EXECUTE
    -- contra o cross-product 12 entity_types × 30 actions = 360 pares.
    -- Quem decide se um par é permitido é o Postgres executando o predicado
    -- real — não há parsing, não há contagem, papel sintático não importa.
    -- =====================================================================
    SELECT pg_get_expr(c.conbin, c.conrelid) INTO v_expr
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_action_entity_match';

    IF v_expr IS NULL OR btrim(v_expr) = '' THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_MATCH_EXPR_UNREADABLE: não foi possível renderizar a expressão de ck_catalog_admin_action_log_action_entity_match. STOP.';
    END IF;

    v_sql := format($q$
        SELECT
            count(*) FILTER (WHERE x.expected     AND NOT (%1$s)),
            count(*) FILTER (WHERE NOT x.expected AND     (%1$s))
          FROM (
              SELECT e.v AS entity_type,
                     a.v AS action,
                     (e.v, a.v) IN (
                         VALUES
                           ('GAME','GAME_CREATED'),
                           ('GAME','GAME_UPDATED'),
                           ('GAME','GAME_DELETED'),
                           ('EXPANSION','EXPANSION_CREATED'),
                           ('EXPANSION','EXPANSION_UPDATED'),
                           ('EXPANSION','EXPANSION_DELETED'),
                           ('CARD_SET','CARD_SET_CREATED'),
                           ('CARD_SET','CARD_SET_UPDATED'),
                           ('CARD_SET','CARD_SET_DELETED'),
                           ('CARD_SET','CARD_ASSET_MANUAL_IMPORT_COMPLETED'),
                           ('CARD','CARD_CREATED'),
                           ('CARD','CARD_UPDATED'),
                           ('CARD','CARD_DEACTIVATED'),
                           ('CARD','CARD_REACTIVATED'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_JOB'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_ROWS_REVALIDATED'),
                           ('RARITY','RARITY_CREATED'),
                           ('RARITY','RARITY_UPDATED'),
                           ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_CREATED'),
                           ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_UPDATED'),
                           ('CATALOG_VARIANT_IMPORT_JOB','CARD_VARIANT_IMPORT_CONFIRMED'),
                           ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_CREATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_UPDATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_DEACTIVATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_REACTIVATED'),
                           ('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_RESOLVED'),
                           ('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_CORRECTED'),
                           ('CARD_PRINTING_EXTERNAL_MAPPING','CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
                     ) AS expected
                FROM unnest(ARRAY[
                         'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
                         'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
                         'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
                         'CARD_PRIMARY_SPECIES','CARD_PRINTING_EXTERNAL_MAPPING']::text[]) AS e(v)
                CROSS JOIN unnest(ARRAY[
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
                         'CARD_PRINTING_EXTERNAL_MAPPING_CREATED']::text[]) AS a(v)
          ) x
    $q$, v_expr);

    EXECUTE v_sql INTO v_missing_pairs, v_extra_pairs;

    IF v_missing_pairs <> 0 THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_MATCH_PAIR_MISSING: % par(es) da matriz baseline da Query 2185 NÃO são aceitos pela CHECK real. O contrato encolheu. STOP — recapturar pg_get_expr() e reescrever o ADD CONSTRAINT como superconjunto estrito.', v_missing_pairs;
    END IF;

    IF v_extra_pairs <> 0 THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_MATCH_PAIR_EXTRA: % par(es) FORA da matriz baseline são aceitos pela CHECK real — permissão que este staging desconhece, inclusive uma que nenhuma linha usou ainda. A CHECK está À FRENTE do baseline. STOP — recapturar e incorporar antes de executar.', v_extra_pairs;
    END IF;

    -- Regressão nominal do B-11: o par cujo entity_type e action são o MESMO
    -- literal precisa passar. Se falhar, a prova voltou a confundir papel
    -- sintático com ocorrência textual.
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_JOB') INTO v_ok;

    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_MATCH_REGRESSION_B11: o par LEGÍTIMO (CATALOG_IMPORT_JOB, CATALOG_IMPORT_JOB) foi recusado pela CHECK real. STOP.';
    END IF;

    -- Contraprova: um par que NUNCA foi permitido.
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'GAME', 'CARD_CREATED') INTO v_ok;

    IF v_ok IS NOT FALSE THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_MATCH_OVERPERMISSIVE: o par ILEGÍTIMO (GAME, CARD_CREATED) é aceito pela CHECK real. O contrato de pares não é o conhecido. STOP.';
    END IF;

    -- Contraprova específica desta frente: o par que esta Query vai CRIAR
    -- ainda NÃO pode existir. Se já existir, outra frente o criou e este
    -- arquivo é redundante ou conflitante.
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'CARD_PRINTING_PROFILE', 'CARD_PRINTING_PROFILE_CREATED') INTO v_ok;

    IF v_ok IS NOT FALSE THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_ALREADY_PRESENT: o par (CARD_PRINTING_PROFILE, CARD_PRINTING_PROFILE_CREATED) JÁ é aceito pela CHECK real. Esta migration já foi aplicada, ou outra frente a antecipou. STOP — reauditar antes de reexecutar.';
    END IF;

    -- (E) Nenhum literal desconhecido no texto da terceira CHECK. Aqui a
    -- extração textual é legítima: não infere papel nem cardinalidade,
    -- apenas confirma que o vocabulário é o ratificado.
    SELECT string_agg(DISTINCT t, ', ' ORDER BY t) INTO v_extra
      FROM (SELECT (regexp_matches(v_match_def, '''([A-Z][A-Z_]*)''', 'g'))[1] AS t) AS found
     WHERE t NOT IN (
            'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
            'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES','CARD_PRINTING_EXTERNAL_MAPPING',
            'GAME_CREATED','GAME_UPDATED','GAME_DELETED',
            'EXPANSION_CREATED','EXPANSION_UPDATED','EXPANSION_DELETED',
            'CARD_SET_CREATED','CARD_SET_UPDATED','CARD_SET_DELETED',
            'CARD_CREATED','CARD_UPDATED','CARD_DEACTIVATED','CARD_REACTIVATED',
            'CATALOG_IMPORT_CONFIRMED','CATALOG_IMPORT_ROWS_REVALIDATED',
            'RARITY_CREATED','RARITY_UPDATED',
            'RARITY_EXTERNAL_MAPPING_CREATED','RARITY_EXTERNAL_MAPPING_UPDATED',
            'CARD_ASSET_MANUAL_IMPORT_COMPLETED','CARD_VARIANT_IMPORT_CONFIRMED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED','CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED','CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED','CARD_PRIMARY_SPECIES_CORRECTED',
            'CARD_PRINTING_EXTERNAL_MAPPING_CREATED'
     );

    IF v_extra IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_PRINTING_PROFILE_MATCH_DRIFT_UNKNOWN: a CHECK action_entity_match cita valor(es) que este staging desconhece: %. A CHECK real está À FRENTE do baseline conhecido. STOP — recapturar e incorporar antes de executar.', v_extra;
    END IF;
END;
$guard$;

-- =========================================================================
-- ACTION — 30 preservados + 1 = 31.
-- =========================================================================
ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;

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
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED',
            'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
            'CARD_PRINTING_PROFILE_CREATED'
        )
    );

-- =========================================================================
-- ENTITY_TYPE — 12 preservados + 1 = 13.
-- =========================================================================
ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
    CHECK (
        entity_type IN (
            'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
            'RARITY', 'RARITY_EXTERNAL_MAPPING', 'CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', 'CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES',
            'CARD_PRINTING_EXTERNAL_MAPPING',
            'CARD_PRINTING_PROFILE'
        )
    );

-- =========================================================================
-- ACTION × ENTITY_TYPE — 12 ramos preservados + 1 = 13.
-- =========================================================================
ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

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
        OR (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND action = 'CARD_VARIANT_IMPORT_CONFIRMED')
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
-- Resultado esperado:
--   3 DROP + 3 ADD CONSTRAINT. Estado final:
--     31 actions / 13 entity_types / 13 ramos de action_entity_match.
--   Nenhuma linha existente invalidada (o guard já provou isso antes).
--
-- Como validar:
--   Query 2825 - Validate Card Printing Profile Creation Backfill, Seção V.
-- ============================================================================
