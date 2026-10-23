/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5237 - Corrige a recursão RLS da política INSERT do bucket
              `binder-slot-image` (5231)
              (P2-BINDER-IMAGE-UPLOAD-RLS-FIX-01)
Versão......: 1.2 (2026-10-23, CORRECTION-02: removida a exigência de vínculo com o dono
              de storage.objects; BYPASSRLS preservado)
              1.1 (2026-10-23, CORRECTION-01: função sem argumentos, teto 550 fixo
              dentro dela)
              1.0 (2026-10-23)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-BINDER-IMAGE-UPLOAD-RLS-FIX-LIVE-APPLY-01, autorização expressa de
              Fabrício; ledger 20261023202009 `5237_fix_binder_slot_image_insert_policy_recursion`).
              Do `begin;` ao `commit;` byte a byte idêntica ao arquivo da pasta
              database/proposals/2026-10-23-p2-binder-image-upload-rls-fix/ (só este
              bloco Status difere); enviada via apply_migration sem as linhas
              `begin;`/`commit;` externas e sem os comentários `--` (o SQL
              executável é o mesmo). POST-1 8/8 PASS; POST-2 = PRE-5; Advisor só
              0029 esperado. Prova funcional F1–F6 PASS (2026-10-23); F7 (opcional,
              concorrência) NÃO EXECUTADA; harness 5852 NÃO EXECUTADO.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Causa (evidência — logs do LIVE, 2026-10-23 19:46:23 UTC):
  POST /storage/v1/object/binder-slot-image/<uid>/<layout>/<uuid>.webp → 400
  Postgres: infinite recursion detected in policy for relation "objects".
  A política `binder_slot_image_insert_own` (5231) contém
      (select count(*) from storage.objects o where ...) < 550
  Uma política de storage.objects que consulta storage.objects sob RLS
  dispara a expansão recursiva das políticas da própria tabela; o Postgres
  recusa. Resultado: TODO envio ao bucket falha (nenhum arquivo criado).

Correção (mínima, só a contagem):
  1. Função auxiliar `public.binder_slot_image_under_object_cap()` (sem
     argumentos; teto de 550 arquivos FIXO dentro dela):
     SECURITY DEFINER (dono `postgres`, com BYPASSRLS — a leitura interna de
     storage.objects não passa pelas políticas, logo não recorre),
     search_path vazio, STABLE. Conta SÓ os arquivos do próprio usuário
     autenticado (`auth.uid()` lido dentro da função; nenhum parâmetro de
     usuário, pasta ou caminho) e devolve apenas um booleano.
     Sem sessão → false (fail-closed).
  2. ALTER POLICY da mesma política, trocando só a subconsulta pela chamada
     `public.binder_slot_image_under_object_cap()`. Bucket, pasta = auth.uid()
     e formato canônico do nome continuam no texto da política; o teto 550
     passa a viver só na função (o literal 550 sai do texto da política —
     checagens antigas `with_check like '%550%'` deixam de valer; ver README).
     ALTER POLICY é atômico: não há janela sem política.

Não muda: políticas SELECT e DELETE (sem autorreferência — a DELETE usa
`binder_slot_image_path_is_linked`, que lê public.collection_layout_slot_image),
bucket, limites de tamanho/tipo, tabela de imagens, RPCs 5233/5234, limite de
500 imagens vinculadas (5233), bolsos, cartas, reservas.

Segurança:
  - a função não recebe argumento algum (nem usuário, nem caminho, nem
    limite): não revela nada de terceiros; no máximo, o próprio usuário
    descobre se tem menos de 550 arquivos na própria pasta (informação que
    ele já lê pela política SELECT);
  - EXECUTE só para `authenticated` (a política é avaliada com o papel do
    chamador, que precisa poder chamá-la); revogado de PUBLIC e anon;
  - nenhuma permissão nova de escrita; nenhuma política nova.
Desempenho: contagem por bucket + prefixo da pasta (índice do Storage em
bucket_id + name); no máximo ~550 linhas do próprio usuário. Uma chamada por
envio.
Concorrência: idêntica à 5231 (contagem sem trava; o teto pode ser
excedido por poucos arquivos sob envios simultâneos — aceito, folga de 50).

Como validar: LIVE_90_postcheck_readonly.sql desta pasta (POST-1…POST-4) e,
com autorização própria, a prova funcional F1–F7 (RUNBOOK-LIVE da 5231–5236).
Como reverter (não recomendado — volta a bloquear todo envio):
  alter policy binder_slot_image_insert_own on storage.objects with check (<texto da 5231>);
  drop function public.binder_slot_image_under_object_cap();
