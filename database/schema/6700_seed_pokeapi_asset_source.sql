/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6700 - Seed PokéAPI Asset Source
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (aplicado em 2026-09-04,
               COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01)

Descrição...:
Insere a linha de asset_source correspondente à PokéAPI — Fonte
externa usada para popular/enriquecer pokemon_species_external_
reference (Query 6020). Decisão congelada
(COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01): PokéAPI é
representada via asset_source, nunca via coluna solta (pokeapi_id) ou
mecanismo polimórfico genérico.

Confirmado nesta rodada, via SELECT direto em asset_source: os únicos
registros existentes antes desta Query eram POKEMON_TCG_API
(source_order 1), TCGDEX (source_order 2) e MANUAL (source_order 99).
source_order = 3 foi o próximo valor livre.

Pré-requisitos:
- Query 200 - Create Asset Source Table (já CONFIRMADO EXECUTADO).
===============================================================================
*/

BEGIN;

INSERT INTO public.asset_source (
    code,
    name,
    source_type,
    base_url,
    api_base_url,
    documentation_url,
    attribution_text,
    supports_api,
    supports_bulk_download,
    is_active,
    source_order
) VALUES (
    'POKEAPI',
    'PokéAPI',
    'API',
    'https://pokeapi.co/',
    'https://pokeapi.co/api/v2/',
    'https://pokeapi.co/docs/v2',
    'Dados de espécies Pokémon via PokéAPI (pokeapi.co).',
    TRUE,
    FALSE,
    TRUE,
    3
);

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01). Postcheck
-- confirmou exatamente 1 linha com code='POKEAPI' em asset_source.
-- ================================================================

-- ================================================================
-- Nota de padrão (2026-09-04, achado de auditoria externa,
-- COLLECTIONS-PHYSICAL-INCREMENT-02G-SECURITY-CLOSEOUT-FIX-01): esta
-- Query difere deliberadamente do padrão de
-- database/seeds/900_seed_asset_source.sql (que usa
-- ON CONFLICT (code) DO UPDATE para os 3 registros originais
-- POKEMON_TCG_API/TCGDEX/MANUAL, sendo reexecutável com segurança).
-- 6700 é uma migration one-shot já CONFIRMADO EXECUTADO — um único
-- INSERT sem ON CONFLICT, seguindo o padrão mais recente de
-- Collections (Queries 5000+/6000+: uma migration = um evento
-- discreto e não reexecutável, nunca um seed idempotente). As duas
-- linhas de código (POKEMON_TCG_API/TCGDEX/MANUAL) coexistem com
-- POKEAPI na mesma tabela asset_source, cada uma sob a convenção
-- vigente no momento em que foi inserida — divergência de padrão
-- documentada, não corrigida retroativamente (não reescrever
-- silenciosamente histórico físico já executado).
-- ================================================================
