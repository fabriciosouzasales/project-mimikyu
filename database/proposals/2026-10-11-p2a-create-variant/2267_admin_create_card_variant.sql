/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2267 - Cadastro individual de Card Variant (RPC administrativa) — P2a
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de Fabrício para executar no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — P2a aprovada: cadastrar uma variante por carta pelo Catálogo
              de Cartas (Acabamento obrigatório; Impressão e Contexto de edição opcionais), sem
              reimportar o Set; reconciliação de preço restrita à carta e incapaz de impedir o cadastro.
Depende.....: 2143 (internal.write_card_variant), 2170/2224 (triggers same-Game), 2259 (padrão
              automático), 2264 (CHECKs do log), 3986/3977 (resolvedor de preço).

O que faz
  1. Amplia 2 CHECKs de catalog_admin_action_log com CARD_VARIANT_CREATED (entidade CARD).
     Listas = as da 2264 (LIVE) + a ação nova.
  2. public.admin_create_card_variant(p_card_id, p_variant_type_id, p_printing_profile_id,
     p_edition_context_profile_id) RETURNS jsonb:
       - só admin; carta precisa existir e estar ativa;
       - trava a carta (FOR NO KEY UPDATE, mesmo protocolo da 2264/2259; espera máx. 5 s);
       - Acabamento, Impressão e Contexto precisam existir, estar ativos e ser do Game da carta
         (os triggers 2170/2224 seguem como autoridade final);
       - identidade dos 3 eixos já cadastrada → erro legível (o índice uq_card_variant_identity
         continua como barreira final);
       - variant_order = max + 1 da carta (sob a trava);
       - grava por internal.write_card_variant (mesmo writer da importação); o trigger 2259 dá o
         padrão se a carta ainda não tiver um;
       - log CARD_VARIANT_CREATED (metadata: variant id, rótulo, eixos, is_default, pricing);
       - Pricing: depois do cadastro, liga só os pricing_product DESTA carta com card_variant_id
         nulo, pelo resolvedor existente (mesmas resoluções aceitas pelo trigger de preço e pela
         reconciliação). Roda num bloco com EXCEPTION próprio: qualquer falha ali é registrada no
         retorno/log e o cadastro da variante é mantido.
     Retorno: {card_variant_id, card_id, label, is_default, pricing:{status, candidates,
     linked, linked_to_new, error}}.

Como validar
  select has_function_privilege('authenticated','public.admin_create_card_variant(uuid,uuid,uuid,uuid)','EXECUTE') as auth_ok,
         has_function_privilege('anon','public.admin_create_card_variant(uuid,uuid,uuid,uuid)','EXECUTE') as anon_must_be_false,
         (select count(*) from pg_constraint where conrelid='public.catalog_admin_action_log'::regclass
            and pg_get_constraintdef(oid) like '%CARD_VARIANT_CREATED%') as checks_must_be_2;
===============================================================================
*/

-- 1. Log administrativo: nova ação CARD_VARIANT_CREATED (entidade CARD)
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
    'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED',
    'RARITY_CREATED', 'RARITY_UPDATED',
    'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED',
    'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
    'CARD_VARIANT_IMPORT_CONFIRMED', 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED',
    'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
    'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
    'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED',
    'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED',
    'CARD_PRINTING_EXTERNAL_MAPPING_CREATED', 'CARD_PRINTING_PROFILE_CREATED'
  ]::text[])),
  ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match CHECK (
       (entity_type = 'GAME' AND action = ANY (ARRAY['GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED']::text[]))
    OR (entity_type = 'EXPANSION' AND action = ANY (ARRAY['EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED']::text[]))
    OR (entity_type = 'CARD_SET' AND action = ANY (ARRAY['CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
                                                         'CARD_ASSET_MANUAL_IMPORT_COMPLETED']::text[]))
    OR (entity_type = 'CARD' AND action = ANY (ARRAY['CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED',
                                                     'CARD_VARIANT_DEFAULT_SET', 'CARD_VARIANT_CREATED']::text[]))
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
  );