================================================================
*/

begin;

do $pre$
declare
  v_check text;
begin
  -- Dependências: pacote 5231–5236 aplicado.
  if not exists (select 1 from storage.buckets b where b.id = 'binder-slot-image') then
    raise exception 'PRECHECK 5237: bucket binder-slot-image ausente (aplique 5231 antes)';
  end if;
  if to_regprocedure('public.list_my_unlinked_binder_slot_images(integer)') is null then
    raise exception 'PRECHECK 5237: pacote 5231–5236 incompleto (5234 ausente)';
  end if;
  -- Ainda não aplicada.
  if to_regprocedure('public.binder_slot_image_under_object_cap()') is not null then
    raise exception 'PRECHECK 5237: função binder_slot_image_under_object_cap já existe';
  end if;
  -- A política a corrigir é exatamente a da 5231 (com a subconsulta autorreferente).
  select p.with_check into v_check
  from pg_policies p
  where p.schemaname = 'storage' and p.tablename = 'objects'
    and p.policyname = 'binder_slot_image_insert_own' and p.cmd = 'INSERT';
  if v_check is null then
    raise exception 'PRECHECK 5237: política binder_slot_image_insert_own ausente';
  end if;
  if v_check not like '%count(%' or v_check not like '%storage.objects%' or v_check not like '%550%' then
    raise exception 'PRECHECK 5237: texto da política difere do esperado (5231) — conferir antes';
  end if;
  -- O dono da função precisa ler storage.objects sem passar pelas políticas.
  if not exists (select 1 from pg_roles r where r.rolname = current_user and (r.rolbypassrls or r.rolsuper)) then
    raise exception 'PRECHECK 5237: % sem BYPASSRLS — a função voltaria a recorrer', current_user;
  end if;
  -- Sem checagem de dono de storage.objects: no Supabase o `postgres` não é membro de
  -- `supabase_storage_admin` e, ainda assim, criou as políticas binder_slot_image_*
  -- (5231/5232) e collection_cover_*. Isso é EVIDÊNCIA DE COMPATIBILIDADE, não prova de
  -- autorização para ALTER POLICY: se o ALTER for recusado, a transação inteira desfaz
  -- (nada muda) e o erro é reportado. Nenhuma concessão de privilégio é feita aqui.
end;
$pre$;

-- 1. Contagem fora da política (sem recursão) --------------------------------------------
create function public.binder_slot_image_under_object_cap()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and (select count(*)
          from storage.objects o
          where o.bucket_id = 'binder-slot-image'
            and o.name like (select auth.uid())::text || '/%') < 550;
$$;

comment on function public.binder_slot_image_under_object_cap() is
  'Fichário Digital (5237): true se o usuário autenticado tem menos de 550 arquivos na PRÓPRIA pasta do bucket binder-slot-image. Usada pela política INSERT do bucket (teto 550) no lugar da subconsulta autorreferente da 5231, que causava recursão RLS. Só booleano; sem sessão = false.';

revoke all on function public.binder_slot_image_under_object_cap() from public, anon;
grant execute on function public.binder_slot_image_under_object_cap() to authenticated;

-- 2. Mesma política, mesma regra, sem autorreferência -------------------------------------
alter policy binder_slot_image_insert_own
  on storage.objects
  with check (
    bucket_id = 'binder-slot-image'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|jpg)$'
    and public.binder_slot_image_under_object_cap()
  );

-- 3. Pós-condição na mesma transação (fail-loud) -------------------------------------------
do $post$
declare
  v_check text;
  v_roles name[];
begin
  select p.with_check, p.roles into v_check, v_roles
  from pg_policies p
  where p.schemaname = 'storage' and p.tablename = 'objects'
    and p.policyname = 'binder_slot_image_insert_own' and p.cmd = 'INSERT';
  if v_check is null
     or v_check like '%storage.objects%'
     or v_check like '%count(%'
     or v_check not like '%binder_slot_image_under_object_cap()%'
     or v_check not like '%binder-slot-image%'
     or v_check not like '%foldername%'
     or v_check not like '%auth.uid()%'
     or v_roles <> array['authenticated']::name[] then
    raise exception 'POSTCHECK 5237: política INSERT não ficou como esperado: % / %', v_roles, v_check;
  end if;
  if has_function_privilege('anon', 'public.binder_slot_image_under_object_cap()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.binder_slot_image_under_object_cap()', 'EXECUTE') then
    raise exception 'POSTCHECK 5237: privilégios da função fora do esperado';
  end if;
end;
$post$;

commit;
