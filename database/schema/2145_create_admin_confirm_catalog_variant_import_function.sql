/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2145 - Create admin_confirm_catalog_variant_import() Function
Versão......: 2.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15 (v1.0) · 2026-09-13 (v2.0)
Reconciliada: 2026-09-13 — CANONICAL-RECONCILIATION-01

Descrição...:
Cria admin_confirm_catalog_variant_import(), função pública
SECURITY DEFINER — único caminho pelo qual as propostas de um
catalog_variant_import_job (Query 2136) se tornam Card Variants
reais em public.card_variant. Chama internal.write_card_variant()
(Query 2143) diretamente, mesma camada canônica isolada do padrão
já usado por Importar Cartas. Equivalente exata de
admin_confirm_catalog_import() (Query 2082) para o bloco Card
Variant (Incremento 3, ADR-028).

----------------------------------------------------------------
v2.0 — CONSOLIDAÇÃO DE TRÊS FRENTES
----------------------------------------------------------------
Esta versão é o ESTADO TERMINAL de:

    2145 v1.0   função original
    2164 v1.1   hardening de contrato bulk
    2179 v1.1   Printing Routing (matching triplo, writer de 6 args)

O QUE VEIO DA 2164 — PRESERVADO LITERALMENTE:
  c_max_rows = 1000; array_ndims(p_row_ids) = 1; cardinality > 0;
  teto de ids por chamada; CONJUNTO EFETIVO CONGELADO
  (v_effective_row_ids) com ORDER BY created_at, id + LIMIT
  c_max_rows + 1, que elimina o TOCTOU entre a contagem e o LOOP;
  semântica de p_row_ids = NULL; LOOP restrito ao conjunto congelado;
  SELECT ... FOR UPDATE no job e FOR UPDATE OF r nas linhas.

O QUE VEIO DA 2179 — PRESERVADO:
  variant_type_id obrigatório; contrato tri-estado de
  printing_profile_id lido por jsonb_typeof; MATCHING TRIPLO
  (card_id + variant_type_id + printing_profile_id) com
  IS NOT DISTINCT FROM; chamada de internal.write_card_variant() com
  SEIS argumentos, repassando o perfil.

----------------------------------------------------------------
O QUE NÃO VEIO — E POR QUÊ
----------------------------------------------------------------
A função LIVE ainda carrega, por rastreabilidade histórica, o RAMO
DE COMPATIBILIDADE do rollout:

    v_bridge_present
    leitura de pg_indexes procurando uq_cvir_job_card_type_bridge_legacy
    resolução de v_game_id / v_asset_source_id para o fallback
    chamada a internal.compute_variant_residual_signature()

Esse ramo existia para uma situação real e transitória: entre a
PHASE B e a PHASE D havia 5.653 linhas VALID legadas SEM a chave
printing_profile_id, e a Edge antiga continuava criando mais. Recusá-las
em bloco não seria fail-closed — seria indisponibilidade
auto-infligida. O ramo permitia confirmá-las, mas só mediante PROVA
(via 2176) de que a assinatura bruta não continha nenhum token de
Impressão conhecido.

Ele foi desenhado para EXPIRAR SOZINHO, amarrado à existência física
do índice-ponte. A PHASE E (Query 2184) removeu o bridge, e no mesmo
instante o ramo virou código inalcançável — comprovado pela Seção
S25.04 do harness 2824.

NUMA INSTALAÇÃO LIMPA ele nunca teria sido alcançável em momento
algum:
  - o bridge não é criado (Query 2138 v2.0);
  - ck_catalog_variant_import_row_valid_requires_printing_key nasce
    VALIDADA, tornando "VALID + chave ausente" impossível no banco;
  - a Edge nova é a única writer, e ela sempre grava null explícito
    ou UUID.

Carregá-lo para a canônica seria reproduzir um mecanismo de migração
numa instalação que não tem nada a migrar — e manter viva, no código
de instalação, uma dependência de leitura de pg_indexes que só fazia
sentido durante uma janela já fechada.

DIFERENÇA INTENCIONAL E ÚNICA frente ao LIVE. Em todo estado
representável após a PHASE E as duas formas são equivalentes: chave
ausente é fail-closed nas duas. A forma canônica apenas falha um
passo antes, sem consultar o catálogo.

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- SELECT ... FOR UPDATE na linha do job trava concorrência — mesmo
  raciocínio da Query 2082.
- Só aceita jobs em STAGED ou CONFIRMING.
- p_row_ids (opcional): permite confirmar um subconjunto das linhas
  aprovadas, em sublotes. NULL processa todas as linhas elegíveis,
  até o teto de c_max_rows. A FORMA do array é validada antes de
  qualquer acesso a tabela e antes de qualquer lock: array de uma
  dimensão, não vazio, no máximo c_max_rows ids.
