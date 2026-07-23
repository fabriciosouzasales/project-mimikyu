/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 810 - Seed Expansion
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Insere a primeira Expansion incorporada ao catálogo: Mega Evolution (ME),
do Game Pokémon Trading Card Game.
Regras de Negócio:
- O game_id é resolvido por SELECT no código de negócio do Game, nunca
  por UUID fixo.
- A execução deve ser idempotente (ON CONFLICT ... DO NOTHING).
- release_order = 1 representa a primeira Expansion incorporada ao catálogo
  do Project Mimikyu, não a primeira da história do Pokémon TCG — sujeito a
  revisão quando Expansions históricas anteriores forem importadas.
===============================================================================
*/

INSERT INTO public.expansion (
    game_id,
    code,
    name,
    release_order
)
SELECT
    game.id,
    'ME',
    'Mega Evolution',
    1
FROM public.game
WHERE game.code = 'POKEMON'
ON CONFLICT (game_id, code)
DO NOTHING;
