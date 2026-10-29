/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_DRYRUN_S1_rollback_v2.3.sql — ensaio da P3-B S1 no LIVE com reversão total
Versão......: 2.3 (2026-10-27, E3 BASELINE RECONCILIATION — MEP-01: precheck T6 exige o último ledger
              20261026124224 fix_mep_bootstrap_preserve_confirmed_primary_identity (versão e nome); nada mais muda)
              2.2 (2026-10-26, P3-B S1 E3 DRY-RUN v2.2: T8a identifica as 10 funções da S1
              pela lista canônica do LIVE_90 (90.3, 90.4, 90.10); v2.1 falhou nesses itens
              porque usava like '%binder_activity%' e omitia list_my_closed_binder_histories)
              2.1 (2026-10-25, P3-B-S1-FINAL-READINESS-03: só cabeçalho — locks,
              lock_timeout, contrato do executor, restauração da sessão; SQL inalterado)
              2.0 (P3-B-S1-LIVE-DRYRUN-STRUCTURAL-CORRECTION-02)
              1.0 (P3-B-S1-SECURITY-CORRECTION-01) SUBSTITUÍDA: embutia as migrations
              num único bloco DO PL/pgSQL (defeito apontado pela auditoria).
Status......: PROPOSTA — NÃO EXECUTADO. GERADO por build_live_dryrun_s1.py; não editar à
              mão (S.18 recusa divergência). Execução só com autorização expressa e
              específica de Fabrício para o ENSAIO (não abre G8).
Fontes......: 5267@e8e69f4c5020656e, 5268@76e2bac4de3dffed, 5269@98d83f701c9d3b1d, 5270@53dc5fd526315b56

----------------------------------------------------------------
A. Estrutura transacional (ordem exata dos statements)
----------------------------------------------------------------
  T0  SET SESSION default_transaction_read_only = on      guarda de autocommit
  T1  BEGIN                                                 única abertura
  T2  SET TRANSACTION READ WRITE                            só esta transação escreve
  T3  SET LOCAL statement_timeout / lock_timeout /
      idle_in_transaction_session_timeout / transaction_timeout
  T4  trava de COMMIT: 2 tabelas temporárias + 1 linha que viola uma FK
      DEFERRABLE INITIALLY DEFERRED → qualquer COMMIT desta transação falha
  T5  tabela temporária de evidência
  T6  DO precheck (só leitura + evidência)
  T7  5267 → 5270, statement a statement, texto idêntico ao aprovado, no nível
      superior (sem os `begin;`/`commit;` próprios)
  T8  DO postcheck, DO sondas (só verificação; nenhuma DDL)
  T9  DO sentinela: RAISE EXCEPTION 'MSDRYRUN {json}' — SEMPRE
  T10 ROLLBACK
  T11 RESET default_transaction_read_only
  Não há COMMIT, END, SAVEPOINT nem SET CONSTRAINTS em nenhum ponto (S.18c/S.18h).

----------------------------------------------------------------
B. Por que o ensaio não pode confirmar alterações
----------------------------------------------------------------
  1. Caminho normal termina em ERRO (T9): a transação aborta e tudo é desfeito.
  2. COMMIT enviado por engano com a transação abortada: o PostgreSQL responde
     ROLLBACK (comportamento padrão de COMMIT em bloco abortado).
  3. COMMIT enviado com a transação ainda ativa (ex.: alguém remove T9): a
     verificação adiada da FK de T4 falha no COMMIT e a transação é desfeita.
  4. Executor que ignora o BEGIN e confirma statement a statement: T0 deixou a
     sessão em somente leitura; T2 vira só um aviso; todo CREATE/INSERT em
     public falha com 25006 (read-only transaction). Nada persiste; a sessão
     fica em somente leitura até RESET/reconexão (falha segura).
  5. Envio do script inteiro numa só mensagem (Supabase SQL Editor, execute_sql):
     T0 roda dentro do bloco convertido pelo BEGIN e é desfeito pelo
     ROLLBACK/aborto; qualquer erro descarta o resto da mensagem.
  Única forma de confirmar algo: editar o arquivo (remover T0/T4/T9 e incluir
  COMMIT) — bloqueado pelo S.18 e fora de qualquer autorização.

----------------------------------------------------------------
C. Comportamento diante de erros
----------------------------------------------------------------
  | Momento                          | Efeito                                         |
  | T0–T5 (antes da aplicação)       | transação abortada; nada criado; STOP          |
  | T6 precheck falha                | 'DRYRUN PRECHECK FALHOU' → abortada; STOP      |
  | T7 statement de migration falha  | abortada; DDL parcial descartada; STOP         |
  |  (inclui lock_timeout/statement) |                                                |
  | T8 postcheck/sonda diverge       | 'DRYRUN POSTCHECK FALHOU {json}' → abortada; |
  |                                  | STOP                                           |
  | T9 caminho normal                | 'MSDRYRUN {"ok":true,…}' → abortada (esperado)|
  Em qualquer aborto, o PostgreSQL libera locks e reverte SET LOCAL na hora do
  erro; a sessão fica em "idle in transaction (aborted)" até ROLLBACK ou fim da
  conexão, sem segurar locks.

----------------------------------------------------------------
D. Contrato do executor (obrigatório; README §23)
----------------------------------------------------------------
  D1 Conexão única: todo o script na MESMA conexão, do T0 ao T11. Proibido
     pooler em modo transação/statement que troque de backend entre comandos.
  D2 Execução integral: o arquivo inteiro, na ordem, sem edição, sem seleção de
     trechos, sem acrescentar comandos. Hash do arquivo conferido antes (S.18a).
  D3 Formas aceitas (uma só):
     E1 script inteiro numa única mensagem simple-query (SQL Editor do Supabase;
        execute_sql), sem parâmetros;
     E2 psql NÃO interativo: psql -X -v ON_ERROR_STOP=1 -f LIVE_DRYRUN_S1_rollback_v2.3.sql
        (sem -1/--single-transaction, sem \i dentro de sessão interativa).
  D4 Tratamento de erros: parar no primeiro erro. O erro esperado é o da T9
     ('MSDRYRUN …'); qualquer outro é STOP. Não reexecutar, não completar à mão,
     não enviar COMMIT.
  D5 Recuperação da sessão, sempre, no fim, qualquer que seja o resultado:
     fechar a conexão. Se a conexão precisar continuar aberta (ferramenta que
     reaproveita a sessão): enviar ROLLBACK; e depois
     RESET default_transaction_read_only; e conferir
     SHOW default_transaction_read_only = off antes de qualquer outro uso.
  D6 Interrupção / perda de conexão: o servidor desfaz a transação ao perceber a
     queda (ao fim do statement corrente, limitado por statement_timeout);
     ocioso em transação ativa → idle_in_transaction_session_timeout (15 s)
     encerra a sessão. Depois, conferir o pós-estado (item 8). Não repetir.

----------------------------------------------------------------
E. Restauração de default_transaction_read_only por caminho
----------------------------------------------------------------
  T0 é SET de sessão. Se ele é desfeito depende de ter rodado dentro ou fora da
  transação do ensaio (por inspeção do código do PostgreSQL; não exercitado):
  | Caminho                                   | T0 fica na sessão?          |
  | E1 mensagem única (T0 no bloco implícito  | não: o BEGIN converte o     |
  |    convertido pelo BEGIN)                 | bloco; o aborto desfaz T0   |
  | E2 psql -f, para no erro da T9            | sim, mas a conexão fecha    |
  |                                           | ao sair → sem resíduo       |
  | executor que continua após erro           | não: T10 ROLLBACK + T11     |
  |                                           | RESET restauram             |
  | \i interativo / ferramenta que para no    | SIM — resíduo: sessão em    |
  |    erro e mantém a sessão aberta          | somente leitura até D5      |
  | executor que ignora o BEGIN e para no erro| SIM — idem (falha segura)   |
  O resíduo nunca permite escrita: só deixa a sessão em somente leitura. Por
  isso D5 (fechar a conexão ou RESET + SHOW) é parte obrigatória do contrato e
  item do pós-estado (8). SET LOCAL, papel (SET ROLE), claims, tabelas
  temporárias e locks não deixam resíduo em nenhum caminho: são desfeitos no
  aborto ou no ROLLBACK.

