-- ============================================================================
-- Query 2237 — FORWARD-FIX B-SEMANTIC: mappings de finish (SOURCE_SET)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- Mandato: BATCH13-2831-B-SEMANTIC-REMEDIATION-PREP-01
--
-- O QUE FAZ — exatamente 2 INSERTs em card_variant_type_external_mapping,
-- ambos ESCOPADOS por Card Set (external_set_id NOT NULL). Nenhum GLOBAL.
--
--   M1  base3 · HOLO | STARLIGHT | NULL | {}  →  HOLO
--       Autoridade: 05b (BASE3 — "starlight" e "galaxy" são o mesmo padrão
--       holográfico do set) + base3-editorial-convergence. O par vizinho
--       base3 (HOLO, GALAXY) → HOLO já existe; este é o resíduo starlight
--       que sobra depois que PRE-RELEASE vai para Edition Context.
--   M2  sv05  · REVERSE | GALAXY | NULL | {}  →  COSMOS_REVERSE
--       Autoridade: decisão D3 de Fabrício (2026-10-04) — Koraidon SV5 #119
--       GameStop: o resíduo depois que GAMESTOP vai para Edition Context.
--       Escopo SOURCE_SET apenas. NÃO cria equivalência GLOBAL GALAXY=COSMOS.
--
-- Efeito esperado: B-SEMANTIC "FINISH NULL" 2 → 0 (as 2 Variants do plano
-- cujo residual não tinha finish passam a ter lookup determinístico).
--
-- POR QUE INSERT DIRETO e não internal.apply_variant_type_mapping():
--   o writer canônico exige ator admin e uma row de origem NEEDS_REVIEW;
--   as rows de origem destes resíduos já são terminais (COMPLETED/INSERTED,
--   CANCELLED). Precedente: seed 2142 e migration 2200 (INSERT direto com
--   gates). Sem linha em catalog_admin_action_log (precedente 2200) —
--   registrado como dívida em 2213-CRITICAL-PATH-DECISION.md §9.
--
-- FORMATO: o mesmo das rows escopadas existentes — external_* = normalized_*,
--   MAIÚSCULAS, stamp NULL (nunca array vazio: ck exige NULL ou não vazio).
--
-- IDEMPOTÊNCIA CONTROLADA: fail-closed. Se qualquer das 2 combinações já
--   existir (escopada OU global), aborta 2237_ALREADY_APPLIED_OR_COLLISION.
-- ============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

CREATE TEMP TABLE fm_params ON COMMIT DROP AS
SELECT (SELECT id FROM public.game         WHERE code = 'POKEMON') AS game_id,
       (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')  AS src_id;

CREATE TEMP TABLE fm_target (
    k TEXT, external_set_id TEXT, card_set_code TEXT,
    t TEXT, f TEXT, target_code TEXT
) ON COMMIT DROP;
INSERT INTO fm_target VALUES
    ('M1', 'base3', 'BASE3', 'HOLO',    'STARLIGHT', 'HOLO'),
    ('M2', 'sv05',  'SV5',   'REVERSE', 'GALAXY',    'COSMOS_REVERSE');

-- ---------------------------------------------------------------- PASSO 1 ---
DO $$
DECLARE v_n INT; v_txt TEXT; p fm_params%ROWTYPE;
BEGIN
    IF (SELECT COUNT(*) FROM public.game WHERE code = 'POKEMON') <> 1
       OR (SELECT COUNT(*) FROM public.asset_source WHERE code = 'TCGDEX') <> 1 THEN
        RAISE EXCEPTION '2237_REFERENCE: Game POKEMON / asset_source TCGDEX não únicos.';
    END IF;
    SELECT * INTO p FROM fm_params;

    -- Escopo: external_set_id resolve exatamente para o Card Set esperado.
    SELECT string_agg(t.k, ', ') INTO v_txt
      FROM fm_target t
     WHERE (SELECT COUNT(*) FROM public.card_set cs
             CROSS JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, p.src_id) sc
             WHERE cs.code = t.card_set_code AND sc.external_set_id = t.external_set_id) <> 1;
    IF v_txt IS NOT NULL THEN
        RAISE EXCEPTION '2237_SCOPE: escopo não resolve 1:1 para %.', v_txt;
    END IF;

    -- Destino existe, único, no Game.
    SELECT string_agg(t.k, ', ') INTO v_txt
      FROM fm_target t
     WHERE (SELECT COUNT(*) FROM public.card_variant_type vt
             WHERE vt.code = t.target_code AND vt.game_id = p.game_id) <> 1;
    IF v_txt IS NOT NULL THEN
        RAISE EXCEPTION '2237_TARGET_MISSING: %.', v_txt;
    END IF;

    -- Ausência/colisão: nenhuma row (escopada ou global) com a combinação.
    SELECT COUNT(*) INTO v_n
      FROM fm_target t
      JOIN public.card_variant_type_external_mapping m
        ON m.game_id = p.game_id AND m.asset_source_id = p.src_id
       AND m.normalized_type = t.t AND m.normalized_foil = t.f
       AND m.normalized_subtype IS NULL AND m.normalized_stamp IS NULL
       AND (m.external_set_id = t.external_set_id OR m.external_set_id IS NULL);
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2237_ALREADY_APPLIED_OR_COLLISION: % combinação(ões) já mapeada(s).', v_n;
    END IF;

    -- Lookup hoje: NULL nas 2 (é exatamente o FINISH NULL).
    SELECT COUNT(*) INTO v_n
      FROM fm_target t JOIN public.card_set cs ON cs.code = t.card_set_code
     WHERE internal.lookup_variant_type_for_row(p.game_id, p.src_id, cs.id, t.t, t.f, NULL, NULL) IS NOT NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2237_PRE_LOOKUP_NOT_NULL: % lookup(s) já resolvem.', v_n;
    END IF;
