/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 890 - Seed Language
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Popula o catálogo inicial de idiomas utilizados pelo Project Mimikyu.

Nesta primeira versão são cadastrados apenas os idiomas necessários para os
ativos atualmente suportados pelo sistema.

Pré-requisitos:
- Query 190 - Create Language Table.
- Query 191 - Create Language Triggers.
===============================================================================
*/

BEGIN;

INSERT INTO public.language (
    code,
    name,
    native_name,
    language_order,
    is_active
)
VALUES
(
    'pt-BR',
    'Português (Brasil)',
    'Português (Brasil)',
    1,
    TRUE
),
(
    'en',
    'English',
    'English',
    2,
    TRUE
)
ON CONFLICT (code)
DO UPDATE
SET
    name = EXCLUDED.name,
    native_name = EXCLUDED.native_name,
    language_order = EXCLUDED.language_order,
    is_active = EXCLUDED.is_active;

COMMIT;
