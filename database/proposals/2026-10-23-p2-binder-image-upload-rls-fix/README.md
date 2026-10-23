# P2-BINDER-IMAGE-UPLOAD-RLS-FIX-01 — recursão RLS no envio de imagens do bolso

| Campo | Valor |
|---|---|
| Versão | 1.2 (2026-10-23, `CORRECTION-02`: critério de dono removido da PRE-4 e da 5237; BYPASSRLS mantido) |
| Status | **5237 CONFIRMADO EXECUTADO no LIVE** (2026-10-23, ledger `20261023202009 5237_fix_binder_slot_image_insert_policy_recursion`; corpo do arquivo sha256 `c005b0d4…0960d` enviado sem os `begin;`/`commit;` externos — o `apply_migration` já é uma transação única — e sem os comentários `--`). R1-pós: POST-1 8/8 ok, POST-2 idêntico ao PRE-5, POST-3 1 linha; Advisor: só o achado esperado 0029 da função nova. **F1 PASS** (2026-10-23 20:27:21 UTC, pelo app, página 20 L1C1 do fichário de "Celebração de 30 Anos"): Storage `POST 200` + `ObjectCreated` (WebP 8774 B, `owner_id` = usuário), `set_my_binder_slot_image` 200, linha em `collection_layout_slot_image` (focal_y 50), imagem exibida e persistente após recarregar, sem erro no Postgres/console; cartas, reservas, cadeados e alocações com assinatura idêntica à anterior. **F2–F6 PASS** (20:32–20:34 UTC, sessão real do usuário via API): F2 `get_my_collection_binder_slot_images` mostra o bolso; F3 `remove([path])` → `200 []`, DELETE direto → `403 Access denied`, anônimo → recusado, arquivo/eTag/SHA-256 intactos; F4 `upsert:true` e PUT → `403 new row violates RLS`, move → `NoSuchKey`, conteúdo/eTag/versão intactos; F5 `clear_my_binder_slot_image` → `REMOVED` com `previous_path`; F6 `remove([path])` → removido (Storage e `storage.objects`). F7 (opcional, duas sessões concorrentes) não executada. Estado final: 0 imagens, 0 objetos; cartas, reservas, bolsos, 20 páginas, alocações e 1352 cartas físicas com assinatura idêntica ao baseline (autorização própria); promoção para `database/schema/` depois do F1–F7. Antes: R1-pré executado só leitura (2026-10-23, papel `postgres`): PRE-1…PRE-6 PASS — PRE-5: 0 objetos, 0 imagens, 24 políticas, `fp_other_storage_policies` `1e347f41dc9a6c7e00a309896afe50f4`, bucket `false\|524288\|{image/webp,image/jpeg}` |
| Depende de | 5231–5236 aplicadas e canônicas (`database/schema/`) |
| Arquivos canônicos tocados | nenhum (5231–5236 permanecem como aplicadas) |

## Causa

`P2-BINDER-CUSTOM-IMAGES-VALIDATION-01`: o primeiro envio real (Fabrício, 2026-10-23 19:46:23 UTC) recebeu `400` do Storage e o Postgres registrou `infinite recursion detected in policy for relation "objects"`. A política `binder_slot_image_insert_own` (5231) contém `(select count(*) from storage.objects …) < 550`; uma política de `storage.objects` que lê `storage.objects` sob RLS expande recursivamente as políticas da tabela e o Postgres recusa. Todo envio ao bucket falha; nenhum arquivo é criado. As políticas SELECT e DELETE não se autorreferenciam (a DELETE lê `public.collection_layout_slot_image`) e não mudam.

## Correção — `5237_fix_binder_slot_image_insert_policy_recursion.sql`

