/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2145 - Create admin_confirm_catalog_variant_import() Function
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_confirm_catalog_variant_import(), função pública
SECURITY DEFINER — único caminho pelo qual as propostas de um
catalog_variant_import_job (Query 2136) se tornam Card Variants
reais em public.card_variant. Chama internal.write_card_variant()
(Query 2143) diretamente, mesma camada canônica isolada do padrão
já usado por Importar Cartas. Equivalente exata de
admin_confirm_catalog_import() (Query 2082) para o bloco Card
Variant (Incremento 3, ADR-028).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- SELECT ... FOR UPDATE na linha do job trava concorrência — mesmo
  raciocínio da Query 2082.
- Só aceita jobs em STAGED ou CONFIRMING.
- p_row_ids (opcional): permite confirmar um subconjunto das linhas
  aprovadas, em sublotes — quem decide o tamanho do lote é o
  chamador (nenhuma UI/Server Action criada nesta rodada; validado
  diretamente por RPC). NULL processa todas as linhas elegíveis.
- Só processa linhas com persistence_status = 'PENDING' E
  decision_status IN ('APPROVED', 'SKIPPED').
- Linha SKIPPED: persistence_status = 'UNCHANGED', sem chamar
  internal.write_card_variant().
- Linha APPROVED: revalidação defensiva antes de qualquer escrita —
  validation_status precisa ser 'VALID' E normalized_data precisa
  conter variant_type_id (mesma regra já aplicada em
  admin_decide_catalog_variant_import_row, Query 2144, reconferida
  aqui porque o estado pode, em tese, ter mudado entre a decisão e
  a confirmação). Uma linha que falhar essa revalidação é tratada
  como falha isolada da própria linha (persistence_status =
  'FAILED'), nunca interrompe as demais.
- match_status é recalculado aqui contra public.card_variant real,
  nunca herdado do processamento — o catálogo pode ter mudado entre
  o processamento/decisão e esta confirmação (ex.: outra importação
  ou edição manual já criou a mesma variante nesse meio-tempo).
  Diferente de Importar Cartas, não existe conceito de CONFLICT de
  conteúdo aqui: a existência de (card_id, variant_type_id) é
  binária (card_variant não tem campo mutável comparável a
  name/rarity_id/category_id de card) — só NEW ou MATCHED.
  - MATCHED (já existe): NENHUMA escrita — persistence_status =
    'UNCHANGED', matched_variant_id/resulting_variant_id apontam
    para a variante existente. Nunca sobrescreve silenciosamente.
  - NEW: internal.write_card_variant('CREATE', ...) com
    variant_order = próximo inteiro livre para aquele card_id
    (MAX(variant_order) do card_id + 1, ou 1 se a Card ainda não
    tem nenhuma variante) — nunca lido de raw_data/normalized_data.
    is_default nunca é definido (nasce FALSE pelo default da
    coluna, Query 160) — persistence_status = 'INSERTED'.
- Cada linha isolada em seu próprio bloco de exceção — mesmo
  raciocínio da Query 2082 (bloco EXCEPTION nativo do PL/pgSQL, sem
  savepoint manual; falha sistêmica ainda aborta a transação
  inteira).
- Contadores do job recalculados por agregação ao final da chamada,
  nunca incrementados. catalog_variant_import_job não tem
  updated_rows (diferença estrutural real já registrada na Query
  2136 — variant não tem conteúdo para divergir/atualizar).
- Status final do job — mesma lógica de três camadas da Query 2082
  v1.1: decision_status = 'PENDING' restante (linha nunca decidida)
  força STAGED antes de qualquer outra avaliação; senão
  persistence_status = 'PENDING' restante força CONFIRMING (sublote
  parcial); senão failed_rows > 0 força COMPLETED_WITH_ERRORS;
  senão COMPLETED.
- Idempotência: uma segunda chamada só encontra linhas com
  persistence_status = 'PENDING' — linhas já INSERTED/UNCHANGED/
  FAILED nunca são reprocessadas. Chamar de novo um job já
  COMPLETED simplesmente não encontra nada a fazer e devolve os
  mesmos contadores agregados.
- Uma única linha de auditoria agregada por chamada bem-sucedida
  (catalog_admin_action_log, ação CARD_VARIANT_IMPORT_CONFIRMED,
  entity_type CATALOG_VARIANT_IMPORT_JOB, entity_id = job_id) — só
  quando o status final é COMPLETED/COMPLETED_WITH_ERRORS. Domínio
  ampliado pela Query 2146 (widen catalog_admin_action_log).

