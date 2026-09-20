-- ============================================================================
-- Query 2840 — PROBE T1: caminho de execução × UNIQUE NULLS NOT DISTINCT
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 2.0
-- Mandato: CORREÇÃO 10 (GATE-A-FINAL-CORRECTION-01)
--          + EDITION-CONTEXT-AXIS-T1-PREFLIGHT-01 (v2.0)
--
-- ----------------------------------------------------------------------------
-- v2.0 — DOIS DEFEITOS DA v1.0, CORRIGIDOS
-- ----------------------------------------------------------------------------
-- D1  MATRIZ INSUFICIENTE. A v1.0 testava uma tabela de DUAS colunas (a, b)
--     com UM ÚNICO componente nulável, e provava apenas (1,NULL) x 2. Mas a
--     identidade real da Query 2209 tem QUATRO componentes e DOIS nuláveis
--     SIMULTÂNEOS — e é exatamente o par (card, type, NULL, NULL) x 2 que a
--     migração legada precisa ver colidir. Um teste de um NULL só não prova
--     nada sobre dois NULLs na mesma chave. A v2.0 reproduz a forma exata da
--     chave e cobre a matriz C1–C7 abaixo.
--
-- D2  TERMINADOR `ROLLBACK;` DEIXAVA O LEDGER EM ABERTO. Ver seção própria.
--     Trocado por RAISE EXCEPTION deliberado — o padrao ja MEDIDO no projeto.
--
-- T1 é o ÚNICO probe LIVE que resta no pacote. T2 (INDEX CONCURRENTLY) foi
-- ELIMINADO: a Correção 2 descartou `CONCURRENTLY` em favor de índice normal
-- sob FREEZE, logo não há mais nada a provar sobre execução não-transacional.
--
-- ----------------------------------------------------------------------------
-- O QUE ESTÁ SENDO PROVADO
-- ----------------------------------------------------------------------------
-- Que o caminho de execução real do projeto entrega ao servidor a cláusula
-- `NULLS NOT DISTINCT` LITERAL, sem reescrita nem supressão por camada
-- intermediária. "PostgreSQL 17.6" prova que o SERVIDOR suporta; não prova
-- que o CAMINHO preserva.
--
-- O MODO DE FALHA QUE IMPORTA não é o erro de sintaxe — esse é ruidoso e
-- inofensivo. É a cláusula ser silenciosamente IGNORADA: o índice nasceria
-- com semântica NULLS DISTINCT, duas Variants "sem contexto" deixariam de
-- colidir, e a identidade de quatro componentes estaria quebrada sem nenhum
-- sinal. Por isso o teste é COMPORTAMENTAL, não sintático.
--
-- ----------------------------------------------------------------------------
-- POR QUE `RAISE EXCEPTION` NO FIM, E NÃO `ROLLBACK;`
-- ----------------------------------------------------------------------------
-- Precedente MEDIDO neste projeto, registrado na Query 2200 (linhas 22-24):
--     "O abort desfez as três escritas (bloco DO é instrução única);
--      rollback provado TOTAL, migration NÃO REGISTRADA no LIVE."
-- Ou seja: quando a execução ABORTA, o `apply_migration` não grava entrada em
-- `supabase_migrations.schema_migrations`. O registro do ledger participa da
-- mesma transação do corpo.
--
-- Um `ROLLBACK;` explícito no corpo NÃO tem essa garantia medida: ele encerra
-- a transação por dentro, e o que o driver faz depois com o INSERT do ledger
-- é comportamento não observado neste projeto. Assumir que também não grava
-- seria exatamente o "é só um registro" que o mandato T1-PREFLIGHT-01 proíbe.
--
-- Portanto o artefato termina em erro DELIBERADO. O abort é o mecanismo, não
-- um acidente: garante rollback total E ausência de ledger, por construção e
-- por precedente. É o mesmo padrão já adotado em 5822/5823, pelo mesmo motivo.
--
-- CONSEQUÊNCIA OPERACIONAL: uma execução BEM-SUCEDIDA de T1 TERMINA EM ERRO.
-- O texto do erro é o relatório. Ver "RESULTADO ESPERADO" no rodapé.
--
-- ----------------------------------------------------------------------------
-- INDEPENDÊNCIA
-- ----------------------------------------------------------------------------
-- Zero referência a card_variant, card_edition_context_*, card_printing_* ou
-- qualquer objeto de 2203–2232. Os UUIDs são literais fixos. O probe roda
-- igual num banco vazio.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRÉ-CHECK: NULLS NOT DISTINCT existe desde o PG 15.
DO $$
DECLARE v_num INT := current_setting('server_version_num')::INT;
BEGIN
    IF v_num < 150000 THEN
        RAISE EXCEPTION 'T1_SERVER_TOO_OLD: server_version_num=% (< 150000). NULLS NOT DISTINCT indisponivel.', v_num;
    END IF;
    RAISE NOTICE 'T1 servidor: % — OK', current_setting('server_version');
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- FORMA EXATA DA IDENTIDADE DA QUERY 2209: quatro componentes, os dois
-- ÚLTIMOS nuláveis. Tipos UUID como no real — não para testar o tipo, mas
-- para remover qualquer objeção de que o probe testou outra coisa.
-- Se a cláusula for REJEITADA pelo caminho, o erro aparece AQUI.
CREATE TEMP TABLE t_nnd_probe (
    card_id                    UUID NOT NULL,
    variant_type_id            UUID NOT NULL,
    printing_profile_id        UUID,
    edition_context_profile_id UUID,
    CONSTRAINT uq_t_nnd UNIQUE NULLS NOT DISTINCT
        (card_id, variant_type_id, printing_profile_id, edition_context_profile_id)
) ON COMMIT DROP;

