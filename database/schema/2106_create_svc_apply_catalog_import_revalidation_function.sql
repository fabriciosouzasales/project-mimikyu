/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2106 - Create svc_apply_catalog_import_revalidation() Function
Versão......: 1.3
Status......: CANÔNICA — CONFIRMADO EXECUTADO (v1.3 aguardando validação funcional — sem Card Set com linha pendente disponível no momento)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07 (v1.2), 2026-08-09 (v1.3)

Correção v1.3 (2026-08-09): metadata de CATALOG_IMPORT_ROWS_
REVALIDATED passa a gravar card_set_name/card_set_code (resolvidos
a partir de v_job.card_set_id) no momento do evento — mesma decisão
das Queries 2080 v1.1/2082 v1.2, ver Log de Atualizações V1. Nota de
transparência: catalog_import_job.card_set_id tem FK ON DELETE
RESTRICT (Query 2060) — uma Coleção com qualquer job associado nunca
podia ser fisicamente excluída, então o JOIN-fallback que esta ação
já tinha (via catalog_import_job → card_set) nunca quebraria de
fato. Esta mudança é uma melhoria de consistência/performance (evita
o JOIN em toda leitura futura), não a correção de um bug ativo —
diferente da Query 2122 v1.1 (CARD_ASSET_MANUAL_IMPORT_COMPLETED),
onde o risco de entity_label órfão era real. Nenhuma mudança de
assinatura.

Descrição...:
Cria public.svc_apply_catalog_import_revalidation(), contrato
público chamado pela Edge Function revalidate-catalog-import-rows
(JWT verificado na própria Edge Function — esta função confia no
p_actor_id recebido, mesmo padrão de svc_* já usado por outras
integrações service_role). Recalcula catalog_import_row de um job
via internal.persist_catalog_import_revalidation() (Query 2105),
destrava linhas que falharam só por raridade não mapeada
(persistence_status FAILED + validation_status VALID) e atualiza
os contadores agregados do job.

Regras de Negócio:
- Escopo de status ampliado no mesmo dia (v1.2) para cobrir jobs
  COMPLETED_WITH_ERRORS (não só STAGED/CONFIRMING) — caminho real
  observado em produção (GYM1/SWSH1 com linhas FAILED por raridade
  não mapeada, terminadas em COMPLETED_WITH_ERRORS).
- `SELECT ... FOR UPDATE` no job — mesma linha não pode ser
  revalidada concorrentemente duas vezes.
- Um job COMPLETED_WITH_ERRORS com pelo menos uma linha destravada
  volta para CONFIRMING (nunca fica preso em "concluído com erro"
  depois que o erro real já foi corrigido) — nos demais casos, o
  status do job não muda.
- Grava catalog_admin_action_log
  (CATALOG_IMPORT_ROWS_REVALIDATED) só quando ao menos uma linha
  foi de fato alterada — chamadas "revalidar tudo" sem nenhuma
  linha pendente não geram ruído de auditoria.
- p_actor_id validado contra auth.users quando informado — nunca
  aceita um UUID arbitrário sem checagem.

Pré-requisitos:
- Query 2070/2071 - Create catalog_import_row Table.
- Query 2098 - Add Rarity Actions to Catalog Admin Action Log
  (CATALOG_IMPORT_ROWS_REVALIDATED).
