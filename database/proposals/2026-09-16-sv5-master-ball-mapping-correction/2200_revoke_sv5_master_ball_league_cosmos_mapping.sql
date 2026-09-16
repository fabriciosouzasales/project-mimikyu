/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2200 - Revoke SV5 Master Ball League COSMOS Mapping
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO — LIVE (migration 20260916212542, 2026-09-16)
              G01–G26 PASS. Efeito: mappings SCOPED sv05 9→8; row 64eeface
              VALID→NEEDS_REVIEW com normalized_data={}; job valid_rows 418→417.
              Aplicada em SV5-MASTER-BALL-CORRECTION-EXECUTION-02.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Criação (2026-09-16).** Correção pontual da falsa certeza COSMOS em
        SV5: remove o mapping d050cd63, devolve a row 64eeface a NEEDS_REVIEW e
        recalcula valid_rows do job. Aprovada em SV5-MASTER-BALL-CORRECTION-
        STAGING-01.
| 1.1 | **Fix do guard G22 (2026-09-16).** A primeira execução (EXECUTION-01)
        abortou com `42803: aggregate functions are not allowed in GROUP BY`.
        Causa: o `GROUP BY 1` do G22 referenciava a expressão da coluna 1, que
        contém `COUNT(*)`. Substituído por `GROUP BY r.decision_status,
        r.persistence_status` — semântica idêntica à pretendida. O abort
        desfez as três escritas (bloco DO é instrução única); rollback provado
        TOTAL, migration não registrada no LIVE. Nenhuma constante, nenhum
        outro guard, nenhuma escrita e nenhum comportamento foram alterados.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-16
Mandato.....: CARD-VARIANTS — EDITORIAL CONVERGENCE /
               SV5-MASTER-BALL-CORRECTION-STAGING-01
Diagnóstico.: SV5-EXTERNAL-EVIDENCE-AUDIT-02 (contradição material) +
               SV5-MASTER-BALL-MAPPING-FORENSIC-01 (blast radius provado)

-------------------------------------------------------------------------------
POR QUE ESTA MIGRATION EXISTE
-------------------------------------------------------------------------------
Em 2026-09-15T23:43 um ciclo editorial criou, em 32 segundos e na mesma sessão:

  23:43:19  card_variant_type   11f7c959-… MASTER_BALL_LEAGUE_COSMOS_HOLO
  23:43:51  mapping SCOPED sv05 d050cd63-… NORMAL + {MASTER-BALL-LEAGUE}
                                  -> 11f7c959-…

O mapping materializou `normalized_data.variant_type_id` na única linha de
staging com essa assinatura residual e promoveu-a de NEEDS_REVIEW para VALID.

A auditoria SV5-EXTERNAL-EVIDENCE-AUDIT-02 esgotou a pesquisa externa
(níveis 1 a 5 da hierarquia de evidência) e concluiu:

  - NENHUMA fonte sustenta acabamento COSMOS para a variante Master Ball
    League de sv05 (Buddy-Buddy Poffin 144/162);
  - a única atestação de "Cosmos Holo" encontrada pertence a OUTRO produto
    (Play! Prize Pack Series, TCGplayer 565451) — transferência indevida;
  - a única atestação específica do selo Master Ball diz "Holo", não COSMOS,
    e é listing isolado (nível 5) — insuficiente para fechar decisão.

A auditoria forense SV5-MASTER-BALL-MAPPING-FORENSIC-01 acrescentou que o
MESMO selo já possuía interpretação anterior no próprio corpus:

  mapping GLOBAL d50c6a98-… (2026-08-15, external_set_id = NULL)
    holo + {master-ball-league} -> MASTER_BALL_HOLO

Não são duplicata (assinaturas residuais diferem: NORMAL vs HOLO, e por isso
`fallback_global_mapping_id` foi corretamente registrado como null). Mas o
efeito editorial é que o mesmo selo físico recebeu duas leituras de acabamento
em momentos distintos, e a segunda inventou um Variant Type sem evidência.

O mapping d050cd63 é, portanto, uma FALSA CERTEZA: afirma um acabamento
(COSMOS) que nenhuma evidência sustenta, e — pior — BLOQUEIA a correção
futura, porque `internal.apply_variant_type_mapping` recusa reprocessar
qualquer linha que não esteja em NEEDS_REVIEW (guard ORIGIN_NOT_NEEDS_REVIEW)
e recusa segunda interpretação da mesma assinatura (guard DUPLICATE_GLOBAL).