END $$;

CREATE TEMP TABLE fm_pre ON COMMIT DROP AS
SELECT COUNT(*) AS n,
       COUNT(*) FILTER (WHERE external_set_id IS NULL) AS n_global,
       md5(string_agg(id::TEXT || '|' || variant_type_id::TEXT, ',' ORDER BY id)) AS fp
  FROM public.card_variant_type_external_mapping;

-- ---------------------------------------------------------------- PASSO 2 ---
INSERT INTO public.card_variant_type_external_mapping (
    game_id, asset_source_id, external_set_id,
    external_type, external_foil, external_subtype, external_stamp,
    normalized_type, normalized_foil, normalized_subtype, normalized_stamp,
    variant_type_id)
SELECT p.game_id, p.src_id, t.external_set_id,
       t.t, t.f, NULL, NULL,
       t.t, t.f, NULL, NULL,
       vt.id
  FROM fm_target t
  CROSS JOIN fm_params p
  JOIN public.card_variant_type vt ON vt.code = t.target_code AND vt.game_id = p.game_id;

-- ---------------------------------------------------------------- PASSO 3 ---
DO $$
DECLARE v_n INT; f fm_pre%ROWTYPE; p fm_params%ROWTYPE;
BEGIN
    SELECT * INTO f FROM fm_pre;
    SELECT * INTO p FROM fm_params;

    IF (SELECT COUNT(*) FROM public.card_variant_type_external_mapping) <> f.n + 2 THEN
        RAISE EXCEPTION '2237_POST_DELTA: esperado exatamente +2.'; END IF;
    IF (SELECT COUNT(*) FROM public.card_variant_type_external_mapping WHERE external_set_id IS NULL) <> f.n_global THEN
        RAISE EXCEPTION '2237_POST_GLOBAL_TOUCHED: nenhum mapping GLOBAL pode ser criado.'; END IF;

    -- Nada pré-existente mudou (id → variant_type_id das rows antigas).
    IF (SELECT md5(string_agg(id::TEXT || '|' || variant_type_id::TEXT, ',' ORDER BY id))
          FROM public.card_variant_type_external_mapping
         WHERE NOT (external_set_id IN ('base3', 'sv05')
                    AND normalized_subtype IS NULL AND normalized_stamp IS NULL
                    AND (normalized_type, normalized_foil) IN (('HOLO','STARLIGHT'), ('REVERSE','GALAXY'))))
       IS DISTINCT FROM f.fp THEN
        RAISE EXCEPTION '2237_POST_EXISTING_CHANGED: mapping pré-existente alterado.'; END IF;

    -- Lookup operacional agora resolve exatamente o destino, só no escopo.
    SELECT COUNT(*) INTO v_n
      FROM fm_target t
      JOIN public.card_set cs ON cs.code = t.card_set_code
      JOIN public.card_variant_type vt ON vt.code = t.target_code AND vt.game_id = p.game_id
     WHERE internal.lookup_variant_type_for_row(p.game_id, p.src_id, cs.id, t.t, t.f, NULL, NULL) IS DISTINCT FROM vt.id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2237_POST_LOOKUP: % lookup(s) não resolvem para o destino.', v_n; END IF;

    -- Sem vazamento: fora do escopo (lookup global, card_set_id NULL) segue NULL.
    SELECT COUNT(*) INTO v_n
      FROM fm_target t
     WHERE internal.lookup_variant_type_for_row(p.game_id, p.src_id, NULL, t.t, t.f, NULL, NULL) IS NOT NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2237_POST_GLOBAL_LEAK: % combinação(ões) resolvem fora do escopo.', v_n; END IF;

    RAISE NOTICE '2237 OK — +2 mappings SOURCE_SET (base3 HOLO|STARLIGHT→HOLO; sv05 REVERSE|GALAXY→COSMOS_REVERSE); 0 GLOBAL.';
END $$;

COMMIT;
