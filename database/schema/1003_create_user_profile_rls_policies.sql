/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1003 - Create User Profile RLS policies
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria as políticas de RLS de user_profile: cada usuário
autenticado só lê e atualiza a própria linha. Sem política de
INSERT/DELETE — a criação só acontece via trigger em auth.users
(Query 1020), que roda como dono da function e ignora RLS.

Regras de Negócio:
- SELECT e UPDATE restritos a auth.uid() = id.
- UPDATE usa USING e WITH CHECK idênticos, impedindo tanto ler
  quanto gravar fora da própria linha.
- A imutabilidade de username já está garantida pelo trigger da
  Query 1002 — esta política não duplica essa regra, só decide
  quem pode tentar um UPDATE, não o que pode ser alterado nele.
================================================================
*/

CREATE POLICY user_profile_select_own
    ON public.user_profile
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY user_profile_update_own
    ON public.user_profile
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);
