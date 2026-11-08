/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357-R1 - PROCEDIMENTO DE REVERSÃO da Query 5357
Versão......: 0.1 (B2 — PHASE C FINAL READINESS-01)
Status......: PROPOSTO — NÃO EXECUTADO. R0 é somente leitura e exige
              autorização; R1 MODIFICA O LIVE e só pode ser executado com
              autorização EXPLÍCITA e específica do proprietário.
Data........: 2026-11-08

Quando usar: só se um gate da fase C (C2, C3a ou C3b) falhar depois da
aplicação, ou por decisão do proprietário. Nunca automático.

Escopo: remove SOMENTE public.get_my_binder_value_groups(uuid, integer,
integer). Sem CASCADE: se algum objeto depender da função, o DROP falha em
vez de levar o dependente junto. A aplicação ainda não chama a função; a
remoção não afeta telas.
================================================================
*/

-- R0 [GATE da reversão, somente leitura] confirmar o alvo exato antes de remover
-- PASS: existe = true, assinatura_exata = true, sobrecargas = 1,
--       dependentes_normais = 0. Qualquer divergência → STOP (não remover).
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with f as (
  select to_regprocedure('public.get_my_binder_value_groups(uuid,integer,integer)') as oid
)
select jsonb_build_object(
  'bloco', 'R0',
  'existe', (select oid from f) is not null,
  'assinatura_exata', coalesce((select pg_get_function_identity_arguments(oid) = 'p_collection_id uuid, p_limit integer, p_offset integer' from f where oid is not null), false),
  'sobrecargas', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'get_my_binder_value_groups'),
  'dependentes_normais', (select count(*) from pg_depend d
                           where d.refclassid = 'pg_proc'::regclass and d.refobjid = (select oid from f)
                             and d.deptype = 'n'),
  'corpo_igual_a_proposta', coalesce((select md5(p.prosrc) = 'e6cdae3e7c48d6df06f3fba4836c5575'
                                        from pg_proc p where p.oid = (select oid from f)), false)
) as resultado_r0;
rollback;

-- R1 [MODIFICA O LIVE — SÓ COM AUTORIZAÇÃO EXPLÍCITA] remoção da função
-- Mantido comentado de propósito: executar exige descomentar conscientemente,
-- depois de R0 em PASS e da autorização. Não usar CASCADE.
--
-- drop function public.get_my_binder_value_groups(uuid, integer, integer);
--
-- R2 [somente leitura] confirmação: repetir R0; esperado existe = false,
-- sobrecargas = 0. Registrar a reversão em docs/log.md e no documento de
-- validação; a 5357 volta ao estado PROPOSTA.
