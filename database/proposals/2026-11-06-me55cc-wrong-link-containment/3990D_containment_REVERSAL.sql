/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3990D - ME5.5CC WRONG LINK CONTAINMENT-01 — REVERSÃO (só se a 3990C precisar ser desfeita)
Status......: PROPOSTO — NÃO EXECUTADO. Uso excepcional, com autorização explícita.
Data........: 2026-11-06

Objetivo
  Devolver os 5 vínculos ao estado exato anterior à 3990C: REJECTED -> CONFIRMED, com a autoria
  automática original (confirmed_sync_run_id guardado em match_evidence.containment_3990),
  confirmed_by nulo e confirmed_at preservado pelo trigger. Remove só a chave containment_3990 da
  evidência. Os registros de auditoria da 3990C permanecem; um novo registro documenta a reversão.

Pré-condições
  Os 5 vínculos estão REJECTED com a chave containment_3990 e o run original válido.
Resultado esperado
  5 CONFIRMED; a 3989 volta a devolver os valores da linha de base (3990A, parte B).
================================================================
*/
begin;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

do $$
declare
  v_admin uuid;
  v_n integer;
  v_ids constant uuid[] := array[
    '63ad9941-d8b2-495f-9260-5fc92f38bceb', '1d3f88ea-3706-4763-90aa-70c8c20f668f', '61c330ab-dd73-4d4c-99e0-1c3ab0af8bbe',
    'bb3044be-7e6e-4e59-a2f1-98ef938e2740', '001152c1-b86c-4957-86a0-345fd09f0f4c']::uuid[];
begin
  select id into v_admin from public.admin_user;

  select count(*) into v_n from public.pricing_card_mapping m
  join public.pricing_sync_run r on r.id = (m.match_evidence -> 'containment_3990' ->> 'previous_confirmed_sync_run_id')::uuid
  where m.id = any (v_ids) and m.match_status = 'REJECTED' and m.match_evidence ? 'containment_3990';
  if v_n <> 5 then raise exception 'Q3990D_PRE_STATE: % de 5 vínculos reversíveis', v_n; end if;

  update public.pricing_card_mapping m set
    match_status = 'CONFIRMED',
    confirmed_by = null,
    confirmed_sync_run_id = (m.match_evidence -> 'containment_3990' ->> 'previous_confirmed_sync_run_id')::uuid,
    match_method = m.match_evidence -> 'containment_3990' ->> 'previous_match_method',
    match_evidence = m.match_evidence - 'containment_3990'
  where m.id = any (v_ids) and m.match_status = 'REJECTED';
  get diagnostics v_n = row_count;
  if v_n <> 5 then raise exception 'Q3990D_ROWCOUNT: % de 5', v_n; end if;

  insert into public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  select v_admin, 'PRICING_MAPPING_CONFIRMED', 'PRICING_CARD_MAPPING', id,
         jsonb_build_object('old_status', 'REJECTED', 'new_status', 'CONFIRMED', 'query', '3990D', 'reason', 'Reversão da contenção 3990.')
  from unnest(v_ids) as id;

  select count(*) into v_n from public.pricing_card_mapping
  where id = any (v_ids) and match_status = 'CONFIRMED' and confirmed_by is null and confirmed_sync_run_id is not null
    and not (match_evidence ? 'containment_3990');
  if v_n <> 5 then raise exception 'Q3990D_POST_STATE: % de 5', v_n; end if;
end $$;

commit;
