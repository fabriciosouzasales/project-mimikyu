/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5023 - Alter Physical Card: Add Storage Container Link (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Adiciona physical_card.storage_container_id — Storage corrente da
Physical Card (LDM-46, C-58), 0..1, nulável por desenho (uma Physical
Card pode existir sem Storage corrente).

Integridade Inventory × Storage (C-61 — Storage nunca cruza Inventory)
é garantida de forma DECLARATIVA, via FK composta, substituindo a
alternativa de trigger AFTER INSERT/UPDATE com transition table
avaliada em COLLECTIONS-PHYSICAL-MODELING-03-REVISION-02 (item 3) e
descartada em COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01 (item 1) em
favor desta abordagem, tecnicamente mais simples e sem função PL/pgSQL
para manter:

  storage_container: UNIQUE (id, inventory_id)                [5020]
  physical_card:      FOREIGN KEY (storage_container_id, inventory_id)
                       REFERENCES storage_container (id, inventory_id)

Validação de semântica da FK composta (MATCH SIMPLE, padrão do
Postgres quando MATCH não é especificado): a constraint só é avaliada
quando TODAS as colunas referenciadoras são non-null simultaneamente.
Isso cobre corretamente os casos exigidos:
  A. inventory_id = X, storage_container_id = Storage de X   -> PASS
  B. inventory_id = X, storage_container_id = Storage de Y≠X -> FAIL
  C. storage_container_id = NULL (qualquer inventory_id)     -> PASS
  D. UPDATE de inventory_id mantendo storage_container_id de
     outro Inventory                                          -> FAIL
Mas MATCH SIMPLE também SKIPA a validação quando qualquer uma das
colunas é NULL — incluindo o caso não coberto pelos quatro acima:
  E. inventory_id = NULL, storage_container_id = <não-nulo>
Sem tratamento adicional, a FK composta sozinha NÃO impediria o caso
E (uma Physical Card sem Inventory corrente ainda referenciando um
Storage Container) — descoberto durante a validação técnica desta
Query, não solicitado explicitamente na rodada, mas coerente com C-57
("Storage Container pertence ao contexto patrimonial de exatamente um
Inventory") e com o espírito de C-61. Fechado com um CHECK local
adicional (não depende de outra tabela, custo desprezível):
  CHECK (storage_container_id IS NULL OR inventory_id IS NOT NULL)
Caso E, hoje, não é alcançável por nenhum caminho de escrita real —
não existe RPC que zere physical_card.inventory_id (isso pertence à
frente futura de Ownership Exit/Lifecycle, C-72, não implementada) —
mas o CHECK fecha a lacuna de qualquer forma, por rigor declarativo,
sem custo de manutenção adicional.

Índice: ix_physical_card_storage_container (storage_container_id) —
justificado por workload confirmado ("conteúdo deste Storage
Container"), não especulativo. Não composto com inventory_id: a
própria RLS de physical_card já escopa por Inventory antes de
qualquer filtro de Storage; um índice líder por
(inventory_id, storage_container_id) seria redundante frente aos dois
índices compostos já existentes de 5010 mais este índice isolado.

Autoridade conceitual: LDM-46, C-58, C-61.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA. Depende da execução
prévia de 5020 (storage_container deve existir e ter
UNIQUE(id, inventory_id) antes desta FK composta poder ser criada).
================================================================
*/

ALTER TABLE public.physical_card
    ADD COLUMN storage_container_id UUID NULL;

ALTER TABLE public.physical_card
    ADD CONSTRAINT fk_physical_card_storage_same_inventory
    FOREIGN KEY (storage_container_id, inventory_id)
    REFERENCES public.storage_container (id, inventory_id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE public.physical_card
    ADD CONSTRAINT chk_physical_card_storage_requires_inventory
    CHECK (storage_container_id IS NULL OR inventory_id IS NOT NULL);

CREATE INDEX ix_physical_card_storage_container
    ON public.physical_card (storage_container_id);

COMMENT ON COLUMN public.physical_card.storage_container_id IS
    'Storage corrente da Physical Card (LDM-46/C-58), 0..1, nulável. Integridade Inventory×Storage garantida declarativamente por fk_physical_card_storage_same_inventory (FK composta contra storage_container(id, inventory_id)) + chk_physical_card_storage_requires_inventory (fecha o caso não coberto por MATCH SIMPLE: storage_container_id preenchido com inventory_id NULL).';
