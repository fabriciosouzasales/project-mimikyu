/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5244 - Identidade do Fichário: colunas em collection_layout
              display_name    text     null   — nome próprio do fichário
              show_brand_mark boolean  true   — exibir a logomarca na contracapa
Versão......: 1.0 (2026-10-23, P3A-BINDER-CONTROL-IDENTITY-IMPLEMENTATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. Nenhum SQL desta pasta foi
              aplicado no LIVE. Aplicação só com autorização expressa de
              Fabrício, uma migration por vez (ver README §11).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Decisões (README §2 e §12):
  - O nome pertence ao FICHÁRIO (collection_layout), não à coleção (R1).
  - NULL = sem nome próprio; a leitura usa o nome da coleção proprietária
    (P3: fallback de leitura, nunca gravado — sem cópia no banco).
  - show_brand_mark NOT NULL DEFAULT true (R6). ADD COLUMN com default
    constante não reescreve a tabela (PG ≥ 11) — linhas existentes leem
    true sem UPDATE.
  - Formato canônico garantido também por CHECK (defesa em profundidade:
    a RPC 5245 normaliza; o CHECK recusa qualquer outro caminho):
      1..60 caracteres, sem espaço nas pontas, sem caractere de controle
      (inclui quebra de linha e tab), sem espaços repetidos.
  - Sem índice: nenhuma busca por nome; leitura sempre pela PK/UNIQUE.
  - Sem grant novo: a tabela já recusa DML do cliente (5105 §9); a escrita
    só acontece pela RPC SECURITY DEFINER da 5245.

Efeitos colaterais conhecidos:
  - trg_collection_layout_updated_at (5106) bumpa updated_at quando a
    identidade muda; nenhum token do Fichário depende de
    collection_layout.updated_at (conferido em 5223–5243).
  - trg_collection_layout_grid_immutability (5107) só reage a mudança de
    grid; não é afetado.
  - Desmontagem (5226/5236/5242) apaga a linha inteira: nome e flag somem
    com o fichário. Nenhuma mudança necessária.

Nada aqui toca cartas, alocações, reservas, travas, regiões, imagens,
páginas ou progresso.
Dependências: 5105, 5106, 5107.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout') is null then
    raise exception 'PRECHECK 5244: collection_layout ausente';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'collection_layout'
               and column_name in ('display_name', 'show_brand_mark')) then
    raise exception 'PRECHECK 5244: colunas de identidade já existem';
  end if;
end;
$pre$;

alter table public.collection_layout
  add column display_name    text    null,
  add column show_brand_mark boolean not null default true;

alter table public.collection_layout
  add constraint chk_collection_layout_display_name_format
  check (
    display_name is null
    or (
      char_length(display_name) between 1 and 60
      and display_name = btrim(display_name)
      and display_name !~ '[[:cntrl:]]'
      and display_name !~ '\s\s'
    )
  );

comment on column public.collection_layout.display_name is
  'P3-A (5244): nome próprio do fichário, independente das coleções vinculadas. NULL = usar o nome da coleção proprietária (fallback de leitura, nunca gravado). 1..60, sem controle, sem espaços nas pontas nem repetidos. Escrita só por set_my_binder_identity (5245), só pela proprietária.';
comment on column public.collection_layout.show_brand_mark is
  'P3-A (5244): exibir a logomarca MMKYU (asset interno) na contracapa. Compartilhado por todas as coleções do fichário; editado só pela proprietária.';

commit;

/*
Resultado esperado: 2 colunas novas, 1 CHECK novo, 0 linhas alteradas.

Como validar (só leitura):
select
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name='collection_layout'
      and column_name in ('display_name','show_brand_mark'))                    as colunas,   -- 2
  (select count(*) from pg_constraint
    where conrelid='public.collection_layout'::regclass
      and conname='chk_collection_layout_display_name_format')                  as checks,    -- 1
  (select count(*) from public.collection_layout where display_name is not null) as com_nome,  -- 0
  (select count(*) from public.collection_layout where show_brand_mark is not true) as sem_logo; -- 0
*/
