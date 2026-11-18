# V1-13 · E1-E2 — Cadeia protegida e prontidão para os ensaios G2

| Campo | Valor |
|-------|-------|
| **Rodada** | `V1-13 / E1-E2 \| PROTECTED CHAIN AND G2 TEST READINESS-01` (2026-11-15) |
| **Etapa oficial** | 6 — E1-E (em andamento). E1-E2 é subdivisão interna; as dez etapas não mudam. |
| **Status** | **E1 DEPLOY — PASS LIVE / BARRIER CLOSED (2026-11-18).** G2_A v2 e G2_B v3 PASS (§14); E1 implantada com a barreira CLOSED (§15). Histórico: **PREPARAÇÃO LOCAL — NÃO EXECUTADO. G2 NÃO INICIADO.** Sem SQL (nem SELECT), sem S0, sem P1, sem migration, sem harness em banco, sem conta, sem mudança de estado da barreira, sem commit. |
| **Base** | `main` em `9c11ea0` (G1 versionado). |
| **E2-D1** | defeito de compatibilidade **detectado e corrigido localmente** em `CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02` (§2): 5380 v1.1, 5891 v1.1, `static_check_e1b3.py`, P5380 e manifestos regerados. |

## Arquivos

| Arquivo | Papel |
|---|---|
| `build_g2_chain.py` | gerador determinístico: entradas com sha256 fixado (10 migrations não protegidas + 5389 + 12 harnesses; as 16 protegidas pelo `G1_MANIFEST.json`, também fixado); recusa ausência, divergência, duplicidade, ordem fora das dependências, harness fora do modo e redefinição desprotegida de capacidade |
| `G2_A_E1A_PROTECTED_rollback.sql` | **P1-G**: 5389 + E1-A protegida; 5861 [CLOSED], 5888 [OPEN] (105 verificações) |
| `G2_A_E1A_PROTECTED_rollback_MGMTAPI.sql` | variante de **canal** do G2_A para a Supabase Management API (§11); blocos T2–T9 idênticos; NÃO EXECUTADA |
| `G2_B_…_MGMTAPI.sql`, `G2_C_…_MGMTAPI.sql` | variantes de canal do G2_B/G2_C para a Management API: moldura e T6 do G2_A MGMTAPI + sentinela compacta (limite de 1.024 caracteres da CLI); critério `v_ok` idêntico; NÃO EXECUTADAS |
| `harness/5889_…_v1.3-E1E.sql`, `harness/5890…5893_…_v1.2-E1E.sql` | conferências internas de estado (classe B) lidas no contexto do dono; sob o EDITOR a RLS `select_own` devolvia vazio e as tabelas revogadas dariam 42501; originais preservados |
| `G2_B_CHAIN_STORAGE_LAST_rollback.sql` | cadeia completa, 5377 por último; 5861/5862/5864 [CLOSED], 5888–5894 [OPEN] antes da 5377; 5863 v1.3 [CLOSED], 5890 [OPEN], 5895 [CLOSED] depois (417) |
| `G2_C_CHAIN_FULL_FINAL_rollback.sql` | cadeia completa; os 12 harnesses no estado final (417) |
| `harness/5861_…_v1.5-E1E.sql`, `harness/5888_…_v1.1-E1E.sql` | correções só de harness após a execução LIVE do G2_A MGMTAPI (E2ANO, TXID 814967): 5861 3.8 aceita as chaves `binder_name`/`show_brand_mark` da 5321 (tipadas); 5888 faz as 16 conferências internas (classe B) no contexto do dono; originais da E1-A preservados |
| `harness/5863_…_v1.3-E1E.sql` | variante **autorizada** da 5863 (só a S.4 muda, linhas marcadas `-- E1E`; original preservado); v1.3 = alias de `pg_policies` `p`→`pol` (§12) |
| `harness/5863_…_v1.2-E1E.sql` | histórico: variante executada no G2_B LIVE (STOP 12 / 55000, §12); preservada, fora do manifesto |
| `executed/G2_B_…_MGMTAPI_EXECUTED-STOP12_9566d4f4.sql` | histórico: texto exato enviado no G2_B LIVE (sha256 `9566d4f4…`), recomposto byte a byte pelo gerador anterior; não reutilizar |
| `scan_alias_collisions.py` | varredura estática de homônimos alias SQL × variável PL/pgSQL (§12); usada pela verificação 4.3 |
| `harness/5889_…_v1.4-E1E.sql`, `harness/5890_…_v1.3-E1E.sql`, `harness/5892_…_v1.3-E1E.sql`, `harness/5893_…_v1.3-E1E.sql`, `harness/5894_…_v1.4-E1E.sql` | correção consolidada após o G2_B v2 LIVE (§13): C1 caminhos de imagem canônicos, 10.2 com pré-condição de fixture, C2 5894 3.4 pela leitura pública 5312; versões anteriores preservadas |
| `executed/G2_B_…_MGMTAPI_EXECUTED-V2-E2BNO_ba19c2f7.sql` | histórico: texto exato do G2_B v2 LIVE (E2BNO, TXID 815477); não reutilizar |
| `S0_G2_readonly.sql` | S0 ampliada, uma instrução SELECT (v1.1) |
| `S0_AUTHORIZATION.md` | pacote de decisão para uma eventual execução da S0 (não autoriza) |
| `G2_MANIFEST.sha256` | sha256 de todas as entradas e saídas |
| `static_check_e1e2.py` | verificação estática independente do gerador |

Todos os ensaios usam a moldura T0–T11 do P1 da E1-A: sessão somente leitura por padrão (T0), um único `BEGIN`, trava de COMMIT por FK adiada (T4), precheck do ambiente e da ausência de objetos da V1-13 (T6), `LOCK … NOWAIT` antes do DDL (T6, e antes da 5377), migrations no nível superior sem seus `begin;`/`commit;` (T7), harnesses `pg_temp` (T8), postcheck da barreira (T9) e sentinela que **sempre** aborta com SQLSTATE próprio (`E2AOK/E2ANO`, `E2BOK/E2BNO`, `E2COK/E2CNO`).

## 1. Inventário e sequência definitiva

