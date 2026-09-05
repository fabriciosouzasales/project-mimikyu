/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6101 - Create Pokemon Catalog Sourcing Run Triggers
Versão......: 1.1 (PROPOSTA — GATE 3 STAGING, REVISION-01)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01; revisado em ...-STAGING-REVISION-01)

REVISION-01 — o que mudou e por quê: a máquina de estados da v1.0 validava a
SEQUÊNCIA de transições (PENDING→ACQUIRING→PLANNING→terminal ou
PENDING→APPLYING→terminal) mas SEM considerar `run_type` — nada impedia, na
prática, um run DRY_RUN de sair de PENDING direto para APPLYING (a CASE
original listava PENDING → {ACQUIRING, APPLYING, FAILED, CANCELLED} para
QUALQUER run_type). O GATE 4 apontou isso como bloqueante, exigindo
enforcement tanto em CHECK (Query 6100, ck_pokemon_catalog_sourcing_run_
dry_run_never_applying) quanto na máquina de estados — corrigido aqui
tornando a CASE de transição condicional a OLD.run_type.

Mudança adicional (Fix 4 — observabilidade de ACQUIRING): esta revisão
também remove a responsabilidade de iniciar ACQUIRING do PLAN (Query 6104).
A transição PENDING→ACQUIRING agora só é válida via o novo auxiliar
`heartbeat_pokemon_catalog_sourcing_run()` (Query 6107), chamado pelo script
ANTES de iniciar a aquisição HTTP — tornando o estado ACQUIRING real e
durável (visível a outras sessões) enquanto a aquisição está em andamento,
em vez de ser atravessado apenas dentro da transação de PLAN. PLAN agora
exige status ATUAL = ACQUIRING como precondição (ver Query 6104 REVISION-01)
e só executa a transição ACQUIRING→PLANNING.

Regras de Negócio (matriz de transições REVISION-01, agora run_type-aware):
- run_type = DRY_RUN: PENDING → {ACQUIRING (via 6107), FAILED, CANCELLED};
  ACQUIRING → {PLANNING (via 6104), FAILED, CANCELLED}; PLANNING →
  {COMPLETED, COMPLETED_WITH_DIVERGENCES, FAILED, CANCELLED}.
- run_type = APPLY: PENDING → {APPLYING (via 6105), FAILED, CANCELLED};
  APPLYING → {COMPLETED, FAILED, CANCELLED}.
- FAILED pode também ser alcançado a qualquer momento por
  close_failed_pokemon_catalog_sourcing_run() (Query 6108), que reutiliza
  esta mesma máquina de estados (nenhuma transição nova é necessária — FAILED
  já é alcançável de qualquer estado ATIVO em ambos os fluxos).
- Demais regras inalteradas da v1.0: id/run_code/asset_source_id/run_type/
  preflight_run_id/created_at imutáveis; estados TERMINAL imutáveis;
  started_at/finished_at automáticos; INSERT sempre começa PENDING.

Pré-requisitos:
- Query 6100 v1.1 - Pokemon Catalog Sourcing Run Table (com a nova CHECK
  ck_pokemon_catalog_sourcing_run_dry_run_never_applying).
===============================================================================
*/

BEGIN;

-- 1. Normalização (inalterada da v1.0) ---------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_pokemon_catalog_sourcing_run()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.run_type := UPPER(BTRIM(NEW.run_type));
    NEW.status := UPPER(BTRIM(NEW.status));
    IF NEW.error_summary IS NOT NULL THEN
        NEW.error_summary := NULLIF(BTRIM(NEW.error_summary), '');
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.normalize_pokemon_catalog_sourcing_run()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_normalize_pokemon_catalog_sourcing_run
    BEFORE INSERT OR UPDATE ON public.pokemon_catalog_sourcing_run
    FOR EACH ROW
    EXECUTE FUNCTION public.normalize_pokemon_catalog_sourcing_run();

-- 2. Governança de máquina de estados (REVISION-01: run_type-aware) ----------

