/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2273 - Resolução administrativa de Contexto de Edição na importação — P3a
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de Fabrício (ensaio e aplicação no LIVE).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-12
Depende.....: 2211/2243 (resolve_variant_row_axes), 2196 (lookup_variant_type_for_row), 2193
              (resolve_variant_mapping_scope), 2181 (RPC de Impressão), 2270 (CHECKs do log).
Aplicar.....: depois da 2271 e da 2272; a 2274 usa os helpers criados aqui.

O que faz
  1. internal.variant_import_rows_with_token(game, fonte, código da fonte, campo, token,
     external_set_id, ignorar_overrides_de_set) — seleção ÚNICA das linhas em revisão que contêm
     o item: job STAGED da mesma fonte e jogo, decisão PENDING, validação VALID/NEEDS_REVIEW
     (o mesmo recorte da RPC de Impressão 2181). Com external_set_id: só aquele Set (escopo
     externo oficial). Com o flag: exclui Sets que têm mapeamento de Contexto ESPECÍFICO ativo
     para o mesmo item (lá o global não manda). Usado pela 2273 e pela prévia 2272.
  2. internal.reconcile_variant_import_rows(row_ids[]) — a reconciliação A/B/C das linhas,
     transcrita da canônica mais recente (create_card_printing_profile_with_backfill v4.0,
     passos 7–9): trava job→linha, reavalia pelos 3 eixos oficiais, grava as 3 chaves,
     validation_status, match_status NEW e recalcula total/valid do job. As RPCs existentes não
     foram alteradas; as novas (2273/2274) usam esta única cópia.
  3. Trava de eixos (cuidado 2): internal.guard_axis_mapping_overlap() em INSERT de
     card_printing_external_mapping e card_edition_context_external_mapping. Recusa um
     mapeamento ATIVO de Impressão para (jogo, fonte, campo, item) se existir mapeamento ATIVO
     de Contexto para o mesmo item, e vice-versa. Impressão é sempre global e é avaliada antes
     do Contexto, então os escopos SEMPRE se sobrepõem — por isso não há exceção por Set.
     Contexto x Contexto em Sets diferentes, ou específico x global, NÃO é conflito (o
     específico do Set prevalece, mesma precedência do resolvedor). LIVE: 0 sobreposições hoje.
  4. CHECKs do log: + CARD_EDITION_CONTEXT_EXTERNAL_MAPPING_CREATED
     (entidade CARD_EDITION_CONTEXT_EXTERNAL_MAPPING) e CARD_EDITION_CONTEXT_PROFILE_CREATED
     (entidade CARD_EDITION_CONTEXT_PROFILE, usada pela 2274).
  5. public.admin_resolve_catalog_variant_import_edition_context_mapping(
        p_row_id, p_raw_field, p_token, p_trait_ids, p_scope DEFAULT 'SOURCE_SET')
     Espelho da RPC de Impressão: só admin; campo subtype|foil|stamp; características de
     Contexto ativas do mesmo jogo (1..20, sem repetição); a linha de origem precisa conter o
     item (evidência editorial); escopo SOURCE_SET (padrão — usa o external_set_id oficial do
     Card Set da linha; recusa se o Set não tiver referência externa ativa) ou GLOBAL;
     recusa item com Impressão ativa; recusa composição idêntica à ativa do mesmo escopo
     (NO_CHANGE); aposenta o mapeamento ativo do MESMO escopo (histórico preservado — o
     trigger da tabela impede reativar) e cria o novo; reconcilia só as linhas atingidas;
     log CARD_EDITION_CONTEXT_EXTERNAL_MAPPING_CREATED.

