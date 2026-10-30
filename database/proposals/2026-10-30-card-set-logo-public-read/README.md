# CARD-SET-LOGO PUBLIC READ — logo do Set na vitrine pública (proposta)

| Campo | Valor |
|---|---|
| Status | **5330 APLICADA NO LIVE (2026-10-30, LIVE ROLLOUT — PACOTE B), ledger `20261030203139`; 5864 executada uma vez: GATE PASS 7/7** (anon lista 200 de 200 logos atuais; 3 substituídos e caminho inventado negados; expansion-logo sem leitura anon; demais 26 políticas com assinatura idêntica à do precheck). Dependia de 5331 (anon sem `is_admin()` nas políticas SELECT admin). **Promovida para `database/schema/`** (V1-12 FINAL SCHEMA RECONCILIATION & VISUAL HANDOFF; ledger ≡ proposta, md5); este arquivo permanece como evidência histórica. **Pendência de hardening registrada (fora deste escopo):** políticas de escrita admin (INSERT/UPDATE/DELETE) de card-front, card-set-logo, expansion-logo e pokemon-species-artwork seguem `TO public` com `(SELECT is_admin())` — fail-closed para anon (erro 42501), sem exposição; alinhar a `authenticated` em rodada própria. |
| Data | 2026-10-30 |
| Origem | V1-12 SHARED VISUAL ASSETS — SECURITY READINESS-01, item 4 |

**Problema.** O bucket privado `card-set-logo` só tem SELECT para `authenticated` (5174) e administrador. O visitante anônimo da vitrine (`/fichario/[id]`) não consegue assinar a URL do logo do Set → capa tipográfica.

**Correção mínima (5330).** Uma política SELECT só para `anon`, só no bucket `card-set-logo`, só para o arquivo que é o **logo atual** de algum Card Set (`card_set.logo_storage_path`), via função `card_set_logo_is_current(name)` (SECURITY DEFINER, booleano, porque `card_set` é admin-only por RLS). Mais estreita que a 5174:

- envios antigos/substituídos (LIVE hoje: 3 de 203 objetos) e caminhos inventados continuam negados, inclusive na listagem;
- sem escrita; bucket continua privado (URL assinada); políticas existentes intactas; `expansion-logo` e demais buckets intactos;
- frontend sem mudança (a vitrine já assina com a sessão anon).

**Validação (5864, leitura pura, sem fixture):** S.1–S.3 estrutura; A.1 anon lê um logo atual; A.2 anon lista exatamente os logos atuais; A.3 logo antigo e inventado negados; A.4 `expansion-logo` continua fechado. Gate `GATE PASS 7/7`.

**Aplicação:** 5330 (uma migration) → 5864 uma vez. Qualquer FAIL → STOP. Reversão: `DROP POLICY card_set_logo_public_current_select ON storage.objects; DROP FUNCTION public.card_set_logo_is_current(text);`

**Risco residual:** quem souber o caminho de um logo atual consegue vê-lo sem login — é conteúdo de catálogo, o mesmo exibido a qualquer usuário autenticado.
