/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6119 - Create Auto SPECIES_MATCH After Allocation Trigger
Versão......: 1.1 (STAGING — NÃO EXECUTADO — correção de
               STAGING-AUDIT-01, item 2: JOIN col agora exige
               mode = 'REFERENCE_BASED' explicitamente)
Status......: PROPOSTO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01;
               revisado em ...-STAGING-AUDIT-01)

Correção v1.1 (STAGING-AUDIT-01, item 2) — defesa em profundidade: o
JOIN original filtrava só por cr.reference_kind = 'POKEDEX', assumindo
implicitamente que isso já implica col.mode = 'REFERENCE_BASED'.
Conferido via validate_collection_reference_presence() (2B/2C) que a
regra estrutural só é garantida em UMA direção — REFERENCE_BASED exige
que exista uma collection_reference, mas o inverso (existir uma
collection_reference implica mode = REFERENCE_BASED) não é uma
constraint estruturalmente forçada em todo estado hipotético do banco.
Para não depender dessa implicação one-way, o JOIN abaixo agora exige
explicitamente col.mode = 'REFERENCE_BASED' — sem isso, uma Collection
em outro mode com uma collection_reference remanescente (estado que
não deveria ocorrer, mas não é impedido por constraint) poderia
disparar uma auto-Assignment indevida.

Descrição...:
Resolução automática de SPECIES_MATCH (LDM-178) imediatamente após uma
Allocation ser criada, para Collections Pokédex — item 9 da auditoria
física (Physical Modeling Audit-01): "se o sistema sabe inequivocamente
a Species, o usuário não deve precisar fazer trabalho manual".

Decisão de integração (Audit-01, item 9, mantida sem mudança na
Revision-01): trigger AFTER INSERT em collection_allocation, não uma
segunda RPC chamada pelo frontend. Diferente da Fatia C (Fluxo A/B, que
precisou de RPC explícita por operar em lote administrativo através de
um Edge Function com isolamento de erro por job), a Allocation aqui é
uma operação síncrona, por usuário, de no máximo 500 itens, já dentro
da mesma transação de allocate_physical_cards_to_collection() (Query
2C) — um trigger que roda na mesma transação é estruturalmente mais
simples e não exige nenhuma mudança de assinatura naquela função nem
uma segunda chamada de rede do frontend.

FOR EACH STATEMENT com REFERENCING NEW TABLE AS new_table (mesmo padrão
já usado por validate_collection_allocation_integrity, 2C) — não FOR
EACH ROW: allocate_physical_cards_to_collection() insere até 500 linhas
em uma única chamada; um único INSERT...SELECT processa o lote inteiro
sem N execuções de trigger.

Um único INSERT...SELECT com JOINs internos resolve todo o algoritmo:
    collection_allocation (linha nova)
    -> collection (mode/lifecycle, via collection_id)
    -> collection_reference (reference_kind = 'POKEDEX')
    -> collection_pokedex_reference (pokedex_id)
    -> physical_card -> card_variant -> card
    -> card_primary_species (pokemon_species_id resolvido, Fatia C)
    -> pokedex_position (mesmo pokedex_id E mesmo species_id)
Os JOINs são todos INNER — qualquer elo ausente (Collection não é
Pokédex, Card sem Primary Species resolvida, Card Trainer/Energy sem
linha em card_primary_species, ou nenhuma Position correspondente à
Species dentro do Pokédex referenciado) simplesmente não produz linha
de saída para aquela Allocation, silenciosamente — nunca uma exceção.
Isso implementa exatamente "mismatch/sem Species/Trainer/Energy/Position
inexistente -> não cria Assignment e não gera USER_OVERRIDE
automaticamente" (mandato desta rodada): USER_OVERRIDE só nasce de uma
confirmação humana explícita via set_pokedex_position_assignment()
(Query 6122), nunca deste trigger.

assigned_by_user_id é sempre NULL aqui (decisão do sistema, não de uma
pessoa) e assignment_basis é sempre 'SPECIES_MATCH' — únicos valores que
este trigger pode produzir.

ON CONFLICT (collection_allocation_id) DO NOTHING é defesa em
profundidade (nunca deveria colidir: collection_allocation_id vem de
linhas recém-inseridas em new_table, com PK physical_card_id UNIQUE
global — nenhuma Allocation nova pode reaproveitar o id de uma
Allocation já existente).

Scope (LDM-177): nenhuma referência a collection_pokedex_scope_generation
nem a scope_kind neste trigger — a auto-Assignment é criada
independentemente do Scope corrente, exatamente como qualquer Assignment
manual (Query 6117, header).

Ordem de disparo relativa a trg_collection_allocation_validate_insert
(2C) é irrelevante para a correção: ambos os triggers são AFTER INSERT
FOR EACH STATEMENT na mesma tabela/evento — se
validate_collection_allocation_integrity levantar exceção (Allocation
inválida), o Postgres desfaz TODA a statement, incluindo qualquer
INSERT que este trigger já tenha feito em
collection_pokedex_position_assignment, independentemente de qual dos
dois disparou primeiro. Atomicidade vem da transação da própria
chamada de RPC, não da ordem de disparo dos triggers.

Pré-requisitos:
- Query 6117 - Create Collection Pokédex Position Assignment Table.
- Query 6118 - Create Collection Pokédex Position Assignment Triggers.
- Query 6112 - Create Card Primary Species Table.
- Query 5040-5048 (2C) - Create Collection Allocation Table.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.auto_assign_pokedex_position_species_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.collection_pokedex_position_assignment
        (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
    SELECT
        nt.id,
        pp.id,
        'SPECIES_MATCH',
        NOW(),
        NULL
    FROM new_table nt
    JOIN public.collection col
        ON col.id = nt.collection_id
       AND col.mode = 'REFERENCE_BASED'
    JOIN public.collection_reference cr
        ON cr.collection_id = col.id
       AND cr.reference_kind = 'POKEDEX'
    JOIN public.collection_pokedex_reference cpr
        ON cpr.collection_reference_id = cr.id
    JOIN public.physical_card pc
        ON pc.id = nt.physical_card_id
    JOIN public.card_variant cv
        ON cv.id = pc.card_variant_id
    JOIN public.card_primary_species cps
        ON cps.card_id = cv.card_id
    JOIN public.pokedex_position pp
        ON pp.pokedex_id = cpr.pokedex_id
       AND pp.species_id = cps.pokemon_species_id
    ON CONFLICT (collection_allocation_id) DO NOTHING;

    RETURN NULL;
END;
$$;

-- Nome segue a convenção já usada pelos triggers existentes de
-- collection_allocation (trg_collection_allocation_*, Query 2C) — esta
-- tabela não usa a convenção trg_0NN_* (essa é própria de tabelas novas
-- desta Fatia, ex. Query 6118).
CREATE TRIGGER trg_collection_allocation_auto_assign_species_match
AFTER INSERT
ON public.collection_allocation
REFERENCING NEW TABLE AS new_table
FOR EACH STATEMENT
EXECUTE FUNCTION public.auto_assign_pokedex_position_species_match();

COMMIT;
