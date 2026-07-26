/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1040 - Create avatars bucket and storage policies
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria o bucket "avatars" (Supabase Storage) e as políticas de
storage.objects que o governam: leitura pública, escrita restrita
à própria pasta do usuário (<uid>/<arquivo>).

Regras de Negócio:
- MIME aceitos: image/png, image/jpeg, image/webp. Tamanho máximo:
  2 MB (2097152 bytes).
- Toda política filtra bucket_id = 'avatars' explicitamente —
  storage.objects é compartilhada entre todos os buckets do
  projeto, então uma política sem esse filtro vazaria para
  outros buckets (ex.: o de assets do catálogo editorial).
- Caminho: <user_id>/<uuid>.<ext> — cada upload gera nome novo
  (cache busting automático). INSERT/UPDATE/DELETE checam que o
  primeiro segmento do path é o próprio auth.uid().
- UPDATE define USING e WITH CHECK idênticos.
================================================================
*/

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 2097152, ARRAY['image/png', 'image/jpeg', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY avatars_public_read
    ON storage.objects
    FOR SELECT
    USING (bucket_id = 'avatars');

CREATE POLICY avatars_insert_own_folder
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY avatars_update_own_folder
    ON storage.objects
    FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    )
    WITH CHECK (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY avatars_delete_own_folder
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
