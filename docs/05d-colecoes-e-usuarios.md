# Modelo de Dados — Coleções e Usuários

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados — Coleções e Usuários |
| **Arquivo** | `docs/05d-colecoes-e-usuarios.md` |
| **Versão** | 1.0 |
| **Status** | Em elaboração |
| **Objetivo** | Modelo lógico e físico de Collection Item, Collection/Collection Entry, User Profile/Reserved Username e Administração de Usuários. |
| **Escopo** | Parte de `docs/05-modelo-de-dados.md` (índice) — resultado da divisão de 2026-08-06, motivada pelo tamanho do arquivo original (mais de 700 KB, acima do que ferramentas de leitura processam em uma chamada). |
| **Dependências** | `04-domain-model.md`, `standards/STD-001-database-standards.md`, `05-modelo-de-dados.md` |

Ver `docs/05-modelo-de-dados.md` para o mapa completo do domínio, a metodologia (Roteiro por Entidade) e o histórico de revisão consolidado até 2026-08-06 (revisões anteriores a esta divisão não foram redistribuídas retroativamente por entidade — ver nota na Revision History de lá).

---

# Collection Item (Item da Coleção)

*Documentação pendente.*

---

# Collection (Coleção) / Collection Entry (Entrada da Coleção)

*Documentação pendente.*

---

# User Profile (Perfil de Usuário) / Reserved Username

## Status

**Camada Identidade e Acesso criada, semeada e homologada nesta revisão — Incremento 1 ("Meu Perfil") do módulo, `1000`–`1040`/`1710`/`1800`–`1840` CONFIRMADOS EXECUTADOS.** Primeira entidade fora do Catálogo Editorial, motivada pela decisão de arquitetura frontend (ADR-019) e formalizada em ADR-020 (User Profile and Username Identity Model). Introduz o Modelo Modular de Numeração (STD-001, Seção 10): esta é a primeira entidade do milhar `1000–1999`.

## Decisão de Modelagem

`user_profile` separa identidade de negócio (nome, avatar, username) da autenticação (`auth.users`, gerida pelo Supabase Auth) — ver ADR-020. Relação 1:1 via `id` compartilhado. `username` é a identidade pública, única e estável do usuário (imutável pelo próprio usuário); `display_name` é livremente editável. `reserved_username` é uma tabela de apoio (não uma entidade de domínio), consultada apenas por functions `SECURITY DEFINER`, sem acesso direto via API.

## Modelo Físico — `user_profile` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
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
```

Regras de negócio: `username` minúsculo, 3–20 caracteres (letras, números, underscore), único, imutável após criado (garantido por trigger, não pela tabela em si); `display_name` sempre gravado já com `trim`; `avatar_path` guarda o caminho relativo dentro do bucket `avatars` (Query `1040`), não a URL pública completa (derivada em runtime); RLS habilitado. Confirmado executado por Fabrício (estrutura e colunas conferidas via `information_schema`). Arquivo em `database/schema/1000_create_user_profile_table.sql`.

## Query `1001` — Create User Profile Trigger (CONFIRMADO EXECUTADO)

Mantém `updated_at` atualizado, reaproveitando `public.set_updated_at()` — mesmo padrão de toda a base. Confirmado via `information_schema.triggers`. Arquivo em `database/schema/1001_create_user_profile_trigger.sql`.

## Query `1002` — Create User Profile Invariants Trigger (CONFIRMADO EXECUTADO)

Function `enforce_user_profile_invariants()` + trigger `BEFORE INSERT OR UPDATE`: normaliza `display_name` (`trim`) incondicionalmente e bloqueia qualquer alteração de `username` (`RAISE EXCEPTION`), sem válvula de exceção — imutabilidade total nesta fase, por decisão explícita de Fabrício. Uma futura correção administrativa será modelada apenas quando existir papel administrativo aprovado (ver ADR-020), sem reabrir este trigger. Confirmado via `information_schema.triggers` (três linhas: `enforce_invariants` em INSERT e UPDATE, `set_updated_at` em UPDATE). Arquivo em `database/schema/1002_create_user_profile_invariants_trigger.sql`.

## Query `1003` — Create User Profile RLS Policies (CONFIRMADO EXECUTADO)

`user_profile_select_own`/`user_profile_update_own`, ambas restritas a `auth.uid() = id`. Sem política de `INSERT`/`DELETE` — a única via de criação é o trigger da Query `1020` (roda como dono da function, ignora RLS). Confirmado via `pg_policies`. Arquivo em `database/schema/1003_create_user_profile_rls_policies.sql`.

## Modelo Físico — `reserved_username` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.reserved_username (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username   TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.reserved_username ENABLE ROW LEVEL SECURITY;
```

