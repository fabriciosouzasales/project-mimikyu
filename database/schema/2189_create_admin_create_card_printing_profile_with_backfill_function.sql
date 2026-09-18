/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2189 - Create admin_create_card_printing_profile_with_backfill()
              (+ worker internal.create_card_printing_profile_with_backfill)
Versão......: 3.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / RECONCILIADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-13 (execução) · 2026-09-18 (promoção canônica)
Ledger......: 20260913234802 / 2189_create_admin_create_card_printing_profile_with_backfill_function_v21
Promovida...: 2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01

Descrição...:
Cadastro de um Perfil de Impressão (card_printing_profile) com sua
composição de traços, em uma única transação, seguido de backfill e
revalidação das linhas de staging afetadas.

Dois objetos, um contrato:
- internal.create_card_printing_profile_with_backfill() — worker, recebe
  o ator já resolvido; nunca exposto a nenhuma role;
- public.admin_create_card_printing_profile_with_backfill() — RPC
  SECURITY DEFINER; resolve a identidade da sessão (auth.uid()) e delega.

Esta é a forma que uma INSTALAÇÃO LIMPA deve executar. As cópias dos
ciclos originais permanecem em database/proposals/ como evidência
histórica, e as migrations em database/migrations/.

Pré-requisitos:
- Query 2165/2166/2167 - Card Printing Trait / Profile / Profile Trait.
- Query 2176 - compute_variant_residual_signature() (v2.0).
- Query 2188 - Widen catalog_admin_action_log for Printing Profile.
- Query 1060 - Create is_admin() Function.

----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação do par worker + RPC (2026-09-13).** Não promovida: o
        arquivo do ciclo permaneceu em proposals/. |
| 2.1 | **Versão efetivamente executada no LIVE (2026-09-13, ledger
        `20260913234802`).** É o `_v21` do nome no ledger. |
| 3.0 | **Estado terminal consolidado (2026-09-18, BULK-STP-01-CANONICAL-
        RECONCILIATION-IMPLEMENTATION-01).** Promoção canônica com fold-in das
        duas camadas posteriores que o LIVE já possuía:
        · **`2190`** (`migrations/`, ledger `20260914000431`) — correção da
          agregação UUID no backfill;
        · **`2196`** (`migrations/`, ledger `20260914025208`) — parte
          alteradora do worker, para respeitar escopo `GLOBAL`/`SOURCE_SET`.
        O corpo do worker aqui é o de `2196`, terminal e provado equivalente
        ao LIVE. As duas migrations permanecem em `database/migrations/`
        como histórico. |
================================================================
*/

BEGIN;

