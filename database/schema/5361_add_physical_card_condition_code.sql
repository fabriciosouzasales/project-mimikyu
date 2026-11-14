/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5361 - physical_card.condition_code (V1-16 · S1)
Versão......: 1.1 (2026-11-13, `S1 EXECUTION FAILURE DIAGNOSIS-01`)
Status......: CANÔNICA (forma 1.1) — NÃO EXECUTADA nesta forma. Promovida em
              2026-11-13 (`PR-01 | CANONICAL RECONCILIATION IMPLEMENTATION-01`),
              texto idêntico a database/proposals/2026-11-13-v1-16-card-condition/ no
              commit b51dcc4, exceto este bloco Status. O que foi APLICADO no LIVE
              mimikyu-core em 2026-11-13 foi a v1.0, pelo SQL Editor: DDL e comentário
              persistidos, postcheck não executado (42P01; caso D2 — protocolo §11). A v1.0
              não foi versionada; evidência parcial (7 comandos de pg_stat_statements,
              md5 do banco) em .../pr01-evidence/5361-v1.0-pg-stat-statements/. Coluna,
              FK e comentário no LIVE iguais aos desta forma (G1, leitura). Equivalência
              de DDL não é identidade textual; reconstrução limpa a partir desta forma
              NÃO comprovada. SEM registro no ledger supabase_migrations.
Correção 1.1: a 1.0 criava uma tabela temporária ON COMMIT DROP numa
              instrução de topo e a lia em OUTRA (o DO $post$), o que exige
              mesma sessão E mesma transação aberta entre instruções. O
              canal não garantiu isso: no $post$ a tabela já não existia.
              Logo, as instruções anteriores ao $post$ (ALTER/COMMENT) podem
              ter sido comitadas isoladamente, sem postcheck, e o SET LOCAL
              pode não ter tido efeito. Na 1.1 a etapa inteira é UMA
              instrução de topo (um único DO): precheck, baseline em
              variáveis, DDL, comentário e postcheck. Um DO é atômico em
              qualquer canal (exceção em qualquer ponto desfaz tudo) e não
              deixa transação explícita aberta em caso de erro. Sem
              BEGIN/COMMIT externos e sem tabela temporária. lock_timeout
              passa a set_config(..., true) dentro do DO (só a transação da
              própria instrução). statement_timeout não pode ser armado de
              dentro da instrução em curso e foi retirado; o único passo de
              duração variável é o VALIDATE (varredura proporcional a
              physical_card, S0-14). Prechecks, baseline, padrão NM, FK
              (NOT VALID → VALIDATE), comentário e postchecks: os da 1.0.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-13
Contrato....: concept-decisions C-227–C-233 (C-108 substituída por C-228);
              05d v3.01, seção "Condição física por exemplar (V1-16)".
Objetivo....: Toda Physical Card passa a ter condição física obrigatória,
              padrão 'NM', referenciando a escala canônica
              card_condition(code). Exemplares existentes recebem 'NM'
              (classificação inicial presumida, C-230).

Comportamento no PostgreSQL (>= 11)
  ADD COLUMN ... NOT NULL DEFAULT 'NM' com padrão CONSTANTE é só de
  catálogo ("fast default"): nenhuma linha é reescrita, nenhum gatilho
  dispara (updated_at, quantidades, alocações, local, bolsos e histórico
  intocados). Exige ACCESS EXCLUSIVE breve em physical_card — por isso
  lock_timeout curto: com transação longa em curso a etapa FALHA em vez
  de enfileirar o resto do sistema. A FK nasce NOT VALID (sem varredura)
  e é validada em seguida, na mesma transação (a tabela é pequena; a
  varredura lê o padrão virtual 'NM').
  Sem índice em condition_code: a FK só é consultada no lado
  referenciado (card_condition, 6 linhas, RESTRICT, administrativo).

Pré-condições (fail-closed, mensagens distintas)
  - card_condition com exatamente M, NM, LP, MP, HP, DMG, ordem 1..6, e
    uq_card_condition_code presente (alvo da FK);
  - physical_card SEM coluna condition_code e SEM a FK:
      * coluna + FK idênticas ao desejado -> 'PRECHECK 5361: JÁ APLICADA'
      * qualquer estado parcial           -> 'PRECHECK 5361: ESTADO DIVERGENTE'
    Reaplicação nunca é silenciosa.

Resultado esperado: coluna text NOT NULL DEFAULT 'NM', FK validada,
  100% das linhas = 'NM', contagens de physical_card,
  collection_allocation e exemplares com local iguais às de antes
  (postcheck interno compara e aborta se divergirem).
Como validar: harness 5887, grupo A; e
  select count(*) filter (where condition_code <> 'NM') from public.physical_card;  -- 0
Recuperação (só ANTES de qualquer edição real de condição, isto é,
  antes de 5364 entrar em uso):
  alter table public.physical_card drop constraint fk_physical_card_condition_code;
  alter table public.physical_card drop column condition_code;
  Depois de edições reais, desfazer apaga condições declaradas —
  exige decisão explícita do proprietário.
