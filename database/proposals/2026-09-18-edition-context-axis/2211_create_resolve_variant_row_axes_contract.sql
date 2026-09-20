-- ============================================================================
-- Query 2211 — internal.resolve_variant_row_axes()
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.1
--
-- v1.1 (EDITION-CONTEXT-AXIS-GATE-A-01) — quatro defeitos corrigidos:
--   A1 ESCOPO: faltava filtro de external_set_id no WHERE. Um mapping escopado
--      a OUTRO Set podia ser eleito pelo LIMIT 1 quando p_external_set_id era
--      NULL. Fail-OPEN cross-set. Corrigido + desempate deterministico por id.
--   A2 NULIDADE: `p.printing_state NOT IN (...)` avalia NULL se 2176 nao
--      devolver linha, e o fluxo seguia para o eixo 3. Agora RAISE explicito.
--   A3 ASSIMETRIA: subtype com mapping conhecido porem INATIVO caia no residual
--      de Finish (fail-OPEN), enquanto stamp ja retornava NEEDS_REVIEW.
--      Simetrizado.
--   A4 RESIDUAL: as saidas NEEDS_REVIEW_* descartavam residual_subtype e
--      residual_stamp, perdendo os tokens que o revisor precisa ver.
-- BLOCKER 2 da CORRECTION-01 — ROUTING ÚNICO
--
-- PROBLEMA
--   compute_variant_residual_signature (2176) resolve size-scope + Printing e
--   devolve o residual APÓS UM eixo. Se Edition Context fosse resolvido em cada
--   consumidor, haveria N implementações paralelas do mesmo roteamento — o
--   erro que a 2193 já corrigiu para Variant Type ao centralizar o worker.
--
-- SOLUÇÃO
--   UM contrato server-side TERMINAL. Todos os consumidores downstream passam a
--   receber o residual APÓS OS DOIS EIXOS. Nenhum reimplementa Edition Context.
--
--   resolve_variant_row_axes() CHAMA compute_variant_residual_signature() —
--   não a duplica. Printing continua sendo resolvido lá; aqui se acrescenta a
--   camada de Edition Context sobre o residual que sobrou.
--
-- ORDEM CANÔNICA (fixa, não configurável)
--   size-scope -> Printing -> Edition Context -> residual Finish
--   Um token consumido por Printing NÃO reaparece para Edition Context.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-02).
-- Três statements: função, COMMENT e REVOKE. O REVOKE não é epílogo — é
-- parte do contrato: a função nasceria EXECUTÁVEL por `anon`/`authenticated`
-- se o arquivo parasse entre o CREATE e o REVOKE. Atomicidade aqui é
-- segurança, não só arrumação.
BEGIN;

