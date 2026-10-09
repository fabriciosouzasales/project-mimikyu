# NEEDS-REVIEW-REVALIDATION-01 — reavaliação das `NEEDS_REVIEW` já resolvíveis

**Status: EXECUTADO NO LIVE em 2026-10-09** (Claude, via MCP, com autorização de Fabrício).

Locais finais dos arquivos:

- `2238` está em `database/migrations/` (ledger `20261009231911`). A canônica `database/schema/2010` subiu para a v2.1.
- `2239` está em `database/schema/` (ledger `20261009232048`).
- `2843` continua nesta pasta como evidência de validação.

## Resultado da execução

| Etapa | Resultado |
|---|---|
| Pré-check | 1.642 `NEEDS_REVIEW`; a função não existia; a action não existia; 31 actions; `card_variant` = 24.893 |
| `2238` | O guard passou (as três CHECK eram iguais ao baseline). Ficaram 32 actions e o ramo `CATALOG_VARIANT_IMPORT_JOB` passou a ter 2 actions. |
| `2239` | Função criada: `SECURITY DEFINER`, `search_path=""`, `EXECUTE` só do owner. |
| `2843` v1.0 | Falhou em S1b por defeito do próprio teste: comparava `proconfig::text`, que vem com aspas escapadas. Nada foi escrito. Corrigido na v1.1. |
| `2843` v1.1 | **`NRR_2843_ROLLBACK_PASS`**: todos os casos passaram e o estado do banco foi conferido como intacto depois. |
| Dry-run | `plan_rows` 1.085 · 59 jobs · H2 excluídas 379 · H3 excluídas 57 · não resolvíveis 121 · conflitos 0 |
| Apply (`p_expected_rows` = 1.085) | **1.085 linhas revalidadas** em 59 jobs (`run_id` `39390676-f033-4000-a0e6-dc1a103f5921`) |

Na apply, as linhas revalidadas ficaram assim por tipo:

| Tipo | Linhas |
|---|---:|
| `STANDARD` | 897 |
| `HOLO` | 164 |
| `REVERSE_HOLO` | 16 |
| `COSMOS_HOLO` | 4 |
| `COSMOS_REVERSE` | 4 |

### Pós-check

- **Staging `STAGED`/`PENDING`:** `NEEDS_REVIEW` caiu de 1.642 para **557**; `VALID/PENDING` subiu de 48 para **1.133**; `VALID/SKIPPED` ficou em 64.
- **Nova medição da `NR-DRYRUN-01`:** `A_AUTO` = 1, que é a linha retida em H3. `B_FINISH_GAP` = 556, igual ao previsto.
- **Auditoria:** 59 linhas `CARD_VARIANT_IMPORT_ROWS_REVALIDATED`, somando 1.085.
- **`card_variant`:** continua em 24.893. Nada foi materializado.

**Próximo passo para as 1.085 linhas:** decidir e confirmar pelo fluxo normal (`2144` → `2145`), em mandato próprio.

---


## Por quê

A `NR-DRYRUN-01` foi uma medição só de leitura, feita em 2026-10-09. A evidência está em `docs/history/development/needs-review-remeasure-2026-10-09/`.

Ela mostrou que **1.086 das 1.642 `NEEDS_REVIEW`** já se resolvem nos três eixos com o vocabulário vigente. Essas linhas continuam pendentes porque nunca foram reavaliadas depois das seeds de Edition Context (`2230`–`2232`). O único caminho de reavaliação que existe hoje é o worker `2219`, e ele só dispara quando um mapping de acabamento novo é criado.

## Arquivos

| Query | Tipo | O que faz |
|---|---|---|
| `2238` (→ `database/migrations/`) | migration (DDL) | Widen aditivo do `catalog_admin_action_log`. Acrescenta a action `CARD_VARIANT_IMPORT_ROWS_REVALIDATED` e o par `(CATALOG_VARIANT_IMPORT_JOB, CARD_VARIANT_IMPORT_ROWS_REVALIDATED)`. O guard confere o estado real antes de qualquer DDL, comparando o conjunto exato de valores aceitos pelas CHECKs vigentes. |
| `2239` (→ `database/schema/`) | migration (função) | Cria `internal.revalidate_needs_review_variant_rows(p_actor_id, p_apply, p_expected_rows)`. O modo padrão é **dry-run**. Para aplicar, `p_expected_rows` precisa ser igual ao plano medido. Usa o mesmo contrato da `2219` (`resolve_variant_row_axes` + `lookup_variant_type_for_row`, gravando as três chaves de uma vez). Exclui os HOLDs H2 e H3. Detecta colisão de `uq_cvir_row_identity` antes de escrever. É idempotente e audita cada job afetado. |
| `2843` | validação | Um único bloco `DO` que **termina sempre em erro** e por isso desfaz tudo o que fez. Sucesso aparece como `NRR_2843_ROLLBACK_PASS`. Cobre estrutura, guards, pin, holds, shape, auditoria, idempotência e o fato de nenhuma `card_variant` ser criada. |
| — | frontend | `web/lib/catalogo/log-atualizacoes-labels.ts` ganha o rótulo da action nova e das chaves de metadata. Não tem efeito enquanto a `2238` não for aplicada. |

## O que a função NÃO faz

- Não cria mapping, perfil, trait nem `card_variant`.
- Não decide nem confirma linhas. As linhas promovidas ficam `VALID / PENDING / PENDING` e seguem o fluxo normal: `2144` (decide) e depois `2145` (confirm), em mandato próprio.
- Não toca linhas dos HOLDs:
  - **H2:** `set-logo` em EX7–EX10.
  - **H3:** `foil` `league`, `player-reward` ou `professor-program`. Uma linha de H3 resolveria sozinha como `STANDARDS_LEAGUE`, mas a decisão B3 ainda está pendente, então ela não é promovida.
- Não tem EXECUTE para `anon`, `authenticated` nem `service_role`. Uma RPC pública para a tela editorial, com `is_admin()`, fica para um mandato separado.

## Ordem de execução (referência — já executada em 2026-10-09)

1. Aplicar a `2238` e confirmar com a query de validação no rodapé do arquivo.
2. Aplicar a `2239` e confirmar com a query de validação no rodapé do arquivo.
3. Rodar a `2843`. O esperado é a mensagem `NRR_2843_ROLLBACK_PASS` com o plano, que deve ser **1.085** (1.086 − 1 linha de H3). O banco fica intacto.
4. Rodar o dry-run e anotar `plan_rows`:
   ```sql
   SELECT internal.revalidate_needs_review_variant_rows('<seu admin_user.id>', false, NULL);
   ```
5. Aplicar com o número anotado:
   ```sql
   SELECT internal.revalidate_needs_review_variant_rows('<seu admin_user.id>', true, <plan_rows>);
   ```
6. Pós-check: rodar de novo o `NR-DRYRUN-01`. O esperado é `A_AUTO` = 1 (a linha de H3) e `B_FINISH_GAP` = 556.

Os scripts só entram em `database/migrations` / `database/schema` depois de **confirmadamente executados**.

## Riscos registrados

- **Deriva entre o dry-run e o apply.** Coberta pelo pin `p_expected_rows`. Se o plano mudar, nada é escrito.
- **Concorrência com o worker `2219`.** Locks JOB → ROW na mesma ordem determinística da `2219`.
- **CHECK do log mudou desde a `2188`.** O guard da `2238` aborta antes de qualquer DDL.
- **Volume.** O plano tem cerca de 1,6 mil linhas, recalculadas em uma chamada (a mesma ordem de grandeza da `NR-DRYRUN-01`, que respondeu normalmente).
