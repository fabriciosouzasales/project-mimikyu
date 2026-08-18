-- Query 3909 — CONFIRMADO EXECUTADO (Incremento P13.2 — correção pós-auditoria do piloto real
-- de 2026-08-18). Aplicada via Supabase MCP no mesmo dia.
--
-- Contexto: a auditoria pós-piloto do P13.2 (2026-08-18) encontrou pricing_sync_run.started_at
-- e .finished_at sistematicamente divergentes do relógio real do servidor em TODOS os runs já
-- existentes (P8/JustTCG de 2026-08-17 e P13.2/PTAX de 2026-08-18) — causa raiz: os dois
-- adapters (scripts/sync-justtcg-pricing.ts e scripts/sync-ptax-fx-rate.ts) capturam
-- new Date().toISOString() no relógio do processo cliente (máquina local de Fabrício) e
-- gravam esse valor explicitamente, sobrescrevendo o default now() da coluna, enquanto
-- created_at/updated_at/pricing_sync_run_call.called_at sempre usam now() do próprio banco —
-- um desvio de relógio do cliente aparece como uma inversão temporal aparente entre essas
-- colunas (ver ADR-031, decisão "PostgreSQL é a autoridade dos timestamps persistidos").
--
-- Esta migration move essa autoridade para o próprio Postgres via trigger dedicado — nunca
-- consolidada em set_updated_at() (função genérica compartilhada por dezenas de outras
-- tabelas do projeto, fora de escopo desta correção). Não altera nenhuma linha histórica
-- (nenhum UPDATE/backfill aqui) — os 6 pricing_sync_run existentes mantêm o desvio já
-- documentado, apenas toda gravação NOVA a partir de agora passa a ser imune a ele.
--
-- Testado transacionalmente (BEGIN/ROLLBACK) contra 10 cenários antes desta aplicação real:
-- started_at client-side incorreto substituído; started_at ausente recebe servidor;
-- PROCESSING->COMPLETED recebe finished_at do servidor; finished_at client-side incorreto
-- substituído; COMPLETED_WITH_ERRORS e FAILED recebem finished_at; update posterior de run
-- terminal preserva finished_at original; run não terminal mantém finished_at NULL; regras
-- MANUAL/SCHEDULED e confirmed_by permanecem válidas; índices de concorrência da Query 3907
-- continuam funcionando; nenhuma linha histórica real foi modificada. 10/10 aprovados.
-- Estados terminais tratados: COMPLETED, COMPLETED_WITH_ERRORS, FAILED (pedido explícito) e
-- CANCELLED (incluído por consistência com ck_pricing_sync_run_finished_consistency, que já
-- exige finished_at NOT NULL para CANCELLED — divergência sinalizada explicitamente, nunca
-- aplicada silenciosamente).

CREATE OR REPLACE FUNCTION public.set_pricing_sync_run_server_timestamps()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    terminal_statuses CONSTANT text[] := ARRAY['COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED', 'CANCELLED'];
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- started_at é sempre o relógio do servidor, independentemente do valor enviado
        -- pelo cliente (nenhum adapter deveria mais enviar um valor, mas a garantia vale
        -- mesmo que envie).
        NEW.started_at := now();
        -- Cobertura defensiva: se algum caminho futuro inserir um run já em status
        -- terminal num único INSERT (nenhum adapter atual faz isso), finished_at também
        -- é atribuído pelo servidor aqui, nunca pelo cliente.
        IF NEW.status = ANY (terminal_statuses) THEN
            NEW.finished_at := now();
        END IF;
        RETURN NEW;
    END IF;

    -- TG_OP = 'UPDATE'
    IF OLD.status = ANY (terminal_statuses) THEN
        -- Run já terminal: finished_at é imutável a partir daqui — qualquer novo valor
        -- enviado pelo cliente (ou por outra transição de status) é ignorado.
        NEW.finished_at := OLD.finished_at;
    ELSIF NEW.status = ANY (terminal_statuses) THEN
        -- Primeira transição de não-terminal (RECEIVED/PROCESSING) para terminal:
        -- finished_at é atribuído pelo relógio do servidor, nunca pelo valor do cliente.
        NEW.finished_at := now();
    END IF;
    -- Demais casos (ex.: RECEIVED -> PROCESSING, ou UPDATE que não muda status):
    -- finished_at permanece o que já estava, sem regra especial.

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.set_pricing_sync_run_server_timestamps() IS
  'Autoridade temporal do servidor para pricing_sync_run: started_at (todo INSERT) e finished_at (primeira transição para status terminal) são sempre now() do Postgres, nunca o valor enviado pelo cliente. Runs já terminais nunca têm finished_at recalculado. Dedicado a esta tabela — nunca consolidado em set_updated_at(), que é compartilhada por outras tabelas. Ver ADR-031 e Query 3909.';

-- Dedicado a esta tabela (nunca consolidado em set_updated_at(), compartilhada por outras
-- tabelas) — dispara BEFORE INSERT OR UPDATE, antes das CHECKs de consistência de
-- finished_at (ck_pricing_sync_run_finished_consistency, ck_pricing_sync_run_finished_after_started),
-- garantindo que a CHECK sempre veja o valor final já atribuído pelo servidor.
CREATE TRIGGER trg_pricing_sync_run_server_timestamps
    BEFORE INSERT OR UPDATE ON public.pricing_sync_run
    FOR EACH ROW EXECUTE FUNCTION public.set_pricing_sync_run_server_timestamps();
