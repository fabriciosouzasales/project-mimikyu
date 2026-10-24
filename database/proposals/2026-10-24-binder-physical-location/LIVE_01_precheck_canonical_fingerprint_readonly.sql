-- BINDER-PHYSICAL-LOCATION — LIVE_01: precheck SÓ LEITURA — o LIVE executa exatamente os corpos
-- canônicos que as migrations substituem e que R1/R2A/R2B restauram (mimikyu-core).
-- Status: PROPOSTO — NÃO EXECUTADO. Rodar junto com o LIVE_00, antes da fase A; qualquer FAIL = STOP.
-- Por quê: sem execução prévia em ambiente isolado, a fidelidade da recuperação depende de o LIVE
-- ser idêntico a database/schema/. Os md5 abaixo são do corpo ($$…$$) do arquivo canônico indicado,
-- calculados em LIVE-READINESS-01; pg_proc.prosrc guarda o corpo literal enviado na criação.
-- Somente SELECT em catálogo; nenhum dado de usuário é lido.
with expected(fn, args, canon, md5) as (values
  ('get_my_collection_binder',                             'uuid',                              '5230', '0c5c9d91f32c634d094b178ff62655f3'),
  ('get_my_collection_binder_pages',                       'uuid, integer, integer',            '5230', '61c67d8c71ca2559d2746eaeffa37e94'),
  ('get_my_collection_binder_unplaced',                    'uuid, integer, integer',            '5230', '47c15e9ab57921c59aa693ffaef3daf6'),
  ('list_my_binder_join_candidates',                       'uuid',                              '5230', '651dcd371f44a97541d6bca950fdf6e4'),
  ('get_my_binder_participants',                           'uuid',                              '5246', '5cb91322b3210bbeeb50e9316370ce93'),
  ('collection_binder_plan',                               'uuid, integer, integer, text',      '5224', 'e98b559818bb9ce37185d43664e34c93'),
  ('attach_my_collection_to_binder',                       'uuid, uuid',                        '5229', '395d02acd444c919336b322e72e5a94b'),
  ('detach_my_collection_from_binder',                     'uuid, text, boolean',               '5229', 'f9eabbb4711570f2c4ea8ab6a2e4bea8'),
  ('collection_binder_detach_snapshot',                    'uuid',                              '5229', '31824bb6b68563794dff5815aac61188'),
  ('assign_card_to_slot',                                  'uuid, uuid',                        '5229', 'a3408505636c1962ecfbc06793a3448c'),
  ('enforce_collection_layout_slot_assignment_integrity',  '',                                  '5229', 'd66e488401aec3b995ca7acfd95f317e'),
  ('enforce_collection_layout_slot_lock',                  '',                                  '5118', '3b6a5b77f9be78eee700e1f845674728'),
  ('enforce_collection_layout_structural_fk_immutability', '',                                  '5136', '3b43591c3494fab605c5be449c5f8827'),
  ('set_physical_cards_storage',                           'uuid, uuid[]',                      '5024', 'cf8d15bcbd1f0842541bfac99be3eb72'),
  ('organize_my_collection_storage',                       'uuid, uuid, text, integer, text',   '5222', '595e5229051e4dc6e16a1c9e484a6e9b')
)
select e.fn, e.args, e.canon,
       p.oid is not null                         as present,
       md5(p.prosrc) = e.md5                     as body_matches_canonical,
       p.prosecdef                               as security_definer,
       coalesce(p.proconfig @> array['search_path=""'], false) as search_path_empty
from expected e
left join pg_proc p
  on p.pronamespace = 'public'::regnamespace
 and p.proname = e.fn
 and coalesce((select string_agg(format_type(t, null), ', ' order by o)
               from unnest(p.proargtypes) with ordinality as a(t, o)), '') = e.args
order by e.canon, e.fn;

-- Resumo (deve retornar l01_all_canonical = true):
with expected(fn, args, md5) as (values
  ('get_my_collection_binder','uuid','0c5c9d91f32c634d094b178ff62655f3'),
  ('get_my_collection_binder_pages','uuid, integer, integer','61c67d8c71ca2559d2746eaeffa37e94'),
  ('get_my_collection_binder_unplaced','uuid, integer, integer','47c15e9ab57921c59aa693ffaef3daf6'),
  ('list_my_binder_join_candidates','uuid','651dcd371f44a97541d6bca950fdf6e4'),
  ('get_my_binder_participants','uuid','5cb91322b3210bbeeb50e9316370ce93'),
  ('collection_binder_plan','uuid, integer, integer, text','e98b559818bb9ce37185d43664e34c93'),
  ('attach_my_collection_to_binder','uuid, uuid','395d02acd444c919336b322e72e5a94b'),
  ('detach_my_collection_from_binder','uuid, text, boolean','f9eabbb4711570f2c4ea8ab6a2e4bea8'),
  ('collection_binder_detach_snapshot','uuid','31824bb6b68563794dff5815aac61188'),
  ('assign_card_to_slot','uuid, uuid','a3408505636c1962ecfbc06793a3448c'),
  ('enforce_collection_layout_slot_assignment_integrity','','d66e488401aec3b995ca7acfd95f317e'),
  ('enforce_collection_layout_slot_lock','','3b6a5b77f9be78eee700e1f845674728'),
  ('enforce_collection_layout_structural_fk_immutability','','3b43591c3494fab605c5be449c5f8827'),
  ('set_physical_cards_storage','uuid, uuid[]','cf8d15bcbd1f0842541bfac99be3eb72'),
  ('organize_my_collection_storage','uuid, uuid, text, integer, text','595e5229051e4dc6e16a1c9e484a6e9b')
)
select bool_and(exists (
         select 1 from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = e.fn
           and coalesce((select string_agg(format_type(t, null), ', ' order by o)
                         from unnest(p.proargtypes) with ordinality as a(t, o)), '') = e.args
           and md5(p.prosrc) = e.md5)) as l01_all_canonical,
       count(*) as l01_functions_checked
from expected e;
