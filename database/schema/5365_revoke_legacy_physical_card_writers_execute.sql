/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5365 - Revoga EXECUTE de authenticated em três escritores
              legados de physical_card (PR-04, hardening)
Versão......: 1.1 (2026-11-13, `PR-04A | LEGACY EXECUTE HARDENING CORRECTION-01`:
              D2 comparações NULL-seguras; D4 pg_catalog.; D5 cabeçalho)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-11-14
              (`PR-04A | 5365 LIVE CONTROLLED EXECUTION-01`, autorização expressa do
              proprietário, G-D dispensado com aceitação de risco), arquivo integral
              numa chamada de execute_sql (MCP) como postgres. Texto idêntico ao de
              database/proposals/2026-11-13-pr04-legacy-execute-hardening/ (sha256
              747a1dea…), exceto este bloco Status. Consulta 1 PRE = T0; POST: só as 3
              legadas sem EXECUTE de authenticated; 5 vigentes inalteradas (evidência em
              …/execution-2026-11-14/). SEM registro no ledger supabase_migrations.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-13
Objetivo....: Retirar de `authenticated` o EXECUTE de três funções que o
              aplicativo não usa mais, sem mudar corpo, dono, assinatura
              nem as funções vigentes:
                1. public.set_physical_cards_storage(uuid, uuid[])          (5024)
                2. public.organize_my_collection_storage(uuid, uuid, text,
                   integer, text)                                            (5222)
                3. public.add_physical_cards(jsonb)                          (5012)
              Vigentes, que NÃO mudam: set_physical_cards_storage(uuid,
              uuid[], boolean) e organize_my_collection_storage(..., boolean)
              (5249/5287), set_my_physical_cards_condition (5364),
              remove_my_physical_card (5165), register_physical_cards_bulk
              (5362).

Forma.......: UMA instrução de topo (um único DO): precheck → REVOKE ×3 →
              postcheck. Exceção em qualquer ponto desfaz tudo, em qualquer
              canal (lição da 5361 v1.0). Sem BEGIN/COMMIT externos.
Idempotência: estado já revogado nas três → 'PRECHECK 5365: JÁ APLICADA'
              (nada muda). Qualquer outro estado diferente do esperado →
              'ESTADO DIVERGENTE' (nada muda).
Efeito......: só pg_proc.proacl das três assinaturas. `postgres` (dono)
              mantém EXECUTE — rotinas administrativas executadas como
              postgres continuam funcionando. `anon`, `service_role` e
              PUBLIC já não têm EXECUTE e continuam sem.
Reversão....: R5365_rollback_regrant_authenticated.sql (só GRANT de volta
              a authenticated, com precheck do estado pós-5365).
Executor....: o dono das funções (`postgres`) ou superusuário. Outro papel
              não revoga (o PostgreSQL só emite WARNING) e o postcheck aborta.
NULL........: toda comparação de ACL, md5, dono e privilégio rejeita NULL
              explicitamente (IS DISTINCT FROM / IS NOT TRUE / IS NOT FALSE).
Resultado esperado: NOTICE '5365 OK: EXECUTE revogado de authenticated em 3
              legadas; 5 vigentes intactas'. As 3 legadas ficam com ACL
              {postgres=X/postgres}; as 5 vigentes não mudam.
              Já aplicada → EXCEPTION 'PRECHECK 5365: JÁ APLICADA' (nada muda).
              Qualquer outro estado → EXCEPTION 'ESTADO DIVERGENTE' ou
              'POSTCHECK 5365' e nada muda.
Como validar: 5365_STATE_readonly.sql, consulta 1, antes (PRE) e depois
              (POST), comparada com o README ("Critérios de aceite").
================================================================
*/

do $hardening$
declare
  -- Identidade exata (assinatura + md5(prosrc) lido no LIVE em 2026-11-13).
  c_legacy constant text[] := array[
    'public.set_physical_cards_storage(uuid,uuid[])',
    'public.organize_my_collection_storage(uuid,uuid,text,integer,text)',
    'public.add_physical_cards(jsonb)'];
  c_legacy_md5 constant text[] := array[
    'cf8d15bcbd1f0842541bfac99be3eb72',
    '595e5229051e4dc6e16a1c9e484a6e9b',
    '1a20285062a276992c8a3b679c4d6c6c'];
  -- Vigentes: corpo e ACL não podem mudar.
  c_current constant text[] := array[
    'public.set_physical_cards_storage(uuid,uuid[],boolean)',
    'public.organize_my_collection_storage(uuid,uuid,text,integer,text,boolean)',
    'public.set_my_physical_cards_condition(uuid[],text)',
    'public.remove_my_physical_card(uuid)',
    'public.register_physical_cards_bulk(jsonb)'];
  c_current_md5 constant text[] := array[
    '09e342a1fc65b6eb588dc9784f20034d',
    '26ea92ac712d103ff21856e779b94ef2',
    'b569ecdbe202428a6bdc9461c6d62e37',
    'd51b9264381b5e1623fe186d7dec67a3',
    'd08dcc259222a286d99bcd53f9da7285'];
  c_acl_before constant text := '{postgres=X/postgres,authenticated=X/postgres}';
  c_acl_after  constant text := '{postgres=X/postgres}';
  v_oid   oid;
  v_acl   text;
  v_md5   text;
  v_owner text;
  v_secdef boolean;
  v_before int := 0;
  v_after  int := 0;
  i int;
