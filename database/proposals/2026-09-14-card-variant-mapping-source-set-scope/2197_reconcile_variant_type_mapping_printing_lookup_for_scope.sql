/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2197 - Reconcile Printing Mapping Resolver
              (CONSUMIDOR 2) para Source-Set Scope
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE em 2026-09-14 (GATE-B-EXECUTION-01)
              Baseline pre-apply conferida: md5 2063b34d552766ff8cb220c9c6099f40.
              Pos-apply conferida: md5 b98f96a287f7c4d270c4239433bb6f2c,
              length 12.524 — os dois valores previstos no bloco VERIFICACAO
              do rodape. Diff exaustivo provado por igualdade de hash.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
              SOURCE-SET-SCOPED-FOUNDATION / GATE-A-REV-01 §6

Descrição...:
Segundo (e último) consumidor SQL do mapping de Card Variant Type
a passar a enxergar escopo:

    public.admin_resolve_catalog_variant_import_printing_mapping()

================================================================
PROVENIÊNCIA DO CORPO — MECÂNICA, NÃO DE MEMÓRIA
================================================================
O corpo abaixo NÃO foi transcrito à mão. Foi derivado do LIVE por
transformação textual verificada dentro do próprio PostgreSQL:

    s_novo := replace(replace(replace(replace(
                  prosrc, o1,n1), o2,n2), o3,n3), o4,n4)

BASELINE LIVE (medida em 2026-09-14, read-only):

    prosrc  linhas ...... 272
    prosrc  caracteres .. 12.644
    md5(prosrc) ......... 2063b34d552766ff8cb220c9c6099f40

RESULTADO DA TRANSFORMAÇÃO (o corpo deste arquivo):

    linhas .............. 272
    caracteres .......... 12.524
    md5 ................. b98f96a287f7c4d270c4239433bb6f2c

PROVA DE UNICIDADE — cada trecho antigo ocorre EXATAMENTE 1 vez
no prosrc LIVE (medido por length/replace, não por inspeção):

    occ(o1) = 1   occ(o2) = 1   occ(o3) = 1   occ(o4) = 1

PROVA DE EXAUSTÃO — após a transformação, no corpo inteiro:

    referências remanescentes a 'vm.' ............................... 0
    referências a 'card_variant_type_external_mapping' .............. 0

PROVA DE EQUIVALÊNCIA — o corpo literal deste arquivo foi devolvido
ao PostgreSQL e comparado por md5 contra s_novo. Ver o bloco
`VERIFICAÇÃO` no rodapé para as queries reexecutáveis.

HIGIENE DO CORPO (medida, não presumida): o prosrc não contém
aspas duplas, backslash, TAB, CR nem espaço à direita em nenhuma
linha; começa e termina com newline. Por isso a reconstrução é
segura e não introduz ruído invisível.

CONFRONTO LIVE × ARTEFATO CANÔNICO — exigido pelo §6:
`database/schema/2181_create_admin_resolve_printing_mapping_function.sql`
apresenta, nas linhas 517, 557, 561 e 566, exatamente as mesmas
quatro âncoras que o LIVE apresenta nas linhas 155, 186, 190 e 195
do prosrc. **Não há divergência LIVE × base esperada.** Nenhuma
condição de STOP do §6 foi disparada.

================================================================
DIFF AUTORIZADO — QUATRO SUBSTITUIÇÕES, E SÓ QUATRO
================================================================
Numeração relativa ao prosrc LIVE.

--- DIFF 1 (linha 155) — `touched` passa a expor card_set_id -----
-        SELECT r.id, r.job_id, s.*
+        SELECT r.id, r.job_id, j.card_set_id, s.*

`j` já está no FROM (linha 157). Nenhum JOIN novo, nenhuma linha a
mais no universo. A coluna extra é consumida só pelo DIFF 4.

--- DIFF 2 (linha 186) — projeção do CTE classified --------------
-               vm.variant_type_id,
+               lk.variant_type_id,

