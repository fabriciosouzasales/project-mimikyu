/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5012 - Create add_physical_cards Function (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01)

Descrição...:
Cria add_physical_cards(p_items jsonb) — única via de escrita de
public.physical_card para authenticated, bulk-first (1 chamada = 1 a
500 Physical Cards). Inventory do chamador é resolvido no servidor a
partir de auth.uid() — o parâmetro NÃO aceita inventory_id, tornando
estruturalmente impossível ao cliente forjar o Inventory de destino.

Contrato de retorno revisado nesta rodada (item 2 de
COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01): não usa mais
`RETURNS SETOF public.physical_card`. Um retorno acoplado à tabela
inteira exporia automaticamente qualquer coluna futura adicionada a
physical_card (Collection, Storage, Condition, Certification,
Lifecycle, Audit — todos incrementos previstos) como parte do
contrato público da RPC, sem decisão deliberada nenhuma no momento em
que essa coluna fosse criada. Define-se em vez disso um
RETURNS TABLE explícito com o conjunto mínimo útil:

- id              -> identifica os exemplares recém-criados (permite
                      ao cliente destacar/navegar até eles);
- card_variant_id -> confirma o que foi de fato persistido por item;
- language_id     -> idem;
- created_at      -> timestamp de criação, útil para ordenação/UX
                      imediata (ex.: "adicionadas agora").

Deliberadamente EXCLUÍDO deste retorno:
- inventory_id: o chamador já sabe que o resultado pertence ao seu
  próprio Inventory (é o único destino possível da chamada) — ecoar
  de volta não agrega informação e amarraria o contrato a essa coluna
  existir com esse nome para sempre;
- updated_at: idêntico a created_at no momento da criação, sem valor
  informativo aqui;
- qualquer coluna futura (Collection/Storage/Condition/etc.): por
  definição ainda não existe nesta fundação — adicioná-la ao
  contrato de retorno será uma decisão explícita de uma Query futura,
  não um efeito colateral automático de ALTER TABLE.

SECURITY DEFINER é estruturalmente necessário, não estilístico: como
não existe nenhuma policy de INSERT para authenticated em
physical_card, uma função SECURITY INVOKER seria bloqueada pela
própria RLS ao tentar inserir. Justificativa completa em
COLLECTIONS-PHYSICAL-MODELING-02, item 6.

Regras de Negócio (preservadas desta revisão, sem alteração de
comportamento):
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- Inventory do chamador resolvido via public.inventory.owner_user_id
  = auth.uid(); se não encontrado, RAISE EXCEPTION;
- p_items deve ser array JSON, não vazio, no máximo 500 itens;
- 1 elemento do array = 1 Physical Card; duplicatas permitidas; sem
  parâmetro de quantity;
- validação de UUID/NOT NULL/FK a cargo das constraints nativas da
  tabela;
- atomicidade nativa: um único INSERT...SELECT...RETURNING como única
  escrita da função;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Nota técnica: com RETURNS TABLE(id, card_variant_id, language_id,
created_at), o PL/pgSQL cria variáveis OUT com esses mesmos nomes no
escopo da função. Por isso as colunas referenciadas no corpo abaixo
são qualificadas explicitamente (inv.id, physical_card.id, etc.) —
evita ambiguidade entre a variável OUT e a coluna da tabela, prática
recomendada pela documentação do Postgres para este padrão.

Auditoria de ambiguidade confirmada em
COLLECTIONS-PHYSICAL-INCREMENT-01A-FINAL-CHECK (Check 2): revisada
toda referência de coluna do corpo da função. `SELECT inv.id INTO
v_inventory_id FROM public.inventory inv WHERE inv.owner_user_id =
auth.uid()` já qualifica `id` via alias `inv`. O `RETURNING` final já
qualifica as 4 colunas via `physical_card.<coluna>`. A lista de
colunas-alvo do INSERT INTO (`card_variant_id, language_id,
inventory_id`) resolve sempre contra a tabela de destino, não é um
contexto de expressão genérica, então não é candidata a substituição
de variável PL/pgSQL. As strings `'card_variant_id'`/`'language_id'`
usadas com o operador `->>` são literais de texto, não identificadores.
Nenhuma referência não-qualificada a `id`/`card_variant_id`/
`language_id`/`created_at` permanece no corpo da função. Nenhum ajuste
de código foi necessário — a qualificação já presente desde a revisão
anterior (COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01) já cobria
integralmente o risco. Contrato de retorno não foi alterado.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE FUNCTION public.add_physical_cards(p_items jsonb)
RETURNS TABLE (
    id               UUID,
    card_variant_id  UUID,
    language_id      UUID,
    created_at       TIMESTAMPTZ
)
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

    IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'p_items deve ser um array JSON';
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'p_items não pode ser vazio';
    END IF;

    IF jsonb_array_length(p_items) > 500 THEN
        RAISE EXCEPTION 'lote excede o limite de 500 itens por chamada';
    END IF;

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user';
    END IF;

    RETURN QUERY
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT
        (item->>'card_variant_id')::uuid,
        (item->>'language_id')::uuid,
        v_inventory_id
    FROM jsonb_array_elements(p_items) AS item
    RETURNING
        physical_card.id,
        physical_card.card_variant_id,
        physical_card.language_id,
        physical_card.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_physical_cards(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_physical_cards(jsonb) TO authenticated;
