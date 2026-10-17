# Proposta — Cor do fichário e leitura de logos de Set (MY-COLLECTIONS-LIBRARY-VISUAL-02)

| Campo | Valor |
|---|---|
| Status | **EXECUTED / VALIDATED / PROMOTED** — 5171–5174 aplicadas no LIVE em 2026-10-17 (ledgers `20261017191204`, `20261017191234`, `20261017191305`, `20261017191335`), autorização de Fabrício; 5831 v1.2 PASS; promovidas para `database/schema/`. Esta pasta fica como evidência histórica. |
| Data | 2026-10-17 |
| Decisão de Fabrício | "Proposta SQL + seletor" (cor) e "Logo se legível + proposta" (arte do Set), 2026-10-17 |
| Frontend | Já preparado: sem a proposta, cada coleção usa uma cor padrão estável e a capa usa a identidade tipográfica do Set para quem não pode ler logos; com a proposta aplicada, o seletor de cor aparece sozinho (detecção da coluna `cover_finish` em R1) e os logos passam a aparecer para todos. |
| Contratos C-*/LDM-* | Inalterados (aparência da coleção; não toca cartas, alocações, locais nem progresso). |

## Por que

1. A cor do fichário é parte da identidade da coleção e é escolhida pelo colecionador → precisa ser persistida por coleção. Hoje a tabela `collection` não tem onde guardá-la.
2. A capa deve usar a identidade do Set. O logo mora no bucket privado `card-set-logo`, que hoje só administradores leem → colecionadores comuns não conseguem ver a arte.

## Arquivos (ordem de execução)

| Query | Arquivo | O que faz |
|---|---|---|
| 5171 | `5171_add_collection_cover_finish.sql` | Coluna `collection.cover_finish text null` + CHECK do vocabulário (`onix`, `vinho`, `floresta`, `marinho`, `caramelo`, `perola`). Sem backfill. |
| 5172 | `5172_create_set_my_collection_cover_finish_function.sql` | RPC `set_my_collection_cover_finish(coleção, cor) → text`: dono por `auth.uid()`, idempotente, sem enumerar coleção alheia, só `authenticated`. |
| 5173 | `5173_recreate_get_my_collections_with_cover_finish.sql` | R1 v2: mesma saída da 5168 + `cover_finish` (DROP + CREATE na mesma transação, mesmos grants). |
| 5174 | `5174_create_card_set_logo_authenticated_read_policy.sql` | Policy `SELECT` em `storage.objects` do bucket `card-set-logo` para `authenticated`. Escrita continua admin-only; bucket continua privado (URL assinada); `anon` sem acesso. |
| 5831 | `5831_validate_collection_cover_finish.sql` (v1.1) | Validação: estrutura e privilégios (S1.1–S1.12), comportamento com usuários efêmeros em BEGIN … ROLLBACK (S2.1–S2.8, S3.1–S3.2), leitura de logo por não-admin (S4, manual). |

## Riscos e decisões a confirmar

- **5174 libera a leitura de todos os logos de Set para qualquer usuário autenticado.** São imagens públicas de catálogo, não dados de usuário. Se preferir manter o bucket restrito, a alternativa é uma cópia pública só dos logos (outro desenho, não proposto aqui).
- **Vocabulário fechado**: as 6 cores são as mesmas de `web/lib/colecoes/binder-finish.ts`; ampliar exige mudar o CHECK e a lista no frontend juntos.
- **K12 resolvido (2026-10-17):** Fabrício aprovou a paleta fechada de seis cores desta proposta para a versão atual (North Star NS-16). *(Antes: "bloqueio de execução até fechar a paleta".)* A decisão **não** autoriza a execução no LIVE.
- O Security Advisor deve registrar +1 em `0029` (5172, SECURITY DEFINER por desenho).

## Readiness de implantação (2026-10-17, após a decisão K12)

**Revisão de segurança e isolamento (estática, sobre o repositório; nenhum SQL executado):**

| Item | Resultado |
|---|---|
| 5171 — coluna nula sem backfill; CHECK = paleta aprovada | OK. `collection` só tem GRANT SELECT para `authenticated` (5030): a coluna só é gravável pela 5172. Nenhum trigger de `collection` (5031, 5032, 5033, 5059, 5076) reage a `cover_finish` além do `updated_at`. |
| 5172 — RPC de gravação | OK. `SECURITY DEFINER`, `search_path = ''`, dono por `auth.uid()` no próprio `WHERE`, alheia = inexistente (`P0002`), vocabulário revalidado no servidor, idempotente, REVOKE de `PUBLIC`/`anon`, EXECUTE só `authenticated`. Não toca cartas, alocações, locais nem progresso. |
| 5173 — R1 v2 | OK. Corpo **idêntico** ao da `5168` promovida (diff: só a coluna `cover_finish` e o comentário); mesmos REVOKE/GRANT. DROP + CREATE na mesma transação; único chamador é `web/lib/colecoes/colecoes-queries.ts`, que tolera a coluna nova (detecção). |
| 5174 — leitura de `card-set-logo` | OK com risco aceito no desenho: libera SELECT/listagem do bucket inteiro para `authenticated` (logos de catálogo, sem dado de usuário). Escrita segue admin-only; `anon` sem acesso; bucket continua privado (URL assinada). |
| 5831 v1.0 | **Corrigido para v1.1 (defeito do harness, não das migrations):** (a) `auth.users` sem `username`/`display_name` faria o gatilho `handle_new_user` (Query 1020) abortar as Seções 2–3; (b) S1.8 ignorava `WITH CHECK` (policies de INSERT) e passaria vazio; (c) acrescentados S1.9–S1.12 (policy não alcança `anon`; EXECUTE de `authenticated`; sem UPDATE direto) e S2.6–S2.8 (inexistente = alheia; sem sessão; `anon` sem EXECUTE, comportamento real). Fixture de Set no mesmo critério do 5830. |
| Frontend | Pronto: vocabulário de `binder-finish.ts` idêntico ao CHECK; seletor aparece só quando a R1 devolver `cover_finish`; logos aparecem quando a URL assinada for gerada. |
| Security Advisor | Esperado: +1 em `0029` (5172, SECURITY DEFINER por desenho), como 5167–5170. |

