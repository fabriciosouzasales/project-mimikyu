/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5106 - Create Collection Layout updated_at Trigger
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Mantém collection_layout.updated_at, seguindo a convenção física já
vigente em todas as tabelas do módulo Collections. Função dedicada por
tabela (mesmo padrão de 5031/5041/5021), nunca uma função genérica
compartilhada — mantém o blast radius de qualquer alteração futura
restrito a uma tabela.

Segurança: SECURITY DEFINER com search_path = '' e EXECUTE revogado de
anon/authenticated (trigger function nunca é chamada diretamente por
cliente) — padrão consolidado desde 02G-SECURITY-CLOSEOUT-FIX-01.

Dependências:
- public.collection_layout (Query 5105).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_collection_layout_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_collection_layout_updated_at()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_updated_at
    BEFORE UPDATE ON public.collection_layout
    FOR EACH ROW
    EXECUTE FUNCTION public.set_collection_layout_updated_at();

COMMIT;

/*
Como validar:

SELECT tgname, tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.collection_layout'::regclass
  AND NOT tgisinternal;

Esperado: trg_collection_layout_updated_at presente, tgenabled='O'.
*/
