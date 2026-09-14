/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2190 - Fix Card Printing Profile Backfill UUID Aggregate
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-13
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-10 /
              FIRST-EDITION-PROFILE-IMPLEMENTATION-01 /
              GATE-B-CORRECTION-04 / UUID-AGGREGATE-FIX

-------------------------------------------------------------------------------
POR QUE ESTA QUERY EXISTE
-------------------------------------------------------------------------------
A Query 2189 v2.1 foi aplicada no LIVE em 2026-09-13 e está ESTRUTURALMENTE
correta (assinatura, SECURITY DEFINER, search_path, grants, guards, selo,
elegibilidade, locks, contadores, action log, contrato NEW-only). Mas está
FUNCIONALMENTE QUEBRADA por uma única expressão, no GUARD 4:

    SELECT count(DISTINCT ct.game_id), min(ct.game_id) ...

PostgreSQL NÃO possui o agregado min(uuid). O tipo uuid tem opclass btree —
por isso DISTINCT e ORDER BY funcionam — mas min/max não são registrados para
ele. Toda chamada ao worker aborta com:

    function min(uuid) does not exist

Isso foi descoberto pela PRIMEIRA EXECUÇÃO REAL do harness 2825 (GATE-B-
EXECUTION-02, 12 PASS / 17 FAIL). Cinco rodadas de revisão estática não o
pegaram porque a função nunca havia sido executada. O harness fez exatamente o
que existe para fazer.

PRECEDENTE NO PRÓPRIO REPOSITÓRIO: o mesmo erro ocorreu nas Queries 5129/5130/
5133 (Binder Layout Foundation, 2026-09-06), onde `min(p.layout_id)` sobre UUID
foi classificado como BLOCKER REAL e corrigido. O comentário daquelas Queries
registra literalmente "PostgreSQL NÃO possui min(uuid) built-in". A lição
estava escrita no repositório e foi repetida assim mesmo — registro isso aqui
para que a próxima frente não precise redescobrir.

-------------------------------------------------------------------------------
ESCOPO — MÍNIMO POSSÍVEL
-------------------------------------------------------------------------------
Esta Query substitui SOMENTE a definição de
internal.create_card_printing_profile_with_backfill(...).

NÃO toca em:
  - public.admin_create_card_printing_profile_with_backfill() — intacta;
  - assinatura do worker (mesmos 6 parâmetros, mesmo RETURNS TABLE);
  - SECURITY DEFINER / search_path = '';
  - grants (CREATE OR REPLACE PRESERVA a ACL — ver nota abaixo);
  - nenhum outro objeto do schema.

NOTA SOBRE GRANTS, DELIBERADA: esta Query NÃO repete os quatro REVOKE da 2189.
CREATE OR REPLACE FUNCTION preserva a ACL existente, então repeti-los seria
redundante — e pior: mascararia uma eventual perda de ACL que o postcheck
precisa ser capaz de detectar. A ACL é VERIFICADA depois, não reafirmada aqui.

-------------------------------------------------------------------------------
DIFF EXECUTÁVEL — UMA EXPRESSÃO
-------------------------------------------------------------------------------
DE (2189 v2.1, GUARD 4):

    SELECT count(DISTINCT ct.game_id), min(ct.game_id)
      INTO v_game_count, v_game_id
      FROM public.card_printing_trait ct
     WHERE ct.id = ANY(p_trait_ids);

PARA (2190 v1.0):

    SELECT count(DISTINCT ct.game_id),
           (array_agg(DISTINCT ct.game_id ORDER BY ct.game_id))[1]
      INTO v_game_count, v_game_id
      FROM public.card_printing_trait ct
     WHERE ct.id = ANY(p_trait_ids);

Tudo o mais é byte-a-byte o corpo aprovado da 2189 v2.1.

-------------------------------------------------------------------------------
PROVA DE SEMÂNTICA — 0 / 1 / >1 GAMES
-------------------------------------------------------------------------------
array_agg(DISTINCT x ORDER BY x) usa o operador de ordenação btree de uuid, que
EXISTE. O resultado é o conjunto distinto, ordenado ascendentemente; [1] é o
primeiro elemento. Comparando com a intenção original (min = menor elemento),
é o MESMO valor — apenas obtido por um caminho que o PostgreSQL sabe executar.

  0 traits correspondentes (conjunto vazio)
      array_agg sobre zero linhas devolve NULL; NULL[1] é NULL.
      count(DISTINCT) = 0, logo v_game_count = 0 <> 1 e o guard levanta
      MIXED_GAME. Idêntico ao comportamento pretendido pela 2189 — e, na
      prática, inalcançável: o GUARD 4 já provou acima que todos os ids
      existem (TRAIT_NOT_FOUND) e que p_trait_ids não é vazio (MISSING_TRAITS).

  1 game
      count(DISTINCT ct.game_id) = 1;
      array_agg(DISTINCT ...) devolve um array de UM elemento;
      [1] = esse UUID único. v_game_id fica EXATAMENTE igual ao que min()
      teria devolvido. Este é o único caminho que prossegue.

  >1 games
      count(DISTINCT ct.game_id) > 1 → v_game_count <> 1 → RAISE MIXED_GAME
      na linha seguinte, ANTES de v_game_id ser lido por qualquer instrução.
      O valor escolhido é irrelevante ao fluxo válido; ainda assim é
      determinístico (menor UUID), não arbitrário.

