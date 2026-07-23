/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 860C - Seed Card Variant ME2.5
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cadastra e atualiza explicitamente as 630 variantes editoriais
identificadas para as 295 Cards da coleção ME2.5 - Heróis Excélsios.

Abordagem:
- A matriz editorial explícita está armazenada em JSONB dentro de um único
  bloco PL/pgSQL.
- Nenhuma tabela temporária ou auxiliar é criada.
- Nenhuma variante é inferida durante a execução por raridade, categoria,
  nome ou número da Card.
- A Query é idempotente.
- Divergências provocam rollback integral.

Distribuição canônica:
- COSMOS_HOLO: 7
- DUSK_BALL_REVERSE: 26
- ENERGY_REVERSE: 140
- FRIEND_BALL_REVERSE: 23
- HOLO: 142
- LOVE_BALL_REVERSE: 25
- POKE_BALL_REVERSE: 34
- PROMO_STAMPED: 10
- QUICK_BALL_REVERSE: 22
- REVERSE_HOLO: 38
- ROCKET_REVERSE: 10
- STANDARD: 153
- TOTAL: 630

Fonte editorial:
- Ascended Heroes - Track and Price Pokemon Cards - pkmn.gg, versão completa
  em PDF com as Cards 001 a 295.

Pré-requisitos:
- Query 840 - Seed Card.
- Query 850 - Seed Card Variant Type, versão 1.3.
- Query 160 - Create Card Variant.
- Query 161 - Card Variant Triggers.
- Queries 860A e 860B homologadas.

===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;
    v_card_set_id UUID;
    v_base_set_size INTEGER;
    v_total_set_size INTEGER;
    v_card_count INTEGER;

    v_matrix JSONB := $matrix$
