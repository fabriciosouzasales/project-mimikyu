/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: F2-01 - Fundação da 2ª fonte de variantes (Pokémon TCG API, snapshot)
Versão......: 1.0
Status......: PRONTA — v_apply = false (dry-run, desfaz tudo) / true (aplica)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: ADR-034 v0.2 (aprovado); decisão de Fabrício em 2026-10-09: CEL25CC fica
              sem variante; a F2 segue com as coleções que casam por número.

Escreve
  S1 CHECK de catalog_variant_import_job.source passa a aceitar 'POKEMON_TCG_API'
  S2 49 card_set_external_reference (asset_source POKEMON_TCG_API), com o hash do
     arquivo do snapshot em metadata
  S3 3 rotas de Finish GLOBAIS do asset_source: NORMAL -> STANDARD,
     HOLOFOIL -> HOLO, REVERSEHOLOFOIL -> REVERSE_HOLO
  S4 guards de servidor (deny by default), só para jobs POKEMON_TCG_API:
       internal.guard_cvir_second_source()  -> trigger trg_cvir_second_source
         INSERT: carta do Card Set do job; carta SEM nenhuma variante; só VALID;
                 raw_data.type em {normal, holofoil, reverseHolofoil}
         UPDATE: card_id/job_id imutáveis; nunca deixa de ser VALID;
                 ao virar INSERTED (confirm), a carta não pode ter variante que
                 não tenha saído deste mesmo job (corrida com o TCGdex)
       internal.guard_cvij_source_immutable() -> trigger trg_cvij_source_immutable
         source do job não muda depois de criado
  S5 cancela o job TCGDEX vazio da SM12 (0 linhas, STAGED desde 2026-09-18), que
     ocupa o índice de job ativo da coleção

Não muda
  admin_confirm_catalog_variant_import, decide, revalidação (2239/2245): a revalidação
  só toca linhas NEEDS_REVIEW, e o guard impede que uma linha da 2ª fonte seja outra
  coisa além de VALID — por construção ela nunca entra na revalidação do TCGdex.

Provas (rodam nos dois modos, dentro de bloco desfeito): T1–T10 + rotas.
===============================================================================
*/

DO $f2$
DECLARE
    v_apply CONSTANT BOOLEAN := false;   -- << trocar para true para aplicar
    v_game UUID; v_tcg UUID; v_ptcg UUID; v_std UUID; v_holo UUID; v_rev UUID;
    v_n INTEGER; v_cv0 BIGINT; v_cv1 BIGINT; v_gap BIGINT;
    v_xy1 UUID; v_xy2 UUID; v_ca UUID; v_cb UUID; v_cc UUID; v_cd UUID; v_cx UUID;
    v_job UUID; v_job_t UUID; v_ra UUID; v_rb UUID; v_rc UUID;
    v_v1 UUID; v_v2 UUID; v_v3 UUID; v_vf UUID;
    v_fail TEXT := '';
    v_sm12_job CONSTANT UUID := 'bf615e89-b8bc-49dd-8fb9-0e9d9ee567f9';
    v_t TEXT; v_code TEXT; v_exp TEXT;
