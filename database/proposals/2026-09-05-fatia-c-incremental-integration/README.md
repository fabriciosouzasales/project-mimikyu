# Staging — Collections Pokédex Fatia C — Integração Incremental (pós-confirmação)

| Campo | Valor |
|--------|-------|
| **Pasta** | `database/proposals/2026-09-05-fatia-c-incremental-integration/` |
| **Status** | **PROMOVIDO** — Esta pasta é mantida apenas como histórico do staging original (auditoria de call graph, correções REVISION-01/FINAL-CHECK-01, incidente e recuperação dos fixtures de teste) — a fonte canônica é `database/schema/6116_create_resolve_card_primary_species_for_catalog_import_job_function.sql`, e as alterações reais nos dois callers vivem em `web/app/catalogo/importar-cartas/tcgdex/actions.ts` e `supabase/functions/revalidate-catalog-import-rows/index.ts`. Promovido em `COLLECTIONS-POKEDEX-FATIA-C-CANONICAL-CLOSEOUT-01` (2026-09-05). `6116` v1.2 aplicada via `apply_migration` (postcheck estrutural/segurança OK: `SECURITY DEFINER`, `search_path=''`, `is_admin()` no corpo, `GRANT EXECUTE` só para `authenticated`). Fluxo A e Fluxo B implementados e reconfirmados no diff final do closeout. 26 cenários de teste funcional (BEGIN/RAISE EXCEPTION para forçar ROLLBACK) — todos PASS. Zero regressão confirmada (`card_primary_species` = 5675 antes e depois). `npm run typecheck` limpo; Edge Function reimplantada com sucesso (v9, `ACTIVE`) no closeout. Nenhum `git add`/`commit`/`push` realizado (Fabrício faz o commit final). |
| **Rodadas de origem** | `COLLECTIONS-POKEDEX-FATIA-C-INCREMENTAL-INTEGRATION-AUDIT-01`, `-REVISION-01` (corrige divergência de call graph), `-FINAL-CHECK-01` (fecha guard de `source`), `-IMPLEMENTATION-01` (execução real) |
| **Incidente desta rodada** | Durante a execução dos testes funcionais de `6116`, um primeiro bloco de fixtures foi encerrado por engano com `COMMIT` em vez de `ROLLBACK`, persistindo temporariamente 8 Cards sintéticas, 3 `catalog_import_job`, 10 `catalog_import_row`, 1 `card_primary_species` e 1 `catalog_admin_action_log` de teste no banco real. Detectado imediatamente, corrigido via `DELETE` explícito de cada linha (por id/prefixo determinístico usado nos fixtures) na ordem correta de FK, e confirmado `card_primary_species` de volta a exatamente 5675 linhas (baseline do backfill). Os 26 testes foram então reexecutados com sucesso dentro de uma transação que termina em `RAISE EXCEPTION` (nunca `COMMIT`), forçando ROLLBACK automático independentemente do resultado — ver seção 7. |
| **Data** | 2026-09-05 |
| **Pré-requisito físico** | `card_primary_species` + `resolve_card_primary_species_bulk()` já implementados no banco real (Fatia C, `2026-09-05-fatia-c-card-primary-species/`) e backfill de 5675 Cards já aplicado (`BACKFILL-APPLY-01`) |

## REVISION-01 — o que mudou e por quê

`AUDIT-01` afirmou "chamador real único de `admin_confirm_catalog_import()`: `confirmarImportacao()`". **Isso estava incorreto** — divergência identificada externamente e confirmada por reauditoria completa desta rodada (`grep` de `rpc\(['"]admin_confirm_catalog_import['"]` em **todo** o repositório, não só em `web/`, que é onde a auditoria anterior parou). Existe um **segundo caller real**: `confirmCatalogImport()` em `supabase/functions/revalidate-catalog-import-rows/services/database.ts`, chamado por `revalidate-catalog-import-rows/index.ts` sempre que a revalidação destrava pelo menos uma linha (`unblocked_count > 0`). A reauditoria completa desta rodada não encontrou nenhum terceiro caller.

