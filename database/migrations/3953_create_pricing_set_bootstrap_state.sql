-- STATUS: PROPOSTA -- ainda NAO aplicada em producao. Testada em BEGIN/ROLLBACK nesta
-- rodada (P16.5.1 -- Bootstrap Automatico de Cartas, item 1 do escopo autorizado por
-- Fabricio em 2026-08-26). Aguarda autorizacao explicita para aplicacao real.
--
-- Revisao pos-review (mesmo dia): 'RECONCILIATION_INCOMPLETE' adicionado ao vocabulario de
-- last_outcome -- usado pela migration 3955 quando um MATCHING_COMPLETE reivindicado pelo
-- caller nao se prova no banco (ver 3955 para o desenho completo da prova). 'MAX_ATTEMPTS_EXCEEDED'
-- permanece no vocabulario de pause_reason por compatibilidade futura, mas nenhuma logica
-- automatica desta rodada o aciona mais -- ver 3955.
--
-- Contexto: fecha o desenho arquitetural do Incremento P16.5 (Fases 1-4, ja aprovadas
-- em rodadas anteriores desta mesma sessao) -- Opcao B (bootstrap automatico embutido
-- no primeiro refresh, mas como fase SEPARADA e durável, nunca dentro do core de
-- price-refresh). Este arquivo cria pricing_set_bootstrap_state, o espelho estrutural
-- de pricing_set_refresh_state (migration 3930) para a fase de aquisicao/matching de
-- cartas -- 1 linha por pricing_set_mapping_id, nunca por Set isolado (chave é sempre
-- Set x Fonte, mesma disciplina de 3930).
--
-- Diferencas deliberadas frente a pricing_set_refresh_state (motivadas pela revisao
-- critica de Fabricio nas Fases 3/4 desta sessao):
--  1. `status` (PENDING/ACQUIRING/MATCHING/COMPLETE/PAUSED) é a UNICA fonte de verdade
--     de fase -- refresh_state nao tem conceito de fase (é um ciclo continuo), entao
--     nao tem este campo. PAUSED é um VALOR de status aqui, nao um boolean paralelo
--     (isso evita a ambiguidade "is_paused=true mas status diz outra coisa").
--  2. Claim nunca depende do valor de `status` (exceto excluir COMPLETE/PAUSED) --
--     retomada dentro da mesma fase (ex.: duas paginas de ACQUIRING) usa o mesmo lease
--     +checkpoint da fase de refresh, sem reverter `status`.
--  3. `next_attempt_at` (nao `next_due_at`): nomeado deliberadamente diferente porque
--     bootstrap nao é ciclico -- uma vez COMPLETE, nunca mais reagenda sozinho.
--  4. `attempt_count` representa falhas CONSECUTIVAS sem progresso (correcao 2 exigida
--     por Fabricio nesta rodada) -- resetado pelo RPC de checkpoint sempre que a
--     aquisicao avanca com sucesso, nao só quando chega a COMPLETE. Ver migration 3955.
--  5. `cards_confirmed`/`cards_pending`/`cards_not_found` só existem preenchidos em
--     COMPLETE (par obrigatorio via CHECK) -- dá observabilidade imediata de quantas
--     cartas de fato ficaram com identidade utilizável ao fim do bootstrap, sem
--     confundir "bootstrap terminou" com "todo o Set tem preco disponivel" (ver Fase 3,
--     ponto 6 -- essas são duas propriedades distintas, nunca uma implicando a outra
--     automaticamente na UI).
--
-- Reaproveitamento deliberado de infraestrutura ja existente (nenhuma nova):
--  - Runs de bootstrap usam run_type='CARD_SYNC' em pricing_sync_run -- os dois indices
--    unicos parciais ja existentes (3907: (source,run_type); 3926: (source) WHERE
--    run_type IN (CARD_SYNC,PRICE_REFRESH)) ja impedem sozinhos: (a) dois CARD_SYNC
--    simultaneos da mesma fonte, e (b) CARD_SYNC e PRICE_REFRESH simultaneos da mesma
--    fonte. Nenhum indice novo é necessario para a Política A (serializacao total por
--    fonte), que já é o comportamento vigente confirmado nesta sessão.
--  - Lease de 180s e SELECT...FOR UPDATE SKIP LOCKED: mesmo padrao de
--    open_pricing_set_refresh_attempt (3933).
--  - set_updated_at(): funcao ja existente, reaproveitada sem alteracao.

