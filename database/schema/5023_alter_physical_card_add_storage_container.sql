/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5023 - Alter Physical Card: Add Storage Container Link
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01)

Descrição...:
Adiciona physical_card.storage_container_id — Storage corrente da
Physical Card (LDM-46, C-58), 0..1, nulável por desenho (uma Physical
Card pode existir sem Storage corrente).

Integridade Inventory × Storage (C-61 — Storage nunca cruza Inventory)
é garantida de forma DECLARATIVA, via FK composta, em vez de trigger
AFTER INSERT/UPDATE com transition table (alternativa avaliada em
COLLECTIONS-PHYSICAL-MODELING-03-REVISION-02 e descartada em
COLLECTIONS-PHYSICAL-MODELING-03-FINAL-01 em favor desta abordagem,
mais simples e sem função PL/pgSQL para manter):

  storage_container: UNIQUE (id, inventory_id)                [5020]
  physical_card:      FOREIGN KEY (storage_container_id, inventory_id)
                       REFERENCES storage_container (id, inventory_id)

Semântica da FK composta (MATCH SIMPLE, padrão do Postgres): a
constraint só é avaliada quando TODAS as colunas referenciadoras são
non-null simultaneamente. Cobre corretamente os casos A-D validados
fisicamente nesta rodada:
  A. inventory_id = X, storage_container_id = Storage de X   -> PASS
  B. inventory_id = X, storage_container_id = Storage de Y≠X -> FAIL
  C. storage_container_id = NULL (qualquer inventory_id)     -> PASS
  D. UPDATE de inventory_id mantendo storage_container_id de
     outro Inventory                                          -> FAIL
MATCH SIMPLE também SKIPA a validação quando qualquer coluna é NULL —
incluindo um caso não coberto pelos quatro acima:
  E. inventory_id = NULL, storage_container_id = <não-nulo>
Sem tratamento adicional, a FK composta sozinha não impediria o caso
E — descoberto durante a validação técnica da proposta (não solicitado
explicitamente na rodada, mas coerente com C-57/C-61). Fechado com um
CHECK local adicional (não depende de outra tabela, custo desprezível):
  CHECK (storage_container_id IS NULL OR inventory_id IS NOT NULL)
Caso E, hoje, não é alcançável por nenhum caminho de escrita real —
não existe RPC que zere physical_card.inventory_id (pertence à frente
futura de Ownership Exit/Lifecycle, C-72, não implementada) — mas o
CHECK fecha a lacuna de qualquer forma, por rigor declarativo.

Índice: ix_physical_card_storage_container (storage_container_id) —
justificado por workload confirmado ("conteúdo deste Storage
Container"), não especulativo. Não composto com inventory_id: a
própria RLS de physical_card já escopa por Inventory antes de
qualquer filtro de Storage; um índice líder por
(inventory_id, storage_container_id) seria redundante frente aos dois
índices compostos já existentes de 5010 mais este índice isolado.

Autoridade conceitual: LDM-46, C-58, C-61.

CONFIRMADO EXECUTADO em 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02A-
IMPLEMENTATION-01, Fase 2) via apply_migration (versão de migration
Supabase 20260901003403). FK composta, CHECK e índice confirmados
fisicamente contra o banco (pg_constraint/pg_indexes). Casos A-E
validados fisicamente via tentativa de escrita real (não apenas
introspecção de schema): A e C aceitos; B, D e E rejeitados com o
erro esperado em cada caso (B/D via violação da FK composta; E via
violação do CHECK) — ver
database/validations/5802_validate_collections_physical_increment_02a.sql.
Performance: query "conteúdo de um Storage Container" sobre volume
sintético de 20.000 Physical Cards confirmou uso de
ix_physical_card_storage_container (Index Scan), 0,764ms, 284 buffer
hits, 0 leituras de disco — ver
database/validations/5803_performance_checks_collections_physical_increment_02a.sql.
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
