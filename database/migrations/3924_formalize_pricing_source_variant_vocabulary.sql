-- 3924_formalize_pricing_source_variant_vocabulary
--
-- Formaliza o vocabulario de variantes externas por pricing_source (JustTCG e futuras
-- fontes), permitindo classificar candidatos PENDING de pricing_card_mapping em PRIMARY
-- (STANDARD) + N ALTERNATE sem inferencia por substring/nome local, conforme decisoes
-- 1-12 do pedido de Fabricio (2026-08-20, rodada "P14 - vocabulario de variantes").
--
-- Decisoes ja tomadas, nao reabertas nesta migration:
--   1. Nao reutiliza card_variant_type_external_mapping (dominio asset_source/TCGdex).
--   2. Tabela irma nova, vinculada a pricing_source, reutilizavel por qualquer fonte.
--   3. pricing_source_card_identity recebe card_variant_type_id nullable +
--      external_variant_key auditavel.
--   4. PRIMARY = tipo editorial padrao STANDARD.
--   5. ALTERNATE = variante formalmente mapeada.
--   6. ALIAS permanece sem uso nesta rodada (nenhum caso autorizado).
--   7. MASTER_BALL_PATTERN e POKE_BALL_PATTERN sao tipos novos, distintos de
--      MASTER_BALL_REVERSE e POKE_BALL_REVERSE.
--
-- Contagem de recuperaveis (534 PENDING atuais, algoritmo do executor
-- --repair-multi-identities, comprovado via SQL real contra producao em 2026-08-20):
--   458 PROMOTABLE, 71 UNKNOWN_QUALIFIER, 4 MULTIPLE_STANDARD_CANDIDATES,
--   1 NO_STANDARD_CANDIDATE. Uma estimativa preliminar de 463 foi feita antes desta
--   validacao e esta substituida por este numero comprovado -- nao reaberta.
--
-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao em 2026-08-20, apos validacao
-- completa em BEGIN/ROLLBACK e autorizacao explicita de Fabricio.
-- Nenhuma instrucao BEGIN/COMMIT/ROLLBACK neste arquivo -- a ferramenta de aplicacao de
-- migration do Supabase MCP fornece a transacao implicita.

-- 0) Guarda de concorrencia -- reusa o mesmo padrao da 3923 ------------------
LOCK TABLE public.pricing_sync_run IN EXCLUSIVE MODE NOWAIT;

DO $$
DECLARE
  v_active_count int;
BEGIN
  SELECT count(*) INTO v_active_count FROM pricing_sync_run WHERE status IN ('RECEIVED','PROCESSING');
  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'PRICING_MIGRATION_BLOCKED_ACTIVE_SYNC_RUN: % run(s) em RECEIVED/PROCESSING', v_active_count;
  END IF;
END $$;

-- 1) Novos card_variant_type -- apenas os 4 comprovadamente necessarios para
--    promover os candidatos PENDING recuperaveis identificados no inventario desta
--    rodada. PRERELEASE, POKEMON_CENTER NY, World Championships etc. NAO entram aqui --
--    nenhum recuperavel depende deles (ver relatorio da Parte A/E).
INSERT INTO public.card_variant_type (game_id, code, name, description, display_order)
SELECT g.id, v.code, v.name, v.description, v.display_order
FROM (VALUES
    ('MASTER_BALL_PATTERN', 'Master Ball Pattern', 'Tratamento especial "Master Ball Pattern" (textura), distinto de Master Ball Reversa classica -- introduzido a partir de Evolucoes Prismaticas (SV8.5).', 40),
    ('POKE_BALL_PATTERN', 'Poke Ball Pattern', 'Tratamento especial "Poke Ball Pattern" (textura), distinto de Poke Ball Reversa classica -- introduzido a partir de Evolucoes Prismaticas (SV8.5).', 41),
    ('POKEMON_CENTER_EXCLUSIVE', 'Exclusiva Pokemon Center', 'Versao promocional distribuida exclusivamente por lojas/canal Pokemon Center (generico, sem localizacao especifica).', 42),
    ('CRACKED_ICE_HOLO', 'Holografica Cracked Ice', 'Versao com acabamento holografico no padrao "gelo rachado" (Cracked Ice Holo).', 43)
) AS v(code, name, description, display_order)
CROSS JOIN (SELECT id FROM public.game WHERE code = 'POKEMON') AS g
WHERE NOT EXISTS (
    SELECT 1 FROM public.card_variant_type existing WHERE existing.code = v.code
);

