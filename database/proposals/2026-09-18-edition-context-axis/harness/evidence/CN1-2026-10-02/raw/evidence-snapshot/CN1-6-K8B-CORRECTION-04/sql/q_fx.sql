select 'FX|' || ((select count(*) from public.game where id = 'c16b8b00-0000-4000-8000-000000000001')
  + (select count(*) from public.expansion where id = 'c16b8b00-0000-4000-8000-000000000002')
  + (select count(*) from public.card_set where id = 'c16b8b00-0000-4000-8000-000000000003')
  + (select count(*) from public.rarity where id = 'c16b8b00-0000-4000-8000-000000000004')
  + (select count(*) from public.card_category where id = 'c16b8b00-0000-4000-8000-000000000005')
  + (select count(*) from public.card_variant_type where id = 'c16b8b00-0000-4000-8000-000000000011')
  + (select count(*) from public.card where id in ('c16b8b00-0000-4000-8000-000000000021', 'c16b8b00-0000-4000-8000-000000000022'))
  + (select count(*) from public.catalog_variant_import_job where id = 'c16b8b00-0000-4000-8000-000000000031')
  + (select count(*) from public.catalog_variant_import_row where id in ('c16b8b00-0000-4000-8000-000000000041', 'c16b8b00-0000-4000-8000-000000000042')))::text;