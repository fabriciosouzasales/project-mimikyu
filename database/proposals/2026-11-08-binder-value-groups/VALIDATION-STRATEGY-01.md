# Query 5357 — estratégia de validação no ambiente existente (sem ambiente isolado)

| Campo | Valor |
|---|---|
| **Rodadas** | `BINDER VALUE — B2 VALIDATION STRATEGY CORRECTION-01` (2026-11-08) · `B2 — LIVE READONLY PROTOCOL AUDIT-01` (2026-11-08: V1 e V2 → v0.2; V3 sem mudança, defeitos registrados no §10) · `B2 — V1.8 CONTROLLED EXECUTION-01` · `B2 — V1 STRUCTURAL & INTEGRITY EXECUTION-01` (V1 → v0.3) · `B2 — V1 CLOSEOUT & V2 READINESS-01` (V2 → v0.3; V1.9 proposto; §11) · `B2 — V2.1 GENERIC EXPLAIN EXECUTION-01` · `B2 — V2.1 G3 CORRECTION & INDEX DIAGNOSIS-01` (V2 → v0.4; V2.4 proposto; §12) · `B2 — V2.4 INDEX DIAGNOSIS EXECUTION-01` (§13) · `B2 — PHASE C FINAL READINESS-01` (V3 → v0.2; R1; §14) |
| **Decisão do proprietário** | Sem ambiente isolado: sem Supabase local, sem ampliar réplicas, sem extrair esquema. `LOCAL ENVIRONMENT READINESS` cancelada neste incremento |
| **Status** | **ENCERRADO (2026-11-08).** Query 5357 CONFIRMADA EXECUTADA no LIVE `mimikyu-core` (ledger `20261108042423`); C1.0, C1, C2, C3a e C3b **PASS**; C3c dispensado; **promovida** a `database/schema/5357_create_get_my_binder_value_groups.sql` (§15). Fase B encerrada (§11–§13); V1.7, V1.9, V2.2 e V2.3 dispensados (§14). Interface do Valor do Fichário não implementada |
| **Preservados sem alteração (B2 v0.2)** | `5357_..._PROPOSAL.sql` (md5 do arquivo `4a309a81…`, do corpo `$$…$$` `e6cdae3e…`) · `5885_..._HARNESS_LOCAL.sql` (fica **sem uso** neste incremento; não vira harness do LIVE) · `5357_P1_EXPLAIN_PROTOCOL.sql` (critérios reaproveitados) · `README.md` |
| **Novos** | `5357_V1_READONLY_PRECHECK.sql` v0.3 (fase B, executado) · `5357_V1_9_ALLOCATION_UNIQUENESS_READONLY.sql` v0.1 (proposto) · `5357_V2_EXPLAIN_READONLY.sql` v0.4 (fase B; V2.1 executado) · `EVIDENCE-V2.1-2026-11-08.txt` (plano integral) · `5357_V2_4_CARD_ASSET_INDEX_CATALOG_READONLY.sql` v0.1 (executado) · `EVIDENCE-V2.4-2026-11-08.txt` · `5357_V3_POSTAPPLY_READONLY.sql` v0.2 (fase C; não executado) · `5357_R1_ROLLBACK_PROCEDURE.sql` v0.1 (reversão; não executado) · este documento |

## 1. Estratégia

1. **A — estática e documental (feita nesta rodada).** Prova pelo texto da SQL tudo o que não depende de privilégios nem de dados reais.
2. **B — diagnósticos somente leitura (autorização própria).** Antes de aplicar: confirmar no banco real os objetos, gatilhos, papéis, privilégios padrão e invariantes de dados de que a 5357 depende (V1), e o plano sem ANALYZE (V2). Nada é criado nem alterado.
3. **C — aplicação definitiva (autorização independente) + verificação pós-aplicação somente leitura (V3).** A aplicação só **adiciona** uma função que a aplicação ainda não chama. Os testes de comportamento que exigem a função existir (negativos de privilégio e de identidade, positivos e integridade) rodam logo depois, **antes de qualquer código usar a função**. Gate reprovado → `DROP FUNCTION` (sem efeito em tela).

O que torna B e C seguros não é ROLLBACK: é a transação **READ ONLY imposta pelo servidor** (qualquer escrita falha com `25006`), a função ser `STABLE` e só ler, `statement_timeout` e `lock_timeout` curtos, blocos autocontidos (um resultado por bloco), e a saída restrita a contagens, booleanos e SQLSTATE — nenhum id, nome ou carta é exibido.

Testes que dependem de criar dados de teste (o fixture sintético do 5885) **não são executados**: no ambiente real, criar titulares e exemplares de teste seria escrita em produção. Esses cenários ficam cobertos pela prova estática, pelos invariantes de dados (V1.6) e, quando o cenário já existir nos dados reais (V1.7), pela verificação agregada C3c.

## 2. Auditoria estática (A)

Revisão integral do corpo da 5357 contra as definições versionadas; **nenhum defeito encontrado — a 5357 não foi alterada.**

