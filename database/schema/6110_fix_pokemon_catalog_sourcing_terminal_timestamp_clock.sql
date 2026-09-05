/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6110 - Fix Pokemon Catalog Sourcing Terminal Timestamp Clock
               (HOTFIX incremental sobre 6104/6105/6108 — NÃO reescreve/
               substitui o histórico já executado dessas três migrations)
Versão......: 1.0 (PROPOSTA — GATE 5 HOTFIX STAGING)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-GATE-5-HOTFIX-
               6110-STAGING-01, após a execução real de 6820 v2.2 pós-6109
               ter revelado um segundo defeito de runtime — desta vez em
               6104/6105/6108, não em 6103/6109; aplicado em 2026-09-04 via POKEMON-CATALOG-SOURCING-GATE-5-HOTFIX-6110-IMPLEMENTATION-01)

CONTEXTO DO HOTFIX — o que aconteceu e por quê:
Após aplicar o hotfix 6109 (que corrigiu o RETURNING ambíguo de 6103), a
reexecução completa de 6820 v2.2 avançou até a Seção 9 e abortou com:

    ERROR: 23514: new row for relation "pokemon_catalog_sourcing_run"
           violates check constraint "ck_pokemon_catalog_sourcing_run_period"
    DETAIL: Failing row contains (..., started_at=2026-09-04 23:58:07.340718,
            finished_at=2026-09-04 23:58:07.267658, ...)

A CHECK `ck_pokemon_catalog_sourcing_run_period` exige:
    finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at

Causa raiz: o trigger `govern_pokemon_catalog_sourcing_run` (Query 6101)
preenche `started_at` (na transição para ACQUIRING/APPLYING) e `finished_at`
(quando o status vira terminal, via `COALESCE(NEW.finished_at,
CLOCK_TIMESTAMP())`) usando `CLOCK_TIMESTAMP()` — hora real, que avança a
cada instrução da transação. Mas `plan_pokemon_catalog_sourcing_run` (6104),
`apply_pokemon_catalog_sourcing_run` (6105) e
`close_failed_pokemon_catalog_sourcing_run` (6108) fecham o run com
`finished_at = NOW()` explícito — e `NOW()` é o timestamp de INÍCIO da
transação (congelado desde o BEGIN), não a hora real do momento do closeout.
Em qualquer transação que já vem executando há um tempo real não-trivial
antes de chegar ao closeout (como o próprio 6820, um script longo com
dezenas de instruções), `started_at` (CLOCK_TIMESTAMP(), hora real, mais
tarde) pode facilmente ficar À FRENTE de `finished_at` (NOW(), hora de início
da transação, mais cedo) — violando a CHECK. Isso não é um problema
hipotético isolado do fixture de teste do 6820: as mesmas três funções de
produção (6104/6105/6108) têm exatamente o mesmo padrão `finished_at =
NOW()`, então o mesmo defeito se manifestaria em qualquer chamada real dessas
RPCs dentro de uma transação/sessão de longa duração — inclusive
funcionalmente no APPLY real (6105), como apontado pelo achado que originou
esta rodada.

O QUE ESTE HOTFIX FAZ — e o que NÃO faz:
Esta migration NÃO edita nem substitui os arquivos 6104/6105/6108 já
executados (seus históricos de migration permanecem intocados). Ela aplica
três `CREATE OR REPLACE FUNCTION`, um por função, sobre as MESMAS assinaturas
já aplicadas — `plan_pokemon_catalog_sourcing_run(UUID, JSONB)`,
`apply_pokemon_catalog_sourcing_run(UUID, JSONB)`,
`close_failed_pokemon_catalog_sourcing_run(UUID, TEXT)` — preservando
integralmente: lifecycle; máquina de status; hash; as 18 categorias de
validação estrutural de PLAN; protocolo de locks e reconciliação de APPLY
(fases (a)/(b)/(c)); postconditions (comparação direta + reconciliação final
100%% UNCHANGED); `apply_summary` (fonte em `v_fresh`, REVISION-02 já
preservada); sanitização de `error_summary` em 6108; assinaturas; `SECURITY
DEFINER`; `SET search_path = ''`; grants/revokes idênticos; comentários
funcionais (com uma frase adicionada em cada um só para registrar a
correção).

ÚNICA alteração funcional: TODA atribuição explícita de `finished_at =
NOW()` nessas três funções passa a ser `finished_at = CLOCK_TIMESTAMP()` —
5 ocorrências ao todo: 3 em `plan_pokemon_catalog_sourcing_run` (guard de
payload >25000; VALIDATION FAILURE; desfecho COMPLETED/
COMPLETED_WITH_DIVERGENCES), 1 em `apply_pokemon_catalog_sourcing_run`
(COMPLETED), 1 em `close_failed_pokemon_catalog_sourcing_run` (desfecho
FAILED). Nenhuma outra linha de nenhuma das três funções foi alterada.
Alinha o comportamento de
`finished_at` com o de `started_at` (ambos hora real, nunca hora de início
de transação), tornando a CHECK `ck_pokemon_catalog_sourcing_run_period`
estruturalmente impossível de violar por essas três funções, independente de
quão longa seja a transação/sessão que as chama.

