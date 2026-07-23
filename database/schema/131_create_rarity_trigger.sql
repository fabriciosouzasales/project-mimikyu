/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 131 - Create Rarity Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18
Descrição...:
Cria o trigger responsável por atualizar automaticamente o campo updated_at
da tabela rarity sempre que um registro for alterado.
Regras de Negócio:
- O trigger deve ser executado antes de qualquer UPDATE.
- O campo updated_at deve receber automaticamente o timestamp da alteração.
- A função set_updated_at() deve existir previamente.
Pré-requisitos:
- Query 001 - Create updated_at Function.
- Query 130 - Create Rarity Table.
===============================================================================
*/

CREATE TRIGGER trg_rarity_set_updated_at
BEFORE UPDATE
ON public.rarity
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
