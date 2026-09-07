/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5107 - Create Collection Layout Grid Immutability Trigger
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
DP-03, enforcement. grid_rows/grid_columns só podem mudar enquanto o
Layout tiver ZERO Pages. Havendo qualquer Page, o UPDATE é rejeitado.

Por quê não permitir migração no lugar: C-39 é explícito — "não há
remoção automática silenciosa de conteúdo". Reduzir um grid 4×4 para
3×3 destruiria Slots e, com eles, Slot Assignments, Expected Content e
Layout Regions que não cabem mais. A política de reconciliação (o que
fazer com a Card do Slot que deixou de existir) é DECISÃO DE PRODUTO
e C-40 registra literalmente que "não é decidido nesta rodada".
Grid migration/rebuild permanece DEFERRED.

Nota de escopo V1 (MATERIALITY AUDIT): como DP-01 limita a Collection
a UM Layout, NÃO existe o escape "crie um novo Layout". Para alterar o
grid depois da primeira Page, as Pages precisam ser explicitamente
resolvidas e removidas primeiro (Query 5126, que por sua vez recusa
remover Page com dependências). A mensagem de erro reflete isso.

Escopo do trigger: dispara apenas quando grid_rows ou grid_columns
mudam de fato — UPDATE de outras colunas (updated_at, por exemplo)
nunca é afetado.

Dependências:
- public.collection_layout (Query 5105).
- public.collection_layout_page (Query 5108) — referenciada em tempo
  de execução; por isso este trigger é criado DEPOIS da Page? Não:
  a função é resolvida em runtime, não em CREATE FUNCTION time, mas
  para evitar qualquer ambiguidade de ordem de aplicação este arquivo
  DEVE ser aplicado depois de 5108. Ver README, "Ordem de aplicação".

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_collection_layout_grid_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.grid_rows    IS DISTINCT FROM OLD.grid_rows
    OR NEW.grid_columns IS DISTINCT FROM OLD.grid_columns THEN

        IF EXISTS (
            SELECT 1
            FROM public.collection_layout_page p
            WHERE p.layout_id = OLD.id
        ) THEN
            RAISE EXCEPTION
                'grid do Layout não pode ser alterado enquanto existirem Pages — remova todas as Pages primeiro (Grid Change com Pages existentes é DEFERRED)';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_collection_layout_grid_immutability()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_grid_immutability
    BEFORE UPDATE ON public.collection_layout
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_grid_immutability();

COMMIT;

/*
Como validar (dentro de BEGIN...ROLLBACK, com fixture):

-- Layout sem Pages: UPDATE de grid deve funcionar.
-- Layout com >= 1 Page: UPDATE de grid deve falhar com a mensagem acima.
*/
