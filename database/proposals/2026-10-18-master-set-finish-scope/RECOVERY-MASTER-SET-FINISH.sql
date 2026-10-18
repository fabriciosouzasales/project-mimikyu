/*
================================================================
Projeto.....: Project Mimikyu
Artefato....: RECUPERAÇÃO — desfazer 5184–5197 (Master Set por acabamento)
Versão......: 1.1 (LIVE-EXECUTION-START-01: equivalência dos canônicos, ledger e gate objetivo)
Status......: ROTEIRO — NÃO EXECUTADO. Só com autorização expressa de Fabrício.
Data........: 2026-10-18 (MASTER-SET-LIVE-EXECUTION-READINESS-01)

NÃO É MIGRATION NUMERADA. Usar apenas se um gate do plano
LIVE-EXECUTION-READINESS-01.md der STOP depois de alguma aplicação.

Pré-condição (conferida no bloco R0): nenhuma coleção MASTER_SET e nenhuma
linha em collection_master_set_finish. Enquanto o frontend do Master Set
não existir, essa condição se mantém (só os harnesses criam linhas, e eles
desfazem tudo). Se ela falhar, PARAR: a reversão passaria a exigir decisão
sobre dados (Fabrício).

Escolher o caminho conforme o ponto em que a aplicação parou:
  R-A  5197 NÃO aplicada (tabela antiga ainda existe)
  R-B  5197 aplicada (tabela antiga removida) → executar R-B1 e depois R-A

Cada passo "reaplicar <arquivo>" significa aplicar o arquivo canônico de
database/schema/ correspondente, sem alteração, como migration nova.

Equivalência dos canônicos com o LIVE (conferida em 2026-10-18, só leitura):
corpo normalizado (sem espaços) idêntico para 5073, 5074, 5075, 5077, 5082
e 5102; idêntico também sem comentários para 5079, 5080 e 5084 (o LIVE foi
aplicado sem os comentários de linha; a lógica é a mesma). ACLs dos
canônicos (REVOKE/GRANT ao fim de cada arquivo) iguais às do LIVE:
EXECUTE para authenticated só em 5080, 5082, 5084 e 5102.

Ledger: cada passo vira uma migration NOVA via apply_migration, com nome
ms_finish_recovery_<NN>_<o-que> (ex.: ms_finish_recovery_01_restore_5072).
Nenhuma linha de supabase_migrations.schema_migrations é apagada ou editada:
as migrations 5184–5197 continuam registradas e a recuperação fica como
histórico compensatório posterior.

Ordem exata:
  Parou ANTES de 5197 (R-A):
    01 R0 (guarda) → 02 reaplicar 5102 → 03 reaplicar 5075 → 04 bloco A3
    (drops) → 05 reaplicar 5080 → 06 reaplicar 5082 → 07 reaplicar 5084
    (05–07 só para o que 5194/5195/5189 chegaram a remover) → 08 R-V.
  5197 JÁ aplicada (R-B1 + R-A):
    01 R0 → 02 reaplicar 5072 → 03 reaplicar 5073 → 04 reaplicar 5074 →
    05 reaplicar 5077 → 06 reaplicar 5079 → 07 gatilho de 2268 → depois
    R-A a partir do 5102 (5102 é LANGUAGE sql e valida o corpo na criação:
    exige a tabela antiga já restaurada) → R-V.
================================================================
*/

-- R0 — guarda (somente leitura, aborta se houver dado Master Set) -------------
do $$
begin
  if exists (select 1 from public.collection where completion_policy = 'MASTER_SET') then
    raise exception 'RECOVERY ABORT: há coleção MASTER_SET — decisão de dados necessária';
  end if;
  if to_regclass('public.collection_master_set_finish') is not null
     and exists (select 1 from public.collection_master_set_finish) then
    raise exception 'RECOVERY ABORT: collection_master_set_finish tem linhas';
  end if;
end;
$$;

-- R-B1 — só se 5197 foi aplicada: restaurar a tabela antiga e suas funções ----
--   reaplicar 5072_create_collection_master_set_scope_table.sql
--   reaplicar 5073_create_collection_master_set_scope_eligibility_trigger.sql
--   reaplicar 5074_create_collection_master_set_scope_update_block_trigger.sql
--   reaplicar 5077_create_master_set_scope_presence_on_delete_trigger.sql
--   reaplicar 5079_create_apply_master_set_scope_diff_function.sql
--   e o gatilho de 2268 na tabela restaurada:
--     create trigger trg_guard_card_variant_active
--       before insert or update of card_variant_id on public.collection_master_set_scope
--       for each row execute function internal.guard_card_variant_reference_active();

