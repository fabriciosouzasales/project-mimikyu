/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2199 - Guard SIZE_OUT_OF_SCOPE Decision Immutability
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE (migration 20260916170733, 2026-09-16)
              Fechamento documental: DOCUMENTATION-CLOSEOUT-01 (2026-09-16).
              md5(pg_get_functiondef) pré-aplicação.: 8495aa378ff34a568bd9c23db4370a42 (corpo da 2163)
              md5(pg_get_functiondef) pós-aplicação.: bc2e5f378a95e02fbcc8b10819451f52
              Delta de dados na aplicação: ZERO (14 fingerprints idênticos).
              Validada pelo harness 2828 v2.0 — gate_state = COMPLETE
              (18 estruturais PASS / 0 FAIL · 5 E2E autenticados PASS / 0 PENDING).
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-16
Mandato.....: CARD-VARIANTS — JUMBO INCIDENT /
               SIZE-SCOPE-EDGE-UI-CORRECTION-01 (OBJETIVO 1)
               Aplicada em SIZE-SCOPE-DECISION-GUARD-2199-EXECUTE-01.
Diagnóstico.: SIZE-SCOPE-EDGE-UI-DIFF-AUDIT-01 — BLOCKER-1

-------------------------------------------------------------------------------
POR QUE ESTA MIGRATION EXISTE
-------------------------------------------------------------------------------
A Query 2198 (LIVE) fechou o eixo de ESCOPO POR TAMANHO no ponto único de
routing: `size` normalizado fora de {NULL, STANDARD} devolve
BLOCKED_SIZE_OUT_OF_SCOPE / BLOCKED_SIZE_UNSUPPORTED, e nenhum writer
consegue produzir identidade canônica a partir da linha.

A Edge (import-card-variants) passou a materializar essa decisão no staging:

    normalized_data.skip_reason = 'SIZE_OUT_OF_SCOPE'
      -> validation_status = 'INVALID'
      -> decision_status   = 'SKIPPED'

Essa tripla é decisão AUTOMÁTICA, tomada pelo sistema no momento da
importação. Não é decisão editorial em aberto.

A auditoria SIZE-SCOPE-EDGE-UI-DIFF-AUDIT-01 provou que ela era reversível:
`admin_decide_catalog_variant_import_row` só protege APPROVED (recusado para
`validation_status <> 'VALID'`). Para REJECTED, SKIPPED e PENDING a única
pré-condição é `job.status = 'STAGED'`. Um clique em "Rejeitar" na tela de
revisão — ou um "Selecionar todas" que arrastasse a linha — mudava
`decision_status` de SKIPPED para REJECTED, com estes efeitos reais:

  1. a linha sai do universo `decision_status IN ('APPROVED','SKIPPED')` da
     confirmação (Queries 2145 / 2164 / 2179) e NUNCA é processada, ficando
     com `persistence_status = 'PENDING'` indefinidamente;
  2. `rejected_rows` (2145, linha 419) passa a contar variantes que o sistema
     decidiu não catalogar, misturando decisão humana com decisão automática;
  3. a evidência de "pulada por escopo" sobrevive só em
     `normalized_data.skip_reason` — nenhum contador a reflete.

ARQUITETURA DE DEFESA — DUAS CAMADAS, NÃO TRÊS
(atualizado em 2026-09-16 pela Correction-02; a redação anterior deste
parágrafo descrevia uma terceira camada que deixou de existir)

  UI (web/components/catalogo/revisao-importacao-variantes-table.tsx)
    - a linha fora de escopo NÃO é selecionável (isVariantRowSelectable);
    - os handlers de decisão filtram defensivamente (canDecideVariantRow),
      de modo que nenhum id travado é sequer enviado;
    - é conveniência e evita a viagem — não é garantia.

  RPC (esta função, a partir da 2199)
    - AUTORIDADE FINAL E ATÔMICA. Único writer de decision_status.

NÃO existe mais um precheck na Server Action. A Correction-02 removeu o
`.in("id", rowIds)` que a Correction-01 havia colocado em
`decidirLinhasVariantes`, por três razões registradas lá: duplicação da
mesma regra de negócio em duas camadas; incompatibilidade com o teto de
10.000 UUIDs por chamada (uma querystring de ~370 KB, mais um round-trip por
decisão, ou chunking arbitrário); e ausência de atomicidade, já que o
precheck e o UPDATE eram transações distintas.

DEPENDÊNCIA DE SEQUÊNCIA: enquanto esta migration não estiver LIVE, a única
barreira contra REJECTED/PENDING sobre uma linha SIZE_OUT_OF_SCOPE é a da
UI. Logo, a 2199 precede o deploy do frontend.