--- DIFF 3 (linha 190) — condição do outcome 'A' ------------------
-                 WHEN vm.variant_type_id IS NOT NULL
+                 WHEN lk.variant_type_id IS NOT NULL

--- DIFF 4 (linhas 195-201) — lookup direto vira helper -----------
-        LEFT JOIN public.card_variant_type_external_mapping vm
-          ON vm.game_id = v_game_id
-         AND vm.asset_source_id = v_asset_source_id
-         AND vm.normalized_type = t.residual_type
-         AND COALESCE(vm.normalized_foil, '')    = COALESCE(t.residual_foil, '')
-         AND COALESCE(vm.normalized_subtype, '') = COALESCE(t.residual_subtype, '')
-         AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(t.residual_stamp, '{}'::TEXT[])
+        LEFT JOIN LATERAL (
+            SELECT internal.lookup_variant_type_for_row(
+                       v_game_id, v_asset_source_id, t.card_set_id,
+                       t.residual_type, t.residual_foil,
+                       t.residual_subtype, t.residual_stamp
+                   ) AS variant_type_id
+        ) lk ON TRUE

DIFFs 2 e 3 são consequência sintática obrigatória do DIFF 4 (o
alias deixou de existir), não decisões independentes. Os quatro
juntos são UM diff semântico: "o lookup direto passa a usar
internal.lookup_variant_type_for_row()".

CARDINALIDADE — LATERAL sobre função escalar devolve exatamente
uma linha, NULL inclusive. Nenhuma row de `touched` é perdida nem
duplicada. O predicado do JOIN antigo era conjuntivo e resolvia no
máximo uma linha do mapping (garantido pelo UNIQUE do combo), logo
a substituição preserva a cardinalidade 1:1 anterior. O helper é
avaliado UMA vez por row — mesma correção aplicada ao Consumidor 1
na Query 2196 por este mesmo mandato.

TUDO O MAIS É BYTE-IDÊNTICO AO LIVE. Permanecem intocados: os
guards de p_raw_field / p_trait_ids / traits inativos / Game /
Fonte, a prova de token na linha de origem
(`PRINTING_MAPPING_ORIGIN_TOKEN_NOT_FOUND`), o `FOR UPDATE` do
mapping ativo, o supersede (`is_active=FALSE` +
`supersedes_mapping_id`), o INSERT em
`card_printing_external_mapping_trait`, o universo de `touched`
(STAGED · decision=PENDING · validation IN (VALID, NEEDS_REVIEW)),
os três outcomes A/B/C, o UPDATE de `normalized_data`, os guards
`RECONCILIATION_GAP` / `COUNTER_GAP`, o action log
`CARD_PRINTING_EXTERNAL_MAPPING_CREATED` e o RETURN QUERY.

>>> ESTA FUNÇÃO CONTINUA SEM FILTRAR persistence_status, SEM
    CHECAR resulting_variant_id E SEM RECALCULAR COUNTERS. <<<
É o contrato divergente já registrado como dívida D-1 no README.
Corrigi-lo AQUI seria um quinto diff não autorizado, escondido
dentro de uma Query cujo escopo é escopo de mapping. Fica
registrado e separado.

Pré-requisitos:
- Query 2191 — coluna/índices de escopo.
- Query 2196 — internal.lookup_variant_type_for_row().
- Query 2181 — versão vigente desta função (baseline do diff).
================================================================
*/

