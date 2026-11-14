/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5365 - Reversão da 5365: devolve EXECUTE a authenticated
Versão......: 1.1 (2026-11-13, `PR-04A | LEGACY EXECUTE HARDENING CORRECTION-01`:
              D2 comparações NULL-seguras; D4 pg_catalog.; D5 cabeçalho)
Status......: PROPOSTA — NÃO EXECUTADA. Uso só por decisão expressa do
              proprietário (consumidor legítimo descoberto após a 5365).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-13
Escopo......: Só GRANT EXECUTE a authenticated nas três assinaturas da
              5365, restaurando a ACL comprovada antes dela
              ({postgres=X/postgres,authenticated=X/postgres}). Sem DROP,
              sem mudança de corpo, sem tocar nas vigentes. Um único DO.
Idempotência: ACL já restaurada nas três → 'PRECHECK R5365: NADA A
              DESFAZER'. Outro estado (inclusive ACL nula ou permissão
              concedida depois da 5365) → 'ESTADO DIVERGENTE'; nada muda.
Executor....: o dono (`postgres`) ou superusuário (GRANT registrado como
              do dono: authenticated=X/postgres).
Resultado esperado: NOTICE 'R5365 OK: EXECUTE de authenticated restaurado
              nas 3 legadas'; ACL das 3 de volta a
              {postgres=X/postgres,authenticated=X/postgres}.
Como validar: 5365_STATE_readonly.sql, consulta 1 — as 3 legadas com
              authenticated_x = true, anon_x/service_role_x = false e a ACL
              acima; as 5 vigentes como no PRE da 5365.
================================================================
*/

do $rollback$
declare
  c_legacy constant text[] := array[
    'public.set_physical_cards_storage(uuid,uuid[])',
    'public.organize_my_collection_storage(uuid,uuid,text,integer,text)',
    'public.add_physical_cards(jsonb)'];
  c_legacy_md5 constant text[] := array[
    'cf8d15bcbd1f0842541bfac99be3eb72',
    '595e5229051e4dc6e16a1c9e484a6e9b',
    '1a20285062a276992c8a3b679c4d6c6c'];
  c_acl_before constant text := '{postgres=X/postgres,authenticated=X/postgres}';
  c_acl_after  constant text := '{postgres=X/postgres}';
  v_oid oid;
  v_acl text;
  v_revoked  int := 0;
  v_restored int := 0;
  i int;
begin
  perform pg_catalog.set_config('lock_timeout', '5s', true);

  for i in 1 .. 3 loop
    v_oid := pg_catalog.to_regprocedure(c_legacy[i]);
    if v_oid is null
       or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_legacy_md5[i] then
      raise exception 'PRECHECK R5365: ESTADO DIVERGENTE — % ausente ou com outro corpo', c_legacy[i];
    end if;
    select p.proacl::text into v_acl from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_acl is null then
      raise exception 'PRECHECK R5365: ESTADO DIVERGENTE — % ACL nula (privilégio padrão, inclui PUBLIC)', c_legacy[i];
    elsif v_acl is not distinct from c_acl_after then v_revoked := v_revoked + 1;
    elsif v_acl is not distinct from c_acl_before then v_restored := v_restored + 1;
    else raise exception 'PRECHECK R5365: ESTADO DIVERGENTE — % ACL inesperada: %', c_legacy[i], v_acl;
    end if;
  end loop;
  if v_restored = 3 then
    raise exception 'PRECHECK R5365: NADA A DESFAZER — ACL já restaurada';
  end if;
  if v_revoked <> 3 then
    raise exception 'PRECHECK R5365: ESTADO DIVERGENTE — estado parcial (revogadas=% restauradas=%)', v_revoked, v_restored;
  end if;

  grant execute on function public.set_physical_cards_storage(uuid, uuid[]) to authenticated;
  grant execute on function public.organize_my_collection_storage(uuid, uuid, text, integer, text) to authenticated;
  grant execute on function public.add_physical_cards(jsonb) to authenticated;

  for i in 1 .. 3 loop
    v_oid := pg_catalog.to_regprocedure(c_legacy[i]);
    if v_oid is null
       or (select p.proacl::text from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_acl_before
       or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_legacy_md5[i]
       or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', v_oid, 'EXECUTE') is not false then
      raise exception 'POSTCHECK R5365: % não voltou à ACL anterior', c_legacy[i];
    end if;
  end loop;

  raise notice 'R5365 OK: EXECUTE de authenticated restaurado nas 3 legadas';
end;
$rollback$;
