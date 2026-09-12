/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2164 - Harden admin_confirm_catalog_variant_import()
               UUID[]/NULL contract (shape + ceiling + snapshot)
Versão......: 1.1
Status......: MIGRATION / CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Executado...: 2026-09-12, via apply_migration (MCP Supabase), projeto
               qjfutqujxrbzgrtkpgkg. Versao executada: v1.1. Postcheck
               read-only PASS: assinatura, RETURNS TABLE, SECURITY
               DEFINER, search_path="", grants nao ampliados
               (authenticated + postgres), teto 1000,
               v_effective_row_ids, LIMIT c_max_rows + 1,
               ORDER BY r.created_at, r.id, LOOP restrito a
               ANY(v_effective_row_ids), AUSENCIA do padrao antigo
               `p_row_ids IS NULL OR r.id = ANY(p_row_ids)`, e
               congelamento/teto posicionados antes de
               SET status='CONFIRMING' e antes do FOR v_row IN.
               Validado pela Query 2822, Secoes 1 e 3 (11 assercoes
               comportamentais, BEGIN...ROLLBACK), incluindo a prova do
               conjunto congelado (S3.11a-c).
Mandato.....: CARD-VARIANTS-GLOBAL-RECONCILIATION —
               BULK-CONTRACT-HARDENING-GATE-A-01 (autoria v1.0) /
               GATE-A-CORRECTION-01 (v1.1) /
               GATE-A-EXECUTE-NOW-01 (execucao) /
               BULK-CONTRACT-HARDENING-CLOSEOUT-01 (promocao)
Diagnostico.: CARD-VARIANTS-GLOBAL-RECONCILIATION — AUDIT-01 /
               AUDIT-01-CORRECTION-01

Esta e a copia promovida para database/migrations/. O corpo executavel e
IDENTICO ao do artefato de staging em
database/proposals/2026-09-12-card-variants-bulk-contract-hardening/ — a
unica diferenca esta neste cabecalho documental. Migration incremental de
CONTRATO de funcao (CREATE OR REPLACE sobre a 2145): por isso migrations/
e nao schema/, seguindo a mesma convencao ja aplicada as Queries 6129/6130.

v1.1 (GATE-A-CORRECTION-01) sobre a v1.0:
- A v1.0 tinha uma JANELA DE CONCORRENCIA (TOCTOU) real no caminho
  p_row_ids IS NULL: contava as rows elegiveis em uma instrucao e o
  LOOP reabria o universo em OUTRA instrucao. Em READ COMMITTED sao
  snapshots distintos — a Query 2144 podia aprovar novas rows entre
  as duas, e o LOOP processaria mais de c_max_rows. O teto era
  verificado, mas nao era GARANTIDO.
- v1.1 substitui a contagem por CONGELAMENTO DO CONJUNTO EFETIVO em
  variavel local (v_effective_row_ids) e faz o LOOP consumir apenas
  esse conjunto. O teto deixa de ser uma medicao e passa a ser uma
  propriedade estrutural.
- A v1.0 nunca foi executada em lugar nenhum. O corpo LIVE e o da v1.1.

Migration INCREMENTAL sobre a Query 2145 (CONFIRMADO EXECUTADO,
2026-08-15). A 2145 NAO e reescrita retroativamente — permanece como
a migration de criacao original. A partir desta Query, o corpo LIVE
da funcao passa a ser o definido aqui.

-------------------------------------------------------------------------------
POR QUE ESTA MIGRATION EXISTE
-------------------------------------------------------------------------------
A 2145 e mais exposta que a 2144: NAO possui NENHUM guard sobre
p_row_ids. Nem NULL, nem forma, nem cardinalidade, nem teto. E a secao
critica nao e uma varredura unica — e um LOOP com FOR UPDATE OF r e
escrita real por linha via internal.write_card_variant().

Medido read-only em 2026-09-12: `array_ndims`, `cardinality` e
`array_length` NAO apareciam no prosrc LIVE da funcao.

