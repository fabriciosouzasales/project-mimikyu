/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1010 - Create Reserved Username table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria public.reserved_username, tabela de apoio com termos que
não podem ser usados como username (ex.: admin, suporte). Não é
uma entidade de domínio — existe só para governar a validação de
username em user_profile.

Regras de Negócio:
- RLS habilitado, sem nenhuma política para anon/authenticated:
  a única leitura possível é via function SECURITY DEFINER
  (username_available(), Query 1030, e o trigger da Query 1020),
  que roda com o privilégio do dono da function, ignorando RLS.
- username já é gravado normalizado (trim + lowercase) pela
  própria Seed (Query 1710) — esta tabela não tem trigger de
  normalização próprio, diferente de user_profile.
================================================================
*/

CREATE TABLE public.reserved_username (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username   TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.reserved_username ENABLE ROW LEVEL SECURITY;
