# WHERE-05A — Organização física em lote contextual à coleção — ETAPA DE BANCO EXECUTADA (canônica em database/schema/)

| Campo | Valor |
|---|---|
| Frente | Organização física — WHERE-05A (organizar as cartas de uma coleção no local padrão dela) |
| Rodada | WHERE-05A CONTRACT GAP RESOLUTION — QUERIES 5221/5222 + HARNESS 5849 (2026-10-22) → LIVE CONTRACT EXECUTION → DATABASE CONTRACT CLOSEOUT |
| Status | **EXECUTADA / CANÔNICA (etapa de banco).** `5221` e `5222` **v1.2** aplicadas no LIVE em 2026-10-22 UTC (autorização de Fabrício; ledger `20261022194133` e `20261022194352`; corpos idênticos aos arquivos). Harness `5849` **v1.4: 50/50 PASS**, GATE `PASS_FUNCTIONAL_LIMIT_NOT_EXERCISED`, 99.1 resíduo zero (histórico v1.2 → v1.4 em §15). **Desempenho NÃO medido**; L.1/L.2 e K1–K4 não exercitados. Promovidas para `database/schema/` (do `begin;` em diante idênticas ao aplicado; os arquivos desta pasta permanecem byte a byte os executados). Rodadas de contrato anteriores: CONTRACT CONCURRENCY CORRECTION-01 (trava de todo o universo do token) e CONTRACT CORRECTION-02 (D6; travas de exemplar em laço ordenado). **Frontend WHERE-05A pendente (não iniciado).** |
| Base | `HEAD 3fc06b8` (WHERE-04 encerrada). Contratos vigentes intactos: 5024, 5036, 5046, 5047, 5210, 5218, 5219, 5220. |
| Decisões | D1 contrato por coleção · D2 destino = local padrão vigente (`DEFAULT_CHANGED`) · D3 teto 10.000 por operação (proposta, não capacidade comprovada) · D4 desempenho com ressalva, sem carga no LIVE · D5 histórico fora do escopo · **D6 teto de 10.000 também sobre o total alocado à coleção (aprovada)** |

## 1. Arquivos

| Arquivo | Conteúdo |
|---|---|
| `5221_create_get_my_collection_storage_plan_function.sql` | Helper interno `collection_storage_plan_snapshot(uuid, uuid)` (fonte única de contagens e `plan_token`) + RPC pública `get_my_collection_storage_plan(uuid, uuid)` |
| `5222_create_organize_my_collection_storage_function.sql` | RPC pública `organize_my_collection_storage(uuid, uuid, text, integer, text)` — gravação atômica com revalidação |
| `5849_validate_where_05a_collection_storage.sql` | Harness (`pg_temp`, sentinela `MS849`, resíduo zero): 50 verificações funcionais + Seção L opcional |

Nenhum contrato existente é alterado. Não há tabela nova (D5).

## 2. Contratos

### 5221 — prévia

`get_my_collection_storage_plan(p_collection_id uuid, p_storage_container_id uuid)` → **uma linha**:

| Coluna | Significado |
|---|---|
| `collection_id`, `storage_container_id` | O que foi pedido |
| `collection_active` | Coleção ativa (a 5222 recusa arquivada) |
| `target_is_default` | Destino = local padrão vigente (a 5222 exige — D2) |
| `total_count` | Exemplares **efetivamente alocados** à coleção |
| `unlocated_count` / `at_target_count` / `elsewhere_count` | Sem localização / já no destino / em outro local |
| `eligible_unlocated` | O que **UNLOCATED** moveria (= `unlocated_count`) |
| `eligible_all` | O que **ALL** moveria (= `total_count − at_target_count`) |
| `max_per_operation` | 10.000 (D3) |
| `plan_token` | Identificação verificável da prévia (`v1:` + md5) |

Não devolve lista de exemplares. Invariantes: `total = unlocated + at_target + elsewhere`; `eligible_all = unlocated + elsewhere`.

