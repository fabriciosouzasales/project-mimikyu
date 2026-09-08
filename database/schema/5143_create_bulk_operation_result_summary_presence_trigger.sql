/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5143 - bulk_operation: invariante de commit (result_summary)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BULK-01-PHYSICAL-PROPOSAL-01, decisão R9)

Descrição...:
Torna ESTRUTURAL o invariante I4: nenhuma linha PERSISTENTE de
`bulk_operation` pode ter `result_summary` NULL.

POR QUE NÃO É `NOT NULL` NEM `CHECK`
------------------------------------
O claim nasce ANTES do resultado — `5144` insere a linha logo no início
da operação, e `5145` a completa no fim, na MESMA transação. Um
`NOT NULL` na coluna impediria o próprio claim.

`CHECK` também não serve: PostgreSQL não permite `CHECK` DEFERRABLE
(é sempre NOT DEFERRABLE). Só um CONSTRAINT TRIGGER pode ser
`DEFERRABLE INITIALLY DEFERRED`.

Precedente literal no projeto: `5059`
(`validate_collection_reference_presence`), `5057`, `5058` — mesma
técnica, mesmo padrão de segurança.

VALIDA O ESTADO FINAL, NÃO `NEW`
--------------------------------
Exigência explícita do mandato, e é o ponto que faz o trigger valer
alguma coisa. O trigger NÃO inspeciona `NEW.result_summary` — esse
valor é o do instante do INSERT, quando result_summary é
LEGITIMAMENTE NULL. Ele RECONSULTA `bulk_operation` pelo `NEW.id` no
momento do disparo (fim da transação) e avalia o ESTADO FINAL da linha,
já com o UPDATE de `5145` aplicado.

Consequência: se `5145` não rodar, ou rodar e ser desfeito, o COMMIT
falha. É exatamente o que se quer.

`AFTER INSERT OR UPDATE`, não só INSERT: sem grants de UPDATE para
cliente nenhum, o caminho de regressão seria uma RPC futura zerando
`result_summary`. Cobrir UPDATE é defesa em profundidade barata.

LINHA APAGADA NA MESMA TRANSAÇÃO
--------------------------------
O trigger diferido dispara mesmo que a linha tenha sido removida
depois. Reconsulta não encontra nada -> não há invariante a violar ->
retorna sem erro. Tratado explicitamente, não por acidente.

SEGURANÇA
---------
`SECURITY DEFINER`, `search_path = ''`, owner `postgres`,
`RETURNS TRIGGER` (impede chamada direta como função comum) e `EXECUTE`
revogado de `PUBLIC`/`anon`/`authenticated`/`service_role`. O disparo do
trigger NÃO depende desse privilégio. Mesmo padrão de `5059`/`5083`.

Dependências: public.bulk_operation (Query 5142).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, ledger `20260908003907`, na rodada
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

CREATE FUNCTION public.validate_bulk_operation_result_summary_presence()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_exists         BOOLEAN;
    v_has_result     BOOLEAN;
BEGIN
    -- ESTADO FINAL, por reconsulta. NUNCA NEW.result_summary: no
    -- INSERT do claim esse valor e legitimamente NULL, e validar NEW
    -- reprovaria o proprio claim.
    SELECT TRUE, (b.result_summary IS NOT NULL)
      INTO v_exists, v_has_result
      FROM public.bulk_operation b
     WHERE b.id = NEW.id;

    -- Linha removida dentro da mesma transacao: nao ha invariante a
    -- violar. Tratado explicitamente.
    IF NOT COALESCE(v_exists, FALSE) THEN
        RETURN NULL;
    END IF;

    IF NOT v_has_result THEN
        RAISE EXCEPTION
            'bulk_operation % nao pode ser commitada com result_summary NULL — uma linha persistente representa operacao bem-sucedida (D9)',
            NEW.id
            USING ERRCODE = '23514';
    END IF;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.validate_bulk_operation_result_summary_presence() IS
    'Invariante I4/R9: nenhuma linha PERSISTENTE de bulk_operation com result_summary NULL. Constraint trigger DEFERRABLE INITIALLY DEFERRED — reconsulta a linha por NEW.id e avalia o ESTADO FINAL, nunca NEW.result_summary (que e legitimamente NULL no claim).';

CREATE CONSTRAINT TRIGGER trg_bulk_operation_result_summary_presence
    AFTER INSERT OR UPDATE ON public.bulk_operation
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_bulk_operation_result_summary_presence();

REVOKE EXECUTE ON FUNCTION public.validate_bulk_operation_result_summary_presence()
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5821`, grupo T.

Técnica obrigatória no harness: como o trigger é DEFERRED e o harness
roda em `BEGIN ... ROLLBACK` (nunca comita), o disparo é forçado com

    SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;

dentro de um SAVEPOINT. Sem isso, os casos T02/T04 (commit deve falhar)
seriam impossíveis de provar sem comitar de verdade.
*/
