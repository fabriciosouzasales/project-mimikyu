/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5358 - Evolução da completude (R2-F, B1): fotografias, cobertura
              por coleção, execuções, rotina interna de captura e leitura do
              titular
Versão......: 0.2 (R2-F B1 SQL CORRECTION-05: identidade gravada nas DUAS
              configurações que auth.uid() pode ler e conferida antes da 5188;
              janela conferida por coleção; contadores só no sucesso da
              subtransação; contador de coleções não alcançadas pela janela)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-11-08
              (R2-F B1 — P0 PASS / EXECUÇÃO CONTROLADA, autorização expressa de
              Fabrício; ledger 20261108160502, apply_migration em transação
              única). Texto aplicado = arquivo integral de database/proposals/
              2026-11-08-r2f-completion-history/
              5358_create_collection_completion_history_PROPOSAL.sql (md5
              06ac07b933d1571a699632ec4d88bca1); este arquivo difere dele só
              neste bloco Status. Corpos no LIVE (prosrc) conferidos em
              2026-11-08 iguais aos deste arquivo: capture_collection_completion
              md5 827139f6dfad0549c0ffd505b120e2b8; get_my_collection_completion_
              history md5 1cfb2bff78014099c283862a7e720062. Validação: P0 e
              A1–A4 PASS (5886 v0.2). Operação noturna: N1/N2 pendentes.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-08

Contrato: D7 v1.63 §4n (D1–D12), alternativa C mínima.

Autoridade da completude: public.collection_completion_summary() v6.0 (5188)
— a rotina CHAMA a 5188; não copia nem altera a regra (nenhuma terceira
implementação; 5188/5310 intocadas).

Objetos (todos novos):
  public.collection_completion_capture_run   execuções (operacional, 400 dias)
  public.collection_completion_snapshot      fotografias (uma por mudança)
  public.collection_completion_coverage      cobertura por coleção (intervalos)
  internal.capture_collection_completion(p_dry_run boolean default false)
                                             rotina interna (cron, 5359)
  public.get_my_collection_completion_history(p_collection_id uuid)
                                             leitura do titular

Regras implementadas (D3–D8):
  - Dia de referência D = dia civil anterior em America/Sao_Paulo; válido só
    se a leitura começar antes de 03h00 locais (D4). Fora da janela: registra
    a execução como OUTSIDE_WINDOW e não grava fechamento.
  - Execuções simultâneas: trava consultiva da transação; a segunda vira
    SKIPPED_CONCURRENT.
  - Janela por coleção: antes de cada coleção a hora local é conferida de
    novo; passou de 03h00 (ou virou outro dia), a rotina para, a coleção e as
    seguintes ficam sem cobertura em D (late_count) e a execução é PARTIAL.
  - Identidade: o repositório não guarda a definição de auth.uid() (schema
    auth é do Supabase) e usa as duas formas de simulação em validações
    anteriores — request.jwt.claim.sub (ADR-027, 05e) e request.jwt.claims
    (migrations 2252/2276/3975). A rotina grava o titular NAS DUAS e, antes de
    chamar a 5188, confere auth.uid() = titular (R2F_IDENTITY_MISMATCH se não).
    O P0 (5886) registra a definição vigente; o A2 prova na prática.
  - Contadores: cada coleção termina em exatamente um destes —
    processed (subtransação concluída), skipped (dia já coberto), failed
    (subtransação desfeita) ou late (não alcançada pela janela);
    expected = processed + skipped + failed + late. written conta fotografias
    gravadas em subtransações concluídas.
  - Por coleção (Set padrão e Master Set com referência de Card Set — o mesmo
    alvo da 5188), numa SUBTRANSAÇÃO: dia já coberto → ignorada (idempotente);
    identidade do titular só nesta subtransação → 5188 → identidade limpa;
    resultado conferido (uma linha, mesma coleção, mesma modalidade);
    cobertura: contínua (fim = D−1) estende; senão abre intervalo novo
    (início ou retomada após lacuna — D6); fotografia gravada se abriu
    intervalo OU se mudou total, satisfeitas, percentual, modalidade, Card
    Set, acabamentos (Master Set) ou situação (D5). Falha → a subtransação
    desfaz tudo daquela coleção (inclusive a identidade) e ela fica sem
    cobertura em D (lacuna honesta); as outras seguem.
  - Cobertura comprovada só pela própria coleção (D6); a execução global não
    prova cobertura.
  - p_dry_run = true: mesmo percurso (identidade + 5188 + conferências), sem
    nenhuma escrita e sem a janela; para validação em transação READ ONLY.