Como validar
  select has_function_privilege('authenticated','public.admin_resolve_catalog_variant_import_edition_context_mapping(uuid,text,text,uuid[],text)','EXECUTE') as auth_ok,
         has_function_privilege('anon','public.admin_resolve_catalog_variant_import_edition_context_mapping(uuid,text,text,uuid[],text)','EXECUTE') as anon_must_be_false,
         has_function_privilege('authenticated','internal.reconcile_variant_import_rows(uuid[])','EXECUTE') as helper_must_be_false,
         (select count(*) from pg_trigger where tgname in ('trg_card_printing_external_mapping_zz_axis_overlap','trg_cecem_zz_axis_overlap')) as triggers_must_be_2,
         (select count(*) from pg_constraint where conrelid='public.catalog_admin_action_log'::regclass
            and pg_get_constraintdef(oid) like '%CARD_EDITION_CONTEXT_PROFILE_CREATED%') as checks_must_be_2;
===============================================================================
*/

-- 1. Seleção única das linhas em revisão que contêm o item
CREATE OR REPLACE FUNCTION internal.variant_import_rows_with_token(
  p_game_id uuid, p_asset_source_id uuid, p_source_code text, p_raw_field text, p_token text,
  p_external_set_id text, p_skip_ec_scoped_overrides boolean)
RETURNS TABLE(row_id uuid, job_id uuid, card_set_id uuid, external_set_id text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT r.id, r.job_id, j.card_set_id, sc.external_set_id
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
    JOIN public.card_set cs ON cs.id = j.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, p_asset_source_id) sc ON TRUE
   WHERE j.status = 'STAGED'
     AND j.source = p_source_code
     AND e.game_id = p_game_id
     AND r.decision_status = 'PENDING'
     AND r.validation_status IN ('VALID', 'NEEDS_REVIEW')
     AND (   (p_raw_field = 'subtype' AND public.normalize_external_catalog_value(r.raw_data ->> 'subtype') = p_token)
          OR (p_raw_field = 'foil'    AND public.normalize_external_catalog_value(r.raw_data ->> 'foil') = p_token)
          OR (p_raw_field = 'stamp'   AND jsonb_typeof(r.raw_data -> 'stamp') = 'array'
              AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(r.raw_data -> 'stamp') x
                           WHERE public.normalize_external_catalog_value(x) = p_token)))
     AND (p_external_set_id IS NULL OR sc.external_set_id = p_external_set_id)
     AND (NOT p_skip_ec_scoped_overrides OR NOT EXISTS (
            SELECT 1 FROM public.card_edition_context_external_mapping m
             WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
               AND m.raw_field = p_raw_field AND m.normalized_token = p_token
               AND m.is_active AND m.external_set_id IS NOT NULL
               AND m.external_set_id = sc.external_set_id))
   ORDER BY r.id;
$$;

REVOKE ALL ON FUNCTION internal.variant_import_rows_with_token(uuid, uuid, text, text, text, text, boolean) FROM PUBLIC, anon, authenticated;

