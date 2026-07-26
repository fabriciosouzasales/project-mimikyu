/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2010 - Create Catalog Admin Action Log Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria public.catalog_admin_action_log: auditoria própria do módulo
Catálogo Editorial — Escrita e Ingestão, deliberadamente separada
de public.admin_action_log (domínio de Identidade & Acesso,
ADR-021, CHECK restrito a GRANT_ADMIN/REVOKE_ADMIN). Ver ADR-023,
seção "Auditoria editorial própria, separada de admin_action_log".

Este é o nome definitivo da tabela — ADR-023 registrou apenas um
exemplo (catalog_admin_action_log) e deixou a confirmação para
este documento/Query, conforme previsto em sua seção
"Restrições / Pendências".

Regras de Negócio:
- Registra toda operação administrativa bem-sucedida das funções
  criadas por ADR-023 (Game/Expansion/Card Set/Card) e, em
  ADR-024, a confirmação em lote de importação — sempre uma linha
  agregada por chamada (referenciando o job), nunca uma linha por
  Card confirmada; o detalhe linha a linha já vive em
  catalog_import_row.
- actor_id anulável com ON DELETE SET NULL, mesmo padrão de
  admin_action_log (Query 1070): a exclusão futura do usuário
  nunca apaga o registro da ação, só desfaz a referência direta.
- entity_id é polimórfico (aponta para game, expansion, card_set
  ou card, dependendo de entity_type) e por isso não tem FK —
  mesmo motivo estrutural pelo qual não há uma única tabela-alvo
  possível. É NOT NULL: toda ação registrada aqui sempre tem
  exatamente uma entidade concreta como alvo, nunca uma ação
  global.
- action restrito por CHECK às 10 ações reconhecidas nesta fase
  (ADR-023); ampliar a lista é uma evolução simples (ALTER da
  constraint), não uma mudança estrutural — mesmo padrão já usado
  em admin_action_log.
- CHECK adicional garante que action é sempre compatível com
  entity_type (ex.: GAME_CREATED só é aceito com entity_type =
  'GAME') — reforço de integridade de implementação, não uma
  decisão de ADR-023; impede que um erro na função de escrita
  grave uma combinação logicamente inválida na auditoria.
- metadata (JSONB) anulável, sem valor padrão — mesmo padrão de
  admin_action_log (Query 1070), guarda um retrato dos dados
  relevantes da operação no momento da ação.
- RLS habilitado, sem nenhuma política: só funções SECURITY
  DEFINER escrevem aqui; não há leitura via API nesta fase, mesmo
  padrão de admin_action_log.
- Sem updated_at/trigger: tabela de auditoria append-only, nunca
  editada após a escrita.

Pré-requisitos:
- Query 2000 - Create Internal Schema (mesmo módulo).
================================================================
*/

CREATE TABLE public.catalog_admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL
                     REFERENCES auth.users(id)
                     ON DELETE SET NULL,
    action           TEXT NOT NULL,
    entity_type      TEXT NOT NULL,
    entity_id        UUID NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT ck_catalog_admin_action_log_action_valid
        CHECK (
            action IN (
                'GAME_CREATED', 'GAME_UPDATED',
                'EXPANSION_CREATED', 'EXPANSION_UPDATED',
                'CARD_SET_CREATED', 'CARD_SET_UPDATED',
                'CARD_CREATED', 'CARD_UPDATED',
                'CARD_DEACTIVATED', 'CARD_REACTIVATED'
            )
        ),

    CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
        CHECK (
            entity_type IN ('GAME', 'EXPANSION', 'CARD_SET', 'CARD')
        ),

    CONSTRAINT ck_catalog_admin_action_log_action_entity_match
        CHECK (
            (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED'))
            OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED'))
            OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED'))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
        )
);

COMMENT ON TABLE public.catalog_admin_action_log IS
    'Auditoria própria do Catálogo Editorial — Escrita e Ingestão (ADR-023/ADR-024), separada de admin_action_log.';

COMMENT ON COLUMN public.catalog_admin_action_log.actor_id IS
    'Administrador que executou a ação. Anulável: sobrevive à exclusão futura do usuário.';

COMMENT ON COLUMN public.catalog_admin_action_log.action IS
    'Ação administrativa executada, restrita à lista reconhecida em ADR-023.';

COMMENT ON COLUMN public.catalog_admin_action_log.entity_type IS
    'Tipo da entidade afetada: GAME, EXPANSION, CARD_SET ou CARD.';

COMMENT ON COLUMN public.catalog_admin_action_log.entity_id IS
    'Identificador da entidade afetada. Polimórfico (sem FK) — a tabela real depende de entity_type.';

COMMENT ON COLUMN public.catalog_admin_action_log.metadata IS
    'Retrato dos dados relevantes da operação no momento da ação, para leitura futura mesmo após alterações posteriores.';

COMMENT ON COLUMN public.catalog_admin_action_log.created_at IS
    'Data e hora da ação. Tabela append-only, sem updated_at.';

ALTER TABLE public.catalog_admin_action_log ENABLE ROW LEVEL SECURITY;