Ordem operacional (não numérica): **5389** → 5366 → 5367 → 5368 → P5369 → P5370 → 5371 → 5372 → P5373 → P5374 → P5375 → P5376 → [P5377] → 5378 → 5379 → P5380 → 5381 → P5382 → P5383 → 5384 → P5385 → P5386 → P5387 → P5323 → P5324 → P5388 (P = versão protegida do G1). Dependências tiradas dos prechecks, mais a funcional 5384 → 5385–5387. A 5377 só depende de 5366, 5176 e 5329 e nenhuma migration posterior a referencia: pode ir ao fim (G2-B) ou ficar no lugar (G3, cada migration é uma transação curta). 5323/5324 têm número menor mas entram na E1-D. O gerador recusa qualquer outra ordem que viole as dependências e qualquer definição de capacidade fora da sua versão protegida.

## 2. E2-D1 — causa, equivalência funcional e correção

**Causa raiz.** A 5380 foi escrita conferindo as funções do titular contra `database/schema/6122_…` (o `static_check_e1b3.py` apontava para a 6122). Mas a `set_pokedex_position_assignment` foi redefinida pela `6123_fix_fatia_d_applied_objects_pause_sql_direct_audit.sql` (CONFIRMADO EXECUTADO; nenhum outro arquivo de `database/schema/` a redefine). Corpo da 6122: md5 `b2ba1c7de00420c15733a4d2f3e0bf43`; corpo da 6123 (canônico vigente): md5 `8c572182a03025503e993e5ecc25e07a`. As fontes estáticas não conflitam: a 6123 declara que substitui a 6122 por `CREATE OR REPLACE` e foi executada depois.

**6122 × 6123 (o que mudou no titular)** e **cobertura na função do EDITOR (5380, inalterada):**

| Correção da 6123 | `editor_set_pokedex_position_assignment` |
|---|---|
| confirmação fail-closed (`IS DISTINCT FROM TRUE`; NULL não confirma) | `coalesce(p_confirm_override, false)` — NULL não confirma |
| colunas sem ambiguidade no DELETE e na RETURNING | `#variable_conflict use_column`, alias `a.` no DELETE, INSERT sem RETURNING |
| trava da coleção **antes** da alocação | `assert_collection_editor` trava a coleção (`FOR UPDATE`) e a participação (`FOR SHARE`) antes; depois a alocação de X `FOR UPDATE` |
| coleção Pokédex **REFERENCE_BASED** explícita | `editor_pokedex_of_collection` exige `mode = 'REFERENCE_BASED'` e `REFERENCE_POSITION` |
| revalidação da alocação depois da trava | a alocação é lida e travada com `collection_id = X` depois da trava da coleção |

As duas correções dos gatilhos da 6123 (6118/6119) valem para qualquer INSERT na tabela de atribuições, inclusive o do EDITOR. **Nenhuma diferença funcional** impede a compatibilidade: só a constante de conferência estava errada.

**Correção mínima (diff exato):**
- `5380` v1.1: as duas constantes `b2ba…` → `8c57…` (pre e postcheck), a mensagem do precheck e o cabeçalho (6122 → 6123). Corpos das funções do EDITOR **idênticos** (md5 do manifesto G1 inalterados).
- `5891` v1.1: 0.3 `b2ba…` → `8c57…`; L4 e texto do detalhe.
- `static_check_e1b3.py`: `OWNER_DEX` da `set_pokedex_position_assignment` → arquivo 6123.
- `README.md` da E1-B3: seção "Correção E2-D1".
- Regerados: `g1/protected/5380`, `G1_MANIFEST.json` (só `base_sha256` e `protected_sha256` da 5380), ensaios G2 e `G2_MANIFEST.sha256`; sha256 fixados atualizados no `build_g2_chain.py`. Prechecks não removidos; falha fechada preservada.
- **Verificações:** `static_check_e1e2.py` 6.1 e 6.2 passam (não foram afrouxadas); `static_check_e1b3.py` 42/42 com a 6123.

**Defeito corrigido no G1 (harness, não mecanismo):** a 5895 0.4 fixava em `get_shared_collection` o md5 da 5308 (`e36aa…`). Corrigida (v1.1) para o corpo da 5368 (`69d69fd1…`), com a 5308 conferida à parte. A redação "5888 fixa … 5312" do plano também foi corrigida (é a 5308). Encontrado pela mesma conferência.

## 3. Reconciliação com o P1

| Item | P1 original (E1-A) | P1-G (`G2_A`) |
|---|---|---|
| Moldura T0–T11, canal, trava de COMMIT, T3, recusa de PG < 14 | — | **idêntica** (verificação 3.1) |
| T6 precheck | ambiente, gatilhos externos, sessões em `collection_membership` | idem + **ausência de objetos da V1-13** + gatilhos de `storage` |
| LOCK NOWAIT | `collection_membership` | idem |
| T7 | 5366, 5367, 5368, 5369, 5370 | **5389** + 5366/5367/5368 **byte a byte iguais** + **P5369/P5370** |
| T8 | 5888 | **5861 v1.4 em CLOSED** (V1-12 intacta com a barreira fechada) + **modo OPEN** + 5888 (corpo idêntico) + **CLOSED** |
| T9 | estado da E1-A | barreira de volta a CLOSED e registro vazio; nenhuma capacidade exposta sem porta |
| Sentinela | `E1AOK/E1ANO`, 54 verificações, ≤ 10 s | `E2AOK/E2ANO`, 105 verificações, ≤ 20 s (limite proposto) |

**CLOSED** é verificado pela 5861 (V1-12 com a porta fechada) e pelo postcheck; **TEST** pela 5895 (só nos ensaios da cadeia, porque ela exige as 37 capacidades); a **autorização funcional** é exercida com OPEN só dentro da transação abortada, para a barreira não recusar antes da regra do produto; o estado inicial é restaurado pelo aborto (prova: `txid_status = aborted` + S0 repetida). O P1 original fica **preservado** como evidência histórica (sha256 igual ao manifesto da E1-A, verificação 3.2) e deixa de ser o ensaio a executar.

## 4. Revisão dos harnesses 5862–5864