Corrigido nesta rodada:
1. **Call graph** (seção 1) — agora lista os dois callers reais, com trecho de código de cada um.
2. **Ponto de integração** (seção 2) — passa a cobrir os DOIS fluxos, cada um com seu próprio trecho proposto e sua própria estratégia de isolamento de erro (o segundo fluxo tem uma armadilha real: um `try/catch` por JOB já existente em `index.ts` que, se a chamada nova for colocada sem cuidado, reportaria uma falha de Primary Species como se fosse falha da confirmação de Cards — ver seção 5).
3. **Contrato de 6116** — `p_row_ids` **removido** (v1.0 → v1.1): nenhum dos dois callers reais o exerceria (ambos chamam a função nova uma única vez, para o job inteiro, nunca para um subconjunto) — mantê-lo seria superfície de contrato sem uso demonstrado. Ver seção 3.
4. **Testes** (seção 7) — removido o teste de `p_row_ids`, adicionados testes específicos do segundo fluxo (revalidação) e do isolamento de erro em ambos.

Nada do desenho central mudou: `resolve_card_primary_species_for_catalog_import_job()` (Query 6116) continua sendo a única implementação da orquestração (leitura de `resulting_card_id`, filtro POKEMON, agregação de dexId, delegação a `resolve_card_primary_species_bulk()`); os dois callers só passam a invocá-la.

## FINAL-CHECK-01 — o que mudou e por quê

Último invariante obrigatório antes da implementação: **confirmar que 6116 só processa jobs `catalog_import_job.source = 'TCGDEX'`**. Auditoria focada desta rodada confirmou que a v1.1 (REVISION-01) **não tinha esse guard** — ela carregava `catalog_import_row.raw_data->'dexId'` de qualquer job com Cards POKEMON elegíveis, sem nunca olhar `catalog_import_job.source`. `catalog_import_job.source` é restrito por CHECK a exatamente `'PDF'` ou `'TCGDEX'` (Query 2060) — a semântica de `dexId` em `raw_data` é inteiramente específica do payload da API TCGdex; um job `PDF` nunca deveria ter essa evidência interpretada.

Isso não era só um risco teórico: o **Fluxo B** (`revalidate-catalog-import-rows`) é genérico — `listRevalidatableJobs()` não filtra por `source`, processa qualquer job elegível, `PDF` ou `TCGDEX`. O Fluxo A (`confirmarImportacao()`) vive na rota `/tcgdex/`, então hoje só é exercitado por jobs `TCGDEX` na prática — mas 6116 não pode depender da disciplina da rota que a chama para se manter correta; o guard precisa estar na própria função.

Corrigido nesta rodada (6116 v1.1 → v1.2):
- A função agora **carrega o `catalog_import_job` completo** (antes só verificava existência) e, se `source <> 'TCGDEX'`, **retorna imediatamente** — sem tocar em `raw_data->'dexId'`, sem chamar `resolve_card_primary_species_bulk()` (Query 6115), sem nenhuma escrita em `card_primary_species`.
- O contrato de retorno ganhou uma coluna nova, **`status TEXT`** (ausente em v1.0/v1.1), com três valores possíveis: `'SOURCE_NOT_TCGDEX'` (guard disparado, zero processamento), `'NO_ELIGIBLE_CARDS'` (job TCGDEX, mas nenhuma Card POKEMON elegível), `'PROCESSED'` (job TCGDEX com Cards elegíveis — contadores/`details` refletem `resolve_card_primary_species_bulk()`). Preferência explícita do mandato ("retornar erro/estado explícito... sem escrita") — sem essa coluna, `SOURCE_NOT_TCGDEX` e `NO_ELIGIBLE_CARDS` seriam indistinguíveis (os dois retornariam todos os contadores zerados e `details = []`).
- `p_job_id` inexistente continua `RAISE EXCEPTION` (erro de chamador); `source <> 'TCGDEX'` NUNCA levanta exceção — é um estado normal de operação do Fluxo B genérico, não um bug.

Ver `6116...sql`, seção "Correção v1.2 (FINAL-CHECK-01)", para o texto completo.

