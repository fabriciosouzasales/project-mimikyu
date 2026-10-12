/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2271 - Diagnóstico de uma linha da importação de variantes (3 eixos) — P3a
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de Fabrício (ensaio e aplicação no LIVE).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-12
Mandato.....: Fabrício, 2026-10-12 — P3a aprovada (Queries 2271–2274).

O que faz
  public.admin_explain_catalog_variant_import_row(p_row_id uuid) RETURNS jsonb — SÓ LEITURA.
  Só admin (42501). Nenhum algoritmo novo: os estados vêm do resolvedor oficial
  (internal.resolve_variant_row_axes, mesmo escopo externo da importação via
  internal.resolve_variant_mapping_scope) e o acabamento vem de
  internal.lookup_variant_type_for_row sobre a sobra que o resolvedor devolve.

  Retorno:
    row_id, job_id, job_status, card_id, card_set_id, game_id, asset_source_id, external_set_id,
    printing         {state, profile:{id,code,name,is_active}|null, traits:[{id,code,name}]}
    edition_context  {state, profile:{...}|null, traits:[...]}
    finish           {evaluated, residual:{type,foil,subtype,stamp}, variant_type:{id,code,name}|null}
    outcome          'A' (válida) | 'B' (eixos ok, acabamento sem mapeamento) | 'C' (eixo indeterminado)
                     — mesmo critério das RPCs de mapeamento e de perfil.
    items[]          um por item de origem (type, foil, subtype, cada stamp):
                     {field, raw, normalized, allowed_axes[],
                      printing_mapping {id, active, traits[]} | null,
                      edition_context_mapping {id, active, scope GLOBAL|SOURCE_SET, traits[]} | null,
                      in_finish_residual (null quando outcome = C),
                      status: PRINTING | EDITION_CONTEXT | FINISH | UNRECOGNIZED | NOT_EVALUATED}
                     UNRECOGNIZED = o item ficou na sobra e a combinação não tem acabamento mapeado.
                     O eixo NÃO é presumido: allowed_axes só diz quais eixos o campo admite
                     (type → FINISH; foil → FINISH, EDITION_CONTEXT; subtype/stamp → os três).

Como validar
  select has_function_privilege('authenticated','public.admin_explain_catalog_variant_import_row(uuid)','EXECUTE') as auth_ok,
         has_function_privilege('anon','public.admin_explain_catalog_variant_import_row(uuid)','EXECUTE') as anon_must_be_false;