| Tema | Conclusão estática |
|---|---|
| `SECURITY DEFINER` | `search_path = ''`, todos os objetos qualificados (`public.`/`auth.`), sem SQL dinâmico, nenhuma escrita, `STABLE`; só usa `auth.uid()` como identidade |
| Autorização | primeira leitura de dados é `collection` com `owner_user_id = auth.uid()`; antes dela só validações de parâmetro; falha → `P0002` com a mesma mensagem para inexistente, de outro titular ou compartilhada |
| Proprietária × convidada | fichário resolvido só a partir da coleção autorizada (`collection_layout.collection_id`, depois `collection_layout_guest`); dono da proprietária reconferido |
| Isolamento | exemplares só via `inventory.owner_user_id = auth.uid()` |
| Privilégios | `REVOKE ALL` de `PUBLIC` e `anon`, `GRANT EXECUTE` a `authenticated`, no mesmo script (sem janela de exposição se aplicado em uma transação) |
| Agregação | `group by (card_variant_id, language_id)`; `count(*)` por grupo; totais por janela antes do filtro de página |
| Ordenação | total e determinística (termina em `card_variant_id`, `language_id`); mesma ordem SET_NUMBER da 5261 |
| Paginação | 1..200 / 0..10.000; filtro `ord > offset and ord <= offset + limit`; sem estouro de inteiro |
| Perímetro | sem referência a `collection_allocation` no corpo (D1) |
| R2-E | `toItem` lê os nomes exigidos; `rarity_code` ausente vira nulo e não é usado no valor; `buildCollectionValueReport` sem mudança, com `collectionCopies = filled_count` (divergência → `collection_mismatch`, "incompleto"); `COLLECTION_VALUE_MAX_GROUPS` 5.000 < offset máximo 10.000 + 200; preços continuam vindo de `readVariantPrices` |

## 3. Matriz de garantias

Legenda: **E** = demonstrado estaticamente (texto da SQL / definições versionadas) · **V1/V2** = diagnóstico somente leitura antes de aplicar · **C2/C3a/C3b/C3c** = somente leitura depois de aplicar · **N** = não será executado.

| Garantia | Estática | Depende de execução | Observação |
|---|---|---|---|
| Sem sessão → `28000` | E | C3a.2 | |
| Parâmetros inválidos → `22023` | E | C3a.3–5 | uuid malformado (`22P02`) é rejeitado pelo PostgREST/cast antes da função — E |
| Coleção de outro titular / inexistente → `P0002`, mesma mensagem | E | C3a.6–7 | identidade de teste = uuid aleatório sem conta |
| VIEWER ativo não lê o fichário alheio | E (a função não consulta `collection_membership`; fronteira é `owner_user_id`) | C3c indiretamente; **N** como teste direto | teste direto exigiria agir como um titular que tem compartilhamento — fora do escopo autorizado |
| Convidada = proprietária | E | C3b.5 / C3c | só se existir convidada (V1.7) |
| Isolamento entre titulares | E + gatilho 5248 | V1.6a | o exemplar igual de outro titular não pode estar no bolso |
| Perímetro D1 (todas as origens no bolso entram) | E | V1.6d (todos os fichários) + C3c | origens presentes nos dados reais: V1.7; ausentes ficam só E |
| Fora do bolso, outro local, reserva, imagem, mesclado não contam | E (só há linha de ocupação para exemplar) | — | |
| Σ = `total_copies` = `filled_count` | E | V1.6d, C3b.1, C3c | |
| Paginação estável | E | C3b.3 | totais constantes por página |
| Subconjunto do Acervo | E | C3b.4 | referência 5261 sem filtro de coleção |
| `SECURITY DEFINER`, `search_path`, `STABLE`, corpo igual à proposta | E | C2 (md5 de `prosrc` = `e6cdae3e…`) | |
| `anon`/`PUBLIC` sem EXECUTE; `authenticated` com | E (script) | C2 + C3a.1 | **depende dos privilégios padrão reais** (V1.5) |
| Chamada como `anon` → `42501` | — | C3a.1 | |
| `postgres` (dono) ignora RLS | — | V1.5 | |
| `auth.uid()` lê os claims | — | V1.5 | |
| `service_role` | — | C2 (registrado) | segue o padrão de 5252/5356; sem asserção |
| Gatilhos de integridade ativos | E (versionado) | V1.3 | |
| Desempenho proporcional ao fichário | E (índices) | V2 | |

**Não executados (N), declarados como tal — nunca como PASS:** fixture sintético completo (titulares, coleções arquivada/não participante, exemplar sem coleção criados para o teste); VIEWER ativo como teste direto; cenários de origem que não existirem nos dados reais; concorrência; EXPLAIN ANALYZE.

## 4. Protocolo somente leitura

| Etapa | Arquivo | Quando | O que prova |
|---|---|---|---|
| B1 | `5357_V1_READONLY_PRECHECK.sql` | antes de aplicar | nome livre; PG ≥ 16; colunas, constraints, índices; gatilhos habilitados; leituras 5252/5261 com os mesmos nomes/tipos; papéis, privilégios padrão e ACL das irmãs; `auth.uid()`; invariantes V1.6a–d; cobertura real V1.7; estatísticas V1.8 |
| B2 | `5357_V2_EXPLAIN_READONLY.sql` | antes de aplicar | plano genérico (`EXPLAIN (GENERIC_PLAN)`, sem ids) e plano do fichário mais denso (ids só dentro do bloco) |
| C1 | `5357_create_..._PROPOSAL.sql` | autorização independente | aplicação em uma única transação (criar + revogar + conceder + comentar) |
| C2 | V3 §C2 | logo após C1 | metadados e ACL reais, corpo igual à proposta |
| C3a | V3 §C3a | logo após C2 | negativos sem dados de ninguém (identidade inexistente) |
| C3b | V3 §C3b | logo após C3a | positivo na conta do Fabrício (coleção informada por ele) |
| C3c | V3 §C3c | **autorização explícita adicional** | todos os fichários, como cada titular, só contagens de divergência |

