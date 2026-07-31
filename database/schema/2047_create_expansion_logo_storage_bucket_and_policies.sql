/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2047 - Create Expansion Logo Storage Bucket and Policies
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Cria o bucket privado expansion-logo (destino de logo_storage_path,
Query 2045) e quatro políticas separadas em storage.objects — SELECT,
INSERT, UPDATE e DELETE — cada uma restrita a administradores via
is_admin(). Mesmo padrão de card-set-logo (Query 276, ADR-022):
Catálogo Editorial é admin-only, logo incluído. Leitura ocorre via URL
assinada (createSignedUrl), nunca getPublicUrl(). Bucket não é
registrado na tabela storage_bucket (mesmo padrão de card-set-logo/
avatars — bucket module-owned, fora do catálogo multi-bucket de
card_asset).

Regras de Negócio:
- Bucket expansion-logo é privado (public = false).
- Quatro políticas distintas em storage.objects, nunca uma única FOR ALL
  — cada uma checando bucket_id = 'expansion-logo' AND is_admin().
- Não há política de acesso público nem de usuário comum — só admin.
================================================================
*/

begin;

insert into storage.buckets (id, name, public)
values ('expansion-logo', 'expansion-logo', false)
on conflict (id) do nothing;

create policy expansion_logo_admin_select on storage.objects
    for select
    using (bucket_id = 'expansion-logo' and is_admin());

create policy expansion_logo_admin_insert on storage.objects
    for insert
    with check (bucket_id = 'expansion-logo' and is_admin());

create policy expansion_logo_admin_update on storage.objects
    for update
    using (bucket_id = 'expansion-logo' and is_admin())
    with check (bucket_id = 'expansion-logo' and is_admin());

create policy expansion_logo_admin_delete on storage.objects
    for delete
    using (bucket_id = 'expansion-logo' and is_admin());

commit;

-- ================================================================
-- Validação: aguardando execução por Fabrício. Sugestão de roteiro:
-- - storage.buckets: expansion-logo, public = false.
-- - pg_policies: as quatro políticas presentes em storage.objects, cada
--   uma com qual/with_check = ((bucket_id = 'expansion-logo') AND
--   is_admin()).
-- - public.storage_bucket: nenhum registro com code = 'expansion-logo'
--   (bucket intencionalmente fora do catálogo, mesmo padrão de
--   card-set-logo/avatars).
-- ================================================================
