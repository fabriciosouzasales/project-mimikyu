/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2163 - Harden admin_decide_catalog_variant_import_row()
               UUID[] contract (shape + ceiling)
Versão......: 1.0
Status......: MIGRATION / CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Executado...: 2026-09-12, via apply_migration (MCP Supabase), projeto
               qjfutqujxrbzgrtkpgkg. Postcheck read-only PASS: assinatura,
               SECURITY DEFINER, search_path="", grants nao ampliados
               (authenticated + postgres), array_ndims, cardinality,
               teto 10000 e ordem dos guards
               (is_admin < ndims < cardinality < teto < ANY()).
               Validado pela Query 2822, Secoes 1 e 2 (8 assercoes
               comportamentais, BEGIN...ROLLBACK).
Mandato.....: CARD-VARIANTS-GLOBAL-RECONCILIATION —
               BULK-CONTRACT-HARDENING-GATE-A-01 (autoria) /
               GATE-A-CORRECTION-01 (revisao; 2163 aprovada COMO ESTA,
               sem alteracao) / GATE-A-EXECUTE-NOW-01 (execucao) /
               BULK-CONTRACT-HARDENING-CLOSEOUT-01 (promocao)
Diagnostico.: CARD-VARIANTS-GLOBAL-RECONCILIATION — AUDIT-01 /
               AUDIT-01-CORRECTION-01

Esta e a copia promovida para database/migrations/. O corpo executavel e
IDENTICO ao do artefato de staging em
database/proposals/2026-09-12-card-variants-bulk-contract-hardening/ — a
unica diferenca esta neste cabecalho documental. Migration incremental de
CONTRATO de funcao (CREATE OR REPLACE sobre a 2144): por isso migrations/
e nao schema/, seguindo a mesma convencao ja aplicada as Queries 6129/6130.

Migration INCREMENTAL sobre a Query 2144 (CONFIRMADO EXECUTADO,
2026-08-15). A 2144 NAO e reescrita retroativamente — permanece como
a migration de criacao original. A partir desta Query, o corpo LIVE
da funcao passa a ser o definido aqui.

-------------------------------------------------------------------------------
POR QUE ESTA MIGRATION EXISTE
-------------------------------------------------------------------------------
Ate aqui, admin_decide_catalog_variant_import_row() so foi chamada pela
UI de revisao (web/app/catalogo/importar-variantes/actions.ts,
decidirLinhasVariantes), onde o tamanho do array e o numero de linhas
que um administrador marcou na tela — pequeno por construcao.

A frente CARD VARIANTS — GLOBAL RECONCILIATION coloca esta funcao no
caminho de uma operacao administrativa em LOTE, com arrays montados
programaticamente, fora do caminho da UI. Medido no AUDIT-01: o maior
lote plausivel imediato e de 408 ids (SV5), e a campanha do Bloco 3
vai repetir isso em ~174 Card Sets.

Dois gaps reais do contrato atual, provados read-only em 2026-09-12:

1. MULTIDIMENSIONAL. O guard de presenca usa
   `array_length(p_row_ids, 1) IS NULL`. Para um array 2x3,
   array_length(...,1) devolve 2 — o guard NAO bloqueia —, enquanto
   `= ANY(...)` varre os 6 elementos. A funcao opera sobre um conjunto
   maior do que o que o proprio guard mediu.
   Prova: array_ndims = 2, array_length(...,1) = 2, cardinality = 6.

2. SEM TETO. Nem a funcao nem o caller web impoem limite. Ao contrario
   de confirmarImportacaoVariantes(), que envia lotes de
   CONFIRM_CHUNK_SIZE = 50, decidirLinhasVariantes() envia o array
   INTEIRO em uma unica chamada. Hoje este e o unico ponto de escrita
   administrativa do modulo sem teto em lugar nenhum.

Nenhum dos dois e falha de AUTORIZACAO: public.is_admin() continua
sendo a primeira instrucao e nenhum ANY() executa antes dela. Sao
falhas de robustez de payload e de controle de recurso.

