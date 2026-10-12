/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3988 - Set externo sem numeração: casamento de cartas por nome (MFB)
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de execução. Nada aplicado no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-12
Mandato.....: Fabrício, 2026-10-12: "Ligar as cartas pelo nome"

Problema
  MFB (My First Battle) está mapeado no Set certo da JustTCG (my-first-battle-pokemon),
  mas as cartas desse produto não têm número impresso — a fonte as publica sem número e o
  número 01–34 do catálogo é artificial (TCGdex). O bootstrap casa por Set + número, então
  as 34 cartas ficaram NOT_FOUND e o refresh foi pausado (3979). Único Set nessa situação.

O que faz (precedente: 3981, Set externo compartilhado)
  1. pricing_set_mapping.external_unnumbered (boolean, default false) — opt-in explícito;
     não combinável com is_shared_external.
  2. Marca só o mapping do MFB (gate: exatamente 1 linha, Set externo esperado).
  3. Reabre o bootstrap do MFB (mesmo UPDATE da 3979): o dispatcher readquire as cartas e o
     matching roda com classifyCardMatchByName (Edge justtcg-set-bootstrap, código desta
     entrega). NOT_FOUND → CONFIRMED/PENDING é UPGRADE já previsto na RPC 3958.
  4. Despausa o refresh do MFB — só depois de conferir o resultado do matching.

Regra de casamento por nome (supabase/functions/_shared/pricing-justtcg-matching/card-matching.ts)
  - nome externo = nome base + qualificador opcional entre parênteses no fim;
  - "Basic X Energy" ≡ "X Energy";
  - igualdade exata de nome base (nunca prefixo/fuzzy);
  - SAFE se houver 1 candidato sem qualificador (versão comum preferida sobre "(Blue Border)")
    ou 1 candidato no total; ambiguidade → PENDING; nenhum → NOT_FOUND.
  Esperado: 32 CONFIRMED e 2 PENDING (Potion e Switch — a fonte só publica versões por deck).

Ordem de execução (cada PASSO numa chamada própria)
  PASSO 1  SQL  — coluna + flag do MFB (antes do deploy: o código novo lê a coluna).
  PASSO 2  Deploy da Edge Function justtcg-set-bootstrap.
  PASSO 3  SQL  — reabrir o bootstrap do MFB.
  PASSO 4  Aguardar o dispatcher (2-59/5) concluir aquisição + matching; conferir.
  PASSO 5  SQL  — despausar o refresh do MFB (só se o PASSO 4 tiver CONFIRMED > 0).

Reversão
  - A coluna só pode ser removida depois de voltar o deploy anterior da Edge (o código novo
    lê a coluna; sem ela, o bootstrap de qualquer Set falharia na leitura da flag).
  - Desligar só o MFB: UPDATE public.pricing_set_mapping SET external_unnumbered = false
    (mapping do MFB) e pausar o refresh de novo; mappings CONFIRMED podem ser rejeitados
    pela tela de Mapeamentos de Cartas.
===============================================================================
*/


-- ============================================================================
-- PASSO 1 — Coluna + flag do MFB
-- ============================================================================
BEGIN;

ALTER TABLE public.pricing_set_mapping
  ADD COLUMN external_unnumbered boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.pricing_set_mapping.external_unnumbered IS
  '3988: o Set externo não publica número de carta; o bootstrap casa as cartas por nome '
  '(classifyCardMatchByName). Opt-in explícito, só para Sets sem numeração impressa (ex.: MFB).';

ALTER TABLE public.pricing_set_mapping
  ADD CONSTRAINT ck_pricing_set_mapping_unnumbered_not_shared
  CHECK (NOT (external_unnumbered AND is_shared_external));

DO $$
DECLARE v_n integer;
BEGIN
  UPDATE public.pricing_set_mapping psm
     SET external_unnumbered = true, updated_at = now()
    FROM public.card_set cs
   WHERE cs.id = psm.card_set_id
     AND cs.code = 'MFB'
     AND psm.external_set_id = 'my-first-battle-pokemon'
     AND psm.match_status = 'CONFIRMED';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '3988_GATE: esperado 1 mapping MFB confirmado, encontrado %', v_n;
  END IF;
END $$;

COMMIT;

