/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2274 - Criação administrativa de Perfil de Contexto de Edição + reavaliação — P3a
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-12, apply_migration no LIVE, versão 20261012125501, autorizado por
              Fabrício após ensaio PASS S1 S2 E1 P1 W1 N1 C1 G1 X1 K1 I1). Validação: auth_ok true, anon false.
              Pós-P3a: mapeamentos de Impressão 24, de Contexto 152, perfis de Contexto 179,
              37.881 variantes, 37.239 linhas de importação — idênticos ao pré (hash).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-12
Depende.....: 2273 (internal.reconcile_variant_import_rows, CHECKs do log), selo trg_cecp_seal.

O que faz
  public.admin_create_card_edition_context_profile_with_backfill(
     p_code, p_name, p_description, p_display_order, p_trait_ids uuid[])
  RETURNS TABLE(profile_id, traits_signature, rows_touched, rows_revalidated, rows_still_pending, jobs_affected)

  Espelho da criação de Perfil de Impressão (2190 / v4.0):
    - só admin; código ^[A-Z][A-Z0-9_]*$, nome obrigatório, ordem > 0 e única no jogo,
      código único no jogo; 1..64 características EXISTENTES, ATIVAS e de UM só jogo;
    - composição é identidade: recusa se já existir perfil com exatamente estas características
      (reutilize o existente) — o índice uq_cecp_game_signature é a barreira final;
    - cria o perfil, a composição, força o selo (SET CONSTRAINTS trg_cecp_seal IMMEDIATE) e
      prova o selo (assinatura = características ordenadas, perfil ativo);
    - reavalia SÓ as linhas em revisão (job STAGED, decisão PENDING, mesmo jogo) que o resolvedor
      oficial passa a ligar a ESTE perfil, pela reconciliação única da 2273;
    - restaura o selo para DEFERRED e grava CARD_EDITION_CONTEXT_PROFILE_CREATED.
  Nunca cria característica nova (fora do escopo da P3a).

Como validar
  select has_function_privilege('authenticated','public.admin_create_card_edition_context_profile_with_backfill(text,text,text,integer,uuid[])','EXECUTE') as auth_ok,
         has_function_privilege('anon','public.admin_create_card_edition_context_profile_with_backfill(text,text,text,integer,uuid[])','EXECUTE') as anon_must_be_false;
===============================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_card_edition_context_profile_with_backfill(
  p_code text, p_name text, p_description text, p_display_order integer, p_trait_ids uuid[])
