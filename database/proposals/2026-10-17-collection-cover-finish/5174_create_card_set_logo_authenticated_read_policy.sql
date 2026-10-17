/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5174 - Leitura do bucket card-set-logo por usuários
              autenticados (identidade do Set na capa do fichário)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contexto:
Hoje só administradores leem `card-set-logo` (policy
card_set_logo_admin_select). A capa do fichário usa o logo do Set quando a
sessão consegue assinar a URL; para colecionadores comuns cai na identidade
tipográfica. Logo de Set é conteúdo público de catálogo (não é dado de
usuário), então liberar LEITURA para `authenticated` não expõe nada privado.

O que muda: só SELECT em storage.objects do bucket `card-set-logo` para
`authenticated`. Escrita (INSERT/UPDATE/DELETE) continua admin-only; o
bucket continua privado (URLs assinadas, nunca públicas); `anon` sem acesso;
`expansion-logo` intocado.

Resultado esperado: um usuário autenticado não-admin consegue
createSignedUrl de um logo existente; não consegue gravar.
Como validar: Query 5831 (Seção 4).
================================================================
*/

begin;

create policy card_set_logo_authenticated_select
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'card-set-logo');

commit;
