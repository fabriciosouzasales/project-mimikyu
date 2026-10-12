/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2263 - EXU: Unown "!" e "?" como EXCL e QUES
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, apply_migration no LIVE qjfutqujxrbzgrtkpgkg).
              Dry-run abortado de propósito antes: EXCL ordem 27, QUES ordem 28, POKEMON, espécie nas duas.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — opção "B": gravar o número impresso "!"/"?" como código.

Por quê
  ck_card_collector_number_format não aceita "!" nem "?", e o número compõe o caminho da imagem.
  Códigos: EXCL ("!") e QUES ("?"). O símbolo impresso fica registrado em
  catalog_import_row.normalized_data.printed_number.

O que faz (um bloco, fail-loud)
  1. Reabre o job TCGdex do EXU e aprova as duas linhas puladas, com número EXCL/QUES, ordem 27/28,
     raridade e categoria iguais às 26 Unown (a linha "?" veio da TCGdex com 404: sem raridade e com
     categoria por fallback TRAINER).
  2. Confirma pelo caminho oficial (admin_confirm_catalog_import, como o admin), só essas 2 linhas.
  3. Espécie: "!" pela integração (dexId 201); "?" por resolução editorial
     (admin_resolve_card_primary_species, mesma espécie das demais Unown).
  4. Variante única HOLO; o trigger 2259 marca o padrão.
  Postcheck: 28 cartas, 28 padrões, 28 espécies.
===============================================================================
*/

DO $m$
DECLARE
  v_actor uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_job uuid := 'd4abc3f3-1d74-4e56-81f1-a924e6508926';
  v_row_excl uuid := '2e7ca6b8-0858-4e1b-8db2-6d4fa8e63c8f';
  v_row_ques uuid := 'bf4105e2-0cc7-4dcf-a664-e094d14aec23';
  v_set uuid; v_holo uuid; v_rare uuid; v_pkm uuid; v_species uuid; v_ques_card uuid;
  v_res record; v_var int; v_sp jsonb;
BEGIN
  SELECT id INTO STRICT v_set FROM public.card_set WHERE code = 'EXU';
  SELECT id INTO STRICT v_holo FROM public.card_variant_type WHERE code = 'HOLO';
  SELECT id INTO STRICT v_pkm FROM public.card_category WHERE code = 'POKEMON';
  -- raridade e espécie copiadas das 26 Unown já confirmadas (todas iguais)
  SELECT DISTINCT c.rarity_id INTO STRICT v_rare FROM public.card c WHERE c.card_set_id = v_set;
  SELECT DISTINCT s.pokemon_species_id INTO STRICT v_species
    FROM public.card_primary_species s JOIN public.card c ON c.id = s.card_id WHERE c.card_set_id = v_set;

  IF (SELECT count(*) FROM public.card WHERE card_set_id = v_set) <> 26
     OR EXISTS (SELECT 1 FROM public.card WHERE card_set_id = v_set AND collector_number IN ('EXCL','QUES')) THEN
    RAISE EXCEPTION '2263: EXU fora do estado esperado (26 cartas, sem EXCL/QUES)';
  END IF;
  IF (SELECT count(*) FROM public.catalog_import_row
       WHERE id IN (v_row_excl, v_row_ques) AND job_id = v_job
         AND decision_status = 'SKIPPED' AND persistence_status = 'UNCHANGED') <> 2
     OR NOT EXISTS (SELECT 1 FROM public.catalog_import_job WHERE id = v_job AND status = 'COMPLETED') THEN
    RAISE EXCEPTION '2263: linhas !/? ou job fora do estado esperado';
  END IF;

  -- 1. reabrir o job e corrigir as duas linhas (número em código, ordem 27/28, dados iguais às demais Unown)
  UPDATE public.catalog_import_job SET status = 'STAGED' WHERE id = v_job;
  UPDATE public.catalog_import_row r
     SET decision_status = 'APPROVED', persistence_status = 'PENDING', match_status = 'NEW',
         normalized_data = r.normalized_data || jsonb_build_object(
           'collector_number', CASE WHEN r.id = v_row_excl THEN 'EXCL' ELSE 'QUES' END,
           'collector_order',  CASE WHEN r.id = v_row_excl THEN 27 ELSE 28 END,
           'rarity_id', v_rare, 'category', 'POKEMON', 'category_id', v_pkm,
           'printed_number', CASE WHEN r.id = v_row_excl THEN '!' ELSE '?' END,
           'editorial_note', 'EXU-2263: número impresso "!"/"?" gravado como código (decisão de Fabrício, opção B)')
   WHERE r.id IN (v_row_excl, v_row_ques);

  -- 2. confirmar pelo caminho oficial, como o admin
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  SELECT * INTO v_res FROM public.admin_confirm_catalog_import(v_job, ARRAY[v_row_excl, v_row_ques]);
  IF v_res.failed_count <> 0 OR v_res.job_status <> 'COMPLETED' THEN
    RAISE EXCEPTION '2263: confirmação inesperada %', row_to_json(v_res);
  END IF;

  -- 3. espécie: "!" pela integração (dexId 201); "?" não tem detalhe na TCGdex → resolução editorial
  SELECT to_jsonb(x) INTO v_sp FROM public.resolve_card_primary_species_for_catalog_import_job(v_job) x LIMIT 1;
  SELECT id INTO STRICT v_ques_card FROM public.card WHERE card_set_id = v_set AND collector_number = 'QUES';
  IF NOT EXISTS (SELECT 1 FROM public.card_primary_species WHERE card_id = v_ques_card) THEN
    PERFORM public.admin_resolve_card_primary_species(v_ques_card, v_species,
      jsonb_build_object('operation', 'EXU-2263', 'reason', 'TCGdex sem detalhe (404); mesma espécie das demais 27 Unown do Set'));
  END IF;

  -- 4. variante única HOLO (como as demais); o trigger 2259 marca o padrão
  INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default)
  SELECT c.id, v_holo, 1, false FROM public.card c
   WHERE c.card_set_id = v_set AND c.collector_number IN ('EXCL','QUES');
  GET DIAGNOSTICS v_var = ROW_COUNT;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor, 'CARD_SET_UPDATED', 'CARD_SET', v_set,
          jsonb_build_object('operation', 'EXU-IMPORT-2263', 'change', 'unown_exclamation_question_imported',
                             'cards', jsonb_build_object('EXCL', '!', 'QUES', '?'), 'variants', v_var, 'job_id', v_job));

  IF (SELECT count(*) FROM public.card WHERE card_set_id = v_set AND is_active) <> 28
     OR (SELECT count(*) FROM public.card_variant v JOIN public.card c ON c.id = v.card_id
          WHERE c.card_set_id = v_set AND v.is_default) <> 28
     OR (SELECT count(*) FROM public.card_primary_species s JOIN public.card c ON c.id = s.card_id
          WHERE c.card_set_id = v_set) <> 28 THEN
    RAISE EXCEPTION '2263: postcheck falhou';
  END IF;
END
$m$;
