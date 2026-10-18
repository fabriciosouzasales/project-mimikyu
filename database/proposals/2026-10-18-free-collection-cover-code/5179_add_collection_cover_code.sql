/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5179 - collection.cover_code: Código opcional da Coleção
              livre (FREE-COLLECTION-COVER-CODE-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018005335; 5834 v1.0 21/21 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18

Decisão de origem (Fabrício, 2026-10-18): a Coleção livre pode ter um
Código, como o código do Set no foil da capa. OPCIONAL; 2 a 6 letras ou
números (maiúsculas); não precisa ser único; definido na criação e
editável depois.

Coluna nova, NULL = sem código (a capa continua como hoje). Só aparência:
não entra em identidade, progresso, alocação nem local; compatível com
validate_collection_structural_identity (5032, só imutáveis de identidade).

CHECK de formato (defesa em profundidade; a normalização — trim e
maiúsculas — é de 5180, única via de escrita):
  ^[A-Z0-9]{2,6}$
Sem UNIQUE (decisão: dois fichários podem ter o mesmo código).

Leitura: pela política existente `collection_select_own` (5030).
Escrita direta: `authenticated` só tem SELECT em public.collection (5030).

Como validar: Query 5834 (Seção 0 e 3.x).
Como reverter: alter table public.collection drop column cover_code.
================================================================
*/

begin;

alter table public.collection
  add column if not exists cover_code text null;

alter table public.collection
  add constraint chk_collection_cover_code
  check (cover_code is null or cover_code ~ '^[A-Z0-9]{2,6}$');

comment on column public.collection.cover_code is
  'Código opcional da Coleção livre (2–6 letras/números, maiúsculas), mostrado no foil da capa. Só via set_my_collection_cover_code (5180). Query 5179.';

commit;