BEGIN;

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

    WITH touched AS (
        SELECT r.id, r.job_id, j.card_set_id, s.*
        FROM public.catalog_variant_import_row r
        JOIN public.catalog_variant_import_job j ON j.id = r.job_id
        CROSS JOIN LATERAL internal.compute_variant_residual_signature(
            r.raw_data, v_game_id, v_asset_source_id
        ) s
        WHERE j.status = 'STAGED'
          AND j.source = v_job_source
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
                   SELECT 1 FROM jsonb_array_elements_text(r.raw_data -> 'stamp') e
                    WHERE public.normalize_external_catalog_value(e) = v_token
               ))
          )
    ),
    classified AS (
        SELECT t.id,
               t.job_id,
               t.printing_profile_id,
               lk.variant_type_id,
               CASE
                 WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                      THEN 'C'
                 WHEN lk.variant_type_id IS NOT NULL
                      THEN 'A'
                 ELSE 'B'
               END AS outcome
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
                    WHEN 'A' THEN
                        jsonb_set(
                            jsonb_set(r.normalized_data,
                                      '{variant_type_id}',
                                      to_jsonb(c.variant_type_id::TEXT), true),
                            '{printing_profile_id}',
                            CASE WHEN c.printing_profile_id IS NULL
                                 THEN 'null'::JSONB
                                 ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                            true)
                    WHEN 'B' THEN
                        jsonb_set(
                            r.normalized_data - 'variant_type_id',
                            '{printing_profile_id}',
                            CASE WHEN c.printing_profile_id IS NULL
                                 THEN 'null'::JSONB
                                 ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                            true)
                    ELSE
                        (r.normalized_data - 'variant_type_id') - 'printing_profile_id'
                END,
            validation_status =
                CASE c.outcome WHEN 'A' THEN 'VALID' ELSE 'NEEDS_REVIEW' END
        FROM classified c
        WHERE r.id = c.id
        RETURNING r.id, r.job_id, c.outcome
    )
    SELECT
        (SELECT count(*) FROM updated WHERE outcome = 'A'),
        (SELECT count(*) FROM updated WHERE outcome IN ('B', 'C')),
        (SELECT count(DISTINCT job_id) FROM updated),
        (SELECT count(*) FROM touched),
        (SELECT count(*) FROM updated)
      INTO v_rows_updated, v_rows_pending, v_jobs_affected,
           v_touched_total, v_reconciled_total;

    IF v_reconciled_total IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
            v_touched_total, v_reconciled_total;
    END IF;

    IF (v_rows_updated + v_rows_pending) IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
            v_rows_updated, v_rows_pending, v_touched_total;
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
                'jobs_affected', v_jobs_affected
            )
        );

    RETURN QUERY SELECT v_new_mapping_id, v_old_mapping_id,
                        v_rows_updated, v_rows_pending, v_jobs_affected;
END;
$printing$;

-- ACL preservada por CREATE OR REPLACE. Os REVOKE/GRANT da Query
-- 2181 NÃO são repetidos aqui, pelo mesmo motivo da Query 2190:
-- repeti-los mascararia uma eventual perda de ACL que o postcheck
-- precisa ser capaz de detectar.

COMMIT;

/*
================================================================
VERIFICAÇÃO — reexecutável, read-only
================================================================
GATE-B, ANTES de aplicar este arquivo:

    SELECT md5(p.prosrc) = '2063b34d552766ff8cb220c9c6099f40' AS baseline_ok
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_resolve_catalog_variant_import_printing_mapping';

Se baseline_ok = FALSE, a função mudou entre o staging e a
aplicação: **STOP** e rebasear o diff. O harness 2826 carrega o
caso AA dedicado a esta checagem.

GATE-B, DEPOIS de aplicar:

    SELECT md5(p.prosrc) = 'b98f96a287f7c4d270c4239433bb6f2c' AS resultado_ok,
           length(p.prosrc) = 12524                           AS tamanho_ok
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_resolve_catalog_variant_import_printing_mapping';

Ambos TRUE ⟹ o corpo aplicado é exatamente o prosrc anterior com
os quatro diffs declarados, e nada mais. É prova de diff exaustivo
por igualdade de hash — não por leitura visual.
================================================================
CONFIRMADO EXECUTADO em 2026-09-14 (GATE-B-EXECUTION-01). As duas checagens
acima foram rodadas de verdade: baseline_ok = TRUE antes, resultado_ok = TRUE
e tamanho_ok = TRUE depois. Cópia mantida em proposals/ como evidência
histórica do ciclo.
================================================================
*/
