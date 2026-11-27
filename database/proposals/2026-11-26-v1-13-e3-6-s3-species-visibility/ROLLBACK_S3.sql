/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_S3 — reversão da 5393 (V1-13 · E3-6 / S3)
Versão......: 1.0 (2026-11-26)
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo de recuperação, pelo
              proprietário, com autorização expressa. Uma transação (psql).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-26
Efeito......: retira só a porta 5393. Não apaga nem altera dado algum
              (referências, preferência de exibição, fichário, participações).
              5315, 5316 e 5318 não são tocadas; o fichário do participante
              volta a ler pela 5316 (fallback C2: função ausente → PGRST202/
              42883). Nenhuma outra função depende da 5393.
Como validar: depois, to_regprocedure da 5393 é NULL; md5 do prosrc de
              5315/5316/5318 iguais aos do precheck da 5393 (harness 5897 §6).
================================================================
*/

-- R5393 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.get_shared_collection_binder_pages_with_species(uuid, integer, integer);
do $post$
begin
  if to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)') is not null then
    raise exception 'POSTCHECK R5393: função ainda existe';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')) is distinct from 'ce559a495a49571a6598c83bc3d59202'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)')) is distinct from '79f893c45a08909e0a61d661952ab750'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)')) is distinct from '0da2d28209cd85b6bdbf6c20ae47efd6' then
    raise exception 'POSTCHECK R5393: 5315/5316/5318 fora do canônico';
  end if;
end;
$post$;
commit;