Ordem obrigatória; cada etapa só começa com a anterior em PASS.

## 5. Critérios PASS/STOP

**Impedem a aplicação (STOP antes de C1):**
- V1.1: nome já existe, sobrecarga existente ou PG < 16 (sem `GENERIC_PLAN`: V2 é refeito sem esse modo, nova auditoria).
- V1.2/V1.3: coluna, constraint, índice ou gatilho ausente/desabilitado.
- V1.4: 5252/5261 com assinatura diferente da versionada.
- V1.5: `anon`/`authenticated` com `rolsuper` ou `rolbypassrls`; sessão sem poder assumir `anon`/`authenticated` (C3 não seria executável); `postgres` sem `rolbypassrls`; `auth.uid()` sem leitura dos claims.
- V1.6: qualquer invariante ≠ 0.
- V2: qualquer critério STOP do protocolo de desempenho.

**Exigem reversão (`DROP FUNCTION`, com autorização) depois de C1:**
- C2: qualquer item falso; ACL diferente da 5252/5356; `prosrc` com md5 diferente.
- C3a: qualquer SQLSTATE diferente do esperado; mensagens diferentes entre inexistente e alheia.
- C3b/C3c: qualquer divergência > 0.

**PASS** só é declarado para o que executou e passou. Itens não executados ou inconclusivos (por exemplo C3b com mais de 200 grupos, ou cenário sem dados em V1.7) são reportados como **NÃO EXECUTADO** ou **INCONCLUSIVO**.

## 6. Desempenho

Os critérios do `5357_P1_EXPLAIN_PROTOCOL.sql` v0.2 continuam valendo (seletividade, cardinalidade, índices existentes, custo só informativo). A forma de execução no ambiente existente é o `V2`: `EXPLAIN (GENERIC_PLAN)` com `$1/$2` (sem ids) e, para o plano com valores, um bloco que escolhe o fichário mais denso internamente e emite só as linhas do plano. O P1.0 do P1 v0.2 (que exibe `layout_id` e `uid`) **não** é usado no ambiente existente.

## 7. Riscos residuais

1. Cenários de origem ausentes dos dados reais ficam só com prova estática.
2. VIEWER ativo sem teste direto (a função não lê `collection_membership`; risco baixo, prova estática).
3. Os testes negativos de privilégio só são possíveis **depois** de a função existir no banco real; a janela entre C1 e C2/C3a é coberta por: aplicação em uma transação (o REVOKE acompanha o CREATE) e função ainda não chamada pela aplicação.
4. C3c lê como cada titular (só contagens); por privacidade, tem autorização separada e pode ser dispensado — nesse caso a cobertura de todos os fichários fica com V1.6d (mesmo percurso, sem chamar a função).
5. Privilégios padrão reais podem diferir do esperado (V1.5 detecta; o REVOKE explícito cobre `anon`/`PUBLIC`).
6. EXPLAIN sem ANALYZE não mede latência; a medição real fica para depois da publicação (logs da aplicação).
7. Concorrência não testada (leitura `STABLE`; divergência entre páginas vira "incompleto" na aplicação).

## 8. Alterações documentais necessárias (não aplicadas nesta rodada)

- `README.md` da proposta: §6 (ambiente local) e a matriz de equivalência passam a "**cancelado neste incremento** (decisão do proprietário, 2026-11-08)"; apontar para este documento; status do 5885 = "não utilizado".
- Cabeçalho do `5885_..._HARNESS_LOCAL.sql`: status "NÃO UTILIZADO neste incremento; proibido no LIVE".
- `docs/log.md`: linha `docs` da rodada.
- Contrato `05d` (seção do Valor do Fichário, D7): registrar que a validação da 5357 será feita no ambiente existente por V1/V2/V3 — no ciclo da aplicação.
- Na aplicação (fase C): promover a 5357 para `database/schema/` só após C2/C3 PASS, registrar ledger/md5 e o resultado de cada etapa (PASS / NÃO EXECUTADO / INCONCLUSIVO).

## 9. Próximo gate recomendado

**GO para autorizar somente a fase B** (V1 e V2, somente leitura) no ambiente existente. **STOP** para a aplicação (C1) até o relatório da fase B ser auditado. C3c depende de autorização explícita adicional.

## 10. Auditoria dos scripts (LIVE READONLY PROTOCOL AUDIT-01)