## Objetivo desta rodada

Fechar o desenho de como novas Cards Pokémon importadas via TCGdex recebem `card_primary_species` automaticamente, **sem** reabrir a premissa já corrigida: a resolução só pode acontecer depois que `resulting_card_id` existir — nunca durante o staging em `catalog_import_row`, nunca dentro do Edge Function `import-catalog-cards` (que só cria linhas de staging, nunca Cards persistidas).

## 1. Call graph real (corrigido)

```
TCGdex
  → import-catalog-cards (Edge Function)         [cria/atualiza catalog_import_row — staging]
  → catalog_import_row                            [persistence_status = PENDING]
  → admin_decide_catalog_import_row()  (Query 2081) [decision_status = APPROVED/SKIPPED/REJECTED — NUNCA toca resulting_card_id]
  │
  ├─ FLUXO A — confirmação direta (web)
  │  confirmarImportacao()  (Server Action, web/app/catalogo/importar-cartas/tcgdex/actions.ts:267-330)
  │        ├─ busca ids elegíveis (persistence_status=PENDING, decision_status IN (APPROVED,SKIPPED))
  │        ├─ chunk() em lotes de CONFIRM_CHUNK_SIZE=50
  │        └─ for cada lote:
  │              supabase.rpc("admin_confirm_catalog_import", {p_job_id, p_row_ids: lote})  (Query 2082)
  │                    → grava resulting_card_id em catalog_import_row (ÚNICO writer deste campo)
  │                    → recalcula catalog_import_job.status
  │        [PONTO DE INTEGRAÇÃO A — ver seção 2] → revalidatePath(...) × 4, return lastResult
  │
  └─ FLUXO B — revalidação + retomada (Edge Function)
     revalidate-catalog-import-rows/index.ts
        ├─ listRevalidatableJobs() → para cada job:
        ├─ applyRevalidation()  (svc_apply_catalog_import_revalidation, Query 2106)
        │       → destrava linhas FAILED → PENDING quando a nova validação as torna VALID
        │       → unblockedCount = result.unblocked_count
        └─ if (unblockedCount > 0):
              confirmCatalogImport(userClient, job.id)  (database.ts:233-245)
                    → userClient.rpc("admin_confirm_catalog_import", {p_job_id, p_row_ids: null})  (Query 2082)
                          → grava resulting_card_id (mesmo writer único)
              [PONTO DE INTEGRAÇÃO B — ver seção 2]
        jobResults.push({..., error: null})  — tudo dentro de um try/catch POR JOB
```

**Achados de auditoria (corrigidos e reconfirmados):**
- `admin_confirm_catalog_import()` (Query 2082) tem **exatamente dois** callers reais em todo o repositório — reauditado nesta rodada com `grep` irrestrito (não só `web/`):
  - **A.** `confirmarImportacao()` — `web/app/catalogo/importar-cartas/tcgdex/actions.ts:287`, chunка em lotes de 50.
  - **B.** `confirmCatalogImport()` — `supabase/functions/revalidate-catalog-import-rows/services/database.ts:234`, chamada por `index.ts:202` só quando `unblockedCount > 0`, sempre com `p_row_ids: null` (job inteiro, nunca chunка).
  As demais ocorrências do nome (`web/lib/catalogo/queries.ts`, `revisao-importacao-table.tsx`, `page.tsx`, `_shared/catalog-normalization/types.ts`) são comentários/documentação, não chamadas RPC. **Nenhum terceiro caller encontrado.**