### 5222 — execução

`organize_my_collection_storage(p_collection_id, p_storage_container_id, p_mode 'UNLOCATED'|'ALL', p_expected_count, p_plan_token)` → `collection_id, storage_container_id, mode, moved_count, total_count, at_target_count` (contagens após a operação).

- **UNLOCATED**: só exemplares da coleção sem localização; não toca os que estão em outros locais nem os já no destino.
- **ALL**: todos os exemplares da coleção que ainda não estão no destino.
- Escreve **só** `physical_card.storage_container_id` (e `updated_at`, pelo trigger 5011). Vínculos, variante, idioma, condição, posições (Master Set, Pokédex, fichário) e demais coleções: intocados. Não cria nem remove exemplar.

## 3. Pré-condições de execução

1. 5024, 5036, 5040–5047, 5210, 5218, 5219 no LIVE (confirmado em `database/schema/`).
2. Índices `ix_collection_allocation_collection` (5040) e PK de `physical_card` (5010) — a 5221 confere na pré-checagem.
3. Funções novas ausentes — as duas Queries falham alto se já existirem.
4. Ordem obrigatória: **5221 → 5222 → 5849**.

## 4. Universo e identificação da prévia

**Universo**: `collection_allocation.collection_id = coleção` — 0..1 coleção por exemplar (`physical_card_id UNIQUE`, 5040). Nunca entram cartas do catálogo da expansão, posições do checklist / Master Set / Pokédex sem exemplar, nem exemplares do acervo fora da coleção.

**`plan_token`** = `'v1:' || md5(coleção | destino | lista ordenada por id de "id:local_atual" de TODOS os exemplares alocados)`. Cobre:

| Mudança entre prévia e execução | Detectada por |
|---|---|
| Destino diferente | token (o destino entra no hash) e `DEFAULT_CHANGED` |
| Exemplar entra ou sai da coleção | token (composição) |
| Local de qualquer exemplar da coleção muda | token (local anterior) |
| Modalidade trocada | `p_expected_count` comparado com o elegível da modalidade |
| Quantidade diferente da exibida | `p_expected_count` e a contagem dos elegíveis |

Os números exibidos e o conjunto elegível derivam do mesmo estado coberto pelo token. Na 5222 **v1.1**, **todo** esse estado fica travado antes da conferência final: a composição, pela trava da coleção; o local de cada exemplar, pela trava de linha de **todos** os exemplares alocados. Assim, se o token confere, ele continua valendo até o `COMMIT`, e o conjunto movido é exatamente o autorizado. **Nunca há substituição silenciosa**: qualquer diferença → `PLAN_CHANGED`, nada gravado, e a interface (futura) busca nova prévia e pede nova confirmação.

## 5. Estratégia de locks

Inventário das travas vigentes (lido em `database/schema/`):

| Operação | Primeira trava |
|---|---|
| 5046 vincular, 5047 desvincular, 5039 excluir coleção, 5210 Pokédex, 5150/5153 cadastro em lote | `collection` **FOR UPDATE** |
| 5036 local padrão, 5037/5038 arquivar/reativar | `UPDATE collection` (trava a linha) |
| 5024 mover exemplares | `UPDATE physical_card` nas linhas, sem ordem; FK → `FOR KEY SHARE` no local |
| 5217 renomear / 5218 excluir local | `storage_container` **FOR UPDATE** |
| 5165 remover exemplar | `physical_card` **FOR UPDATE** (recusa se alocado) |

Ordem da 5222 **v1.2** (sempre a mesma):
1. `collection FOR UPDATE`.
2. Destino `FOR KEY SHARE`.
3. Tetos: D6 sobre o **total** alocado e D3 sobre os elegíveis. Ambos são contagens sem trava de exemplar.
4. **Todos** os exemplares alocados, travados **um a um** com `FOR UPDATE NOWAIT`, num laço `FOREACH` sobre a lista ordenada por id.
5. Seleção dos elegíveis dentro do conjunto travado.
6. Recálculo do token.
7. `UPDATE` só dos elegíveis.