----------------------------------------------------------------
1. SQL exato           → corpos das 5267–5270 em T7, statement a statement,
                         idênticos aos arquivos (hash acima; S.18e compara
                         statement por statement com o lexer).
2. Objetos temporários → 4 tabelas, sequência da identidade, 1 índice, 4
                         gatilhos, 10 funções, 1 linha em _setting, 1 evento
                         LEGADO + 1 item (cópia real da Chi-Yu); 3 tabelas
                         temporárias do ensaio. Nada existente é alterado.
3. Locks               → auth.users: SHARE ROW EXCLUSIVE, pedido pela primeira
                         FK da 5267 e mantido até o fim da transação (aborto ou
                         ROLLBACK). Compatível com SELECT comum (ACCESS SHARE) e
                         com SELECT … FOR UPDATE/SHARE e verificações de FK de
                         outras tabelas (ROW SHARE). Conflita com INSERT/UPDATE/
                         DELETE em auth.users (ROW EXCLUSIVE) e com VACUUM/
                         ANALYZE dela. Autenticação: a validação do JWT nas
                         requisições não lê auth.users no banco; leituras de
                         login seguem; o que ESCREVE em auth.users (cadastro,
                         gravação de last_sign_in_at no login, confirmação de
                         e-mail, alteração de dados/senha, exclusão) espera até
                         o fim do ensaio. Ao pedir o lock, a 5267 espera
                         escritores já em curso em auth.users (até 2 s) e, nessa
                         espera, novos escritores entram na fila atrás dela;
                         leitores não. Tabelas novas: locks invisíveis a outras
                         sessões. Leituras (ACCESS SHARE) em collection_layout,
                         collection, *_catalog_incorporation, card, card_set,
                         card_variant_type.
4. Não revertido       → xid e OIDs consumidos; WAL; tuplas mortas no catálogo
                         (autovacuum); pg_stat_* e pg_stat_statements; logs.
                         Sem resíduo de sequência, ledger, NOTIFY (pgrst_ddl_watch
                         só entrega em COMMIT), grants, GUCs ou dados.
5. Tempo e recursos    → lock_timeout 2 s limita só a ESPERA para obter cada
                         lock; não limita quanto tempo o lock obtido fica
                         mantido. A duração do lock em auth.users = do statement
                         da 5267 até o fim da transação, limitada por: statement
                         20 s (cada statement); ocioso 15 s; transação 60 s
                         (transaction_timeout definido dentro da transação:
                         conforme o PG 17 passa a contar a partir do SET — não
                         comprovado por execução). Esperado < 2 s no total.
                         Janela fora de uso (item 3).
6. STOP                → qualquer erro que não comece com 'MSDRYRUN'; 'ok':false;
                         duration_ms > 5000; pós-estado (item 8) divergente. Não
                         repetir sem nova autorização.
7. Evidência           → erro P0001 'MSDRYRUN {json}' com precheck, 90.2–90.12,
                         sondas, contagens, txid e duration_ms; em E2 também as
                         linhas de evidência impressas antes do erro (NOTICE).
8. Pós-estado          → LIVE_00 inteiro true (ledger 20261026124224, nenhum objeto
                         binder_activity_*, 5267–5270 livres, 1 incorporação);
                         nenhuma sessão do ensaio em pg_stat_activity;
                         nenhum lock em auth.users vindo dela (pg_locks);
                         conexão fechada, ou SHOW default_transaction_read_only
                         = off na sessão reaproveitada (D5, seção E).
9. Limitações          → NÃO prova: sintaxe por parser antes da execução, concorrência,
                         desempenho, gravação real, exclusões com dados,
                         apply_migration/ledger. Sondas rodam como postgres com
                         SET ROLE (não exercitam PostgREST/JWT). O lexer do S.18
                         valida estrutura léxica, não gramática.
================================================================
*/

-- T0 guarda de autocommit (falha segura se o executor ignorar o BEGIN)
set session default_transaction_read_only = on;

-- T1/T2 única transação do ensaio
begin;
set transaction read write;

-- T3 limites
set local statement_timeout = '20s';
set local lock_timeout = '2s';
set local idle_in_transaction_session_timeout = '15s';
set local transaction_timeout = '60s';

-- T4 trava de COMMIT: a linha abaixo viola a FK adiada; qualquer COMMIT falha
create temporary table mmkyu_dryrun_veto_parent (id integer primary key);
create temporary table mmkyu_dryrun_veto_child (
  parent_id integer not null
            references mmkyu_dryrun_veto_parent (id) deferrable initially deferred
);
insert into mmkyu_dryrun_veto_child (parent_id) values (1);

-- T5 evidência
create temporary table mmkyu_dryrun_evidence (k text primary key, v jsonb not null);

-- T6 precheck (só leitura)
do $dry_pre$
begin
  if current_setting('transaction_read_only') <> 'off'
     or not exists (select 1 from pg_temp.mmkyu_dryrun_veto_child)
     or current_setting('session_replication_role') <> 'origin'
     or coalesce(current_setting('mmkyu.binder_activity_purge', true), '') <> ''
     or coalesce(current_setting('mmkyu.binder_activity_ctx', true), '') <> ''
     or coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
          <> '20261026124224|fix_mep_bootstrap_preserve_confirmed_primary_identity'
     or exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5267|5268|5269|5270)_')
     or exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public' and c.relname like 'binder_activity%')
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname like '%binder_activity%')
     or (select count(*) from public.collection_layout_catalog_incorporation) <> 1 then
    raise exception 'DRYRUN PRECHECK FALHOU — STOP' using errcode = 'P0001';
  end if;
  insert into pg_temp.mmkyu_dryrun_evidence values
    ('precheck', 'true'::jsonb), ('txid', to_jsonb(pg_current_xact_id()::text));
end;
$dry_pre$;

-- T7 migrations 5267 → 5270 (texto aprovado, nível superior)
-- ===== 5267_create_binder_activity_structures.sql (sha256 e8e69f4c5020656e) — sem `begin;`/`commit;` próprios =====
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5267 - P3-B S1 · Histórico do Fichário — estruturas
              binder_activity_event · binder_activity_item ·
              binder_activity_coverage · binder_activity_setting
              + gatilhos de imutabilidade (exceção controlada)
Versão......: 1.1 (2026-10-25, P3-B-S1-SECURITY-CORRECTION-01: B1 e W8)
Status......: PROPOSTA — NÃO EXECUTADA. G8 (autorização LIVE) FECHADO.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: concept-decisions.md C-201–C-209; logical-model.md LDM-196–LDM-203;
              README da proposta (v1.3) §3, §6, §12, §19.

O que cria (só objetos novos; nenhuma função ou tabela existente é tocada):
  1. binder_activity_event   — um evento por operação lógica concluída.
     · owner_user_id  = titular (dono do fichário NO MOMENTO do evento),
       FK auth.users ON DELETE CASCADE  → exclusão de conta (A5).
     · layout_key     = id do fichário SEM FK → o evento sobrevive à
       desmontagem e à remoção do fichário (A1).
     · actor_user_id  = quem executou, guardado como VALOR (sem FK, B1).
       Validado na gravação (5268: precisa ser auth.uid() e, na V1, o
       titular). Nunca é reescrito: nenhuma ação referencial, nenhum UPDATE.
       NULL só em legado (D4). Se a conta de um ator que não é o titular for
       excluída (só possível com colaboração futura), o valor permanece como
       identificador opaco, sem resolução para auth.users; anonimização, se
       exigida, é decisão própria (README §19.1), nunca UPDATE silencioso.
     · id identity    = desempate da ordem e cursor de paginação. A sequência
       da identidade tem REVOKE explícito (W8), independente dos privilégios
       padrão do papel executor.
  2. binder_activity_item    — itens do evento (efeitos internos), com cópia
     de carta e posições (R3). Cascata a partir do evento.
  3. binder_activity_coverage — marco mínimo por (titular, fichário):
     só data e motivo, nenhum conteúdo histórico (exclusão definitiva,
     recebimento futuro entre usuários, montagem). Não é histórico.
  4. binder_activity_setting  — linha única com a data de início da
     cobertura completa (NULL até a última fatia S2–S6, O4).

