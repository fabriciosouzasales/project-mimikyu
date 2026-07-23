/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 111 - Create Expansion Trigger
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Cria o trigger responsável por atualizar automaticamente o campo updated_at
sempre que um registro da tabela expansion for alterado. Reaproveita a
função compartilhada criada em 001.
===============================================================================
*/

CREATE TRIGGER trg_expansion_set_updated_at
BEFORE UPDATE ON public.expansion
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
