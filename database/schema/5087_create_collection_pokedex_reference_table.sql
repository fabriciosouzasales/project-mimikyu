/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5087 - Create Collection Pokedex Reference Table
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01; aplicado em
               2026-09-05 via COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Segundo subtipo físico de Collection Reference, correspondendo a
reference_kind = 'POKEDEX' — exatamente o subtipo que o cabeçalho de
5052 (collection_card_set_reference) já anunciava como extensão futura
sem migration destrutiva. Mesmo padrão clássico de subtipo 1:1: PK =
FK do supertipo (collection_reference_id), nenhum id próprio.

pokedex_id referencia public.pokedex (Query 6030) — hoje só existe a
linha 'NATIONAL', mas a tabela existe como catálogo desde a Fatia A,
então esta FK já suporta uma Pokédex adicional futura sem retrabalho.
ON DELETE RESTRICT em pokedex_id: excluir uma Collection nunca pode
cascatear até excluir catálogo Pokémon — mesmo raciocínio de
card_set_id em 5052.

scope_kind materializa LDM-177 (Collection Pokédex Scope): declara se
esta Collection adota TODAS as Positions da Pokédex referenciada
(FULL_REFERENCE, padrão) ou um subconjunto filtrado por Generation
(GENERATION_FILTERED). Vive nesta tabela — não em uma tabela própria —
porque é um atributo 1:1 da Reference, mesmo raciocínio que já levou
card_set_id a ser uma coluna direta de collection_card_set_reference,
não uma tabela à parte.

Diferença estrutural central em relação a collection_card_set_reference:
pokedex_id é imutável após reference_locked_at (mesma disciplina de
card_set_id — "qual universo esta Collection referencia" congela após
a primeira Allocation), mas scope_kind permanece mutável mesmo DEPOIS
do lock — LDM-177 é explícito ("Scope mutation... recalcula completion...
não remove Assignments") e LDM-185 só torna Scope imutável quando a
Collection está ARCHIVED, nunca por causa de reference_locked_at. Esta
assimetria é aplicada na Query 5090 (trigger), não nesta tabela.

Nenhuma coluna de "quais Generations compõem o filtro" aqui —
modelada como tabela filha própria (collection_pokedex_scope_generation,
Query 5091), pela mesma razão que levou Collection Master Set Scope
(5072) a ser uma tabela própria em vez de um array em collection: a
cardinalidade é 1..N, exige integridade referencial contra
pokemon_generation, e precisa ser adicionável/removível sem reescrever
uma coluna inteira.

Regras de Negócio:
- Cada Collection Reference de kind POKEDEX possui exatamente uma
  linha aqui (garantia via Queries 5092/5093 — mesmo mecanismo diferido
  já usado para CARD_SET em 5057/5058).
- pokedex_id NOT NULL — toda Collection Pokédex referencia exatamente
  uma Pokédex (LDM-176).
- scope_kind NOT NULL, default 'FULL_REFERENCE', restrito a
  ('FULL_REFERENCE', 'GENERATION_FILTERED').
- Integridade de Game (Collection deve pertencer ao Game Pokémon TCG) e
  imutabilidade de pokedex_id após lock são responsabilidade da Query
  5090 (trigger dedicado) — não uma FK composta possível aqui (pokedex
  não tem game_id: é entidade global do universo Pokémon, LDM-175,
  decisão congelada em COLLECTIONS-PHYSICAL-INCREMENT-02G).

RLS: SELECT via join até collection.owner_user_id — mesmo padrão de
collection_card_set_reference (5052). Nenhuma policy de escrita para
authenticated; toda escrita passa pelas RPCs 5098/5099 ou pelos
triggers estruturais desta rodada.

Least privilege de tabela: REVOKE explícito de TRUNCATE/REFERENCES/
TRIGGER/MAINTAIN de anon/authenticated E service_role já nesta Query de
criação — incorpora o achado de 6111 (pg_default_acl do role postgres
concede service_role=Dxtm a toda tabela nova por herança) desde o
primeiro momento. Auditoria read-only em 2026-09-05 confirmou que as
tabelas Collection já existentes AINDA têm essas quatro permissões
concedidas a service_role — achado colateral, registrado como débito
separado (ver README), NÃO corrigido nesta rodada por instrução
explícita de Fabrício (REVISION-01, item 7).

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou colunas/tipos/defaults, PK=FK em collection_reference_id, FK
pokedex_id ON UPDATE RESTRICT ON DELETE RESTRICT, o CHECK de scope_kind,
RLS habilitado com a policy SELECT própria, GRANT SELECT restrito a
authenticated, e REVOKE de TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de
anon/authenticated/service_role. Validado funcionalmente por duas
Collections Pokédex reais criadas em BEGIN/ROLLBACK (FULL_REFERENCE e
GENERATION_FILTERED). Zero resíduo (0 linhas após os testes).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

CREATE TABLE public.collection_pokedex_reference (
    collection_reference_id UUID PRIMARY KEY
                                REFERENCES public.collection_reference(id)
                                ON UPDATE RESTRICT ON DELETE CASCADE,
    pokedex_id               UUID NOT NULL
                                REFERENCES public.pokedex(id)
                                ON UPDATE RESTRICT ON DELETE RESTRICT,
    scope_kind                TEXT NOT NULL DEFAULT 'FULL_REFERENCE',
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_collection_pokedex_reference_scope_kind
        CHECK (scope_kind IN ('FULL_REFERENCE', 'GENERATION_FILTERED'))
);

COMMENT ON TABLE public.collection_pokedex_reference IS
    'Subtipo de Collection Reference para reference_kind = POKEDEX (LDM-176/LDM-177). pokedex_id é a Pokédex canônica referenciada — imutável após reference_locked_at (Query 5090). scope_kind declara FULL_REFERENCE ou GENERATION_FILTERED (LDM-177) — mutável mesmo após o lock, ao contrário de card_set_id.';

COMMENT ON COLUMN public.collection_pokedex_reference.pokedex_id IS
    'Pokédex canônica referenciada (public.pokedex). Imutável após collection.reference_locked_at ser definido (Query 5090).';

COMMENT ON COLUMN public.collection_pokedex_reference.scope_kind IS
    'FULL_REFERENCE (todas as Positions da Pokédex) ou GENERATION_FILTERED (subconjunto por Generation — ver collection_pokedex_scope_generation, Query 5091). Mutável a qualquer momento enquanto a Collection estiver ACTIVE (LDM-177/LDM-185) — não gated por reference_locked_at.';

-- Nenhum índice adicional em pokedex_id nesta rodada: hoje existe
-- exatamente 1 linha em public.pokedex ('NATIONAL'); nenhum padrão de
-- acesso "todas as Collections que referenciam esta Pokédex" foi
-- identificado. Mesmo raciocínio já aplicado em 5052/pokedex_position
-- (Query 6040) para não antecipar índice especulativo.

ALTER TABLE public.collection_pokedex_reference ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_pokedex_reference_select_own
    ON public.collection_pokedex_reference FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.collection_reference cr
            JOIN public.collection col ON col.id = cr.collection_id
            WHERE cr.id = collection_pokedex_reference.collection_reference_id
              AND col.owner_user_id = (select auth.uid())
        )
    );

GRANT SELECT ON public.collection_pokedex_reference TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.collection_pokedex_reference
    FROM anon, authenticated, service_role;

COMMIT;