-------------------------------------------------------------------------------
TETO ESCOLHIDO — 10.000
-------------------------------------------------------------------------------
Nao e numero arbitrario. E o mesmo teto de lote bulk ja adotado pelo
projeto em outras duas funcoes:
    - c_max_batch_size  = 10000  (Query 6115, resolve_card_primary_species_bulk)
    - c_max_variant_ids = 10000  (Query 5079, escopo de Master Set)

Dimensionamento: 200x o lote operacional da UI (50) e ~24x o maior
lote plausivel medido (408). Nao estorva nenhum uso legitimo,
atual ou futuro, e barra payload absurdo. A 2144 faz um UPDATE
set-based — suporta com folga esta ordem de grandeza.

(A Query 2164, irma desta, adota teto de 1.000 para
admin_confirm_catalog_variant_import() — uma ordem de grandeza abaixo,
deliberadamente, porque la a secao critica e um LOOP com escrita e
FOR UPDATE por linha, nao uma varredura unica.)

-------------------------------------------------------------------------------
O QUE ESTA MIGRATION DELIBERADAMENTE NAO FAZ
-------------------------------------------------------------------------------
- nao altera NENHUMA regra de negocio;
- nao altera a assinatura publica (UUID[], TEXT) -> INTEGER;
- nao altera SECURITY DEFINER nem SET search_path = '';
- nao altera grants (REVOKE PUBLIC / GRANT authenticated reafirmados
  identicos, por idempotencia do CREATE OR REPLACE);
- nao altera os estados permitidos (PENDING/APPROVED/REJECTED/SKIPPED);
- nao altera a regra de job STAGED;
- nao altera a regra NEEDS_REVIEW (APPROVED recusado para linha nao-VALID);
- nao altera o UPDATE nem o retorno (ROW_COUNT);
- nao altera a ausencia deliberada de catalog_admin_action_log;
- nao toca 2143, 2145, card_variant, card_variant_type, mappings,
  rows/jobs existentes nem o frontend.

-------------------------------------------------------------------------------
ORDEM OBRIGATORIA DOS GUARDS (mandato)
-------------------------------------------------------------------------------
    auth
    -> NULL
    -> dimensionalidade
    -> cardinalidade/vazio
    -> teto
    -> demais guards existentes (status / job STAGED / NEEDS_REVIEW)
    -> ANY()/UPDATE

Nenhum ANY() e nenhuma leitura de tabela ocorre antes dos guards de
forma e teto. Os quatro guards novos sao puramente sobre o payload —
zero acesso ao banco.

Pre-requisitos:
- Query 2144 - Create admin_decide_catalog_variant_import_row() (LIVE).
- Query 2138/2136 - Staging tables de importacao de variantes.
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
    -- Teto de lote. Mesmo valor ja adotado pela 6115 e pela 5079 —
    -- nao e constante nova no projeto.
    c_max_row_ids CONSTANT INTEGER := 10000;

    v_decision_status TEXT;
    v_rows_affected INTEGER;
    v_id_count INTEGER;
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
    -- A PARTIR DAQUI, TUDO E EXATAMENTE COMO NA QUERY 2144.
    -- Nenhuma regra de negocio foi alterada.
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

-- Grants reafirmados identicos aos da Query 2144. CREATE OR REPLACE nao
-- altera ACL de funcao existente; estas linhas existem por idempotencia
-- e para que este arquivo seja autossuficiente.
REVOKE ALL ON FUNCTION public.admin_decide_catalog_variant_import_row(UUID[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_decide_catalog_variant_import_row(UUID[], TEXT) TO authenticated;

-- ================================================================
-- Resultado esperado:
--   CREATE FUNCTION (0 linhas), REVOKE, GRANT.
--
-- Como validar:
--   Query 2822 - Validate Variant Import Bulk Contract, Secoes 1 e 2.
--   Espera-se, alem dos testes comportamentais:
--     SELECT prosecdef, proconfig FROM pg_proc ...
--       -> prosecdef = true, proconfig = {"search_path=\"\""}
--     SELECT grantee, privilege_type FROM information_schema.role_routine_grants
--      WHERE routine_name = 'admin_decide_catalog_variant_import_row';
--       -> so 'authenticated' (alem do owner 'postgres'), nenhum anon/PUBLIC.
-- ================================================================
