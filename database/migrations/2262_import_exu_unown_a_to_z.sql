/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2262 - EXU (Unseen Forces Unown Collection): importar Unown A–Z
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, apply_migration no LIVE qjfutqujxrbzgrtkpgkg).
              Dry-run abortado de propósito antes: 26 cartas A=1…Z=26, espécie Unown nas 26, 26 padrões.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — "Importar as 28 Unown".

Diagnóstico
  O job TCGdex do EXU (d4abc3f3…, 2026-09-10) tinha as 28 linhas com decisão SKIPPED e fechou sem
  criar carta. Causa real: "!" e "?" violam ck_card_collector_number_format
  (^[A-Za-z0-9][A-Za-z0-9._-]*$), e o "?" ainda veio como "%3F" com detalhe 404 na fonte (sem
  raridade, categoria por fallback). A ordem derivada também estava errada (! = 1, ? = 2, A = 3…).

O que faz (um bloco, fail-loud)
  1. Reabre o job (COMPLETED → STAGED) e aprova só as 26 linhas A–Z, corrigindo collector_order
     para A=1 … Z=26 (27 e 28 ficam reservados para ! e ?). As linhas ! e ? continuam SKIPPED.
  2. Confirma pelo caminho oficial (admin_confirm_catalog_import, como o admin) → 26 cartas.
  3. Espécie primária pela integração pós-confirmação (resolve_card_primary_species_for_catalog_import_job).
  4. Uma variante HOLO por carta (fonte: variants.holo = true, normal/reverse = false); o trigger
     2259 marca o padrão.
  5. Rastro: catalog_admin_action_log CARD_SET_UPDATED, metadata.operation = EXU-IMPORT-2262.

Pendente (decisão de Fabrício)
  "!" e "?" — a regra de formato do número não aceita esses caracteres e o número entra no caminho
  do arquivo de imagem. Imagens: a TCGdex não tem imagem para o EXU (image nulo nas 28).

Como validar
  select count(*) from public.card c join public.card_set s on s.id = c.card_set_id where s.code = 'EXU';  -- 26
===============================================================================
*/

DO $m$
DECLARE
  v_actor uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_job uuid := 'd4abc3f3-1d74-4e56-81f1-a924e6508926';
  v_set uuid; v_holo uuid; v_n int; v_res record; v_sp jsonb; v_var int;
BEGIN
  SELECT id INTO STRICT v_set FROM public.card_set WHERE code = 'EXU';
  SELECT id INTO STRICT v_holo FROM public.card_variant_type WHERE code = 'HOLO';
  IF EXISTS (SELECT 1 FROM public.card WHERE card_set_id = v_set) THEN RAISE EXCEPTION '2262: EXU já tem cartas'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.catalog_import_job WHERE id = v_job AND card_set_id = v_set AND status = 'COMPLETED' AND source = 'TCGDEX') THEN
    RAISE EXCEPTION '2262: job EXU não está no estado esperado';
  END IF;
  SELECT count(*) INTO v_n FROM public.catalog_import_row
   WHERE job_id = v_job AND raw_data->>'localId' ~ '^[A-Z]$' AND validation_status = 'VALID'
     AND decision_status = 'SKIPPED' AND persistence_status = 'UNCHANGED';
  IF v_n <> 26 THEN RAISE EXCEPTION '2262: esperado 26 linhas A–Z, encontrado %', v_n; END IF;

  -- 1. reabrir o job e aprovar A–Z, com ordem de colecionador A=1 … Z=26 (! = 27 e ? = 28 ficam reservados)
  UPDATE public.catalog_import_job SET status = 'STAGED' WHERE id = v_job;
  UPDATE public.catalog_import_row r
     SET decision_status = 'APPROVED', persistence_status = 'PENDING', match_status = 'NEW',
         normalized_data = jsonb_set(r.normalized_data, '{collector_order}',
                                     to_jsonb(ascii(r.raw_data->>'localId') - 64))
   WHERE r.job_id = v_job AND r.raw_data->>'localId' ~ '^[A-Z]$';

  -- 2. confirmar pelo caminho oficial, como o admin
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  SELECT * INTO v_res FROM public.admin_confirm_catalog_import(v_job, NULL);
  IF v_res.inserted_count <> 26 OR v_res.failed_count <> 0 OR v_res.job_status <> 'COMPLETED' THEN
    RAISE EXCEPTION '2262: confirmação inesperada %', row_to_json(v_res);
  END IF;

  -- 3. espécie primária (integração pós-confirmação, 6116)
  SELECT to_jsonb(x) INTO v_sp FROM public.resolve_card_primary_species_for_catalog_import_job(v_job) x LIMIT 1;

  -- 4. variante única HOLO (fonte: variants.holo = true em todas); o trigger 2259 define o padrão
  INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default)
  SELECT c.id, v_holo, 1, false FROM public.card c WHERE c.card_set_id = v_set;
  GET DIAGNOSTICS v_var = ROW_COUNT;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor, 'CARD_SET_UPDATED', 'CARD_SET', v_set,
          jsonb_build_object('operation', 'EXU-IMPORT-2262', 'change', 'unown_collection_imported',
                             'cards', 26, 'variants', v_var, 'job_id', v_job,
                             'pending', jsonb_build_array('!', '?')));

  IF (SELECT count(*) FROM public.card WHERE card_set_id = v_set) <> 26
     OR (SELECT count(*) FROM public.card_variant v JOIN public.card c ON c.id = v.card_id
          WHERE c.card_set_id = v_set AND v.is_default) <> 26 THEN
    RAISE EXCEPTION '2262: postcheck falhou';
  END IF;
END
$m$;
