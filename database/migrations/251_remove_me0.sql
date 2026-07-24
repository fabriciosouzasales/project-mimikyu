-- Project Mimikyu
-- Query 251 - Remove ME0
-- Status: CONFIRMADA EXECUTADA (`npx supabase db push`, reconfirmada por
-- consulta real pós-execução)
-- Ver docs/05-modelo-de-dados.md, seção "Migration 251 — Remoção de ME0", e
-- docs/06-pipeline-importacao.md, "Sprint B3.7", para o contexto completo.
--
-- Decisão de negócio real, confirmada por Fabrício: a coleção interna ME0
-- ("ME Black Star Promos" — cartas promocionais de Mega Evolução) NÃO tem
-- relação com o Set `mee` da TCGdex ("Mega Evolution Energy" — cartas de
-- Energia). São coleções diferentes; o código semelhante era coincidência.
-- Criar esse vínculo introduziria um erro conceitual no modelo. Decisão:
-- remover ME0 de card_set por completo, até que exista uma fonte externa
-- homologada para esse conteúdo especificamente.
--
-- Pré-checagem real de dependências, confirmada antes desta migration:
--   card                        referenciando ME0: 0
--   asset_import_run            referenciando ME0: 1 (execução de teste)
--   card_set_external_reference referenciando ME0: 0 (nunca existiu)
--
-- Pendência registrada, não resolvida nesta migration: a Query 820 v2.0
-- (Seed canônica de Card Set) ainda insere ME0 caso executada em uma
-- instalação nova — precisa ser reescrita para não reintroduzir a linha
-- removida aqui. Ver "Em Aberto" em docs/06-pipeline-importacao.md.

DO $$
DECLARE
    v_card_set_id uuid;
BEGIN
    SELECT id
    INTO v_card_set_id
    FROM public.card_set
    WHERE code = 'ME0';

    IF v_card_set_id IS NULL THEN
        RAISE NOTICE 'ME0 não encontrada. Nenhuma alteração necessária.';
        RETURN;
    END IF;

    DELETE FROM public.asset_import_run
    WHERE card_set_id = v_card_set_id;

    DELETE FROM public.card_set
    WHERE id = v_card_set_id;
END;
$$;
