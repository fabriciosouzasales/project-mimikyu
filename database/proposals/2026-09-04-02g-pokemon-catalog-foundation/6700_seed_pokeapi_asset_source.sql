/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6700 - Seed PokéAPI Asset Source
Versão......: 1.0
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04

Descrição...:
Insere a linha de asset_source correspondente à PokéAPI — Fonte
externa usada para popular/enriquecer pokemon_species_external_
reference (Query 6020). Decisão congelada
(COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01): PokéAPI é
representada via asset_source, nunca via coluna solta (pokeapi_id) ou
mecanismo polimórfico genérico.

Confirmado nesta rodada, via SELECT direto em asset_source: os únicos
registros hoje são POKEMON_TCG_API (source_order 1), TCGDEX
(source_order 2) e MANUAL (source_order 99). source_order = 3 é o
próximo valor livre.

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