Tabela de apoio, não uma entidade de domínio — sem política de RLS para `anon`/`authenticated` (só as functions `SECURITY DEFINER` a leem). Confirmado executado. Arquivo em `database/schema/1010_create_reserved_username_table.sql`; trigger de `updated_at` em `1011` (mesmo padrão, confirmado via `information_schema.triggers`, arquivo `database/schema/1011_create_reserved_username_trigger.sql`).

## Query `1710` — Seed Reserved Username (v1.1, CONFIRMADA EXECUTADA)

Carga idempotente (`ON CONFLICT (username) DO NOTHING`) com 50 termos reservados (`admin`, `suporte`, `sistema`, `perfil`, `me`, `about`, entre outros) — nenhum usuário pode reivindicá-los como `username`. v1.0 tinha 48 termos; v1.1 acrescenta `me` (rotas futuras como `/me`, `/api/me`) e `about` (rota institucional comum), sugeridos por Fabrício após a execução original e já aplicados incrementalmente ao banco antes desta consolidação. Confirmado: `count(*) = 48` na execução original, lista conferida termo a termo contra a intenção. Arquivo em `database/seeds/1710_seed_reserved_username.sql`.

## Query `1020` — Create `handle_new_user()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, trigger `AFTER INSERT ON auth.users`: popula `user_profile` a partir de `raw_user_meta_data` (`username`/`display_name` enviados pelo formulário via `options.data` do `signUp()`), tratado como dado não confiável — normalizado e revalidado no próprio trigger (formato, reservados, presença). Qualquer falha cancela a transação inteira do `INSERT` em `auth.users`: a partir desta Query, nunca existe usuário sem perfil. `EXECUTE` revogado de `PUBLIC` — só o próprio trigger invoca. Confirmado: `prosecdef = true`, trigger correto em `auth.users`, `anon`/`authenticated` sem `EXECUTE`. Arquivo em `database/schema/1020_create_handle_new_user_function.sql`.

**Limitação de MVP documentada em ADR-020**: esta function assume que `username` sempre vem em `raw_user_meta_data`, o que só é verdade no cadastro por e-mail/senha controlado pelo próprio formulário. Login social (OAuth) não popula esse campo — precisará de um fluxo de onboarding pós-login, não implementado nesta fase.

**Achado real desta revisão**: a conta de teste de Fabrício (criada antes desta Query existir) ficou sem `user_profile` — detectado pela checagem de inconsistência da Query `1800`. Decisão tomada: excluir a conta de teste via painel do Supabase (Authentication → Users) e recriá-la pelo fluxo real assim que o frontend estiver pronto, em vez de criar um perfil manualmente ou deixar a conta órfã.

## Query `1030` — Create `username_available()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, retorno estritamente `BOOLEAN`, chamável por `anon`/`authenticated` (checagem de disponibilidade durante o cadastro, antes de existir sessão). Documentada explicitamente como antecipação de UX sujeita a condição de corrida — a autoridade final continua sendo o `UNIQUE` de `user_profile`, verificado no `INSERT` real da Query `1020`. Testado com três casos reais: `'admin'` → `false` (reservado), `'ab'` → `false` (formato inválido), `'fabricio_teste'` → `true` (disponível). Arquivo em `database/schema/1030_create_username_available_function.sql`.

## Query `1040` — Create bucket `avatars` (CONFIRMADO EXECUTADO)

Bucket Supabase Storage dedicado a avatares: leitura pública (única exceção aprovada), escrita restrita à própria pasta do usuário (`<uid>/<arquivo>`), MIME `image/png`/`image/jpeg`/`image/webp`, limite de 2 MB. Toda política em `storage.objects` filtra `bucket_id = 'avatars'` explicitamente (tabela compartilhada entre todos os buckets do projeto). Confirmado: bucket e as quatro políticas (`avatars_public_read`/`avatars_insert_own_folder`/`avatars_update_own_folder`/`avatars_delete_own_folder`) conferidos via `storage.buckets`/`pg_policies`. Arquivo em `database/schema/1040_create_avatars_bucket.sql`.

