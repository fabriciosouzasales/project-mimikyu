/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5181 - collection.library_position: ordem escolhida pelo
              colecionador na Biblioteca (LIBRARY-ORDER-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018012416; 5835 v1.0 22/22 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18

Decisão de origem (Fabrício, 2026-10-18): a ordem das coleções em
"Minhas coleções" deixa de depender da data de criação; o colecionador
reordena arrastando e soltando (Cards e Lista). Coleção nova entra NO
INÍCIO.

Coluna nova, NULL = "ainda sem lugar escolhido". R1 (5182) ordena por
`library_position NULLS FIRST, created_at DESC`: sem nenhuma reordenação a
Biblioteca fica exatamente como hoje (mais nova primeiro), e toda coleção
criada depois de uma reordenação aparece no início — sem tocar nos
contratos de criação (5034/5167/5175) e sem gatilho. A primeira
reordenação (5183) numera todas as coleções do dono 1..n.

Só apresentação: não entra em identidade, progresso, alocação nem local;
compatível com validate_collection_structural_identity (5032).
Sem UNIQUE: a numeração é mantida por 5183 (única via de escrita) sob
trava das linhas do dono; o CHECK impede valores sem sentido.
Sem índice novo: a ordenação é por dono (índice existente em
owner_user_id) e a cardinalidade por colecionador é pequena.

Escrita direta: `authenticated` só tem SELECT em public.collection (5030).
Como validar: Query 5835.
Como reverter: alter table public.collection drop column library_position
               (antes, recriar R1 pela 5173).
================================================================
*/

begin;

alter table public.collection
  add column if not exists library_position integer null;

alter table public.collection
  add constraint chk_collection_library_position
  check (library_position is null or library_position >= 1);

comment on column public.collection.library_position is
  'Ordem escolhida pelo colecionador na Biblioteca (1 = primeiro). NULL = ainda sem lugar: aparece antes das posicionadas, mais nova primeiro. Só via move_my_collection (5183). Query 5181.';

commit;