**V1 v0.2 e V2 v0.2** — defeitos corrigidos: sem `lock_timeout` (V1, V2); vários SELECTs por transação, incompatível com cliente que devolve só o último resultado (V1, V2); casts `::regprocedure` que abortavam o bloco quando o objeto faltava, em vez de responder FALSE (V1.4, V1.5); lista de colunas incompleta — 23 de 54 usadas pela 5357, sem conferência de tipo das colunas que vão sem cast para o retorno (V1.2); ACL nula (padrão, que dá EXECUTE a PUBLIC) não considerada (V1.5c); consulta explicada parcial — sem o catálogo final, a imagem e o filtro de página (V2.1, V2.2); plano customizado imprimia os uuids do fichário e do titular (constantes no texto do plano) (V2.2); plano entregue por NOTICE, que nem todo cliente mostra (V2.2).

**V3 (não alterado nesta rodada; corrigir na auditoria da fase C):**
- D-V3-1: C2 confere PUBLIC só em `proacl`; com `proacl` nulo o EXECUTE padrão a PUBLIC passaria despercebido → usar `coalesce(proacl, acldefault('f', proowner))` (mesmo defeito existe no S2 do 5885, que fica sem uso).
- D-V3-2: C3a/C3b/C3c entregam resultados por NOTICE → devolver como linha (configuração local da transação + SELECT final, como no V2.2).
- D-V3-3: sem `lock_timeout` e `idle_in_transaction_session_timeout`.
- D-V3-4: C3b depende de marcadores trocados à mão; se ficarem sem troca, o cast falha (falha segura, mas precisa estar no roteiro).
- C3c continua **independente e bloqueado** (lê como cada titular); nenhuma autorização de aplicação ou `DROP FUNCTION` decorre deste documento.

## 11. Resultado da fase B — V1 (encerrado em 2026-11-08)

Executado no projeto `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`, PostgreSQL 17.6.1.147), pelo conector do Supabase, um bloco por chamada, cada um em transação READ ONLY própria com `statement_timeout` 5 s, `lock_timeout` 2 s, `idle_in_transaction_session_timeout` 30 s e ROLLBACK. Protocolo: V1.8 pela v0.2 (`b6492a88…`); V1.1–V1.6 pela v0.3 (`fc92e26a…`; a v0.3 só muda o V1.5c e um comentário do V1.7). Nenhum SQLSTATE de erro, nenhum timeout, nenhuma alteração no banco.

| Bloco | Status | Evidência |
|---|---|---|
| V1.8 | PASS (informativo) | 14/14 tabelas; bolsos ≈ 3,2 mil, ocupações ≈ 1,15 mil, exemplares ≈ 3,6 mil, inventários ≈ 3; `card_variant` 1.027 páginas, `card_asset` 982, `card` 462; `language` e `collection_layout_guest` sem estatística (−1) |
| V1.1 | PASS | PG ≥ 16; nome `get_my_binder_value_groups` livre, sem sobrecarga |
| V1.2 | PASS | 54/54 colunas; tipos conferidos; ocupação no modelo 5248 |
| V1.3 | PASS | 4 UNIQUE, 2 índices, nenhum gatilho desabilitado; gatilhos 5117/5248, 5229 e 5247 presentes |
| V1.4 | PASS | 5252 e 5261 com as assinaturas versionadas |
| V1.5a | PASS | `anon`/`authenticated` sem superusuário e sem BYPASSRLS, assumíveis pela sessão; `postgres` com BYPASSRLS (não superusuário) |
| V1.5b | INFORMATIVO | privilégios padrão: `supabase_admin` concede EXECUTE a `postgres`, `anon`, `authenticated`, `service_role`; `postgres` concede só a `postgres` |
| V1.5c | PASS | 5252 e 5356: `postgres:EXECUTE, authenticated:EXECUTE`; `anon` sem EXECUTE; `service_role` sem EXECUTE |
| V1.5d | PASS | `auth.uid()` lê os claims; `authenticated` executa |
| V1.6 | PASS | (a) ocupação do mesmo dono da proprietária; (b) exemplar no local físico do fichário; (c) convidada do mesmo dono e não proprietária; (d) `filled_count` = percurso da 5357 — os quatro TRUE em todos os fichários |
| V1.7 | **NÃO EXECUTADO** | decisão de priorização; pré-requisito proposto: V1.9 (unicidade de `collection_allocation.physical_card_id`) |

**Limitações das provas.** O V1 prova que as dependências, os privilégios e as regras de dados de que a 5357 depende existem e valem **hoje**; não prova o comportamento da 5357, que **não foi aplicada, testada nem homologada**. As provas de privilégio são de catálogo (`has_function_privilege`, ACL), não chamadas reais. O V1.6 é um retrato num instante; a manutenção futura das regras depende dos gatilhos verificados no V1.3. V1.5b mostra só privilégios padrão por schema; regras globais, se existirem, não aparecem. Estatísticas do V1.8 são estimativas.

**Efeito na futura função.** Criada por `postgres`, a 5357 nasce sem EXECUTE para `anon`/`authenticated`/`service_role` por regra do schema, mas com o EXECUTE padrão do PostgreSQL a PUBLIC — o `REVOKE ... FROM PUBLIC` da 5357 é necessário e o `GRANT ... TO authenticated` é o que dá acesso. ACL esperada após a aplicação (C2): `postgres:EXECUTE, authenticated:EXECUTE`, igual às irmãs.

