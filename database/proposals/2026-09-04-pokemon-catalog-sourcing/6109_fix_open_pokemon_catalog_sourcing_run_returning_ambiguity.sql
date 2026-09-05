/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6109 - Fix Open Pokemon Catalog Sourcing Run Returning Ambiguity
               (HOTFIX incremental sobre 6103 — NÃO reescreve/substitui o
               histórico já executado de 6103)
Versão......: 1.0 (PROPOSTA — GATE 5 HOTFIX STAGING)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-GATE-5-HOTFIX-
               6103-STAGING-01, após a primeira execução real de
               open_pokemon_catalog_sourcing_run() em GATE-5-IMPLEMENTATION-01
               ter retornado erro real do PostgreSQL)

CONTEXTO DO HOTFIX — o que aconteceu e por quê:
6090-6108 foram aplicados com sucesso ao banco real (GATE 5 IMPLEMENTATION-01).
Na primeira chamada real e efetiva a open_pokemon_catalog_sourcing_run()
(dentro da execução de 6820 v2.2, Seção 6), o PostgreSQL retornou:

    ERROR: 42702: column reference "run_code" is ambiguous
    DETAIL: It could refer to either a PL/pgSQL variable or a table column.
    QUERY: INSERT INTO public.pokemon_catalog_sourcing_run
           (asset_source_id, run_type, preflight_run_id)
           VALUES (v_asset_source_id, v_run_type, p_preflight_run_id)
           RETURNING id, run_code
    CONTEXT: PL/pgSQL function public.open_pokemon_catalog_sourcing_run(text,uuid)

Causa raiz: a função declara RETURNS TABLE (outcome TEXT, run_id UUID,
run_code TEXT, preflight_run_id UUID, preflight_snapshot_hash TEXT) — o que
cria implicitamente uma variável PL/pgSQL de nome `run_code` (o próprio OUT
parameter). A tabela public.pokemon_catalog_sourcing_run também tem uma
coluna física chamada `run_code`. Dentro do corpo da função, a cláusula
`RETURNING id, run_code INTO v_new_id, v_new_code` referenciava `run_code`
sem qualificação — ambíguo entre a coluna da linha recém-inserida e o OUT
parameter homônimo. O PostgreSQL só detecta essa ambiguidade em tempo de
execução (CREATE FUNCTION não valida isso estaticamente), por isso o defeito
sobreviveu incólume a três rodadas de GATE 4 (STAGING, REVISION-01,
VALIDATION-REVISION-03) e só se manifestou agora, na primeira execução real.

O QUE ESTE HOTFIX FAZ — e o que NÃO faz:
Esta migration NÃO edita nem substitui o arquivo 6103 já executado (seu
histórico de migration permanece intocado). Ela aplica um único
CREATE OR REPLACE FUNCTION sobre a MESMA assinatura
(public.open_pokemon_catalog_sourcing_run(TEXT, UUID)), preservando
integralmente: assinatura; RETURNS TABLE; SECURITY DEFINER;
SET search_path = ''; stale recovery (Passo 0, threshold de 30 minutos);
validação de p_run_type (DRY_RUN/APPLY); validação de preflight (obrigatório
e com todas as checagens semânticas para APPLY; proibido para DRY_RUN);
tradução SELETIVA de unique_violation em SOURCE_BUSY por CONSTRAINT_NAME
(REVISION-01, Fix 6 — só uq_pokemon_catalog_sourcing_run_active_source vira
SOURCE_BUSY, qualquer outra colisão é relançada); grants/revokes idênticos;
comentário funcional idêntico.

ÚNICA alteração lógica: no INSERT de claim, a tabela-alvo recebe um alias
explícito (`AS inserted_run`) e a cláusula RETURNING qualifica as duas
colunas por esse alias (`inserted_run.id`, `inserted_run.run_code`),
eliminando a ambiguidade de forma inequívoca para o parser do PL/pgSQL — sem
renomear o OUT parameter `run_code` da função (que permanece com o mesmo
nome, preservando o contrato de retorno da RPC) e sem qualquer outra
refatoração oportunística no corpo da função.

Precedente do mesmo padrão de correção incremental (hotfix numerado à parte,
sem reescrever a migration já aplicada) já usado neste projeto: `3944b`,
`5035`/`5036` (fix de ambiguidade de `id`), `3904_fix_ambiguous_card_id_...`.

Pré-requisitos:
- Query 6100/6101 v1.1 - Pokemon Catalog Sourcing Run (tabela + triggers).
- Query 6103 v1.1 - Open Pokemon Catalog Sourcing Run Function (CONFIRMADO
  EXECUTADO no banco real — este hotfix depende do objeto já existir para
  fazer CREATE OR REPLACE sobre ele).
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
        -- HOTFIX 6109: alias explícito `inserted_run` na tabela-alvo do INSERT
        -- e qualificação de AMBAS as colunas na cláusula RETURNING
        -- (inserted_run.id, inserted_run.run_code). Sem o alias, `run_code`
        -- é ambíguo entre a coluna física da tabela e o OUT parameter
        -- homônimo `run_code` do RETURNS TABLE desta função — erro real do
        -- PostgreSQL (42702), detectável apenas em execução, nunca em
        -- CREATE FUNCTION. Nenhuma outra linha deste bloco foi alterada.
        INSERT INTO public.pokemon_catalog_sourcing_run AS inserted_run
            (asset_source_id, run_type, preflight_run_id)
        VALUES (v_asset_source_id, v_run_type, p_preflight_run_id)
        RETURNING
            inserted_run.id,
            inserted_run.run_code
        INTO
            v_new_id,
            v_new_code;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
        IF v_constraint_name = 'uq_pokemon_catalog_sourcing_run_active_source' THEN
            RETURN QUERY SELECT 'SOURCE_BUSY'::TEXT, NULL::UUID, NULL::TEXT, NULL::UUID, NULL::TEXT;
            RETURN;
        ELSE
            -- Qualquer outra unique_violation (ex.: colisão de run_code) NÃO
            -- é um SOURCE_BUSY -- é um erro de integridade real. Relança sem
            -- modificação (Fix 6, REVISION-01 — preservado intocado).
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
    'Abre (claim) um run de Pokémon Catalog Sourcing para POKEAPI, com reconciliação de stale e guard de concorrência SOURCE_BUSY. Ver docs/06a-pokemon-catalog-sourcing.md Seção 7.2. SERVICE_ROLE ONLY. (6109: RETURNING qualificado por alias, corrige 42702 ambiguous run_code — mesmo contrato de 6103.)';

REVOKE ALL ON FUNCTION public.open_pokemon_catalog_sourcing_run(TEXT, UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.open_pokemon_catalog_sourcing_run(TEXT, UUID)
    TO service_role;

COMMIT;
