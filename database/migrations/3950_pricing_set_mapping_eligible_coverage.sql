-- STATUS: CONFIRMADO EXECUTADO -- P16.1, Onboarding de Sets no Pricing -- Cobertura e Visibilidade.
-- Aplicada via Supabase MCP em 2026-08-25 (apos autorizacao explicita de Fabricio,
-- pos-auditoria semantica de fontes ativas -- ver revisao datada 2026-08-24 abaixo).
--
-- Elimina a invisibilidade estrutural de Card Sets elegiveis sem
-- pricing_set_mapping (causa raiz do gap SWSH8 -- "Golpe Fusao", diagnostico
-- forense de 2026-08-24, confirmado nesta rodada: 46 Sets no Catalogo, 45
-- com pricing_set_mapping, SWSH8 com footprint zero em todo o dominio
-- Pricing). admin_list_pricing_set_mappings() partia de pricing_set_mapping
-- com JOIN interno em card_set -- um Set sem mapping nunca aparecia na tela
-- /pricing/mapeamentos-sets. Reescrita para partir de card_set (filtrado
-- por elegibilidade) com LEFT JOIN opcional a pricing_set_mapping.
--
-- Elegibilidade (regra aprovada por Fabricio, sem coluna/entidade nova):
-- "Card Set elegivel para Pricing = pertence a um jogo suportado por pelo
-- menos uma fonte de preco ativa aplicavel". Hoje, unico jogo cadastrado =
-- POKEMON, unica fonte ativa = JUSTTCG (GAME_CODE fixo em
-- supabase/functions/_shared/pricing-justtcg/mod.ts -- mesmo nivel de
-- acoplamento ja aceito nesse cliente). Micro-auditoria por set_type
-- (pedida por Fabricio antes desta migration) confirmou REGULAR (30/30),
-- SPECIAL (10/10), PROMO (4/4) e ENERGY (2/2) TODOS com precedente real de
-- precificacao CONFIRMED -- nenhum candidato a exclusao editorial hoje. Nao
-- existe tabela game<->pricing_source no schema atual; o literal 'POKEMON'
-- fica documentado aqui para revisao no dia em que um 2o jogo ou uma 2a
-- fonte exigir mapeamento real (nao inventado especulativamente agora).
--
-- Cobertura (bloco novo em get_pricing_admin_overview(), migration 3939):
-- Sets elegiveis com QUALQUER linha em pricing_set_mapping (CONFIRMED,
-- PENDING ou NOT_FOUND contam -- so a ausencia TOTAL nao conta), dividido
-- pelo total de Sets elegiveis. "Cobertura = o Pricing conhece/administra
-- este Set", nunca "este Set tem preco disponivel" (isso continua sendo
-- Saude + Atencoes e Acoes). Conta SETS, nunca pares Set x Fonte -- decisao
-- deliberada de Fabricio para nao virar armadilha semantica no dia em que
-- uma 2a fonte for ativada (o denominador nao pode dobrar sozinho). Saude
-- dos Sets (bloco "sets" da mesma RPC, migration 3939) fica INTOCADA nesta
-- migration -- continua medindo soh o operacional de
-- pricing_set_refresh_state (Sets ja onboardados), nunca redefinida para
-- incluir Sets ainda sem mapping.
--
-- REVISAO (2026-08-24, mesmo dia, antes da aplicacao -- Fabricio pediu uma
-- ultima auditoria semantica para nao criar armadilha no dia em que existir
-- uma 2a fonte de preco). Dois problemas reais encontrados na primeira
-- versao desta migration (corrigidos aqui no mesmo arquivo, sem versionar
-- 3951):
--
-- (a) NUMERADOR DE COBERTURA nao filtrava por fonte ativa: `covered`
-- contava qualquer linha em pricing_set_mapping, mesmo de uma fonte hoje
-- INATIVA. Cenario que isso quebraria: Fonte A fica inativa, Set X so tem
-- mapping historico na Fonte A, Fonte B (ativa) nunca mapeou o Set X -- a
-- versao anterior contava X como "coberto" por causa do resíduo da Fonte
-- A, mesmo sem nenhuma fonte ativa hoje efetivamente o administrando.
-- Corrigido: o LEFT JOIN de pricing_set_mapping no bloco de cobertura agora
-- exige psm.pricing_source_id IN (SELECT id FROM pricing_source WHERE
-- is_active) -- so mapping de fonte ativa conta.
--
-- (b) LISTAGEM nao materializava a combinacao Set x Fonte ausente quando
-- existe mais de uma fonte ativa: o LEFT JOIN original so enxergava linhas
-- que JA existem em pricing_set_mapping (por card_set_id, com filtro
-- opcional de fonte no ON). Um Set com mapping na Fonte A mas SEM mapping
-- na Fonte B (ambas ativas) so aparecia como 1 linha (Fonte A), nunca como
-- 2 (Fonte A confirmada + Fonte B UNMAPPED) -- a Fonte B ficaria
-- estruturalmente invisivel, o MESMO problema de fundo que esta migration
-- existe para resolver (so que por fonte, nao por Set). Corrigido: a
-- listagem agora parte de `eligible_sets CROSS JOIN eligible_sources`
-- (grade completa Set elegivel x Fonte ativa/aplicavel) com LEFT JOIN em
-- pricing_set_mapping casando OS DOIS campos (card_set_id E
-- pricing_source_id) -- toda combinacao Set x Fonte ativa aparece, mapeada
-- ou nao. Consequencia aceita e desejada: um mapping historico ligado a
-- uma fonte hoje inativa deixa de aparecer nesta listagem (mesma logica do
-- item (a) -- esta tela administra fontes ativas, nao arquiva fontes
-- desativadas).
--
-- O bloco de Cobertura (get_pricing_admin_overview) continua contando SETS
-- (DISTINCT card_set_id), nunca pares Set x Fonte -- corrigido so o
-- criterio de "conta como coberto" (item a), a unidade de contagem em si
-- nao mudou. Prova controlada (transacao com ROLLBACK, nao persistida, antes
-- da aplicacao): com 2 fontes ativas simuladas, um Set mapeado so na Fonte A
-- e sem mapping na Fonte B (ativa) apareceu como 2 linhas na listagem
-- (Fonte A mapeada + Fonte B UNMAPPED) e contou 1 (nao 2) na Cobertura
-- geral; um mapping CONFIRMED numa fonte simulada como INATIVA nao contou
-- como coberto e nao apareceu na listagem.
--
-- Sem escrita nova, sem RPC nova, sem tabela/coluna nova, sem trigger novo
-- -- so CREATE OR REPLACE de 2 funcoes ja existentes. Grants inalterados
-- (EXECUTE ja concedido a authenticated/postgres, enforcement admin-only
-- via is_admin() dentro do corpo de cada funcao, mesmo padrao das duas
-- funcoes originais). Validado transacionalmente (BEGIN/ROLLBACK, com
-- request.jwt.claims simulando um admin_user real) antes de aplicar: com o
-- estado real (1 fonte ativa, JUSTTCG), 46 linhas retornadas sem filtro
-- (= 46 Sets elegiveis x 1 fonte ativa), SWSH8 aparece com
-- match_status='UNMAPPED' sintetico e id NULL (mas pricing_source_id/
-- pricing_source_code preenchidos com a fonte elegivel, ja que agora vem da
-- grade, nao do mapping ausente), os 45 mappings existentes permanecem
-- identicos (amostra ME5 conferida), filtro por status CONFIRMED continua
-- trazendo exatamente 45 linhas (nunca o UNMAPPED), filtro por 'UNMAPPED'
-- traz exatamente 1, coverage = {"covered": 45, "eligible_total": 46}.

