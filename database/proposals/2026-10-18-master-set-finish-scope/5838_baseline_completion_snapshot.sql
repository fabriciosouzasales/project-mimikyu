\set ON_ERROR_STOP on
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5838 - Baseline de regressão: resumo de completude de
              todas as coleções existentes (antes × depois de 5184–5197)
Versão......: 1.3
Status......: PROPOSTO — NÃO EXECUTADO (executar com autorização de Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (AUDIT-CORRECTION-01; reclassificado na -02;
              transação somente leitura explícita na -03; coleção livre
              tratada como resumo ausente esperado na LIVE-EXECUTION-START-01)

CLIENTE: psql (script psql, NÃO serve para o SQL Editor). A primeira linha
(\set ON_ERROR_STOP on) é um meta-comando do psql; colada no SQL Editor,
falha de propósito. Conexão: direta ou Session Pooler (porta 5432) — a
mesma usada nos roteiros de concorrência. NÃO usar o Transaction Pooler
(6543): objetos pg_temp não sobrevivem entre transações nele.
Execução (cada execução é autocontida; não depende de sessão anterior):
    psql "<connection string 5432>" -X -f 5838_baseline_completion_snapshot.sql

DUAS FASES, NA MESMA SESSÃO E NO MESMO ARQUIVO
  Fase A — preparação (DDL TEMPORÁRIA DE SESSÃO, transação própria):
    CREATE OR REPLACE FUNCTION pg_temp.ms_5838_snapshot(). Objeto visível
    só nesta sessão, removido quando o psql desconecta. Nenhum objeto
    permanente é criado ou alterado. Repetir o arquivo recria a função
    (idempotente), então nenhuma execução depende de objeto temporário de
    outra conexão.
  Fase B — snapshot (transação aberta EXPLICITAMENTE como somente leitura):
    START TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
    SELECT * FROM pg_temp.ms_5838_snapshot();
    ROLLBACK;
    - READ ONLY declarado na abertura: é o modo documentado do
      PostgreSQL; qualquer INSERT/UPDATE/DELETE/DDL na transação (inclusive
      dentro de funções SECURITY DEFINER chamadas) falha com 25006.
    - REPEATABLE READ: uma única fotografia do banco para todas as
      coleções do snapshot (consistência entre coleções).
    - A função RECUSA rodar (erro 25000 MS5838_REQUIRES_READ_ONLY_RR, sem
      linhas de resultado) se a transação não for somente leitura em
      REPEATABLE READ ou SERIALIZABLE. Não há mais set_config de
      transaction_read_only dentro da função (v1.1): a garantia vem da
      abertura da transação e é conferida, não presumida.
    - ROLLBACK no fim: descarta as claims locais e qualquer estado da
      transação.
  Estado de sessão alterado: request.jwt.claims e request.jwt.claim.sub,
  com escopo LOCAL à transação da fase B (zerados no fim da função e
  descartados pelo ROLLBACK).
  Privilégios: TEMPORARY no banco (fase A), EXECUTE em
  collection_completion_summary e SELECT em public.collection. O papel
  postgres tem os três. Não usa service_role.
  Autorização: execução no LIVE; Fabrício executa.

Por que não um SELECT único: o resumo exige auth.uid() = dono; num SELECT
seria preciso definir a identidade por linha antes do resumo da mesma
linha, e a ordem de avaliação não é garantida (5836 caso 8.1). O laço
procedural define a identidade numa instrução e chama o resumo na
seguinte.

Identidade por iteração: sem troca de papel (o resumo é SECURITY DEFINER e
só usa auth.uid(), 5188 linhas 65/66 e 189/190). Para cada coleção, em
ordem de id, as duas claims recebem o dono daquela coleção imediatamente
antes da chamada.

Erros NÃO viram resultado de regressão:
  - erro numa coleção é registrado (id|ERRO|sqlstate) para diagnóstico e
    a execução continua;
  - resumo vazio é registrado (id|SEM_LINHA) e invalida o snapshot,
    EXCETO para coleção livre (completion_policy = 'NONE'): o resumo
    (5102) só cobre STANDARD_SET, MASTER_SET e REFERENCE_POSITION, então
    para ela a ausência de linha é o contrato. Registrada como
    id|NONE|SEM_RESUMO, entra no md5 e não conta como lacuna (v1.3; o LIVE
    tem 1 coleção livre, que invalidaria a v1.2 indevidamente);
  - se houver qualquer erro, qualquer SEM_LINHA ou divergência entre
    coleções lidas e existentes, TODAS as linhas saem com
    status = 'INVALIDO' e o digest do GATE sai NULL: o resultado não pode
    ser usado para comparação. Só status = 'OK' em todas as linhas é
    snapshot válido;
  - erro na fase A ou fora do laço interrompe o script (ON_ERROR_STOP).

Determinismo e cobertura: todas as linhas de public.collection (qualquer
política, modo ou ciclo de vida), uma linha de texto por coleção
(id|política|total|satisfeitas|faltantes|percentual|completa), md5 sobre
as linhas ordenadas; linha COBERTURA com lidas/existentes, sem_linha e
erros.
Privacidade: a saída tem só rótulos de grupo (política × modo),
contagens, md5 e status. Nenhum id, nome ou dado de dono sai do banco.

Protocolo de comparação: ver README da proposta (seção 5838).
================================================================
*/

-- Fase A — preparação (DDL temporária de sessão) ------------------------------
begin;

create or replace function pg_temp.ms_5838_snapshot()
returns table (grp text, collections bigint, digest text, status text)
language plpgsql
volatile
as $fn$
declare
  v_coll    record;
  v_line    text;
  v_rows    text[] := '{}';
  v_total   bigint;
  v_errors  bigint;
  v_empty   bigint;
  v_status  text;
begin
  -- recusa fora de transação somente leitura com fotografia única
  if current_setting('transaction_read_only') <> 'on'
     or current_setting('transaction_isolation') not in ('repeatable read', 'serializable') then
    raise exception 'MS5838_REQUIRES_READ_ONLY_RR'
      using errcode = '25000',
            detail  = format('transaction_read_only=%s, transaction_isolation=%s',
                             current_setting('transaction_read_only'),
                             current_setting('transaction_isolation')),
            hint    = 'START TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;';
  end if;

  select count(*) into v_total from public.collection;

  for v_coll in
    select c.id, c.owner_user_id, c.completion_policy
    from public.collection c
    order by c.id
  loop
    perform set_config('request.jwt.claim.sub', v_coll.owner_user_id::text, true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_coll.owner_user_id, 'role', 'authenticated')::text, true);
    begin
      v_line := null;
      select concat_ws('|', s.collection_id, s.completion_policy, s.total_positions,
                       s.satisfied_positions, s.missing_positions,
                       s.progress_percentage, s.is_complete)
        into v_line
      from public.collection_completion_summary(v_coll.id) s;
      v_line := coalesce(v_line,
                         case when v_coll.completion_policy = 'NONE'
                              then v_coll.id::text || '|NONE|SEM_RESUMO'
                              else v_coll.id::text || '|SEM_LINHA'
                         end);
    exception when others then
      v_line := v_coll.id::text || '|ERRO|' || sqlstate;
    end;
    v_rows := v_rows || v_line;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  select count(*) filter (where x.line like '%|ERRO|%'),
         count(*) filter (where x.line like '%|SEM_LINHA')
    into v_errors, v_empty
  from unnest(v_rows) x(line);

  v_status := case
                when v_errors = 0 and v_empty = 0 and cardinality(v_rows) = v_total then 'OK'
                else 'INVALIDO'
              end;

  return query
  with r as (
    select x.line, c.completion_policy, c.mode
    from unnest(v_rows) x(line)
    join public.collection c on c.id = split_part(x.line, '|', 1)::uuid
  )
  select r.completion_policy || ' × ' || r.mode, count(*)::bigint,
         md5(string_agg(r.line, E'\n' order by r.line)), v_status
  from r
  group by r.completion_policy, r.mode
  union all
  select 'COBERTURA (lidas/existentes, sem_linha, erros)',
         cardinality(v_rows)::bigint,
         format('%s/%s, %s, %s', cardinality(v_rows), v_total, v_empty, v_errors),
         v_status
  union all
  select 'GATE (global)', cardinality(v_rows)::bigint,
         case when v_status = 'OK'
              then md5(coalesce((select string_agg(x.line, E'\n' order by x.line)
                                 from unnest(v_rows) x(line)), ''))
         end,
         v_status
  order by 1;
end;
$fn$;

commit;

-- Fase B — snapshot em transação somente leitura explícita --------------------
start transaction isolation level repeatable read, read only;

select * from pg_temp.ms_5838_snapshot();

rollback;
