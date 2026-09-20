-- ============================================================================
-- Query 2833 — MATRIZ DE STATE MACHINE (gate de entrada do 2214)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 2.0
-- CORREÇÕES 1 e 3 da OPERATIONAL-BOUNDARY-CORRECTION-01
--
-- ----------------------------------------------------------------------------
-- O DEFEITO DA v1.0 — uma afirmação falsa, provada falsa
-- ----------------------------------------------------------------------------
--   A v1.0 tinha o gate SM5: "o predicado NAO atinge nenhuma row terminal".
--   O predicado era `VALID + persistence = PENDING`. Medido no LIVE:
--
--       VALID + PENDING = 415 rows
--         414 -> job CANCELLED, decision SKIPPED
--           1 -> job CANCELLED, decision PENDING
--
--       jobs STAGED/CONFIRMING + PENDING + VALID = 0 rows
--
--   Ou seja: o predicado atingia 415 rows HISTORICAS e ZERO operacionais.
--   Errava nas duas direcoes, e o gate SM5 declarava o oposto — porque
--   classificava "terminal" por persistence_status, ignorando o job.
--
--   CAUSA RAIZ, conceitual: persistence_status descreve a ROW; "operacional"
--   e propriedade do JOB. Row PENDING em job cancelado nao e backlog.
--
-- ----------------------------------------------------------------------------
-- O QUE MUDA NA v2.0
-- ----------------------------------------------------------------------------
--   * A matriz passa a ter job_status como PRIMEIRA dimensao.
--   * `pode_mutar` e `pode_confirmar` sao COMPUTADAS a partir do contrato
--     lido em database/schema/2145_... (linhas 270, 286/307, 314, 324),
--     nunca digitadas.
--   * SM5 foi REESCRITO: em vez de afirmar que o predicado nao atinge
--     terminal, MEDE a intersecao e exige zero.
--   * SM9/SM10/SM11 novos: CANCELLED e terminal; o universo confirmavel e
--     conhecido; nenhuma row historica e exigida.
--
-- READ-ONLY. 11 casos.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- MATRIZ COMPLETA. job_status entra como dimensao — era o que faltava.
CREATE TEMP TABLE sm_matrix ON COMMIT DROP AS
SELECT j.status                                                      AS job_status,
       r.validation_status,
       r.decision_status,
       r.persistence_status,
       COUNT(*)                                                      AS rows,
       COUNT(*) FILTER (WHERE jsonb_exists(r.normalized_data,'edition_context_profile_id'))     AS com_chave,
       COUNT(*) FILTER (WHERE NOT jsonb_exists(r.normalized_data,'edition_context_profile_id')) AS sem_chave,
       COUNT(*) FILTER (WHERE r.resulting_variant_id IS NOT NULL)    AS com_resulting,
       COUNT(*) FILTER (WHERE r.matched_variant_id   IS NOT NULL)    AS com_matched,
       -- MEDIDA EXATA DE AUSENCIA DE LINEAGE (LINEAGE-SEMANTICS-CORRECTION-02).
       -- `com_resulting` e `com_matched` sao contagens INDEPENDENTES e a mesma
       -- row pode entrar nas DUAS: o caminho APPROVED -> MATCHED -> UNCHANGED
       -- grava resulting_variant_id E matched_variant_id. Logo a soma
       -- (com_resulting + com_matched) NAO e uma contagem de rows com lineage
       -- — e uma soma de ponteiros, e pode exceder `rows`. Usa-la como prova
       -- de cobertura MASCARA rows sem lineage nenhum:
       --     rows=10, com_resulting=9, com_matched=9  ->  9+9 >= 10  ->  PASS
       --     ainda que UMA row esteja com os dois IDs NULL.
       -- No LIVE ha 715 rows UNCHANGED com AMBOS os ids preenchidos — massa
       -- de sobra para mascarar. Esta coluna conta ROWS, nao ponteiros, e e a
       -- unica base legitima para o SM3.
       COUNT(*) FILTER (WHERE r.resulting_variant_id IS NULL
                          AND r.matched_variant_id   IS NULL)        AS sem_lineage,
       -- ===== COLUNAS DERIVADAS DO CONTRATO CANONICO 2145 =====
       -- pode_mutar: o job ainda aceita trabalho sobre a row.
       (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
        AND r.persistence_status = 'PENDING')                        AS pode_mutar,
       -- pode_confirmar: conjunto que REALMENTE chega ao writer.
       --   2145:270 job IN (STAGED, CONFIRMING)
       --   2145:286/307 persistence PENDING AND decision IN (APPROVED, SKIPPED)
       --   2145:314 SKIPPED -> UNCHANGED, CONTINUE (nenhuma escrita)
       --   2145:324 APPROVED exige validation VALID
       (j.status IN ('STAGED','CONFIRMING')
        AND r.persistence_status = 'PENDING'
        AND r.decision_status    = 'APPROVED'
        AND r.validation_status  = 'VALID')                          AS pode_confirmar
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 GROUP BY 1,2,3,4;

