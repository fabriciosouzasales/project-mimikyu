/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5171 - collection.cover_finish: cor (acabamento) do fichário
              (MY-COLLECTIONS-LIBRARY-VISUAL-02)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 (ledger 20261017191204); validado por 5831 v1.2
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Objetivo:
A cor do fichário faz parte da identidade da coleção e é escolhida pelo
colecionador. Coluna opcional: nula = a interface usa o padrão estável
derivado do id da coleção (web/lib/colecoes/binder-finish.ts), então
nenhum backfill é necessário e nada muda para coleções existentes.

Vocabulário fechado (CHECK) espelhado em BINDER_FINISHES no frontend;
mudar um exige mudar o outro.
Paleta aprovada por Fabrício em 2026-10-17 (decisão K12, North Star NS-16):
onix, vinho, floresta, marinho, caramelo, perola. Ampliar exige nova decisão.

Escrita: só pela 5172 (a tabela continua sem UPDATE para clientes).
Resultado esperado: coluna nova, nula em todas as linhas.
Como validar: Query 5831 (Seção 1).
================================================================
*/

begin;

alter table public.collection
  add column cover_finish text null;

alter table public.collection
  add constraint chk_collection_cover_finish
  check (cover_finish is null or cover_finish in ('onix', 'vinho', 'floresta', 'marinho', 'caramelo', 'perola'));

comment on column public.collection.cover_finish is
  'Cor do fichário escolhida pelo colecionador (Query 5171). Nula = padrão estável calculado na interface.';

commit;