| Harness | Cenários | Classificação | Motivo |
|---|---|---|---|
| 5862 (paridade VIEWER, 33) | S, F, P, N, B, M, PB, R | **válido sem ajuste** | convites VIEWER de 2 argumentos (padrão `'VIEWER'` da 5369); leituras 5320/5321/5316 inalteradas; nenhum md5 fixado; histórico gravado pela 5379 no caminho do titular e desfeito pela sentinela; nenhuma dependência de papel além de VIEWER. Roda em **CLOSED** |
| 5863 (imagens compartilhadas, 37) | S.4 | **incompatível com o contrato vigente → variante v1.2-E1E AUTORIZADA (vigente: v1.3-E1E, §12)** | a S.4 original exige "9 políticas" e "toda escrita com `auth.uid()`"; a 5377 acrescenta 3 políticas do EDITOR. A variante confere **individualmente** as 12 políticas por nome, comando, papéis, caráter permissivo e predicado (7 do dono: pasta do próprio usuário por `auth.uid()`, só `authenticated`, UPDATE com as duas expressões; 2 de leitura compartilhada: `anon`+`authenticated`, decisão delegada; 3 do EDITOR: só `authenticated`, inserção pelo ajudante, leitura e exclusão só do próprio envio por `owner_id = auth.uid()` e pelo ajudante), exige **conjunto fechado** (nenhuma outra política nos dois buckets, nenhuma restritiva, nenhuma escrita para `anon`, nada para PUBLIC) e prova a dependência de identidade dos ajudantes (definer, sem EXECUTE para `anon`, `(select auth.uid())`, participação EDITOR ativa, porta `v1_13_capability_open`, pasta do próprio titular recusada). Original preservado |
| 5863 | demais (S.1–S.3, S.5, F, I, ST, C, N, PB, SO, RM) | **válido sem ajuste** | VIEWER B não é EDITOR: as políticas novas não lhe concedem nada (e a porta está fechada); objetos inseridos como dono e desfeitos |
| 5864 (logo, 7) | todos | **válido sem ajuste** | só o bucket `card-set-logo`; nenhuma política da V1-13 nele |
| 5862–5864 | resolução pelo PostgREST e pela API do Storage (H.6) | **dependente de prova dinâmica adicional** | G3/G4 |

## 5. Matriz de execução dos harnesses

| Harness | Migrations necessárias | Modo | Identidades | Efeitos | Histórico | Travas relevantes | Rollback | Exigido | Falso PASS pela barreira? |
|---|---|---|---|---|---|---|---|---|---|
| 5861 v1.4 | E1-A | CLOSED | sintéticas | fixture desfeita (sentinela) | não | O1 | aborto | 51/51 | não: não chama capacidade nova |
| 5862 | E1-A (+V1-12) | CLOSED | sintéticas | idem | eventos do titular | O1, O3 (B/C) | aborto | 33/33 | não |
| 5863 v1.3 | +5377 | CLOSED | sintéticas | objetos de Storage | não | **O2** | aborto | 37/37 | não |
| 5864 | — | CLOSED | anon/authenticated | nenhuma escrita | não | — | aborto | 7/7 | não |
| 5888 | E1-A | OPEN | sintéticas | idem | não | O1 | aborto | 54/54 | evitado: OPEN deixa a regra funcional decidir |
| 5889 | E1-B1 | OPEN | sintéticas | idem | eventos (5379) | O1, O3 | aborto | 56/56 | idem |
| 5890 | E1-B2 + 5377 | OPEN | sintéticas | objetos de Storage | eventos | O1, **O2**, O3 | aborto | 45/45 | idem |
| 5891 | E1-B3 | OPEN | sintéticas | idem | eventos | O1, O3 | aborto | 33/33 (E2-D1 corrigido: 0.3 confere a 6123) | idem |
| 5892 | E1-C1 | OPEN | sintéticas | idem | eventos | O1, O3, O4 | aborto | 27/27 | idem |
| 5893 | E1-C2 | OPEN | sintéticas | idem | eventos | O1, O3, O4 | aborto | 24/24 | idem |
| 5894 | E1-D | OPEN | sintéticas | idem | eventos gravados direto | O1, O3 | aborto | 29/29 | idem |
| 5895 | cadeia + 5377 | CLOSED → TEST/OPEN internos → CLOSED | sintéticas | registro e modo dentro da transação | não | O1, **O2**, O3 | aborto | 21/21 | é a prova da barreira; recusa da barreira identificada pela mensagem exata, nunca contada como prova funcional |

Regra do gerador e do verificador: harness funcional nunca roda em CLOSED; harness da V1-12 nunca roda em OPEN; 5895 começa em CLOSED; o ensaio termina em CLOSED.

**OPEN pode mascarar defeito da barreira?** Sim, se fosse a única prova. Por isso: (a) OPEN só existe dentro da transação abortada; (b) a 5895 prova CLOSED e TEST de forma independente, com contas registradas e não registradas, nas 37 capacidades; (c) o postcheck exige que nenhuma capacidade exposta esteja sem porta; (d) G3 prova a negação com JWT real.

## 6. Plano de travas

| Op. | Objeto | Comando | Lock | Aquisição | Fila | Retenção | Impacto V1-12 | Storage | Limite proposto | STOP | Recuperação |
|---|---|---|---|---|---|---|---|---|---|---|---|
| O1 | `collection_membership` | `LOCK … NOWAIT` (T6) e `ALTER TABLE` (5366) | ACCESS EXCLUSIVE | imediata ou `55P03` | nenhuma (NOWAIT) | até o aborto | compartilhamento, convites, "compartilhadas comigo" esperam | — | janela fora de uso | `55P03`, timeout | aborto; repetir só com nova autorização |
| O3 | `binder_activity_event`, `binder_activity_item` | `LOCK … NOWAIT` (T6); `ALTER TABLE` (5379) | ACCESS EXCLUSIVE | idem | nenhuma | até o aborto | toda operação de fichário que grava histórico espera | — | idem | idem | idem |
| O4 | `binder_activity_event` | `CREATE TRIGGER` (5381); `CREATE OR REPLACE` da função (5384) | SHARE ROW EXCLUSIVE (já coberto pelo O3) | — | — | até o aborto | idem | — | — | — | — |
| O2 | `storage.objects` | `LOCK … NOWAIT` imediatamente antes da 5377; `CREATE POLICY` ×3 | ACCESS EXCLUSIVE | idem | nenhuma | **G2-B:** só durante 5863/5890/5895; **G2-C:** durante os 12 harnesses | — | **todo** o Storage (inclusive vitrine) espera | janela sem tráfego de Storage | `55P03`, privilégio insuficiente, timeout | aborto |
| O5 | funções | `CREATE/REPLACE FUNCTION` (cadeia) | linha de `pg_proc` | — | — | até o aborto | chamadas às versões antigas seguem pelo MVCC; só um `CREATE OR REPLACE` concorrente das mesmas funções esperaria | — | — | — | — |
| O6 | catálogo, `auth.users`, tabelas de coleção | fixtures | ROW EXCLUSIVE; KEY SHARE em linhas reais referenciadas | — | — | até o aborto | só alteração de chave dessas linhas esperaria | — | — | gatilho externo na S0 | aborto |
| O7 | canal | psql direto | — | — | — | — | — | — | só psql, conexão direta | canal diferente → recusa | — |

