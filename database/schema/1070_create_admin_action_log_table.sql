/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1070 - Create Admin Action Log Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria public.admin_action_log: registro de auditoria de ações
administrativas (concessão/revogação do papel de admin). Ver
ADR-021.

Regras de Negócio:
- actor_id e target_user_id são anuláveis, ON DELETE SET NULL:
  a exclusão futura de qualquer um dos dois usuários nunca apaga
  o registro da ação — só desfaz a referência direta.
- metadata (JSONB) guarda um retrato dos dados relevantes
  (username/e-mail de ator e alvo) no momento da ação, para que
  o histórico continue legível mesmo depois que a referência
  direta virar NULL.
- action restrito por CHECK à lista de ações reconhecidas nesta
  fase — ampliar a lista é uma evolução simples (ALTER da
  constraint), não uma mudança estrutural.
- RLS habilitado, sem nenhuma política: só funções SECURITY
  DEFINER escrevem aqui; não há leitura via API nesta fase.
================================================================
*/

CREATE TABLE public.admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL
                     REFERENCES auth.users(id)
                     ON DELETE SET NULL,
    target_user_id   UUID NULL
                     REFERENCES auth.users(id)
                     ON DELETE SET NULL,
    action           TEXT NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT admin_action_log_action_valid
        CHECK (action IN ('GRANT_ADMIN', 'REVOKE_ADMIN'))
);

ALTER TABLE public.admin_action_log
    ENABLE ROW LEVEL SECURITY;