FORA DE ESCOPO (explicitamente, por instrução): `open_pokemon_catalog_
sourcing_run` (6103/6109) também possui uma atribuição `finished_at = NOW()`
(no Passo 0, reconciliação de stale recovery) com o mesmo padrão — mas esta
rodada NÃO altera 6103/6109. Fica registrado aqui como um achado residual
conhecido, não corrigido nesta rodada, para decisão em rodada futura caso
necessário.

Precedente do mesmo padrão de correção incremental já usado neste projeto:
`6109` (rodada imediatamente anterior desta mesma proposta), `3944b`,
`5035`/`5036`.

Pré-requisitos:
- Query 6100/6101 v1.1 - Pokemon Catalog Sourcing Run (tabela + triggers,
  incluindo a CHECK ck_pokemon_catalog_sourcing_run_period e o uso de
  CLOCK_TIMESTAMP() em started_at/finished_at pelo trigger de governança).
- Query 6104 v2.1 - Plan Function (CONFIRMADO EXECUTADO no banco real — este
  hotfix depende do objeto já existir para fazer CREATE OR REPLACE).
- Query 6105 v2.1 - Apply Function (idem).
- Query 6108 v1.0 - Close Failed Function (idem).
- Query 6106 v2.0 - Reconcile Snapshot Function (chamada por 6104/6105,
  inalterada).
===============================================================================
*/

BEGIN;

-- =============================================================================
-- 1/3: plan_pokemon_catalog_sourcing_run(UUID, JSONB)
-- Única mudança: as 3 ocorrências de `finished_at = NOW()` (guard de payload,
-- VALIDATION FAILURE, desfecho COMPLETED/COMPLETED_WITH_DIVERGENCES) passam a
-- `finished_at = CLOCK_TIMESTAMP()`. Todo o restante é byte-idêntico a 6104.
-- =============================================================================

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
                finished_at = CLOCK_TIMESTAMP()
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
            finished_at = CLOCK_TIMESTAMP()
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
        finished_at = CLOCK_TIMESTAMP()
    WHERE id = p_run_id;

    RETURN QUERY SELECT v_final_status::TEXT, p_run_id, v_final_status, v_hash, v_plan_summary;
END;
$$;

COMMENT ON FUNCTION public.plan_pokemon_catalog_sourcing_run(UUID, JSONB) IS
    'PLAN do fluxo DRY_RUN — exige status ACQUIRING (iniciado via 6107), 18 categorias de validação estrutural (todo PLAN COMPLETED deve ser estruturalmente aplicável), hash e reconciliação read-only por família. Ver docs/06a-pokemon-catalog-sourcing.md Seções 4/5/6/8/9. SERVICE_ROLE ONLY. v2.1 — REVISION-02. (6110: finished_at via CLOCK_TIMESTAMP(), corrige ck_pokemon_catalog_sourcing_run_period — mesmo contrato de 6104.)';

