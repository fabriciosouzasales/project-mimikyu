/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2150 - Create admin_resolve_catalog_variant_import_mapping() Function
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_resolve_catalog_variant_import_mapping(), função pública
SECURITY DEFINER — permite ao administrador resolver, a partir de
uma linha NEEDS_REVIEW de catalog_variant_import_row (Query 2138),
uma combinação externa (type/foil/subtype/stamp) sem mapeamento,
associando-a a um card_variant_type canônico já existente. Cadastra
o mapeamento em card_variant_type_external_mapping (Query 2140) e
revalida, no mesmo statement, todas as linhas NEEDS_REVIEW
compatíveis em qualquer job ainda revisável do mesmo Game+Fonte —
mesmo espírito de admin_create_rarity_external_mapping() (Query
2101), mas com revalidação embutida (lá, a revalidação de
catalog_import_row é feita por uma Edge Function separada,
revalidate-catalog-import-rows, porque depende de lógica adicional
em TypeScript — aqui a resolução é puramente relacional, cabe
inteira numa função SQL).

Diferença deliberada frente à revalidação de raridade: o mapeamento
recém-criado é canônico para Game+Fonte+combinação — não apenas
para o job que originou a ação (decisão explícita de Fabrício,
2026-08-15). Por isso a revalidação aqui é cross-job/cross-Card Set
dentro do mesmo Game+Fonte, não restrita ao job_id da linha
original: resolver holo+cosmos->COSMOS_HOLO uma única vez destrava
automaticamente qualquer outro staging já existente com a mesma
combinação, em qualquer Card Set daquele Game+Fonte.

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- Só aceita linhas com validation_status = 'NEEDS_REVIEW' —
  resolver uma linha já VALID não faz sentido (já tem mapeamento).
- game_id é resolvido a partir da própria linha (card -> card_set ->
  expansion -> game), nunca recebido como parâmetro — elimina a
  possibilidade de o chamador informar um Game divergente do real.
  asset_source_id é resolvido a partir de catalog_variant_import_job
  .source (hoje sempre 'TCGDEX') -> asset_source.code.
- p_variant_type_id deve pertencer ao mesmo game_id resolvido acima
  (ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_VARIANT_TYPE_MISMATCH)
  — nunca aceita silenciosamente um cruzamento entre Games. Esta
  função NUNCA cria um card_variant_type novo — só associa a um já
  existente (fora de escopo: CRUD de card_variant_type é incremento
  futuro).
- type/foil/subtype/stamp são extraídos de raw_data (preservado
  integralmente, nunca reinterpretado) e normalizados exatamente
  pela mesma disciplina de quem grava a seed/processador (Query
  2140 v1.1): normalize_external_catalog_value() nos três campos de
  texto; stamp normalizado elemento a elemento e ORDENADO, tratando
  a combinação como conjunto, não sequência.
- Verificação explícita de duplicidade contra o índice único de
  combinação (uq_card_variant_type_external_mapping_combo, Query
  2140) antes do INSERT, com erro dedicado — mesmo padrão de
  admin_create_rarity_external_mapping (Query 2101).
- Revalidação set-based, um único UPDATE (sem loop, sem N+1):
  atualiza normalized_data.variant_type_id e validation_status =
  'VALID' em toda catalog_variant_import_row cuja combinação
  normalizada bate com a recém-mapeada, restrita a:
  (a) mesmo game_id (via job.card_set_id -> expansion.game_id) e
      mesmo asset_source_id (via job.source);
  (b) job.status = 'STAGED' — "job ainda revisável". Um job só
      permanece STAGED enquanto tiver alguma linha com decision_
      status = 'PENDING' (admin_confirm_catalog_variant_import,
      Query 2145, força o status para STAGED sempre que houver
      decision_pending_rows > 0) — logo esta condição já é, por
      construção, equivalente a "ainda tem linha pendente de
      decisão", mas é mantida explícita por defesa em profundidade;
  (c) row.decision_status = 'PENDING' — deliberado: uma linha
      NEEDS_REVIEW já REJECTED/SKIPPED teve uma decisão humana
      final registrada; não é silenciosamente reescrita para VALID
      só porque um mapeamento surgiu depois (o rótulo de decisão já
      resolveu o destino dela, independente da validação).
  match_status NUNCA é tocado aqui — admin_confirm_catalog_variant_
  import() (Query 2145) já recalcula match_status contra
  public.card_variant real no momento da confirmação, nunca herda
  do processamento/revalidação (mesmo raciocínio já documentado na
  Query 2145).
- Jobs futuros (ainda não criados) não precisam de nenhuma ação
  aqui: o processador (import-card-variants) já consulta
  card_variant_type_external_mapping no momento da geração — uma
  vez cadastrado o mapeamento, toda nova execução nasce VALID
  automaticamente para essa combinação.
- Nunca escreve em public.card_variant — só staging
  (catalog_variant_import_row) e o próprio mapeamento.
