/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2257 - Variantes das 295 cartas sem nenhuma Card Variant (BOOTSTRAP-03 closeout)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, execute_sql no LIVE qjfutqujxrbzgrtkpgkg; 295 inseridas, 0 cartas sem variante)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — Trainer Kits: "Usar a Scrydex"; CEL25CC: "Criar HOLO pela
              tabela" (revoga a decisão de 2026-10-09 de deixar a CEL25CC sem variante).
Origem......: database/proposals/2026-10-11-bootstrap-03-closeout/README.md

O que faz
  Cria uma Card Variant para cada uma das 295 cartas ativas que não têm nenhuma:
  - 270 cartas de 9 Trainer Kits (TK-HS-G, TK-XY-N/SY/W/B/LATIO/LATIA/SU/P): fonte Scrydex
    (variante declarada por carta na página da expansão: normal -> STANDARD, holofoil -> HOLO;
    em todos os 9 kits só a carta 30 é holofoil). Mesmo padrão dos Trainer Kits já catalogados
    (STANDARD 1–29, HOLO 30; sem Printing nem Edition Context).
  - 25 cartas da CEL25CC: HOLO (fonte: snapshot Pokémon TCG API, cel25c, só holofoil), pela tabela
    de correspondência CC001–CC025 conferida carta a carta na importação das imagens. Mesmo padrão da
    CEL25 (HOLO, sem Edition Context).
  variant_order = 1, is_default = false (o default é tarefa do DEFAULT-BACKFILL-01).

Garantias (fail closed, tudo ou nada)
  G1  cada linha encontra exatamente 1 carta ativa (Set + número) com o nome esperado;
  G2  nenhuma dessas cartas tem variante (idempotência: rodar de novo aborta);
  G3  Variant Types STANDARD e HOLO existem;
  P1  295 variantes inseridas; cartas ativas sem variante = 0 depois.
  Rastro: 1 linha em catalog_admin_action_log por Card Set (CARD_SET_UPDATED, metadata com fonte).

Como validar
  select count(*) from public.card c where c.is_active
     and not exists (select 1 from public.card_variant v where v.card_id = c.id);  -- esperado 0
===============================================================================
*/

DO $mig$
DECLARE
  v_actor uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_std uuid; v_holo uuid; v_n int; v_bad text;
