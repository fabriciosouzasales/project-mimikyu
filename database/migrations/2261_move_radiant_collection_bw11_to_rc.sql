/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2261 - Radiant Collection: mover RC1–RC25 do BW11 para o Set RC
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, apply_migration no LIVE qjfutqujxrbzgrtkpgkg).
              Dry-run abortado de propósito antes: RC 25 · BW11 115 · vínculos de preço RC 0 · bootstrap PENDING.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — Importar Cartas mostrava o Set RC sem cartas; decisão
              "Mover RC1–RC25 para o Set RC".

Causa
  A importação TCGdex do BW11 (Legendary Treasures) trouxe a subcoleção Radiant Collection
  (RC1–RC25) dentro do próprio BW11 (collector_order 116–140, collector_total 113). O Set RC já
  existia no catálogo (SPECIAL, 25 cartas) e tinha correspondência de preço CONFIRMED na JustTCG
  (legendary-treasures-radiant-collection-pokemon), mas ficava vazio. Como cada Set só tem uma
  correspondência por fonte, as 25 cartas ficaram NOT_FOUND no preço (casadas contra o BW11).

O que faz (um bloco, fail-loud)
  G1 Set RC vazio; G2 exatamente RC1..RC25 no BW11.
  1. card: card_set_id → RC, collector_order = número RC (1–25), collector_total = 25.
     Identidade preservada (mesmo id): variantes, imagens, referências externas e Collections seguem.
  2. card_set BW11: total_set_size 140 → 115 (113 + 2 secretas). RC já estava 25/25.
  3. Preço: remove os 25 pricing_card_mapping NOT_FOUND dessas cartas (sem produto nem identidade
     dependente) e reabre o bootstrap do RC (COMPLETE com 0 cartas → PENDING). O dispatcher existente
     casa as 25 cartas contra o Set RC da fonte.
  4. Rastro: pricing_admin_action_log (PRICING_SET_BOOTSTRAP_REOPENED) e catalog_admin_action_log
     (CARD_SET_UPDATED para BW11 e RC), metadata.operation = RC-MOVE-2261.

Risco conhecido
  Reimportar o BW11 pelo TCGdex recriaria RC1–RC25 no BW11 (a fonte publica a subcoleção dentro do
  Set). Não reimportar BW11 sem tratar a subcoleção. Mesmo caso existe em Generations (G1, RC1–RC32),
  ainda não tratado.

Como validar
  select cs.code, count(c.*) from public.card_set cs left join public.card c on c.card_set_id = cs.id
   where cs.code in ('BW11','RC') group by cs.code;   -- BW11 115 | RC 25
===============================================================================
*/

DO $m$
DECLARE
  v_actor uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_bw11 uuid; v_rc uuid; v_psm uuid; v_src uuid;
  v_n int; v_del int;
BEGIN
  SELECT id INTO STRICT v_bw11 FROM public.card_set WHERE code = 'BW11';
  SELECT id INTO STRICT v_rc   FROM public.card_set WHERE code = 'RC';

  -- G1: Set RC vazio; G2: exatamente 25 cartas RC no BW11 (RC1..RC25)
  IF EXISTS (SELECT 1 FROM public.card WHERE card_set_id = v_rc) THEN
    RAISE EXCEPTION '2261: Set RC já tem cartas';
  END IF;
  SELECT count(*) INTO v_n FROM public.card
   WHERE card_set_id = v_bw11 AND collector_number ~ '^RC([1-9]|1[0-9]|2[0-5])$';
  IF v_n <> 25 OR EXISTS (SELECT 1 FROM public.card WHERE card_set_id = v_bw11
                            AND collector_number LIKE 'RC%' AND collector_number !~ '^RC([1-9]|1[0-9]|2[0-5])$') THEN
    RAISE EXCEPTION '2261: esperado RC1..RC25 no BW11, encontrado %', v_n;
  END IF;

  -- 1. mover as cartas
  UPDATE public.card c
     SET card_set_id = v_rc,
         collector_order = substring(c.collector_number from 3)::int,
         collector_total = 25,
         updated_at = now()
   WHERE c.card_set_id = v_bw11 AND c.collector_number ~ '^RC([1-9]|1[0-9]|2[0-5])$';

  -- 2. tamanhos dos Sets
  UPDATE public.card_set SET total_set_size = 115, updated_at = now() WHERE id = v_bw11 AND total_set_size = 140;
  IF NOT FOUND THEN RAISE EXCEPTION '2261: BW11 total_set_size inesperado'; END IF;

  -- 3. Pricing: o vínculo NOT_FOUND foi decidido com o Set errado (BW11) — removido para o Set RC casar de novo
  SELECT psm.id, psm.pricing_source_id INTO STRICT v_psm, v_src
    FROM public.pricing_set_mapping psm WHERE psm.card_set_id = v_rc AND psm.match_status = 'CONFIRMED';
  DELETE FROM public.pricing_card_mapping m
   USING public.card c
   WHERE c.id = m.card_id AND c.card_set_id = v_rc
     AND m.pricing_source_id = v_src AND m.match_status = 'NOT_FOUND'
     AND NOT EXISTS (SELECT 1 FROM public.pricing_product p WHERE p.pricing_card_mapping_id = m.id)
     AND NOT EXISTS (SELECT 1 FROM public.pricing_source_card_identity i WHERE i.pricing_card_mapping_id = m.id);
  GET DIAGNOSTICS v_del = ROW_COUNT;
  IF v_del <> 25 THEN RAISE EXCEPTION '2261: esperado remover 25 vínculos NOT_FOUND, removidos %', v_del; END IF;

  -- 4. reabrir o bootstrap do Set RC (concluído com 0 cartas)
  UPDATE public.pricing_set_bootstrap_state bs
     SET status = 'PENDING', acquisition_resume_offset = 0, attempt_count = 0, next_attempt_at = now(),
         cards_confirmed = NULL, cards_pending = NULL, cards_not_found = NULL, last_error_summary = NULL
   WHERE bs.pricing_set_mapping_id = v_psm AND bs.status = 'COMPLETE' AND bs.lease_until IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION '2261: bootstrap do RC não está COMPLETE/livre'; END IF;

  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor, 'PRICING_SET_BOOTSTRAP_REOPENED', 'PRICING_SET_MAPPING', v_psm,
          jsonb_build_object('card_set_code', 'RC', 'operation', 'RC-MOVE-2261',
                             'cards_moved_in', 25, 'not_found_mappings_removed', v_del));

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor, 'CARD_SET_UPDATED', 'CARD_SET', v_bw11,
          jsonb_build_object('operation', 'RC-MOVE-2261', 'change', 'radiant_collection_cards_moved_out',
                             'cards', 25, 'total_set_size', jsonb_build_object('from', 140, 'to', 115))),
         (v_actor, 'CARD_SET_UPDATED', 'CARD_SET', v_rc,
          jsonb_build_object('operation', 'RC-MOVE-2261', 'change', 'radiant_collection_cards_moved_in',
                             'cards', 25, 'from_card_set', 'BW11'));

  -- P1: postcheck
  IF (SELECT count(*) FROM public.card WHERE card_set_id = v_rc AND is_active) <> 25
     OR (SELECT count(*) FROM public.card WHERE card_set_id = v_bw11) <> 115
     OR (SELECT count(DISTINCT collector_order) FROM public.card WHERE card_set_id = v_rc) <> 25 THEN
    RAISE EXCEPTION '2261: postcheck falhou';
  END IF;
END
$m$;
