/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5076 - Create Collection Master Set Scope Presence Trigger (Collection Side)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01)

Descrição...:
Lado "Collection" do enforcement bidirecional diferido de "MASTER_SET
ativo -> Scope não vazio" (LDM-20/LDM-21, fechado em
MODELING-REVISION-01 item 2 e corrigido tecnicamente em
MODELING-FINAL-FIX-01/02). Cobre o caso em que `completion_policy`
muda para `MASTER_SET` sem que o Scope correspondente já exista.

CORREÇÃO TÉCNICA (FINAL-FIX-01): `CONSTRAINT TRIGGER` deferível só
existe como `AFTER`/`FOR EACH ROW` no PostgreSQL — não há forma válida
de `FOR EACH STATEMENT` deferível. `AFTER INSERT OR UPDATE OF
completion_policy ON collection FOR EACH ROW DEFERRABLE INITIALLY
DEFERRED`, uma invocação por linha de `collection` afetada (na prática
sempre 1, nenhuma RPC do domínio cria/atualiza `collection` em lote).
`INSERT` incluído por disciplina estrutural, ainda que nenhuma RPC
hoje crie uma Collection já em `MASTER_SET`.

CORREÇÃO TÉCNICA (FINAL-FIX-02): o corpo do trigger NÃO decide nada
sozinho — delega inteiramente a `check_master_set_scope_presence()`
(Query 5075), passando `NEW.id` só como correlation key, nunca lendo
`NEW.completion_policy`. Isso garante que, mesmo se a mesma Collection
mudar `completion_policy` mais de uma vez dentro da mesma transação
(ex.: STANDARD -> MASTER -> STANDARD), cada invocação diferida
reconsulta o estado final ao vivo no COMMIT, em vez de decidir a
partir do valor capturado em cada evento intermediário — ver Caso F
do futuro `5812`.

SECURITY DEFINER — mesmo padrão de todo trigger estrutural do domínio.
`EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.enforce_collection_master_set_scope_presence()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- NEW.id é usado só como chave de correlação — a decisão real
    -- reconsulta o estado corrente dentro do helper, nunca lê
    -- NEW.completion_policy aqui.
    PERFORM public.check_master_set_scope_presence(NEW.id);
    RETURN NULL; -- AFTER trigger: valor de retorno é ignorado pelo Postgres.
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_collection_master_set_scope_presence() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_collection_master_set_scope_presence() FROM anon;
REVOKE ALL ON FUNCTION public.enforce_collection_master_set_scope_presence() FROM authenticated;

CREATE CONSTRAINT TRIGGER trg_collection_master_set_scope_presence
    AFTER INSERT OR UPDATE OF completion_policy ON public.collection
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_master_set_scope_presence();
