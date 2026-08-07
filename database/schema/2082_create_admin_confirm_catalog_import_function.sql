/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2082 - Create admin_confirm_catalog_import() Function
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01 (v1.0), 2026-08-07 (v1.1)

Correção v1.1 (2026-08-07): bug real encontrado pela validação `2818`
do fechamento do Ciclo 2 — o cálculo do status final do job (fim da
função) só considerava linhas `PENDING` de persistência dentro do
subconjunto `decision_status IN ('APPROVED', 'SKIPPED')`, ignorando
por completo linhas com `decision_status = 'PENDING'` (nunca
decididas por nenhum administrador — o caso típico é uma linha
`CONFLICT` que nasceu `PENDING` e nunca foi revisada). Consequência
real observada em produção: 2 jobs (`0a067e94-b665-4d74-b47f-
2635d12e22a9`, 9 linhas; `3ea4752c-cf6d-4fb9-8228-224f96c11030`, 1
linha) chegaram a `COMPLETED` com linhas nunca decididas — violação
direta da regra já descrita em `ADR-024` ("Se ainda existir alguma
linha com `decision_status = PENDING` ou `persistence_status =
PENDING`, o job permanece (ou retorna a) `STAGED`"), que a
implementação original nunca respeitou para o caso `decision_status
= PENDING`. Corrigido adicionando uma contagem própria de linhas com
`decision_status = 'PENDING'` (sem o filtro por `APPROVED`/`SKIPPED`,
já que é exatamente esse filtro que as escondia) — se houver
qualquer uma, o job volta para `STAGED` (aguardando decisão humana,
não `CONFIRMING`, que descreve uma confirmação ativamente em
execução), antes mesmo de avaliar persistência ou falhas. Nenhuma
mudança na assinatura da função — `CREATE OR REPLACE` é suficiente.
Ver `database/migrations/2118_repair_catalog_import_job_status_for_pending_decisions.sql`
para a correção retroativa dos 2 jobs já afetados.

Nota sobre o "falso alarme" descartado na mesma investigação: um
terceiro job (`bae2f19b-223f-42da-9acd-4283da8fc7b3`) apareceu na
mesma validação com 270 linhas `persistence_status = PENDING`, mas
`decision_status = 'REJECTED'` em todas — comportamento correto por
desenho (linhas rejeitadas nunca entram no laço de gravação desta
função, então nunca saem de `PENDING`; não bloqueiam nem deveriam
bloquear a conclusão do job). Não precisou de nenhuma correção.

Descrição...:
Cria admin_confirm_catalog_import(), função pública SECURITY DEFINER
— único caminho pelo qual as propostas de um catalog_import_job
(Query 2060) se tornam Cards reais em public.card. Chama
internal.write_card() (Query 2030) diretamente, a mesma camada
canônica usada por admin_create_card()/admin_update_card(). Ver
ADR-024 (Catalog Card Ingestion Strategy) e ADR-023 (Princípio da
Fonte Canônica).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- SELECT ... FOR UPDATE na linha do job trava concorrência: duas
  chamadas simultâneas de confirmação para o mesmo job não podem
  processar as mesmas linhas duas vezes.
- Só aceita jobs em STAGED ou CONFIRMING (uma chamada anterior pode
  ter sido interrompida por falha sistêmica e deixado o job em
  CONFIRMING — retomar é uma nova chamada, não um estado de erro).
- p_row_ids (opcional): permite confirmar um subconjunto das linhas
  aprovadas (ex.: "confirmar só as sem conflito" primeiro). NULL
  processa todas as linhas elegíveis do job.
- Só processa linhas com persistence_status = 'PENDING' e
  decision_status IN ('APPROVED', 'SKIPPED') — linhas com decisão
  PENDING ou REJECTED nunca são tocadas por esta função.
- match_status é recalculado aqui, não herdado do processamento: o
  catálogo real pode ter mudado entre o processamento e a
  confirmação (ex.: outra importação já criou a Card nesse meio
  tempo). A comparação usa os mesmos quatro campos do contrato de
  conflito já estabelecido em ADR-024 (name, rarity_id, category_id,
  collector_total — nunca collector_number/collector_order/
  card_set_id).
- Linha SKIPPED nunca é persistida: passa direto para
  persistence_status = 'UNCHANGED', sem chamar internal.write_card().
- Linha NEW aprovada: internal.write_card(CREATE, ...) — cria a Card.
- Linha MATCHED aprovada: nenhuma escrita é necessária (os dados já
  batem) — persistence_status = 'UNCHANGED', matched_card_id e
  resulting_card_id apontam para a Card existente.
- Linha CONFLICT: o match_status já gravado na linha (calculado no
  processamento, visto pelo administrador na tela de Revisão) é
  comparado com o match_status recém-recalculado aqui.
  - Se ambos forem CONFLICT: o administrador já revisou este
    conflito específico e decidiu APPROVED sabendo que a Card
    existente seria sobrescrita — internal.write_card(UPDATE, ...)
    é chamado.
  - Se o match_status gravado era NEW ou MATCHED e só agora, na
    confirmação, o recálculo aponta CONFLICT: é uma mudança no
    catálogo real ocorrida entre o processamento e a confirmação
    (ex.: outra importação criou a Card nesse meio tempo) que o
    administrador nunca viu — a linha permanece persistence_status
    = 'PENDING', só o match_status é atualizado para CONFLICT, e ela
    fica disponível para uma nova decisão explícita na Revisão.
- Cada linha é isolada em seu próprio bloco de exceção: um erro
  específico de uma linha nunca aborta as demais — grava
  persistence_status = 'FAILED' e error_detail, e a função continua
  para a próxima linha. Uma falha sistêmica (ex.: perda de conexão)
  ainda aborta a transação inteira, revertendo inclusive a
  transição para CONFIRMING — comportamento padrão de uma função
  PL/pgSQL: não há savepoint manual por linha além do bloco
  EXCEPTION já embutido.
- Os contadores do job (inserted_rows, updated_rows, etc.) e o
  status final são sempre recalculados por agregação sobre
  catalog_import_row ao final da chamada, nunca incrementados.
- status final do job: COMPLETED se não houver nenhuma linha PENDING
  nem FAILED; COMPLETED_WITH_ERRORS se houver pelo menos uma FAILED
  e nenhuma PENDING; permanece CONFIRMING se ainda houver linhas
  PENDING (sublote parcial, chamada futura completa o restante).
- Uma única linha de auditoria agregada por chamada bem-sucedida
  (catalog_admin_action_log, ação CATALOG_IMPORT_CONFIRMED,
  entity_id = job_id) — nunca uma linha por Card confirmada (ADR-024).

Pré-requisitos:
- Query 2060/2061 - Create Catalog Import Job Table + Triggers.
- Query 2070/2071 - Create Catalog Import Row Table + Triggers.
- Query 2030 - Create internal.write_card() Function.
- Query 2054 - Widen Catalog Admin Action Log for Catalog Import.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_confirm_catalog_import(
    p_job_id UUID,
    p_row_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
    inserted_count INTEGER,
    updated_count INTEGER,
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
    v_job public.catalog_import_job%ROWTYPE;
    v_row public.catalog_import_row%ROWTYPE;
    v_card public.card%ROWTYPE;
    v_match_status TEXT;
    v_result_card_id UUID;
    v_error_message TEXT;
    v_pending_rows INTEGER;
    v_failed_rows INTEGER;
    v_decision_pending_rows INTEGER;
    v_final_status TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_IMPORT_FORBIDDEN: apenas administradores podem confirmar uma importação.';
    END IF;

    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_IMPORT_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    SELECT * INTO v_job FROM public.catalog_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    IF v_job.status NOT IN ('STAGED', 'CONFIRMING') THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_IMPORT_INVALID_STATUS: o job está em % — só é possível confirmar a partir de STAGED ou CONFIRMING.', v_job.status;
    END IF;

    IF v_job.status = 'STAGED' THEN
        UPDATE public.catalog_import_job SET status = 'CONFIRMING' WHERE id = p_job_id;
    END IF;

    FOR v_row IN
        SELECT r.*
        FROM public.catalog_import_row r
        WHERE r.job_id = p_job_id
          AND r.persistence_status = 'PENDING'
          AND r.decision_status IN ('APPROVED', 'SKIPPED')
          AND (p_row_ids IS NULL OR r.id = ANY(p_row_ids))
        ORDER BY r.created_at
        FOR UPDATE OF r
    LOOP
        BEGIN
            IF v_row.decision_status = 'SKIPPED' THEN
                UPDATE public.catalog_import_row
                    SET persistence_status = 'UNCHANGED', match_status = 'NEW'
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            -- decision_status = 'APPROVED' a partir daqui: recalcula match_status contra o catálogo real
            SELECT c.* INTO v_card
            FROM public.card c
            WHERE c.card_set_id = v_job.card_set_id
              AND c.collector_number = (v_row.normalized_data->>'collector_number')
            LIMIT 1;

            IF v_card.id IS NULL THEN
                v_match_status := 'NEW';
            ELSIF v_card.name = (v_row.normalized_data->>'name')
                  AND v_card.rarity_id = (v_row.normalized_data->>'rarity_id')::UUID
                  AND v_card.category_id = (v_row.normalized_data->>'category_id')::UUID
                  AND v_card.collector_total IS NOT DISTINCT FROM NULLIF(v_row.normalized_data->>'collector_total', '')::INTEGER
            THEN
                v_match_status := 'MATCHED';
            ELSE
                v_match_status := 'CONFLICT';
            END IF;

            IF v_match_status = 'CONFLICT' AND v_row.match_status <> 'CONFLICT' THEN
                -- Conflito novo, surgido entre o processamento e esta confirmação: o administrador
                -- nunca revisou este conflito específico. Fica pendente para uma nova decisão explícita,
                -- em vez de sobrescrever a Card existente sem confirmação específica sobre este estado.
                UPDATE public.catalog_import_row
                    SET match_status = v_match_status
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            IF v_match_status = 'CONFLICT' THEN
                -- match_status já era CONFLICT desde o processamento: o administrador revisou este
                -- conflito específico e aprovou a sobrescrita explicitamente.
                v_result_card_id := internal.write_card(
                    'UPDATE', v_card.id, NULL,
                    (v_row.normalized_data->>'rarity_id')::UUID,
                    (v_row.normalized_data->>'category_id')::UUID,
                    NULL,
                    NULLIF(v_row.normalized_data->>'collector_total', '')::INTEGER,
                    NULLIF(v_row.normalized_data->>'collector_order', '')::INTEGER,
                    v_row.normalized_data->>'name'
                );

                UPDATE public.catalog_import_row
                    SET match_status = v_match_status,
                        persistence_status = 'UPDATED',
                        matched_card_id = v_card.id,
                        resulting_card_id = v_result_card_id,
                        error_detail = NULL
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            IF v_match_status = 'NEW' THEN
                v_result_card_id := internal.write_card(
                    'CREATE', NULL, v_job.card_set_id,
                    (v_row.normalized_data->>'rarity_id')::UUID,
                    (v_row.normalized_data->>'category_id')::UUID,
                    v_row.normalized_data->>'collector_number',
                    NULLIF(v_row.normalized_data->>'collector_total', '')::INTEGER,
                    NULLIF(v_row.normalized_data->>'collector_order', '')::INTEGER,
                    v_row.normalized_data->>'name'
                );

                UPDATE public.catalog_import_row
                    SET match_status = v_match_status,
                        persistence_status = 'INSERTED',
                        matched_card_id = v_result_card_id,
                        resulting_card_id = v_result_card_id,
                        error_detail = NULL
                    WHERE id = v_row.id;
            ELSE
                -- MATCHED: dados já batem, nenhuma escrita necessária
                UPDATE public.catalog_import_row
                    SET match_status = v_match_status,
                        persistence_status = 'UNCHANGED',
                        matched_card_id = v_card.id,
                        resulting_card_id = v_card.id,
                        error_detail = NULL
                    WHERE id = v_row.id;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
            UPDATE public.catalog_import_row
                SET persistence_status = 'FAILED', error_detail = v_error_message
                WHERE id = v_row.id;
        END;
    END LOOP;

    -- Recalcula os contadores do job inteiramente por agregação (nunca incrementados diretamente)
    UPDATE public.catalog_import_job j
        SET total_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id),
            valid_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id AND validation_status = 'VALID'),
            rejected_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id AND decision_status = 'REJECTED'),
            inserted_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id AND persistence_status = 'INSERTED'),
            updated_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id AND persistence_status = 'UPDATED'),
            unchanged_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id AND persistence_status = 'UNCHANGED'),
            skipped_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id AND decision_status = 'SKIPPED'),
            failed_rows = (SELECT COUNT(*) FROM public.catalog_import_row WHERE job_id = j.id AND persistence_status = 'FAILED')
        WHERE j.id = p_job_id;

    -- v1.1: contagem própria, SEM o filtro por decision_status IN ('APPROVED',
    -- 'SKIPPED') — é exatamente esse filtro que escondia linhas nunca
    -- decididas (ex.: CONFLICT nascida PENDING e nunca revisada) da checagem
    -- de conclusão do job, permitindo COMPLETED com decisão humana pendente.
    SELECT COUNT(*)
    INTO v_decision_pending_rows
    FROM public.catalog_import_row
    WHERE job_id = p_job_id
      AND decision_status = 'PENDING';

    SELECT
        COUNT(*) FILTER (WHERE persistence_status = 'PENDING'),
        COUNT(*) FILTER (WHERE persistence_status = 'FAILED')
    INTO v_pending_rows, v_failed_rows
    FROM public.catalog_import_row
    WHERE job_id = p_job_id
      AND decision_status IN ('APPROVED', 'SKIPPED');

    IF v_decision_pending_rows > 0 THEN
        -- Ainda há linha(s) nunca decididas por um administrador — o job
        -- volta para STAGED (aguardando revisão humana), não CONFIRMING
        -- (que descreve uma confirmação ativamente em execução, não uma
        -- pendência de decisão). ADR-024: "permanece (ou retorna a) STAGED".
        v_final_status := 'STAGED';
    ELSIF v_pending_rows > 0 THEN
        v_final_status := 'CONFIRMING';
    ELSIF v_failed_rows > 0 THEN
        v_final_status := 'COMPLETED_WITH_ERRORS';
    ELSE
        v_final_status := 'COMPLETED';
    END IF;

    UPDATE public.catalog_import_job SET status = v_final_status WHERE id = p_job_id;

    IF v_final_status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS') THEN
        INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
            VALUES (auth.uid(), 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_JOB', p_job_id,
                    jsonb_build_object('card_set_id', v_job.card_set_id, 'final_status', v_final_status));
    END IF;

    RETURN QUERY
        SELECT j.inserted_rows, j.updated_rows, j.unchanged_rows, j.failed_rows, v_pending_rows, j.status
        FROM public.catalog_import_job j
        WHERE j.id = p_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_catalog_import(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_catalog_import(UUID, UUID[]) TO authenticated;