Segurança:
  - Tabelas em public com RLS ligada e SEM política; REVOKE ALL de PUBLIC,
    anon, authenticated e service_role (os padrões do Supabase concedem;
    precedente 5267). Nenhum acesso direto de cliente.
  - Rotina em internal (STD-001 §9: só funções; schema sem USAGE para
    clientes); SECURITY DEFINER, search_path ''; EXECUTE revogado de todos os
    papéis cliente. Só o dono (postgres, via pg_cron) executa.
  - Leitura do titular: auth.uid() obrigatório (28000); 22023 para argumento
    nulo; coleção alheia/compartilhada/inexistente → P0002 neutro (padrão
    5252/5357); EXECUTE só authenticated.

Desempenho: uma chamada da 5188 por coleção (Set/Master), uma vez por dia,
fora do horário de uso; leitura de duas tabelas pequenas por chave. Nenhum
gatilho nas operações de coleção.
================================================================
*/

-- ---------------------------------------------------------------------------
-- 1. Estruturas
-- ---------------------------------------------------------------------------

create table public.collection_completion_capture_run (
  id                  uuid        primary key default gen_random_uuid(),
  reference_day       date        not null,
  started_at          timestamptz not null default clock_timestamp(),
  finished_at         timestamptz null,
  status              text        not null,
  expected_count      integer     not null default 0,
  processed_count     integer     not null default 0,
  written_count       integer     not null default 0,
  skipped_count       integer     not null default 0,
  failed_count        integer     not null default 0,
  late_count          integer     not null default 0,
  last_error_sqlstate text        null,
  constraint chk_cc_capture_run_status check (status in ('RUNNING', 'COMPLETED', 'PARTIAL', 'FAILED', 'OUTSIDE_WINDOW', 'SKIPPED_CONCURRENT')),
  constraint chk_cc_capture_run_counts check (expected_count >= 0 and processed_count >= 0 and written_count >= 0
                                               and skipped_count >= 0 and failed_count >= 0 and late_count >= 0
                                               and written_count <= processed_count),
  constraint chk_cc_capture_run_balance check (status not in ('COMPLETED', 'PARTIAL', 'FAILED')
                                               or expected_count = processed_count + skipped_count + failed_count + late_count),
  constraint chk_cc_capture_run_finished check (finished_at is null or finished_at >= started_at)
);

create index ix_cc_capture_run_day on public.collection_completion_capture_run (reference_day, started_at);

comment on table public.collection_completion_capture_run is
  'R2-F (5358): execuções da captura diária da completude (registro operacional, 400 dias). NÃO prova cobertura de coleção — ver collection_completion_coverage.';

create table public.collection_completion_snapshot (
  collection_id       uuid        not null references public.collection(id) on update restrict on delete cascade,
  reference_day       date        not null,
  captured_at         timestamptz not null,
  run_id              uuid        null references public.collection_completion_capture_run(id) on update restrict on delete set null,
  completion_policy   text        not null,
  card_set_id         uuid        not null,
  finish_type_ids     uuid[]      null,
  lifecycle_status    text        not null,
  total_positions     bigint      not null,
  satisfied_positions bigint      not null,
  progress_percentage numeric     not null,
  opens_coverage      boolean     not null,
  constraint pk_collection_completion_snapshot primary key (collection_id, reference_day),
  constraint chk_cc_snapshot_policy check (completion_policy in ('STANDARD_SET', 'MASTER_SET')),
  constraint chk_cc_snapshot_finishes check ((completion_policy = 'MASTER_SET') = (finish_type_ids is not null)),
  constraint chk_cc_snapshot_counts check (total_positions >= 0 and satisfied_positions >= 0 and satisfied_positions <= total_positions)
);

