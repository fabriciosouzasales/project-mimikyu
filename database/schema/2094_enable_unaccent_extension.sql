/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2094 - Enable unaccent Extension
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Habilita a extensão `unaccent` (schema `extensions`, padrão do
Supabase), base de `normalize_external_catalog_value()` (Query
2095) — cadastro self-service de Raridade (ADR-024, emenda
"Raridade: mapeamento self-service e revalidação"). Sem esta
extensão, a normalização de valores externos (ex. "Rara Holo" vs
"RARA HOLO" vs "Rara Holó") ficaria restrita a maiúsculas/
minúsculas e espaços, sem remover acentos.

Regras de Negócio:
- Instalada no schema `extensions` (convenção do Supabase — nunca
  `public`, evita colisão de nomes com objetos da aplicação).
- Idempotente (`IF NOT EXISTS`) — segura para reexecução.
================================================================
*/

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- ================================================================
-- Confirmado executado (2026-08-07): extensão presente em
-- pg_extension (extversion 1.1), usada por
-- normalize_external_catalog_value() (Query 2095) sem erros.
-- ================================================================