Pré-requisitos:
- Query 2136/2137 - Create Catalog Variant Import Job Table + Triggers.
- Query 2138/2139 - Create Catalog Variant Import Row Table + Triggers.
- Query 2143 - Create internal.write_card_variant() Function.
- Query 2146 - Widen Catalog Admin Action Log for Variant Import.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_confirm_catalog_variant_import(
    p_job_id UUID,
    p_row_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
    inserted_count INTEGER,
    unchanged_count INTEGER,
    failed_count INTEGER,
    pending_count INTEGER,
    job_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_job public.catalog_variant_import_job%ROWTYPE;
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_existing_variant public.card_variant%ROWTYPE;
    v_variant_type_id UUID;
    v_match_status TEXT;
    v_result_variant_id UUID;
    v_next_order INTEGER;
    v_error_message TEXT;
    v_pending_rows INTEGER;
    v_failed_rows INTEGER;
    v_decision_pending_rows INTEGER;
    v_final_status TEXT;
    v_card_set_name TEXT;
    v_card_set_code TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_FORBIDDEN: apenas administradores podem confirmar uma importação de variantes.';
    END IF;

    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    SELECT * INTO v_job FROM public.catalog_variant_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    IF v_job.status NOT IN ('STAGED', 'CONFIRMING') THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_STATUS: o job está em % — só é possível confirmar a partir de STAGED ou CONFIRMING.', v_job.status;
    END IF;

    SELECT name, code INTO v_card_set_name, v_card_set_code
    FROM public.card_set WHERE id = v_job.card_set_id;

    IF v_job.status = 'STAGED' THEN
        UPDATE public.catalog_variant_import_job SET status = 'CONFIRMING' WHERE id = p_job_id;
    END IF;

    FOR v_row IN
        SELECT r.*
        FROM public.catalog_variant_import_row r
        WHERE r.job_id = p_job_id
          AND r.persistence_status = 'PENDING'
          AND r.decision_status IN ('APPROVED', 'SKIPPED')
          AND (p_row_ids IS NULL OR r.id = ANY(p_row_ids))
        ORDER BY r.created_at
        FOR UPDATE OF r
    LOOP
        BEGIN
            IF v_row.decision_status = 'SKIPPED' THEN
                UPDATE public.catalog_variant_import_row
                    SET persistence_status = 'UNCHANGED'
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            -- decision_status = 'APPROVED' a partir daqui.
            -- Revalidação defensiva: mesma regra já aplicada na decisão
            -- (Query 2144), reconferida porque o estado pode, em tese,
            -- ter mudado entre a decisão e esta confirmação.
            IF v_row.validation_status <> 'VALID' THEN
                RAISE EXCEPTION 'NEEDS_REVIEW_CANNOT_BE_CONFIRMED: linha sem card_variant_type resolvido não pode ser confirmada.';
            END IF;

            v_variant_type_id := NULLIF(v_row.normalized_data->>'variant_type_id', '')::UUID;
            IF v_variant_type_id IS NULL THEN
                RAISE EXCEPTION 'MISSING_VARIANT_TYPE_ID: normalized_data não contém variant_type_id resolvido.';
            END IF;

            -- match_status recalculado contra o catálogo real — nunca herdado.
            SELECT cv.* INTO v_existing_variant
            FROM public.card_variant cv
            WHERE cv.card_id = v_row.card_id
              AND cv.variant_type_id = v_variant_type_id
            LIMIT 1;

            IF v_existing_variant.id IS NULL THEN
                v_match_status := 'NEW';
            ELSE
                v_match_status := 'MATCHED';
            END IF;

            IF v_match_status = 'MATCHED' THEN
                -- Já existe: nenhuma escrita. Nunca sobrescreve silenciosamente.
                UPDATE public.catalog_variant_import_row
                    SET match_status = v_match_status,
                        persistence_status = 'UNCHANGED',
                        matched_variant_id = v_existing_variant.id,
                        resulting_variant_id = v_existing_variant.id,
                        error_detail = NULL
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            -- NEW: variant_order é sempre o próximo inteiro livre para o
            -- card_id, calculado só a partir do que já existe em
            -- card_variant — nunca lido da fonte. is_default nunca é
            -- informado (nasce FALSE pelo default da coluna).
            SELECT COALESCE(MAX(variant_order), 0) + 1 INTO v_next_order
            FROM public.card_variant
            WHERE card_id = v_row.card_id;

            v_result_variant_id := internal.write_card_variant(
                'CREATE', NULL, v_row.card_id, v_variant_type_id, v_next_order
            );

            UPDATE public.catalog_variant_import_row
                SET match_status = v_match_status,
                    persistence_status = 'INSERTED',
                    matched_variant_id = NULL,
                    resulting_variant_id = v_result_variant_id,
                    error_detail = NULL
                WHERE id = v_row.id;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
            UPDATE public.catalog_variant_import_row
                SET persistence_status = 'FAILED', error_detail = v_error_message
                WHERE id = v_row.id;
        END;
    END LOOP;

    -- Recalcula os contadores do job inteiramente por agregação.
    UPDATE public.catalog_variant_import_job j
        SET total_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id),
            valid_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND validation_status = 'VALID'),
            rejected_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND decision_status = 'REJECTED'),
            inserted_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'INSERTED'),
            unchanged_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'UNCHANGED'),
            skipped_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND decision_status = 'SKIPPED'),
            failed_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'FAILED')
        WHERE j.id = p_job_id;

    SELECT COUNT(*)
    INTO v_decision_pending_rows
    FROM public.catalog_variant_import_row
    WHERE job_id = p_job_id
      AND decision_status = 'PENDING';

    SELECT
        COUNT(*) FILTER (WHERE persistence_status = 'PENDING'),
        COUNT(*) FILTER (WHERE persistence_status = 'FAILED')
    INTO v_pending_rows, v_failed_rows
    FROM public.catalog_variant_import_row
    WHERE job_id = p_job_id
      AND decision_status IN ('APPROVED', 'SKIPPED');

    IF v_decision_pending_rows > 0 THEN
        v_final_status := 'STAGED';
    ELSIF v_pending_rows > 0 THEN
        v_final_status := 'CONFIRMING';
    ELSIF v_failed_rows > 0 THEN
        v_final_status := 'COMPLETED_WITH_ERRORS';
    ELSE
        v_final_status := 'COMPLETED';
    END IF;

    UPDATE public.catalog_variant_import_job SET status = v_final_status WHERE id = p_job_id;

    IF v_final_status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS') THEN
        INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
            VALUES (auth.uid(), 'CARD_VARIANT_IMPORT_CONFIRMED', 'CATALOG_VARIANT_IMPORT_JOB', p_job_id,
                    jsonb_build_object(
                        'card_set_id', v_job.card_set_id,
                        'card_set_name', v_card_set_name,
                        'card_set_code', v_card_set_code,
                        'final_status', v_final_status
                    ));
    END IF;

    RETURN QUERY
        SELECT j.inserted_rows, j.unchanged_rows, j.failed_rows, v_pending_rows, j.status
        FROM public.catalog_variant_import_job j
        WHERE j.id = p_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- contra dados reais do ME2.5 (card_set_id 3f4de467-...), cobrindo:
