/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 276 - Create Card Set Logo Storage Bucket and Policies
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria o bucket privado card-set-logo (destino de logo_storage_path, Query
273) e quatro políticas separadas em storage.objects — SELECT, INSERT,
UPDATE e DELETE — cada uma restrita a administradores via is_admin().
Diverge deliberadamente do padrão de bucket público já usado por
card-front/artwork/card-back/avatars, por decisão de Fabrício (ADR-022):
Catálogo Editorial é admin-only, logo incluído. Leitura ocorre via URL
assinada (createSignedUrl), nunca getPublicUrl(). Bucket não é registrado
na tabela storage_bucket (mesmo padrão de avatars — bucket module-owned,
fora do catálogo multi-bucket de card_asset).

Regras de Negócio:
- Bucket card-set-logo é privado (public = false).
- Quatro políticas distintas em storage.objects, nunca uma única FOR ALL
  (ajuste 2 de Fabrício) — cada uma checando bucket_id = 'card-set-logo'
  AND is_admin().
- Não há política de acesso público nem de usuário comum — só admin.
================================================================
*/

begin;

insert into storage.buckets (id, name, public)
values ('card-set-logo', 'card-set-logo', false)
on conflict (id) do nothing;

create policy card_set_logo_admin_select on storage.objects
    for select
    using (bucket_id = 'card-set-logo' and is_admin());

create policy card_set_logo_admin_insert on storage.objects
    for insert
    with check (bucket_id = 'card-set-logo' and is_admin());

create policy card_set_logo_admin_update on storage.objects
    for update
    using (bucket_id = 'card-set-logo' and is_admin())
    with check (bucket_id = 'card-set-logo' and is_admin());

create policy card_set_logo_admin_delete on storage.objects
    for delete
    using (bucket_id = 'card-set-logo' and is_admin());

commit;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
-- - storage.buckets: card-set-logo, public = false.
-- - pg_policies: as quatro políticas presentes em storage.objects, cada uma
--   com qual/with_check = ((bucket_id = 'card-set-logo') AND is_admin()).
-- - public.storage_bucket: nenhum registro com code = 'card-set-logo'
--   (bucket intencionalmente fora do catálogo, mesmo padrão de avatars).
-- ================================================================
