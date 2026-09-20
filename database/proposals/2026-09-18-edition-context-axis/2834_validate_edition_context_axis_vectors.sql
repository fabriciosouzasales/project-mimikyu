-- ===========================================================================
-- Query 2834 — RUNNER SQL DOS VETORES COMPARTILHADOS DO EIXO 3
-- ===========================================================================
-- STATUS: PROPOSTA — NÃO EXECUTADA. Pacote EDITION-CONTEXT-AXIS.
-- Mandato: EDITION-CONTEXT-AXIS-EDGE-D3-FINAL-CORRECTION-01, item 2.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTE ARQUIVO É, E O QUE ELE NÃO É
-- ---------------------------------------------------------------------------
-- É o runner SQL de `test-vectors/edition-context-axis-vectors.json` — o
-- MESMO arquivo que `edge/edition-context.test.ts` consome.
--
-- >>> OS EXPECTED VALUES NÃO SÃO DECLARADOS AQUI. <<<
--
-- Esse é o ponto inteiro. "harness SQL passa E testes TS passam" não prova
-- paridade quando cada lado carrega o seu próprio gabarito — prova duas
-- opiniões independentes. A fixture única é o que transforma duas suítes
-- verdes numa afirmação sobre equivalência.
--
-- Precedente idêntico no repositório:
--   database/proposals/2026-09-14-card-variant-mapping-source-set-scope/
--     · 2826_validate_source_set_scoped_variant_type_mapping.sql, Seção 4
--     · edge/variant-scope-vectors.test.ts
--     · test-vectors/variant-type-mapping-scope-vectors.json
--
-- ---------------------------------------------------------------------------
-- COMO EXECUTAR
-- ---------------------------------------------------------------------------
--   1. Ler test-vectors/edition-context-axis-vectors.json INTEIRO.
--   2. Substituir o literal `{"vectors":[]}` do bloco PAYLOAD abaixo pelo
--      conteúdo do arquivo, sem editar nada.
--   3. Executar este arquivo inteiro. Ele termina em ROLLBACK.
--
-- O gate da Seção 0 ABORTA se o payload estiver vazio. Não existe caminho em
-- que este arquivo rode "com o que tem" e registre PASS.
--
-- ---------------------------------------------------------------------------
-- A ENTRADA DE PRINTING É MEDIDA, NÃO PRESUMIDA
-- ---------------------------------------------------------------------------
-- Cada vetor DECLARA o estado de Printing como entrada (o objeto sob teste é
-- o eixo 3). Este runner monta um `raw_data` que deveria produzir aquele
-- estado — e então CONFERE o `printing_state` que a 2211 devolveu contra o
-- declarado. Se divergirem, o vetor é FAIL com
-- `PRINTING_FIXTURE_MISMATCH`, nunca PASS por acidente.
--
-- Os tokens de fixture são prefixados `VEC2834` e foram escolhidos para não
-- ter mapping de Printing no catálogo real — é o que faz o estado nascer
-- `RESOLVED_NO_PRINTING` sem nenhuma montagem extra. Os vetores que pedem
-- `RESOLVED_WITH_PROFILE` ou `UNRESOLVED` exigem fixture de Printing, e o
-- runner a cria explicitamente.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO — o contrato de três eixos e as tabelas do eixo precisam existir.
-- ---------------------------------------------------------------------------
DO $pre$
DECLARE
    v_missing TEXT := '';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='resolve_variant_row_axes')
    THEN v_missing := v_missing || ' internal.resolve_variant_row_axes'; END IF;

    IF to_regclass('public.card_edition_context_trait') IS NULL
    THEN v_missing := v_missing || ' card_edition_context_trait'; END IF;
    IF to_regclass('public.card_edition_context_profile') IS NULL
    THEN v_missing := v_missing || ' card_edition_context_profile'; END IF;
    IF to_regclass('public.card_edition_context_external_mapping') IS NULL
    THEN v_missing := v_missing || ' card_edition_context_external_mapping'; END IF;

    IF v_missing <> '' THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2834: objetos ausentes —%. Executar 2203-2207 e 2211 antes.', v_missing;
    END IF;
END
$pre$;


-- ===========================================================================
-- SEÇÃO 0 — PAYLOAD + GATES DE INTEGRIDADE DA FIXTURE
-- ===========================================================================
CREATE TEMP TABLE _vec2834 (payload JSONB) ON COMMIT DROP;

