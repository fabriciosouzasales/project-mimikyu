/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5067 - Alter Collection: Add completion_policy
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01)

Descrição...:
Adiciona public.collection.completion_policy — materialização física de
LDM-08/LDM-20. Valores fisicamente liberados nesta etapa: 'NONE' (mode
= 'OPEN_CURATION') e 'STANDARD_SET' (mode = 'REFERENCE_BASED').
'MASTER_SET'/'REFERENCE_POSITION' permanecem CONCEPTUALLY READY,
PHYSICALLY DEFERRED FROM 02E FOR SCOPE CONTROL — não por limitação de
catálogo (ver README de `database/proposals/2026-09-02-02e-completion/`,
seção "Premissa estratégica do catálogo" e "MASTER_SET").

Sequência seguida (diferente de started_at/Query 5043, que nasceu
nulável para sempre porque representa um fato que só passa a existir
depois — aqui a coluna precisa de valor correto em toda linha já
existente, já que 01B/02A/02B/02C/02D podem ter deixado Collections
OPEN_CURATION e REFERENCE_BASED fisicamente possíveis):
1. ADD COLUMN nullable, SEM DEFAULT — nenhuma escrita futura deve
   depender de um valor implícito; toda RPC de criação (5068/5069)
   grava o valor explicitamente, mesmo espírito de mode/visibility
   (que têm DEFAULT na tabela mas são sempre preenchidos explicitamente
   pelas próprias RPCs);
2. backfill por mode — sem presumir que a base hoje só tem
   OPEN_CURATION (02D já liberou REFERENCE_BASED fisicamente; ambas as
   combinações podem existir de fato, dependendo do que Fabrício já
   criou em produção entre 02D e esta rodada);
3. validação (DO block): aborta com RAISE EXCEPTION se sobrar qualquer
   linha com completion_policy IS NULL, ou qualquer combinação
   mode/completion_policy fora das duas permitidas — SEMPRE antes de
   aplicar SET NOT NULL/CHECK, nunca aplicar a restrição física sobre
   dado não confirmado;
4. SET NOT NULL;
5. CHECK chk_collection_completion_policy.

Enforcement simplificado (COLLECTIONS-PHYSICAL-INCREMENT-02E-MODELING-
REVISION-01, item 4): CHECK de coluna única na própria tabela
collection, SEM trigger cross-table. mode e completion_policy são
colunas da mesma linha — nenhum JOIN necessário. O 02D já garante,
via os triggers deferred existentes (Queries 5057-5059), que
REFERENCE_BASED implica exatamente 1 collection_reference do tipo
CARD_SET — a invariante mode <-> Reference já está garantida por outra
camada; completion_policy não precisa reverificá-la.

completion_policy permanece MUTÁVEL — nenhuma linha adicionada a
validate_collection_structural_identity() (Query 5032) nesta rodada.
Necessário para C-23/LDM-22 (troca futura STANDARD_SET <-> MASTER_SET,
preservando Collection identity/Reference/Allocation/Storage — só
denominator/satisfaction/progress mudam). Quando POKEDEX/MASTER_SET
forem materializados, o CHECK abaixo será alargado (DROP+ADD, mesmo
padrão já usado em chk_collection_mode/Query 5060), nunca reescrito
como trigger.

Aplicação real (COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-01,
Fase 1): aplicada via apply_migration no banco físico do projeto, sem
nenhuma linha residual (base ainda não tinha Collections com
mode/completion_policy fora das duas combinações permitidas antes da
migration) — postcheck físico da Fase 2 confirmou coluna NOT NULL,
CHECK correto e zero linha fora do domínio.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

ALTER TABLE public.collection
    ADD COLUMN completion_policy TEXT NULL;

UPDATE public.collection
    SET completion_policy = 'NONE'
    WHERE mode = 'OPEN_CURATION';

UPDATE public.collection
    SET completion_policy = 'STANDARD_SET'
    WHERE mode = 'REFERENCE_BASED';

DO $$
DECLARE
    v_null_count    INT;
    v_invalid_count INT;
BEGIN
    SELECT count(*) INTO v_null_count
    FROM public.collection
    WHERE completion_policy IS NULL;

    IF v_null_count > 0 THEN
        RAISE EXCEPTION 'backfill incompleto: % Collections com completion_policy ainda NULL', v_null_count;
    END IF;

    SELECT count(*) INTO v_invalid_count
    FROM public.collection
    WHERE NOT (
        (mode = 'OPEN_CURATION'   AND completion_policy = 'NONE')
        OR
        (mode = 'REFERENCE_BASED' AND completion_policy = 'STANDARD_SET')
    );

    IF v_invalid_count > 0 THEN
        RAISE EXCEPTION 'backfill inconsistente: % Collections com combinação mode/completion_policy inválida', v_invalid_count;
    END IF;
END $$;

ALTER TABLE public.collection
    ALTER COLUMN completion_policy SET NOT NULL;

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_completion_policy
    CHECK (
        (mode = 'OPEN_CURATION'   AND completion_policy = 'NONE')
        OR
        (mode = 'REFERENCE_BASED' AND completion_policy = 'STANDARD_SET')
    );

COMMENT ON COLUMN public.collection.completion_policy IS
    'Política de completude (LDM-08/LDM-20). Fisicamente NONE (OPEN_CURATION) ou STANDARD_SET (REFERENCE_BASED) nesta etapa — ver chk_collection_completion_policy. MASTER_SET/REFERENCE_POSITION: CONCEPTUALLY READY, PHYSICALLY DEFERRED FROM 02E FOR SCOPE CONTROL (não por limitação de catálogo). Mutável por desenho (C-23/LDM-22) — nenhuma proteção de imutabilidade em validate_collection_structural_identity().';