-- Entrega da Correcao 1 — a matriz pedida, na ordem pedida:
--   SELECT job_status, validation_status, decision_status, persistence_status,
--          rows, pode_mutar, pode_confirmar
--     FROM sm_matrix ORDER BY 1,2,3,4;

-- ---------------------------------------------------------------- PASSO 2 ---
DO $$
DECLARE v_n INT; v_lista TEXT; v_pass INT := 0;
BEGIN
    -- SM1 — vocabulario de job.status conhecido (ck_catalog_variant_import_job_status).
    SELECT string_agg(DISTINCT job_status, ', ') INTO v_lista FROM sm_matrix
     WHERE job_status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING',
                              'COMPLETED','COMPLETED_WITH_ERRORS','FAILED','CANCELLED');
    IF v_lista IS NOT NULL THEN
        RAISE EXCEPTION 'SM1_FAIL: job.status desconhecido(s): %. A fronteira operacional precisa ser reavaliada.', v_lista;
    END IF;
    v_pass := v_pass + 1;

    -- SM2 — vocabulario de persistence_status conhecido.
    SELECT string_agg(DISTINCT persistence_status, ', ') INTO v_lista FROM sm_matrix
     WHERE persistence_status NOT IN ('PENDING','INSERTED','UNCHANGED','FAILED','SKIPPED');
    IF v_lista IS NOT NULL THEN
        RAISE EXCEPTION 'SM2_FAIL: persistence_status desconhecido(s): %.', v_lista;
    END IF;
    v_pass := v_pass + 1;

    -- SM3 — nenhuma row terminal sem efeito registrado.
    --
    -- CORRECAO DE PREMISSA (LINEAGE-SEMANTICS-CORRECTION-01). A versao
    -- anterior exigia lineage de TODA row UNCHANGED. Isso contraria o contrato
    -- canonico do confirm (2145:314, e o futuro 2218):
    --
    --     decision_status = 'SKIPPED' -> persistence_status = 'UNCHANGED'
    --       -> CONTINUE -> NENHUMA materializacao de card_variant
    --       -> lineage NAO e obrigatorio.
    --
    -- A propria coluna derivada `pode_confirmar` acima ja documenta essa linha
    -- do contrato; o gate e que nao a respeitava. Mesma semantica agora
    -- aplicada em 2830 (V7/M2) e 2832 (V7).
    --
    --   INSERTED sem resulting ........................... FAIL
    --   UNCHANGED + decision <> SKIPPED sem lineage ...... FAIL
    --   UNCHANGED + SKIPPED sem lineage .................. PERMITIDO
    --
    -- Nao enfraquece o caminho que materializa/matcheia: INSERTED segue
    -- integralmente coberto, e UNCHANGED segue coberto em tudo que nao for
    -- SKIPPED.
    --
    -- CORRECAO ARITMETICA (LINEAGE-SEMANTICS-CORRECTION-02). A medida do ramo
    -- UNCHANGED era `(com_resulting + com_matched) < rows`. Isso e INSEGURO:
    -- as duas colunas contam ROWS independentemente e a MESMA row entra nas
    -- duas quando o caminho APPROVED -> MATCHED -> UNCHANGED grava os dois
    -- ids. A soma conta PONTEIROS, nao rows cobertas, e uma row sem lineage
    -- nenhum fica mascarada pelas demais:
    --     rows=10 · com_resulting=9 · com_matched=9 -> 18 >= 10 -> falso PASS
    -- Contraexemplo minimo verificado: rows=2, com_resulting=1, com_matched=1
    -- (uma row com AMBOS, outra com NENHUM) -> soma=2, 2 < 2 e FALSO -> o gate
    -- antigo NAO dispara; `sem_lineage=1 > 0` -> o gate novo DISPARA.
    -- A prova passa a ser a contagem EXATA de rows sem os dois ids.
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE persistence_status = 'INSERTED' AND com_resulting < rows;
    IF v_n <> 0 THEN RAISE EXCEPTION 'SM3_FAIL: % rows INSERTED sem resulting_variant_id.', v_n; END IF;
    SELECT COALESCE(SUM(sem_lineage),0) INTO v_n FROM sm_matrix
     WHERE persistence_status = 'UNCHANGED'
       AND decision_status <> 'SKIPPED';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SM3_FAIL: % rows UNCHANGED NAO-SKIPPED sem resulting_variant_id E sem matched_variant_id. SKIPPED+UNCHANGED sem lineage e contrato (2145:314); qualquer outra combinacao e defeito.', v_n;
    END IF;
    v_pass := v_pass + 1;

    -- SM4 — nenhuma row confirmavel ja persistida.
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE pode_confirmar AND com_resulting > 0;
    IF v_n <> 0 THEN RAISE EXCEPTION 'SM4_FAIL: % rows confirmaveis com resulting_variant_id.', v_n; END IF;
    v_pass := v_pass + 1;

    -- ===================================================================
    -- SM5 — REESCRITO. Antes AFIRMAVA; agora MEDE.
    -- O predicado do guard nao pode tocar row de job terminal.
    -- ===================================================================
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE validation_status = 'VALID'
       AND persistence_status = 'PENDING'
       AND job_status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING');
    IF v_n <> 0 THEN
        RAISE NOTICE 'SM5 EVIDENCIA: % rows VALID+PENDING em job TERMINAL. O predicado ANTIGO (sem job_status) as atingiria indevidamente — e exatamente o defeito corrigido nesta versao.', v_n;
    END IF;

    -- O predicado NOVO (com job_status) nao pode atingir nenhuma delas.
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE pode_mutar
       AND job_status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SM5_FAIL: % rows classificadas como mutaveis em job terminal — contradicao na derivacao.', v_n;
    END IF;
    v_pass := v_pass + 1;

    -- SM6 — COBERTURA: todo VALID mutavel esta sob o predicado do guard.
    -- Nenhuma row pode chegar a confirmacao sem passar pela exigencia.
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE pode_confirmar AND NOT pode_mutar;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SM6_FAIL: % rows confirmaveis fora do universo mutavel — o guard nao as protegeria.', v_n;
    END IF;
    v_pass := v_pass + 1;

    -- SM7 — PRONTIDAO: zero row OPERACIONAL VALID sem a chave.
    SELECT COALESCE(SUM(sem_chave),0) INTO v_n FROM sm_matrix
     WHERE pode_mutar AND validation_status = 'VALID';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SM7_FAIL: % rows OPERACIONAIS VALID sem a chave. Resolver o eixo antes de promover o guard (2214).', v_n;
    END IF;
    v_pass := v_pass + 1;

    -- SM8 — HOLD historico: toda row sem chave e historica ou NAO-VALID.
    SELECT COALESCE(SUM(sem_chave),0) INTO v_n FROM sm_matrix
     WHERE pode_mutar AND validation_status = 'VALID';
    IF v_n <> 0 THEN RAISE EXCEPTION 'SM8_FAIL: % rows escaparam.', v_n; END IF;
    v_pass := v_pass + 1;

    -- ===================================================================
    -- SM9 — CANCELLED e TERMINAL. Nenhuma row de job cancelado pode ser
    -- classificada como mutavel ou confirmavel, qualquer que seja o seu
    -- proprio persistence_status.
    -- ===================================================================
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE job_status = 'CANCELLED' AND (pode_mutar OR pode_confirmar);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SM9_FAIL: % rows de job CANCELLED classificadas como operacionais.', v_n;
    END IF;

    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE job_status = 'CANCELLED' AND validation_status = 'VALID'
       AND persistence_status = 'PENDING';
    RAISE NOTICE 'SM9 OK — % rows VALID+PENDING em job CANCELLED reconhecidas como HISTORICO TERMINAL. Nao exigem Edition Context, nao sao reativadas, nao recebem JSON null.', v_n;
    v_pass := v_pass + 1;

    -- SM10 — universo confirmavel conhecido e consistente.
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix WHERE pode_confirmar;
    RAISE NOTICE 'SM10 — universo CONFIRMAVEL hoje: % rows.', v_n;
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE pode_mutar AND validation_status = 'NEEDS_REVIEW';
    RAISE NOTICE 'SM10 — universo OPERACIONAL pendente de resolucao: % rows NEEDS_REVIEW.', v_n;
    v_pass := v_pass + 1;

    -- SM11 — nenhuma row historica e EXIGIDA a ter a chave.
    -- Contrapositiva do predicado: se nao e mutavel, nao ha exigencia.
    SELECT COALESCE(SUM(rows),0) INTO v_n FROM sm_matrix
     WHERE NOT pode_mutar AND sem_chave > 0 AND pode_confirmar;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SM11_FAIL: % rows historicas sem chave classificadas como confirmaveis.', v_n;
    END IF;
    v_pass := v_pass + 1;

    RAISE NOTICE 'STATE MACHINE: %/11 provas OK.', v_pass;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