Consequencias do estado anterior:
1. Array multidimensional passava direto; ANY() varre todos os elementos.
2. Array vazio virava no-op silencioso — a funcao movia o job para
   CONFIRMING, nao processava nada e devolvia contadores como se tivesse
   trabalhado. Contrato ambiguo.
3. Sem teto, uma chamada grande mantinha locks de linha abertos durante
   todo o loop.

Como na 2163, nenhum desses pontos e falha de AUTORIZACAO:
public.is_admin() e a PRIMEIRA instrucao da funcao e continua sendo.
Sao falhas de robustez de payload e de controle de recurso.

-------------------------------------------------------------------------------
TETO ESCOLHIDO — 1.000 (uma ordem de grandeza ABAIXO da 2163)
-------------------------------------------------------------------------------
Deliberadamente menor que os 10.000 da 2163, e a razao e o custo
assimetrico:
    2163/2144 -> UPDATE set-based, uma passada.
    2164/2145 -> LOOP, FOR UPDATE por linha, escrita por linha.
O custo da 2145 cresce linearmente em TEMPO DE LOCK, nao em uma unica
varredura.

1.000 e 20x o lote operacional real do caller web
(CONFIRM_CHUNK_SIZE = 50) — cabe qualquer reuso legitimo — e mantem a
janela de lock limitada. Precedente direto no projeto: a Query 5150
(register_physical_cards_bulk) adota exatamente 1.000 pelo mesmo
motivo (escrita em loop).

-------------------------------------------------------------------------------
CONJUNTO EFETIVO CONGELADO — eliminacao do TOCTOU (v1.1)
-------------------------------------------------------------------------------
O contrato publico NAO muda. NULL continua significando "todas as rows
elegiveis no instante da operacao". O que muda e COMO esse "instante"
e definido: uma unica leitura, materializada.

    v_effective_row_ids UUID[];

    IF p_row_ids IS NULL THEN
        v_effective_row_ids := ARRAY(
            SELECT r.id
            FROM public.catalog_variant_import_row r
            WHERE r.job_id = p_job_id
              AND r.persistence_status = 'PENDING'
              AND r.decision_status IN ('APPROVED', 'SKIPPED')
            ORDER BY r.created_at, r.id
            LIMIT c_max_rows + 1          -- 1001: so o suficiente p/ detectar estouro
        );

        IF cardinality(v_effective_row_ids) > c_max_rows THEN
            RAISE EXCEPTION ... _TOO_MANY_ROWS ...;
        END IF;
    ELSE
        v_effective_row_ids := p_row_ids;
    END IF;

e o LOOP passa a filtrar por

    r.id = ANY(v_effective_row_ids)

em vez de reabrir o universo com `p_row_ids IS NULL OR ...`.

Tres propriedades que isso garante, e que a v1.0 NAO garantia:

1. TETO ESTRUTURAL. O LOOP so consegue ver ids que ja estao no array.
   cardinality(v_effective_row_ids) <= 1000 e verificado antes; logo o
   LOOP processa no maximo 1000 linhas, independentemente do que
   qualquer sessao concorrente faca depois do snapshot.
2. DETERMINISMO. ORDER BY r.created_at, r.id — created_at sozinho NAO
   e unico (varias rows do mesmo job nascem no mesmo now()); o
   desempate por id torna o LIMIT reproduzivel.
3. LIMIT c_max_rows + 1. Nao se conta a tabela inteira: le-se 1001 ids
   no maximo. Isso basta para distinguir "<=1000" de ">1000" e evita
   varrer um job grande so para descobrir que ele excede o teto.

Semantica preservada, explicitamente:
- ZERO elegiveis continua VALIDO. ARRAY(SELECT ...) devolve '{}' (nunca
  NULL) quando nao ha linhas; cardinality = 0; o LOOP nao itera; os
  contadores e o status final sao recalculados normalmente. E o caminho
  que o caller web usa para transicionar/fechar um job sem linhas a
  persistir (actions.ts linha 318).
- Rows que se tornarem elegiveis DEPOIS do snapshot nao entram nesta
  chamada. Permanecem PENDING e sao processadas em chamada posterior.
  O recalculo final de contadores e status continua sendo feito por
  agregacao sobre o estado REAL da tabela — nao sobre o snapshot —,
  entao um job com sobra elegivel termina corretamente em CONFIRMING.
