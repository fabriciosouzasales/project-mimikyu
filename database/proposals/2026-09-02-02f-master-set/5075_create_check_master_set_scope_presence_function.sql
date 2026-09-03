/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5075 - Create check_master_set_scope_presence Helper Function
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01)

Descrição...:
Helper centralizado que decide, sozinho, a invariante "MASTER_SET
ativo -> Scope não vazio" (LDM-20/LDM-21). Chamado pelos dois lados do
enforcement diferido bidirecional (Queries `5076`/`5077`) — nunca
duplicada a lógica entre os dois pontos de disparo.

Contrato final fechado em MODELING-FINAL-FIX-02 (item 1) — SEMPRE
reconsulta o estado CORRENTE da Collection por `id` no momento em que
é chamado, nunca decide a partir de `NEW`/`OLD` de conteúdo recebido
pelo trigger que a invoca (que só serve como correlation key). Isso é
o que torna o enforcement correto mesmo quando a mesma Collection sofre
múltiplas mudanças de `completion_policy` na mesma transação (ex.:
STANDARD -> MASTER -> STANDARD): cada disparo de trigger deferido
chama este helper de forma independente, e todos leem o mesmo estado
final ao vivo no momento do COMMIT — nunca um valor histórico
capturado num evento intermediário.

Contrato:
- Collection não existe (id não encontrado)              -> PASS.
- Collection existe e completion_policy <> 'MASTER_SET'   -> PASS.
- Collection existe, completion_policy = 'MASTER_SET' e
  EXISTS >= 1 linha em collection_master_set_scope         -> PASS.
- Collection existe, completion_policy = 'MASTER_SET' e
  Scope vazio                                              -> FAIL
  (RAISE EXCEPTION).

O caso "Collection não existe" cobre DELETE CASCADE (excluir uma
Collection MASTER_SET com Scope ativo cascateia a exclusão das linhas
de Scope; no momento diferido, a Collection já não existe mais, então
PASS incondicional — a exclusão da Collection nunca falha por causa
desta invariante).

SECURITY DEFINER — a leitura de `collection`/`collection_master_set_
scope` precisa ser consistente independentemente da role que originou
o evento que agendou a verificação diferida (sempre uma das RPCs desta
pasta, nunca acesso direto). `EXECUTE` revogado de `PUBLIC`/`anon`/
`authenticated` — função interna, nunca uma RPC exposta.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.check_master_set_scope_presence(
    p_collection_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_completion_policy TEXT;
BEGIN
    SELECT c.completion_policy
      INTO v_completion_policy
    FROM public.collection c
    WHERE c.id = p_collection_id;

    IF NOT FOUND THEN
        RETURN; -- Collection não existe mais (cobre DELETE CASCADE): PASS.
    END IF;

    IF v_completion_policy IS DISTINCT FROM 'MASTER_SET' THEN
        RETURN; -- policy != MASTER_SET no estado corrente: PASS.
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.collection_master_set_scope s
        WHERE s.collection_id = p_collection_id
    ) THEN
        RETURN; -- MASTER_SET com Scope não-vazio no estado corrente: PASS.
    END IF;

    RAISE EXCEPTION 'master set collection % would have an empty scope at commit', p_collection_id
        USING ERRCODE = 'check_violation';
END;
$$;

REVOKE ALL ON FUNCTION public.check_master_set_scope_presence(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_master_set_scope_presence(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.check_master_set_scope_presence(uuid) FROM authenticated;
