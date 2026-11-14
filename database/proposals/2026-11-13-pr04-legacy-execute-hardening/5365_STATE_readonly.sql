/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5365_STATE - estado das permissões e janela G-D (somente leitura)
Versão......: 1.2 (2026-11-13, `PR-04A | G-D TARGETED CORRECTION-02`: consulta 2
              com origem ADMIN/NÃO-ADMIN, visibilidade comprovada, chave
              dbid+toplevel e detecção de duplicidade). Consulta 1 igual à 1.1.
Status......: PROPOSTA — leitura pura (dois SELECT, nenhuma escrita).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-13
Objetivo....: Consulta 1 — estado das 8 assinaturas (md5, dono, ACL e
              EXECUTE efetivo por papel), antes (PRE) e depois (POST) da
              5365 ou da R5365.
              Consulta 2 — fotografia de pg_stat_statements para o gate
              G-D (T0 e T1): linha META (visibilidade, linhas ocultas,
              stats_reset, dealloc) + uma linha por entrada que cita as
              funções-alvo, com classe, origem e chave completa.
Resultado esperado: Consulta 1 — PRE igual à tabela "Alvo e estado" do
              README; POST conforme "Critérios de aceite". Consulta 2 —
              decisão PASS / STOP / EVIDENCE INSUFFICIENT pela matriz do
              README ("Gate G-D"); não é aprovação automática.
Como validar: guardar a saída integral de cada execução (PRE, POST, T0,
              T1) junto da evidência da rodada e comparar campo a campo.
================================================================
*/

-- Consulta 1 — estado das permissões ----------------------------------------
select p.oid::regprocedure::text                                   as assinatura,
       pg_catalog.md5(p.prosrc)                                    as md5_corpo,
       pg_catalog.pg_get_userbyid(p.proowner)                      as dono,
       p.prosecdef                                                 as secdef,
       coalesce(p.proconfig::text, '')                             as config,
       p.proacl::text                                              as acl,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_x,
       pg_catalog.has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_x,
       pg_catalog.has_function_privilege('service_role',  p.oid, 'EXECUTE') as service_role_x,
       pg_catalog.has_function_privilege('postgres',      p.oid, 'EXECUTE') as postgres_x
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('set_physical_cards_storage', 'organize_my_collection_storage', 'add_physical_cards',
                     'set_my_physical_cards_condition', 'remove_my_physical_card', 'register_physical_cards_bulk')
 order by 1;

-- Consulta 2 — fotografia G-D (T0 e T1) --------------------------------------
-- Linha META (uma): executor, visibilidade comprovada (superusuário ou
-- membro de pg_read_all_stats), linhas com texto oculto em TODA a view,
-- total de linhas, stats_reset e dealloc. Visibilidade false ou ocultas > 0
-- → EVIDENCE INSUFFICIENT (não se infere ausência de chamada de linha
-- invisível).
-- Linhas de dados: entradas cujo texto cita uma das três funções.
--   origem  ADMIN      papel = postgres (rotina administrativa conhecida)
--           NAO_ADMIN  qualquer outro papel (authenticated, anon,
--                      service_role, desconhecido) — potencial consumidor
--   classe  LEGACY_STORAGE   "set_physical_cards_storage"( sem p_unplace_from_binder
--           LEGACY_ORGANIZE  "organize_my_collection_storage"( sem p_unplace_from_binder
--           LEGACY_ADD       add_physical_cards(  (qualquer forma)
--           CURRENT_STORAGE / CURRENT_ORGANIZE   com p_unplace_from_binder (referência)
--           AMBIGUOUS        cita a função mas não se encaixa acima (DDL, DO,
--                            GRANT/REVOKE, comentário, outro formato)
--   chave   (dbid, papel, toplevel, queryid, classe); chave_repetida > 1
--           → EVIDENCE INSUFFICIENT.
-- Observação: SELECT comuns são guardados normalizados (literais viram $n),
-- então esta própria consulta não aparece como chamada às funções; DO e
-- comandos utilitários são guardados como texto literal.
with s as (
  select st.dbid,
         st.userid,
         pg_catalog.pg_get_userbyid(st.userid) as papel,
         st.toplevel,
         st.queryid,
         st.calls,
         st.query
    from extensions.pg_stat_statements st
   where st.query ~* '(set_physical_cards_storage|organize_my_collection_storage|add_physical_cards)'
),
c as (
  select s.*,
         case when s.papel = 'postgres' then 'ADMIN' else 'NAO_ADMIN' end as origem,
         case
           when s.query ~* '^\s*(create|alter|drop|grant|revoke|comment|do)\M' then 'AMBIGUOUS'
           when s.query ~* '"set_physical_cards_storage"\s*\(' and s.query !~* 'p_unplace_from_binder' then 'LEGACY_STORAGE'
           when s.query ~* '"organize_my_collection_storage"\s*\(' and s.query !~* 'p_unplace_from_binder' then 'LEGACY_ORGANIZE'
           when s.query ~* 'add_physical_cards"?\s*\(' then 'LEGACY_ADD'
           when s.query ~* '"set_physical_cards_storage"\s*\(' then 'CURRENT_STORAGE'
           when s.query ~* '"organize_my_collection_storage"\s*\(' then 'CURRENT_ORGANIZE'
           else 'AMBIGUOUS'
         end as classe
    from s
)
select 'META'                                         as linha,
       null::text                                     as origem,
       null::text                                     as classe,
       null::oid                                      as dbid,
       null::text                                     as papel,
       null::boolean                                  as toplevel,
       null::bigint                                   as queryid,
       null::bigint                                   as calls,
       null::bigint                                   as chave_repetida,
       current_user::text                             as executor,
       (coalesce((select r.rolsuper from pg_catalog.pg_roles r where r.rolname = current_user), false)
        or pg_catalog.pg_has_role(current_user, 'pg_read_all_stats', 'USAGE'))
                                                      as visibilidade_total,
       (select count(*) from extensions.pg_stat_statements x
         where x.query is null or x.query = '<insufficient privilege>')
                                                      as linhas_ocultas,
       (select count(*) from extensions.pg_stat_statements)
                                                      as linhas_total,
       i.stats_reset::text                            as stats_reset,
       i.dealloc                                      as dealloc,
       null::text                                     as trecho
  from extensions.pg_stat_statements_info i
union all
select 'DADO',
       c.origem,
       c.classe,
       c.dbid,
       c.papel,
       c.toplevel,
       c.queryid,
       c.calls,
       count(*) over (partition by c.dbid, c.userid, c.toplevel, c.queryid, c.classe),
       null::text,
       null::boolean,
       null::bigint,
       null::bigint,
       null::text,
       null::bigint,
       left(pg_catalog.regexp_replace(c.query, '\s+', ' ', 'g'), 160)
  from c
 order by 1 desc, 2, 3, 5, 4, 6, 7;
