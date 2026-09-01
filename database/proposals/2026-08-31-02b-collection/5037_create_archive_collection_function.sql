/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5037 - Create archive_collection Function (PROPOSTA)
Versão......: 1.2
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01
               → -REVISION-01 → -FINAL-01 → -STAGING-REVISION-01, item 3
               → -IMPLEMENTATION-01, Fase 4 — correção preventiva de
               referência ambígua, achada em 5035/5036 na Fase 3)

CORREÇÃO DE REFERÊNCIA AMBÍGUA (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 3/4). Mesmo problema de update_collection_
metadata() (Query 5035, ver seu cabeçalho): `RETURNS TABLE (id UUID,
lifecycle_status TEXT, archived_at TIMESTAMPTZ)` cria variáveis
PL/pgSQL `id` E `lifecycle_status` (aqui mais grave, porque esta
função também usa `lifecycle_status = 'ACTIVE'` no WHERE — duas
colunas colidindo, não uma). Corrigido qualificando as três colunas do
WHERE com `collection.`, aplicado preventivamente antes da primeira
execução real desta função (achado em 5035/5036 na Fase 3, corrigido
aqui antes de reproduzir o mesmo erro na Fase 4). Nenhuma mudança de
comportamento.

Descrição...:
Cria archive_collection(p_collection_id) — Owner-only, transição
lifecycle_status ACTIVE -> ARCHIVED (C-30). Idempotente: se a
Collection já está ARCHIVED, retorna o estado atual sem erro e sem
sobrescrever archived_at — preserva o timestamp do primeiro
arquivamento real. Erro só ocorre por falta de posse/existência, nunca
por já estar no estado-alvo.

CORREÇÃO DE CONCORRÊNCIA (COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-
REVISION-01, item 3). A versão 1.0 fazia SELECT lifecycle_status ->
IF ARCHIVED retorna -> ELSE UPDATE WHERE id (sem re-checar
lifecycle_status no WHERE). Duas chamadas concorrentes na mesma
Collection ACTIVE poderiam ambas passar pelo SELECT vendo ACTIVE, e
ambas executar o UPDATE — a segunda, executando depois da primeira
commitar, sobrescreveria archived_at com um NOW() mais recente e
disparia o trigger de updated_at de novo, quebrando tanto a
idempotência quanto a garantia de "só uma chamada realiza ACTIVE ->
ARCHIVED".

Corrigido: a transição real é a UPDATE ... WHERE id = p_collection_id
AND owner_user_id = auth.uid() AND lifecycle_status = 'ACTIVE' —
única operação atômica que decide se a transição ocorre. Sob READ
COMMITTED, se duas sessões concorrentes tentam este UPDATE na mesma
linha, a segunda bloqueia até a primeira commitar; ao ser liberada,
reavalia o WHERE contra a linha já commitada (agora ARCHIVED) e afeta
zero linhas — nunca uma segunda vez. Se o UPDATE atômico afeta zero
linhas, uma leitura diagnóstica (read-only, sem novo UPDATE) distingue
"não existe/não é minha" de "já ARCHIVED": no segundo caso, retorna o
estado atual (archived_at/updated_at originais, sem tocá-los) — nunca
executa um segundo UPDATE.

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- UPDATE ... WHERE id = p_collection_id AND owner_user_id = auth.uid()
  AND lifecycle_status = 'ACTIVE' — única operação que decide
  atomicamente se a transição ACTIVE -> ARCHIVED ocorre;
- zero linhas afetadas -> leitura diagnóstica distingue "collection
  not found or not owned by caller" de idempotência (já ARCHIVED,
  retorna estado atual sem erro, sem novo UPDATE);
- chk_collection_archived_at_consistency (Query 5030) garante
  declarativamente que archived_at nunca fica NULL quando ARCHIVED,
  mesmo que esta RPC tivesse um bug — defesa em profundidade;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Contrato externo preservado — mesma assinatura (uuid) e mesmo
RETURNS TABLE(id, lifecycle_status, archived_at) da versão 1.0. Apenas
a implementação interna mudou.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA. Requer 5030-5033.
================================================================
*/

CREATE FUNCTION public.archive_collection(p_collection_id UUID)
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
    SET lifecycle_status = 'ARCHIVED', archived_at = NOW()
    WHERE collection.id = p_collection_id
      AND collection.owner_user_id = auth.uid()
      AND collection.lifecycle_status = 'ACTIVE'
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

    -- só chega aqui se lifecycle_status já era 'ARCHIVED' (o caso
    -- ACTIVE já teria sido resolvido pelo UPDATE acima) — idempotente,
    -- sem tocar archived_at/updated_at
    RETURN QUERY
    SELECT p_collection_id, v_current.lifecycle_status, v_current.archived_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.archive_collection(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.archive_collection(uuid) TO authenticated;
