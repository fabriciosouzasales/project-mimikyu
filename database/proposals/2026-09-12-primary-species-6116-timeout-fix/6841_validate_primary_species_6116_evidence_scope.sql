/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6841 - Validate resolve_card_primary_species_for_catalog_import_job()
               apos a correcao de escopo da CTE `evidence` (Query 6128)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12

Pré-requisito: Query 6128 APLICADA.

Executor: postgres, pelo Supabase SQL Editor.
A Secao 2 usa `SET LOCAL request.jwt.claims` para satisfazer
public.is_admin() — que e EXISTS(SELECT 1 FROM public.admin_user
WHERE id = auth.uid()). Tudo dentro de BEGIN/ROLLBACK.

ESTRUTURA:
  Secao 1 — estrutural / seguranca / diff semantico (read-only, 7 checagens)
  Secao 2 — funcional (BEGIN ... ROLLBACK, 10 casos)
  Secao 3 — zero residuo

PROVA CENTRAL (1.3): md5 do corpo da funcao.

    md5 = 7f2e7de82acf9a50df23a5861475b601   length = 4539

Esse e o md5 do corpo contido na Query 6128 em disco, e e tambem o md5 do
prosrc atualmente aplicado no LIVE. A igualdade byte-a-byte entre os dois foi
provada em RECOVERY-01 pelo operador `=` do Postgres, nao por inspecao visual.

Cadeia de proveniencia provada em RECOVERY-01:

    corpo(6128 em disco)                    = md5 7f2e7de8... / 4539 B
    corpo(6128) - DELTA_APROVADO            = md5 fddacfc4... / 4209 B
    corpo(database/schema/6116 canonico)    = md5 fddacfc4... / 4209 B   <- identico

    => 6128 = CANONICO_6116 + DELTA_APROVADO

DELTA_APROVADO = 4 linhas de comentario + `AND r.job_id = p_job_id`
(330 bytes; ocorrencia unica). Unico delta EXECUTAVEL: a clausula.
Ambos os arquivos em disco sao LF-only (verificado): nao ha delta de CRLF.

CORRECAO DE PREMISSA (RECOVERY-01). A versao anterior deste script esperava
md5 449d88bc... / 3335 B. Aquele valor foi derivado por `replace()` sobre o
prosrc LIVE *anterior* (md5 9d6cd767... / 3005 B), sob a premissa — FALSA —
de que o corpo LIVE e o corpo do arquivo canonico eram byte-identicos. Nao
eram: o corpo LIVE pre-6128 tinha ~1500 bytes a menos, essencialmente por
ausencia das linhas de comentario internas. A 6128 foi montada a partir do
ARQUIVO canonico, e portanto produz o corpo do arquivo + a clausula.

DIVIDA DE PROVENIENCIA, registrada e NAO resolvida aqui: o corpo LIVE
pre-6128 (9d6cd767... / 3005 B) nao esta mais disponivel em lugar algum.
NENHUMA equivalencia byte-level retroativa e alegada entre ele e o canonico.
A divergencia e anterior a esta rodada e contradiz o cabecalho da propria
6116 ("corpo SQL byte-identico ao executado"). Isso e divida de
proveniencia/documentacao — NAO esta classificado como defeito funcional, e
exige mandato proprio.

Se a 6128 tiver alterado QUALQUER byte alem do DELTA_APROVADO, 1.3 falha.

Cada Secao termina em erro (RAISE EXCEPTION) na primeira divergencia —
fail-loud, sem PASS artificial.
===============================================================================
*/

