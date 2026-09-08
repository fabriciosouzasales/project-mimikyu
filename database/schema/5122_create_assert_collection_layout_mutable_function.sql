/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5122 - Create assert_collection_layout_mutable() Helper
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Helper INTERNO compartilhado por todas as RPCs de mutação de Layout
(Queries 5123–5135). NÃO é RPC: EXECUTE é revogado de anon e
authenticated. Existe para que a fronteira de autorização seja escrita
UMA vez e não treze — reduzindo a superfície onde um esquecimento
poderia abrir um furo.

Contrato, na ordem exata (a ordem importa para não-enumeração):

 1. auth.uid() IS NOT NULL, senão 'authentication required'.
    Nunca is_admin() — mesma disciplina das funções de completion.

 2. LOCKA na ordem canônica COLLECTION -> LAYOUT (ver a Correção
    Consolidada 01 abaixo). O lock serializa add/remove/reorder de
    Page, qualquer outra mutação estrutural do mesmo Layout e também
    o lifecycle da Collection — duas abas do MESMO usuário são
    cenário real, "um Owner" NÃO significa "sem concorrência".

 3. Ownership provado ANTES de navegar por qualquer objeto filho
    (C-37 e precedente 5035/5036/5039). Collection inexistente e
    Collection de outro Owner produzem a MESMA mensagem —
    'collection layout not found or not owned by caller' —
    preservando não-enumeração.

 4. lifecycle_status = 'ACTIVE' obrigatório, avaliado com o valor
    lido SOB O LOCK da Collection. Collection ARCHIVED:
    leitura permitida, TODA mutação de Layout/Page/Slot/Expected
    Content/Assignment/Lock/Region bloqueada. O único caminho é
    reactivate_collection() -> editar -> archive_collection().

Retorna o collection_id, útil às RPCs que precisam validar a
Allocation contra a mesma Collection.

Nomenclatura: prefixo assert_ e não internal_ para seguir o padrão
já usado no projeto; a proteção real vem do REVOKE, não do nome.

Dependências:
- public.collection_layout (Query 5105).
- public.collection (Query 5030).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§2 LOCK ORDER E ARCHIVED RACE. A v1.0 lockava apenas o Layout
(`FOR UPDATE OF l`) e lia `lifecycle_status` da Collection SEM lock.
Uma `archive_collection()` concorrente podia mover a Collection de
ACTIVE para ARCHIVED entre a leitura e a mutação, e toda a bateria de
RPCs escreveria num Layout de Collection já arquivada.

A ordem canônica passa a ser COLLECTION -> LAYOUT, nesta sequência
exata, em TODAS as RPCs (nenhuma pode invertê-la, sob pena de
deadlock):
 1. resolve owner-scoped do collection_id (sem lock, sem revelar se o
    Layout existe mas é alheio);
 2. SELECT ... FOR UPDATE da Collection, com o filtro de owner;
 3. erro uniforme se não encontrada;
 4. lifecycle_status verificado com o valor LIDO SOB O LOCK;
 5. SELECT ... FOR UPDATE do Layout, escopado ao collection_id
    resolvido;
 6. revalidação de existência pós-lock.
Isso serializa corretamente contra archive_collection(),
allocate/deallocate e demais mutações de Collections.

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

CREATE OR REPLACE FUNCTION public.assert_collection_layout_mutable(
    p_layout_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id     UUID;
    v_lifecycle_status  TEXT;
    v_layout_check      UUID;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- PASSO 1 — RESOLVE OWNER-SCOPED, AINDA SEM LOCK.
    -- Layout inexistente e Layout de outro Owner caem no MESMO ramo,
    -- porque a navegação já carrega o filtro de ownership.
    SELECT l.collection_id
      INTO v_collection_id
      FROM public.collection_layout l
      JOIN public.collection c ON c.id = l.collection_id
     WHERE l.id = p_layout_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection layout not found or not owned by caller';
    END IF;

    -- PASSO 2 — LOCK DA COLLECTION. Ordem canônica: COLLECTION antes
    -- de LAYOUT, sempre, em toda a Foundation. É este lock que
    -- serializa contra archive_collection().
    SELECT c.lifecycle_status
      INTO v_lifecycle_status
      FROM public.collection c
     WHERE c.id = v_collection_id
       AND c.owner_user_id = (select auth.uid())
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection layout not found or not owned by caller';
    END IF;

    -- PASSO 3 — ACTIVE avaliado com o valor lido SOB O LOCK, nunca com
    -- um snapshot anterior à espera.
    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION
            'collection is ARCHIVED — reactivate it before editing the layout';
    END IF;

    -- PASSO 4 — LOCK DO LAYOUT, escopado ao collection_id já resolvido.
    SELECT l.id
      INTO v_layout_check
      FROM public.collection_layout l
     WHERE l.id = p_layout_id
       AND l.collection_id = v_collection_id
     FOR UPDATE;

    -- PASSO 5 — REVALIDAÇÃO PÓS-LOCK: se o Layout sumiu ou trocou de
    -- Collection enquanto esperávamos, erro uniforme.
    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection layout not found or not owned by caller';
    END IF;

    RETURN v_collection_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.assert_collection_layout_mutable(uuid)
    FROM PUBLIC, anon, authenticated;

COMMIT;

/*
Como validar:

SELECT p.proname, p.prosecdef, p.proconfig,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='assert_collection_layout_mutable';

Esperado: prosecdef=true, proconfig contém search_path=,
auth_exec=false (helper interno, nunca chamado por cliente).
*/
