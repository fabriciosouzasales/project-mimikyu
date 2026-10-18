/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5176 - Bucket `collection-cover` + políticas por dono
              (FREE-COLLECTION-COVER-LOGO-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018000947; 5833 v1.2 25/25 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Objetivo: guardar a imagem que o colecionador envia para a placa do
fichário de uma Coleção livre (decisão de Fabrício, 2026-10-17: "imagem
enviada pelo usuário").

Decisões:
  - Bucket PRIVADO (diferente de `avatars`, que é público): a capa é dado
    da coleção, que é privada. Leitura só pelo dono, via URL assinada.
  - 1 MB por arquivo; só image/png, image/jpeg, image/webp (o banco do
    Storage recusa o resto antes de gravar).
  - Pasta obrigatória: `<auth.uid()>/<collection_id>/<arquivo>`. As quatro
    políticas exigem a primeira pasta = auth.uid(); ninguém lê, grava,
    troca ou apaga arquivo de outra pessoa. Vincular o arquivo a uma
    coleção é papel de 5178, que confere a segunda pasta e o dono da
    coleção.
  - Mesmo padrão de `1040_create_avatars_bucket.sql` (políticas em
    storage.objects por `storage.foldername(name)`), sem `anon`.

Idempotente no bucket (ON CONFLICT DO NOTHING). As políticas usam nomes
novos; reexecutar exige DROP POLICY antes (registrado em "Como reverter").

Como validar: Query 5833 (Seção 1).
Como reverter: drop das 4 políticas `collection_cover_*` e
  `delete from storage.buckets where id = 'collection-cover'` (só com o
  bucket vazio).
================================================================
*/

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('collection-cover', 'collection-cover', false, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

create policy collection_cover_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'collection-cover'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy collection_cover_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'collection-cover'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy collection_cover_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'collection-cover'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'collection-cover'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy collection_cover_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'collection-cover'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

commit;
