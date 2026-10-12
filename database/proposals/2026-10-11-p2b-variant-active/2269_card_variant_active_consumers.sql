/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2269 - Consumidores de Card Variant passam a respeitar is_active — P2b
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de Fabrício (ensaio e aplicação no LIVE).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Depende.....: 2268 (coluna is_active + trava MV001).
Base........: definições LIVE de 2026-10-11 (md5 do prosrc antes desta query):
                resolve_pricing_product_card_variant  2d7ea7085d70caa93b1a569b0575686b
                pick_card_variant_default             27c8f1c72582c08925c886dd5b63d4db
                admin_set_card_variant_default        456d79efda169e06f78b73b6955fc6bc
                admin_create_card_variant             a48ce02ad2a11864d651c3e30556d17a
              Cada função abaixo é a LIVE + só o trecho marcado "P2b".

O que muda (nada além disto)
  1. internal.resolve_pricing_product_card_variant: regras de candidatas INALTERADAS (a variante
     inativa continua contando como candidata, para que desativar nunca "empurre" um produto para
     outra variante). Só no fim: se a variante escolhida estiver inativa, devolve
     resolution = 'TARGET_INACTIVE' e card_variant_id NULL. Nenhum chamador aceita essa resolução,
     então o produto fica sem vínculo (mesmo destino de AMBIGUOUS/NO_CANDIDATE).
  2. internal.link_new_pricing_products_to_variant (trigger de inserção da sincronização de preço):
     mesma UPDATE; se uma desativação concorrente fizer a trava 2268 recusar (MV001), repete a
     UPDATE uma vez (snapshot novo, a variante já aparece inativa e é recusada pelo resolvedor).
     Assim uma desativação nunca derruba o lote inteiro da sincronização.
  3. internal.pick_card_variant_default: só considera variantes ativas.
  4. public.admin_set_card_variant_default (2264): recusa variante inativa (mensagem legível).
  5. public.admin_create_card_variant (2267): duplicata de uma variante INATIVA ganha mensagem
     própria ("reative-a").
  6. view public.catalog_card_variant_default_pending (2266): conta só variantes ativas.
     (Hoje equivalente: carta com variantes sempre tem ao menos uma ativa — regra da 2270.)

Como validar
  select (select count(*) from public.catalog_card_variant_default_pending) as pendentes,
         position('TARGET_INACTIVE' in (select prosrc from pg_proc where proname = 'resolve_pricing_product_card_variant')) > 0 as resolver_ok,
         position('MV001' in (select prosrc from pg_proc where proname = 'link_new_pricing_products_to_variant')) > 0 as link_ok,
         position('is_active' in (select prosrc from pg_proc where proname = 'pick_card_variant_default')) > 0 as pick_ok;
  -- pendentes deve continuar igual ao valor anterior à query.
===============================================================================
*/