Imutabilidade (C-179 + exceção controlada, C-203):
  · UPDATE em evento/item → sempre recusado.
  · DELETE em evento → recusado, EXCETO:
      (a) exclusão definitiva: a função 5270 marca a transação com
          mmkyu.binder_activity_purge = '<titular>:<fichário>' e só apaga
          eventos desse par;
      (b) exclusão da conta: a linha do titular em auth.users já não existe
          (cascata da FK).
  · DELETE em item → só quando o evento-pai já não existe (cascata).
  · TRUNCATE → recusado.
  · Clientes não têm nenhum privilégio nas tabelas (só funções 5269).

Índices (hipóteses de desempenho, a medir na S1 — README §10.3):
  · ix_bae_owner_layout_time: (owner_user_id, layout_key, occurred_at desc, id desc)
    → leitura paginada por chave composta; prefixo serve à cascata da conta
    e à listagem de fichários encerrados.
  · (removido na v1.1) ix_bae_actor: só existia para a ação SET NULL da FK
    do ator, que deixou de existir (B1). Nenhuma leitura filtra por ator.
  · PK do item (event_id, ordinal) → itens de uma página de eventos.

Dependências: auth.users; collection_layout (só para os prechecks).
================================================================
*/

do $pre$
begin
  if to_regclass('public.binder_activity_event') is not null
     or to_regclass('public.binder_activity_item') is not null
     or to_regclass('public.binder_activity_coverage') is not null
     or to_regclass('public.binder_activity_setting') is not null then
    raise exception 'PRECHECK 5267: estruturas do histórico já existem';
  end if;
  if to_regclass('public.collection_layout') is null then
    raise exception 'PRECHECK 5267: collection_layout ausente';
  end if;
end;
$pre$;

-- 1. Evento --------------------------------------------------------------------------------
create table public.binder_activity_event (
  id              bigint      generated always as identity primary key,
  owner_user_id   uuid        not null
                  references auth.users (id) on update restrict on delete cascade,
  layout_key      uuid        not null,
  occurred_at     timestamptz not null default now(),
  actor_user_id   uuid        null,   -- valor, sem FK (B1): nunca alterado após a gravação
  event_type      text        not null,
  source          text        not null,
  collection_id   uuid        null,
  collection_name text        null,
  binder_name     text        null,
  summary         jsonb       not null default '{}'::jsonb,
  created_xact    xid8        not null default pg_current_xact_id(),
  constraint chk_bae_event_type check (event_type in (
    'BINDER_ASSEMBLED',                 -- E01
    'CARD_PLACED',                      -- E02
    'CARD_MOVED',                       -- E03
    'CARDS_SWAPPED',                    -- E04
    'CARDS_REMOVED',                    -- E05
    'CARDS_LEFT_BY_STORAGE',            -- E06a
    'CARDS_LEFT_BY_COLLECTION_STORAGE', -- E06b
    'CARD_LEFT_BY_INVENTORY_EXIT',      -- E07
    'POCKET_RESERVED',                  -- E08
    'RESERVATIONS_RELEASED',            -- E09
    'POCKETS_LOCKED',                   -- E10
    'POCKETS_UNLOCKED',                 -- E10
    'GAP_OPENED',                       -- E11
    'GAP_CLOSED',                       -- E12
    'PAGES_ADDED',                      -- E13
    'PAGE_REMOVED',                     -- E14
    'PAGES_REORDERED',                  -- E15
    'CATALOG_NOVELTIES_INCORPORATED',   -- E16
    'COLLECTION_ATTACHED',              -- E17
    'COLLECTION_DETACHED',              -- E18
    'BINDER_DISMANTLED',                -- E19
    'BINDER_DELETED_EMPTY',             -- E19b
    'BINDER_OWNERSHIP_TRANSFERRED',     -- E20
    'LEGACY_CATALOG_INCORPORATION'      -- L01
  )),
  constraint chk_bae_source check (source in ('FICHARIO','ACERVO','COLECAO','CATALOGO','LEGADO')),
  constraint chk_bae_legacy check ((source = 'LEGADO') = (event_type = 'LEGACY_CATALOG_INCORPORATION')),
  constraint chk_bae_legacy_actor check (source <> 'LEGADO' or actor_user_id is null),
  constraint chk_bae_summary check (jsonb_typeof(summary) = 'object' and octet_length(summary::text) <= 2048),
  constraint chk_bae_names check (
    (collection_name is null or char_length(collection_name) <= 200)
    and (binder_name is null or char_length(binder_name) <= 200)),
  constraint chk_bae_collection_name check (collection_name is null or collection_id is not null)
);

create index ix_bae_owner_layout_time
  on public.binder_activity_event (owner_user_id, layout_key, occurred_at desc, id desc);

comment on table public.binder_activity_event is
  'Histórico do Fichário (P3-B, 5267): um evento por operação lógica concluída (C-205). Titular gravado no evento e nunca recalculado (C-204); layout_key sem FK para sobreviver à desmontagem (A1, C-202). Imutável; exclusão só pela 5270 (titular) ou pela exclusão da conta (C-203). Sem acesso de clientes.';
comment on column public.binder_activity_event.owner_user_id is
  'Titular: dono do fichário no instante do evento. Leitura sempre filtrada por ele (segregação por proprietário, C-207).';
comment on column public.binder_activity_event.layout_key is
  'Identificador do fichário guardado como valor (sem FK): o evento sobrevive à desmontagem e à remoção do fichário.';
comment on column public.binder_activity_event.actor_user_id is
  'Quem executou, guardado como valor (sem FK, B1): validado na gravação pela 5268 (auth.uid() = titular na V1) e nunca reescrito. NULL só no legado. Não exposto pelas leituras da S1.';
comment on column public.binder_activity_event.created_xact is
  'Transação que gravou o evento. Diagnóstico e provas de atomicidade do harness; não é exposto ao cliente.';

-- 2. Item ----------------------------------------------------------------------------------
create table public.binder_activity_item (
  event_id          bigint  not null
                    references public.binder_activity_event (id) on update restrict on delete cascade,
  ordinal           integer not null,
  item_kind         text    not null,
  effect            text    not null,
  card_id           uuid    null,
  card_name         text    null,
  collector_number  text    null,
  card_set_code     text    null,
  variant_type_code text    null,
  variant_type_name text    null,
  from_page         integer null,
  from_row          integer null,
  from_col          integer null,
  to_page           integer null,
  to_row            integer null,
  to_col            integer null,
  detail            jsonb   null,
  constraint pk_binder_activity_item primary key (event_id, ordinal),
  constraint chk_bai_ordinal check (ordinal >= 1),
  constraint chk_bai_kind check (item_kind in ('CARD','RESERVATION','POCKET','PAGE','COLLECTION','BINDER')),
  constraint chk_bai_effect check (effect in (
    'PLACED','MOVED','SWAPPED','REMOVED','LEFT','RESERVED','RELEASED','LOCKED','UNLOCKED',
    'SHIFTED','PAGE_ADDED','PAGE_REMOVED','PAGE_RENUMBERED','INCORPORATED','ATTACHED',
    'DETACHED','CLOSED','TRANSFERRED')),
  constraint chk_bai_card_snapshot check (card_id is null or card_name is not null),
  constraint chk_bai_from_position check (
    (from_page is null and from_row is null and from_col is null)
    or (from_page >= 1 and (from_row is null) = (from_col is null)
        and (from_row is null or (from_row >= 1 and from_col >= 1)))),
  constraint chk_bai_to_position check (
    (to_page is null and to_row is null and to_col is null)
    or (to_page >= 1 and (to_row is null) = (to_col is null)
        and (to_row is null or (to_row >= 1 and to_col >= 1)))),
  constraint chk_bai_detail check (detail is null or (jsonb_typeof(detail) = 'object' and octet_length(detail::text) <= 1024)),
  constraint chk_bai_text_sizes check (
    coalesce(char_length(card_name), 0) <= 200 and coalesce(char_length(collector_number), 0) <= 40
    and coalesce(char_length(card_set_code), 0) <= 40 and coalesce(char_length(variant_type_code), 0) <= 60
    and coalesce(char_length(variant_type_name), 0) <= 120)
);