**Por que a ordem de aquisição é determinística (e não só "tem ORDER BY")**
- A lista vem de `array_agg(ca.physical_card_id ORDER BY ca.physical_card_id)`. O `ORDER BY` **dentro** do agregado define a ordem dos elementos do array; isso é garantia documentada do PostgreSQL para agregados ordenados, não um efeito do plano.
- O laço `FOREACH v_id IN ARRAY v_all` executa **um** `PERFORM … WHERE pc.id = v_id FOR UPDATE NOWAIT` por elemento, em sequência. Cada comando trava no máximo uma linha (busca pela PK) e só começa depois que o anterior termina.
- Logo, a ordem de aquisição **é** a ordem do array por construção, sem depender de onde o otimizador coloca o nó de trava. Na v1.1 dependia de o `LockRows` ficar acima do `Sort` (comportamento documentado, mas uma prova mais fraca); a v1.2 eliminou essa dependência.
- A lista é estável durante o laço: a composição está congelada pela trava da coleção (passo 1), porque todo gravador de `collection_allocation` (5046, 5047, 5039, 5150/5153) trava a coleção antes. Um exemplar listado também não pode sumir, pois a 5165 recusa remover exemplar alocado e a FK de `collection_allocation` é `RESTRICT`. Mesmo assim, se a trava não encontrar a linha, o resultado é `PLAN_CHANGED`.

**Proteção de todo o `plan_token`**
- O token depende da composição (congelada no passo 1), da identidade e do local de cada exemplar alocado (congelados no passo 4, para **todos**, não só para os elegíveis), da coleção e do destino (parâmetros).
- A conferência final roda **depois** de todas as travas e exige total travado = total do token. Nenhuma entrada do token pode mudar entre a conferência e o `COMMIT`.

**`NOWAIT` → `LOCK_BUSY` sem movimentação parcial**
- Se qualquer exemplar estiver travado ou alterado por transação em curso, o `lock_not_available` é capturado e relançado como `LOCK_BUSY` (55P03).
- O erro sai da função e a transação da chamada é desfeita: as travas já adquiridas no laço são liberadas.
- O `UPDATE` (passo 7) só existe **depois** do laço completo, portanto nenhum exemplar é movido.

**Esperas possíveis da 5222 (inspeção do código):**

| Onde | Segura no momento | Espera por |
|---|---|---|
| Passo 1, coleção | nada | quem segura a linha da coleção (5036, 5037/5038, 5039, 5046, 5047, 5150/5153, 5210, outra 5222) — `lock_timeout` 5 s |
| Passo 2, destino `KEY SHARE` | a coleção | quem segura o local com `FOR UPDATE` (5217, 5218) — `lock_timeout` 5 s |
| Passo 4, exemplares | coleção + destino | **ninguém** (`NOWAIT`) |
| Passo 7, `UPDATE` | coleção + destino + todos os exemplares | ninguém: as linhas já são suas e a FK pede `KEY SHARE` no destino, que a 5222 já tem |

