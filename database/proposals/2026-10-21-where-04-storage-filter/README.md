# WHERE-04 — Filtro do Meu acervo por localização física — ETAPA DE BANCO EXECUTADA (canônica em database/schema/)

| Campo | Valor |
|---|---|
| Frente | Organização física — WHERE-04 (filtros do Meu acervo por local) |
| Rodada | WHERE-04 CONTRACT GAP RESOLUTION (2026-10-21) |
| Status | **EXECUTADA / CANÔNICA (etapa de banco).** `5220` aplicada no LIVE em 2026-10-22 UTC (autorização de Fabrício; ledger `20261022021252`; corpo da função idêntico ao arquivo). Harness `5848`: v1.0 49/50 (falha só na 5.9, por erro do próprio harness — esperado lido de `card`/`card_variant` sob `authenticated`, que a RLS admin-only esvazia); **v1.1 50/50 PASS**, GATE `PASS_FUNCTIONAL_PERF_NOT_MEASURED`, 99.1 resíduo zero, contagens idênticas antes/depois. Security Advisor sem achado novo. **Desempenho NÃO medido** (Seção P não executada no LIVE). Promovida para `database/schema/5220_…` (do `begin;` em diante idêntica ao aplicado; o arquivo desta pasta permanece byte a byte o executado); `5159` canônica com nota de substituição. **Frontend WHERE-04 pendente.** |
| Base | `HEAD 12f57c5` (WHERE-03 homologada); 5159 canônica em `database/schema/` |
| Arquivos | `5220_evolve_get_my_inventory_items_storage_filter.sql`, `5848_validate_where_04_storage_filter.sql` |

## 1. Diagnóstico de compatibilidade da 5159

- **Assinatura vigente** (canônica, executada em 2026-10-17, 5827 52/52): `get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer)`, todos os parâmetros com default; retorno de 14 colunas; `SECURITY DEFINER`, `STABLE`, `search_path ''`; `EXECUTE` só `authenticated`.
- **Por que DROP + CREATE e não `CREATE OR REPLACE`:** acrescentar parâmetros muda a lista de argumentos — `CREATE OR REPLACE` criaria uma **segunda sobrecarga** (ambiguidade no PostgREST); e mudar `RETURNS TABLE` é proibido em `CREATE OR REPLACE`. A 5220 faz `DROP` da assinatura antiga e `CREATE` da nova **na mesma transação** (sessões concorrentes continuam vendo a versão antiga até o `COMMIT`).
- **Dependências no banco:** `pg_depend` não registra chamadas dentro de corpos PL/pgSQL; por isso a 5220 tem pré-checagem que **falha alto** se (a) a assinatura antiga não existir, (b) houver outra sobrecarga, (c) houver view/regra dependente, (d) faltar algum dos dois índices usados. No repositório, **nenhuma função SQL** chama `get_my_inventory_items` (busca em `database/`: só a própria 5159 e harnesses).
- **Efeitos do DROP:** comentário e grants pertencem ao objeto e somem com ele — a 5220 recria ambos para a assinatura nova (`REVOKE` de `PUBLIC` e `anon` explícito, porque as permissões padrão do Supabase concederiam `EXECUTE` a `anon`). `notify pgrst, 'reload schema'` dentro da transação faz o PostgREST trocar o cache da assinatura no `COMMIT`.
- **Conclusão: evolução direta é compatível.** Nenhuma incompatibilidade material encontrada.

## 2. Matriz de regressão dos consumidores

| Consumidor | Argumentos enviados (todos por nome) | Colunas lidas | Efeito da 5220 |
|---|---|---|---|
| `web/lib/colecoes/acervo-queries.ts` `getAcervoItems` (galeria) | os 8 atuais (`toItemsRpcParams`) | 14 atuais via `toItem` | nenhum: params novos assumem default; colunas novas ignoradas |
| `web/lib/colecoes/colecoes-queries.ts` `getAvailableGroupCount` | 8 atuais, `p_without_collection = true`, `p_limit 1` | `total_count` | nenhum |
| `web/app/colecoes/colecoes/actions.ts` (~l.824, exemplares de uma carta do Set) | 8 atuais | `card_variant_id`, `language_code`, `collector_number` | nenhum |
| `web/app/colecoes/colecoes/actions.ts` (~l.1349, opções de vínculo por Set, paginado) | 8 atuais | colunas de identificação/rotulagem | nenhum |
| Funções SQL do banco | — (nenhuma encontrada) | — | pré-checagem confirma ausência de dependentes rastreáveis |

