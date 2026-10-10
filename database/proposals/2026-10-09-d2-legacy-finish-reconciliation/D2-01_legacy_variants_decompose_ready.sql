/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: D2-01 - Decompor as 709 Card Variants de tipos legados (SET_LOGO_* / STAFF_HOLO)
Versão......: 1.0
Status......: PRONTA PARA EXECUÇÃO — executar no SQL Editor (Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: D2 parte 1, aprovada por Fabrício em 2026-10-09 (4 grupos).

Objetivo
  Atualizar NO LUGAR (mesmo id) as variantes cujo tipo de Finish legado mistura
  acabamento e contexto. Alvo = acabamento da fonte (raw_data.type/foil da lineage)
  + perfil de Edition Context (raw_data.stamp).

  Grupo 1  EX11–EX16, SET_LOGO_STANDARDS + SET_LOGO_REVERSE (555)
           -> REVERSE_HOLO, sem contexto (mesma decisão H2 de EX7–EX10).
  Grupo 2  fora de EX11–EX16:
           SET_LOGO_STANDARDS (11)   normal + set-logo        -> STANDARD    + ARTWORK_SET_LOGO
           SET_LOGO_REVERSE   (99)   holo + set-logo          -> HOLO        + ARTWORK_SET_LOGO
           SET_LOGO_COSMOS_HOLO (3)  holo cosmos/galaxy + logo -> COSMOS_HOLO + ARTWORK_SET_LOGO
  Grupo 3  STAFF_HOLO (40):
           39 com stamp [set-logo, staff] -> HOLO + ARTWORK_SET_LOGO__ROLE_STAFF
            1 com stamp [staff]           -> HOLO + ROLE_STAFF
  Grupo 4  SET_LOGO_STAFF_HOLO (1) [staff, set-logo] -> HOLO + ARTWORK_SET_LOGO__ROLE_STAFF

  Cria 1 perfil de Edition Context: ARTWORK_SET_LOGO__ROLE_STAFF (display_order 1770).

Garantias (fail-loud; qualquer divergência aborta e desfaz tudo)
  G1 exatamente 709 variantes no plano, distribuição esperada por grupo
  G2 0 colisão com identidade existente (card, finish, printing, EC)
  G3 0 referência em physical_card / pricing_product / collection_* (ids preservados mesmo assim)
  P1 709 atualizadas; 0 variante restante nos 5 tipos legados
  P2 card_variant total inalterado (26.524)

Não toca: mappings, tipos (desativação = D2 parte 2), staging rows.
Como validar (depois):
  SELECT t.code, count(*) FROM card_variant v JOIN card_variant_type t ON t.id=v.variant_type_id
   WHERE t.code IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE','SET_LOGO_COSMOS_HOLO','SET_LOGO_STAFF_HOLO','STAFF_HOLO')
   GROUP BY 1;   -- esperado: 0 linhas
===============================================================================
*/

DO $d2$
DECLARE
    v_game UUID; v_n INTEGER; v_total0 BIGINT; v_total1 BIGINT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    IF v_game IS NULL THEN RAISE EXCEPTION 'D2_G0_GAME_MISSING'; END IF;
    SELECT count(*) INTO v_total0 FROM public.card_variant;

    -- W0: perfil Logo da Coleção · Staff
    IF EXISTS (SELECT 1 FROM public.card_edition_context_profile
                WHERE code = 'ARTWORK_SET_LOGO__ROLE_STAFF' OR display_order = 1770) THEN
        RAISE EXCEPTION 'D2_G0_PROFILE_OR_ORDER_TAKEN';
    END IF;
    INSERT INTO public.card_edition_context_profile (game_id, code, name, description, display_order)
    VALUES (v_game, 'ARTWORK_SET_LOGO__ROLE_STAFF', 'Logo da Coleção · Staff',
            'Carta com carimbo do logo da coleção e marcação de Staff.', 1770);
    INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
    SELECT p.id, t.id, v_game
      FROM public.card_edition_context_profile p
      JOIN public.card_edition_context_trait t
        ON t.game_id = v_game AND t.code IN ('ARTWORK_SET_LOGO','ROLE_STAFF')
     WHERE p.code = 'ARTWORK_SET_LOGO__ROLE_STAFF';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 2 THEN RAISE EXCEPTION 'D2_W0_PROFILE_TRAITS: %', v_n; END IF;
    SET CONSTRAINTS ALL IMMEDIATE;

    -- Plano
    CREATE TEMP TABLE d2_plan ON COMMIT DROP AS
    WITH src AS (
        SELECT v.id, v.card_id, v.printing_profile_id, t.code AS legacy,
               cs.code IN ('EX11','EX12','EX13','EX14','EX15','EX16') AS is_ex,
               bool_or(r.raw_data->'stamp' ? 'set-logo') AS has_logo
          FROM public.card_variant v
          JOIN public.card_variant_type t ON t.id = v.variant_type_id
          JOIN public.card c ON c.id = v.card_id
          JOIN public.card_set cs ON cs.id = c.card_set_id
          LEFT JOIN public.catalog_variant_import_row r
                 ON r.resulting_variant_id = v.id OR r.matched_variant_id = v.id
         WHERE t.code IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE','SET_LOGO_COSMOS_HOLO',
                          'SET_LOGO_STAFF_HOLO','STAFF_HOLO')
         GROUP BY v.id, v.card_id, v.printing_profile_id, t.code, cs.code
    )
    SELECT s.id, s.card_id, s.printing_profile_id, s.legacy,
           CASE WHEN s.is_ex AND s.legacy IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE') THEN 'G1'
                WHEN s.legacy IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE','SET_LOGO_COSMOS_HOLO') THEN 'G2'
                WHEN s.legacy = 'STAFF_HOLO' THEN 'G3' ELSE 'G4' END AS grp,
           CASE WHEN s.is_ex AND s.legacy IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE') THEN 'REVERSE_HOLO'
                WHEN s.legacy = 'SET_LOGO_STANDARDS' THEN 'STANDARD'
                WHEN s.legacy = 'SET_LOGO_COSMOS_HOLO' THEN 'COSMOS_HOLO'
                ELSE 'HOLO' END AS tgt_finish,
           CASE WHEN s.is_ex AND s.legacy IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE') THEN NULL
                WHEN s.legacy IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE','SET_LOGO_COSMOS_HOLO') THEN 'ARTWORK_SET_LOGO'
                WHEN s.legacy = 'SET_LOGO_STAFF_HOLO' THEN 'ARTWORK_SET_LOGO__ROLE_STAFF'
                WHEN s.legacy = 'STAFF_HOLO' AND s.has_logo THEN 'ARTWORK_SET_LOGO__ROLE_STAFF'
                ELSE 'ROLE_STAFF' END AS tgt_ec
      FROM src s;

    -- G1: tamanho e distribuição
    SELECT count(*) INTO v_n FROM d2_plan;
    IF v_n <> 709 THEN RAISE EXCEPTION 'D2_G1_PLAN_SIZE: esperado 709, encontrado %', v_n; END IF;
    IF (SELECT count(*) FROM d2_plan WHERE grp='G1') <> 555
       OR (SELECT count(*) FROM d2_plan WHERE grp='G2') <> 113
       OR (SELECT count(*) FROM d2_plan WHERE grp='G3' AND tgt_ec='ARTWORK_SET_LOGO__ROLE_STAFF') <> 39
       OR (SELECT count(*) FROM d2_plan WHERE grp='G3' AND tgt_ec='ROLE_STAFF') <> 1
       OR (SELECT count(*) FROM d2_plan WHERE grp='G4') <> 1 THEN
        RAISE EXCEPTION 'D2_G1_GROUP_DISTRIBUTION_DRIFT';
    END IF;

    -- G2: colisões
    SELECT count(*) INTO v_n
      FROM d2_plan p
      JOIN public.card_variant_type tf ON tf.code = p.tgt_finish
      LEFT JOIN public.card_edition_context_profile e ON e.code = p.tgt_ec
     WHERE EXISTS (SELECT 1 FROM public.card_variant v2
                    WHERE v2.card_id = p.card_id AND v2.id <> p.id
                      AND v2.variant_type_id = tf.id
                      AND v2.printing_profile_id IS NOT DISTINCT FROM p.printing_profile_id
                      AND v2.edition_context_profile_id IS NOT DISTINCT FROM e.id);
    IF v_n <> 0 THEN RAISE EXCEPTION 'D2_G2_COLLISIONS: %', v_n; END IF;

    -- G3: referências
    IF EXISTS (SELECT 1 FROM public.physical_card x JOIN d2_plan p ON p.id = x.card_variant_id)
       OR EXISTS (SELECT 1 FROM public.pricing_product x JOIN d2_plan p ON p.id = x.card_variant_id)
       OR EXISTS (SELECT 1 FROM public.collection_master_set_scope x JOIN d2_plan p ON p.id = x.card_variant_id)
       OR EXISTS (SELECT 1 FROM public.collection_layout_slot_expected_content x JOIN d2_plan p ON p.id = x.card_variant_id) THEN
        RAISE EXCEPTION 'D2_G3_REFERENCED_VARIANTS';
    END IF;

    -- W1: atualização no lugar
    UPDATE public.card_variant v
       SET variant_type_id = tf.id,
           edition_context_profile_id = e.id
      FROM d2_plan p
      JOIN public.card_variant_type tf ON tf.code = p.tgt_finish
      LEFT JOIN public.card_edition_context_profile e ON e.code = p.tgt_ec
     WHERE v.id = p.id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 709 THEN RAISE EXCEPTION 'D2_W1_UPDATED: %', v_n; END IF;

    -- P1/P2
    SELECT count(*) INTO v_n FROM public.card_variant v JOIN public.card_variant_type t ON t.id = v.variant_type_id
     WHERE t.code IN ('SET_LOGO_STANDARDS','SET_LOGO_REVERSE','SET_LOGO_COSMOS_HOLO','SET_LOGO_STAFF_HOLO','STAFF_HOLO');
    IF v_n <> 0 THEN RAISE EXCEPTION 'D2_P1_LEGACY_REMAINING: %', v_n; END IF;
    SELECT count(*) INTO v_total1 FROM public.card_variant;
    IF v_total0 <> v_total1 THEN RAISE EXCEPTION 'D2_P2_TOTAL_DRIFT: % -> %', v_total0, v_total1; END IF;

    RAISE NOTICE 'D2-01_OK: 709 variantes decompostas; perfil ARTWORK_SET_LOGO__ROLE_STAFF criado.';
END;
$d2$;
