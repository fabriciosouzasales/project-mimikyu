/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5113 - Create Collection Layout Slot Expected Content Table
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria public.collection_layout_slot_expected_content — a intenção
editorial de um Slot ("o que esta posição deveria representar"),
independente de sua ocupação física atual (C-42 / LDM-33).

DP-06 (congelado):
- slot_id UUID PK — o PK É o slot_id. Materializa "0..1 por Slot"
  sem coluna extra e sem UNIQUE separada.
- card_id NOT NULL.
- card_variant_id NULL. Ausente = qualquer Variant compatível daquela
  Card satisfaz a expectativa (C-42, literal).

INVARIANTE CRÍTICO — Variant pertence à Card:
provado DECLARATIVAMENTE por FK COMPOSTA (card_variant_id, card_id)
-> card_variant(id, card_id), apoiada na constraint criada pela Query
5104. Não é trigger. Precedente físico idêntico já vigente:
physical_card.fk_physical_card_storage_same_inventory sobre
uq_storage_container_id_inventory (Query 5023).

Comportamento com card_variant_id NULL: em Postgres, uma FK composta
com MATCH SIMPLE (default) é satisfeita automaticamente quando
QUALQUER coluna referenciante é NULL — portanto o par (NULL, card_id)
não é verificado, exatamente o comportamento desejado. A FK simples
para card(id) permanece separada e sempre verificada, garantindo que
card_id é sempre válido.

Os QUATRO estados de C-42 permanecem todos válidos: nenhum; só
Expected Content; só ocupação; ambos. Mismatch entre Expected Content
e a Physical Card ocupando o Slot NUNCA bloqueia a ocupação — é
estado derivado, apenas sinalizável pelo produto. Nada aqui, nem em
5115, impede a combinação.

EXPECTED CONTENT NÃO PARTICIPA DE COMPLETION (C-42, LDM-20,
literal). Nenhuma das quatro funções de completion vigentes
(collection_completion_summary, collection_completion_positions,
collection_master_set_scope_positions, collection_pokedex_scope_
positions) é tocada por esta Foundation. Completude permanece
derivada exclusivamente da alocação frente ao universo de referência.

Expected Content é EXCLUSIVAMENTE editorial/colecionável (C-42):
não incorpora custom image, divisor visual, região decorativa ou
qualquer elemento puramente visual — DP-05 mantém artwork FORA.

FK slot_id ON DELETE RESTRICT: Expected Content é CONTEÚDO, não
estrutura. Apagar a Page (que faria CASCADE nos Slots) é bloqueado
enquanto houver Expected Content, exatamente como C-39 exige.

FKs de Catálogo com RESTRICT: nenhum Expected Content pode desaparecer
por efeito colateral de manutenção do Catálogo Editorial.

Dependências:
- public.collection_layout_slot (Query 5110).
- public.card / public.card_variant (Catálogo Editorial).
- Query 5104 (uq_card_variant_id_card) — OBRIGATÓRIA antes desta.

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§9 TABLE DML DEFENSE — REVOKE EXPLÍCITO de INSERT/UPDATE/DELETE
para PUBLIC, anon e authenticated. Antes, a ausência de DML dependia
apenas de default privileges (nenhum GRANT de DML foi emitido). Isso
é verdadeiro mas FRÁGIL: qualquer ALTER DEFAULT PRIVILEGES futuro, ou
um GRANT ALL acidental no schema, abriria escrita direta e contornaria
o caminho RPC. A garantia passa a ser explícita e verificável — o 5818
checa os TRÊS grantees (PUBLIC, anon, authenticated).

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

CREATE TABLE public.collection_layout_slot_expected_content (
    slot_id          UUID        PRIMARY KEY
                     REFERENCES public.collection_layout_slot(id)
                     ON UPDATE RESTRICT ON DELETE RESTRICT,
    card_id          UUID        NOT NULL
                     REFERENCES public.card(id)
                     ON UPDATE RESTRICT ON DELETE RESTRICT,
    card_variant_id  UUID        NULL
                     REFERENCES public.card_variant(id)
                     ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_expected_content_variant_belongs_to_card
        FOREIGN KEY (card_variant_id, card_id)
        REFERENCES public.card_variant (id, card_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
);

COMMENT ON TABLE public.collection_layout_slot_expected_content IS
    'Expected Content do Slot (C-42/LDM-33). PK = slot_id materializa '
    '0..1 por Slot. NÃO participa de completion (C-42/LDM-20). '
    'Exclusivamente editorial — artwork/visual está FORA (DP-05).';

COMMENT ON COLUMN public.collection_layout_slot_expected_content.card_variant_id IS
    'Opcional. NULL = qualquer Variant compatível da Card satisfaz. '
    'Quando informado, a FK composta '
    'fk_expected_content_variant_belongs_to_card prova '
    'declarativamente que a Variant pertence à Card.';

ALTER TABLE public.collection_layout_slot_expected_content
    ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_layout_slot_expected_content_select_own
    ON public.collection_layout_slot_expected_content FOR SELECT
    USING (EXISTS (
        SELECT 1
        FROM public.collection_layout_slot s
        JOIN public.collection_layout_page p ON p.id = s.page_id
        JOIN public.collection_layout l      ON l.id = p.layout_id
        JOIN public.collection c             ON c.id = l.collection_id
        WHERE s.id = collection_layout_slot_expected_content.slot_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_layout_slot_expected_content TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.collection_layout_slot_expected_content FROM anon, authenticated;

-- §9 CORREÇÃO CONSOLIDADA 01 — DML nunca é concedido a cliente algum.
-- Explícito, não herdado de default privileges.
REVOKE INSERT, UPDATE, DELETE ON public.collection_layout_slot_expected_content
    FROM PUBLIC, anon, authenticated;

COMMIT;

/*
Como validar:

SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.collection_layout_slot_expected_content'::regclass
  AND contype = 'f'
ORDER BY conname;

Esperado: 4 FKs, incluindo
fk_expected_content_variant_belongs_to_card ::
FOREIGN KEY (card_variant_id, card_id) REFERENCES card_variant(id, card_id).
*/