- CONJUNTO EFETIVO CONGELADO: quando p_row_ids é NULL, os ids
  elegíveis são materializados UMA vez, em ordem determinística
  (created_at, id), com LIMIT c_max_rows + 1 — o + 1 é o que permite
  detectar "tem mais que o teto" sem contar a tabela inteira. O LOOP
  percorre esse conjunto, não uma nova consulta: o que foi contado é
  exatamente o que é processado.
- Só processa linhas com persistence_status = 'PENDING' E
  decision_status IN ('APPROVED', 'SKIPPED').
- Linha SKIPPED: persistence_status = 'UNCHANGED', sem chamar
  internal.write_card_variant().
- Linha APPROVED: revalidação defensiva antes de qualquer escrita —
  validation_status precisa ser 'VALID', normalized_data precisa
  conter variant_type_id, E a chave printing_profile_id precisa
  ESTAR PRESENTE (JSON null ou string UUID). Uma linha que falhar
  essa revalidação é tratada como falha isolada da própria linha
  (persistence_status = 'FAILED'), nunca interrompe as demais.
- CONTRATO TRI-ESTADO lido por jsonb_typeof, nunca por `->>`:
      chave ausente -> SQL NULL  -> Impressão NÃO resolvida -> RECUSA
      JSON null     -> 'null'    -> resolvido SEM perfil    -> NULL
      string        -> 'string'  -> resolvido COM perfil    -> UUID
      qualquer outro tipo JSON                              -> RECUSA
- match_status é recalculado aqui contra public.card_variant real,
  nunca herdado do processamento — o catálogo pode ter mudado entre
  o processamento/decisão e esta confirmação. Não existe conceito de
  CONFLICT de conteúdo: a existência de
  (card_id, variant_type_id, printing_profile_id) é binária — só NEW
  ou MATCHED.
  - MATCHED (já existe): NENHUMA escrita — persistence_status =
    'UNCHANGED', matched_variant_id/resulting_variant_id apontam
    para a variante existente. Nunca sobrescreve silenciosamente.
  - NEW: internal.write_card_variant('CREATE', ...) com
    variant_order = próximo inteiro livre para aquele card_id
    (MAX(variant_order) do card_id + 1, ou 1 se a Card ainda não
    tem nenhuma variante) — nunca lido de raw_data/normalized_data.
    is_default nunca é definido (nasce FALSE pelo default da
    coluna, Query 160) — persistence_status = 'INSERTED'.
- MATCHING TRIPLO com IS NOT DISTINCT FROM, não `=`. Para uma linha
  resolvida SEM perfil, v_printing_profile_id é NULL, e
  `cv.printing_profile_id = NULL` devolve sempre NULL — o ramo
  MATCHED jamais dispararia, o confirm tentaria INSERT de uma
  variante que já existe, violaria
  uq_card_variant_card_type_no_printing e marcaria a linha como
  FAILED. IS NOT DISTINCT FROM trata NULL como valor comparável, que
  é exatamente a semântica de "sem perfil declarado" como parte da
  identidade.
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
  FAILED nunca são reprocessadas.
- Uma única linha de auditoria agregada por chamada bem-sucedida
  (catalog_admin_action_log, ação CARD_VARIANT_IMPORT_CONFIRMED,
  entity_type CATALOG_VARIANT_IMPORT_JOB, entity_id = job_id) — só
  quando o status final é COMPLETED/COMPLETED_WITH_ERRORS.
- NENHUMA criação automática de Print Profile. NENHUMA alteração de
  card_variant já persistida.

Pré-requisitos:
- Query 2136/2137 - Create Catalog Variant Import Job Table + Triggers.
- Query 2138/2139 - Create Catalog Variant Import Row Table + Triggers.
- Query 2143 - internal.write_card_variant() com SEIS argumentos.
- Query 2146 - Widen Catalog Admin Action Log for Variant Import.
- Query 2171 - dois índices parciais de unicidade de card_variant.
- Query 1060 - Create is_admin() Function.

----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação da função de confirmação de variantes (2026-08-15).**
        Matching por (card_id, variant_type_id); writer com cinco
        argumentos; p_row_ids sem validação de forma nem teto. |
