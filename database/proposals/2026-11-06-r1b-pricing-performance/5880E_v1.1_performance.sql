/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5880E - v1.1 | Desempenho da 3989 em lotes reais (somente leitura)
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-11-06 (R1-B PRICING 3989 VALIDATION RECOVERY-03)
Autor.......: Fabrício Sales / Claude

Rastreabilidade com o 5880 v1.0: 9.1 (pior lote < 8.000 ms). A comparação de tempo com a 3983
sobre o acervo inteiro NÃO é repetida (foi a causa da execução monolítica que não terminou);
a referência de custo da 3983 é a medida do diagnóstico (buffers 6.797 por lote de 100).

O que mede: todas as variantes distintas do acervo (todas as contas), em lotes de 100 na
mesma ordem do app (ordem por id), chamando SÓ a 3989 como authenticated, :reps repetições.
Por chamada: ms (clock_timestamp), linhas, erro (SQLSTATE) — cada chamada isolada em bloco
de exceção, então um 57014/erro em um lote não interrompe os demais.
Critérios de desempenho (métricas, não gate funcional):
  - nenhuma chamada com erro;
  - pior chamada < 8.000 ms (o statement_timeout do papel authenticated em produção);
O statement_timeout desta execução é 100 s para o conjunto (abaixo do limite do conector) —
não altera configuração de papel nem de banco.
Termina em ROLLBACK.
================================================================
*/
begin isolation level repeatable read read only;
set local statement_timeout = '100s';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000058e1","role":"authenticated"}', true);

do $e$
declare
  c_reps constant int := 3;
  v_all uuid[];
  v_batch uuid[];
  v_n int; v_b int; v_rep int;
  t0 timestamptz; v_ms numeric; v_rows int; v_err text;
  v_out jsonb := '[]'::jsonb;
begin
  select array_agg(id order by id) into v_all from (select distinct card_variant_id as id from public.physical_card) s;
  v_n := coalesce(cardinality(v_all), 0);
  execute 'set local role authenticated';
  for v_rep in 1..c_reps loop
    v_b := 0;
    while v_b * 100 < v_n loop
      v_batch := v_all[v_b * 100 + 1 : least((v_b + 1) * 100, v_n)];
      v_err := null; v_rows := null;
      t0 := clock_timestamp();
      begin
        select count(*) into v_rows from public.get_card_variants_pricing_summary(v_batch);
      exception when others then v_err := sqlstate;
      end;
      v_ms := round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
      v_out := v_out || jsonb_build_object('rep', v_rep, 'lote', v_b + 1, 'ids', cardinality(v_batch), 'linhas', v_rows, 'ms', v_ms, 'erro', v_err);
      v_b := v_b + 1;
    end loop;
  end loop;
  execute 'reset role';
  perform set_config('mmkyu.e_out', v_out::text, true);
  perform set_config('mmkyu.e_n', v_n::text, true);
end
$e$;

with r as (
  select (x->>'rep')::int as rep, (x->>'lote')::int as lote, (x->>'ids')::int as ids,
         (x->>'linhas')::int as linhas, (x->>'ms')::numeric as ms, x->>'erro' as erro
    from jsonb_array_elements(current_setting('mmkyu.e_out')::jsonb) x
)
select current_setting('mmkyu.e_n')::int as variantes,
       count(*) as chamadas,
       count(*) filter (where erro is not null) as chamadas_com_erro,
       string_agg(distinct erro, ',') as sqlstates,
       count(*) filter (where linhas is distinct from ids) as linhas_divergentes_de_ids,
       min(ms) as ms_min, round(avg(ms), 1) as ms_media,
       percentile_cont(0.5) within group (order by ms) as ms_mediana,
       percentile_cont(0.95) within group (order by ms) as ms_p95,
       max(ms) as ms_max,
       round(stddev_samp(ms), 1) as ms_desvio,
       (select string_agg(format('rep %s: %s ms', rep, s), ' | ' order by rep)
          from (select rep, sum(ms) as s from r group by rep) t) as total_por_repeticao,
       (select string_agg(format('L%s=%s/%s/%s', lote, a, b, c), ' ' order by lote)
          from (select lote,
                       max(ms) filter (where rep = 1) as a, max(ms) filter (where rep = 2) as b, max(ms) filter (where rep = 3) as c
                  from r group by lote) t) as ms_por_lote_rep1_2_3,
       case when count(*) filter (where erro is not null) = 0 and max(ms) < 8000 then 'PASS' else 'FAIL' end as status
  from r;
rollback;