BEGIN
  SELECT id INTO v_std  FROM public.card_variant_type WHERE code = 'STANDARD';
  SELECT id INTO v_holo FROM public.card_variant_type WHERE code = 'HOLO';
  IF v_std IS NULL OR v_holo IS NULL THEN RAISE EXCEPTION '2257_G3_VARIANT_TYPES'; END IF;

  CREATE TEMP TABLE t2257 (set_code text, num text, expected_name text, vt text, source_id text, source_variant text) ON COMMIT DROP;
  INSERT INTO t2257 VALUES
  ('TK-HS-G', '01', 'Totodile', 'STANDARD', 'tk4b-1', 'normal'),
  ('TK-HS-G', '02', 'Water Energy', 'STANDARD', 'tk4b-2', 'normal'),
  ('TK-HS-G', '03', 'Water Energy', 'STANDARD', 'tk4b-3', 'normal'),
  ('TK-HS-G', '04', 'Water Energy', 'STANDARD', 'tk4b-4', 'normal'),
  ('TK-HS-G', '05', 'Bill', 'STANDARD', 'tk4b-5', 'normal'),
  ('TK-HS-G', '06', 'Water Energy', 'STANDARD', 'tk4b-6', 'normal'),
  ('TK-HS-G', '07', 'Water Energy', 'STANDARD', 'tk4b-7', 'normal'),
  ('TK-HS-G', '08', 'Water Energy', 'STANDARD', 'tk4b-8', 'normal'),
  ('TK-HS-G', '09', 'Water Energy', 'STANDARD', 'tk4b-9', 'normal'),
  ('TK-HS-G', '10', 'Water Energy', 'STANDARD', 'tk4b-10', 'normal'),
  ('TK-HS-G', '11', 'Water Energy', 'STANDARD', 'tk4b-11', 'normal'),
  ('TK-HS-G', '12', 'Magikarp', 'STANDARD', 'tk4b-12', 'normal'),
  ('TK-HS-G', '13', 'Croconaw', 'STANDARD', 'tk4b-13', 'normal'),
  ('TK-HS-G', '14', 'Totodile', 'STANDARD', 'tk4b-14', 'normal'),
  ('TK-HS-G', '15', 'Marill', 'STANDARD', 'tk4b-15', 'normal'),
  ('TK-HS-G', '16', 'Water Energy', 'STANDARD', 'tk4b-16', 'normal'),
  ('TK-HS-G', '17', 'Croconaw', 'STANDARD', 'tk4b-17', 'normal'),
  ('TK-HS-G', '18', 'Bill', 'STANDARD', 'tk4b-18', 'normal'),
  ('TK-HS-G', '19', 'Magikarp', 'STANDARD', 'tk4b-19', 'normal'),
  ('TK-HS-G', '20', 'Gyarados', 'STANDARD', 'tk4b-20', 'normal'),
  ('TK-HS-G', '21', 'Energy Switch', 'STANDARD', 'tk4b-21', 'normal'),
  ('TK-HS-G', '22', 'Pokémon Communication', 'STANDARD', 'tk4b-22', 'normal'),
  ('TK-HS-G', '23', 'Poké Ball', 'STANDARD', 'tk4b-23', 'normal'),
  ('TK-HS-G', '24', 'Marill', 'STANDARD', 'tk4b-24', 'normal'),
  ('TK-HS-G', '25', 'Professor Elm''s Training Method', 'STANDARD', 'tk4b-25', 'normal'),
  ('TK-HS-G', '26', 'Water Energy', 'STANDARD', 'tk4b-26', 'normal'),
  ('TK-HS-G', '27', 'Pokémon Communication', 'STANDARD', 'tk4b-27', 'normal'),
  ('TK-HS-G', '28', 'Switch', 'STANDARD', 'tk4b-28', 'normal'),
  ('TK-HS-G', '29', 'Water Energy', 'STANDARD', 'tk4b-29', 'normal'),
  ('TK-HS-G', '30', 'Gyarados', 'HOLO', 'tk4b-30', 'holofoil'),
  ('TK-XY-B', '01', 'Fletchling', 'STANDARD', 'tk7b-1', 'normal'),
  ('TK-XY-B', '02', 'Metal Energy', 'STANDARD', 'tk7b-2', 'normal'),
  ('TK-XY-B', '03', 'Metal Energy', 'STANDARD', 'tk7b-3', 'normal'),
  ('TK-XY-B', '04', 'Vigoroth', 'STANDARD', 'tk7b-4', 'normal'),
  ('TK-XY-B', '05', 'Metal Energy', 'STANDARD', 'tk7b-5', 'normal'),
  ('TK-XY-B', '06', 'Metal Energy', 'STANDARD', 'tk7b-6', 'normal'),
  ('TK-XY-B', '07', 'Metal Energy', 'STANDARD', 'tk7b-7', 'normal'),
  ('TK-XY-B', '08', 'Metal Energy', 'STANDARD', 'tk7b-8', 'normal'),
  ('TK-XY-B', '09', 'Metal Energy', 'STANDARD', 'tk7b-9', 'normal'),
  ('TK-XY-B', '10', 'Metal Energy', 'STANDARD', 'tk7b-10', 'normal'),
  ('TK-XY-B', '11', 'Honedge', 'STANDARD', 'tk7b-11', 'normal'),
  ('TK-XY-B', '12', 'Bidoof', 'STANDARD', 'tk7b-12', 'normal'),
  ('TK-XY-B', '13', 'Pawniard', 'STANDARD', 'tk7b-13', 'normal'),
  ('TK-XY-B', '14', 'Doublade', 'STANDARD', 'tk7b-14', 'normal'),
  ('TK-XY-B', '15', 'Slakoth', 'STANDARD', 'tk7b-15', 'normal'),
  ('TK-XY-B', '16', 'Bisharp', 'STANDARD', 'tk7b-16', 'normal'),
  ('TK-XY-B', '17', 'Patrat', 'STANDARD', 'tk7b-17', 'normal'),
  ('TK-XY-B', '18', 'Metal Energy', 'STANDARD', 'tk7b-18', 'normal'),
  ('TK-XY-B', '19', 'Tierno', 'STANDARD', 'tk7b-19', 'normal'),
  ('TK-XY-B', '20', 'Trevor', 'STANDARD', 'tk7b-20', 'normal'),
  ('TK-XY-B', '21', 'Pawniard', 'STANDARD', 'tk7b-21', 'normal'),
  ('TK-XY-B', '22', 'Metal Energy', 'STANDARD', 'tk7b-22', 'normal'),
  ('TK-XY-B', '23', 'Doublade', 'STANDARD', 'tk7b-23', 'normal'),
  ('TK-XY-B', '24', 'Metal Energy', 'STANDARD', 'tk7b-24', 'normal'),
  ('TK-XY-B', '25', 'Potion', 'STANDARD', 'tk7b-25', 'normal'),
  ('TK-XY-B', '26', 'Slakoth', 'STANDARD', 'tk7b-26', 'normal'),
  ('TK-XY-B', '27', 'Honedge', 'STANDARD', 'tk7b-27', 'normal'),
  ('TK-XY-B', '28', 'Vigoroth', 'STANDARD', 'tk7b-28', 'normal'),
  ('TK-XY-B', '29', 'Potion', 'STANDARD', 'tk7b-29', 'normal'),
  ('TK-XY-B', '30', 'Bisharp', 'HOLO', 'tk7b-30', 'holofoil'),
  ('TK-XY-LATIA', '01', 'Grass Energy', 'STANDARD', 'tk8b-1', 'normal'),
  ('TK-XY-LATIA', '02', 'Grass Energy', 'STANDARD', 'tk8b-2', 'normal'),
  ('TK-XY-LATIA', '03', 'Grass Energy', 'STANDARD', 'tk8b-3', 'normal'),
  ('TK-XY-LATIA', '04', 'Fletchling', 'STANDARD', 'tk8b-4', 'normal'),
  ('TK-XY-LATIA', '05', 'Grass Energy', 'STANDARD', 'tk8b-5', 'normal'),
  ('TK-XY-LATIA', '06', 'Lombre', 'STANDARD', 'tk8b-6', 'normal'),
  ('TK-XY-LATIA', '07', 'Treecko', 'STANDARD', 'tk8b-7', 'normal'),
  ('TK-XY-LATIA', '08', 'Psychic Energy', 'STANDARD', 'tk8b-8', 'normal'),
  ('TK-XY-LATIA', '09', 'Psychic Energy', 'STANDARD', 'tk8b-9', 'normal'),
  ('TK-XY-LATIA', '10', 'Psychic Energy', 'STANDARD', 'tk8b-10', 'normal'),
  ('TK-XY-LATIA', '11', 'Lotad', 'STANDARD', 'tk8b-11', 'normal'),
  ('TK-XY-LATIA', '12', 'Tangrowth', 'STANDARD', 'tk8b-12', 'normal'),
  ('TK-XY-LATIA', '13', 'Tangela', 'STANDARD', 'tk8b-13', 'normal'),
  ('TK-XY-LATIA', '14', 'Latias', 'STANDARD', 'tk8b-14', 'normal'),
  ('TK-XY-LATIA', '15', 'Potion', 'STANDARD', 'tk8b-15', 'normal'),
  ('TK-XY-LATIA', '16', 'Surskit', 'STANDARD', 'tk8b-16', 'normal'),
  ('TK-XY-LATIA', '17', 'Psychic Energy', 'STANDARD', 'tk8b-17', 'normal'),
  ('TK-XY-LATIA', '18', 'Grovyle', 'STANDARD', 'tk8b-18', 'normal'),
  ('TK-XY-LATIA', '19', 'Grass Energy', 'STANDARD', 'tk8b-19', 'normal'),
  ('TK-XY-LATIA', '20', 'Acro Bike', 'STANDARD', 'tk8b-20', 'normal'),
  ('TK-XY-LATIA', '21', 'Lombre', 'STANDARD', 'tk8b-21', 'normal'),
  ('TK-XY-LATIA', '22', 'Psychic Energy', 'STANDARD', 'tk8b-22', 'normal'),
  ('TK-XY-LATIA', '23', 'Lotad', 'STANDARD', 'tk8b-23', 'normal'),
  ('TK-XY-LATIA', '24', 'Treecko', 'STANDARD', 'tk8b-24', 'normal'),
  ('TK-XY-LATIA', '25', 'Tangrowth', 'STANDARD', 'tk8b-25', 'normal'),
  ('TK-XY-LATIA', '26', 'Tangela', 'STANDARD', 'tk8b-26', 'normal'),
  ('TK-XY-LATIA', '27', 'Grovyle', 'STANDARD', 'tk8b-27', 'normal'),
  ('TK-XY-LATIA', '28', 'Psychic Energy', 'STANDARD', 'tk8b-28', 'normal'),
  ('TK-XY-LATIA', '29', 'Acro Bike', 'STANDARD', 'tk8b-29', 'normal'),
  ('TK-XY-LATIA', '30', 'Latias', 'HOLO', 'tk8b-30', 'holofoil'),
  ('TK-XY-LATIO', '01', 'Skitty', 'STANDARD', 'tk8a-1', 'normal'),
  ('TK-XY-LATIO', '02', 'Fighting Energy', 'STANDARD', 'tk8a-2', 'normal'),
  ('TK-XY-LATIO', '03', 'Fighting Energy', 'STANDARD', 'tk8a-3', 'normal'),
  ('TK-XY-LATIO', '04', 'Rhydon', 'STANDARD', 'tk8a-4', 'normal'),
  ('TK-XY-LATIO', '05', 'Fighting Energy', 'STANDARD', 'tk8a-5', 'normal'),
  ('TK-XY-LATIO', '06', 'Fighting Energy', 'STANDARD', 'tk8a-6', 'normal'),
  ('TK-XY-LATIO', '07', 'Fighting Energy', 'STANDARD', 'tk8a-7', 'normal'),
  ('TK-XY-LATIO', '08', 'Fighting Energy', 'STANDARD', 'tk8a-8', 'normal'),
  ('TK-XY-LATIO', '09', 'Fighting Energy', 'STANDARD', 'tk8a-9', 'normal'),
  ('TK-XY-LATIO', '10', 'Fighting Energy', 'STANDARD', 'tk8a-10', 'normal'),
  ('TK-XY-LATIO', '11', 'Machop', 'STANDARD', 'tk8a-11', 'normal'),
  ('TK-XY-LATIO', '12', 'Solrock', 'STANDARD', 'tk8a-12', 'normal'),
  ('TK-XY-LATIO', '13', 'Latios', 'STANDARD', 'tk8a-13', 'normal'),
  ('TK-XY-LATIO', '14', 'Machoke', 'STANDARD', 'tk8a-14', 'normal'),
  ('TK-XY-LATIO', '15', 'Rhyhorn', 'STANDARD', 'tk8a-15', 'normal'),
  ('TK-XY-LATIO', '16', 'Psychic Energy', 'STANDARD', 'tk8a-16', 'normal'),
  ('TK-XY-LATIO', '17', 'Fighting Energy', 'STANDARD', 'tk8a-17', 'normal'),
  ('TK-XY-LATIO', '18', 'Psychic Energy', 'STANDARD', 'tk8a-18', 'normal'),
  ('TK-XY-LATIO', '19', 'Delcatty', 'STANDARD', 'tk8a-19', 'normal'),
  ('TK-XY-LATIO', '20', 'Acro Bike', 'STANDARD', 'tk8a-20', 'normal'),
  ('TK-XY-LATIO', '21', 'Potion', 'STANDARD', 'tk8a-21', 'normal'),
  ('TK-XY-LATIO', '22', 'Machoke', 'STANDARD', 'tk8a-22', 'normal'),
  ('TK-XY-LATIO', '23', 'Rhyhorn', 'STANDARD', 'tk8a-23', 'normal'),
  ('TK-XY-LATIO', '24', 'Delcatty', 'STANDARD', 'tk8a-24', 'normal'),
  ('TK-XY-LATIO', '25', 'Rhydon', 'STANDARD', 'tk8a-25', 'normal'),
  ('TK-XY-LATIO', '26', 'Solrock', 'STANDARD', 'tk8a-26', 'normal'),
  ('TK-XY-LATIO', '27', 'Skitty', 'STANDARD', 'tk8a-27', 'normal'),
  ('TK-XY-LATIO', '28', 'Machop', 'STANDARD', 'tk8a-28', 'normal'),
  ('TK-XY-LATIO', '29', 'Psychic Energy', 'STANDARD', 'tk8a-29', 'normal'),
  ('TK-XY-LATIO', '30', 'Latios', 'HOLO', 'tk8a-30', 'holofoil'),
  ('TK-XY-N', '01', 'Spoink', 'STANDARD', 'tk6b-1', 'normal'),
  ('TK-XY-N', '02', 'Gourgeist', 'STANDARD', 'tk6b-2', 'normal'),
  ('TK-XY-N', '03', 'Arbok', 'STANDARD', 'tk6b-3', 'normal'),
  ('TK-XY-N', '04', 'Bunnelby', 'STANDARD', 'tk6b-4', 'normal'),
  ('TK-XY-N', '05', 'Psychic Energy', 'STANDARD', 'tk6b-5', 'normal'),
  ('TK-XY-N', '06', 'Psychic Energy', 'STANDARD', 'tk6b-6', 'normal'),
  ('TK-XY-N', '07', 'Psychic Energy', 'STANDARD', 'tk6b-7', 'normal'),
  ('TK-XY-N', '08', 'Psychic Energy', 'STANDARD', 'tk6b-8', 'normal'),
  ('TK-XY-N', '09', 'Psychic Energy', 'STANDARD', 'tk6b-9', 'normal'),
  ('TK-XY-N', '10', 'Psychic Energy', 'STANDARD', 'tk6b-10', 'normal'),
  ('TK-XY-N', '11', 'Pumpkaboo', 'STANDARD', 'tk6b-11', 'normal'),
  ('TK-XY-N', '12', 'Noibat', 'STANDARD', 'tk6b-12', 'normal'),
  ('TK-XY-N', '13', 'Noivern', 'STANDARD', 'tk6b-13', 'normal'),
  ('TK-XY-N', '14', 'Pokémon Catcher', 'STANDARD', 'tk6b-14', 'normal'),
  ('TK-XY-N', '15', 'Potion', 'STANDARD', 'tk6b-15', 'normal'),
  ('TK-XY-N', '16', 'Ekans', 'STANDARD', 'tk6b-16', 'normal'),
  ('TK-XY-N', '17', 'Psychic Energy', 'STANDARD', 'tk6b-17', 'normal'),
  ('TK-XY-N', '18', 'Pumpkaboo', 'STANDARD', 'tk6b-18', 'normal'),
  ('TK-XY-N', '19', 'Darkness Energy', 'STANDARD', 'tk6b-19', 'normal'),
  ('TK-XY-N', '20', 'Furfrou', 'STANDARD', 'tk6b-20', 'normal'),
  ('TK-XY-N', '21', 'Poké Ball', 'STANDARD', 'tk6b-21', 'normal'),
  ('TK-XY-N', '22', 'Darkness Energy', 'STANDARD', 'tk6b-22', 'normal'),
  ('TK-XY-N', '23', 'Noibat', 'STANDARD', 'tk6b-23', 'normal'),
  ('TK-XY-N', '24', 'Professor’s Letter', 'STANDARD', 'tk6b-24', 'normal'),
  ('TK-XY-N', '25', 'Psychic Energy', 'STANDARD', 'tk6b-25', 'normal'),
  ('TK-XY-N', '26', 'Darkness Energy', 'STANDARD', 'tk6b-26', 'normal'),
  ('TK-XY-N', '27', 'Potion', 'STANDARD', 'tk6b-27', 'normal'),
  ('TK-XY-N', '28', 'Darkness Energy', 'STANDARD', 'tk6b-28', 'normal'),
  ('TK-XY-N', '29', 'Switch', 'STANDARD', 'tk6b-29', 'normal'),
  ('TK-XY-N', '30', 'Noivern', 'HOLO', 'tk6b-30', 'holofoil'),
  ('TK-XY-P', '01', 'Glameow', 'STANDARD', 'tk9b-1', 'normal'),
  ('TK-XY-P', '02', 'Lightning Energy', 'STANDARD', 'tk9b-2', 'normal'),
  ('TK-XY-P', '03', 'Lightning Energy', 'STANDARD', 'tk9b-3', 'normal'),
  ('TK-XY-P', '04', 'Electivire', 'STANDARD', 'tk9b-4', 'normal'),
  ('TK-XY-P', '05', 'Lightning Energy', 'STANDARD', 'tk9b-5', 'normal'),
  ('TK-XY-P', '06', 'Lightning Energy', 'STANDARD', 'tk9b-6', 'normal'),
  ('TK-XY-P', '07', 'Taillow', 'STANDARD', 'tk9b-7', 'normal'),
  ('TK-XY-P', '08', 'Lightning Energy', 'STANDARD', 'tk9b-8', 'normal'),
  ('TK-XY-P', '09', 'Lightning Energy', 'STANDARD', 'tk9b-9', 'normal'),
  ('TK-XY-P', '10', 'Lightning Energy', 'STANDARD', 'tk9b-10', 'normal'),
  ('TK-XY-P', '11', 'Electrike', 'STANDARD', 'tk9b-11', 'normal'),
  ('TK-XY-P', '12', 'Blitzle', 'STANDARD', 'tk9b-12', 'normal'),
  ('TK-XY-P', '13', 'Manectric', 'STANDARD', 'tk9b-13', 'normal'),
  ('TK-XY-P', '14', 'Pikachu Libre', 'STANDARD', 'tk9b-14', 'normal'),
  ('TK-XY-P', '15', 'Electabuzz', 'STANDARD', 'tk9b-15', 'normal'),
  ('TK-XY-P', '16', 'Fletchling', 'STANDARD', 'tk9b-16', 'normal'),
  ('TK-XY-P', '17', 'Lightning Energy', 'STANDARD', 'tk9b-17', 'normal'),
  ('TK-XY-P', '18', 'Lightning Energy', 'STANDARD', 'tk9b-18', 'normal'),
  ('TK-XY-P', '19', 'Purugly', 'STANDARD', 'tk9b-19', 'normal'),
  ('TK-XY-P', '20', 'Tierno', 'STANDARD', 'tk9b-20', 'normal'),
  ('TK-XY-P', '21', 'Potion', 'STANDARD', 'tk9b-21', 'normal'),
  ('TK-XY-P', '22', 'Manectric', 'STANDARD', 'tk9b-22', 'normal'),
  ('TK-XY-P', '23', 'Electabuzz', 'STANDARD', 'tk9b-23', 'normal'),
  ('TK-XY-P', '24', 'Purugly', 'STANDARD', 'tk9b-24', 'normal'),
  ('TK-XY-P', '25', 'Electivire', 'STANDARD', 'tk9b-25', 'normal'),
  ('TK-XY-P', '26', 'Blitzle', 'STANDARD', 'tk9b-26', 'normal'),
  ('TK-XY-P', '27', 'Glameow', 'STANDARD', 'tk9b-27', 'normal'),
  ('TK-XY-P', '28', 'Electrike', 'STANDARD', 'tk9b-28', 'normal'),
  ('TK-XY-P', '29', 'Lightning Energy', 'STANDARD', 'tk9b-29', 'normal'),
  ('TK-XY-P', '30', 'Pikachu Libre', 'HOLO', 'tk9b-30', 'holofoil'),
  ('TK-XY-SU', '01', 'Water Energy', 'STANDARD', 'tk9a-1', 'normal'),
  ('TK-XY-SU', '02', 'Water Energy', 'STANDARD', 'tk9a-2', 'normal'),
  ('TK-XY-SU', '03', 'Water Energy', 'STANDARD', 'tk9a-3', 'normal'),
  ('TK-XY-SU', '04', 'Eevee', 'STANDARD', 'tk9a-4', 'normal'),
  ('TK-XY-SU', '05', 'Water Energy', 'STANDARD', 'tk9a-5', 'normal'),
  ('TK-XY-SU', '06', 'Frogadier', 'STANDARD', 'tk9a-6', 'normal'),
  ('TK-XY-SU', '07', 'Ducklett', 'STANDARD', 'tk9a-7', 'normal'),
  ('TK-XY-SU', '08', 'Water Energy', 'STANDARD', 'tk9a-8', 'normal'),
  ('TK-XY-SU', '09', 'Water Energy', 'STANDARD', 'tk9a-9', 'normal'),
  ('TK-XY-SU', '10', 'Water Energy', 'STANDARD', 'tk9a-10', 'normal'),
  ('TK-XY-SU', '11', 'Froakie', 'STANDARD', 'tk9a-11', 'normal'),
  ('TK-XY-SU', '12', 'Seaking', 'STANDARD', 'tk9a-12', 'normal'),
  ('TK-XY-SU', '13', 'Goldeen', 'STANDARD', 'tk9a-13', 'normal'),
  ('TK-XY-SU', '14', 'Suicune', 'STANDARD', 'tk9a-14', 'normal'),
  ('TK-XY-SU', '15', 'Potion', 'STANDARD', 'tk9a-15', 'normal'),
  ('TK-XY-SU', '16', 'Piplup', 'STANDARD', 'tk9a-16', 'normal'),
  ('TK-XY-SU', '17', 'Water Energy', 'STANDARD', 'tk9a-17', 'normal'),
  ('TK-XY-SU', '18', 'Swanna', 'STANDARD', 'tk9a-18', 'normal'),
  ('TK-XY-SU', '19', 'Water Energy', 'STANDARD', 'tk9a-19', 'normal'),
  ('TK-XY-SU', '20', 'Tierno', 'STANDARD', 'tk9a-20', 'normal'),
  ('TK-XY-SU', '21', 'Frogadier', 'STANDARD', 'tk9a-21', 'normal'),
  ('TK-XY-SU', '22', 'Water Energy', 'STANDARD', 'tk9a-22', 'normal'),
  ('TK-XY-SU', '23', 'Froakie', 'STANDARD', 'tk9a-23', 'normal'),
  ('TK-XY-SU', '24', 'Ducklett', 'STANDARD', 'tk9a-24', 'normal'),
  ('TK-XY-SU', '25', 'Seaking', 'STANDARD', 'tk9a-25', 'normal'),
  ('TK-XY-SU', '26', 'Goldeen', 'STANDARD', 'tk9a-26', 'normal'),
  ('TK-XY-SU', '27', 'Swanna', 'STANDARD', 'tk9a-27', 'normal'),
  ('TK-XY-SU', '28', 'Water Energy', 'STANDARD', 'tk9a-28', 'normal'),
  ('TK-XY-SU', '29', 'Tierno', 'STANDARD', 'tk9a-29', 'normal'),
  ('TK-XY-SU', '30', 'Suicune', 'HOLO', 'tk9a-30', 'holofoil'),
  ('TK-XY-SY', '01', 'Fletchling', 'STANDARD', 'tk6a-1', 'normal'),
  ('TK-XY-SY', '02', 'Fairy Energy', 'STANDARD', 'tk6a-2', 'normal'),
  ('TK-XY-SY', '03', 'Fairy Energy', 'STANDARD', 'tk6a-3', 'normal'),
  ('TK-XY-SY', '04', 'Switch', 'STANDARD', 'tk6a-4', 'normal'),
  ('TK-XY-SY', '05', 'Fairy Energy', 'STANDARD', 'tk6a-5', 'normal'),
  ('TK-XY-SY', '06', 'Fairy Energy', 'STANDARD', 'tk6a-6', 'normal'),
  ('TK-XY-SY', '07', 'Fairy Energy', 'STANDARD', 'tk6a-7', 'normal'),
  ('TK-XY-SY', '08', 'Fairy Energy', 'STANDARD', 'tk6a-8', 'normal'),
  ('TK-XY-SY', '09', 'Fairy Energy', 'STANDARD', 'tk6a-9', 'normal'),
  ('TK-XY-SY', '10', 'Fairy Energy', 'STANDARD', 'tk6a-10', 'normal'),
  ('TK-XY-SY', '11', 'Snubbull', 'STANDARD', 'tk6a-11', 'normal'),
  ('TK-XY-SY', '12', 'Fairy Energy', 'STANDARD', 'tk6a-12', 'normal'),
  ('TK-XY-SY', '13', 'Eevee', 'STANDARD', 'tk6a-13', 'normal'),
  ('TK-XY-SY', '14', 'Granbull', 'STANDARD', 'tk6a-14', 'normal'),
  ('TK-XY-SY', '15', 'Sylveon', 'STANDARD', 'tk6a-15', 'normal'),
  ('TK-XY-SY', '16', 'Furfrou', 'STANDARD', 'tk6a-16', 'normal'),
  ('TK-XY-SY', '17', 'Fairy Energy', 'STANDARD', 'tk6a-17', 'normal'),
  ('TK-XY-SY', '18', 'Fairy Energy', 'STANDARD', 'tk6a-18', 'normal'),
  ('TK-XY-SY', '19', 'Fletchling', 'STANDARD', 'tk6a-19', 'normal'),
  ('TK-XY-SY', '20', 'Potion', 'STANDARD', 'tk6a-20', 'normal'),
  ('TK-XY-SY', '21', 'Eevee', 'STANDARD', 'tk6a-21', 'normal'),
  ('TK-XY-SY', '22', 'Furfrou', 'STANDARD', 'tk6a-22', 'normal'),
  ('TK-XY-SY', '23', 'Pokémon Catcher', 'STANDARD', 'tk6a-23', 'normal'),
  ('TK-XY-SY', '24', 'Potion', 'STANDARD', 'tk6a-24', 'normal'),
  ('TK-XY-SY', '25', 'Fairy Energy', 'STANDARD', 'tk6a-25', 'normal'),
  ('TK-XY-SY', '26', 'Poké Ball', 'STANDARD', 'tk6a-26', 'normal'),
  ('TK-XY-SY', '27', 'Snubbull', 'STANDARD', 'tk6a-27', 'normal'),
  ('TK-XY-SY', '28', 'Professor’s Letter', 'STANDARD', 'tk6a-28', 'normal'),
  ('TK-XY-SY', '29', 'Granbull', 'STANDARD', 'tk6a-29', 'normal'),
  ('TK-XY-SY', '30', 'Sylveon', 'HOLO', 'tk6a-30', 'holofoil'),
  ('TK-XY-W', '01', 'Swirlix', 'STANDARD', 'tk7a-1', 'normal'),
  ('TK-XY-W', '02', 'Pidgeotto', 'STANDARD', 'tk7a-2', 'normal'),
  ('TK-XY-W', '03', 'Fairy Energy', 'STANDARD', 'tk7a-3', 'normal'),
  ('TK-XY-W', '04', 'Sentret', 'STANDARD', 'tk7a-4', 'normal'),
  ('TK-XY-W', '05', 'Fairy Energy', 'STANDARD', 'tk7a-5', 'normal'),
  ('TK-XY-W', '06', 'Fairy Energy', 'STANDARD', 'tk7a-6', 'normal'),
  ('TK-XY-W', '07', 'Fairy Energy', 'STANDARD', 'tk7a-7', 'normal'),
  ('TK-XY-W', '08', 'Fairy Energy', 'STANDARD', 'tk7a-8', 'normal'),
  ('TK-XY-W', '09', 'Fairy Energy', 'STANDARD', 'tk7a-9', 'normal'),
  ('TK-XY-W', '10', 'Fairy Energy', 'STANDARD', 'tk7a-10', 'normal'),
  ('TK-XY-W', '11', 'Pidgey', 'STANDARD', 'tk7a-11', 'normal'),
  ('TK-XY-W', '12', 'Jigglypuff', 'STANDARD', 'tk7a-12', 'normal'),
  ('TK-XY-W', '13', 'Clefairy', 'STANDARD', 'tk7a-13', 'normal'),
  ('TK-XY-W', '14', 'Wigglytuff', 'STANDARD', 'tk7a-14', 'normal'),
  ('TK-XY-W', '15', 'Potion', 'STANDARD', 'tk7a-15', 'normal'),
  ('TK-XY-W', '16', 'Clefable', 'STANDARD', 'tk7a-16', 'normal'),
  ('TK-XY-W', '17', 'Fairy Energy', 'STANDARD', 'tk7a-17', 'normal'),
  ('TK-XY-W', '18', 'Swirlix', 'STANDARD', 'tk7a-18', 'normal'),
  ('TK-XY-W', '19', 'Clefairy', 'STANDARD', 'tk7a-19', 'normal'),
  ('TK-XY-W', '20', 'Potion', 'STANDARD', 'tk7a-20', 'normal'),
  ('TK-XY-W', '21', 'Fairy Energy', 'STANDARD', 'tk7a-21', 'normal'),
  ('TK-XY-W', '22', 'Fairy Energy', 'STANDARD', 'tk7a-22', 'normal'),
  ('TK-XY-W', '23', 'Pidgeotto', 'STANDARD', 'tk7a-23', 'normal'),
  ('TK-XY-W', '24', 'Trevor', 'STANDARD', 'tk7a-24', 'normal'),
  ('TK-XY-W', '25', 'Jigglypuff', 'STANDARD', 'tk7a-25', 'normal'),
  ('TK-XY-W', '26', 'Tierno', 'STANDARD', 'tk7a-26', 'normal'),
  ('TK-XY-W', '27', 'Fairy Energy', 'STANDARD', 'tk7a-27', 'normal'),
  ('TK-XY-W', '28', 'Clefable', 'STANDARD', 'tk7a-28', 'normal'),
  ('TK-XY-W', '29', 'Pidgey', 'STANDARD', 'tk7a-29', 'normal'),
  ('TK-XY-W', '30', 'Wigglytuff', 'HOLO', 'tk7a-30', 'holofoil'),
  ('CEL25CC', 'CC001', 'Blastoise', 'HOLO', 'cel25c-2_A', 'holofoil'),
  ('CEL25CC', 'CC002', 'Charizard', 'HOLO', 'cel25c-4_A', 'holofoil'),
  ('CEL25CC', 'CC003', 'Venusaur', 'HOLO', 'cel25c-15_A1', 'holofoil'),
  ('CEL25CC', 'CC004', 'Imposter Professor Oak', 'HOLO', 'cel25c-73_A', 'holofoil'),
  ('CEL25CC', 'CC005', 'Dark Gyarados', 'HOLO', 'cel25c-8_A', 'holofoil'),
  ('CEL25CC', 'CC006', 'Here Comes Team Rocket!', 'HOLO', 'cel25c-15_A2', 'holofoil'),
  ('CEL25CC', 'CC007', 'Rocket''s Zapdos', 'HOLO', 'cel25c-15_A3', 'holofoil'),
  ('CEL25CC', 'CC008', '_____''s Pikachu', 'HOLO', 'cel25c-24_A', 'holofoil'),
  ('CEL25CC', 'CC009', 'Cleffa', 'HOLO', 'cel25c-20_A', 'holofoil'),
  ('CEL25CC', 'CC010', 'Shining Magikarp', 'HOLO', 'cel25c-66_A', 'holofoil'),
  ('CEL25CC', 'CC011', 'Team Magma''s Groudon', 'HOLO', 'cel25c-9_A', 'holofoil'),
  ('CEL25CC', 'CC012', 'Rocket''s Admin.', 'HOLO', 'cel25c-86_A', 'holofoil'),
  ('CEL25CC', 'CC013', 'Mew ex', 'HOLO', 'cel25c-88_A', 'holofoil'),
  ('CEL25CC', 'CC014', 'Gardevoir ex', 'HOLO', 'cel25c-93_A', 'holofoil'),
  ('CEL25CC', 'CC015', 'Umbreon ☆', 'HOLO', 'cel25c-17_A', 'holofoil'),
  ('CEL25CC', 'CC016', 'Claydol', 'HOLO', 'cel25c-15_A4', 'holofoil'),
  ('CEL25CC', 'CC017', 'Luxray GL LV.X', 'HOLO', 'cel25c-109_A', 'holofoil'),
  ('CEL25CC', 'CC018', 'Garchomp C LV.X', 'HOLO', 'cel25c-145_A', 'holofoil'),
  ('CEL25CC', 'CC019', 'Donphan', 'HOLO', 'cel25c-107_A', 'holofoil'),
  ('CEL25CC', 'CC020', 'Reshiram', 'HOLO', 'cel25c-113_A', 'holofoil'),
  ('CEL25CC', 'CC021', 'Zekrom', 'HOLO', 'cel25c-114_A', 'holofoil'),
  ('CEL25CC', 'CC022', 'Mewtwo EX', 'HOLO', 'cel25c-54_A', 'holofoil'),
  ('CEL25CC', 'CC023', 'Xerneas EX', 'HOLO', 'cel25c-97_A', 'holofoil'),
  ('CEL25CC', 'CC024', 'M Rayquaza EX', 'HOLO', 'cel25c-76_A', 'holofoil'),
  ('CEL25CC', 'CC025', 'Tapu Lele GX', 'HOLO', 'cel25c-60_A', 'holofoil');

  -- G1: carta única, ativa, com o nome esperado
  SELECT string_agg(t.set_code||' '||t.num, ', ') INTO v_bad
    FROM t2257 t
   WHERE (SELECT count(*) FROM public.card c JOIN public.card_set cs ON cs.id = c.card_set_id
           WHERE cs.code = t.set_code AND c.collector_number = t.num AND c.is_active AND c.name = t.expected_name) <> 1;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '2257_G1_CARD_MISMATCH: %', v_bad; END IF;

  -- G2: nenhuma tem variante
  SELECT string_agg(t.set_code||' '||t.num, ', ') INTO v_bad
    FROM t2257 t JOIN public.card_set cs ON cs.code = t.set_code
    JOIN public.card c ON c.card_set_id = cs.id AND c.collector_number = t.num AND c.is_active
   WHERE EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id);
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '2257_G2_ALREADY_HAS_VARIANT: %', v_bad; END IF;

  INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default)
  SELECT c.id, CASE t.vt WHEN 'HOLO' THEN v_holo ELSE v_std END, 1, false
    FROM t2257 t JOIN public.card_set cs ON cs.code = t.set_code
    JOIN public.card c ON c.card_set_id = cs.id AND c.collector_number = t.num AND c.is_active;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 295 THEN RAISE EXCEPTION '2257_P1_INSERTED: %', v_n; END IF;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  SELECT v_actor, 'CARD_SET_UPDATED', 'CARD_SET', cs.id,
         jsonb_build_object('operation', 'BOOTSTRAP-03-CLOSEOUT-2257', 'change', 'card_variant_created',
           'variants', count(*), 'standard', count(*) FILTER (WHERE t.vt = 'STANDARD'), 'holo', count(*) FILTER (WHERE t.vt = 'HOLO'),
           'source', CASE WHEN t.set_code = 'CEL25CC' THEN 'POKEMON_TCG_API snapshot 2026-10-09 (cel25c), tabela CC curada'
                          ELSE 'Scrydex (página da expansão, variante por carta)' END)
    FROM t2257 t JOIN public.card_set cs ON cs.code = t.set_code
   GROUP BY cs.id, t.set_code;

  SELECT count(*) INTO v_n FROM public.card c
   WHERE c.is_active AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id);
  IF v_n <> 0 THEN RAISE EXCEPTION '2257_P1_STILL_WITHOUT_VARIANT: %', v_n; END IF;
  RAISE NOTICE '2257_OK';
END;
$mig$;
