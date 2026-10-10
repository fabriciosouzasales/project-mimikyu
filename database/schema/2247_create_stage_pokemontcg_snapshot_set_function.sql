-- CANÔNICO (promovido em 2026-10-10 de proposals/2026-10-09-variant-coverage-gap/F3-01_stage_function_ready.sql).
-- CONFIRMADO EXECUTADO por Fabrício no SQL Editor em 2026-10-10. Corpo de
-- internal.stage_pokemontcg_snapshot_set conferido contra o LIVE em 2026-10-10: md5 do prosrc (sem CR) idêntico.
-- Usada pelo piloto XY1 (F5) e pela campanha F6 (49 jobs COMPLETED, 10.812 variantes).
/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: F3-01 - Carregador do snapshot Pokémon TCG API para o staging de variantes
Versão......: 1.0
Status......: PRONTA — cria a função; não grava staging (a função só escreve quando
              chamada com p_apply = true, pelos scripts F3/stage_<set>.sql)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-10
Mandato.....: ADR-034 v0.3; CATALOG-VARIANT-COVERAGE-GAP-01, fatia F3.

internal.stage_pokemontcg_snapshot_set(p_snapshot_text TEXT, p_apply BOOLEAN) RETURNS JSONB

  p_snapshot_text = conteúdo EXATO de database/seeds/sources/pokemontcg-snapshot-2026-10-09/sets/<id>.json

  1. Integridade: o SHA-256 do texto recebido (sem CR) tem de ser igual ao snapshot_sha256 gravado na
     card_set_external_reference da coleção (F2-01), e o número de cartas igual a total_count.
  2. Correspondência: cartas da coleção SEM nenhuma variante × cartas do snapshot, pelo número
     normalizado (maiúsculas; zeros à esquerda removidos em cada sequência de dígitos). Só pares
     1 para 1 entram; número repetido em qualquer lado é ambíguo e fica de fora.
  3. Uma linha de staging por chave de preço da carta casada, já resolvida pelos 3 eixos
     (resolve_variant_row_axes + lookup_variant_type_for_row da fonte POKEMON_TCG_API).
     Carta casada sem chave de preço não gera linha (ADR-034: sem variante padrão).
  4. p_apply = false: só calcula e devolve o plano. p_apply = true: cria o job (STAGED) e as
     linhas (VALID / NEW / PENDING / PENDING). Os guards da F2-01 valem nas duas pontas.
  Recusa: job ativo na coleção, plano vazio (nada a fazer), rota que não resolve.
  Devolve: contagens, combinações de chaves por raridade nossa (checagem cruzada F4) e job_id.
  Auditoria: como no import do TCGdex, o staging não grava action log (o confirm grava
  CARD_VARIANT_IMPORT_CONFIRMED); a origem fica no job (source) e em cada raw_data (ptcg_card_id, snapshot).
===============================================================================
*/

