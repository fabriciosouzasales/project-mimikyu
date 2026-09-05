/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6107 - Create Heartbeat Pokemon Catalog Sourcing Run Function
               (AUXILIAR — entrypoint)
Versão......: 1.0 (PROPOSTA — GATE 3 STAGING, REVISION-01)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, REVISION-01, item 4 da auditoria GATE 4; aplicado em 2026-09-04 via POKEMON-CATALOG-SOURCING-GATE-5-IMPLEMENTATION-01)

Justificativa de existência (por que este auxiliar é "estritamente
necessário" — GATE 4 explicitamente permitiu e pediu 6107+ para este fim):
Na v1.0 desta proposta, PLAN (Query 6104) fazia a transição PENDING →
ACQUIRING → PLANNING inteiramente DENTRO da própria transação — ou seja, o
estado ACQUIRING nunca era durável nem observável por outra sessão enquanto o
script chamador executava a aquisição HTTP de fato (que acontece ANTES de
PLAN ser chamado, fora do banco). O GATE 4 apontou isso como uma falha de
observabilidade: "DRY_RUN deve permanecer realmente em ACQUIRING enquanto o
caller executa HTTP, não apenas atravessar ACQUIRING dentro da transação de
PLAN." Esta função resolve isso: o script chama heartbeat_pokemon_catalog_
sourcing_run() ANTES de iniciar a aquisição HTTP (o que efetiva e
durav elmente transiciona PENDING → ACQUIRING, committado nesta própria
chamada) e pode chamá-la novamente periodicamente durante uma aquisição
longa apenas para atualizar heartbeat_at (mesma função, mesmo efeito
incremental) — sem repetir a transição de status quando já está em
ACQUIRING.

Descrição resumida:
- Se o run está em PENDING: transiciona para ACQUIRING e grava heartbeat_at
  = NOW() — esta é a ÚNICA forma de um run DRY_RUN entrar em ACQUIRING
  (PLAN, Query 6104, deixou de fazer essa transição nesta revisão).
- Se o run já está em ACQUIRING: apenas atualiza heartbeat_at = NOW() (usado
  para manter viva a "prova de vida" durante uma aquisição HTTP longa,
  evitando que o stale recovery de open_run — Query 6103, threshold de 30
  minutos — reconcilie prematuramente um run que ainda está legitimamente em
  andamento).
- Qualquer outro run_type ou status é rejeitado com RAISE EXCEPTION (esta
  função só faz sentido durante a fase de aquisição de um DRY_RUN; APPLY não
  tem fase de aquisição — Seção 10: "APPLY reutiliza snapshot aprovado e faz
  ZERO HTTP").

SECURITY DEFINER + SET search_path = ''. SERVICE_ROLE ONLY.

Grants:
- REVOKE EXECUTE de PUBLIC, anon, authenticated.
- GRANT EXECUTE a service_role.

Pré-requisitos:
- Query 6100/6101 v1.1 - Pokemon Catalog Sourcing Run (lifecycle run_type-
  aware, REVISION-01).
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.heartbeat_pokemon_catalog_sourcing_run(
    p_run_id UUID
)
RETURNS TABLE (
    outcome TEXT,
    run_id UUID,
    status TEXT,
    heartbeat_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_run public.pokemon_catalog_sourcing_run%ROWTYPE;
    v_now TIMESTAMPTZ := CLOCK_TIMESTAMP();
BEGIN
    SELECT * INTO v_run
    FROM public.pokemon_catalog_sourcing_run
    WHERE id = p_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'HEARTBEAT_POKEMON_CATALOG_SOURCING_RUN_NOT_FOUND: run % não encontrado.', p_run_id;
    END IF;
    IF v_run.run_type <> 'DRY_RUN' THEN
        RAISE EXCEPTION 'HEARTBEAT_POKEMON_CATALOG_SOURCING_RUN_WRONG_TYPE: heartbeat só se aplica à fase de aquisição de DRY_RUN (run % é %).', p_run_id, v_run.run_type;
    END IF;
    IF v_run.status NOT IN ('PENDING', 'ACQUIRING') THEN
        RAISE EXCEPTION 'HEARTBEAT_POKEMON_CATALOG_SOURCING_RUN_INVALID_STATUS: run % está em % (esperado PENDING ou ACQUIRING).', p_run_id, v_run.status;
    END IF;

    IF v_run.status = 'PENDING' THEN
        UPDATE public.pokemon_catalog_sourcing_run
        SET status = 'ACQUIRING',
            heartbeat_at = v_now
        WHERE id = p_run_id;
    ELSE
        UPDATE public.pokemon_catalog_sourcing_run
        SET heartbeat_at = v_now
        WHERE id = p_run_id;
    END IF;

    RETURN QUERY SELECT 'OK'::TEXT, p_run_id, 'ACQUIRING'::TEXT, v_now;
END;
$$;

COMMENT ON FUNCTION public.heartbeat_pokemon_catalog_sourcing_run(UUID) IS
    'AUXILIAR entrypoint — inicia (PENDING->ACQUIRING) ou renova (heartbeat_at) a fase de aquisição de um DRY_RUN, tornando ACQUIRING real e durável enquanto o caller executa HTTP. Ver docs/06a-pokemon-catalog-sourcing.md Seção 7. SERVICE_ROLE ONLY.';

REVOKE ALL ON FUNCTION public.heartbeat_pokemon_catalog_sourcing_run(UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.heartbeat_pokemon_catalog_sourcing_run(UUID)
    TO service_role;

COMMIT;
