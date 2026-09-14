/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2192 - Create Variant Type Mapping Scope
              READ CONTRACT (scope resolver + impact classifier)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE em 2026-09-14 (GATE-B-EXECUTION-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
              SOURCE-SET-SCOPED-FOUNDATION / GATE-A-STAGING-01

Descrição...:
Duas funções de LEITURA PURA que, juntas, formam o contrato único
de escopo e de impacto. Ficam num único Query porque são
indivisíveis: a segunda não faz sentido sem a primeira, e as duas
existem para que PREVIEW e EXECUTE compartilhem exatamente a
mesma lógica de classificação — nunca duas implementações.

ZERO ESCRITA. Nenhuma das duas altera qualquer linha.

--------------------------------------------------------------
1. internal.resolve_variant_mapping_scope()
--------------------------------------------------------------
Fonte canônica do source-set é `card_set_external_reference`,
NUNCA `catalog_variant_import_job.external_set_id`.

Racional (decisão 4 do mandato): o campo do job é um dado de
operação, gravado pela Edge no momento do import; a referência
canônica é a entidade de catálogo, tem UNIQUE e é o alvo da FK
criada na Query 2191. Confiar no job seria eleger como autoridade
um valor que ninguém garante.

`is_active` participa: só referência ATIVA define escopo.

--------------------------------------------------------------
2. internal.variant_type_mapping_impact()
--------------------------------------------------------------
Classifica o universo alvo em A / B / C e devolve o veredito.

UNIVERSO: rows cuja assinatura RESIDUAL (não bruta) é exatamente
o combo informado, dentro da mesma Fonte + Game, e — quando o
escopo é SOURCE_SET — dentro daquele source-set.

  A  job STAGED
     decision_status    = PENDING
     persistence_status = PENDING
     resulting_variant_id IS NULL
     -> elegível para propagation

  B  qualquer alvo fora de A

  C  identidade canônica já materializada pela interpretação
     anterior

--------------------------------------------------------------
>>> QUANDO O BLOQUEIO DISPARA — REGRA DE DADO, NÃO DE ESCOPO <<<
--------------------------------------------------------------
O guard fail-closed dispara quando o mapping novo MUDA UMA
INTERPRETAÇÃO EFETIVA VIGENTE (`supersedes_interpretation`).

Isso é deliberado e é o que preserva a retrocompatibilidade
exigida pelo §5 do mandato:

- Caminho GLOBAL atual (Query 2150): a RPC recusa criar mapping
  quando já existe um para o combo (DUPLICATE). Logo o mapping
  global nasce SEMPRE sobre um combo SEM interpretação vigente —
  não há drift possível, `supersedes_interpretation` é FALSE, e
  o comportamento continua exatamente o de hoje: linhas fora de
  A são FILTRADAS, não bloqueiam.

- Caminho SOURCE_SET: por definição existe um global vigente que
  o override passa a sobrepor. `supersedes_interpretation` é
  TRUE e o bloqueio fail-closed vale integralmente.

Amarrar o guard ao ESCOPO (e não ao dado) teria sido mais
simples de escrever e errado: um global que um dia superasse
algo ficaria desprotegido.

--------------------------------------------------------------
>>> DETECÇÃO DE C — LIMITE DE PROVENANCE, DECLARADO <<<
--------------------------------------------------------------
Auditado em 2026-09-14: `public.card_variant` tem exatamente
id, card_id, variant_type_id, variant_order, is_default,
created_at, updated_at, printing_profile_id.

NÃO EXISTE COLUNA DE PROVENANCE. A única ligação de origem no
modelo é a inversa: `catalog_variant_import_row.resulting_variant_id`.

Consequências, assumidas explicitamente:

(a) DETECÇÃO EXATA — um card_variant cuja row de origem ainda
    existe e está no universo é detectado sem ambiguidade por
    `resulting_variant_id`. Zero falso positivo.

(b) PONTO CEGO REAL — se as rows de origem tiverem sido
    APAGADAS (precedente concreto: as 410 rows do job CANCELLED
    excluídas em EDITORIAL-CONVERGENCE-09), a provenance some e
    (a) não enxerga mais nada.

(c) GUARD CONSERVADOR para (b) — quando há supersessão e (a)
    devolve zero, verifica-se se existe QUALQUER card_variant
    das cards DAQUELE ESCOPO com o variant_type_id da
    interpretação vigente. Se existir, bloqueia com
    PROVENANCE_INSUFFICIENT.

    Este guard PODE gerar falso positivo — um card_variant do
    mesmo tipo pode ter nascido de outro combo ou de curadoria
    manual. Isso é aceito de propósito: falso positivo custa um
    bloqueio que um humano destrava; falso negativo custaria
    taxonomia mudada por baixo de identidade materializada.
    Fail-closed, como manda o §12.

    O escopo do guard é deliberadamente estreito (cards do
    source-set × variant_type vigente) justamente para não cair
    no falso positivo grosseiro que o §8 do mandato alerta:
    "um card_variant do mesmo tipo/card não significa, sozinho,
    que nasceu daquele combo".

NENHUMA provenance foi inventada. O que não dá para provar está
declarado acima e coberto por guard conservador.

Pré-requisitos:
- Query 2140/2191 - card_variant_type_external_mapping (+ escopo).
- Query 2176 - internal.compute_variant_residual_signature().
- card_set_external_reference com UNIQUE (asset_source_id, external_set_id).
================================================================
*/

BEGIN;

-- =============================================================
-- 1. RESOLVEDOR DE ESCOPO — FONTE CANÔNICA
-- =============================================================

CREATE OR REPLACE FUNCTION internal.resolve_variant_mapping_scope(
    p_card_set_id     UUID,
    p_asset_source_id UUID
)
RETURNS TABLE(
    external_set_id TEXT,
    reference_id    UUID
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT r.external_set_id, r.id
      FROM public.card_set_external_reference r
     WHERE r.card_set_id      = p_card_set_id
       AND r.asset_source_id  = p_asset_source_id
       AND r.is_active
     LIMIT 1;
$$;

COMMENT ON FUNCTION internal.resolve_variant_mapping_scope(UUID, UUID) IS
    'Fonte canonica do source-set scope. Le card_set_external_reference (ativa). NUNCA usar catalog_variant_import_job.external_set_id como autoridade. Zero linha = Set sem referencia externa ativa -> lookup so pode usar GLOBAL, e criacao de override SCOPED deve FALHAR.';

-- =============================================================
-- 2. CLASSIFICADOR DE IMPACTO A / B / C
--
-- Contrato ÚNICO, compartilhado por preview e execute.
-- =============================================================

CREATE OR REPLACE FUNCTION internal.variant_type_mapping_impact(
    p_game_id                UUID,
    p_asset_source_id        UUID,
    p_external_set_id        TEXT,      -- NULL = escopo GLOBAL
    p_residual_type          TEXT,
    p_residual_foil          TEXT,
    p_residual_subtype       TEXT,
    p_residual_stamp         TEXT[],
    p_target_variant_type_id UUID
)
RETURNS TABLE(
    current_effective_mapping_id     UUID,
    current_effective_scope          TEXT,
    current_effective_variant_type_id UUID,
    supersedes_interpretation        BOOLEAN,
    rows_total                       INTEGER,
    rows_class_a                     INTEGER,
    rows_class_b                     INTEGER,
    canonical_class_c                INTEGER,
    rows_valid_reclassified          INTEGER,
    jobs_affected                    INTEGER,
    block_reason                     TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $impact$
DECLARE
    v_src_code   TEXT;
    v_cur_id     UUID;
    v_cur_scope  TEXT;
    v_cur_vt     UUID;
    v_supersedes BOOLEAN;
    v_total      INTEGER := 0;
    v_a          INTEGER := 0;
    v_b          INTEGER := 0;
    v_c          INTEGER := 0;
    v_reclass    INTEGER := 0;
    v_jobs       INTEGER := 0;
    v_prov_risk  BOOLEAN := FALSE;
    v_block      TEXT    := NULL;
BEGIN
    SELECT a.code INTO v_src_code
      FROM public.asset_source a WHERE a.id = p_asset_source_id;

    IF v_src_code IS NULL THEN
        RAISE EXCEPTION 'VARIANT_TYPE_MAPPING_IMPACT_SOURCE_NOT_FOUND: asset_source_id % nao existe.', p_asset_source_id;
    END IF;

    -- ---------------------------------------------------------
    -- 2.1 INTERPRETAÇÃO EFETIVA VIGENTE (antes do novo mapping)
    --     Mesma precedência do lookup de produção: scoped > global.
    -- ---------------------------------------------------------
    SELECT vm.id,
           CASE WHEN vm.external_set_id IS NULL THEN 'GLOBAL' ELSE 'SOURCE_SET' END,
           vm.variant_type_id
      INTO v_cur_id, v_cur_scope, v_cur_vt
      FROM public.card_variant_type_external_mapping vm
     WHERE vm.game_id         = p_game_id
       AND vm.asset_source_id = p_asset_source_id
       AND (vm.external_set_id IS NULL
            OR (p_external_set_id IS NOT NULL AND vm.external_set_id = p_external_set_id))
       AND vm.normalized_type = p_residual_type
       AND COALESCE(vm.normalized_foil, '')          = COALESCE(p_residual_foil, '')
       AND COALESCE(vm.normalized_subtype, '')       = COALESCE(p_residual_subtype, '')
       AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(p_residual_stamp, '{}'::TEXT[])
     ORDER BY (vm.external_set_id IS NULL) ASC
     LIMIT 1;

    v_supersedes := (v_cur_vt IS NOT NULL
                     AND v_cur_vt IS DISTINCT FROM p_target_variant_type_id);

    -- ---------------------------------------------------------
    -- 2.2 UNIVERSO ALVO + PARTIÇÃO A / B
    -- ---------------------------------------------------------
    WITH universo AS (
        SELECT r.id,
               r.job_id,
               r.validation_status,
               r.decision_status,
               r.persistence_status,
               r.resulting_variant_id,
               r.normalized_data,
               j.status AS job_status
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set  cs ON cs.id = j.card_set_id
          JOIN public.expansion e  ON e.id  = cs.expansion_id
          -- escopo: quando SOURCE_SET, a row só entra se o Card Set dela
          -- resolver, pela referência CANÔNICA ATIVA, para o mesmo
          -- external_set_id. Quando GLOBAL, o filtro não se aplica.
          LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, p_asset_source_id) sc ON TRUE
          CROSS JOIN LATERAL internal.compute_variant_residual_signature(
              r.raw_data, e.game_id, p_asset_source_id
          ) sg
         WHERE j.source  = v_src_code
           AND e.game_id = p_game_id
           AND (p_external_set_id IS NULL OR sc.external_set_id = p_external_set_id)
           AND sg.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
           AND sg.residual_type = p_residual_type
           AND COALESCE(sg.residual_foil, '')          = COALESCE(p_residual_foil, '')
           AND COALESCE(sg.residual_subtype, '')       = COALESCE(p_residual_subtype, '')
           AND COALESCE(sg.residual_stamp, '{}'::TEXT[]) = COALESCE(p_residual_stamp, '{}'::TEXT[])
    ),
    classificado AS (
        SELECT u.*,
               (u.job_status = 'STAGED'
                AND u.decision_status    = 'PENDING'
                AND u.persistence_status = 'PENDING'
                AND u.resulting_variant_id IS NULL) AS is_a
          FROM universo u
    )
    SELECT count(*),
           count(*) FILTER (WHERE is_a),
           count(*) FILTER (WHERE NOT is_a),
           count(DISTINCT resulting_variant_id) FILTER (WHERE resulting_variant_id IS NOT NULL),
           count(*) FILTER (WHERE is_a
                              AND validation_status = 'VALID'
                              AND jsonb_typeof(normalized_data->'variant_type_id') = 'string'
                              AND (normalized_data->>'variant_type_id')::UUID
                                  IS DISTINCT FROM p_target_variant_type_id),
           count(DISTINCT job_id) FILTER (WHERE is_a)
      INTO v_total, v_a, v_b, v_c, v_reclass, v_jobs
      FROM classificado;

    -- ---------------------------------------------------------
    -- 2.3 GUARD CONSERVADOR DE PROVENANCE
    --     Só quando há supersessão E a detecção exata deu zero.
    --     Ver bloco dedicado no cabeçalho.
    -- ---------------------------------------------------------
    IF v_supersedes AND v_c = 0 AND v_cur_vt IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
              FROM public.card_variant cv
              JOIN public.card c   ON c.id  = cv.card_id
              JOIN public.card_set cs2 ON cs2.id = c.card_set_id
              LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs2.id, p_asset_source_id) sc2 ON TRUE
              JOIN public.expansion e2 ON e2.id = cs2.expansion_id
             WHERE cv.variant_type_id = v_cur_vt
               AND e2.game_id = p_game_id
               AND (p_external_set_id IS NULL OR sc2.external_set_id = p_external_set_id)
        ) INTO v_prov_risk;
    END IF;

    -- ---------------------------------------------------------
    -- 2.4 VEREDITO
    --
    -- >>> ORDEM DE PRECEDÊNCIA — CORRIGIDA EM GATE-A-REV-01 <<<
    --
    -- A v1.0 reportava ROWS_NOT_ELIGIBLE antes de
    -- CANONICAL_VARIANT_MATERIALIZED. Isso tornava a classe C
    -- INDISTINGUÍVEL na prática: uma row com
    -- `resulting_variant_id IS NOT NULL` é, por definição, classe
    -- B também — logo C NUNCA apareceria como motivo, e o caso Q
    -- do harness não teria como provar a sua própria condição.
    --
    -- A ordem correta reporta a condição MAIS GRAVE primeiro:
    -- identidade canônica já materializada é pior do que row
    -- inelegível, e é o que o revisor precisa ver.
    --
    -- O bloqueio em si é idêntico nos dois casos — muda só qual
    -- motivo é nomeado. Nenhuma linha deixa de ser bloqueada.
    -- ---------------------------------------------------------
    IF v_supersedes THEN
        IF v_c > 0 THEN
            v_block := 'CANONICAL_VARIANT_MATERIALIZED';
        ELSIF v_b > 0 THEN
            v_block := 'ROWS_NOT_ELIGIBLE';
        ELSIF v_prov_risk THEN
            v_block := 'PROVENANCE_INSUFFICIENT';
        END IF;
    END IF;

    RETURN QUERY SELECT v_cur_id, v_cur_scope, v_cur_vt, v_supersedes,
                        v_total, v_a, v_b, v_c, v_reclass, v_jobs, v_block;