CREATE FUNCTION internal.stage_pokemontcg_snapshot_set(p_snapshot_text TEXT, p_apply BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
    v_doc      JSONB;
    v_ext      TEXT;
    v_game     UUID;
    v_src      UUID;
    v_set      UUID;
    v_set_code TEXT;
    v_meta     JSONB;
    v_sha      TEXT;
    v_admin    UUID;
    v_job      UUID;
    v_n        INTEGER;
    v_summary  JSONB;
    v_rows     INTEGER;
BEGIN
    IF p_snapshot_text IS NULL OR p_apply IS NULL THEN
        RAISE EXCEPTION 'F3_ARGS: p_snapshot_text e p_apply são obrigatórios.';
    END IF;

    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code = 'POKEMON_TCG_API';
    IF v_game IS NULL OR v_src IS NULL THEN RAISE EXCEPTION 'F3_CONTEXT'; END IF;

    v_doc := p_snapshot_text::JSONB;
    v_ext := v_doc ->> 'set_id';

    SELECT r.card_set_id, r.metadata, cs.code INTO v_set, v_meta, v_set_code
      FROM public.card_set_external_reference r
      JOIN public.card_set cs ON cs.id = r.card_set_id
     WHERE r.asset_source_id = v_src AND r.external_set_id = v_ext AND r.is_active;
    IF v_set IS NULL THEN
        RAISE EXCEPTION 'F3_SET_NOT_REFERENCED: coleção % sem card_set_external_reference ativa da fonte.', v_ext;
    END IF;

    -- 1. Integridade do snapshot
    -- CR removido: o arquivo do repositório é LF; um editor Windows pode ter convertido para CRLF.
    v_sha := encode(extensions.digest(convert_to(replace(p_snapshot_text, E'\r', ''), 'UTF8'), 'sha256'), 'hex');
    IF v_sha IS DISTINCT FROM v_meta ->> 'snapshot_sha256' THEN
        RAISE EXCEPTION 'F3_SNAPSHOT_HASH: texto recebido (%) difere do snapshot registrado (%).', v_sha, v_meta ->> 'snapshot_sha256';
    END IF;
    IF jsonb_array_length(v_doc -> 'cards') <> (v_meta ->> 'total_count')::INTEGER
       OR (v_doc ->> 'total_count')::INTEGER <> (v_meta ->> 'total_count')::INTEGER THEN
        RAISE EXCEPTION 'F3_SNAPSHOT_COUNT: contagem do arquivo difere de total_count (%).', v_meta ->> 'total_count';
    END IF;

    IF EXISTS (SELECT 1 FROM public.catalog_variant_import_job j
                WHERE j.card_set_id = v_set
                  AND j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')) THEN
        RAISE EXCEPTION 'F3_ACTIVE_JOB: % já tem job de variantes ativo.', v_set_code;
    END IF;

    -- 2 + 3. Plano
    DROP TABLE IF EXISTS pg_temp.f3_plan;
    DROP TABLE IF EXISTS pg_temp.f3_rows;
    CREATE TEMP TABLE f3_plan ON COMMIT DROP AS
    WITH src AS (
        SELECT c ->> 'id' AS ptcg_id, c ->> 'number' AS ptcg_number, c ->> 'rarity' AS ptcg_rarity,
               c -> 'tcgplayer_price_keys' AS keys,
               regexp_replace(upper(c ->> 'number'), '(?<![0-9])0+(?=[0-9])', '', 'g') AS n
          FROM jsonb_array_elements(v_doc -> 'cards') c
    ),
    ours AS (
        SELECT cd.id AS card_id, cd.collector_number, r.code AS rarity_code,
               regexp_replace(upper(cd.collector_number), '(?<![0-9])0+(?=[0-9])', '', 'g') AS n
          FROM public.card cd
          LEFT JOIN public.rarity r ON r.id = cd.rarity_id
         WHERE cd.card_set_id = v_set
           AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = cd.id)
    ),
    src_u  AS (SELECT n FROM src  GROUP BY n HAVING count(*) = 1),
    ours_u AS (SELECT n FROM ours GROUP BY n HAVING count(*) = 1)
    SELECT o.card_id, o.collector_number, o.rarity_code, o.n,
           s.ptcg_id, s.ptcg_number, s.ptcg_rarity, s.keys,
           CASE WHEN s.ptcg_id IS NULL THEN
                     CASE WHEN EXISTS (SELECT 1 FROM src s2 WHERE s2.n = o.n) OR o.n NOT IN (SELECT n FROM ours_u)
                          THEN 'AMBIGUOUS' ELSE 'ORPHAN' END
                WHEN jsonb_array_length(s.keys) = 0 THEN 'NO_KEYS'
                ELSE 'MATCHED' END AS outcome
      FROM ours o
      LEFT JOIN src s ON s.n = o.n AND o.n IN (SELECT n FROM ours_u) AND s.n IN (SELECT n FROM src_u);

    CREATE TEMP TABLE f3_rows ON COMMIT DROP AS
    SELECT p.card_id, k.key,
           jsonb_build_object('type', k.key, 'foil', NULL, 'subtype', NULL, 'stamp', '[]'::JSONB,
                              'size', 'standard', 'ptcg_card_id', p.ptcg_id,
                              'ptcg_number', p.ptcg_number, 'ptcg_rarity', p.ptcg_rarity,
                              'snapshot', 'pokemontcg-snapshot-2026-10-09') AS raw_data,
           a.printing_state, a.edition_context_state, a.printing_profile_id, a.edition_context_profile_id,
           internal.lookup_variant_type_for_row(v_game, v_src, v_set, a.residual_type, a.residual_foil,
                                                a.residual_subtype, COALESCE(a.residual_stamp, '{}'::TEXT[])) AS variant_type_id
      FROM f3_plan p
     CROSS JOIN LATERAL jsonb_array_elements_text(p.keys) k(key)
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(
                jsonb_build_object('type', k.key, 'foil', NULL, 'subtype', NULL, 'stamp', '[]'::JSONB, 'size', 'standard'),
                v_game, v_src, v_ext) a
     WHERE p.outcome = 'MATCHED';

    IF EXISTS (SELECT 1 FROM f3_rows
                WHERE variant_type_id IS NULL
                   OR printing_state <> 'RESOLVED_NO_PRINTING'
                   OR edition_context_state <> 'RESOLVED_NO_EDITION_CONTEXT') THEN
        RAISE EXCEPTION 'F3_ROUTE_UNRESOLVED: % linha(s) sem rota completa; nada foi escrito.',
            (SELECT count(*) FROM f3_rows WHERE variant_type_id IS NULL
                OR printing_state <> 'RESOLVED_NO_PRINTING' OR edition_context_state <> 'RESOLVED_NO_EDITION_CONTEXT');
    END IF;

    SELECT count(*) INTO v_rows FROM f3_rows;

    SELECT jsonb_build_object(
             'set_code', v_set_code, 'external_set_id', v_ext, 'snapshot_sha256', v_sha,
             'cards_without_variant', (SELECT count(*) FROM f3_plan),
             'matched', (SELECT count(*) FROM f3_plan WHERE outcome = 'MATCHED'),
             'matched_no_keys', (SELECT count(*) FROM f3_plan WHERE outcome = 'NO_KEYS'),
             'ambiguous', (SELECT count(*) FROM f3_plan WHERE outcome = 'AMBIGUOUS'),
             'orphan', (SELECT count(*) FROM f3_plan WHERE outcome = 'ORPHAN'),
             'rows_planned', v_rows,
             'rows_by_type', (SELECT jsonb_object_agg(code, n) FROM (
                                SELECT t.code, count(*) AS n FROM f3_rows r
                                  JOIN public.card_variant_type t ON t.id = r.variant_type_id GROUP BY t.code) z),
             'crosscheck_rarity_keys', (SELECT jsonb_object_agg(k, n) FROM (
                                SELECT coalesce(rarity_code, 'NONE') || ' | ' ||
                                       coalesce((SELECT string_agg(x, '+' ORDER BY x) FROM jsonb_array_elements_text(keys) x), '-') AS k,
                                       count(*) AS n
                                  FROM f3_plan WHERE outcome IN ('MATCHED', 'NO_KEYS') GROUP BY 1) z),
             'not_staged', (SELECT jsonb_agg(collector_number || ':' || outcome ORDER BY collector_number)
                              FROM f3_plan WHERE outcome <> 'MATCHED'))
      INTO v_summary;

    IF v_rows = 0 THEN
        RETURN v_summary || jsonb_build_object('mode', CASE WHEN p_apply THEN 'APPLY' ELSE 'DRY_RUN' END,
                                               'note', 'plano vazio — nenhum job criado');
    END IF;

    IF NOT p_apply THEN
        RETURN v_summary || jsonb_build_object('mode', 'DRY_RUN');
    END IF;

    SELECT id INTO v_admin FROM public.admin_user;
    IF (SELECT count(*) FROM public.admin_user) <> 1 THEN RAISE EXCEPTION 'F3_ADMIN_AMBIGUOUS'; END IF;

    INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status, initiated_by)
    VALUES (v_set, 'POKEMON_TCG_API', v_ext, 'STAGED', v_admin)
    RETURNING id INTO v_job;

    INSERT INTO public.catalog_variant_import_row
           (job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status)
    SELECT v_job, r.card_id, r.raw_data,
           jsonb_build_object('variant_type_id', r.variant_type_id::TEXT,
                              'printing_profile_id', NULL, 'edition_context_profile_id', NULL),
           'VALID', 'NEW', 'PENDING', 'PENDING'
      FROM f3_rows r;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> v_rows THEN RAISE EXCEPTION 'F3_INSERT_GAP: % de %', v_n, v_rows; END IF;

    UPDATE public.catalog_variant_import_job
       SET total_rows = v_n, valid_rows = v_n
     WHERE id = v_job;

    RETURN v_summary || jsonb_build_object('mode', 'APPLY', 'job_id', v_job);
END;
$fn$;

REVOKE ALL ON FUNCTION internal.stage_pokemontcg_snapshot_set(TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION internal.stage_pokemontcg_snapshot_set(TEXT, BOOLEAN) IS
'ADR-034 / F3: carrega um arquivo do snapshot pokemontcg-snapshot-2026-10-09 no staging de variantes. Execução manual (SQL Editor), sem rede.';