-------------------------------------------------------------------------------
O QUE ESTA MIGRATION FAZ — E O QUE DELIBERADAMENTE NÃO FAZ
-------------------------------------------------------------------------------
FAZ, em uma única transação, exatamente três escritas:

  1. DELETE do mapping d050cd63-…                        (cardinalidade = 1)
  2. UPDATE da row 64eeface-… de volta para
     NEEDS_REVIEW / NEW / PENDING / PENDING,
     normalized_data = '{}', matched_variant_id = NULL   (cardinalidade = 1)
  3. UPDATE de catalog_variant_import_job.valid_rows,
     recalculado pela MESMA fórmula usada em
     internal.apply_variant_type_mapping                 (cardinalidade = 1)

NÃO FAZ, por decisão explícita do mandato:

  - NÃO substitui COSMOS por HOLO / REVERSE / STANDARD. A ausência de
    evidência não autoriza uma segunda afirmação; a linha volta a ser
    um resíduo editorial honesto, classe B (existência confirmada,
    acabamento indeterminado).
  - NÃO desativa o Variant Type. A desativação é passo separado, por RPC
    canônica (`public.admin_deactivate_card_variant_type`), sob autorização
    própria. Ver README desta proposal.
  - NÃO remove o Variant Type. Há 0 card_variant e 0 referência de pricing,
    mas "sem uso" não é prova de "errado" — a hipótese COSMOS permanece
    arquivada e reativável.
  - NÃO cria RPC genérica de rollback de mapping (decisão aprovada:
    correção pontual, não mecanismo novo).
  - NÃO amplia o CHECK de `catalog_admin_action_log` (decisão aprovada).
    Consequência assumida e registrada: a REMOÇÃO não deixa rastro no
    action_log. O rastro passa a ser esta migration versionada + os dois
    eventos de CRIAÇÃO, que permanecem intactos. Dívida conhecida, não
    silenciada.
  - NÃO toca o mapping GLOBAL d50c6a98 (Master Ball / MASTER_BALL_HOLO).
  - NÃO toca a row irmã c2bc937a (Master Ball + Judge, NEEDS_REVIEW).
  - NÃO toca a linha EB Games aa9ba80b.
  - NÃO toca nenhum outro mapping, row, job ou Card Set.
  - NÃO cria, altera ou remove card_variant.
  - NÃO confirma o job.

-------------------------------------------------------------------------------
ATOMICIDADE
-------------------------------------------------------------------------------
Todo o corpo é UM ÚNICO bloco DO. Um bloco DO é uma única instrução SQL,
portanto atômica mesmo sob autocommit: qualquer RAISE EXCEPTION — de
pré-condição OU de pós-condição — desfaz as três escritas. Não existe estado
intermediário observável. Isto é deliberado: remover o mapping sem reverter
a row deixaria a linha VALID apontando para um Variant Type sem mapeamento,
estado PIOR que o atual.

-------------------------------------------------------------------------------
GUARDS (fail-closed)
-------------------------------------------------------------------------------
PRÉ  G01..G14  — identidade nominal, unicidade, estado e baseline numérico.
POST G15..G26  — efeito exato, e prova de NÃO-TOQUE por fingerprint md5
                 capturado ANTES e comparado DEPOIS.

Nenhum guard usa heurística textual. Toda seleção é por UUID nominal.
================================================================
*/