===============================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_explain_catalog_variant_import_row(p_row_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row     public.catalog_variant_import_row%ROWTYPE;
  v_job     public.catalog_variant_import_job%ROWTYPE;
  v_game    uuid;
  v_src     uuid;
  v_ext     text;
  ax        record;
  v_vt      uuid;
  v_outcome text;
  v_items   jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_EXPLAIN_VARIANT_IMPORT_ROW_FORBIDDEN: apenas administradores podem diagnosticar linhas de importação.'
      USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADMIN_EXPLAIN_VARIANT_IMPORT_ROW_NOT_FOUND: linha de importação não encontrada.';
  END IF;

  SELECT j.* INTO v_job FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;
  SELECT e.game_id INTO v_game
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
   WHERE c.id = v_row.card_id;
  SELECT s.id INTO v_src FROM public.asset_source s WHERE s.code = v_job.source;
  IF v_game IS NULL OR v_src IS NULL THEN
    RAISE EXCEPTION 'ADMIN_EXPLAIN_VARIANT_IMPORT_ROW_CONTEXT: não foi possível resolver o jogo ou a fonte desta linha.';
  END IF;
  SELECT sc.external_set_id INTO v_ext
    FROM internal.resolve_variant_mapping_scope(v_job.card_set_id, v_src) sc;

  -- Resolvedor oficial (mesmo contrato da importação e das RPCs de mapeamento).
  SELECT * INTO ax FROM internal.resolve_variant_row_axes(v_row.raw_data, v_game, v_src, v_ext);

  IF ax.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
     OR ax.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE') THEN
    v_outcome := 'C';
  ELSE
    v_vt := internal.lookup_variant_type_for_row(v_game, v_src, v_job.card_set_id,
              ax.residual_type, ax.residual_foil, ax.residual_subtype, ax.residual_stamp);
    v_outcome := CASE WHEN v_vt IS NOT NULL THEN 'A' ELSE 'B' END;
  END IF;

  WITH src_items AS (
    SELECT 1 AS ord, 'type'::text AS field, v_row.raw_data ->> 'type' AS raw
     WHERE v_row.raw_data ->> 'type' IS NOT NULL
    UNION ALL
    SELECT 2, 'foil', v_row.raw_data ->> 'foil' WHERE v_row.raw_data ->> 'foil' IS NOT NULL
    UNION ALL
    SELECT 3, 'subtype', v_row.raw_data ->> 'subtype' WHERE v_row.raw_data ->> 'subtype' IS NOT NULL
    UNION ALL
    SELECT 4, 'stamp', x
      FROM jsonb_array_elements_text(
             CASE WHEN jsonb_typeof(v_row.raw_data -> 'stamp') = 'array'
                  THEN v_row.raw_data -> 'stamp' ELSE '[]'::jsonb END) x
  ), norm AS (
    SELECT s.*, public.normalize_external_catalog_value(s.raw) AS tok FROM src_items s
  ), enriched AS (
    SELECT n.*,
           pm.id AS pm_id, pm.is_active AS pm_active,
           COALESCE(pm.traits_signature, ARRAY(SELECT t.trait_id FROM public.card_printing_external_mapping_trait t
                                                WHERE t.mapping_id = pm.id ORDER BY t.trait_id)) AS pm_sig,
           em.id AS em_id, em.is_active AS em_active, em.external_set_id AS em_ext,
           COALESCE(em.traits_signature, ARRAY(SELECT t.trait_id FROM public.card_edition_context_external_mapping_trait t
                                                WHERE t.mapping_id = em.id ORDER BY t.trait_id)) AS em_sig,
           CASE WHEN v_outcome = 'C' THEN NULL
                WHEN n.field = 'type' THEN TRUE
                WHEN n.field = 'foil' THEN ax.residual_foil IS NOT DISTINCT FROM n.tok
                WHEN n.field = 'subtype' THEN ax.residual_subtype IS NOT DISTINCT FROM n.tok
                ELSE n.tok = ANY (COALESCE(ax.residual_stamp, '{}'::text[])) END AS in_residual
      FROM norm n
      -- Impressão: só subtype/stamp; o ativo, ou o mais recente se nenhum ativo.
      LEFT JOIN LATERAL (
        SELECT m.* FROM public.card_printing_external_mapping m
         WHERE n.field IN ('subtype', 'stamp')
           AND m.game_id = v_game AND m.asset_source_id = v_src
           AND m.raw_field = n.field AND m.normalized_token = n.tok
         ORDER BY m.is_active DESC, m.created_at DESC
         LIMIT 1) pm ON TRUE
      -- Contexto de edição: aplicável a este Set (específico do Set precede o global),
      -- mesma precedência do resolvedor.
      LEFT JOIN LATERAL (
        SELECT m.* FROM public.card_edition_context_external_mapping m
         WHERE n.field IN ('subtype', 'foil', 'stamp')
           AND m.game_id = v_game AND m.asset_source_id = v_src
           AND m.raw_field = n.field AND m.normalized_token = n.tok
           AND (m.external_set_id IS NULL OR (v_ext IS NOT NULL AND m.external_set_id = v_ext))
         ORDER BY m.is_active DESC, (m.external_set_id IS NOT NULL) DESC, m.created_at DESC
         LIMIT 1) em ON TRUE
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'field', e.field,
           'raw', e.raw,
           'normalized', e.tok,
           'allowed_axes', CASE e.field WHEN 'type' THEN '["FINISH"]'::jsonb
                                        WHEN 'foil' THEN '["FINISH","EDITION_CONTEXT"]'::jsonb
                                        ELSE '["FINISH","PRINTING","EDITION_CONTEXT"]'::jsonb END,
           'printing_mapping', CASE WHEN e.pm_id IS NULL THEN NULL ELSE jsonb_build_object(
               'id', e.pm_id, 'active', e.pm_active,
               'traits', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name) ORDER BY t.display_order, t.name), '[]'::jsonb)
                            FROM public.card_printing_trait t WHERE t.id = ANY (e.pm_sig))) END,
           'edition_context_mapping', CASE WHEN e.em_id IS NULL THEN NULL ELSE jsonb_build_object(
               'id', e.em_id, 'active', e.em_active,
               'scope', CASE WHEN e.em_ext IS NULL THEN 'GLOBAL' ELSE 'SOURCE_SET' END,
               'traits', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name) ORDER BY t.display_order, t.name), '[]'::jsonb)
                            FROM public.card_edition_context_trait t WHERE t.id = ANY (e.em_sig))) END,
           'in_finish_residual', e.in_residual,
           'status', CASE
               WHEN e.pm_id IS NOT NULL AND e.pm_active THEN 'PRINTING'
               WHEN e.em_id IS NOT NULL AND e.em_active THEN 'EDITION_CONTEXT'
               WHEN e.in_residual IS NULL THEN 'NOT_EVALUATED'
               WHEN e.in_residual AND v_outcome = 'A' THEN 'FINISH'
               WHEN e.in_residual THEN 'UNRECOGNIZED'
               ELSE 'NOT_EVALUATED' END
         ) ORDER BY e.ord, e.tok), '[]'::jsonb)
    INTO v_items
    FROM enriched e;

  RETURN jsonb_build_object(
    'row_id', v_row.id, 'job_id', v_job.id, 'job_status', v_job.status,
    'card_id', v_row.card_id, 'card_set_id', v_job.card_set_id,
    'game_id', v_game, 'asset_source_id', v_src, 'external_set_id', v_ext,
    'validation_status', v_row.validation_status,
    'printing', jsonb_build_object(
        'state', ax.printing_state,
        'profile', (SELECT jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'is_active', p.is_active)
                      FROM public.card_printing_profile p WHERE p.id = ax.printing_profile_id),
        'traits', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name) ORDER BY t.display_order, t.name), '[]'::jsonb)
                     FROM public.card_printing_trait t WHERE t.id = ANY (COALESCE(ax.printing_trait_ids, '{}'::uuid[])))),
    'edition_context', jsonb_build_object(
        'state', ax.edition_context_state,
        'profile', (SELECT jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'is_active', p.is_active)
                      FROM public.card_edition_context_profile p WHERE p.id = ax.edition_context_profile_id),
        'traits', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name) ORDER BY t.display_order, t.name), '[]'::jsonb)
                     FROM public.card_edition_context_trait t WHERE t.id = ANY (COALESCE(ax.edition_context_trait_ids, '{}'::uuid[])))),
    'finish', jsonb_build_object(
        'evaluated', v_outcome <> 'C',
        'residual', jsonb_build_object('type', ax.residual_type, 'foil', ax.residual_foil,
                                       'subtype', ax.residual_subtype, 'stamp', to_jsonb(ax.residual_stamp)),
        'variant_type', (SELECT jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name)
                           FROM public.card_variant_type t WHERE t.id = v_vt)),
    'outcome', v_outcome,
    'items', v_items);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_explain_catalog_variant_import_row(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_explain_catalog_variant_import_row(uuid) TO authenticated;