================================================================
*/

do $s1$
declare
  v_codes   text;
  v_col     record;
  v_fk      record;
  b_pc      bigint;
  b_alloc   bigint;
  b_storage bigint;
  b_max     public.physical_card.updated_at%type;
begin
  -- Só para a transação desta instrução (não altera a sessão).
  perform set_config('lock_timeout', '5s', true);

  -- ---------------------------------------------------------------
  -- PRECHECK (idêntico à 1.0)
  -- ---------------------------------------------------------------
  -- Escala canônica (C-105): exatamente seis códigos, ordem 1..6.
  select string_agg(code || ':' || condition_order, ',' order by condition_order)
    into v_codes
    from public.card_condition;
  if v_codes is distinct from 'M:1,NM:2,LP:3,MP:4,HP:5,DMG:6' then
    raise exception 'PRECHECK 5361: escala card_condition diverge do contrato C-105 (encontrado: %)', v_codes;
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.card_condition'::regclass
                    and conname = 'uq_card_condition_code' and contype = 'u') then
    raise exception 'PRECHECK 5361: uq_card_condition_code ausente (alvo da FK)';
  end if;

  select a.attname, format_type(a.atttypid, a.atttypmod) as typ, a.attnotnull,
         pg_get_expr(ad.adbin, ad.adrelid) as def
    into v_col
    from pg_attribute a
    left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
   where a.attrelid = 'public.physical_card'::regclass
     and a.attname = 'condition_code' and not a.attisdropped;

  select c.conname, c.convalidated, pg_get_constraintdef(c.oid) as def
    into v_fk
    from pg_constraint c
   where c.conrelid = 'public.physical_card'::regclass
     and c.conname = 'fk_physical_card_condition_code';

  if v_col.attname is not null or v_fk.conname is not null then
    if v_col.typ = 'text' and v_col.attnotnull and v_col.def = '''NM''::text'
       and v_fk.convalidated
       and replace(v_fk.def, 'public.', '') = 'FOREIGN KEY (condition_code) REFERENCES card_condition(code) ON UPDATE RESTRICT ON DELETE RESTRICT' then
      raise exception 'PRECHECK 5361: JÁ APLICADA — nada a fazer (não reaplicar)';
    end if;
    raise exception 'PRECHECK 5361: ESTADO DIVERGENTE — coluna=% tipo=% notnull=% default=% fk=% validada=% def=%',
      v_col.attname, v_col.typ, v_col.attnotnull, v_col.def, v_fk.conname, v_fk.convalidated, v_fk.def;
  end if;

  -- ---------------------------------------------------------------
  -- BASELINE em variáveis (na 1.0: tabela temporária _v116_s1_before)
  -- ---------------------------------------------------------------
  select (select count(*) from public.physical_card),
         (select count(*) from public.collection_allocation),
         (select count(*) from public.physical_card where storage_container_id is not null),
         (select max(updated_at) from public.physical_card)
    into b_pc, b_alloc, b_storage, b_max;

  -- ---------------------------------------------------------------
  -- DDL (idêntico à 1.0)
  -- ---------------------------------------------------------------
  alter table public.physical_card
    add column condition_code text not null default 'NM';

  alter table public.physical_card
    add constraint fk_physical_card_condition_code
    foreign key (condition_code) references public.card_condition(code)
    on update restrict on delete restrict
    not valid;

  alter table public.physical_card
    validate constraint fk_physical_card_condition_code;

  comment on column public.physical_card.condition_code is
    'V1-16 (C-227–C-233): condição física corrente do exemplar — código canônico de card_condition (M, NM, LP, MP, HP, DMG). Obrigatória, padrão NM (C-228). Exemplares anteriores a 5361 = NM como classificação inicial presumida, não inspecionada (C-230). Rótulos exibidos (SP para LP, DM para DMG) são só da interface (C-229).';

  -- ---------------------------------------------------------------
  -- POSTCHECK (idêntico à 1.0; qualquer exceção desfaz a instrução inteira)
  -- ---------------------------------------------------------------
  if (select count(*) from public.physical_card) <> b_pc
     or (select count(*) from public.collection_allocation) <> b_alloc
     or (select count(*) from public.physical_card where storage_container_id is not null) <> b_storage
     or (select max(updated_at) from public.physical_card) is distinct from b_max then
    raise exception 'POSTCHECK 5361: contagens ou updated_at mudaram — abortar';
  end if;
  if exists (select 1 from public.physical_card where condition_code is distinct from 'NM') then
    raise exception 'POSTCHECK 5361: há exemplar sem NM depois da inicialização';
  end if;
  if not (select convalidated from pg_constraint
           where conrelid = 'public.physical_card'::regclass
             and conname = 'fk_physical_card_condition_code') then
    raise exception 'POSTCHECK 5361: FK não validada';
  end if;
end;
$s1$;

-- Como validar (depois de a instrução concluir sem erro):
-- select count(*) as total,
--        count(*) filter (where condition_code = 'NM')  as nm,
--        count(*) filter (where condition_code <> 'NM') as outros   -- 0
--   from public.physical_card;
