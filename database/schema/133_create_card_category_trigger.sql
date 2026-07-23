/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 133 - Create Card Category Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria o trigger responsável pela atualização automática do campo updated_at da
tabela card_category.

Descrição:
O trigger executa a função compartilhada set_updated_at() antes de cada
atualização realizada na tabela card_category.

Regras de Negócio:
- O campo updated_at deve refletir a última alteração do registro.
- A atualização do timestamp não deve depender da aplicação.
- A função compartilhada set_updated_at() deve existir previamente.
- A Query pode ser executada novamente sem gerar triggers duplicados.

Pré-requisitos:
- Query 000 - Infrastructure.
- Query 132 - Create Card Category Table.
===============================================================================
*/

DROP TRIGGER IF EXISTS trg_card_category_set_updated_at
ON public.card_category;

CREATE TRIGGER trg_card_category_set_updated_at
BEFORE UPDATE ON public.card_category
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
