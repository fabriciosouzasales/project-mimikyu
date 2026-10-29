/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: R0_rollback_s1.sql — reversão da P3-B S1 (5267–5270)
Versão......: 1.1 (2026-10-25, P3-B-S1-SECURITY-CORRECTION-01: W2)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização expressa de Fabrício.

Remove APENAS os objetos criados pela S1. Nenhuma tabela ou função existente
antes da S1 é tocada; nenhum estado do fichário (bolsos, reservas, páginas,
coleções, exemplares) depende destes objetos. NÃO toca o ledger.

----------------------------------------------------------------
1. Estados possíveis antes da reversão (W2)
----------------------------------------------------------------
Cada migration 5267–5270 é atômica (begin … commit): ou entra inteira, com sua
linha no ledger, ou não deixa nada. Por isso só existem estes estados:

  NONE      nenhuma das 4 aplicada. Nada a reverter; R0 é no-op seguro.
  PARTIAL   prefixo aplicado (5267; 5267–5268; 5267–5269) e a seguinte
            falhou. Objetos presentes = os das migrations com linha no ledger.
  COMPLETE  as 4 aplicadas.
  ANOMALY   objetos sem linha correspondente no ledger, linha sem objetos,
            ou fora de prefixo (ex.: 5269 sem 5268). Indica intervenção
            externa → R0 recusa e PARA (seção do precheck abaixo).

  Objetos por migration (o precheck confere exatamente estes):
    5267  4 tabelas, sequência da identidade (própria da tabela de eventos),
          2 funções de guarda, 4 gatilhos
    5268  binder_activity_begin / _add_item / _end
    5269  binder_activity_category, get_my_binder_activity,
          get_my_binder_activity_coverage, list_my_closed_binder_histories
    5270  purge_my_binder_activity + linhas LEGADO (dados em tabela da 5267)

----------------------------------------------------------------
2. Efeito da reversão sobre os objetos
----------------------------------------------------------------
  · DROP … IF EXISTS em todos os 14 objetos: funciona igual em PARTIAL e
    COMPLETE. DROP TABLE leva junto gatilhos, índices, constraints e a
    sequência da identidade (OWNED BY); não dispara gatilhos de linha nem de
    TRUNCATE, então a imutabilidade não bloqueia a reversão.
  · Os dados do histórico somem por inteiro (eventos, itens, marcos). Antes
    da S2 o único conteúdo é o legado L01 (cópia de uma linha da
    collection_layout_catalog_incorporation, que continua intacta na 5263).
  · Pós-condição verificada: zero objetos binder_activity_* no schema public.

----------------------------------------------------------------
3. Ledger (supabase_migrations.schema_migrations) — política
----------------------------------------------------------------
  · R0 NÃO altera, apaga nem reescreve linhas do ledger. As linhas de
    5267–5270 que foram gravadas continuam lá: o ledger é registro do que foi
    aplicado, não do estado atual.
  · Para o ledger refletir a reversão, R0 deve ser aplicado pelo MESMO
    mecanismo das migrations, com NÚMERO NOVO (o próximo livre no ledger no
    dia, nome `NNNN_revert_binder_activity_s1`). Assim o ledger mostra
    "5267–5270 aplicadas, NNNN reverteu" sem apagar nada.
  · Reaplicar com a MESMA numeração é impossível por política e bloqueado
    por verificação: LIVE_00 (00.3) recusa se 5267–5270 já existem no ledger,
    e duas linhas com o mesmo nome destruiriam a rastreabilidade.
  · Migration que FALHOU (rollback da própria transação) não grava linha:
    seu número não foi consumido. Pode ser reexecutada com o mesmo número
    somente se a falha foi ambiental (timeout, lock) e o arquivo não mudou;
    qualquer mudança de conteúdo exige nova auditoria do arquivo antes.
  · Intervenção direta no ledger (DELETE/UPDATE em schema_migrations) só com
    autorização específica e escrita de Fabrício para aquele caso — nunca
    como parte de R0, nunca para "liberar" numeração.