| 2.0 | **Consolidação 2145 + 2164 v1.1 + 2179 v1.1 — estado terminal
        do Printing Routing (2026-09-13).** Reconciliação canônica
        (CANONICAL-RECONCILIATION-01). Incorpora o hardening de
        contrato bulk da Query 2164 (teto, forma do array, conjunto
        efetivo congelado, ordenação determinística) e o Printing
        Routing da Query 2179 (contrato tri-estado, matching triplo
        com IS NOT DISTINCT FROM, writer de seis argumentos). NÃO
        incorpora o ramo de compatibilidade legada da 2179 — ver
        "O QUE NÃO VEIO" no cabeçalho: ele dependia da existência do
        índice-ponte, que a Query 2138 v2.0 não cria, e é inalcançável
        no estado terminal. Esta Query NÃO foi reexecutada contra o
        LIVE: o banco já está no estado funcionalmente equivalente
        desde a PHASE B (ver database/migrations/2164, 2179). |
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
    -- Teto de lote por chamada (Query 2164).
    c_max_rows CONSTANT INTEGER := 1000;

    v_job public.catalog_variant_import_job%ROWTYPE;
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_existing_variant public.card_variant%ROWTYPE;
    v_variant_type_id UUID;
    v_printing_profile_id UUID;
    v_printing_key_type TEXT;
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
    v_id_count INTEGER;
    v_effective_row_ids UUID[];
