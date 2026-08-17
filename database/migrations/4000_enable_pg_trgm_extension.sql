-- Query 4000 | Habilitar extensão pg_trgm
-- Objetivo: habilitar pg_trgm (schema extensions) para suportar índice trigram de pesquisa
-- parcial por nome de carta. Primeira migration do módulo 4000-4999 (Pesquisa de Cartas).
-- CONFIRMADO EXECUTADO em 2026-08-16/17 via Supabase MCP (apply_migration).

create extension if not exists pg_trgm with schema extensions;