- O LOOP mantem os guards defensivos de persistence_status e
  decision_status alem do filtro por id: se uma linha do snapshot
  deixar de ser elegivel entre o congelamento e o LOOP, ela e
  simplesmente ignorada, nunca reprocessada.

Para p_row_ids explicitamente VAZIO, o contrato e RAISE EXCEPTION
(preferencia registrada no mandato), nao no-op silencioso: "nenhum id"
e diferente de "todos os ids". Isto NAO afeta o caller web, que nunca
envia array vazio — ele envia NULL nesse caso.

-------------------------------------------------------------------------------
O QUE ESTA MIGRATION DELIBERADAMENTE NAO FAZ
-------------------------------------------------------------------------------
- nao altera NENHUMA regra de negocio;
- nao altera a assinatura publica (UUID, UUID[] DEFAULT NULL) -> TABLE(...);
- nao altera as colunas nem a ordem do RETURNS TABLE;
- nao altera SECURITY DEFINER nem SET search_path = '';
- nao altera grants;
- nao altera o SELECT ... FOR UPDATE do job nem os status aceitos;
- nao altera o recalculo de match_status contra card_variant;
- nao altera a regra MATCHED (nenhuma escrita) / NEW (write_card_variant);
- nao altera o calculo de variant_order (MAX+1) nem o is_default (nasce FALSE);
- nao altera o bloco EXCEPTION por linha;
- nao altera o recalculo de contadores por agregacao;
- nao altera a logica de tres camadas do status final;
- nao altera a auditoria (CARD_VARIANT_IMPORT_CONFIRMED);
- nao altera a idempotencia;
- nao altera a ordenacao de processamento do LOOP (ORDER BY r.created_at);
- nao toca 2143, 2144, card_variant, card_variant_type, mappings,
  rows/jobs existentes nem o frontend.

-------------------------------------------------------------------------------
ORDEM EXATA DOS GUARDS
-------------------------------------------------------------------------------
    1. auth (is_admin)                                  [2145, preservado]
    2. p_job_id NULL                                    [2145, preservado]
    3. forma/teto de p_row_ids quando NOT NULL          [2164, NOVO]
         ndims -> vazio -> teto
         (validacao pura de payload, zero acesso ao banco,
          antes de qualquer lock)
    4. SELECT job FOR UPDATE + NOT FOUND                [2145, preservado]
    5. status do job (STAGED/CONFIRMING)                [2145, preservado]
    6. lookup de card_set (nome/codigo p/ auditoria)    [2145, preservado]
    7. CONGELAMENTO do conjunto efetivo + teto do       [2164 v1.1, NOVO]
       caminho NULL — antes do UPDATE status='CONFIRMING'
    8. UPDATE status = 'CONFIRMING'                     [2145, preservado]
    9. LOOP sobre v_effective_row_ids                   [2145 + filtro v1.1]

Pre-requisitos:
- Query 2145 - Create admin_confirm_catalog_variant_import() (LIVE).
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
    -- Teto de lote. Uma ordem de grandeza abaixo da 2163 por causa do
    -- custo de lock do loop. Mesmo valor da Query 5150.
    c_max_rows CONSTANT INTEGER := 1000;

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
    v_id_count INTEGER;
    -- Conjunto EFETIVO de linhas desta chamada. Materializado uma unica
    -- vez; o LOOP consome exclusivamente este array.
    v_effective_row_ids UUID[];
