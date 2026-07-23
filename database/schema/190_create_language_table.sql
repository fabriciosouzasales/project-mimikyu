/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 190 - Create Language Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria o catálogo global de idiomas utilizados pelos ativos digitais do sistema.

Descrição:
A entidade language representa idiomas e suas variações regionais.
O idioma não pertence exclusivamente a um Game. Por isso, esta tabela não
possui relacionamento com game.

O código do idioma deve seguir o padrão BCP 47 utilizado pelo sistema, como:
- pt-BR
- en
- ja
- es
- fr
- de
- it

Exemplos de utilização:
- imagem da frente de uma Card em português do Brasil;
- imagem da frente da mesma Card em inglês;
- futuros textos, traduções ou ativos localizados.

Estrutura:
- id
- code
- name
- native_name
- language_order
- is_active
- created_at
- updated_at

Regras de Negócio:
- Cada idioma deve possuir um código único.
- O código deve utilizar formato compatível com os códigos adotados pelo
  Project Mimikyu.
- O nome não pode estar vazio.
- O nome nativo não pode estar vazio.
- language_order deve ser maior que zero.
- language_order deve ser único.
- Row Level Security deve permanecer habilitado.

Pré-requisitos:
- Extensão ou infraestrutura que disponibilize gen_random_uuid().

Nota (Princípio da Fonte Canônica): a constraint ck_language_code_format
definida abaixo foi posteriormente simplificada pela Query 192 - Refine
Language Code Constraint, que restringe o formato a xx ou xx-YY. Este
arquivo preserva o texto originalmente executado; ver
database/migrations/192_refine_language_code_constraint.sql para a versão
vigente da constraint.
===============================================================================
*/

BEGIN;

CREATE TABLE IF NOT EXISTS public.language (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    native_name TEXT NOT NULL,
    language_order INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_language_code
        UNIQUE (code),
    CONSTRAINT uq_language_order
        UNIQUE (language_order),
    CONSTRAINT ck_language_code_not_blank
        CHECK (BTRIM(code) <> ''),
    CONSTRAINT ck_language_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_language_native_name_not_blank
        CHECK (BTRIM(native_name) <> ''),
    CONSTRAINT ck_language_code_format
        CHECK (
            code ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$'
        ),
    CONSTRAINT ck_language_order_positive
        CHECK (language_order > 0)
);

COMMENT ON TABLE public.language IS
'Catálogo global de idiomas e variações regionais utilizados pelos ativos e conteúdos localizados do sistema.';

COMMENT ON COLUMN public.language.id IS
'Identificador técnico único do idioma.';

COMMENT ON COLUMN public.language.code IS
'Código estável do idioma em formato compatível com BCP 47, como pt-BR, en ou ja.';

COMMENT ON COLUMN public.language.name IS
'Nome do idioma utilizado na interface principal do sistema.';

COMMENT ON COLUMN public.language.native_name IS
'Nome do idioma escrito em sua própria língua.';

COMMENT ON COLUMN public.language.language_order IS
'Ordem editorial de apresentação do idioma no sistema.';

COMMENT ON COLUMN public.language.is_active IS
'Indica se o idioma está disponível para utilização em novos registros.';

COMMENT ON COLUMN public.language.created_at IS
'Data e hora de criação do registro.';

COMMENT ON COLUMN public.language.updated_at IS
'Data e hora da última atualização do registro.';

CREATE INDEX IF NOT EXISTS ix_language_is_active
    ON public.language (is_active);

ALTER TABLE public.language ENABLE ROW LEVEL SECURITY;

COMMIT;