[{"collector_number":"001","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"001","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"001","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"002","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"002","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"002","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"003","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"004","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"004","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"004","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"005","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"005","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"005","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"006","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"006","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"006","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"007","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"007","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"007","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"007","variant_type_code":"COSMOS_HOLO","variant_order":4,"is_default":false},{"collector_number":"008","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"008","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"008","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"008","variant_type_code":"COSMOS_HOLO","variant_order":4,"is_default":false},{"collector_number":"009","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"009","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"009","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"010","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"011","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"011","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"011","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"012","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"012","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"012","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"013","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"013","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"013","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"014","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"014","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"014","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"015","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"015","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"015","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"016","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"016","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"016","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"017","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"017","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"017","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"018","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"018","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"018","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"019","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"019","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"019","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"020","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"020","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"020","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"020","variant_type_code":"COSMOS_HOLO","variant_order":4,"is_default":false},{"collector_number":"021","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"021","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"021","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"022","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"022","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"023","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"023","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"023","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"024","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"024","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"024","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"025","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"025","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"025","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"026","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"027","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"027","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"027","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"028","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"028","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"028","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"029","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"029","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"029","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"029","variant_type_code":"COSMOS_HOLO","variant_order":4,"is_default":false},{"collector_number":"030","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"030","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"030","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"031","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"032","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"032","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"032","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"033","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"033","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"033","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"034","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"034","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"034","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"035","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"035","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"035","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"036","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"036","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"036","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"037","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"037","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"037","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"038","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"039","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"039","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"039","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"039","variant_type_code":"PROMO_STAMPED","variant_order":4,"is_default":false},{"collector_number":"040","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"040","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"040","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"041","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"041","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"041","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"041","variant_type_code":"COSMOS_HOLO","variant_order":4,"is_default":false},{"collector_number":"042","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"042","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"042","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"043","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"044","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"044","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"044","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"045","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"045","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"045","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"046","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"046","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"046","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"047","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"048","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"049","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"049","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"049","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"050","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"050","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"050","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"051","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"051","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"051","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"052","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"052","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"052","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"053","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"053","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"053","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"054","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"054","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"054","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"055","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"055","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"055","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"056","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"056","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"056","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"057","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"058","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"059","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"059","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"059","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"060","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"060","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"060","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"061","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"061","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"062","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"062","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"062","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"063","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"063","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"063","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"064","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"064","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"064","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"065","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"065","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"065","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"066","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"066","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"066","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"067","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"067","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"067","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"068","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"069","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"069","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"069","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"070","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"071","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"071","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"071","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"072","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"072","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"072","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"073","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"074","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"074","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"074","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"075","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"075","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"075","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"076","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"077","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"077","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"077","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"078","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"078","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"078","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"079","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"080","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"080","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"080","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"081","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"081","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"081","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"082","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"082","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"082","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"083","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"083","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"083","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"084","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"085","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"085","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"085","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"086","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"086","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"086","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"086","variant_type_code":"PROMO_STAMPED","variant_order":4,"is_default":false},{"collector_number":"087","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"087","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"087","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"088","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"088","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"088","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"089","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"090","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"090","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"090","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"091","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"091","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"091","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"092","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"092","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"092","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"093","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"093","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"093","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"094","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"094","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"094","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"095","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"095","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"095","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"096","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"096","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"096","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"097","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"097","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"097","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"098","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"098","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"098","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"099","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"099","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"099","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"100","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"100","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"100","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"101","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"101","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"101","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"102","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"102","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"102","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"103","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"103","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"103","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"104","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"104","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"104","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"105","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"105","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"105","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"106","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"106","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"106","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"107","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"108","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"108","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"108","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"109","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"109","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"109","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"110","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"110","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"110","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"111","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"112","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"112","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"112","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"113","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"114","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"115","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"115","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"115","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"116","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"117","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"117","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"117","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"118","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"118","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"118","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"119","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"119","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"119","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"120","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"120","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"120","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"121","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"122","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"122","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"122","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"123","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"123","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"123","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"123","variant_type_code":"COSMOS_HOLO","variant_order":4,"is_default":false},{"collector_number":"124","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"124","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"124","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"125","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"126","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"126","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"126","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"127","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"127","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"127","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"128","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"128","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"128","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"129","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"129","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"129","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"130","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"130","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"130","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"131","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"131","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"131","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"132","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"132","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"132","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"133","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"133","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"133","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"134","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"134","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"134","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"135","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"136","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"136","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"136","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"137","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"138","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"138","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"138","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"139","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"140","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"140","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"140","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"141","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"141","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"141","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"142","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"143","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"143","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"143","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"144","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"144","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"144","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"145","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"146","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"146","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"146","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"147","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"147","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"147","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"148","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"148","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"148","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"149","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"150","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"150","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"150","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"150","variant_type_code":"PROMO_STAMPED","variant_order":4,"is_default":false},{"collector_number":"151","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"151","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"151","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"151","variant_type_code":"PROMO_STAMPED","variant_order":4,"is_default":false},{"collector_number":"152","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"152","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"153","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"153","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"153","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"154","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"154","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"154","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"155","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"155","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"155","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"155","variant_type_code":"PROMO_STAMPED","variant_order":4,"is_default":false},{"collector_number":"156","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"156","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"156","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"157","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"157","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"157","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"158","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"158","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"158","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"159","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"159","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"159","variant_type_code":"QUICK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"160","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"161","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"161","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"161","variant_type_code":"ROCKET_REVERSE","variant_order":3,"is_default":false},{"collector_number":"162","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"163","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"163","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"163","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"164","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"165","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"165","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"165","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"166","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"166","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"166","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"167","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"168","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"168","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"168","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"169","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"169","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"169","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"170","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"170","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"170","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"171","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"171","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"171","variant_type_code":"DUSK_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"172","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"173","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"173","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"173","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"174","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"174","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"174","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"175","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"175","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"175","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"175","variant_type_code":"COSMOS_HOLO","variant_order":4,"is_default":false},{"collector_number":"176","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"176","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"176","variant_type_code":"FRIEND_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"177","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"177","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"177","variant_type_code":"POKE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"178","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"178","variant_type_code":"ENERGY_REVERSE","variant_order":2,"is_default":false},{"collector_number":"178","variant_type_code":"LOVE_BALL_REVERSE","variant_order":3,"is_default":false},{"collector_number":"179","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"180","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"180","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"181","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"181","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"182","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"182","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"183","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"183","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"183","variant_type_code":"PROMO_STAMPED","variant_order":3,"is_default":false},{"collector_number":"184","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"184","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"185","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"185","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"185","variant_type_code":"PROMO_STAMPED","variant_order":3,"is_default":false},{"collector_number":"186","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"186","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"187","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"187","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"188","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"188","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"189","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"189","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"190","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"190","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"191","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"191","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"192","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"192","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"193","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"193","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"194","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"194","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"195","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"195","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"196","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"196","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"197","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"197","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"198","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"198","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"199","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"199","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"200","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"200","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"201","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"201","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"202","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"202","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"203","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"203","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"204","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"204","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"205","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"205","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"206","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"206","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"207","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"207","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"208","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"208","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"209","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"209","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"210","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"210","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"211","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"211","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"212","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"212","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"213","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"213","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"214","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"214","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"215","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"215","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"216","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"216","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"217","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"217","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"218","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"219","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"220","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"221","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"222","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"223","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"224","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"225","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"226","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"227","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"228","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"229","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"230","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"231","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"232","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"233","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"234","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"235","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"236","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"237","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"238","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"239","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"240","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"241","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"242","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"243","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"244","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"245","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"246","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"247","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"248","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"249","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"250","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"251","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"252","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"253","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"254","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"255","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"256","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"257","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"258","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"259","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"260","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"261","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"262","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"263","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"264","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"265","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"266","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"267","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"268","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"269","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"270","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"271","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"272","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"273","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"274","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"275","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"276","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"277","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"278","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"279","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"280","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"281","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"282","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"283","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"284","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"285","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"286","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"287","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"288","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"289","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"290","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"291","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"292","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"293","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"294","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"295","variant_type_code":"HOLO","variant_order":1,"is_default":true}]
$matrix$::JSONB;

    v_item JSONB;
    v_collector_number TEXT;
    v_variant_type_code TEXT;
    v_variant_order INTEGER;
    v_is_default BOOLEAN;

    v_card_id UUID;
    v_variant_type_id UUID;

    v_matrix_count INTEGER;
    v_distinct_card_count INTEGER;
    v_duplicate_matrix_count INTEGER;
    v_default_error_count INTEGER;
    v_reference_error_count INTEGER;
    v_registered_count INTEGER;
    v_additional_count INTEGER;
    v_divergent_count INTEGER;
    v_invalid_default_count INTEGER;
    v_distribution JSONB;