O PostgREST resolve por nome de argumento: chamadas com subconjunto de argumentos continuam válidas porque os dois novos têm default. A 5848 (seção 2) repete os valores da 5827 (4.2–4.15) sem os parâmetros novos.

## 3. Contadores — definição exata

**Item** = grupo Card Variant + idioma (definição da 5159, inalterada).

| Coluna | Definição | Afetada por |
|---|---|---|
| `copies_count` | Exemplares do item que atendem a **todos** os filtros por exemplar | idioma, coleção, sem coleção, **local**, **sem local** |
| `copies_owned` (nova) | **Todos** os exemplares do item no acervo, sem filtro algum | nada (busca, Set e idioma definem o item, não o exemplar) |
| `total_count` | Itens distintos que atendem aos filtros (paginação) — semântica da 5159 | todos os filtros |
| `total_copies` (nova) | Soma de `copies_count` de todos os itens que atendem aos filtros, em **todas** as páginas | todos os filtros |

Invariantes (provados na 5848 5.10): `1 ≤ copies_count ≤ copies_owned`; `total_copies ≥ total_count`; sem filtro por exemplar, `copies_owned = copies_count`; sem filtro algum, `total_copies` = exemplares do acervo.

Combinações: os filtros por exemplar se somam (E lógico) **antes** do agrupamento — ex.: coleção C + sem localização = exemplares que estão em C **e** sem local; `copies_owned` continua sendo o total do item. Busca e Set filtram itens depois do agrupamento (como hoje).

Exemplo obrigatório (5848 seção 3): carta com 5 exemplares (2 Fichário A, 1 Caixa B, 2 sem local) → Todos 5/5; Fichário A 2/5; Caixa B 1/5; Sem localização 2/5; a carta aparece uma vez em cada lista.

## 4. Segurança

- Dono nunca é parâmetro: `inventory.owner_user_id = auth.uid()`; sem sessão → `28000`.
- O filtro de local é aplicado **sobre os exemplares do acervo do chamador**; a FK composta da 5023 garante que um exemplar só aponta para local do mesmo Inventory. Local de outro usuário ou inexistente → **vazio**, idêntico a um local próprio vazio (não enumera, não revela existência).
- `INVALID_STORAGE_FILTER` (22023) para local + sem local juntos.
- `copies_owned` conta só `physical_card` do Inventory do chamador.
- Privilégios iguais à 5159: `SECURITY DEFINER`, `STABLE`, `search_path ''`, objetos qualificados, `EXECUTE` só `authenticated`.
- 5848 seção 4: anon, sem identidade, combinação inválida, local inexistente, local de outro usuário (nos dois sentidos), controle positivo, usuário sem acervo, leitura direta de `physical_card` alheia = 0.

## 5. Plano de validação de desempenho

- **Índices:** `ix_physical_card_inventory_variant (inventory_id, card_variant_id)` — entrada atual da 5159 e das contagens de `copies_owned` (≤ 96 buscas, só quando há filtro por exemplar); `ix_physical_card_storage_container (storage_container_id)` — candidato do planejador para local específico. "Sem localização" percorre o acervo do usuário (mesmo custo do caminho atual). **Nenhum índice novo** sem evidência de necessidade.
- **Medição (5848 Seção P, `p_perf = true`):** 20.000 exemplares sintéticos (~6.700 num local grande, 50 num pequeno, resto sem local); 30 execuções por cenário; p95 e mediana: sem filtro RECENT, SET_NUMBER, busca, local pequeno, local grande, sem localização, sem localização pág. 21, local grande + SET_NUMBER, local grande + idioma, sem localização + busca. Meta B4: p95 ≤ 150 ms.
- **Comparação com o comportamento atual:** rodar a 5827 Seção P (`p_perf = true`) **antes** da 5220 e a 5848 Seção P **depois**, no mesmo ambiente; comparar P.1–P.3 (mesmas consultas).
- **Não há PASS de desempenho sem medição:** sem `p_perf`, o GATE é `PASS_FUNCTIONAL_PERF_NOT_MEASURED`.
- Se algum cenário passar de 150 ms: `EXPLAIN (ANALYZE, BUFFERS)` da consulta interna correspondente antes de qualquer índice novo.