## 12. Resultado da fase B — V2.1 (2026-11-08)

Executado no `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`, PostgreSQL 17.6.1.147) pelo conector do Supabase: bloco V2.1 do V2 v0.3 (`f16184ef…`; trecho `43f455ed…`), sem alteração; READ ONLY, `statement_timeout` 10 s, `lock_timeout` 2 s, `idle_in_transaction_session_timeout` 30 s, ROLLBACK; `EXPLAIN (GENERIC_PLAN)` sem ANALYZE, sem valores de parâmetro. Sucesso, sem SQLSTATE de erro. Plano integral: `EVIDENCE-V2.1-2026-11-08.txt`.

| Gate | Resultado | Evidência |
|---|---|---|
| G1 âncora | PASS | `Index Scan using uq_collection_layout_page_number on collection_layout_page p` · `Index Cond: (layout_id = $1)` · rows=43 |
| G2 catálogo grande por índice | PASS | `card_variant_pkey`, `card_pkey`, `card_set_pkey`; `card_asset` por `uq_card_asset_card_type_external_url` com `Index Cond: (card_id = c.id)`; nenhum Seq Scan nessas tabelas |
| G3 (v0.3, literal) | **STOP — registro original mantido** | `Seq Scan` em `collection_layout_slot` (rows=3216), `collection_layout_slot_assignment` (1150) e `physical_card` (3631) > 1.000 |
| G4 imagem após a página | PASS | `Subquery Scan on o` (`Filter: o.ord > $3`) e `WindowAgg` (`Run Condition`) abaixo do `Nested Loop Left Join` do lateral de `card_asset` (rows=18) |

**Por que o G3 foi corrigido.** O G3 da v0.3 contradizia o próprio protocolo: aceitava Seq Scan em tabela pequena, mas a estimativa de um Seq Scan é sempre a tabela inteira, então qualquer Seq Scan aceito reprovaria o G3. O STOP veio do texto do critério, não de um defeito do plano. Decisão da auditoria (`B2 — V2.1 G3 CORRECTION & INDEX DIAGNOSIS-01`): dividir em G3-A e G3-B (V2 v0.4), sem alterar a SQL da 5357 e sem reexecutar o EXPLAIN.

**Critério revisado.**
- **G3-A — seletividade do percurso:** as junções entre a âncora e a agregação por variante/idioma estimam no máximo max(4 × bolsos do fichário, 1.000) linhas (1.000 no plano genérico) e não crescem ao longo do percurso.
- **G3-B — varreduras globais:** Seq Scan em tabela do percurso é aceito com até 128 páginas (V1.8). Seq Scan não é falha automática; 128 páginas é **gatilho de reavaliação**, não garantia de desempenho; varredura global cresce com a base inteira e é risco residual; a decisão sobre escala futura exige nova evidência.

**Resultado reavaliado (mesmo plano, sem nova execução).**
- G3-A **PASS**: `Hash Join (s.page_id = p.id)` 459 → `Hash Join (a.slot_id = s.id)` 164 → `Hash Join (pc.id = a.physical_card_id)` 164 → `Hash Join (pc.inventory_id = i.id)` 55 → `GroupAggregate` 55 — todas ≤ 1.000 e não crescentes.
- G3-B **PASS**: Seq Scan em `collection_layout_slot` (39 páginas), `collection_layout_slot_assignment` (22), `physical_card` (57) e `inventory` (1) — todas ≤ 128.
- **V2.1: PASS em G1, G2, G3-A, G3-B e G4** pelos critérios da v0.4.

**Limitações da evidência.** Plano genérico: as estimativas usam médias da base, não o maior fichário; nada aqui mede latência. O plano reflete o volume atual (tabelas pequenas lidas inteiras em cada chamada): o custo dessas leituras cresce com a base, não com o fichário — **risco residual**; se as tabelas passarem de 128 páginas, o V2 deve ser repetido. `language` e `card_printing_profile` também aparecem em Seq Scan (fora do percurso; tabelas pequenas; `language` sem estatística, estimativa padrão de 500 linhas).

**Achado lateral — índice de `card_asset`.** O plano usou `uq_card_asset_card_type_external_url` para buscar por `card_id` sem condição sobre `external_url`, mas a Query 180 o declara parcial (`WHERE external_url IS NOT NULL`). Hipótese [I]: no banco a definição difere da versionada (possivelmente pelo `CREATE ... IF NOT EXISTS`). Não afeta a correção da 5357 (o planejador só usa índice compatível); é divergência entre banco e repositório. Verificação proposta, só de catálogo: `5357_V2_4_CARD_ASSET_INDEX_CATALOG_READONLY.sql` (não executada).

**Classificação no `docs/log.md`.** As execuções somente leitura no LIVE foram registradas como `lint`, seguindo o precedente do repositório para execuções de validação no LIVE (harnesses 5881, 5883 e 5884, 2026-11-06/07). A classificação foi mantida.

## 13. Resultado da fase B — V2.4 (2026-11-08)

Executado no `mimikyu-core` (PostgreSQL 17.6.1.147): bloco V2.4 do arquivo v0.1 (`991716be…`; trecho `aad7c304…`), sem alteração; READ ONLY, 5 s / 2 s / 30 s, ROLLBACK; só catálogo. Sucesso, sem SQLSTATE; 15 linhas (integral em `EVIDENCE-V2.4-2026-11-08.txt`).