**Estático × versão real:** os modos de trava e a ordem são demonstráveis no texto; dependem da versão e do ambiente real: `transaction_timeout` (só PG ≥ 17; sem ele o teto total é a sentinela ou o operador), `client_connection_check_interval`, o privilégio do executor para `LOCK`/`CREATE POLICY` em `storage.objects` e a duração efetiva (não medida; os limites de 20 s/240 s são propostas).

### Tratamento da 5377

| Alternativa | O que prova | O que fica sem cobertura |
|---|---|---|
| Ensaio reduzido só das políticas (harness novo, não preparado) | autorização de Storage por SQL | integração com a capa (5376); estado final; não preparado nesta rodada |
| Ensaio separado de integração com a capa (5890 com E1-A/B1/B2) | 5890 inteiro | estado final com B3…D |
| Regressão sem 5377 (G2-B, primeira parte) | 5888–5894 com a cadeia sem Storage | interação 5377 × B3…D só por argumento estático |
| Prova final com 5377 (G2-B, segunda parte; G2-C) | 5863 v1.3, 5890 e 5895 no estado final (G2-C: todos) | G2-B: 5888–5894 não repetidos depois da 5377 |
| Janela própria para Storage | reduz impacto do O2 | não substitui nenhuma prova |

Nenhuma validação parcial é apresentada como prova da cadeia completa: G2-B só vale como cadeia completa para os harnesses que rodam depois da 5377.

## 7. S0 ampliada

`S0_G2_readonly.sql` (não executada). **Observável em S0:** versão e disponibilidade de `transaction_timeout`; executor; dono, pertença e privilégios em `collection_membership`, histórico, `storage.objects`, `auth.users`; md5 vigentes de 24 funções fixadas (todas as sobrecargas, por nome) × canônicos de `database/schema` (**inclusive o da 6123**, que decide o E2-D1); ausência de objetos da V1-13 (barreira, CHECK, sobrecargas do convite, funções, colunas da 5379, gatilho); buckets e políticas atuais de Storage; gatilhos com efeito externo em public/auth/storage; gatilhos de evento; publicações; extensões; ledger recente; sessões com trava; timeouts dos papéis da API; pré-requisitos e resíduo das fixtures; contagens. **Só por ensaio:** se `LOCK`/`CREATE POLICY` em `storage.objects` funcionam de fato; retenção real; duração; comportamento das versões protegidas.

## 8. Rollback e preservação

| Camada | Mecanismo | Alcance | Não desfaz |
|---|---|---|---|
| G2 | aborto da transação (sentinela) + `txid_status` + S0 repetida | tudo | sequências, tuplas mortas, `pg_stat*`, log, WAL; esperas sentidas |
| G3 (futuro, plano próprio) | CLOSED; `EMERGENCY_STOP_V1_13.sql`; `ROLLBACK_E1D` … `ROLLBACK_E1A` e por último `ROLLBACK_G1` | funções, políticas, porta; dados gravados preservados | mudanças compartilhadas já vistas; dados gravados |
| G4 (futuro) | compensação de identidades e dados de teste (`g1/README.md` §9) | contas de teste e o que é delas | histórico imutável fora das contas de teste (por isso proibido testar em coleções reais); logs |

A exclusão de uma conta de teste **não** resolve efeitos externos (logs, WAL, Storage sem cascata) nem eventos gravados em fichários de outros titulares — daí a vedação de fixtures em coleções reais.

## 9. G2 × G3/G4

**G2 (transação abortada, estes artefatos):** cadeia protegida, funções compartilhadas da V1-12 (5861–5864), autorização do EDITOR (5888–5894), leituras compartilhadas (5894), Storage por SQL (5863 v1.2, 5890), barreira em CLOSED/TEST/OPEN (5895), integridade do histórico (5889, 5891, 5894), rollback por aborto. Nenhuma depende de mudança visível a outra sessão.

**Só em G3/G4 (pendentes, não iniciados):** JWT real e PostgREST (P4-A/P4-B); Storage pela API (ST1–ST9) e envios simultâneos; S8 concorrente e S10; PR-04B; revogação durante operação em curso; medições M1–M7; compensação de dados persistidos.

**Critérios de entrada no G2 (para autorização futura):** correção E2-D1 e variante 5863 revisadas e versionadas; revisão independente do G1 e da E1-E2; S0 autorizada e aprovada (versão ≥ 14, sem gatilho externo, md5 vigentes = canônicos, nada da V1-13, privilégios em `storage.objects`, conexão direta); janela fora de uso para O1/O3 e sem tráfego de Storage para O2; autorização por hash do arquivo, executor, canal e janela. **Critérios de saída:** SQLSTATE `E2xOK`, GATE de cada harness PASS, `txid_status = aborted`, pós-estado igual à S0; qualquer outro desfecho = FAIL ou STOP, sem "repetir até passar".

## 10. Riscos e bloqueios remanescentes

E2-D1 corrigido localmente (pendente de revisão e do commit; até o commit, as verificações estáticas da E1-C1, E1-C2 e E1-D acusam a alteração da pasta da E1-B3); S1–S10 sem prova dinâmica; S8/S10 concorrentes; PR-04B; P4-A/P4-B; API real do Storage; O1–O7; mudanças compartilhadas; versão e privilégios do LIVE não confirmados; desempenho não medido; G2–G5 pendentes; etapa 7 bloqueada; nenhum ambiente isolado; nenhuma autorização para o LIVE.

## 11. Variante de canal do G2_A — Management API

