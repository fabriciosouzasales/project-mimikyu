/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2081 - Create admin_decide_catalog_import_row() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Cria admin_decide_catalog_import_row(), função pública SECURITY
DEFINER — único caminho pelo qual decision_status de uma ou mais
catalog_import_row (Query 2070) é alterado. Usada pela tela de
Revisão (Etapa 2 do fluxo de ingestão, ADR-024): aprovar, rejeitar
ou pular uma linha, e opcionalmente corrigir um campo antes de
aprovar. Não persiste nada em public.card — só ajusta o estado de
staging. A persistência real só acontece em
admin_confirm_catalog_import() (Query 2082).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- Aceita um array de ids para permitir tanto a decisão de uma única
  linha quanto uma ação em massa ("aprovar selecionadas") a partir
  da mesma função — sem duplicar lógica em duas funções.
- p_corrected_normalized_data (opcional) sobrescreve
  normalized_data da linha antes de aplicar a decisão — só é aceito
  quando exatamente uma linha é informada em p_row_ids: uma
  correção de campo é, por natureza, específica de uma linha, nunca
  aplicável em massa.
- Só decide linhas cujo job ainda está em status = 'STAGED' — o
  estado em que o ADR-024 define a revisão como possível. Job em
  RECEIVED/PROCESSING ainda não tem linhas prontas para decisão;
  job em CONFIRMING ou em estado terminal não aceita mais decisões
  (a confirmação já está em curso ou já terminou).
- decision_status restrito a PENDING (permite desfazer uma decisão
  anterior), APPROVED, REJECTED ou SKIPPED.
- Não grava em catalog_admin_action_log: decisões de revisão são
  reversíveis e de baixo risco (cada linha já guarda seu próprio
  decision_status como registro) — só a confirmação final, que
  persiste em public.card, justifica uma entrada de auditoria
  administrativa (ver Query 2054).
- Retorna a quantidade de linhas efetivamente atualizadas.

Pré-requisitos:
- Query 2070 - Create Catalog Import Row Table.
- Query 2060 - Create Catalog Import Job Table.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_decide_catalog_import_row(
    p_row_ids UUID[],
    p_decision_status TEXT,
    p_corrected_normalized_data JSONB DEFAULT NULL
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
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_IMPORT_ROW_FORBIDDEN: apenas administradores podem decidir sobre linhas de importação.';
    END IF;

    IF p_row_ids IS NULL OR array_length(p_row_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_IMPORT_ROW_MISSING_IDS: p_row_ids é obrigatório e não pode ser vazio.';
    END IF;

    v_decision_status := UPPER(BTRIM(p_decision_status));

    IF v_decision_status NOT IN ('PENDING', 'APPROVED', 'REJECTED', 'SKIPPED') THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_IMPORT_ROW_INVALID_STATUS: decision_status deve ser PENDING, APPROVED, REJECTED ou SKIPPED (recebido: %).', p_decision_status;
    END IF;

    IF p_corrected_normalized_data IS NOT NULL AND array_length(p_row_ids, 1) <> 1 THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_IMPORT_ROW_BULK_CORRECTION: uma correção de dados só pode ser aplicada a uma única linha por vez.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.catalog_import_row r
        JOIN public.catalog_import_job j ON j.id = r.job_id
        WHERE r.id = ANY(p_row_ids)
          AND j.status <> 'STAGED'
    ) THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_IMPORT_ROW_JOB_NOT_STAGED: uma ou mais linhas pertencem a um job que não está em revisão (status STAGED).';
    END IF;

    IF p_corrected_normalized_data IS NOT NULL THEN
        UPDATE public.catalog_import_row
            SET decision_status = v_decision_status,
                normalized_data = p_corrected_normalized_data
            WHERE id = p_row_ids[1];
    ELSE
        UPDATE public.catalog_import_row
            SET decision_status = v_decision_status
            WHERE id = ANY(p_row_ids);
    END IF;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected = 0 THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_IMPORT_ROW_NOT_FOUND: nenhuma linha encontrada para os ids informados.';
    END IF;

    RETURN v_rows_affected;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_decide_catalog_import_row(UUID[], TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_decide_catalog_import_row(UUID[], TEXT, JSONB) TO authenticated;
