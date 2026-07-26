/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1050 - Create Admin User Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria a tabela public.admin_user: presença de uma linha significa
que o usuário é administrador. Entidade separada de user_profile
(ver ADR-021) — nenhuma política de RLS é criada para esta
tabela; todo acesso passa por funções SECURITY DEFINER (Queries
1060-1062).

Regras de Negócio:
- id referencia auth.users(id), ON DELETE CASCADE: se a conta do
  administrador for excluída, sua entrada administrativa some
  junto — não há sentido em preservá-la isoladamente.
- granted_by é anulável, ON DELETE SET NULL: identifica quem
  concedeu o papel quando possível, mas a exclusão futura desse
  concedente nunca deve apagar ou invalidar a concessão em si.
- Sem coluna updated_at/trigger: é uma tabela de presença
  (INSERT/DELETE), não um registro editável.
================================================================
*/

CREATE TABLE public.admin_user (
    id           UUID PRIMARY KEY
                 REFERENCES auth.users(id)
                 ON DELETE CASCADE,
    granted_by   UUID NULL
                 REFERENCES auth.users(id)
                 ON DELETE SET NULL,
    granted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_user
    ENABLE ROW LEVEL SECURITY;
