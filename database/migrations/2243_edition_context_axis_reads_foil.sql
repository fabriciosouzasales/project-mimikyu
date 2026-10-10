/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2243 - Eixo de Edition Context passa a ler o campo `foil`
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE (2026-10-09, apply_migration, ledger 20261010003718 = edition_context_axis_reads_foil_2243)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: Decisão H3 de Fabrício (2026-10-09): foil de programa (league,
              player-reward, professor-program) = acabamento pelo `type` +
              Edition Context pelo `foil`. "Modelo certo, depois das simples".

-------------------------------------------------------------------------------
O QUE MUDA (e só isso)
-------------------------------------------------------------------------------
1. CHECK ck_cecem_raw_field de public.card_edition_context_external_mapping:
   ('stamp','subtype')  ->  ('stamp','subtype','foil').
2. internal.resolve_variant_row_axes (2211): novo bloco do eixo 3 para o
   `residual_foil`, idêntico ao bloco de `subtype` (token inteiro; escopo
   scoped > global; mapping conhecido-inativo => NEEDS_REVIEW_INACTIVE_EC_MAPPING;
   desconhecido => fail-closed, permanece no residual de Finish). Quando
   consumido, `residual_foil` volta NULL e o Finish é resolvido só pelo `type`.

O QUE NÃO MUDA
- Assinatura, retorno, SECURITY DEFINER, search_path='' e grants da 2211.
- Comportamento para qualquer `foil` sem mapping de EC com raw_field='foil':
  idêntico ao anterior (o bloco só age se existir mapping 'foil'). Antes da
  seed 2244 não existe nenhum => esta migration sozinha é no-op funcional.
- Nenhum dado é escrito. Nenhum mapping é criado aqui (isso é a 2244).

IMPACTO MEDIDO (2026-10-09, antes da 2244): linhas com foil LEAGUE /
PLAYER-REWARD / PROFESSOR-PROGRAM ainda não persistidas = 57 NEEDS_REVIEW (H3)
em jobs STAGED + 2 em jobs CANCELLED. As 5 já persistidas não são reavaliadas.
Consequência permanente: futuras importações com `normal + league` passam a
resolver STANDARD + PROGRAM_LEAGUE em vez do tipo legado STANDARDS_LEAGUE
(mapping de Finish GLOBAL NORMAL+LEAGUE fica sem efeito), e `reverse +
player-reward` em sv05 deixa de cair em PLAYER_REWARD_REVERSE. Reconciliação dos
tipos legados = frente D2.

Como validar: 2846 (rollback-only) + leitura:
    SELECT pg_get_constraintdef(oid) FROM pg_constraint
     WHERE conname = 'ck_cecem_raw_field';
    -- esperado: CHECK ((raw_field = ANY (ARRAY['stamp'::text, 'subtype'::text, 'foil'::text])))
===============================================================================
*/

BEGIN;

ALTER TABLE public.card_edition_context_external_mapping
    DROP CONSTRAINT ck_cecem_raw_field;
ALTER TABLE public.card_edition_context_external_mapping
    ADD CONSTRAINT ck_cecem_raw_field CHECK (raw_field = ANY (ARRAY['stamp'::text, 'subtype'::text, 'foil'::text]));

CREATE OR REPLACE FUNCTION internal.resolve_variant_row_axes(
    p_raw_data jsonb, p_game_id uuid, p_asset_source_id uuid, p_external_set_id text DEFAULT NULL::text)
RETURNS TABLE(printing_state text, printing_profile_id uuid, printing_trait_ids uuid[],
              edition_context_state text, edition_context_profile_id uuid, edition_context_trait_ids uuid[],
              residual_type text, residual_foil text, residual_subtype text, residual_stamp text[])
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    p          RECORD;
    v_ec_sig   UUID[] := '{}';
    v_res_st   TEXT;
    v_res_fl   TEXT;
    v_res_sp   TEXT[] := '{}';
    v_tok      TEXT;
    v_mid      UUID;
    v_msig     UUID[];
    v_known    BOOLEAN;
    v_profile  UUID;
    v_state    TEXT := 'RESOLVED_NO_EDITION_CONTEXT';