**Índice que motivou o diagnóstico.** `uq_card_asset_card_type_external_url` no banco: `CREATE UNIQUE INDEX … USING btree (card_id, asset_type_id, external_url)`, **sem predicado**, válido e pronto. A Query 180 o declara parcial (`WHERE external_url IS NOT NULL`). **Divergência semântica confirmada** (ausência de predicado; não é diferença de formatação). Efeito: como a definição real não tem `NULLS NOT DISTINCT`, linhas com `external_url` nulo não colidem entre si — a regra de unicidade é a mesma da versão parcial; muda o que o índice contém (também as linhas com `external_url` nulo) e, por isso, ele é utilizável para busca por `card_id` em qualquer consulta, como no V2.1.

**Demais divergências entre banco e Query 180 (catálogo).**
- `uq_card_asset_card_type_storage_path`: no banco **sem predicado** (180: `WHERE storage_path IS NOT NULL`) — mesma natureza da anterior; nenhuma migration versionada explica.
- `uq_card_asset_one_primary_per_card_type` (180): **ausente** no banco. Substituído por `ux_card_asset_primary_per_card_type_language (card_id, asset_type_id, language_id) WHERE (is_primary = true)` — regra diferente (um principal por carta + tipo + **idioma**). Explicado pela migration versionada `database/migrations/193_add_language_to_card_asset.sql` (CANÔNICA), que remove o índice antigo e cria o novo: a divergência é da 180 em `database/schema/`, não do banco.
- Índices do banco que a 180 não declara, todos presentes nas migrations 193/197: `uq_card_asset_card_type_language_order`, `ix_card_asset_card_language_type`, `ix_card_asset_language_id`, `ix_card_asset_card_bucket`, `ix_card_asset_bucket_language`, `ix_card_asset_storage_bucket_id`. Não declarados na 180 e sem divergência apurada: `card_asset_pkey`, `ix_card_asset_asset_type_id`, `ix_card_asset_is_active`, `ix_card_asset_source_code` (a comparação do V2.4 cobre só os 4 índices nomeados na 180).
- `ix_card_asset_card_id`: igual ao versionado.

**Índices utilizáveis pela busca de imagem da 5357 (`card_id` na primeira posição, sem predicado incompatível).** `ix_card_asset_card_id`, `ix_card_asset_card_bucket`, `ix_card_asset_card_language_type`, `uq_card_asset_card_type_language_order`, `uq_card_asset_card_type_storage_path` e `uq_card_asset_card_type_external_url` — todos válidos e prontos, sem predicado. `ux_card_asset_primary_per_card_type_language` tem `card_id` na primeira posição, mas é **parcial** (`is_primary = true`); a consulta da 5357 filtra `ca.is_primary`, o que em princípio implica o predicado — utilizabilidade por esse índice depende do planejador e não foi verificada.

**Conclusão.** A busca de imagem da 5357 não depende de nenhum índice divergente: há índice não parcial por `card_id` (`ix_card_asset_card_id`, igual ao versionado). As divergências são **dívida documental do repositório** (Query 180 desatualizada em relação ao banco e às migrations 193/197; predicados ausentes no banco sem migration correspondente). Correção fica para rodada própria — sem DDL nesta fase.

**Pendências estáticas do V2.2 (registradas, não corrigidas).**
1. G3-A não verifica a condição de cardinalidade **não crescente** entre as etapas — só o teto.
2. G3-A localiza a agregação por texto (`Group Key` contendo `card_variant_id`).
3. G3-B usa `coalesce(relpages, 0)`: tabela não encontrada ou sem estatística seria tratada como pequena — deve falhar fechado.
4. A análise do plano deve ser conservadora diante de nós inesperados (ex.: agregação não encontrada, `Gather`, `Merge Join`, estatística −1): STOP em vez de aceitar.

## 14. Prontidão da fase C (2026-11-08)

**Estado consolidado.** V1 aprovado; V2.1 aprovado (com o STOP original do G3 preservado no §12); V2.4 concluído; V1.7, V1.9, V2.2 e V2.3 **dispensados** por decisão da auditoria (fase de diagnóstico concluída; não são pré-requisito da aplicação). A Query 5357 continua **não aplicada**, com o mesmo artefato (`4a309a81…`; corpo `e6cdae3e…`). V3 corrigido para a v0.2, **não executado**. Fase C aguardando autorização explícita.