comment on table public.binder_activity_item is
  'Itens do evento (P3-B, 5267): efeitos internos da operação lógica, com cópia da carta e das posições no momento do evento (R3). Imutável; só sai em cascata do evento.';

-- 3. Marco de cobertura --------------------------------------------------------------------
create table public.binder_activity_coverage (
  owner_user_id uuid        not null
                references auth.users (id) on update restrict on delete cascade,
  layout_key    uuid        not null,
  covered_from  timestamptz not null,
  reason        text        not null,
  updated_at    timestamptz not null default now(),
  constraint pk_binder_activity_coverage primary key (owner_user_id, layout_key),
  constraint chk_bac_reason check (reason in ('BINDER_ASSEMBLED','HISTORY_PURGED','OWNERSHIP_RECEIVED'))
);

comment on table public.binder_activity_coverage is
  'Marco mínimo de início de cobertura por (titular, fichário) (P3-B, 5267, C-203/C-207): só data e motivo. Após exclusão definitiva, é o único rastro e não contém conteúdo histórico recuperável. Sai com a conta.';

-- 4. Configuração (linha única) --------------------------------------------------------------
create table public.binder_activity_setting (
  id                 smallint    primary key default 1,
  full_coverage_from timestamptz null,
  updated_at         timestamptz not null default now(),
  constraint chk_bas_singleton check (id = 1)
);
insert into public.binder_activity_setting (id, full_coverage_from) values (1, null);

comment on table public.binder_activity_setting is
  'Data global de início da cobertura completa (O4): NULL até a última fatia S2–S6 ser comprovada; definida por migration própria de encerramento.';

-- 5. Imutabilidade ---------------------------------------------------------------------------
create function public.binder_activity_event_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' then
    raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
  elsif tg_op = 'DELETE' then
    if coalesce(current_setting('mmkyu.binder_activity_purge', true), '') = old.owner_user_id::text || ':' || old.layout_key::text then
      return old;  -- (a) exclusão definitiva pela 5270
    end if;
    if not exists (select 1 from auth.users u where u.id = old.owner_user_id) then
      return old;  -- (b) exclusão da conta do titular (cascata)
    end if;
    raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
  elsif tg_op = 'TRUNCATE' then
    raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
  end if;
  return null;
end;
$fn$;

create function public.binder_activity_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if not exists (select 1 from public.binder_activity_event e where e.id = old.event_id) then
      return old;  -- cascata do evento (exclusão definitiva ou da conta)
    end if;
  end if;
  raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
end;
$fn$;

create trigger trg_bae_immutable
  before update or delete on public.binder_activity_event
  for each row execute function public.binder_activity_event_guard();
create trigger trg_bae_no_truncate
  before truncate on public.binder_activity_event
  for each statement execute function public.binder_activity_event_guard();
create trigger trg_bai_immutable
  before update or delete on public.binder_activity_item
  for each row execute function public.binder_activity_item_guard();
create trigger trg_bai_no_truncate
  before truncate on public.binder_activity_item
  for each statement execute function public.binder_activity_item_guard();

revoke all on function public.binder_activity_event_guard() from public, anon, authenticated, service_role;
revoke all on function public.binder_activity_item_guard() from public, anon, authenticated, service_role;

-- 6. Privilégios -----------------------------------------------------------------------------
alter table public.binder_activity_event    enable row level security;
alter table public.binder_activity_item     enable row level security;
alter table public.binder_activity_coverage enable row level security;
alter table public.binder_activity_setting  enable row level security;

revoke all on table public.binder_activity_event    from public, anon, authenticated, service_role;
revoke all on table public.binder_activity_item     from public, anon, authenticated, service_role;
revoke all on table public.binder_activity_coverage from public, anon, authenticated, service_role;
revoke all on table public.binder_activity_setting  from public, anon, authenticated, service_role;

-- W8: sequência da identidade sem privilégio de cliente, explicitamente. Hoje os
-- privilégios padrão de sequências do dono postgres no schema public não concedem
-- nada a anon/authenticated/service_role (leitura LIVE de 2026-10-25), mas a S1 não
-- depende disso: o REVOKE vale qualquer que seja o papel executor ou seus padrões.
do $seq$
declare
  v_seq text := pg_get_serial_sequence('public.binder_activity_event', 'id');
begin
  if v_seq is null or v_seq <> 'public.binder_activity_event_id_seq' then
    raise exception 'PRECHECK 5267: sequência da identidade inesperada (%)', coalesce(v_seq, 'NULL');
  end if;
end;
$seq$;
revoke all on sequence public.binder_activity_event_id_seq from public, anon, authenticated, service_role;

-- ===== 5268_create_binder_activity_recording_functions.sql (sha256 76e2bac4de3dffed) — sem `begin;`/`commit;` próprios =====
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5268 - P3-B S1 · Histórico do Fichário — gravação interna
              binder_activity_begin(uuid, text, text, uuid, jsonb)
              binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)
              binder_activity_end()
Versão......: 1.2 (2026-10-25, P3-B-S1-LIVE-DRYRUN-STRUCTURAL-CORRECTION-02: W1 —
              folga de repetição de deslocamento e recálculo em PAGE_ADDED)
              1.1 (P3-B-S1-SECURITY-CORRECTION-01: W1 teto por capacidade)
Status......: PROPOSTA — NÃO EXECUTADA. G8 (autorização LIVE) FECHADO.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: C-205 (operação lógica), C-206 (atomicidade/idempotência);
              LDM-199–LDM-201; README v1.2 §7.2, §8.

Funções INTERNAS: SECURITY DEFINER, search_path vazio, EXECUTE revogado de
PUBLIC/anon/authenticated/service_role. Na S1 nenhuma função homologada as
chama — elas só passam a ser usadas nas fatias S2–S6, que recriam as funções
instrumentadas com diff mínimo (begin no início do caminho de sucesso,
add_item para cada efeito, end antes de cada RETURN).