**Ciclos eliminados e ciclos que ainda podem existir**
- **Eliminado (v1.0):** 5222 × 5024. Na v1.0 a 5222 esperava por linhas de exemplar travadas pela 5024 (que trava sem ordem), formando um ciclo possível (`40P01`). Agora a 5222 nunca espera por exemplar.
- **Sem ciclo com a 5024:** a 5024 pode esperar a 5222 (exemplar travado), mas a 5222 nunca espera a 5024. A `KEY SHARE` da FK da 5024 no destino é compatível com a `KEY SHARE` da 5222.
- **Sem ciclo com 5036, 5046, 5047 (e 5039, 5150/5153, 5210):** a primeira trava delas é a coleção. A 5222 espera pela coleção sem segurar nada; elas esperam pela coleção da 5222 sem que a 5222 espere por elas.
- **Sem ciclo com a 5165:** ela trava um exemplar e espera se a 5222 já o tiver; a 5222 nunca espera exemplar.
- **Sem ciclo com a 5217/5218:**
  - A única espera da 5222 que acontece enquanto ela segura algo é o passo 2 (segura a coleção, espera o local). Um ciclo exigiria que a 5217/5218 esperasse pela coleção.
  - A 5217 só renomeia o local e não toca a coleção.
  - A 5218 só exclui local vazio que **não** seja padrão de nenhuma coleção. O efeito de FK da exclusão (verificar coleções que apontam para o local) só trava linhas de coleção que o referenciam, e nesse caso a 5218 recusa antes de excluir. A leitura em que ela se baseia não usa trava.
- **O que continua possível (não comprovado como ausente):**
  - **(a)** Ciclos que não envolvem a 5222 (por exemplo, 5024 × 5024 sem ordem): preexistentes e fora deste escopo.
  - **(b)** Funções fora do inventário acima que travem um local com `FOR UPDATE` e depois esperem uma coleção, ou transações multi-comando abertas manualmente (SQL direto do dono). Não há prova exaustiva sobre todas as funções do schema, só sobre as inspecionadas.
  - **(c)** Esperas por coleção/destino ainda acontecem e terminam em `55P03` pelo `lock_timeout` de 5 s, não em deadlock.
- **Ausência universal de deadlock não é afirmada.**

- **`lock_timeout = 5s`** na função: abaixo do `statement_timeout` de 8 s do `authenticated` (registrado na 6128). Espera longa pela coleção ou pelo destino falha com `55P03` claro.

## 6. Tratamento de erros

| Código | Mensagem | Quando | Interface (futura) |
|---|---|---|---|
| 28000 | `not_authenticated` | Sem sessão | Login |
| 22023 | `INVALID_MODE` / `INVALID_ARGUMENT` | Modalidade ou argumento inválido | Erro genérico |
| 54000 | `COLLECTION_TOO_LARGE` | Total alocado à coleção > 10.000 (D6), elegíveis > 10.000 ou quantidade declarada > 10.000 | Explica o limite |
| P0002 | `COLLECTION_NOT_FOUND` | Inexistente **ou** de outro usuário (não enumera) | "Coleção não encontrada" |
| P0002 | `STORAGE_NOT_FOUND` | Local inexistente **ou** de outro acervo | Recarregar locais |
| 55000 | `COLLECTION_ARCHIVED` | Coleção arquivada | Reativar primeiro |
| P0001 | `DEFAULT_CHANGED` | Destino deixou de ser o padrão | Nova proposta com o padrão atual |
| P0001 | `PLAN_CHANGED` | Composição/locais mudaram desde a prévia | Nova prévia + nova confirmação |
| 55P03 | `LOCK_BUSY` | (v1.1) Exemplar da coleção em uso por outra transação neste instante | "Tente novamente" |
| 55P03 | `lock_not_available` | Trava da coleção ou do destino ocupada > 5 s | "Tente novamente" |

Toda recusa acontece **antes** do `UPDATE` ou o desfaz: zero alterações.

## 7. Idempotência e confirmação duplicada

- Após um sucesso, o estado mudou e o token antigo não confere: **repetir a mesma confirmação → `PLAN_CHANGED`, nada muda.** A nova prévia mostra 0 a mover.
- Duplo clique simultâneo: a 2ª chamada espera a trava da coleção e, ao entrar, encontra o token já diferente → `PLAN_CHANGED`. A interface também bloqueia o reenvio (padrão do WHERE-03).
- Nada a mover (`expected 0` com token válido): no-op, `moved_count = 0`.
- Fechar a interface durante a gravação: a transação conclui ou é desfeita no servidor; a próxima prévia mostra o estado real.

