/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 860A - Seed Card Variant ME1
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cadastra e atualiza explicitamente as 310 variantes editoriais oficiais das
188 Cards da coleção ME1 - Megaevolução.

Correção da versão 1.2:
- Elimina completamente tabelas temporárias e tabelas auxiliares.
- Toda a matriz editorial é processada dentro de um único bloco PL/pgSQL.
- A execução não depende da preservação de relações entre comandos do editor.
- Nenhum objeto intermediário é criado no banco de dados.

Abordagem:
A matriz editorial explícita é armazenada em uma variável JSONB local ao bloco.
Nenhuma variante é inferida durante a execução a partir da raridade da Card.

Distribuição canônica:
- STANDARD: 111
- HOLO: 77
- REVERSE_HOLO: 122
- Total: 310

Regras editoriais:
- Cada Card possui exatamente uma variante principal:
  variant_order = 1 e is_default = TRUE.
- Cards 001 a 132, exceto as dez DOUBLE_RARE, possuem REVERSE_HOLO:
  variant_order = 2 e is_default = FALSE.
- As dez DOUBLE_RARE do conjunto base possuem somente HOLO.
- As Cards 133 a 188 possuem somente HOLO.
- POKE_BALL_REVERSE, MASTER_BALL_REVERSE e PROMO_STAMPED não integram
  a matriz editorial principal de ME1.
- A Query é idempotente.
- A Query não exclui silenciosamente variantes adicionais.
- Qualquer divergência provoca rollback integral.

Pré-requisitos:
- Query 840 - Seed Card ME1.
- Query 850 - Seed Card Variant Type.
- Query 160 - Create Card Variant Table.
- Query 161 - Create Card Variant Triggers.

===============================================================================

NOTA DE DOCUMENTAÇÃO: primeira Query de carga real de card_variant executada
com sucesso, confirmada por Fabrício via saída real do editor SQL — a
distribuição retornada (STANDARD 111, HOLO 77, REVERSE_HOLO 122, total 310)
bateu exatamente com o esperado. A matriz editorial JSONB confirma, na
prática, que variant_order é local e sem lacunas por Card (cada Card recebe
apenas 1 ou 1-2, nunca a posição global do catálogo de Card Variant Type) —
resolve a dúvida sinalizada no ciclo anterior sobre local vs. global.
===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;
    v_card_set_id UUID;
    v_card_count INTEGER;
    v_variant_type_count INTEGER;

    v_matrix JSONB := $matrix$