-- 2. Reconciliação A/B/C (cópia única da canônica v4.0 para as RPCs novas)
CREATE OR REPLACE FUNCTION internal.reconcile_variant_import_rows(p_row_ids uuid[])
RETURNS TABLE(rows_touched integer, rows_revalidated integer, rows_still_pending integer,
              jobs_affected integer, rows_blocked_edition_context integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job_ids    uuid[];
  v_touched    integer := 0;
  v_reconciled integer := 0;
  v_revalid    integer := 0;
  v_pending    integer := 0;
  v_jobs       integer := 0;
  v_blocked_ec integer := 0;
BEGIN
  IF p_row_ids IS NULL OR cardinality(p_row_ids) = 0 THEN
    RETURN QUERY SELECT 0, 0, 0, 0, 0;
    RETURN;
  END IF;

  v_job_ids := ARRAY(SELECT DISTINCT r.job_id FROM public.catalog_variant_import_row r
                      WHERE r.id = ANY (p_row_ids) ORDER BY 1);

  -- Locks na ordem JOB -> ROW (mesma da canônica).
  PERFORM 1 FROM public.catalog_variant_import_job j WHERE j.id = ANY (v_job_ids) ORDER BY j.id FOR UPDATE;
  PERFORM 1 FROM public.catalog_variant_import_row r WHERE r.id = ANY (p_row_ids) ORDER BY r.id FOR UPDATE;

  WITH touched AS (
    SELECT r.id, r.job_id,
           ax.printing_state, ax.printing_profile_id,
           ax.edition_context_state, ax.edition_context_profile_id,
           ax.residual_type, ax.residual_foil, ax.residual_subtype, ax.residual_stamp,
           e.game_id AS game_id, s.id AS asset_source_id, cs.id AS card_set_id
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card_set cs    ON cs.id = j.card_set_id
      JOIN public.expansion e    ON e.id  = cs.expansion_id
      JOIN public.asset_source s ON s.code = j.source
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, s.id) sc ON TRUE
      CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, e.game_id, s.id, sc.external_set_id) ax
     WHERE r.id = ANY (p_row_ids)
       AND j.status = 'STAGED'
       AND r.decision_status = 'PENDING'
  ),
  classified AS (
    SELECT t.id, t.job_id, t.printing_profile_id, t.edition_context_profile_id, lk.variant_type_id,
           CASE
             WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE') THEN 'C'
             WHEN t.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE') THEN 'C'
             WHEN lk.variant_type_id IS NOT NULL THEN 'A'
             ELSE 'B'
           END AS outcome,
           (t.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
            AND t.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE'))
             AS blocked_by_edition_context
      FROM touched t
      LEFT JOIN LATERAL (
        SELECT internal.lookup_variant_type_for_row(
                 t.game_id, t.asset_source_id, t.card_set_id,
                 t.residual_type, t.residual_foil, t.residual_subtype, t.residual_stamp) AS variant_type_id
      ) lk ON TRUE
  ),
  updated AS (
    UPDATE public.catalog_variant_import_row r
       SET normalized_data =
             CASE c.outcome
               WHEN 'A' THEN
                 jsonb_set(jsonb_set(jsonb_set(r.normalized_data,
                   '{variant_type_id}', to_jsonb(c.variant_type_id::text), true),
                   '{printing_profile_id}',
                   CASE WHEN c.printing_profile_id IS NULL THEN 'null'::jsonb ELSE to_jsonb(c.printing_profile_id::text) END, true),
                   '{edition_context_profile_id}',
                   CASE WHEN c.edition_context_profile_id IS NULL THEN 'null'::jsonb ELSE to_jsonb(c.edition_context_profile_id::text) END, true)
               WHEN 'B' THEN
                 jsonb_set(jsonb_set(r.normalized_data - 'variant_type_id',
                   '{printing_profile_id}',
                   CASE WHEN c.printing_profile_id IS NULL THEN 'null'::jsonb ELSE to_jsonb(c.printing_profile_id::text) END, true),
                   '{edition_context_profile_id}',
                   CASE WHEN c.edition_context_profile_id IS NULL THEN 'null'::jsonb ELSE to_jsonb(c.edition_context_profile_id::text) END, true)
               ELSE
                 ((r.normalized_data - 'variant_type_id') - 'printing_profile_id') - 'edition_context_profile_id'
             END,
           validation_status  = CASE c.outcome WHEN 'A' THEN 'VALID' ELSE 'NEEDS_REVIEW' END,
           match_status       = 'NEW',
           matched_variant_id = NULL,
           error_detail       = NULL
      FROM classified c
     WHERE r.id = c.id
    RETURNING r.id, r.job_id, c.outcome, c.blocked_by_edition_context
  )
  SELECT (SELECT count(*) FROM touched),
         (SELECT count(*) FROM updated),
         (SELECT count(*) FROM updated WHERE outcome = 'A'),
         (SELECT count(*) FROM updated WHERE outcome IN ('B', 'C')),
         (SELECT count(DISTINCT job_id) FROM updated),
         (SELECT count(*) FROM updated WHERE blocked_by_edition_context)
    INTO v_touched, v_reconciled, v_revalid, v_pending, v_jobs, v_blocked_ec;

  IF v_reconciled IS DISTINCT FROM v_touched THEN
    RAISE EXCEPTION 'RECONCILE_VARIANT_IMPORT_ROWS_GAP: % linha(s) atingidas, % reconciliadas.', v_touched, v_reconciled;
  END IF;
  IF (v_revalid + v_pending) IS DISTINCT FROM v_touched THEN
    RAISE EXCEPTION 'RECONCILE_VARIANT_IMPORT_ROWS_COUNTER_GAP: % + % <> %.', v_revalid, v_pending, v_touched;
  END IF;
  IF v_blocked_ec > v_pending THEN
    RAISE EXCEPTION 'RECONCILE_VARIANT_IMPORT_ROWS_CAUSE_GAP: % > %.', v_blocked_ec, v_pending;
  END IF;

  UPDATE public.catalog_variant_import_job j
     SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r WHERE r.job_id = j.id),
         valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                        WHERE r.job_id = j.id AND r.validation_status = 'VALID')
   WHERE j.id = ANY (v_job_ids);

  RETURN QUERY SELECT v_touched, v_revalid, v_pending, v_jobs, v_blocked_ec;