## 8. Limite de 10.000 exemplares (D3) — análise sem medição

- **O que se sabe** (medido antes, não nesta rodada): a 5024 moveu 500 exemplares em ~61–65 ms sobre 20.000 linhas (5803).
- **O que NÃO se pode assumir:** que 10.000 custem 20× isso. Aumentam de forma não linear:
  - travar linhas, o que grava xmax em cada tupla, suja a página e gera WAL. Desde a v1.1 são travados **todos** os exemplares da coleção (≤ 10.000 pelo D6), um comando por exemplar na v1.2;
  - a agregação `string_agg` de ~750 KB, calculada duas vezes (antes e depois das travas);
  - 10.000 novas versões de linha (`UPDATE` MVCC) e manutenção dos índices de `physical_card`, inclusive `ix_physical_card_storage_container`;
  - o trigger `updated_at` por linha.
- **Timeout:** `statement_timeout` de 8 s do `authenticated`. Se estourar, a transação inteira é desfeita (`57014`): **rollback integral, nada movido**. O teto é avaliado **antes** de travar linhas.
- **Impacto das travas:** durante a operação ficam travados a coleção (1 linha), o destino (`KEY SHARE`) e **todos os exemplares da coleção** (v1.1). Uma 5024 sobre algum deles, nesse intervalo, espera o `COMMIT`. Outras coleções e outros usuários não são afetados. Leituras nunca bloqueiam (MVCC).
- **Repetição:** idempotente (§7).
- **Ressalva objetiva antes de autorizar a execução no LIVE:** a viabilidade de 10.000 em < 8 s **não está demonstrada**. Recomendação:
  - medir em ambiente isolado (branch/cópia) com 1.000, 5.000 e 10.000 elegíveis, p95 de 10 execuções, critério ≤ 2 s em 10.000 (folga ≥ 4× sobre os 8 s);
  - se não atingir, reduzir o teto (por exemplo, 2.000) na própria 5222 antes de promover.
  - Coleções reais hoje são da ordem de dezenas a centenas de exemplares (uma coleção de Set típica tem < 300 posições).
- **Regra de limite vigente (v1.2, D3 + D6):**
  - **D6:** o total de exemplares alocados à coleção não pode passar de **10.000**. É o universo travado e o que entra no token.
  - **D3:** os elegíveis da modalidade também não (redundante com D6, porque elegíveis ≤ total; mantido como defesa).
  - **Quantidade declarada:** `p_expected_count` > 10.000 é recusado já na validação de forma.
  - **Momento da recusa:** depois das travas de coleção e destino e **antes** de qualquer trava de exemplar, com `COLLECTION_TOO_LARGE` (54000) e rollback integral. Nada é gravado.
  - **Consequência de produto:** a organização em lote vale para coleções com até 10.000 exemplares, o que inclui todas as coleções reais de hoje. Acima disso, a interface (futura) explica o limite, usando `total_count` e `max_per_operation` da prévia 5221, sem alteração na 5221.
  - O teto **não** foi aumentado.
- **Custo na v1.2:** até 10.000 comandos de trava (um por exemplar, pela PK) + duas agregações do token + o `UPDATE` dos elegíveis. É linear no total da coleção. **Não medido** (D4): nenhum número de tempo nesta proposta é medição.

## 9. Compatibilidade com as modalidades

| Modalidade | Vínculo físico | Coberta por |
|---|---|---|
| Coleção de Set (`REFERENCE_BASED`/`CARD_SET`) | `collection_allocation` via 5046 | Fixture CS (4.5) |
| Coleção livre | `collection_allocation` via 5046 (5175 cria a coleção com 5034) | Fixture CF (4.6) + C1/C2 (OPEN) |
| Master Set | `collection_allocation` via 5046 (vínculo pelo checklist, 5200 é leitura); escopo em `collection_master_set_scope` | Estrutura (4.8) + invariância do escopo (4.9) |
| Pokédex | `collection_allocation` + `collection_pokedex_position_assignment` (PK = id da alocação, 6117) via 5210 | Estrutura (4.8) + invariância das posições (4.9) |

