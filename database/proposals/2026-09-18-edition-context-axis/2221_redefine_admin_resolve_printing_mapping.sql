-- ===========================================================================
-- Query 2221 — public.admin_resolve_catalog_variant_import_printing_mapping()
--              v2.0 — terceiro eixo (Contexto de Edição) no caminho de escrita
-- ===========================================================================
-- STATUS: PROPOSTA — NÃO EXECUTADA. Pacote EDITION-CONTEXT-AXIS.
-- Base canônica: database/schema/2181_create_admin_resolve_printing_mapping_function.sql
--   · assinatura  ............ linha 297
--   · corpo ................... linhas 297–584 (dollar-quote `printing`)
--   · CTE `touched` ........... linhas 466–491  ← ÚNICO call site de 2176
--   · CTE `classified` ........ linhas 492–512
--   · CTE `updated` ........... linhas 513–540
--   · gates de reconciliação .. linhas 550–558
--
-- ---------------------------------------------------------------------------
-- O QUE MUDA
-- ---------------------------------------------------------------------------
--   (a) `touched` passa a chamar internal.resolve_variant_row_axes() no lugar
--       de internal.compute_variant_residual_signature(). É o call site da
--       linha 470 da canônica — o último dos 7 inventariados em
--       IMPACTED-CONTRACTS.md que ainda usava o contrato de dois eixos.
--   (b) `classified` passa a exigir os DOIS eixos terminalmente resolvidos
--       para que a linha possa ser promovida. Contexto de Edição indeterminado
--       degrada para outcome 'C', exatamente como Impressão indeterminada.
--   (c) `updated` grava a TERCEIRA chave (`edition_context_profile_id`) nos
--       outcomes A e B, e a REMOVE no outcome C — o mesmo tri-state
--       ausente/`JSON null`/string-UUID já usado nos demais artefatos.
--   (d) o metadata do action log ganha `rows_blocked_edition_context`, para
--       que a contagem de `rows_still_pending` continue auditável por causa.
--
-- ---------------------------------------------------------------------------
-- O QUE NÃO MUDA — e por quê
-- ---------------------------------------------------------------------------
--   · A assinatura, o RETURNS TABLE, LANGUAGE/SECURITY DEFINER/search_path=''.
--   · TODOS os 13 guards de entrada (linhas 330–420 da canônica): ator admin,
--     args obrigatórios, raw_field ∈ (subtype, stamp), forma do array, teto de
--     20 traits, NULL em trait, duplicata, row/job/game/source encontrados,
--     traits válidos e ativos no Game, token normalizado não vazio, token
--     presente na linha de origem.
--   · A lógica de Impressão em si — supersede do mapping ativo, INSERT do novo
--     mapping e de seus traits. O mandato é explícito: este artefato NÃO
--     reabre modelagem de Impressão.
--   · Os dois gates de reconciliação, com os MESMOS códigos de erro
--     (`…_RECONCILIATION_GAP`, `…_COUNTER_GAP`). O segundo continua válido:
--     `rows_updated + rows_pending = touched` permanece verdadeiro porque o
--     bloqueio por Contexto de Edição cai dentro de `rows_pending` (outcome C).
--   · O bloco de REVOKE/GRANT ao final, reincorporado pelo mesmo motivo
--     documentado na 2181 v1.2 (instalação limpa divergiria do LIVE).
--
-- ---------------------------------------------------------------------------
-- NOTA DE FIDELIDADE — o `IN (…)` da linha 476 foi PRESERVADO
-- ---------------------------------------------------------------------------
-- `resolve_variant_row_axes` recebe `p_external_set_id` — o identificador
-- EXTERNO do Card Set na Fonte (`card_set_external_reference.external_set_id`),
-- resolvido por `internal.resolve_variant_mapping_scope(card_set_id,
-- asset_source_id)`. NÃO é `card_set.code`: o código interno é maiúsculo
-- ('BASE2') e o identificador da Fonte é minúsculo ('base2'), de modo que
-- passar `cs.code` torna TODO mapping SCOPED inalcançável (corrigido em
-- SOURCE-SCOPE-CORRECTION-01). A CTE canônica não materializava nenhum dos
-- dois. Para obter o escopo foi necessário juntar `card_set` e `expansion`.
-- Havia duas saídas:
--
--   A. trocar `j.card_set_id IN (SELECT cs2.id … WHERE e2.game_id = v_game_id)`
--      pelo predicado equivalente `e.game_id = v_game_id` sobre o novo join;
--   B. ADICIONAR os joins e PRESERVAR o predicado original, byte a byte.
--
-- Escolhida **B**. As duas são logicamente equivalentes, mas B mantém o diff
-- restrito ao que o mandato pede e não exige que o revisor aceite uma prova
-- de equivalência para validar a mudança de eixo. O join não altera
-- cardinalidade: `cs.id = j.card_set_id` e `e.id = cs.expansion_id` são FKs
-- NOT NULL de valor único, logo `touched` devolve exatamente o mesmo conjunto
-- de linhas que devolvia antes.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO 1 — o contrato de três eixos (2211) precisa existir.
-- ---------------------------------------------------------------------------
DO $pre1$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'internal'
           AND p.proname = 'resolve_variant_row_axes'
    ) THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2221_A: internal.resolve_variant_row_axes() nao existe. Executar a Query 2211 antes desta.';
    END IF;
