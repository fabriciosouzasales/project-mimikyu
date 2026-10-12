/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2264 - Definição manual da variante padrão de uma carta (RPC administrativa)
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de Fabrício para executar no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — P1 "Gestão Administrativa da Variante Padrão" (aprovada):
              escolha manual explícita; só admin; servidor valida que a variante pertence à
              carta; no máximo um padrão por carta; trilha no log administrativo existente;
              a escolha manual nunca é desfeita por atribuição automática; sem campos novos.
Depende.....: 160 (card_variant + uq_card_variant_one_default_per_card), 2159 (precedente de
              ampliação das CHECKs do log), 2259 (trigger automático de padrão).

O que faz
  1. Recria 2 das 3 CHECKs de catalog_admin_action_log (action_valid e action_entity_match) com a
     ação CARD_VARIANT_DEFAULT_SET (entidade CARD; entity_type_valid já aceita CARD e não muda).
     Listas idênticas às do LIVE em 2026-10-11 + a ação nova.
  2. Cria public.admin_set_card_variant_default(p_card_variant_id uuid) RETURNS jsonb:
       - recusa quem não é admin;
       - deriva a carta da própria variante (o cliente nunca informa card_id);
       - trava a carta em FOR NO KEY UPDATE — o MESMO protocolo do trigger 2259 e compatível
         com o FOR UPDATE da confirmação de importação de variantes: as três escritas de
         is_default ficam serializadas por carta, sem conflito no índice único;
       - espera no máximo 5 s pela trava (importação em andamento na mesma carta) e devolve
         erro legível em vez de pendurar a tela;
       - recusa carta inativa; escolha igual à atual não altera nada nem gera log;
       - remove o padrão anterior e define o novo na mesma transação;
       - registra CARD_VARIANT_DEFAULT_SET com metadata.source = 'MANUAL', ids e rótulos
         (Acabamento / Impressão / Contexto de edição) do padrão anterior e do novo.

Por que a escolha manual é preservada (sem campo novo)
  - O trigger 2259 só age em AFTER INSERT e só em cartas SEM padrão; nunca troca um padrão.
  - internal.write_card_variant (importação) não lê nem escreve is_default.
  - Nenhuma outra função do LIVE escreve is_default (inventário de 2026-10-11).
  - A origem "manual" fica identificável no log: entity_id = card, action =
    CARD_VARIANT_DEFAULT_SET, metadata.source = 'MANUAL'.

Concorrência (análise 2026-10-11)
  - Confirmação de importação: trava as cartas do lote em FOR UPDATE, em ordem, antes de
    inserir; só INSERT em card_variant. A RPC trava uma única carta e só depois toca nas
    variantes dela → nenhuma ordem cruzada de travas, sem deadlock.
  - Trigger 2259: trava em FOR NO KEY UPDATE e reconfere "sem padrão" na própria UPDATE; se a
    RPC confirmou antes, o trigger não age. Se a RPC espera, ela relê o padrão depois da trava.
  - FOR NO KEY UPDATE não bloqueia o FOR KEY SHARE das FKs (inserts que só referenciam card).
  - O índice único parcial continua como última barreira.

Como validar
  select has_function_privilege('authenticated','public.admin_set_card_variant_default(uuid)','EXECUTE') as auth_ok,
         has_function_privilege('anon','public.admin_set_card_variant_default(uuid)','EXECUTE') as anon_must_be_false,
         (select count(*) from pg_constraint where conrelid='public.catalog_admin_action_log'::regclass
            and pg_get_constraintdef(oid) like '%CARD_VARIANT_DEFAULT_SET%') as checks_must_be_2;
  -- checks_must_be_2: action_valid e action_entity_match citam a ação; entity_type_valid não muda.
===============================================================================
*/

-- 1. Log administrativo: nova ação CARD_VARIANT_DEFAULT_SET (entidade CARD)
ALTER TABLE public.catalog_admin_action_log
  DROP CONSTRAINT ck_catalog_admin_action_log_action_valid,
  DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