**Sequência de implantação (executor: Fabrício, uma Query por vez, STD-001 §10):**

0. **Pré-check (somente leitura):** coluna `collection.cover_finish` inexistente; função `set_my_collection_cover_finish` inexistente; `get_my_collections` com a assinatura da 5168; policy `card_set_logo_authenticated_select` inexistente; baseline do Security Advisor anotado.
1. **5171** → confirmar coluna e CHECK.
2. **5172** → confirmar `prosecdef`, `search_path` e ACL.
3. **5173** → confirmar `cover_finish` no resultado e ACL (a Biblioteca continua funcionando: o frontend já tolera a coluna).
4. **5174** → confirmar a policy.
5. **5831 v1.1** Seção 1 (leitura) e depois Seções 2–3 (bloco BEGIN … ROLLBACK) → todas as linhas `ok = true`; resíduo zero.
6. **Seção 4 manual:** com sessão de colecionador comum, o logo aparece na capa e o upload no bucket falha.
7. Security Advisor antes × depois; promover 5171–5174 para `database/schema/`; registrar no 05d, HANDOFF e log.

**Rollback (se algum passo falhar):** 5174 → `drop policy card_set_logo_authenticated_select on storage.objects`; 5173 → reaplicar `database/schema/5168`; 5172 → `drop function public.set_my_collection_cover_finish(uuid, text)`; 5171 → `alter table public.collection drop column cover_finish` (seguro enquanto nenhuma cor tiver sido gravada).

**Status (histórico):** READY FOR EXECUTION em 2026-10-17; executado na mesma data — ver "Execução no LIVE" abaixo.

## Execução

Quem executa é Fabrício, uma Query por vez, confirmando antes de avançar (STD-001 §10). Depois: rodar 5831, conferir resíduo zero, promover 5171–5174 para `database/schema/` e registrar no `05d`.

## Execução no LIVE (2026-10-17, autorização de Fabrício)

**Pré-check (somente leitura):** objetos novos ausentes; R1 com a assinatura da 5168 (md5 `5dec6a61…`); policies de `card-set-logo` = 4 admin (`is_admin()`), bucket privado; baseline de dados: 1 coleção, 147 alocações, 427 exemplares, 1 local, impressão digital das coleções `6ba9b83b…`; Security Advisor: 0008=30, 0011=1, 0014=1, 0028=1, 0029=157, senha vazada=1.

**Condição da 5174 — conteúdo do bucket:** 203 objetos, todos `image/png` (52) ou `image/webp` (151), todos no formato `<card_set_id>/<uuid>.<ext>`. 200 são os logos atuais dos 200 Sets com logo; 3 são logos anteriores não referenciados: 2 versões substituídas (SV5, BASE5) e 1 do Set BASEP criado e excluído em 2026-08-04 (log `CARD_SET_CREATED/UPDATED/DELETED`, upload 8 s antes do `UPDATED`). Nenhum arquivo administrativo ou sensível. **Condição atendida.**

**Aplicação:** 5171 → coluna `text null` + CHECK das 6 cores; 0 linhas com cor. 5172 → `SECURITY DEFINER`, `search_path=""`, VOLATILE, ACL `{postgres, authenticated}`, sem `anon`, 1 assinatura. 5173 → zero dependências antes do DROP; resultado com `cover_finish`; ACL igual; corpo `prosrc` md5 `4902ed72…` = arquivo; leitura do dono real devolve a coleção existente (158 posições, 147 satisfeitas, 147 cópias, cor nula). 5174 → policy `card_set_logo_authenticated_select` (SELECT, `{authenticated}`, `bucket_id = 'card-set-logo'`). Corpo da 5172 md5 `4f48d916…` = arquivo.

**5831 v1.2:** Seção 1 = 12/12; Seções 2–3 = 10/10 (BEGIN … ROLLBACK, usuários efêmeros). v1.2 corrige S1.9 (as policies admin pré-existentes têm `roles {public}` mas exigem `is_admin()`; a checagem passou a considerar só policies sem `is_admin()`).

**Seção 4 (storage, BEGIN … ROLLBACK, usuário comum efêmero):** não é admin; lê 203/203 logos; INSERT recusado por RLS; UPDATE afeta 0 linhas; anon recebe `permission denied` (comportamento pré-existente das policies admin `{public}`, não introduzido aqui); bucket intacto (203). DELETE: o Storage bloqueia DELETE direto em SQL para todos (`storage.protect_delete`); pela API, a única policy de DELETE do bucket é a admin (`is_admin()`), então usuário comum não exclui (verificado na definição das policies).

**Resíduo e dados reais:** auth.users 3 (sem `cover-%@test.invalid`), perfis 3, inventários 3, coleções 1, locais 1, pedidos de criação 1, exemplares 427, alocações 147, logos 203, nenhum objeto de sonda; impressão digital das coleções idêntica (`6ba9b83b…`).

**Security Advisor depois:** 0029 = 158 (+1, `set_my_collection_cover_finish`, esperado por desenho); demais categorias inalteradas; nenhuma exposição nova.