CREATE OR REPLACE FUNCTION public.govern_pokemon_catalog_sourcing_run()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_is_terminal BOOLEAN;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'PENDING' THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_MUST_START_PENDING: status inicial deve ser PENDING (recebido %).', NEW.status;
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.id IS DISTINCT FROM OLD.id THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_ID_IMMUTABLE';
        END IF;
        IF NEW.run_code IS DISTINCT FROM OLD.run_code THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_CODE_IMMUTABLE';
        END IF;
        IF NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_ASSET_SOURCE_IMMUTABLE';
        END IF;
        IF NEW.run_type IS DISTINCT FROM OLD.run_type THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_TYPE_IMMUTABLE';
        END IF;
        IF NEW.preflight_run_id IS DISTINCT FROM OLD.preflight_run_id THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_PREFLIGHT_IMMUTABLE';
        END IF;
        IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_CREATED_AT_IMMUTABLE';
        END IF;

        IF OLD.status IN ('COMPLETED', 'COMPLETED_WITH_DIVERGENCES', 'FAILED', 'CANCELLED')
           AND NEW.status IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_TERMINAL_STATUS_IMMUTABLE: % é terminal.', OLD.status;
        END IF;

        IF NEW.status IS DISTINCT FROM OLD.status THEN
            IF OLD.run_type = 'DRY_RUN' THEN
                CASE OLD.status
                    WHEN 'PENDING' THEN
                        IF NEW.status NOT IN ('ACQUIRING', 'FAILED', 'CANCELLED') THEN
                            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_INVALID_TRANSITION: DRY_RUN PENDING -> %.', NEW.status;
                        END IF;
                    WHEN 'ACQUIRING' THEN
                        IF NEW.status NOT IN ('PLANNING', 'FAILED', 'CANCELLED') THEN
                            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_INVALID_TRANSITION: DRY_RUN ACQUIRING -> %.', NEW.status;
                        END IF;
                    WHEN 'PLANNING' THEN
                        IF NEW.status NOT IN ('COMPLETED', 'COMPLETED_WITH_DIVERGENCES', 'FAILED', 'CANCELLED') THEN
                            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_INVALID_TRANSITION: DRY_RUN PLANNING -> %.', NEW.status;
                        END IF;
                    ELSE
                        RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_INVALID_TRANSITION: DRY_RUN estado de origem % desconhecido.', OLD.status;
                END CASE;
            ELSE -- APPLY
                CASE OLD.status
                    WHEN 'PENDING' THEN
                        IF NEW.status NOT IN ('APPLYING', 'FAILED', 'CANCELLED') THEN
                            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_INVALID_TRANSITION: APPLY PENDING -> %.', NEW.status;
                        END IF;
                    WHEN 'APPLYING' THEN
                        IF NEW.status NOT IN ('COMPLETED', 'FAILED', 'CANCELLED') THEN
                            RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_INVALID_TRANSITION: APPLY APPLYING -> %.', NEW.status;
                        END IF;
                    ELSE
                        RAISE EXCEPTION 'POKEMON_CATALOG_SOURCING_RUN_INVALID_TRANSITION: APPLY estado de origem % desconhecido.', OLD.status;
                END CASE;
            END IF;
        END IF;
    END IF;

    v_is_terminal := NEW.status IN ('COMPLETED', 'COMPLETED_WITH_DIVERGENCES', 'FAILED', 'CANCELLED');

    IF NEW.status IN ('ACQUIRING', 'APPLYING') THEN
        NEW.started_at := COALESCE(NEW.started_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.started_at END, CLOCK_TIMESTAMP());
    END IF;

    IF v_is_terminal THEN
        NEW.finished_at := COALESCE(NEW.finished_at, CLOCK_TIMESTAMP());
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.govern_pokemon_catalog_sourcing_run()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_govern_pokemon_catalog_sourcing_run
    BEFORE INSERT OR UPDATE ON public.pokemon_catalog_sourcing_run
    FOR EACH ROW
    EXECUTE FUNCTION public.govern_pokemon_catalog_sourcing_run();

-- 3. Touch updated_at (inalterada da v1.0) ------------------------------------

CREATE OR REPLACE FUNCTION public.touch_pokemon_catalog_sourcing_run_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.touch_pokemon_catalog_sourcing_run_updated_at()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_touch_pokemon_catalog_sourcing_run_updated_at
    BEFORE UPDATE ON public.pokemon_catalog_sourcing_run
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_pokemon_catalog_sourcing_run_updated_at();

COMMIT;
