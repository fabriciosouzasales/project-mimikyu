/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5300 - Create collection_membership table
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030142130 `5300_create_collection_membership_table`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-collection-sharing/
              (só este bloco Status difere); texto do ledger ≡ arquivo da proposta inteiro (md5).
              Validação: 5861 v1.3 51/51 PASS.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Collection Membership (C-142/C-143/C-153): participação de um usuário
NÃO titular numa coleção. O titular continua sendo a relação estrutural
collection.owner_user_id (C-141) — nunca uma linha aqui.

Regras de Negócio:
- role: só 'VIEWER' neste incremento (EDITOR é V1-13; o CHECK será
  alargado lá, quando houver contrato de escrita para ele).
- status: PENDING (convite emitido, sem acesso), ACTIVE (aceito — leitura),
  DECLINED (recusado — sem acesso; o titular vê "recusou" e pode convidar
  de novo). Remoção, cancelamento e saída APAGAM a linha: revogação
  imediata, sem estado intermediário que alguma leitura possa confundir.
- Um par (coleção, usuário) no máximo (UNIQUE) — convite repetido é
  idempotente.
- responded_at preenchido sse status <> PENDING.
- Deny by default: RLS ligada SEM políticas e nenhum privilégio de tabela
  para anon/authenticated. Toda leitura/escrita passa pelas funções
  5303–5313 (SECURITY DEFINER, autorização dentro da função).
- ON DELETE CASCADE nas duas FKs: excluir a coleção (só titular, 5039) ou
  a conta encerra as participações.
================================================================
*/

CREATE TABLE public.collection_membership (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id   UUID NOT NULL REFERENCES public.collection(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'VIEWER',
    status          TEXT NOT NULL DEFAULT 'PENDING',
    invited_by      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    invited_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at    TIMESTAMPTZ NULL,
    CONSTRAINT uq_collection_membership_collection_user UNIQUE (collection_id, user_id),
    CONSTRAINT chk_collection_membership_role CHECK (role IN ('VIEWER')),
    CONSTRAINT chk_collection_membership_status CHECK (status IN ('PENDING', 'ACTIVE', 'DECLINED')),
    CONSTRAINT chk_collection_membership_responded CHECK ((status = 'PENDING') = (responded_at IS NULL))
);

COMMENT ON TABLE public.collection_membership IS
    'Collection Membership (C-142/C-143/C-153, V1-12): participação de usuário não titular. Titular = collection.owner_user_id (C-141), nunca uma linha aqui. Acesso só pelas funções 5303–5313.';

-- Caixa de convites e "compartilhadas comigo": por usuário e estado.
CREATE INDEX ix_collection_membership_user_status
    ON public.collection_membership (user_id, status);

ALTER TABLE public.collection_membership ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.collection_membership FROM PUBLIC, anon, authenticated;