BEGIN
    -- =================================================================
    -- GUARD 1 — AUTORIZACAO. Continua sendo a primeira instrucao.
    -- =================================================================
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_FORBIDDEN: apenas administradores podem confirmar uma importação de variantes.';
    END IF;

    -- =================================================================
    -- GUARD 2 — p_job_id obrigatorio.
    -- =================================================================
    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    -- =================================================================
    -- GUARD 3 — FORMA E TETO DE p_row_ids (2164), SOMENTE quando o
    --           chamador passou um array. Validacao pura de payload:
    --           nenhum acesso a tabela, nenhum lock ainda tomado.
    --           p_row_ids IS NULL passa direto por aqui — a semantica
    --           de "todas as rows elegiveis" e preservada e tem seu
    --           proprio tratamento no GUARD 7.
    -- =================================================================
    IF p_row_ids IS NOT NULL THEN
        IF array_ndims(p_row_ids) <> 1 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_ARRAY_SHAPE: p_row_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_row_ids);
        END IF;

        v_id_count := cardinality(p_row_ids);

        -- Array VAZIO e explicitamente rejeitado (nao vira no-op
        -- silencioso): "nenhum id" nao e a mesma coisa que "todos os
        -- ids". Para "todos", o contrato e passar NULL.
        IF v_id_count = 0 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_EMPTY_ROW_IDS: p_row_ids veio vazio. Envie NULL para confirmar todas as linhas elegíveis, ou pelo menos um id.';
        END IF;

        IF v_id_count > c_max_rows THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_TOO_MANY_ROWS: p_row_ids tem % ids, acima do teto de % por chamada. Divida em lotes menores.', v_id_count, c_max_rows;
        END IF;
    END IF;

    -- =================================================================
    -- GUARD 4/5/6 — exatamente como na Query 2145.
    -- =================================================================
    SELECT * INTO v_job FROM public.catalog_variant_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    IF v_job.status NOT IN ('STAGED', 'CONFIRMING') THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_STATUS: o job está em % — só é possível confirmar a partir de STAGED ou CONFIRMING.', v_job.status;
    END IF;

    SELECT name, code INTO v_card_set_name, v_card_set_code
    FROM public.card_set WHERE id = v_job.card_set_id;

    -- =================================================================
    -- GUARD 7 — CONJUNTO EFETIVO CONGELADO (2164 v1.1).
    --
    --   Elimina o TOCTOU da v1.0. O universo desta chamada e definido
    --   por UMA unica leitura, materializada em v_effective_row_ids. O
    --   LOOP abaixo nao reabre o universo — ele so consegue enxergar
    --   ids que ja estao neste array. O teto deixa de ser uma medicao
    --   e passa a ser uma propriedade estrutural.
    --
    --   Predicado canonico, identico ao do LOOP:
    --       job_id = p_job_id
    --       AND persistence_status = 'PENDING'
    --       AND decision_status IN ('APPROVED','SKIPPED')
    --
    --   ORDER BY created_at, id: created_at sozinho NAO e unico (rows
    --   do mesmo job nascem no mesmo now()); o desempate por id torna o
    --   LIMIT reproduzivel.
    --
    --   LIMIT c_max_rows + 1: le no maximo 1001 ids — o suficiente para
    --   distinguir "<=1000" de ">1000" sem varrer o job inteiro.
    --
    --   ZERO elegiveis continua VALIDO: ARRAY(SELECT ...) devolve '{}'
    --   (nunca NULL), o LOOP nao itera, e o recalculo de contadores e
    --   status acontece normalmente. E o caminho usado pelo caller web
    --   para transicionar/fechar um job sem linhas a persistir.
    --
    --   Posicionado ANTES do UPDATE para 'CONFIRMING' — uma chamada
    --   rejeitada por teto nao deixa nenhum rastro de estado.
    -- =================================================================
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

    -- =================================================================
    -- A PARTIR DAQUI, TUDO E EXATAMENTE COMO NA QUERY 2145, com a unica
    -- diferenca do filtro do LOOP (conjunto congelado em vez de
    -- reabertura do universo). Nenhuma regra de negocio foi alterada.
    -- =================================================================
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
    -- Sobre o estado REAL da tabela, nunca sobre o snapshot — um job com
    -- sobra elegível termina corretamente em CONFIRMING.
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

-- Grants reafirmados identicos aos da Query 2145.
REVOKE ALL ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) TO authenticated;

-- ================================================================
-- Resultado esperado:
--   CREATE FUNCTION (0 linhas), REVOKE, GRANT.
--
-- Como validar:
--   Query 2822 - Validate Variant Import Bulk Contract, Secoes 1 e 3.
-- ================================================================