-- =============================================================================
-- WORKER — internal.create_card_printing_profile_with_backfill()
--
-- Superfície OWNER-ONLY. Concentra TODA a lógica transacional. Não conhece
-- auth.uid(): o administrador autorizador chega como p_actor_id e é validado
-- contra public.admin_user.
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
    -- GUARD 1 — ATOR. Primeira instrução.
    IF p_actor_id IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_ACTOR: p_actor_id é obrigatório. Toda criação de Perfil precisa de um administrador autorizador nomeado.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.admin_user a WHERE a.id = p_actor_id) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_ACTOR_NOT_ADMIN: p_actor_id (%) não corresponde a um administrador cadastrado em public.admin_user.', p_actor_id;
    END IF;

    -- GUARD 2 — ESCALARES.
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

    -- GUARD 3 — FORMA DO ARRAY DE TRAITS.
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

    -- GUARD 4 — EXISTÊNCIA, ATIVIDADE E GAME ÚNICO.
    -- array_agg(DISTINCT ... ORDER BY ...)[1] preservado da Query
    -- 2190: PostgreSQL não tem min(uuid).
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

    -- GUARD 5 — UNICIDADE.
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

    -- PASSO 1 — CRIAR O PERFIL "EM MONTAGEM".
    INSERT INTO public.card_printing_profile
        (game_id, code, name, description, display_order)
    VALUES
        (v_game_id, v_code, v_name, v_description, p_display_order)
    RETURNING id INTO v_profile_id;

    -- PASSO 2 — COMPOSIÇÃO.
    INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
    SELECT v_profile_id, t, v_game_id FROM unnest(v_expected) AS t;

    -- PASSO 3 — FORÇAR O SELO.
    SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;

    -- PASSOS 4 e 5 — RELER E PROVAR O SELO.
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

    -- PASSO 6 — SELEÇÃO DAS CANDIDATAS.
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
        v_row_ids := ARRAY[]::UUID[];
        v_job_ids := ARRAY[]::UUID[];
    ELSE
        SELECT ARRAY(
            SELECT DISTINCT r.job_id
              FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_row_ids)
             ORDER BY 1
        ) INTO v_job_ids;

        -- PASSO 7 — LOCKS. Ordem JOB -> ROW.
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

        -- PASSO 8 — RECONCILIAÇÃO.
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
                   s.id      AS asset_source_id,
                   cs.id     AS card_set_id      -- >>> DIFF 2196 <<<
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
            -- >>> DIFF 2196: lookup com precedência scoped > global.
            -- Substitui o LEFT JOIN direto contra
            -- card_variant_type_external_mapping.
            --
            -- >>> CORRIGIDO EM GATE-A-REV-01 <<<
            -- A v1.0 chamava o helper DUAS vezes por row (uma para
            -- a coluna, outra dentro do CASE). O helper resolve o
            -- escopo e varre o mapping — duplicar a chamada dobra o
            -- trabalho por linha sem nenhum ganho, e o planner não
            -- tem como deduplicar com segurança uma função STABLE
            -- em contextos distintos da mesma projeção.
            --
            -- LEFT JOIN LATERAL resolve UMA vez por row e o valor é
            -- reutilizado nos dois pontos. Semântica idêntica:
            -- LATERAL sobre função escalar produz exatamente uma
            -- linha (NULL inclusive), então nenhuma row de `touched`
            -- é perdida nem duplicada.
            SELECT t.id,
                   t.job_id,
                   t.printing_profile_id,
                   lk.variant_type_id,
                   CASE
                     WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                          THEN 'C'
                     WHEN lk.variant_type_id IS NOT NULL
                          THEN 'A'
                     ELSE 'B'
                   END AS outcome
              FROM touched t
              LEFT JOIN LATERAL (
                  SELECT internal.lookup_variant_type_for_row(
                             t.game_id, t.asset_source_id, t.card_set_id,
                             t.residual_type, t.residual_foil,
                             t.residual_subtype, t.residual_stamp
                         ) AS variant_type_id
              ) lk ON TRUE
        ),
        -- CONTRATO NEW-ONLY (GATE-A-REV-03): sem lookup em public.card_variant.
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

        IF v_reconciled IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
                v_touched, v_reconciled;
        END IF;

        IF (v_revalidated + v_pending) IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
                v_revalidated, v_pending, v_touched;
        END IF;

        -- PASSO 9 — CONTADORES DOS JOBS AFETADOS.
        UPDATE public.catalog_variant_import_job j
           SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id),
               valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id AND r.validation_status = 'VALID')
         WHERE j.id = ANY(v_job_ids);
    END IF;

    -- PASSO 10 — RESTAURAR O MODO DIFERIDO DO SELO.
    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

    -- PASSO 11 — AUDITORIA.
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

-- -----------------------------------------------------------------------------
-- O worker é OWNER-ONLY. Nenhum papel externo executa. O único caminho de
-- aplicação é (a) a RPC pública abaixo, que é SECURITY DEFINER e portanto roda
-- como owner, ou (b) manutenção explícita pelo próprio owner.
-- Mesmo princípio de isolamento de internal.write_card() e
-- internal.persist_catalog_import_revalidation().
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM anon;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM authenticated;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM service_role;