[{"collector_number":"001","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"001","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"002","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"002","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"003","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"004","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"004","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"005","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"005","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"006","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"006","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"007","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"007","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"008","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"008","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"009","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"009","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"010","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"010","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"011","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"011","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"012","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"012","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"013","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"013","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"014","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"014","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"015","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"015","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"016","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"016","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"017","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"017","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"018","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"018","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"019","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"019","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"020","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"020","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"021","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"021","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"022","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"023","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"023","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"024","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"024","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"025","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"025","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"026","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"026","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"027","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"027","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"028","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"028","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"029","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"029","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"030","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"030","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"031","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"031","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"032","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"032","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"033","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"033","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"034","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"034","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"035","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"035","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"036","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"037","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"037","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"038","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"038","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"039","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"039","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"040","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"040","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"041","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"041","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"042","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"042","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"043","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"043","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"044","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"044","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"045","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"045","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"046","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"046","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"047","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"047","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"048","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"048","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"049","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"049","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"050","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"051","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"051","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"052","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"052","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"053","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"053","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"054","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"054","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"055","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"055","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"056","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"056","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"057","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"057","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"058","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"058","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"059","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"059","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"060","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"061","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"061","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"062","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"062","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"063","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"063","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"064","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"064","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"065","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"065","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"066","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"066","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"067","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"067","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"068","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"068","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"069","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"069","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"070","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"070","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"071","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"071","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"072","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"072","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"073","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"073","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"074","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"074","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"075","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"075","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"076","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"076","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"077","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"078","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"078","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"079","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"079","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"080","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"080","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"081","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"081","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"082","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"082","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"083","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"083","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"084","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"084","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"085","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"085","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"086","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"087","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"087","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"088","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"088","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"089","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"089","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"090","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"090","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"091","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"091","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"092","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"092","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"093","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"093","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"094","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"095","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"095","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"096","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"096","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"097","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"097","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"098","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"098","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"099","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"099","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"100","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"101","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"101","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"102","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"102","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"103","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"103","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"104","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"105","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"105","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"106","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"106","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"107","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"107","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"108","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"108","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"109","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"109","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"110","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"110","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"111","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"111","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"112","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"112","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"113","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"113","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"114","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"114","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"115","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"115","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"116","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"116","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"117","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"117","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"118","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"118","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"119","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"119","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"120","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"120","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"121","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"121","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"122","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"122","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"123","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"123","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"124","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"124","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"125","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"125","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"126","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"126","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"127","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"127","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"128","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"128","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"129","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"129","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"130","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"130","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"131","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"131","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"132","variant_type_code":"STANDARD","variant_order":1,"is_default":true},{"collector_number":"132","variant_type_code":"REVERSE_HOLO","variant_order":2,"is_default":false},{"collector_number":"133","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"134","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"135","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"136","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"137","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"138","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"139","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"140","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"141","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"142","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"143","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"144","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"145","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"146","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"147","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"148","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"149","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"150","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"151","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"152","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"153","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"154","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"155","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"156","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"157","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"158","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"159","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"160","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"161","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"162","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"163","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"164","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"165","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"166","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"167","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"168","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"169","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"170","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"171","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"172","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"173","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"174","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"175","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"176","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"177","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"178","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"179","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"180","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"181","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"182","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"183","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"184","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"185","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"186","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"187","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"188","variant_type_code":"HOLO","variant_order":1,"is_default":true}]
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
    v_default_error_count INTEGER;
    v_registered_count INTEGER;
    v_standard_count INTEGER;
    v_holo_count INTEGER;
    v_reverse_count INTEGER;
    v_additional_count INTEGER;
    v_divergent_count INTEGER;
    v_invalid_default_count INTEGER;
BEGIN
    -- ========================================================================
    -- 1. Validar Game, Card Set, Cards e tipos de variante
    -- ========================================================================

    SELECT g.id
      INTO v_game_id
      FROM public.game AS g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860A: o Game POKEMON não está cadastrado.';
    END IF;

    SELECT cs.id
      INTO v_card_set_id
      FROM public.card_set AS cs
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE e.game_id = v_game_id
       AND cs.code = 'ME1';

    IF v_card_set_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860A: o Card Set ME1 do Game POKEMON não está cadastrado.';
    END IF;

    SELECT COUNT(*)
      INTO v_card_count
      FROM public.card AS c
     WHERE c.card_set_id = v_card_set_id;

    IF v_card_count <> 188 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860A: ME1 possui % Cards, mas o esperado é 188.',
            v_card_count;
    END IF;

    SELECT COUNT(*)
      INTO v_variant_type_count
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND cvt.code IN ('STANDARD', 'HOLO', 'REVERSE_HOLO');

    IF v_variant_type_count <> 3 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 860A: os tipos STANDARD, HOLO e REVERSE_HOLO devem estar cadastrados para POKEMON.';
    END IF;

    -- ========================================================================
    -- 2. Validar a matriz editorial local
    -- ========================================================================

    v_matrix_count := jsonb_array_length(v_matrix);

    IF v_matrix_count <> 310 THEN
        RAISE EXCEPTION
            'A matriz editorial de ME1 possui % linhas, mas o esperado é 310.',
            v_matrix_count;
    END IF;

    SELECT COUNT(DISTINCT item->>'collector_number')
      INTO v_distinct_card_count
      FROM jsonb_array_elements(v_matrix) AS item;

    IF v_distinct_card_count <> 188 THEN
        RAISE EXCEPTION
            'A matriz editorial de ME1 referencia % Cards distintas, mas o esperado é 188.',
            v_distinct_card_count;
    END IF;

    SELECT COUNT(*)
      INTO v_default_error_count
      FROM (
            SELECT
                item->>'collector_number' AS collector_number
            FROM jsonb_array_elements(v_matrix) AS item
            GROUP BY item->>'collector_number'
            HAVING COUNT(*) FILTER (
                WHERE (item->>'is_default')::BOOLEAN = TRUE
            ) <> 1
      ) AS invalid_default;

    IF v_default_error_count <> 0 THEN
        RAISE EXCEPTION
            'A matriz editorial contém % Cards sem exatamente uma variante padrão.',
            v_default_error_count;
    END IF;

    -- ========================================================================
    -- 3. Validar todas as referências antes de alterar os dados
    -- ========================================================================

    FOR v_item IN
        SELECT value
          FROM jsonb_array_elements(v_matrix)
    LOOP
        v_collector_number := v_item->>'collector_number';
        v_variant_type_code := v_item->>'variant_type_code';
        v_variant_order := (v_item->>'variant_order')::INTEGER;
        v_is_default := (v_item->>'is_default')::BOOLEAN;

        SELECT c.id
          INTO v_card_id
          FROM public.card AS c
         WHERE c.card_set_id = v_card_set_id
           AND c.collector_number = v_collector_number;

        IF v_card_id IS NULL THEN
            RAISE EXCEPTION
                'A Query 860A foi interrompida: a Card % não foi encontrada em ME1.',
                v_collector_number;
        END IF;

        SELECT cvt.id
          INTO v_variant_type_id
          FROM public.card_variant_type AS cvt
         WHERE cvt.game_id = v_game_id
           AND cvt.code = v_variant_type_code;

        IF v_variant_type_id IS NULL THEN
            RAISE EXCEPTION
                'A Query 860A foi interrompida: o Card Variant Type % não foi encontrado.',
                v_variant_type_code;
        END IF;

        IF v_variant_order <= 0 THEN
            RAISE EXCEPTION
                'A Query 860A foi interrompida: variant_order inválido para a Card %.',
                v_collector_number;
        END IF;
    END LOOP;

    -- ========================================================================
    -- 4. Preparar os registros existentes para convergência segura
    -- ========================================================================

    UPDATE public.card_variant AS cv
       SET variant_order = cv.variant_order + 1000,
           is_default = FALSE
      FROM public.card AS c
     WHERE cv.card_id = c.id
       AND c.card_set_id = v_card_set_id;

    -- ========================================================================
    -- 5. Inserir ou atualizar cada linha explícita da matriz
    -- ========================================================================

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

    -- ========================================================================
    -- 6. Validar quantidade e distribuição finais
    -- ========================================================================

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE cvt.code = 'STANDARD'),
        COUNT(*) FILTER (WHERE cvt.code = 'HOLO'),
        COUNT(*) FILTER (WHERE cvt.code = 'REVERSE_HOLO')
      INTO
        v_registered_count,
        v_standard_count,
        v_holo_count,
        v_reverse_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE c.card_set_id = v_card_set_id;

    IF v_registered_count <> 310 THEN
        RAISE EXCEPTION
            'A Query 860A foi interrompida: ME1 possui % Card Variants, mas deveria possuir exatamente 310.',
            v_registered_count;
    END IF;

    IF v_standard_count <> 111
       OR v_holo_count <> 77
       OR v_reverse_count <> 122 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em ME1. STANDARD: %/111; HOLO: %/77; REVERSE_HOLO: %/122.',
            v_standard_count,
            v_holo_count,
            v_reverse_count;
    END IF;

    -- ========================================================================
    -- 7. Detectar variantes adicionais fora da matriz
    -- ========================================================================

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
            'A Query 860A foi interrompida: ME1 possui % variantes adicionais fora da matriz canônica.',
            v_additional_count;
    END IF;

    -- ========================================================================
    -- 8. Detectar divergências de ordem ou variante padrão
    -- ========================================================================

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
            'A Query 860A foi interrompida: % variantes divergem da matriz canônica.',
            v_divergent_count;
    END IF;

    -- ========================================================================
    -- 9. Confirmar exatamente uma variante padrão por Card
    -- ========================================================================

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
            'A Query 860A foi interrompida: % Cards de ME1 não possuem exatamente uma variante padrão.',
            v_invalid_default_count;
    END IF;

    RAISE NOTICE
        'Query 860A concluída: 310 variantes cadastradas em ME1 — 111 STANDARD, 77 HOLO e 122 REVERSE_HOLO.';
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
  AND cs.code = 'ME1'
GROUP BY
    cvt.code,
    cvt.display_order
ORDER BY
    cvt.display_order;

COMMIT;