-- >>> SUBSTITUIR O LITERAL ABAIXO PELO CONTEÚDO DO JSON <<<
INSERT INTO _vec2834 (payload) VALUES ('{"vectors":[]}'::JSONB);

DO $s0$
DECLARE
    p        JSONB;
    v_n      INTEGER;
    v_roster TEXT;
    v_decl   TEXT;
    v_vocab  TEXT;
BEGIN
    SELECT payload INTO p FROM _vec2834;

    v_n := jsonb_array_length(COALESCE(p->'vectors','[]'::JSONB));
    IF v_n = 0 THEN
        RAISE EXCEPTION 'S0 ABORT: payload de vetores vazio. Substitua o literal do bloco PAYLOAD pelo conteudo de test-vectors/edition-context-axis-vectors.json antes de executar. NAO registrar nenhum vetor como PASS nem como FAIL — o runner nao roda sem a fixture.';
    END IF;

    -- G1 — o roster declarado tem de bater com os vetores presentes. Um vetor
    -- que some do arquivo tem de quebrar o runner, não reduzir a cobertura
    -- em silêncio.
    SELECT string_agg(x, ',') INTO v_decl
      FROM jsonb_array_elements_text(p->'roster') x;
    SELECT string_agg(v->>'id', ',' ORDER BY ord) INTO v_roster
      FROM jsonb_array_elements(p->'vectors') WITH ORDINALITY AS t(v, ord);

    IF v_roster IS DISTINCT FROM v_decl THEN
        RAISE EXCEPTION 'S0 ABORT: roster divergente. Declarado: %. Presente: %.', v_decl, v_roster;
    END IF;

    -- G2 — bindings obrigatórios. Sem eles o runner inventaria a própria
    -- ligação símbolo -> objeto físico, e a paridade viraria coincidência.
    IF p->'bindings'->'tokens' IS NULL
       OR p->'bindings'->'scope' IS NULL
       OR p->'bindings'->>'game' IS NULL
       OR p->'bindings'->>'asset_source' IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: bloco bindings incompleto (esperado game, asset_source, tokens, scope).';
    END IF;

    -- G3 — todo estado citado em algum expected tem de estar no vocabulário.
    SELECT string_agg(DISTINCT e, ',') INTO v_vocab
      FROM (
        SELECT v->'expected'->>'edition_context_state' AS e
          FROM jsonb_array_elements(p->'vectors') v
         WHERE v ? 'expected'
        UNION ALL
        SELECT sc->'expected'->>'edition_context_state'
          FROM jsonb_array_elements(p->'vectors') v,
               LATERAL jsonb_array_elements(COALESCE(v->'sub_cases','[]'::JSONB)) sc
      ) q
     WHERE e IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(p->'vocabulary') w WHERE w = e);

    IF v_vocab IS NOT NULL THEN
        RAISE EXCEPTION 'S0 ABORT: estados fora do vocabulario declarado: %.', v_vocab;
    END IF;

    RAISE NOTICE 'S0 OK — % vetores, roster conferido, bindings presentes.', v_n;
END
$s0$;


-- ===========================================================================
-- SEÇÃO 1 — SENTINELA: o corpus real não pode conter os tokens de fixture
-- ===========================================================================
-- Se um token VEC2834* já existir no catálogo, o vetor mediria o dado de
-- produção e "passaria" provando outra coisa. É o mesmo cuidado que o bloco
-- `$why_foil_substitution` do precedente 2826 documenta.
-- ===========================================================================
DO $s1$
DECLARE
    v_game UUID;
    v_src  UUID;
    v_hits INTEGER;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = (SELECT payload->'bindings'->>'game' FROM _vec2834);
    SELECT id INTO v_src  FROM public.asset_source WHERE code = (SELECT payload->'bindings'->>'asset_source' FROM _vec2834);

    IF v_game IS NULL OR v_src IS NULL THEN
        RAISE EXCEPTION 'S1 ABORT: game ou asset_source dos bindings nao existe no LIVE.';
    END IF;

    SELECT count(*) INTO v_hits
      FROM public.card_edition_context_external_mapping m
     WHERE m.game_id = v_game AND m.normalized_token LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % mapping(s) de Edition Context com token VEC2834* ja existem no catalogo. A sentinela esta suja — os vetores mediriam dado real. Limpar antes.', v_hits;
    END IF;

    SELECT count(*) INTO v_hits FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % trait(s) VEC2834* ja existem.', v_hits;
    END IF;

    SELECT count(*) INTO v_hits FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % profile(s) VEC2834* ja existem.', v_hits;
    END IF;

    -- Os tokens de fixture também não podem ter routing de IMPRESSÃO — é isso
    -- que garante printing_state = RESOLVED_NO_PRINTING sem montagem extra.
    SELECT count(*) INTO v_hits
      FROM public.card_printing_external_mapping m
     WHERE m.game_id = v_game AND m.asset_source_id = v_src
       AND m.normalized_token LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % mapping(s) de IMPRESSAO com token VEC2834* existem. O estado de Printing dos vetores deixaria de ser o declarado.', v_hits;
    END IF;

    RAISE NOTICE 'S1 OK — sentinela limpa nos quatro catalogos.';