-- =============================================================================
-- SECAO 1 — ESTRUTURAL / SEGURANCA / DIFF SEMANTICO (read-only)
-- =============================================================================
DO $secao1$
DECLARE
    -- Corpo da 6128 em disco == prosrc LIVE (provado em RECOVERY-01).
    c_md5_esperado  CONSTANT TEXT := '7f2e7de82acf9a50df23a5861475b601';
    c_len_esperado  CONSTANT INT  := 4539;
    -- Sentinela historica: corpo LIVE ANTERIOR a 6128. Nao e o corpo canonico
    -- (ver cabecalho, "DIVIDA DE PROVENIENCIA"). Mantido apenas para produzir
    -- uma mensagem especifica caso este corpo reapareca.
    c_md5_pre_fix   CONSTANT TEXT := '9d6cd767dfcd627e76a38c21d820dbcf';

    v_p        pg_proc%ROWTYPE;
    v_n        INT;
    v_acl      TEXT;
    v_comment  TEXT;
    v_cols     TEXT;
BEGIN
    -- 1.1 Existe exatamente uma funcao com este nome.
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'resolve_card_primary_species_for_catalog_import_job';
    IF v_n <> 1 THEN
        RAISE EXCEPTION '6841_1.1_OVERLOAD: esperado exatamente 1 funcao, encontrado %.', v_n;
    END IF;

    SELECT p.* INTO v_p
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'resolve_card_primary_species_for_catalog_import_job';

    -- 1.2 Postura de execucao inalterada.
    IF NOT v_p.prosecdef THEN
        RAISE EXCEPTION '6841_1.2_SECDEF: SECURITY DEFINER foi perdido.';
    END IF;
    IF v_p.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN
        RAISE EXCEPTION '6841_1.2_SEARCH_PATH: proconfig = % (esperado search_path="").', v_p.proconfig;
    END IF;
    IF v_p.prolang <> (SELECT oid FROM pg_language WHERE lanname = 'plpgsql') THEN
        RAISE EXCEPTION '6841_1.2_LANGUAGE: LANGUAGE deixou de ser plpgsql.';
    END IF;
    IF v_p.provolatile <> 'v' THEN
        RAISE EXCEPTION '6841_1.2_VOLATILITY: provolatile = % (esperado v).', v_p.provolatile;
    END IF;
    IF v_p.pronargs <> 1 THEN
        RAISE EXCEPTION '6841_1.2_ARITY: pronargs = % (esperado 1).', v_p.pronargs;
    END IF;

    -- 1.3 DIFF SEMANTICO — o corpo e EXATAMENTE o anterior + a clausula.
    IF md5(v_p.prosrc) = c_md5_pre_fix THEN
        RAISE EXCEPTION '6841_1.3_NAO_APLICADA: corpo ainda e o pre-fix (md5 %). A 6128 nao foi aplicada.', c_md5_pre_fix;
    END IF;
    IF md5(v_p.prosrc) <> c_md5_esperado THEN
        RAISE EXCEPTION '6841_1.3_MD5: md5 = % / length = % (esperado % / %). A 6128 alterou algo alem da clausula autorizada.',
            md5(v_p.prosrc), length(v_p.prosrc), c_md5_esperado, c_len_esperado;
    END IF;
    IF length(v_p.prosrc) <> c_len_esperado THEN
        RAISE EXCEPTION '6841_1.3_LENGTH: length = % (esperado %).', length(v_p.prosrc), c_len_esperado;
    END IF;

    -- 1.4 ACL — identica ao estado anterior: postgres + authenticated, nada mais.
    v_acl := COALESCE(array_to_string(v_p.proacl, ' | '), '(default)');
    IF v_acl NOT LIKE '%authenticated=X/postgres%' THEN
        RAISE EXCEPTION '6841_1.4_ACL_AUTH: authenticated perdeu EXECUTE. ACL = %.', v_acl;
    END IF;
    IF v_acl LIKE '%anon=%' THEN
        RAISE EXCEPTION '6841_1.4_ACL_ANON: anon ganhou privilegio. ACL = %.', v_acl;
    END IF;
    IF v_acl LIKE '%=X/postgres%' AND v_acl LIKE '% =%' THEN
        RAISE EXCEPTION '6841_1.4_ACL_PUBLIC: PUBLIC ganhou EXECUTE. ACL = %.', v_acl;
    END IF;
    IF v_acl LIKE '%service_role=%' THEN
        RAISE EXCEPTION '6841_1.4_ACL_SERVICE: service_role ganhou EXECUTE nesta funcao. ACL = %.', v_acl;
    END IF;

    -- 1.5 COMMENT preservado por CREATE OR REPLACE.
    SELECT obj_description(v_p.oid, 'pg_proc') INTO v_comment;
    IF v_comment IS NULL OR v_comment NOT LIKE '%SOURCE_NOT_TCGDEX%' THEN
        RAISE EXCEPTION '6841_1.5_COMMENT: comentario perdido ou alterado.';
    END IF;

    -- 1.6 Contrato de retorno inalterado — 9 colunas OUT, nomes e ordem exatos.
    SELECT string_agg(a, ',' ORDER BY i)
      INTO v_cols
      FROM unnest(v_p.proargnames) WITH ORDINALITY AS t(a, i)
     WHERE i > v_p.pronargs;
    IF v_cols IS DISTINCT FROM 'status,considered_count,resolved_count,unchanged_count,unresolved_count,ambiguous_count,conflict_count,failed_count,details' THEN
        RAISE EXCEPTION '6841_1.6_RETURNS: colunas de saida = % (contrato alterado).', v_cols;
    END IF;

    -- 1.7 Invariantes de corpo.
    IF (length(v_p.prosrc) - length(replace(v_p.prosrc, 'AND r.job_id = p_job_id', ''))) / length('AND r.job_id = p_job_id') <> 1 THEN
        RAISE EXCEPTION '6841_1.7_CLAUSULA: `AND r.job_id = p_job_id` deve aparecer exatamente 1 vez.';
    END IF;
    IF v_p.prosrc NOT LIKE '%public.is_admin()%' THEN
        RAISE EXCEPTION '6841_1.7_IS_ADMIN: guard is_admin() ausente.';
    END IF;
    IF v_p.prosrc NOT LIKE '%SOURCE_NOT_TCGDEX%' OR v_p.prosrc NOT LIKE '%NO_ELIGIBLE_CARDS%' THEN
        RAISE EXCEPTION '6841_1.7_STATUS: estados SOURCE_NOT_TCGDEX / NO_ELIGIBLE_CARDS ausentes.';
    END IF;
    IF v_p.prosrc NOT LIKE '%c_max_batch_size CONSTANT INTEGER := 10000%' THEN
        RAISE EXCEPTION '6841_1.7_GUARD: bulk guard de 10000 alterado ou ausente.';
    END IF;
    IF v_p.prosrc NOT LIKE '%resolve_card_primary_species_bulk(v_payload)%' THEN
        RAISE EXCEPTION '6841_1.7_DELEGACAO: delegacao a 6115 ausente.';
    END IF;
    IF v_p.prosrc ~* '(insert|update|delete)\s+(into\s+)?\S*card_primary_species' THEN
        RAISE EXCEPTION '6841_1.7_DML: escrita direta em card_primary_species detectada — invariante da Fatia C violado.';
    END IF;
    IF v_p.prosrc LIKE '%matched_card_id%' THEN
        RAISE EXCEPTION '6841_1.7_MATCHED: matched_card_id nao pode ser lido por esta funcao.';
    END IF;

    RAISE NOTICE 'SECAO 1 OK — 7 checagens. md5=% length=%', md5(v_p.prosrc), length(v_p.prosrc);