-- Verificação 1 (esperado: 1 linha MFB true; total true = 1)
SELECT cs.code, psm.external_set_id, psm.external_unnumbered, psm.is_shared_external
  FROM public.pricing_set_mapping psm JOIN public.card_set cs ON cs.id = psm.card_set_id
 WHERE psm.external_unnumbered;


-- ============================================================================
-- PASSO 2 — Deploy da Edge Function justtcg-set-bootstrap (código desta entrega)
-- ============================================================================


-- ============================================================================
-- PASSO 3 — Reabrir o bootstrap do MFB
-- Pré-check: sem lease ativo no bootstrap do MFB.
-- ============================================================================
BEGIN;

WITH alvo AS (
  SELECT bs.id AS bs_id, psm.id AS psm_id
    FROM public.pricing_set_bootstrap_state bs
    JOIN public.pricing_set_mapping psm ON psm.id = bs.pricing_set_mapping_id
    JOIN public.card_set cs ON cs.id = psm.card_set_id
   WHERE cs.code = 'MFB' AND psm.external_unnumbered
     AND bs.status = 'COMPLETE' AND bs.lease_until IS NULL
   FOR UPDATE OF bs
), reaberto AS (
  UPDATE public.pricing_set_bootstrap_state bs
     SET status = 'PENDING', acquisition_resume_offset = 0, attempt_count = 0,
         next_attempt_at = now(), cards_confirmed = NULL, cards_pending = NULL, cards_not_found = NULL,
         last_error_summary = NULL
    FROM alvo a
   WHERE bs.id = a.bs_id
  RETURNING a.psm_id
)
INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
SELECT NULL, 'PRICING_SET_BOOTSTRAP_REOPENED', 'PRICING_SET_MAPPING', r.psm_id,
       jsonb_build_object('card_set_code', 'MFB', 'rule', '3988', 'reason', 'external_unnumbered: casamento por nome')
  FROM reaberto r;

COMMIT;

-- Verificação 3 (esperado: status PENDING; 1 linha de log com rule 3988)
SELECT bs.status, bs.next_attempt_at
  FROM public.pricing_set_bootstrap_state bs
  JOIN public.pricing_set_mapping psm ON psm.id = bs.pricing_set_mapping_id
  JOIN public.card_set cs ON cs.id = psm.card_set_id
 WHERE cs.code = 'MFB';


-- ============================================================================
-- PASSO 4 — Conferência do matching (após o dispatcher concluir)
-- Esperado: bootstrap COMPLETE; ~32 CONFIRMED + 2 PENDING (Potion, Switch); 0 NOT_FOUND.
-- ============================================================================
SELECT pcm.match_status, count(*), string_agg(c.name || ' → ' || coalesce(pcm.external_card_name, '—'), ' | ' ORDER BY c.collector_order)
  FROM public.pricing_card_mapping pcm
  JOIN public.card c ON c.id = pcm.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
 WHERE cs.code = 'MFB'
 GROUP BY 1;


-- ============================================================================
-- PASSO 5 — Despausar o refresh do MFB (só com CONFIRMED > 0 no PASSO 4)
-- ============================================================================
BEGIN;

UPDATE public.pricing_set_refresh_state rs
   SET is_paused = false, pause_reason = NULL, paused_at = NULL, next_due_at = now(), updated_at = now()
  FROM public.pricing_set_mapping psm
  JOIN public.card_set cs ON cs.id = psm.card_set_id
 WHERE rs.pricing_set_mapping_id = psm.id
   AND cs.code = 'MFB' AND psm.external_unnumbered
   AND rs.is_paused
   AND EXISTS (SELECT 1 FROM public.pricing_card_mapping pcm JOIN public.card c ON c.id = pcm.card_id
                WHERE c.card_set_id = cs.id AND pcm.match_status = 'CONFIRMED');

COMMIT;

-- Verificação 5 (esperado: is_paused = false; após o próximo tick, last_outcome = SUCCESS)
SELECT rs.is_paused, rs.last_outcome, rs.next_due_at
  FROM public.pricing_set_refresh_state rs
  JOIN public.pricing_set_mapping psm ON psm.id = rs.pricing_set_mapping_id
  JOIN public.card_set cs ON cs.id = psm.card_set_id
 WHERE cs.code = 'MFB';