END;
$$;

REVOKE ALL ON FUNCTION internal.reconcile_variant_import_rows(uuid[]) FROM PUBLIC, anon, authenticated;

-- 3. Trava de eixos: o mesmo item nunca ativo em Impressão e em Contexto ao mesmo tempo
CREATE OR REPLACE FUNCTION internal.guard_axis_mapping_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT NEW.is_active THEN
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'card_printing_external_mapping' THEN
    IF EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping m
                WHERE m.game_id = NEW.game_id AND m.asset_source_id = NEW.asset_source_id
                  AND m.raw_field = NEW.raw_field AND m.normalized_token = NEW.normalized_token
                  AND m.is_active) THEN
      RAISE EXCEPTION 'AXIS_MAPPING_OVERLAP: o item %:% já está mapeado como Contexto de Edição. Um item não pode ser Impressão e Contexto de Edição ao mesmo tempo.',
        NEW.raw_field, NEW.normalized_token USING ERRCODE = 'MV002';
    END IF;
  ELSE
    IF EXISTS (SELECT 1 FROM public.card_printing_external_mapping m
                WHERE m.game_id = NEW.game_id AND m.asset_source_id = NEW.asset_source_id
                  AND m.raw_field = NEW.raw_field AND m.normalized_token = NEW.normalized_token
                  AND m.is_active) THEN
      RAISE EXCEPTION 'AXIS_MAPPING_OVERLAP: o item %:% já está mapeado como Impressão (global). Um item não pode ser Impressão e Contexto de Edição ao mesmo tempo.',
        NEW.raw_field, NEW.normalized_token USING ERRCODE = 'MV002';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.guard_axis_mapping_overlap() FROM PUBLIC, anon, authenticated;

-- "zz" para rodar depois dos triggers de normalização do item (ordem alfabética).
CREATE TRIGGER trg_card_printing_external_mapping_zz_axis_overlap
  BEFORE INSERT ON public.card_printing_external_mapping
  FOR EACH ROW EXECUTE FUNCTION internal.guard_axis_mapping_overlap();

CREATE TRIGGER trg_cecem_zz_axis_overlap
  BEFORE INSERT ON public.card_edition_context_external_mapping
  FOR EACH ROW EXECUTE FUNCTION internal.guard_axis_mapping_overlap();

-- 4. Log administrativo
ALTER TABLE public.catalog_admin_action_log
  DROP CONSTRAINT ck_catalog_admin_action_log_action_valid,
  DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

