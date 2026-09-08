/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5104 - Alter Card Variant: Add UNIQUE (id, card_id)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Constraint-supporting exclusivamente. Acrescenta UNIQUE (id, card_id)
a public.card_variant para viabilizar a FK COMPOSTA de
collection_layout_slot_expected_content (Query 5113), que prova
declarativamente o invariante de DP-06:

    "quando card_variant_id não for NULL, a Card Variant deve
     pertencer à mesma Card referenciada por card_id"

Precedente físico idêntico já vigente no projeto: physical_card usa
fk_physical_card_storage_same_inventory sobre
uq_storage_container_id_inventory (Query 5023) para provar
"Storage Container e Physical Card pertencem ao mesmo Inventory".
Este arquivo aplica o mesmo padrão ao par (Card Variant, Card).

NÃO É ÍNDICE DE PERFORMANCE. O índice implícito criado pelo UNIQUE é
estrutural (constraint-supporting) e não deve ser contabilizado como
otimização — nenhum access pattern de leitura o motivou.

NÃO altera a semântica do Catálogo Editorial: `id` já é PK e portanto
único sozinho; (id, card_id) é trivialmente único por consequência. A
constraint não rejeita nenhuma linha existente nem futura — só torna o
par referenciável por FK.

PRECHECK OBRIGATÓRIO (executado em 2026-09-06, read-only):
card_variant possui hoje apenas
  - card_variant_pkey          PRIMARY KEY (id)
  - uq_card_variant_card_order UNIQUE (card_id, variant_order)
  - uq_card_variant_card_type  UNIQUE (card_id, variant_type_id)
Nenhuma delas é UNIQUE (id, card_id) — a constraint NÃO existe e
precisa ser criada. Reconfirmar antes de aplicar.

Dependências:
- public.card_variant (Catálogo Editorial, pré-existente).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, na rodada
`COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`. Validada por
`5818` v7.2 (196/196 runtime, FAIL 0) e por `5819` v3.0 (22/22 HEALTHY,
nenhum indice novo criado). Ledger e evidencia completa em
`database/proposals/2026-09-06-binder-layout-foundation/README.md`.

Promovida para `database/schema/` em `SCHEMA-PROMOTION-RECONCILIATION-01`
(2026-09-08). A copia historica permanece em
`database/proposals/2026-09-06-binder-layout-foundation/`, junto com os
harnesses `5818`/`5819`, o roteiro `CONCURRENCY-PROOF-C04-R18.sql` e o
`README.md` da rodada — esses quatro NAO sao promovidos, por convencao.
A promocao alterou apenas cabecalho/rodape: o corpo executavel
(`BEGIN;` .. `COMMIT;`) permanece byte-identico ao da copia em proposals.
================================================================
*/

BEGIN;

ALTER TABLE public.card_variant
    ADD CONSTRAINT uq_card_variant_id_card UNIQUE (id, card_id);

COMMIT;

/*
Como validar:

SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.card_variant'::regclass
  AND conname  = 'uq_card_variant_id_card';

Esperado: 1 linha, UNIQUE (id, card_id).
*/