BEGIN
    -- ===================== G0 — contexto e baseline =====================
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_tcg  FROM public.asset_source WHERE code = 'TCGDEX';
    SELECT id INTO v_ptcg FROM public.asset_source WHERE code = 'POKEMON_TCG_API';
    SELECT id INTO v_std  FROM public.card_variant_type WHERE code = 'STANDARD'     AND is_active;
    SELECT id INTO v_holo FROM public.card_variant_type WHERE code = 'HOLO'         AND is_active;
    SELECT id INTO v_rev  FROM public.card_variant_type WHERE code = 'REVERSE_HOLO' AND is_active;
    IF v_game IS NULL OR v_tcg IS NULL OR v_ptcg IS NULL OR v_std IS NULL OR v_holo IS NULL OR v_rev IS NULL THEN
        RAISE EXCEPTION 'F2_G0_CONTEXT';
    END IF;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;
    IF v_cv0 <> 26491 THEN RAISE EXCEPTION 'F2_G0_BASELINE_CARD_VARIANT: %', v_cv0; END IF;
    SELECT count(*) INTO v_gap FROM public.card c
     WHERE NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id);
    IF v_gap <> 6727 THEN RAISE EXCEPTION 'F2_G0_BASELINE_GAP: %', v_gap; END IF;

    -- ===================== G1 — nada pré-existente =====================
    IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
         WHERE conrelid = 'public.catalog_variant_import_job'::regclass
           AND conname = 'ck_catalog_variant_import_job_source') IS DISTINCT FROM 'CHECK ((source = ''TCGDEX''::text))' THEN
        RAISE EXCEPTION 'F2_G1_CHECK_UNEXPECTED';
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_set_external_reference WHERE asset_source_id = v_ptcg)
       OR EXISTS (SELECT 1 FROM public.card_variant_type_external_mapping WHERE asset_source_id = v_ptcg)
       OR EXISTS (SELECT 1 FROM public.catalog_variant_import_job WHERE source <> 'TCGDEX')
       OR to_regprocedure('internal.guard_cvir_second_source()') IS NOT NULL
       OR to_regprocedure('internal.guard_cvij_source_immutable()') IS NOT NULL THEN
        RAISE EXCEPTION 'F2_G1_ALREADY_EXISTS';
    END IF;

    -- ===================== S1 — CHECK de source =====================
    ALTER TABLE public.catalog_variant_import_job DROP CONSTRAINT ck_catalog_variant_import_job_source;
    ALTER TABLE public.catalog_variant_import_job ADD CONSTRAINT ck_catalog_variant_import_job_source
        CHECK (source IN ('TCGDEX', 'POKEMON_TCG_API'));

    -- ===================== S2 — 49 referências de coleção =====================
    CREATE TEMP TABLE f2_sets (code TEXT PRIMARY KEY, ext TEXT NOT NULL UNIQUE, total INTEGER NOT NULL, sha TEXT NOT NULL) ON COMMIT DROP;
    INSERT INTO f2_sets (code, ext, total, sha) VALUES
        ('BW1', 'bw1', 115, 'aa6d5205833d29f14ba76c6cb005efa27cf1df1189e9e74b17d9bf9a8ae09144'),
        ('BW2', 'bw2', 98, 'a81c963d8edda9e6b9b098db9e446104053b3de63beafbb5fe603ce9a7396fff'),
        ('BW3', 'bw3', 102, '077a28eec3a87a3a2bb31787f5e58dd37a1f82167ffdf203e62b07157e688d4c'),
        ('BW4', 'bw4', 103, '178740988d1bb7eee35e135c0028b33b330bcbb39396b4f34d6442c5aaf38049'),
        ('BW5', 'bw5', 111, 'fadabe8824ca2837df88b59146adc3c870f0711c763ece73cba96f46e31963fb'),
        ('BW6', 'bw6', 128, 'eb3065127594696542044781b31cabf7cfd930f319f0c4229c43f3a533f225bd'),
        ('BW7', 'bw7', 153, '9f3629fdb00980ad069183a6c278f5167f135c234da29cd771ca661f69ae6481'),
        ('BW8', 'bw8', 138, 'c074f12792beef92fb4ec96e26a17dc39c8e6d6df0bc02bc91b6628b892a837c'),
        ('BW9', 'bw9', 122, '51874e6371cefe3fd23fb5493250821eb222b8140b2fb2ef26b87e212fba2575'),
        ('BW10', 'bw10', 105, '033e9d64ffe42d11f19fbdc0cd402283fe0197fa1d01a5e8827a78b2c0a73751'),
        ('BW11', 'bw11', 140, 'fc165d44579a126191f82648cdd9219a43caf9a5376ca3ebc59f025c1eb37737'),
        ('BWP', 'bwp', 101, 'ad0696072327412060ceaa7f509a95b60b028131e1496be787ee71d33b138f92'),
        ('DC1', 'dc1', 34, '68059f90b8a1728955ebdfca3cb4136f3536fcaa503b626af83b65904db5e53f'),
        ('DET1', 'det1', 18, 'f7927b13d5500f57cc93759c6f4c3b025dbd372ba63b6cf183ea52ca091db82f'),
        ('DV1', 'dv1', 21, '8c0b5d7fce388c88ff42ca24f23679ee2168920967b1ba8ba2e3de0afa1d06c5'),
        ('G1', 'g1', 117, '62d604e21fc8dd7bb803c32590b86b5a87e1633bba12196c0aebd10c7212e20f'),
        ('SM1', 'sm1', 173, '1274a345e484000477aa37b35ec7edeb58eb0a7f6dfa58de34face8bf6f04af2'),
        ('SM2', 'sm2', 180, 'e498b0270569882601257bd664daaa7507db9ebf6eab0a3dc630da7a3638fe74'),
        ('SM3.5', 'sm35', 81, '46ba4378a680e3a713b2fe3dcae80186ed2d24da3d3672f6ce2d136f06de6412'),
        ('SM4', 'sm4', 126, 'd489851baf915a30fb3bb45e58a68392b3f013e8bc19433fb283f7f565b4a6af'),
        ('SM5', 'sm5', 178, 'a81acf04fefaf67fb0755c38e57d09a82cf58cda5001967f154e3ddd68c5bd99'),
        ('SM6', 'sm6', 150, '9dde9f1ae4100a7f110dc4a1b16eb6b121491b3a7696f95d9b04eebc5e732989'),
        ('SM7', 'sm7', 187, '18c3e2f0c6cb2ebd4b29c6f1b9ccdcb0fde557cb64be367ec724ae38de25daf0'),
        ('SM7.5', 'sm75', 80, 'b2432d40b8de2faaae70110909cdcbe177b44757446f94a8762f226cf4bf1841'),
        ('SM8', 'sm8', 240, '217d8dd00765158ab5caedfc0845965c7f29460546286c45452182e63c8a0e81'),
        ('SM9', 'sm9', 198, '2e3f33f2a1efbe78232dc14ef813041ff2b655463924db257b48fcaf2bfa513f'),
        ('SM10', 'sm10', 238, '883e61ad1ed06b1a8b2644ae7c77101976c4df1fd7f6dbcafa2f20ec5e282e94'),
        ('SM11', 'sm11', 261, 'e504041a2a4022e1a684055684427884da73c56b0c802f5b1a77cd38ff454fbd'),
        ('SM12', 'sm12', 272, '33b6f8dec0a364587c21ca084ccfed1c80b0dcf020d906e45d73bb42c275a163'),
        ('SM115', 'sm115', 69, 'fa77752f6cd1c3f183e601fde5e7a02d543dbdd12e493bcdf906c78a5b69219c'),
        ('SMA', 'sma', 94, '4cbb02de3a0ea4bc91235076479df2f79e84e7911966116cd9eee0568ce93805'),
        ('SVP', 'svp', 200, '78570ff18f4c732dd194ec983383ebbafc4836d856b29d65b289e6a4d641e6e1'),
        ('SWSH1', 'swsh1', 216, 'ed123a2e2803d84ffd25a0f0f687d363acaaf56b9cb0bb5833b969300facf250'),
        ('SWSH3.5', 'swsh35', 80, 'dc11fa695ca36fe8b13731f5b5391cfa43b906089e353427ccabdb22f721830f'),
        ('SWSHP', 'swshp', 304, 'af4ba8bc230bd648923d20ed2a7269abc43104370fc42b0eeeeb5f6b0a7f8da0'),
        ('XY0', 'xy0', 39, 'df178115ae3972d5d34180257533b7a3b03e43b9a53610ac8f31d3dca54e61b2'),
        ('XY1', 'xy1', 146, 'ca0fded5c65c848d6c4e85f58125df527b1b6e496a2592e4c7791d6f8c09ca17'),
        ('XY2', 'xy2', 110, '8e860e566a7dcbfb6dcf6b1114372fb8e65d31f6958d13fe18c127bd904baa3d'),
        ('XY3', 'xy3', 114, '2bc5f6e21d79a8ee75c2550c1e1b47205111d90d6d91088bdab033f27d3cbbbe'),
        ('XY4', 'xy4', 124, 'aba86aeaa580691007d810006ed0700a67fea24f1ead8f58720d85d85f242fe9'),
        ('XY5', 'xy5', 164, '35cf870d5aaffa5b894e417f13b717a2b0efd712a46c276a71253245d1834291'),
        ('XY6', 'xy6', 112, '08b169e34c3ea526a6bb0b1f011d39be3540f26f0ea9f8a5e80ec99bfa810f1d'),
        ('XY7', 'xy7', 101, '7b6fa1356410569002196678cdc3e35858318d463ae008196241eb6107fb9d42'),
        ('XY8', 'xy8', 165, '9762a299c2a24b41789fe15644cfcbab9117a344c072cdc5edfd74205486ac55'),
        ('XY9', 'xy9', 126, 'e8c5872a7557d75d6108373793019beba66b3e70bafe71a8c8ee164dbeaedf9c'),
        ('XY10', 'xy10', 129, 'c187830d032e41dd389191c84146bc19c90e8e72fd151755f77e94601b237fad'),
        ('XY11', 'xy11', 116, '414dc6b4ca53410a079b83f267a95da97f73c0c106d4a56f6d68fed5d923d138'),
        ('XY12', 'xy12', 113, '346a1659d3dab420ccc7b94923e9d16dcddb880c66a8fa5a91f29b44b1d9d465'),
        ('XYP', 'xyp', 216, '4331f0666ddd7417f70078899003ca9af3bee0cb0f0ba6a21385b9415f3202c0');
    SELECT count(*) INTO v_n FROM f2_sets s JOIN public.card_set cs ON cs.code = s.code;
    IF v_n <> 49 THEN RAISE EXCEPTION 'F2_S2_SETS_NOT_FOUND: % de 49', v_n; END IF;
    IF EXISTS (SELECT 1 FROM f2_sets s WHERE s.code = 'CEL25CC') THEN RAISE EXCEPTION 'F2_S2_CEL25CC'; END IF;

    INSERT INTO public.card_set_external_reference (card_set_id, asset_source_id, external_set_id, source_url, metadata)
    SELECT cs.id, v_ptcg, s.ext, 'https://api.pokemontcg.io/v2/sets/' || s.ext,
           jsonb_build_object('snapshot', 'pokemontcg-snapshot-2026-10-09',
                              'snapshot_file', 'sets/' || s.ext || '.json',
                              'snapshot_sha256', s.sha,
                              'total_count', s.total,
                              'adr', 'ADR-034')
      FROM f2_sets s JOIN public.card_set cs ON cs.code = s.code;
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 49 THEN RAISE EXCEPTION 'F2_S2_INSERT: %', v_n; END IF;

    -- ===================== S3 — 3 rotas de Finish =====================
    INSERT INTO public.card_variant_type_external_mapping
           (game_id, asset_source_id, external_set_id, external_type, normalized_type, variant_type_id)
    VALUES (v_game, v_ptcg, NULL, 'normal',          public.normalize_external_catalog_value('normal'),          v_std),
           (v_game, v_ptcg, NULL, 'holofoil',        public.normalize_external_catalog_value('holofoil'),        v_holo),
           (v_game, v_ptcg, NULL, 'reverseHolofoil', public.normalize_external_catalog_value('reverseHolofoil'), v_rev);
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 3 THEN RAISE EXCEPTION 'F2_S3: %', v_n; END IF;

    -- ===================== S4 — guards =====================
    CREATE FUNCTION internal.guard_cvir_second_source()
    RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $g$
    DECLARE
        v_source TEXT;
        v_set    UUID;
    BEGIN
        SELECT j.source, j.card_set_id INTO v_source, v_set
          FROM public.catalog_variant_import_job j WHERE j.id = NEW.job_id;
        IF v_source IS DISTINCT FROM 'POKEMON_TCG_API' THEN
            RETURN NEW;   -- TCGdex e demais: comportamento inalterado
        END IF;

        IF NEW.validation_status IS DISTINCT FROM 'VALID' THEN
            RAISE EXCEPTION 'CVIR_SECOND_SOURCE_VALID_ONLY: linha da 2a fonte (job %) so pode existir como VALID; recebido %.', NEW.job_id, NEW.validation_status;
        END IF;

        IF TG_OP = 'INSERT' THEN
            IF NOT EXISTS (SELECT 1 FROM public.card c WHERE c.id = NEW.card_id AND c.card_set_id = v_set) THEN
                RAISE EXCEPTION 'CVIR_SECOND_SOURCE_CARD_NOT_IN_SET: carta % nao pertence ao Card Set do job %.', NEW.card_id, NEW.job_id;
            END IF;
            IF EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = NEW.card_id) THEN
                RAISE EXCEPTION 'CVIR_SECOND_SOURCE_CARD_HAS_VARIANT: carta % ja tem Card Variant; a 2a fonte so atua em carta sem variante (ADR-034).', NEW.card_id;
            END IF;
            IF (NEW.raw_data ->> 'type') IS NULL
               OR (NEW.raw_data ->> 'type') NOT IN ('normal', 'holofoil', 'reverseHolofoil') THEN
                RAISE EXCEPTION 'CVIR_SECOND_SOURCE_TYPE_NOT_ALLOWED: chave de preco % fora do vocabulario aprovado.', COALESCE(NEW.raw_data ->> 'type', '(nula)');
            END IF;
        ELSE
            IF NEW.card_id IS DISTINCT FROM OLD.card_id OR NEW.job_id IS DISTINCT FROM OLD.job_id THEN
                RAISE EXCEPTION 'CVIR_SECOND_SOURCE_IDENTITY_IMMUTABLE: card_id/job_id de linha da 2a fonte nao mudam.';
            END IF;
            IF NEW.persistence_status = 'INSERTED' AND OLD.persistence_status IS DISTINCT FROM 'INSERTED' THEN
                IF EXISTS (SELECT 1 FROM public.card_variant cv
                            WHERE cv.card_id = NEW.card_id
                              AND cv.id IS DISTINCT FROM NEW.resulting_variant_id
                              AND NOT EXISTS (SELECT 1 FROM public.catalog_variant_import_row r
                                               WHERE r.job_id = NEW.job_id
                                                 AND r.resulting_variant_id = cv.id)) THEN
                    RAISE EXCEPTION 'CVIR_SECOND_SOURCE_CARD_GAINED_VARIANT: carta % ganhou variante de outra origem depois do staging; nada e gravado por esta fonte.', NEW.card_id;
                END IF;
            END IF;
        END IF;
        RETURN NEW;
    END;
    $g$;

    CREATE FUNCTION internal.guard_cvij_source_immutable()
    RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $g$
    BEGIN
        IF NEW.source IS DISTINCT FROM OLD.source THEN
            RAISE EXCEPTION 'CVIJ_SOURCE_IMMUTABLE: a fonte de um job de variantes nao muda depois de criado (% -> %).', OLD.source, NEW.source;
        END IF;
        RETURN NEW;
    END;
    $g$;

    REVOKE ALL ON FUNCTION internal.guard_cvir_second_source()    FROM PUBLIC, anon, authenticated;
    REVOKE ALL ON FUNCTION internal.guard_cvij_source_immutable() FROM PUBLIC, anon, authenticated;

    -- Nome ordena depois de trg_catalog_..._normalize: o guard lê status já normalizados.
    CREATE TRIGGER trg_cvir_second_source
        BEFORE INSERT OR UPDATE ON public.catalog_variant_import_row
        FOR EACH ROW EXECUTE FUNCTION internal.guard_cvir_second_source();
    CREATE TRIGGER trg_cvij_source_immutable
        BEFORE UPDATE OF source ON public.catalog_variant_import_job
        FOR EACH ROW EXECUTE FUNCTION internal.guard_cvij_source_immutable();

    -- ===================== S5 — job vazio da SM12 =====================
    UPDATE public.catalog_variant_import_job j
       SET status = 'CANCELLED',
           error_summary = 'F2-01 (2026-10-09): job TCGDEX sem nenhuma linha, cancelado para liberar o indice de job ativo da SM12 para a 2a fonte (ADR-034).'
     WHERE j.id = v_sm12_job AND j.status = 'STAGED' AND j.source = 'TCGDEX' AND j.total_rows = 0
       AND NOT EXISTS (SELECT 1 FROM public.catalog_variant_import_row r WHERE r.job_id = j.id);
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'F2_S5_SM12: %', v_n; END IF;

    -- ===================== PROVA — rotas resolvem =====================
    SELECT cs.id INTO v_xy1 FROM public.card_set cs WHERE cs.code = 'XY1';
    SELECT cs.id INTO v_xy2 FROM public.card_set cs WHERE cs.code = 'XY2';
    FOREACH v_t IN ARRAY ARRAY['normal', 'holofoil', 'reverseHolofoil'] LOOP
        SELECT t.code INTO v_code
          FROM internal.resolve_variant_row_axes(
                   jsonb_build_object('type', v_t, 'foil', NULL, 'subtype', NULL, 'stamp', '[]'::jsonb, 'size', 'standard'),
                   v_game, v_ptcg, 'xy1') a
          JOIN public.card_variant_type t
            ON t.id = internal.lookup_variant_type_for_row(v_game, v_ptcg, v_xy1, a.residual_type, a.residual_foil, a.residual_subtype, COALESCE(a.residual_stamp, '{}'::TEXT[]))
         WHERE a.printing_state = 'RESOLVED_NO_PRINTING' AND a.edition_context_state = 'RESOLVED_NO_EDITION_CONTEXT';
        v_exp := CASE v_t WHEN 'normal' THEN 'STANDARD' WHEN 'holofoil' THEN 'HOLO' ELSE 'REVERSE_HOLO' END;
        IF v_code IS DISTINCT FROM v_exp THEN
            v_fail := v_fail || ' ROUTE_' || v_t || '=' || COALESCE(v_code, 'NULL');
        END IF;
    END LOOP;

    -- ===================== PROVA — guards (bloco desfeito) =====================
    SELECT c.id INTO v_ca FROM public.card c WHERE c.card_set_id = v_xy1
       AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id) ORDER BY c.collector_order OFFSET 0 LIMIT 1;
    SELECT c.id INTO v_cb FROM public.card c WHERE c.card_set_id = v_xy1
       AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id) ORDER BY c.collector_order OFFSET 1 LIMIT 1;
    SELECT c.id INTO v_cc FROM public.card c WHERE c.card_set_id = v_xy1
       AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id) ORDER BY c.collector_order OFFSET 2 LIMIT 1;
    SELECT c.id INTO v_cd FROM public.card c WHERE c.card_set_id = v_xy1
       AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id) ORDER BY c.collector_order OFFSET 3 LIMIT 1;
    SELECT c.id INTO v_cx FROM public.card c WHERE c.card_set_id = v_xy2 ORDER BY c.collector_order LIMIT 1;
    IF v_ca IS NULL OR v_cb IS NULL OR v_cc IS NULL OR v_cd IS NULL OR v_cx IS NULL THEN RAISE EXCEPTION 'F2_T_FIXTURE'; END IF;

    BEGIN
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_xy1, 'POKEMON_TCG_API', 'xy1', 'STAGED') RETURNING id INTO v_job;

        -- T1 linha VALID em carta sem variante: aceita
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_ca, '{"type":"normal","foil":null,"subtype":null,"stamp":[],"size":"standard"}',
                jsonb_build_object('variant_type_id', v_std::TEXT, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID')
        RETURNING id INTO v_ra;
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_ca, '{"type":"reverseHolofoil","foil":null,"subtype":null,"stamp":[],"size":"standard"}',
                jsonb_build_object('variant_type_id', v_rev::TEXT, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID')
        RETURNING id INTO v_rb;

        -- T2 NEEDS_REVIEW: recusada
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
            VALUES (v_job, v_cb, '{"type":"normal"}', '{}', 'NEEDS_REVIEW');
            v_fail := v_fail || ' T2_ACEITA';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'CVIR_SECOND_SOURCE_VALID_ONLY%' THEN v_fail := v_fail || ' T2:' || SQLERRM; END IF;
        END;

        -- T3 carta de outra coleção: recusada
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
            VALUES (v_job, v_cx, '{"type":"normal"}',
                    jsonb_build_object('variant_type_id', v_std::TEXT, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID');
            v_fail := v_fail || ' T3_ACEITA';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'CVIR_SECOND_SOURCE_CARD_NOT_IN_SET%' THEN v_fail := v_fail || ' T3:' || SQLERRM; END IF;
        END;

        -- T4 carta que já tem variante: recusada
        v_vf := internal.write_card_variant('CREATE', NULL, v_cd, v_holo, 1, NULL, NULL);
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
            VALUES (v_job, v_cd, '{"type":"normal"}',
                    jsonb_build_object('variant_type_id', v_std::TEXT, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID');
            v_fail := v_fail || ' T4_ACEITA';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'CVIR_SECOND_SOURCE_CARD_HAS_VARIANT%' THEN v_fail := v_fail || ' T4:' || SQLERRM; END IF;
        END;

        -- T5 chave fora do vocabulário: recusada
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
            VALUES (v_job, v_cb, '{"type":"1stEditionHolofoil"}',
                    jsonb_build_object('variant_type_id', v_holo::TEXT, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID');
            v_fail := v_fail || ' T5_ACEITA';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'CVIR_SECOND_SOURCE_TYPE_NOT_ALLOWED%' THEN v_fail := v_fail || ' T5:' || SQLERRM; END IF;
        END;

        -- T6 confirm de duas variantes da mesma carta, mesmo job: aceita
        v_v1 := internal.write_card_variant('CREATE', NULL, v_ca, v_std, 1, NULL, NULL);
        UPDATE public.catalog_variant_import_row SET decision_status = 'APPROVED', persistence_status = 'INSERTED', resulting_variant_id = v_v1 WHERE id = v_ra;
        v_v2 := internal.write_card_variant('CREATE', NULL, v_ca, v_rev, 2, NULL, NULL);
        BEGIN
            UPDATE public.catalog_variant_import_row SET decision_status = 'APPROVED', persistence_status = 'INSERTED', resulting_variant_id = v_v2 WHERE id = v_rb;
        EXCEPTION WHEN OTHERS THEN v_fail := v_fail || ' T6:' || SQLERRM;
        END;

        -- T7 carta ganhou variante de outra origem entre staging e confirm: recusada
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_cc, '{"type":"holofoil"}',
                jsonb_build_object('variant_type_id', v_holo::TEXT, 'printing_profile_id', NULL, 'edition_context_profile_id', NULL), 'VALID')
        RETURNING id INTO v_rc;
        PERFORM internal.write_card_variant('CREATE', NULL, v_cc, v_std, 1, NULL, NULL);   -- "TCGdex" chegou antes
        v_v3 := internal.write_card_variant('CREATE', NULL, v_cc, v_holo, 2, NULL, NULL);
        BEGIN
            UPDATE public.catalog_variant_import_row SET decision_status = 'APPROVED', persistence_status = 'INSERTED', resulting_variant_id = v_v3 WHERE id = v_rc;
            v_fail := v_fail || ' T7_ACEITA';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'CVIR_SECOND_SOURCE_CARD_GAINED_VARIANT%' THEN v_fail := v_fail || ' T7:' || SQLERRM; END IF;
        END;

        -- T8 job TCGDEX não é afetado: NEEDS_REVIEW em carta com variante é aceita
        INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
        VALUES (v_xy2, 'TCGDEX', 'f2-test-xy2', 'STAGED') RETURNING id INTO v_job_t;
        BEGIN
            INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
            VALUES (v_job_t, v_cx, '{"type":"normal"}', '{}', 'NEEDS_REVIEW');
        EXCEPTION WHEN OTHERS THEN v_fail := v_fail || ' T8:' || SQLERRM;
        END;

        -- T9 source do job é imutável
        BEGIN
            UPDATE public.catalog_variant_import_job SET source = 'TCGDEX' WHERE id = v_job;
            v_fail := v_fail || ' T9_ACEITA';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'CVIJ_SOURCE_IMMUTABLE%' THEN v_fail := v_fail || ' T9:' || SQLERRM; END IF;
        END;

        -- T10 card_id de linha da 2a fonte é imutável
        BEGIN
            UPDATE public.catalog_variant_import_row SET card_id = v_cb WHERE id = v_rc;
            v_fail := v_fail || ' T10_ACEITA';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'CVIR_SECOND_SOURCE_IDENTITY_IMMUTABLE%' THEN v_fail := v_fail || ' T10:' || SQLERRM; END IF;
        END;

        RAISE EXCEPTION 'F2_TESTS_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'F2_TESTS_ROLLBACK' THEN RAISE; END IF;
    END;

    IF v_fail <> '' THEN RAISE EXCEPTION 'F2_PROOF_FAILED:%', v_fail; END IF;

    -- ===================== Pós-condições =====================
    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv1 <> v_cv0 THEN RAISE EXCEPTION 'F2_POST_CARD_VARIANT: % -> %', v_cv0, v_cv1; END IF;
    IF EXISTS (SELECT 1 FROM public.catalog_variant_import_job WHERE source = 'POKEMON_TCG_API' OR external_set_id = 'f2-test-xy2') THEN
        RAISE EXCEPTION 'F2_POST_TEST_RESIDUE';
    END IF;
    SELECT count(*) INTO v_n FROM public.card_set_external_reference WHERE asset_source_id = v_ptcg;
    IF v_n <> 49 THEN RAISE EXCEPTION 'F2_POST_REFS: %', v_n; END IF;

    IF NOT v_apply THEN
        RAISE EXCEPTION 'F2_DRYRUN_OK (rollback): CHECK ampliado, 49 refs, 3 rotas, 2 guards, SM12 liberada; provas T1-T10 e rotas PASS; card_variant %', v_cv1;
    END IF;
    RAISE NOTICE 'F2-01_OK: card_variant % (inalterado)', v_cv1;
END;
$f2$;