- Grava catalog_admin_action_log
  (CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED) — ação habilitada
  pela Query 2151, com rows_updated/jobs_affected no metadata para
  auditoria do alcance real da resolução.
- Retorna mapping_id, rows_updated e jobs_affected (contagem
  distinta de jobs cujas linhas foram revalidadas) — a UI usa os
  dois últimos para informar ao administrador o alcance real da
  resolução ("N linhas em M jobs foram destravadas").

Pré-requisitos:
- Query 2095 - Create normalize_external_catalog_value() Function.
- Query 2136/2138 - Create Catalog Variant Import Job/Row Tables.
- Query 2140 - Create card_variant_type_external_mapping Table.
- Query 2151 - Widen Catalog Admin Action Log for Variant Mapping.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_mapping(
    p_row_id UUID,
    p_variant_type_id UUID
)
RETURNS TABLE (
    mapping_id UUID,
    rows_updated INTEGER,
    jobs_affected INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_job_source TEXT;
    v_game_id UUID;
    v_asset_source_id UUID;
    v_type TEXT;
    v_foil TEXT;
    v_subtype TEXT;
    v_stamp TEXT[];
    v_normalized_type TEXT;
    v_normalized_foil TEXT;
    v_normalized_subtype TEXT;
    v_normalized_stamp TEXT[];
    v_mapping_id UUID;
    v_rows_updated INTEGER;
    v_jobs_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_FORBIDDEN: apenas administradores podem resolver um mapeamento de variante.';
    END IF;

    IF p_row_id IS NULL OR p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_MISSING_IDS: p_row_id e p_variant_type_id são obrigatórios.';
    END IF;

    SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_ROW_NOT_FOUND: nenhuma linha encontrada para o id informado (%).', p_row_id;
    END IF;

    SELECT j.source INTO v_job_source FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;

    IF v_job_source IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_JOB_NOT_FOUND: não foi possível resolver o job desta linha.';
    END IF;

    IF v_row.validation_status <> 'NEEDS_REVIEW' THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_NOT_NEEDS_REVIEW: só linhas sem mapeamento (NEEDS_REVIEW) podem ser resolvidas por aqui.';
    END IF;

    -- game_id resolvido a partir da própria linha (card -> card_set ->
    -- expansion -> game) — nunca recebido como parâmetro.
    SELECT e.game_id INTO v_game_id
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    WHERE c.id = v_row.card_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_GAME_NOT_FOUND: não foi possível resolver o Game desta linha.';
    END IF;

    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = v_job_source;

    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_SOURCE_NOT_FOUND: nenhuma Fonte encontrada para o código % do job desta linha.', v_job_source;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_variant_type WHERE id = p_variant_type_id AND game_id = v_game_id) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_VARIANT_TYPE_MISMATCH: o Card Variant Type informado não existe ou não pertence ao Game desta combinação.';
    END IF;

    v_type := v_row.raw_data ->> 'type';
    v_foil := v_row.raw_data ->> 'foil';
    v_subtype := v_row.raw_data ->> 'subtype';

    IF v_type IS NULL OR btrim(v_type) = '' THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_MISSING_TYPE: raw_data.type ausente nesta linha — dado inconsistente.';
    END IF;

    IF jsonb_typeof(v_row.raw_data -> 'stamp') = 'array' THEN
        SELECT array_agg(elem) INTO v_stamp FROM jsonb_array_elements_text(v_row.raw_data -> 'stamp') elem;
    ELSE
        v_stamp := NULL;
    END IF;

    v_normalized_type := public.normalize_external_catalog_value(v_type);
    v_normalized_foil := CASE WHEN v_foil IS NULL THEN NULL ELSE public.normalize_external_catalog_value(v_foil) END;
    v_normalized_subtype := CASE WHEN v_subtype IS NULL THEN NULL ELSE public.normalize_external_catalog_value(v_subtype) END;

    IF v_stamp IS NULL THEN
        v_normalized_stamp := NULL;
    ELSE
        SELECT array_agg(public.normalize_external_catalog_value(elem) ORDER BY public.normalize_external_catalog_value(elem))
            INTO v_normalized_stamp
            FROM unnest(v_stamp) AS elem;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card_variant_type_external_mapping
        WHERE game_id = v_game_id
          AND asset_source_id = v_asset_source_id
          AND normalized_type = v_normalized_type
          AND COALESCE(normalized_foil, '') = COALESCE(v_normalized_foil, '')
          AND COALESCE(normalized_subtype, '') = COALESCE(v_normalized_subtype, '')
          AND COALESCE(normalized_stamp, '{}'::TEXT[]) = COALESCE(v_normalized_stamp, '{}'::TEXT[])
    ) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_DUPLICATE: já existe um mapeamento para esta combinação nesta Fonte/Game.';
    END IF;

    INSERT INTO public.card_variant_type_external_mapping (
        game_id, asset_source_id,
        external_type, external_foil, external_subtype, external_stamp,
        normalized_type, normalized_foil, normalized_subtype, normalized_stamp,
        variant_type_id
    ) VALUES (
        v_game_id, v_asset_source_id,
        v_type, v_foil, v_subtype, v_stamp,
        v_normalized_type, v_normalized_foil, v_normalized_subtype, v_normalized_stamp,
        p_variant_type_id
    ) RETURNING id INTO v_mapping_id;

    -- Revalidação set-based, cross-job/cross-Card Set dentro do mesmo
    -- Game+Fonte — o mapeamento é canônico, não fica preso ao job que
    -- originou a resolução (decisão explícita de Fabrício, 2026-08-15).
    WITH updated AS (
        UPDATE public.catalog_variant_import_row r
        SET normalized_data = jsonb_set(r.normalized_data, '{variant_type_id}', to_jsonb(p_variant_type_id::TEXT), true),
            validation_status = 'VALID'
        FROM public.catalog_variant_import_job j
        WHERE r.job_id = j.id
          AND j.status = 'STAGED'
          AND j.source = v_job_source
          AND j.card_set_id IN (
              SELECT cs2.id FROM public.card_set cs2
              JOIN public.expansion e2 ON e2.id = cs2.expansion_id
              WHERE e2.game_id = v_game_id
          )
          AND r.decision_status = 'PENDING'
          AND r.validation_status = 'NEEDS_REVIEW'
          AND public.normalize_external_catalog_value(r.raw_data ->> 'type') = v_normalized_type
          AND COALESCE(
                CASE WHEN r.raw_data ->> 'foil' IS NULL THEN NULL ELSE public.normalize_external_catalog_value(r.raw_data ->> 'foil') END,
                ''
              ) = COALESCE(v_normalized_foil, '')
          AND COALESCE(
                CASE WHEN r.raw_data ->> 'subtype' IS NULL THEN NULL ELSE public.normalize_external_catalog_value(r.raw_data ->> 'subtype') END,
                ''
              ) = COALESCE(v_normalized_subtype, '')
          AND COALESCE(
                (
                    SELECT array_agg(public.normalize_external_catalog_value(elem) ORDER BY public.normalize_external_catalog_value(elem))
                    FROM jsonb_array_elements_text(
                        CASE WHEN jsonb_typeof(r.raw_data -> 'stamp') = 'array' THEN r.raw_data -> 'stamp' ELSE '[]'::JSONB END
                    ) elem
                ),
                '{}'::TEXT[]
              ) = COALESCE(v_normalized_stamp, '{}'::TEXT[])
        RETURNING r.id, r.job_id
    )
    SELECT count(*), count(DISTINCT job_id) INTO v_rows_updated, v_jobs_affected FROM updated;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED', 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', v_mapping_id,
            jsonb_build_object(
                'game_id', v_game_id, 'asset_source_id', v_asset_source_id, 'variant_type_id', p_variant_type_id,
                'external_type', v_type, 'external_foil', v_foil, 'external_subtype', v_subtype, 'external_stamp', v_stamp,
                'origin_row_id', p_row_id, 'rows_updated', v_rows_updated, 'jobs_affected', v_jobs_affected
            )
        );

    RETURN QUERY SELECT v_mapping_id, v_rows_updated, v_jobs_affected;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- contra dado real (job BASEP cf829d56-..., job SV10 cf38d2ea-...):