END;
$impact$;

COMMENT ON FUNCTION internal.variant_type_mapping_impact(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT[], UUID) IS
    'Contrato UNICO de classificacao A/B/C, compartilhado por preview e execute. Leitura pura. block_reason so e preenchido quando o mapping novo SUPERA uma interpretacao efetiva vigente (regra de dado, nao de escopo) - o que preserva o comportamento historico do caminho GLOBAL.';

-- =============================================================
-- 3. DECISÃO COMPLETA — PRÉ-CONDIÇÕES + IMPACTO, SEM RAISE
--
-- >>> ESTA É A FUNÇÃO QUE ELIMINA A DIVERGÊNCIA PREVIEW × EXECUTE <<<
--
-- Um erro de desenho tentador seria: preview avalia as condições
-- devolvendo motivos, e o worker avalia as MESMAS condições
-- levantando exceções. Duas implementações da mesma regra — e a
-- garantia de que um dia elas discordam, com o preview dizendo
-- "pode aplicar" e o execute abortando.
--
-- Aqui as pré-condições e o impacto vivem NUMA função só, que
-- NUNCA levanta exceção de regra de negócio: devolve `ok` e
-- `block_reason` como DADO.
--
--   - o PREVIEW (Query 2194) devolve este retorno verbatim;
--   - o WORKER (Query 2193) chama esta função e, se ok = FALSE,
--     converte block_reason em exceção antes de qualquer escrita.
--
-- Só há exceção aqui para argumento estruturalmente impossível
-- (p_scope_kind fora do domínio), que não é condição de negócio.
-- =============================================================

