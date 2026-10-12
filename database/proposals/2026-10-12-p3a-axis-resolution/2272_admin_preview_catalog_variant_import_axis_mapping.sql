/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2272 - Prévia do impacto de um mapeamento de Impressão ou Contexto de Edição — P3a
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de Fabrício (ensaio e aplicação no LIVE).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-12
Depende.....: 2181 (RPC de Impressão), 2273 (RPC de Contexto e seleção de linhas). Pode ser criada
              antes da 2273 (PL/pgSQL resolve as chamadas só na execução), mas só funciona depois.

O que faz
  public.admin_preview_catalog_variant_import_axis_mapping(
     p_row_id, p_axis 'PRINTING'|'EDITION_CONTEXT', p_raw_field, p_token, p_trait_ids uuid[],
     p_scope DEFAULT NULL)  RETURNS jsonb

  Prévia confiável SEM um segundo algoritmo: a função executa a PRÓPRIA RPC de escrita
  (Impressão: admin_resolve_catalog_variant_import_printing_mapping; Contexto:
  admin_resolve_catalog_variant_import_edition_context_mapping) dentro de um subbloco, lê o
  resultado de cada linha atingida pelo resolvedor oficial e DESFAZ o subbloco (SQLSTATE PV001).
  Nada é gravado: mapeamento, reconciliação, contadores e log são revertidos juntos.
  Só admin (a RPC simulada também exige admin). Locks tomados no subbloco são soltos no rollback.

  Escopo: Impressão é sempre GLOBAL (a tabela não tem escopo de Set); Contexto aceita
  SOURCE_SET (padrão) ou GLOBAL.

  Retorno:
    ok / error / error_code  — ok=false quando a RPC real recusaria (conflito de eixos, NO_CHANGE,
                               características inválidas, Set sem referência externa, …)
    axis, raw_field, token (normalizado), scope, external_set_id
    target      {trait_ids, traits[], profile {id,code,name,is_active} | null}
                — profile null = nenhuma linha resolverá este eixo até o perfil ser criado (2274).
    superseded  mapeamento ativo do MESMO escopo que seria aposentado | null
    scoped_overrides  (Contexto GLOBAL) Sets com mapeamento específico ativo para o item; continuam
                      prevalecendo e ficam fora do impacto
    conflicts[] PRINTING_ACTIVE | EDITION_CONTEXT_ACTIVE | NO_CHANGE (antes de simular)
    finish_mappings_referencing_token  combinações de acabamento que usam o item (deixam de casar
                                       nas linhas onde o item passar a ser deste eixo)
    impact      {rows_touched, jobs, card_sets, resolved, pending, newly_resolved, regressed,
                 pending_by_reason{...}}
    rows[]      até 200 linhas: {row_id, job_id, card_id, before, after, reason,
                 printing_profile_id, edition_context_profile_id}
    simulated_result  retorno da RPC simulada

Como validar
  select has_function_privilege('authenticated','public.admin_preview_catalog_variant_import_axis_mapping(uuid,text,text,text,uuid[],text)','EXECUTE') as auth_ok,
         has_function_privilege('anon','public.admin_preview_catalog_variant_import_axis_mapping(uuid,text,text,text,uuid[],text)','EXECUTE') as anon_must_be_false;