Contrato de contexto (uma operação lógica por chamada do cliente, C-205):
  · Contexto guardado na configuração local da transação
    mmkyu.binder_activity_ctx (json). set_config(..., true): some no fim da
    transação e é desfeito com a subtransação que falhar.
  · begin em profundidade 0 abre a operação (parâmetros pendentes, sem linha
    gravada). begin com operação aberta só aumenta a profundidade: a função
    interna (ex.: add_layout_page chamada por insert_my_binder_gap) acrescenta
    ITENS ao evento externo e nunca cria evento próprio — sem duplicidade.
    Fichário diferente do da operação aberta → erro (nunca mistura).
  · add_item cria o cabeçalho do evento no PRIMEIRO item (gravação preguiçosa):
    operação sem efeito (repetição idempotente, lista vazia, UNCHANGED) não
    grava nada (C-206).
  · end diminui a profundidade; em 0 limpa o contexto, de modo que duas
    operações na mesma transação geram dois eventos.
  · Titular = dono do fichário no momento do primeiro item; precisa ser o
    usuário autenticado (V1: ator = titular). Sem sessão → erro.
  · Posições: add_item recebe os bolsos (slot) e os converte JÁ em página,
    linha e coluna (cópia, R3). Deve ser chamado antes de apagar ou
    renumerar o bolso/página de origem e depois de gravar o destino.
  · Carta: cópia de nome, número, código do Set e acabamento no momento.
  · Limite de itens DERIVADO DA CAPACIDADE do fichário (W1, v1.1), nunca
    um número fixo. Fundamento: cada item descreve um efeito distinto sobre
    um objeto distinto do fichário (contrato W3, regra I-7: nenhum objeto
    repete o mesmo efeito numa operação). Por bolso há no máximo 4 objetos
    capazes de gerar item — carta, reserva, trava e imagem do bolso — e cada
    um pode, numa mesma operação, sair (o ocupante anterior) e entrar (o
    novo): no máximo 8 itens por bolso. Por página, no máximo 2 efeitos
    (criada/removida e renumerada); por operação, no máximo 8 itens de
    coleção/fichário. Parcela de capacidade:
        páginas × (8 × linhas × colunas + 2) + 8
    (a grade é imutável, 5107; bolsos = páginas × linhas × colunas; 1 objeto
    de cada tipo por bolso: UNIQUE(slot_id) em assignment, expected_content e
    slot_image; locked é coluna do bolso — leitura LIVE 2026-10-25).
    Folga de repetição (v1.2): a reconciliação do Catálogo (E16) desloca o
    mesmo objeto várias vezes numa operação (uma vez por novidade); a
    própria 5264 limita a soma de linhas movidas a 500 e as novidades a
    100. A instrumentação aninhada gera um item por deslocamento (R5), o que
    pode exceder a parcela de capacidade num fichário pequeno. Por isso
        teto = parcela de capacidade + c_repeat_slack (600 = 500 + 100)
    e o static_check (S.14) exige c_repeat_slack ≥ c_row_limit + c_item_limit
    da 5264 e ≥ c_row_limit da 5243. Exemplo: o maior fichário do LIVE
    (1.056 bolsos) admite ≥ 9.048 itens; um 2×2 de 2 páginas, 676.
    O teto é calculado no primeiro item e guardado no contexto; é
    RECALCULADO (v1.2) em todo item PAGE/PAGE_ADDED — gravado depois de criar
    a página (I-10), então já inclui seus bolsos — e sempre que excedido. Só
    cresce (máximo observado — nunca diminui quando páginas/bolsos são
    apagados depois de registrados). Só então, se ainda excedido, erro explícito
    BINDER_ACTIVITY_ITEM_LIMIT: indica defeito de instrumentação (efeito
    duplicado ou laço), nunca uma operação legítima; nunca truncamento
    silencioso. Proteção contra crescimento excessivo: o histórico de uma
    operação fica linear no tamanho do fichário, que já é limitado pelos
    caps das próprias operações (500 por chamada, 10.000 alocações e 20.000
    bolsos na montagem, 100 novidades por reconciliação).

Dependências: 5267; collection_layout, collection, collection_layout_page,
collection_layout_slot, card, card_set, card_variant_type.
================================================================
*/

do $pre$
begin
  if to_regclass('public.binder_activity_event') is null then
    raise exception 'PRECHECK 5268: aplique a 5267 antes';
  end if;
  if to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is not null
     or to_regprocedure('public.binder_activity_end()') is not null then
    raise exception 'PRECHECK 5268: funções de gravação já existem';
  end if;
end;
$pre$;

-- begin ----------------------------------------------------------------------------------
create function public.binder_activity_begin(
  p_layout_id     uuid,
  p_event_type    text,
  p_source        text,
  p_collection_id uuid  default null,
  p_summary       jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
begin
  if p_layout_id is null or p_event_type is null or p_source is null then
    raise exception 'binder activity: layout, type and source are required' using errcode = '22004';
  end if;
  if v_ctx is not null and (v_ctx ->> 'depth')::integer > 0 then
    if (v_ctx ->> 'layout')::uuid <> p_layout_id then
      raise exception 'binder activity: nested operation on another binder' using errcode = 'P0001',
        hint = 'BINDER_ACTIVITY_NESTED_LAYOUT';
    end if;
    v_ctx := jsonb_set(v_ctx, '{depth}', to_jsonb((v_ctx ->> 'depth')::integer + 1));
  else
    v_ctx := jsonb_build_object(
      'depth', 1, 'layout', p_layout_id, 'type', p_event_type, 'source', p_source,
      'collection', p_collection_id, 'summary', coalesce(p_summary, '{}'::jsonb),
      'event_id', null, 'n', 0, 'cap', 0);
  end if;
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

-- add_item -------------------------------------------------------------------------------
create function public.binder_activity_add_item(
  p_kind            text,
  p_effect          text,
  p_card_id         uuid    default null,
  p_variant_type_id uuid    default null,
  p_from_slot_id    uuid    default null,
  p_to_slot_id      uuid    default null,
  p_from_page       integer default null,
  p_to_page         integer default null,
  p_detail          jsonb   default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx      jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_uid      uuid  := (select auth.uid());
  v_layout   uuid;
  v_event    bigint;
  v_n        integer;
  v_cap      bigint;
  v_cap_now  bigint;
  c_repeat_slack constant integer := 600;   -- ≥ 5264 c_row_limit (500) + c_item_limit (100); ≥ 5243 c_row_limit (500)
  v_owner    uuid;
  v_binder   text;
  v_coll     uuid;
  v_collname text;
  f_page int; f_row int; f_col int;
  t_page int; t_row int; t_col int;
  c_name text; c_num text; c_set text; vt_code text; vt_name text;
begin
  if v_ctx is null or (v_ctx ->> 'depth')::integer < 1 then
    raise exception 'binder activity: no open operation' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_NO_CONTEXT';
  end if;
  if v_uid is null then
    raise exception 'binder activity requires an authenticated actor' using errcode = '28000';
  end if;
  v_layout := (v_ctx ->> 'layout')::uuid;
  v_event  := (v_ctx ->> 'event_id')::bigint;
  v_n      := (v_ctx ->> 'n')::integer + 1;
  v_cap    := coalesce((v_ctx ->> 'cap')::bigint, 0);

  -- W1: teto derivado da capacidade + folga de repetição (ver cabeçalho). Calculado no
  -- primeiro item (cap = 0), em todo PAGE_ADDED e quando excedido; guarda o máximo observado.
  if v_n > v_cap or (p_kind = 'PAGE' and p_effect = 'PAGE_ADDED') then
    select count(p.id) * (8::bigint * l.grid_rows * l.grid_columns + 2) + 8 + c_repeat_slack
      into v_cap_now
    from public.collection_layout l
    left join public.collection_layout_page p on p.layout_id = l.id
    where l.id = v_layout
    group by l.grid_rows, l.grid_columns;
    v_cap := greatest(v_cap, coalesce(v_cap_now, 8 + c_repeat_slack));
    if v_n > v_cap then
      raise exception 'binder activity: item limit exceeded (% > %)', v_n, v_cap using errcode = 'P0001',
        hint = 'BINDER_ACTIVITY_ITEM_LIMIT';
    end if;
    v_ctx := jsonb_set(v_ctx, '{cap}', to_jsonb(v_cap));
  end if;

  if v_event is null then
    -- Cabeçalho no primeiro item: titular e nomes copiados agora.
    select c.owner_user_id, coalesce(nullif(l.display_name, ''), c.name)
      into v_owner, v_binder
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    where l.id = v_layout;
    if v_owner is null then
      raise exception 'binder activity: binder not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_LAYOUT_NOT_FOUND';
    end if;
    if v_owner <> v_uid then
      raise exception 'binder activity: actor is not the binder owner' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_NOT_OWNER';
    end if;
    v_coll := nullif(v_ctx ->> 'collection', '')::uuid;
    if v_coll is not null then
      select c.name into v_collname from public.collection c where c.id = v_coll and c.owner_user_id = v_owner;
    end if;
    insert into public.binder_activity_event
      (owner_user_id, layout_key, actor_user_id, event_type, source,
       collection_id, collection_name, binder_name, summary)
    values
      (v_owner, v_layout, v_uid, v_ctx ->> 'type', v_ctx ->> 'source',
       case when v_collname is not null then v_coll end, left(v_collname, 200), left(v_binder, 200),
       coalesce(v_ctx -> 'summary', '{}'::jsonb))
    returning id into v_event;
    v_ctx := jsonb_set(v_ctx, '{event_id}', to_jsonb(v_event));
  end if;

  -- Posições copiadas agora (R3); bolso de outro fichário → erro.
  if p_from_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into f_page, f_row, f_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_from_slot_id and p.layout_id = v_layout;
    if f_page is null then
      raise exception 'binder activity: origin pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    f_page := p_from_page;
  end if;
  if p_to_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into t_page, t_row, t_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_to_slot_id and p.layout_id = v_layout;
    if t_page is null then
      raise exception 'binder activity: target pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    t_page := p_to_page;
  end if;

  -- Cópia da carta e do acabamento.
  if p_card_id is not null then
    select k.name, k.collector_number, cs.code into c_name, c_num, c_set
    from public.card k join public.card_set cs on cs.id = k.card_set_id
    where k.id = p_card_id;
    if c_name is null then
      raise exception 'binder activity: card not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_CARD';
    end if;
  end if;
  if p_variant_type_id is not null then
    select t.code, t.name into vt_code, vt_name from public.card_variant_type t where t.id = p_variant_type_id;
  end if;

  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     variant_type_code, variant_type_name, from_page, from_row, from_col, to_page, to_row, to_col, detail)
  values
    (v_event, v_n, p_kind, p_effect, p_card_id, left(c_name, 200), left(c_num, 40), left(c_set, 40),
     left(vt_code, 60), left(vt_name, 120), f_page, f_row, f_col, t_page, t_row, t_col, p_detail);

  v_ctx := jsonb_set(v_ctx, '{n}', to_jsonb(v_n));
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

-- end ------------------------------------------------------------------------------------
create function public.binder_activity_end()
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_depth integer;
begin
  if v_ctx is null or (v_ctx ->> 'depth')::integer < 1 then
    raise exception 'binder activity: no open operation' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_NO_CONTEXT';
  end if;
  v_depth := (v_ctx ->> 'depth')::integer - 1;
  if v_depth = 0 then
    perform set_config('mmkyu.binder_activity_ctx', '', true);
  else
    perform set_config('mmkyu.binder_activity_ctx', jsonb_set(v_ctx, '{depth}', to_jsonb(v_depth))::text, true);
  end if;
end;
$fn$;

revoke all on function public.binder_activity_begin(uuid, text, text, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.binder_activity_end() from public, anon, authenticated, service_role;

comment on function public.binder_activity_begin(uuid, text, text, uuid, jsonb) is
  'P3-B 5268 (interna): abre a operação lógica ou entra numa já aberta (C-205). Sem gravação até o primeiro item.';
comment on function public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb) is
  'P3-B 5268 (interna): acrescenta um efeito à operação aberta; cria o cabeçalho no primeiro item; copia carta e posições no momento (R3).';
comment on function public.binder_activity_end() is
  'P3-B 5268 (interna): fecha um nível da operação; em profundidade 0 limpa o contexto.';

-- ===== 5269_create_binder_activity_reads.sql (sha256 98d83f701c9d3b1d) — sem `begin;`/`commit;` próprios =====
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5269 - P3-B S1 · Histórico do Fichário — leituras
              binder_activity_category(text)                       — interna
              get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)
              get_my_binder_activity_coverage(uuid)
              list_my_closed_binder_histories(integer)