CREATE OR REPLACE FUNCTION public.admin_list_pricing_set_mappings(
  p_status text[] DEFAULT NULL::text[],
  p_pricing_source_id uuid DEFAULT NULL::uuid,
  p_search text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  card_set_id uuid,
  card_set_code text,
  card_set_name text,
  pricing_source_id uuid,
  pricing_source_code text,
  external_set_id text,
  external_set_name text,
  match_status text,
  match_method text,
  last_checked_at timestamp with time zone,
  has_dependency boolean,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_limit int; v_offset int; v_search text; v_status text[];
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_SET_MAPPINGS_FORBIDDEN: acesso restrito a administradores.';
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);
  v_search := NULLIF(BTRIM(p_search), '');
  -- 'UNMAPPED' aceito no filtro de status (P16.1) -- pseudo-status
  -- sintetico produzido pelo COALESCE abaixo, nunca gravado em
  -- pricing_set_mapping.match_status (constraint da tabela permanece
  -- restrita aos 4 status reais, intocada).
  v_status := NULLIF(
    ARRAY(SELECT x FROM unnest(p_status) AS x WHERE x IN ('CONFIRMED', 'PENDING', 'NOT_FOUND', 'REJECTED', 'UNMAPPED')),
    ARRAY[]::text[]
  );

  RETURN QUERY
  WITH eligible_sets AS (
    SELECT cs.id, cs.code, cs.name, cs.release_date
    FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    JOIN public.game g ON g.id = ex.game_id
    WHERE g.code = 'POKEMON'
  ),
  eligible_sources AS (
    -- Fonte "aplicavel" = ativa (is_active). Nao existe tabela
    -- game<->pricing_source no schema atual -- mesma nota da elegibilidade
    -- de Set, acima. Quando uma 2a fonte for cadastrada, revisar se ela de
    -- fato atende POKEMON antes de assumir aplicabilidade automatica so por
    -- is_active=true.
    SELECT ps.id, ps.code
    FROM public.pricing_source ps
    WHERE ps.is_active
  )
  SELECT
    psm.id,
    es.id,
    es.code::text,
    es.name::text,
    esrc.id,
    esrc.code::text,
    psm.external_set_id::text,
    psm.external_set_name::text,
    COALESCE(psm.match_status, 'UNMAPPED') AS match_status,
    psm.match_method,
    psm.last_checked_at,
    public.pricing_set_mapping_dependency_exists(es.id, esrc.id) AS has_dependency,
    count(*) OVER() AS total_count
  FROM eligible_sets es
  -- CROSS JOIN, nao mais so os mappings existentes: a grade completa
  -- Set elegivel x Fonte ativa/aplicavel e a unidade real desta listagem
  -- (Set x Fonte), nao so "Sets sem NENHUM mapping" -- um Set mapeado na
  -- Fonte A mas nao na Fonte B (ambas ativas) precisa aparecer 2 vezes, uma
  -- por fonte, e a Fonte B como UNMAPPED explicito. Ver cabecalho da
  -- migration para o racional completo da correcao.
  CROSS JOIN eligible_sources esrc
  LEFT JOIN public.pricing_set_mapping psm
    ON psm.card_set_id = es.id
    AND psm.pricing_source_id = esrc.id
  WHERE (p_pricing_source_id IS NULL OR esrc.id = p_pricing_source_id)
    AND (v_status IS NULL OR COALESCE(psm.match_status, 'UNMAPPED') = ANY(v_status))
    AND (v_search IS NULL OR es.name ILIKE '%' || v_search || '%' OR es.code ILIKE '%' || v_search || '%')
  ORDER BY es.release_date DESC NULLS LAST, es.code ASC
  LIMIT v_limit OFFSET v_offset;