**Defeitos do V3 corrigidos (v0.1 → v0.2).**
- V3-1 (D-V3-1) permissões efetivas: C2 lê a ACL explícita ou, se nula, a padrão (`acldefault`); exige ACL exata `{authenticated, postgres}` e PUBLIC ausente; compara o privilégio **efetivo** (`has_function_privilege`, que considera herança e PUBLIC) de `postgres`, `authenticated`, `anon` e `service_role` com o da leitura irmã 5252 — qualquer concessão inesperada reprova.
- V3-2 (D-V3-2) evidências: cada bloco devolve uma única linha jsonb com `status`, resultados e `pass`; nada depende de NOTICE; erro inesperado expõe só o SQLSTATE.
- V3-3 (D-V3-3) limites: todo bloco com READ ONLY, `statement_timeout`, `lock_timeout` 2 s, `idle_in_transaction_session_timeout` 30 s e ROLLBACK; só configurações locais da transação.
- V3-4 (D-V3-4) C3b sem marcadores: parâmetros `colecao_propria` (obrigatório) e `colecao_convidada` (opcional) recebidos só na chamada e validados no bloco **antes** de qualquer teste (formato uuid, coleção proprietária de um fichário, convidada do mesmo fichário → `status` PARAM_*). Nenhum id no repositório nem nas evidências. **v0.3 (compatibilidade com o executor):** o conector `execute_sql` do Supabase, usado no V1 e no V2, não interpreta variáveis do psql; a chamada passa a ser *prefixo* (BEGIN READ ONLY + timeouts + `set_config(..., true)` com os valores) **concatenado** ao bloco do arquivo, sem alterá-lo; o bloco recusa executar (`PREFIXO_INVALIDO`) se a transação, o isolamento ou os timeouts não forem os do prefixo.

**Conferência final da Query 5357 (única).** Sem defeito material; a 5357 não foi alterada.
- Segurança: `auth.uid()` obrigatório (28000); validação de parâmetros (22023); titularidade da coleção conferida **antes** de resolver o fichário (P0002 neutro); fichário só pela coleção autorizada (proprietária ou convidada) e reconferência do dono da proprietária; exemplares só do inventário do chamador; `SECURITY DEFINER`, `search_path = ''`, objetos qualificados, sem SQL dinâmico; `REVOKE` de PUBLIC e anon, `GRANT` a authenticated (V1.5b/V1.5c: necessário e suficiente para repetir a ACL das irmãs).
- Integridade: só ocupações de bolso (exemplares fora de bolso, reservas, imagens e mesclagens não têm linha de ocupação); nenhuma referência a `collection_allocation` (com ou sem coleção, participante ou não); agrupamento por variante + idioma; exemplar único por bolso e por sistema (V1.3); totais antes da paginação; ordem total determinística; mesmo percurso do `filled_count` (V1.6d).
- Desempenho: SQL idêntica à explicada no V2.1 (comparação de tokens); nenhuma consulta nova; nenhum índice novo.
- Compatibilidade: `toItem` e `buildCollectionValueReport` da R2-E sem mudança; nenhuma regra nova de preço.

**Procedimento C1–C3b (preparado; executar só com autorização).**
1. **C1.0 — precheck (somente leitura):** confirmar o projeto pela API de gestão (`mimikyu-core`, `qjfutqujxrbzgrtkpgkg`, `ACTIVE_HEALTHY`); repetir o bloco V1.1 do V1 v0.3 (nome livre, sem sobrecarga); confirmar o md5 do arquivo da 5357 (`4a309a81…`). Qualquer divergência → STOP.
2. **C1 — aplicação:** aplicar o conteúdo **integral** de `5357_create_get_my_binder_value_groups_PROPOSAL.sql` como uma única migration (`create or replace function` + `revoke` + `revoke` + `grant` + `comment`) numa transação atômica. Se o mecanismo de aplicação não garantir transação única, envolver em `BEGIN; … COMMIT;`. Sucesso = execução sem erro **e** C2 PASS; o retorno da criação, sozinho, não é PASS. Falha na aplicação = nada criado (transação desfeita) → STOP e relatório.
3. **C2 — verificação imediata** (V3 v0.2 §C2): assinatura, retorno de 14 colunas, `SECURITY DEFINER`, STABLE, `search_path` vazio, plpgsql, dono `postgres`, md5 do corpo = `e6cdae3e…`, comentário, ACL exata e privilégios efetivos iguais aos da 5252. `pass = false` → reversão (com autorização).
4. **C3a — negativos** (V3 §C3a): anon 42501; sem sub 28000; coleção nula, limite 201 e offset negativo 22023; coleção inexistente e coleção de outro titular P0002 com a mesma mensagem. `pass = false` → reversão.
5. **C3b — positivo** (V3 §C3b; chamada = prefixo de três linhas com os parâmetros, montado só na execução, + bloco do arquivo sem alteração): numa coleção indicada e autorizada pelo proprietário (e, se houver, uma convidada do mesmo fichário), conferir soma = `total_copies` = `filled_count`, linhas = `total_count`, totais constantes, nenhum grupo repetido, páginas de 50 = páginas de 200, além do fim vazio, cópias ≥ 1, subconjunto do Acervo e convidada = proprietária. `status` PARAM_* → corrigir o parâmetro e repetir; `LIMITE_OFFSET` → INCONCLUSIVO; `pass = false` → reversão.
6. **C3c** — fora da autorização padrão; bloqueado.
7. **Registro:** depois de C2–C3b PASS, promover a 5357 para `database/schema/` (só o bloco Status muda), registrar ledger/md5 e o resultado de cada etapa aqui e no `docs/log.md`.

**Reversão (preparada; nunca automática).** `5357_R1_ROLLBACK_PROCEDURE.sql`: R0 somente leitura confirma existência, assinatura exata, sobrecarga única, ausência de dependentes e corpo igual à proposta; R1 (`DROP FUNCTION` exato, **sem CASCADE**) fica comentado e só roda com autorização explícita; R2 repete o R0 para confirmar a remoção.

