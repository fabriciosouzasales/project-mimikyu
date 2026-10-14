-- Pokédex P3e · Lote 01 — snapshot da base factual (SOMENTE LEITURA)
--
-- Objetivo: congelar, por espécie do lote, a versão e o md5 da descrição oficial (FLAVOR) e
-- da classificação (GENUS) SOURCE en usadas como base factual, e confirmar 0 linhas editoriais.
-- Uso: executar no LIVE, salvar o array "species" como source-snapshot-AAAA-MM-DD.json e passar
-- ao validador com --snapshot. Divergência de md5 = a fonte mudou desde a redação → revisar.
-- Resultado esperado: 50 objetos, editorial_rows = 0 até a publicação do lote.

select json_agg(x order by x.national_dex_number) as species from (
  select s.national_dex_number,
         s.canonical_name as species_name,
         max(t.source_version) filter (where t.text_kind = 'FLAVOR') as flavor_version,
         max(md5(t.content))   filter (where t.text_kind = 'FLAVOR') as flavor_md5,
         max(md5(t.content))   filter (where t.text_kind = 'GENUS')  as genus_md5,
         (select count(*) from public.pokemon_species_text e
           where e.pokemon_species_id = s.id and e.origin = 'MMKYU_EDITORIAL') as editorial_rows
    from public.pokemon_species s
    join public.pokemon_species_text t
      on t.pokemon_species_id = s.id and t.origin = 'SOURCE' and t.language_code = 'en'
   where s.national_dex_number = any (array[
     4, 6, 7, 39, 52, 54, 94, 133, 143, 151, 155, 175, 197, 212, 248, 249, 257, 282, 359, 382,
     384, 385, 393, 405, 445, 448, 483, 491, 494, 495, 530, 609, 643, 658, 681, 700, 701, 716,
     722, 745, 778, 791, 823, 873, 887, 888, 908, 959, 998, 1000])
   group by s.id, s.national_dex_number, s.canonical_name
) x;
