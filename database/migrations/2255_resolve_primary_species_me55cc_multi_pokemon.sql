/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2255 - Primary Species das 3 cartas multi-Pokémon da ME5.5CC
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Origem......: database/proposals/2026-10-10-me55-30th-celebration/README.md

Decisão editorial de Fabrício (2026-10-10):
  008 Pikachu & Zekrom GX        [25, 644]  -> Pikachu (25)
  019 Darkrai & Cresselia LENDA  [491, 488] -> Darkrai (491)
  020 Darkrai & Cresselia LENDA  [491, 488] -> Cresselia (488)
Gravado por admin_resolve_card_primary_species (EDITORIAL_RECONCILIATION),
com os dois dexIds e o escolhido na evidência. Escopo: só estas 3 cartas
(as originais SM9/SMP/HGSS4 continuam sem Primary Species).
===============================================================================
*/
DO $p$
DECLARE r record; v_n int := 0;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub','fe316458-49dd-44e1-aac0-f4b7604ef8f2','role','authenticated')::text, true);
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
  FOR r IN
    SELECT c.id card_id, sp.id species_id, m.dex, m.ext, m.all_dex
      FROM (VALUES ('008', 25, 'me55c-33', '[25,644]'), ('019', 491, 'me55c-99', '[491,488]'), ('020', 488, 'me55c-100', '[491,488]')) m(num, dex, ext, all_dex)
      JOIN public.card_set s ON s.code = 'ME5.5CC'
      JOIN public.card c ON c.card_set_id = s.id AND c.collector_number = m.num AND c.is_active
      JOIN public.pokemon_species sp ON sp.national_dex_number = m.dex
  LOOP
    PERFORM public.admin_resolve_card_primary_species(r.card_id, r.species_id, jsonb_build_object(
      'source', 'EDITORIAL', 'decided_by', 'Fabrício (2026-10-10)',
      'external_card_id', r.ext, 'national_dex_numbers', r.all_dex::jsonb, 'chosen_dex_id', r.dex,
      'rule', 'carta com mais de um Pokémon: escolha editorial explícita', 'operation', '2255', 'observed_at', now()));
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 3 THEN RAISE EXCEPTION 'G_ESPERADO_3: %', v_n; END IF;
END $p$;
