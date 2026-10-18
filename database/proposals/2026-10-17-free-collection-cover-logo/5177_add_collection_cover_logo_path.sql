/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5177 - collection.cover_logo_path: imagem da placa da
              Coleção livre (FREE-COLLECTION-COVER-LOGO-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018001008; 5833 v1.2 25/25 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Coluna nova, NULL = sem imagem (a placa mostra o nome da coleção, como
hoje). Só aparência: não entra em identidade, progresso, alocação ou
local; compatível com validate_collection_structural_identity (5032, só
imutáveis de identidade).

Formato verificado por CHECK (defesa em profundidade; a validação de dono
e de existência do arquivo é de 5178, única via de escrita):
  <uuid do dono>/<uuid da coleção>/<uuid>.(png|jpg|webp)

Leitura: pela política existente `collection_select_own` (5030) — o
frontend lê a coluna da própria coleção; R1 (5168/5173) não muda.
Escrita direta: `authenticated` não tem UPDATE em public.collection (só
SELECT, 5030) — a coluna só muda por 5178.

Como validar: Query 5833 (Seção 2).
Como reverter: alter table public.collection drop column cover_logo_path.
================================================================
*/

begin;

alter table public.collection
  add column cover_logo_path text null;

alter table public.collection
  add constraint chk_collection_cover_logo_path
  check (
    cover_logo_path is null
    or cover_logo_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$'
  );

comment on column public.collection.cover_logo_path is
  'Imagem da placa do fichário (Coleção livre), no bucket privado collection-cover. NULL = placa tipográfica. Só muda por set_my_collection_cover_logo (5178).';

commit;