- `resulting_card_id` continua sendo escrito **exclusivamente** por `admin_confirm_catalog_import()` — confirmado (grep negativo) em `admin_decide_catalog_import_row()` (2081) e nas duas funções de revalidação (2105/2106). `svc_apply_catalog_import_revalidation` só reabre linhas `FAILED → PENDING`; nunca toca `resulting_card_id` nem reabre linhas já `INSERTED`/`UPDATED`/`UNCHANGED`.
- Cada chamada a `admin_confirm_catalog_import()` — em qualquer um dos dois fluxos — é uma chamada RPC PostgREST independente, commitada isoladamente. Não existe uma única transação de banco cobrindo o job inteiro em nenhum dos dois fluxos.
- **Achado específico do Fluxo B, relevante para a estratégia de erro (seção 5):** em `index.ts`, TODO o bloco por job (revalidação + `confirmCatalogImport()`) roda dentro de um único `try { ... } catch (jobError) { jobResults.push({..., error: message}) }` (linhas ~150-236). Se a chamada nova a 6116 for inserida ali SEM seu próprio isolamento, uma falha nela seria capturada pelo `catch` do job e reportada como `jobResults[].error` — fazendo a resposta da Edge Function dizer que o JOB falhou, mesmo que `confirmCatalogImport()` já tenha persistido as Cards com sucesso. Isso violaria diretamente o requisito crítico. A chamada nova precisa checar `{ data, error }` diretamente (sem usar um helper que lança, como `confirmCatalogImport()` faz) para nunca escapar para esse `catch` externo.
- Precedente arquitetural relevante (mantido de AUDIT-01): a "Continuação automática: cartas → imagens" (`useAnalyzeJob`, `web/components/catalogo/importar-tcgdex-view.tsx`) já resolve o mesmo tipo de problema no Fluxo A — falha na continuação nunca reabre a confirmação de Cards.

## 2. Pontos de integração (dois, um por fluxo)

`resolve_card_primary_species_for_catalog_import_job()` (Query 6116) é chamada **uma vez por invocação bem-sucedida de `admin_confirm_catalog_import()`**, em cada um dos dois fluxos, sempre para o job inteiro (sem subconjunto — ver seção 3 sobre `p_row_ids`).

### Ponto A — `confirmarImportacao()` (web)

Depois do laço `for (const batch of batches)` existente (linha 312 atual), antes do bloco de `revalidatePath(...)` (linha ~314):

```ts
// Resolução automática de Primary Species (Fatia C, Query 6116) — chamada
// separada e best-effort: uma falha aqui NUNCA deve alterar lastResult,
// que já reflete o resultado (bem-sucedido) da confirmação de Cards acima.
const { error: speciesError } = await supabase.rpc(
  "resolve_card_primary_species_for_catalog_import_job",
  { p_job_id: jobId },
);
if (speciesError) {
  console.error(`RESOLVE_CARD_PRIMARY_SPECIES_FOR_CATALOG_IMPORT_JOB_FAILED ${jobId}:`, speciesError);
}
```

Razões para este ponto (mantidas de AUDIT-01): chamada SQL síncrona e rápida, mesma natureza de `admin_confirm_catalog_import()` — não precisa do padrão `abrir*/executar*` de duas fases usado para imagens (que existe por causa de uma chamada HTTP externa longa). Chamada **uma única vez** ao final do laço inteiro, nunca por chunk.

### Ponto B — `confirmCatalogImport()` / revalidação (Edge Function) — NOVO nesta revisão

Dentro do bloco `if (unblockedCount > 0)` de `index.ts` (linhas ~200-203), logo depois de `confirmResult = await confirmCatalogImport(userClient, job.id)`:

```ts
let confirmResult: { inserted_count: number; updated_count: number; failed_count: number; job_status: string } | null = null;
if (unblockedCount > 0) {
  confirmResult = await confirmCatalogImport(userClient, job.id);

  // Resolução automática de Primary Species (Fatia C, Query 6116) — chamada
  // separada e best-effort. IMPORTANTE: usa userClient.rpc(...) diretamente
  // (checagem de { data, error }), nunca um helper que lança — este bloco
  // inteiro está dentro do try/catch POR JOB de index.ts (linha ~150), e uma
  // exceção aqui seria incorretamente reportada como jobResults[].error,
  // fazendo o job parecer falho mesmo com as Cards já persistidas.
  const { error: speciesError } = await userClient.rpc(
    "resolve_card_primary_species_for_catalog_import_job",
    { p_job_id: job.id },
  );
  if (speciesError) {
    console.error(`RESOLVE_CARD_PRIMARY_SPECIES_FOR_CATALOG_IMPORT_JOB_FAILED ${job.id}:`, speciesError);
  }
}
```