comment on table public.collection_completion_snapshot is
  'R2-F (5358): fotografia da completude devolvida pela 5188 no fechamento do dia de referência; gravada só quando algo muda ou quando a cobertura (re)começa (D5/D6).';

create table public.collection_completion_coverage (
  collection_id uuid not null references public.collection(id) on update restrict on delete cascade,
  covered_from  date not null,
  covered_to    date not null,
  constraint pk_collection_completion_coverage primary key (collection_id, covered_from),
  constraint chk_cc_coverage_range check (covered_to >= covered_from)
);

create index ix_cc_coverage_collection_to on public.collection_completion_coverage (collection_id, covered_to desc);

comment on table public.collection_completion_coverage is
  'R2-F (5358): dias de fechamento comprovados por coleção, em intervalos contínuos. Dia fora de todo intervalo = lacuna (D6).';

alter table public.collection_completion_capture_run enable row level security;
alter table public.collection_completion_snapshot    enable row level security;
alter table public.collection_completion_coverage    enable row level security;

revoke all on table public.collection_completion_capture_run from public, anon, authenticated, service_role;
revoke all on table public.collection_completion_snapshot    from public, anon, authenticated, service_role;
revoke all on table public.collection_completion_coverage    from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Rotina interna de captura
-- ---------------------------------------------------------------------------