-- ---------------------------------------------------------------- PASSO 3 ---
-- PROVA ESTRUTURAL: o catálogo confirma indnullsnotdistinct = true.
-- Prova contra o modo de falha silenciosa (aceita e ignora).
DO $$
DECLARE v_nnd BOOLEAN; v_ncols INT;
BEGIN
    SELECT i.indnullsnotdistinct, i.indnatts
      INTO v_nnd, v_ncols
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
     WHERE c.relname = 'uq_t_nnd';

    IF v_nnd IS NULL THEN
        RAISE EXCEPTION 'T1_INDEX_NOT_FOUND: indice uq_t_nnd nao encontrado no catalogo.';
    END IF;
    IF v_ncols <> 4 THEN
        RAISE EXCEPTION 'T1_INDEX_ARITY: esperadas 4 colunas no indice, obtidas %.', v_ncols;
    END IF;
    IF v_nnd IS NOT TRUE THEN
        RAISE EXCEPTION 'T1_CLAUSE_SILENTLY_DROPPED: indice criado mas indnullsnotdistinct = false. A clausula foi ACEITA e IGNORADA — pior cenario. A estrategia de identidade cai para indices parciais e a Query 2209 deve ser reescrita ANTES de qualquer execucao.';
    END IF;
    RAISE NOTICE 'T1 estrutural: indnullsnotdistinct = true, 4 colunas — OK';
END $$;

-- ---------------------------------------------------------------- PASSO 4 ---
-- MATRIZ COMPORTAMENTAL C1–C7. É a parte que realmente importa.
--
-- Convenção dos literais:
--   CARD_A = aaaaaaaa-...  CARD_B = bbbbbbbb-...
--   TYPE_1 = 11111111-...  PRINT_1 = 33333333-...  EC_1 = 44444444-...
DO $$
DECLARE
    c_card_a  UUID := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    c_card_b  UUID := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    c_type_1  UUID := '11111111-1111-4111-8111-111111111111';
    c_print_1 UUID := '33333333-3333-4333-8333-333333333333';
    c_ec_1    UUID := '44444444-4444-4444-8444-444444444444';
    v_state   TEXT;
    v_n       INT;