Só dispara quando `confirmCatalogImport()` de fato rodou (`unblockedCount > 0`) — se nenhuma linha foi destravada, não há `resulting_card_id` novo para processar, então não há por que chamar 6116 (seria um no-op idempotente, mas desnecessário).

Em **ambos** os pontos: `p_job_id` apenas, sem `p_row_ids` (ver seção 3), chamada via checagem direta de erro (não `try/catch` em torno de uma função que lança), e o erro nunca é escrito em `lastResult.error` (Fluxo A) nem em `jobResults[].error` (Fluxo B).

## 3. Contrato físico/API (v1.2 — `p_row_ids` removido em v1.1; `status` + guard de `source` adicionados em v1.2)

Ver `6116_create_resolve_card_primary_species_for_catalog_import_job_function.sql` (cabeçalho completo, seções "Correção v1.1"/"Correção v1.2"). Resumo:

```sql
resolve_card_primary_species_for_catalog_import_job(
    p_job_id UUID   -- obrigatório, único parâmetro
) RETURNS TABLE (
    status TEXT,                 -- 'SOURCE_NOT_TCGDEX' | 'NO_ELIGIBLE_CARDS' | 'PROCESSED'
    considered_count INTEGER,    -- Cards POKEMON elegíveis no job (0 se status != 'PROCESSED')
    resolved_count INTEGER,      -- repassado de resolve_card_primary_species_bulk()
    unchanged_count INTEGER,
    unresolved_count INTEGER,
    ambiguous_count INTEGER,
    conflict_count INTEGER,
    failed_count INTEGER,
    details JSONB
)
```

**Guard de `source` (v1.2, FINAL-CHECK-01):** a função carrega `catalog_import_job` completo e verifica `source` ANTES de tocar em `catalog_import_row.raw_data`. Para `source <> 'TCGDEX'` (hoje só `'PDF'` é possível, por CHECK da Query 2060): retorna `status = 'SOURCE_NOT_TCGDEX'`, todos os contadores em `0`, `details = '[]'`, **sem** ler `raw_data->'dexId'`, **sem** chamar `resolve_card_primary_species_bulk()` (Query 6115), **sem** nenhuma escrita em `card_primary_species`. Nunca `RAISE` — é um estado normal, não um erro de chamador. Isso é o que efetivamente protege o Fluxo B (`confirmCatalogImport`/revalidação), que é genérico e processa jobs de qualquer `source`.

**Por que `p_row_ids` foi removido:** a v1.0 (`AUDIT-01`) incluía `p_row_ids UUID[] DEFAULT NULL`, espelhando a assinatura de `admin_confirm_catalog_import()`, "para permitir uso pontual futuro". A reauditoria desta rodada mostra que **nenhum dos dois callers reais o exerceria**: o Ponto A chama uma vez, sem subconjunto, ao final do laço de chunks inteiro (não por chunk); o Ponto B (`confirmCatalogImport`) já sempre chama `admin_confirm_catalog_import()` com `p_row_ids: null` — nunca chunка. Um parâmetro sem nenhum caller real que o use é superfície de contrato sem benefício demonstrado (YAGNI). Removido nesta revisão (`DROP FUNCTION` defensivo incluído no arquivo, já que a v1.0 nunca foi promovida/executada em lugar nenhum). Pode ser reintroduzido no futuro, com justificativa própria, se surgir um caso de uso real (ex.: uma ferramenta administrativa para reprocessar manualmente um subconjunto específico de um job antigo).

`is_admin()`-gated, `SECURITY DEFINER SET search_path=''`, `GRANT EXECUTE TO authenticated` (mesma exposição de `admin_confirm_catalog_import()` — chamada pela mesma sessão administrativa nos dois fluxos: sessão do administrador no Fluxo A, `userClient` com o JWT do administrador no Fluxo B). Internamente delega 100% da decisão a `resolve_card_primary_species_bulk()` (Query 6115, `service_role`-only) — a chamada interna funciona por posse de função (SECURITY DEFINER + mesmo owner), sem precisar de nenhum `GRANT` novo em `card_primary_species` nem relaxar o `GRANT EXECUTE` de 6115. O invariante "só duas funções escrevem em `card_primary_species`" (6114/6115) permanece verdadeiro — 6116 nunca escreve na tabela diretamente, só orquestra.