1. `public.binder_slot_image_under_object_cap() → boolean` (sem argumentos; teto 550 fixo dentro dela): `SECURITY DEFINER` (dono com BYPASSRLS, então a contagem não passa pelas políticas), `search_path = ''`, `STABLE`; conta só a pasta do `auth.uid()` lido dentro da função; sem sessão → `false`. EXECUTE só `authenticated` (revogado de PUBLIC e anon).
2. `ALTER POLICY binder_slot_image_insert_own … WITH CHECK (...)`: mesmo nome, papel, bucket, pasta = `auth.uid()` e regex do nome; só a subconsulta vira `public.binder_slot_image_under_object_cap()`. Atômico (sem janela sem política). O teto 550 passa a viver só na função.
3. Pré-checagens fail-loud (pacote presente, texto da política = 5231, função ausente, papel com BYPASSRLS; sem exigir vínculo com o dono de `storage.objects` — CORRECTION-02: as políticas criadas antes por este papel são evidência de compatibilidade, não prova de autorização para `ALTER POLICY`; se recusado, a transação desfaz tudo) e pós-checagem na mesma transação (política sem autorreferência, com bucket/pasta/`auth.uid()`, só `authenticated`; EXECUTE da função sem anon).

Inalterados: limite de 550 arquivos por usuário (mesma semântica e mesma imprecisão sob concorrência já aceita na 5231), limite de 500 imagens vinculadas (5233), bucket (512 KB, WebP/JPEG, privado), SELECT/DELETE, tabela, RPCs, bolsos, cartas e reservas.

## Ordem (classes do RUNBOOK-LIVE da 5231–5236)

| # | Etapa | Classe | Autorização |
|---|---|---|---|
| 0 | `LIVE_00_precheck_readonly.sql` (PRE-1…PRE-6) | R1 | própria |
| 1 | `5237` via `apply_migration` (`5237_fix_binder_slot_image_insert_policy_recursion`) | W1 | **expressa e separada** |
| 2 | `LIVE_90_postcheck_readonly.sql` (POST-1…POST-3) + `get_advisors(security)` (POST-4) | R1 | própria |
| 3 | F1–F7 do RUNBOOK-LIVE (5231–5236 §7) | F | **expressa e separada** |
| 4 | Promoção para `database/schema/` + 05d/HANDOFF/INDEX/log | — | — |

**PASS/STOP:** PRE-1…PRE-4 conforme comentários do arquivo; PRE-6 sem transação longa. POST-1 8/8 `ok`; POST-2 idêntico ao PRE-5 (cinco valores); POST-3 uma linha; POST-4 sem classe nova. Erro em qualquer passo: parar, guardar SQLSTATE/texto, não reaplicar nem editar no LIVE.

**Reversão** (não recomendada — volta a bloquear todo envio; só com autorização): `alter policy` com o texto da 5231 e `drop function public.binder_slot_image_under_object_cap()`.

## Efeito em artefatos existentes

- `LIVE_90` da 5231–5236 (Q1.03) e harness `5852` (S0) conferem `with_check like '%550%'` — **deixam de valer após a 5237** (o literal sai da política e vai para a função). São artefatos históricos do pacote 5231–5236; a conferência vigente do teto é o Q4 do `LIVE_90` desta pasta (`prosrc like '%< 550%'`). O harness 5852 continua proibido no LIVE e não foi alterado.
- Frontend: nenhuma mudança (o envio continua `upsert:false` no mesmo caminho canônico).

## Riscos residuais

1. Prova comportamental só no F1–F7 (a correção é estrutural; nenhuma checagem de leitura executa um INSERT real pelo Storage).
2. A função é chamável por RPC por qualquer `authenticated`: revela apenas se o PRÓPRIO usuário tem menos de 550 arquivos na PRÓPRIA pasta — informação que ele já lê pela política SELECT. Sem acesso a terceiros.
3. Teto 550 pode ser excedido por poucos arquivos sob envios simultâneos (inalterado, aceito na 5231).
4. `ALTER POLICY` pede trava exclusiva breve de `storage.objects` (PRE-6 escolhe a janela).