Mudar o local do exemplar não toca alocação, escopo, posição da Pokédex nem posição do fichário (5115): **nenhuma modalidade exige tratamento diferente.**

## 10. Harness 5849

- Protocolo da 5847/5848: um statement, usuários efêmeros, sentinela, resíduo zero.
- **50** verificações funcionais. GATE sem a Seção L = `PASS_FUNCTIONAL_LIMIT_NOT_EXERCISED`; a Seção L (≥ 10.001 exemplares sintéticos) **não roda no LIVE**.

| Seção | Cobre |
|---|---|
| 0.1–0.8 | Funções, `SECURITY DEFINER`/`VOLATILE`/`search_path`/`lock_timeout`, grants (helper sem nenhum papel de API), retornos exatos, fixture |
| 1.1–1.10 | anon 42501, sem identidade 28000, helper inacessível, coleção e local de outro usuário (não enumera), argumento nulo |
| 2.1–2.6 | Coleção vazia; 6/2/2/2 e elegíveis 2/4; destino ≠ padrão; token determinístico e por destino; prévia sem escrita |
| 3.1–3.16 | Modalidade/argumento inválidos; teto declarado; contagem e token divergentes; mudança de local, entrada e saída de exemplar e troca do padrão entre prévia e execução (cada uma com zero alterações); local de outro usuário; UNLOCATED; confirmação duplicada; no-op; ALL; tudo no destino; arquivada |
| 4.1–4.9 | Fora da coleção intactos; vínculos intactos; colunas além do local intactas; B intacto; Set e Livre; contagem por local (5219); estrutura; Master Set/Pokédex/fichário intactos |
| L.1 | (opcional, fora do LIVE) teto pela contagem real (total e elegíveis > 10.000) |
| L.2 | (opcional, fora do LIVE) **D6**: total > 10.000 com 1 elegível → recusa pelo total, nada alterado |
| 99.1 | Resíduo zero e papel restaurado |

**Concorrência real entre sessões** não é provada por um único statement (limitação L2). Roteiro manual, em ambiente isolado, com duas sessões:
- **K1:** 5222 segura a trava da coleção; 5046 na mesma coleção espera e conclui depois; a nova prévia reflete.
- **K2:** 5047 primeiro; a 5222 com token antigo → `PLAN_CHANGED`.
- **K3:** 5218 tentando excluir o destino durante a 5222 → espera e depois recusa (é o padrão).
- **K4 (v1.1/v1.2):** 5024 sobre qualquer exemplar da coleção, elegível ou não, em transação aberta → a 5222 falha na hora com `LOCK_BUSY`, nada gravado. Com a ordem inversa (5222 primeiro), a 5024 espera e conclui depois do `COMMIT`. Em nenhuma combinação deve aparecer `40P01`.

Nenhum resultado é PASS até ser executado.

## 11. Plano de execução (após auditoria + autorização)

1. **Precheck (só leitura):** `HEAD`, ledger, ausência das 3 funções, contagens de base.
2. **`apply_migration` 5221** e postcheck: funções, grants, `prosrc` igual ao arquivo.
3. **`apply_migration` 5222** e postcheck.
4. **Harness:** `select * from pg_temp.wh_5849_validate(false);` — esperar 50/50 e `PASS_FUNCTIONAL_LIMIT_NOT_EXERCISED`. **Nunca `true` no LIVE.**
5. **Security Advisor:** sem achado novo além dos padrões (`authenticated_security_definer_function_executable` para as 2 RPCs públicas).
6. **Medição de desempenho (§8):** em ambiente isolado, se autorizada; senão, ressalva mantida.
7. **Promoção canônica, documentação (05d, log) e só então frontend WHERE-05A.**

