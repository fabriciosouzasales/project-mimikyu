/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5033 - Create Collection Default Storage Owner Trigger (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01
               → -REVISION-01, item 2 — simplificado → -IMPLEMENTATION-
               01, Fase 6 — correção de segurança: EXECUTE nunca
               revogado)

CORREÇÃO DE SEGURANÇA (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 6) — mesmo achado e mesma correção de
validate_collection_structural_identity() (Query 5032, ver seu
cabeçalho): EXECUTE nunca revogado de PUBLIC/anon, achado pelo
Supabase Advisor. Corrigido com REVOKE EXECUTE explícito.

Descrição...:
Garante que default_storage_container_id sempre pertence ao mesmo
Owner da Collection (C-36). Diferente de physical_card × storage_
container (que usa FK composta, porque ambos compartilham
inventory_id — Query 5023), collection.owner_user_id e storage_
container.inventory_id não têm coluna em comum: adicionar um
inventory_id redundante a Collection só para viabilizar uma FK
composta foi avaliado e descartado em COLLECTIONS-PHYSICAL-MODELING-
03-FINAL-01, item 3 — decisão não reaberta nesta rodada.

Enforcement via trigger + join até inventory:
  storage_container.inventory_id -> inventory.owner_user_id
comparado contra NEW.owner_user_id.

Só dispara em INSERT ou UPDATE OF default_storage_container_id — não
mais em UPDATE OF owner_user_id (simplificação desta revisão): como
owner_user_id agora é estruturalmente imutável (Query 5032), esse
caminho já é rejeitado antes por trg_collection_validate_structural_
identity: disparar esta função também nesse evento seria redundante.

SECURITY DEFINER estruturalmente necessário: a função lê inventory e
storage_container, ambas sob RLS com policy de SELECT restrita ao
próprio owner — mesma justificativa já usada nas RPCs SECURITY
DEFINER do domínio.

A RPC de criação/atualização (Queries 5034/5036) faz a mesma validação
antes, para erro amigável antes de tentar a escrita; este trigger é a
garantia estrutural permanente, independente de qualquer caminho de
escrita futuro.

FOR EACH ROW simples, sem transition table — Collection não é bulk, o
problema de sintaxe que motivou a divisão de triggers no incremento de
Storage (AFTER INSERT OR UPDATE + REFERENCING NEW TABLE não podem
coexistir) não se aplica aqui.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE FUNCTION public.validate_collection_default_storage_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_storage_owner_user_id UUID;
BEGIN
    SELECT inv.owner_user_id INTO v_storage_owner_user_id
    FROM public.storage_container sc
    JOIN public.inventory inv ON inv.id = sc.inventory_id
    WHERE sc.id = NEW.default_storage_container_id;

    IF v_storage_owner_user_id IS DISTINCT FROM NEW.owner_user_id THEN
        RAISE EXCEPTION 'default_storage_container_id não pertence ao Owner da Collection';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_validate_default_storage_owner
    BEFORE INSERT OR UPDATE OF default_storage_container_id
    ON public.collection
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_default_storage_owner();

REVOKE EXECUTE ON FUNCTION public.validate_collection_default_storage_owner() FROM PUBLIC, anon, authenticated;