Contexto: a senha do PostgreSQL não está disponível, e o único canal é a Management API (MCP `execute_sql`). A prova `G2A-PROOF-01` (2 chamadas, evidências fora do repositório) mostrou PASS: o texto com várias instruções forma **uma transação implícita**, o `SET LOCAL` vale nas instruções seguintes, o erro interrompe o restante (`E2PXX` não alcançado), SQLSTATE e mensagem são devolvidos (`ERROR:  E2POK: …`) e `txid_status` = `aborted`. A prova valida só a semântica do canal, não as migrations.

`build_g2_chain.py` gera `G2_A_E1A_PROTECTED_rollback_MGMTAPI.sql` pela mesma derivação do G2_A (`CHANNEL_VARIANTS`); a saída psql continua byte a byte igual. Só a moldura muda:

| Moldura | psql (original) | Management API |
|---|---|---|
| metacomandos `\set` | sim | retirados (o servidor não os aceita) |
| T0 `SET SESSION default_transaction_read_only` | sim | retirado: na transação implícita seria desfeito; a proteção contra instruções após erro vem do protocolo, que interrompe o restante do texto |
| T1 `BEGIN` / T10 `ROLLBACK` / T11 `RESET` | sim | retirados: com `BEGIN` explícito, o erro deixaria a conexão do pool num bloco falho |
| T6 (precheck) | exige `default_transaction_read_only = on` (T0) e recusa todo gatilho de evento cujo corpo cite `pg_net`/`net.`/`http_`/`dblink` | **2 ajustes exatos (CORRECTION-03, verificações 9.1 e 9.4):** não exige `default_transaction_read_only = on` (sem T0; a S0 observou `off`), mantém `transaction_read_only = off`; exceção única para `issue_pg_net_access` só se `ddl_command_end`, tags exatamente `{CREATE EXTENSION}` e função `extensions.grant_pg_net_access` (gatilho padrão do Supabase, `supabase/postgres` `00000000000003-post-setup.sql`); o ensaio não tem `CREATE/ALTER/DROP EXTENSION`; gatilhos de tabela e demais gatilhos de evento continuam recusados |
| demais T2–T9 | — | **idênticos** (verificação 9.1): `SET TRANSACTION READ WRITE`, limites `SET LOCAL` e `transaction_timeout`, trava de COMMIT, `LOCK … NOWAIT`, 5389 → 5366–5370, 5861 [CLOSED] e 5888 [OPEN] (105 verificações, 2 GATEs), postcheck e sentinela `E2AOK/E2ANO` |

Proteção contra persistência no canal: a sentinela sempre aborta a transação implícita; se ela não for alcançada (texto truncado, por exemplo), a confirmação implícita esbarra na trava de COMMIT (FK adiada criada no T4, antes de qualquer DDL) e falha; nenhum controle de transação explícito existe no arquivo (verificação 9.2). Depois da execução, `txid_status(<txid da sentinela>)` tem de ser `aborted`.

Limitações não demonstradas: o tamanho do texto (≈133 KB) numa chamada da API; a integridade do texto transmitido só é conferida depois, pelo histórico da chamada; o SQLSTATE é lido da mensagem formatada; o comportamento das migrations e dos harnesses só o ensaio mostra. Execução: não autorizada; exige revisão independente e autorização própria.

## 12. G2_B LIVE — STOP 12 / SQLSTATE 55000 / S.4

**Resultado registrado (2026-11-17T02:01:56Z, executor `G2_B_MGMTAPI_CLI_harness.ps1`, texto `9566d4f4…`):** `G2_B LIVE — STOP 12 / SQLSTATE 55000 / S.4`. A CLI devolveu o corpo de erro truncado (não JSON) — daí o STOP 12; o corpo mostra `ERROR: 55000: record "p" is not assigned yet` no contexto da `pg_temp.wh_5863_validate()`, S.4. **Rollback não confirmado** por evidência direta (sem `txid_status` nesta rodada); pela moldura, o erro aborta a transação implícita antes de qualquer `COMMIT` e a trava de COMMIT (FK adiada do T4) impediria confirmação. A trava `runsG2B\G2B_MGMTAPI_LIVE.trava` foi consumida e **permanece**; nova execução exige executor versionado (novo hash do texto, nova pasta e nova trava) e autorização explícita.

**Causa raiz (comprovada estaticamente):** a S.4 introduzida pela variante v1.2-E1E usa `from pg_policies p` (5 subconsultas, 53 referências `p.<coluna>`) dentro de uma função que declara `p record;` (usada legitimamente depois em `select * into p from public.preview_my_collection_binder(…)` e no laço `for p in …`). Sem `#variable_conflict use_column`, o PL/pgSQL resolve `p.policyname` também como campo da variável `p`; como ela ainda não foi atribuída na S.4, a análise da consulta falha com 55000 (se estivesse atribuída, o erro seria 42703 ou 42702). A primeira expressão que falha é `on p.policyname = e.n and p.cmd = e.c` da primeira subconsulta. A S.4 original da 5863 usava `pg_policies` sem alias; os demais blocos da 5863 não mudaram.

**Correção mínima (v1.3-E1E):** em `S4_NEW` do gerador, alias `p`→`pol` (5 aliases, 53 referências), só em linhas `-- E1E`. Critérios idênticos: `S.4(v1.3)` com `pol.`→`p.` é byte a byte a `S.4(v1.2)` (verificação 4.3). Nada muda nas 7 políticas do dono, nas 12 do conjunto, nos comandos, condições e escopos, na lógica de aprovação, nas migrations, permissões e RLS. G2_A psql e MGMTAPI byte a byte iguais; G2_B/G2_C: 417 verificações, 12 GATEs, sentinela compacta, travas `NOWAIT` e trava de COMMIT preservadas.

**Varredura preventiva (`scan_alias_collisions.py`, só os corpos PL/pgSQL dos quatro ensaios G2_B/G2_C):** antes da correção, 1 DEFEITO por ensaio (o da S.4) e nenhum outro; depois, 0 DEFEITO/0 REVISAR. Restam homônimos sem efeito: `q record` como alias de `pg_proc q` em 5893 e 5894 (corpos com `#variable_conflict use_column`: a coluna prevalece) e variáveis escalares (`m11`, `m12`, `v_policy`, `r`, `p2`), que o PL/pgSQL não resolve como `nome.campo`. Nas 191 linhas `-- E1E` de cada ensaio, nenhuma referência qualificada a variável record.