-------------------------------------------------------------------------------
AUDITORIA DE WRITERS — POR QUE SÓ ESTA FUNÇÃO
-------------------------------------------------------------------------------
Varredura de `SET decision_status` / `INSERT ... decision_status` em
database/schema/ e database/migrations/ (2026-09-16):

  2138  DEFAULT 'PENDING' na criação da tabela        (não é writer de decisão)
  2139  trigger BEFORE: UPPER(BTRIM(...)) normaliza   (normalizador, não writer)
  2144  UPDATE ... SET decision_status                 (SUPERSEDED por 2163)
  2163  UPDATE ... SET decision_status                 <-- ÚNICO WRITER LIVE

  2145 / 2164 / 2179 (confirm)     -> persistence_status, match_status, error_detail
  2150 / 2180 / 2181 / 2183        -> normalized_data
  2189 / 2190 / 2193 / 2196 / 2197 -> normalized_data
  (nenhum deles toca decision_status)

Logo, o hardening mínimo é um único CREATE OR REPLACE sobre
`admin_decide_catalog_variant_import_row`.

LIMITE CONHECIDO E DELIBERADO: um UPDATE direto na tabela pelo papel
`postgres` (MCP / SQL Editor) continua podendo alterar a coluna. Fechar isso
exigiria um trigger na tabela — superfície maior, que afetaria os harnesses
de fixture (2827, 2822, 2824) e caminhos não auditados neste incidente.
Mandato: "hardening mínimo". Registrado como dívida, não silenciado.

-------------------------------------------------------------------------------
CONTRATO ACRESCENTADO
-------------------------------------------------------------------------------
GUARD 7 (novo). Se QUALQUER linha do lote tem
`normalized_data ->> 'skip_reason' = 'SIZE_OUT_OF_SCOPE'` e o
`decision_status` pedido NÃO é 'SKIPPED', a chamada INTEIRA falha com
ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_SIZE_OUT_OF_SCOPE. Nenhuma linha é
alterada — mesma semântica "tudo ou nada" já usada pelo guard de APPROVED.

'SKIPPED' é aceito DE PROPÓSITO: a linha já nasce SKIPPED, então a chamada é
um no-op idempotente. Recusá-la obrigaria todo caller a conhecer o eixo de
tamanho antes de pedir a decisão que já é a vigente — contrato pior, sem
ganho de integridade.

Ordem dos guards preservada e estendida:
  is_admin < NULL < ndims < cardinality < teto < status válido <
  job STAGED < APPROVED-needs-review < SIZE_OUT_OF_SCOPE

O guard novo entra POR ÚLTIMO entre as validações e ANTES do UPDATE. Motivo:
os anteriores são sobre a FORMA da chamada (autorização, contrato do array,
estado do job); este é sobre o CONTEÚDO das linhas, e só faz sentido depois
de o lote ter sido aceito como bem formado. Isso também mantém as mensagens
de erro já existentes com precedência inalterada.

NADA MAIS MUDA. Todo o resto do corpo é idêntico ao da Query 2163.

-------------------------------------------------------------------------------
NÃO TOCA / NÃO REAPLICA
-------------------------------------------------------------------------------
- Não altera a Query 2198 (guard de residual signature) — nem reaplica.
- Não altera `catalog_variant_import_row` (nenhum DDL de tabela).
- Não altera a confirmação (2145/2164/2179).
- Não altera grants: reafirmados idênticos, por idempotência.
- Não altera a assinatura da função.
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
    -- Teto de lote. Mesmo valor ja adotado pela 6115 e pela 5079 —
    -- nao e constante nova no projeto.
    c_max_row_ids CONSTANT INTEGER := 10000;

    v_decision_status TEXT;
    v_rows_affected INTEGER;
    v_id_count INTEGER;
    -- 2199: quantas linhas do lote sao fora de escopo por tamanho.
    v_out_of_scope_count INTEGER;
