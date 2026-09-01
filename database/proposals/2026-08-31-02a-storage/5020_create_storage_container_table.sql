/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5020 - Create Storage Container Table (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Cria public.storage_container — unidade física endereçável de
armazenamento corrente (C-55/C-56). Ownership mediado por Inventory
(C-57), nunca owner_user_id direto como fonte paralela — mesmo
princípio já corrigido para Physical Card em C-48.

Escopo desta Query (mínimo necessário para desbloquear Collection,
COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01): apenas identidade, nome e
vínculo com Inventory. Hierarquia (C-60), capacidade (C-62), Bulk Card
Transfer (C-64), Reparent (C-65) e Protection/Encapsulation (C-56)
permanecem explicitamente fora desta Query — nenhum campo, tabela ou
relação referente a eles é criado aqui.

Autoridade conceitual: C-55, C-56, C-57, C-58, C-59, C-61 (Storage
block, concept-decisions.md). Nenhum skeleton lógico físico havia sido
fixado para Storage Container em nenhuma rodada anterior (LDM-44 a
LDM-54 são "decisão lógica, sem skeleton físico" — confirmado por
leitura literal em COLLECTIONS-PHYSICAL-MODELING-03). Esta Query é,
portanto, a primeira materialização física de Storage Container no
projeto, derivada diretamente dos C-* aprovados.

Sequenciamento: esta Query precede Collection (Incremento 2B) porque
collection.default_storage_container_id é NOT NULL desde a criação
(C-36) — criar a tabela collection antes de Storage existir geraria
estado fisicamente incompatível com C-36 (ver
COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01, correção 1/Rev-01).

Regras de Negócio:
- inventory_id NOT NULL, ON UPDATE/DELETE RESTRICT — todo Storage
  Container pertence a exatamente um Inventory (C-57); nenhum DELETE
  em Inventory pode remover silenciosamente containers vinculados;
- UNIQUE(id, inventory_id) — não é uma segunda chave candidata
  independente; existe exclusivamente para servir de alvo de FK
  composta a partir de physical_card.storage_container_id (Query
  5023), permitindo que o Postgres garanta declarativamente que
  "quando um Physical Card referencia um Storage Container, os dois
  pertencem ao mesmo Inventory" (C-61) sem precisar de trigger;
- name TEXT NOT NULL — Storage Container não tem tipo fechado (C-55:
  "tipos não fixados como enum fechado"), então nenhuma coluna de
  tipo é criada nesta Query; name é o único atributo descritivo
  mínimo necessário;
- pode existir vazio, sem nenhuma Physical Card associada (C-59) —
  nenhuma constraint exige associação;
- RLS habilitado desde a criação; única policy é SELECT via subquery
  escalar contra inventory.owner_user_id — mesma forma já usada em
  physical_card (Query 5010);
- nenhuma policy de INSERT/UPDATE/DELETE para authenticated — única
  via de escrita é a RPC create_storage_container() (Query 5022);
- GRANT mínimo (authenticated: SELECT; anon: nenhum); REVOKE de
  TRUNCATE/REFERENCES/TRIGGER/MAINTAIN mantido por consistência
  defensiva, mesmo padrão de inventory/physical_card.

Não auto-provisionar um Storage Container "padrão"/genérico por
Inventory nesta Query (correção explícita de
COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01, item 5) — Storage
Container representa unidade física real do acervo do usuário, nunca
um placeholder fictício. Fica registrado como requisito de UX futuro:
na criação da Collection, o usuário poderá selecionar um Storage
Container já existente ou criar um novo dentro do próprio fluxo — UI
não desenhada nesta rodada.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA. Não aplicada no
Supabase. Numeração 5020 é provisória (mesma milhar 5000-5999 sugerida
para Collections, nunca formalmente reservada — STD-001 Seção 10).
Confirmar numeração definitiva no momento da reconciliação para
database/schema/ e database/migrations/, após execução real
autorizada.
================================================================
*/

CREATE TABLE public.storage_container (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_id   UUID NOT NULL
                       REFERENCES public.inventory(id)
                       ON UPDATE RESTRICT ON DELETE RESTRICT,
    name           TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_storage_container_id_inventory UNIQUE (id, inventory_id)
);

COMMENT ON TABLE public.storage_container IS
    'Unidade física endereçável de armazenamento corrente (C-55/C-56). Ownership mediado por Inventory (C-57), nunca owner_user_id direto. UNIQUE(id, inventory_id) existe só para servir de alvo de FK composta a partir de physical_card (Query 5023) — não é uma segunda chave candidata independente. Hierarquia/capacidade/bulk transfer/reparent/Protection fora desta Query.';

ALTER TABLE public.storage_container ENABLE ROW LEVEL SECURITY;

CREATE POLICY storage_container_select_own
    ON public.storage_container
    FOR SELECT
    USING (inventory_id = (SELECT i.id FROM public.inventory i WHERE i.owner_user_id = (select auth.uid())));

GRANT SELECT ON public.storage_container TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.storage_container FROM anon, authenticated;