DO $mig$
DECLARE
    -- ---------------------------------------------------------------
    -- Identidades nominais (SV5-MASTER-BALL-MAPPING-FORENSIC-01)
    -- ---------------------------------------------------------------
    c_mapping_id      CONSTANT UUID := 'd050cd63-099a-47c4-9a1c-46ad09e37e6a';
    c_variant_type_id CONSTANT UUID := '11f7c959-a063-4d43-9daf-1290f69c18db';
    c_row_id          CONSTANT UUID := '64eeface-00f2-49a4-a093-cb3b6d033614';
    c_job_id          CONSTANT UUID := '601f7c96-8118-4b97-a0f3-cbbf418e8c21';
    c_card_id         CONSTANT UUID := '36687b33-78b2-4185-a325-34e1cc84a219';
    c_game_id         CONSTANT UUID := 'f3c1ae5f-c387-46bd-b7a8-2bb21455c285';
    c_source_id       CONSTANT UUID := 'f070791a-a2a0-4bdf-b84d-abf873c5f8d5';

    -- Objetos que NÃO podem ser tocados
    c_global_mbl_id   CONSTANT UUID := 'd50c6a98-fcfa-4c11-aaf4-07e6a1cb0b60';
    c_sibling_row_id  CONSTANT UUID := 'c2bc937a-270a-4ae6-8b82-c2448881b5fa';
    c_ebgames_id      CONSTANT UUID := 'aa9ba80b-9f83-45a4-8a50-ebf6472197d5';

    c_vt_code         CONSTANT TEXT := 'MASTER_BALL_LEAGUE_COSMOS_HOLO';
    c_scope           CONSTANT TEXT := 'sv05';

    -- Baseline numérico esperado (LIVE em 2026-09-16)
    c_pre_scoped_sv05 CONSTANT INTEGER := 9;
    c_pre_valid       CONSTANT INTEGER := 418;
    c_pre_needs       CONSTANT INTEGER := 10;
    c_pre_total       CONSTANT INTEGER := 428;

    -- Alvo
    c_post_scoped_sv05 CONSTANT INTEGER := 8;
    c_post_valid       CONSTANT INTEGER := 417;
    c_post_needs       CONSTANT INTEGER := 11;

    v_n                INTEGER;
    v_txt              TEXT;
    v_affected         INTEGER;

    -- Fingerprints de NÃO-TOQUE (capturados antes, conferidos depois)
    v_fp_global_pre    TEXT;  v_fp_global_post    TEXT;
    v_fp_sibling_pre   TEXT;  v_fp_sibling_post   TEXT;
    v_fp_ebgames_pre   TEXT;  v_fp_ebgames_post   TEXT;
    v_fp_othermap_pre  TEXT;  v_fp_othermap_post  TEXT;
    v_fp_otherrows_pre TEXT;  v_fp_otherrows_post TEXT;
    v_cv_count_pre     INTEGER; v_cv_count_post    INTEGER;
    v_job_total_pre    INTEGER; v_job_total_post   INTEGER;
    v_fp_actionlog_pre TEXT;  v_fp_actionlog_post TEXT;