## Query `1004` — Grant User Profile Privileges (CONFIRMADO EXECUTADO)

**Bug real encontrado durante a integração do frontend (2026-07-26)**: `/perfil` retornava `permission denied for table user_profile` (`code 42501`) mesmo com as políticas de RLS da Query `1003` corretas. Causa: RLS restringe linhas, mas pressupõe que o privilégio de tabela já exista — o `GRANT` de base para o role `authenticated` nunca tinha sido emitido (mesma classe de lacuna já vista antes neste projeto com `service_role`/Edge Functions, ver revisão `0.69`, migration `272`). Corrigido com `GRANT SELECT, UPDATE ON public.user_profile TO authenticated;`, espelhando exatamente as duas políticas de RLS existentes — nenhum privilégio concedido a `anon` (perfil não é público neste incremento) nem `INSERT` (a criação da linha continua exclusiva de `handle_new_user()`, que roda como `SECURITY DEFINER`). Confirmado via `information_schema.role_table_grants`: `authenticated` com `SELECT`/`UPDATE`, `anon` sem nenhum dos dois. Arquivo em `database/schema/1004_grant_user_profile_privileges.sql`.

## Sequência

```text
1000 - Create User Profile table                       (CONFIRMADO EXECUTADO — database/schema/1000_create_user_profile_table.sql)
1001 - Create User Profile trigger                      (CONFIRMADO EXECUTADO — database/schema/1001_create_user_profile_trigger.sql)
1002 - Create User Profile invariants trigger           (CONFIRMADO EXECUTADO — database/schema/1002_create_user_profile_invariants_trigger.sql)
1003 - Create User Profile RLS policies                 (CONFIRMADO EXECUTADO — database/schema/1003_create_user_profile_rls_policies.sql)
1004 - Grant User Profile privileges                    (CONFIRMADO EXECUTADO — database/schema/1004_grant_user_profile_privileges.sql)
1010 - Create Reserved Username table                   (CONFIRMADO EXECUTADO — database/schema/1010_create_reserved_username_table.sql)
1011 - Create Reserved Username trigger                 (CONFIRMADO EXECUTADO — database/schema/1011_create_reserved_username_trigger.sql)
1020 - Create handle_new_user function and trigger      (CONFIRMADO EXECUTADO — database/schema/1020_create_handle_new_user_function.sql)
1030 - Create username_available function                (CONFIRMADO EXECUTADO — database/schema/1030_create_username_available_function.sql)
1040 - Create avatars bucket and storage policies         (CONFIRMADO EXECUTADO — database/schema/1040_create_avatars_bucket.sql)
1710 - Seed Reserved Username (v1.1, 50 termos)           (CONFIRMADA EXECUTADA — database/seeds/1710_seed_reserved_username.sql)
1800 - Validate User Profile                              (EXECUTADA — database/validations/1800_validate_user_profile.sql)
1810 - Validate Reserved Username                         (EXECUTADA — database/validations/1810_validate_reserved_username.sql)
1820 - Validate handle_new_user                           (EXECUTADA — database/validations/1820_validate_handle_new_user.sql)
1830 - Validate username_available                        (EXECUTADA — database/validations/1830_validate_username_available.sql)
1840 - Validate avatars bucket                            (EXECUTADA — database/validations/1840_validate_avatars_bucket.sql)
```

## Pendências / Próximos Passos

Frontend do Incremento 1 concluído e validado por Fabrício (2026-07-26): cadastro com `username`/`display_name`, tela `/perfil` real (avatar, nome de exibição editável, username bloqueado) — cadastro completo, carregamento de `/perfil`, edição de `display_name` e troca de avatar todos confirmados em produção. Incremento 2 (Administração de Usuários) iniciado — ver seção própria abaixo.

---

# Administração de Usuários

## Status

**Incremento 2, Fases 1–3 (fundação, leitura segura, interface) CONFIRMADAS EXECUTADAS e validadas em produção (2026-07-26).** Segunda entidade do módulo Identidade e Acesso (milhar `1000`–`1999`), formalizada em ADR-021 (Administrative Role Model). Fase 4 (correção administrativa de `username`) deliberadamente fora deste incremento — tratada como incremento futuro separado.

## Decisão de Modelagem