BEGIN
    -- GUARD 1 — AUTORIZACAO.
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_FORBIDDEN: apenas administradores podem confirmar uma importação de variantes.';
    END IF;

    -- GUARD 2 — p_job_id obrigatorio.
    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    -- GUARD 3 — FORMA E TETO DE p_row_ids (Query 2164). Validacao pura
    -- de payload: nenhum acesso a tabela, nenhum lock ainda tomado.
    IF p_row_ids IS NOT NULL THEN
        IF array_ndims(p_row_ids) <> 1 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_ARRAY_SHAPE: p_row_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_row_ids);
        END IF;

        v_id_count := cardinality(p_row_ids);

        IF v_id_count = 0 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_EMPTY_ROW_IDS: p_row_ids veio vazio. Envie NULL para confirmar todas as linhas elegíveis, ou pelo menos um id.';
        END IF;

        IF v_id_count > c_max_rows THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_TOO_MANY_ROWS: p_row_ids tem % ids, acima do teto de % por chamada. Divida em lotes menores.', v_id_count, c_max_rows;
        END IF;
    END IF;

    -- GUARD 4/5/6 — job existe, está em estado confirmável, e fica
    -- travado para o resto da transação.
    SELECT * INTO v_job FROM public.catalog_variant_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    IF v_job.status NOT IN ('STAGED', 'CONFIRMING') THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_STATUS: o job está em % — só é possível confirmar a partir de STAGED ou CONFIRMING.', v_job.status;
    END IF;

    SELECT name, code INTO v_card_set_name, v_card_set_code
    FROM public.card_set WHERE id = v_job.card_set_id;

    -- GUARD 7 — CONJUNTO EFETIVO CONGELADO (Query 2164). Elimina o
    -- TOCTOU: o que foi contado é exatamente o que será processado.
    -- O LIMIT c_max_rows + 1 detecta "tem mais que o teto" sem varrer
    -- a tabela inteira.
    IF p_row_ids IS NULL THEN
        v_effective_row_ids := ARRAY(
            SELECT r.id
            FROM public.catalog_variant_import_row r
            WHERE r.job_id = p_job_id
              AND r.persistence_status = 'PENDING'
              AND r.decision_status IN ('APPROVED', 'SKIPPED')
            ORDER BY r.created_at, r.id
            LIMIT c_max_rows + 1
        );

        IF cardinality(v_effective_row_ids) > c_max_rows THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_TOO_MANY_ROWS: o job tem mais de % linhas elegíveis. Informe p_row_ids em lotes menores.', c_max_rows;
        END IF;
    ELSE
        v_effective_row_ids := p_row_ids;
    END IF;

    IF v_job.status = 'STAGED' THEN
        UPDATE public.catalog_variant_import_job SET status = 'CONFIRMING' WHERE id = p_job_id;
    END IF;

    FOR v_row IN
        SELECT r.*
        FROM public.catalog_variant_import_row r
        WHERE r.job_id = p_job_id
          AND r.persistence_status = 'PENDING'
          AND r.decision_status IN ('APPROVED', 'SKIPPED')
          AND r.id = ANY(v_effective_row_ids)
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
            -- Revalidação defensiva: o estado pode, em tese, ter mudado
            -- entre a decisão (Query 2144) e esta confirmação.
            IF v_row.validation_status <> 'VALID' THEN
                RAISE EXCEPTION 'NEEDS_REVIEW_CANNOT_BE_CONFIRMED: linha sem card_variant_type resolvido não pode ser confirmada.';
            END IF;

            v_variant_type_id := NULLIF(v_row.normalized_data->>'variant_type_id', '')::UUID;
            IF v_variant_type_id IS NULL THEN
                RAISE EXCEPTION 'MISSING_VARIANT_TYPE_ID: normalized_data não contém variant_type_id resolvido.';
            END IF;

            -- EIXO IMPRESSÃO — contrato TRI-ESTADO.
            --
            -- jsonb_typeof distingue os tres estados; `->>` nao:
            --   chave ausente -> SQL NULL   (Impressao NAO resolvida)
            --   JSON null     -> 'null'     (resolvido SEM perfil)
            --   string        -> 'string'   (resolvido COM perfil)
            v_printing_key_type := jsonb_typeof(v_row.normalized_data -> 'printing_profile_id');

            IF v_printing_key_type IS NULL THEN
                -- FAIL-CLOSED. Chave ausente = Impressao nao resolvida.
                -- Este estado e impossivel para uma linha VALID
                -- (ck_catalog_variant_import_row_valid_requires_printing_key,
                -- Query 2138), e so seria alcancavel por escrita direta
                -- fora do pipeline. Recusar e o unico comportamento
                -- correto: confirmar criaria uma card_variant sem perfil
                -- que talvez devesse ter perfil.
                RAISE EXCEPTION 'PRINTING_NOT_RESOLVED: normalized_data não contém a chave printing_profile_id. Toda linha VALID precisa da chave — resolva o mapeamento de Impressão ou reprocesse a importação.';
            ELSIF v_printing_key_type = 'null' THEN
                v_printing_profile_id := NULL;      -- resolvido SEM perfil, explícito
            ELSIF v_printing_key_type = 'string' THEN
                v_printing_profile_id := (v_row.normalized_data->>'printing_profile_id')::UUID;
            ELSE
                RAISE EXCEPTION 'PRINTING_PROFILE_ID_INVALID_SHAPE: printing_profile_id tem tipo JSON % — esperado null ou string UUID.', v_printing_key_type;
            END IF;

            -- MATCHING TRIPLO. match_status recalculado contra o
            -- catalogo real — nunca herdado. IS NOT DISTINCT FROM, e
            -- nao `=`, porque NULL faz parte da identidade.
            SELECT cv.* INTO v_existing_variant
            FROM public.card_variant cv
            WHERE cv.card_id = v_row.card_id
              AND cv.variant_type_id = v_variant_type_id
              AND cv.printing_profile_id IS NOT DISTINCT FROM v_printing_profile_id
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

            -- Perfil repassado ao writer (Query 2143, seis argumentos).
            v_result_variant_id := internal.write_card_variant(
                'CREATE', NULL, v_row.card_id, v_variant_type_id, v_next_order,
                v_printing_profile_id
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
-- Confirmado executado:
--   v1.0 em 2026-08-15 (via execute_sql/MCP do Supabase, projeto
--   qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
--   contra dados reais do ME2.5, cobrindo APPROVED -> INSERTED com
--   variant_order correto e is_default FALSE; APPROVED de linha já
--   existente -> UNCHANGED sem escrita; REJECTED nunca processada;
--   sublote (p_row_ids) idempotente; job COMPLETED; reconfirmação de
--   job COMPLETED corretamente rejeitada; não-admin -> FORBIDDEN;
--   nenhuma duplicata em card_variant; action log gravado.
--
--   v2.0 NÃO foi reexecutada. O estado LIVE funcionalmente
--   equivalente já existe desde a PHASE B do rollout CARD-VARIANTS —
--   PRINTING-ROUTING, produzido por:
--     database/migrations/2164_harden_admin_confirm_catalog_variant_import_contract.sql
--     database/migrations/2179_extend_admin_confirm_catalog_variant_import_for_printing.sql
--   Esta é a forma que uma INSTALAÇÃO LIMPA deve usar.
--
-- Estado LIVE verificado em 2026-09-13 (read-only, pg_get_functiondef):
--   assinatura ......................... (p_job_id uuid, p_row_ids uuid[])
--   pronargs / pronargdefaults ......... 2 / 1
--   prosecdef .......................... true
--   proconfig .......................... search_path=""
--   c_max_rows = 1000 .................. presente
--   conjunto efetivo congelado ......... presente
--   matching triplo (IS NOT DISTINCT FROM) presente
--   writer com seis argumentos ......... presente
--
-- DIFERENÇA INTENCIONAL CANÔNICA × LIVE — uma, e documentada acima:
--   o LIVE conserva o ramo de compatibilidade legada (v_bridge_present,
--   leitura de pg_indexes, chamada a
--   internal.compute_variant_residual_signature). Ele é INALCANÇÁVEL
--   desde a PHASE E — provado pela Seção S25.04 da Query 2824 — e não
--   é reproduzido aqui. Em todo estado representável após a PHASE E as
--   duas formas se comportam de maneira idêntica.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT routine_name, security_type FROM information_schema.routines
-- WHERE routine_name = 'admin_confirm_catalog_variant_import';
-- Esperado: security_type = 'DEFINER'.
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants
-- WHERE routine_name = 'admin_confirm_catalog_variant_import';
-- Esperado: só 'authenticated' com EXECUTE.
-- Query 2824 - Validate Card Printing Routing, Seções S12, S20 e S25.
-- ================================================================