RETURNS TABLE(profile_id uuid, traits_signature uuid[], rows_touched integer, rows_revalidated integer,
              rows_still_pending integer, jobs_affected integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $$
DECLARE
  c_max_traits CONSTANT integer := 64;
  v_actor     uuid;
  v_code      text;
  v_name      text;
  v_desc      text;
  v_count     integer;
  v_unknown   integer;
  v_inactive  text;
  v_games     integer;
  v_game      uuid;
  v_expected  uuid[];
  v_profile   uuid;
  v_sealed    uuid[];
  v_active    boolean;
  v_ids       uuid[];
  rc          record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_FORBIDDEN: apenas administradores podem cadastrar um perfil de contexto de edição.'
      USING ERRCODE = '42501';
  END IF;
  v_actor := auth.uid();
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_NO_SESSION: sessão sem usuário; não há ator a registrar.';
  END IF;

  v_code := upper(btrim(coalesce(p_code, '')));
  v_name := btrim(coalesce(p_name, ''));
  v_desc := NULLIF(btrim(coalesce(p_description, '')), '');
  IF v_code = '' OR v_code !~ '^[A-Z][A-Z0-9_]*$' THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_INVALID_CODE: código inválido (%). Use letras maiúsculas, números e _ começando por letra.', p_code;
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_INVALID_NAME: o nome não pode ser vazio.';
  END IF;
  IF p_display_order IS NULL OR p_display_order <= 0 THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_INVALID_DISPLAY_ORDER: a ordem precisa ser um inteiro positivo.';
  END IF;

  IF p_trait_ids IS NULL OR array_ndims(p_trait_ids) <> 1 OR cardinality(p_trait_ids) = 0 THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_MISSING_TRAITS: informe ao menos uma característica.';
  END IF;
  v_count := cardinality(p_trait_ids);
  IF v_count > c_max_traits THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_TOO_MANY_TRAITS: % características, acima do teto de %.', v_count, c_max_traits;
  END IF;
  IF array_position(p_trait_ids, NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_NULL_TRAIT: a lista de características contém valor vazio.';
  END IF;
  v_expected := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) t ORDER BY t);
  IF cardinality(v_expected) <> v_count THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_DUPLICATE_TRAIT: a mesma característica foi informada mais de uma vez.';
  END IF;

  SELECT count(*) INTO v_unknown FROM unnest(v_expected) t(id)
   WHERE NOT EXISTS (SELECT 1 FROM public.card_edition_context_trait x WHERE x.id = t.id);
  IF v_unknown > 0 THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_TRAIT_NOT_FOUND: % característica(s) não existem.', v_unknown;
  END IF;
  SELECT string_agg(x.code, ', ' ORDER BY x.code) INTO v_inactive
    FROM public.card_edition_context_trait x WHERE x.id = ANY (v_expected) AND NOT x.is_active;
  IF v_inactive IS NOT NULL THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_TRAIT_INACTIVE: característica(s) inativa(s): %.', v_inactive;
  END IF;
  SELECT count(DISTINCT x.game_id), (array_agg(DISTINCT x.game_id))[1] INTO v_games, v_game
    FROM public.card_edition_context_trait x WHERE x.id = ANY (v_expected);
  IF v_games <> 1 THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_MIXED_GAME: as características pertencem a % jogos.', v_games;
  END IF;

  IF EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.code = v_code) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_DUPLICATE_CODE: já existe um perfil com o código % neste jogo.', v_code;
  END IF;
  IF EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.display_order = p_display_order) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_DUPLICATE_DISPLAY_ORDER: já existe um perfil com a ordem % neste jogo.', p_display_order;
  END IF;
  IF EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.traits_signature = v_expected) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_DUPLICATE_SIGNATURE: já existe um perfil com exatamente estas características; reutilize-o.';
  END IF;

  INSERT INTO public.card_edition_context_profile (game_id, code, name, description, display_order)
  VALUES (v_game, v_code, v_name, v_desc, p_display_order)
  RETURNING id INTO v_profile;

  INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
  SELECT v_profile, t, v_game FROM unnest(v_expected) t;

  SET CONSTRAINTS public.trg_cecp_seal IMMEDIATE;

  SELECT p.traits_signature, p.is_active INTO v_sealed, v_active
    FROM public.card_edition_context_profile p WHERE p.id = v_profile;
  IF v_sealed IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_SEAL_MISMATCH: a assinatura selada não corresponde às características informadas.';
  END IF;
  IF v_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ADMIN_CREATE_EC_PROFILE_NOT_ACTIVE: o perfil recém-criado não está ativo.';
  END IF;

  -- Linhas que o resolvedor oficial passa a ligar a este perfil.
  v_ids := ARRAY(
    SELECT r.id
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card_set cs    ON cs.id = j.card_set_id
      JOIN public.expansion e    ON e.id  = cs.expansion_id
      JOIN public.asset_source s ON s.code = j.source
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, s.id) sc ON TRUE
      CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, e.game_id, s.id, sc.external_set_id) ax
     WHERE j.status = 'STAGED'
       AND r.decision_status = 'PENDING'
       AND r.persistence_status = 'PENDING'
       AND e.game_id = v_game
       AND ax.edition_context_profile_id = v_profile
     ORDER BY r.id);

  SELECT * INTO rc FROM internal.reconcile_variant_import_rows(v_ids);

  SET CONSTRAINTS public.trg_cecp_seal DEFERRED;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor, 'CARD_EDITION_CONTEXT_PROFILE_CREATED', 'CARD_EDITION_CONTEXT_PROFILE', v_profile,
          jsonb_build_object(
            'source', 'MANUAL',
            'game_id', v_game, 'code', v_code, 'name', v_name, 'display_order', p_display_order,
            'trait_ids', to_jsonb(v_expected), 'traits_signature', to_jsonb(v_sealed),
            'rows_touched', rc.rows_touched, 'rows_revalidated', rc.rows_revalidated,
            'rows_still_pending', rc.rows_still_pending, 'jobs_affected', rc.jobs_affected,
            'axes_contract', 'resolve_variant_row_axes/v1'));

  RETURN QUERY SELECT v_profile, v_sealed, rc.rows_touched, rc.rows_revalidated, rc.rows_still_pending, rc.jobs_affected;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_card_edition_context_profile_with_backfill(text, text, text, integer, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_card_edition_context_profile_with_backfill(text, text, text, integer, uuid[]) TO authenticated;
