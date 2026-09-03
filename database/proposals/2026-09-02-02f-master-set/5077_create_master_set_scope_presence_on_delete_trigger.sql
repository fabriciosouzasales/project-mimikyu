/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5077 - Create Master Set Scope Presence Trigger (Scope Side, On Delete)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01)

Descrição...:
Lado "Scope" do mesmo enforcement bidirecional diferido de `5076`.
Cobre o caso em que a última linha de Scope é removida enquanto a
Collection já está `MASTER_SET`.

`AFTER DELETE ON collection_master_set_scope FOR EACH ROW DEFERRABLE
INITIALLY DEFERRED` — só `DELETE`, nunca `DELETE OR UPDATE`, porque
`UPDATE` já é rejeitado incondicionalmente e imediatamente por `5074`
(nunca chega a existir um evento de `UPDATE` para este trigger reagir).
Usa `OLD.collection_id` só como correlation key, delegando a decisão
inteira a `check_master_set_scope_presence()` (5075) — mesmo
raciocínio de "estado corrente, nunca NEW/OLD histórico" de `5076`.

Comportamento provado nos cenários fechados em MODELING-FINAL-FIX-01
(Seção 4) e reafirmados aqui:
- `DELETE` da última linha de Scope + `INSERT` de uma linha nova
  (mesma ou outra Variant) na mesma transação -> no COMMIT, o helper
  encontra `EXISTS scope` = true para aquele `collection_id` -> PASS,
  mesmo que o Scope tenha passado por um instante vazio dentro da
  transação (`replace_master_set_scope()`, Query 5082, opera assim
  por desenho).
- `DELETE` da última linha sem reposição -> no COMMIT, `EXISTS scope`
  = false e `completion_policy` ainda `MASTER_SET` -> FAIL, transação
  inteira revertida.
- `DELETE` cascateado por exclusão da própria Collection
  (`delete_collection()`, C-13 já satisfeita) -> no COMMIT, a
  Collection já não existe mais -> helper retorna PASS incondicional
  (primeira ramificação do contrato de `5075`) — a exclusão da
  Collection nunca falha por causa desta invariante.

Se um `DELETE` remover várias linhas da mesma Collection num único
statement (ex.: dentro de `replace_master_set_scope()`), o Postgres
enfileira uma invocação diferida por linha — todas reavaliam a mesma
condição para o mesmo `collection_id` no COMMIT; redundante, mas
correto e barato (o helper é uma leitura simples).

SECURITY DEFINER — mesmo padrão de todo trigger estrutural do
domínio. `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.enforce_scope_master_set_presence_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM public.check_master_set_scope_presence(OLD.collection_id);
    RETURN NULL; -- AFTER trigger: valor de retorno é ignorado pelo Postgres.
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_scope_master_set_presence_on_delete() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_scope_master_set_presence_on_delete() FROM anon;
REVOKE ALL ON FUNCTION public.enforce_scope_master_set_presence_on_delete() FROM authenticated;

CREATE CONSTRAINT TRIGGER trg_collection_master_set_scope_presence_on_delete
    AFTER DELETE ON public.collection_master_set_scope
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_scope_master_set_presence_on_delete();
