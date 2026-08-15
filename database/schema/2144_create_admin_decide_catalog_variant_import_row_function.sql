/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2144 - Create admin_decide_catalog_variant_import_row() Function
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_decide_catalog_variant_import_row(), função pública
SECURITY DEFINER — único caminho pelo qual decision_status de uma
ou mais catalog_variant_import_row (Query 2138) é alterado.
Equivalente exata de admin_decide_catalog_import_row() (Query 2081)
para o bloco Card Variant (Incremento 3, ADR-028). Não persiste
nada em public.card_variant — só ajusta o estado de staging. A
persistência real acontece em
admin_confirm_catalog_variant_import() (Query 2145).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- Aceita array de ids — decisão única ou em massa, mesma função.
- Sem parâmetro de correção de dado (diferença deliberada frente à
  Query 2081): normalized_data de uma linha de variante só contém
  variant_type_id, já resolvido automaticamente contra
  card_variant_type_external_mapping no processamento — não há
  campo livre para um administrador corrigir manualmente nesta
  rodada.
- Só decide linhas cujo job ainda está em status = 'STAGED' — mesmo
  raciocínio da Query 2081.
- decision_status restrito a PENDING, APPROVED, REJECTED ou SKIPPED.
- Regra própria deste bloco: decision_status = 'APPROVED' é
  recusado para qualquer linha com validation_status <> 'VALID'
  (ou seja, NEEDS_REVIEW) — uma linha sem card_variant_type
  resolvido não tem o que confirmar; precisa primeiro ganhar um
  mapeamento em card_variant_type_external_mapping e ser
  reprocessada, nunca ser aprovada "no escuro". REJECTED/SKIPPED
  continuam permitidos para NEEDS_REVIEW (descartar ou pular uma
  linha sem mapeamento é uma decisão legítima).
- Não grava em catalog_admin_action_log — mesmo raciocínio da Query
  2081 (decisão reversível, de baixo risco).
- Retorna a quantidade de linhas efetivamente atualizadas.

Pré-requisitos:
- Query 2138 - Create Catalog Variant Import Row Table.
- Query 2136 - Create Catalog Variant Import Job Table.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_decide_catalog_variant_import_row(
    p_row_ids UUID[],
    p_decision_status TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_decision_status TEXT;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_FORBIDDEN: apenas administradores podem decidir sobre linhas de importação de variantes.';
    END IF;

    IF p_row_ids IS NULL OR array_length(p_row_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_MISSING_IDS: p_row_ids é obrigatório e não pode ser vazio.';
    END IF;

    v_decision_status := UPPER(BTRIM(p_decision_status));

    IF v_decision_status NOT IN ('PENDING', 'APPROVED', 'REJECTED', 'SKIPPED') THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_INVALID_STATUS: decision_status deve ser PENDING, APPROVED, REJECTED ou SKIPPED (recebido: %).', p_decision_status;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.catalog_variant_import_row r
        JOIN public.catalog_variant_import_job j ON j.id = r.job_id
        WHERE r.id = ANY(p_row_ids)
          AND j.status <> 'STAGED'
    ) THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_JOB_NOT_STAGED: uma ou mais linhas pertencem a um job que não está em revisão (status STAGED).';
    END IF;

    IF v_decision_status = 'APPROVED' AND EXISTS (
        SELECT 1
        FROM public.catalog_variant_import_row r
        WHERE r.id = ANY(p_row_ids)
          AND r.validation_status <> 'VALID'
    ) THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_NEEDS_REVIEW: uma ou mais linhas estão NEEDS_REVIEW (sem card_variant_type resolvido) e não podem ser aprovadas — resolva o mapeamento em card_variant_type_external_mapping e reprocesse antes de aprovar.';
    END IF;

    UPDATE public.catalog_variant_import_row
        SET decision_status = v_decision_status
        WHERE id = ANY(p_row_ids);

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected = 0 THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_NOT_FOUND: nenhuma linha encontrada para os ids informados.';
    END IF;

    RETURN v_rows_affected;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_decide_catalog_variant_import_row(UUID[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_decide_catalog_variant_import_row(UUID[], TEXT) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- que exercitou: aprovação de linha VALID (sucesso), bloqueio de
-- aprovação de linha NEEDS_REVIEW (ADMIN_DECIDE_CATALOG_VARIANT_
-- IMPORT_ROW_NEEDS_REVIEW), rejeição de linha NEEDS_REVIEW (permitida),
-- e negação para chamador não-admin (ADMIN_DECIDE_CATALOG_VARIANT_
-- IMPORT_ROW_FORBIDDEN, via request.jwt.claims sem sub válido).
-- role_routine_grants confirma EXECUTE só para 'authenticated' (além
-- do owner 'postgres'), nenhum grant para anon/PUBLIC.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT routine_name, security_type FROM information_schema.routines
-- WHERE routine_name = 'admin_decide_catalog_variant_import_row';
-- Esperado: security_type = 'DEFINER'.
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants
-- WHERE routine_name = 'admin_decide_catalog_variant_import_row';
-- Esperado: só 'authenticated' com EXECUTE, nenhum grant para anon/PUBLIC.
-- ================================================================
