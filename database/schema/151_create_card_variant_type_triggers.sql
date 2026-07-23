/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 151 - Create Card Variant Type Triggers
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria o trigger responsável pela atualização automática de updated_at na tabela
card_variant_type.

Descrição:
A tabela card_variant_type possui apenas uma dependência direta com Game.
A integridade desse relacionamento é garantida pela Foreign Key criada na
Query 150.

Não há, nesta entidade, relacionamentos cruzados que exijam trigger adicional
de consistência de Game.

Regras de Negócio:
- updated_at deve ser atualizado automaticamente antes de cada UPDATE.
- A função compartilhada public.set_updated_at() deve ser reutilizada.
- A Query deve substituir uma definição anterior do mesmo trigger.

Pré-requisitos:
- Query 000 - Infrastructure.
- Query 150 - Create Card Variant Type Table.
- Função public.set_updated_at().

===============================================================================
*/

BEGIN;

DROP TRIGGER IF EXISTS trg_card_variant_type_set_updated_at
    ON public.card_variant_type;

CREATE TRIGGER trg_card_variant_type_set_updated_at
BEFORE UPDATE ON public.card_variant_type
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMIT;