## 6. Riscos remanescentes

| # | Risco | Mitigação |
|---|---|---|
| R1 | Janela entre `COMMIT` e recarga do cache do PostgREST (galeria responde "função não encontrada" por instantes) | `notify pgrst` na mesma transação; executar fora de horário de uso; a galeria já trata falha de leitura com estado de erro |
| R2 | Chamador futuro posicional (não por nome) quebraria se a ordem mudasse | parâmetros novos ao **final**; todos os chamadores atuais usam nomes |
| R3 | Seção P no LIVE concorre com a carga real | preferir ambiente isolado; transação revertida (sem resíduo) |
| R4 | Harness sem execução real ainda (só verificação estática: blocos, parênteses, ids) | primeira execução é a prova; X.1 captura qualquer erro inesperado sem deixar resíduo |
| R5 | A 5827 permanece válida contra a assinatura nova? | sim, chama por nome; o seu teste 0.1 usa `to_regprocedure` da assinatura **antiga** e passaria a falhar — esperado: a 5827 é evidência histórica; a regressão vigente é a 5848 seção 2 |

## 7. Plano de execução (depois da autorização)

1. **Pré-check (somente leitura):** `select pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid) from pg_proc p where p.proname = 'get_my_inventory_items';` → exatamente 1 linha, assinatura de 8 argumentos e retorno de 14 colunas. Linha de base: `count(*)` de `physical_card`, `collection`, `collection_allocation`, `storage_container`.
2. (Opcional, recomendado) 5827 Seção P para linha de base de desempenho.
3. Aplicar `5220` (uma transação; a pré-checagem falha alto e não altera nada se algo divergir).
4. Pós-check estrutural: 1 sobrecarga, assinatura de 10 argumentos, retorno de 16 colunas, `EXECUTE` só `authenticated`.
5. `5848` com `false` → GATE `PASS_FUNCTIONAL_PERF_NOT_MEASURED`, 50/50; depois com `true` (ambiente isolado de preferência) → GATE `PASS`.
6. Pós-check: contagens iguais à linha de base (99.1 já prova dentro do statement).
7. Security Advisor: nenhum achado novo além do padrão (`authenticated_security_definer_function_executable` mantém a mesma contagem — a função é substituída, não acrescentada).
8. Smoke da galeria atual (sem frontend novo): `/colecoes/acervo` carrega igual.
9. Promoção canônica: a 5220 vira a definição canônica do objeto (padrão uma definição por objeto, como `5024`×`5138`): `database/schema/5159_…` recebe o corpo efetivo da 5220 com nota de fold-in, ou a 5220 é promovida e a 5159 recebe nota de supersessão — **decisão de Fabrício**.

## 8. Rollback

Na mesma transação (só se necessário):

```sql
begin;
drop function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean);
-- reaplicar integralmente database/schema/5159_create_get_my_inventory_items_function.sql (corpo entre begin; e commit;)
notify pgrst, 'reload schema';
commit;
```

Sem perda de dados: a função é só leitura. O frontend atual não depende das colunas novas.

## 9. Verificações estáticas feitas

- 5220: `$$` e `$pre$` balanceados; um `begin;`/`commit;`; parênteses do corpo balanceados; diferença para a 5159 restrita a: pré-checagem, `DROP`, 2 parâmetros, 2 colunas, 3 variáveis, 1 erro novo, 2 predicados por exemplar (nos dois caminhos), 2 somas de janela, 1 `LATERAL` de `copies_owned`, comentário/grants com a assinatura nova, `notify pgrst`.
- 5848: `$fn$` balanceado; blocos `begin`/`end` e parênteses conferidos; 50 ids funcionais distintos (= `v_expected`); P.1–P.10 só com `p_perf`.
- Nenhuma execução em banco algum (sintaxe será provada na primeira execução autorizada).
