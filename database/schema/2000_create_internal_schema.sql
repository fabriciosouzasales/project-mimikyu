/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2000 - Create Internal Schema
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria o schema internal, destinado exclusivamente a rotinas de
persistência reutilizáveis do módulo Catálogo Editorial — Escrita
e Ingestão (ADR-023, ADR-024). Formalizado em STD-001 v1.17,
Seção 9 ("Schema internal — Rotinas Não Expostas pela API").

A primeira rotina a residir aqui será internal.write_card()
(Query 2030), reutilizada pelas funções administrativas públicas
de Card e pela futura confirmação em lote de importação
(ADR-024).

Regras de Negócio:
- O schema internal nunca deve conter tabelas ou views — apenas
  funções SECURITY DEFINER (STD-001 §9).
- O schema internal nunca deve ser adicionado à lista de schemas
  expostos pela API do Supabase (Studio → Settings → API →
  Exposed schemas). Esta é uma configuração de plataforma, não
  um objeto do banco, e não pode ser verificada por SQL — deve
  ser confirmada manualmente por Fabrício.
- USAGE do schema é revogado explicitamente de PUBLIC, anon e
  authenticated. Schemas novos não recebem USAGE automático de
  PUBLIC por padrão no PostgreSQL (esse comportamento padrão só
  se aplica ao schema public); a revogação aqui é uma medida
  defensiva e documental, não uma correção de um grant que
  existiria por padrão.
- EXECUTE sobre cada função futura deste schema é revogado
  individualmente na própria Query de criação da função — mesmo
  padrão já usado em public.is_admin() (Query 1060) e
  public.admin_set_card_set_logo() (Query 275). Não se usa
  ALTER DEFAULT PRIVILEGES aqui, para manter o mesmo estilo
  explícito e auditável já estabelecido no repositório.
- Funções internas são chamadas apenas por outras funções
  SECURITY DEFINER do mesmo owner (as funções públicas
  administrativas de ADR-023) — o owner tem USAGE/EXECUTE
  implícito sobre seus próprios objetos, sem necessidade de GRANT
  adicional para chamadas internal-to-internal.

Pré-requisitos:
- Nenhum. Primeira Query do módulo Catálogo Editorial — Escrita e
  Ingestão (ADR-023 / ADR-024; STD-001 v1.17, Seção 10, milhar
  2000–2999).
================================================================
*/

CREATE SCHEMA internal;

COMMENT ON SCHEMA internal IS
    'Rotinas de persistência internas do Catálogo Editorial (ADR-023/ADR-024). '
    'Nunca exposto pela API do Supabase. Contém apenas funções SECURITY DEFINER, '
    'nunca tabelas ou views (STD-001 v1.17, Seção 9).';

REVOKE ALL ON SCHEMA internal FROM PUBLIC;
REVOKE ALL ON SCHEMA internal FROM anon;
REVOKE ALL ON SCHEMA internal FROM authenticated;
