/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: ROLLBACK_v1_12.sql — desfaz 5300–5318 (NÃO a 5319)
Status......: PROPOSTA — usar SÓ se a implantação parar no meio ou se a 5861
              falhar, ANTES de qualquer uso real (convites, publicações).
Data........: 2026-10-30

Idempotente (IF EXISTS); ordem reversa de dependência. A 5319 (privilégios
excedentes) não é desfeita: remove grants sem uso e é independente.
Pré-condições (fail-closed, decisão de Fabrício 2026-10-30):
  1. nenhuma coleção PUBLIC;
  2. nenhuma linha em collection_membership, em QUALQUER estado (ACTIVE,
     PENDING ou DECLINED), inclusive participações de teste/homologação —
     o rollback nunca apaga participação existente. Para prosseguir, o
     titular encerra cada participação pelos contratos (5305/5306); o
     rollback não faz isso por conta própria.
Limite declarado: o contrato de revogação (C-155, 5305/5306) apaga a linha;
não existe histórico de participações encerradas, portanto não há histórico
a preservar nem a perder aqui.
================================================================
*/

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.collection WHERE visibility <> 'PRIVATE') THEN
        RAISE EXCEPTION 'ROLLBACK_ABORTED: existe coleção PUBLIC — despublicar antes';
    END IF;
    IF to_regclass('public.collection_membership') IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.collection_membership) THEN
            RAISE EXCEPTION 'ROLLBACK_ABORTED: existem participações em collection_membership — o rollback não apaga participação';
        END IF;
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.get_public_collection_binder_pages(UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.get_public_collection_binder(UUID);
DROP FUNCTION IF EXISTS public.get_shared_collection_binder_pages(UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.collection_binder_masked_pages(UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.get_shared_collection_binder(UUID);
DROP FUNCTION IF EXISTS public.get_shared_collection_cards(UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.get_shared_collection(UUID);
DROP FUNCTION IF EXISTS public.get_collections_shared_with_me();
DROP FUNCTION IF EXISTS public.collection_completion_summary_shared(UUID);
DROP FUNCTION IF EXISTS public.get_my_collection_invites();
DROP FUNCTION IF EXISTS public.get_my_collection_sharing(UUID);
DROP FUNCTION IF EXISTS public.set_collection_visibility(UUID, TEXT);
DROP FUNCTION IF EXISTS public.leave_shared_collection(UUID);
DROP FUNCTION IF EXISTS public.remove_collection_member(UUID, UUID);
DROP FUNCTION IF EXISTS public.respond_collection_invite(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.invite_collection_member(UUID, TEXT);
DROP FUNCTION IF EXISTS public.collection_share_role(UUID);
DROP TABLE IF EXISTS public.collection_membership;

ALTER TABLE public.collection DROP CONSTRAINT IF EXISTS chk_collection_visibility;
ALTER TABLE public.collection ADD CONSTRAINT chk_collection_visibility CHECK (visibility = 'PRIVATE');

/*
Como validar:
select to_regclass('public.collection_membership') is null as tabela_removida,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in
          ('collection_share_role','invite_collection_member','get_shared_collection','get_public_collection_binder',
           'collection_binder_masked_pages','get_shared_collection_binder_pages')) = 0 as funcoes_removidas,
       (select pg_get_constraintdef(oid) from pg_constraint where conname = 'chk_collection_visibility') as chk;
-- esperado: true · true · CHECK ((visibility = 'PRIVATE'::text))
*/