## 4. Arquivos que precisariam mudar (implementação futura — NÃO feita nesta rodada)

| Arquivo | Mudança proposta |
|---|---|
| `database/schema/6116_create_resolve_card_primary_species_for_catalog_import_job_function.sql` | Promover o arquivo staged nesta pasta (após aprovação + implementação real no banco). |
| `web/app/catalogo/importar-cartas/tcgdex/actions.ts` | Ponto A — ver seção 2. Nenhuma mudança em `ConfirmarImportacaoResult` é estritamente necessária (resolução "melhor esforço", não reportada ao usuário nesta primeira integração); opcionalmente um campo informativo não-bloqueante no futuro, fora do escopo desta rodada ("não criar frontend novo"). |
| `supabase/functions/revalidate-catalog-import-rows/index.ts` | Ponto B — ver seção 2. Opcionalmente adicionar um campo informativo em `jobResults[]` (ex.: `primary_species_error: string \| null`), no mesmo espírito dos campos `confirm_*` já existentes — não obrigatório para o requisito de não-bloqueio, só para observabilidade. |
| `supabase/functions/revalidate-catalog-import-rows/services/database.ts` | Nenhuma mudança necessária — a chamada nova fica em `index.ts`, não dentro de `confirmCatalogImport()` (mantém essa função com responsabilidade única, mesma convenção do arquivo). |
| `web/lib/catalogo/queries.ts` | Nenhuma mudança obrigatória. |

Nenhum outro arquivo de frontend, nenhuma nova tela, nenhum novo componente — consistente com "não criar frontend novo".

## 5. Estratégia de erro não-bloqueante (nos dois fluxos)

Duas camadas independentes garantem o requisito crítico ("falha de Primary Species não pode reverter a confirmação, mudar status para FAILED/reportar erro no job, nem impedir criação/atualização de Cards") — válidas para os DOIS pontos de integração:

1. **Estrutural (banco), comum aos dois fluxos:** `resolve_card_primary_species_for_catalog_import_job()` é chamada numa transação/chamada RPC **separada**, depois que `admin_confirm_catalog_import()` já retornou e commitou — em ambos os callers. Não há como uma exceção nesta função reverter algo já commitado em uma chamada RPC anterior e distinta; propriedade da arquitetura de chamadas RPC do PostgREST (cada `supabase.rpc(...)`/`userClient.rpc(...)` é sua própria transação), não algo que dependa de cuidado no código.
2. **Aplicação (TypeScript), específica por fluxo:**
   - **Fluxo A:** checagem direta de `{ error }` (sem lançar), nunca escrita em `lastResult.error` — mesmo padrão já usado para a continuação de imagens (`supported: false` tratado como informativo).
   - **Fluxo B — cuidado adicional identificado nesta revisão:** todo o corpo do laço por job em `index.ts` já está dentro de um `try/catch` que popula `jobResults[].error` em caso de exceção. A chamada a 6116 usa `userClient.rpc(...)` diretamente (checagem de `{ data, error }`), **nunca** um helper que lança como `confirmCatalogImport()` — se fosse chamada via um helper que lança (ex.: reaproveitando o padrão de `confirmCatalogImport()`), uma falha na resolução de Species seria incorretamente capturada pelo `catch` externo do job e reportada como falha da confirmação inteira. Este é exatamente o tipo de armadilha que a divergência desta rodada expôs — vale a pena registrar explicitamente como risco de implementação a não repetir.

Em nenhum dos dois fluxos uma falha aqui muda `catalog_import_job.status`, marca o job como `FAILED`, ou impede que Cards já persistidas continuem persistidas.

## 6. Avaliação de cenários especiais (revisada)

