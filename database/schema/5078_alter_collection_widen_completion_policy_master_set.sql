/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5078 - Alter Collection: Widen completion_policy for MASTER_SET
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02F-IMPLEMENTATION-01)

Descrição...:
Alarga `chk_collection_completion_policy` (criada em `5067`/02E) para
liberar a terceira combinação: `mode = 'REFERENCE_BASED' AND
completion_policy = 'MASTER_SET'`. Mesmo padrão já usado para alargar
`chk_collection_mode` em `5060` (02D) — `DROP CONSTRAINT` + `ADD
CONSTRAINT`, nunca reescrita como trigger (o próprio cabeçalho de
`5067` já anunciava esta extensão futura: "Quando POKEDEX/MASTER_SET
forem materializados, o CHECK abaixo será alargado (DROP+ADD, mesmo
padrão já usado em chk_collection_mode/Query 5060), nunca reescrito
como trigger").

`mode` não é tocado — permanece `OPEN_CURATION`/`REFERENCE_BASED`,
inalterado desde 02D. Nenhum `DEFAULT` novo ou alterado — `NONE`,
`STANDARD_SET` e `MASTER_SET` continuam exigindo escrita explícita
pela RPC de criação/transição correspondente, nunca um valor implícito
escondendo a decisão (mesma disciplina já registrada no cabeçalho de
`5067`).

`completion_policy` continua MUTÁVEL — nenhuma linha adicionada a
`validate_collection_structural_identity()` (5032) por esta Query.
A garantia de que `MASTER_SET` nunca fica com Scope vazio não é
responsabilidade deste CHECK (que é de coluna única, sem JOIN) — é
inteiramente responsabilidade do enforcement diferido bidirecional
(`5076`/`5077`, via `5075`).

Aplicação real (COLLECTIONS-PHYSICAL-INCREMENT-02F-IMPLEMENTATION-01):
aplicada via apply_migration; postcheck físico confirmou
`chk_collection_completion_policy` idêntico a esta definição (3
combinações válidas: OPEN_CURATION/NONE, REFERENCE_BASED/STANDARD_SET,
REFERENCE_BASED/MASTER_SET). Validado funcionalmente em 5812
(114/114 PASS, zero resíduo).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

ALTER TABLE public.collection
    DROP CONSTRAINT chk_collection_completion_policy;

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_completion_policy
    CHECK (
        (mode = 'OPEN_CURATION'   AND completion_policy = 'NONE')
        OR
        (mode = 'REFERENCE_BASED' AND completion_policy = 'STANDARD_SET')
        OR
        (mode = 'REFERENCE_BASED' AND completion_policy = 'MASTER_SET')
    );

COMMENT ON COLUMN public.collection.completion_policy IS
    'Política de completude (LDM-08/LDM-20). Fisicamente NONE (OPEN_CURATION), STANDARD_SET ou MASTER_SET (ambos REFERENCE_BASED) — ver chk_collection_completion_policy. REFERENCE_POSITION (Pokédex): CONCEPTUALLY READY, PHYSICALLY DEFERRED (não por limitação de catálogo). Mutável por desenho (C-23/LDM-22) — nenhuma proteção de imutabilidade em validate_collection_structural_identity(). MASTER_SET ativo nunca pode ficar sem Scope — ver collection_master_set_scope e os constraint triggers diferidos 5076/5077.';
