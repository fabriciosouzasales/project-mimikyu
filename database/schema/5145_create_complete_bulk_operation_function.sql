/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5145 - complete_bulk_operation(): fecha o claim
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BULK-01-PHYSICAL-PROPOSAL-01)

Descrição...:
Helper INTERNO, par de `5144`. É o PASSO 8 de B1/B2: grava o
`result_summary` no claim, na MESMA transação da operação.

Sem esta chamada, o constraint trigger diferido de `5143` reprova o
COMMIT — que é precisamente o desenho: a operação só existe se o
resultado existir.

CONTRATO
--------
- só o dono da linha pode completá-la (defesa em profundidade; o
  chamador já é SECURITY DEFINER, mas o helper não confia nisso);
- `result_summary` NULL é rejeitado aqui, não empurrado para o trigger
  — falhar cedo dá mensagem melhor;
- completar duas vezes a mesma operação é rejeitado: sobrescrever um
  resultado já gravado significaria que o chamador perdeu o controle do
  fluxo, e silenciar isso esconderia o defeito.

SEGURANÇA
---------
`SECURITY DEFINER`, `search_path = ''`, owner `postgres`, `EXECUTE`
revogado de PUBLIC/anon/authenticated/service_role. Não é RPC pública.

Dependências: public.bulk_operation (5142), trigger de 5143,
public.claim_bulk_operation() (5144).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, ledger `20260908003951`, na rodada
`COLLECTIONS-BULK-01-IMPLEMENTATION-01` (5142-5145) /
`-POST-AUDIT-HARDENING-REVISION-02` (5146). Validada pelo harness `5821`
v1.3 — TOTAL 39 / PASS 36 / FAIL 0 / NOT PROVEN 3, com baseline 0 e
postcheck pos-ROLLBACK 0; os 3 NOT PROVEN sao exatamente K01/K02/K03,
provados externamente em duas sessoes psql persistentes (A e B, com role
temporaria de teste detentora de EXECUTE explicito nos helpers e sem
acesso direto a tabela) mais observador externo one-shot via SQL Editor
do Supabase. Resultado efetivo: 39/39 provados.

Promovida para `database/schema/` em `COLLECTIONS-BULK-01-SCHEMA-
PROMOTION-01`. A copia historica permanece em
`database/proposals/2026-09-07-bulk-operations-foundation/`, junto com o
harness `5821`, o roteiro `CONCURRENCY-PROOF-BULK-CLAIM.sql` e o
`README.md` da rodada — esses tres NAO sao promovidos, por convencao.
A promocao alterou apenas cabecalho/rodape: o corpo executavel
permanece byte-identico ao da copia em proposals.
================================================================
*/

BEGIN;

CREATE FUNCTION public.complete_bulk_operation(
    p_operation_id   UUID,
    p_result_summary JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_owner    UUID;
    v_affected INTEGER;
BEGIN
    v_owner := (select auth.uid());

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
    END IF;

    IF p_result_summary IS NULL THEN
        RAISE EXCEPTION 'result_summary nao pode ser NULL' USING ERRCODE = '22023';
    END IF;

    UPDATE public.bulk_operation b
       SET result_summary = p_result_summary
     WHERE b.id            = p_operation_id
       AND b.owner_user_id = v_owner
       AND b.result_summary IS NULL;   -- completar duas vezes NAO e no-op silencioso

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    IF v_affected = 0 THEN
        -- Mensagem unica para inexistente / de outro dono / ja completada:
        -- nao enumera operacoes alheias (mesma disciplina de nao-enumeracao
        -- do helper 5122 do Binder).
        RAISE EXCEPTION
            'bulk operation not found, not owned by caller, or already completed'
            USING ERRCODE = '22023';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.complete_bulk_operation(UUID, JSONB) IS
    'Helper INTERNO. Grava result_summary no claim, na mesma transacao da operacao (passo 8 de B1/B2). Sem esta chamada o constraint trigger de 5143 reprova o COMMIT. Rejeita NULL, linha de outro dono e recompletar. EXECUTE revogado de todos os papeis.';

REVOKE EXECUTE ON FUNCTION public.complete_bulk_operation(UUID, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5821`, grupo T.
*/