## 12. Rollback

Sem dados novos e sem mudança de contrato existente. Rollback = remover as funções (nenhum objeto depende delas):

```sql
begin;
drop function if exists public.organize_my_collection_storage(uuid, uuid, text, integer, text);
drop function if exists public.get_my_collection_storage_plan(uuid, uuid);
drop function if exists public.collection_storage_plan_snapshot(uuid, uuid);
notify pgrst, 'reload schema';
commit;
```

Movimentações já confirmadas pelo usuário **não** são revertidas pelo rollback: são o estado desejado e auditável pelos locais atuais. Não há histórico (D5) para reverter automaticamente.

## 13. Riscos remanescentes

| # | Risco | Tratamento |
|---|---|---|
| R1 | Viabilidade de 10.000 em < 8 s não demonstrada | §8 — medir fora do LIVE ou reduzir o teto antes de promover |
| R2 | (v1.1) `LOCK_BUSY` quando uma 5024 está em curso sobre exemplar da coleção | Falha imediata, sem gravação, "tente novamente". O deadlock da v1.0 deixou de ser possível (`NOWAIT`) |
| R7 | Coleção muito grande com poucos elegíveis travaria muitas linhas | **Resolvido pela D6 (v1.2):** total > 10.000 é recusado antes de travar exemplares |
| R8 | Ausência de deadlock comprovada só para as funções inspecionadas (§5) | Funções fora do inventário e transações manuais multi-comando não estão cobertas; as esperas restantes da 5222 (coleção, destino) terminam em `lock_timeout` |
| R3 | Pokédex/Master Set sem fixture de vínculo de posição | Estrutura + invariância (4.8/4.9); mesmo mecanismo físico |
| R4 | Concorrência entre sessões não coberta pelo harness | Roteiro K1–K4 manual em ambiente isolado |
| R5 | Prévia em coleção com milhares de exemplares (custo da agregação) | Sem medição (D4); mesma ressalva de R1 |
| R6 | Sem histórico de movimentação | D5 — evolução futura possível (registro por operação), fora do escopo |

## 14. Verificações estáticas desta rodada

Ver o relatório da rodada: balanço `begin`/`commit`, `$$` pareados, `git diff --check`, nenhuma alteração fora desta pasta.

## 15. Execução no LIVE e fechamento (2026-10-22)

Projeto `qjfutqujxrbzgrtkpgkg` (PostgreSQL 17.6), autorização expressa de Fabrício (WHERE-05A LIVE CONTRACT EXECUTION).

**Migrations.**

| Query | Ledger | md5 do arquivo (esta pasta) | md5 do texto aplicado (`begin;` → fim) | md5 dos corpos no banco |
|---|---|---|---|---|
| `5221` | `20261022194133` | `e0913bf41c7e251cf90973409a566c1f` | `89460b5a5fa90f83a1ec5f2e5bed12d8` | RPC `f9a796de70292f19aed5bd2224c9c0d9`; helper `7cdd1b6a56ccb3915744225210e33479` |
| `5222` v1.2 | `20261022194352` | `8ee862b7d8a8e4a6671bbffe3edf41b0` | `1bc40e7aa3bb374c6679259e96d6c0fe` | `595e5229051e4dc6e16a1c9e484a6e9b` |

Postchecks estruturais: assinaturas e retornos exatos (12 e 6 colunas); RPCs `SECURITY DEFINER`, helper `SECURITY INVOKER`, todas `VOLATILE` com `search_path ''`; `5222` com `lock_timeout = 5s`; `EXECUTE` das RPCs só `authenticated`; helper sem `EXECUTE` para PUBLIC/anon/authenticated/service_role; `5024`/`5036` inalteradas. A chamada de aplicação da `5222` foi enviada duas vezes por erro operacional; a segunda foi barrada pela pré-checagem da própria migration (`função já existe`) antes de qualquer DDL — uma única entrada no ledger. Security Advisor: lint 0029 passou de 178 para 180 (as duas RPCs novas, padrão conhecido e aceito); helper não listado; nenhum outro achado novo.