BEGIN
    -- ===== C1 — LINHA BASE: legado puro, DOIS NULLs simultâneos ==============
    INSERT INTO t_nnd_probe VALUES (c_card_a, c_type_1, NULL, NULL);

    -- ===== C2 — O CASO CENTRAL DO MANDATO ===================================
    -- (a, b, NULL, NULL) versus (a, b, NULL, NULL) -> DEVE COLIDIR.
    -- Sem isto, duas Variants legadas idênticas coexistiriam e a identidade
    -- de quatro componentes seria ficção.
    BEGIN
        INSERT INTO t_nnd_probe VALUES (c_card_a, c_type_1, NULL, NULL);
        RAISE EXCEPTION 'T1_C2_FAILED: duplicata (card_a, type_1, NULL, NULL) foi ACEITA. Com DOIS NULLs simultaneos a chave NAO colide — NULLS NOT DISTINCT nao esta em vigor. Este e o cenario que quebra a identidade legada.';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'C2 OK — (a, t, NULL, NULL) x2 rejeitada com 23505';
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
            IF v_state = 'P0001' THEN RAISE; END IF;
            RAISE EXCEPTION 'T1_C2_UNEXPECTED_SQLSTATE: esperado 23505, obtido %.', v_state;
    END;

    -- ===== C3 — DIFERE SÓ EM PRINTING (NULL -> valor): DEVE PASSAR ==========
    -- Prova que a cláusula trata NULL como VALOR, não como curinga que
    -- casaria com qualquer coisa. Se falhasse, o eixo Printing seria inútil.
    BEGIN
        INSERT INTO t_nnd_probe VALUES (c_card_a, c_type_1, c_print_1, NULL);
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'T1_C3_FAILED: (a, t, PRINT_1, NULL) foi REJEITADA contra (a, t, NULL, NULL). NULL esta agindo como curinga — identidades legitimamente distintas estao sendo bloqueadas.';
    END;
    RAISE NOTICE 'C3 OK — difere so em Printing: aceita';

    -- ===== C4 — DIFERE SÓ EM EDITION CONTEXT (NULL -> valor): DEVE PASSAR ===
    -- É a razão de ser do eixo 3. Se falhasse, 2209 tornaria impossível
    -- decompor o legado em 2213.
    BEGIN
        INSERT INTO t_nnd_probe VALUES (c_card_a, c_type_1, NULL, c_ec_1);
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'T1_C4_FAILED: (a, t, NULL, EC_1) foi REJEITADA contra (a, t, NULL, NULL). O eixo de Edition Context nao discrimina — a decomposicao da 2213 seria impossivel.';
    END;
    RAISE NOTICE 'C4 OK — difere so em Edition Context: aceita';

    -- ===== C5 — DIFERE NOS DOIS EIXOS: DEVE PASSAR ==========================
    BEGIN
        INSERT INTO t_nnd_probe VALUES (c_card_a, c_type_1, c_print_1, c_ec_1);
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'T1_C5_FAILED: (a, t, PRINT_1, EC_1) foi REJEITADA indevidamente.';
    END;
    RAISE NOTICE 'C5 OK — difere em Printing e Edition Context: aceita';

    -- ===== C6 — COLAPSO NA CHAVE DE 3: UM NULL, MESMO PRINTING ==============
    -- (a, t, PRINT_1, NULL) ja existe por C3. Repetir DEVE colidir.
    -- Prova o argumento de colapso do 2213-CRITICAL-PATH-DECISION: restrita
    -- a EC = NULL, a chave de 4 se comporta exatamente como a de 3.
    BEGIN
        INSERT INTO t_nnd_probe VALUES (c_card_a, c_type_1, c_print_1, NULL);
        RAISE EXCEPTION 'T1_C6_FAILED: duplicata (a, t, PRINT_1, NULL) foi ACEITA. A chave de 4 NAO colapsa na de 3 quando EC e NULL — o argumento de nao-colisao do legado nao se sustenta.';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'C6 OK — (a, t, PRINT_1, NULL) x2 rejeitada com 23505';
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
            IF v_state = 'P0001' THEN RAISE; END IF;
            RAISE EXCEPTION 'T1_C6_UNEXPECTED_SQLSTATE: esperado 23505, obtido %.', v_state;
    END;

    -- ===== C7 — OUTRA CARD, MESMOS NULLs: DEVE PASSAR =======================
    -- O primeiro componente continua discriminando; a colisao de C2 nao é
    -- um "tudo com NULL colide".
    BEGIN
        INSERT INTO t_nnd_probe VALUES (c_card_b, c_type_1, NULL, NULL);
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'T1_C7_FAILED: (card_b, t, NULL, NULL) foi REJEITADA contra (card_a, ...). A chave nao discrimina por card_id.';
    END;
    RAISE NOTICE 'C7 OK — outra Card com os mesmos NULLs: aceita';

    -- ===== POSTCHECK: exatamente 5 linhas =================================
    -- C1 · C3 · C4 · C5 · C7 entraram. C2 e C6 foram rejeitadas.
    SELECT COUNT(*) INTO v_n FROM t_nnd_probe;
    IF v_n <> 5 THEN
        RAISE EXCEPTION 'T1_POSTCHECK_COUNT: esperadas 5 linhas (C1,C3,C4,C5,C7), obtidas %.', v_n;
    END IF;

    -- ===== TERMINADOR DELIBERADO ==========================================
    -- Sucesso comunicado POR EXCEÇÃO. Ver "POR QUE RAISE EXCEPTION" no
    -- cabeçalho: aborta -> rollback total -> ledger nao registra.
    RAISE EXCEPTION 'T1_PASS_ROLLBACK_INTENCIONAL: 7/7 casos + postcheck (5 linhas). NULLS NOT DISTINCT VIAVEL por este caminho de execucao. Este erro e DELIBERADO — garante rollback total e ausencia de entrada no migration ledger. Query 2209 LIBERADA.';