-- 2) Tabela irma: mapping de vocabulario de variante por pricing_source -------
CREATE TABLE public.pricing_source_variant_mapping (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pricing_source_id     uuid NOT NULL REFERENCES public.pricing_source(id) ON DELETE CASCADE,
    external_variant_key  text NOT NULL,
    variant_type_id       uuid NOT NULL REFERENCES public.card_variant_type(id) ON DELETE RESTRICT,
    notes                 text,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ck_pricing_source_variant_mapping_key_not_blank
        CHECK (btrim(external_variant_key) <> ''),
    CONSTRAINT ck_pricing_source_variant_mapping_key_normalized
        CHECK (external_variant_key = lower(btrim(external_variant_key))),
    CONSTRAINT uq_pricing_source_variant_mapping_source_key
        UNIQUE (pricing_source_id, external_variant_key)
);

COMMENT ON TABLE public.pricing_source_variant_mapping IS
    'Vocabulario formal de qualificadores de variante por pricing_source (ex.: JustTCG). external_variant_key e sempre normalizado (lower+trim) -- nunca comparado por fuzzy/substring. Tabela irma de card_variant_type_external_mapping, mas escopada a pricing_source em vez de asset_source (decisao 1-2, 2026-08-20).';

CREATE INDEX ix_pricing_source_variant_mapping_variant_type_id
    ON public.pricing_source_variant_mapping (variant_type_id);

CREATE TRIGGER trg_pricing_source_variant_mapping_set_updated_at
    BEFORE UPDATE ON public.pricing_source_variant_mapping
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.pricing_source_variant_mapping ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
    ON public.pricing_source_variant_mapping
    FOR SELECT
    TO authenticated
    USING (is_admin());

REVOKE ALL ON public.pricing_source_variant_mapping FROM PUBLIC;
REVOKE ALL ON public.pricing_source_variant_mapping FROM anon;
REVOKE ALL ON public.pricing_source_variant_mapping FROM authenticated;

GRANT SELECT ON public.pricing_source_variant_mapping TO authenticated;
GRANT SELECT ON public.pricing_source_variant_mapping TO service_role;

-- 3) Seed do vocabulario JustTCG -- apenas os padroes comprovados no inventario
--    desta rodada (17 chaves -> 13 card_variant_type distintos, 9 ja existentes e
--    4 novos). Chaves ja normalizadas (lower+trim) na propria insercao.
INSERT INTO public.pricing_source_variant_mapping (pricing_source_id, external_variant_key, variant_type_id, notes)
SELECT ps.id, v.key, vt.id, v.notes
FROM (VALUES
    ('master ball pattern', 'MASTER_BALL_PATTERN', 'SV8.5/SV10.5W/SV10.5B -- candidato "(Master Ball Pattern)"'),
    ('poke ball pattern',   'POKE_BALL_PATTERN',   'SV8.5/SV10.5W/SV10.5B -- candidato "(Poke Ball Pattern)"'),
    ('energy symbol pattern','ENERGY_REVERSE',     'ME2.5 -- candidato "(Energy Symbol Pattern)"'),
    ('poke ball',           'POKE_BALL_REVERSE',   'ME2.5 -- candidato "(Poke Ball)" (sem "Pattern")'),
    ('dusk ball',           'DUSK_BALL_REVERSE',   'ME2.5 -- candidato "(Dusk Ball)"'),
    ('love ball',           'LOVE_BALL_REVERSE',   'ME2.5 -- candidato "(Love Ball)"'),
    ('friend ball',         'FRIEND_BALL_REVERSE', 'ME2.5 -- candidato "(Friend Ball)"'),
    ('quick ball',          'QUICK_BALL_REVERSE',  'ME2.5 -- candidato "(Quick Ball)"'),
    ('team rocket',         'ROCKET_REVERSE',      'ME2.5 -- candidato "(Team Rocket)"'),
    ('staff',               'STAFF_HOLO',          'MEP/SVP -- candidato "(Staff)" isolado (sem Prerelease)'),
    ('cosmos holo',         'COSMOS_HOLO',         'SVE/SVP/SWSHP -- grafia canonica'),
    ('cosmos holofoil',     'COSMOS_HOLO',         'SVP -- variacao de grafia observada na fonte'),
    ('cosmo holo',          'COSMOS_HOLO',         'SWSHP -- variacao de grafia/typo observada na fonte'),
    ('pokemon center exclusive', 'POKEMON_CENTER_EXCLUSIVE', 'MEP/SVP -- grafia canonica'),
    ('pokémon center exclusive', 'POKEMON_CENTER_EXCLUSIVE', 'SVP -- variacao com acento observada na fonte'),
    ('pokemon center',      'POKEMON_CENTER_EXCLUSIVE', 'SVP -- grafia curta observada na fonte (ver ressalva no relatorio: julgamento equiparando a "Exclusive")'),
    ('cracked ice holo',    'CRACKED_ICE_HOLO',    'SVE -- candidato "(Cracked Ice Holo)"')
) AS v(key, vt_code, notes)
JOIN public.pricing_source ps ON ps.code = 'JUSTTCG'
JOIN public.card_variant_type vt ON vt.code = v.vt_code
WHERE NOT EXISTS (
    SELECT 1 FROM public.pricing_source_variant_mapping existing
    WHERE existing.pricing_source_id = ps.id AND existing.external_variant_key = v.key
);

