/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6104 - Create Plan Pokemon Catalog Sourcing Run Function
Versão......: 2.1 (PROPOSTA — GATE 3 STAGING, REVISION-02)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, materializando docs/06a-pokemon-catalog-
               sourcing.md v1.1, Seções 4, 5, 6, 8, 9; revisado em ...-
               STAGING-REVISION-01 (itens 3 e 4) e ...-STAGING-REVISION-02
               (item 1 — NO-GO residual))

REVISION-02 — o que mudou e por quê (item 1 do segundo GATE 4, NO-GO
residual restrito a 6104/6105/6820):

A REVISION-01 cobria 13 categorias de VALIDATION FAILURE, mas o GATE 4
identificou 5 lacunas que ainda deixavam um PLAN COMPLETED estruturalmente
inaplicável (só descoberto por um UNIQUE/NOT NULL/CHECK real durante o
APPLY, o que o item 1 da REVISION-02 proíbe explicitamente). Adicionadas
como itens 14-18 (ver lista consolidada abaixo):

14. REGION_CODE_INVALID — regions[].code nulo/vazio/fora do formato
    ^[A-Z][A-Z0-9_]*$ (mesmo CHECK físico de ck_pokemon_region_code_format,
    Query 6060).
15. GENERATION_CODE_INVALID — generations[].code nulo/vazio/fora do mesmo
    formato (ck_pokemon_generation_code_format, Query 6000).
16. NATURAL_KEY_DUPLICATE_IN_SNAPSHOT — colisão de chave natural DENTRO do
    próprio snapshot (não contra o catálogo existente, que já é papel de
    6106): Region.code, Generation.code, Generation.ordinal_number ou
    Species.national_dex_number duplicados entre duas linhas do mesmo
    payload.
17. SOURCE_URL_INVALID — source_url ausente ou não-HTTPS em Region/
    Generation/Species/National Pokédex. Ficou necessário nesta revisão
    porque 6105 (REVISION-01, item 8) passou a persistir source_url como
    evidência de origem — a ausência dessa evidência agora é um defeito de
    snapshot, não um detalhe permitido.
18. METADATA_INVALID — mesmo racional do item 17, para metadata: obrigatório
    e deve ser um objeto JSON (JSONB_TYPEOF = 'object'), nunca ausente/
    array/escalar.

Além disso, o item 13 (NON_POSITIVE_NUMBER) foi corrigido: a v2.0 comparava
apenas "<= 0", que em lógica de três valores do SQL deixa um campo NULL
passar sem ser pego (NULL <= 0 avalia para NULL, não TRUE, e a linha some do
WHERE) — agora inclui explicitamente "IS NULL OR <= 0".

REVISION-01 — o que mudou e por quê:

Item 4 (lifecycle/observabilidade de ACQUIRING): esta função DEIXA de fazer
a transição PENDING → ACQUIRING internamente. Essa transição agora só ocorre
via heartbeat_pokemon_catalog_sourcing_run() (Query 6107), chamada pelo
script ANTES de iniciar a aquisição HTTP — tornando o estado ACQUIRING real
e observável por outras sessões enquanto a aquisição está em andamento. PLAN
agora EXIGE status atual = ACQUIRING como precondição (antes exigia PENDING)
e só executa a transição ACQUIRING → PLANNING.

