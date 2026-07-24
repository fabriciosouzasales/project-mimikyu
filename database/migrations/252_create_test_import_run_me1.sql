-- Project Mimikyu
-- Query 252 - Create Test Import Run ME1
-- Status: CONFIRMADA EXECUTADA (`npx supabase db push` → "Finished supabase db
-- push"; reconfirmada por consulta real pós-execução)
-- Ver docs/06-pipeline-importacao.md, "Sprint B3.8", para o contexto completo
-- do marco real que esta migration desbloqueou (primeira resposta de ponta a
-- ponta da TCGdex através da Edge Function import-card-assets).
--
-- Cria um asset_import_run real para a coleção ME1 (já integrada à TCGdex via
-- card_set_external_reference, Query 910), usado para testar o fluxo de
-- importação de ponta a ponta pela primeira vez no projeto.
--
-- Episódio real, registrado por transparência: a primeira versão desta
-- migration (run_code fixado manualmente como 'RUN-ME1-TEST-0001', sem a
-- coluna run_type) FALHOU ao ser aplicada — run_type é NOT NULL, sem DEFAULT.
-- Em vez de adivinhar um valor, os valores reais aceitos foram confirmados
-- por consulta direta ao catálogo do PostgreSQL (information_schema.columns
-- + pg_constraint/pg_get_constraintdef): run_type IN ('MISSING_ONLY',
-- 'REFRESH_EXISTING', 'RETRY_FAILURES', 'SINGLE_CARD', 'FULL_CARD_SET') —
-- o mesmo conjunto já documentado na Query 220 (docs/05-modelo-de-dados.md),
-- uma reconfirmação real, não uma descoberta nova. A versão corrigida abaixo
-- também deixou de forçar run_code manualmente, confiando no DEFAULT da
-- tabela (sequência asset_import_run_code_seq) para reduzir o acoplamento à
-- implementação interna de asset_import_run.

DO $$
DECLARE
    v_card_set_id uuid;
    v_asset_source_id uuid;
BEGIN
    SELECT id
    INTO v_card_set_id
    FROM public.card_set
    WHERE code = 'ME1';

    IF v_card_set_id IS NULL THEN
        RAISE EXCEPTION 'Coleção ME1 não encontrada.';
    END IF;

    SELECT id
    INTO v_asset_source_id
    FROM public.asset_source
    WHERE code = 'TCGDEX';

    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'Asset Source TCGDEX não encontrado.';
    END IF;

    INSERT INTO public.asset_import_run (
        asset_source_id,
        card_set_id,
        run_type,
        status
    )
    VALUES (
        v_asset_source_id,
        v_card_set_id,
        'FULL_CARD_SET',
        'PENDING'
    );
END;
$$;
