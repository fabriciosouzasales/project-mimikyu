/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5319 - Revoke TRUNCATE/REFERENCES/TRIGGER excedentes (anon/authenticated)
Versão......: 2.0 (V1-12 SECURITY CLOSEOUT & LIVE GATE-04)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030142055 `5319_revoke_excess_table_privileges`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-collection-sharing/
              (só este bloco Status difere); texto do ledger ≡ arquivo da proposta inteiro (md5).
              Validação: 5861 v1.3 51/51 PASS.
              Aplicada ANTES da 5300 (independente das demais; ver ledger).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Remove os únicos privilégios TRUNCATE, REFERENCES e TRIGGER que anon e
authenticated ainda têm no schema public. Levantamento no LIVE (somente
leitura, information_schema.role_table_grants, 2026-10-30): exatamente 42
grants, em 8 objetos — nenhum outro objeto do schema (117) os possui.

  objeto                               tipo  anon    authenticated
  user_profile                         table D x t   S U D x t   (2 políticas own)
  storage_bucket                       table D x t   D x t       (RLS, 0 políticas)
  admin_action_log                     table D x t   D x t       (RLS, 0 políticas)
  reserved_username                    table D x t   D x t       (RLS, 0 políticas)
  admin_user                           table D x t   D x t       (RLS, 0 políticas)
  catalog_card_set_variant_coverage    view  D x t   S D x t     (security_invoker)
  catalog_card_set_image_coverage      view  —       S D x t     (security_invoker)
  catalog_card_set_metrics             view  —       S D x t     (security_invoker)
  (D = TRUNCATE, x = REFERENCES, t = TRIGGER, S = SELECT, U = UPDATE)

Origem: o default ACL de supabase_admin concede arwdDxtm a anon/authenticated;
esses objetos tiveram SELECT/INSERT/UPDATE/DELETE revogados no passado, mas
não D/x/t. O default ACL de postgres (dono dos objetos do projeto) já é
limpo — objetos novos não herdam o problema.

Dependências legítimas: nenhuma.
- TRUNCATE ignora RLS e não é usado pelo app (PostgREST não emite TRUNCATE;
  nenhuma função do schema faz TRUNCATE nesses objetos — a única função com
  a palavra é um guard de trigger de outra tabela).
- REFERENCES só serve para criar FK apontando para o objeto; o app nunca
  cria tabela como anon/authenticated.
- TRIGGER só serve para criar trigger no objeto; idem.
- Em views, TRUNCATE nem é aplicável.

Regras de Negócio:
- Revoga SÓ D/x/t de anon e authenticated, SÓ nesses 8 objetos.
- Preserva tudo o mais: SELECT/UPDATE de authenticated em user_profile
  (perfil próprio, com as políticas own), SELECT de authenticated nas três
  views do catálogo (security_invoker: o RLS das tabelas-base decide), todos
  os grants de service_role/postgres, todas as políticas RLS.
- Idempotente: REVOKE de privilégio ausente é no-op.
================================================================
*/

REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE
    public.user_profile,
    public.storage_bucket,
    public.admin_action_log,
    public.reserved_username,
    public.admin_user,
    public.catalog_card_set_variant_coverage,
    public.catalog_card_set_image_coverage,
    public.catalog_card_set_metrics
FROM anon, authenticated;

/*
Como validar (somente leitura, logo após aplicar):

select
  (select count(*) from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon','authenticated')
      and privilege_type in ('TRUNCATE','REFERENCES','TRIGGER'))                         as excedentes,      -- esperado 0
  has_table_privilege('authenticated','public.user_profile','SELECT')                    as perfil_select,   -- true
  has_table_privilege('authenticated','public.user_profile','UPDATE')                    as perfil_update,   -- true
  has_table_privilege('authenticated','public.catalog_card_set_metrics','SELECT')        as metrics_select,  -- true
  has_table_privilege('authenticated','public.catalog_card_set_image_coverage','SELECT') as image_select,    -- true
  has_table_privilege('authenticated','public.catalog_card_set_variant_coverage','SELECT') as variant_select, -- true
  (select count(*) from pg_policy where polrelid = 'public.user_profile'::regclass)       as perfil_policies; -- 2 (inalterado)
*/
