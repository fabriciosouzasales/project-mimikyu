/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6108 - Create Close Failed Pokemon Catalog Sourcing Run
               Function (AUXILIAR — entrypoint)
Versão......: 1.0 (PROPOSTA — GATE 3 STAGING, REVISION-01)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, REVISION-01, item 5 da auditoria GATE 4)

Justificativa de existência (GATE 4 permitiu e pediu explicitamente 6107+
para este fim — "APPLY FAILURE CLOSEOUT"):
apply_pokemon_catalog_sourcing_run() (Query 6105) preserva, por desenho
aprovado, o comportamento "divergência/erro → RAISE EXCEPTION → ROLLBACK
canônico total" (Seção 10: "nenhuma escrita canônica" em caso de falha). Mas
RAISE EXCEPTION reverte TUDO dentro daquela transação, inclusive a própria
transição de status para APPLYING — o run físico permanece em PENDING. Sem
nenhuma ação corretiva, isso bloqueia a Fonte (via o índice UNIQUE parcial de
run ativo, Query 6100) por até 30 minutos, até o stale recovery de open_run
(Query 6103) reconciliar. Esta função dá ao caller (o script Deno, que já
capturou a exceção lançada por 6105 em seu próprio try/catch) um meio
imediato e mínimo de marcar aquele run como FAILED, liberando a Fonte na
hora — sem esperar o threshold de 30 minutos.

Descrição resumida:
- Aceita QUALQUER run em estado ATIVO (PENDING, ACQUIRING, PLANNING,
  APPLYING) de QUALQUER run_type — todas as transições para FAILED a partir
  de um estado ativo já são legais na máquina de estados (Query 6101), então
  esta função não precisa (nem deve) ser específica de APPLY: também serve
  para o caller marcar como FAILED um DRY_RUN cuja aquisição HTTP falhou
  antes de chegar a chamar PLAN.
- Rejeita runs já em estado TERMINAL (nada a fechar).
- Preserva identidade (não altera id/run_code/asset_source_id/run_type/
  preflight_run_id/created_at — a própria máquina de estados já bloquearia
  qualquer tentativa nesse sentido, mas esta função nunca tenta).
- Sanitiza error_summary: remove quebras de linha/tabulação (CR/LF/TAB) e
  trunca em 2000 caracteres, nunca grava string vazia (usa um valor padrão
  'CLOSED_BY_CALLER' quando o caller não fornece motivo).
- Ao transicionar para FAILED, o run sai do conjunto ACTIVE e o índice
  UNIQUE parcial de run ativo (uq_pokemon_catalog_sourcing_run_active_source)
  passa a permitir um novo claim imediatamente — "libera o unique active
  guard" tal como exigido.

SECURITY DEFINER + SET search_path = ''. SERVICE_ROLE ONLY.

Grants:
- REVOKE EXECUTE de PUBLIC, anon, authenticated.
- GRANT EXECUTE a service_role.

Pré-requisitos:
- Query 6100/6101 v1.1 - Pokemon Catalog Sourcing Run (lifecycle run_type-
  aware, REVISION-01).
===============================================================================
*/

BEGIN;

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
        finished_at = NOW()
    WHERE id = p_run_id;

    RETURN QUERY SELECT 'FAILED'::TEXT, p_run_id, 'FAILED'::TEXT;
END;
$$;

COMMENT ON FUNCTION public.close_failed_pokemon_catalog_sourcing_run(UUID, TEXT) IS
    'AUXILIAR entrypoint — fecha imediatamente como FAILED um run ATIVO cujo erro já foi capturado pelo caller (ex.: exceção de apply_pokemon_catalog_sourcing_run), liberando o guard de run ativo sem esperar o stale recovery de 30 minutos. Ver docs/06a-pokemon-catalog-sourcing.md Seção 10. SERVICE_ROLE ONLY.';

REVOKE ALL ON FUNCTION public.close_failed_pokemon_catalog_sourcing_run(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.close_failed_pokemon_catalog_sourcing_run(UUID, TEXT)
    TO service_role;

COMMIT;