-- chamador não-admin -> FORBIDDEN; caso obrigatório holo+cosmos ->
-- COSMOS_HOLO resolveu rows_updated=10/jobs_affected=2, confirmado por
-- SELECT independente (10/10 linhas VALID com o variant_type_id
-- correto); linha com a mesma combinação MAIS stamp:eb-games
-- corretamente NÃO tocada (combinação diferente, permanece
-- NEEDS_REVIEW); segunda tentativa da mesma combinação -> DUPLICATE;
-- catalog_admin_action_log gravado com rows_updated/jobs_affected no
-- metadata. Execução real repetiu a mesma chamada (mapping_id
-- 1558d092-b768-473b-9abf-fc1e869c67af): 3 linhas de BASEP + 7 de
-- SV10 = 10 linhas em 2 jobs, reverificado por SELECT independente
-- pós-commit — a linha SV10 com stamp:eb-games permanece NEEDS_REVIEW,
-- como esperado (não é a mesma combinação externa).
-- role_routine_grants confirma EXECUTE só para 'authenticated' (além
-- do owner 'postgres'), nenhum grant para anon/PUBLIC.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT routine_name, security_type FROM information_schema.routines
-- WHERE routine_name = 'admin_resolve_catalog_variant_import_mapping';
-- Esperado: security_type = 'DEFINER'.
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants
-- WHERE routine_name = 'admin_resolve_catalog_variant_import_mapping';
-- Esperado: só 'authenticated' com EXECUTE, nenhum grant para anon/PUBLIC.
-- ================================================================