**Harness 5849 — histórico de execução.**

| Versão | Resultado no LIVE | Causa / correção |
|---|---|---|
| v1.2 | Abortou com `42P01` antes de emitir qualquer verificação; resíduo zero | Referência estática a `public.collection_master_set_scope` (inexistente no LIVE) num `CASE` — o PL/pgSQL prepara os dois ramos; `to_regclass` não impede. |
| v1.3 | Executou até o fim: **47/50**, GATE `FAIL` (3.7, 3.8, 3.9); resíduo zero | Corrigiu o `42P01` (contagens de tabelas opcionais por `EXECUTE` dinâmico após `to_regclass`; ausente = `-1`). As três falhas vinham do próprio harness: a `5222` devolveu o erro esperado em todas, mas a comparação usava o `h_map` do 3.6, capturado com a1 em Y antes da devolução de a1. |
| **v1.4** | **50/50 PASS**, GATE `PASS_FUNCTIONAL_LIMIT_NOT_EXERCISED`; 99.1 resíduo zero | Uma linha: recaptura de `h_map` logo após a devolução de a1, no fim do 3.6. Nenhum check, ID, gate ou protocolo alterado. |

Artefato executado: `5849_validate_where_05a_collection_storage.sql` v1.4 — md5 do arquivo `030b59bdd738dfcfb56d11fce6d4eb78` (630 linhas); trecho executado (`create or replace function` → fim) md5 `2c05293e0eab9a646b665ec36e7ae6cf`; chamada `wh_5849_validate(false)`, uma vez. O arquivo é preservado byte a byte como evidência (o cabeçalho de status interno reflete o momento anterior à execução; o resultado oficial é este README). Harness **não promovido** para `database/schema/`.

Após a execução: contagens idênticas ao baseline (usuários 3, locais 2, coleções 10, alocações 210, exemplares 1352 com 1 localizado, referências 9, pedidos de criação 10, acervos 3); mapa de exemplares `d640ddec25f8124ac591efa25b7b3a3a` inalterado; nenhum objeto `*5849*` remanescente; nenhum exemplar real movido.

**Registro processual.** A execução da v1.4 ocorreu com base no "Autorizado" de Fabrício à proposta apresentada após o resultado da v1.3 (correção de uma linha + nova conferência estática + execução única com `false`). A correção intermediária (v1.3 → v1.4) **não foi submetida a auditoria independente antes da execução**; a única revisão prévia foi a conferência estática feita pelo próprio agente (diff, IDs, gate, ausência de outra comparação com referência desatualizada). O mesmo vale para a v1.3, conferida estaticamente e autorizada, mas não auditada de forma independente.

**Ressalvas mantidas.**
- Desempenho (p95) **NÃO medido**; nenhum timing registrado.
- L.1/L.2 (teto pela contagem real, D6 com > 10.000 alocados) **não executadas** — carga sintética proibida no LIVE.
- Concorrência entre sessões (travas, espera, `LOCK_BUSY`, deadlock) **não exercitada**; roteiro K1–K4 (§5) pendente, fora do LIVE.
- 4.9: `collection_master_set_scope` não existe no LIVE → sentinela `-1/-1`; a invariância do Master Set no 4.9 fica sem medição por contagem, coberta só estruturalmente pelo 4.8 (a `5222` não referencia `master_set`). Nenhuma tabela substituída por equivalência não demonstrada.

**Canônicas.** `database/schema/5221_create_get_my_collection_storage_plan_function.sql` e `database/schema/5222_create_organize_my_collection_storage_function.sql` — só o bloco `Status` do cabeçalho difere desta pasta; do `begin;` em diante, idênticas ao aplicado.
