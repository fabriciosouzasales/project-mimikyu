/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 900 - Validate Game
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Valida a estrutura e os dados persistidos da entidade game: confirma a
associação do trigger de updated_at (não basta o "Success" da execução).
===============================================================================
*/

SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    event_object_schema,
    event_object_table
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'game'
  AND trigger_name = 'trg_game_set_updated_at';

-- Resultado esperado: uma linha com trigger_name = trg_game_set_updated_at,
-- event_manipulation = UPDATE, action_timing = BEFORE,
-- event_object_schema = public, event_object_table = game.
