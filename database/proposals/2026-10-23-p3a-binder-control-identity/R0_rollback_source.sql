-- P3-A — R0: reversão das 5244–5246. NÃO EXECUTAR sem autorização expressa de Fabrício.
-- Ordem inversa. As três migrations só CRIAM objetos novos (nenhuma função existente é substituída),
-- então não há definição original a restaurar. O frontend já trata a ausência das funções
-- (PGRST202 → nome da coleção + logomarca, edição indisponível).

-- 5246
drop function if exists public.get_my_binder_participants(uuid);

-- 5245
drop function if exists public.get_my_binder_occupancy(uuid);
drop function if exists public.get_my_binder_identity(uuid);
drop function if exists public.set_my_binder_identity(uuid, text, boolean);

-- 5244 — ATENÇÃO: apaga os nomes próprios e a escolha de logomarca já gravados.
-- Antes, se houver dados: select collection_id, display_name, show_brand_mark from public.collection_layout
--   where display_name is not null or not show_brand_mark;  (guardar o resultado)
alter table public.collection_layout drop constraint if exists chk_collection_layout_display_name_format;
alter table public.collection_layout drop column if exists show_brand_mark;
alter table public.collection_layout drop column if exists display_name;

-- Ledger: remover as linhas 5244/5245/5246 de supabase_migrations.schema_migrations só se a reversão for definitiva.