===============================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_preview_catalog_variant_import_axis_mapping(
  p_row_id uuid, p_axis text, p_raw_field text, p_token text, p_trait_ids uuid[], p_scope text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $$
DECLARE
  c_max_rows CONSTANT integer := 200;
  v_axis       text := upper(btrim(coalesce(p_axis, '')));
  v_scope      text;
  v_row        public.catalog_variant_import_row%ROWTYPE;
  v_job        public.catalog_variant_import_job%ROWTYPE;
  v_game       uuid;
  v_src        uuid;
  v_row_ext    text;
  v_ext        text;
  v_token      text;
  v_sig        uuid[];
  v_ids        uuid[];
  v_jobs       integer;
  v_sets       integer;
  v_before     jsonb;
  v_after      jsonb;
  v_sim        jsonb;
  v_err        text;
  v_err_code   text;
  v_target     jsonb;
  v_superseded jsonb;
  v_overrides  jsonb := '[]'::jsonb;
  v_conflicts  jsonb := '[]'::jsonb;
  v_finish     integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_FORBIDDEN: apenas administradores podem simular mapeamentos.'
      USING ERRCODE = '42501';
  END IF;

  IF v_axis = 'PRINTING' THEN
    IF p_scope IS NOT NULL AND upper(btrim(p_scope)) <> 'GLOBAL' THEN
      RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_PRINTING_GLOBAL_ONLY: impressão só tem escopo global.';
    END IF;
    v_scope := 'GLOBAL';
    IF p_raw_field IS NULL OR p_raw_field NOT IN ('subtype', 'stamp') THEN
      RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_INVALID_FIELD: impressão aceita só subtype ou stamp.';
    END IF;
  ELSIF v_axis = 'EDITION_CONTEXT' THEN
    v_scope := upper(btrim(coalesce(p_scope, 'SOURCE_SET')));
    IF v_scope NOT IN ('SOURCE_SET', 'GLOBAL') THEN
      RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_INVALID_SCOPE: escopo deve ser SOURCE_SET ou GLOBAL.';
    END IF;
    IF p_raw_field IS NULL OR p_raw_field NOT IN ('subtype', 'foil', 'stamp') THEN
      RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_INVALID_FIELD: contexto de edição aceita só subtype, foil ou stamp.';
    END IF;
  ELSE
    RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_INVALID_AXIS: eixo deve ser PRINTING ou EDITION_CONTEXT (acabamento usa admin_preview_catalog_variant_import_mapping).';
  END IF;

  IF p_row_id IS NULL OR p_token IS NULL OR p_trait_ids IS NULL OR array_ndims(p_trait_ids) <> 1
     OR cardinality(p_trait_ids) = 0 OR array_position(p_trait_ids, NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_MISSING_ARGS: informe a linha, o item e ao menos uma característica.';
  END IF;

  SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADMIN_PREVIEW_AXIS_MAPPING_ROW_NOT_FOUND: linha de importação não encontrada.';
  END IF;
  SELECT j.* INTO v_job FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;
  SELECT e.game_id INTO v_game
    FROM public.card c JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
   WHERE c.id = v_row.card_id;
  SELECT s.id INTO v_src FROM public.asset_source s WHERE s.code = v_job.source;
  SELECT sc.external_set_id INTO v_row_ext
    FROM internal.resolve_variant_mapping_scope(v_job.card_set_id, v_src) sc;

  v_token := public.normalize_external_catalog_value(p_token);
  v_sig   := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) t ORDER BY t);
  v_ext   := CASE WHEN v_axis = 'EDITION_CONTEXT' AND v_scope = 'SOURCE_SET' THEN v_row_ext END;

  -- Destino: perfil cuja composição é exatamente esta (mesma regra do resolvedor).
  IF v_axis = 'PRINTING' THEN
    v_target := jsonb_build_object(
      'trait_ids', to_jsonb(v_sig),
      'traits', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name, 'is_active', t.is_active)
                                           ORDER BY t.display_order, t.name), '[]'::jsonb)
                   FROM public.card_printing_trait t WHERE t.id = ANY (v_sig)),
      'profile', (SELECT jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'is_active', p.is_active)
                    FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.traits_signature = v_sig));
    v_superseded := (SELECT jsonb_build_object('id', m.id, 'scope', 'GLOBAL',
                              'trait_ids', to_jsonb(COALESCE(m.traits_signature, ARRAY(SELECT x.trait_id FROM public.card_printing_external_mapping_trait x
                                                                                       WHERE x.mapping_id = m.id ORDER BY x.trait_id))))
                       FROM public.card_printing_external_mapping m
                      WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = p_raw_field
                        AND m.normalized_token = v_token AND m.is_active);
    IF EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping m
                WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = p_raw_field
                  AND m.normalized_token = v_token AND m.is_active) THEN
      v_conflicts := v_conflicts || jsonb_build_object('code', 'EDITION_CONTEXT_ACTIVE',
        'scopes', (SELECT jsonb_agg(COALESCE(m.external_set_id, 'GLOBAL') ORDER BY m.external_set_id NULLS FIRST)
                     FROM public.card_edition_context_external_mapping m
                    WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = p_raw_field
                      AND m.normalized_token = v_token AND m.is_active));
    END IF;
  ELSE
    v_target := jsonb_build_object(
      'trait_ids', to_jsonb(v_sig),
      'traits', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name, 'is_active', t.is_active)
                                           ORDER BY t.display_order, t.name), '[]'::jsonb)
                   FROM public.card_edition_context_trait t WHERE t.id = ANY (v_sig)),
      'profile', (SELECT jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'is_active', p.is_active)
                    FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.traits_signature = v_sig));
    v_superseded := (SELECT jsonb_build_object('id', m.id,
                              'scope', CASE WHEN m.external_set_id IS NULL THEN 'GLOBAL' ELSE 'SOURCE_SET' END,
                              'external_set_id', m.external_set_id,
                              'trait_ids', to_jsonb(COALESCE(m.traits_signature, ARRAY(SELECT x.trait_id FROM public.card_edition_context_external_mapping_trait x
                                                                                       WHERE x.mapping_id = m.id ORDER BY x.trait_id))))
                       FROM public.card_edition_context_external_mapping m
                      WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = p_raw_field
                        AND m.normalized_token = v_token AND m.is_active
                        AND m.external_set_id IS NOT DISTINCT FROM v_ext);
    IF v_scope = 'GLOBAL' THEN
      v_overrides := (SELECT COALESCE(jsonb_agg(m.external_set_id ORDER BY m.external_set_id), '[]'::jsonb)
                        FROM public.card_edition_context_external_mapping m
                       WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = p_raw_field
                         AND m.normalized_token = v_token AND m.is_active AND m.external_set_id IS NOT NULL);
    END IF;
    IF p_raw_field IN ('subtype', 'stamp') AND EXISTS (
         SELECT 1 FROM public.card_printing_external_mapping m
          WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = p_raw_field
            AND m.normalized_token = v_token AND m.is_active) THEN
      v_conflicts := v_conflicts || jsonb_build_object('code', 'PRINTING_ACTIVE', 'scopes', '["GLOBAL"]'::jsonb);
    END IF;
  END IF;

  IF v_superseded IS NOT NULL AND (v_superseded -> 'trait_ids') = to_jsonb(v_sig) THEN
    v_conflicts := v_conflicts || jsonb_build_object('code', 'NO_CHANGE');
  END IF;

  SELECT count(*) INTO v_finish
    FROM public.card_variant_type_external_mapping vm
   WHERE vm.game_id = v_game AND vm.asset_source_id = v_src
     AND ((p_raw_field = 'subtype' AND vm.normalized_subtype = v_token)
       OR (p_raw_field = 'foil'    AND vm.normalized_foil = v_token)
       OR (p_raw_field = 'stamp'   AND v_token = ANY (COALESCE(vm.normalized_stamp, '{}'::text[]))));

  -- Linhas atingidas: a MESMA seleção usada pela RPC de Contexto (2273), que reproduz o recorte
  -- da RPC de Impressão (STAGED, mesma fonte e jogo, decisão PENDING, VALID/NEEDS_REVIEW).
  SELECT COALESCE(array_agg(w.row_id ORDER BY w.row_id), '{}'::uuid[]),
         count(DISTINCT w.job_id), count(DISTINCT w.card_set_id)
    INTO v_ids, v_jobs, v_sets
    FROM internal.variant_import_rows_with_token(
           v_game, v_src, v_job.source, p_raw_field, v_token, v_ext,
           v_axis = 'EDITION_CONTEXT' AND v_scope = 'GLOBAL') w;

  SELECT COALESCE(jsonb_object_agg(r.id::text, r.validation_status), '{}'::jsonb) INTO v_before
    FROM public.catalog_variant_import_row r WHERE r.id = ANY (v_ids);

  -- Simulação: a RPC real roda e é desfeita.
  BEGIN
    IF v_axis = 'PRINTING' THEN
      SELECT to_jsonb(f) INTO v_sim
        FROM public.admin_resolve_catalog_variant_import_printing_mapping(p_row_id, p_raw_field, p_token, p_trait_ids) f;
    ELSE
      SELECT to_jsonb(f) INTO v_sim
        FROM public.admin_resolve_catalog_variant_import_edition_context_mapping(p_row_id, p_raw_field, p_token, p_trait_ids, v_scope) f;
    END IF;

    SELECT jsonb_agg(jsonb_build_object(
             'row_id', r.id, 'job_id', r.job_id, 'card_id', r.card_id,
             'before', v_before ->> r.id::text,
             'after', r.validation_status,
             'reason', CASE
                 WHEN r.validation_status = 'VALID' THEN NULL
                 WHEN ax.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE') THEN ax.printing_state
                 WHEN ax.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE') THEN ax.edition_context_state
                 ELSE 'FINISH_NOT_MAPPED' END,
             'printing_profile_id', ax.printing_profile_id,
             'edition_context_profile_id', ax.edition_context_profile_id) ORDER BY r.id)
      INTO v_after
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card_set cs    ON cs.id = j.card_set_id
      JOIN public.expansion e    ON e.id  = cs.expansion_id
      JOIN public.asset_source s ON s.code = j.source
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, s.id) sc ON TRUE
      CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, e.game_id, s.id, sc.external_set_id) ax
     WHERE r.id = ANY (v_ids);

    RAISE EXCEPTION USING ERRCODE = 'PV001', MESSAGE = 'P3A_PREVIEW_ROLLBACK';
  EXCEPTION
    WHEN SQLSTATE 'PV001' THEN
      NULL;
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_err_code = RETURNED_SQLSTATE;
      v_sim := NULL;
      v_after := NULL;
  END;

  RETURN jsonb_build_object(
    'ok', v_err IS NULL,
    'error', v_err,
    'error_code', v_err_code,
    'axis', v_axis, 'raw_field', p_raw_field, 'token', v_token,
    'scope', v_scope, 'external_set_id', v_ext,
    'target', v_target,
    'superseded', v_superseded,
    'scoped_overrides', v_overrides,
    'conflicts', v_conflicts,
    'finish_mappings_referencing_token', v_finish,
    'impact', CASE WHEN v_after IS NULL THEN
        jsonb_build_object('rows_touched', cardinality(v_ids), 'jobs', v_jobs, 'card_sets', v_sets)
      ELSE jsonb_build_object(
        'rows_touched', cardinality(v_ids), 'jobs', v_jobs, 'card_sets', v_sets,
        'resolved', (SELECT count(*) FROM jsonb_array_elements(v_after) x WHERE x ->> 'after' = 'VALID'),
        'pending', (SELECT count(*) FROM jsonb_array_elements(v_after) x WHERE x ->> 'after' <> 'VALID'),
        'newly_resolved', (SELECT count(*) FROM jsonb_array_elements(v_after) x
                            WHERE x ->> 'after' = 'VALID' AND x ->> 'before' <> 'VALID'),
        'regressed', (SELECT count(*) FROM jsonb_array_elements(v_after) x
                       WHERE x ->> 'after' <> 'VALID' AND x ->> 'before' = 'VALID'),
        'pending_by_reason', (SELECT COALESCE(jsonb_object_agg(k, n), '{}'::jsonb) FROM (
                                SELECT x ->> 'reason' AS k, count(*) AS n FROM jsonb_array_elements(v_after) x
                                 WHERE x ->> 'after' <> 'VALID' GROUP BY 1) q))
      END,
    'rows', CASE WHEN v_after IS NULL THEN '[]'::jsonb
                 ELSE (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                         SELECT x FROM jsonb_array_elements(v_after) x LIMIT c_max_rows) q) END,
    'rows_truncated', v_after IS NOT NULL AND jsonb_array_length(v_after) > c_max_rows,
    'simulated_result', v_sim);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_preview_catalog_variant_import_axis_mapping(uuid, text, text, text, uuid[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_catalog_variant_import_axis_mapping(uuid, text, text, text, uuid[], text) TO authenticated;
