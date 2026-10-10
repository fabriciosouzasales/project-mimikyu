/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: R1 - Recuperação de collector_order em 8 Coleções XY + 15 cartas ausentes
Status......: PROPOSTA (dry-run com v_apply = false)
Data........: 2026-10-10
Origem......: database/proposals/2026-10-10-xy-collector-order-recovery/README.md

Problema
  Na importação de 11/09 (TCGdex pt-BR) a regra antiga deriveCollectorOrder()
  deu às cartas com sufixo ("24a") a ordem da carta seguinte. 15 linhas falharam
  com uq_card_card_set_collector_order e as cartas nunca foram criadas.
  A regra SET-LEVEL (collector-order.ts, 2026-09-10) já corrige importações
  novas, mas os 8 Sets afetados nunca foram reprocessados.

O que faz (por Set: XY2, XY3, XY4, XY6, XY7, XY8, XY9, XY10)
  1. Plano: conjunto COMPLETO = todas as linhas do job TCGDEX do Set (persistidas
     + FAILED). Ordem = chave natural (número, sufixo; "88" < "88a" < "88b" < "89"),
     1..N denso — mesma regra ORDINAL_DERIVED do collector-order.ts.
  2. Gates: toda carta persistida do Set mapeada por resulting_card_id; zero
     formato desconhecido; zero chave duplicada.
  3. Reordena as cartas existentes (duas fases: +100000 e depois o valor final,
     para não violar o UNIQUE no meio do caminho).
  4. Cria as 15 cartas pelo writer canônico internal.write_card('CREATE'),
     com os dados normalizados da própria linha FAILED; a linha passa a
     INSERTED e o job é recontado (COMPLETED quando não sobra FAILED).
  5. Primary Species: resolve_card_primary_species_for_catalog_import_job por job.

Fora deste script (pelos fluxos oficiais da UI, depois do apply)
  - Importar Imagens dos 8 Sets (import-card-assets cria card_external_reference e card_asset);
  - Importar Variantes dos 8 Sets (só as 15 cartas novas geram linhas novas).
===============================================================================
*/