CREATE TABLE public.pricing_set_bootstrap_state (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_set_mapping_id uuid NOT NULL UNIQUE
    REFERENCES public.pricing_set_mapping(id) ON DELETE CASCADE,

  status text NOT NULL DEFAULT 'PENDING',

  acquisition_resume_offset integer NOT NULL DEFAULT 0,
  attempt_count integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),

  lease_until timestamptz NULL,
  leased_by uuid NULL REFERENCES public.pricing_sync_run(id) ON DELETE SET NULL,
  last_started_at timestamptz NULL,

  pause_reason text NULL,
  paused_at timestamptz NULL,

  last_outcome text NOT NULL DEFAULT 'NEVER_RUN',
  last_error_summary text NULL,
  last_sync_run_id uuid NULL REFERENCES public.pricing_sync_run(id) ON DELETE SET NULL,

  cards_confirmed integer NULL,
  cards_pending integer NULL,
  cards_not_found integer NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_psbs_status
    CHECK (status IN ('PENDING', 'ACQUIRING', 'MATCHING', 'COMPLETE', 'PAUSED')),
  CONSTRAINT ck_psbs_lease_pair
    CHECK ((lease_until IS NULL) = (leased_by IS NULL)),
  CONSTRAINT ck_psbs_pause_pair
    CHECK (
      (status <> 'PAUSED' AND pause_reason IS NULL AND paused_at IS NULL)
      OR (status = 'PAUSED' AND pause_reason IS NOT NULL AND paused_at IS NOT NULL)
    ),
  CONSTRAINT ck_psbs_pause_reason
    CHECK (pause_reason IS NULL OR pause_reason IN ('SET_TERMINAL_ERROR', 'MAX_ATTEMPTS_EXCEEDED', 'MANUAL_PAUSE')),
  CONSTRAINT ck_psbs_last_outcome
    CHECK (last_outcome IN ('NEVER_RUN', 'NO_MORE_PAGES', 'BUDGET_STOPPED', 'DEADLINE_STOPPED',
                             'MATCHING_COMPLETE', 'RECONCILIATION_INCOMPLETE', 'TRANSIENT_ERROR',
                             'SET_TERMINAL_ERROR', 'AUTH_FAILURE', 'MAX_ATTEMPTS_EXCEEDED')),
  CONSTRAINT ck_psbs_resume_offset_nonneg CHECK (acquisition_resume_offset >= 0),
  CONSTRAINT ck_psbs_attempt_count_nonneg CHECK (attempt_count >= 0),
  CONSTRAINT ck_psbs_complete_counts
    CHECK (
      (status = 'COMPLETE' AND cards_confirmed IS NOT NULL AND cards_pending IS NOT NULL AND cards_not_found IS NOT NULL)
      OR (status <> 'COMPLETE' AND cards_confirmed IS NULL AND cards_pending IS NULL AND cards_not_found IS NULL)
    )
);

-- Ordenacao de claim identica a ix_prs_claim (3930): proximos por next_attempt_at,
-- desempate por last_started_at (NULLS FIRST -- nunca tentado ainda tem prioridade
-- sobre um que já foi tentado e falhou), desempate final por id para determinismo.
CREATE INDEX ix_psbs_claim
  ON public.pricing_set_bootstrap_state (next_attempt_at, last_started_at NULLS FIRST, id)
  WHERE status NOT IN ('COMPLETE', 'PAUSED');

CREATE INDEX ix_psbs_lease_observability
  ON public.pricing_set_bootstrap_state (lease_until)
  WHERE lease_until IS NOT NULL;

CREATE TRIGGER trg_pricing_set_bootstrap_state_set_updated_at
  BEFORE UPDATE ON public.pricing_set_bootstrap_state
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Autoentry: espelha trg_pricing_set_mapping_sync_refresh_state (3932), com uma
-- diferenca deliberada -- aqui é DO NOTHING em conflito (nunca ON CONFLICT DO UPDATE),
-- porque bootstrap nao é ciclico. Uma vez que a linha existe (em qualquer status,
-- inclusive COMPLETE ou PAUSED), uma reconfirmacao do Set-level match_status='CONFIRMED'
-- NUNCA deve reabrir ou reagendar o bootstrap automaticamente -- isso exigiria uma acao
-- humana explicita (fora de escopo do P16.5.1: nenhum mecanismo de "reabrir bootstrap"
-- é criado nesta rodada).
CREATE OR REPLACE FUNCTION public.trg_pricing_set_mapping_sync_bootstrap_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.match_status = 'CONFIRMED' THEN
    INSERT INTO public.pricing_set_bootstrap_state (pricing_set_mapping_id, next_attempt_at)
    VALUES (NEW.id, now())
    ON CONFLICT (pricing_set_mapping_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_pricing_set_mapping_sync_bootstrap_state
  AFTER INSERT OR UPDATE OF match_status ON public.pricing_set_mapping
  FOR EACH ROW EXECUTE FUNCTION trg_pricing_set_mapping_sync_bootstrap_state();

ALTER TABLE public.pricing_set_bootstrap_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
  ON public.pricing_set_bootstrap_state
  FOR SELECT
  TO public
  USING (is_admin());

REVOKE ALL ON public.pricing_set_bootstrap_state FROM PUBLIC;
GRANT SELECT ON public.pricing_set_bootstrap_state TO authenticated;
GRANT SELECT, INSERT, UPDATE, REFERENCES, TRIGGER, TRUNCATE ON public.pricing_set_bootstrap_state TO service_role;
