/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6105 - Create Apply Pokemon Catalog Sourcing Run Function
Versão......: 2.1 (PROPOSTA — GATE 3 STAGING, REVISION-02)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, materializando docs/06a-pokemon-catalog-
               sourcing.md v1.1, Seção 10; revisado em ...-STAGING-
               REVISION-01 (itens 7, 8 e 9) e ...-STAGING-REVISION-02
               (item 2 — NO-GO residual); aplicado em 2026-09-04 via POKEMON-CATALOG-SOURCING-GATE-5-IMPLEMENTATION-01)

REVISION-02 — o que mudou e por quê (item 2 do segundo GATE 4, NO-GO
residual restrito a 6104/6105/6820):

apply_summary.unchanged usava v_post (a reconciliação PÓS-escrita, cuja
função exclusiva é provar a postcondition "100% UNCHANGED" — item (ii)
abaixo). No momento em que v_post é calculado, TODA linha do snapshot já foi
convergida para o catálogo por esta própria execução, então v_post classifica
até as linhas recém-inseridas/atualizadas como UNCHANGED. Usar
v_post.unchanged no summary produzia dupla contagem: inserted + updated +
unchanged(v_post) somava mais do que o total de linhas processadas. Corrigido
para usar v_fresh (a reconciliação PRÉ-escrita da fase (c), que reflete o
estado do catálogo imediatamente antes desta escrita). v_post permanece
exclusivamente como prova de postcondition, nunca mais como fonte de números
do summary. Nenhuma mudança no protocolo de locks (fases (a)/(b)/(c)) nem nas
demais postconditions (comparação direta inserted=new/updated=update_name
continua usando v_fresh, como já era).

REVISION-01 — o que mudou e por quê:

Item 7 (CONCORRÊNCIA): a v1.0 fazia UMA fresh reconciliation e escrevia em
seguida, deixando uma janela entre a leitura e a escrita em que uma
alteração administrativa concorrente nas MESMAS linhas canônicas poderia ser
sobrescrita silenciosamente. Corrigido com um protocolo de 3 fases:
  (a) fresh reconciliation #1 — fail-fast, evita tomar locks à toa quando já
      há divergência óbvia;
  (b) LOCK explícito (`FOR UPDATE`) de toda linha EXISTENTE (via referência
      externa já mapeada) que este snapshot toca, em ordem FIXA e
      determinística — Region (por id ASC) → Generation (por id ASC) →
      Species (por id ASC) → Pokedex — para nunca inverter a ordem entre
      duas execuções concorrentes de APPLY e assim nunca deadlockar;
  (c) fresh reconciliation #2, DEPOIS dos locks — fecha a janela: qualquer
      mudança concorrente que tenha ocorrido entre (a) e a aquisição dos
      locks em (b) é detectada aqui, pois o lock só bloqueia ESCRITAS
      futuras, não invalida uma leitura já feita antes dele.
  Linhas NEW continuam protegidas apenas pelas constraints UNIQUE (a v1.0 já
  fazia isso corretamente) — qualquer conflito de INSERT aborta a transação
  inteira, o que é aceito explicitamente pelo GATE 4 como suficiente para o
  caso NEW.

Item 8 (SOURCE EVIDENCE): a v1.0 descartava source_url/metadata do
snapshot. Corrigido: toda linha NOVA de *_external_reference grava
source_url/metadata vindos do snapshot; toda linha JÁ EXISTENTE tem
source_url/metadata sincronizados quando realmente divergem — SEM tocar a
identidade externa (external_*_id nunca é alterado por este sincronismo,
apenas os dois campos de evidência).

Item 9 (POSTCONDITIONS): a v1.0 confiava cegamente no resultado das
instruções DML. Corrigido com dupla verificação antes de COMPLETED: (i)
comparação direta `inserted = new` e `updated = update_name` por família,
usando os contadores da fresh reconciliation #2 (pré-escrita) como
expectativa; (ii) uma TERCEIRA reconciliação, agora pós-escrita, que deve
fechar 100% UNCHANGED (new=0, update_name=0, divergent=0) em todas as
famílias — prova de que a escrita realmente convergiu o catálogo para o
snapshot aprovado. Qualquer mismatch em (i) ou (ii) → RAISE EXCEPTION →
ROLLBACK total (nenhum COMPLETED silencioso com escrita parcial).

Regras de Negócio preservadas da v1.0 (ver header original para detalhe
integral): validação de preflight/hash/asset_source inalterada; qualquer
falha usa RAISE EXCEPTION (rollback total, "ZERO commit canônico" — Seção
10); escrita atômica na ordem exata Regions→Generations→Species→National
Pokédex→Positions; Positions somente INSERT (nunca corrige position_number).

Fechamento de falha (complementar, não faz parte desta função): se esta
função lançar exceção, o run físico permanece em PENDING (rollback total,
inclusive da transição para APPLYING) — o caller deve chamar
close_failed_pokemon_catalog_sourcing_run() (Query 6108) para marcar
imediatamente o run como FAILED e liberar o guard de run ativo, em vez de
esperar os 30 minutos do stale recovery.

SECURITY DEFINER + SET search_path = ''. SERVICE_ROLE ONLY.

Pré-requisitos:
- Query 6100/6101 v1.1 - Pokemon Catalog Sourcing Run.
- Query 6102 - Snapshot Hash Function.
- Query 6106 v2.0 - Reconcile Snapshot Function (AUXILIAR, lockstep, LANGUAGE
  sql — seguro para múltiplas chamadas na mesma transação).
- Query 6060/6070, 6000/6090, 6010/6020, 6030/6050, 6040, 6080 - todas as
  tabelas canônicas e external references envolvidas na escrita.
===============================================================================
*/

BEGIN;

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
        finished_at = NOW()
    WHERE id = p_run_id;

    RETURN QUERY SELECT 'COMPLETED'::TEXT, p_run_id, 'COMPLETED'::TEXT, v_apply_summary;
END;
$$;

COMMENT ON FUNCTION public.apply_pokemon_catalog_sourcing_run(UUID, JSONB) IS
    'APPLY do fluxo APPLY — fresh reconciliation dupla com locks em ordem fixa (R->G->S->P), sincronização de evidência (source_url/metadata), escrita canônica atômica e postconditions (contagens + reconciliação final 100%% UNCHANGED). apply_summary.unchanged vem de v_fresh (pré-escrita), nunca de v_post (pós-escrita, exclusivo para prova de postcondition). Ver docs/06a-pokemon-catalog-sourcing.md Seção 10. SERVICE_ROLE ONLY. v2.1 — REVISION-02.';

REVOKE ALL ON FUNCTION public.apply_pokemon_catalog_sourcing_run(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.apply_pokemon_catalog_sourcing_run(UUID, JSONB)
    TO service_role;

COMMIT;