- **Confirmação em batches via `p_row_ids` (Fluxo A):** `confirmarImportacao()` fragmenta a CONFIRMAÇÃO em lotes de 50, mas a RESOLUÇÃO DE SPECIES é chamada uma única vez, sem subconjunto, ao final do laço inteiro — ver seção 3 para por que `p_row_ids` foi removido do contrato de 6116.
- **Revalidação posterior de linhas (Fluxo B):** `svc_apply_catalog_import_revalidation` só reabre linhas `FAILED`, nunca toca `resulting_card_id` de linhas já persistidas. Quando destrava pelo menos uma linha, o próprio `index.ts` já chama `confirmCatalogImport()` — e, com esta integração, 6116 logo em seguida — cobrindo exatamente as linhas recém-persistidas sem nenhum caso especial adicional.
- **Jobs parcialmente confirmados:** a função deliberadamente NÃO verifica `catalog_import_job.status` — um job em `CONFIRMING` (decisões pendentes, ou uma chamada anterior interrompida, em qualquer um dos dois fluxos) já pode ter algumas linhas com `resulting_card_id` setado; essas Cards são resolvidas imediatamente. Uma chamada futura, em qualquer um dos dois fluxos, processa o resto — sem duplicar trabalho sobre as já resolvidas (idempotência de 6115).
- **Reexecução:** chamar a função repetidamente para o mesmo job — inclusive alternando entre os dois fluxos (ex.: confirmado parcialmente pelo Fluxo A, retomado depois pelo Fluxo B após uma revalidação) — é sempre seguro: leitura pura de `catalog_import_row` + delegação a uma função já comprovadamente idempotente. Nenhum estado próprio é mantido.
- **Duplicação de lógica entre callers:** com os dois callers reais mapeados, o ponto de integração único (6116) elimina o risco por construção — nenhum dos dois fluxos reimplementa a agregação de evidência ou a lógica de decisão; ambos só invocam a mesma função. Se um terceiro caller de `admin_confirm_catalog_import()` surgir no futuro, deve chamar 6116 da mesma forma, nunca duplicar a lógica de agregação.

## 7. Testes necessários (revisado — implementação futura)

1. Job `source = 'PDF'` com Cards POKEMON já confirmadas (`resulting_card_id` setado) → `status = 'SOURCE_NOT_TCGDEX'`, todos os contadores `0`, `details = []`, **zero linhas lidas de `raw_data`** (verificável indiretamente: nenhuma escrita mesmo que o `raw_data` daquele job PDF contenha, por coincidência, uma chave `dexId`).
2. Job `source = 'TCGDEX'` 100% TRAINER/ENERGY → `status = 'NO_ELIGIBLE_CARDS'`, `considered_count = 0`, nenhuma chamada a 6115.
3. Job `source = 'TCGDEX'` com Cards POKEMON + `resulting_card_id` de INSERT (NEW), UPDATE (CONFLICT aprovado) e UNCHANGED (MATCHED) → `status = 'PROCESSED'`, todos os três `persistence_status` contribuem evidência igualmente.
4. Confirmar que a função só olha `resulting_card_id`, nunca `matched_card_id` (ver risco dos 168 casos históricos).
5. Chamada dupla consecutiva sobre o mesmo job TCGDEX (mesmo fluxo) → segunda chamada devolve `status = 'PROCESSED'`, `unchanged_count = considered_count`, zero escrita nova.
6. Job TCGDEX sem nenhuma Card com `dexId` sobrevivente em `raw_data` → `status = 'PROCESSED'`, todas `UNRESOLVED`/`NO_DEX_ID_EVIDENCE`.
7. Job TCGDEX com uma Card cujo dexId aponta para `pokemon_species` inexistente → `UNRESOLVED`/`DEX_ID_NOT_FOUND_IN_SPECIES_CATALOG`.
8. Job TCGDEX com uma Card cujas linhas trazem dexIds distintos entre si → `AMBIGUOUS`.
9. `p_job_id` inexistente → `RAISE EXCEPTION` claro (nunca um `status` de resultado — categoria de erro diferente de `SOURCE_NOT_TCGDEX`).
10. Chamador não-admin (sessão `authenticated` sem linha em `admin_user`) → `RAISE EXCEPTION ..._FORBIDDEN`.
11. **Fluxo A, integração fim-a-fim:** simular `confirmarImportacao()` completo com a chamada nova e um erro forçado nela (mock retornando `{ error }`) — confirmar que `lastResult.error` permanece `null` e todas as Cards do job continuam persistidas.
12. **Fluxo B, integração fim-a-fim:** simular `revalidate-catalog-import-rows` com `unblockedCount > 0`, `confirmCatalogImport()` bem-sucedido, e um erro forçado na chamada a 6116 — confirmar que `jobResults[].error` permanece `null`, `jobResults[].job_status` reflete o `job_status` de `confirmCatalogImport()` normalmente, e o `success: true` de nível de resposta da Edge Function não é afetado.
13. **Fluxo B, cenário de regressão específico:** confirmar explicitamente que a chamada a 6116 usa checagem de `{ error }` e NÃO um helper que lança — um teste que troque a implementação por um helper que lança (`throw`) deve falhar, provando que o `catch` por job de `index.ts` capturaria a exceção incorretamente.
14. **Fluxo B com job PDF (novo nesta rodada):** simular `revalidate-catalog-import-rows` revalidando e confirmando um job `source = 'PDF'` (cenário real, já que este fluxo é genérico) — confirmar que a chamada a 6116 retorna `status = 'SOURCE_NOT_TCGDEX'` e `card_primary_species` permanece sem nenhuma linha nova para aquele job.
15. Alternância entre os dois fluxos no mesmo job TCGDEX (Fluxo A confirma parcialmente, Fluxo B retoma depois de uma revalidação) → cobertura final agregada correta, sem duplicação nem perda.