ALTER TABLE public.catalog_admin_action_log
  ADD CONSTRAINT ck_catalog_admin_action_log_action_valid CHECK (action = ANY (ARRAY[
    'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
    'EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED',
    'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED',
    'CARD_VARIANT_DEFAULT_SET', 'CARD_VARIANT_CREATED',
    'CARD_VARIANT_DEACTIVATED', 'CARD_VARIANT_REACTIVATED',
    'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED',
    'RARITY_CREATED', 'RARITY_UPDATED',
    'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED',
    'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
    'CARD_VARIANT_IMPORT_CONFIRMED', 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED',
    'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
    'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
    'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED',
    'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED',
    'CARD_PRINTING_EXTERNAL_MAPPING_CREATED', 'CARD_PRINTING_PROFILE_CREATED',
    'CARD_EDITION_CONTEXT_EXTERNAL_MAPPING_CREATED', 'CARD_EDITION_CONTEXT_PROFILE_CREATED'
  ]::text[])),
  ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match CHECK (
       (entity_type = 'GAME' AND action = ANY (ARRAY['GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED']::text[]))
    OR (entity_type = 'EXPANSION' AND action = ANY (ARRAY['EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED']::text[]))
    OR (entity_type = 'CARD_SET' AND action = ANY (ARRAY['CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
                                                         'CARD_ASSET_MANUAL_IMPORT_COMPLETED']::text[]))
    OR (entity_type = 'CARD' AND action = ANY (ARRAY['CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED',
                                                     'CARD_VARIANT_DEFAULT_SET', 'CARD_VARIANT_CREATED',
                                                     'CARD_VARIANT_DEACTIVATED', 'CARD_VARIANT_REACTIVATED']::text[]))
    OR (entity_type = 'CATALOG_IMPORT_JOB' AND action = ANY (ARRAY['CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED',
                                                                   'CATALOG_IMPORT_ROWS_REVALIDATED']::text[]))
    OR (entity_type = 'RARITY' AND action = ANY (ARRAY['RARITY_CREATED', 'RARITY_UPDATED']::text[]))
    OR (entity_type = 'RARITY_EXTERNAL_MAPPING' AND action = ANY (ARRAY['RARITY_EXTERNAL_MAPPING_CREATED',
                                                                        'RARITY_EXTERNAL_MAPPING_UPDATED']::text[]))
    OR (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND action = ANY (ARRAY['CARD_VARIANT_IMPORT_CONFIRMED',
                                                                           'CARD_VARIANT_IMPORT_ROWS_REVALIDATED']::text[]))
    OR (entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' AND action = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED')
    OR (entity_type = 'CARD_VARIANT_TYPE' AND action = ANY (ARRAY['CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
                                                                  'CARD_VARIANT_TYPE_DEACTIVATED',
                                                                  'CARD_VARIANT_TYPE_REACTIVATED']::text[]))
    OR (entity_type = 'CARD_PRIMARY_SPECIES' AND action = ANY (ARRAY['CARD_PRIMARY_SPECIES_RESOLVED',
                                                                     'CARD_PRIMARY_SPECIES_CORRECTED']::text[]))
    OR (entity_type = 'CARD_PRINTING_EXTERNAL_MAPPING' AND action = 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
    OR (entity_type = 'CARD_PRINTING_PROFILE' AND action = 'CARD_PRINTING_PROFILE_CREATED')
    OR (entity_type = 'CARD_EDITION_CONTEXT_EXTERNAL_MAPPING' AND action = 'CARD_EDITION_CONTEXT_EXTERNAL_MAPPING_CREATED')
    OR (entity_type = 'CARD_EDITION_CONTEXT_PROFILE' AND action = 'CARD_EDITION_CONTEXT_PROFILE_CREATED')
  );

-- 5. RPC administrativa
CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_edition_context_mapping(
  p_row_id uuid, p_raw_field text, p_token text, p_trait_ids uuid[], p_scope text DEFAULT 'SOURCE_SET')
RETURNS TABLE(mapping_id uuid, superseded_mapping_id uuid, scope text, external_set_id text,
              rows_touched integer, rows_revalidated integer, rows_still_pending integer, jobs_affected integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $$
DECLARE
  c_max_traits CONSTANT integer := 20;
  v_row     public.catalog_variant_import_row%ROWTYPE;
  v_job     public.catalog_variant_import_job%ROWTYPE;
  v_game    uuid;
  v_src     uuid;
  v_token   text;
  v_sig     uuid[];
  v_scope   text;
  v_ext     text;
  v_old_id  uuid;
  v_old_sig uuid[];
  v_new_id  uuid;
  v_ids     uuid[];
  rc        record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_FORBIDDEN: apenas administradores podem resolver um mapeamento de contexto de edição.'
      USING ERRCODE = '42501';
  END IF;

  IF p_row_id IS NULL OR p_raw_field IS NULL OR p_token IS NULL OR p_trait_ids IS NULL THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_MISSING_ARGS: informe a linha, o campo, o item e as características.';
  END IF;
  IF p_raw_field NOT IN ('subtype', 'foil', 'stamp') THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_INVALID_FIELD: contexto de edição aceita só subtype, foil ou stamp (recebido: %).', p_raw_field;
  END IF;
  v_scope := upper(btrim(coalesce(p_scope, 'SOURCE_SET')));
  IF v_scope NOT IN ('SOURCE_SET', 'GLOBAL') THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_INVALID_SCOPE: escopo deve ser SOURCE_SET ou GLOBAL (recebido: %).', p_scope;
  END IF;
  IF array_ndims(p_trait_ids) <> 1 OR cardinality(p_trait_ids) = 0 THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_EMPTY_TRAITS: informe ao menos uma característica de contexto de edição.';
  END IF;
  IF cardinality(p_trait_ids) > c_max_traits THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_TOO_MANY_TRAITS: % características, acima do teto de %.', cardinality(p_trait_ids), c_max_traits;
  END IF;
  IF array_position(p_trait_ids, NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_NULL_TRAIT: a lista de características contém valor vazio.';
  END IF;
  v_sig := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) t ORDER BY t);
  IF cardinality(v_sig) <> cardinality(p_trait_ids) THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_DUPLICATE_TRAIT: a mesma característica foi informada mais de uma vez.';
  END IF;

  SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_ROW_NOT_FOUND: linha de importação não encontrada.';
  END IF;
  SELECT j.* INTO v_job FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;
  SELECT e.game_id INTO v_game
    FROM public.card c JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
   WHERE c.id = v_row.card_id;
  SELECT s.id INTO v_src FROM public.asset_source s WHERE s.code = v_job.source;
  IF v_game IS NULL OR v_src IS NULL THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_CONTEXT: não foi possível resolver o jogo ou a fonte desta linha.';
  END IF;

  IF (SELECT count(*) FROM public.card_edition_context_trait t
       WHERE t.id = ANY (v_sig) AND t.game_id = v_game AND t.is_active) <> cardinality(v_sig) THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_INVALID_TRAITS: uma ou mais características não existem, são de outro jogo ou estão inativas.';
  END IF;

  v_token := public.normalize_external_catalog_value(p_token);
  IF btrim(v_token) = '' THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_EMPTY_TOKEN: o item ficou vazio após a normalização.';
  END IF;

  -- Evidência editorial: a linha de origem precisa conter exatamente este item neste campo.
  IF NOT (
       (p_raw_field = 'subtype' AND public.normalize_external_catalog_value(v_row.raw_data ->> 'subtype') = v_token)
    OR (p_raw_field = 'foil'    AND public.normalize_external_catalog_value(v_row.raw_data ->> 'foil') = v_token)
    OR (p_raw_field = 'stamp'   AND jsonb_typeof(v_row.raw_data -> 'stamp') = 'array'
        AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_row.raw_data -> 'stamp') x
                     WHERE public.normalize_external_catalog_value(x) = v_token))) THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_ORIGIN_TOKEN_NOT_FOUND: a linha informada não contém %:%.', p_raw_field, v_token;
  END IF;

  IF v_scope = 'SOURCE_SET' THEN
    SELECT sc.external_set_id INTO v_ext
      FROM internal.resolve_variant_mapping_scope(v_job.card_set_id, v_src) sc;
    IF v_ext IS NULL THEN
      RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_NO_SET_SCOPE: este Card Set não tem referência externa ativa nesta fonte; use o escopo global ou cadastre a referência.';
    END IF;
  END IF;

  -- Conflito entre eixos (a trava da tabela é a barreira final; aqui a mensagem é legível).
  IF p_raw_field IN ('subtype', 'stamp') AND EXISTS (
       SELECT 1 FROM public.card_printing_external_mapping m
        WHERE m.game_id = v_game AND m.asset_source_id = v_src
          AND m.raw_field = p_raw_field AND m.normalized_token = v_token AND m.is_active) THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_PRINTING_ACTIVE: %:% já é Impressão (global, avaliada antes do contexto de edição). Um item não pode estar nos dois eixos.', p_raw_field, v_token;
  END IF;

  -- Mapeamento ativo do MESMO escopo (outro Set, ou global x Set, não é substituído).
  SELECT m.id,
         COALESCE(m.traits_signature, ARRAY(SELECT t.trait_id FROM public.card_edition_context_external_mapping_trait t
                                             WHERE t.mapping_id = m.id ORDER BY t.trait_id))
    INTO v_old_id, v_old_sig
    FROM public.card_edition_context_external_mapping m
   WHERE m.game_id = v_game AND m.asset_source_id = v_src
     AND m.raw_field = p_raw_field AND m.normalized_token = v_token
     AND m.is_active AND m.external_set_id IS NOT DISTINCT FROM v_ext
     FOR UPDATE;

  IF v_old_id IS NOT NULL AND v_old_sig = v_sig THEN
    RAISE EXCEPTION 'ADMIN_RESOLVE_EC_MAPPING_NO_CHANGE: o mapeamento ativo deste item neste escopo já tem exatamente estas características.';
  END IF;

  IF v_old_id IS NOT NULL THEN
    UPDATE public.card_edition_context_external_mapping SET is_active = false WHERE id = v_old_id;
  END IF;

  INSERT INTO public.card_edition_context_external_mapping
    (game_id, asset_source_id, external_set_id, raw_field, normalized_token, is_active)
  VALUES (v_game, v_src, v_ext, p_raw_field, v_token, true)
  RETURNING id INTO v_new_id;

  INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
  SELECT v_new_id, t, v_game FROM unnest(v_sig) t;

  -- Só as linhas atingidas: no escopo de Set, só aquele Set; no global, todos os Sets
  -- exceto os que têm mapeamento específico ativo para o mesmo item.
  v_ids := ARRAY(SELECT w.row_id FROM internal.variant_import_rows_with_token(
                   v_game, v_src, v_job.source, p_raw_field, v_token, v_ext, v_scope = 'GLOBAL') w);

  SELECT * INTO rc FROM internal.reconcile_variant_import_rows(v_ids);

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'CARD_EDITION_CONTEXT_EXTERNAL_MAPPING_CREATED', 'CARD_EDITION_CONTEXT_EXTERNAL_MAPPING', v_new_id,
          jsonb_build_object(
            'source', 'MANUAL',
            'game_id', v_game, 'asset_source_id', v_src,
            'scope', v_scope, 'external_set_id', v_ext,
            'raw_field', p_raw_field, 'external_token', p_token, 'normalized_token', v_token,
            'trait_ids', to_jsonb(v_sig),
            'supersedes_mapping_id', v_old_id,
            'origin_row_id', p_row_id,
            'rows_touched', rc.rows_touched,
            'rows_revalidated', rc.rows_revalidated,
            'rows_still_pending', rc.rows_still_pending,
            'rows_blocked_edition_context', rc.rows_blocked_edition_context,
            'jobs_affected', rc.jobs_affected,
            'axes_contract', 'resolve_variant_row_axes/v1'));

  RETURN QUERY SELECT v_new_id, v_old_id, v_scope, v_ext,
                      rc.rows_touched, rc.rows_revalidated, rc.rows_still_pending, rc.jobs_affected;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_edition_context_mapping(uuid, text, text, uuid[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_edition_context_mapping(uuid, text, text, uuid[], text) TO authenticated;
