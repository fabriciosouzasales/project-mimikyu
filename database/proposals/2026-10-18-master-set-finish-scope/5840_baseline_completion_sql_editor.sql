/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5840 - Baseline de regressão do resumo de completude,
              executável no SQL Editor do Supabase (sem psql, sem senha)
Versão......: 1.0
Status......: PROPOSTO — validado como leitura pelo agente (ver README)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-BASELINE-WITHOUT-PSQL-01)

Substitui o protocolo psql do 5838 para Fabrício (sem senha de banco, sem
psql, sem ambiente paralelo). Mesmo objetivo: provar que aplicar 5184–5197
não mudou o resultado de completude das coleções existentes.

COMO EXECUTAR: colar o arquivo INTEIRO no SQL Editor e clicar Run uma vez.
São duas instruções SELECT; o SQL Editor envia as duas na mesma requisição,
que roda numa única transação, e mostra o resultado da última.

O QUE CADA INSTRUÇÃO FAZ
  1. SELECT set_config(..., true): define as claims JWT do dono das
     coleções SÓ para esta transação (is_local = true). É o mecanismo que o
     próprio Supabase usa para "rodar como usuário". Não troca papel, não
     concede privilégio e não altera dado; termina junto com a requisição
     (verificado: a requisição seguinte não vê as claims).
  2. SELECT final: para cada coleção, em ordem de id,
       - ORÁCULO independente, lido direto das tabelas (sem identidade):
         vínculos, total de cartas do Set referenciado e cartas distintas
         satisfeitas — a mesma regra do ramo STANDARD_SET do 5102;
       - RESUMO real: collection_completion_summary(id), chamado como o dono.
     Linha por coleção sem id nem dado pessoal; COBERTURA; GATE com md5.

SEGURANÇA: nenhuma instrução pode escrever. A instrução 2 só chama funções
STABLE (o PostgreSQL proíbe comandos de escrita dentro delas) e a 1 só muda
parâmetros locais da transação. Não usa service_role nem SET ROLE.
Pré-condição: um único dono para todas as coleções (LIVE de hoje: 1). Com
mais de um dono a COBERTURA acusa e tudo sai INVALIDO.

STATUS
  - Coleção de Set (STANDARD_SET): OK se o resumo existir E bater com o
    oráculo (total e satisfeitas).
  - Coleção livre (NONE): OK se NÃO houver resumo (contrato do 5102).
  - MASTER_SET / REFERENCE_POSITION: OK se o resumo existir (sem oráculo
    nesta versão; o LIVE não tem nenhuma).
  - Qualquer linha INVALIDO → todas as linhas INVALIDO e GATE sem digest.

Resultado esperado no LIVE de 2026-10-18 (pré-aplicação): ver README,
seção "Baseline sem psql (5840)".
================================================================
*/

select set_config('request.jwt.claims',
         json_build_object('sub', (select min(c.owner_user_id::text) from public.collection c),
                           'role', 'authenticated')::text,
         true) is not null as claims_set,
       set_config('request.jwt.claim.sub',
         (select min(c.owner_user_id::text) from public.collection c),
         true) is not null as sub_set;

with coll as (
  select c.id,
         row_number() over (order by c.id) as n,
         c.completion_policy,
         c.mode,
         ccsr.card_set_id,
         cs.code as set_code
  from public.collection c
  left join public.collection_reference cr on cr.collection_id = c.id
  left join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  left join public.card_set cs on cs.id = ccsr.card_set_id
),
oracle as (
  select k.id,
         (select count(*) from public.collection_allocation ca where ca.collection_id = k.id) as alloc,
         case when k.card_set_id is not null then
           (select count(*) from public.card card where card.card_set_id = k.card_set_id) end as o_total,
         case when k.card_set_id is not null then
           (select count(distinct card.id)
              from public.collection_allocation ca
              join public.physical_card pc on pc.id = ca.physical_card_id
              join public.card_variant cv on cv.id = pc.card_variant_id
              join public.card card on card.id = cv.card_id and card.card_set_id = k.card_set_id
             where ca.collection_id = k.id) end as o_sat
  from coll k
),
summ as (
  select k.id, s.total_positions, s.satisfied_positions, s.missing_positions,
         s.progress_percentage, s.is_complete, (s.collection_id is not null) as has_summary
  from coll k
  left join lateral public.collection_completion_summary(k.id) s on true
),
lines as (
  select k.n,
         format('C%s|%s|%s|set=%s|alloc=%s|oraculo=%s/%s|resumo=%s',
                k.n, k.completion_policy, k.mode, coalesce(k.set_code, '-'), o.alloc,
                coalesce(o.o_total::text, '-'), coalesce(o.o_sat::text, '-'),
                case when s.has_summary
                     then concat_ws('/', s.total_positions, s.satisfied_positions, s.missing_positions,
                                    s.progress_percentage, s.is_complete)
                     else 'SEM_RESUMO' end) as line,
         case
           when k.completion_policy = 'NONE' then not s.has_summary
           when k.completion_policy = 'STANDARD_SET' then
                s.has_summary and s.total_positions = o.o_total and s.satisfied_positions = o.o_sat
           else s.has_summary
         end as ok
  from coll k
  join oracle o on o.id = k.id
  join summ s on s.id = k.id
),
chk as (
  select (select count(*) from public.collection) as existentes,
         (select count(*) from lines) as lidas,
         (select count(*) from lines where not ok) as invalidas,
         (select count(distinct owner_user_id) from public.collection) as donos,
         (select auth.uid())::text = (select min(owner_user_id::text) from public.collection) as identidade_ok
),
verdict as (
  select case when c.invalidas = 0 and c.lidas = c.existentes and c.donos = 1 and c.identidade_ok
              then 'OK' else 'INVALIDO' end as status
  from chk c
)
select x.ordem, x.item, x.detalhe, v.status
from (
  select l.n as ordem, 'COLECAO C' || l.n as item,
         l.line || case when l.ok then '' else '  <-- divergente' end as detalhe
  from lines l
  union all
  select 900, 'COBERTURA',
         format('lidas=%s/%s; invalidas=%s; donos=%s; identidade=%s',
                c.lidas, c.existentes, c.invalidas, c.donos, c.identidade_ok)
  from chk c
  union all
  select 999, 'GATE',
         case when (select status from verdict) = 'OK'
              then md5(string_agg(l.line, E'\n' order by l.n)) end
  from lines l
) x
cross join verdict v
order by x.ordem;
