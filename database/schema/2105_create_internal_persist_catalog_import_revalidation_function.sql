/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2105 - Create internal.persist_catalog_import_revalidation() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria internal.persist_catalog_import_revalidation(), camada
canônica de escrita em lote para a revalidação de
catalog_import_row depois que uma Raridade/mapeamento é
cadastrado ou corrigido — permite recalcular linhas já staged sem
reimportar do zero (ADR-024, emenda "Raridade: mapeamento self-
service e revalidação"). Chamada exclusivamente por
svc_apply_catalog_import_revalidation() (Query 2106, o único
chamador autorizado — EXECUTE revogado de authenticated/anon,
mesmo princípio de isolamento de internal.write_card()).

Regras de Negócio:
- p_row_updates é um array JSONB não vazio — cada elemento
  {row_id, normalized_data, validation_status, match_status,
  matched_card_id} — recalculado pelo chamador (Edge Function
  revalidate-catalog-import-rows, via o módulo compartilhado
  _shared/catalog-normalization/), não por esta função.
- jsonb_to_recordset() + UPDATE ... FROM é uma escrita em lote
  única (não um loop linha a linha) — todas as linhas do array são
  aplicadas na mesma instrução SQL, mais eficiente para jobs com
  centenas de linhas.
- Só atualiza linhas cujo (id, job_id) já existiam — nunca insere
  linha nova, nunca cruza jobs (WHERE r.id = u.row_id AND r.job_id
  = p_job_id).
- Retorna a contagem real de linhas afetadas (GET DIAGNOSTICS ...
  ROW_COUNT), nunca assume sucesso total.

Pré-requisitos:
- Query 2070/2071 - Create catalog_import_row Table.
================================================================
*/

CREATE OR REPLACE FUNCTION internal.persist_catalog_import_revalidation(
    p_job_id UUID,
    p_row_updates JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rows_affected INTEGER;
BEGIN
    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_PERSIST_CATALOG_IMPORT_REVALIDATION_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    IF p_row_updates IS NULL
       OR JSONB_TYPEOF(p_row_updates) <> 'array'
       OR JSONB_ARRAY_LENGTH(p_row_updates) = 0
    THEN
        RAISE EXCEPTION 'INTERNAL_PERSIST_CATALOG_IMPORT_REVALIDATION_MISSING_UPDATES: p_row_updates deve ser um array JSONB não vazio.';
    END IF;

    UPDATE public.catalog_import_row r
        SET normalized_data = u.normalized_data,
            validation_status = u.validation_status,
            match_status = u.match_status,
            matched_card_id = u.matched_card_id
        FROM jsonb_to_recordset(p_row_updates) AS u(
            row_id UUID,
            normalized_data JSONB,
            validation_status TEXT,
            match_status TEXT,
            matched_card_id UUID
        )
        WHERE r.id = u.row_id
          AND r.job_id = p_job_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    RETURN v_rows_affected;
END;
$$;

REVOKE ALL ON FUNCTION internal.persist_catalog_import_revalidation(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.persist_catalog_import_revalidation(UUID, JSONB) FROM anon;
REVOKE ALL ON FUNCTION internal.persist_catalog_import_revalidation(UUID, JSONB) FROM authenticated;

-- ================================================================
-- Confirmado executado e validado funcionalmente (2026-08-07):
-- definição em produção lida via pg_get_functiondef() e conferida
-- idêntica a este arquivo. Validado ponta a ponta contra o job
-- GYM1 real: 132 linhas recalculadas, decision_status preservado
-- em todas.
-- ================================================================
