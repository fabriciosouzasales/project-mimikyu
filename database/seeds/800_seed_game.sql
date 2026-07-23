/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 800 - Seed Game
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Insere o primeiro Game do catálogo editorial: Pokémon Trading Card Game.
Regras de Negócio:
- A execução deve ser idempotente (ON CONFLICT ... DO NOTHING).
- O código deve seguir o formato normalizado (ck_game_code_format).
===============================================================================
*/

INSERT INTO public.game (code, name)
VALUES ('POKEMON', 'Pokémon Trading Card Game')
ON CONFLICT (code) DO NOTHING;
