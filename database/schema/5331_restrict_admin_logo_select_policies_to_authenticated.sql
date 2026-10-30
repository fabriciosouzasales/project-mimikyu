/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5331 - Restringir as políticas SELECT administrativas de
              card-set-logo e expansion-logo ao papel authenticated
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030202408 `5331_restrict_admin_logo_select_policies_to_authenticated`). Aplicada ANTES da 5330 (ordem real do ledger).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-shared-binder-visual-assets/
              (só este bloco Status difere); texto do ledger ≡ corpo após o cabeçalho (md5).
              Validação: postcheck read-only (roles {authenticated}, USING inalterado, demais 24 políticas idênticas) + 5863 v1.2 37/37 PASS, resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Contexto:
`card_set_logo_admin_select` (276, reescrita em 2134) e
`expansion_logo_admin_select` (2047, reescrita em 2134) valem para o papel
`public` e avaliam `(SELECT is_admin())`. `anon` não tem EXECUTE em
`is_admin()` (deliberado). Como políticas SELECT permissivas são combinadas
por OR, todo SELECT de `anon` em `storage.objects` falha com
`42501 permission denied for function is_admin`, em qualquer bucket — o que
impede a vitrine pública de assinar URLs (5329) e já havia sido observado no
harness 5833 (2026-10-17).

Correção (alternativa A): só o papel alvo das duas políticas muda, de
`public` para `authenticated`. Administrador é sempre authenticated, então
nenhuma leitura legítima se perde. `ALTER POLICY ... TO` altera apenas
`polroles`: a expressão USING (bucket + `(SELECT is_admin())`, forma de
2134 com initplan) permanece byte a byte; sem DROP/CREATE, sem janela sem
política.

Não muda: políticas de escrita (INSERT/UPDATE/DELETE) de nenhum bucket;
políticas de 5174 e 5329; `is_admin()` e seus grants (anon continua sem
EXECUTE); nenhuma outra política ou função.

Como validar: postcheck read-only (roles = {authenticated}, qual inalterado,
demais políticas com assinatura idêntica) e 5863 v1.2.
Reversão: ALTER POLICY card_set_logo_admin_select ON storage.objects TO public;
          ALTER POLICY expansion_logo_admin_select ON storage.objects TO public;
================================================================
*/

ALTER POLICY card_set_logo_admin_select ON storage.objects TO authenticated;
ALTER POLICY expansion_logo_admin_select ON storage.objects TO authenticated;