END
$pre1$;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO 2 — a função-alvo precisa existir com ESTA assinatura.
-- CREATE OR REPLACE com assinatura divergente criaria uma sobrecarga nova e
-- deixaria a antiga viva: dois caminhos de escrita simultâneos.
-- ---------------------------------------------------------------------------
DO $pre2$
BEGIN
    -- IDENTIFICACAO POR OID (FUNCTION-IDENTITY-GATE-CORRECTION-01).
    -- NAO comparar o TEXTO devolvido por pg_get_function_identity_arguments():
    -- essa funcao INCLUI os nomes dos parametros, de modo que o literal
    -- 'uuid, text, text, uuid[]' nunca casa com uma funcao de parametros
    -- nomeados — e esta tem os quatro nomeados. to_regprocedure() resolve
    -- schema + tipos e devolve NULL (sem levantar excecao) quando o alvo nao
    -- existe, que e exatamente o teste desejado aqui.
    IF to_regprocedure('public.admin_resolve_catalog_variant_import_printing_mapping(uuid,text,text,uuid[])') IS NULL THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2221_B: public.admin_resolve_catalog_variant_import_printing_mapping(uuid, text, text, uuid[]) nao encontrada com a assinatura esperada.';
    END IF;
END
$pre2$;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO 3 — a coluna do terceiro eixo precisa existir em card_variant.
-- Esta função não escreve em card_variant, mas as chaves que ela grava em
-- normalized_data são consumidas pela 2218; gravar a chave antes de o destino
-- existir criaria staging que nenhum confirm consegue persistir.
-- ---------------------------------------------------------------------------
DO $pre3$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'card_variant'
           AND column_name  = 'edition_context_profile_id'
    ) THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2221_C: public.card_variant.edition_context_profile_id nao existe. Executar a Query 2208 antes desta.';
    END IF;
END
$pre3$;


CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(
    p_row_id     UUID,
    p_raw_field  TEXT,
    p_token      TEXT,
    p_trait_ids  UUID[]
)
RETURNS TABLE(
    mapping_id            UUID,
    superseded_mapping_id UUID,
    rows_updated          INTEGER,
    rows_still_pending    INTEGER,
    jobs_affected         INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $printing$
DECLARE
    c_max_traits CONSTANT INTEGER := 20;

    v_row public.catalog_variant_import_row%ROWTYPE;
    v_job_source TEXT;
    v_game_id UUID;
    v_asset_source_id UUID;
    v_token TEXT;
    v_signature UUID[];
    v_active_sig UUID[];
    v_old_mapping_id UUID;
    v_new_mapping_id UUID;
    v_rows_updated INTEGER;
    v_rows_pending INTEGER;
    v_jobs_affected INTEGER;
    v_touched_total INTEGER;
    v_reconciled_total INTEGER;
    -- v2.0: desdobramento auditável de rows_still_pending por causa.
    v_blocked_ec INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_FORBIDDEN: apenas administradores podem resolver um mapeamento de impressão.';
    END IF;

    IF p_row_id IS NULL OR p_raw_field IS NULL OR p_token IS NULL OR p_trait_ids IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_MISSING_ARGS: p_row_id, p_raw_field, p_token e p_trait_ids são obrigatórios.';
    END IF;

    IF p_raw_field NOT IN ('subtype', 'stamp') THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_FIELD: p_raw_field deve ser subtype ou stamp (recebido: %). type e foil são acabamento e nunca são roteados para Impressão.', p_raw_field;
    END IF;

    IF array_ndims(p_trait_ids) <> 1 THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_ARRAY_SHAPE: p_trait_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_trait_ids);
    END IF;

    IF cardinality(p_trait_ids) = 0 THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_EMPTY_TRAITS: p_trait_ids veio vazio. Mapeamento parcial não é permitido — informe o conjunto completo de Características de Impressão.';
    END IF;

    IF cardinality(p_trait_ids) > c_max_traits THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_TOO_MANY_TRAITS: % traits, acima do teto de % por token.', cardinality(p_trait_ids), c_max_traits;
    END IF;

    IF EXISTS (SELECT 1 FROM unnest(p_trait_ids) t WHERE t IS NULL) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_NULL_TRAIT: p_trait_ids contém NULL.';
    END IF;

    v_signature := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) t ORDER BY t);

    IF cardinality(v_signature) <> cardinality(p_trait_ids) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_DUPLICATE_TRAIT: p_trait_ids contém a mesma Característica de Impressão mais de uma vez.';
    END IF;

    SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_ROW_NOT_FOUND: nenhuma linha encontrada para o id informado (%).', p_row_id;
    END IF;

    SELECT j.source INTO v_job_source FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;
    IF v_job_source IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_JOB_NOT_FOUND: não foi possível resolver o job desta linha.';
    END IF;

    SELECT e.game_id INTO v_game_id
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    WHERE c.id = v_row.card_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_GAME_NOT_FOUND: não foi possível resolver o Game desta linha.';
    END IF;

    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = v_job_source;
    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_SOURCE_NOT_FOUND: nenhuma Fonte encontrada para o código % do job desta linha.', v_job_source;
    END IF;

    IF (SELECT count(*) FROM public.card_printing_trait t
         WHERE t.id = ANY (v_signature) AND t.game_id = v_game_id AND t.is_active)
       <> cardinality(v_signature) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_TRAITS: uma ou mais Características de Impressão não existem, pertencem a outro Game ou estão inativas.';
    END IF;

    v_token := public.normalize_external_catalog_value(p_token);
    IF btrim(v_token) = '' THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_EMPTY_TOKEN: o token normalizado ficou vazio (recebido: %).', p_token;
    END IF;

    IF p_raw_field = 'subtype' THEN
        IF public.normalize_external_catalog_value(v_row.raw_data ->> 'subtype')
           IS DISTINCT FROM v_token THEN
            RAISE EXCEPTION 'PRINTING_MAPPING_ORIGIN_TOKEN_NOT_FOUND: o token % (normalizado: %) não é o subtype da linha de origem %. A linha informada precisa conter exatamente esta combinação — ela é a evidência editorial da decisão.',
                p_token, v_token, p_row_id;
        END IF;
    ELSE
        IF jsonb_typeof(v_row.raw_data -> 'stamp') IS DISTINCT FROM 'array'
           OR NOT EXISTS (
               SELECT 1
                 FROM jsonb_array_elements_text(v_row.raw_data -> 'stamp') e
                WHERE public.normalize_external_catalog_value(e) = v_token
           ) THEN
            RAISE EXCEPTION 'PRINTING_MAPPING_ORIGIN_TOKEN_NOT_FOUND: o token % (normalizado: %) não está no array stamp da linha de origem %. A linha informada precisa conter exatamente este token — ela é a evidência editorial da decisão.',
                p_token, v_token, p_row_id;
        END IF;
    END IF;

    SELECT m.id INTO v_old_mapping_id
      FROM public.card_printing_external_mapping m
     WHERE m.game_id = v_game_id
       AND m.asset_source_id = v_asset_source_id
       AND m.raw_field = p_raw_field
       AND m.normalized_token = v_token
       AND m.is_active
     FOR UPDATE;

    IF v_old_mapping_id IS NOT NULL THEN
        SELECT COALESCE(
                   m.traits_signature,
                   ARRAY(SELECT mt.trait_id
                           FROM public.card_printing_external_mapping_trait mt
                          WHERE mt.mapping_id = m.id
                          ORDER BY mt.trait_id))
          INTO v_active_sig
          FROM public.card_printing_external_mapping m
         WHERE m.id = v_old_mapping_id;

        IF v_active_sig IS NULL OR cardinality(v_active_sig) = 0 THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_ACTIVE_COMPOSITION: o mapeamento ativo % deste token está com composição efetiva vazia — estado estruturalmente inválido. Corrigir a integridade do mapeamento antes de substituí-lo.', v_old_mapping_id;
        END IF;

        IF v_active_sig = v_signature THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_NO_CHANGE: o mapeamento ativo deste token já tem exatamente esta composição.';
        END IF;
    END IF;

    IF v_old_mapping_id IS NOT NULL THEN
        UPDATE public.card_printing_external_mapping
           SET is_active = FALSE
         WHERE id = v_old_mapping_id;
    END IF;

    INSERT INTO public.card_printing_external_mapping
        (game_id, asset_source_id, raw_field, normalized_token, external_token,
         is_active, supersedes_mapping_id)
    VALUES
        (v_game_id, v_asset_source_id, p_raw_field, v_token, p_token,
         TRUE, v_old_mapping_id)
    RETURNING id INTO v_new_mapping_id;

    INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
    SELECT v_new_mapping_id, t, v_game_id FROM unnest(v_signature) t;

    -- =======================================================================
    -- PROPAGAÇÃO — v2.0, três eixos
    --
    -- A ordem importa e é a mesma da canônica: o novo mapping JÁ FOI gravado
    -- acima, portanto `resolve_variant_row_axes` abaixo já enxerga o efeito da
    -- decisão editorial que está sendo tomada nesta mesma transação. É por
    -- isso que a reavaliação pode ser feita em uma única passada.
    -- =======================================================================
    WITH touched AS (
        SELECT r.id, r.job_id, j.card_set_id, ax.*
        FROM public.catalog_variant_import_row r
        JOIN public.catalog_variant_import_job j ON j.id = r.job_id
        -- v2.0: joins ADICIONADOS apenas para materializar o escopo externo.
        -- FKs NOT NULL de valor único — não alteram a cardinalidade de
        -- `touched`. Ver NOTA DE FIDELIDADE no cabeçalho.
        JOIN public.card_set  cs ON cs.id = j.card_set_id
        JOIN public.expansion e  ON e.id  = cs.expansion_id
        -- v2.1 (SOURCE-SCOPE-CORRECTION-01): ESCOPO CANÔNICO. O 4º argumento
        -- é o identificador EXTERNO da Fonte (card_set_external_reference
        -- .external_set_id), NUNCA card_set.code — os dois divergem em caixa e
        -- em valor ('base2' vs 'BASE2'). Autoridade única:
        -- internal.resolve_variant_mapping_scope(card_set_id, asset_source_id).
        LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(
            cs.id, v_asset_source_id) sc ON TRUE
        -- v2.0: ÚNICA troca de contrato desta CTE. O contrato de DOIS eixos
        -- (2176) foi substituído pelo de TRÊS (2211). O nome antigo NÃO é
        -- citado aqui de propósito: o POSTCHECK 1 varre `prosrc`, que inclui
        -- comentários, e uma citação em comentário produziria falso-positivo.
        CROSS JOIN LATERAL internal.resolve_variant_row_axes(
            r.raw_data, v_game_id, v_asset_source_id, sc.external_set_id
        ) ax
        WHERE j.status = 'STAGED'
          AND j.source = v_job_source
          -- PRESERVADO byte a byte da canônica (linha 476).
          AND j.card_set_id IN (
              SELECT cs2.id FROM public.card_set cs2
              JOIN public.expansion e2 ON e2.id = cs2.expansion_id
              WHERE e2.game_id = v_game_id
          )
          AND r.decision_status = 'PENDING'
          AND r.validation_status IN ('VALID', 'NEEDS_REVIEW')
          AND (
              (p_raw_field = 'subtype'
               AND public.normalize_external_catalog_value(r.raw_data ->> 'subtype') = v_token)
              OR
              (p_raw_field = 'stamp'
               AND jsonb_typeof(r.raw_data -> 'stamp') = 'array'
               AND EXISTS (
                   SELECT 1 FROM jsonb_array_elements_text(r.raw_data -> 'stamp') e3
                    WHERE public.normalize_external_catalog_value(e3) = v_token
               ))
          )
    ),
    classified AS (
        SELECT t.id,
               t.job_id,
               t.printing_profile_id,
               t.edition_context_profile_id,
               lk.variant_type_id,
               -- v2.0: o outcome passa a depender dos DOIS eixos.
               --
               --   C  →  QUALQUER eixo indeterminado. As três chaves são
               --         removidas e a linha vai para NEEDS_REVIEW. Um eixo
               --         indeterminado torna o residual não confiável: o
               --         token do eixo não resolvido continua dentro dele.
               --   A  →  ambos terminais E Variant Type encontrado.
               --   B  →  ambos terminais, Variant Type ainda não mapeado.
               --
               -- Os dois testes são simétricos DE PROPÓSITO. Tratar Contexto
               -- de Edição como "menos bloqueante" que Impressão reintroduziria
               -- exatamente a assimetria que este pacote existe para eliminar.
               CASE
                 WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                      THEN 'C'
                 WHEN t.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE')
                      THEN 'C'
                 WHEN lk.variant_type_id IS NOT NULL
                      THEN 'A'
                 ELSE 'B'
               END AS outcome,
               -- Desdobramento da causa, para o metadata. Note que a ordem do
               -- CASE acima faz Impressão ter precedência: uma linha com os
               -- DOIS eixos indeterminados é contada como bloqueio de
               -- Impressão, não de Contexto. Isso é deliberado — o operador
               -- resolve Impressão primeiro; contar duas vezes inflaria o
               -- total e quebraria o gate de contadores.
               (t.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                AND t.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE'))
                   AS blocked_by_edition_context
        FROM touched t
        LEFT JOIN LATERAL (
            SELECT internal.lookup_variant_type_for_row(
                       v_game_id, v_asset_source_id, t.card_set_id,
                       t.residual_type, t.residual_foil,
                       t.residual_subtype, t.residual_stamp
                   ) AS variant_type_id
        ) lk ON TRUE
    ),
    updated AS (
        UPDATE public.catalog_variant_import_row r
        SET normalized_data =
                CASE c.outcome
                    -- ---------------------------------------------------------
                    -- A — identidade completa. As TRÊS chaves são gravadas na
                    -- mesma expressão: não existe estado intermediário em que
                    -- a linha tenha duas chaves e a terceira ausente.
                    -- ---------------------------------------------------------
                    WHEN 'A' THEN
                        jsonb_set(
                            jsonb_set(
                                jsonb_set(r.normalized_data,
                                          '{variant_type_id}',
                                          to_jsonb(c.variant_type_id::TEXT), true),
                                '{printing_profile_id}',
                                CASE WHEN c.printing_profile_id IS NULL
                                     THEN 'null'::JSONB
                                     ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                true),
                            '{edition_context_profile_id}',
                            CASE WHEN c.edition_context_profile_id IS NULL
                                 THEN 'null'::JSONB
                                 ELSE to_jsonb(c.edition_context_profile_id::TEXT) END,
                            true)
                    -- ---------------------------------------------------------
                    -- B — eixos resolvidos, Variant Type ainda não mapeado.
                    -- As duas chaves de eixo são gravadas (o trabalho feito é
                    -- preservado e fica visível ao revisor); variant_type_id é
                    -- removida. `JSON null` aqui é AFIRMAÇÃO — "resolvido, sem
                    -- Contexto de Edição" — nunca placeholder.
                    -- ---------------------------------------------------------
                    WHEN 'B' THEN
                        jsonb_set(
                            jsonb_set(
                                r.normalized_data - 'variant_type_id',
                                '{printing_profile_id}',
                                CASE WHEN c.printing_profile_id IS NULL
                                     THEN 'null'::JSONB
                                     ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                true),
                            '{edition_context_profile_id}',
                            CASE WHEN c.edition_context_profile_id IS NULL
                                 THEN 'null'::JSONB
                                 ELSE to_jsonb(c.edition_context_profile_id::TEXT) END,
                            true)
                    -- ---------------------------------------------------------
                    -- C — algum eixo indeterminado. TODAS as chaves saem.
                    -- Chave AUSENTE ≠ `JSON null`: ausente significa "eixo não
                    -- avaliado/indeterminado"; `JSON null` significa "avaliado,
                    -- sem perfil". Manter uma chave antiga aqui seria afirmar
                    -- um resultado que esta passada não apurou.
                    -- ---------------------------------------------------------
                    ELSE
                        ((r.normalized_data - 'variant_type_id')
                                            - 'printing_profile_id')
                                            - 'edition_context_profile_id'
                END,
            validation_status =
                CASE c.outcome WHEN 'A' THEN 'VALID' ELSE 'NEEDS_REVIEW' END
        FROM classified c
        WHERE r.id = c.id
        RETURNING r.id, r.job_id, c.outcome, c.blocked_by_edition_context
    )
    SELECT
        (SELECT count(*) FROM updated WHERE outcome = 'A'),
        (SELECT count(*) FROM updated WHERE outcome IN ('B', 'C')),
        (SELECT count(DISTINCT job_id) FROM updated),
        (SELECT count(*) FROM touched),
        (SELECT count(*) FROM updated),
        (SELECT count(*) FROM updated WHERE blocked_by_edition_context)
      INTO v_rows_updated, v_rows_pending, v_jobs_affected,
           v_touched_total, v_reconciled_total, v_blocked_ec;

    -- Gate 1 — PRESERVADO. Nenhuma linha atingida pode ficar sem estado
    -- terminal definido. O outcome C é um estado terminal desta passada
    -- (NEEDS_REVIEW com chaves removidas), não uma linha "esquecida".
    IF v_reconciled_total IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
            v_touched_total, v_reconciled_total;
    END IF;

    -- Gate 2 — PRESERVADO, e continua verdadeiro em v2.0: o bloqueio por
    -- Contexto de Edição cai em outcome 'C', que já está dentro de
    -- v_rows_pending. A soma não muda de forma.
    IF (v_rows_updated + v_rows_pending) IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
            v_rows_updated, v_rows_pending, v_touched_total;
    END IF;

    -- Gate 3 — NOVO em v2.0. O desdobramento por causa não pode exceder o
    -- total pendente. Se exceder, o CASE de `blocked_by_edition_context`
    -- divergiu do CASE de `outcome` — defeito de código, não de dado.
    IF v_blocked_ec > v_rows_pending THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_CAUSE_GAP: rows_blocked_edition_context (%) > rows_still_pending (%). A classificacao por causa divergiu da classificacao por outcome.',
            v_blocked_ec, v_rows_pending;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
            'CARD_PRINTING_EXTERNAL_MAPPING', v_new_mapping_id,
            jsonb_build_object(
                'game_id', v_game_id, 'asset_source_id', v_asset_source_id,
                'raw_field', p_raw_field, 'external_token', p_token, 'normalized_token', v_token,
                'trait_ids', to_jsonb(v_signature),
                'supersedes_mapping_id', v_old_mapping_id,
                'origin_row_id', p_row_id,
                'rows_revalidated', v_rows_updated,
                'rows_still_pending', v_rows_pending,
                'rows_blocked_edition_context', v_blocked_ec,
                'axes_contract', 'resolve_variant_row_axes/v1',
                'jobs_affected', v_jobs_affected
            )
        );

    RETURN QUERY SELECT v_new_mapping_id, v_old_mapping_id,
                        v_rows_updated, v_rows_pending, v_jobs_affected;