create or replace function internal.capture_collection_completion(p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_local      timestamp := (clock_timestamp() at time zone 'America/Sao_Paulo');
  v_day        date      := (clock_timestamp() at time zone 'America/Sao_Paulo')::date - 1;
  v_run        uuid;
  v_expected   integer := 0;
  v_processed  integer := 0;
  v_written    integer := 0;
  v_skipped    integer := 0;
  v_failed     integer := 0;
  v_late       integer := 0;
  v_last_state text;
  v_status     text;
  v_started    timestamptz := clock_timestamp();
  v_now_local  timestamp;
  c            record;
  s            record;
  v_cov_from   date;
  v_cov_to     date;
  v_has_cov    boolean;
  v_last       record;
  v_has_last   boolean;
  v_finishes   uuid[];
  v_opens      boolean;
  v_wrote      boolean;
  v_outcome    text;
begin
  if not p_dry_run then
    if v_local::time >= time '03:00' then
      insert into public.collection_completion_capture_run (reference_day, status, finished_at)
      values (v_day, 'OUTSIDE_WINDOW', clock_timestamp())
      returning id into v_run;
      return jsonb_build_object('status', 'OUTSIDE_WINDOW', 'reference_day', v_day, 'local_time', v_local, 'run_id', v_run);
    end if;
    if not pg_try_advisory_xact_lock(hashtext('mmkyu.r2f.collection_completion_capture')) then
      insert into public.collection_completion_capture_run (reference_day, status, finished_at)
      values (v_day, 'SKIPPED_CONCURRENT', clock_timestamp())
      returning id into v_run;
      return jsonb_build_object('status', 'SKIPPED_CONCURRENT', 'reference_day', v_day, 'run_id', v_run);
    end if;
    -- Retenção operacional (400 dias). Fotografias guardam run_id anulável.
    delete from public.collection_completion_capture_run r where r.started_at < clock_timestamp() - interval '400 days';
    insert into public.collection_completion_capture_run (reference_day, status)
    values (v_day, 'RUNNING')
    returning id into v_run;
  end if;

  -- Mesmo alvo da 5188: coleções REFERENCE_BASED de Set padrão ou Master Set com Card Set.
  select count(*) into v_expected
  from public.collection col
  join public.collection_reference cr            on cr.collection_id = col.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where col.mode = 'REFERENCE_BASED'
    and col.completion_policy in ('STANDARD_SET', 'MASTER_SET');

  for c in
    select col.id, col.owner_user_id, col.completion_policy, col.lifecycle_status, ccsr.card_set_id
    from public.collection col
    join public.collection_reference cr            on cr.collection_id = col.id
    join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
    where col.mode = 'REFERENCE_BASED'
      and col.completion_policy in ('STANDARD_SET', 'MASTER_SET')
    order by col.id
  loop
    -- Janela conferida por coleção (D4): a leitura desta coleção só começa
    -- antes de 03h00 de D+1. Depois disso, nada mais ganha cobertura em D.
    if not p_dry_run then
      v_now_local := (clock_timestamp() at time zone 'America/Sao_Paulo');
      if v_now_local::date <> v_day + 1 or v_now_local::time >= time '03:00' then
        exit;
      end if;
    end if;

    v_outcome := null;
    v_wrote := false;
    begin
      -- Idempotência (D4): dia já coberto para esta coleção.
      if not p_dry_run and exists (
           select 1 from public.collection_completion_coverage k
           where k.collection_id = c.id and v_day between k.covered_from and k.covered_to) then
        v_outcome := 'skipped';
      else
        -- Identidade do titular SÓ nesta subtransação (D12), nas duas
        -- configurações que auth.uid() pode ler; conferida antes da 5188.
        perform set_config('request.jwt.claim.sub', c.owner_user_id::text, true);
        perform set_config('request.jwt.claims', json_build_object('sub', c.owner_user_id, 'role', 'authenticated')::text, true);
        if (select auth.uid()) is distinct from c.owner_user_id then
          raise exception using errcode = 'P0001', message = 'R2F_IDENTITY_MISMATCH';
        end if;
        select r.collection_id, r.completion_policy, r.total_positions, r.satisfied_positions, r.progress_percentage
          into s
        from public.collection_completion_summary(c.id) r;
        if not found or s.collection_id is distinct from c.id or s.completion_policy is distinct from c.completion_policy
           or s.total_positions is null or s.satisfied_positions is null or s.progress_percentage is null then
          raise exception using errcode = 'P0001', message = 'R2F_SUMMARY_MISMATCH';
        end if;
        perform set_config('request.jwt.claims', '', true);
        perform set_config('request.jwt.claim.sub', '', true);

        v_finishes := case when c.completion_policy = 'MASTER_SET'
                           then array(select f.variant_type_id from public.collection_master_set_finish f
                                      where f.collection_id = c.id order by f.variant_type_id)
                      end;

        if not p_dry_run then
          -- Cobertura (D6): contínua estende; senão abre intervalo (início ou retomada).
          select k.covered_from, k.covered_to into v_cov_from, v_cov_to
          from public.collection_completion_coverage k
          where k.collection_id = c.id
          order by k.covered_to desc
          limit 1;
          v_has_cov := found;
          v_opens := not v_has_cov or v_cov_to <> v_day - 1;
          if v_opens then
            insert into public.collection_completion_coverage (collection_id, covered_from, covered_to)
            values (c.id, v_day, v_day);
          else
            update public.collection_completion_coverage k
            set covered_to = v_day
            where k.collection_id = c.id and k.covered_from = v_cov_from;
          end if;

          -- Fotografia (D5/D6): ao abrir intervalo, sempre; senão só se mudou algo.
          select l.completion_policy, l.card_set_id, l.finish_type_ids, l.lifecycle_status,
                 l.total_positions, l.satisfied_positions, l.progress_percentage
            into v_last
          from public.collection_completion_snapshot l
          where l.collection_id = c.id
          order by l.reference_day desc
          limit 1;
          v_has_last := found;
          if v_opens or not v_has_last
             or v_last.total_positions     is distinct from s.total_positions
             or v_last.satisfied_positions is distinct from s.satisfied_positions
             or v_last.progress_percentage is distinct from s.progress_percentage
             or v_last.completion_policy   is distinct from c.completion_policy
             or v_last.card_set_id         is distinct from c.card_set_id
             or v_last.finish_type_ids     is distinct from v_finishes
             or v_last.lifecycle_status    is distinct from c.lifecycle_status then
            insert into public.collection_completion_snapshot (
              collection_id, reference_day, captured_at, run_id, completion_policy, card_set_id, finish_type_ids,
              lifecycle_status, total_positions, satisfied_positions, progress_percentage, opens_coverage)
            values (
              c.id, v_day, clock_timestamp(), v_run, c.completion_policy, c.card_set_id, v_finishes,
              c.lifecycle_status, s.total_positions, s.satisfied_positions, s.progress_percentage, v_opens);
            v_wrote := true;
          end if;
        end if;
        v_outcome := 'processed';
      end if;
    exception when others then
      -- A subtransação desfez cobertura, fotografia e identidade desta coleção.
      v_outcome := 'failed';
      v_wrote := false;
      v_last_state := sqlstate;
    end;

    -- Contadores só depois do desfecho da subtransação (nada contado em dobro).
    if v_outcome = 'processed' then
      v_processed := v_processed + 1;
      if v_wrote then v_written := v_written + 1; end if;
    elsif v_outcome = 'skipped' then
      v_skipped := v_skipped + 1;
    else
      v_failed := v_failed + 1;
    end if;
  end loop;

  -- Coleções não alcançadas (janela encerrada no meio da execução).
  v_late := v_expected - v_processed - v_skipped - v_failed;

  -- Garantia final de identidade limpa.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  v_status := case when v_failed = 0 and v_late = 0 then 'COMPLETED'
                   when v_processed + v_skipped > 0 then 'PARTIAL'
                   else 'FAILED' end;
  if not p_dry_run then
    update public.collection_completion_capture_run r
    set finished_at = clock_timestamp(), status = v_status, expected_count = v_expected, processed_count = v_processed,
        written_count = v_written, skipped_count = v_skipped, failed_count = v_failed, late_count = v_late,
        last_error_sqlstate = v_last_state
    where r.id = v_run;
  end if;

  return jsonb_build_object(
    'status', v_status,
    'dry_run', p_dry_run,
    'reference_day', v_day,
    'run_id', v_run,
    'expected', v_expected,
    'processed', v_processed,
    'written', v_written,
    'skipped', v_skipped,
    'failed', v_failed,
    'late', v_late,
    'last_error_sqlstate', v_last_state,
    'identity_clear', coalesce(current_setting('request.jwt.claims', true), '') = ''
                      and coalesce(current_setting('request.jwt.claim.sub', true), '') = '',
    'ms', round(extract(epoch from (clock_timestamp() - v_started)) * 1000));
end;
$$;

revoke all on function internal.capture_collection_completion(boolean) from public, anon, authenticated, service_role;

comment on function internal.capture_collection_completion(boolean) is
  'R2-F (5358): fechamento diário da completude (D7 §4n). Chama a 5188 com a identidade do titular restrita à subtransação de cada coleção. Interna: só o dono (pg_cron) executa. p_dry_run = percurso completo sem escrita (validação).';

-- ---------------------------------------------------------------------------
-- 3. Leitura do titular
-- ---------------------------------------------------------------------------

create or replace function public.get_my_collection_completion_history(p_collection_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  -- Fronteira de autorização antes de qualquer outra tabela.
  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'tracking_since',   (select min(k.covered_from) from public.collection_completion_coverage k where k.collection_id = p_collection_id),
    'last_covered_day', (select max(k.covered_to)   from public.collection_completion_coverage k where k.collection_id = p_collection_id),
    'coverage', coalesce((
      select jsonb_agg(jsonb_build_object('from', k.covered_from, 'to', k.covered_to) order by k.covered_from)
      from public.collection_completion_coverage k
      where k.collection_id = p_collection_id), '[]'::jsonb),
    'snapshots', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', l.reference_day,
               'captured_at', l.captured_at,
               'completion_policy', l.completion_policy,
               'card_set_id', l.card_set_id,
               'finish_type_ids', l.finish_type_ids,
               'lifecycle_status', l.lifecycle_status,
               'total', l.total_positions,
               'satisfied', l.satisfied_positions,
               'progress', l.progress_percentage,
               'opens_coverage', l.opens_coverage) order by l.reference_day)
      from public.collection_completion_snapshot l
      where l.collection_id = p_collection_id), '[]'::jsonb));
end;
$$;

revoke all on function public.get_my_collection_completion_history(uuid) from public;
revoke all on function public.get_my_collection_completion_history(uuid) from anon;
grant execute on function public.get_my_collection_completion_history(uuid) to authenticated;

comment on function public.get_my_collection_completion_history(uuid) is
  'R2-F (5358): histórico da completude da coleção do titular — início do acompanhamento, intervalos de cobertura e fotografias (D7 §4n). Exige auth.uid(); coleção alheia/inexistente → P0002 sem enumerar. Somente leitura.';
