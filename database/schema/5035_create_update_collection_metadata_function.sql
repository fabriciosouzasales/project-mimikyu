/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5035 - Create update_collection_metadata Function
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01)

Descrição...:
Cria update_collection_metadata(p_collection_id, p_name,
p_description) — única via de escrita de name/description para
authenticated. Owner-only; nenhuma outra tabela/coluna tocada.

Bloqueada quando lifecycle_status = 'ARCHIVED' (C-37 — "não aceita
operações que alterem... configuração"). Único caminho para editar
metadata de uma Collection arquivada: reactivate_collection() (Query
5038) -> editar -> archive_collection() (Query 5037) novamente.

CORREÇÃO DE CONCORRÊNCIA (COLLECTIONS-PHYSICAL-INCREMENT-02B-STAGING-
REVISION-01). A versão 1.0 fazia SELECT lifecycle_status -> depois
UPDATE sem repetir a checagem no WHERE — uma janela real entre as duas
statements onde archive_collection() concorrente poderia arquivar a
Collection depois da leitura e antes da escrita, permitindo esta
função editar metadata de uma Collection já ARCHIVED. Corrigido:
lifecycle_status = 'ACTIVE' agora faz parte do próprio WHERE do
UPDATE — a checagem e a escrita são a mesma operação atômica, sem
janela. Sob READ COMMITTED (padrão do Postgres), se uma segunda sessão
tiver arquivado a linha entre a leitura e a tentativa de escrita desta
função, o UPDATE simplesmente não encontra a linha em estado ACTIVE e
afeta zero linhas — nunca escreve sobre uma Collection arquivada,
independente de ordem de chegada.

Se o UPDATE atômico afeta zero linhas, uma leitura diagnóstica
(read-only, sem novo UPDATE) distingue as duas causas possíveis só
para produzir uma mensagem de erro clara — essa leitura não reabre
nenhuma janela de escrita, porque a escrita já falhou/não ocorreu de
forma atômica antes dela.

CORREÇÃO DE REFERÊNCIA AMBÍGUA (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 3). A v1.1 usava `WHERE id = p_collection_id
AND owner_user_id = auth.uid() AND lifecycle_status = 'ACTIVE'` sem
qualificar as colunas — mas `RETURNS TABLE (id UUID, ...)` declara `id`
como parâmetro OUT/variável PL/pgSQL dentro do corpo da função, que
colide com a coluna `collection.id` no mesmo escopo. Postgres recusa a
ambiguidade em vez de adivinhar (`ERROR: column reference "id" is
ambiguous`) — erro só detectável em execução real, nunca durante
CREATE FUNCTION nem durante a modelagem/staging anteriores (que nunca
chegaram a rodar contra o banco). Corrigido qualificando todas as três
colunas do WHERE com `collection.` — mesmo padrão já usado no
RETURNING desde a v1.0. Nenhuma mudança de comportamento, só de
sintaxe.

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- p_name obrigatório e não-vazio após btrim();
- UPDATE ... WHERE collection.id = p_collection_id AND
  collection.owner_user_id = auth.uid() AND collection.lifecycle_status
  = 'ACTIVE' — única operação que decide atomicamente se a escrita é
  permitida;
- zero linhas afetadas -> leitura diagnóstica distingue "collection
  not found or not owned by caller" (não existe ou não é do chamador)
  de "collection is archived — reactivate before editing metadata"
  (existe, é do chamador, mas está ARCHIVED);
- retorno explícito (id, name, description, updated_at) — não usa
  RETURNS SETOF public.collection;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.update_collection_metadata(
    p_collection_id UUID,
    p_name TEXT,
    p_description TEXT
)
RETURNS TABLE (id UUID, name TEXT, description TEXT, updated_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'p_name não pode ser vazio';
    END IF;

    RETURN QUERY
    UPDATE public.collection
    SET name = btrim(p_name), description = p_description
    WHERE collection.id = p_collection_id
      AND collection.owner_user_id = auth.uid()
      AND collection.lifecycle_status = 'ACTIVE'
    RETURNING collection.id, collection.name, collection.description, collection.updated_at;

    IF NOT FOUND THEN
        IF EXISTS (
            SELECT 1 FROM public.collection c
            WHERE c.id = p_collection_id AND c.owner_user_id = auth.uid()
        ) THEN
            RAISE EXCEPTION 'collection is archived — reactivate before editing metadata';
        ELSE
            RAISE EXCEPTION 'collection not found or not owned by caller';
        END IF;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_collection_metadata(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_collection_metadata(uuid, text, text) TO authenticated;