-- 1. Resolvedor de preço
CREATE OR REPLACE FUNCTION internal.resolve_pricing_product_card_variant(p_product_ids uuid[])
 RETURNS TABLE(pricing_product_id uuid, resolution text, card_variant_id uuid, candidate_count integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  WITH p AS (
    SELECT pp.id, m.card_id, m.pricing_source_id, pp.pricing_source_card_identity_id AS identity_id,
           i.external_variant_key AS k, pp.source_printing_label AS lbl
      FROM public.pricing_product pp
      JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
      LEFT JOIN public.pricing_source_card_identity i ON i.id = pp.pricing_source_card_identity_id
     WHERE pp.id = ANY (p_product_ids)
  ), r AS (
    SELECT p.*, pm.id AS pm_id, pm.card_variant_type_id AS lbl_type, pm.printing_profile_id AS pprof,
           pm.fallback_printing_profile_id AS fb_pprof,
           q.id AS q_id, q.catalog_finish_type_id AS q_type, q.edition_context_trait_id AS q_trait
      FROM p
      LEFT JOIN public.pricing_source_printing_mapping pm
             ON pm.pricing_source_id = p.pricing_source_id AND pm.source_printing_label = p.lbl
      LEFT JOIN public.pricing_source_variant_mapping q
             ON q.pricing_source_id = p.pricing_source_id AND q.external_variant_key = p.k
  ), c AS (
    SELECT r.id, cv.id AS cv_id,
           (SELECT count(*) FROM public.card_edition_context_profile_trait t
             WHERE t.profile_id = cv.edition_context_profile_id) AS ntraits
      FROM r
      JOIN public.card_variant cv
        ON cv.card_id = r.card_id
       AND cv.variant_type_id = COALESCE(r.q_type, r.lbl_type)
       AND cv.printing_profile_id IS NOT DISTINCT FROM r.pprof
     WHERE r.identity_id IS NOT NULL AND r.pm_id IS NOT NULL AND (r.k IS NULL OR r.q_id IS NOT NULL)
       AND (r.q_trait IS NULL OR EXISTS (
             SELECT 1 FROM public.card_edition_context_profile_trait t
              WHERE t.profile_id = cv.edition_context_profile_id AND t.trait_id = r.q_trait))
  ), best AS (
    SELECT x.id, count(*) AS n, min(x.cv_id::text)::uuid AS cv, min(x.ntraits) AS ntraits
      FROM (SELECT c.*, min(c.ntraits) OVER (PARTITION BY c.id) AS mn FROM c) x
     WHERE x.ntraits = x.mn
     GROUP BY x.id
  ), fb AS (
    -- 3977: fallback só para produto sem qualificador e sem candidata na regra principal
    SELECT r.id, count(*) AS n, min(cv.id::text)::uuid AS cv
      FROM r
      JOIN public.card_variant cv
        ON cv.card_id = r.card_id AND cv.edition_context_profile_id IS NULL
     WHERE r.identity_id IS NOT NULL AND r.pm_id IS NOT NULL AND r.k IS NULL
       AND NOT EXISTS (SELECT 1 FROM best b WHERE b.id = r.id)
       AND (cv.variant_type_id = r.lbl_type
            OR cv.variant_type_id IN (SELECT f.card_variant_type_id FROM public.pricing_source_printing_finish_fallback f
                                       WHERE f.printing_mapping_id = r.pm_id))
       AND (cv.printing_profile_id IS NOT DISTINCT FROM r.pprof
            OR (r.pprof IS NULL AND r.fb_pprof IS NOT NULL AND cv.printing_profile_id = r.fb_pprof))
     GROUP BY r.id
  ), sp AS (
    -- 3986 (R3): impressão única dos dois lados.
    SELECT r.id, min(cv.id::text)::uuid AS cv
      FROM r
      JOIN public.card_variant cv ON cv.card_id = r.card_id
      LEFT JOIN public.card_printing_profile cpp ON cpp.id = cv.printing_profile_id
     WHERE r.identity_id IS NOT NULL AND r.pm_id IS NOT NULL AND r.k IS NULL AND r.pprof IS NULL
       AND NOT EXISTS (SELECT 1 FROM best b WHERE b.id = r.id)
       AND NOT EXISTS (SELECT 1 FROM fb x WHERE x.id = r.id)
       AND (cpp.code IS NULL OR cpp.code = 'UNLIMITED')
       AND (SELECT count(*) FROM public.card_variant v WHERE v.card_id = r.card_id) = 1
       AND (SELECT count(DISTINCT p2.source_printing_label) FROM public.pricing_product p2
             WHERE p2.pricing_source_card_identity_id = r.identity_id) = 1
     GROUP BY r.id
  ), res AS (
  SELECT r.id AS pid,
         CASE WHEN r.identity_id IS NULL THEN 'NO_IDENTITY'
              WHEN r.pm_id IS NULL THEN 'NO_LABEL_RULE'
              WHEN r.k IS NOT NULL AND r.q_id IS NULL THEN 'NO_QUALIFIER_RULE'
              WHEN b.id IS NULL AND f.n = 1 THEN 'UNIQUE_FALLBACK'
              WHEN b.id IS NULL AND f.n > 1 THEN 'AMBIGUOUS'
              WHEN b.id IS NULL AND s.id IS NOT NULL THEN 'UNIQUE_SINGLE_PRINTING'
              WHEN b.id IS NULL THEN 'NO_CANDIDATE'
              WHEN b.n > 1 THEN 'AMBIGUOUS'
              WHEN r.k IS NULL AND b.ntraits > 0 AND NOT EXISTS (
                     SELECT 1 FROM public.card_variant v
                      WHERE v.card_id = r.card_id
                        AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile_trait t
                                         WHERE t.profile_id = v.edition_context_profile_id))
                   THEN 'UNIQUE_INHERENT_CONTEXT'
              WHEN r.k IS NULL AND b.ntraits > 0 THEN 'UNIQUE_CONTEXT_ONLY'
              ELSE 'UNIQUE' END AS resolution,
         CASE WHEN b.n = 1 THEN b.cv WHEN b.id IS NULL AND f.n = 1 THEN f.cv
              WHEN b.id IS NULL AND f.id IS NULL AND s.id IS NOT NULL THEN s.cv END AS cv,
         COALESCE(b.n, f.n, CASE WHEN s.id IS NOT NULL THEN 1 END, 0)::int AS n
    FROM r LEFT JOIN best b ON b.id = r.id LEFT JOIN fb f ON f.id = r.id LEFT JOIN sp s ON s.id = r.id
  )
  -- P2b (2269): alvo inativo nunca é devolvido como vínculo; as candidatas acima não mudam.
  SELECT res.pid,
         CASE WHEN res.cv IS NOT NULL AND NOT tv.is_active THEN 'TARGET_INACTIVE' ELSE res.resolution END,
         CASE WHEN res.cv IS NOT NULL AND NOT tv.is_active THEN NULL ELSE res.cv END,
         res.n
    FROM res LEFT JOIN public.card_variant tv ON tv.id = res.cv;
$function$;