Item 3 (SNAPSHOT VALIDATION): a v1.0 só validava 2 casos (canonical_name
vazio; S≠P). O GATE 4 apontou que isso era insuficiente para provar que um
PLAN COMPLETED é confiável, e listou 13 categorias adicionais de rejeição
estrutural obrigatória, todas adicionadas nesta revisão, na ordem abaixo
(cada uma produz um error_summary com um código dedicado, todas usam o mesmo
padrão RETURN-não-RAISE já aprovado para VALIDATION FAILURE — Seção
"PLANO/RETURN" da auditoria):

 1. MISSING_OR_EMPTY_FAMILY — regions[]/generations[]/species[]/national_
    pokedex_entries[] ausentes, de tipo errado ou vazios; national_pokedex
    ausente ou não é objeto.
 2. EXTERNAL_ID_INVALID — external_region_id/external_generation_id/
    external_species_id/external_pokedex_id/entries.external_species_id
    nulos, vazios ou não numéricos (PokéAPI usa IDs numéricos em TEXT).
 3. EXTERNAL_ID_DUPLICATE — external id duplicado dentro de regions[],
    generations[] ou species[].
 4. ENTRY_SPECIES_ID_DUPLICATE — external_species_id duplicado dentro de
    national_pokedex_entries[].
 5. POSITION_NUMBER_DUPLICATE — position_number duplicado dentro de
    national_pokedex_entries[].
 6. CANONICAL_NAME_BLANK — inalterado da v1.0 (Seção 4.0).
 7. SP_MISMATCH — inalterado da v1.0 (S≠P, Seção 4.3).
 8. NDEX_POSITION_MISMATCH — para cada Species, national_dex_number deve ser
    igual ao position_number da entry correspondente (mesmo
    external_species_id) — a AUTORIDADE de ambos os campos é a mesma fonte
    (/pokedex/national.pokemon_entries[].entry_number, Seção 4.3), logo eles
    nunca podem divergir em um snapshot bem formado.
 9. NATIONAL_POKEDEX_EXTERNAL_ID_INVALID — national_pokedex.external_
    pokedex_id deve ser exatamente "1" (id estável do recurso Pokédex
    Nacional na PokéAPI).
10. NATIONAL_POKEDEX_CODE_INVALID — national_pokedex.code deve ser
    exatamente "NATIONAL".
11. GENERATION_MAIN_REGION_UNRESOLVED — toda generations[].main_region_
    external_id deve aparecer em regions[] do MESMO snapshot OU já existir
    como referência externa (Seção 4.2). Distinto do DIVERGENT de 6106: este
    check pega o caso mais grave de "o ID não aparece em lugar nenhum"
    (payload malformado); 6106 ainda cobre, à parte, o caso de o ID aparecer
    mas apontar para uma Region que não pôde ser efetivamente criada/mapeada
    (colisão de chave natural cascateando em DIVERGENT).
12. SPECIES_GENERATION_UNRESOLVED — mesmo racional do item 11, para
    species[].generation_external_id vs. generations[] (Seção 4.3).
13. NON_POSITIVE_NUMBER — ordinal_number, national_dex_number e
    position_number devem ser > 0 em todo o snapshot.

O cross-check nacional (PokemonSpecies.pokedex_numbers[national] vs.
/pokedex/national) CONTINUA sendo responsabilidade exclusiva do script Deno,
ANTES da construção do snapshot — nenhuma checagem aqui finge provar algo que
não está representado no JSON recebido (exigência explícita do GATE 4).

Regras de Negócio (inalteradas da v1.0, ver header original para detalhe):
VALIDATION FAILURE estrutural fecha FAILED via RETURN (commit, preserva
auditoria); erros de chamada inválida (run não encontrado/tipo errado/status
errado/snapshot malformado) usam RAISE EXCEPTION (rollback total); DIVERGENT
por família é resultado válido (COMPLETED_WITH_DIVERGENCES); nenhuma escrita
canônica ocorre aqui.

SECURITY DEFINER + SET search_path = ''. SERVICE_ROLE ONLY.

Pré-requisitos:
- Query 6100/6101 v1.1 - Pokemon Catalog Sourcing Run (lifecycle run_type-
  aware).