## 13. G2_B v2 LIVE — E2BNO / TXID 815477 e correção consolidada dos harnesses

**Resultado registrado (2026-11-17T02:21:17Z, `G2_B_MGMTAPI_CLI_harness_v2.ps1`, texto `ba19c2f7…`):** `FAIL (21)` — E2BNO, 1 POST, TXID 815477, 327/417 linhas, 321 PASS, 6 falhas (`5889:10.1`, `5889:10.3`, `5890:X.1`, `5892:X.1`, `5893:X.1`, `5894:X.1`), `x1_count = 4`, `trap_intact = true`, 4 travas, 4.352 ms. Sem `txid_status()` (caminho E2BNO); aborto não confirmado de forma independente. Trava `runsG2B_v2\G2B_MGMTAPI_LIVE_v2.trava` consumida e mantida; texto executado preservado em `executed/`.

**Causas (diagnóstico estático, `CONSOLIDATED ROOT CAUSE ANALYSIS-01`):** C1 — caminho de imagem de bolso com nome literal (`<dono>/<fichário>/wh589N.webp`) viola `chk_collection_layout_slot_image_path_format` (5232: três UUIDs) → 23514 na 10.1 (capturado; desfaz a página 2 e derruba a 10.3) e X.1 em 5890, 5892 e 5893. C2 — a 5894 3.4 chamava `collection_completion_summary_shared` (5310, interna, `REVOKE` de `authenticated`; afirmado pela 5861 0.3) sob o EDITOR → falta de EXECUTE → X.1. A 10.2 passou sem a página 2 (falso positivo). Contas: 292 linhas dos 8 harnesses sem X.1 + 7 (5890) + 4 (5892) + 10 (5893) + 14 (5894) = 327; 94 verificações não alcançadas. Nenhum defeito de migration, função, CHECK, RLS ou privilégio.

**Correção (`CONSOLIDATED HARNESS CORRECTION-01`, só harnesses; linhas `-- E1E`):** C1 nos cinco pontos (5889 10.1; 5890, 5892 montagem; 5893 1.6 e plano de incorporação) — `<dono>/<fichário>/<gen_random_uuid()>.webp`, mesmo padrão da 5863/5890 §11. 10.2 exige, em conjunção e no contexto do dono, a imagem em 2:1:1 e a mesclagem r2c1–r2c2 da página 2 (sem a página, `wh_5889_slotp` é NULL e o EXISTS é falso). C2: 5894 3.4 lê `satisfied_positions`/`total_positions` do EDITOR por `get_shared_collection` (5312/5368: mesma 5310, mesma coleção, BIGINT, só OWNER/VIEWER-nível), critério final idêntico. 417 verificações e 12 GATEs preservados; nenhuma verificação nova nos harnesses; G2_A byte a byte igual. Verificações 3.5a/b/c (46/46).

## 14. E1-E — Encerramento documental de G2_A e G2_B (2026-11-17)