Papel administrativo modelado como presença de linha em `admin_user`, entidade separada de `user_profile` — nunca um atributo booleano nela, para não expor uma coluna autopromovível pelas políticas de RLS de `UPDATE` já existentes. Um único papel (`admin`), sem sistema genérico de papéis/permissões. Todo acesso administrativo passa por functions `SECURITY DEFINER`; `admin_user` e `admin_action_log` têm RLS habilitado e zero políticas — nenhum acesso direto via API, nem para o próprio admin. Ver ADR-021 para o raciocínio completo e as alternativas rejeitadas.

## Modelo Físico — `admin_user` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.admin_user (
    id           UUID PRIMARY KEY
                 REFERENCES auth.users(id)
                 ON DELETE CASCADE,
    granted_by   UUID NULL
                 REFERENCES auth.users(id)
                 ON DELETE SET NULL,
    granted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_user ENABLE ROW LEVEL SECURITY;
```

Sem `updated_at`/trigger: tabela de presença (INSERT/DELETE), não um registro editável. `granted_by` anulável com `ON DELETE SET NULL` — a exclusão futura de quem concedeu o papel nunca invalida a concessão em si. Confirmado via `information_schema`/`pg_tables`. Arquivo em `database/schema/1050_create_admin_user_table.sql`.

## Modelo Físico — `admin_action_log` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    target_user_id   UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    action           TEXT NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT admin_action_log_action_valid CHECK (action IN ('GRANT_ADMIN', 'REVOKE_ADMIN'))
);

ALTER TABLE public.admin_action_log ENABLE ROW LEVEL SECURITY;
```

FKs anuláveis com `ON DELETE SET NULL` (não `CASCADE`): o histórico administrativo sobrevive à exclusão futura de qualquer usuário envolvido — `metadata` grava um retrato (username/e-mail de ator e alvo) capturado no momento da ação, preservando contexto legível mesmo depois que a referência direta vira `NULL`. Ajuste pedido por Fabrício antes da implementação. Confirmado via `pg_constraint`/`pg_tables`. Arquivo em `database/schema/1070_create_admin_action_log_table.sql`.

## Query `1060` — Create `is_admin()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, **sem parâmetro** — verifica somente `auth.uid()`, o usuário da própria sessão. Ajuste pedido por Fabrício antes da implementação: a proposta original aceitava um `p_user_id` arbitrário, permitindo que qualquer usuário consultasse o status administrativo de outro UUID; rejeitado. `EXECUTE` concedido apenas a `authenticated`. Confirmado: `prosecdef = true`, `pronargs = 0`, grants corretos. Testado via SQL Editor retornando `false` (esperado — sem sessão real, `auth.uid()` é `NULL` nesse contexto). Arquivo em `database/schema/1060_create_is_admin_function.sql`.

## Query `1061` — Create `admin_list_users()` (CONFIRMADO EXECUTADO, v1.1)

Function `SECURITY DEFINER` que lista usuários para fins administrativos — única via de leitura de e-mail (`auth.users`) para esse propósito; o frontend nunca consulta `auth.users` diretamente. Paginada desde a origem (`limit`/`offset`, teto de 100 controlado no servidor), mesmo sem busca/filtros nesta fase — ajuste pedido por Fabrício antes da implementação ("uma listagem ilimitada não é adequada à evolução comercial do sistema"). Retorna `total_count` via `count(*) OVER()` em cada linha, evitando uma segunda chamada para montar a paginação. Campos: `id`, `username`, `display_name`, `avatar_path`, `email`, `created_at`, `is_admin`.

**Bug real encontrado na integração da Fase 3**: `structure of query does not match function result type` (erro `42804`) — `auth.users.email` é `character varying(255)`, não `TEXT`; o `RETURN QUERY` exige tipo exato contra o `RETURNS TABLE` declarado. Corrigido com `au.email::text` (v1.1). Confirmado funcionando a partir do app real, retornando a lista corretamente. Arquivo em `database/schema/1061_create_admin_list_users_function.sql`.

## Query `1062` — Create `admin_grant_admin()` / `admin_revoke_admin()` (CONFIRMADO EXECUTADO)

Functions `SECURITY DEFINER` para conceder/revogar o papel administrativo, ambas exigindo `is_admin()` do chamador. Ambas adquirem a mesma trava consultiva de transação (`pg_advisory_xact_lock`), serializando concessões/revogações concorrentes — ajuste pedido por Fabrício antes da implementação, para que duas revogações simultâneas não possam remover o último administrador ao mesmo tempo. `admin_revoke_admin()` bloqueia explicitamente essa remoção (`RAISE EXCEPTION` se restaria zero administradores). Ambas gravam em `admin_action_log` com o retrato de `metadata`. Confirmado: `prosecdef = true`, `pronargs = 1`, grants corretos. Arquivo em `database/schema/1062_create_admin_grant_revoke_functions.sql`.