END;
$function$;

COMMENT ON FUNCTION public.admin_list_pricing_set_mappings(text[], uuid, text, integer, integer) IS
  'P16.1 -- lista a grade completa Card Set elegivel x Fonte de preco ativa/aplicavel (eligible_sets CROSS JOIN eligible_sources, LEFT JOIN pricing_set_mapping por card_set_id+pricing_source_id) -- nunca mais so pricing_set_mapping. Combinacoes sem mapping aparecem com match_status sintetico UNMAPPED (so id/external_set_* NULL -- pricing_source_id/code sempre vem da fonte elegivel, nunca NULL). Elegibilidade de Set: jogo suportado por fonte ativa; elegibilidade de fonte: is_active=true (hoje, literal POKEMON x JUSTTCG -- ver cabecalho da migration 3950 para o racional e a nota de revisao futura).';

CREATE OR REPLACE FUNCTION public.get_pricing_admin_overview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mapping_counts record;
  v_set_counts record;
  v_coverage_counts record;
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'GET_PRICING_ADMIN_OVERVIEW_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  SELECT
    count(*) FILTER (WHERE match_status = 'CONFIRMED') AS confirmed,
    count(*) FILTER (WHERE match_status = 'PENDING') AS pending,
    count(*) FILTER (WHERE match_status = 'NOT_FOUND') AS not_found,
    count(*) AS total
  INTO v_mapping_counts
  FROM public.pricing_card_mapping;

  SELECT
    count(*) AS total,
    count(*) FILTER (WHERE last_outcome = 'SUCCESS' AND NOT is_paused) AS healthy,
    count(*) FILTER (WHERE last_outcome IS DISTINCT FROM 'SUCCESS' OR is_paused) AS problem,
    count(*) FILTER (WHERE is_paused) AS paused,
    min(next_due_at) FILTER (WHERE NOT is_paused) AS next_due_at
  INTO v_set_counts
  FROM public.pricing_set_refresh_state;

  -- P16.1: Cobertura de Sets -- bloco independente de "sets" (Saude, acima,
  -- intocado). Mesma regra de elegibilidade de
  -- admin_list_pricing_set_mappings (migration 3950). Coberto = QUALQUER
  -- linha em pricing_set_mapping (CONFIRMED/PENDING/NOT_FOUND), nunca so
  -- CONFIRMED -- mede "o Pricing conhece este Set", nao "tem preco
  -- disponivel". Conta Sets (DISTINCT cs.id), nunca pares Set x Fonte.
  --
  -- REVISAO (2026-08-24): o LEFT JOIN agora so aceita mapping de uma fonte
  -- ATIVA (psm.pricing_source_id IN (SELECT id FROM pricing_source WHERE
  -- is_active)) -- um mapping historico ligado a uma fonte hoje inativa
  -- NAO conta mais como cobertura (mesma correcao do numerador aplicada na
  -- listagem, ver cabecalho da migration). Sem essa restricao, um Set
  -- ficaria marcado como "coberto" so por um residuo de fonte desativada,
  -- mesmo sem nenhuma fonte ativa hoje o administrando de fato.
  SELECT
    count(DISTINCT cs.id) AS eligible_total,
    count(DISTINCT cs.id) FILTER (WHERE psm.id IS NOT NULL) AS covered
  INTO v_coverage_counts
  FROM public.card_set cs
  JOIN public.expansion ex ON ex.id = cs.expansion_id
  JOIN public.game g ON g.id = ex.game_id
  LEFT JOIN public.pricing_set_mapping psm
    ON psm.card_set_id = cs.id
    AND psm.pricing_source_id IN (SELECT ps.id FROM public.pricing_source ps WHERE ps.is_active)
  WHERE g.code = 'POKEMON';

  SELECT jsonb_build_object(
    'sources', jsonb_build_object(
      'active', (SELECT count(*) FROM public.pricing_source WHERE is_active),
      'total', (SELECT count(*) FROM public.pricing_source)
    ),
    'mappings', jsonb_build_object(
      'confirmed', v_mapping_counts.confirmed,
      'pending', v_mapping_counts.pending,
      'not_found', v_mapping_counts.not_found,
      'total', v_mapping_counts.total,
      'coverage_pct', CASE WHEN v_mapping_counts.total > 0
        THEN round((v_mapping_counts.confirmed::numeric / v_mapping_counts.total) * 100, 1)
        ELSE NULL END
    ),
    'coverage', jsonb_build_object(
      'eligible_total', v_coverage_counts.eligible_total,
      'covered', v_coverage_counts.covered
    ),
    'products_count', (SELECT count(*) FROM public.pricing_product),
    'observations_count', (SELECT count(*) FROM public.pricing_observation),
    'last_sync_run', (
      SELECT jsonb_build_object(
        'id', id, 'run_type', run_type, 'status', status,
        'finished_at', finished_at, 'triggered_by', triggered_by
      )
      FROM public.pricing_sync_run
      WHERE status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS')
      ORDER BY finished_at DESC NULLS LAST
      LIMIT 1
    ),
    'sets', jsonb_build_object(
      'total', v_set_counts.total,
      'healthy', v_set_counts.healthy,
      'problem', v_set_counts.problem,
      'paused', v_set_counts.paused,
      'next_due_at', v_set_counts.next_due_at
    ),
    'refresh_policy', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'pricing_source_id', ps.id,
        'pricing_source_code', ps.code,
        'pricing_source_name', ps.name,
        'frequency_days', COALESCE(prp.frequency_days, 1)
      ) ORDER BY ps.source_order), '[]'::jsonb)
      FROM public.pricing_source ps
      LEFT JOIN public.pricing_refresh_policy prp ON prp.pricing_source_id = ps.id
    ),
    'dispatcher', (
      SELECT jsonb_build_object('active', active, 'schedule', schedule)
      FROM cron.job
      WHERE jobname = 'justtcg-price-refresh-set-dispatcher'
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_pricing_admin_overview() IS
  'P16.1 -- adiciona bloco "coverage" (Sets elegiveis com QUALQUER pricing_set_mapping DE FONTE ATIVA / total elegivel -- mapping de fonte inativa nao conta, revisao 2026-08-24), sem alterar a semantica de "sets" (Saude, ja existente, migration 3939) nem de "mappings.coverage_pct" (confirmacao de pricing_card_mapping, metrica ja existente e conceitualmente distinta -- ver frontend, pricing-overview-hero.tsx, onde o rotulo Hero e trocado nesta mesma rodada para nao colidir semanticamente com Cobertura de Sets).';
