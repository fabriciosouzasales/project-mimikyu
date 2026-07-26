/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2800 - Validate Internal Schema
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação do schema internal (Query 2000): existência, comentário,
owner/ACL e ausência de USAGE para anon/authenticated. Não valida
a lista de schemas expostos pela API do Supabase — essa é uma
configuração de plataforma (Studio → Settings → API → Exposed
schemas), não um objeto do banco, e deve ser conferida manualmente
por Fabrício.
================================================================
*/

-- 1. Schema existe, com comentário
SELECT nspname, obj_description(oid, 'pg_namespace') AS comentario
FROM pg_namespace
WHERE nspname = 'internal';

-- 2. USAGE ausente para anon/authenticated
SELECT
    has_schema_privilege('anon', 'internal', 'USAGE') AS anon_tem_usage,
    has_schema_privilege('authenticated', 'internal', 'USAGE') AS authenticated_tem_usage;
-- Esperado: false, false

-- 3. ACL bruto (auditoria)
SELECT nspname, nspowner::regrole AS owner, nspacl
FROM pg_namespace
WHERE nspname = 'internal';
-- Esperado: apenas o owner (postgres) com privilégios; nenhuma
-- entrada para PUBLIC, anon ou authenticated.

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
-- - schema internal existe, comentário gravado corretamente.
-- - anon_tem_usage = false; authenticated_tem_usage = false.
-- - nspacl = {postgres=UC/postgres} — nenhuma entrada para PUBLIC,
--   anon ou authenticated.
-- - Pendente confirmação manual de Fabrício: schema internal não
--   deve constar em Studio → Settings → API → Exposed schemas.
-- ================================================================