-- R-A — desfazer 5184–5196 ----------------------------------------------------
-- A1. resumo volta ao 5102 ANTES de remover master_set_positions (5188 o usa;
--     corpo SQL em string não registra dependência, o DROP não avisaria):
--   reaplicar 5102_update_collection_completion_summary_reference_position_performance.sql
-- A2. helper de presença volta ao corpo do 5075 (lê a tabela antiga):
--   reaplicar 5075_create_check_master_set_scope_presence_function.sql
-- A3. remover contratos novos (ordem inversa de criação)
begin;
drop function if exists public.get_my_master_set_out_of_scope_copies(uuid, integer, integer);
drop function if exists public.replace_master_set_finishes(uuid, uuid[]);
drop function if exists public.set_collection_completion_policy_to_master_set(uuid, uuid[]);
drop function if exists public.apply_master_set_finishes(uuid, uuid, uuid[]);
drop function if exists public.preview_my_master_set_finishes(uuid, uuid[]);
drop function if exists public.get_my_master_set_finish_options(uuid);
drop function if exists public.normalize_master_set_finishes(uuid, uuid, uuid[]);
drop function if exists public.get_my_master_set_positions(uuid, text, integer, integer);
drop function if exists public.master_set_positions(uuid, uuid[]);
drop table if exists public.collection_master_set_finish;          -- leva seus gatilhos e a policy
drop function if exists public.enforce_master_set_finish_presence_on_delete();
drop function if exists public.validate_master_set_finish_eligibility();
drop function if exists public.reject_collection_master_set_finish_update();
commit;
-- A4. restaurar contratos antigos removidos por 5189/5194/5195:
--   reaplicar 5080_create_set_collection_completion_policy_to_master_set_function.sql
--   reaplicar 5082_create_replace_master_set_scope_function.sql
--   reaplicar 5084_create_collection_master_set_scope_positions_function.sql

-- R-V — verificação (somente leitura): deve reproduzir o pré-check original ----
select
  (select count(*) from public.collection_master_set_scope)                       as scope_rows_0,
  (select count(*) from public.collection where completion_policy = 'MASTER_SET') as master_0,
  to_regclass('public.collection_master_set_finish')                              as finish_null,
  (select md5(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', '', 'g'))
     from pg_proc where proname = 'collection_completion_summary')               as summary_md5_0a644fe6,
  to_regprocedure('public.set_collection_completion_policy_to_master_set(uuid,jsonb)') is not null
    and to_regprocedure('public.set_collection_completion_policy_to_master_set(uuid,uuid[])') is null as old_activation_only;
-- Gate objetivo do estado restaurado (somente leitura): corpos iguais aos de
-- antes da aplicação (md5 sem comentários e sem espaços, medidos no LIVE em
-- 2026-10-18), ACL e gatilhos.
select p.proname,
       md5(regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '\s+', '', 'g')) as body_md5,
       p.proacl::text as acl
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('validate_master_set_scope_eligibility','reject_collection_master_set_scope_update',
                    'check_master_set_scope_presence','enforce_scope_master_set_presence_on_delete',
                    'apply_master_set_scope_diff','set_collection_completion_policy_to_master_set',
                    'replace_master_set_scope','collection_master_set_scope_positions','collection_completion_summary')
order by 1;
-- Esperado (ignorando comentários; valores medidos com comentários removidos):
--   collection_completion_summary          0a644fe65e044a352e1a8327e9373284
--   apply_master_set_scope_diff            838dbc235ae30c486f699275f68c3ffa
--   set_collection_completion_policy_to_master_set c8630232e064adf7ab9588e31a174be8
--   collection_master_set_scope_positions  0daf1ec8740eafb7805d07aa94e9bea4
--   check_master_set_scope_presence        910d1aa7ea97db74a49f706da7d2d20f
--   enforce_scope_master_set_presence_on_delete 8c2127d27afb8214e372fbc8c87f214a
--   reject_collection_master_set_scope_update 1619e42782370957ed4e57a73bb0813c
--   replace_master_set_scope               def9797646ea59b476a61030a94e8e9c
--   validate_master_set_scope_eligibility  cb96c181ba9bbf2341a44f325e9b093a
-- ACL esperada: authenticated=X só em collection_completion_summary,
--   collection_master_set_scope_positions, replace_master_set_scope e
--   set_collection_completion_policy_to_master_set; demais {postgres=X/postgres}.
-- E: (select count(*) from pg_trigger where tgname = 'trg_guard_card_variant_active') = 4
-- Em seguida: 5838 (psql) deve dar o mesmo GATE da linha de base.