-- =============================================================================
-- FRONTEIRA PÚBLICA — public.admin_create_card_printing_profile_with_backfill()
--
-- FINA por decisão de desenho. Ela responde por UMA coisa: provar que quem
-- chamou é administrador e informar QUEM é. Toda a semântica está no worker.
-- Duplicar qualquer regra aqui criaria dois lugares para corrigir o mesmo bug.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_create_card_printing_profile_with_backfill(
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
AS $rpc$
DECLARE
    v_actor UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_PRINTING_PROFILE_FORBIDDEN: apenas administradores podem cadastrar um Perfil de Impressão.';
    END IF;

    -- Identidade da sessão real. NUNCA vem do corpo da chamada.
    v_actor := auth.uid();

    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_PRINTING_PROFILE_NO_SESSION: is_admin() passou mas auth.uid() é NULL. Estado inconsistente — não há ator a registrar. STOP.';
    END IF;

    RETURN QUERY
        SELECT w.profile_id, w.traits_signature, w.rows_touched,
               w.rows_revalidated, w.rows_still_pending, w.jobs_affected
          FROM internal.create_card_printing_profile_with_backfill(
                   v_actor, p_code, p_name, p_description, p_display_order, p_trait_ids
               ) w;
END;
$rpc$;

REVOKE ALL ON FUNCTION public.admin_create_card_printing_profile_with_backfill(TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_card_printing_profile_with_backfill(TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_create_card_printing_profile_with_backfill(TEXT, TEXT, TEXT, INTEGER, UUID[]) TO authenticated;
-- service_role NÃO recebe grant: não há Edge Function no caminho desta operação.

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   2 funções criadas (1 internal owner-only, 1 public admin-gated).
--
-- DOIS CAMINHOS OPERACIONAIS LEGÍTIMOS (nenhum depende de JWT fabricado):
--
--   A. SESSÃO ADMINISTRATIVA REAL DA APLICAÇÃO.
--
--      Uma sessão em que o usuário autenticou pelo GoTrue e o JWT dele chega
--      ao Postgres, de modo que auth.uid() devolve o id real e is_admin()
--      avalia esse id. Hoje isso significa a UI/servidor da aplicação.
--
--      O SQL Editor do painel Supabase NÃO é esse caminho. Ele executa com
--      papel administrativo do banco e SEM request.jwt.claims: auth.uid()
--      é NULL, is_admin() é FALSE e esta RPC recusa com _FORBIDDEN. Isso é o
--      comportamento correto, não um defeito — e é exatamente o que o caso A
--      da Query 2825 prova. Para operar pelo SQL Editor, use o caminho B.
--
--        SELECT * FROM public.admin_create_card_printing_profile_with_backfill(
--            'FIRST_EDITION',
--            '1ª Edição',
--            'Perfil de impressão com selo de 1ª Edição, sem outras marcas de tiragem.',
--            7,
--            ARRAY[(SELECT id FROM public.card_printing_trait
--                    WHERE code = 'FIRST_EDITION'
--                      AND game_id = (SELECT id FROM public.game WHERE code = 'POKEMON'))]
--        );
--
--   B. MANUTENÇÃO EXPLICITAMENTE AUTORIZADA, por owner/postgres, com o
--      administrador autorizador NOMEADO em p_actor_id.
--
--      É este o caminho do SQL Editor e de qualquer operação de manutenção.
--      Não há JWT envolvido: p_actor_id é parâmetro de auditoria, informado
--      por quem executa e validado contra public.admin_user. Registra-se no
--      action log o admin que autorizou, não o papel do banco.
--
--        SELECT * FROM internal.create_card_printing_profile_with_backfill(
--            '<uuid do admin que autorizou>',
--            'FIRST_EDITION',
--            '1ª Edição',
--            'Perfil de impressão com selo de 1ª Edição, sem outras marcas de tiragem.',
--            7,
--            ARRAY[(SELECT id FROM public.card_printing_trait
--                    WHERE code = 'FIRST_EDITION'
--                      AND game_id = (SELECT id FROM public.game WHERE code = 'POKEMON'))]
--        );
--
--   Retorno esperado em 2026-09-13, nos dois caminhos:
--     rows_touched = 62 | rows_revalidated = 16 | rows_still_pending = 46
--     jobs_affected = 1 (BASE3)
--
-- Como validar:
--   Query 2825 - Validate Card Printing Profile Creation Backfill.
-- ============================================================================

-- ================================================================
-- CONFIRMADO EXECUTADO / LIVE.
--
-- Esta Query CANÔNICA foi promovida/reconciliada em 2026-09-18
-- (BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01): o corpo
-- representa o ESTADO TERMINAL LIVE, provado equivalente por md5(prosrc)
-- normalizado contra pg_get_functiondef do Supabase (qjfutqujxrbzgrtkpgkg).
--
-- NÃO foi reexecutada contra o LIVE — promoção/fold-in canônico é alteração
-- de arquivo, não execução. As migrations históricas seguem preservadas em
-- database/migrations/.
-- ================================================================