**Riscos residuais relevantes.**
- As leituras inteiras das tabelas pequenas do percurso crescem com a base; repetir o V2 quando alguma passar de 128 páginas (§12).
- A garantia de transação única da C1 depende do mecanismo de aplicação; a C2 detecta estado parcial (ACL ou definição divergente).
- Os testes de comportamento só existem depois da aplicação; entre C1 e C2/C3 a função existe sem uso pela interface.
- C3b cobre só a coleção indicada; a cobertura de todos os fichários vem do V1.6 (sem chamar a função) ou do C3c, bloqueado.

## 15. Aplicação controlada no LIVE (2026-11-08)

Autorização: `PHASE C — LIVE CONTROLLED APPLICATION-01` (C1.0, C1, C2, C3a e C3b; C3c excluído). Projeto `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`, PostgreSQL 17.6.1.147). Executor: conector SQL do Supabase (`apply_migration` para C1; `execute_sql` para os blocos somente leitura).

| Etapa | Resultado | Evidência |
|---|---|---|
| C1.0 | PASS | projeto confirmado pela API de gestão (`ACTIVE_HEALTHY`); branch `main`, HEAD `bb3062a8…`, `05d` v2.73; 5357 md5 `4a309a81…` (sha256 `8e7138b8…`, 12.282 bytes); V3 v0.3 `5ab1aad0…`; bloco V1.1: `nome_livre_sem_sobrecarga` true, PG 17.6 |
| C1 | PASS | arquivo integral aplicado como uma migration (`apply_migration`, transação única, mesmo mecanismo da 5356): `5357_create_get_my_binder_value_groups`, versão no ledger `20261108042423`; retorno `success`; nenhuma outra migration |
| C2 | PASS | `pass` true; existe, assinatura, 14 colunas, SECURITY DEFINER, STABLE, `search_path` vazio, plpgsql, dono `postgres`, corpo (`prosrc`) md5 = `e6cdae3e…`, comentário presente; ACL exata `authenticated:EXECUTE, postgres:EXECUTE`; PUBLIC sem EXECUTE; efetivos: `postgres` true, `authenticated` true, `anon` false, `service_role` false — iguais aos da 5252 |
| C3a | PASS | `pass` true; anon `42501`; sem sub `28000`; coleção nula `22023`; limite 201 `22023`; offset negativo `22023`; coleção inexistente `P0002`; coleção de outro titular `P0002`; mesma mensagem nos dois `P0002` |
| C3b (1ª rodada) | **NÃO EXECUTADO** | nenhuma coleção autorizada pelo proprietário foi informada para o teste positivo; nenhuma coleção do LIVE foi presumida como autorizada |

Estado final: função `public.get_my_binder_value_groups(uuid, integer, integer)` presente no LIVE, com a definição e os privilégios aprovados; ainda não chamada pela aplicação. Nenhuma reversão executada. A promoção para `database/schema/` e a homologação dependem do C3b PASS.

**C3b — execução (`PHASE C — C3B FUNCTIONAL VALIDATION-01`).** Titular identificado de forma inequívoca por consulta somente leitura: exatamente **1** conta com o e-mail do proprietário do produto; essa conta é dona de 7 coleções proprietárias de fichário; escolha determinística da coleção proprietária (preferência por fichário com convidada, depois menor id) e da convidada desse mesmo fichário (menor id). Os identificadores foram usados só nas chamadas ao executor; **não estão** neste documento, no `docs/log.md` nem nas evidências. Chamada = prefixo de três linhas + bloco C3b do V3 v0.3 copiado sem alteração (md5 do bloco `9f0df69e…`; arquivo `5ab1aad0…`).

| C3b | Resultado |
|---|---|
| status / pass | `OK` / **true** (contexto READ ONLY + REPEATABLE READ e timeouts conferidos pelo próprio bloco; parâmetros validados) |
| fichário vazio | false |
| c3b_1 Σ cópias = `total_copies` = `filled_count` | true |
| c3b_2 linhas = `total_count` | true |
| c3b_3 totais constantes em todas as páginas | true |
| c3b_4 sem grupo repetido | true |
| c3b_5 páginas de 50 = páginas de 200 | true |
| c3b_6 página além do fim vazia | true |
| c3b_7 cópias ≥ 1 | true |
| c3b_8 subconjunto do Acervo (5261 sem filtro) e total ≤ Acervo | true |
| c3b_9 convidada = proprietária | true |

**Estado final:** fase C concluída com C1.0, C1, C2, C3a e C3b PASS. Função no LIVE com a definição e os privilégios aprovados, ainda não chamada pela aplicação. Fechamento (`B2 — FINAL DATABASE CLOSEOUT-01`): promovida a `database/schema/5357_create_get_my_binder_value_groups.sql` — difere do arquivo aplicado só no bloco Status; corpo `prosrc` md5 `e6cdae3e…` e trecho executável md5 `a84c3df3…` idênticos aos do arquivo aplicado (`4a309a81…`); `05d` v2.74 e README da proposta atualizados. Sem nova execução no banco.
