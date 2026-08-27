-- STATUS: PROPOSTA (não aplicada ainda) -- P16.4, Onboarding de Sets no Pricing --
-- Confirmação do Mapping.
--
-- Objetivo: permitir que o administrador confirme, de forma segura, idempotente e
-- auditável, a correspondência descoberta no P16.3 (Edge Function
-- pricing-set-matching-preview, estado SAFE_CANDIDATE) -- persistindo
-- pricing_set_mapping. Mesmo padrão de RPC admin-only write já em produção desde a
-- migration 3942 (Bloco 4 do Pricing Admin): SECURITY DEFINER, is_admin() no corpo,
-- SET search_path TO '', REVOKE ALL FROM PUBLIC + GRANT EXECUTE só a authenticated,
-- pricing_admin_action_log para auditoria. Nenhuma RPC nova de leitura, nenhuma
-- alteração em pricing_set_mapping_dependency_exists nem nos objetos já existentes.
--
-- Reaproveitamento explícito de decideMappingUpsert() (núcleo P16.2,
-- supabase/functions/_shared/pricing-justtcg-matching/mapping-upsert.ts): os 4 blocos de
-- decisão abaixo (INSERTED / NOOP_SAME_STATUS / bloqueio de overwrite divergente /
-- UPGRADED_TO_CONFIRMED) são a MESMA semântica dessa função pura, só expressos em SQL
-- porque este caminho de escrita é uma RPC (padrão vigente de todo o Bloco 4 do Pricing
-- Admin -- Edge Functions só existem hoje para o preview P16.3, que é read-only), nunca
-- uma segunda regra de persistência paralela ou divergente.
--
-- Autoentrada de pricing_set_refresh_state: NÃO reimplementada aqui. O trigger já
-- existente da migration 3932 (trg_pricing_set_mapping_sync_refresh_state, AFTER INSERT
-- OR UPDATE OF match_status) dispara sozinho sempre que este RPC grava match_status =
-- 'CONFIRMED' -- tanto no caminho de INSERT quanto no de UPDATE. Nenhum refresh é
-- disparado por este trigger (só INSERT/ON CONFLICT em pricing_set_refresh_state, com
-- next_due_at = now() -- o Set fica elegível para o dispatcher já existente, mas
-- continua PARADO até o próximo tick natural dele; este RPC não chama nenhuma Edge
-- Function de refresh).
--
-- Superfície de confiança / o que NÃO é revalidado aqui (decisão de escopo, registrada
-- explicitamente em vez de expandir silenciosamente): este RPC NÃO faz uma segunda
-- chamada à JustTCG para reconfirmar que external_set_id/external_set_name realmente
-- correspondem ao que a fonte devolveu -- isso exigiria rede dentro de PL/pgSQL (fora de
-- escopo do P16.4, mesmo padrão de admin_reclassify_pricing_set_mapping e
-- admin_update_pricing_set_mapping_details, migration 3942, que também nunca revalidam
-- contra a fonte externa). O que O RPC revalida sempre, server-side, ignorando qualquer
-- valor id enviado pelo browser além do necessário:
--   1. card_set existe e é elegível (mesmo critério da migration 3950: pertence a um
--      jogo suportado por fonte ativa -- hoje, literal POKEMON);
--   2. pricing_source existe e está is_active;
--   3. estado atual do mapping Set+fonte (ausente/PENDING/NOT_FOUND/REJECTED/CONFIRMED);
--   4. external_set_id não é vazio (mesma guarda de
--      ck_pricing_set_mapping_confirmed_requires_external_id, redundante e intencional);
--   5. um CONFIRMED existente com candidato DIFERENTE nunca é sobrescrito por este RPC --
--      exige o fluxo explícito já existente (admin_reclassify_pricing_set_mapping /
--      admin_update_pricing_set_mapping_details).
-- O frontend (Dialog de Sincronização, P16.3) nunca oferece um campo de texto livre para
-- external_set_id -- só o candidato literal devolvido pelo preview -- o que reduz a
-- superfície real de payload adulterado a "outro Set/fonte", já coberto pelos itens 1-3.
--
-- HARDENING (2026-08-26, revisão pré-aplicação -- gap de trust boundary identificado por
-- Fabrício antes de aplicar): esta RPC sozinha NUNCA foi (e continua não sendo) prova de que
-- external_set_id/external_set_name/match_method/match_evidence correspondem ao candidato
-- SAFE_CANDIDATE real da JustTCG -- ela só valida elegibilidade/fonte/estado do MAPPING, não
-- a PROVENIÊNCIA do candidato em si. Essa prova de proveniência foi movida para a camada
-- ACIMA desta RPC: `confirmarCorrespondenciaSet()` (Server Action,
-- web/app/pricing/mapeamentos-sets/actions.ts) agora REPETE o preview real
-- (pricing-set-matching-preview, mesmo núcleo P16.2) imediatamente antes de chamar esta RPC,
-- e só encaminha os 4 campos com o valor que essa resposta fresca do servidor devolveu --
-- nunca o que o browser enviou. A assinatura desta RPC foi deliberadamente MANTIDA (Set +
-- fonte + candidato + método + evidência): ela continua sendo, e precisa continuar sendo, a
-- autoridade transacional FINAL (idempotência, bloqueio de overwrite de CONFIRMED
-- divergente, proteção contra TOCTOU se outro admin confirmar entre o repreview da Server
-- Action e o INSERT/UPDATE aqui dentro) -- mudar a assinatura substituiria uma
-- responsabilidade por outra, não resolveria o gap. Ver cabeçalho de
-- `confirmarCorrespondenciaSet()` para o fluxo completo e os testes adversariais
-- (payload adulterado, candidato mudou, repreview não-SAFE_CANDIDATE) que provam isso.
--
-- 'PRICING_SET_MAPPING_CONFIRMED' já existe no CHECK de pricing_admin_action_log desde a
-- migration 3942 (reusado hoje por admin_reclassify_pricing_set_mapping) -- nenhuma
-- migration de schema incremental necessária além da função em si.