CREATE OR REPLACE FUNCTION internal.variant_type_mapping_decision(
    p_origin_row_id   UUID,
    p_variant_type_id UUID,
    p_scope_kind      TEXT
)
RETURNS TABLE(
    ok                               BOOLEAN,
    block_reason                     TEXT,
    block_detail                     TEXT,
    game_id                          UUID,
    asset_source_id                  UUID,
    external_set_id                  TEXT,
    residual_type                    TEXT,
    residual_foil                    TEXT,
    residual_subtype                 TEXT,
    residual_stamp                   TEXT[],
    current_effective_mapping_id     UUID,
    current_effective_scope          TEXT,
    current_effective_variant_type_id UUID,
    supersedes_interpretation        BOOLEAN,
    rows_total                       INTEGER,
    rows_class_a                     INTEGER,
    rows_class_b                     INTEGER,
    canonical_class_c                INTEGER,
    rows_valid_reclassified          INTEGER,
    jobs_affected                    INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $decision$
DECLARE
    v_row        public.catalog_variant_import_row%ROWTYPE;
    v_job_source TEXT;
    v_job_scope  TEXT;      -- catalog_variant_import_job.external_set_id (NAO e autoridade)
    v_card_set   UUID;
    v_game_id    UUID;
    v_src_id     UUID;
    v_canon      TEXT := NULL;   -- escopo CANONICO do Card Set, seja qual for o scope_kind
    v_scope      TEXT := NULL;   -- escopo efetivo do mapping (NULL quando GLOBAL)
    v_sig        RECORD;
    v_imp        RECORD;
    v_reason     TEXT := NULL;
    v_detail     TEXT := NULL;
BEGIN
    IF p_scope_kind IS NULL OR p_scope_kind NOT IN ('GLOBAL', 'SOURCE_SET') THEN
        RAISE EXCEPTION 'VARIANT_TYPE_MAPPING_INVALID_SCOPE: p_scope_kind deve ser GLOBAL ou SOURCE_SET (recebido: %).', p_scope_kind;
    END IF;

    IF p_origin_row_id IS NULL OR p_variant_type_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'MISSING_IDS',
            'p_origin_row_id e p_variant_type_id sao obrigatorios.',
            NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT[],
            NULL::UUID, NULL::TEXT, NULL::UUID, NULL::BOOLEAN,
            0, 0, 0, 0, 0, 0;
        RETURN;
    END IF;

    SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_origin_row_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'ROW_NOT_FOUND',
            format('nenhuma linha para o id informado (%s).', p_origin_row_id),
            NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT[],
            NULL::UUID, NULL::TEXT, NULL::UUID, NULL::BOOLEAN,
            0, 0, 0, 0, 0, 0;
        RETURN;
    END IF;

    SELECT j.source, j.card_set_id, j.external_set_id
      INTO v_job_source, v_card_set, v_job_scope
      FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;

    SELECT e.game_id INTO v_game_id
      FROM public.card c
      JOIN public.card_set cs ON cs.id = c.card_set_id
      JOIN public.expansion e ON e.id  = cs.expansion_id
     WHERE c.id = v_row.card_id;

    SELECT a.id INTO v_src_id FROM public.asset_source a WHERE a.code = v_job_source;

    IF v_job_source IS NULL OR v_game_id IS NULL OR v_src_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'CONTEXT_NOT_RESOLVABLE',
            'nao foi possivel resolver job, Game ou Fonte a partir da linha de origem.',
            v_game_id, v_src_id, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT[],
            NULL::UUID, NULL::TEXT, NULL::UUID, NULL::BOOLEAN,
            0, 0, 0, 0, 0, 0;
        RETURN;
    END IF;

    -- Compatibilidade histórica do caminho GLOBAL (Query 2150).
    IF p_scope_kind = 'GLOBAL' AND v_row.validation_status <> 'NEEDS_REVIEW' THEN
        v_reason := 'ORIGIN_NOT_NEEDS_REVIEW';
        v_detail := 'so linhas sem mapeamento (NEEDS_REVIEW) podem ser resolvidas pelo caminho GLOBAL.';
    END IF;

    IF v_reason IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.card_variant_type t
                        WHERE t.id = p_variant_type_id AND t.game_id = v_game_id) THEN
        v_reason := 'VARIANT_TYPE_MISMATCH';
        v_detail := 'o Card Variant Type informado nao existe ou nao pertence ao Game desta combinacao.';
    END IF;

    SELECT * INTO v_sig
      FROM internal.compute_variant_residual_signature(v_row.raw_data, v_game_id, v_src_id);

    IF v_reason IS NULL
       AND v_sig.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE') THEN
        v_reason := 'PRINTING_UNRESOLVED';
        v_detail := format('linha pendente pelo eixo de IMPRESSAO (estado: %s). Resolva o Printing antes.', v_sig.printing_state);
    END IF;

    -- =========================================================
    -- ESCOPO CANÔNICO + GUARD DE MISMATCH
    --
    -- >>> ACRESCENTADO EM GATE-A-REV-01 <<<
    --
    -- A v1.0 apenas DERIVAVA o escopo da referência canônica e
    -- ignorava `catalog_variant_import_job.external_set_id`.
    -- Ignorar em silêncio não é o mesmo que tratar: se o job
    -- declara um source-set e a referência canônica diz outro,
    -- há corrupção de dado de operação — e seguir em frente
    -- usando a referência canônica seria "preferir um dos dois
    -- na surdina", exatamente o que o mandato veda.
    --
    -- Contrato: a autoridade CONTINUA sendo
    -- card_set_external_reference. Mas divergência DECLARADA e
    -- não-nula é FAIL-CLOSED. Coincide, por construção, com o
    -- guard VARIANT_IMPORT_SCOPE_MISMATCH da Edge.
    --
    -- `v_job_scope IS NULL` NÃO é mismatch: job sem o campo
    -- preenchido apenas não contradiz nada.
    -- =========================================================
    SELECT s.external_set_id INTO v_canon
      FROM internal.resolve_variant_mapping_scope(v_card_set, v_src_id) s;

    IF v_reason IS NULL
       AND v_job_scope IS NOT NULL
       AND v_canon IS NOT NULL
       AND v_job_scope IS DISTINCT FROM v_canon THEN
        v_reason := 'SCOPE_MISMATCH';
        v_detail := format('job.external_set_id=%s diverge da referencia canonica ATIVA=%s para este Card Set/Fonte. A autoridade e card_set_external_reference; a divergencia indica dado de operacao corrompido e bloqueia por seguranca.',
                           v_job_scope, v_canon);
    END IF;

    IF p_scope_kind = 'SOURCE_SET' THEN
        v_scope := v_canon;

        IF v_reason IS NULL AND v_scope IS NULL THEN
            v_reason := 'SOURCE_SET_NOT_FOUND';
            v_detail := 'o Card Set deste job nao possui referencia externa ATIVA em card_set_external_reference para esta Fonte.';
        END IF;
    END IF;

    -- Duplicidade NO MESMO ESCOPO.
    IF v_reason IS NULL AND EXISTS (
        SELECT 1 FROM public.card_variant_type_external_mapping m
         WHERE m.game_id         = v_game_id
           AND m.asset_source_id = v_src_id
           AND m.external_set_id IS NOT DISTINCT FROM v_scope
           AND m.normalized_type = v_sig.residual_type
           AND COALESCE(m.normalized_foil, '')            = COALESCE(v_sig.residual_foil, '')
           AND COALESCE(m.normalized_subtype, '')         = COALESCE(v_sig.residual_subtype, '')
           AND COALESCE(m.normalized_stamp, '{}'::TEXT[]) = COALESCE(v_sig.residual_stamp, '{}'::TEXT[])
    ) THEN
        v_reason := CASE WHEN p_scope_kind = 'GLOBAL' THEN 'DUPLICATE_GLOBAL' ELSE 'DUPLICATE_SCOPED' END;
        v_detail := 'ja existe um mapeamento para esta combinacao residual NESTE escopo.';
    END IF;

    -- Impacto A/B/C — sempre calculado, mesmo quando já há motivo
    -- de bloqueio, para que o preview mostre o quadro completo.
    SELECT * INTO v_imp
      FROM internal.variant_type_mapping_impact(
               v_game_id, v_src_id, v_scope,
               v_sig.residual_type, v_sig.residual_foil,
               v_sig.residual_subtype, v_sig.residual_stamp,
               p_variant_type_id);

    IF v_reason IS NULL AND v_imp.block_reason IS NOT NULL THEN
        v_reason := v_imp.block_reason;
        v_detail := format('universo=%s classe_A=%s classe_B=%s canonicas_C=%s',
                           v_imp.rows_total, v_imp.rows_class_a,
                           v_imp.rows_class_b, v_imp.canonical_class_c);
    END IF;

    RETURN QUERY SELECT
        (v_reason IS NULL), v_reason, v_detail,
        v_game_id, v_src_id, v_scope,
        v_sig.residual_type, v_sig.residual_foil, v_sig.residual_subtype, v_sig.residual_stamp,
        v_imp.current_effective_mapping_id, v_imp.current_effective_scope,
        v_imp.current_effective_variant_type_id, v_imp.supersedes_interpretation,
        v_imp.rows_total, v_imp.rows_class_a, v_imp.rows_class_b,
        v_imp.canonical_class_c, v_imp.rows_valid_reclassified, v_imp.jobs_affected;
END;
$decision$;

COMMENT ON FUNCTION internal.variant_type_mapping_decision(UUID, UUID, TEXT) IS
    'Contrato UNICO de pre-condicoes + impacto. NAO levanta excecao de regra de negocio: devolve ok/block_reason como DADO. O preview devolve este retorno verbatim; o worker converte block_reason em excecao antes de escrever. Impede por construcao que preview e execute divirjam.';

-- Least-privilege: funções internal nunca são expostas.
REVOKE ALL ON FUNCTION internal.variant_type_mapping_decision(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.variant_type_mapping_decision(UUID, UUID, TEXT) FROM anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.resolve_variant_mapping_scope(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.resolve_variant_mapping_scope(UUID, UUID) FROM anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.variant_type_mapping_impact(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT[], UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.variant_type_mapping_impact(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT[], UUID) FROM anon, authenticated, service_role;

COMMIT;

-- ================================================================
-- CONFIRMADO EXECUTADO em 2026-09-14 (GATE-B-EXECUTION-01). Cópia mantida em
-- proposals/ como evidência histórica do ciclo.
-- ================================================================
