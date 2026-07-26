/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1000 - Create User Profile table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria a tabela public.user_profile, entidade de identidade e perfil
básico do usuário, separada de auth.users (Supabase Auth) conforme
ADR-020. Relação 1:1 via chave primária compartilhada (id).

Regras de Negócio:
- username é a identidade pública, única e estável do usuário
  (formato: minúsculas, dígitos e underscore, 3 a 20 caracteres).
  A imutabilidade em si é imposta por trigger em Query própria
  (1002), não por esta Query.
- display_name é editável a qualquer momento pelo usuário; seu
  trim também é imposto por trigger em Query própria (1002) — o
  CHECK aqui usa trim() como reforço redundante, não como único
  lugar onde a normalização acontece.
- avatar_path guarda o caminho relativo dentro do bucket de
  Storage "avatars" (Query 1040), não a URL pública completa.
- RLS habilitado nesta mesma Query, sem políticas ainda (Query
  1003 traz as políticas de SELECT/UPDATE da própria linha).
================================================================
*/

CREATE TABLE public.user_profile (
    id            UUID PRIMARY KEY
                  REFERENCES auth.users(id)
                  ON DELETE CASCADE,
    username      TEXT NOT NULL,
    display_name  TEXT NOT NULL,
    avatar_path   TEXT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT user_profile_username_unique
        UNIQUE (username),
    CONSTRAINT user_profile_username_format
        CHECK (username ~ '^[a-z0-9_]{3,20}$'),
    CONSTRAINT user_profile_display_name_length
        CHECK (char_length(trim(display_name)) BETWEEN 1 AND 60)
);

ALTER TABLE public.user_profile
    ENABLE ROW LEVEL SECURITY;