Versão......: 1.0 (2026-10-25, P3-B-S1-FOUNDATION-READINESS-01)
Status......: PROPOSTA — NÃO EXECUTADA. G8 (autorização LIVE) FECHADO.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: C-204 (titularidade e acesso), C-208 (fichários encerrados);
              LDM-198, LDM-202; README v1.2 §3.1, §6.2, §9.

Autorização (deny by default): toda leitura filtra owner_user_id = auth.uid().
Fichário de outro usuário, chave inexistente ou sem sessão → zero linhas,
indistinguíveis (não enumera). Nada depende do fichário existir: o histórico
de um fichário desmontado ou transferido para fora continua legível pelo
titular dos eventos, e só por ele.

Ordenação e paginação: (occurred_at desc, id desc), cursor composto
(p_before_occurred_at, p_before_id) — ambos ou nenhum. Limite 1–50 (padrão
20). Itens: até 50 por evento, por ordinal, com item_count e items_truncated.

Categorias (filtros da interface, README §3.3):
  CARDS · RESERVATIONS · LOCKS · PAGES · CATALOG · BINDER.

Nota C-172: o predicado "pode ler estes eventos" está isolado nesta função;
quando a associação de membros existir, ele é ampliado aqui, sem mudar
tabelas nem eventos.
================================================================
*/

do $pre$
begin
  if to_regclass('public.binder_activity_event') is null then
    raise exception 'PRECHECK 5269: aplique a 5267 antes';
  end if;
  if to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)') is not null then
    raise exception 'PRECHECK 5269: leituras já existem';
  end if;
end;
$pre$;

create function public.binder_activity_category(p_event_type text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case
    when p_event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                          'CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT') then 'CARDS'
    when p_event_type in ('POCKET_RESERVED','RESERVATIONS_RELEASED') then 'RESERVATIONS'
    when p_event_type in ('POCKETS_LOCKED','POCKETS_UNLOCKED') then 'LOCKS'
    when p_event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED') then 'PAGES'
    when p_event_type in ('CATALOG_NOVELTIES_INCORPORATED','LEGACY_CATALOG_INCORPORATION') then 'CATALOG'
    when p_event_type in ('BINDER_ASSEMBLED','COLLECTION_ATTACHED','COLLECTION_DETACHED',
                          'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED') then 'BINDER'
  end
$fn$;

create function public.get_my_binder_activity(
  p_layout_key         uuid,
  p_categories         text[]      default null,
  p_before_occurred_at timestamptz default null,
  p_before_id          bigint      default null,
  p_limit              integer     default 20
)
returns table (
  event_id        bigint,
  occurred_at     timestamptz,
  event_type      text,
  category        text,
  source          text,
  is_legacy       boolean,
  collection_id   uuid,
  collection_name text,
  binder_name     text,
  summary         jsonb,
  item_count      integer,
  items           jsonb,
  items_truncated boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid    := (select auth.uid());
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if v_uid is null or p_layout_key is null then
    return;
  end if;
  if (p_before_occurred_at is null) <> (p_before_id is null) then
    raise exception 'cursor must have occurred_at and id together' using errcode = '22023', hint = 'BINDER_ACTIVITY_CURSOR';
  end if;
  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER']) then
    raise exception 'unknown category' using errcode = '22023', hint = 'BINDER_ACTIVITY_CATEGORY';
  end if;

  return query
  with page as (
    select e.*
    from public.binder_activity_event e
    where e.owner_user_id = v_uid
      and e.layout_key = p_layout_key
      and (p_categories is null or public.binder_activity_category(e.event_type) = any (p_categories))
      and (p_before_id is null or (e.occurred_at, e.id) < (p_before_occurred_at, p_before_id))
    order by e.occurred_at desc, e.id desc
    limit v_limit
  )
  select pg.id, pg.occurred_at, pg.event_type, public.binder_activity_category(pg.event_type), pg.source,
         pg.source = 'LEGADO',
         pg.collection_id,
         coalesce(pg.collection_name,
                  (select c.name from public.collection c where c.id = pg.collection_id and c.owner_user_id = v_uid)),
         pg.binder_name, pg.summary,
         ic.n::integer,
         coalesce(it.items, '[]'::jsonb),
         ic.n > 50
  from page pg
  cross join lateral (select count(*) as n from public.binder_activity_item i where i.event_id = pg.id) ic
  cross join lateral (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'ordinal', i.ordinal, 'kind', i.item_kind, 'effect', i.effect,
             'card_id', i.card_id, 'card_name', i.card_name, 'collector_number', i.collector_number,
             'card_set_code', i.card_set_code, 'variant_type_code', i.variant_type_code,
             'variant_type_name', i.variant_type_name,
             'from_page', i.from_page, 'from_row', i.from_row, 'from_col', i.from_col,
             'to_page', i.to_page, 'to_row', i.to_row, 'to_col', i.to_col, 'detail', i.detail))
           order by i.ordinal) as items
    from (select * from public.binder_activity_item i0 where i0.event_id = pg.id order by i0.ordinal limit 50) i
  ) it
  order by pg.occurred_at desc, pg.id desc;
end;
$fn$;