BEGIN
    /*
    ===========================================================================
    1. Validar Game e Card Set
    ===========================================================================
    */

    SELECT g.id
      INTO v_game_id
      FROM public.game AS g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860C: o Game POKEMON não está cadastrado.';
    END IF;

    SELECT
        cs.id,
        cs.base_set_size,
        cs.total_set_size
      INTO
        v_card_set_id,
        v_base_set_size,
        v_total_set_size
      FROM public.card_set AS cs
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE e.game_id = v_game_id
       AND cs.code = 'ME2.5';

    IF v_card_set_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860C: o Card Set ME2.5 do Game POKEMON não está cadastrado.';
    END IF;

    IF v_base_set_size <> 217 OR v_total_set_size <> 295 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860C: ME2.5 possui base_set_size % e total_set_size %, mas os valores esperados são 217 e 295.',
            v_base_set_size,
            v_total_set_size;
    END IF;

    SELECT COUNT(*)
      INTO v_card_count
      FROM public.card AS c
     WHERE c.card_set_id = v_card_set_id;

    IF v_card_count <> 295 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860C: ME2.5 possui % Cards, mas o esperado é 295.',
            v_card_count;
    END IF;

    /*
    ===========================================================================
    2. Validar a matriz editorial
    ===========================================================================
    */

    v_matrix_count := jsonb_array_length(v_matrix);

    IF v_matrix_count <> 630 THEN
        RAISE EXCEPTION
            'A matriz editorial de ME2.5 possui % linhas, mas o esperado é 630.',
            v_matrix_count;
    END IF;

    SELECT COUNT(DISTINCT item->>'collector_number')
      INTO v_distinct_card_count
      FROM jsonb_array_elements(v_matrix) AS item;

    IF v_distinct_card_count <> 295 THEN
        RAISE EXCEPTION
            'A matriz editorial de ME2.5 referencia % Cards distintas, mas o esperado é 295.',
            v_distinct_card_count;
    END IF;

    SELECT COUNT(*)
      INTO v_duplicate_matrix_count
      FROM (
            SELECT
                item->>'collector_number' AS collector_number,
                item->>'variant_type_code' AS variant_type_code
              FROM jsonb_array_elements(v_matrix) AS item
             GROUP BY
                item->>'collector_number',
                item->>'variant_type_code'
            HAVING COUNT(*) > 1
      ) AS duplicate_matrix;

    IF v_duplicate_matrix_count <> 0 THEN
        RAISE EXCEPTION
            'A matriz editorial de ME2.5 contém % pares Card/tipo de variante duplicados.',
            v_duplicate_matrix_count;
    END IF;

    SELECT COUNT(*)
      INTO v_default_error_count
      FROM (
            SELECT item->>'collector_number' AS collector_number
              FROM jsonb_array_elements(v_matrix) AS item
             GROUP BY item->>'collector_number'
            HAVING COUNT(*) FILTER (
                WHERE (item->>'is_default')::BOOLEAN = TRUE
            ) <> 1
      ) AS invalid_default;

    IF v_default_error_count <> 0 THEN
        RAISE EXCEPTION
            'A matriz editorial de ME2.5 contém % Cards sem exatamente uma variante padrão.',
            v_default_error_count;
    END IF;

    /*
    ===========================================================================
    3. Validar todas as referências antes da alteração
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_reference_error_count
      FROM jsonb_array_elements(v_matrix) AS item
      LEFT JOIN public.card AS c
          ON c.card_set_id = v_card_set_id
         AND c.collector_number = item->>'collector_number'
      LEFT JOIN public.card_variant_type AS cvt
          ON cvt.game_id = v_game_id
         AND cvt.code = item->>'variant_type_code'
     WHERE c.id IS NULL
        OR cvt.id IS NULL
        OR (item->>'variant_order')::INTEGER <= 0;

    IF v_reference_error_count <> 0 THEN
        RAISE EXCEPTION
            'A Query 860C foi interrompida: existem % referências inválidas na matriz editorial.',
            v_reference_error_count;
    END IF;

    /*
    ===========================================================================
    4. Liberar temporariamente as posições e defaults existentes
    ===========================================================================
    */

    UPDATE public.card_variant AS cv
       SET variant_order = cv.variant_order + 1000,
           is_default = FALSE
      FROM public.card AS c
     WHERE cv.card_id = c.id
       AND c.card_set_id = v_card_set_id;

    /*
    ===========================================================================
    5. Inserir ou atualizar a matriz explícita
    ===========================================================================
    */

    FOR v_item IN
        SELECT value
          FROM jsonb_array_elements(v_matrix)
    LOOP
        v_collector_number := v_item->>'collector_number';
        v_variant_type_code := v_item->>'variant_type_code';
        v_variant_order := (v_item->>'variant_order')::INTEGER;
        v_is_default := (v_item->>'is_default')::BOOLEAN;

        SELECT c.id
          INTO STRICT v_card_id
          FROM public.card AS c
         WHERE c.card_set_id = v_card_set_id
           AND c.collector_number = v_collector_number;

        SELECT cvt.id
          INTO STRICT v_variant_type_id
          FROM public.card_variant_type AS cvt
         WHERE cvt.game_id = v_game_id
           AND cvt.code = v_variant_type_code;

        INSERT INTO public.card_variant (
            card_id,
            variant_type_id,
            variant_order,
            is_default
        )
        VALUES (
            v_card_id,
            v_variant_type_id,
            v_variant_order,
            v_is_default
        )
        ON CONFLICT (card_id, variant_type_id)
        DO UPDATE SET
            variant_order = EXCLUDED.variant_order,
            is_default = EXCLUDED.is_default;
    END LOOP;

    /*
    ===========================================================================
    6. Validar quantidade final
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_registered_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
     WHERE c.card_set_id = v_card_set_id;

    IF v_registered_count <> 630 THEN
        RAISE EXCEPTION
            'A Query 860C foi interrompida: ME2.5 possui % Card Variants, mas deveria possuir exatamente 630.',
            v_registered_count;
    END IF;

    /*
    ===========================================================================
    7. Validar distribuição final
    ===========================================================================
    */

    SELECT jsonb_object_agg(distribution.code, distribution.total)
      INTO v_distribution
      FROM (
            SELECT
                cvt.code,
                COUNT(*)::INTEGER AS total
              FROM public.card_variant AS cv
              INNER JOIN public.card AS c
                  ON c.id = cv.card_id
              INNER JOIN public.card_variant_type AS cvt
                  ON cvt.id = cv.variant_type_id
             WHERE c.card_set_id = v_card_set_id
             GROUP BY cvt.code
      ) AS distribution;

    IF COALESCE((v_distribution->>'COSMOS_HOLO')::INTEGER, 0) <> 7 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para COSMOS_HOLO: % registrado(s), esperado(s) 7.',
            COALESCE((v_distribution->>'COSMOS_HOLO')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'DUSK_BALL_REVERSE')::INTEGER, 0) <> 26 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para DUSK_BALL_REVERSE: % registrado(s), esperado(s) 26.',
            COALESCE((v_distribution->>'DUSK_BALL_REVERSE')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'ENERGY_REVERSE')::INTEGER, 0) <> 140 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para ENERGY_REVERSE: % registrado(s), esperado(s) 140.',
            COALESCE((v_distribution->>'ENERGY_REVERSE')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'FRIEND_BALL_REVERSE')::INTEGER, 0) <> 23 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para FRIEND_BALL_REVERSE: % registrado(s), esperado(s) 23.',
            COALESCE((v_distribution->>'FRIEND_BALL_REVERSE')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'HOLO')::INTEGER, 0) <> 142 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para HOLO: % registrado(s), esperado(s) 142.',
            COALESCE((v_distribution->>'HOLO')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'LOVE_BALL_REVERSE')::INTEGER, 0) <> 25 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para LOVE_BALL_REVERSE: % registrado(s), esperado(s) 25.',
            COALESCE((v_distribution->>'LOVE_BALL_REVERSE')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'POKE_BALL_REVERSE')::INTEGER, 0) <> 34 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para POKE_BALL_REVERSE: % registrado(s), esperado(s) 34.',
            COALESCE((v_distribution->>'POKE_BALL_REVERSE')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'PROMO_STAMPED')::INTEGER, 0) <> 10 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para PROMO_STAMPED: % registrado(s), esperado(s) 10.',
            COALESCE((v_distribution->>'PROMO_STAMPED')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'QUICK_BALL_REVERSE')::INTEGER, 0) <> 22 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para QUICK_BALL_REVERSE: % registrado(s), esperado(s) 22.',
            COALESCE((v_distribution->>'QUICK_BALL_REVERSE')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'REVERSE_HOLO')::INTEGER, 0) <> 38 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para REVERSE_HOLO: % registrado(s), esperado(s) 38.',
            COALESCE((v_distribution->>'REVERSE_HOLO')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'ROCKET_REVERSE')::INTEGER, 0) <> 10 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para ROCKET_REVERSE: % registrado(s), esperado(s) 10.',
            COALESCE((v_distribution->>'ROCKET_REVERSE')::INTEGER, 0);
    END IF;

    IF COALESCE((v_distribution->>'STANDARD')::INTEGER, 0) <> 153 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME2.5 para STANDARD: % registrado(s), esperado(s) 153.',
            COALESCE((v_distribution->>'STANDARD')::INTEGER, 0);
    END IF;


    /*
    ===========================================================================
    8. Detectar variantes adicionais fora da matriz
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_additional_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE c.card_set_id = v_card_set_id
       AND NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(v_matrix) AS item
             WHERE item->>'collector_number' = c.collector_number
               AND item->>'variant_type_code' = cvt.code
       );

    IF v_additional_count <> 0 THEN
        RAISE EXCEPTION
            'A Query 860C foi interrompida: ME2.5 possui % variantes adicionais fora da matriz canônica.',
            v_additional_count;
    END IF;

    /*
    ===========================================================================
    9. Detectar divergências de ordem ou default
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_divergent_count
      FROM jsonb_array_elements(v_matrix) AS item
      INNER JOIN public.card AS c
          ON c.card_set_id = v_card_set_id
         AND c.collector_number = item->>'collector_number'
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.game_id = v_game_id
         AND cvt.code = item->>'variant_type_code'
      INNER JOIN public.card_variant AS cv
          ON cv.card_id = c.id
         AND cv.variant_type_id = cvt.id
     WHERE cv.variant_order <> (item->>'variant_order')::INTEGER
        OR cv.is_default <> (item->>'is_default')::BOOLEAN;

    IF v_divergent_count <> 0 THEN
        RAISE EXCEPTION
            'A Query 860C foi interrompida: % variantes divergem da matriz canônica.',
            v_divergent_count;
    END IF;

    /*
    ===========================================================================
    10. Confirmar exatamente uma variante padrão por Card
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_invalid_default_count
      FROM (
            SELECT cv.card_id
              FROM public.card_variant AS cv
              INNER JOIN public.card AS c
                  ON c.id = cv.card_id
             WHERE c.card_set_id = v_card_set_id
             GROUP BY cv.card_id
            HAVING COUNT(*) FILTER (WHERE cv.is_default = TRUE) <> 1
      ) AS invalid_default;

    IF v_invalid_default_count <> 0 THEN
        RAISE EXCEPTION
            'A Query 860C foi interrompida: % Cards de ME2.5 não possuem exatamente uma variante padrão.',
            v_invalid_default_count;
    END IF;

    RAISE NOTICE
        'Query 860C concluída: 630 variantes cadastradas para as 295 Cards de ME2.5.';
END;
$$;

-- Resultado final para conferência no editor SQL.
SELECT
    cvt.code AS variant_type_code,
    COUNT(*) AS registered_total
FROM public.card_variant AS cv
INNER JOIN public.card AS c
    ON c.id = cv.card_id
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.card_variant_type AS cvt
    ON cvt.id = cv.variant_type_id
WHERE g.code = 'POKEMON'
  AND cs.code = 'ME2.5'
GROUP BY
    cvt.code,
    cvt.display_order
ORDER BY
    cvt.display_order;

COMMIT;
