/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2119 - Create Card Front Storage Admin Policies
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria duas políticas em storage.objects (INSERT e DELETE) restritas a
bucket_id = 'card-front' AND is_admin() — mesma técnica da Query 276
(card-set-logo), mas com o conjunto reduzido ao mínimo privilégio
real exigido pelo fluxo Manual via UI (ajuste de Fabrício,
2026-08-07): o navegador só precisa (1) subir um arquivo novo, em
path sempre único (nunca reaproveita um path existente — ver ADR-026,
emenda "Segundo ponto de entrada via UI") e (2) remover um arquivo
(rollback do que acabou de subir, se a persistência em card_asset
falhar, OU o arquivo antigo, só depois de confirmada a troca do
ponteiro). Nenhum SELECT ou UPDATE autenticado é necessário: a
checagem de "Card já tem imagem" usa o manifesto vindo de
public.card_asset (consulta normal, sem tocar em storage.objects), e
nenhuma sobrescrita in-place ocorre (sempre INSERT em path novo,
nunca UPDATE do mesmo objeto).

Motivação: novo canal de importação manual de imagens via UI
(ADR-026, emenda "Segundo ponto de entrada via UI") — o upload passa
a ocorrer direto do navegador (sessão do próprio admin) para
card-front, em vez de exclusivamente via Service Role Key (Edge
Function import-card-assets e o script scripts/import-manual-
assets.ts, que continuam funcionando exatamente como hoje, sem
qualquer dependência destas políticas). Antes desta Query,
confirmado por consulta a pg_policies (2026-08-07, zero linhas) que
card-front não tinha nenhuma política dedicada em storage.objects —
só os buckets privados (card-set-logo/expansion-logo/avatars) tinham.

Regras de Negócio:
- card-front é público (public.storage_bucket.is_public = TRUE,
  Query 895) — a leitura anônima via getPublicUrl() NÃO passa por
  RLS, é um mecanismo do Supabase Storage independente destas
  políticas. As duas políticas abaixo só passam a valer para chamadas
  autenticadas via API (upload/remove com JWT de usuário) — nunca
  afetam a URL pública já em uso hoje por toda a galeria de cartas.
- Duas políticas distintas, nunca uma única FOR ALL — mesma técnica
  da Query 276.
- Sem SELECT nem UPDATE: menor privilégio real do fluxo (ver
  Descrição acima). Se uma necessidade futura concreta aparecer
  (ex.: listar objetos autenticado para uma auditoria de órfãos),
  isso é uma nova migration pequena — ADD CONSTRAINT/CREATE POLICY é
  aditivo, não há custo em adiar até existir uso real.
- Sem exceção por idioma/Card Set/Coleção: qualquer administrador
  pode gravar/remover em qualquer caminho dentro de card-front, mesmo
  nível de confiança já implícito em quem tem is_admin() = true no
  resto do Catálogo Editorial (ADR-023).

Pré-requisitos:
- Bucket card-front já existente (Query 895 - Seed Storage Bucket;
  criado fisicamente antes deste ciclo de documentação).
- Função public.is_admin() (Query 1060).
================================================================
*/

BEGIN;

CREATE POLICY card_front_admin_insert ON storage.objects
    FOR INSERT
    WITH CHECK (bucket_id = 'card-front' AND is_admin());

CREATE POLICY card_front_admin_delete ON storage.objects
    FOR DELETE
    USING (bucket_id = 'card-front' AND is_admin());

COMMIT;

-- ================================================================
-- Resultado esperado: "Success. No rows returned" (CREATE POLICY não
-- devolve linhas).
--
-- Como validar (rodar depois, confirma as 2 políticas físicas):
-- SELECT policyname, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'storage'
--   AND tablename = 'objects'
--   AND policyname LIKE 'card_front_admin_%'
-- ORDER BY policyname;
--
-- Esperado: 2 linhas (card_front_admin_delete/insert), cada uma com
-- qual/with_check = ((bucket_id = 'card-front'::text) AND
-- is_admin()).
-- ================================================================
--
-- CONFIRMADO EXECUTADO (2026-08-07): pg_policies devolveu as 2
-- linhas esperadas, qual/with_check exatamente conforme acima.
-- ================================================================