CREATE OR REPLACE FUNCTION public.admin_confirm_pricing_set_mapping(
  p_card_set_id uuid,
  p_pricing_source_id uuid,
  p_external_set_id text,
  p_external_set_name text,
  p_match_method text DEFAULT NULL,
  p_match_evidence jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_game_code text;
  v_source_active boolean;
  v_row public.pricing_set_mapping;
  v_external_id text;
  v_external_name text;
  v_evidence jsonb;
  v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  IF p_card_set_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_CARD_SET';
  END IF;
  IF p_pricing_source_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_SOURCE';
  END IF;

  v_external_id := NULLIF(BTRIM(p_external_set_id), '');
  v_external_name := NULLIF(BTRIM(p_external_set_name), '');
  IF v_external_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_EXTERNAL_ID';
  END IF;

  v_evidence := COALESCE(p_match_evidence, '{}'::jsonb);
  IF jsonb_typeof(v_evidence) IS DISTINCT FROM 'object' THEN
    v_evidence := '{}'::jsonb;
  END IF;

  -- Revalidação 1: Set existe e é elegível -- mesmo critério de
  -- admin_list_pricing_set_mappings / get_pricing_admin_overview (migration 3950):
  -- pertence a um jogo suportado por fonte ativa, hoje literal POKEMON.
  SELECT g.code INTO v_game_code
  FROM public.card_set cs
  JOIN public.expansion ex ON ex.id = cs.expansion_id
  JOIN public.game g ON g.id = ex.game_id
  WHERE cs.id = p_card_set_id
  FOR UPDATE OF cs;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SET_NOT_FOUND: id=%', p_card_set_id;
  END IF;
  IF v_game_code IS DISTINCT FROM 'POKEMON' THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SET_NOT_ELIGIBLE: id=%', p_card_set_id;
  END IF;

  -- Revalidação 2: fonte existe e está ativa -- nunca confia no is_active implícito de
  -- um payload antigo do browser.
  SELECT is_active INTO v_source_active FROM public.pricing_source WHERE id = p_pricing_source_id;
  IF v_source_active IS NULL THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SOURCE_NOT_FOUND: id=%', p_pricing_source_id;
  END IF;
  IF NOT v_source_active THEN
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_SOURCE_NOT_ACTIVE: id=%', p_pricing_source_id;
  END IF;

  -- Revalidação 3: estado atual do mapping Set+fonte (uq_pricing_set_mapping_card_set_source
  -- garante no máximo 1 linha) -- decide entre os 4 ramos de decideMappingUpsert().
  SELECT * INTO v_row
  FROM public.pricing_set_mapping
  WHERE card_set_id = p_card_set_id AND pricing_source_id = p_pricing_source_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- decideMappingUpsert(null, 'CONFIRMED') === "INSERTED".
    INSERT INTO public.pricing_set_mapping (
      card_set_id, pricing_source_id, external_set_id, external_set_name,
      match_status, match_method, match_evidence, confirmed_at, confirmed_by, last_checked_at
    ) VALUES (
      p_card_set_id, p_pricing_source_id, v_external_id, v_external_name,
      'CONFIRMED', p_match_method, v_evidence, now(), auth.uid(), now()
    )
    RETURNING id INTO v_id;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'PRICING_SET_MAPPING_CONFIRMED', 'PRICING_SET_MAPPING', v_id,
      jsonb_build_object(
        'outcome', 'INSERTED',
        'external_set_id', v_external_id, 'external_set_name', v_external_name,
        'match_method', p_match_method
      ));
    RETURN;
  END IF;

  IF v_row.match_status = 'CONFIRMED' THEN
    IF v_row.external_set_id = v_external_id THEN
      -- decideMappingUpsert(existing CONFIRMED, 'CONFIRMED') === "NOOP_SAME_STATUS":
      -- confirmação repetida idêntica -- idempotente, zero escrita nova (não dispara o
      -- trigger da 3932 de novo, não altera pricing_set_refresh_state).
      RETURN;
    END IF;

    -- decideMappingUpsert nunca sobrescreve um CONFIRMED existente por um novo candidato
    -- ("NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" na direção genérica) -- aqui, como o único
    -- newStatus possível desta RPC é CONFIRMED, um candidato realmente diferente precisa
    -- do fluxo explícito já existente, nunca deste caminho de confirmação inicial.
    RAISE EXCEPTION 'ADMIN_CONFIRM_PRICING_SET_MAPPING_ALREADY_CONFIRMED_DIFFERENT_CANDIDATE: este Set+fonte já está confirmado com outra correspondência -- use a edição de detalhes ou a reclassificação existente para trocar o vínculo.';
  END IF;

  -- PENDING / NOT_FOUND / REJECTED -> CONFIRMED: decideMappingUpsert() ===
  -- "UPGRADED_TO_CONFIRMED" nos 3 casos, sem distinção -- mesma regra aqui.
  UPDATE public.pricing_set_mapping SET
    external_set_id = v_external_id,
    external_set_name = v_external_name,
    match_status = 'CONFIRMED',
    match_method = COALESCE(p_match_method, match_method),
    match_evidence = v_evidence,
    confirmed_at = now(),
    confirmed_by = auth.uid(),
    last_checked_at = now(),
    updated_at = now()
  WHERE id = v_row.id;

  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'PRICING_SET_MAPPING_CONFIRMED', 'PRICING_SET_MAPPING', v_row.id,
    jsonb_build_object(
      'outcome', 'UPGRADED_TO_CONFIRMED', 'old_status', v_row.match_status,
      'external_set_id', v_external_id, 'external_set_name', v_external_name,
      'match_method', p_match_method
    ));
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_confirm_pricing_set_mapping(uuid, uuid, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_pricing_set_mapping(uuid, uuid, text, text, text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.admin_confirm_pricing_set_mapping(uuid, uuid, text, text, text, jsonb) IS
  'P16.4 -- persiste a confirmação de um pricing_set_mapping descoberto no preview P16.3 (SAFE_CANDIDATE). Reaproveita a semântica de decideMappingUpsert() (núcleo P16.2) expressa em SQL: ausente->INSERTED, CONFIRMED igual->NOOP idempotente, CONFIRMED com candidato diferente->bloqueado (usar edição/reclassificação existente), PENDING/NOT_FOUND/REJECTED->UPGRADED_TO_CONFIRMED. Revalida sempre server-side elegibilidade do Set (jogo POKEMON) e fonte ativa -- nunca revalida contra a JustTCG (fora de escopo, mesmo padrão de admin_reclassify_pricing_set_mapping). Autoentrada em pricing_set_refresh_state via trigger já existente da migration 3932 -- nenhum refresh é disparado aqui.';