END;
$printing$;


COMMENT ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) IS
'v2.1 (EDITION-CONTEXT-AXIS + SOURCE-SCOPE-CORRECTION-01). Cria o mapeamento externo de Impressao para um token e reavalia, na mesma transacao, as linhas STAGED que o contem.
A reavaliacao usa internal.resolve_variant_row_axes() — TRES eixos. Uma linha so e promovida a VALID quando Impressao E Contexto de Edicao estao terminalmente resolvidos e o Variant Type e encontrado pelo residual pos-dois-eixos.
O escopo (4o argumento do routing) vem de internal.resolve_variant_mapping_scope(card_set_id, asset_source_id) — identificador EXTERNO da Fonte, nunca card_set.code.
Contrato tri-state de normalized_data: chave AUSENTE = eixo indeterminado; JSON null = resolvido sem perfil; string UUID = resolvido com perfil. O outcome C remove as tres chaves.
A logica de Impressao (supersede + insert do mapping) e identica a v1.2.';


-- ACL preservada por CREATE OR REPLACE. Ainda assim os REVOKE/GRANT são
-- repetidos abaixo, exatamente como na 2181 v1.2 — ver justificativa lá:
-- numa INSTALAÇÃO LIMPA a função nasceria sem ACL explícita e divergiria do
-- LIVE (EXECUTE só para authenticated, nenhum grant para anon/PUBLIC).
REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) TO authenticated;


