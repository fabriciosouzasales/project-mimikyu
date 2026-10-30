/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5302 - Create collection_share_role() (interna)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Fronteira única de leitura compartilhada: devolve como o usuário da
sessão pode ver a coleção — 'OWNER', 'VIEWER' (participação ACTIVE) ou
'PUBLIC' (coleção PUBLIC, inclusive sem sessão) — ou NULL (nenhum
acesso; coleção inexistente e coleção alheia são indistinguíveis).

Regras de Negócio:
- PENDING e DECLINED nunca dão acesso (convite não antecipa leitura).
- Precedência OWNER > VIEWER > PUBLIC.
- Interna: sem EXECUTE para PUBLIC/anon/authenticated. Só as leituras
  5311–5313 (SECURITY DEFINER, mesmo dono) a chamam.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_share_role(p_collection_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT CASE
        WHEN (select auth.uid()) IS NOT NULL AND c.owner_user_id = (select auth.uid()) THEN 'OWNER'
        WHEN (select auth.uid()) IS NOT NULL AND EXISTS (
            SELECT 1
            FROM public.collection_membership m
            WHERE m.collection_id = c.id
              AND m.user_id = (select auth.uid())
              AND m.status = 'ACTIVE'
        ) THEN 'VIEWER'
        WHEN c.visibility = 'PUBLIC' THEN 'PUBLIC'
        ELSE NULL
    END
    FROM public.collection c
    WHERE c.id = p_collection_id;
$$;

REVOKE ALL ON FUNCTION public.collection_share_role(UUID) FROM PUBLIC, anon, authenticated;