-- 2. Trigger de vínculo da sincronização de preço
CREATE OR REPLACE FUNCTION internal.link_new_pricing_products_to_variant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  BEGIN
    UPDATE public.pricing_product pp
       SET card_variant_id = r.card_variant_id
      FROM internal.resolve_pricing_product_card_variant(
             ARRAY(SELECT n.id FROM new_rows n WHERE n.card_variant_id IS NULL)) r
     WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT', 'UNIQUE_SINGLE_PRINTING')
       AND pp.card_variant_id IS NULL;
  EXCEPTION WHEN SQLSTATE 'MV001' THEN
    -- P2b (2269): uma variante foi desativada durante este lote. Repete uma vez: o novo snapshot
    -- já a vê inativa e o resolvedor a recusa (TARGET_INACTIVE). O lote da sincronização segue.
    UPDATE public.pricing_product pp
       SET card_variant_id = r.card_variant_id
      FROM internal.resolve_pricing_product_card_variant(
             ARRAY(SELECT n.id FROM new_rows n WHERE n.card_variant_id IS NULL)) r
     WHERE r.pricing_product_id = pp.id AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT', 'UNIQUE_SINGLE_PRINTING')
       AND pp.card_variant_id IS NULL;
  END;
  RETURN NULL;
END;
$function$;

-- 3. Escolha automática da padrão: só ativas
CREATE OR REPLACE FUNCTION internal.pick_card_variant_default(p_card_ids uuid[])
 RETURNS TABLE(card_id uuid, card_variant_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  WITH r AS (
    SELECT v.id, v.card_id,
           CASE WHEN t.code = 'STANDARD' THEN 1 WHEN t.code = 'HOLO' THEN 2
                WHEN t.code LIKE '%REVERSE%' THEN 4 ELSE 3 END AS r1,
           CASE WHEN ec.code IS NULL THEN 0
                ELSE 1 + (length(ec.code) - length(replace(ec.code, '__', ''))) / 2 END AS r2,
           CASE WHEN pp.code IS NULL OR pp.code = 'UNLIMITED' THEN 0 ELSE 1 END AS r3
      FROM public.card_variant v
      JOIN public.card c ON c.id = v.card_id AND c.is_active
      JOIN public.card_variant_type t ON t.id = v.variant_type_id
      LEFT JOIN public.card_edition_context_profile ec ON ec.id = v.edition_context_profile_id
      LEFT JOIN public.card_printing_profile pp ON pp.id = v.printing_profile_id
     WHERE v.card_id = ANY (p_card_ids)
       AND v.is_active  -- P2b (2269)
       AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = v.card_id AND d.is_default)
  ), k AS (
    SELECT r.*, dense_rank() OVER (PARTITION BY r.card_id ORDER BY r.r1, r.r2, r.r3) AS rk FROM r
  )
  SELECT k.card_id, min(k.id::text)::uuid
    FROM k WHERE k.rk = 1
   GROUP BY k.card_id
  HAVING count(*) = 1;
$function$;

-- 4. Padrão manual (2264): recusa variante inativa
CREATE OR REPLACE FUNCTION public.admin_set_card_variant_default(p_card_variant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
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

  BEGIN
    SELECT c.is_active INTO v_card_active FROM public.card c WHERE c.id = v_card_id FOR NO KEY UPDATE;
  EXCEPTION WHEN lock_not_available THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_BUSY: a carta está sendo atualizada por outra operação; tente novamente em instantes.';
  END;
  IF NOT v_card_active THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_CARD_INACTIVE: reative a carta antes de definir a variante padrão.';
  END IF;

  -- P2b (2269): lido sob a trava da carta (a 2270 desativa sob a mesma trava).
  IF NOT (SELECT v.is_active FROM public.card_variant v WHERE v.id = p_card_variant_id) THEN
    RAISE EXCEPTION 'ADMIN_SET_CARD_VARIANT_DEFAULT_INACTIVE: esta variação está inativa; reative-a antes de defini-la como padrão.';
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
$function$;

-- 5. Cadastro individual (2267): duplicata de variante inativa com mensagem própria
CREATE OR REPLACE FUNCTION public.admin_create_card_variant(p_card_id uuid, p_variant_type_id uuid, p_printing_profile_id uuid DEFAULT NULL::uuid, p_edition_context_profile_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
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
  v_dup_active  boolean;
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

  SELECT v.is_active INTO v_dup_active
    FROM public.card_variant v
   WHERE v.card_id = p_card_id
     AND v.variant_type_id = p_variant_type_id
     AND v.printing_profile_id IS NOT DISTINCT FROM p_printing_profile_id
     AND v.edition_context_profile_id IS NOT DISTINCT FROM p_edition_context_profile_id;
  IF v_dup_active IS FALSE THEN  -- P2b (2269)
    RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_DUPLICATE_INACTIVE: esta variação já existe, mas está inativa; reative-a na lista em vez de cadastrar de novo.';
  END IF;
  IF v_dup_active THEN
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
$function$;

-- 6. View de pendências de padrão (2266): só variantes ativas
CREATE OR REPLACE VIEW public.catalog_card_variant_default_pending
  WITH (security_invoker = true) AS
SELECT c.id AS card_id,
       c.card_set_id
  FROM public.card c
 WHERE c.is_active
   AND EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id AND v.is_active)
   AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = c.id AND d.is_default);
