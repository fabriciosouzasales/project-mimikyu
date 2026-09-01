/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5036 - Create set_collection_default_storage Function (PROPOSTA)
Versão......: 1.2
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01
               → -REVISION-01 → -FINAL-01 → -STAGING-REVISION-01, item 2
               → -IMPLEMENTATION-01, Fase 3 — correção de referência
               ambígua, achada na primeira execução real)

CORREÇÃO DE REFERÊNCIA AMBÍGUA (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 3) — mesma correção e mesmo motivo de
update_collection_metadata() (Query 5035, ver seu cabeçalho para o
detalhamento completo): `RETURNS TABLE (id UUID, ...)` cria uma
variável PL/pgSQL `id` que colide com `collection.id` no WHERE do
UPDATE. Corrigido qualificando as três colunas do WHERE com
`collection.`. Nenhuma mudança de comportamento.

Descrição...:
Cria set_collection_default_storage(p_collection_id,
p_storage_container_id) — única via de escrita de
default_storage_container_id para authenticated. Owner-only; C-36
("pode ser alterado pelo Owner a qualquer momento") não previa a
exceção de ARCHIVED — por consistência com C-37 ("configuração" é
bloqueada durante ARCHIVED), esta RPC também é bloqueada nesse estado
(mesma regra de update_collection_metadata(), Query 5035).

Diferente de create_collection() (Query 5034), p_storage_container_id
é obrigatório aqui — não existe "limpar" Default Storage (C-36 não
prevê Collection sem Default Storage; a coluna é NOT NULL desde a
criação).

CORREÇÃO DE CONCORRÊNCIA (COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-
REVISION-01, item 2) — mesma correção e mesmo raciocínio de
update_collection_metadata() (Query 5035, ver seu cabeçalho para o
detalhamento completo da race original). lifecycle_status = 'ACTIVE'
passa a fazer parte do próprio WHERE do UPDATE, tornando checagem e
escrita atômicas — nenhuma janela SELECT→UPDATE permite trocar o
Default Storage concorrentemente com um archive_collection(). A
validação de pertencimento do Storage ao Inventory do chamador
permanece exatamente onde estava, antes do UPDATE — é um invariante
independente (garantido estruturalmente pelo trigger da Query 5033 de
qualquer forma), não precisa ser atômico com a checagem de lifecycle.

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_storage_container_id obrigatório (NOT NULL);
- p_storage_container_id deve pertencer ao Inventory do chamador
  (early error; a garantia estrutural permanente é o trigger da Query
  5033, que dispara de qualquer forma no UPDATE abaixo) — validado
  antes do UPDATE, como na versão 1.0;
- UPDATE ... WHERE id = p_collection_id AND owner_user_id = auth.uid()
  AND lifecycle_status = 'ACTIVE' — única operação que decide
  atomicamente se a escrita é permitida;
- zero linhas afetadas -> leitura diagnóstica distingue "collection
  not found or not owned by caller" de "collection is archived —
  reactivate before editing default storage";
- retorno explícito (id, default_storage_container_id, updated_at);
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Contrato externo preservado — mesma assinatura (uuid, uuid) e mesmo
RETURNS TABLE(id, default_storage_container_id, updated_at) da versão
1.0. Apenas a implementação interna mudou.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA. Requer 5030-5033.
================================================================
*/

CREATE FUNCTION public.set_collection_default_storage(
    p_collection_id UUID,
    p_storage_container_id UUID
)
RETURNS TABLE (id UUID, default_storage_container_id UUID, updated_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inventory_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_storage_container_id IS NULL THEN
        RAISE EXCEPTION 'p_storage_container_id não pode ser nulo';
    END IF;

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF NOT EXISTS (
        SELECT 1 FROM public.storage_container sc
        WHERE sc.id = p_storage_container_id
          AND sc.inventory_id = v_inventory_id
    ) THEN
        RAISE EXCEPTION 'storage container does not belong to caller inventory';
    END IF;

    RETURN QUERY
    UPDATE public.collection
    SET default_storage_container_id = p_storage_container_id
    WHERE collection.id = p_collection_id
      AND collection.owner_user_id = auth.uid()
      AND collection.lifecycle_status = 'ACTIVE'
    RETURNING collection.id, collection.default_storage_container_id, collection.updated_at;

    IF NOT FOUND THEN
        IF EXISTS (
            SELECT 1 FROM public.collection c
            WHERE c.id = p_collection_id AND c.owner_user_id = auth.uid()
        ) THEN
            RAISE EXCEPTION 'collection is archived — reactivate before editing default storage';
        ELSE
            RAISE EXCEPTION 'collection not found or not owned by caller';
        END IF;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_collection_default_storage(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_default_storage(uuid, uuid) TO authenticated;
