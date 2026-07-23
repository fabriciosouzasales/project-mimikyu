/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 121 - Create Card Set Trigger
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Cria o trigger da tabela card_set responsável por executar a função
public.set_updated_at() antes de cada atualização de registro.
Regras de Negócio:
- Toda alteração em um Card Set deve atualizar automaticamente updated_at.
- A aplicação não deve informar manualmente esse horário.
- O trigger utiliza a função compartilhada public.set_updated_at().
===============================================================================
*/

CREATE TRIGGER trg_card_set_set_updated_at
BEFORE UPDATE ON public.card_set
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