- Query 6102 - Snapshot Hash Function.
- Query 6106 v2.0 - Reconcile Snapshot Function (AUXILIAR, lockstep).
- Query 6107 - Heartbeat Function (nova precondição: run deve chegar aqui já
  em ACQUIRING).
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.plan_pokemon_catalog_sourcing_run(
    p_run_id UUID,
    p_snapshot JSONB
)
RETURNS TABLE (
    outcome TEXT,
    run_id UUID,
    status TEXT,
    snapshot_hash TEXT,
    plan_summary JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_run public.pokemon_catalog_sourcing_run%ROWTYPE;
    v_hash TEXT;
    v_payload_count INTEGER;
    v_count INTEGER;
    v_error TEXT := NULL;
    v_plan_summary JSONB;
    v_any_divergent BOOLEAN;
    v_final_status TEXT;
BEGIN
    SELECT * INTO v_run
    FROM public.pokemon_catalog_sourcing_run
    WHERE id = p_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PLAN_POKEMON_CATALOG_SOURCING_RUN_NOT_FOUND: run % não encontrado.', p_run_id;
    END IF;
    IF v_run.run_type <> 'DRY_RUN' THEN
        RAISE EXCEPTION 'PLAN_POKEMON_CATALOG_SOURCING_RUN_WRONG_TYPE: PLAN só se aplica a runs DRY_RUN (run % é %).', p_run_id, v_run.run_type;
    END IF;
    IF v_run.status <> 'ACQUIRING' THEN
        RAISE EXCEPTION 'PLAN_POKEMON_CATALOG_SOURCING_RUN_INVALID_STATUS: run % está em % (esperado ACQUIRING -- chame heartbeat_pokemon_catalog_sourcing_run() antes de iniciar a aquisição).', p_run_id, v_run.status;
    END IF;
    IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot) <> 'object' THEN
        RAISE EXCEPTION 'PLAN_POKEMON_CATALOG_SOURCING_RUN_INVALID_SNAPSHOT: snapshot deve ser um objeto JSON.';
    END IF;

    -- Transição ACQUIRING -> PLANNING (Seção 7.1). A transição PENDING ->
    -- ACQUIRING já ocorreu, de forma durável, via heartbeat (Query 6107).
    UPDATE public.pokemon_catalog_sourcing_run SET status = 'PLANNING' WHERE id = p_run_id;

    -- ============= 1/18: MISSING_OR_EMPTY_FAMILY ============================
    IF NOT (p_snapshot ? 'regions') OR jsonb_typeof(p_snapshot -> 'regions') <> 'array' OR jsonb_array_length(p_snapshot -> 'regions') = 0 THEN
        v_error := 'MISSING_OR_EMPTY_FAMILY: regions[] ausente, de tipo errado ou vazio.';
    ELSIF NOT (p_snapshot ? 'generations') OR jsonb_typeof(p_snapshot -> 'generations') <> 'array' OR jsonb_array_length(p_snapshot -> 'generations') = 0 THEN
        v_error := 'MISSING_OR_EMPTY_FAMILY: generations[] ausente, de tipo errado ou vazio.';
    ELSIF NOT (p_snapshot ? 'species') OR jsonb_typeof(p_snapshot -> 'species') <> 'array' OR jsonb_array_length(p_snapshot -> 'species') = 0 THEN
        v_error := 'MISSING_OR_EMPTY_FAMILY: species[] ausente, de tipo errado ou vazio.';
    ELSIF NOT (p_snapshot ? 'national_pokedex') OR jsonb_typeof(p_snapshot -> 'national_pokedex') <> 'object' THEN
        v_error := 'MISSING_OR_EMPTY_FAMILY: national_pokedex ausente ou não é objeto.';
    ELSIF NOT (p_snapshot ? 'national_pokedex_entries') OR jsonb_typeof(p_snapshot -> 'national_pokedex_entries') <> 'array' OR jsonb_array_length(p_snapshot -> 'national_pokedex_entries') = 0 THEN
        v_error := 'MISSING_OR_EMPTY_FAMILY: national_pokedex_entries[] ausente, de tipo errado ou vazio.';
    END IF;

    -- Payload guard (Seção 5.1) — só é seguro calcular agora que o shape
    -- básico (arrays de fato arrays) foi confirmado acima.
    IF v_error IS NULL THEN
        v_payload_count := jsonb_array_length(p_snapshot -> 'regions')
            + jsonb_array_length(p_snapshot -> 'generations')
            + jsonb_array_length(p_snapshot -> 'species')
            + jsonb_array_length(p_snapshot -> 'national_pokedex_entries')
            + 1;
        IF v_payload_count > 25000 THEN
            v_hash := public.compute_pokemon_catalog_sourcing_snapshot_hash(p_snapshot);
            UPDATE public.pokemon_catalog_sourcing_run
            SET status = 'FAILED',
                snapshot_hash = v_hash,
                error_summary = FORMAT('PAYLOAD_GUARD_EXCEEDED: %s > 25000', v_payload_count),
                finished_at = NOW()
            WHERE id = p_run_id;
            RETURN QUERY SELECT 'PAYLOAD_GUARD_EXCEEDED'::TEXT, p_run_id, 'FAILED'::TEXT, v_hash, NULL::JSONB;
            RETURN;
        END IF;
    END IF;

    -- Hash determinístico (Seção 6) — calculado após o shape básico ser
    -- confirmado seguro para serialização (na prática, ::text funciona para
    -- qualquer JSONB válido; mantido aqui para preservar a ordem "hash
    -- disponível para toda gravação de FAILED a partir deste ponto").
    v_hash := public.compute_pokemon_catalog_sourcing_snapshot_hash(p_snapshot);

    -- ============= 2/18: EXTERNAL_ID_INVALID =================================
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM (
            SELECT external_region_id AS eid FROM jsonb_to_recordset(p_snapshot -> 'regions') AS x(external_region_id TEXT)
            UNION ALL
            SELECT external_generation_id FROM jsonb_to_recordset(p_snapshot -> 'generations') AS x(external_generation_id TEXT)
            UNION ALL
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'species') AS x(external_species_id TEXT)
            UNION ALL
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'national_pokedex_entries') AS x(external_species_id TEXT)
            UNION ALL
            SELECT (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id')
        ) ids
        WHERE eid IS NULL OR BTRIM(eid) = '' OR eid !~ '^[0-9]+$';
        IF v_count > 0 THEN
            v_error := FORMAT('EXTERNAL_ID_INVALID: %s external id(s) nulo(s), vazio(s) ou não-numérico(s).', v_count);
        END IF;
    END IF;

    -- ============= 3/18: EXTERNAL_ID_DUPLICATE ==============================
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT external_region_id FROM jsonb_to_recordset(p_snapshot -> 'regions') AS x(external_region_id TEXT)
            GROUP BY external_region_id HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'EXTERNAL_ID_DUPLICATE: regions[].external_region_id duplicado.'; END IF;
    END IF;
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT external_generation_id FROM jsonb_to_recordset(p_snapshot -> 'generations') AS x(external_generation_id TEXT)
            GROUP BY external_generation_id HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'EXTERNAL_ID_DUPLICATE: generations[].external_generation_id duplicado.'; END IF;
    END IF;
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'species') AS x(external_species_id TEXT)
            GROUP BY external_species_id HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'EXTERNAL_ID_DUPLICATE: species[].external_species_id duplicado.'; END IF;
    END IF;

    -- ============= 4/18: ENTRY_SPECIES_ID_DUPLICATE =========================
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'national_pokedex_entries') AS x(external_species_id TEXT)
            GROUP BY external_species_id HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'ENTRY_SPECIES_ID_DUPLICATE: national_pokedex_entries[].external_species_id duplicado.'; END IF;
    END IF;

    -- ============= 5/18: POSITION_NUMBER_DUPLICATE ==========================
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT position_number FROM jsonb_to_recordset(p_snapshot -> 'national_pokedex_entries') AS x(position_number INTEGER)
            GROUP BY position_number HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'POSITION_NUMBER_DUPLICATE: national_pokedex_entries[].position_number duplicado.'; END IF;
    END IF;

    -- ============= 6/18: CANONICAL_NAME_BLANK (Seção 4.0, inalterado) ======
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM (
            SELECT canonical_name FROM jsonb_to_recordset(p_snapshot -> 'regions') AS r(canonical_name TEXT)
            UNION ALL
            SELECT canonical_name FROM jsonb_to_recordset(p_snapshot -> 'generations') AS g(canonical_name TEXT)
            UNION ALL
            SELECT canonical_name FROM jsonb_to_recordset(p_snapshot -> 'species') AS s(canonical_name TEXT)
            UNION ALL
            SELECT (p_snapshot -> 'national_pokedex' ->> 'canonical_name')
        ) names
        WHERE canonical_name IS NULL OR BTRIM(canonical_name) = '';
        IF v_count > 0 THEN v_error := 'CANONICAL_NAME_BLANK: canonical_name ausente/vazio em uma ou mais famílias (Seção 4.0).'; END IF;
    END IF;

    -- ============= 7/18: SP_MISMATCH (S=P, Seção 4.3, inalterado) ==========
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM (
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'species') AS s(external_species_id TEXT)
            UNION
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'national_pokedex_entries') AS e(external_species_id TEXT)
        ) all_ids
        WHERE external_species_id NOT IN (
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'species') AS s2(external_species_id TEXT)
            INTERSECT
            SELECT external_species_id FROM jsonb_to_recordset(p_snapshot -> 'national_pokedex_entries') AS e2(external_species_id TEXT)
        );
        IF v_count > 0 THEN v_error := FORMAT('SP_MISMATCH: %s divergente(s) entre species[] e national_pokedex_entries[] (Seção 4.3).', v_count); END IF;
    END IF;

    -- ============= 8/18: NDEX_POSITION_MISMATCH =============================
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM jsonb_to_recordset(p_snapshot -> 'species') AS s(external_species_id TEXT, national_dex_number INTEGER)
        JOIN jsonb_to_recordset(p_snapshot -> 'national_pokedex_entries') AS e(external_species_id TEXT, position_number INTEGER)
            ON e.external_species_id = s.external_species_id
        WHERE s.national_dex_number IS DISTINCT FROM e.position_number;
        IF v_count > 0 THEN v_error := FORMAT('NDEX_POSITION_MISMATCH: %s Species com national_dex_number <> position_number da entry correspondente.', v_count); END IF;
    END IF;

    -- ============= 9/18 e 10/18: NATIONAL_POKEDEX fixed values ==============
    IF v_error IS NULL AND (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id') IS DISTINCT FROM '1' THEN
        v_error := FORMAT('NATIONAL_POKEDEX_EXTERNAL_ID_INVALID: esperado "1", recebido "%s".', (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id'));
    END IF;
    IF v_error IS NULL AND (p_snapshot -> 'national_pokedex' ->> 'code') IS DISTINCT FROM 'NATIONAL' THEN
        v_error := FORMAT('NATIONAL_POKEDEX_CODE_INVALID: esperado "NATIONAL", recebido "%s".', (p_snapshot -> 'national_pokedex' ->> 'code'));
    END IF;

    -- ============= 11/18: GENERATION_MAIN_REGION_UNRESOLVED =================
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM jsonb_to_recordset(p_snapshot -> 'generations') AS g(main_region_external_id TEXT)
        WHERE NOT EXISTS (
            SELECT 1 FROM jsonb_to_recordset(p_snapshot -> 'regions') AS r(external_region_id TEXT)
            WHERE r.external_region_id = g.main_region_external_id
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.pokemon_region_external_reference xref
            WHERE xref.asset_source_id = v_run.asset_source_id
              AND xref.external_region_id = g.main_region_external_id
        );
        IF v_count > 0 THEN v_error := FORMAT('GENERATION_MAIN_REGION_UNRESOLVED: %s generation(s) com main_region_external_id inexistente em regions[] e sem referência externa já existente (Seção 4.2).', v_count); END IF;
    END IF;

    -- ============= 12/18: SPECIES_GENERATION_UNRESOLVED =====================
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM jsonb_to_recordset(p_snapshot -> 'species') AS s(generation_external_id TEXT)
        WHERE NOT EXISTS (
            SELECT 1 FROM jsonb_to_recordset(p_snapshot -> 'generations') AS g(external_generation_id TEXT)
            WHERE g.external_generation_id = s.generation_external_id
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.pokemon_generation_external_reference xref
            WHERE xref.asset_source_id = v_run.asset_source_id
              AND xref.external_generation_id = s.generation_external_id
        );
        IF v_count > 0 THEN v_error := FORMAT('SPECIES_GENERATION_UNRESOLVED: %s species com generation_external_id inexistente em generations[] e sem referência externa já existente (Seção 4.3).', v_count); END IF;
    END IF;

    -- ============= 13/18: NON_POSITIVE_NUMBER =================================
    -- REVISION-02 (item 1 do GATE 4): a v2.0 comparava apenas "<= 0", o que em
    -- SQL de três valores deixa NULL passar incólume (NULL <= 0 é NULL, não
    -- TRUE, logo a linha some do WHERE). Corrigido para IS NULL OR <= 0 nos
    -- três campos numéricos de negócio do snapshot.
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM jsonb_to_recordset(p_snapshot -> 'generations') AS g(ordinal_number INTEGER) WHERE ordinal_number IS NULL OR ordinal_number <= 0;
        IF v_count > 0 THEN v_error := 'NON_POSITIVE_NUMBER: generations[].ordinal_number nulo ou <= 0.'; END IF;
    END IF;
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM jsonb_to_recordset(p_snapshot -> 'species') AS s(national_dex_number INTEGER) WHERE national_dex_number IS NULL OR national_dex_number <= 0;
        IF v_count > 0 THEN v_error := 'NON_POSITIVE_NUMBER: species[].national_dex_number nulo ou <= 0.'; END IF;
    END IF;
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM jsonb_to_recordset(p_snapshot -> 'national_pokedex_entries') AS e(position_number INTEGER) WHERE position_number IS NULL OR position_number <= 0;
        IF v_count > 0 THEN v_error := 'NON_POSITIVE_NUMBER: national_pokedex_entries[].position_number nulo ou <= 0.'; END IF;
    END IF;

    -- ============= 14/18: REGION_CODE_INVALID (NOVO REVISION-02) =============
    -- Replica o CHECK físico ck_pokemon_region_code_format (Query 6060):
    -- '^[A-Z][A-Z0-9_]*$'. Sem isso, um code inválido só seria descoberto
    -- durante o INSERT do APPLY (item 1 do GATE 4 REVISION-02: todo PLAN
    -- COMPLETED deve ser estruturalmente aplicável).
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM jsonb_to_recordset(p_snapshot -> 'regions') AS r(code TEXT)
        WHERE code IS NULL OR BTRIM(code) = '' OR code !~ '^[A-Z][A-Z0-9_]*$';
        IF v_count > 0 THEN v_error := FORMAT('REGION_CODE_INVALID: %s regions[].code nulo(s), vazio(s) ou fora do formato ^[A-Z][A-Z0-9_]*$.', v_count); END IF;
    END IF;

    -- ============= 15/18: GENERATION_CODE_INVALID (NOVO REVISION-02) =========
    -- Replica o CHECK físico ck_pokemon_generation_code_format (Query 6000):
    -- mesmo formato ^[A-Z][A-Z0-9_]*$.
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM jsonb_to_recordset(p_snapshot -> 'generations') AS g(code TEXT)
        WHERE code IS NULL OR BTRIM(code) = '' OR code !~ '^[A-Z][A-Z0-9_]*$';
        IF v_count > 0 THEN v_error := FORMAT('GENERATION_CODE_INVALID: %s generations[].code nulo(s), vazio(s) ou fora do formato ^[A-Z][A-Z0-9_]*$.', v_count); END IF;
    END IF;

    -- ============= 16/18: NATURAL_KEY_DUPLICATE_IN_SNAPSHOT (NOVO REVISION-02)
    -- Distinto de EXTERNAL_ID_DUPLICATE (item 3, que checa a identidade
    -- externa): aqui a checagem é sobre as CHAVES NATURAIS que a Seção 9/6106
    -- usa para casar com o catálogo já existente. Duas linhas do MESMO
    -- snapshot competindo pela mesma chave natural (Region.code,
    -- Generation.code, Generation.ordinal_number ou Species.national_dex_
    -- number) não é um caso que 6106 resolve sozinho — é payload malformado.
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT code FROM jsonb_to_recordset(p_snapshot -> 'regions') AS x(code TEXT)
            GROUP BY code HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'NATURAL_KEY_DUPLICATE_IN_SNAPSHOT: regions[].code duplicado no próprio snapshot.'; END IF;
    END IF;
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT code FROM jsonb_to_recordset(p_snapshot -> 'generations') AS x(code TEXT)
            GROUP BY code HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'NATURAL_KEY_DUPLICATE_IN_SNAPSHOT: generations[].code duplicado no próprio snapshot.'; END IF;
    END IF;
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT ordinal_number FROM jsonb_to_recordset(p_snapshot -> 'generations') AS x(ordinal_number INTEGER)
            GROUP BY ordinal_number HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'NATURAL_KEY_DUPLICATE_IN_SNAPSHOT: generations[].ordinal_number duplicado no próprio snapshot.'; END IF;
    END IF;
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count FROM (
            SELECT national_dex_number FROM jsonb_to_recordset(p_snapshot -> 'species') AS x(national_dex_number INTEGER)
            GROUP BY national_dex_number HAVING COUNT(*) > 1
        ) dups;
        IF v_count > 0 THEN v_error := 'NATURAL_KEY_DUPLICATE_IN_SNAPSHOT: species[].national_dex_number duplicado no próprio snapshot.'; END IF;
    END IF;

    -- ============= 17/18: SOURCE_URL_INVALID (NOVO REVISION-02) ==============
    -- Item 2 do GATE 4 REVISION-02: como 6105 agora persiste source_url/
    -- metadata como evidência de origem (item 8 da REVISION-01), a ausência
    -- ou malformação dessa evidência deve ser um VALIDATION FAILURE de PLAN,
    -- não uma falha descoberta no meio da escrita do APPLY. Mesmo formato do
    -- CHECK físico ck_..._source_url das quatro tabelas de external_reference
    -- (source_url IS NULL OR (não-vazio E começa com https://)) — mas aqui
    -- source_url é OBRIGATÓRIO (não pode ser NULL) para o snapshot de
    -- sourcing, mais estrito que o CHECK físico genérico.
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM (
            SELECT source_url FROM jsonb_to_recordset(p_snapshot -> 'regions') AS r(source_url TEXT)
            UNION ALL
            SELECT source_url FROM jsonb_to_recordset(p_snapshot -> 'generations') AS g(source_url TEXT)
            UNION ALL
            SELECT source_url FROM jsonb_to_recordset(p_snapshot -> 'species') AS s(source_url TEXT)
            UNION ALL
            SELECT (p_snapshot -> 'national_pokedex' ->> 'source_url')
        ) urls
        WHERE source_url IS NULL OR BTRIM(source_url) = '' OR source_url !~ '^https://';
        IF v_count > 0 THEN v_error := FORMAT('SOURCE_URL_INVALID: %s source_url ausente(s) ou não-HTTPS em Region/Generation/Species/National Pokédex.', v_count); END IF;
    END IF;

    -- ============= 18/18: METADATA_INVALID (NOVO REVISION-02) ================
    -- Mesmo racional do item 17, para metadata: obrigatório e deve ser um
    -- objeto JSON (nunca array/escalar/ausente) — mesmo formato do CHECK
    -- físico ck_..._metadata (JSONB_TYPEOF(metadata) = 'object'), mas aqui
    -- metadata é OBRIGATÓRIO no snapshot (o CHECK físico é satisfeito por um
    -- DEFAULT '{}'::JSONB que só se aplica quando a coluna já tem valor —
    -- não protege contra a CHAVE estar ausente no JSON de entrada).
    IF v_error IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM (
            SELECT r.entry AS entry FROM jsonb_array_elements(p_snapshot -> 'regions') AS r(entry)
            UNION ALL
            SELECT g.entry FROM jsonb_array_elements(p_snapshot -> 'generations') AS g(entry)
            UNION ALL
            SELECT s.entry FROM jsonb_array_elements(p_snapshot -> 'species') AS s(entry)
            UNION ALL
            SELECT (p_snapshot -> 'national_pokedex')
        ) rows_
        WHERE NOT (rows_.entry ? 'metadata') OR jsonb_typeof(rows_.entry -> 'metadata') <> 'object';
        IF v_count > 0 THEN v_error := FORMAT('METADATA_INVALID: %s metadata ausente(s) ou não-objeto em Region/Generation/Species/National Pokédex.', v_count); END IF;
    END IF;

    -- ============= Desfecho de VALIDATION FAILURE ============================
    IF v_error IS NOT NULL THEN
        UPDATE public.pokemon_catalog_sourcing_run
        SET status = 'FAILED',
            snapshot_hash = v_hash,
            error_summary = 'VALIDATION_FAILURE: ' || v_error,
            finished_at = NOW()
        WHERE id = p_run_id;
        RETURN QUERY SELECT 'VALIDATION_FAILURE'::TEXT, p_run_id, 'FAILED'::TEXT, v_hash, NULL::JSONB;
        RETURN;
    END IF;

    -- Reconciliação por família (Seção 9), somente leitura, via helper 6106
    -- (v2.0 — lockstep de Initial Load + eixos independentes de Generation).
    v_plan_summary := public.reconcile_pokemon_catalog_sourcing_snapshot(v_run.asset_source_id, p_snapshot);

    v_any_divergent := (
        (v_plan_summary -> 'regions' ->> 'divergent')::INT > 0
        OR (v_plan_summary -> 'generations' ->> 'divergent')::INT > 0
        OR (v_plan_summary -> 'species' ->> 'divergent')::INT > 0
        OR (v_plan_summary -> 'pokedex' ->> 'divergent')::INT > 0
        OR (v_plan_summary -> 'positions' ->> 'divergent')::INT > 0
    );

    v_final_status := CASE WHEN v_any_divergent THEN 'COMPLETED_WITH_DIVERGENCES' ELSE 'COMPLETED' END;

    UPDATE public.pokemon_catalog_sourcing_run
    SET status = v_final_status,
        snapshot_hash = v_hash,
        plan_summary = v_plan_summary,
        finished_at = NOW()
    WHERE id = p_run_id;

    RETURN QUERY SELECT v_final_status::TEXT, p_run_id, v_final_status, v_hash, v_plan_summary;
END;
$$;

COMMENT ON FUNCTION public.plan_pokemon_catalog_sourcing_run(UUID, JSONB) IS
    'PLAN do fluxo DRY_RUN — exige status ACQUIRING (iniciado via 6107), 18 categorias de validação estrutural (todo PLAN COMPLETED deve ser estruturalmente aplicável), hash e reconciliação read-only por família. Ver docs/06a-pokemon-catalog-sourcing.md Seções 4/5/6/8/9. SERVICE_ROLE ONLY. v2.1 — REVISION-02.';

REVOKE ALL ON FUNCTION public.plan_pokemon_catalog_sourcing_run(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.plan_pokemon_catalog_sourcing_run(UUID, JSONB)
    TO service_role;

COMMIT;