BEGIN
    -- =================================================================
    -- PRÉ G01 — o mapping alvo existe com identidade EXATA e completa.
    -- Qualquer divergência de um único campo aborta.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.card_variant_type_external_mapping m
     WHERE m.id                = c_mapping_id
       AND m.game_id           = c_game_id
       AND m.asset_source_id   = c_source_id
       AND m.external_set_id   = c_scope
       AND m.external_type     = 'NORMAL'
       AND m.external_foil     IS NULL
       AND m.external_subtype  IS NULL
       AND m.external_stamp    = ARRAY['MASTER-BALL-LEAGUE']::TEXT[]
       AND m.normalized_type   = 'NORMAL'
       AND m.normalized_foil   IS NULL
       AND m.normalized_subtype IS NULL
       AND m.normalized_stamp  = ARRAY['MASTER-BALL-LEAGUE']::TEXT[]
       AND m.variant_type_id   = c_variant_type_id;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G01_MAPPING_IDENTITY: esperado exatamente 1 mapping com a identidade nominal completa, encontrado %.', v_n;
    END IF;

    -- =================================================================
    -- PRÉ G02 — o Variant Type alvo existe com o code esperado.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.card_variant_type vt
     WHERE vt.id = c_variant_type_id AND vt.code = c_vt_code;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G02_VT_IDENTITY: Variant Type % com code % não encontrado (n=%).', c_variant_type_id, c_vt_code, v_n;
    END IF;

    -- =================================================================
    -- PRÉ G03 — o mapping alvo é o ÚNICO que aponta para esse VT.
    -- Impede remover um mapping que faz parte de um conjunto maior.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.card_variant_type_external_mapping m
     WHERE m.variant_type_id = c_variant_type_id;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G03_VT_MAPPING_CARDINALITY: esperado 1 mapping apontando para o VT, encontrado %.', v_n;
    END IF;

    -- =================================================================
    -- PRÉ G04 — o VT não tem identidade materializada. Se existir
    -- card_variant, a correção deixa de ser reversível e vira
    -- reconciliação editorial — que NÃO é o escopo desta migration.
    -- =================================================================
    SELECT COUNT(*) INTO v_n FROM public.card_variant cv
     WHERE cv.variant_type_id = c_variant_type_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SV5_MBL_G04_VT_MATERIALIZED: o VT já possui % card_variant. Correção exige reconciliação editorial explícita, fora do escopo desta migration.', v_n;
    END IF;

    -- =================================================================
    -- PRÉ G05 — o VT não é referenciado por pricing.
    -- =================================================================
    SELECT (SELECT COUNT(*) FROM public.pricing_source_variant_mapping p
             WHERE p.variant_type_id = c_variant_type_id)
         + (SELECT COUNT(*) FROM public.pricing_source_card_identity i
             WHERE i.card_variant_type_id = c_variant_type_id)
      INTO v_n;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SV5_MBL_G05_VT_PRICING_REFS: o VT possui % referência(s) em pricing.', v_n;
    END IF;

    -- =================================================================
    -- PRÉ G06 — a staging row alvo está no estado EXATO documentado.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
     WHERE r.id = c_row_id
       AND r.job_id  = c_job_id
       AND r.card_id = c_card_id
       AND r.validation_status  = 'VALID'
       AND r.match_status       = 'NEW'
       AND r.decision_status    = 'PENDING'
       AND r.persistence_status = 'PENDING'
       AND r.matched_variant_id   IS NULL
       AND r.resulting_variant_id IS NULL
       AND r.normalized_data ->> 'variant_type_id' = c_variant_type_id::TEXT;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G06_ROW_STATE: a row alvo não está no estado esperado (VALID/NEW/PENDING/PENDING apontando para o VT). n=%.', v_n;
    END IF;

    -- =================================================================
    -- PRÉ G07 — o raw_data da row é exatamente a assinatura auditada.
    -- Protege contra re-staging silencioso do job entre auditoria e
    -- execução.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
     WHERE r.id = c_row_id
       AND r.raw_data ->> 'type'    = 'normal'
       AND (r.raw_data -> 'foil')    = 'null'::JSONB
       AND (r.raw_data -> 'subtype') = 'null'::JSONB
       AND (r.raw_data -> 'stamp')   = '["master-ball-league"]'::JSONB;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G07_ROW_RAW_SIGNATURE: raw_data da row alvo diverge da assinatura auditada.';
    END IF;

    -- =================================================================
    -- PRÉ G08 — essa row é a ÚNICA no banco inteiro resolvida por esse
    -- VT. Garante que a reversão não deixa órfãos nem atinge outro job.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
     WHERE r.normalized_data ->> 'variant_type_id' = c_variant_type_id::TEXT;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G08_ROW_CARDINALITY: esperado exatamente 1 row resolvida pelo VT em todo o banco, encontrado %.', v_n;
    END IF;

    -- =================================================================
    -- PRÉ G09 — o job está STAGED e é o job nominal. Job confirmado ou
    -- cancelado torna a reversão sem sentido.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_job j
     WHERE j.id = c_job_id
       AND j.status = 'STAGED'
       AND j.source = 'TCGDEX'
       AND j.external_set_id = c_scope;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G09_JOB_STATE: job % não está STAGED/TCGDEX/sv05.', c_job_id;
    END IF;

    -- =================================================================
    -- PRÉ G10 — baseline de contagens do job.
    -- =================================================================
    SELECT COUNT(*) FILTER (WHERE r.validation_status = 'VALID'),
           COUNT(*) FILTER (WHERE r.validation_status = 'NEEDS_REVIEW'),
           COUNT(*)
      INTO v_n, v_affected, v_job_total_pre
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = c_job_id;
    IF v_n <> c_pre_valid OR v_affected <> c_pre_needs OR v_job_total_pre <> c_pre_total THEN
        RAISE EXCEPTION 'SV5_MBL_G10_JOB_BASELINE: esperado VALID=%/NEEDS_REVIEW=%/TOTAL=%, encontrado %/%/%.',
            c_pre_valid, c_pre_needs, c_pre_total, v_n, v_affected, v_job_total_pre;
    END IF;

    -- Contador GRAVADO precisa estar coerente com o real antes de mexer.
    SELECT j.valid_rows, j.total_rows INTO v_n, v_affected
      FROM public.catalog_variant_import_job j WHERE j.id = c_job_id;
    IF v_n <> c_pre_valid OR v_affected <> c_pre_total THEN
        RAISE EXCEPTION 'SV5_MBL_G10B_JOB_COUNTERS_DRIFT: contadores gravados (valid=%, total=%) divergem do baseline (%, %).',
            v_n, v_affected, c_pre_valid, c_pre_total;
    END IF;

    -- =================================================================
    -- PRÉ G11 — baseline de mappings SCOPED sv05.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.card_variant_type_external_mapping m
     WHERE m.external_set_id = c_scope;
    IF v_n <> c_pre_scoped_sv05 THEN
        RAISE EXCEPTION 'SV5_MBL_G11_SCOPED_BASELINE: esperados % mappings SCOPED sv05, encontrados %.', c_pre_scoped_sv05, v_n;
    END IF;

    -- =================================================================
    -- PRÉ G12 — o mapping GLOBAL de Master Ball existe e NÃO é o alvo.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.card_variant_type_external_mapping m
     WHERE m.id = c_global_mbl_id AND m.external_set_id IS NULL;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G12_GLOBAL_MISSING: mapping GLOBAL de Master Ball (%) não encontrado.', c_global_mbl_id;
    END IF;

    -- =================================================================
    -- PRÉ G13 — a row irmã (Master Ball + Judge) existe e está em
    -- NEEDS_REVIEW. Ela NÃO pode ser tocada.
    -- =================================================================
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
     WHERE r.id = c_sibling_row_id
       AND r.job_id = c_job_id
       AND r.validation_status = 'NEEDS_REVIEW';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G13_SIBLING_STATE: row irmã % não está em NEEDS_REVIEW no job alvo.', c_sibling_row_id;
    END IF;

    -- =================================================================
    -- PRÉ G14 — nenhum dos ids protegidos coincide com os alvos.
    -- Guard de sanidade contra erro de digitação nas constantes.
    -- =================================================================
    IF c_mapping_id IN (c_global_mbl_id, c_ebgames_id)
       OR c_row_id  IN (c_sibling_row_id, c_ebgames_id)
       OR c_variant_type_id = c_ebgames_id THEN
        RAISE EXCEPTION 'SV5_MBL_G14_ID_COLLISION: um id alvo coincide com um id protegido.';
    END IF;

    -- =================================================================
    -- FINGERPRINTS DE NÃO-TOQUE (capturados ANTES das escritas)
    -- =================================================================
    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_global_pre
      FROM (SELECT to_jsonb(m)::TEXT AS r FROM public.card_variant_type_external_mapping m
             WHERE m.id = c_global_mbl_id) t;

    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_sibling_pre
      FROM (SELECT to_jsonb(r)::TEXT AS r FROM public.catalog_variant_import_row r
             WHERE r.id = c_sibling_row_id) t;

    -- EB Games: o id é rastreado em TODAS as tabelas plausíveis, sem
    -- assumir de qual entidade ele é.
    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_ebgames_pre
      FROM (
        SELECT to_jsonb(m)::TEXT AS r FROM public.card_variant_type_external_mapping m WHERE m.id = c_ebgames_id
        UNION ALL
        SELECT to_jsonb(vt)::TEXT FROM public.card_variant_type vt WHERE vt.id = c_ebgames_id
        UNION ALL
        SELECT to_jsonb(r2)::TEXT FROM public.catalog_variant_import_row r2 WHERE r2.id = c_ebgames_id
        UNION ALL
        SELECT to_jsonb(cv)::TEXT FROM public.card_variant cv WHERE cv.id = c_ebgames_id
      ) t;

    -- Todos os OUTROS mappings (qualquer escopo) devem ficar idênticos.
    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_othermap_pre
      FROM (SELECT to_jsonb(m)::TEXT AS r FROM public.card_variant_type_external_mapping m
             WHERE m.id <> c_mapping_id) t;

    -- Todas as OUTRAS rows do universo de variantes devem ficar idênticas.
    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_otherrows_pre
      FROM (SELECT to_jsonb(r)::TEXT AS r FROM public.catalog_variant_import_row r
             WHERE r.id <> c_row_id) t;

    SELECT COUNT(*) INTO v_cv_count_pre FROM public.card_variant;

    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_actionlog_pre
      FROM (SELECT to_jsonb(l)::TEXT AS r FROM public.catalog_admin_action_log l) t;

    -- =================================================================
    -- ESCRITA 1 — remover o mapping (a falsa certeza).
    -- =================================================================
    DELETE FROM public.card_variant_type_external_mapping
     WHERE id = c_mapping_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_W1_DELETE_CARDINALITY: DELETE afetou % linha(s), esperado exatamente 1.', v_affected;
    END IF;

    -- =================================================================
    -- ESCRITA 2 — devolver a row ao estado de revisão editorial.
    -- normalized_data = '{}' reproduz o shape canônico de uma linha
    -- NEEDS_REVIEW não resolvida (idêntico ao da row irmã c2bc937a).
    -- Os guards de estado são repetidos no WHERE: fail-closed também
    -- contra concorrência entre o SELECT de G06 e este UPDATE.
    -- =================================================================
    UPDATE public.catalog_variant_import_row r
       SET normalized_data    = '{}'::JSONB,
           validation_status  = 'NEEDS_REVIEW',
           match_status       = 'NEW',
           matched_variant_id = NULL,
           error_detail       = NULL
     WHERE r.id = c_row_id
       AND r.job_id = c_job_id
       AND r.validation_status  = 'VALID'
       AND r.decision_status    = 'PENDING'
       AND r.persistence_status = 'PENDING'
       AND r.resulting_variant_id IS NULL;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_W2_UPDATE_CARDINALITY: UPDATE da row afetou % linha(s), esperado exatamente 1.', v_affected;
    END IF;

    -- =================================================================
    -- ESCRITA 3 — recalcular valid_rows do job.
    -- Fórmula IDÊNTICA à de internal.apply_variant_type_mapping, para
    -- que o contador continue consistente com o caminho canônico.
    -- total_rows NÃO é recalculado aqui: nenhuma linha foi criada ou
    -- removida, e reescrevê-lo seria ruído.
    -- =================================================================
    UPDATE public.catalog_variant_import_job j
       SET valid_rows = (SELECT COUNT(*)
                           FROM public.catalog_variant_import_row r
                          WHERE r.job_id = j.id
                            AND r.validation_status = 'VALID')
     WHERE j.id = c_job_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_W3_JOB_CARDINALITY: UPDATE do job afetou % linha(s), esperado exatamente 1.', v_affected;
    END IF;

    -- =================================================================
    -- POST G15 — o mapping não existe mais.
    -- =================================================================
    SELECT COUNT(*) INTO v_n FROM public.card_variant_type_external_mapping m
     WHERE m.id = c_mapping_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SV5_MBL_G15_MAPPING_STILL_EXISTS: mapping alvo ainda presente.';
    END IF;

    -- =================================================================
    -- POST G16 — mappings SCOPED sv05: 9 -> 8.
    -- =================================================================
    SELECT COUNT(*) INTO v_n FROM public.card_variant_type_external_mapping m
     WHERE m.external_set_id = c_scope;
    IF v_n <> c_post_scoped_sv05 THEN
        RAISE EXCEPTION 'SV5_MBL_G16_SCOPED_POST: esperados % mappings SCOPED sv05, encontrados %.', c_post_scoped_sv05, v_n;
    END IF;

    -- =================================================================
    -- POST G17 — nenhum mapping aponta mais para o VT.
    -- =================================================================
    SELECT COUNT(*) INTO v_n FROM public.card_variant_type_external_mapping m
     WHERE m.variant_type_id = c_variant_type_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'SV5_MBL_G17_VT_STILL_MAPPED: VT ainda referenciado por % mapping(s).', v_n;
    END IF;

    -- =================================================================
    -- POST G18 — o VT CONTINUA existindo e CONTINUA ativo.
    -- Esta migration NÃO desativa o VT (passo separado, RPC canônica).
    -- =================================================================
    SELECT COUNT(*) INTO v_n FROM public.card_variant_type vt
     WHERE vt.id = c_variant_type_id AND vt.code = c_vt_code AND vt.is_active = TRUE;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G18_VT_UNEXPECTED_CHANGE: o VT deveria continuar existindo e ativo após esta migration.';
    END IF;

    -- =================================================================
    -- POST G19 — a row está no estado-alvo EXATO.
    -- =================================================================
    SELECT COUNT(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.id = c_row_id
       AND r.validation_status  = 'NEEDS_REVIEW'
       AND r.match_status       = 'NEW'
       AND r.decision_status    = 'PENDING'
       AND r.persistence_status = 'PENDING'
       AND r.matched_variant_id   IS NULL
       AND r.resulting_variant_id IS NULL
       AND r.error_detail IS NULL
       AND r.normalized_data = '{}'::JSONB;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G19_ROW_TARGET_STATE: a row não atingiu o estado-alvo.';
    END IF;

    -- G19b — o raw_data NÃO foi tocado (é a evidência de origem).
    SELECT COUNT(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.id = c_row_id
       AND r.raw_data ->> 'type'  = 'normal'
       AND (r.raw_data -> 'stamp') = '["master-ball-league"]'::JSONB;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G19B_RAW_MUTATED: raw_data da row foi alterado — nunca deveria.';
    END IF;

    -- =================================================================
    -- POST G20 — contagens reais do job: VALID 417, NEEDS_REVIEW 11,
    -- TOTAL inalterado.
    -- =================================================================
    SELECT COUNT(*) FILTER (WHERE r.validation_status = 'VALID'),
           COUNT(*) FILTER (WHERE r.validation_status = 'NEEDS_REVIEW'),
           COUNT(*)
      INTO v_n, v_affected, v_job_total_post
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = c_job_id;
    IF v_n <> c_post_valid OR v_affected <> c_post_needs OR v_job_total_post <> c_pre_total THEN
        RAISE EXCEPTION 'SV5_MBL_G20_JOB_POST: esperado VALID=%/NEEDS_REVIEW=%/TOTAL=%, encontrado %/%/%.',
            c_post_valid, c_post_needs, c_pre_total, v_n, v_affected, v_job_total_post;
    END IF;

    -- =================================================================
    -- POST G21 — contador GRAVADO reconciliado com o real.
    -- =================================================================
    SELECT j.valid_rows, j.total_rows INTO v_n, v_affected
      FROM public.catalog_variant_import_job j WHERE j.id = c_job_id;
    IF v_n <> c_post_valid OR v_affected <> c_pre_total THEN
        RAISE EXCEPTION 'SV5_MBL_G21_JOB_COUNTERS: esperado valid_rows=% e total_rows=%, encontrado % e %.',
            c_post_valid, c_pre_total, v_n, v_affected;
    END IF;

    -- =================================================================
    -- POST G22 — decision/persistence do job INALTERADOS.
    -- Baseline auditado: 408 APPROVED/INSERTED + 20 PENDING/PENDING.
    -- =================================================================
    SELECT string_agg(t.k, ' | ' ORDER BY t.k) INTO v_txt
      FROM (SELECT r.decision_status || '/' || r.persistence_status || '=' || COUNT(*)::TEXT AS k
              FROM public.catalog_variant_import_row r
             WHERE r.job_id = c_job_id
             GROUP BY r.decision_status, r.persistence_status) t;
    IF v_txt IS DISTINCT FROM 'APPROVED/INSERTED=408 | PENDING/PENDING=20' THEN
        RAISE EXCEPTION 'SV5_MBL_G22_DECISION_DRIFT: distribuição decision/persistence mudou: %.', v_txt;
    END IF;

    -- =================================================================
    -- POST G23 — card_variant totalmente inalterado.
    -- =================================================================
    SELECT COUNT(*) INTO v_cv_count_post FROM public.card_variant;
    IF v_cv_count_post <> v_cv_count_pre THEN
        RAISE EXCEPTION 'SV5_MBL_G23_CARD_VARIANT_DRIFT: card_variant mudou de % para %.', v_cv_count_pre, v_cv_count_post;
    END IF;

    -- =================================================================
    -- POST G24 — NÃO-TOQUE provado por fingerprint:
    --   mapping GLOBAL · row irmã · EB Games · demais mappings · demais rows
    -- =================================================================
    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_global_post
      FROM (SELECT to_jsonb(m)::TEXT AS r FROM public.card_variant_type_external_mapping m
             WHERE m.id = c_global_mbl_id) t;
    IF v_fp_global_post IS DISTINCT FROM v_fp_global_pre THEN
        RAISE EXCEPTION 'SV5_MBL_G24A_GLOBAL_TOUCHED: mapping GLOBAL de Master Ball foi alterado.';
    END IF;

    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_sibling_post
      FROM (SELECT to_jsonb(r)::TEXT AS r FROM public.catalog_variant_import_row r
             WHERE r.id = c_sibling_row_id) t;
    IF v_fp_sibling_post IS DISTINCT FROM v_fp_sibling_pre THEN
        RAISE EXCEPTION 'SV5_MBL_G24B_SIBLING_TOUCHED: row Master Ball + Judge foi alterada.';
    END IF;

    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_ebgames_post
      FROM (
        SELECT to_jsonb(m)::TEXT AS r FROM public.card_variant_type_external_mapping m WHERE m.id = c_ebgames_id
        UNION ALL
        SELECT to_jsonb(vt)::TEXT FROM public.card_variant_type vt WHERE vt.id = c_ebgames_id
        UNION ALL
        SELECT to_jsonb(r2)::TEXT FROM public.catalog_variant_import_row r2 WHERE r2.id = c_ebgames_id
        UNION ALL
        SELECT to_jsonb(cv)::TEXT FROM public.card_variant cv WHERE cv.id = c_ebgames_id
      ) t;
    IF v_fp_ebgames_post IS DISTINCT FROM v_fp_ebgames_pre THEN
        RAISE EXCEPTION 'SV5_MBL_G24C_EBGAMES_TOUCHED: a entidade EB Games foi alterada.';
    END IF;

    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_othermap_post
      FROM (SELECT to_jsonb(m)::TEXT AS r FROM public.card_variant_type_external_mapping m
             WHERE m.id <> c_mapping_id) t;
    IF v_fp_othermap_post IS DISTINCT FROM v_fp_othermap_pre THEN
        RAISE EXCEPTION 'SV5_MBL_G24D_OTHER_MAPPINGS_TOUCHED: algum outro mapping foi alterado.';
    END IF;

    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_otherrows_post
      FROM (SELECT to_jsonb(r)::TEXT AS r FROM public.catalog_variant_import_row r
             WHERE r.id <> c_row_id) t;
    IF v_fp_otherrows_post IS DISTINCT FROM v_fp_otherrows_pre THEN
        RAISE EXCEPTION 'SV5_MBL_G24E_OTHER_ROWS_TOUCHED: alguma outra staging row foi alterada.';
    END IF;

    -- =================================================================
    -- POST G25 — action_log INTACTO. Esta migration não escreve
    -- auditoria (decisão aprovada: não ampliar o CHECK). Os dois eventos
    -- de CRIAÇÃO permanecem como registro histórico.
    -- =================================================================
    SELECT md5(COALESCE(string_agg(t.r, '|' ORDER BY t.r), '<none>')) INTO v_fp_actionlog_post
      FROM (SELECT to_jsonb(l)::TEXT AS r FROM public.catalog_admin_action_log l) t;
    IF v_fp_actionlog_post IS DISTINCT FROM v_fp_actionlog_pre THEN
        RAISE EXCEPTION 'SV5_MBL_G25_ACTION_LOG_TOUCHED: catalog_admin_action_log foi alterado — não deveria.';
    END IF;

    -- =================================================================
    -- POST G26 — a row volta a ser elegível ao caminho CANÔNICO.
    -- Prova positiva de que a correção reabre a porta: o guard
    -- ORIGIN_NOT_NEEDS_REVIEW de internal.apply_variant_type_mapping
    -- deixa de bloqueá-la.
    -- =================================================================
    SELECT COUNT(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.id = c_row_id AND r.validation_status = 'NEEDS_REVIEW';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'SV5_MBL_G26_NOT_RESOLVABLE: a row não ficou elegível ao fluxo canônico de resolução.';
    END IF;

    RAISE NOTICE 'SV5_MBL_CORRECTION_OK: mapping % removido; row % devolvida a NEEDS_REVIEW; job % com valid_rows=%.',
        c_mapping_id, c_row_id, c_job_id, c_post_valid;
END;
$mig$;