-- 4) pricing_source_card_identity: card_variant_type_id nullable + chave auditavel
ALTER TABLE public.pricing_source_card_identity
    ADD COLUMN card_variant_type_id uuid REFERENCES public.card_variant_type(id) ON DELETE RESTRICT,
    ADD COLUMN external_variant_key text;

COMMENT ON COLUMN public.pricing_source_card_identity.card_variant_type_id IS
    'Tipo de variante formalmente classificado (STANDARD para PRIMARY, tipo especifico para ALTERNATE). NULL para identidades PRIMARY legadas (backfill da migration 3923, anteriores a este vocabulario) -- tratadas implicitamente como STANDARD.';
COMMENT ON COLUMN public.pricing_source_card_identity.external_variant_key IS
    'Chave normalizada (lower+trim) do qualificador bruto da fonte externa que originou esta identidade, para auditoria -- nunca usada como criterio de match por si so (o match e feito via pricing_source_variant_mapping).';

CREATE INDEX ix_pricing_source_card_identity_card_variant_type_id
    ON public.pricing_source_card_identity (card_variant_type_id)
    WHERE card_variant_type_id IS NOT NULL;

GRANT UPDATE (card_variant_type_id, external_variant_key)
    ON public.pricing_source_card_identity TO service_role;

-- 5) get_cards_pricing_summary: passa a exigir identidade PRIMARY/CONFIRMED -----
--    Hoje a funcao nao tem nenhuma nocao de pricing_source_card_identity -- filtra
--    so por pricing_card_mapping.match_status/pricing_product.is_active. Isso e um
--    risco real assim que a primeira identidade ALTERNATE existir: um produto
--    ALTERNATE com o mesmo source_printing_label reconhecido poderia competir e
--    vencer o produto PRIMARY na ordenacao por observed_at. Todos os pricing_product
--    hoje ja apontam para uma identidade PRIMARY/CONFIRMED (backfill 3923), entao este
--    filtro adicional e comportamentalmente invisivel no estado atual e so passa a
--    atuar quando a primeira ALTERNATE for persistida (decisao 10).
CREATE OR REPLACE FUNCTION public.get_cards_pricing_summary(p_card_ids uuid[])
 RETURNS TABLE(card_id uuid, has_pricing boolean, brl_amount numeric, fx_status text, printing_label text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_REQUIRES_AUTHENTICATION'
            USING ERRCODE = '28000';
    END IF;

    IF p_card_ids IS NULL OR array_length(p_card_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_EMPTY_INPUT'
            USING ERRCODE = '22023';
    END IF;

    IF array_length(p_card_ids, 1) > 100 THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_TOO_MANY_CARD_IDS'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH input_ids AS (
        SELECT DISTINCT input_id FROM unnest(p_card_ids) AS input_id
    ),
    candidate_by_printing AS (
        SELECT DISTINCT ON (pcm.card_id, pp.source_printing_label)
            pcm.card_id,
            pp.source_printing_label,
            po.price,
            po.currency_code,
            po.observed_at
        FROM public.pricing_card_mapping pcm
        JOIN public.pricing_product pp
            ON pp.pricing_card_mapping_id = pcm.id
           AND pp.is_active = TRUE
           AND pp.source_printing_label IN (
               'Normal', 'Holofoil', 'Reverse Holofoil',
               'Unlimited', 'Unlimited Holofoil',
               '1st Edition', '1st Edition Holofoil'
           )
        JOIN public.pricing_source ps
            ON ps.id = pcm.pricing_source_id
           AND ps.is_active = TRUE
        JOIN public.pricing_source_card_identity psci
            ON psci.id = pp.pricing_source_card_identity_id
           AND psci.identity_role = 'PRIMARY'
           AND psci.match_status = 'CONFIRMED'
        JOIN public.pricing_observation po
            ON po.pricing_product_id = pp.id
           AND po.price_type = 'MARKET'
        JOIN public.card_condition cc
            ON cc.id = po.condition_id
           AND cc.code = 'NM'
        WHERE pcm.match_status = 'CONFIRMED'
          AND pcm.card_id IN (SELECT input_id FROM input_ids)
        ORDER BY pcm.card_id, pp.source_printing_label, po.observed_at DESC, po.created_at DESC, po.id DESC
    ),
    candidate AS (
        SELECT DISTINCT ON (cbp.card_id)
            cbp.card_id, cbp.source_printing_label, cbp.price, cbp.currency_code, cbp.observed_at
        FROM candidate_by_printing cbp
        ORDER BY cbp.card_id,
            CASE cbp.source_printing_label
                WHEN 'Normal' THEN 1
                WHEN 'Holofoil' THEN 2
                WHEN 'Reverse Holofoil' THEN 3
                WHEN 'Unlimited' THEN 4
                WHEN 'Unlimited Holofoil' THEN 5
                WHEN '1st Edition' THEN 6
                WHEN '1st Edition Holofoil' THEN 7
                ELSE 8
            END
    )
    SELECT
        ii.input_id AS card_id,
        (fx.rate IS NOT NULL) AS has_pricing,
        CASE WHEN fx.rate IS NOT NULL THEN round(c.price * fx.rate, 2) ELSE NULL END AS brl_amount,
        CASE
            WHEN c.card_id IS NULL THEN NULL
            WHEN fx.rate IS NOT NULL THEN 'CONVERTED'
            ELSE 'FX_RATE_UNAVAILABLE'
        END AS fx_status,
        c.source_printing_label AS printing_label
    FROM input_ids ii
    LEFT JOIN candidate c ON c.card_id = ii.input_id
    LEFT JOIN LATERAL (
        SELECT r.rate
        FROM public.pricing_fx_rate r
        WHERE c.currency_code = 'USD'
          AND r.from_currency = 'USD'
          AND r.to_currency = 'BRL'
          AND r.rate_source_code = 'BCB_PTAX'
          AND r.rate_date <= (c.observed_at AT TIME ZONE 'UTC')::date
        ORDER BY r.rate_date DESC
        LIMIT 1
    ) fx ON TRUE;
END;
$function$;

-- 6) Asserções pos-migration embutidas -- contagens dinamicas, sem numeros fixos
DO $$
DECLARE
  v_new_types int;
  v_seed_rows int;
  v_products_total int;
  v_products_matched_by_new_filter int;
