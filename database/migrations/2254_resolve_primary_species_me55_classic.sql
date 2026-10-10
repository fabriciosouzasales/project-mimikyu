/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2254 - Primary Species das cartas ME5.5 e ME5.5CC (Pokédex)
Status......: CONFIRMADO EXECUTADO (2026-10-10; dry-run PASS antes)
Origem......: database/proposals/2026-10-10-me55-30th-celebration/README.md

Problema
  A API da TCGdex ainda não publica dexId para 30th / 30th-c, então o fluxo
  automático (resolve_card_primary_species_for_catalog_import_job) resolveu 0
  das 183 cartas Pokémon. Sem Primary Species elas ficam fora do módulo
  Pokédex/Collection.

Evidência
  ME5.5   : pokemontcg.io cards/en/me55.json (nationalPokedexNumbers), número a
            número; nome conferido contra o catálogo (gate).
  ME5.5CC : pokemontcg.io cards/en/me55c.json + repositório tcgdex/cards-database
            (30th Classic Collection/*.ts, dexId) — Erika's Jigglypuff = 39 vem
            só da TCGdex (pokemontcg classifica como Trainer).
  Gravação pelo writer editorial admin_resolve_card_primary_species()
  (resolution_basis EDITORIAL_RECONCILIATION, catalog_admin_action_log),
  porque resolve_card_primary_species_bulk() rotula a evidência como TCGDEX.

Fora (decisão editorial pendente — mais de um Pokémon na carta)
  ME5.5CC 008 Pikachu & Zekrom GX [25, 644]; 019 e 020 Darkrai & Cresselia
  LEGEND [491, 488]. Mesma regra do fluxo automático: dexId múltiplo nunca é
  escolhido sozinho.
===============================================================================
*/
DO $p$
DECLARE
  v_apply CONSTANT boolean := true;
  v_me55 jsonb := '[["001","102","Exeggcute"],["002","103","Alolan Exeggutor"],["003","313","Volbeat"],["004","314","Illumise"],["005","357","Tropius"],["006","420","Cherubi"],["007","421","Cherrim"],["008","666","Vivillon"],["009","37","Vulpix"],["010","38","Ninetales"],["011","146","Moltres"],["012","250","Ho-Oh"],["013","494","Victini"],["014","643","Reshiram"],["015","909","Fuecoco ex"],["016","79","Slowpoke"],["017","131","Lapras"],["018","144","Articuno"],["019","382","Kyogre"],["020","484","Palkia"],["021","658","Greninja ex"],["022","746","Wishiwashi"],["053","25","Pikachu ex"],["054","25","Pikachu ex"],["055","145","Zapdos"],["056","644","Zekrom"],["057","807","Zeraora"],["058","848","Toxel"],["059","849","Toxtricity"],["060","849","Toxtricity"],["061","877","Morpeko"],["062","1008","Miraidon"],["063","150","Mewtwo"],["064","150","Mewtwo ex"],["065","151","Mew"],["066","151","Mew ex"],["067","183","Marill"],["068","184","Azumarill"],["069","196","Espeon"],["070","196","Espeon ex"],["071","700","Sylveon ex"],["072","201","Unown"],["073","425","Drifloon"],["074","488","Cresselia"],["075","609","Chandelure"],["076","716","Xerneas"],["077","764","Comfey"],["078","789","Cosmog"],["079","790","Cosmoem"],["080","792","Lunala"],["081","999","Gimmighoul"],["082","383","Groudon"],["083","448","Lucario"],["084","537","Seismitoad"],["085","745","Lycanroc"],["086","1007","Koraidon"],["087","29","Nidoran ♀"],["088","30","Nidorina"],["089","52","Alolan Meowth"],["090","94","Gengar ex"],["091","197","Umbreon"],["092","197","Umbreon ex"],["093","198","Murkrow"],["094","559","Scraggy"],["095","570","Zorua"],["096","571","Zoroark"],["097","633","Deino"],["098","634","Zweilous"],["099","635","Hydreigon"],["100","717","Yveltal"],["101","52","Galarian Meowth"],["102","385","Jirachi ex"],["103","483","Dialga"],["104","598","Ferrothorn"],["105","791","Solgaleo"],["106","888","Zacian"],["107","889","Zamazenta"],["108","1000","Gholdengo"],["109","373","Salamence ex"],["110","782","Jangmo-o"],["111","783","Hakamo-o"],["112","784","Kommo-o"],["113","52","Meowth"],["114","115","Kangaskhan"],["115","132","Ditto"],["116","133","Eevee"],["117","133","Eevee"],["118","133","Eevee"],["119","143","Snorlax"],["120","174","Igglybuff"],["121","249","Lugia"],["122","570","Hisuian Zorua"],["123","571","Hisuian Zoroark"],["124","774","Minior"],["125","925","Maushold"],["129","103","Alolan Exeggutor"],["130","146","Moltres"],["131","131","Lapras"],["132","144","Articuno"],["133","145","Zapdos"],["134","849","Toxtricity"],["135","877","Morpeko"],["136","425","Drifloon"],["137","609","Chandelure"],["138","745","Lycanroc"],["139","52","Alolan Meowth"],["140","559","Scraggy"],["141","52","Galarian Meowth"],["142","1000","Gholdengo"],["143","784","Kommo-o"],["144","52","Meowth"],["145","570","Hisuian Zorua"],["146","925","Maushold"],["147","909","Fuecoco ex"],["148","658","Greninja ex"],["149","25","Pikachu ex"],["150","25","Pikachu ex"],["151","150","Mewtwo ex"],["152","151","Mew ex"],["153","700","Sylveon ex"],["154","94","Gengar ex"],["155","385","Jirachi ex"],["156","373","Salamence ex"],["157","150","Mewtwo ex"],["158","151","Mew ex"]]';
  v_cc jsonb := '[["001","6","Charizard","me55c-4"],["002","301","Delcatty","me55c-5"],["003","376","Metagross","me55c-11"],["004","649","Genesect","me55c-11g"],["006","248","Tyranitar","me55c-19"],["007","215","Sneasel","me55c-25"],["009","658","Greninja","me55c-41"],["010","480","Uxie","me55c-43"],["011","169","Crobat","me55c-47"],["012","243","Raikou","me55c-50"],["013","794","Buzzwole","me55c-57"],["014","25","Pikachu","me55c-58"],["015","39","Jigglypuff","30th-c-015"],["016","384","Rayquaza","me55c-85"],["017","791","Solgaleo","me55c-89"],["018","94","Gengar","me55c-94"],["022","484","Palkia","me55c-106p"],["023","282","Gardevoir","me55c-106m"],["024","251","Celebi","me55c-106"],["025","212","Scizor","me55c-108"],["026","151","Mew","me55c-114"],["027","493","Arceus","me55c-123"],["028","888","Zacian","me55c-138"],["029","249","Lugia","me55c-149"],["030","129","Magikarp","me55c-203"]]';
  r record; v_n int; v_ok int := 0; v_species uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub','fe316458-49dd-44e1-aac0-f4b7604ef8f2','role','authenticated')::text, true);
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;

  -- ME5.5: 23..52 são 30 Pikachu (dex 25)
  SELECT v_me55 || jsonb_agg(jsonb_build_array(lpad(g::text,3,'0'),'25','Pikachu')) INTO v_me55 FROM generate_series(23,52) g;

  CREATE TEMP TABLE p2254 ON COMMIT DROP AS
  SELECT 'ME5.5'::text set_code, e->>0 num, (e->>1)::int dex, e->>2 sname, 'me55-'||ltrim(e->>0,'0') ext, 'POKEMON_TCG_API cards/en/me55.json'::text src
    FROM jsonb_array_elements(v_me55) e
  UNION ALL
  SELECT 'ME5.5CC', e->>0, (e->>1)::int, e->>2, e->>3,
         CASE WHEN e->>3 LIKE '30th-c-%' THEN 'TCGDEX repo 30th Classic Collection (API sem dexId)' ELSE 'POKEMON_TCG_API cards/en/me55c.json + TCGDEX repo' END
    FROM jsonb_array_elements(v_cc) e;

  ALTER TABLE p2254 ADD COLUMN card_id uuid, ADD COLUMN cname text, ADD COLUMN species_id uuid;
  UPDATE p2254 p SET card_id = c.id, cname = c.name
    FROM public.card c JOIN public.card_set s ON s.id = c.card_set_id
   WHERE s.code = p.set_code AND c.collector_number = p.num AND c.is_active;
  UPDATE p2254 p SET species_id = ps.id FROM public.pokemon_species ps WHERE ps.national_dex_number = p.dex;

  -- G1: todas as linhas acham carta e espécie
  SELECT count(*) INTO v_n FROM p2254 WHERE card_id IS NULL OR species_id IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION 'G1_SEM_CARTA_OU_ESPECIE: %', (SELECT string_agg(set_code||' '||num, ', ') FROM p2254 WHERE card_id IS NULL OR species_id IS NULL); END IF;
  -- G2: nome confere (ME5.5 igual ao da fonte, exceto 001/002 já em pt; CC contém o nome-chave)
  SELECT count(*) INTO v_n FROM p2254
   WHERE (set_code = 'ME5.5' AND num NOT IN ('001','002') AND replace(lower(cname),' ','') <> replace(lower(sname),' ',''))
      OR (set_code = 'ME5.5CC' AND position(lower(sname) in lower(cname)) = 0);
  IF v_n <> 0 THEN RAISE EXCEPTION 'G2_NOME_DIVERGENTE: %', (SELECT string_agg(set_code||' '||num||' '||cname||'<>'||sname, '; ') FROM p2254
   WHERE (set_code = 'ME5.5' AND num NOT IN ('001','002') AND replace(lower(cname),' ','') <> replace(lower(sname),' ','')) OR (set_code = 'ME5.5CC' AND position(lower(sname) in lower(cname)) = 0)); END IF;
  -- G3: cobertura = todas as Pokémon dos dois Sets, menos as 3 multi-Pokémon
  SELECT count(*) INTO v_n FROM public.card c JOIN public.card_set s ON s.id=c.card_set_id JOIN public.card_category cc ON cc.id=c.category_id
   WHERE s.code IN ('ME5.5','ME5.5CC') AND cc.code='POKEMON' AND c.is_active
     AND c.id NOT IN (SELECT card_id FROM p2254)
     AND NOT (s.code='ME5.5CC' AND c.collector_number IN ('008','019','020'));
  IF v_n <> 0 THEN RAISE EXCEPTION 'G3_POKEMON_FORA_DO_PLANO: %', v_n; END IF;

  FOR r IN SELECT * FROM p2254 ORDER BY set_code, num LOOP
    PERFORM public.admin_resolve_card_primary_species(r.card_id, r.species_id, jsonb_build_object(
      'source', CASE WHEN r.ext LIKE '30th-c-%' THEN 'TCGDEX' ELSE 'POKEMON_TCG_API' END,
      'external_card_id', r.ext, 'national_dex_numbers', jsonb_build_array(r.dex),
      'evidence', r.src, 'operation', '2254', 'observed_at', now()));
    v_ok := v_ok + 1;
  END LOOP;

  IF NOT v_apply THEN RAISE EXCEPTION 'DRYRUN_OK resolvidas %', v_ok; END IF;
  RAISE NOTICE 'APPLY_OK resolvidas %', v_ok;
END $p$;