BEGIN
    -- =================================================================
    -- GUARD 1 — AUTORIZACAO. Continua sendo a primeira instrucao.
    -- =================================================================
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_FORBIDDEN: apenas administradores podem decidir sobre linhas de importação de variantes.';
    END IF;

    -- =================================================================
    -- GUARD 2 — NULL. Contrato preservado da 2144: p_row_ids e
    --           obrigatorio. Mesmo codigo de erro de sempre.
    -- =================================================================
    IF p_row_ids IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_MISSING_IDS: p_row_ids é obrigatório e não pode ser vazio.';
    END IF;

    -- =================================================================
    -- GUARD 3 — DIMENSIONALIDADE (2163). p_row_ids precisa ser um array
    --           de UMA dimensao. Um array multidimensional passa por
    --           array_length(...,1) reportando apenas o tamanho da
    --           primeira dimensao, enquanto ANY() varre TODOS os
    --           elementos — a funcao operaria sobre mais ids do que
    --           mediu. Fail-closed antes de qualquer ANY().
    -- =================================================================
    IF array_ndims(p_row_ids) <> 1 THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_INVALID_ARRAY_SHAPE: p_row_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_row_ids);
    END IF;

    -- =================================================================
    -- GUARD 4 — VAZIO (2163). cardinality() conta ELEMENTOS REAIS e
    --           devolve 0 (nunca NULL) para array vazio — contrato mais
    --           honesto que array_length(...,1), que devolve NULL.
    --           Mesmo codigo de erro da 2144 para nao quebrar contrato
    --           de mensagem ja existente.
    -- =================================================================
    v_id_count := cardinality(p_row_ids);

    IF v_id_count = 0 THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_MISSING_IDS: p_row_ids é obrigatório e não pode ser vazio.';
    END IF;

    -- =================================================================
    -- GUARD 5 — TETO (2163). Ver cabecalho para a justificativa do
    --           valor. Medido sobre cardinality (elementos reais).
    -- =================================================================
    IF v_id_count > c_max_row_ids THEN
        RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_TOO_MANY_IDS: p_row_ids tem % ids, acima do teto de % por chamada. Divida em lotes menores.', v_id_count, c_max_row_ids;
    END IF;

    -- =================================================================
    -- A PARTIR DAQUI, TUDO E EXATAMENTE COMO NA QUERY 2163,
    -- ate o GUARD 7 (novo, 2199).
    -- =================================================================
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

    -- =================================================================
    -- GUARD 7 — ESCOPO POR TAMANHO, IMUTAVEL (2199).
    --
    -- Uma linha com skip_reason = 'SIZE_OUT_OF_SCOPE' ja recebeu, na
    -- importacao, a unica decisao que lhe cabe: SKIPPED. Isso e decisao
    -- do SISTEMA (eixo de escopo, Query 2198), nao decisao editorial em
    -- aberto — e por isso nao pode ser sobrescrita por APPROVED,
    -- REJECTED nem revertida para PENDING.
    --
    -- SKIPPED e aceito: a chamada e um no-op idempotente sobre o estado
    -- que a linha ja tem. Exigir que o caller saiba disso de antemao
    -- seria um contrato pior sem ganho de integridade.
    --
    -- FALHA O LOTE INTEIRO, como o guard de APPROVED acima: um lote misto
    -- nao deve aplicar metade das decisoes em silencio.
    --
    -- `->>` nao distingue chave ausente de JSON null, e os dois casos sao
    -- "nao ha skip_reason" — comparacao com igualdade resolve ambos como
    -- NULL, que nao satisfaz a condicao. Linhas legadas (sem a chave)
    -- passam intactas.
    -- =================================================================
    IF v_decision_status <> 'SKIPPED' THEN
        SELECT COUNT(*)
          INTO v_out_of_scope_count
          FROM public.catalog_variant_import_row r
         WHERE r.id = ANY(p_row_ids)
           AND r.normalized_data ->> 'skip_reason' = 'SIZE_OUT_OF_SCOPE';

        IF v_out_of_scope_count > 0 THEN
            RAISE EXCEPTION 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_SIZE_OUT_OF_SCOPE: % linha(s) do lote estão fora do escopo do sistema por tamanho (JUMBO) e já foram puladas automaticamente na importação. Essa decisão é do sistema e não pode virar % — nenhuma linha foi alterada.', v_out_of_scope_count, v_decision_status;
        END IF;
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

-- Grants reafirmados identicos aos das Queries 2144/2163. CREATE OR REPLACE
-- nao altera ACL de funcao existente; estas linhas existem por idempotencia
-- e para que este arquivo seja autossuficiente.
REVOKE ALL ON FUNCTION public.admin_decide_catalog_variant_import_row(UUID[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_decide_catalog_variant_import_row(UUID[], TEXT) TO authenticated;

-- ================================================================
-- Resultado esperado:
--   CREATE FUNCTION (0 linhas), REVOKE, GRANT.
--
-- Como validar:
--   Query 2828 - Validate Size Out Of Scope Decision Immutability.
--   Espera-se, alem dos testes comportamentais:
--     SELECT prosecdef, proconfig FROM pg_proc
--       WHERE proname = 'admin_decide_catalog_variant_import_row'
--       -> prosecdef = true, proconfig = {"search_path=\"\""}
--     pg_get_functiondef(...) ILIKE '%SIZE_OUT_OF_SCOPE%' -> TRUE
--
-- BASELINE LIVE — CONFIRMADO (2026-09-16, auditoria
-- SIZE-SCOPE-DECISION-GUARD-GATE-AUDIT-01):
--
--   md5(pg_get_functiondef(public.admin_decide_catalog_variant_import_row))
--     = 8495aa378ff34a568bd9c23db4370a42
--
--   Esse hash corresponde ao corpo da Query 2163, que e a base sobre a qual
--   este arquivo foi escrito. O diff executavel 2163 -> 2199 e de UMA unica
--   mudanca funcional: a declaracao de v_out_of_scope_count e o GUARD 7.
--   Nenhuma linha executavel da 2163 foi removida ou alterada.
--
-- GATE DE PRE-FLIGHT (continua obrigatorio no momento da execucao):
--   reconferir o mesmo md5 IMEDIATAMENTE antes de aplicar. O baseline acima
--   e de 2026-09-16; se o corpo LIVE tiver mudado desde entao, esta migration
--   NAO deve ser aplicada sem nova auditoria do diff.
-- ================================================================