begin
  perform pg_catalog.set_config('lock_timeout', '5s', true);

  -- PRECHECK 1: nomes sem sobrecarga inesperada.
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'set_physical_cards_storage') <> 2
     or (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'organize_my_collection_storage') <> 2
     or (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'add_physical_cards') <> 1 then
    raise exception 'PRECHECK 5365: ESTADO DIVERGENTE — número de sobrecargas diferente do esperado (2/2/1)';
  end if;

  -- PRECHECK 2: identidade e ACL das três legadas.
  for i in 1 .. 3 loop
    v_oid := pg_catalog.to_regprocedure(c_legacy[i]);
    if v_oid is null then
      raise exception 'PRECHECK 5365: ESTADO DIVERGENTE — % ausente', c_legacy[i];
    end if;
    select pg_catalog.md5(p.prosrc), p.proacl::text, pg_catalog.pg_get_userbyid(p.proowner), p.prosecdef
      into v_md5, v_acl, v_owner, v_secdef
      from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5 is distinct from c_legacy_md5[i]
       or v_owner is distinct from 'postgres'
       or v_secdef is not true then
      raise exception 'PRECHECK 5365: ESTADO DIVERGENTE — % corpo/dono/secdef inesperado (md5=% dono=% secdef=%)',
        c_legacy[i], v_md5, v_owner, v_secdef;
    end if;
    if v_acl is null then
      raise exception 'PRECHECK 5365: ESTADO DIVERGENTE — % ACL nula (privilégio padrão, inclui PUBLIC)', c_legacy[i];
    elsif v_acl is not distinct from c_acl_before then v_before := v_before + 1;
    elsif v_acl is not distinct from c_acl_after then v_after := v_after + 1;
    else
      raise exception 'PRECHECK 5365: ESTADO DIVERGENTE — % ACL inesperada: %', c_legacy[i], v_acl;
    end if;
  end loop;
  if v_after = 3 then
    raise exception 'PRECHECK 5365: JÁ APLICADA — nada a fazer (não reaplicar)';
  end if;
  if v_before <> 3 then
    raise exception 'PRECHECK 5365: ESTADO DIVERGENTE — revogação parcial (antes=% depois=%)', v_before, v_after;
  end if;

  -- PRECHECK 3: vigentes íntegras e acessíveis.
  for i in 1 .. 5 loop
    v_oid := pg_catalog.to_regprocedure(c_current[i]);
    if v_oid is null
       or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_current_md5[i]
       or (select p.proacl::text from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_acl_before then
      raise exception 'PRECHECK 5365: ESTADO DIVERGENTE — vigente % ausente, com outro corpo ou outra ACL (inclusive nula)', c_current[i];
    end if;
  end loop;

  -- EFEITO: restrição mínima — só EXECUTE de authenticated nas três legadas.
  revoke execute on function public.set_physical_cards_storage(uuid, uuid[]) from authenticated;
  revoke execute on function public.organize_my_collection_storage(uuid, uuid, text, integer, text) from authenticated;
  revoke execute on function public.add_physical_cards(jsonb) from authenticated;

  -- POSTCHECK 1: legadas sem EXECUTE para authenticated/anon/service_role/PUBLIC; dono mantém; corpo igual.
  for i in 1 .. 3 loop
    v_oid := pg_catalog.to_regprocedure(c_legacy[i]);
    if v_oid is null
       or (select p.proacl::text from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_acl_after
       or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_legacy_md5[i]
       or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', v_oid, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('postgres', v_oid, 'EXECUTE') is not true then
      raise exception 'POSTCHECK 5365: % não ficou no estado esperado', c_legacy[i];
    end if;
  end loop;

  -- POSTCHECK 2: vigentes intactas (corpo, ACL e EXECUTE de authenticated).
  for i in 1 .. 5 loop
    v_oid := pg_catalog.to_regprocedure(c_current[i]);
    if v_oid is null
       or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_current_md5[i]
       or (select p.proacl::text from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from c_acl_before
       or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true then
      raise exception 'POSTCHECK 5365: vigente % foi afetada — abortar', c_current[i];
    end if;
  end loop;

  raise notice '5365 OK: EXECUTE revogado de authenticated em 3 legadas; 5 vigentes intactas';
end;
$hardening$;