BEGIN
    -- ---- EIXOS 1 e 2: size-scope + Printing (contrato 2176) ----------------
    SELECT * INTO p
      FROM internal.compute_variant_residual_signature(p_raw_data, p_game_id, p_asset_source_id);

    IF p IS NULL OR p.printing_state IS NULL THEN
        RAISE EXCEPTION 'VARIANT_AXES_UPSTREAM_NO_ROW: compute_variant_residual_signature nao devolveu linha.';
    END IF;

    IF p.printing_state NOT IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE') THEN
        RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                            'NOT_EVALUATED'::TEXT, NULL::UUID, '{}'::UUID[],
                            p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
        RETURN;
    END IF;

    v_res_st := p.residual_subtype;
    v_res_fl := p.residual_foil;

    -- ---- EIXO 3: Edition Context sobre o residual --------------------------
    -- subtype residual (token inteiro ou nada) — inalterado desde 2211.
    -- Escopo obrigatório no WHERE (GATE-A-01/A1): universo = {este Set} ∪ {GLOBAL};
    -- precedência scoped > global; `m.id` é rede determinística, não regra.
    IF v_res_st IS NOT NULL AND btrim(v_res_st) <> '' THEN
        SELECT m.id, COALESCE(m.traits_signature,
                 ARRAY(SELECT mt.trait_id FROM public.card_edition_context_external_mapping_trait mt
                        WHERE mt.mapping_id = m.id ORDER BY mt.trait_id))
          INTO v_mid, v_msig
          FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
           AND m.raw_field = 'subtype' AND m.normalized_token = v_res_st AND m.is_active
           AND (m.external_set_id IS NULL
                OR (p_external_set_id IS NOT NULL AND m.external_set_id = p_external_set_id))
         ORDER BY (m.external_set_id IS NOT NULL) DESC, m.id
         LIMIT 1;

        IF v_mid IS NOT NULL THEN
            IF v_msig IS NULL OR cardinality(v_msig) = 0 THEN
                RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                                    'NEEDS_REVIEW_INVALID_EC_MAPPING'::TEXT, NULL::UUID, '{}'::UUID[],
                                    p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
                RETURN;
            END IF;
            v_ec_sig := v_ec_sig || v_msig;
            v_res_st := NULL;                       -- consumido pelo eixo 3
        ELSE
            -- Simetria com stamp (GATE-A-01/A3): conhecido-inativo não cai no Finish.
            SELECT TRUE INTO v_known FROM public.card_edition_context_external_mapping m
             WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
               AND m.raw_field = 'subtype' AND m.normalized_token = v_res_st
               AND (m.external_set_id IS NULL
                    OR (p_external_set_id IS NOT NULL AND m.external_set_id = p_external_set_id))
             LIMIT 1;
            IF v_known THEN
                RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                                    'NEEDS_REVIEW_INACTIVE_EC_MAPPING'::TEXT, NULL::UUID, '{}'::UUID[],
                                    p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
                RETURN;
            END IF;
            -- desconhecido: fail-closed, permanece no residual de Finish.
        END IF;
    END IF;

    -- foil residual (token inteiro ou nada) — NOVO (2243, decisão H3).
    -- Mesmo contrato do bloco de subtype. Só age se existir mapping raw_field='foil';
    -- sem mapping, o foil segue intacto para o Finish (comportamento anterior).
    v_mid := NULL; v_msig := NULL; v_known := NULL;
    IF v_res_fl IS NOT NULL AND btrim(v_res_fl) <> '' THEN
        SELECT m.id, COALESCE(m.traits_signature,
                 ARRAY(SELECT mt.trait_id FROM public.card_edition_context_external_mapping_trait mt
                        WHERE mt.mapping_id = m.id ORDER BY mt.trait_id))
          INTO v_mid, v_msig
          FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
           AND m.raw_field = 'foil' AND m.normalized_token = v_res_fl AND m.is_active
           AND (m.external_set_id IS NULL
                OR (p_external_set_id IS NOT NULL AND m.external_set_id = p_external_set_id))
         ORDER BY (m.external_set_id IS NOT NULL) DESC, m.id
         LIMIT 1;

        IF v_mid IS NOT NULL THEN
            IF v_msig IS NULL OR cardinality(v_msig) = 0 THEN
                RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                                    'NEEDS_REVIEW_INVALID_EC_MAPPING'::TEXT, NULL::UUID, '{}'::UUID[],
                                    p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
                RETURN;
            END IF;
            v_ec_sig := v_ec_sig || v_msig;
            v_res_fl := NULL;                       -- consumido pelo eixo 3
        ELSE
            SELECT TRUE INTO v_known FROM public.card_edition_context_external_mapping m
             WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
               AND m.raw_field = 'foil' AND m.normalized_token = v_res_fl
               AND (m.external_set_id IS NULL
                    OR (p_external_set_id IS NOT NULL AND m.external_set_id = p_external_set_id))
             LIMIT 1;
            IF v_known THEN
                RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                                    'NEEDS_REVIEW_INACTIVE_EC_MAPPING'::TEXT, NULL::UUID, '{}'::UUID[],
                                    p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
                RETURN;
            END IF;
        END IF;
    END IF;

    -- stamp residual (token a token) — inalterado desde 2211.
    FOREACH v_tok IN ARRAY COALESCE(p.residual_stamp, '{}') LOOP
        v_mid := NULL; v_msig := NULL; v_known := NULL;

        SELECT m.id, COALESCE(m.traits_signature,
                 ARRAY(SELECT mt.trait_id FROM public.card_edition_context_external_mapping_trait mt
                        WHERE mt.mapping_id = m.id ORDER BY mt.trait_id))
          INTO v_mid, v_msig
          FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
           AND m.raw_field = 'stamp' AND m.normalized_token = v_tok AND m.is_active
           AND (m.external_set_id IS NULL
                OR (p_external_set_id IS NOT NULL AND m.external_set_id = p_external_set_id))
         ORDER BY (m.external_set_id IS NOT NULL) DESC, m.id
         LIMIT 1;

        IF v_mid IS NOT NULL THEN
            IF v_msig IS NULL OR cardinality(v_msig) = 0 THEN
                RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                                    'NEEDS_REVIEW_INVALID_EC_MAPPING'::TEXT, NULL::UUID, '{}'::UUID[],
                                    p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
                RETURN;
            END IF;
            v_ec_sig := v_ec_sig || v_msig;
        ELSE
            SELECT TRUE INTO v_known FROM public.card_edition_context_external_mapping m
             WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
               AND m.raw_field = 'stamp' AND m.normalized_token = v_tok
               AND (m.external_set_id IS NULL
                    OR (p_external_set_id IS NOT NULL AND m.external_set_id = p_external_set_id))
             LIMIT 1;
            IF v_known THEN
                RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                                    'NEEDS_REVIEW_INACTIVE_EC_MAPPING'::TEXT, NULL::UUID, '{}'::UUID[],
                                    p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
                RETURN;
            END IF;
            v_res_sp := v_res_sp || v_tok;          -- FAIL CLOSED: fica no residual
        END IF;
    END LOOP;

    v_res_sp := ARRAY(SELECT s FROM unnest(v_res_sp) s ORDER BY s);

    IF cardinality(v_ec_sig) = 0 THEN
        RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                            'RESOLVED_NO_EDITION_CONTEXT'::TEXT, NULL::UUID, '{}'::UUID[],
                            p.residual_type, v_res_fl, v_res_st, v_res_sp;
        RETURN;
    END IF;

    v_ec_sig := ARRAY(SELECT DISTINCT t FROM unnest(v_ec_sig) t ORDER BY t);

    IF EXISTS (SELECT 1 FROM public.card_edition_context_trait t
                WHERE t.id = ANY (v_ec_sig) AND NOT t.is_active) THEN
        v_state := 'NEEDS_REVIEW_INACTIVE_EC_TRAIT';
    ELSE
        SELECT ecp.id INTO v_profile
          FROM public.card_edition_context_profile ecp
         WHERE ecp.game_id = p_game_id AND ecp.traits_signature = v_ec_sig;
        IF v_profile IS NULL THEN
            v_state := 'NEEDS_REVIEW_NO_EC_PROFILE';   -- jamais criar profile na importação
        ELSIF NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile x
                           WHERE x.id = v_profile AND x.is_active) THEN
            v_state := 'NEEDS_REVIEW_INACTIVE_EC_PROFILE';
            v_profile := NULL;
        ELSE
            v_state := 'RESOLVED_WITH_EC_PROFILE';
        END IF;
    END IF;

    RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                        v_state, v_profile, v_ec_sig,
                        p.residual_type, v_res_fl, v_res_st, v_res_sp;
END;
$function$;

COMMIT;
