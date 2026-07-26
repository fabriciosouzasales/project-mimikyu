/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1840 - Validate avatars bucket
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Validação do bucket "avatars": configuração (público, MIME,
tamanho máximo) e as quatro políticas de storage.objects
esperadas, todas filtrando bucket_id = 'avatars'.
================================================================
*/

SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets WHERE id = 'avatars';

SELECT policyname, cmd, roles
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'avatars_%'
ORDER BY policyname;