create function public.get_my_binder_activity_coverage(p_layout_key uuid)
returns table (
  full_coverage_from timestamptz,
  covered_from       timestamptz,
  coverage_reason    text,
  has_legacy         boolean,
  binder_is_mine     boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or p_layout_key is null then
    return;
  end if;
  return query
  select s.full_coverage_from,
         greatest(s.full_coverage_from, cv.covered_from),
         cv.reason,
         exists (select 1 from public.binder_activity_event e
                 where e.owner_user_id = v_uid and e.layout_key = p_layout_key and e.source = 'LEGADO'),
         exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
                 where l.id = p_layout_key and c.owner_user_id = v_uid)
  from public.binder_activity_setting s
  left join public.binder_activity_coverage cv
         on cv.owner_user_id = v_uid and cv.layout_key = p_layout_key
  where s.id = 1
    and (exists (select 1 from public.binder_activity_event e where e.owner_user_id = v_uid and e.layout_key = p_layout_key)
         or cv.owner_user_id is not null
         or exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
                    where l.id = p_layout_key and c.owner_user_id = v_uid));
end;
$fn$;

create function public.list_my_closed_binder_histories(p_limit integer default 50)
returns table (
  layout_key    uuid,
  binder_name   text,
  last_event_at timestamptz,
  event_count   bigint,
  closed        boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return;
  end if;
  return query
  select e.layout_key,
         (array_agg(e.binder_name order by e.occurred_at desc, e.id desc)
            filter (where e.binder_name is not null))[1],
         max(e.occurred_at),
         count(*),
         bool_or(e.event_type in ('BINDER_DISMANTLED','BINDER_DELETED_EMPTY'))
  from public.binder_activity_event e
  where e.owner_user_id = v_uid
    and not exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
                    where l.id = e.layout_key and c.owner_user_id = v_uid)
  group by e.layout_key
  order by max(e.occurred_at) desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$fn$;

revoke all on function public.binder_activity_category(text) from public, anon, authenticated, service_role;
revoke all on function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer) from public, anon;
revoke all on function public.get_my_binder_activity_coverage(uuid) from public, anon;
revoke all on function public.list_my_closed_binder_histories(integer) from public, anon;
grant execute on function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer) to authenticated;
grant execute on function public.get_my_binder_activity_coverage(uuid) to authenticated;
grant execute on function public.list_my_closed_binder_histories(integer) to authenticated;

comment on function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer) is
  'P3-B 5269: eventos do fichário do titular (auth.uid()), do mais recente ao mais antigo, cursor (occurred_at, id), até 50 por página e 50 itens por evento. Outro usuário/chave inexistente/sem sessão → zero linhas.';
comment on function public.get_my_binder_activity_coverage(uuid) is
  'P3-B 5269: início da cobertura completa (global), marco do titular (exclusão definitiva/recebimento/montagem), presença de legado e se o fichário ainda é do titular.';
comment on function public.list_my_closed_binder_histories(integer) is
  'P3-B 5269 (C-208): fichários com histórico do titular que não existem mais ou já não são dele (desmontados, removidos ou transferidos para fora). Interface pós-MVP.';

-- ===== 5270_create_binder_activity_purge_and_legacy.sql (sha256 53dc5fd526315b56) — sem `begin;`/`commit;` próprios =====
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5270 - P3-B S1 · Histórico do Fichário — exclusão definitiva
              e registro legado
              purge_my_binder_activity(uuid, uuid)   — SEM permissão para clientes (O2)
              importação única do legado L01 (Chi-Yu)
Versão......: 1.0 (2026-10-25, P3-B-S1-FOUNDATION-READINESS-01)
Status......: PROPOSTA — NÃO EXECUTADA. G8 (autorização LIVE) FECHADO.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: C-203 (exclusão definitiva como exceção controlada),
              C-209 (legado parcial); LDM-201, LDM-203; README v1.2 §6.3, §6.4.

A. Exclusão definitiva (A3) — estrutura pronta, interface pós-MVP:
  · Só o titular (auth.uid()), só os SEUS eventos de UM fichário.
  · Confirmação explícita: p_confirm deve repetir a chave do fichário.
  · Marca a transação com mmkyu.binder_activity_purge = '<titular>:<chave>'
    — a única porta que o gatilho de imutabilidade (5267) abre para DELETE
    de evento; itens saem em cascata.
  · Grava/atualiza o marco mínimo (binder_activity_coverage):
    covered_from = agora, reason = HISTORY_PURGED. Nada mais: o marco não
    guarda contagem, tipos, cartas, posições nem datas dos eventos apagados
    (nenhum conteúdo histórico recuperável).
  · Não grava evento (registrar o apagamento contradiria a exclusão).
  · Obrigação de retenção (P2): ponto de extensão documentado — nenhuma
    identificada hoje; se existir, a verificação entra aqui antes do DELETE.
  · EXECUTE revogado de authenticated nesta fatia: a liberação acontece com
    a interface, por migration própria.
  · Diferença para exclusão de conta (A5): a conta apaga eventos E marcos
    do titular pela cascata das FKs (5267), sem esta função e sem marco
    remanescente.

B. Legado L01 (D4) — importação única e idempotente:
  · Fonte: collection_layout_catalog_incorporation (linhas reais).
  · Cada linha vira um evento LEGACY_CATALOG_INCORPORATION com:
      titular = dono da coleção da linha (mesmo dono do fichário; 5229/5255),
      occurred_at = incorporated_at (data real), actor = NULL,
      source = LEGADO, collection_id da linha, collection_name = NULL,
      binder_name = NULL, summary = {"item_key": <chave>}.
    Item único CARD/INCORPORATED com a cópia do catálogo (nome, número, Set,
    acabamento quando a chave o tiver; '*' = qualquer acabamento → NULL).
    Sem posição, sem ator, sem quantidade, sem efeito no bolso: atributos
    ausentes não são inventados.
  · Idempotência: não importa se já existe evento legado com a mesma chave
    para o mesmo fichário, coleção e titular.
  · LIVE (leitura de 2026-10-25): 1 linha esperada (Chi-Yu · 059 · Holo Reversa).

Dependências: 5267; collection_layout_catalog_incorporation (5263).
================================================================
*/

do $pre$
begin
  if to_regclass('public.binder_activity_event') is null or to_regclass('public.binder_activity_coverage') is null then
    raise exception 'PRECHECK 5270: aplique a 5267 antes';
  end if;
  if to_regclass('public.collection_layout_catalog_incorporation') is null then
    raise exception 'PRECHECK 5270: 5263 ausente';
  end if;
  if to_regprocedure('public.purge_my_binder_activity(uuid, uuid)') is not null then
    raise exception 'PRECHECK 5270: função de exclusão já existe';
  end if;
end;
$pre$;