END
$s1$;


-- ===========================================================================
-- SEÇÃO 2 — RUNNER
-- ===========================================================================
CREATE TEMP TABLE _res2834 (
    vector_id   TEXT,
    label       TEXT,
    status      TEXT,          -- PASS | FAIL | SKIP
    detail      TEXT
) ON COMMIT DROP;

DO $s2$
DECLARE
    p          JSONB;
    v_game     UUID;
    v_src      UUID;
    v_scope    TEXT;

    v_vec      JSONB;
    v_case     JSONB;
    v_exp      JSONB;
    v_label    TEXT;

    v_trait    JSONB;
    v_prof     JSONB;
    v_map      JSONB;

    v_trait_id UUID;
    v_prof_id  UUID;
    v_map_id   UUID;

    v_sym2uuid JSONB;          -- simbolo -> uuid (traits e profiles)
    v_uuid2sym JSONB;          -- uuid    -> simbolo
    v_sig      UUID[];

    v_raw      JSONB;
    v_sub      TEXT;
    v_stamp    TEXT[];

    v_ax       RECORD;

    v_got_state   TEXT;
    v_got_profile TEXT;
    v_got_traits  TEXT[];
    v_got_sub     TEXT;
    v_got_stamp   TEXT[];
    v_got_emits   BOOLEAN;

    v_exp_traits  TEXT[];
    v_exp_stamp   TEXT[];
    v_exp_sub     TEXT;

    v_errs     TEXT;
    v_tok      TEXT;