- Query 2105 - Create internal.persist_catalog_import_revalidation() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.svc_apply_catalog_import_revalidation(
    p_job_id UUID,
    p_row_updates JSONB,
    p_actor_id UUID DEFAULT NULL
)
RETURNS TABLE(
    updated_count INTEGER,
    unblocked_count INTEGER,
    valid_rows INTEGER,
    needs_review_rows INTEGER,
    invalid_rows INTEGER,
    job_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_job public.catalog_import_job%ROWTYPE;
    v_rows_affected INTEGER;
    v_unblocked_count INTEGER;
    v_total_rows INTEGER;
    v_valid_rows INTEGER;
    v_needs_review_rows INTEGER;
    v_invalid_rows INTEGER;
    v_final_status TEXT;
    v_card_set_name TEXT;
    v_card_set_code TEXT;
BEGIN
    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'SVC_APPLY_CATALOG_IMPORT_REVALIDATION_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    IF p_actor_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_actor_id) THEN
        RAISE EXCEPTION 'SVC_APPLY_CATALOG_IMPORT_REVALIDATION_ACTOR_NOT_FOUND: p_actor_id não corresponde a um usuário existente (%).', p_actor_id;
    END IF;

    SELECT * INTO v_job FROM public.catalog_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SVC_APPLY_CATALOG_IMPORT_REVALIDATION_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    IF v_job.status NOT IN ('STAGED', 'CONFIRMING', 'COMPLETED_WITH_ERRORS') THEN
        RAISE EXCEPTION 'SVC_APPLY_CATALOG_IMPORT_REVALIDATION_INVALID_STATUS: o job está em % — só é possível revalidar STAGED, CONFIRMING ou COMPLETED_WITH_ERRORS.', v_job.status;
    END IF;

    SELECT name, code INTO v_card_set_name, v_card_set_code
    FROM public.card_set WHERE id = v_job.card_set_id;

    v_rows_affected := internal.persist_catalog_import_revalidation(p_job_id, p_row_updates);

    UPDATE public.catalog_import_row
        SET persistence_status = 'PENDING', error_detail = NULL
        WHERE job_id = p_job_id
          AND persistence_status = 'FAILED'
          AND validation_status = 'VALID';

    GET DIAGNOSTICS v_unblocked_count = ROW_COUNT;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE validation_status = 'VALID'),
        COUNT(*) FILTER (WHERE validation_status = 'NEEDS_REVIEW'),
        COUNT(*) FILTER (WHERE validation_status = 'INVALID')
    INTO v_total_rows, v_valid_rows, v_needs_review_rows, v_invalid_rows
    FROM public.catalog_import_row
    WHERE job_id = p_job_id;

    v_final_status := CASE
        WHEN v_job.status = 'COMPLETED_WITH_ERRORS' AND v_unblocked_count > 0 THEN 'CONFIRMING'
        ELSE v_job.status
    END;

    UPDATE public.catalog_import_job
        SET total_rows = v_total_rows,
            valid_rows = v_valid_rows,
            status = v_final_status
        WHERE id = p_job_id;

    IF v_rows_affected > 0 THEN
        INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
            VALUES (p_actor_id, 'CATALOG_IMPORT_ROWS_REVALIDATED', 'CATALOG_IMPORT_JOB', p_job_id,
                    jsonb_build_object(
                        'card_set_name', v_card_set_name,
                        'card_set_code', v_card_set_code,
                        'rows_updated', v_rows_affected,
                        'rows_unblocked', v_unblocked_count
                    ));
    END IF;

    RETURN QUERY
        SELECT v_rows_affected, v_unblocked_count, v_valid_rows, v_needs_review_rows, v_invalid_rows, v_final_status;
END;
$$;

GRANT EXECUTE ON FUNCTION public.svc_apply_catalog_import_revalidation(UUID, JSONB, UUID) TO service_role;

-- ================================================================
-- Confirmado executado e validado funcionalmente (2026-08-07):
-- definição em produção lida via pg_get_functiondef() e conferida
-- idêntica a este arquivo (v1.2, escopo COMPLETED_WITH_ERRORS já
-- incorporado). Validado ponta a ponta contra o job GYM1 real: 34
-- linhas destravadas e persistidas como Card via confirmação
-- subsequente, decision_status preservado nas 132 linhas,
-- actor_id real gravado em catalog_admin_action_log. Usado em
-- produção pelo botão "Revalidar tudo" de /catalogo/raridades.
-- ================================================================
--
-- v1.3 CONFIRMADO EXECUTADO (2026-08-09): CREATE OR REPLACE
-- aplicado sem erro ("Success"). Validação funcional (metadata com
-- card_set_name/card_set_code preenchidos) ainda pendente no
-- momento desta nota — nenhum Card Set com linha pendente de
-- revalidação disponível para o teste; a próxima chamada real desta
-- function em produção fecha essa validação.
-- ================================================================
