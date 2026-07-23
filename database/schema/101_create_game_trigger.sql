/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 101 - Create Game Trigger
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Cria o trigger responsável por atualizar automaticamente o campo updated_at
sempre que um registro da tabela game for alterado.
Regras de Negócio:
- Toda alteração em um Game deve atualizar automaticamente updated_at.
- A aplicação não deve informar manualmente esse horário.
- O trigger utiliza a função compartilhada public.set_updated_at().
===============================================================================
*/

CREATE TRIGGER trg_game_set_updated_at
BEFORE UPDATE ON public.game
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
