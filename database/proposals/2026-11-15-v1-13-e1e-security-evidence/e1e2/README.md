# V1-13 · E1-E2 — Cadeia protegida e prontidão para os ensaios G2

| Campo | Valor |
|-------|-------|
| **Rodada** | `V1-13 / E1-E2 \| PROTECTED CHAIN AND G2 TEST READINESS-01` (2026-11-15) |
| **Etapa oficial** | 6 — E1-E (em andamento). E1-E2 é subdivisão interna; as dez etapas não mudam. |
| **Status** | **PREPARAÇÃO LOCAL — NÃO EXECUTADO. G2 NÃO INICIADO.** Sem SQL (nem SELECT), sem S0, sem P1, sem migration, sem harness em banco, sem conta, sem mudança de estado da barreira, sem commit. |
| **Base** | `main` em `9c11ea0` (G1 versionado). |
| **E2-D1** | defeito de compatibilidade **detectado e corrigido localmente** em `CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02` (§2): 5380 v1.1, 5891 v1.1, `static_check_e1b3.py`, P5380 e manifestos regerados. |

## Arquivos

| Arquivo | Papel |
|---|---|
| `build_g2_chain.py` | gerador determinístico: entradas com sha256 fixado (10 migrations não protegidas + 5389 + 12 harnesses; as 16 protegidas pelo `G1_MANIFEST.json`, também fixado); recusa ausência, divergência, duplicidade, ordem fora das dependências, harness fora do modo e redefinição desprotegida de capacidade |
| `G2_A_E1A_PROTECTED_rollback.sql` | **P1-G**: 5389 + E1-A protegida; 5861 [CLOSED], 5888 [OPEN] (105 verificações) |
| `G2_B_CHAIN_STORAGE_LAST_rollback.sql` | cadeia completa, 5377 por último; 5861/5862/5864 [CLOSED], 5888–5894 [OPEN] antes da 5377; 5863 v1.2 [CLOSED], 5890 [OPEN], 5895 [CLOSED] depois (417) |
| `G2_C_CHAIN_FULL_FINAL_rollback.sql` | cadeia completa; os 12 harnesses no estado final (417) |
| `harness/5863_…_v1.2-E1E.sql` | variante **autorizada** da 5863 (só a S.4 muda, linhas marcadas `-- E1E`; original preservado) |
| `S0_G2_readonly.sql` | S0 ampliada, uma instrução SELECT |
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
| 5863 (imagens compartilhadas, 37) | S.4 | **incompatível com o contrato vigente → variante v1.2-E1E AUTORIZADA** | a S.4 original exige "9 políticas" e "toda escrita com `auth.uid()`"; a 5377 acrescenta 3 políticas do EDITOR. A variante confere **individualmente** as 12 políticas por nome, comando, papéis, caráter permissivo e predicado (7 do dono: pasta do próprio usuário por `auth.uid()`, só `authenticated`, UPDATE com as duas expressões; 2 de leitura compartilhada: `anon`+`authenticated`, decisão delegada; 3 do EDITOR: só `authenticated`, inserção pelo ajudante, leitura e exclusão só do próprio envio por `owner_id = auth.uid()` e pelo ajudante), exige **conjunto fechado** (nenhuma outra política nos dois buckets, nenhuma restritiva, nenhuma escrita para `anon`, nada para PUBLIC) e prova a dependência de identidade dos ajudantes (definer, sem EXECUTE para `anon`, `(select auth.uid())`, participação EDITOR ativa, porta `v1_13_capability_open`, pasta do próprio titular recusada). Original preservado |
| 5863 | demais (S.1–S.3, S.5, F, I, ST, C, N, PB, SO, RM) | **válido sem ajuste** | VIEWER B não é EDITOR: as políticas novas não lhe concedem nada (e a porta está fechada); objetos inseridos como dono e desfeitos |
| 5864 (logo, 7) | todos | **válido sem ajuste** | só o bucket `card-set-logo`; nenhuma política da V1-13 nele |
| 5862–5864 | resolução pelo PostgREST e pela API do Storage (H.6) | **dependente de prova dinâmica adicional** | G3/G4 |

## 5. Matriz de execução dos harnesses

| Harness | Migrations necessárias | Modo | Identidades | Efeitos | Histórico | Travas relevantes | Rollback | Exigido | Falso PASS pela barreira? |
|---|---|---|---|---|---|---|---|---|---|
| 5861 v1.4 | E1-A | CLOSED | sintéticas | fixture desfeita (sentinela) | não | O1 | aborto | 51/51 | não: não chama capacidade nova |
| 5862 | E1-A (+V1-12) | CLOSED | sintéticas | idem | eventos do titular | O1, O3 (B/C) | aborto | 33/33 | não |
| 5863 v1.2 | +5377 | CLOSED | sintéticas | objetos de Storage | não | **O2** | aborto | 37/37 | não |
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
| Prova final com 5377 (G2-B, segunda parte; G2-C) | 5863 v1.2, 5890 e 5895 no estado final (G2-C: todos) | G2-B: 5888–5894 não repetidos depois da 5377 |
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

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Preparação local (2026-11-15, `E1-E2 \| PROTECTED CHAIN AND G2 TEST READINESS-01`).** Gerador e três ensaios G2 (P1-G, cadeia com 5377 por último, cadeia completa), variante proposta 5863 v1.2-E1E, S0 ampliada, manifesto, verificação estática; bloqueio E2-D1 (md5 da 6123); 5895 v1.1 (md5 da 5368). Nada executado; G2 não iniciado. |
| 1.1 | **Correção (2026-11-15, `CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02`).** E2-D1 corrigido localmente (5380 v1.1, 5891 v1.1, static_check_e1b3, P5380, G1/G2 regerados); 5863 v1.2-E1E com conjunto fechado e prova dos ajudantes; guardas de alteração das verificações G1/E1-E2 passam a aceitar só as 4 mudanças autorizadas, com sha256 exato. Nada executado; G2 não iniciado. |