REVOKE ALL ON FUNCTION public.plan_pokemon_catalog_sourcing_run(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.plan_pokemon_catalog_sourcing_run(UUID, JSONB)
    TO service_role;

-- =============================================================================
-- 2/3: apply_pokemon_catalog_sourcing_run(UUID, JSONB)
-- Única mudança: a 1 ocorrência de `finished_at = NOW()` (desfecho COMPLETED)
-- passa a `finished_at = CLOCK_TIMESTAMP()`. Todo o restante é byte-idêntico
-- a 6105 (protocolo de locks, fases (a)/(b)/(c), postconditions, apply_summary
-- vindo de v_fresh — REVISION-02 preservada integralmente).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.apply_pokemon_catalog_sourcing_run(
    p_run_id UUID,
    p_snapshot JSONB
)
RETURNS TABLE (
    outcome TEXT,
    run_id UUID,
    status TEXT,
    apply_summary JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_run public.pokemon_catalog_sourcing_run%ROWTYPE;
    v_preflight public.pokemon_catalog_sourcing_run%ROWTYPE;
    v_asset_source public.asset_source%ROWTYPE;
    v_hash TEXT;
    v_pre_fresh JSONB;
    v_fresh JSONB;
    v_post JSONB;
    v_regions_ins INTEGER := 0;
    v_regions_upd INTEGER := 0;
    v_generations_ins INTEGER := 0;
    v_generations_upd INTEGER := 0;
    v_species_ins INTEGER := 0;
    v_species_upd INTEGER := 0;
    v_pokedex_ins INTEGER := 0;
    v_pokedex_upd INTEGER := 0;
    v_positions_ins INTEGER := 0;
    v_apply_summary JSONB;
BEGIN
    SELECT * INTO v_run
    FROM public.pokemon_catalog_sourcing_run
    WHERE id = p_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_NOT_FOUND: run % não encontrado.', p_run_id;
    END IF;
    IF v_run.run_type <> 'APPLY' THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_WRONG_TYPE: run % é %, esperado APPLY.', p_run_id, v_run.run_type;
    END IF;
    IF v_run.status <> 'PENDING' THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_INVALID_STATUS: run % está em % (esperado PENDING).', p_run_id, v_run.status;
    END IF;
    IF v_run.preflight_run_id IS NULL THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_MISSING_PREFLIGHT: run % sem preflight_run_id.', p_run_id;
    END IF;
    IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot) <> 'object' THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_INVALID_SNAPSHOT: snapshot deve ser um objeto JSON.';
    END IF;

    SELECT * INTO v_preflight
    FROM public.pokemon_catalog_sourcing_run
    WHERE id = v_run.preflight_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_PREFLIGHT_NOT_FOUND: preflight % não encontrado.', v_run.preflight_run_id;
    END IF;
    IF v_preflight.run_type <> 'DRY_RUN' THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_INVALID_PREFLIGHT_TYPE: preflight % não é DRY_RUN.', v_run.preflight_run_id;
    END IF;
    IF v_preflight.status <> 'COMPLETED' THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_INVALID_PREFLIGHT_STATUS: preflight % está em % (exige exatamente COMPLETED).', v_run.preflight_run_id, v_preflight.status;
    END IF;
    IF v_preflight.asset_source_id <> v_run.asset_source_id THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_ASSET_SOURCE_MISMATCH.';
    END IF;
    IF v_preflight.snapshot_hash IS NULL THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_PREFLIGHT_HASH_NULL.';
    END IF;

    SELECT * INTO v_asset_source FROM public.asset_source WHERE id = v_run.asset_source_id;
    IF NOT FOUND OR v_asset_source.code <> 'POKEAPI' OR v_asset_source.is_active <> TRUE THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_ASSET_SOURCE_INACTIVE.';
    END IF;

    v_hash := public.compute_pokemon_catalog_sourcing_snapshot_hash(p_snapshot);
    IF v_preflight.snapshot_hash IS DISTINCT FROM v_hash THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_HASH_MISMATCH: snapshot recebido não corresponde ao hash aprovado no preflight %.', v_run.preflight_run_id;
    END IF;

    -- Transição PENDING -> APPLYING (Seção 7.1). A partir daqui, qualquer
    -- RAISE EXCEPTION reverte esta transição também — ZERO commit canônico
    -- em caso de divergência (Seção 10). Se isto acontecer, o caller deve
    -- chamar close_failed_pokemon_catalog_sourcing_run() (Query 6108) para
    -- fechar o run imediatamente, em vez de esperar o stale recovery.
    UPDATE public.pokemon_catalog_sourcing_run SET status = 'APPLYING' WHERE id = p_run_id;

    -- ================= FASE (a): fresh reconciliation #1 (fail-fast) ========
    v_pre_fresh := public.reconcile_pokemon_catalog_sourcing_snapshot(v_run.asset_source_id, p_snapshot);
    IF (v_pre_fresh -> 'regions' ->> 'divergent')::INT > 0
       OR (v_pre_fresh -> 'generations' ->> 'divergent')::INT > 0
       OR (v_pre_fresh -> 'species' ->> 'divergent')::INT > 0
       OR (v_pre_fresh -> 'pokedex' ->> 'divergent')::INT > 0
       OR (v_pre_fresh -> 'positions' ->> 'divergent')::INT > 0
    THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_FRESH_DIVERGENCE: reconciliação no momento do APPLY encontrou divergência -- nenhuma escrita canônica realizada. Detalhe: %', v_pre_fresh;
    END IF;

    -- ================= FASE (b): LOCKING (Fix 7 — ordem fixa R->G->S->P) ===
    -- Apenas linhas EXISTENTES (já mapeadas por referência externa) são
    -- travadas — linhas NEW não existem ainda e permanecem protegidas pelas
    -- constraints UNIQUE no momento do INSERT (qualquer conflito aborta toda
    -- a transação). Ordem sempre R -> G -> S -> P, cada família ordenada por
    -- id ASC, para nunca inverter a ordem de locks entre duas execuções
    -- concorrentes de APPLY (evita deadlock).
    PERFORM 1
    FROM public.pokemon_region reg
    JOIN public.pokemon_region_external_reference xref
        ON xref.pokemon_region_id = reg.id
       AND xref.asset_source_id = v_run.asset_source_id
    JOIN jsonb_to_recordset(COALESCE(p_snapshot -> 'regions', '[]'::JSONB)) AS snap(external_region_id TEXT)
        ON snap.external_region_id = xref.external_region_id
    ORDER BY reg.id
    FOR UPDATE OF reg;

    PERFORM 1
    FROM public.pokemon_generation gen
    JOIN public.pokemon_generation_external_reference xref
        ON xref.pokemon_generation_id = gen.id
       AND xref.asset_source_id = v_run.asset_source_id
    JOIN jsonb_to_recordset(COALESCE(p_snapshot -> 'generations', '[]'::JSONB)) AS snap(external_generation_id TEXT)
        ON snap.external_generation_id = xref.external_generation_id
    ORDER BY gen.id
    FOR UPDATE OF gen;

    PERFORM 1
    FROM public.pokemon_species sp
    JOIN public.pokemon_species_external_reference xref
        ON xref.pokemon_species_id = sp.id
       AND xref.asset_source_id = v_run.asset_source_id
    JOIN jsonb_to_recordset(COALESCE(p_snapshot -> 'species', '[]'::JSONB)) AS snap(external_species_id TEXT)
        ON snap.external_species_id = xref.external_species_id
    ORDER BY sp.id
    FOR UPDATE OF sp;

    PERFORM 1
    FROM public.pokedex pd
    JOIN public.pokedex_external_reference xref
        ON xref.pokedex_id = pd.id
       AND xref.asset_source_id = v_run.asset_source_id
    WHERE xref.external_pokedex_id = (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id')
    ORDER BY pd.id
    FOR UPDATE OF pd;

    -- ================= FASE (c): fresh reconciliation #2 (pós-lock) ========
    -- Fecha a janela entre (a) e a aquisição dos locks: qualquer mudança
    -- concorrente ocorrida nesse intervalo é detectada aqui. Este resultado
    -- (v_fresh) é o que efetivamente orienta a escrita e as postconditions.
    v_fresh := public.reconcile_pokemon_catalog_sourcing_snapshot(v_run.asset_source_id, p_snapshot);
    IF (v_fresh -> 'regions' ->> 'divergent')::INT > 0
       OR (v_fresh -> 'generations' ->> 'divergent')::INT > 0
       OR (v_fresh -> 'species' ->> 'divergent')::INT > 0
       OR (v_fresh -> 'pokedex' ->> 'divergent')::INT > 0
       OR (v_fresh -> 'positions' ->> 'divergent')::INT > 0
    THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_CONCURRENT_DIVERGENCE: catálogo mudou entre a fresh reconciliation inicial e a aquisição de locks -- nenhuma escrita canônica realizada. Detalhe: %', v_fresh;
    END IF;

    -- ================= ESCRITA ATÔMICA — ORDEM EXATA (Seção 10.1) =========

    -- 1. Regions + Region External References (com source_url/metadata —
    --    Fix 8) ---------------------------------------------------------------
    WITH snap AS (
        SELECT external_region_id, code, canonical_name, source_url, metadata
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'regions', '[]'::JSONB))
            AS x(external_region_id TEXT, code TEXT, canonical_name TEXT, source_url TEXT, metadata JSONB)
    ),
    new_rows AS (
        INSERT INTO public.pokemon_region (code, canonical_name)
        SELECT snap.code, snap.canonical_name
        FROM snap
        LEFT JOIN public.pokemon_region_external_reference xref
            ON xref.asset_source_id = v_run.asset_source_id
           AND xref.external_region_id = snap.external_region_id
        WHERE xref.pokemon_region_id IS NULL
        RETURNING id, code
    )
    INSERT INTO public.pokemon_region_external_reference (pokemon_region_id, asset_source_id, external_region_id, source_url, metadata)
    SELECT new_rows.id, v_run.asset_source_id, snap.external_region_id, snap.source_url, COALESCE(snap.metadata, '{}'::JSONB)
    FROM new_rows
    JOIN snap ON snap.code = new_rows.code;
    GET DIAGNOSTICS v_regions_ins = ROW_COUNT;

    WITH snap AS (
        SELECT external_region_id, code, canonical_name
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'regions', '[]'::JSONB))
            AS x(external_region_id TEXT, code TEXT, canonical_name TEXT, source_url TEXT, metadata JSONB)
    )
    UPDATE public.pokemon_region reg
    SET canonical_name = snap.canonical_name
    FROM public.pokemon_region_external_reference xref
    JOIN snap ON snap.external_region_id = xref.external_region_id
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.pokemon_region_id = reg.id
      AND reg.code = snap.code
      AND reg.canonical_name IS DISTINCT FROM snap.canonical_name;
    GET DIAGNOSTICS v_regions_upd = ROW_COUNT;

    -- Sincronização de evidência (Fix 8) — nunca altera external_region_id.
    WITH snap AS (
        SELECT external_region_id, source_url, metadata
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'regions', '[]'::JSONB))
            AS x(external_region_id TEXT, code TEXT, canonical_name TEXT, source_url TEXT, metadata JSONB)
    )
    UPDATE public.pokemon_region_external_reference xref
    SET source_url = snap.source_url,
        metadata = COALESCE(snap.metadata, '{}'::JSONB)
    FROM snap
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.external_region_id = snap.external_region_id
      AND (xref.source_url IS DISTINCT FROM snap.source_url
           OR xref.metadata IS DISTINCT FROM COALESCE(snap.metadata, '{}'::JSONB));

    -- 2. Generations + Main Region + Generation External References ---------
    WITH snap AS (
        SELECT external_generation_id, code, canonical_name, ordinal_number, main_region_external_id, source_url, metadata
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'generations', '[]'::JSONB))
            AS x(external_generation_id TEXT, code TEXT, canonical_name TEXT,
                 ordinal_number INTEGER, main_region_external_id TEXT, source_url TEXT, metadata JSONB)
    ),
    resolved AS (
        SELECT snap.*, region_xref.pokemon_region_id AS resolved_main_region_id
        FROM snap
        JOIN public.pokemon_region_external_reference region_xref
            ON region_xref.asset_source_id = v_run.asset_source_id
           AND region_xref.external_region_id = snap.main_region_external_id
    ),
    new_rows AS (
        INSERT INTO public.pokemon_generation (code, canonical_name, ordinal_number, main_region_id)
        SELECT resolved.code, resolved.canonical_name, resolved.ordinal_number, resolved.resolved_main_region_id
        FROM resolved
        LEFT JOIN public.pokemon_generation_external_reference gen_xref
            ON gen_xref.asset_source_id = v_run.asset_source_id
           AND gen_xref.external_generation_id = resolved.external_generation_id
        WHERE gen_xref.pokemon_generation_id IS NULL
        RETURNING id, code, ordinal_number
    )
    INSERT INTO public.pokemon_generation_external_reference (pokemon_generation_id, asset_source_id, external_generation_id, source_url, metadata)
    SELECT new_rows.id, v_run.asset_source_id, resolved.external_generation_id, resolved.source_url, COALESCE(resolved.metadata, '{}'::JSONB)
    FROM new_rows
    JOIN resolved ON resolved.code = new_rows.code AND resolved.ordinal_number = new_rows.ordinal_number;
    GET DIAGNOSTICS v_generations_ins = ROW_COUNT;

    WITH snap AS (
        SELECT external_generation_id, canonical_name
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'generations', '[]'::JSONB))
            AS x(external_generation_id TEXT, code TEXT, canonical_name TEXT,
                 ordinal_number INTEGER, main_region_external_id TEXT, source_url TEXT, metadata JSONB)
    )
    UPDATE public.pokemon_generation gen
    SET canonical_name = snap.canonical_name
    FROM public.pokemon_generation_external_reference xref
    JOIN snap ON snap.external_generation_id = xref.external_generation_id
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.pokemon_generation_id = gen.id
      AND gen.canonical_name IS DISTINCT FROM snap.canonical_name;
    GET DIAGNOSTICS v_generations_upd = ROW_COUNT;

    WITH snap AS (
        SELECT external_generation_id, source_url, metadata
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'generations', '[]'::JSONB))
            AS x(external_generation_id TEXT, code TEXT, canonical_name TEXT,
                 ordinal_number INTEGER, main_region_external_id TEXT, source_url TEXT, metadata JSONB)
    )
    UPDATE public.pokemon_generation_external_reference xref
    SET source_url = snap.source_url,
        metadata = COALESCE(snap.metadata, '{}'::JSONB)
    FROM snap
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.external_generation_id = snap.external_generation_id
      AND (xref.source_url IS DISTINCT FROM snap.source_url
           OR xref.metadata IS DISTINCT FROM COALESCE(snap.metadata, '{}'::JSONB));

    -- 3. Species + Species External References --------------------------------
    WITH snap AS (
        SELECT external_species_id, national_dex_number, canonical_name, generation_external_id, source_url, metadata
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'species', '[]'::JSONB))
            AS x(external_species_id TEXT, national_dex_number INTEGER,
                 canonical_name TEXT, generation_external_id TEXT, source_url TEXT, metadata JSONB)
    ),
    resolved AS (
        SELECT snap.*, gen_xref.pokemon_generation_id AS resolved_generation_id
        FROM snap
        JOIN public.pokemon_generation_external_reference gen_xref
            ON gen_xref.asset_source_id = v_run.asset_source_id
           AND gen_xref.external_generation_id = snap.generation_external_id
    ),
    new_rows AS (
        INSERT INTO public.pokemon_species (generation_id, national_dex_number, canonical_name)
        SELECT resolved.resolved_generation_id, resolved.national_dex_number, resolved.canonical_name
        FROM resolved
        LEFT JOIN public.pokemon_species_external_reference sp_xref
            ON sp_xref.asset_source_id = v_run.asset_source_id
           AND sp_xref.external_species_id = resolved.external_species_id
        WHERE sp_xref.pokemon_species_id IS NULL
        RETURNING id, national_dex_number
    )
    INSERT INTO public.pokemon_species_external_reference (pokemon_species_id, asset_source_id, external_species_id, source_url, metadata)
    SELECT new_rows.id, v_run.asset_source_id, resolved.external_species_id, resolved.source_url, COALESCE(resolved.metadata, '{}'::JSONB)
    FROM new_rows
    JOIN resolved ON resolved.national_dex_number = new_rows.national_dex_number;
    GET DIAGNOSTICS v_species_ins = ROW_COUNT;

    WITH snap AS (
        SELECT external_species_id, canonical_name
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'species', '[]'::JSONB))
            AS x(external_species_id TEXT, national_dex_number INTEGER,
                 canonical_name TEXT, generation_external_id TEXT, source_url TEXT, metadata JSONB)
    )
    UPDATE public.pokemon_species sp
    SET canonical_name = snap.canonical_name
    FROM public.pokemon_species_external_reference xref
    JOIN snap ON snap.external_species_id = xref.external_species_id
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.pokemon_species_id = sp.id
      AND sp.canonical_name IS DISTINCT FROM snap.canonical_name;
    GET DIAGNOSTICS v_species_upd = ROW_COUNT;

    WITH snap AS (
        SELECT external_species_id, source_url, metadata
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'species', '[]'::JSONB))
            AS x(external_species_id TEXT, national_dex_number INTEGER,
                 canonical_name TEXT, generation_external_id TEXT, source_url TEXT, metadata JSONB)
    )
    UPDATE public.pokemon_species_external_reference xref
    SET source_url = snap.source_url,
        metadata = COALESCE(snap.metadata, '{}'::JSONB)
    FROM snap
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.external_species_id = snap.external_species_id
      AND (xref.source_url IS DISTINCT FROM snap.source_url
           OR xref.metadata IS DISTINCT FROM COALESCE(snap.metadata, '{}'::JSONB));

    -- 4. National Pokédex + Pokédex External Reference -----------------------
    WITH snap AS (
        SELECT
            p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id' AS external_pokedex_id,
            p_snapshot -> 'national_pokedex' ->> 'code' AS code,
            p_snapshot -> 'national_pokedex' ->> 'canonical_name' AS canonical_name,
            p_snapshot -> 'national_pokedex' ->> 'source_url' AS source_url,
            (p_snapshot -> 'national_pokedex' -> 'metadata') AS metadata
    ),
    new_row AS (
        INSERT INTO public.pokedex (code, canonical_name)
        SELECT snap.code, snap.canonical_name
        FROM snap
        LEFT JOIN public.pokedex_external_reference pd_xref
            ON pd_xref.asset_source_id = v_run.asset_source_id
           AND pd_xref.external_pokedex_id = snap.external_pokedex_id
        WHERE pd_xref.pokedex_id IS NULL
        RETURNING id
    )
    INSERT INTO public.pokedex_external_reference (pokedex_id, asset_source_id, external_pokedex_id, source_url, metadata)
    SELECT new_row.id, v_run.asset_source_id, snap.external_pokedex_id, snap.source_url, COALESCE(snap.metadata, '{}'::JSONB)
    FROM new_row, snap;
    GET DIAGNOSTICS v_pokedex_ins = ROW_COUNT;

    UPDATE public.pokedex pd
    SET canonical_name = (p_snapshot -> 'national_pokedex' ->> 'canonical_name')
    FROM public.pokedex_external_reference xref
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.external_pokedex_id = (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id')
      AND xref.pokedex_id = pd.id
      AND pd.canonical_name IS DISTINCT FROM (p_snapshot -> 'national_pokedex' ->> 'canonical_name');
    GET DIAGNOSTICS v_pokedex_upd = ROW_COUNT;

    UPDATE public.pokedex_external_reference xref
    SET source_url = (p_snapshot -> 'national_pokedex' ->> 'source_url'),
        metadata = COALESCE((p_snapshot -> 'national_pokedex' -> 'metadata'), '{}'::JSONB)
    WHERE xref.asset_source_id = v_run.asset_source_id
      AND xref.external_pokedex_id = (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id')
      AND (xref.source_url IS DISTINCT FROM (p_snapshot -> 'national_pokedex' ->> 'source_url')
           OR xref.metadata IS DISTINCT FROM COALESCE((p_snapshot -> 'national_pokedex' -> 'metadata'), '{}'::JSONB));

    -- 5. Positions (somente INSERT — Seção 9.4) -------------------------------
    WITH snap AS (
        SELECT external_species_id, position_number
        FROM jsonb_to_recordset(COALESCE(p_snapshot -> 'national_pokedex_entries', '[]'::JSONB))
            AS x(external_species_id TEXT, position_number INTEGER)
    ),
    resolved AS (
        SELECT
            snap.position_number,
            pd_xref.pokedex_id,
            sp_xref.pokemon_species_id AS species_id
        FROM snap
        JOIN public.pokedex_external_reference pd_xref
            ON pd_xref.asset_source_id = v_run.asset_source_id
           AND pd_xref.external_pokedex_id = (p_snapshot -> 'national_pokedex' ->> 'external_pokedex_id')
        JOIN public.pokemon_species_external_reference sp_xref
            ON sp_xref.asset_source_id = v_run.asset_source_id
           AND sp_xref.external_species_id = snap.external_species_id
    )
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
    SELECT resolved.pokedex_id, resolved.species_id, resolved.position_number
    FROM resolved
    LEFT JOIN public.pokedex_position existing
        ON existing.pokedex_id = resolved.pokedex_id
       AND existing.species_id = resolved.species_id
    WHERE existing.id IS NULL;
    GET DIAGNOSTICS v_positions_ins = ROW_COUNT;

    -- ================= FIM DA ESCRITA ATÔMICA ==============================

    -- ================= POSTCONDITIONS (Fix 9) ===============================
    -- (i) Comparação direta contra a expectativa da fresh reconciliation #2
    --     (pré-escrita): inserted deve corresponder a new, updated deve
    --     corresponder a update_name, por família.
    IF v_regions_ins <> (v_fresh -> 'regions' ->> 'new')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: regions inserted (%) <> new esperado (%).', v_regions_ins, (v_fresh -> 'regions' ->> 'new')::INT;
    END IF;
    IF v_regions_upd <> (v_fresh -> 'regions' ->> 'update_name')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: regions updated (%) <> update_name esperado (%).', v_regions_upd, (v_fresh -> 'regions' ->> 'update_name')::INT;
    END IF;
    IF v_generations_ins <> (v_fresh -> 'generations' ->> 'new')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: generations inserted (%) <> new esperado (%).', v_generations_ins, (v_fresh -> 'generations' ->> 'new')::INT;
    END IF;
    IF v_generations_upd <> (v_fresh -> 'generations' ->> 'update_name')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: generations updated (%) <> update_name esperado (%).', v_generations_upd, (v_fresh -> 'generations' ->> 'update_name')::INT;
    END IF;
    IF v_species_ins <> (v_fresh -> 'species' ->> 'new')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: species inserted (%) <> new esperado (%).', v_species_ins, (v_fresh -> 'species' ->> 'new')::INT;
    END IF;
    IF v_species_upd <> (v_fresh -> 'species' ->> 'update_name')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: species updated (%) <> update_name esperado (%).', v_species_upd, (v_fresh -> 'species' ->> 'update_name')::INT;
    END IF;
    IF v_pokedex_ins <> (v_fresh -> 'pokedex' ->> 'new')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: pokedex inserted (%) <> new esperado (%).', v_pokedex_ins, (v_fresh -> 'pokedex' ->> 'new')::INT;
    END IF;
    IF v_pokedex_upd <> (v_fresh -> 'pokedex' ->> 'update_name')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: pokedex updated (%) <> update_name esperado (%).', v_pokedex_upd, (v_fresh -> 'pokedex' ->> 'update_name')::INT;
    END IF;
    IF v_positions_ins <> (v_fresh -> 'positions' ->> 'new')::INT THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_MISMATCH: positions inserted (%) <> new esperado (%).', v_positions_ins, (v_fresh -> 'positions' ->> 'new')::INT;
    END IF;

    -- (ii) Reconciliação final pós-escrita: exige 100% UNCHANGED em todas as
    --      famílias — prova de que a escrita convergiu o catálogo para o
    --      snapshot aprovado (inclusive dependências resolvidas e
    --      referências externas novas existindo 1:1, já que a própria
    --      classificação UNCHANGED depende disso).
    v_post := public.reconcile_pokemon_catalog_sourcing_snapshot(v_run.asset_source_id, p_snapshot);
    IF (v_post -> 'regions' ->> 'new')::INT <> 0 OR (v_post -> 'regions' ->> 'update_name')::INT <> 0 OR (v_post -> 'regions' ->> 'divergent')::INT <> 0
       OR (v_post -> 'generations' ->> 'new')::INT <> 0 OR (v_post -> 'generations' ->> 'update_name')::INT <> 0 OR (v_post -> 'generations' ->> 'divergent')::INT <> 0
       OR (v_post -> 'species' ->> 'new')::INT <> 0 OR (v_post -> 'species' ->> 'update_name')::INT <> 0 OR (v_post -> 'species' ->> 'divergent')::INT <> 0
       OR (v_post -> 'pokedex' ->> 'new')::INT <> 0 OR (v_post -> 'pokedex' ->> 'update_name')::INT <> 0 OR (v_post -> 'pokedex' ->> 'divergent')::INT <> 0
       OR (v_post -> 'positions' ->> 'new')::INT <> 0 OR (v_post -> 'positions' ->> 'divergent')::INT <> 0
    THEN
        RAISE EXCEPTION 'APPLY_POKEMON_CATALOG_SOURCING_RUN_POSTCONDITION_FAILED: reconciliação pós-escrita não é 100%% UNCHANGED. Detalhe: %', v_post;
    END IF;

    -- REVISION-02 (item 2 do GATE 4, NO-GO residual): a v2.0 montava
    -- apply_summary.unchanged a partir de v_post (reconciliação PÓS-escrita),
    -- que a essa altura já classificou TODA linha do snapshot -- inclusive as
    -- que este próprio APPLY acabou de inserir/atualizar -- como UNCHANGED
    -- (é exatamente isso que a postcondition (ii) acima exige). Usar
    -- v_post.unchanged aqui gerava dupla contagem: inserted + updated +
    -- unchanged(v_post) somava mais que o total processado, porque as linhas
    -- recém-escritas apareciam tanto em inserted/updated quanto em
    -- unchanged(v_post). v_post permanece EXCLUSIVAMENTE como prova de
    -- postcondition (usado acima) -- nunca como fonte de números do summary.
    -- Corrigido: unchanged agora vem de v_fresh (reconciliação PRÉ-escrita,
    -- fase (c)), que reflete o que já estava correto ANTES desta escrita.
    -- Semântica resultante: no primeiro APPLY, inserted + updated +
    -- unchanged(v_fresh) = total processado, sem dupla contagem; num
    -- segundo APPLY idempotente (nada para inserir/atualizar), v_fresh já
    -- mostra new=0/update_name=0 e unchanged=total, e a escrita não
    -- encontra nada a fazer -- inserted=0, updated=0, unchanged=total em
    -- todas as famílias.
    v_apply_summary := jsonb_build_object(
        'regions', jsonb_build_object('inserted', v_regions_ins, 'updated', v_regions_upd, 'unchanged', (v_fresh -> 'regions' ->> 'unchanged')::INT),
        'generations', jsonb_build_object('inserted', v_generations_ins, 'updated', v_generations_upd, 'unchanged', (v_fresh -> 'generations' ->> 'unchanged')::INT),
        'species', jsonb_build_object('inserted', v_species_ins, 'updated', v_species_upd, 'unchanged', (v_fresh -> 'species' ->> 'unchanged')::INT),
        'pokedex', jsonb_build_object('inserted', v_pokedex_ins, 'updated', v_pokedex_upd, 'unchanged', (v_fresh -> 'pokedex' ->> 'unchanged')::INT),
        'positions', jsonb_build_object('inserted', v_positions_ins, 'updated', 0, 'unchanged', (v_fresh -> 'positions' ->> 'unchanged')::INT)
    );

    UPDATE public.pokemon_catalog_sourcing_run
    SET status = 'COMPLETED',
        apply_summary = v_apply_summary,
        finished_at = CLOCK_TIMESTAMP()
    WHERE id = p_run_id;

    RETURN QUERY SELECT 'COMPLETED'::TEXT, p_run_id, 'COMPLETED'::TEXT, v_apply_summary;
END;
$$;

COMMENT ON FUNCTION public.apply_pokemon_catalog_sourcing_run(UUID, JSONB) IS
    'APPLY do fluxo APPLY — fresh reconciliation dupla com locks em ordem fixa (R->G->S->P), sincronização de evidência (source_url/metadata), escrita canônica atômica e postconditions (contagens + reconciliação final 100%% UNCHANGED). apply_summary.unchanged vem de v_fresh (pré-escrita), nunca de v_post (pós-escrita, exclusivo para prova de postcondition). Ver docs/06a-pokemon-catalog-sourcing.md Seção 10. SERVICE_ROLE ONLY. v2.1 — REVISION-02. (6110: finished_at via CLOCK_TIMESTAMP(), corrige ck_pokemon_catalog_sourcing_run_period — mesmo contrato de 6105.)';

REVOKE ALL ON FUNCTION public.apply_pokemon_catalog_sourcing_run(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.apply_pokemon_catalog_sourcing_run(UUID, JSONB)
    TO service_role;

-- =============================================================================
-- 3/3: close_failed_pokemon_catalog_sourcing_run(UUID, TEXT)
-- Única mudança: a 1 ocorrência de `finished_at = NOW()` passa a
-- `finished_at = CLOCK_TIMESTAMP()`. Todo o restante é byte-idêntico a 6108
-- (aceitação de qualquer run ATIVO, sanitização de error_summary).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.close_failed_pokemon_catalog_sourcing_run(
    p_run_id UUID,
    p_error_summary TEXT DEFAULT NULL
)
RETURNS TABLE (
    outcome TEXT,
    run_id UUID,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_run public.pokemon_catalog_sourcing_run%ROWTYPE;
    v_sanitized TEXT;
BEGIN
    SELECT * INTO v_run
    FROM public.pokemon_catalog_sourcing_run
    WHERE id = p_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CLOSE_FAILED_POKEMON_CATALOG_SOURCING_RUN_NOT_FOUND: run % não encontrado.', p_run_id;
    END IF;
    IF v_run.status NOT IN ('PENDING', 'ACQUIRING', 'PLANNING', 'APPLYING') THEN
        RAISE EXCEPTION 'CLOSE_FAILED_POKEMON_CATALOG_SOURCING_RUN_NOT_ACTIVE: run % já está em estado terminal (%).', p_run_id, v_run.status;
    END IF;

    -- Sanitização: remove CR/LF/TAB, colapsa espaços redundantes, trunca em
    -- 2000 caracteres, nunca grava string vazia.
    v_sanitized := REGEXP_REPLACE(COALESCE(p_error_summary, ''), '[\r\n\t]+', ' ', 'g');
    v_sanitized := BTRIM(v_sanitized);
    v_sanitized := LEFT(v_sanitized, 2000);
    v_sanitized := NULLIF(v_sanitized, '');
    v_sanitized := COALESCE(v_sanitized, 'CLOSED_BY_CALLER');

    UPDATE public.pokemon_catalog_sourcing_run
    SET status = 'FAILED',
        error_summary = v_sanitized,
        finished_at = CLOCK_TIMESTAMP()
    WHERE id = p_run_id;

    RETURN QUERY SELECT 'FAILED'::TEXT, p_run_id, 'FAILED'::TEXT;
END;
$$;

COMMENT ON FUNCTION public.close_failed_pokemon_catalog_sourcing_run(UUID, TEXT) IS
    'AUXILIAR entrypoint — fecha imediatamente como FAILED um run ATIVO cujo erro já foi capturado pelo caller (ex.: exceção de apply_pokemon_catalog_sourcing_run), liberando o guard de run ativo sem esperar o stale recovery de 30 minutos. Ver docs/06a-pokemon-catalog-sourcing.md Seção 10. SERVICE_ROLE ONLY. (6110: finished_at via CLOCK_TIMESTAMP(), corrige ck_pokemon_catalog_sourcing_run_period — mesmo contrato de 6108.)';

REVOKE ALL ON FUNCTION public.close_failed_pokemon_catalog_sourcing_run(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.close_failed_pokemon_catalog_sourcing_run(UUID, TEXT)
    TO service_role;

COMMIT;
