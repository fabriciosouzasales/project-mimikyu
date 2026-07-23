/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 171 - Create Card Asset Type Triggers
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-23

Descrição resumida:
Cria o trigger responsável pela atualização automática de updated_at na
tabela card_asset_type.

Descrição:
A tabela card_asset_type possui apenas uma dependência direta com Game. A
integridade desse relacionamento é garantida pela Foreign Key criada na
Query 170. Não há, nesta entidade, relacionamentos cruzados que exijam
trigger adicional de consistência de Game.

Regras de Negócio:
- updated_at deve ser atualizado automaticamente antes de cada UPDATE.
- A função compartilhada public.set_updated_at() deve ser reutilizada.
- A Query deve substituir uma definição anterior do mesmo trigger.

Pré-requisitos:
- Query 000 - Infrastructure.
- Query 170 - Create Card Asset Type Table.
- Função public.set_updated_at().

===============================================================================

NOTA DE DOCUMENTAÇÃO: cabeçalho reformatado para o padrão STD-001 e comentários
(COMMENT ON) traduzidos para português, mantendo a lógica SQL idêntica ao
texto originalmente executado.
===============================================================================
*/

BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION 'A função obrigatória public.set_updated_at() não existe.';
    END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_card_asset_type_set_updated_at
    ON public.card_asset_type;

CREATE TRIGGER trg_card_asset_type_set_updated_at
BEFORE UPDATE ON public.card_asset_type
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TRIGGER trg_card_asset_type_set_updated_at
ON public.card_asset_type IS
    'Atualiza automaticamente updated_at antes de cada UPDATE do registro.';

COMMIT;
