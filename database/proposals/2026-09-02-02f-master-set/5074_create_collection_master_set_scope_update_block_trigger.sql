/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5074 - Create Collection Master Set Scope Update Block Trigger
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01)

Descrição...:
Formaliza `(collection_id, card_variant_id)` como identidade
estrutural imutável de uma linha de Scope (decisão fechada em
MODELING-FINAL-FIX-01, item 4). Não existe operação válida de
reidentificação — trocar a Variant A pela Variant B "no lugar" via
`UPDATE`, preservando o `adopted_at` original de A. Toda mudança de
composição do Scope é sempre REMOVE (`DELETE`) + ADD (`INSERT`), nunca
`UPDATE`.

A decisão vai além de bloquear só a PK: **todo `UPDATE` em
`collection_master_set_scope` é rejeitado incondicionalmente**,
inclusive de `adopted_at`/`adopted_by_user_id` — nenhum fluxo
legítimo do V1 precisa atualizar uma linha existente (KEEP significa
"não tocar", ver `5079`/`5080`/`5082`), e permitir `UPDATE` dessas
colunas reabriria exatamente a falha que MODELING-REVISION-01 corrigiu
no `replace` (resetar a proveniência de uma Variant que já estava
adotada). Mesmo padrão de Structural Identity trigger já usado em
`collection_reference`/`collection_card_set_reference` (02D), levado
ao extremo de bloquear `UPDATE` por completo — a tabela é
insert/delete-only por desenho.

Consequência direta: o lado Scope do enforcement diferido (Query
`5077`) só precisa reagir a `AFTER DELETE`, nunca a `AFTER DELETE OR
UPDATE` — simplificação explícita permitida por este trigger.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.reject_collection_master_set_scope_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION 'collection_master_set_scope rows are immutable — update collection_id=%, card_variant_id=% is not permitted (remove + add instead)', OLD.collection_id, OLD.card_variant_id
        USING ERRCODE = 'check_violation';
END;
$$;

REVOKE ALL ON FUNCTION public.reject_collection_master_set_scope_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_collection_master_set_scope_update() FROM anon;
REVOKE ALL ON FUNCTION public.reject_collection_master_set_scope_update() FROM authenticated;

CREATE TRIGGER trg_collection_master_set_scope_reject_update
    BEFORE UPDATE ON public.collection_master_set_scope
    FOR EACH ROW
    EXECUTE FUNCTION public.reject_collection_master_set_scope_update();
