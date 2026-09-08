/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5146 - Hardening do contrato de result_summary
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BULK-01-POST-AUDIT-HARDENING-01)

Descrição...:
Correção INCREMENTAL sobre `5142`–`5145`, que JÁ FORAM APLICADAS
(ledger 20260908003848 / 003907 / 003935 / 003951). Nenhuma migration
histórica é editada.

O DEFEITO
---------
`result_summary` é `JSONB NULL`. O invariante de `5143` só pergunta
`result_summary IS NOT NULL` — SQL NULL. Isso deixa passar valores que
são "não nulos" para o SQL mas vazios de significado para o contrato:

    'null'::jsonb   -> jsonb_typeof = 'null'    -> passa em 5143
    '[]'::jsonb     -> jsonb_typeof = 'array'   -> passa em 5143
    '"ok"'::jsonb   -> jsonb_typeof = 'string'  -> passa em 5143
    '0'::jsonb      -> jsonb_typeof = 'number'  -> passa em 5143
    'false'::jsonb  -> jsonb_typeof = 'boolean' -> passa em 5143

`'null'::jsonb` é o pior deles: NÃO é SQL NULL, então `5143` o aceita e
`claim_bulk_operation` o trataria como resultado legítimo, devolvendo
JSON null ao chamador como se fosse o resumo de uma operação concluída
— exatamente a classe de erro que `5144` v1.1 fechou do outro lado
(patrimônio nunca criado apresentado como criado).

O CONTRATO, AGORA EXPLÍCITO
---------------------------
`result_summary` pode ser SQL NULL SOMENTE enquanto o claim está em
voo, dentro da transação que o criou. Quando preenchido, é um JSON
OBJECT — porque é um resumo com campos nomeados (`created`,
`allocated`, ...), nunca um escalar nem uma lista solta.

DEFESA EM DUAS CAMADAS, DE PROPÓSITO
------------------------------------
  1. CHECK de tabela: vale para QUALQUER caminho de escrita, inclusive
     UPDATE direto de uma migration futura ou de uma sessão
     privilegiada. É a camada que não depende de ninguém lembrar.
  2. Guard em `complete_bulk_operation()`: falha CEDO, com mensagem
     que nomeia o tipo recebido. O CHECK sozinho produziria um erro de
     constraint genérico no fim da instrução.

As três verificações passam a ser complementares e não redundantes:
     NOT NULL estrutural  -> nao existe (o claim precisa nascer NULL)
     5143 (diferido)      -> nenhuma linha PERSISTENTE com SQL NULL
     5146 (imediato)      -> quando preenchido, e um JSON object

PRESERVADO SEM ALTERAÇÃO EM `complete_bulk_operation`
-----------------------------------------------------
Assinatura `(UUID, JSONB) RETURNS VOID`, `LANGUAGE plpgsql`,
`SECURITY DEFINER`, `SET search_path = ''`, owner `postgres`, `EXECUTE`
revogado de PUBLIC/anon/authenticated/service_role, a disciplina de
não-enumeração do erro de 0 linhas e a recusa de recompletar.

O `REVOKE` é reemitido após o `CREATE OR REPLACE` por segurança: se a
função tivesse sido dropada e recriada em vez de substituída, o ACL
default (`EXECUTE TO PUBLIC`) voltaria em silêncio. Reemitir é barato;
descobrir depois, não.

Dependências: public.bulk_operation (5142), trigger de 5143,
public.complete_bulk_operation() (5145).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, ledger `20260908011925`, na rodada
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

-- ================================================================
-- 1. CHECK DE TABELA — camada independente do caminho de escrita.
--
-- A tabela esta VAZIA (medido em 2026-09-07: 0 linhas), logo a
-- validacao e instantanea e nao ha necessidade de NOT VALID.
-- ================================================================
ALTER TABLE public.bulk_operation
    ADD CONSTRAINT chk_bulk_operation_result_summary_object
    CHECK (
        result_summary IS NULL
        OR jsonb_typeof(result_summary) = 'object'
    );

COMMENT ON CONSTRAINT chk_bulk_operation_result_summary_object
    ON public.bulk_operation IS
    'result_summary e SQL NULL apenas enquanto o claim esta em voo; quando preenchido e um JSON OBJECT. Fecha a brecha de jsonb_typeof: 5143 so testa IS NOT NULL, e ''null''::jsonb NAO e SQL NULL — passaria por 5143 e seria devolvido no replay como resultado legitimo. Array, string, number e boolean tambem sao rejeitados: o resumo tem campos nomeados.';

-- Reforca o texto do invariante de 5143 sem tocar na logica aplicada.
COMMENT ON COLUMN public.bulk_operation.result_summary IS
    'Resultado devolvido no replay. NULLABLE por necessidade estrutural (o claim nasce antes do resultado). Dois invariantes complementares: 5143 (constraint trigger diferido) garante que nenhuma linha PERSISTENTE fica com SQL NULL; 5146 (CHECK imediato) garante que, quando preenchido, o valor e um JSON OBJECT — nunca ''null''::jsonb, array ou escalar.';

-- ================================================================
-- 2. complete_bulk_operation() — falha CEDO e nomeia o tipo recebido.
--
-- CREATE OR REPLACE: mesma assinatura, mesmo owner, mesmo
-- SECURITY DEFINER, mesmo search_path. Unica mudanca de comportamento
-- e a rejeicao explicita de payload que nao seja JSON object.
-- ================================================================
CREATE OR REPLACE FUNCTION public.complete_bulk_operation(
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
    v_tipo     TEXT;
BEGIN
    v_owner := (select auth.uid());

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
    END IF;

    -- SQL NULL: ausencia de resultado. Nunca completa uma operacao.
    IF p_result_summary IS NULL THEN
        RAISE EXCEPTION 'result_summary nao pode ser NULL' USING ERRCODE = '22023';
    END IF;

    -- CONTRATO DE FORMA. Cobre inclusive 'null'::jsonb, que NAO e SQL
    -- NULL e por isso escapa do teste acima e do invariante de 5143.
    v_tipo := jsonb_typeof(p_result_summary);
    IF v_tipo <> 'object' THEN
        RAISE EXCEPTION
            'result_summary deve ser um JSON object; recebido: %', v_tipo
            USING ERRCODE = '22023';
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
    'Helper INTERNO. Grava result_summary no claim, na mesma transacao da operacao (passo 8 de B1/B2). Sem esta chamada o constraint trigger de 5143 reprova o COMMIT. Rejeita SQL NULL, payload que nao seja JSON object (inclusive ''null''::jsonb, array e escalares — 5146), linha de outro dono e recompletar. EXECUTE revogado de todos os papeis.';

-- Reemitido de proposito: ver cabecalho.
REVOKE EXECUTE ON FUNCTION public.complete_bulk_operation(UUID, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5821` v1.3, grupos R e E.
EXECUTADO em 2026-09-07: 39 TOTAL / 36 PASS / 0 FAIL / 3 NOT PROVEN.

Verificação rápida:

SELECT pg_get_constraintdef(k.oid)
FROM pg_constraint k
WHERE k.conrelid = 'public.bulk_operation'::regclass
  AND k.conname  = 'chk_bulk_operation_result_summary_object';

SELECT p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner), p.proacl
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'complete_bulk_operation';

Esperado: CHECK presente; prosecdef=t; proconfig={search_path=""};
owner=postgres; proacl={postgres=X/postgres} (NAO NULL — NULL
significaria EXECUTE TO PUBLIC por default).
*/
