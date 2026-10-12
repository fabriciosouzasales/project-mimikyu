/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2270 - Desativar / reativar Card Variant (RPC administrativa) — P2b
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-12, apply_migration no LIVE, versão 20261012031548, autorizado por
              Fabrício após ensaio PASS 11/11). Validação: auth_ok true, anon false, 2 CHECKs, SECURITY DEFINER, search_path vazio, lock_timeout 5s.
              Pós-P2b: 37.881 variantes (todas ativas), 156.706 produtos de preço, 715 sem variante,
              log 2.017, Collections 0 vínculos — iguais ao pré; demais funções inalteradas (hash).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Depende.....: 2268 (is_active, CHECK padrão-ativa), 2269, 2267 (listas atuais dos CHECKs do log).

O que faz
  1. Amplia 2 CHECKs de catalog_admin_action_log com CARD_VARIANT_DEACTIVATED e
     CARD_VARIANT_REACTIVATED (entidade CARD). Listas = as da 2267 (LIVE) + as duas ações.
  2. public.admin_set_card_variant_active(p_card_variant_id uuid, p_active boolean) RETURNS jsonb
       - só admin (42501); validação toda no servidor;
       - trava a carta (FOR NO KEY UPDATE, mesmo protocolo de 2259/2264/2267) e depois a própria
         variante; espera máx. 5 s (BUSY legível) — inclusive se uma sincronização de preço estiver
         ligando produtos a esta variante naquele instante (a trava 2268 segura FOR SHARE);
       - mesmo estado já gravado → changed=false, nada é escrito nem logado (idempotente);
       - desativar: recusa a variante padrão (DEFAULT) e a última variante ativa da carta
         (LAST_ACTIVE);
       - reativar: recusa se a carta estiver inativa (CARD_INACTIVE) ou se o acabamento, a
         impressão ou o contexto de edição tiver sido desativado no vocabulário (AXIS_INACTIVE);
       - só altera card_variant.is_active da variante pedida. Não apaga nada, não mexe em
         is_default, identidade, preços, inventário ou Collections;
       - log CARD_VARIANT_DEACTIVATED / CARD_VARIANT_REACTIVATED, metadata {source: MANUAL,
         card_variant_id, label, linked_pricing_products}. Só Pricing é contado: é a única
         referência com índice por variante; contar inventário/Collections exigiria varrer tabelas
         que vão crescer.
     Retorno: {changed, card_id, card_variant_id, is_active, label, linked_pricing_products}.

Como validar
  select has_function_privilege('authenticated','public.admin_set_card_variant_active(uuid,boolean)','EXECUTE') as auth_ok,
         has_function_privilege('anon','public.admin_set_card_variant_active(uuid,boolean)','EXECUTE') as anon_must_be_false,
         (select count(*) from pg_constraint where conrelid='public.catalog_admin_action_log'::regclass
            and pg_get_constraintdef(oid) like '%CARD_VARIANT_DEACTIVATED%') as checks_must_be_2;
===============================================================================
*/

-- 1. Log administrativo
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
    'CARD_PRINTING_EXTERNAL_MAPPING_CREATED', 'CARD_PRINTING_PROFILE_CREATED'
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
  );

-- 2. RPC administrativa
CREATE OR REPLACE FUNCTION public.admin_set_card_variant_active(p_card_variant_id uuid, p_active boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $$
DECLARE
  v_card_id     uuid;
  v_card_active boolean;
  v_is_active   boolean;
  v_is_default  boolean;
  v_type_id     uuid;
  v_print_id    uuid;
  v_edition_id  uuid;
  v_label       text;
  v_linked      int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_FORBIDDEN: apenas administradores podem ativar ou desativar variações.'
      USING ERRCODE = '42501';
  END IF;
  IF p_card_variant_id IS NULL OR p_active IS NULL THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_INVALID: informe a variação e o estado desejado.';
  END IF;

  SELECT v.card_id INTO v_card_id FROM public.card_variant v WHERE v.id = p_card_variant_id;
  IF v_card_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_NOT_FOUND: variação não encontrada.';
  END IF;

  BEGIN
    SELECT c.is_active INTO v_card_active FROM public.card c WHERE c.id = v_card_id FOR NO KEY UPDATE;
    SELECT v.is_active, v.is_default, v.variant_type_id, v.printing_profile_id, v.edition_context_profile_id
      INTO v_is_active, v_is_default, v_type_id, v_print_id, v_edition_id
      FROM public.card_variant v
     WHERE v.id = p_card_variant_id
       FOR NO KEY UPDATE;
  EXCEPTION WHEN lock_not_available THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_BUSY: a carta ou a variação está sendo atualizada por outra operação; tente novamente em instantes.';
  END;

  SELECT concat_ws(' / ', t.name, pp.name, ec.name) INTO v_label
    FROM public.card_variant_type t
    LEFT JOIN public.card_printing_profile pp ON pp.id = v_print_id
    LEFT JOIN public.card_edition_context_profile ec ON ec.id = v_edition_id
   WHERE t.id = v_type_id;

  IF v_is_active = p_active THEN
    RETURN jsonb_build_object('changed', false, 'card_id', v_card_id, 'card_variant_id', p_card_variant_id,
                              'is_active', v_is_active, 'label', v_label);
  END IF;

  IF NOT p_active THEN
    IF v_is_default THEN
      RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_DEFAULT: esta é a variante padrão da carta; defina outra variação como padrão antes de desativá-la.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.card_variant v
                    WHERE v.card_id = v_card_id AND v.id <> p_card_variant_id AND v.is_active) THEN
      RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_LAST_ACTIVE: esta é a única variação ativa da carta; a carta precisa manter ao menos uma.';
    END IF;
  ELSE
    IF NOT v_card_active THEN
      RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_CARD_INACTIVE: reative a carta antes de reativar a variação.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.card_variant_type t WHERE t.id = v_type_id AND t.is_active)
       OR (v_print_id IS NOT NULL AND NOT EXISTS (
             SELECT 1 FROM public.card_printing_profile p WHERE p.id = v_print_id AND p.is_active))
       OR (v_edition_id IS NOT NULL AND NOT EXISTS (
             SELECT 1 FROM public.card_edition_context_profile x WHERE x.id = v_edition_id AND x.is_active)) THEN
      RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_ACTIVE_AXIS_INACTIVE: o acabamento, a impressão ou o contexto de edição desta variação foi desativado; reative-o antes.';
    END IF;
  END IF;

  UPDATE public.card_variant SET is_active = p_active WHERE id = p_card_variant_id;

  SELECT count(*) INTO v_linked FROM public.pricing_product pp WHERE pp.card_variant_id = p_card_variant_id;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(),
          CASE WHEN p_active THEN 'CARD_VARIANT_REACTIVATED' ELSE 'CARD_VARIANT_DEACTIVATED' END,
          'CARD', v_card_id,
          jsonb_build_object('source', 'MANUAL', 'card_variant_id', p_card_variant_id, 'label', v_label,
                             'linked_pricing_products', v_linked));

  RETURN jsonb_build_object('changed', true, 'card_id', v_card_id, 'card_variant_id', p_card_variant_id,
                            'is_active', p_active, 'label', v_label, 'linked_pricing_products', v_linked);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_card_variant_active(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_card_variant_active(uuid, boolean) TO authenticated;
