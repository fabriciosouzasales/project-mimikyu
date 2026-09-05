/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5091 - Create Collection Pokedex Scope Generation Table
Versão......: 1.0 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Representa "quais Generations compõem o filtro" (LDM-177,
GENERATION_FILTERED) — 1..N Pokemon Generations selecionadas por uma
Collection Pokedex Reference. Tabela filha de
collection_pokedex_reference, mesmo papel estrutural que
collection_master_set_scope (5072) tem para Master Set: cardinalidade
N, integridade referencial forte contra o catálogo (pokemon_generation),
insert/delete-only (nunca precisa de UPDATE — trocar o filtro é sempre
REMOVE+ADD, nunca "editar uma linha").

PK natural composta (collection_reference_id, generation_id) — mesma
disciplina de collection_master_set_scope: a invariante "uma Generation
aparece no máximo uma vez no filtro de uma Reference" é exatamente o
que a PK declara, sem UUID próprio.

Diferente de collection_master_set_scope, esta tabela NÃO carrega
adopted_at/adopted_by_user_id: uma Generation no filtro não é um "item
adotado individualmente" com proveniência própria digna de auditoria —
é apenas um critério de filtro sobre um conjunto já canônico
(pokemon_generation), e trocar o conjunto nunca precisa preservar
metadado por linha (ao contrário de Master Set Scope, onde cada
Card Variant adotada tem uma "adoção" que merece registro). Por isso a
RPC de troca (Query 5099) pode fazer DELETE total + INSERT total do
conjunto novo, sem o algoritmo VALIDATE ALL -> KEEP -> ADD -> REMOVE que
apply_master_set_scope_diff() (5079) precisa para não destruir
proveniência.

created_at existe só para auditoria/debug de quando o filtro foi
definido — não é dado de domínio consultado por nenhuma regra.

Regras de Negócio:
- collection_reference_id deve apontar para uma Collection Pokedex
  Reference existente (FK forte contra o subtipo, não contra o
  supertipo genérico — só um Collection Reference de kind POKEDEX pode
  ter filtro de Generation).
- generation_id deve existir em pokemon_generation (FK forte,
  ON DELETE RESTRICT — excluir uma Generation do catálogo nunca pode
  apagar silenciosamente o filtro de uma Collection).
- Presença desta tabela (0 ou >=1 linhas) deve coincidir com
  scope_kind = 'FULL_REFERENCE' (0 linhas) ou 'GENERATION_FILTERED'
  (>=1 linha) — garantido pelas Queries 5094/5095/5096/5097 (mesmo
  mecanismo diferido já usado para MASTER_SET Scope em 5075-5077),
  nunca por CHECK/FK isolada (exige contar linhas de outra tabela).
- INSERT só é aceito quando a Reference já está GENERATION_FILTERED no
  momento da chamada (Query 5095, mesma disciplina de
  Collection Master Set Scope Eligibility Trigger, 5073) — nunca é
  possível "adicionar uma Generation" numa Reference ainda
  FULL_REFERENCE sem primeiro declarar a troca de scope_kind.

RLS: SELECT via join triplo até collection.owner_user_id
(scope_generation -> collection_pokedex_reference -> collection_reference
-> collection), mesmo padrão em cascata já usado por
collection_card_set_reference (join duplo) e
collection_master_set_scope (join simples) — aqui um nível a mais
porque o subtipo POKEDEX tem uma tabela filha própria, que os demais
subtipos não têm.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE TABLE public.collection_pokedex_scope_generation (
    collection_reference_id UUID NOT NULL
                                REFERENCES public.collection_pokedex_reference(collection_reference_id)
                                ON UPDATE RESTRICT ON DELETE CASCADE,
    generation_id            UUID NOT NULL
                                REFERENCES public.pokemon_generation(id)
                                ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_collection_pokedex_scope_generation
        PRIMARY KEY (collection_reference_id, generation_id)
);

COMMENT ON TABLE public.collection_pokedex_scope_generation IS
    'Generations que compõem o filtro de uma Collection Pokedex Reference com scope_kind = GENERATION_FILTERED (LDM-177). PK composta natural. Presença (0 vs >=1 linhas) deve coincidir com scope_kind — garantido pelas Queries 5094-5097, não por CHECK/FK isolada.';

-- Nenhum índice adicional em generation_id: a PK já cobre o único
-- padrão de leitura conhecido (Reference -> conjunto de Generations do
-- filtro). Mesmo raciocínio já aplicado em collection_master_set_scope
-- (5072) e collection_card_set_reference (5052).

ALTER TABLE public.collection_pokedex_scope_generation ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_pokedex_scope_generation_select_own
    ON public.collection_pokedex_scope_generation FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.collection_pokedex_reference cpr
            JOIN public.collection_reference cr ON cr.id = cpr.collection_reference_id
            JOIN public.collection col ON col.id = cr.collection_id
            WHERE cpr.collection_reference_id = collection_pokedex_scope_generation.collection_reference_id
              AND col.owner_user_id = (select auth.uid())
        )
    );

GRANT SELECT ON public.collection_pokedex_scope_generation TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.collection_pokedex_scope_generation
    FROM anon, authenticated, service_role;

COMMIT;
