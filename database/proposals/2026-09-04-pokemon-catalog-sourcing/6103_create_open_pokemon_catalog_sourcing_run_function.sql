/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6103 - Create Open Pokemon Catalog Sourcing Run Function
Versão......: 1.1 (PROPOSTA — GATE 3 STAGING, REVISION-01)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, materializando docs/06a-pokemon-catalog-
               sourcing.md v1.1, Seção 7.2; revisado em ...-STAGING-
               REVISION-01, item 6 da auditoria GATE 4)

REVISION-01 — o que mudou e por quê: a v1.0 traduzia QUALQUER
unique_violation capturado no INSERT em SOURCE_BUSY — mas a tabela tem DUAS
constraints UNIQUE (uq_pokemon_catalog_sourcing_run_code, além do índice
parcial de run ativo). Se o run_code colidisse por qualquer motivo (ex.:
corrupção da sequence), a v1.0 mascararia isso como "SOURCE_BUSY", uma
mensagem de negócio enganosa para um erro de integridade real. Corrigido: o
handler agora inspeciona `CONSTRAINT_NAME` via `GET STACKED DIAGNOSTICS` e só
traduz para SOURCE_BUSY a violação de
`uq_pokemon_catalog_sourcing_run_active_source` especificamente; qualquer
outra unique_violation é relançada (`RAISE;`) sem modificação.

Descrição resumida:
Abre (claim) um novo run de Pokémon Catalog Sourcing para a Fonte POKEAPI.
Único ponto de entrada que insere uma linha em pokemon_catalog_sourcing_run.
Precedente físico direto: open_pricing_set_refresh_attempt() (migration 3933)
— mesmo padrão de reconciliação de lease órfã + claim via UNIQUE + tradução de
unique_violation em outcome de negócio (SOURCE_BUSY), em vez de erro solto.

Regras de Negócio (literais do contrato 06a, Seção 7.2):
1. Resolve asset_source ativo de code = 'POKEAPI'; ausência/inatividade →
   RAISE EXCEPTION (erro de configuração, não condição de negócio esperada).
2. p_run_type normalizado e validado ∈ {DRY_RUN, APPLY}.
3. Stale recovery (Passo 0): qualquer run ATIVO (PENDING/ACQUIRING/PLANNING/
   APPLYING) da mesma Fonte cujo COALESCE(heartbeat_at, created_at) exceda 30
   minutos é reconciliado para FAILED (error_summary = STALE_RUN_RECONCILED)
   ANTES da tentativa de claim — nunca depois, para não bloquear
   indevidamente uma abertura legítima.
4. Para APPLY: preflight_run_id é obrigatório; o preflight referenciado deve
   ser DRY_RUN, status EXATAMENTE COMPLETED (nunca COMPLETED_WITH_
   DIVERGENCES), da mesma Fonte, com snapshot_hash NOT NULL. Qualquer
   violação → RAISE EXCEPTION (validação de precondição, não corrida).
   Para DRY_RUN: p_preflight_run_id deve ser NULL.
5. Claim: INSERT com status DEFAULT 'PENDING'. A colisão com o índice UNIQUE
   parcial de run ativo (uq_pokemon_catalog_sourcing_run_active_source,
   Query 6100) é capturada via EXCEPTION WHEN unique_violation e traduzida em
   outcome = 'SOURCE_BUSY' (nunca erro solto ao caller — mesmo padrão do
   precedente 3933).

SECURITY DEFINER + SET search_path = '' (todas as referências de tabela
explicitamente qualificadas por public.). SERVICE_ROLE ONLY.

Grants:
- REVOKE EXECUTE de PUBLIC, anon, authenticated.
- GRANT EXECUTE a service_role.