## Bootstrap administrativo — operação única (NÃO é uma migration replicável)

Como `admin_grant_admin()` exige que o chamador já seja administrador, a primeira concessão não pode passar pela function — é um `INSERT` direto, rodado uma única vez via SQL Editor, concedendo o papel a Fabrício (identificado por e-mail, evitando copiar/colar UUID manualmente) e registrando a ação em `admin_action_log` com uma nota explícita de que é bootstrap. Por decisão de Fabrício, esta operação **não** foi numerada na sequência estrutural nem gravada em `database/schema/` — é específica deste ambiente (hardcoda um e-mail real) e não deve ser reexecutada em outro projeto/ambiente sem ajuste.

```sql
INSERT INTO public.admin_user (id, granted_by)
SELECT id, NULL FROM auth.users WHERE email = 'fabricio.souza.sales@hotmail.com';

INSERT INTO public.admin_action_log (actor_id, target_user_id, action, metadata)
SELECT id, id, 'GRANT_ADMIN',
    jsonb_build_object('note', 'bootstrap inicial — primeiro administrador, concedido manualmente via SQL Editor')
FROM auth.users WHERE email = 'fabricio.souza.sales@hotmail.com';
```

Confirmado executado — Fabrício listado como administrador em `admin_user`, com o registro correspondente em `admin_action_log`.

## Sequência

```text
1050 - Create Admin User table                          (CONFIRMADO EXECUTADO — database/schema/1050_create_admin_user_table.sql)
1060 - Create is_admin() function                        (CONFIRMADO EXECUTADO — database/schema/1060_create_is_admin_function.sql)
1061 - Create admin_list_users() function (v1.1)          (CONFIRMADO EXECUTADO — database/schema/1061_create_admin_list_users_function.sql)
1062 - Create admin_grant_admin()/admin_revoke_admin()     (CONFIRMADO EXECUTADO — database/schema/1062_create_admin_grant_revoke_functions.sql)
1070 - Create Admin Action Log table                      (CONFIRMADO EXECUTADO — database/schema/1070_create_admin_action_log_table.sql)
      - Bootstrap administrativo                          (CONFIRMADO EXECUTADO — operação única, não numerada, não versionada em database/schema/)
1850 - Validate Admin User                                (EXECUTADA — database/validations/1850_validate_admin_user.sql)
1860 - Validate Admin Functions                           (EXECUTADA — database/validations/1860_validate_admin_functions.sql)
1870 - Validate Admin Action Log                          (EXECUTADA — database/validations/1870_validate_admin_action_log.sql)
```

## Frontend (Fase 3, CONFIRMADO EXECUTADO)

Rota `/usuarios` (já existia como placeholder desde a fundação do frontend, agora real): Server Component que redireciona para `/login` sem sessão, mostra "Acesso restrito a administradores" para não-admin, erro dedicado se `admin_list_users()` falhar, "Nenhum usuário encontrado" no caso vazio, e a tabela paginada nos demais casos. Item "Usuários" do menu (`nav-config.ts`) marcado `adminOnly` — some do menu para quem não é admin (checagem de UX; a autorização real está nas functions do banco, não no frontend). `AppShell` busca `is_admin()` uma única vez e repassa a `Sidebar`/`Header`/`MobileNav`. Tabela (`components/usuarios/users-table.tsx`) mostra username/nome/e-mail/data/papel e um botão conceder/revogar por linha, via Server Actions (`app/usuarios/actions.ts`) com tradução de erros dedicada (`lib/supabase/admin-errors.ts`).

## Pendências / Próximos Passos

Fase 4 (correção administrativa de `username`) deliberadamente fora deste incremento — mecanismo desenhado em nível conceitual no ADR-021 (flag local à transação sinalizando ao trigger `enforce_user_profile_invariants()`), implementação adiada para um incremento futuro. Testabilidade de `admin_grant_admin()`/`admin_revoke_admin()` com um segundo usuário real ainda pendente (Fabrício é hoje o único usuário/administrador cadastrado). Visualização do `admin_action_log` pela interface não faz parte deste incremento — o dado já é gravado, sem tela própria ainda.

---