ALTER TABLE public.catalog_admin_action_log
  ADD CONSTRAINT ck_catalog_admin_action_log_action_valid CHECK (action = ANY (ARRAY[
    'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
    'EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED',
    'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED',
    'CARD_VARIANT_DEFAULT_SET',
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
                                                     'CARD_VARIANT_DEFAULT_SET']::text[]))
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
CREATE OR REPLACE FUNCTION public.admin_set_card_variant_default(p_card_variant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $f$
DECLARE
  v_card_id     uuid;
  v_card_active boolean;
  v_prev_id     uuid;
  v_label       text;
  v_prev_label  text;
  v_rows        int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_FORBIDDEN: apenas administradores podem definir a variante padrão.'
      USING ERRCODE = '42501';
  END IF;

  SELECT v.card_id INTO v_card_id FROM public.card_variant v WHERE v.id = p_card_variant_id;
  IF v_card_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_NOT_FOUND: variação não encontrada (%).', p_card_variant_id;
  END IF;

  -- Mesmo modo de trava do trigger 2259; serializa com a confirmação de importação (FOR UPDATE).
  BEGIN
    SELECT c.is_active INTO v_card_active FROM public.card c WHERE c.id = v_card_id FOR NO KEY UPDATE;
  EXCEPTION WHEN lock_not_available THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_BUSY: a carta está sendo atualizada por outra operação; tente novamente em instantes.';
  END;
  IF NOT v_card_active THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_CARD_INACTIVE: reative a carta antes de definir a variante padrão.';
  END IF;

  SELECT v.id INTO v_prev_id FROM public.card_variant v WHERE v.card_id = v_card_id AND v.is_default;

  IF v_prev_id = p_card_variant_id THEN
    RETURN jsonb_build_object('changed', false, 'card_id', v_card_id,
                              'card_variant_id', p_card_variant_id, 'previous_card_variant_id', v_prev_id);
  END IF;

  IF v_prev_id IS NOT NULL THEN
    UPDATE public.card_variant SET is_default = false WHERE id = v_prev_id;
  END IF;

  UPDATE public.card_variant SET is_default = true WHERE id = p_card_variant_id AND card_id = v_card_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_NOT_FOUND: variação não encontrada (%).', p_card_variant_id;
  END IF;

  SELECT concat_ws(' / ', t.name, pp.name, ec.name) INTO v_label
    FROM public.card_variant v
    JOIN public.card_variant_type t ON t.id = v.variant_type_id
    LEFT JOIN public.card_printing_profile pp ON pp.id = v.printing_profile_id
    LEFT JOIN public.card_edition_context_profile ec ON ec.id = v.edition_context_profile_id
   WHERE v.id = p_card_variant_id;

  IF v_prev_id IS NOT NULL THEN
    SELECT concat_ws(' / ', t.name, pp.name, ec.name) INTO v_prev_label
      FROM public.card_variant v
      JOIN public.card_variant_type t ON t.id = v.variant_type_id
      LEFT JOIN public.card_printing_profile pp ON pp.id = v.printing_profile_id
      LEFT JOIN public.card_edition_context_profile ec ON ec.id = v.edition_context_profile_id
     WHERE v.id = v_prev_id;
  END IF;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'CARD_VARIANT_DEFAULT_SET', 'CARD', v_card_id,
          jsonb_build_object('source', 'MANUAL',
                             'card_variant_id', p_card_variant_id, 'label', v_label,
                             'previous_card_variant_id', v_prev_id, 'previous_label', v_prev_label));

  RETURN jsonb_build_object('changed', true, 'card_id', v_card_id, 'card_variant_id', p_card_variant_id,
                            'previous_card_variant_id', v_prev_id, 'label', v_label);
END;
$f$;

REVOKE ALL ON FUNCTION public.admin_set_card_variant_default(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_card_variant_default(uuid) TO authenticated;
