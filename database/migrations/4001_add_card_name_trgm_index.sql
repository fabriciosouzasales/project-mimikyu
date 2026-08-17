-- Query 4001 | Índice trigram sobre lower(card.name)
-- Objetivo: acelerar pesquisa por nome (prefixo e ocorrência parcial, via ILIKE) usada pela
-- função public.search_cards (Incremento — Pesquisa Global de Cartas).
-- CONFIRMADO EXECUTADO em 2026-08-16/17 via Supabase MCP (apply_migration).

create index if not exists ix_card_name_trgm
  on public.card
  using gin (lower(name) extensions.gin_trgm_ops);