END $$;

-- ============================================================================
-- NOTA: a linha abaixo é INALCANÇÁVEL — o PASSO 4 sempre termina em exceção,
-- por desenho. Mantida para que o arquivo continue legível como transação
-- fechada e para o caso de execução manual por psql com o RAISE final
-- comentado.
-- ============================================================================
ROLLBACK;

-- ============================================================================
-- MATRIZ MÍNIMA T1 — 7 casos
-- ----------------------------------------------------------------------------
--  #   (card, type, printing, ec)                   esperado    prova o quê
--  C1  (A, T, NULL, NULL)                           ACEITA      linha base legada
--  C2  (A, T, NULL, NULL)   repetida                23505       DOIS NULLs colidem  <- caso central
--  C3  (A, T, P1,   NULL)                           ACEITA      Printing discrimina
--  C4  (A, T, NULL, E1)                             ACEITA      Edition Context discrimina
--  C5  (A, T, P1,   E1)                             ACEITA      os dois eixos juntos
--  C6  (A, T, P1,   NULL)   repetida                23505       colapso na chave de 3
--  C7  (B, T, NULL, NULL)                           ACEITA      card_id ainda discrimina
--
--  Linhas ao fim: 5   (C1, C3, C4, C5, C7)
--
-- RESULTADO ESPERADO DA EXECUÇÃO
--   NOTICEs: servidor OK · estrutural OK · C2 · C3 · C4 · C5 · C6 · C7
--   ERRO FINAL (esperado e desejado):
--     T1_PASS_ROLLBACK_INTENCIONAL: 7/7 casos + postcheck (5 linhas)...
--
--   QUALQUER outro erro = FALHA REAL. Em especial:
--     T1_CLAUSE_SILENTLY_DROPPED ... cláusula ignorada  -> plano B
--     T1_C2_FAILED ................ dois NULLs não colidem -> plano B
--     T1_C4_FAILED ................ eixo 3 não discrimina  -> revisar 2209
--
-- ZERO RESÍDUO — quatro camadas independentes
--   1. TEMP TABLE: vive em `pg_temp_<n>`, invisível a `public`. Nenhum objeto
--      canônico é criado, alterado ou consultado.
--   2. `ON COMMIT DROP`: mesmo um COMMIT acidental destruiria a tabela.
--   3. O RAISE final ABORTA a transação: tudo é desfeito.
--   4. Precedente medido (Query 2200): abort => migration NÃO registrada no
--      ledger `supabase_migrations.schema_migrations`.
--   Nenhuma tabela, índice, constraint, função, tipo ou grant permanente é
--   criado. Nenhum dado de negócio é lido ou escrito. `card_variant` não é
--   referenciada em lugar nenhum deste arquivo.
--
--   Prova de resíduo zero, em chamada SEPARADA depois de T1:
--     SELECT COUNT(*) AS residuo
--       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
--      WHERE c.relname IN ('t_nnd_probe','uq_t_nnd')
--        AND n.nspname NOT LIKE 'pg_temp%';      -- esperado: 0
--
-- SE T1 FALHAR
--   Plano B: trocar `UNIQUE(4) NULLS NOT DISTINCT` por QUATRO índices únicos
--   parciais (NULL/NULL, NULL/NOT NULL, NOT NULL/NULL, NOT NULL/NOT NULL),
--   reescrevendo a Query 2209 ANTES de qualquer execução. O custo conhecido
--   dessa alternativa é o motivo de ela não ser a primeira escolha: o modo de
--   falha de um predicado parcial mal escrito é SILENCIOSO.
--
-- **NÃO EXECUTAR SEM AUTORIZAÇÃO EXPLÍCITA DE FABRÍCIO.**
-- ============================================================================
