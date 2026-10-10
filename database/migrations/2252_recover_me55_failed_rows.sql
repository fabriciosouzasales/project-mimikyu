/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2252 - ME5.5 / ME5.5CC: raridades novas + 62 linhas FAILED viram cartas
Status......: CONFIRMADO EXECUTADO (2026-10-10, dry-run PASS antes; one-shot)
Origem......: database/proposals/2026-10-10-me55-30th-celebration/README.md

Problema
  Job ME5.5 cfe7b926: 32 linhas FAILED ("Não foi possível identificar o Game da
  Rarity") — raridades TCGdex "Pikachu Rare" (023-052) e "Futuristic Rare"
  (157-158) sem mapeamento.
  Job ME5.5CC 9c54c1d9: 30 linhas FAILED em ck_card_collector_total_positive —
  a TCGdex devolve cardCount.official = 0 para 30th-c (corrigido no importador,
  Versão 7.1).

O que faz
  1. Cria PIKACHU_RARE ("Rara Pikachu", 30) e FUTURISTIC_RARE ("Rara Futurista",
     31), símbolo GOLD_STAR, + 4 mapeamentos TCGDEX (en e pt).
  2. Cria as 62 cartas por internal.write_card a partir de normalized_data;
     ME5.5CC com collector_total 30 e raridade CLASSIC_COLLECTION (precedente CEL25CC).
  3. Linhas -> INSERTED, jobs -> COMPLETED, Primary Species por job
     (resultado 0: a TCGdex ainda não publica dexId para 30th / 30th-c).

Resultado: ME5.5 158 cartas (ordem 1..158), ME5.5CC 30 cartas (1..30).
===============================================================================
*/
DO $m$
DECLARE
  v_apply CONSTANT boolean := true;
  v_game CONSTANT uuid := 'f3c1ae5f-c387-46bd-b7a8-2bb21455c285';
  v_src  CONSTANT uuid := 'f070791a-a2a0-4bdf-b84d-abf873c5f8d5';
  v_jobs CONSTANT uuid[] := ARRAY['cfe7b926-7213-4d36-9212-1a666c2ce252','9c54c1d9-7814-4fb5-a01c-b571d0300d0e']::uuid[];
  v_cc_job CONSTANT uuid := '9c54c1d9-7814-4fb5-a01c-b571d0300d0e';
  v_pika uuid; v_fut uuid; v_cc uuid; v_rar uuid; v_tot int;
  v_row record; v_card uuid; v_n int := 0; v_sp record; v_txt text := '';
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub','fe316458-49dd-44e1-aac0-f4b7604ef8f2','role','authenticated')::text, true);
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;

  INSERT INTO public.rarity (code,name,game_id,symbol_code,display_order)
  VALUES ('PIKACHU_RARE','Rara Pikachu',v_game,'GOLD_STAR',30) RETURNING id INTO v_pika;
  INSERT INTO public.rarity (code,name,game_id,symbol_code,display_order)
  VALUES ('FUTURISTIC_RARE','Rara Futurista',v_game,'GOLD_STAR',31) RETURNING id INTO v_fut;
  INSERT INTO public.rarity_external_mapping (game_id,asset_source_id,rarity_id,external_value,normalized_external_value) VALUES
   (v_game,v_src,v_pika,'Pikachu Rare','PIKACHU RARE'),(v_game,v_src,v_pika,'Rara Pikachu','RARA PIKACHU'),
   (v_game,v_src,v_fut,'Futuristic Rare','FUTURISTIC RARE'),(v_game,v_src,v_fut,'Rara Futurista','RARA FUTURISTA');
  SELECT id INTO v_cc FROM public.rarity WHERE code='CLASSIC_COLLECTION';

  SELECT count(*) INTO v_n FROM public.catalog_import_row WHERE job_id = ANY(v_jobs) AND persistence_status='FAILED';
  IF v_n <> 62 THEN RAISE EXCEPTION 'G_FAILED %', v_n; END IF;
  v_n := 0;

  FOR v_row IN SELECT r.id, r.job_id, j.card_set_id, r.normalized_data nd, r.raw_data->>'rarity' rr
                 FROM public.catalog_import_row r JOIN public.catalog_import_job j ON j.id=r.job_id
                WHERE r.job_id = ANY(v_jobs) AND r.persistence_status='FAILED'
                ORDER BY j.card_set_id, (r.normalized_data->>'collector_order')::int
  LOOP
    IF v_row.job_id = v_cc_job THEN v_rar := v_cc; v_tot := 30;
    ELSE v_rar := CASE v_row.rr WHEN 'Pikachu Rare' THEN v_pika WHEN 'Futuristic Rare' THEN v_fut END;
         v_tot := (v_row.nd->>'collector_total')::int; END IF;
    IF v_rar IS NULL OR (v_row.nd->>'category_id') IS NULL THEN RAISE EXCEPTION 'G_ROW %', v_row.id; END IF;
    v_card := internal.write_card('CREATE', NULL, v_row.card_set_id, v_rar, (v_row.nd->>'category_id')::uuid,
                v_row.nd->>'collector_number', v_tot, (v_row.nd->>'collector_order')::int, v_row.nd->>'name');
    UPDATE public.catalog_import_row SET persistence_status='INSERTED', validation_status='VALID', error_detail=NULL,
           matched_card_id=v_card, resulting_card_id=v_card,
           normalized_data = normalized_data || jsonb_build_object('rarity_id', v_rar, 'collector_total', v_tot, 'review_notes', null)
     WHERE id = v_row.id;
    v_n := v_n + 1;
  END LOOP;

  UPDATE public.catalog_import_job j
     SET inserted_rows=(SELECT count(*) FROM public.catalog_import_row WHERE job_id=j.id AND persistence_status='INSERTED'),
         failed_rows=(SELECT count(*) FROM public.catalog_import_row WHERE job_id=j.id AND persistence_status='FAILED'),
         status='COMPLETED'
   WHERE j.id = ANY(v_jobs);

  FOREACH v_rar IN ARRAY v_jobs LOOP
    SELECT * INTO v_sp FROM public.resolve_card_primary_species_for_catalog_import_job(v_rar);
    v_txt := v_txt || format('%s:%s/%s ', left(v_rar::text,8), v_sp.status, v_sp.resolved_count);
  END LOOP;

  SELECT count(*) INTO v_tot FROM public.card c JOIN public.card_set s ON s.id=c.card_set_id WHERE s.code IN ('ME5.5','ME5.5CC') AND c.is_active;
  IF NOT v_apply THEN RAISE EXCEPTION 'DRYRUN_OK criadas % ; cartas ME5.5+CC % ; species %', v_n, v_tot, v_txt; END IF;
  RAISE NOTICE 'APPLY_OK criadas % ; cartas % ; species %', v_n, v_tot, v_txt;
END $m$;
