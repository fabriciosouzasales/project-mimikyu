-- Project Mimikyu
-- Query 253 - Grant Card External Reference Permissions
-- Status: CONFIRMADA EXECUTADA (SQL Editor do Supabase Dashboard, "Success.
-- No rows returned"; reconfirmada por reexecução bem-sucedida da Edge
-- Function `import-card-assets`, 188/188 registros)
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.15", para o contexto
-- completo da descoberta.
--
-- Causa raiz real: mesmo gap já identificado na Query 250 para
-- card_set_external_reference, agora confirmado também em
-- public.card_external_reference — a tabela tem Row Level Security
-- habilitado (conforme STD-001, Seção 9), mas nunca recebeu um GRANT
-- explícito de SELECT/INSERT/UPDATE para o role service_role. RLS não
-- substitui o GRANT de nível de tabela do PostgreSQL.
--
-- Esse gap foi descoberto na prática pela Edge Function `import-card-assets`
-- v2.1.0 (Incremento 1), ao tentar o primeiro UPSERT real em
-- card_external_reference: erro genérico `CARD_EXTERNAL_REFERENCE_UPSERT_FAILED`,
-- sem detalhe do PostgreSQL, porque o próprio código descartava a causa
-- original (`console.error(error)` sem stringificar o objeto). Corrigido o
-- logging primeiro (ver `services/database.ts`), o erro real então revelado
-- foi "permission denied for table card_external_reference" — confirmando a
-- mesma causa raiz da Query 250.
--
-- Pendência reafirmada, não resolvida nesta migration: auditoria completa de
-- GRANTs para service_role em todas as tabelas do schema public, já proposta
-- desde a Query 250. Com dois casos reais confirmados (card_set_external_reference
-- e card_external_reference), Fabrício propôs consolidar essa auditoria em um
-- único script futuro (`database/migrations/permissions.sql` ou equivalente),
-- a ser feito depois que a implementação do Incremento 2 (download de
-- imagens) estiver concluída. Ver "Em Aberto" em docs/06-pipeline-importacao.md.

begin;

grant select, insert, update
    on table public.card_external_reference
    to service_role;

commit;