## Débito registrado (não investigado nesta rodada, por mandato)

Os 168 casos de `AMBIGUOUS` encontrados na primeira tentativa de dry run (usando `matched_card_id`, achado independente corrigido em `BACKFILL-DRY-RUN-FIX-01`) permanecem como débito de qualidade histórica do pipeline de matching TCGdex — candidatos a uma investigação futura e separada sobre por que `matched_card_id` associou dexIds sem relação (ex.: Geodude ↔ `[74, 386]`) em reimportações antigas. Não afeta esta integração incremental, que usa exclusivamente `resulting_card_id`.

## GO/NO-GO

**GO para implementação.** Desenho fechado após três rodadas de auditoria (AUDIT-01 → REVISION-01 → FINAL-CHECK-01), cada uma corrigindo um achado real e concreto — nenhum deles cosmético:
- REVISION-01: call graph incompleto (segundo caller real de `admin_confirm_catalog_import()` não mapeado) — corrigido, reauditado com `grep` irrestrito, dois callers confirmados, nenhum terceiro.
- FINAL-CHECK-01: ausência de guard de `source` em 6116 — corrigido (carrega o job, `status = 'SOURCE_NOT_TCGDEX'` sem escrita para `source <> 'TCGDEX'`), confirmado por auditoria focada (a v1.1 realmente não tinha nenhuma menção a `source` em todo o arquivo).

Condicionado, na implementação:
- Fluxo A implementado exatamente como na seção 2 (checagem de erro, nunca `lastResult` alterado).
- Fluxo B implementado com o cuidado explícito da seção 5 (checagem direta de `{ error }`, nunca um helper que lança, para não ser capturado pelo `catch` por job já existente em `index.ts`).
- Os 15 testes da seção 7 escritos antes da promoção para `database/schema/` — em particular os testes 1 e 14 (guard de `source`), que são os únicos que exercitam a correção desta rodada.

## Fora de escopo desta rodada

Frontend novo, Fatias D/E, execução de SQL contra o banco real, promoção para `database/schema/`, edição real de `actions.ts`/`index.ts` (só proposto em texto acima), documentação canônica (`docs/`), `git add`/`commit`/`push`, investigação dos 168 casos históricos de `matched_card_id`.