Pré-requisitos:
- Query 6100/6101 - Pokemon Catalog Sourcing Run (tabela + triggers).
- Query 200 - Asset Source Table (CONFIRMADO EXECUTADO).
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.open_pokemon_catalog_sourcing_run(
    p_run_type TEXT,
    p_preflight_run_id UUID DEFAULT NULL
)
RETURNS TABLE (
    outcome TEXT,
    run_id UUID,
    run_code TEXT,
    preflight_run_id UUID,
    preflight_snapshot_hash TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_asset_source_id UUID;
    v_run_type TEXT;
    v_preflight public.pokemon_catalog_sourcing_run%ROWTYPE;
    v_new_id UUID;
    v_new_code TEXT;
    v_constraint_name TEXT;
BEGIN
    v_run_type := UPPER(BTRIM(p_run_type));
    IF v_run_type NOT IN ('DRY_RUN', 'APPLY') THEN
        RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_INVALID_TYPE: % inválido (esperado DRY_RUN ou APPLY).', p_run_type;
    END IF;

    SELECT id INTO v_asset_source_id
    FROM public.asset_source
    WHERE code = 'POKEAPI' AND is_active = TRUE;

    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_ASSET_SOURCE_UNAVAILABLE: asset_source POKEAPI ausente ou inativa.';
    END IF;

    -- Passo 0: reconciliação de runs ativos órfãos/stale (Seção 7.2, threshold
    -- fixo de 30 minutos), ANTES de qualquer tentativa de claim.
    UPDATE public.pokemon_catalog_sourcing_run
    SET status = 'FAILED',
        error_summary = 'STALE_RUN_RECONCILED: run ativo excedeu 30 minutos sem conclusão.',
        finished_at = NOW()
    WHERE asset_source_id = v_asset_source_id
      AND status IN ('PENDING', 'ACQUIRING', 'PLANNING', 'APPLYING')
      AND COALESCE(heartbeat_at, created_at) < NOW() - INTERVAL '30 minutes';

    IF v_run_type = 'DRY_RUN' THEN
        IF p_preflight_run_id IS NOT NULL THEN
            RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_UNEXPECTED_PREFLIGHT: DRY_RUN não aceita preflight_run_id.';
        END IF;
    ELSE
        IF p_preflight_run_id IS NULL THEN
            RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_MISSING_PREFLIGHT: APPLY exige preflight_run_id (DRY_RUN COMPLETED aprovado).';
        END IF;

        SELECT * INTO v_preflight
        FROM public.pokemon_catalog_sourcing_run
        WHERE id = p_preflight_run_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_PREFLIGHT_NOT_FOUND: run % não encontrado.', p_preflight_run_id;
        END IF;
        IF v_preflight.run_type <> 'DRY_RUN' THEN
            RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_INVALID_PREFLIGHT_TYPE: preflight % não é DRY_RUN.', p_preflight_run_id;
        END IF;
        IF v_preflight.status <> 'COMPLETED' THEN
            RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_INVALID_PREFLIGHT_STATUS: preflight % está em % (exige exatamente COMPLETED, nunca COMPLETED_WITH_DIVERGENCES).', p_preflight_run_id, v_preflight.status;
        END IF;
        IF v_preflight.asset_source_id <> v_asset_source_id THEN
            RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_PREFLIGHT_ASSET_SOURCE_MISMATCH.';
        END IF;
        IF v_preflight.snapshot_hash IS NULL THEN
            RAISE EXCEPTION 'OPEN_POKEMON_CATALOG_SOURCING_RUN_PREFLIGHT_HASH_NULL.';
        END IF;
    END IF;

    BEGIN
        INSERT INTO public.pokemon_catalog_sourcing_run (asset_source_id, run_type, preflight_run_id)
        VALUES (v_asset_source_id, v_run_type, p_preflight_run_id)
        RETURNING id, run_code INTO v_new_id, v_new_code;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
        IF v_constraint_name = 'uq_pokemon_catalog_sourcing_run_active_source' THEN
            RETURN QUERY SELECT 'SOURCE_BUSY'::TEXT, NULL::UUID, NULL::TEXT, NULL::UUID, NULL::TEXT;
            RETURN;
        ELSE
            -- Qualquer outra unique_violation (ex.: colisão de run_code) NÃO
            -- é um SOURCE_BUSY -- é um erro de integridade real. Relança sem
            -- modificação (Fix 6, REVISION-01).
            RAISE;
        END IF;
    END;

    RETURN QUERY SELECT
        'CLAIMED'::TEXT,
        v_new_id,
        v_new_code,
        p_preflight_run_id,
        v_preflight.snapshot_hash;
END;
$$;

COMMENT ON FUNCTION public.open_pokemon_catalog_sourcing_run(TEXT, UUID) IS
    'Abre (claim) um run de Pokémon Catalog Sourcing para POKEAPI, com reconciliação de stale e guard de concorrência SOURCE_BUSY. Ver docs/06a-pokemon-catalog-sourcing.md Seção 7.2. SERVICE_ROLE ONLY.';

REVOKE ALL ON FUNCTION public.open_pokemon_catalog_sourcing_run(TEXT, UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.open_pokemon_catalog_sourcing_run(TEXT, UUID)
    TO service_role;

COMMIT;