Conclusão: nenhuma mudança funcional além de tornar o SQL executável. O
conjunto de desfechos possíveis do GUARD 4 é o mesmo; o que muda é que o
caminho de 1 game deixa de abortar.

-------------------------------------------------------------------------------
COMO EXECUTAR
-------------------------------------------------------------------------------
apply_migration, mantendo BEGIN/COMMIT (padrão canônico STD-001 §504 e
precedente direto 2185/2189).

Como validar:
  Query 2825 - Validate Card Printing Profile Creation Backfill, v3.6.
  Exigir 29 PASS / 0 FAIL.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Correção do agregado UUID (2026-09-13, GATE-B-CORRECTION-04).**
        Substitui min(ct.game_id) por (array_agg(DISTINCT ct.game_id ORDER BY
        ct.game_id))[1] no GUARD 4 do worker. Único diff executável. Nenhum
        outro contrato alterado. NÃO EXECUTADA. |
===============================================================================
*/

BEGIN;

-- =============================================================================
-- WORKER — internal.create_card_printing_profile_with_backfill()
--
-- Corpo idêntico ao da Query 2189 v2.1 EXCETO a expressão do GUARD 4.
-- Superfície OWNER-ONLY. Não conhece auth.uid(): o administrador autorizador
-- chega como p_actor_id e é validado contra public.admin_user.
-- =============================================================================
CREATE OR REPLACE FUNCTION internal.create_card_printing_profile_with_backfill(
    p_actor_id      UUID,
    p_code          TEXT,
    p_name          TEXT,
    p_description   TEXT,
    p_display_order INTEGER,
    p_trait_ids     UUID[]
)
RETURNS TABLE(
    profile_id         UUID,
    traits_signature   UUID[],
    rows_touched       INTEGER,
    rows_revalidated   INTEGER,
    rows_still_pending INTEGER,
    jobs_affected      INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $worker$
DECLARE
    c_max_trait_ids CONSTANT INTEGER := 64;

    v_code        TEXT;
    v_name        TEXT;
    v_description TEXT;

    v_trait_count    INTEGER;
    v_distinct_count INTEGER;
    v_game_count     INTEGER;
    v_inactive       TEXT;
    v_unknown        INTEGER;

    v_game_id    UUID;
    v_profile_id UUID;
    v_expected   UUID[];
    v_sealed     UUID[];
    v_active     BOOLEAN;

    v_row_ids  UUID[];
    v_job_ids  UUID[];

    v_touched     INTEGER := 0;
    v_revalidated INTEGER := 0;
    v_pending     INTEGER := 0;
    v_jobs        INTEGER := 0;
    v_reconciled  INTEGER := 0;
BEGIN
    -- =====================================================================
    -- GUARD 1 — ATOR. Primeira instrução.
    -- =====================================================================
    IF p_actor_id IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_ACTOR: p_actor_id é obrigatório. Toda criação de Perfil precisa de um administrador autorizador nomeado.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.admin_user a WHERE a.id = p_actor_id) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_ACTOR_NOT_ADMIN: p_actor_id (%) não corresponde a um administrador cadastrado em public.admin_user.', p_actor_id;
    END IF;

    -- =====================================================================
    -- GUARD 2 — ESCALARES.
    -- =====================================================================
    v_code        := upper(btrim(coalesce(p_code, '')));
    v_name        := btrim(coalesce(p_name, ''));
    v_description := btrim(coalesce(p_description, ''));
    IF v_description = '' THEN v_description := NULL; END IF;

    IF v_code = '' OR v_code !~ '^[A-Z][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_CODE: código inválido (%). Esperado ^[A-Z][A-Z0-9_]*$.', p_code;
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_display_order IS NULL OR p_display_order <= 0 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_DISPLAY_ORDER: ordem inválida (%). Precisa ser inteiro positivo.', p_display_order;
    END IF;

    -- =====================================================================
    -- GUARD 3 — FORMA DO ARRAY DE TRAITS.
    -- =====================================================================
    IF p_trait_ids IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_TRAITS: p_trait_ids é obrigatório e não pode ser vazio.';
    END IF;

    IF array_ndims(p_trait_ids) <> 1 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_ARRAY_SHAPE: p_trait_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_trait_ids);
    END IF;

    v_trait_count := cardinality(p_trait_ids);

    IF v_trait_count = 0 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_TRAITS: p_trait_ids é obrigatório e não pode ser vazio.';
    END IF;

    IF v_trait_count > c_max_trait_ids THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_TOO_MANY_TRAITS: p_trait_ids tem % ids, acima do teto de % por Perfil.', v_trait_count, c_max_trait_ids;
    END IF;

    IF array_position(p_trait_ids, NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_NULL_TRAIT: p_trait_ids contém elemento NULL.';
    END IF;

    SELECT count(DISTINCT t) INTO v_distinct_count FROM unnest(p_trait_ids) AS t;

    IF v_distinct_count <> v_trait_count THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_TRAIT: p_trait_ids tem % elementos mas apenas % distintos. Composição é um CONJUNTO.', v_trait_count, v_distinct_count;
    END IF;

    -- =====================================================================
    -- GUARD 4 — EXISTÊNCIA, ATIVIDADE E GAME ÚNICO. game_id é derivado aqui.
    --
    -- >>> ÚNICO PONTO ALTERADO PELA QUERY 2190. <<<
    -- A 2189 v2.1 usava min(ct.game_id). PostgreSQL não tem min(uuid): o tipo
    -- tem opclass btree (DISTINCT/ORDER BY funcionam), mas os agregados
    -- min/max não são registrados para ele. Toda chamada abortava aqui.
    -- array_agg(DISTINCT ... ORDER BY ...) usa o mesmo operador de ordenação
    -- e devolve o conjunto ordenado; [1] é o menor — exatamente o valor que
    -- min() pretendia. Sem aggregate customizado e sem cast para text.
    -- Mesmo caminho de correção das Queries 5129/5130/5133.
    -- =====================================================================
    SELECT count(*) INTO v_unknown
      FROM unnest(p_trait_ids) AS t(id)
     WHERE NOT EXISTS (SELECT 1 FROM public.card_printing_trait ct WHERE ct.id = t.id);

    IF v_unknown > 0 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_TRAIT_NOT_FOUND: % dos ids informados não existem em card_printing_trait.', v_unknown;
    END IF;

    SELECT string_agg(ct.code, ', ' ORDER BY ct.code) INTO v_inactive
      FROM public.card_printing_trait ct
     WHERE ct.id = ANY(p_trait_ids) AND NOT ct.is_active;

    IF v_inactive IS NOT NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_TRAIT_INACTIVE: Característica(s) de Impressão inativa(s) na composição: %. Um Perfil ativo não pode ser composto por trait desativado.', v_inactive;
    END IF;

    SELECT count(DISTINCT ct.game_id),
           (array_agg(DISTINCT ct.game_id ORDER BY ct.game_id))[1]
      INTO v_game_count, v_game_id
      FROM public.card_printing_trait ct
     WHERE ct.id = ANY(p_trait_ids);

    IF v_game_count <> 1 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MIXED_GAME: os traits informados pertencem a % Games distintos. Um Perfil pertence a exatamente um Game.', v_game_count;
    END IF;

    -- =====================================================================
    -- GUARD 5 — UNICIDADE.
    -- =====================================================================
    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.code = v_code) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_CODE: já existe um Perfil de Impressão com o código % para este Game.', v_code;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.display_order = p_display_order) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_DISPLAY_ORDER: já existe um Perfil de Impressão com a ordem % para este Game.', p_display_order;
    END IF;

    v_expected := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) AS t ORDER BY t);

    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.traits_signature = v_expected) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_SIGNATURE: já existe um Perfil de Impressão com exatamente esta composição neste Game. Composição é identidade — reutilize o Perfil existente.';
    END IF;

    -- =====================================================================
    -- PASSO 1 — CRIAR O PERFIL "EM MONTAGEM" (traits_signature = NULL).
    -- =====================================================================
    INSERT INTO public.card_printing_profile
        (game_id, code, name, description, display_order)
    VALUES
        (v_game_id, v_code, v_name, v_description, p_display_order)
    RETURNING id INTO v_profile_id;

    -- =====================================================================
    -- PASSO 2 — COMPOSIÇÃO. Liberada enquanto a assinatura for NULL.
    -- =====================================================================
    INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
    SELECT v_profile_id, t, v_game_id FROM unnest(v_expected) AS t;

    -- =====================================================================
    -- PASSO 3 — FORÇAR O SELO.
    -- Sem esta linha o backfill abaixo casaria ZERO linhas, em silêncio.
    -- =====================================================================
    SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;

    -- =====================================================================
    -- PASSOS 4 e 5 — RELER E PROVAR O SELO. Fail-closed.
    -- =====================================================================
    SELECT p.traits_signature, p.is_active
      INTO v_sealed, v_active
      FROM public.card_printing_profile p
     WHERE p.id = v_profile_id;

    IF v_sealed IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_SEAL_NOT_APPLIED: traits_signature continua NULL depois de SET CONSTRAINTS IMMEDIATE. O trigger de selo não disparou — qualquer backfill a partir daqui seria vazio e silencioso. STOP.';
    END IF;

    IF cardinality(v_sealed) <> v_trait_count THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_SEAL_CARDINALITY: assinatura selada tem % traits, esperado %.', cardinality(v_sealed), v_trait_count;
    END IF;

    IF v_sealed IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_SEAL_MISMATCH: a assinatura selada não corresponde aos trait_ids informados (ordenados).';
    END IF;

    IF v_active IS NOT TRUE THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_NOT_ACTIVE: o Perfil recém-criado não está ativo. Estado estruturalmente inesperado. STOP.';
    END IF;

    -- =====================================================================
    -- PASSO 6 — SELEÇÃO DAS CANDIDATAS. Derivada do Perfil, nunca de literal.
    -- =====================================================================
    SELECT ARRAY(
        SELECT r.id
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set cs    ON cs.id = j.card_set_id
          JOIN public.expansion e    ON e.id  = cs.expansion_id
          JOIN public.asset_source s ON s.code = j.source
          CROSS JOIN LATERAL internal.compute_variant_residual_signature(
              r.raw_data, e.game_id, s.id
          ) sig
         WHERE j.status = 'STAGED'
           AND r.decision_status = 'PENDING'
           AND r.persistence_status = 'PENDING'
           AND e.game_id = v_game_id
           AND sig.printing_profile_id = v_profile_id
         ORDER BY r.id
    ) INTO v_row_ids;

    IF v_row_ids IS NULL OR cardinality(v_row_ids) = 0 THEN
        -- Nenhuma linha a reconciliar é desfecho LEGÍTIMO.
        v_row_ids := ARRAY[]::UUID[];
        v_job_ids := ARRAY[]::UUID[];
    ELSE
        SELECT ARRAY(
            SELECT DISTINCT r.job_id
              FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_row_ids)
             ORDER BY 1
        ) INTO v_job_ids;

        -- =================================================================
        -- PASSO 7 — LOCKS. Ordem JOB -> ROW, determinística nos dois níveis.
        -- =================================================================
        PERFORM 1
           FROM public.catalog_variant_import_job j
          WHERE j.id = ANY(v_job_ids)
          ORDER BY j.id
            FOR UPDATE;

        PERFORM 1
           FROM public.catalog_variant_import_row r
          WHERE r.id = ANY(v_row_ids)
          ORDER BY r.id
            FOR UPDATE;

        -- =================================================================
        -- PASSO 8 — RECONCILIAÇÃO. Set-based, uma única instrução.
        -- =================================================================
        WITH touched AS (
            SELECT r.id,
                   r.job_id,
                   sig.printing_state,
                   sig.printing_profile_id,
                   sig.residual_type,
                   sig.residual_foil,
                   sig.residual_subtype,
                   sig.residual_stamp,
                   e.game_id AS game_id,
                   s.id      AS asset_source_id
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
              JOIN public.card_set cs    ON cs.id = j.card_set_id
              JOIN public.expansion e    ON e.id  = cs.expansion_id
              JOIN public.asset_source s ON s.code = j.source
              CROSS JOIN LATERAL internal.compute_variant_residual_signature(
                  r.raw_data, e.game_id, s.id
              ) sig
             WHERE r.id = ANY(v_row_ids)
               AND j.status = 'STAGED'
               AND r.decision_status = 'PENDING'
               AND r.persistence_status = 'PENDING'
        ),
        classified AS (
            SELECT t.id,
                   t.job_id,
                   t.printing_profile_id,
                   vm.variant_type_id,
                   CASE
                     WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                          THEN 'C'
                     WHEN vm.variant_type_id IS NOT NULL
                          THEN 'A'
                     ELSE 'B'
                   END AS outcome
              FROM touched t
              LEFT JOIN public.card_variant_type_external_mapping vm
                ON vm.game_id = t.game_id
               AND vm.asset_source_id = t.asset_source_id
               AND vm.normalized_type = t.residual_type
               AND COALESCE(vm.normalized_foil, '')    = COALESCE(t.residual_foil, '')
               AND COALESCE(vm.normalized_subtype, '') = COALESCE(t.residual_subtype, '')
               AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(t.residual_stamp, '{}'::TEXT[])
        ),
        -- ---------------------------------------------------------------
        -- CONTRATO NEW-ONLY (GATE-A-REV-03). Preservado da 2189 v2.1.
        --
        -- Não há lookup em public.card_variant aqui, e não pode haver.
        -- Um Printing Profile RECÉM-CRIADO não pode possuir card_variant
        -- preexistente referenciando seu UUID.
        -- ---------------------------------------------------------------
        updated AS (
            UPDATE public.catalog_variant_import_row r
               SET normalized_data =
                       CASE c.outcome
                           WHEN 'A' THEN
                               jsonb_set(
                                   jsonb_set(r.normalized_data,
                                             '{variant_type_id}',
                                             to_jsonb(c.variant_type_id::TEXT), true),
                                   '{printing_profile_id}',
                                   CASE WHEN c.printing_profile_id IS NULL
                                        THEN 'null'::JSONB
                                        ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                   true)
                           WHEN 'B' THEN
                               jsonb_set(
                                   r.normalized_data - 'variant_type_id',
                                   '{printing_profile_id}',
                                   CASE WHEN c.printing_profile_id IS NULL
                                        THEN 'null'::JSONB
                                        ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                   true)
                           ELSE
                               (r.normalized_data - 'variant_type_id') - 'printing_profile_id'
                       END,
                   validation_status =
                       CASE c.outcome WHEN 'A' THEN 'VALID' ELSE 'NEEDS_REVIEW' END,
                   match_status        = 'NEW',
                   matched_variant_id  = NULL,
                   error_detail        = NULL
              FROM classified c
             WHERE r.id = c.id
            RETURNING r.id, r.job_id, c.outcome
        )
        SELECT
            (SELECT count(*) FROM touched),
            (SELECT count(*) FROM updated),
            (SELECT count(*) FROM updated WHERE outcome = 'A'),
            (SELECT count(*) FROM updated WHERE outcome IN ('B', 'C')),
            (SELECT count(DISTINCT job_id) FROM updated)
          INTO v_touched, v_reconciled, v_revalidated, v_pending, v_jobs;

        -- =================================================================
        -- GUARDS DE RECONCILIAÇÃO.
        -- =================================================================
        IF v_reconciled IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
                v_touched, v_reconciled;
        END IF;

        IF (v_revalidated + v_pending) IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
                v_revalidated, v_pending, v_touched;
        END IF;

        -- =================================================================
        -- PASSO 9 — CONTADORES DOS JOBS AFETADOS.
        -- SOMENTE total_rows e valid_rows.
        -- =================================================================
        UPDATE public.catalog_variant_import_job j
           SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id),
               valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id AND r.validation_status = 'VALID')
         WHERE j.id = ANY(v_job_ids);
    END IF;

    -- =====================================================================
    -- PASSO 10 — RESTAURAR O MODO DIFERIDO DO SELO.
    -- =====================================================================
    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

    -- =====================================================================
    -- PASSO 11 — AUDITORIA. Exatamente 1 evento por Perfil criado.
    -- actor_id = p_actor_id, nunca uma identidade inferida.
    -- =====================================================================
    INSERT INTO public.catalog_admin_action_log
        (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        p_actor_id,
        'CARD_PRINTING_PROFILE_CREATED',
        'CARD_PRINTING_PROFILE',
        v_profile_id,
        jsonb_build_object(
            'game_id',            v_game_id,
            'code',               v_code,
            'name',               v_name,
            'display_order',      p_display_order,
            'trait_ids',          to_jsonb(v_expected),
            'traits_signature',   to_jsonb(v_sealed),
            'rows_touched',       v_touched,
            'rows_revalidated',   v_revalidated,
            'rows_still_pending', v_pending,
            'jobs_affected',      v_jobs
        )
    );

    RETURN QUERY
        SELECT v_profile_id, v_sealed, v_touched, v_revalidated, v_pending, v_jobs;
END;
$worker$;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   1 função substituída (internal). A RPC pública NÃO é tocada.
--   ACL preservada por CREATE OR REPLACE — VERIFICAR, não presumir.
--
-- Como validar:
--   Query 2825 v3.6 — exigir 29 PASS / 0 FAIL.
-- ============================================================================
