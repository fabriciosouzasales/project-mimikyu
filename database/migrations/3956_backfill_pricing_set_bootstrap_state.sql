-- STATUS: PROPOSTA -- ainda NAO aplicada em producao. Testada em BEGIN/ROLLBACK nesta
-- rodada (P16.5.1, item "backfill seguro dos 45 historicos" do escopo autorizado por
-- Fabricio em 2026-08-26). Aguarda autorizacao explicita para aplicacao real.
--
-- REVISAO POS-REVIEW (mesmo dia, antes de qualquer aplicacao) -- Ponto 1 de Fabricio: o
-- mesmo criterio de completude usado aqui no backfill precisa ser IDENTICO ao que
-- close_pricing_set_bootstrap_attempt() (3955) agora exige para provar MATCHING_COMPLETE no
-- banco -- senao o backfill poderia marcar COMPLETE um Set que o proprio RPC, se rodasse
-- hoje, recusaria como RECONCILIATION_INCOMPLETE. Adicionado: exigir tambem que todo
-- pricing_card_mapping CONFIRMED tenha ao menos 1 pricing_source_card_identity CONFIRMED com
-- identity_role IN ('PRIMARY','ALTERNATE') -- mesmo gate ja usado pelo dispatcher de
-- price-refresh (3933). Reconfirmado ao vivo nesta rodada: essa exigencia adicional NAO muda
-- o resultado -- continuam sendo 45 Sets COMPLETE e SWSH8 como unico PENDING (zero Sets entre
-- os 45 tem qualquer mapping CONFIRMED sem identity).
--
-- Contexto: o trigger de autoentry criado em 3953 só dispara em INSERT/UPDATE futuros
-- de pricing_set_mapping.match_status -- os 46 pricing_set_mapping já CONFIRMED antes
-- desta migration nunca disparariam o trigger retroativamente. Este arquivo faz esse
-- backfill em 2 passos, usando o criterio de completude ja validado nesta sessao --
-- count(cartas ativas locais do Set) = count(pricing_card_mapping daquela fonte para
-- essas cartas) E zero mappings CONFIRMED sem identity, aplicado só a
-- pricing_set_mapping.match_status='CONFIRMED'.
--
-- Passo 1 -- os 45 Sets que já satisfazem o criterio entram direto como COMPLETE, com
-- cards_confirmed/cards_pending/cards_not_found computados a partir dos
-- pricing_card_mapping reais (nao zerados/estimados) -- da observabilidade imediata e
-- correta assim que a tabela existe.
--
-- Passo 2 -- qualquer pricing_set_mapping CONFIRMED que ainda nao tenha uma linha em
-- pricing_set_bootstrap_state (ou seja, nao satisfez o criterio do Passo 1 -- na pratica
-- hoje, só SWSH8) entra como PENDING, elegivel para o bootstrap automatico assim que a
-- Edge Function/cron correspondente for criada (fora do escopo desta rodada). É
-- exatamente esta lacuna -- SWSH8 CONFIRMED mas invisivel para qualquer mecanismo
-- automatico -- que motivou todo o Incremento P16.5 (ver diagnostico forense desta
-- mesma sessao).

INSERT INTO public.pricing_set_bootstrap_state (
  pricing_set_mapping_id, status, next_attempt_at,
  cards_confirmed, cards_pending, cards_not_found, last_outcome
)
SELECT
  s.pricing_set_mapping_id,
  'COMPLETE',
  now(),
  s.confirmed_count,
  s.pending_count,
  s.not_found_count,
  'MATCHING_COMPLETE'
FROM (
  SELECT
    psm.id AS pricing_set_mapping_id,
    count(DISTINCT c.id) AS local_active_cards,
    count(DISTINCT pcm.id) AS mapping_count,
    count(*) FILTER (WHERE pcm.match_status = 'CONFIRMED') AS confirmed_count,
    count(*) FILTER (WHERE pcm.match_status = 'PENDING') AS pending_count,
    count(*) FILTER (WHERE pcm.match_status = 'NOT_FOUND') AS not_found_count,
    count(*) FILTER (WHERE pcm.match_status = 'CONFIRMED' AND NOT EXISTS (
      SELECT 1 FROM public.pricing_source_card_identity psci
      WHERE psci.pricing_card_mapping_id = pcm.id
        AND psci.match_status = 'CONFIRMED'
        AND psci.identity_role IN ('PRIMARY', 'ALTERNATE')
    )) AS confirmed_missing_identity
  FROM public.pricing_set_mapping psm
  JOIN public.card c
    ON c.card_set_id = psm.card_set_id AND c.is_active = true
  LEFT JOIN public.pricing_card_mapping pcm
    ON pcm.card_id = c.id AND pcm.pricing_source_id = psm.pricing_source_id
  WHERE psm.match_status = 'CONFIRMED'
  GROUP BY psm.id
) s
WHERE s.local_active_cards = s.mapping_count
  AND s.local_active_cards > 0
  AND s.confirmed_missing_identity = 0
ON CONFLICT (pricing_set_mapping_id) DO NOTHING;

INSERT INTO public.pricing_set_bootstrap_state (pricing_set_mapping_id, status, next_attempt_at)
SELECT psm.id, 'PENDING', now()
FROM public.pricing_set_mapping psm
WHERE psm.match_status = 'CONFIRMED'
ON CONFLICT (pricing_set_mapping_id) DO NOTHING;
