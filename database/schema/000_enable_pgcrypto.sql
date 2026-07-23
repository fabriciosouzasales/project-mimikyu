/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 000 - Enable pgcrypto
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Habilita a extensão pgcrypto, necessária para gen_random_uuid(), usada como
valor padrão da chave técnica (id) de todas as tabelas do catálogo.
===============================================================================
*/

CREATE EXTENSION IF NOT EXISTS pgcrypto;