-- ---------------------------------------------------------------------------
-- CONTRATO DE `p_external_set_id` (reconciliado em SOURCE-SCOPE-CORRECTION-01)
-- ---------------------------------------------------------------------------
-- `p_external_set_id` é o identificador do Card Set **NA FONTE EXTERNA** —
-- exatamente o valor gravado em `card_set_external_reference.external_set_id`
-- e comparado, sem tradução, contra
-- `card_edition_context_external_mapping.external_set_id`.
--
-- NÃO é `card_set.code`. Os dois são domínios diferentes e divergem em valor:
-- `card_set.code` é o código INTERNO, maiúsculo ('BASE2', 'MFB', 'SWSH9');
-- o identificador da Fonte é minúsculo ('base2', 'mfb', 'swsh9'). Passar
-- `cs.code` faz o predicado `m.external_set_id = p_external_set_id` nunca
-- casar, tornando TODO mapping SCOPED inalcançável — e, por ser fail-closed,
-- o defeito é SILENCIOSO: as rows caem no residual de Finish em vez de
-- levantar erro.
--
-- AUTORIDADE ÚNICA do valor, para todo caller real:
--     internal.resolve_variant_mapping_scope(card_set_id, asset_source_id)
--        -> TABLE(external_set_id TEXT, reference_id UUID)
--
-- Esta função NÃO traduz nem resolve o escopo por conta própria: recebe o
-- valor já resolvido. A tradução é responsabilidade do chamador, de propósito
-- — duplicá-la aqui criaria uma segunda autoridade sobre a mesma referência.
-- Passar NULL continua legítimo e significa "sem escopo": o universo se
-- restringe aos mappings GLOBAL (ver o filtro de escopo obrigatório abaixo).
--
-- ESCOPO DESTA RECONCILIAÇÃO: **zero** mudança executável. Só comentários de
-- código foram acrescentados. Em particular, a string do `COMMENT ON FUNCTION`
-- ao final do arquivo foi deixada BYTE A BYTE como está no LIVE — alterá-la
-- exigiria reexecutar a 2211, o que está fora do mandato desta rodada. O
-- defeito de escopo NÃO estava nesta função: ela sempre comparou o valor que
-- recebeu. Estava nos CHAMADORES, que entregavam `card_set.code`. Por isso a
-- correção é feita neles (2212, 2219, 2220, 2221, 2222, 2831, 2832) e a
-- reconciliação do dado já gravado no LIVE é feita pela 2233 — nunca por uma
-- mudança de comportamento aqui.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.resolve_variant_row_axes(
    p_raw_data        JSONB,
    p_game_id         UUID,
    p_asset_source_id UUID,
    p_external_set_id TEXT DEFAULT NULL   -- identificador EXTERNO da Fonte;
                                          -- NUNCA card_set.code. Ver contrato
                                          -- acima.
)
RETURNS TABLE (
    printing_state             TEXT,
    printing_profile_id        UUID,
    printing_trait_ids         UUID[],
    edition_context_state      TEXT,
    edition_context_profile_id UUID,
    edition_context_trait_ids  UUID[],
    residual_type              TEXT,
    residual_foil              TEXT,
    residual_subtype           TEXT,
    residual_stamp             TEXT[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    p          RECORD;
    v_ec_sig   UUID[] := '{}';
    v_res_st   TEXT;
    v_res_sp   TEXT[] := '{}';
    v_tok      TEXT;
    v_mid      UUID;
    v_msig     UUID[];
    v_known    BOOLEAN;
    v_profile  UUID;
    v_state    TEXT := 'RESOLVED_NO_EDITION_CONTEXT';
BEGIN
    -- ---- EIXOS 1 e 2: size-scope + Printing (contrato existente 2176) ------
    SELECT * INTO p
      FROM internal.compute_variant_residual_signature(p_raw_data, p_game_id, p_asset_source_id);

    -- FAIL-CLOSED contra ausência de linha: se 2176 não devolver linha,
    -- p é NULL e p.printing_state é NULL. `NULL NOT IN (...)` avalia NULL,
    -- que NÃO entra no IF — o fluxo seguiria para o eixo 3 com estado nulo.
    -- Por isso o teste de nulidade vem ANTES e é explícito.
    IF p IS NULL OR p.printing_state IS NULL THEN
        RAISE EXCEPTION 'VARIANT_AXES_UPSTREAM_NO_ROW: compute_variant_residual_signature nao devolveu linha.';
    END IF;

    -- Estado não-terminal em Printing (BLOCKED_* de escopo ou NEEDS_REVIEW_*
    -- de tiragem): devolve como está, sem tocar no eixo 3.
    IF p.printing_state NOT IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE') THEN
        RETURN QUERY SELECT p.printing_state, p.printing_profile_id, p.trait_ids,
                            'NOT_EVALUATED'::TEXT, NULL::UUID, '{}'::UUID[],
                            p.residual_type, p.residual_foil, p.residual_subtype, p.residual_stamp;
        RETURN;
    END IF;

    v_res_st := p.residual_subtype;

    -- ---- EIXO 3: Edition Context sobre o residual que sobrou --------------
    -- subtype residual (token inteiro ou nada)
    IF v_res_st IS NOT NULL AND btrim(v_res_st) <> '' THEN
        -- ESCOPO OBRIGATÓRIO no WHERE (GATE-A-01, achado A1): sem este filtro,
        -- quando p_external_set_id é NULL e não existe mapping GLOBAL, o
        -- ORDER BY avalia FALSE para todos e o LIMIT 1 escolheria um mapping
        -- escopado a OUTRO Set — vazamento cross-set, fail-OPEN.
        -- Universo legítimo = { escopado a ESTE Set } união { GLOBAL }.
        SELECT m.id, COALESCE(m.traits_signature,
                 ARRAY(SELECT mt.trait_id FROM public.card_edition_context_external_mapping_trait mt
                        WHERE mt.mapping_id = m.id ORDER BY mt.trait_id))
          INTO v_mid, v_msig
          FROM public.card_edition_context_external_mapping m
         WHERE m.game_id = p_game_id AND m.asset_source_id = p_asset_source_id
           AND m.raw_field = 'subtype' AND m.normalized_token = v_res_st AND m.is_active
           AND (m.external_set_id IS NULL
                OR (p_external_set_id IS NOT NULL AND m.external_set_id = p_external_set_id))
           -- PRECEDÊNCIA DE UM NÍVEL: scoped > global. Determinística:
           -- uq_cecem_active_scoped e uq_cecem_active_global (2207 v3.0)
           -- garantem no máximo 1 ATIVO de cada, e o filtro `m.is_active`
           -- acima restringe o universo a eles. Logo o candidato é no máximo
           -- 1 scoped + 1 global, e o ORDER BY decide entre dois.
           --
           -- `m.id` é desempate PROVAVELMENTE INALCANÇÁVEL: seria preciso dois
           -- ativos com o mesmo (escopo, token), que os índices parciais
           -- proíbem. Mantido como rede determinística — nunca como a regra.
           --
           -- CORREÇÃO DE AFIRMAÇÃO (MAPPING-LIFECYCLE-CORRECTION-02).
           -- A nota escrita na CORRECTION-01 dizia que, antes da
           -- partialização, "o histórico inativo CONCORRIA neste ORDER BY".
           -- ISSO ESTAVA ERRADO e foi removido: o predicado `AND m.is_active`
           -- desta query sempre existiu, então mapping inativo NUNCA
           -- participou deste ORDER BY, em nenhuma versão.
           -- O que a partialização mudou é OUTRA coisa: ela impede que dois
           -- ATIVOS coexistam no mesmo escopo — antes era possível, e aí sim
           -- o desempate por `m.id` decidiria arbitrariamente entre dois
           -- mapeamentos igualmente válidos.
           -- E o `ix_cecem_token` não serve a esta query: ele existe para a
           -- SEGUNDA busca (a de `v_known`, sem `is_active`), que distingue
           -- KNOWN/INACTIVE de UNKNOWN/residual.
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
            -- SIMETRIA COM stamp (GATE-A-01, achado A3): token conhecido mas
            -- com routing INATIVO não pode cair silenciosamente no residual de
            -- Finish — isso é fail-OPEN e produziria um Variant Type errado.
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
            -- Token DESCONHECIDO: fail-closed, permanece no residual de Finish.
        END IF;
    END IF;

    -- stamp residual (token a token)
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
           -- Mesma garantia do bloco de subtype: com `m.is_active` + os dois
           -- índices parciais da 2207, o universo é no máximo 1 scoped + 1
           -- global. `m.id` é rede, não regra. Histórico inativo nunca entrou
           -- aqui — o filtro `is_active` sempre existiu (ver correção de
           -- afirmação no bloco de subtype).
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
                -- conhecido mas sem routing ativo: NÃO volta ao residual.
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
                            p.residual_type, p.residual_foil, v_res_st, v_res_sp;
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
                        p.residual_type, p.residual_foil, v_res_st, v_res_sp;
END;
$$;

COMMENT ON FUNCTION internal.resolve_variant_row_axes(JSONB, UUID, UUID, TEXT) IS
'CONTRATO TERMINAL de roteamento. Ordem fixa: size-scope -> Printing -> Edition Context -> residual Finish. Chama compute_variant_residual_signature (nao duplica). Todo consumidor downstream DEVE usar esta funcao; nenhum reimplementa Edition Context.';

REVOKE ALL ON FUNCTION internal.resolve_variant_row_axes(JSONB, UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;

COMMIT;
