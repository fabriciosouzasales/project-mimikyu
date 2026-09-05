/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6106 - Create Reconcile Pokemon Catalog Sourcing Snapshot
               Function (AUXILIAR)
Versão......: 2.0 (PROPOSTA — GATE 3 STAGING, REVISION-01)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01; revisado em ...-STAGING-REVISION-01 após
               GATE 4 apontar NO-GO)

*** ORDEM DE APLICAÇÃO: esta função deve ser criada ANTES de 6104 (PLAN) e
    6105 (APPLY), pois ambas a chamam. Ver README.md.

REVISION-01 — o que mudou e por quê (GATE 4 apontou 2 defeitos bloqueantes na
lógica de reconciliação, mais um erro de implementação encontrado durante a
própria correção):

1. INITIAL LOAD LOCKSTEP (defeito: Initial Load sobre catálogo vazio nunca
   conseguia fechar com zero DIVERGENT). Na v1.0, a resolução de
   `main_region_external_id` (Generation) e `generation_external_id`
   (Species) só aceitava um mapeamento JÁ EXISTENTE via *_external_reference
   — mas em um Initial Load, Region/Generation ainda não existem fisicamente
   quando Generation/Species são avaliadas no MESMO snapshot, o que
   classificava tudo como DIVERGENT (Region/Generation "não resolvida").
   Correção: a resolução agora aceita DUAS fontes válidas — (a) uma
   referência externa já existente, OU (b) uma entidade classificada NEW
   dentro do MESMO snapshot (lockstep). Para entidades JÁ EXISTENTES
   (possuem *_external_reference), a comparação estrutural deixou de
   depender de "resolver o ID esperado e comparar contra o ID atual" — passa
   a verificar diretamente, via EXISTS, se a referência externa atual do pai
   real (`gen.main_region_id` / `sp.generation_id`) já corresponde ao
   external_id esperado do snapshot. Isso elimina por completo a necessidade
   de prever o UUID de uma entidade ainda não inserida (PLAN é read-only).

2. GENERATION NATURAL KEYS (defeito: colisão em UM ÚNICO eixo de
   `pokemon_generation` — `code` OU `ordinal_number`, não necessariamente os
   dois na MESMA linha — não era detectada). Correção: os dois eixos são
   agora verificados de forma INDEPENDENTE (dois LEFT JOINs distintos,
   `byname_code` e `byname_ordinal`); colisão em qualquer um dos dois, sem
   referência externa correspondente, classifica DIVERGENT.

3. (Encontrado nesta própria revisão, não apontado pelo GATE 4, mas
   corrigido antes de entregar): a primeira tentativa de correção usou
   `CREATE TEMP TABLE ... ON COMMIT DROP` para materializar a classificação
   de Regions/Generations e permitir que Generations/Species a referenciem.
   Isso quebra sempre que esta função é chamada MAIS DE UMA VEZ dentro da
   MESMA transação — exatamente o que 6105 (APPLY) faz agora (fresh
   reconciliation inicial + fresh reconciliation pós-lock + reconciliação
   final pós-escrita, ver Query 6105 REVISION-01): a segunda chamada falharia
   com "relation already exists", pois `ON COMMIT DROP` só libera a tabela no
   fim da TRANSAÇÃO, não no fim da chamada de função. Mesma classe de defeito
   já registrada no histórico do projeto (staging 02C, "remove TEMP TABLEs").
   Corrigido reescrevendo a função inteira como uma única cadeia de CTEs
   (`WITH ... SELECT`), sem nenhuma tabela — CTEs são escopadas à própria
   query, não à transação, e por isso são seguras para chamadas repetidas.

Descrição resumida (inalterada da v1.0): recebe um asset_source_id e um
snapshot já validado estruturalmente (Query 6104) e retorna um objeto JSONB
com a contagem NEW/UNCHANGED/UPDATE_NAME/DIVERGENT por família, seguindo a
matriz de reconciliação da Seção 9.3 do contrato 06a.

Regra geral (reafirmada): colisão de chave natural SEM referência externa
correspondente → DIVERGENT, NUNCA auto-bind — mantida integralmente; o que
mudou é apenas a definição de "referência externa correspondente" para
aceitar o caso lockstep do mesmo snapshot.

Grants: inalterados da v1.0 — helper INTERNO, sem GRANT EXECUTE a nenhum
role (nem service_role); chamado apenas por 6104/6105.