-- APPROVED de linha nova -> INSERTED, variant_order correto (MAX+1),
-- is_default FALSE; APPROVED de linha já existente -> UNCHANGED, sem
-- escrita; REJECTED -> persistence_status nunca sai de PENDING, jamais
-- processada; confirmação em sublote (p_row_ids) seguida de repetição
-- do MESMO sublote -> idempotente, sem duplicata, contadores estáveis;
-- conclusão do job em COMPLETED; nova tentativa de confirmar um job já
-- COMPLETED -> corretamente rejeitada (ADMIN_CONFIRM_CATALOG_VARIANT_
-- IMPORT_INVALID_STATUS), mesmo comportamento de admin_confirm_
-- catalog_import; chamador não-admin -> FORBIDDEN; nenhuma duplicata em
-- card_variant (2 linhas novas, exatamente as esperadas); entrada de
-- catalog_admin_action_log gravada com action/entity_type corretos.
-- Produção verificada limpa após o teste: catalog_variant_import_job/
-- row com 0 linhas, card_variant da amostra (me02.5-001/002) inalterado
-- (6 linhas, mesmas de antes). role_routine_grants confirma EXECUTE só
-- para 'authenticated' (além do owner).
--
-- Achado à parte, fora do escopo deste Incremento (não corrigido aqui,
-- reportado a Fabrício): public.card_variant — e, pelo visto,
-- praticamente toda a public schema (card, catalog_variant_import_job/
-- row, card_variant_type_external_mapping) — concede REFERENCES/
-- TRIGGER/TRUNCATE para anon e authenticated, um resquício de
-- privilégio padrão nunca revogado. TRUNCATE em particular NÃO é
-- coberto por RLS — anon hoje consegue truncar essas tabelas por
-- completo. Recomendo um Finding dedicado (mesmo padrão da auditoria
-- de segurança de 2026-08-13/14), fora deste Incremento.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT routine_name, security_type FROM information_schema.routines
-- WHERE routine_name = 'admin_confirm_catalog_variant_import';
-- Esperado: security_type = 'DEFINER'.
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants
-- WHERE routine_name = 'admin_confirm_catalog_variant_import';
-- Esperado: só 'authenticated' com EXECUTE.
-- ================================================================
