/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2152 - Add is_active to Card Variant Type
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Adiciona public.card_variant_type.is_active — primeiro passo do
Incremento 1 de governança da Taxonomia de Card Variant Type
(ADR-028). Mesmo padrão aditivo/retrocompatível da Query 2020
(is_active em card), com uma diferença deliberada de semântica,
aprovada por Fabrício:

Diferente de Card (ADR-023, "soft delete real e irrestrito", onde
is_active governa se a linha aparece nas consultas operacionais),
aqui is_active governa APENAS a disponibilidade do tipo para NOVOS
cadastros/mappings. Um Card Variant Type inativo:
- permanece válido e visível para toda card_variant já criada com
  ele (nenhuma leitura existente muda de comportamento);
- permanece válido para todo card_variant_type_external_mapping já
  criado com ele;
- só deixa de aparecer como opção em telas futuras de seleção
  (Cadastro → Tipos de Variação, Resolver Mapeamento) — ajuste que
  pertence à camada de leitura de um incremento futuro, não a esta
  Query.

Regras de Negócio:
- NOT NULL DEFAULT true: os 13 tipos canônicos já cadastrados
  (Query 850) tornam-se ativos automaticamente, sem backfill
  separado.
- Nenhuma cascata: esta Query não toca card_variant nem
  card_variant_type_external_mapping.
- Nenhum índice criado: volume atual (13 linhas para o único Game
  hoje) não justifica — mesmo raciocínio da Query 2020.
- V1 desta governança NÃO inclui exclusão física de
  card_variant_type (decisão explícita de Fabrício: taxonomia
  canônica preserva histórico) — is_active é o único mecanismo de
  remoção "suave" previsto.

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
================================================================
*/

ALTER TABLE public.card_variant_type
    ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.card_variant_type.is_active IS
    'Governa a disponibilidade do tipo para NOVOS cadastros/mappings (ADR-028, Incremento 1). '
    'true = disponível. Um tipo inativo permanece válido para card_variant/card_variant_type_external_mapping já existentes — histórico nunca é afetado. Sem exclusão física nesta versão.';

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK.
-- Pós-execução: 13/13 tipos existentes (seed Query 850) com
-- is_active = true, sem backfill manual necessário; 0 linhas de teste
-- remanescentes.
-- ================================================================
