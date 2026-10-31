# Leitura de uma coleção por id — `get_my_collection(uuid)`

| Campo | Valor |
|---|---|
| Frente | COLLECTION PERFORMANCE — TARGETED READ PROPOSAL-02 (Alternativa A aprovada em ROOT CAUSE & MINIMAL REMEDIATION-01) |
| Status | **5332 CONFIRMADO EXECUTADO no LIVE em 2026-10-31** (ledger `20261031130535`) e **promovida para `database/schema/`**. **5865 v1.3 CONFIRMADO EXECUTADO — GATE 17/17 PASS** (RETEST-06). **Frontend integrado localmente** (FRONTEND INTEGRATION-07: `getMyCollection()` chama `get_my_collection`; typecheck e testes PASS; RPC exposta pelo PostgREST). Pendentes: lint/build na máquina de Fabrício, homologação funcional, commit e deploy. |
| Data | 2026-10-31 |
| Arquivos | `5332_create_get_my_collection_function.sql` v1.0 (função), `5865_validate_get_my_collection.sql` v1.3 (harness) |
| Numeração | 5332 e 5865 conferidas livres em `database/schema`, `database/migrations`, `database/proposals` e `docs/` (maiores em uso: 5331 e 5864) |

## Problema

`getMyCollection()` (`web/lib/colecoes/colecoes-queries.ts`) abre uma coleção chamando `get_my_collections(true, 100, offset)` (R1, Query 5182) e filtrando o id no Node. Para cada coleção da página, R1 executa `collection_completion_summary()` (5188: Set, Master Set, Pokédex), a contagem de exemplares e a busca da capa. Toda ação do fichário revalida a página da coleção, então cada carta colocada repete esse custo. Diagnóstico completo e evidências de log na rodada ROOT CAUSE & MINIMAL REMEDIATION-01.

## Contrato proposto (5332)

- Mesmas 19 colunas de R1 (nomes, tipos, ordem). `pg_get_function_result` idêntico — conferido no harness (0.3).
- 18 colunas com o mesmo valor da linha de R1 com `p_include_archived = true`; `total_count = 1`.
- Filtro `c.id = p_collection_id AND c.owner_user_id = auth.uid()` no CTE `mine`, antes dos três `LATERAL` (0.5).
- Arquivadas incluídas. Inexistente ou alheia: zero linhas, sem distinção (não enumera). Id nulo: 22023. Sem identidade: 28000. `anon`: sem `EXECUTE` (42501).
- `SECURITY DEFINER`, `search_path = ''`, objetos qualificados, `STABLE`, `plpgsql` — mesmo padrão de R1. Grants: só `authenticated`.
- R1 não muda (harness 0.4 confere o md5 do corpo de R1 = 5182, `08fc4dd1…`).

## Harness (5865) — 17 checagens, GATE 17/17

Estrutura e ACL (0.1–0.5), sessão anônima, sem identidade e id nulo (1.1, 2.1, 2.2), fixture sintética com usuários efêmeros — livre, Set com 1 exemplar e capa, Pokédex, arquivada, tentativa de Master Set (3.1–3.6), e **dados reais em modo somente leitura** do usuário informado em `v_owner` (4.1 equivalência de todas as coleções; 4.2 redução de trabalho numa amostra determinística de até 3 coleções — tipos caros primeiro: Pokédex, Master Set, Set padrão, a de mais exemplares em cada). Sentinela `TR000` desfaz tudo o que o harness cria; 9.1 confere resíduo zero. Antes de executar, preencher `v_owner` (sem isso 4.1/4.2 falham de propósito).

**Medição em 4.2 (v1.2).** Trabalho = blocos de buffer (shared hit + read) de uma execução instrumentada (`EXPLAIN ANALYZE, BUFFERS`) de cada caminho, mais o nº de resumos calculados (linhas de R1 lidas × 1). É o critério do GATE: não depende da concorrência do momento. Tempo = mediana de 3 rodadas intercaladas, **só informativo** — o LIVE é compartilhado (rotinas agendadas, outros acessos, cache), então uma medição isolada lenta não pode reprovar a mudança. Limitações: blocos contam acertos de cache e não separam CPU; o EXPLAIN mostra a função como um único nó (sem plano interno), mas os blocos acumulados incluem o que ela executa. Carga máxima no LIVE: 3 coleções × (1 + 3) leituras atuais e 3 × (1 + 3) chamadas da nova (antes: 5 + 5 para cada coleção real).

