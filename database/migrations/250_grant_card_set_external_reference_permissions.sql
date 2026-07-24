-- Project Mimikyu
-- Query 250 - Grant Card Set External Reference Permissions
-- Status: CONFIRMADA EXECUTADA (`npx supabase db push`, reconfirmada por
-- consulta real a information_schema.role_table_grants)
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.6", para o contexto
-- completo da descoberta.
--
-- Causa raiz real: a tabela public.card_set_external_reference (Query 240)
-- foi criada com Row Level Security habilitado (conforme exigido pela Seção 9
-- de docs/standards/STD-001-database-standards.md), mas nunca recebeu um
-- GRANT explícito de SELECT/INSERT/UPDATE/DELETE para o role service_role.
-- Habilitar RLS não substitui o GRANT de nível de tabela do PostgreSQL — são
-- verificações independentes, e a ausência do GRANT bloqueia o acesso mesmo
-- para um role que, de outra forma, poderia contornar as políticas de RLS.
--
-- Esse gap foi descoberto na prática pela Edge Function `import-card-assets`
-- (Sprint B3.6), ao migrar de `@supabase/server`/`withSupabase` para um
-- cliente Supabase criado manualmente via `SUPABASE_SERVICE_ROLE_KEY`: a
-- primeira chamada real, livre do bloqueio de autenticação (HTTP 401)
-- resolvido nesta mesma revisão, retornou HTTP 500 com o erro real do
-- PostgreSQL "permission denied for table card_set_external_reference".
--
-- Pendência registrada, não resolvida nesta migration: não está confirmado
-- se esse mesmo gap existe em outras tabelas do projeto criadas por migration
-- SQL direta (em vez do editor visual do Supabase Studio) — uma auditoria
-- completa de GRANTs para service_role em todas as tabelas do schema public
-- foi proposta, mas ainda não executada. Ver "Em Aberto" em
-- docs/06-pipeline-importacao.md.

begin;

grant select, insert, update, delete
    on table public.card_set_external_reference
    to service_role;

grant usage
    on schema public
    to service_role;

commit;