----------------------------------------------------------------
4. Correção para frente (forward fix) — condições
----------------------------------------------------------------
  Depois de R0, a S1 só volta por correção para frente, com todas:
  (a) R0 aplicado por completo (pós-condição OK) e registrado no ledger com
      número próprio;
  (b) causa raiz identificada e documentada (README + docs/log.md);
  (c) arquivos corrigidos renumerados acima do número do R0 (nova faixa
      livre conferida no ledger e em database/), cabeçalhos citando as
      versões substituídas;
  (d) LIVE_00 atualizado para o novo último ledger esperado e para a nova
      faixa;
  (e) verificação estática PASS e nova auditoria independente;
  (f) G8 reaberto por Fabrício para a nova faixa.

Pré-condição de segurança: nenhuma função fora da S1 pode referenciar estes
objetos. Na S1 isso é verdade por construção (G4). A partir da S2, a reversão
desta fatia exige antes a reversão das fatias que instrumentaram funções
homologadas — o precheck abaixo recusa a execução nesse caso.
================================================================
*/
begin;

do $pre$
declare
  v_refs   text;
  v_ledger text[];
  v_has    boolean[];
  v_state  text;
begin
  -- (i) dependência de fatias posteriores
  select string_agg(p.oid::regprocedure::text, ', ')
    into v_refs
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end',
                          'binder_activity_category','get_my_binder_activity','get_my_binder_activity_coverage',
                          'list_my_closed_binder_histories','purge_my_binder_activity',
                          'binder_activity_event_guard','binder_activity_item_guard')
    and pg_get_functiondef(p.oid) ~* 'binder_activity_(begin|add_item|end|event|item|coverage|setting)';
  if v_refs is not null then
    raise exception 'R0 S1: há funções fora da S1 usando o histórico (%). Reverta as fatias S2–S6 antes.', v_refs;
  end if;

  -- (ii) classificação do estado: ledger × objetos (só leitura do ledger)
  select array_agg(substr(m.name, 1, 4) order by m.name) into v_ledger
  from supabase_migrations.schema_migrations m where m.name ~ '^(5267|5268|5269|5270)_';
  v_ledger := coalesce(v_ledger, '{}');
  v_has := array[
    to_regclass('public.binder_activity_event') is not null,
    to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is not null,
    to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)') is not null,
    to_regprocedure('public.purge_my_binder_activity(uuid, uuid)') is not null];

  if v_has[1] <> ('5267' = any (v_ledger)) or v_has[2] <> ('5268' = any (v_ledger))
     or v_has[3] <> ('5269' = any (v_ledger)) or v_has[4] <> ('5270' = any (v_ledger))
     or (v_has[2] and not v_has[1]) or (v_has[3] and not v_has[2]) or (v_has[4] and not v_has[3]) then
    raise exception 'R0 S1: ANOMALY — ledger % não corresponde aos objetos presentes %. PARAR e reportar; não intervir no ledger.',
      v_ledger, v_has;
  end if;
  v_state := case when not v_has[1] then 'NONE' when v_has[4] then 'COMPLETE' else 'PARTIAL' end;
  raise notice 'R0 S1: estado % (ledger %). O ledger não será alterado.', v_state, v_ledger;
end;
$pre$;

drop function if exists public.purge_my_binder_activity(uuid, uuid);
drop function if exists public.list_my_closed_binder_histories(integer);
drop function if exists public.get_my_binder_activity_coverage(uuid);
drop function if exists public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer);
drop function if exists public.binder_activity_category(text);
drop function if exists public.binder_activity_end();
drop function if exists public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb);
drop function if exists public.binder_activity_begin(uuid, text, text, uuid, jsonb);

drop table if exists public.binder_activity_item;
drop table if exists public.binder_activity_event;
drop table if exists public.binder_activity_coverage;
drop table if exists public.binder_activity_setting;

drop function if exists public.binder_activity_item_guard();
drop function if exists public.binder_activity_event_guard();

do $post$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname like 'binder_activity%')
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname like '%binder_activity%') then
    raise exception 'R0 S1: reversão incompleta';
  end if;
end;
$post$;

commit;
