/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5142 - Create bulk_operation table
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO (2026-09-07)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BULK-01-PHYSICAL-PROPOSAL-01;
               v1.1 em -REVISION-01)

v1.1 — três correções, incorporadas ANTES da aplicação (a v1.0 nunca
chegou ao banco):
  (a) `preview_fingerprint` passa a NOT NULL + CHECK de não-branco;
  (b) removido o índice especulativo `(owner_user_id, created_at DESC)`
      — não há workload aprovado;
  (c) grants: `authenticated` deixa de ter SELECT. Ledger interno, sem
      caminho de acesso direto para papel algum de aplicação.

Descrição...:
Ledger MÍNIMO de operações Bulk. Existe por UM motivo: tornar
idempotente uma operação de criação de patrimônio em massa.

NÃO É Activity/Audit. Sem trigger de histórico, sem linha por item
afetado, sem consumo por UI de histórico. C-178/LDM-166 (Activity
agrupada) seguem em aberto, em frente própria.

D9 — LEDGER TRANSACIONAL, SEM `status`
--------------------------------------
Uma linha committada É uma operação bem-sucedida. Isso é a definição,
não uma convenção:

- o claim nasce na MESMA transação da operação (Query `5144`);
- sucesso  -> `result_summary` preenchido + COMMIT;
- falha    -> ROLLBACK apaga também o claim, liberando retry com a
              mesma `idempotency_key`;
- `FAILED` NUNCA é persistido.

Por isso NÃO existe coluna `status`: com FAILED nunca persistido ela
teria um único valor possível, e uma coluna de valor único é ruído que
convida a interpretação errada.

`result_summary` é NULLABLE por necessidade estrutural — o claim é
inserido antes de a operação produzir resultado. O invariante "nenhuma
linha PERSISTENTE com result_summary NULL" é garantido pela Query
`5143` (constraint trigger DEFERRABLE INITIALLY DEFERRED), não por
NOT NULL: um NOT NULL impediria o próprio claim.

IDENTIDADE E IDEMPOTÊNCIA
-------------------------
`UNIQUE (owner_user_id, operation_type, idempotency_key)` é, ao mesmo
tempo:
  (a) a identidade lógica da operação;
  (b) o MECANISMO DE SERIALIZAÇÃO entre sessões concorrentes — ver
      Query `5144`, que usa `INSERT ... ON CONFLICT DO NOTHING` sem
      SELECT-antes-de-INSERT.

`request_hash` é a INTENÇÃO do usuário (requisição normalizada).
`preview_fingerprint` é o ESTADO DO MUNDO no momento do preview.
São coisas diferentes e ficam em colunas diferentes de propósito:
  - mesma chave + mesmo request_hash  -> REPLAY;
  - mesma chave + request_hash outro  -> BULK_IDEMPOTENCY_CONFLICT;
  - fingerprint divergente            -> PREVIEW_STALE (caminho novo).

`preview_fingerprint` é NOT NULL: os dois `operation_type` do
vocabulário atual exigem preview antes da confirmação, logo não existe
operação legítima sem fingerprint. Ele NÃO participa da semântica de
idempotência — um replay NUNCA é invalidado por mudança posterior do
estado do mundo (D9).

ÍNDICES
-------
Apenas os ESTRUTURALMENTE necessários: a PK e o índice implícito da
UNIQUE de identidade/serialização. Nenhum índice especulativo — não há
workload aprovado que justifique um, e índice sem medição é custo de
escrita garantido contra benefício hipotético.

SEGURANÇA
---------
Ledger INTERNO. Na V1 nenhum papel de aplicação acessa a tabela
diretamente: `authenticated`, `anon` e `service_role` ficam sem
privilégio algum. Leitura e escrita acontecem exclusivamente dentro das
funções `SECURITY DEFINER` de `5144`/`5145`.

RLS fica ligada e a policy owner-scoped existe como DEFESA EM
PROFUNDIDADE — para que um GRANT futuro já nasça restrito ao dono —,
não como caminho de acesso vigente.

Dependências: auth.users.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO (2026-09-07). Ledger e
evidencia de validacao no README.md desta pasta.
================================================================
*/

BEGIN;