END
$secao1$;


-- =============================================================================
-- SECAO 2 — FUNCIONAL (BEGIN ... ROLLBACK)
-- =============================================================================
BEGIN;

DO $secao2$
DECLARE
    c_smp  CONSTANT UUID := '3904745c-480b-4884-ba1a-c04ac0c1e8fc';
    c_sm10 CONSTANT UUID := '1150a2eb-2e46-43e5-8e13-e592105778bc';
    c_bw10 CONSTANT UUID := 'fb3b25e3-14be-4260-9d89-020412234c2a';

    v_admin       UUID;
    v_cps_antes   INT;
    v_cps_depois  INT;
    v_r           RECORD;
    v_job_pdf     UUID;
    v_job_vazio   UUID;
    v_card_set    UUID;
    v_divergentes INT;
    v_sqlstate    TEXT;
    v_msg         TEXT;
BEGIN
    SELECT count(*) INTO v_cps_antes FROM public.card_primary_species;

    -- F00 — precondicao: tornar-se admin. Se a tecnica nao funcionar, aborta
    -- aqui em vez de produzir falsos FORBIDDEN nos casos seguintes.
    SELECT id INTO v_admin FROM public.admin_user LIMIT 1;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION '6841_F00_SEM_ADMIN: nenhuma linha em public.admin_user — impossivel exercer a funcao.';
    END IF;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION '6841_F00_IS_ADMIN: set_config nao satisfez is_admin() — revisar tecnica antes de confiar nos demais casos.';
    END IF;

    -- F01/F02/F03 — EQUIVALENCIA FUNCIONAL em jobs conhecidos.
    -- Os tres ja foram reconciliados (BACKFILL-01/02/03). Reexecutar deve ser
    -- integralmente inerte: nenhuma escrita, contadores exatos, e o
    -- `considered_count` deve bater com o payload que o backfill usou.
    FOR v_r IN
        SELECT * FROM (VALUES
            (c_smp,  'SMP',  236, 220, 16),
            (c_sm10, 'SM10', 195, 173, 22),
            (c_bw10, 'BW10',  85,  85,  0)
        ) AS t(job_id, code, considered, unchanged, ambiguous)
    LOOP
        DECLARE v_out RECORD;
        BEGIN
            SELECT * INTO v_out
              FROM public.resolve_card_primary_species_for_catalog_import_job(v_r.job_id);

            IF v_out.status <> 'PROCESSED' THEN
                RAISE EXCEPTION '6841_F01_STATUS(%): status = % (esperado PROCESSED).', v_r.code, v_out.status;
            END IF;
            IF v_out.considered_count <> v_r.considered THEN
                RAISE EXCEPTION '6841_F01_CONSIDERED(%): considered = % (esperado %).', v_r.code, v_out.considered_count, v_r.considered;
            END IF;
            IF v_out.unchanged_count <> v_r.unchanged THEN
                RAISE EXCEPTION '6841_F01_UNCHANGED(%): unchanged = % (esperado %).', v_r.code, v_out.unchanged_count, v_r.unchanged;
            END IF;
            IF v_out.ambiguous_count <> v_r.ambiguous THEN
                RAISE EXCEPTION '6841_F01_AMBIGUOUS(%): ambiguous = % (esperado %).', v_r.code, v_out.ambiguous_count, v_r.ambiguous;
            END IF;
            IF v_out.resolved_count <> 0 OR v_out.conflict_count <> 0
               OR v_out.failed_count <> 0 OR v_out.unresolved_count <> 0 THEN
                RAISE EXCEPTION '6841_F01_INERTE(%): resolved=% conflict=% failed=% unresolved=% (todos deveriam ser 0).',
                    v_r.code, v_out.resolved_count, v_out.conflict_count, v_out.failed_count, v_out.unresolved_count;
            END IF;
            RAISE NOTICE 'F01 OK — %: considered=% unchanged=% ambiguous=%',
                v_r.code, v_out.considered_count, v_out.unchanged_count, v_out.ambiguous_count;
        END;
    END LOOP;

    -- F04 — ISOLAMENTO CROSS-JOB. Para todo job, a evidencia agregada pela
    -- forma CORRIGIDA (escopada por job_id) deve ser identica a uma referencia
    -- independente escopada ao mesmo job. Exercido sobre os jobs dos tres Sets
    -- e sobre Cards que comprovadamente aparecem em mais de um job.
    WITH alvo AS (
        SELECT unnest(ARRAY[c_smp, c_sm10, c_bw10]) AS job_id
    ),
    corrigida AS (
        SELECT r.job_id, r.resulting_card_id AS card_id,
               array_agg(DISTINCT (e)::int ORDER BY (e)::int) AS dex
        FROM public.catalog_import_row r
        CROSS JOIN LATERAL jsonb_array_elements_text(r.raw_data->'dexId') AS e
        WHERE r.raw_data ? 'dexId'
          AND r.job_id IN (SELECT job_id FROM alvo)
        GROUP BY r.job_id, r.resulting_card_id
    ),
    sem_escopo AS (
        SELECT a.job_id, r.resulting_card_id AS card_id,
               array_agg(DISTINCT (e)::int ORDER BY (e)::int) AS dex
        FROM alvo a
        JOIN public.catalog_import_row r ON TRUE
        CROSS JOIN LATERAL jsonb_array_elements_text(r.raw_data->'dexId') AS e
        WHERE r.raw_data ? 'dexId'
          AND r.resulting_card_id IN (
              SELECT DISTINCT r2.resulting_card_id
              FROM public.catalog_import_row r2
              WHERE r2.job_id = a.job_id AND r2.resulting_card_id IS NOT NULL
          )
        GROUP BY a.job_id, r.resulting_card_id
    )
    SELECT count(*) INTO v_divergentes
      FROM corrigida c
      FULL JOIN sem_escopo s ON s.job_id = c.job_id AND s.card_id = c.card_id
     WHERE c.dex IS DISTINCT FROM s.dex;

    IF v_divergentes <> 0 THEN
        RAISE EXCEPTION '6841_F04_CROSS_JOB: % Card(s) cuja evidencia difere entre a forma escopada e a nao escopada. A correcao MUDA resultado — reavaliar antes de aplicar.', v_divergentes;
    END IF;
    RAISE NOTICE 'F04 OK — evidencia escopada == nao escopada (0 divergencias): a correcao e semanticamente neutra HOJE.';

    -- F05 — SOURCE_NOT_TCGDEX. Nao existe job PDF no LIVE; fixture minima.
    -- Contrato real auditado em VALIDATION-FIX-01 (pg_constraint + pg_indexes +
    -- pg_trigger, NAO apenas information_schema.is_nullable):
    --   NOT NULL sem default ...... card_set_id, source
    --   ck_..._source_identifier ... source='PDF' EXIGE file_checksum NOT NULL
    --                                E external_set_id NULL (o inverso vale
    --                                para TCGDEX) — causa do FAIL em
    --                                VALIDATION-01
    --   fk_..._card_set ............ card_set_id deve existir
    --   uq_..._fingerprint_active .. UNIQUE parcial sobre
    --                                (source, card_set_id, file_checksum,
    --                                external_set_id) para status ativos;
    --                                status default 'RECEIVED' cai nesse
    --                                escopo -> checksum aleatorio garante
    --                                ausencia de colisao
    --   trg_..._normalize .......... apenas UPPER/BTRIM; inocuo aqui
    SELECT id INTO v_card_set FROM public.card_set ORDER BY created_at LIMIT 1;
    INSERT INTO public.catalog_import_job (card_set_id, source, file_checksum)
         VALUES (v_card_set, 'PDF', '6841-fixture-' || gen_random_uuid()::text)
      RETURNING id INTO v_job_pdf;

    SELECT * INTO v_r FROM public.resolve_card_primary_species_for_catalog_import_job(v_job_pdf);
    IF v_r.status <> 'SOURCE_NOT_TCGDEX' THEN
        RAISE EXCEPTION '6841_F05_PDF: status = % (esperado SOURCE_NOT_TCGDEX).', v_r.status;
    END IF;
    IF v_r.considered_count <> 0 OR v_r.details <> '[]'::jsonb THEN
        RAISE EXCEPTION '6841_F05_PDF_PAYLOAD: job PDF nao pode considerar Cards nem produzir details.';
    END IF;
    RAISE NOTICE 'F05 OK — job PDF devolve SOURCE_NOT_TCGDEX sem tocar em raw_data.';

    -- F06 — NO_ELIGIBLE_CARDS: job TCGDEX sem nenhuma Card POKEMON confirmada.
    SELECT j.id INTO v_job_vazio
      FROM public.catalog_import_job j
     WHERE j.source = 'TCGDEX'
       AND NOT EXISTS (
           SELECT 1 FROM public.catalog_import_row r
             JOIN public.card c ON c.id = r.resulting_card_id
             JOIN public.card_category cc ON cc.id = c.category_id
            WHERE r.job_id = j.id AND cc.code = 'POKEMON')
     LIMIT 1;

    IF v_job_vazio IS NULL THEN
        RAISE EXCEPTION '6841_F06_SEM_FIXTURE: nenhum job TCGDEX sem Cards POKEMON elegiveis — caso nao exercido.';
    END IF;
    SELECT * INTO v_r FROM public.resolve_card_primary_species_for_catalog_import_job(v_job_vazio);
    IF v_r.status <> 'NO_ELIGIBLE_CARDS' THEN
        RAISE EXCEPTION '6841_F06: status = % (esperado NO_ELIGIBLE_CARDS).', v_r.status;
    END IF;
    RAISE NOTICE 'F06 OK — NO_ELIGIBLE_CARDS preservado.';

    -- F07 — job inexistente.
    BEGIN
        PERFORM * FROM public.resolve_card_primary_species_for_catalog_import_job(gen_random_uuid());
        RAISE EXCEPTION '6841_F07: job inexistente deveria levantar excecao.';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg NOT LIKE '%_NOT_FOUND%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'F07 OK — job inexistente levanta _NOT_FOUND.';

    -- F08 — p_job_id NULL.
    BEGIN
        PERFORM * FROM public.resolve_card_primary_species_for_catalog_import_job(NULL);
        RAISE EXCEPTION '6841_F08: p_job_id NULL deveria levantar excecao.';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg NOT LIKE '%_MISSING_JOB%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'F08 OK — p_job_id NULL levanta _MISSING_JOB.';

    -- F09 — nao-admin e recusado.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid())::text, true);
    IF public.is_admin() THEN
        RAISE EXCEPTION '6841_F09_PRE: is_admin() ainda verdadeiro com uid aleatorio.';
    END IF;
    BEGIN
        PERFORM * FROM public.resolve_card_primary_species_for_catalog_import_job(c_sm10);
        RAISE EXCEPTION '6841_F09: nao-admin deveria ser recusado.';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg NOT LIKE '%_FORBIDDEN%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'F09 OK — nao-admin levanta _FORBIDDEN.';

    -- F10 — ZERO ESCRITA em card_primary_species durante toda a Secao 2.
    SELECT count(*) INTO v_cps_depois FROM public.card_primary_species;
    IF v_cps_depois <> v_cps_antes THEN
        RAISE EXCEPTION '6841_F10_ESCRITA: card_primary_species foi de % para % — a funcao escreveu.',
            v_cps_antes, v_cps_depois;
    END IF;

    RAISE NOTICE 'SECAO 2 OK — 10 casos. card_primary_species inalterada (% linhas).', v_cps_depois;
END
$secao2$;

ROLLBACK;


-- =============================================================================
-- SECAO 3 — ZERO RESIDUO (apos o ROLLBACK). Esperado: 0 | 0 | 0
-- =============================================================================
SELECT
    (SELECT count(*) FROM public.catalog_import_job WHERE source = 'PDF')            AS jobs_pdf_residuais,
    (SELECT count(*) FROM public.card_primary_species) - 16657                        AS delta_card_primary_species,
    (SELECT count(*) FROM public.catalog_import_job
      WHERE created_at >= NOW() - INTERVAL '10 minutes')                              AS jobs_criados_agora;