Pré-requisitos: inalterados da v1.0.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.reconcile_pokemon_catalog_sourcing_snapshot(
    p_asset_source_id UUID,
    p_snapshot JSONB
)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH regions_classified AS (
        -- Regions (Seção 9.3: chave natural = code). Sem dependência de
        -- lockstep: Region é a raiz da hierarquia.
        SELECT
            snap.external_region_id,
            CASE
                WHEN xref.pokemon_region_id IS NOT NULL THEN
                    CASE
                        WHEN reg.code IS DISTINCT FROM snap.code THEN 'DIVERGENT'
                        WHEN reg.canonical_name IS DISTINCT FROM snap.canonical_name THEN 'UPDATE_NAME'
                        ELSE 'UNCHANGED'
                    END
                WHEN byname.id IS NOT NULL THEN 'DIVERGENT'
                ELSE 'NEW'
            END AS classification
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'regions', '[]'::JSONB))
            AS snap(external_region_id TEXT, code TEXT, canonical_name TEXT)
        LEFT JOIN public.pokemon_region_external_reference xref
            ON xref.asset_source_id = p_asset_source_id
           AND xref.external_region_id = snap.external_region_id
        LEFT JOIN public.pokemon_region reg
            ON reg.id = xref.pokemon_region_id
        LEFT JOIN public.pokemon_region byname
            ON byname.code = snap.code
           AND xref.pokemon_region_id IS NULL
    ),
    generations_resolved AS (
        SELECT
            snap.external_generation_id, snap.code, snap.canonical_name,
            snap.ordinal_number, snap.main_region_external_id,
            region_xref.pokemon_region_id AS existing_region_id,
            -- lockstep: main_region_external_id corresponde a uma Region
            -- classificada NEW no mesmo snapshot (só relevante quando NÃO há
            -- referência externa já existente para essa Region) — Fix 1.
            (region_new.external_region_id IS NOT NULL) AS region_is_valid_new
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'generations', '[]'::JSONB))
            AS snap(external_generation_id TEXT, code TEXT, canonical_name TEXT,
                    ordinal_number INTEGER, main_region_external_id TEXT)
        LEFT JOIN public.pokemon_region_external_reference region_xref
            ON region_xref.asset_source_id = p_asset_source_id
           AND region_xref.external_region_id = snap.main_region_external_id
        LEFT JOIN regions_classified region_new
            ON region_new.external_region_id = snap.main_region_external_id
           AND region_new.classification = 'NEW'
           AND region_xref.pokemon_region_id IS NULL
    ),
    generations_classified AS (
        -- Generations (Seção 9.3: chave natural = code E ordinal_number,
        -- verificados em EIXOS INDEPENDENTES — Fix 2; campo estrutural
        -- adicional = main_region_id, resolvido via referência existente OU
        -- via Region NEW no mesmo snapshot — Fix 1 / lockstep).
        SELECT
            resolved.external_generation_id,
            CASE
                WHEN gen_xref.pokemon_generation_id IS NOT NULL THEN
                    -- Generation já existente: comparação estrutural via
                    -- EXISTS contra a referência externa ATUAL do pai real
                    -- (nunca via resolução hipotética de ID) — Fix 1.
                    CASE
                        WHEN gen.code IS DISTINCT FROM resolved.code
                          OR gen.ordinal_number IS DISTINCT FROM resolved.ordinal_number
                            THEN 'DIVERGENT'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM public.pokemon_region_external_reference existing_region_xref
                            WHERE existing_region_xref.pokemon_region_id = gen.main_region_id
                              AND existing_region_xref.asset_source_id = p_asset_source_id
                              AND existing_region_xref.external_region_id = resolved.main_region_external_id
                        ) THEN 'DIVERGENT'
                        WHEN gen.canonical_name IS DISTINCT FROM resolved.canonical_name THEN 'UPDATE_NAME'
                        ELSE 'UNCHANGED'
                    END
                WHEN resolved.existing_region_id IS NULL AND NOT resolved.region_is_valid_new THEN 'DIVERGENT' -- Region não resolvida (4.2)
                WHEN byname_code.id IS NOT NULL OR byname_ordinal.id IS NOT NULL THEN 'DIVERGENT' -- Fix 2: eixos independentes
                ELSE 'NEW'
            END AS classification
        FROM generations_resolved resolved
        LEFT JOIN public.pokemon_generation_external_reference gen_xref
            ON gen_xref.asset_source_id = p_asset_source_id
           AND gen_xref.external_generation_id = resolved.external_generation_id
        LEFT JOIN public.pokemon_generation gen
            ON gen.id = gen_xref.pokemon_generation_id
        LEFT JOIN public.pokemon_generation byname_code
            ON byname_code.code = resolved.code
           AND gen_xref.pokemon_generation_id IS NULL
        LEFT JOIN public.pokemon_generation byname_ordinal
            ON byname_ordinal.ordinal_number = resolved.ordinal_number
           AND gen_xref.pokemon_generation_id IS NULL
    ),
    species_resolved AS (
        SELECT
            snap.external_species_id, snap.national_dex_number,
            snap.canonical_name, snap.generation_external_id,
            gen_xref.pokemon_generation_id AS existing_generation_id,
            (gen_new.external_generation_id IS NOT NULL) AS generation_is_valid_new
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'species', '[]'::JSONB))
            AS snap(external_species_id TEXT, national_dex_number INTEGER,
                    canonical_name TEXT, generation_external_id TEXT)
        LEFT JOIN public.pokemon_generation_external_reference gen_xref
            ON gen_xref.asset_source_id = p_asset_source_id
           AND gen_xref.external_generation_id = snap.generation_external_id
        LEFT JOIN generations_classified gen_new
            ON gen_new.external_generation_id = snap.generation_external_id
           AND gen_new.classification = 'NEW'
           AND gen_xref.pokemon_generation_id IS NULL
    ),
    species_classified AS (
        -- Species (Seção 9.3: chave natural = national_dex_number; campo
        -- estrutural adicional = generation_id, resolvido via referência
        -- existente OU via Generation NEW no mesmo snapshot — Fix 1).
        SELECT
            CASE
                WHEN sp_xref.pokemon_species_id IS NOT NULL THEN
                    CASE
                        WHEN sp.national_dex_number IS DISTINCT FROM resolved.national_dex_number THEN 'DIVERGENT'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM public.pokemon_generation_external_reference existing_gen_xref
                            WHERE existing_gen_xref.pokemon_generation_id = sp.generation_id
                              AND existing_gen_xref.asset_source_id = p_asset_source_id
                              AND existing_gen_xref.external_generation_id = resolved.generation_external_id
                        ) THEN 'DIVERGENT'
                        WHEN sp.canonical_name IS DISTINCT FROM resolved.canonical_name THEN 'UPDATE_NAME'
                        ELSE 'UNCHANGED'
                    END
                WHEN resolved.existing_generation_id IS NULL AND NOT resolved.generation_is_valid_new THEN 'DIVERGENT' -- Generation não resolvida (4.3)
                WHEN byndex.id IS NOT NULL THEN 'DIVERGENT'
                ELSE 'NEW'
            END AS classification
        FROM species_resolved resolved
        LEFT JOIN public.pokemon_species_external_reference sp_xref
            ON sp_xref.asset_source_id = p_asset_source_id
           AND sp_xref.external_species_id = resolved.external_species_id
        LEFT JOIN public.pokemon_species sp
            ON sp.id = sp_xref.pokemon_species_id
        LEFT JOIN public.pokemon_species byndex
            ON byndex.national_dex_number = resolved.national_dex_number
           AND sp_xref.pokemon_species_id IS NULL
    ),
    pokedex_classified AS (
        -- Pokedex National (Seção 9.3: objeto único; chave natural = code).
        SELECT
            CASE
                WHEN pd_xref.pokedex_id IS NOT NULL THEN
                    CASE
                        WHEN pd.code IS DISTINCT FROM snap.code THEN 'DIVERGENT'
                        WHEN pd.canonical_name IS DISTINCT FROM snap.canonical_name THEN 'UPDATE_NAME'
                        ELSE 'UNCHANGED'
                    END
                WHEN bycode.id IS NOT NULL THEN 'DIVERGENT'
                ELSE 'NEW'
            END AS classification
        FROM (
            SELECT
                p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id' AS external_pokedex_id,
                p_snapshot -> 'national_pokedex' ->> 'code' AS code,
                p_snapshot -> 'national_pokedex' ->> 'canonical_name' AS canonical_name
        ) snap
        LEFT JOIN public.pokedex_external_reference pd_xref
            ON pd_xref.asset_source_id = p_asset_source_id
           AND pd_xref.external_pokedex_id = snap.external_pokedex_id
        LEFT JOIN public.pokedex pd
            ON pd.id = pd_xref.pokedex_id
        LEFT JOIN public.pokedex bycode
            ON bycode.code = snap.code
           AND pd_xref.pokedex_id IS NULL
    ),
    positions_classified AS (
        -- Positions (Seção 9.4: reconciliação nos dois eixos UNIQUE).
        -- Pokedex/Species ainda não localmente presentes classificam NEW.
        SELECT
            CASE
                WHEN resolved.resolved_pokedex_id IS NULL OR resolved.resolved_species_id IS NULL THEN 'NEW'
                WHEN byspecies.id IS NOT NULL AND byspecies.position_number = resolved.position_number THEN 'UNCHANGED'
                WHEN byspecies.id IS NOT NULL AND byspecies.position_number <> resolved.position_number THEN 'DIVERGENT'
                WHEN bynumber.id IS NOT NULL THEN 'DIVERGENT'
                ELSE 'NEW'
            END AS classification
        FROM (
            SELECT
                snap.position_number,
                pd_xref.pokedex_id AS resolved_pokedex_id,
                sp_xref.pokemon_species_id AS resolved_species_id
            FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'national_pokedex_entries', '[]'::JSONB))
                AS snap(external_species_id TEXT, position_number INTEGER)
            LEFT JOIN public.pokedex_external_reference pd_xref
                ON pd_xref.asset_source_id = p_asset_source_id
               AND pd_xref.external_pokedex_id = (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id')
            LEFT JOIN public.pokemon_species_external_reference sp_xref
                ON sp_xref.asset_source_id = p_asset_source_id
               AND sp_xref.external_species_id = snap.external_species_id
        ) resolved
        LEFT JOIN public.pokedex_position byspecies
            ON byspecies.pokedex_id = resolved.resolved_pokedex_id
           AND byspecies.species_id = resolved.resolved_species_id
        LEFT JOIN public.pokedex_position bynumber
            ON bynumber.pokedex_id = resolved.resolved_pokedex_id
           AND bynumber.position_number = resolved.position_number
           AND resolved.resolved_pokedex_id IS NOT NULL
    )
    SELECT jsonb_build_object(
        'regions', (SELECT jsonb_build_object(
            'new', COUNT(*) FILTER (WHERE classification = 'NEW'),
            'unchanged', COUNT(*) FILTER (WHERE classification = 'UNCHANGED'),
            'update_name', COUNT(*) FILTER (WHERE classification = 'UPDATE_NAME'),
            'divergent', COUNT(*) FILTER (WHERE classification = 'DIVERGENT')
        ) FROM regions_classified),
        'generations', (SELECT jsonb_build_object(
            'new', COUNT(*) FILTER (WHERE classification = 'NEW'),
            'unchanged', COUNT(*) FILTER (WHERE classification = 'UNCHANGED'),
            'update_name', COUNT(*) FILTER (WHERE classification = 'UPDATE_NAME'),
            'divergent', COUNT(*) FILTER (WHERE classification = 'DIVERGENT')
        ) FROM generations_classified),
        'species', (SELECT jsonb_build_object(
            'new', COUNT(*) FILTER (WHERE classification = 'NEW'),
            'unchanged', COUNT(*) FILTER (WHERE classification = 'UNCHANGED'),
            'update_name', COUNT(*) FILTER (WHERE classification = 'UPDATE_NAME'),
            'divergent', COUNT(*) FILTER (WHERE classification = 'DIVERGENT')
        ) FROM species_classified),
        'pokedex', (SELECT jsonb_build_object(
            'new', COUNT(*) FILTER (WHERE classification = 'NEW'),
            'unchanged', COUNT(*) FILTER (WHERE classification = 'UNCHANGED'),
            'update_name', COUNT(*) FILTER (WHERE classification = 'UPDATE_NAME'),
            'divergent', COUNT(*) FILTER (WHERE classification = 'DIVERGENT')
        ) FROM pokedex_classified),
        'positions', (SELECT jsonb_build_object(
            'new', COUNT(*) FILTER (WHERE classification = 'NEW'),
            'unchanged', COUNT(*) FILTER (WHERE classification = 'UNCHANGED'),
            'update_name', 0,
            'divergent', COUNT(*) FILTER (WHERE classification = 'DIVERGENT')
        ) FROM positions_classified)
    );
$$;

COMMENT ON FUNCTION public.reconcile_pokemon_catalog_sourcing_snapshot(UUID, JSONB) IS
    'AUXILIAR interno (não é entrypoint) — classificação NEW/UNCHANGED/UPDATE_NAME/DIVERGENT por família, com suporte a lockstep de Initial Load (Region/Generation NEW resolvidas dentro do mesmo snapshot). LANGUAGE sql / cadeia de CTEs — seguro para múltiplas chamadas na mesma transação (sem TEMP TABLE). Ver docs/06a-pokemon-catalog-sourcing.md Seção 9. Chamado exclusivamente por PLAN (6104) e APPLY (6105). Sem GRANT EXECUTE a nenhum role. v2.0 — REVISION-01.';

REVOKE ALL ON FUNCTION public.reconcile_pokemon_catalog_sourcing_snapshot(UUID, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