-- ---------------------------------------------------------------------------
-- POSTCHECK 1 — o corpo NÃO pode mais conter chamada direta a 2176.
-- Prova negativa do item 6 do mandato, verificável no banco e não só no diff.
-- ---------------------------------------------------------------------------
DO $post1$
DECLARE
    v_oid REGPROCEDURE;
    v_src TEXT;
BEGIN
    -- IDENTIFICACAO POR OID (FUNCTION-IDENTITY-GATE-CORRECTION-01). O alvo e
    -- resolvido ANTES da leitura e a ausencia FALHA EXPLICITAMENTE. Com o
    -- predicado textual anterior o SELECT nao encontrava linha, v_src ficava
    -- NULL, e `NULL LIKE '%...%'` devolve NULL — de modo que TODO este
    -- postcheck passava sem verificar coisa alguma. PASS vacuoso e proibido.
    v_oid := to_regprocedure('public.admin_resolve_catalog_variant_import_printing_mapping(uuid,text,text,uuid[])');

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_A0: alvo public.admin_resolve_catalog_variant_import_printing_mapping(uuid, text, text, uuid[]) nao resolvido apos o CREATE OR REPLACE. Nenhuma prova de routing pode ser considerada satisfeita.';
    END IF;

    SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = v_oid;

    IF NOT FOUND OR v_src IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_A1: prosrc do alvo nao pode ser lido (oid: %). Postcheck de routing NAO satisfeito.', v_oid;
    END IF;

    IF v_src LIKE '%compute_variant_residual_signature%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_A: o corpo ainda chama compute_variant_residual_signature diretamente. O eixo de Contexto de Edicao seria ignorado nesta funcao.';
    END IF;

    IF v_src NOT LIKE '%resolve_variant_row_axes%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_B: o corpo nao chama resolve_variant_row_axes.';
    END IF;

    IF v_src NOT LIKE '%edition_context_profile_id%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_C: o corpo nao grava a chave edition_context_profile_id.';
    END IF;