-- EVIDENCIA do universo historico que permanece legitimamente sem chave.
CREATE TEMP TABLE sm_historical_evidence ON COMMIT DROP AS
SELECT j.status AS job_status,
       r.validation_status,
       r.persistence_status,
       vt.code  AS variant_type_code,
       COUNT(*) AS rows,
       COUNT(DISTINCT r.resulting_variant_id)
         FILTER (WHERE r.resulting_variant_id IS NOT NULL) AS variants_distintas
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
  LEFT JOIN public.card_variant cv ON cv.id = r.resulting_variant_id
  LEFT JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
 WHERE NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')
 GROUP BY 1,2,3,4;

--   SELECT * FROM sm_historical_evidence ORDER BY rows DESC;
--   `rows > variants_distintas` torna visivel o ponto da Correcao 2 da
--   BACKFILL-SEMANTICS: lineage NAO e 1:1 com card_variant.

-- ============================================================================
-- GATE: 11/11. Qualquer FAIL bloqueia a Query 2214.
--
-- O QUE ESTA QUERY NAO FAZ
--   Nao escreve, nao reclassifica, nao sugere valor. Responde a uma pergunta:
--   "o predicado proposto e verdadeiro contra os estados que realmente
--   existem?". SM1/SM2 abortam se o vocabulario mudar — a fronteira precisa
--   ser reavaliada antes de qualquer promocao.
-- ============================================================================
ROLLBACK;