## Resultado no LIVE (5865 v1.3, 2026-10-31)

17/17 PASS. 3.1: 5 coleções sintéticas, 0 divergências (Master Set sintético ativado). 3.3: 0 linhas A→B e B→A. 4.1: 10 coleções reais, 0 divergências (4 Master Set, 4 Set padrão, 1 Pokédex, 1 livre). 4.2: amostra de 3 coleções; blocos 39.599 → 8.498 (razão 0,215); resumos calculados 30 → 3; mediana informativa ~31–34 ms → ~7–10 ms por abertura. 9.1: resíduo zero.

## Publicação (ordem obrigatória)

1. ~~Aplicar 5332~~ — feito (2026-10-31).
2. ~~Executar 5865 com `v_owner` preenchido~~ — feito, GATE 17/17 (v1.3).
3. ~~`NOTIFY pgrst`~~ — executado em 2026-10-31; a API reconhece a função (anon recebe 42501, não `PGRST202`). Executar `NOTIFY pgrst, 'reload schema';` (o Supabase já recarrega o cache do PostgREST após DDL; o comando é inofensivo e elimina a dúvida). Confirmação de que a API expõe a função: rodar o frontend alterado localmente (`npm run dev` usa o mesmo banco LIVE) e abrir uma coleção — deve abrir normalmente; `PGRST202` no terminal = cache não recarregado, repetir o `NOTIFY`.
4. Só então liberar o frontend (commit/push/deploy autorizados por Fabrício).

Ausência da função vista pelo cliente: o PostgREST responde HTTP 404 com `code: "PGRST202"` ("Could not find the function … in the schema cache"); `42883` (`undefined_function`) só aparece se o cache apontar para uma função que deixou de existir no banco. **Sem fallback para R1**: a ordem acima garante a função antes do código; se `PGRST202`/`42883` aparecer em produção, o frontend registra `logReadFailure("get_my_collection", …)` e mostra o estado de falha já existente ("Não conseguimos abrir esta coleção") — o rollback é reverter o commit, não manter a leitura cara escondida.

## Frontend (mudança mínima — implementada localmente em 2026-10-31)

Só `getMyCollection()` em `web/lib/colecoes/colecoes-queries.ts`: trocar o laço de páginas de R1 por uma chamada única `supabase.rpc("get_my_collection", { p_collection_id: id })`; `[]` → `undefined` (404 da página, como hoje); erro ou resposta que não seja lista → `null` (falha de leitura, como hoje, com `logReadFailure("get_my_collection", …)`); primeira linha → `toSummary(row)` (hoje é `rows.find`, que também pega a primeira; o harness exige exatamente 1 linha) (mesmo mapeamento, mesmo tipo `CollectionRow`). Consumidores: `app/colecoes/colecoes/[id]/page.tsx` e `app/colecoes/colecoes/[id]/fichario/page.tsx` — assinatura e retorno de `getMyCollection` inalterados, nenhuma outra mudança. Biblioteca, contagem de arquivadas e `getMyBinderTransferContext` continuam em R1.

## Aceitação

GATE 17/17 (inclui 4.1 sem divergência em todas as coleções reais e 4.2 com menos blocos lidos pela leitura nova na amostra); typecheck, testes, lint e build; abertura manual de uma coleção de cada tipo; no log do Supabase, `get_my_collection` com tempo próximo ao de um único resumo durante uma sequência de ~10 cartas colocadas no fichário.

## Rollback

Reverter o commit do frontend (volta a R1). Se necessário, `DROP FUNCTION public.get_my_collection(uuid);` — nada depende dela, nenhum dado é alterado, R1 permanece intacta.

## Riscos que permanecem

- Divergência futura entre 5332 e R1: toda mudança em R1 deve ser espelhada (regra registrada no cabeçalho de 5332; o harness 4.1 detecta).
- A lentidão geral da instância observada em 2026-10-30/31 não é resolvida por esta leitura; ela só reduz a carga e a chance de timeout. Revalidação ampla das ações do fichário (Alternativa B) segue fora de escopo.
- JustTCG: nenhuma alteração sem evidência causal. Métricas úteis se os episódios continuarem: CPU e Disk IO budget da instância (Supabase Reports → Database) nas janelas dos episódios; `pg_stat_statements` (total/média/máximo por consulta, antes e depois); `pg_stat_activity` capturado durante um episódio (espera por `wait_event_type`); contagem de conexões; histórico de autovacuum nas tabelas de Pricing e Collection.