END
$post1$;

-- ---------------------------------------------------------------------------
-- POSTCHECK 2 — a ACL tem de ser exatamente a esperada.
-- ---------------------------------------------------------------------------
DO $post2$
DECLARE
    v_oid REGPROCEDURE;
    v_acl TEXT;
BEGIN
    -- IDENTIFICACAO POR OID (FUNCTION-IDENTITY-GATE-CORRECTION-01). Mesma
    -- classe de defeito do POSTCHECK 1: alvo nao encontrado deixava v_acl
    -- NULL e as duas comparacoes LIKE devolviam NULL, aprovando a ACL sem
    -- jamais te-la lido. Aqui a ausencia FALHA.
    v_oid := to_regprocedure('public.admin_resolve_catalog_variant_import_printing_mapping(uuid,text,text,uuid[])');

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_D0: alvo public.admin_resolve_catalog_variant_import_printing_mapping(uuid, text, text, uuid[]) nao resolvido. A ACL NAO foi verificada.';
    END IF;

    SELECT COALESCE(array_to_string(p.proacl, ','), '<null>') INTO v_acl
      FROM pg_proc p WHERE p.oid = v_oid;

    IF NOT FOUND OR v_acl IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_D1: proacl do alvo nao pode ser lida (oid: %). Postcheck de ACL NAO satisfeito.', v_oid;
    END IF;

    IF v_acl LIKE '%anon=%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_D: a role anon tem EXECUTE nesta funcao (acl: %).', v_acl;
    END IF;

    IF v_acl NOT LIKE '%authenticated=X%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_E: a role authenticated nao tem EXECUTE nesta funcao (acl: %).', v_acl;
    END IF;
END
$post2$;

-- ---------------------------------------------------------------------------
-- POSTCHECK 3 — não pode existir sobrecarga desta função.
-- ---------------------------------------------------------------------------
DO $post3$
DECLARE
    v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_resolve_catalog_variant_import_printing_mapping';

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2221_F: existem % sobrecargas de admin_resolve_catalog_variant_import_printing_mapping; esperado exatamente 1.', v_n;
    END IF;
END
$post3$;

COMMIT;
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