DO $r1$
DECLARE
    v_apply  CONSTANT BOOLEAN := false;
    v_admin  CONSTANT UUID := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
    v_jobs   CONSTANT UUID[] := ARRAY[
        '705a1404-e8c4-4283-a7e8-92b020c9e2c8',  -- XY2
        '632f8320-f863-402f-a033-cc7dd23ee3df',  -- XY3
        'df101205-ba71-48ed-ad72-20f9edd1051d',  -- XY4
        '8e815d7d-b2bb-474d-9961-8461e0978ab5',  -- XY6
        'f1db6cac-fd13-4e80-a8e0-7f918ca6038c',  -- XY7
        '5e81c213-c29a-4814-a9c1-ff74963cd3a2',  -- XY8
        '060a52fd-2a4e-4a28-be42-3a30796788ea',  -- XY9
        '12a0ebcf-2cc4-4490-b4f1-c79c882da03f']::uuid[];  -- XY10
    v_n INT; v_cards_before INT; v_cards_after INT; v_reordered INT; v_inserted INT := 0;
    v_row RECORD; v_card UUID; v_job UUID; v_sp RECORD; v_sp_txt TEXT := '';
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'R1_G0_NOT_ADMIN'; END IF;

    -- jobs: 8, TCGDEX, COMPLETED_WITH_ERRORS, 15 FAILED no total
    SELECT count(*) INTO v_n FROM public.catalog_import_job
     WHERE id = ANY(v_jobs) AND source = 'TCGDEX' AND status = 'COMPLETED_WITH_ERRORS';
    IF v_n <> 8 THEN RAISE EXCEPTION 'R1_G1_JOBS: %', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.catalog_import_row
     WHERE job_id = ANY(v_jobs) AND persistence_status = 'FAILED';
    IF v_n <> 15 THEN RAISE EXCEPTION 'R1_G2_FAILED: %', v_n; END IF;

    CREATE TEMP TABLE r1_plan ON COMMIT DROP AS
    SELECT j.card_set_id, r.id AS row_id, r.job_id, r.persistence_status AS ps,
           r.resulting_card_id AS card_id, r.raw_data->>'localId' AS lid,
           substring(r.raw_data->>'localId' from '^([0-9]+)')::int AS num,
           upper(coalesce(substring(r.raw_data->>'localId' from '^[0-9]+([A-Za-z]+)$'), '')) AS suf,
           (r.raw_data->>'localId') ~ '^[0-9]+[A-Za-z]*$' AS fmt_ok
      FROM public.catalog_import_job j
      JOIN public.catalog_import_row r ON r.job_id = j.id
     WHERE j.id = ANY(v_jobs);

    SELECT count(*) INTO v_n FROM r1_plan WHERE NOT fmt_ok;
    IF v_n <> 0 THEN RAISE EXCEPTION 'R1_G3_FORMATO: %', v_n; END IF;
    SELECT count(*) - count(DISTINCT (card_set_id, num, suf)) INTO v_n FROM r1_plan;
    IF v_n <> 0 THEN RAISE EXCEPTION 'R1_G4_CHAVE_DUPLICADA: %', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.card c
     WHERE c.card_set_id IN (SELECT card_set_id FROM r1_plan)
       AND c.id NOT IN (SELECT card_id FROM r1_plan WHERE card_id IS NOT NULL);
    IF v_n <> 0 THEN RAISE EXCEPTION 'R1_G5_CARTA_FORA_DO_PLANO: %', v_n; END IF;
    SELECT count(*) INTO v_n FROM r1_plan WHERE ps <> 'FAILED' AND card_id IS NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'R1_G6_LINHA_SEM_CARTA: %', v_n; END IF;

    ALTER TABLE r1_plan ADD COLUMN new_order INT;
    UPDATE r1_plan p SET new_order = x.o
      FROM (SELECT row_id, row_number() OVER (PARTITION BY card_set_id ORDER BY num, suf) AS o
              FROM r1_plan) x
     WHERE x.row_id = p.row_id;

    SELECT count(*) INTO v_cards_before FROM public.card
     WHERE card_set_id IN (SELECT card_set_id FROM r1_plan);

    -- reordenação em duas fases
    UPDATE public.card c SET collector_order = c.collector_order + 100000
     WHERE c.card_set_id IN (SELECT DISTINCT card_set_id FROM r1_plan);
    UPDATE public.card c SET collector_order = p.new_order
      FROM r1_plan p WHERE p.card_id = c.id;
    GET DIAGNOSTICS v_reordered = ROW_COUNT;

    -- 15 cartas ausentes
    FOR v_row IN
        SELECT p.*, r.normalized_data AS nd
          FROM r1_plan p JOIN public.catalog_import_row r ON r.id = p.row_id
         WHERE p.ps = 'FAILED' ORDER BY p.card_set_id, p.new_order
    LOOP
        v_card := internal.write_card('CREATE', NULL, v_row.card_set_id,
            (v_row.nd->>'rarity_id')::uuid, (v_row.nd->>'category_id')::uuid,
            v_row.nd->>'collector_number', NULLIF(v_row.nd->>'collector_total','')::int,
            v_row.new_order, v_row.nd->>'name');
        UPDATE public.catalog_import_row
           SET persistence_status = 'INSERTED', match_status = 'NEW',
               matched_card_id = v_card, resulting_card_id = v_card, error_detail = NULL,
               normalized_data = jsonb_set(normalized_data, '{collector_order}', to_jsonb(v_row.new_order))
         WHERE id = v_row.row_id;
        v_inserted := v_inserted + 1;
    END LOOP;

    -- collector_order gravado nas demais linhas também passa a refletir o plano
    UPDATE public.catalog_import_row r
       SET normalized_data = jsonb_set(r.normalized_data, '{collector_order}', to_jsonb(p.new_order))
      FROM r1_plan p
     WHERE p.row_id = r.id AND p.ps <> 'FAILED'
       AND (r.normalized_data->>'collector_order')::int IS DISTINCT FROM p.new_order;

    -- recontagem dos jobs
    UPDATE public.catalog_import_job j
       SET inserted_rows = (SELECT count(*) FROM public.catalog_import_row WHERE job_id = j.id AND persistence_status = 'INSERTED'),
           failed_rows   = (SELECT count(*) FROM public.catalog_import_row WHERE job_id = j.id AND persistence_status = 'FAILED'),
           status = CASE WHEN EXISTS (SELECT 1 FROM public.catalog_import_row WHERE job_id = j.id AND persistence_status = 'FAILED')
                         THEN 'COMPLETED_WITH_ERRORS' ELSE 'COMPLETED' END
     WHERE j.id = ANY(v_jobs);

    -- Primary Species (escopo do job; idempotente)
    FOREACH v_job IN ARRAY v_jobs LOOP
        SELECT * INTO v_sp FROM public.resolve_card_primary_species_for_catalog_import_job(v_job);
        v_sp_txt := v_sp_txt || format('%s:%s/%s ', left(v_job::text, 8), v_sp.status, v_sp.resolved_count);
    END LOOP;

    -- postchecks
    SELECT count(*) INTO v_cards_after FROM public.card
     WHERE card_set_id IN (SELECT card_set_id FROM r1_plan);
    IF v_inserted <> 15 OR v_cards_after - v_cards_before <> 15 THEN
        RAISE EXCEPTION 'R1_P1_INSERT: inserted %, delta %', v_inserted, v_cards_after - v_cards_before;
    END IF;
    SELECT count(*) INTO v_n FROM public.card c JOIN r1_plan p ON p.card_set_id = c.card_set_id
     WHERE c.collector_order > 100000;
    IF v_n <> 0 THEN RAISE EXCEPTION 'R1_P2_ORDEM_TEMPORARIA: %', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.catalog_import_job WHERE id = ANY(v_jobs) AND status <> 'COMPLETED';
    IF v_n <> 0 THEN RAISE EXCEPTION 'R1_P3_JOBS: %', v_n; END IF;
    -- cada Set: ordens 1..N densas
    SELECT count(*) INTO v_n FROM (
        SELECT c.card_set_id FROM public.card c
         WHERE c.card_set_id IN (SELECT card_set_id FROM r1_plan)
         GROUP BY 1 HAVING min(c.collector_order) <> 1 OR max(c.collector_order) <> count(*)) z;
    IF v_n <> 0 THEN RAISE EXCEPTION 'R1_P4_DENSIDADE: %', v_n; END IF;

    IF NOT v_apply THEN
        RAISE EXCEPTION 'R1_DRYRUN_OK: cartas % -> %, reordenadas %, inseridas %, species [%]',
            v_cards_before, v_cards_after, v_reordered, v_inserted, v_sp_txt;
    END IF;
    RAISE NOTICE 'R1_APPLY_OK: cartas % -> %, inseridas %, species [%]',
        v_cards_before, v_cards_after, v_inserted, v_sp_txt;
END;
$r1$;
