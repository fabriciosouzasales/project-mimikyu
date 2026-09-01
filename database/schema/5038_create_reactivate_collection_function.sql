/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5038 - Create reactivate_collection Function
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01)

Descrição...:
Cria reactivate_collection(p_collection_id) — espelho exato de
archive_collection() (Query 5037): Owner-only, transição
lifecycle_status ARCHIVED -> ACTIVE (C-37 — "para voltar a operar, o
Owner deve reativá-la"). Idempotente: se a Collection já está ACTIVE,
retorna o estado atual sem erro e sem UPDATE.

CORREÇÃO DE CONCORRÊNCIA (COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-
REVISION-01, item 4) — mesmo raciocínio e mesma correção de
archive_collection() (Query 5037, ver seu cabeçalho para o
detalhamento completo da race original), espelhada: a transição real
ARCHIVED -> ACTIVE passa a ser a própria UPDATE ... WHERE id =
p_collection_id AND owner_user_id = auth.uid() AND lifecycle_status =
'ARCHIVED' — única operação atômica que decide se a transição ocorre.
Zero linhas afetadas -> leitura diagnóstica (read-only, sem novo
UPDATE) distingue "não existe/não é minha" de "já ACTIVE" (idempotente,
retorna estado atual sem tocar archived_at/updated_at).

CORREÇÃO DE REFERÊNCIA AMBÍGUA (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 3/4) — mesmo problema e mesma correção de
archive_collection() (Query 5037, ver seu cabeçalho): `id` e
`lifecycle_status` no WHERE colidem com os parâmetros OUT de
`RETURNS TABLE`. Qualificado com `collection.`. Nenhuma mudança de
comportamento.

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- UPDATE ... WHERE collection.id = p_collection_id AND
  collection.owner_user_id = auth.uid() AND collection.lifecycle_status
  = 'ARCHIVED' — única operação que decide atomicamente se a transição
  ARCHIVED -> ACTIVE ocorre;
- zero linhas afetadas -> leitura diagnóstica distingue "collection
  not found or not owned by caller" de idempotência (já ACTIVE,
  retorna estado atual sem erro, sem novo UPDATE);
- chk_collection_archived_at_consistency (Query 5030) garante
  declarativamente que archived_at nunca fica preenchido quando
  ACTIVE;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Provado por execução real (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 4): reactivate_collection() chamado duas vezes
seguidas na mesma Collection retorna updated_at idêntico nas duas
chamadas — a segunda não realiza nenhum UPDATE.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.reactivate_collection(p_collection_id UUID)
RETURNS TABLE (id UUID, lifecycle_status TEXT, archived_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_current RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    RETURN QUERY
    UPDATE public.collection
    SET lifecycle_status = 'ACTIVE', archived_at = NULL
    WHERE collection.id = p_collection_id
      AND collection.owner_user_id = auth.uid()
      AND collection.lifecycle_status = 'ARCHIVED'
    RETURNING collection.id, collection.lifecycle_status, collection.archived_at;

    IF FOUND THEN
        RETURN;
    END IF;

    SELECT c.lifecycle_status, c.archived_at INTO v_current
    FROM public.collection c
    WHERE c.id = p_collection_id AND c.owner_user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    -- só chega aqui se lifecycle_status já era 'ACTIVE' (o caso
    -- ARCHIVED já teria sido resolvido pelo UPDATE acima) —
    -- idempotente, sem tocar archived_at/updated_at
    RETURN QUERY
    SELECT p_collection_id, v_current.lifecycle_status, v_current.archived_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reactivate_collection(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reactivate_collection(uuid) TO authenticated;
