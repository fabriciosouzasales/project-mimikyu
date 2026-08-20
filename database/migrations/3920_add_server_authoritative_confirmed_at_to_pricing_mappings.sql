-- 3920_add_server_authoritative_confirmed_at_to_pricing_mappings
--
-- P14.4.4 fechamento tecnico — Parte 1: mesmo defeito de autoridade temporal corrigido
-- em P13.2 (pricing_sync_run.started_at/finished_at), agora em confirmed_at de
-- pricing_card_mapping/pricing_set_mapping. Ate aqui, confirmed_at era computado pelo
-- relogio do processo cliente (scripts/sync-justtcg-pricing.ts) e enviado como valor
-- literal em INSERT/UPDATE/RPC — o servidor nunca era autoridade sobre esse instante,
-- ao contrario de finished_at (ja corrigido). Evidencia real do desvio: auditoria
-- pos-reparo do run 66c9e878-2469-453c-86ab-e31875f68f79 (2026-08-19) mostrou as 53
-- linhas promovidas com confirmed_at ~62s POSTERIOR ao finished_at do proprio run,
-- inconsistencia impossivel se o servidor fosse a autoridade.
--
-- Regra da trigger (BEFORE INSERT OR UPDATE, compartilhada pelas duas tabelas — mesmo
-- padrao de set_updated_at()):
--   - match_status em (CONFIRMED, REJECTED) e a linha nao estava antes nesse mesmo
--     conjunto (INSERT, ou UPDATE vindo de PENDING/NOT_FOUND) -> confirmed_at = now()
--     do servidor, ignorando qualquer valor enviado pelo cliente;
--   - match_status em (CONFIRMED, REJECTED) e a linha JA estava nesse conjunto (inclusive
--     troca CONFIRMED<->REJECTED) -> preserva OLD.confirmed_at (instante historico da
--     primeira decisao nunca e reescrito por reconfirmacao/reprocessamento posterior);
--   - match_status em (PENDING, NOT_FOUND) -> confirmed_at = NULL, respeitando os CHECKs
--     ck_pricing_card_mapping_confirmation_consistency / ck_pricing_set_mapping_confirmation_consistency
--     ja existentes (que continuam validos e inalterados).
-- confirmed_by NUNCA e tocado por esta trigger — continua vindo exclusivamente do
-- operador/cliente, exatamente como antes.
--
-- Escopo estrito: cria a trigger para gravacoes FUTURAS. Nao faz backfill/UPDATE nas
-- 53 linhas ja confirmadas pelo reparo real (nem em nenhuma outra linha existente) —
-- os timestamps historicos ja gravados permanecem exatamente como estao.
--
-- CONFIRMADO EXECUTADO em produção (Supabase MCP apply_migration) em 2026-08-19.
-- Testado transacionalmente (BEGIN/ROLLBACK, 6 cenários) antes da aplicação real.

CREATE OR REPLACE FUNCTION public.set_pricing_mapping_confirmed_at_authority()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    decided_statuses CONSTANT text[] := ARRAY['CONFIRMED', 'REJECTED'];
BEGIN
    IF NEW.match_status = ANY (decided_statuses) THEN
        IF TG_OP = 'INSERT' OR NOT (OLD.match_status = ANY (decided_statuses)) THEN
            -- Criacao ja decidida, ou primeira transicao de PENDING/NOT_FOUND para
            -- CONFIRMED/REJECTED: confirmed_at e o relogio do servidor, nunca o valor
            -- enviado pelo cliente.
            NEW.confirmed_at := now();
        ELSE
            -- Ja estava CONFIRMED/REJECTED (inclusive troca entre os dois, ou
            -- reafirmacao do mesmo status): preserva o instante historico da primeira
            -- decisao — nunca reescrito por reprocessamento/reconfirmacao posterior.
            NEW.confirmed_at := OLD.confirmed_at;
        END IF;
    ELSE
        -- PENDING/NOT_FOUND: sem instante de confirmacao (mesma regra dos CHECKs
        -- ck_..._confirmation_consistency ja existentes — NULL e obrigatorio aqui).
        NEW.confirmed_at := NULL;
    END IF;

    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_pricing_card_mapping_confirmed_at_authority
BEFORE INSERT OR UPDATE ON public.pricing_card_mapping
FOR EACH ROW EXECUTE FUNCTION public.set_pricing_mapping_confirmed_at_authority();

CREATE TRIGGER trg_pricing_set_mapping_confirmed_at_authority
BEFORE INSERT OR UPDATE ON public.pricing_set_mapping
FOR EACH ROW EXECUTE FUNCTION public.set_pricing_mapping_confirmed_at_authority();