| Ensaio | Executor (sha256) | SQL (sha256) | Resultado | TXID | `txid_status` | Evidência (`Downloads\mmkyu-g2a-cli\`) |
|---|---|---|---|---|---|---|
| G2_A v1 | `G2_A_MGMTAPI_CLI_harness.ps1` (`062a5496…`) | `3b287fc9…` | FAIL (E2ANO; 5861 3.8 e 5888) | 814967 | — | `runsG2A\` (trava `049597c0…`) |
| **G2_A v2** | `G2_A_MGMTAPI_CLI_harness_v2.ps1` (`4cf580c7…`) | `1b6defd7c3762aa8b148e94105b96569fb536d7933a8c33f63bcc6edf7023095` | **PASS** — E2AOK, 105/105, 2 GATEs, `trap_intact`, 1.321 ms, 1 POST | **815141** | **aborted** | `runsG2A_v2\run-20261117T014216054Z` (`run.json` `68ed8eaf…`; trava `ac718381…`) |
| G2_B v1 | `G2_B_MGMTAPI_CLI_harness.ps1` (`bccc4ab0…`) | `9566d4f4…` (`executed/`) | STOP 12 — 55000 na S.4 (§12) | — | — | `runsG2B\` (trava `4ac855f6…`) |
| G2_B v2 | `G2_B_MGMTAPI_CLI_harness_v2.ps1` (`ad6bbbb9…`) | `ba19c2f7…` (`executed/`) | FAIL 21 — E2BNO, 327/417 (§13) | 815477 | — | `runsG2B_v2\` (trava `db8ab366…`) |
| **G2_B v3** | `G2_B_MGMTAPI_CLI_harness_v3.ps1` (`6e68b302d5e6fd22d16f86334a72c659f8b2fd38c8d3237d39d99a736a483b6a`) | `539707c83a8f851f2b74ae4e2bf35557293eab3e2f6f90dcd36b103ae49b8f01` | **PASS** — E2BOK, 417/417, 12 GATEs, 4 travas, `trap_intact`, 8.610 ms, 1 POST, PG 170006 | **821566** | **aborted** | `runsG2B_v3\run-20261117T232241186Z` (`run.json` `4b92a106…`; trava `3a512e51…`) |

**Tentativas sem `txid_status` (G2_B v1 e v2):** a ausência de persistência decorre do T6 do G2_B v3, que recusa a execução se qualquer objeto da V1-13 existir (`v1_13_barrier_state`, `collection_member_role`, convite de 3 argumentos) e passou em 2026-11-17T23:22Z — nada daquelas tentativas foi confirmado. Prova por inferência, não por `txid_status`.

**G2_C — dispensa recomendada (decisão do proprietário).** Mesmas 26 migrations na mesma ordem (5377 por último nos dois); a diferença é só a posição de 9 harnesses (5861, 5862, 5864, 5888, 5889, 5891–5894), que no G2_B rodam antes da 5377. A 5377 só cria 2 funções novas e 3 políticas de `storage.objects` restritas ao bucket `collection-cover` e a `authenticated`; não substitui objeto existente; nenhuma migration posterior a referencia; desses 9 harnesses só a 5864 lê `storage.objects`, e apenas `card-set-logo` sob `anon`, filtro que as políticas da 5377 não alcançam. O estado final foi provado no G2_B v3 pela 5863 (conjunto fechado das 12 políticas), 5890 e 5895 (barreira nas 37 capacidades) e pelo postcheck. O G2_C reteria `storage.objects` em ACCESS EXCLUSIVE durante todos os harnesses, sem ganho material. Limitação: a combinação 5377 × 5888–5894 fica provada por argumento estático (§6, "Tratamento da 5377").

**Ordem de aplicação provada:** 5389 → 5366 → 5367 → 5368 → P5369 → P5370 → 5371 → 5372 → P5373 → P5374 → P5375 → P5376 → 5378 → 5379 → P5380 → 5381 → P5382 → P5383 → 5384 → P5385 → P5386 → P5387 → P5323 → P5324 → P5388 → P5377 (hashes no `G2_MANIFEST.sha256`). Diverge de `g1/README.md` §6, que lista a P5377 logo após a P5376; a ordem acima é a ensaiada.

**Não comprovado por G2 (transação abortada):** JWT real e PostgREST, Storage pela API, S8 concorrente, S10, PR-04B, revogação durante operação em curso, medições de desempenho, compensação de dados persistidos.

## 15. Etapa 7 — Implantação controlada da E1: PASS LIVE / BARRIER CLOSED (2026-11-18)

**Resultado: E1 DEPLOY — PASS LIVE / BARRIER CLOSED.** As 26 migrations da E1 estão aplicadas no projeto `qjfutqujxrbzgrtkpgkg` (PG 17.6) com a barreira em **CLOSED** e o registro de identidades vazio. Isto é **implantação persistente**, não abertura funcional: nenhuma capacidade nova responde a clientes até uma decisão de abertura (TEST/OPEN), que não foi tomada; E2, E3 e E4 não foram iniciadas.

| Execução | Executor (sha256) | Manifesto | Resultado | Evidência (`Downloads\mmkyu-e1-deploy\`) |
|---|---|---|---|---|
| S0 v1.1 (só leitura) | `S0_MGMTAPI_CLI_executor.ps1` (`dd7c22f6…`) | S0 `142d1492…` | S0 CAPTURADA (0), 1 POST, sessão `supabase_read_only_user`; parecer GO | `runsS0\` |
| Implantação | `E1_DEPLOY_CLI_executor.ps1` (`42642188…`) | `E1_DEPLOY_MANIFEST.txt` (`4a6f6522…`, 26 linhas) | **FAIL 22**: 24/24 CONFIRMADA (1 POST cada, 01:49:36Z–01:50:48Z); **5388 RECUSADA** (42601 `syntax error at or near "to_"`, LINE 102); 5377 não enviada; diagnóstico só leitura: barreira CLOSED, 0 identidades, 33 capacidades, 0 sem porta, 0 `anon`, 5388/5377 ausentes | `runsE1DEPLOY\run-20261118T014929499Z` (`run.json` `79dcc497…`; trava `13905c14…`) |
| Recuperação R1 | `E1_RECOVERY_R1_CLI_executor.ps1` (`f1353a53…`) | `E1_RECOVERY_R1_MANIFEST.txt` (`64cafd18…`, 2 linhas) | **PASS (0)**: estado inicial = 24 confirmadas; 5388 R1 (`f2eecea5…`) e 5377 (`badd1f54…`) CONFIRMADA (1 POST cada, 02:03:31Z–02:03:40Z); estado final: 26/26 marcadores, 37 capacidades, 0 sem porta, 0 `anon`, barreira CLOSED, 0 identidades | `runsE1RECOVERY_R1\run-20261118T020325030Z` (`run.json` `8b4e7ed8…`; trava `3ff43a63…`) |

**Causa da recusa da 5388 e revisão R1.** No cabeçalho da 5388 (base `e1d` `5276f8d2…` e protegida G1 `e0600cf3…`), o texto `from_*/to_*` contém `*/` e fecha o comentário de bloco aberto na linha 6; o resto do cabeçalho virou SQL. O G2 não detectou porque o gerador envia só o corpo entre `begin;` e `commit;`; a implantação envia o arquivo inteiro. Como a falha é de análise, o PostgreSQL rejeitou o texto inteiro antes de executar qualquer instrução (o diagnóstico confirmou a 5388 ausente). A **R1** troca só `from_*/to_*` por `from_* e to_*` no comentário; o corpo entre `begin;` e `commit;` é byte a byte o original e o executado no G2_B v3 (`539707c8…`). Artefatos versionados em `../e1deploy/` (R1, os dois manifestos, a consulta de estado `c75e9b39…` e o diff).

**Regra de rastreabilidade.** A base e a protegida originais da 5388, o `G1_MANIFEST.json` (`03823d13…`) e o gerador G1 ficam **inalterados**: são as entradas do G2 aprovado e da tentativa que falhou. O texto canônico implantado da 5388 é a R1 (`f2eecea5…`); as outras 25 são os arquivos do `E1_DEPLOY_MANIFEST.txt`, com os hashes ali fixados. Qualquer promoção para `database/schema/` ou regeneração da G1 parte desses textos (para a 5388, da R1 — nunca da base nem da protegida).

**Ledger:** o canal (`db query`) não grava `supabase_migrations` (decisão registrada; precedentes da V1-16 e da 5365). **Não comprovado:** S8 concorrente, S10, PR-04B, P4-A/P4-B (JWT real e PostgREST), Storage pela API, medições M1–M7.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Preparação local (2026-11-15, `E1-E2 \| PROTECTED CHAIN AND G2 TEST READINESS-01`).** Gerador e três ensaios G2 (P1-G, cadeia com 5377 por último, cadeia completa), variante proposta 5863 v1.2-E1E, S0 ampliada, manifesto, verificação estática; bloqueio E2-D1 (md5 da 6123); 5895 v1.1 (md5 da 5368). Nada executado; G2 não iniciado. |
| 1.1 | **Correção (2026-11-15, `CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02`).** E2-D1 corrigido localmente (5380 v1.1, 5891 v1.1, static_check_e1b3, P5380, G1/G2 regerados); 5863 v1.2-E1E com conjunto fechado e prova dos ajudantes; guardas de alteração das verificações G1/E1-E2 passam a aceitar só as 4 mudanças autorizadas, com sha256 exato. Nada executado; G2 não iniciado. |
| 1.2 | **Pacote de autorização da S0 (2026-11-15, `S0 AUTHORIZATION READINESS-01`).** S0 v1.1 (papeis_api só com timeouts; pré-condições do executor; timeouts efetivos da sessão); `S0_AUTHORIZATION.md` (reconciliado em `S0 V1.1 LOCAL CLOSEOUT AND COMMIT-02`: procedimento Windows PowerShell, segurança do canal, governança de evidências); verificação 5.1 reforçada e 5.3 nova (35/35). S0 não executada. |
| 1.3 | **Variante de canal do G2_A (2026-11-16, `G2_A MANAGEMENT API VARIANT — GENERATION AND STATIC REVIEW-01`).** `build_g2_chain.py` passa a gerar `G2_A_E1A_PROTECTED_rollback_MGMTAPI.sql` (só a moldura muda; G2_A original byte a byte igual); §11; `static_check_e1e2` 9.1–9.3 (38/38). Nada executado. |
| 1.4 | **Compatibilidade do T6 com o canal (2026-11-16, `G2_A MGMTAPI — T6 COMPATIBILITY CORRECTION-03`).** Dois ajustes do T6 só na variante MGMTAPI, derivados pelo gerador (`T6_MGMTAPI`): sem exigência de `default_transaction_read_only = on`; exceção única e verificada em execução para `issue_pg_net_access`. G2_A psql byte a byte igual (a recusa do `issue_pg_net_access` também o afetaria no LIVE — divergência registrada, não corrigida). `static_check_e1e2` 9.1 (diferença delimitada) e 9.4 nova (39/39). Nada executado. |
| 1.5 | **Exceção NULL-safe (2026-11-16, `G2_A MGMTAPI — NULL-SAFE EVENT TRIGGER CORRECTION`).** A exceção do `issue_pg_net_access` passa de `and not (…)` para `and (…) is not true`: só é excluído da recusa o gatilho com conformidade comprovadamente verdadeira; qualquer NULL (tags, schema) ou divergência mantém a recusa. Variante sha256 `3b287fc9…703a`; G2_A psql inalterado; 39/39. Nada executado. |
| 1.6 | **Correção de harness após a execução LIVE (2026-11-16, `G2_A LIVE FAIL — TARGETED HARNESS CORRECTION-01`).** Causas comprovadas: 5861 3.8 desatualizada em relação à 5321 (chaves `binder_name`/`show_brand_mark`); 5888 lia `collection_membership`/`collection` sob `authenticated` (42501, negativa legítima). 5861 v1.5-E1E e 5888 v1.1-E1E em `harness/`; gerador aponta para eles; G2_A, MGMTAPI (`1b6defd7…`), G2_B e G2_C regerados (só as seções 5861/5888 e o cabeçalho mudam); `static_check_e1e2` 3.1 ajustada e 3.3 nova (40/40). Nada executado; TXID 814967 sem `txid_status`. |
| 1.7 | **Prontidão MGMTAPI do G2_B/G2_C (2026-11-16, `G2_B/G2_C — MGMTAPI READINESS CORRECTION-01`).** 31 conferências de estado (classe B) em 5889–5893 passam ao contexto do dono (5889 v1.3-E1E, 5890–5893 v1.2-E1E); classes A e C intactas (5890 6.4/6.9, 5895 3.5, 5861 2.2, 5888 7.4). `CHANNEL_VARIANTS` gera G2_B/G2_C MGMTAPI com sentinela compacta (`failed_count`/`failed` até 8/`failed_truncated`, `x1_count`/`x1` até 2, 12 GATEs, sem textos de fixture nem horários); G2_A e G2_A MGMTAPI byte a byte iguais. `static_check_e1e2` 3.4 e 9.5 novas (42/42). Nada executado. |
| 1.8 | **G2_B LIVE — STOP 12 / SQLSTATE 55000 / S.4 (2026-11-16, `G2_B LIVE STOP 12 — S.4 ROOT CAUSE AND MINIMAL CORRECTION`).** Colisão do alias `pg_policies p` com a variável `p record` da `wh_5863_validate()` na S.4 da v1.2-E1E; correção mínima na v1.3-E1E (`p`→`pol`, critérios idênticos); G2_B/G2_C psql e MGMTAPI e manifesto regerados, G2_A byte a byte igual; v1.2-E1E e texto executado (`9566d4f4…`, em `executed/`) preservados; `scan_alias_collisions.py` e verificação 4.3 (43/43). Rollback não confirmado; trava consumida mantida; nada executado (§12). |
| 1.9 | **G2_B v2 LIVE — E2BNO / TXID 815477 e correção consolidada (2026-11-16, `CONSOLIDATED ROOT CAUSE ANALYSIS-01` e `CONSOLIDATED HARNESS CORRECTION-01`).** Resultado registrado (327/417, 321 PASS, 6 falhas, 4 X.1; trava v2 mantida; texto `ba19c2f7…` em `executed/`). Causas C1 (caminho de imagem fora do CHECK 5232) e C2 (5894 chamando a 5310 interna sob authenticated); falso positivo da 10.2. Correção só em harness: 5889 v1.4, 5890/5892/5893 v1.3, 5894 v1.4-E1E; G2_B/G2_C regerados, G2_A igual; verificações 3.5a/b/c (46/46). Nada executado (§13). |
| 1.10 | **Encerramento documental de G2_A e G2_B (2026-11-17, `G2 CLOSEOUT AND E1 DEPLOYMENT READINESS-01`, com retificação).** G2_A v2 PASS (TXID 815141, aborted) e G2_B v3 PASS (417/417, 12 GATEs, TXID 821566, aborted) consolidados com hashes e evidências; tentativas anteriores registradas; ausência de persistência de G2_B v1/v2 inferida do T6 do v3; G2_C com dispensa recomendada; ordem de aplicação provada registrada (§14). Nenhum artefato executado alterado; nada executado. |
| 1.11 | **Implantação controlada da E1 — PASS LIVE / BARRIER CLOSED (2026-11-18, `E1 DEPLOY — FINAL CLOSEOUT & CANONICAL RECONCILIATION-01`).** 24 migrations na implantação (FAIL 22 na 5388 por `*/` no comentário) e 5388 R1 + 5377 na recuperação (PASS): 26/26, 37 capacidades, barreira CLOSED; R1 e manifestos em `../e1deploy/`; base/protegida/G1_MANIFEST preservados; status atualizado (§15). |