CREATE TABLE public.bulk_operation (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id       UUID NOT NULL
                            REFERENCES auth.users(id)
                            ON UPDATE RESTRICT ON DELETE RESTRICT,
    operation_type      TEXT NOT NULL,
    idempotency_key     UUID NOT NULL,
    request_hash        TEXT NOT NULL,
    preview_fingerprint TEXT NOT NULL,
    result_summary      JSONB NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.bulk_operation IS
    'Ledger minimo de operacoes Bulk de Collections. Existe para idempotencia (D3/D9): uma linha committada E uma operacao bem-sucedida. Sem coluna status — FAILED nunca e persistido; ROLLBACK apaga o claim. NAO e Activity/Audit (C-178/LDM-166 seguem em frente propria).';

COMMENT ON COLUMN public.bulk_operation.request_hash IS
    'Hash da requisicao NORMALIZADA — a INTENCAO do usuario. Chaves ordenadas, items ordenados por (card_variant_id, language_id), exclude_variant_ids ordenado e deduplicado, quantity como inteiro, campo ausente equivale a null. idempotency_key e preview_fingerprint sao EXCLUIDOS do hash.';

COMMENT ON COLUMN public.bulk_operation.preview_fingerprint IS
    'ESTADO DO MUNDO no preview. NOT NULL: os dois operation_type do vocabulario atual (REGISTER_PHYSICAL_CARDS, REGISTER_CARD_SET) EXIGEM preview antes da confirmacao, logo nao existe operacao legitima sem fingerprint. NAO participa da semantica de idempotencia — replay nunca e invalidado por mudanca posterior do mundo (D9). Ampliar o vocabulario com um tipo que dispense preview exige revisitar esta constraint.';

COMMENT ON COLUMN public.bulk_operation.result_summary IS
    'Resultado devolvido no replay. NULLABLE por necessidade estrutural (o claim nasce antes do resultado). O invariante "nenhuma linha PERSISTENTE com result_summary NULL" e garantido pelo constraint trigger diferido da Query 5143, nunca por NOT NULL.';

-- Vocabulario FECHADO. Ampliar exige migration propria e explicita.
ALTER TABLE public.bulk_operation
    ADD CONSTRAINT chk_bulk_operation_type
    CHECK (operation_type IN (
        'REGISTER_PHYSICAL_CARDS',   -- B1, Query futura (BULK-02)
        'REGISTER_CARD_SET'          -- B2, Query futura (BULK-04)
    ));

ALTER TABLE public.bulk_operation
    ADD CONSTRAINT chk_bulk_operation_request_hash_not_blank
    CHECK (btrim(request_hash) <> '');

ALTER TABLE public.bulk_operation
    ADD CONSTRAINT chk_bulk_operation_preview_fingerprint_not_blank
    CHECK (btrim(preview_fingerprint) <> '');

-- IDENTIDADE + SERIALIZACAO. Ver 5144: o indice desta UNIQUE e o que
-- faz duas sessoes concorrentes com a mesma chave se serializarem.
-- E O UNICO indice desta tabela alem da PK: nao ha workload aprovado
-- que justifique qualquer outro. Indice especulativo so entra depois
-- de medicao (regra de ouro do 5819).
ALTER TABLE public.bulk_operation
    ADD CONSTRAINT uq_bulk_operation_owner_type_key
    UNIQUE (owner_user_id, operation_type, idempotency_key);

-- ================================================================
-- ACESSO: LEDGER INTERNO, NAO Activity/Audit.
--
-- Na V1 NENHUM papel de aplicacao le esta tabela diretamente:
--   authenticated -> sem SELECT;
--   anon          -> sem acesso;
--   service_role  -> sem acesso.
--
-- Leitura e escrita operacionais acontecem EXCLUSIVAMENTE dentro das
-- funcoes SECURITY DEFINER de 5144/5145, que rodam como postgres.
--
-- RLS fica LIGADA e a policy owner-scoped e criada como DEFESA EM
-- PROFUNDIDADE: se um GRANT de leitura for concedido no futuro (por
-- exemplo, uma tela de historico), o escopo por dono ja esta em vigor
-- e nao depende de alguem lembrar de cria-lo. A policy NAO e o caminho
-- de acesso vigente — hoje nao ha caminho de acesso direto.
-- ================================================================
ALTER TABLE public.bulk_operation ENABLE ROW LEVEL SECURITY;

CREATE POLICY bulk_operation_select_own
    ON public.bulk_operation FOR SELECT
    USING (owner_user_id = (select auth.uid()));

COMMENT ON POLICY bulk_operation_select_own ON public.bulk_operation IS
    'Defesa em profundidade. Na V1 nenhum papel tem GRANT SELECT, entao esta policy nao e exercida — existe para que um GRANT futuro ja nasca restrito ao dono.';

-- Nenhum GRANT de aplicacao. Revogacao explicita, incluindo os
-- privilegios que pg_default_acl concede por padrao em tabelas criadas
-- por postgres (mesmo padrao de 3053/6111).
REVOKE ALL ON public.bulk_operation FROM anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5821`, nesta mesma pasta.

Verificação rápida:

SELECT c.relrowsecurity,
       pg_get_userbyid(c.relowner)                                   AS owner,
       has_table_privilege('authenticated', c.oid, 'SELECT')         AS auth_select,
       has_table_privilege('authenticated', c.oid, 'INSERT')         AS auth_insert,
       has_table_privilege('anon',          c.oid, 'SELECT')         AS anon_select,
       has_table_privilege('service_role',  c.oid, 'SELECT')         AS service_select
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname='public' AND c.relname='bulk_operation';

Esperado: rls=t, owner=postgres, auth_select=f, auth_insert=f,
anon_select=f, service_select=f — NENHUM papel de aplicacao tem acesso
direto.

Indices esperados: EXATAMENTE 2 (PK + UNIQUE).

SELECT indexrelid::regclass AS idx
FROM pg_index
WHERE indrelid = 'public.bulk_operation'::regclass
ORDER BY 1;
*/