-- 2. RPC administrativa
CREATE OR REPLACE FUNCTION public.admin_create_card_variant(
  p_card_id uuid,
  p_variant_type_id uuid,
  p_printing_profile_id uuid DEFAULT NULL,
  p_edition_context_profile_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $f$
DECLARE
  v_card_active boolean;
  v_game_id     uuid;
  v_order       int;
  v_new_id      uuid;
  v_is_default  boolean;
  v_label       text;
  v_pricing     jsonb;
  v_ids         uuid[];
  v_linked      int := 0;
  v_linked_new  int := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_FORBIDDEN: apenas administradores podem cadastrar variações.'
      USING ERRCODE = '42501';
  END IF;
  IF p_card_id IS NULL OR p_variant_type_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_INVALID: informe a carta e o acabamento.';
  END IF;

  BEGIN
    SELECT c.is_active, e.game_id INTO v_card_active, v_game_id
      FROM public.card c
      JOIN public.card_set cs ON cs.id = c.card_set_id
      JOIN public.expansion e ON e.id = cs.expansion_id
     WHERE c.id = p_card_id
       FOR NO KEY UPDATE OF c;
  EXCEPTION WHEN lock_not_available THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_BUSY: a carta está sendo atualizada por outra operação; tente novamente em instantes.';
  END;
  IF v_card_active IS NULL THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_CARD_NOT_FOUND: carta não encontrada.';
  END IF;
  IF NOT v_card_active THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_CARD_INACTIVE: reative a carta antes de cadastrar variações.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.card_variant_type t
                  WHERE t.id = p_variant_type_id AND t.is_active AND t.game_id = v_game_id) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_FINISH_INVALID: acabamento inexistente, inativo ou de outro jogo.';
  END IF;
  IF p_printing_profile_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.card_printing_profile p
        WHERE p.id = p_printing_profile_id AND p.is_active AND p.game_id = v_game_id) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_PRINTING_INVALID: impressão inexistente, inativa ou de outro jogo.';
  END IF;
  IF p_edition_context_profile_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.card_edition_context_profile x
        WHERE x.id = p_edition_context_profile_id AND x.is_active AND x.game_id = v_game_id) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_EDITION_CONTEXT_INVALID: contexto de edição inexistente, inativo ou de outro jogo.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.card_variant v
              WHERE v.card_id = p_card_id
                AND v.variant_type_id = p_variant_type_id
                AND v.printing_profile_id IS NOT DISTINCT FROM p_printing_profile_id
                AND v.edition_context_profile_id IS NOT DISTINCT FROM p_edition_context_profile_id) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_DUPLICATE: esta carta já tem uma variação com o mesmo acabamento, impressão e contexto de edição.';
  END IF;

  SELECT COALESCE(max(v.variant_order), 0) + 1 INTO v_order FROM public.card_variant v WHERE v.card_id = p_card_id;

  v_new_id := internal.write_card_variant('CREATE', NULL, p_card_id, p_variant_type_id, v_order,
                                          p_printing_profile_id, p_edition_context_profile_id);

  SELECT v.is_default, concat_ws(' / ', t.name, pp.name, ec.name) INTO v_is_default, v_label
    FROM public.card_variant v
    JOIN public.card_variant_type t ON t.id = v.variant_type_id
    LEFT JOIN public.card_printing_profile pp ON pp.id = v.printing_profile_id
    LEFT JOIN public.card_edition_context_profile ec ON ec.id = v.edition_context_profile_id
   WHERE v.id = v_new_id;

  -- Pricing: só os produtos desta carta ainda sem variante. Falha aqui não desfaz o cadastro.
  BEGIN
    SELECT array_agg(pp.id) INTO v_ids
      FROM public.pricing_product pp
      JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
     WHERE m.card_id = p_card_id AND pp.card_variant_id IS NULL;

    IF v_ids IS NULL THEN
      v_pricing := jsonb_build_object('status', 'NO_CANDIDATES', 'candidates', 0, 'linked', 0, 'linked_to_new', 0);
    ELSE
      WITH r AS (
        SELECT * FROM internal.resolve_pricing_product_card_variant(v_ids)
         WHERE resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT', 'UNIQUE_SINGLE_PRINTING')
      ), u AS (
        UPDATE public.pricing_product pp
           SET card_variant_id = r.card_variant_id
          FROM r
         WHERE r.pricing_product_id = pp.id AND pp.card_variant_id IS NULL
        RETURNING pp.card_variant_id
      )
      SELECT count(*), count(*) FILTER (WHERE u.card_variant_id = v_new_id) INTO v_linked, v_linked_new FROM u;

      v_pricing := jsonb_build_object('status', 'OK', 'candidates', cardinality(v_ids),
                                      'linked', v_linked, 'linked_to_new', v_linked_new);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_pricing := jsonb_build_object('status', 'ERROR', 'candidates', COALESCE(cardinality(v_ids), 0),
                                    'linked', 0, 'linked_to_new', 0, 'error', SQLERRM);
  END;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'CARD_VARIANT_CREATED', 'CARD', p_card_id,
          jsonb_build_object('source', 'MANUAL', 'card_variant_id', v_new_id, 'label', v_label,
                             'variant_type_id', p_variant_type_id,
                             'printing_profile_id', p_printing_profile_id,
                             'edition_context_profile_id', p_edition_context_profile_id,
                             'variant_order', v_order, 'is_default', v_is_default,
                             'pricing', v_pricing));

  RETURN jsonb_build_object('card_variant_id', v_new_id, 'card_id', p_card_id, 'label', v_label,
                            'is_default', v_is_default, 'pricing', v_pricing);
END;
$f$;

REVOKE ALL ON FUNCTION public.admin_create_card_variant(uuid, uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_card_variant(uuid, uuid, uuid, uuid) TO authenticated;