-- A. Exclusão definitiva ---------------------------------------------------------------------
create function public.purge_my_binder_activity(p_layout_key uuid, p_confirm uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_n   integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_layout_key is null or p_confirm is distinct from p_layout_key then
    raise exception 'confirmation does not match the binder' using errcode = '22023', hint = 'BINDER_ACTIVITY_PURGE_CONFIRM';
  end if;
  -- P2 (retenção legal/contratual): verificação entra aqui quando existir.

  perform set_config('mmkyu.binder_activity_purge', v_uid::text || ':' || p_layout_key::text, true);
  delete from public.binder_activity_event e
  where e.owner_user_id = v_uid and e.layout_key = p_layout_key;
  get diagnostics v_n = row_count;
  perform set_config('mmkyu.binder_activity_purge', '', true);

  insert into public.binder_activity_coverage as cv (owner_user_id, layout_key, covered_from, reason, updated_at)
  values (v_uid, p_layout_key, now(), 'HISTORY_PURGED', now())
  on conflict (owner_user_id, layout_key)
  do update set covered_from = excluded.covered_from, reason = excluded.reason, updated_at = excluded.updated_at;

  return v_n;
end;
$fn$;

revoke all on function public.purge_my_binder_activity(uuid, uuid) from public, anon, authenticated, service_role;

comment on function public.purge_my_binder_activity(uuid, uuid) is
  'P3-B 5270 (C-203): exclusão definitiva do histórico de um fichário pelo titular; deixa só o marco HISTORY_PURGED (data). Sem permissão para clientes até a interface (O2).';

-- B. Legado L01 --------------------------------------------------------------------------------
do $legacy$
declare
  r record;
  v_owner uuid;
  v_card uuid;
  v_vt uuid;
  v_event bigint;
  c_name text; c_num text; c_set text; vt_code text; vt_name text;
begin
  for r in
    select ci.layout_id, ci.collection_id, ci.item_key, ci.incorporated_at
    from public.collection_layout_catalog_incorporation ci
    order by ci.incorporated_at, ci.item_key
  loop
    select c.owner_user_id into v_owner from public.collection c where c.id = r.collection_id;
    if v_owner is null then
      raise exception 'LEGACY 5270: coleção sem dono para a chave %', r.item_key;
    end if;
    if exists (select 1 from public.binder_activity_event e
               where e.source = 'LEGADO' and e.owner_user_id = v_owner and e.layout_key = r.layout_id
                 and e.collection_id = r.collection_id and e.summary ->> 'item_key' = r.item_key) then
      continue;
    end if;

    v_card := split_part(r.item_key, ':', 1)::uuid;
    v_vt   := nullif(split_part(r.item_key, ':', 2), '*')::uuid;
    select k.name, k.collector_number, cs.code into c_name, c_num, c_set
    from public.card k join public.card_set cs on cs.id = k.card_set_id where k.id = v_card;
    if c_name is null then
      raise exception 'LEGACY 5270: carta da chave % não encontrada', r.item_key;
    end if;
    vt_code := null; vt_name := null;
    if v_vt is not null then
      select t.code, t.name into vt_code, vt_name from public.card_variant_type t where t.id = v_vt;
    end if;

    insert into public.binder_activity_event
      (owner_user_id, layout_key, occurred_at, actor_user_id, event_type, source,
       collection_id, collection_name, binder_name, summary)
    values
      (v_owner, r.layout_id, r.incorporated_at, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO',
       r.collection_id, null, null, jsonb_build_object('item_key', r.item_key))
    returning id into v_event;

    insert into public.binder_activity_item
      (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
       variant_type_code, variant_type_name)
    values
      (v_event, 1, 'CARD', 'INCORPORATED', v_card, left(c_name, 200), left(c_num, 40), left(c_set, 40),
       left(vt_code, 60), left(vt_name, 120));
  end loop;
end;
$legacy$;

-- T8a postcheck (LIVE_90 sem 90.1, que depende do ledger)
do $dry_post$
declare
  v_eval jsonb;
  v_fns  text[] := array['binder_activity_begin', 'binder_activity_add_item', 'binder_activity_end', 'binder_activity_category', 'get_my_binder_activity', 'get_my_binder_activity_coverage', 'list_my_closed_binder_histories', 'purge_my_binder_activity', 'binder_activity_event_guard', 'binder_activity_item_guard'];  -- lista canônica do LIVE_90 (CTE fns), gerada pelo builder
begin
  v_eval := jsonb_build_object(
    '90.2', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname in ('binder_activity_event','binder_activity_item',
                   'binder_activity_coverage','binder_activity_setting') and c.relrowsecurity) = 4
            and not exists (select 1 from unnest(array['public.binder_activity_event','public.binder_activity_item',
                                    'public.binder_activity_coverage','public.binder_activity_setting']) t(tbl),
                                  unnest(array['anon','authenticated','service_role']) r(rol),
                                  unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) pv(priv)
                            where has_table_privilege(r.rol, t.tbl, pv.priv)),
    '90.3', (select count(*) = cardinality(v_fns) and bool_and(p.proconfig @> array['search_path=""']
                                    and p.prosecdef = (p.proname <> 'binder_activity_category'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = any(v_fns)),
    '90.4', (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                             = (p.proname in ('get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories'))
                             and not has_function_privilege('anon', p.oid, 'EXECUTE'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = any(v_fns)),
    '90.5', (select count(*) from pg_trigger t where not t.tgisinternal
               and t.tgname in ('trg_bae_immutable','trg_bae_no_truncate','trg_bai_immutable','trg_bai_no_truncate')) = 4,
    '90.6', (select count(*) from public.binder_activity_event where source = 'LEGADO') = 1
            and not exists (select 1 from public.binder_activity_event where source = 'LEGADO' and actor_user_id is not null)
            and (select count(*) from public.binder_activity_item) = 1,
    '90.7', not exists (select 1 from public.binder_activity_item where from_page is not null or to_page is not null),
    '90.8', not exists (select 1 from public.binder_activity_event where source <> 'LEGADO'),
    '90.9', (select full_coverage_from is null from public.binder_activity_setting where id = 1),
    '90.10', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public' and not (p.proname = any(v_fns))
                           and pg_get_functiondef(p.oid) ~* 'binder_activity_'),
    '90.11', not exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol),
                                       unnest(array['USAGE','SELECT','UPDATE']) pv(priv)
                         where has_sequence_privilege(r.rol, 'public.binder_activity_event_id_seq', pv.priv)),
    '90.12', (select count(*) from pg_constraint k where k.conrelid = 'public.binder_activity_event'::regclass and k.contype = 'f') = 1
             and to_regclass('public.ix_bae_actor') is null);
  insert into pg_temp.mmkyu_dryrun_evidence select e.key, e.value from jsonb_each(v_eval) e;
end;
$dry_post$;

-- T8b sondas (nenhuma escrita bem-sucedida; cada tentativa em subtransação)
do $dry_probe$
declare
  v_ok   boolean;
  v_hint text;
  v_n    integer;
  v_e    bigint;
  v_key  uuid;
begin
  select id, layout_key into v_e, v_key from public.binder_activity_event where source = 'LEGADO' limit 1;

  -- anon: EXECUTE revogado → 42501
  v_ok := false;
  execute 'set local role anon';
  begin
    perform count(*) from public.get_my_binder_activity(v_key);
  exception when insufficient_privilege then v_ok := true;
  end;
  execute 'reset role';
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_anon_42501', to_jsonb(v_ok));

  -- authenticated sem sessão: auth.uid() NULL → zero linhas
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.get_my_binder_activity(v_key);
  execute 'reset role';
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_no_session_zero_rows', to_jsonb(v_n = 0));

  -- imutabilidade (como postgres, dono das tabelas; gatilhos ativos: session_replication_role = origin)
  v_hint := null;
  begin update public.binder_activity_event set source = 'ACERVO' where id = v_e;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_update_immutable', to_jsonb(v_hint = 'BINDER_ACTIVITY_IMMUTABLE'));
  v_hint := null;
  begin delete from public.binder_activity_event where id = v_e;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_delete_immutable', to_jsonb(v_hint = 'BINDER_ACTIVITY_IMMUTABLE'));
  v_hint := null;
  begin truncate public.binder_activity_item;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_truncate_immutable', to_jsonb(v_hint = 'BINDER_ACTIVITY_IMMUTABLE'));

  insert into pg_temp.mmkyu_dryrun_evidence values
    ('legacy_events', to_jsonb((select count(*) from public.binder_activity_event))),
    ('legacy_items', to_jsonb((select count(*) from public.binder_activity_item))),
    ('role_restored', to_jsonb(current_user = session_user));
end;
$dry_probe$;

-- T9 sentinela: o caminho normal SEMPRE termina em erro (nenhum COMMIT possível)
do $dry_end$
declare
  v_all jsonb;
begin
  select jsonb_object_agg(x.k, x.v) into v_all from pg_temp.mmkyu_dryrun_evidence x;
  v_all := v_all || jsonb_build_object('duration_ms',
         round(extract(epoch from (clock_timestamp() - now())) * 1000));
  v_all := jsonb_build_object('ok', not exists (
         select 1 from jsonb_each(v_all) e where jsonb_typeof(e.value) = 'boolean' and e.value = 'false'::jsonb)) || v_all;
  raise notice 'DRYRUN EVIDENCE %', v_all::text;
  if not (v_all ->> 'ok')::boolean then
    raise exception 'DRYRUN POSTCHECK FALHOU %', v_all::text using errcode = 'P0001';
  end if;
  raise exception 'MSDRYRUN %', v_all::text using errcode = 'P0001';
end;
$dry_end$;

-- T10 encerramento (alcançado só por executores que continuam após erro)
rollback;

-- T11 restaura a sessão (idem)
reset default_transaction_read_only;