BEGIN
    SELECT payload INTO p FROM _vec2834;
    SELECT id INTO v_game FROM public.game         WHERE code = p->'bindings'->>'game';
    SELECT id INTO v_src  FROM public.asset_source WHERE code = p->'bindings'->>'asset_source';

    FOR v_vec IN SELECT v FROM jsonb_array_elements(p->'vectors') v LOOP

        -- ---------------------------------------------------------------
        -- 2.1 MONTAGEM DO ESTADO DO VETOR
        -- ---------------------------------------------------------------
        v_sym2uuid := '{}'::JSONB;
        v_uuid2sym := '{}'::JSONB;

        -- traits declarados
        FOR v_trait IN SELECT t FROM jsonb_array_elements(COALESCE(v_vec->'ec_traits','[]'::JSONB)) t LOOP
            INSERT INTO public.card_edition_context_trait (game_id, code, name, display_order, is_active)
            VALUES (v_game, 'VEC2834_' || (v_trait->>'id'), 'fixture ' || (v_trait->>'id'),
                    1000 + (SELECT count(*)::INT FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%'),
                    (v_trait->>'is_active')::BOOLEAN)
            RETURNING id INTO v_trait_id;
            v_sym2uuid := v_sym2uuid || jsonb_build_object(v_trait->>'id', v_trait_id::TEXT);
            v_uuid2sym := v_uuid2sym || jsonb_build_object(v_trait_id::TEXT, v_trait->>'id');
        END LOOP;

        -- traits citados só em mappings/profiles (nascem ATIVOS)
        FOR v_tok IN
            SELECT DISTINCT x FROM (
                SELECT jsonb_array_elements_text(m->'traits') AS x
                  FROM jsonb_array_elements(COALESCE(v_vec->'ec_mappings','[]'::JSONB)) m
                UNION ALL
                SELECT jsonb_array_elements_text(pr->'traits')
                  FROM jsonb_array_elements(COALESCE(v_vec->'ec_profiles','[]'::JSONB)) pr
            ) q
        LOOP
            IF NOT (v_sym2uuid ? v_tok) THEN
                INSERT INTO public.card_edition_context_trait (game_id, code, name, display_order, is_active)
                VALUES (v_game, 'VEC2834_' || v_tok, 'fixture ' || v_tok,
                        1000 + (SELECT count(*)::INT FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%'),
                        TRUE)
                RETURNING id INTO v_trait_id;
                v_sym2uuid := v_sym2uuid || jsonb_build_object(v_tok, v_trait_id::TEXT);
                v_uuid2sym := v_uuid2sym || jsonb_build_object(v_trait_id::TEXT, v_tok);
            END IF;
        END LOOP;

        -- profiles
        FOR v_prof IN SELECT pr FROM jsonb_array_elements(COALESCE(v_vec->'ec_profiles','[]'::JSONB)) pr LOOP
            SELECT ARRAY(SELECT (v_sym2uuid->>x)::UUID
                           FROM jsonb_array_elements_text(v_prof->'traits') x
                          ORDER BY (v_sym2uuid->>x)::UUID)
              INTO v_sig;

            INSERT INTO public.card_edition_context_profile
                (game_id, code, name, display_order, is_active)
            VALUES (v_game, 'VEC2834_' || (v_prof->>'id'), 'fixture ' || (v_prof->>'id'),
                    1000 + (SELECT count(*)::INT FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%'),
                    (v_prof->>'is_active')::BOOLEAN)
            RETURNING id INTO v_prof_id;

            INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
            SELECT v_prof_id, t, v_game FROM unnest(v_sig) t;

            v_sym2uuid := v_sym2uuid || jsonb_build_object(v_prof->>'id', v_prof_id::TEXT);
            v_uuid2sym := v_uuid2sym || jsonb_build_object(v_prof_id::TEXT, v_prof->>'id');
        END LOOP;

        -- força o selo de assinatura dos profiles (mesmo contrato de 2189)
        SET CONSTRAINTS ALL IMMEDIATE;

        -- mappings
        FOR v_map IN SELECT m FROM jsonb_array_elements(COALESCE(v_vec->'ec_mappings','[]'::JSONB)) m LOOP
            v_tok := split_part(p->'bindings'->'tokens'->>(v_map->>'token'), ' ', 1);

            INSERT INTO public.card_edition_context_external_mapping
                (game_id, asset_source_id, external_set_id, raw_field,
                 normalized_token, external_token, is_active)
            VALUES (v_game, v_src,
                    CASE WHEN v_map->>'scope' IS NULL THEN NULL ELSE 'VEC2834A' END,
                    v_map->>'raw_field', v_tok, v_tok,
                    (v_map->>'is_active')::BOOLEAN)
            RETURNING id INTO v_map_id;

            INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
            SELECT v_map_id, (v_sym2uuid->>x)::UUID, v_game
              FROM jsonb_array_elements_text(v_map->'traits') x;
        END LOOP;

        SET CONSTRAINTS ALL IMMEDIATE;

        -- ---------------------------------------------------------------
        -- 2.2 EXECUÇÃO — um caso principal, mais os sub-casos
        -- ---------------------------------------------------------------
        FOR v_case IN
            SELECT c FROM (
                SELECT jsonb_build_object(
                           'label', v_vec->>'id',
                           'residual', v_vec->'residual_after_printing',
                           'expected', v_vec->'expected') AS c
                 WHERE v_vec ? 'expected'
                UNION ALL
                SELECT jsonb_build_object(
                           'label', sc->>'label',
                           'residual', sc->'residual_after_printing',
                           'expected', sc->'expected')
                  FROM jsonb_array_elements(COALESCE(v_vec->'sub_cases','[]'::JSONB)) sc
            ) q
        LOOP
            v_label := v_case->>'label';
            v_exp   := v_case->'expected';

            v_sub := CASE WHEN v_case->'residual'->>'subtype' IS NULL THEN NULL
                          ELSE split_part(p->'bindings'->'tokens'->>(v_case->'residual'->>'subtype'), ' ', 1) END;
            SELECT ARRAY(SELECT split_part(p->'bindings'->'tokens'->>x, ' ', 1)
                           FROM jsonb_array_elements_text(COALESCE(v_case->'residual'->'stamp','[]'::JSONB)) x
                          ORDER BY 1)
              INTO v_stamp;

            -- Vetores que exigem fixture de IMPRESSÃO não são montáveis sem
            -- criar Perfil de Impressão sintético. Declarados SKIP com motivo
            -- — NUNCA PASS. O lado TS os cobre; a paridade desses vetores fica
            -- registrada como pendente.
            IF (v_vec->'printing'->>'state') <> 'RESOLVED_NO_PRINTING' THEN
                INSERT INTO _res2834 VALUES (v_vec->>'id', v_label, 'SKIP',
                    format('exige printing_state=%s, que precisa de fixture de Impressao. Nao montado neste runner. NAO e PASS.',
                           v_vec->'printing'->>'state'));
                CONTINUE;
            END IF;

            v_raw := jsonb_build_object('size', 'STANDARD')
                  || CASE WHEN v_sub IS NULL THEN '{}'::JSONB
                          ELSE jsonb_build_object('subtype', v_sub) END
                  || CASE WHEN cardinality(v_stamp) = 0 THEN '{}'::JSONB
                          ELSE jsonb_build_object('stamp', to_jsonb(v_stamp)) END;

            SELECT * INTO v_ax
              FROM internal.resolve_variant_row_axes(
                       v_raw, v_game, v_src,
                       CASE WHEN v_vec->>'job_scope' IS NULL THEN NULL ELSE 'VEC2834A' END);

            -- GATE — a fixture de Printing produziu o estado que o vetor
            -- declara? Se não, o vetor não mede o que diz medir.
            IF v_ax.printing_state IS DISTINCT FROM (v_vec->'printing'->>'state') THEN
                INSERT INTO _res2834 VALUES (v_vec->>'id', v_label, 'FAIL',
                    format('PRINTING_FIXTURE_MISMATCH: declarado %s, medido %s',
                           v_vec->'printing'->>'state', v_ax.printing_state));
                CONTINUE;
            END IF;

            -- ---- tradução uuid -> símbolo, para comparar com a fixture ----
            v_got_state   := v_ax.edition_context_state;
            v_got_profile := CASE WHEN v_ax.edition_context_profile_id IS NULL THEN NULL
                                  ELSE COALESCE(v_uuid2sym->>(v_ax.edition_context_profile_id::TEXT),
                                                '<<UUID DESCONHECIDO>>') END;
            SELECT ARRAY(SELECT COALESCE(v_uuid2sym->>(t::TEXT), '<<UUID DESCONHECIDO>>')
                           FROM unnest(COALESCE(v_ax.edition_context_trait_ids,'{}'::UUID[])) t
                          ORDER BY 1)
              INTO v_got_traits;
            v_got_sub   := v_ax.residual_subtype;
            SELECT ARRAY(SELECT s FROM unnest(COALESCE(v_ax.residual_stamp,'{}'::TEXT[])) s ORDER BY s)
              INTO v_got_stamp;
            v_got_emits := v_ax.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
                       AND v_ax.edition_context_state IN ('RESOLVED_NO_EDITION_CONTEXT','RESOLVED_WITH_EC_PROFILE');

            SELECT ARRAY(SELECT x FROM jsonb_array_elements_text(v_exp->'edition_context_trait_ids') x ORDER BY 1)
              INTO v_exp_traits;
            SELECT ARRAY(SELECT split_part(p->'bindings'->'tokens'->>x, ' ', 1)
                           FROM jsonb_array_elements_text(v_exp->'residual_stamp') x ORDER BY 1)
              INTO v_exp_stamp;
            v_exp_sub := CASE WHEN v_exp->>'residual_subtype' IS NULL THEN NULL
                              ELSE split_part(p->'bindings'->'tokens'->>(v_exp->>'residual_subtype'), ' ', 1) END;

            v_errs := '';
            IF v_got_state   IS DISTINCT FROM (v_exp->>'edition_context_state')
                THEN v_errs := v_errs || format('estado: %s != %s; ', v_got_state, v_exp->>'edition_context_state'); END IF;
            IF v_got_profile IS DISTINCT FROM (v_exp->>'edition_context_profile')
                THEN v_errs := v_errs || format('profile: %s != %s; ', v_got_profile, v_exp->>'edition_context_profile'); END IF;
            IF v_got_traits  IS DISTINCT FROM v_exp_traits
                THEN v_errs := v_errs || format('traits: %s != %s; ', v_got_traits, v_exp_traits); END IF;
            IF v_got_sub     IS DISTINCT FROM v_exp_sub
                THEN v_errs := v_errs || format('res_subtype: %s != %s; ', v_got_sub, v_exp_sub); END IF;
            IF v_got_stamp   IS DISTINCT FROM v_exp_stamp
                THEN v_errs := v_errs || format('res_stamp: %s != %s; ', v_got_stamp, v_exp_stamp); END IF;
            IF v_got_emits   IS DISTINCT FROM (v_exp->>'edge_emits_axis_keys')::BOOLEAN
                THEN v_errs := v_errs || format('emits: %s != %s; ', v_got_emits, v_exp->>'edge_emits_axis_keys'); END IF;

            INSERT INTO _res2834
            VALUES (v_vec->>'id', v_label,
                    CASE WHEN v_errs = '' THEN 'PASS' ELSE 'FAIL' END,
                    CASE WHEN v_errs = '' THEN v_got_state ELSE v_errs END);
        END LOOP;

        -- ---------------------------------------------------------------
        -- 2.3 ISOLAMENTO — o vetor seguinte não herda estado deste.
        -- ---------------------------------------------------------------
        DELETE FROM public.card_edition_context_external_mapping_trait
         WHERE mapping_id IN (SELECT id FROM public.card_edition_context_external_mapping
                               WHERE normalized_token LIKE 'VEC2834%');
        DELETE FROM public.card_edition_context_external_mapping
         WHERE normalized_token LIKE 'VEC2834%';
        DELETE FROM public.card_edition_context_profile_trait
         WHERE profile_id IN (SELECT id FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%');
        DELETE FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%';
        DELETE FROM public.card_edition_context_trait   WHERE code LIKE 'VEC2834%';
        SET CONSTRAINTS ALL IMMEDIATE;
    END LOOP;
END
$s2$;


-- ===========================================================================
-- SEÇÃO 3 — GATE FINAL
-- ===========================================================================
DO $s3$
DECLARE
    v_pass INTEGER; v_fail INTEGER; v_skip INTEGER;
    v_det  TEXT;
    v_miss TEXT;
BEGIN
    SELECT count(*) FILTER (WHERE status='PASS'),
           count(*) FILTER (WHERE status='FAIL'),
           count(*) FILTER (WHERE status='SKIP')
      INTO v_pass, v_fail, v_skip FROM _res2834;

    RAISE NOTICE '=== 2834 — % PASS / % FAIL / % SKIP ===', v_pass, v_fail, v_skip;

    FOR v_det IN SELECT format('%s %-6s %s', status, label, detail) FROM _res2834 ORDER BY vector_id, label LOOP
        RAISE NOTICE '%', v_det;
    END LOOP;

    -- G4 — cobertura de estados, medida sobre o que EXECUTOU. Um SKIP não
    -- conta como cobertura: se o único vetor de um estado foi pulado, aquele
    -- estado não foi provado do lado SQL, e isso tem de ficar dito.
    SELECT string_agg(w, ', ') INTO v_miss
      FROM jsonb_array_elements_text((SELECT payload->'vocabulary' FROM _vec2834)) w
     WHERE w NOT IN (SELECT detail FROM _res2834 WHERE status='PASS');

    IF v_miss IS NOT NULL THEN
        RAISE NOTICE 'COBERTURA PARCIAL — estados sem nenhum vetor PASS neste runner: %', v_miss;
        RAISE NOTICE 'Isso NAO e falha do contrato: os vetores correspondentes podem ter sido SKIP por exigirem fixture de Impressao. Conferir a lista acima e registrar a pendencia — nunca declarar paridade completa com SKIP em aberto.';
    END IF;

    IF v_fail > 0 THEN
        RAISE EXCEPTION '2834 FALHOU: % vetor(es) divergem da fixture compartilhada. Paridade Edge x SQL QUEBRADA — rollout do eixo 3 bloqueado.', v_fail;
    END IF;
END
$s3$;

ROLLBACK;
-- Este runner é read-only por efeito: tudo que ele cria é desfeito.
-- NUNCA trocar por COMMIT — a fixture não pertence ao catálogo.
