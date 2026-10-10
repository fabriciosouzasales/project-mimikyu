/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3980 - Alvos da descoberta de correspondência de Sets em lote
Status......: CONFIRMADO EXECUTADO (2026-10-10)
Frente......: PRICING-MODULE-RECOVERY-01 — Fase 3 (ampliar cobertura)
Mandato.....: Fabrício, 2026-10-10: "Vamos avançar para próxima ação do Plano!"

O que faz
  public.pricing_set_discovery_targets(p_pricing_source_id): lista os Sets
  elegíveis (Jogo POKEMON) SEM mapeamento CONFIRMED para a fonte, com Expansão,
  release_date, contagem de cartas ativas e o status atual do mapping (se houver).
  Consumida só pela Edge Function pricing-set-matching-preview (modo batch),
  depois da fronteira de identidade admin (JWT + is_admin) — por isso o EXECUTE
  é exclusivo de service_role. Somente leitura (STABLE, SECURITY INVOKER).
===============================================================================
*/
BEGIN;

CREATE OR REPLACE FUNCTION public.pricing_set_discovery_targets(p_pricing_source_id uuid)
RETURNS TABLE (
  card_set_id uuid,
  card_set_code text,
  card_set_name text,
  release_date date,
  expansion_code text,
  expansion_name text,
  expansion_release_order integer,
  active_card_count integer,
  current_match_status text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $f$
  SELECT cs.id, cs.code::text, cs.name::text, cs.release_date,
         ex.code::text, ex.name::text, ex.release_order,
         (SELECT count(*)::int FROM public.card c WHERE c.card_set_id = cs.id AND c.is_active),
         psm.match_status
    FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    JOIN public.game g ON g.id = ex.game_id AND g.code = 'POKEMON'
    LEFT JOIN public.pricing_set_mapping psm
           ON psm.card_set_id = cs.id AND psm.pricing_source_id = p_pricing_source_id
   WHERE psm.match_status IS DISTINCT FROM 'CONFIRMED'
   ORDER BY cs.release_date DESC NULLS LAST, cs.code;
$f$;

REVOKE ALL ON FUNCTION public.pricing_set_discovery_targets(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pricing_set_discovery_targets(uuid) TO service_role;
COMMENT ON FUNCTION public.pricing_set_discovery_targets(uuid) IS
  'Sets elegíveis sem mapeamento CONFIRMED para a fonte (3980). Só service_role — consumida pela Edge pricing-set-matching-preview em modo batch, após verificação admin.';

COMMIT;