BEGIN
  SELECT count(*) INTO v_new_types FROM card_variant_type
    WHERE code IN ('MASTER_BALL_PATTERN','POKE_BALL_PATTERN','POKEMON_CENTER_EXCLUSIVE','CRACKED_ICE_HOLO');
  IF v_new_types <> 4 THEN
    RAISE EXCEPTION 'ASSERT FALHOU: esperado 4 novos card_variant_type, encontrado %', v_new_types;
  END IF;

  SELECT count(*) INTO v_seed_rows FROM pricing_source_variant_mapping;
  IF v_seed_rows <> 17 THEN
    RAISE EXCEPTION 'ASSERT FALHOU: esperado 17 linhas de seed em pricing_source_variant_mapping, encontrado %', v_seed_rows;
  END IF;

  -- Prova de que a extensao da RPC nao regride nenhum produto legado: todo
  -- pricing_product ja aponta para identidade PRIMARY/CONFIRMED (backfill 3923),
  -- entao o novo JOIN deve casar exatamente o mesmo conjunto de antes.
  SELECT count(*) INTO v_products_total FROM pricing_product;
  SELECT count(*) INTO v_products_matched_by_new_filter
  FROM pricing_product pp
  JOIN pricing_source_card_identity psci
    ON psci.id = pp.pricing_source_card_identity_id
   AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED';
  IF v_products_total <> v_products_matched_by_new_filter THEN
    RAISE EXCEPTION 'ASSERT FALHOU: % produtos totais mas apenas % casam PRIMARY/CONFIRMED -- RPC regrediria',
      v_products_total, v_products_matched_by_new_filter;
  END IF;

  RAISE NOTICE 'OK: 4 tipos novos, 17 mappings de vocabulario, % produtos -- 100%% compativeis com filtro PRIMARY/CONFIRMED da RPC',
    v_products_total;
END $$;
