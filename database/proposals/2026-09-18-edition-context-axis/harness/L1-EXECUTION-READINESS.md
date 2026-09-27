# 2830H — Lote L1: readiness de execução do E03T e critérios para o E03

| Campo | Valor |
|---|---|
| **Natureza** | Preparação operacional e matriz de decisão. **Nenhum SQL executado nesta rodada**, nem SELECT de preflight; nenhum acesso ao LIVE; nenhum envelope, schema, migration, função ou validação alterado. |
| **Mandato** | `BATCH12-2830-P5-L1-EXECUTION-READINESS-01`. Baseline HEAD `7bb44ca4934e9ac81a5ebdf93f795edbc198da4a`. v1.3 (registro das decisões): `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`, baseline HEAD `d9e1b10ed47319e78e9ba06dccc99c1b65b5e034`. |
| **Autoridades** | 2830 v7.0 (blob `b4647dcb…`, imutável) · `L1-E03-IMPLEMENTATION-READINESS.md` v1.2 (blob `4a93a545…`) · `PHASE5-AUTOMATED-COVERAGE-READINESS.md` (blob `1aa8d71d…`) · `LIVE-VALIDATION-PROTOCOL.md` (blob `abe806d6…`) · registros das Etapas 2 (`4ec35e78…`) e 3 (`974674f9…`) · `P9A-READINESS.md`. |
| **Estado** | **v1.3 — decisões registradas, para auditoria independente** (v1.1: fechamento fail-closed do §4.4–§5, `…-EXECUTION-READINESS-CORRECTION-01`; v1.2: ordem L3 diagnóstica → E99 → L3 final no fluxo excepcional, `…-CORRECTION-02`; v1.3: registro das decisões, `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`). **DP-1 = A′, DP-4 = B, DP-5 = A, DP-7 = A**, decididas por Fabrício e válidas **só para o E03T** (§2.5). Execução LIVE do E03T **não autorizada**: depende de mandato próprio (plano em `L1-E03T-LIVE-EXECUTION-PLAN.md`). E03 **não autorizado**. E03T **não executado**. Nenhum PASS novo: cobertura LIVE **17/135**. **FREEZE ATIVO.** |

---

## 0. Resultado

- **STOP: não houve.** Não foi encontrado blocker de segurança, integridade, semântica, concorrência, performance ou perda de dados nos artefatos publicados.
- **Execução hoje: não permitida.** As quatro decisões do §2 estão registradas desde a v1.3, só para o E03T; falta o mandato de execução próprio (§8). O plano operacional está em `L1-E03T-LIVE-EXECUTION-PLAN.md`. Nem ele nem este documento autorizam execução.
- **Três níveis de evidência** são separados em todo o texto (resumo no §7): **H** = histórica (LIVE, Etapas 1–3); **E** = estática, reproduzida nesta rodada sem banco; **R** = depende de runtime, ainda não demonstrada.

## 1. Gate A — identidade e integridade (E, reproduzido nesta rodada)

### 1.1 Repositório

- HEAD = `7bb44ca4934e9ac81a5ebdf93f795edbc198da4a` (commit "feature: implement Batch 12 L1 E03 validation harness").
- `git status --porcelain` **vazio** antes desta rodada: nenhuma alteração local, nenhum arquivo não versionado.
- `git diff --check` limpo.

### 1.2 Arquivos publicados (blob no HEAD = blob do arquivo local)

| Arquivo | Papel | blob git | md5 | sha256 | Bytes |
|---|---|---|---|---|---|
| `2830H_E00_precheck_inventory.sql` | precheck (SELECT) | `a4dd84381b928727611a51147ba1a4c1d11b89ab` | `45b6c35cca849ffbf49d22ec18e8283c` | `2a9539fb48d2d8231da59240b7c9d8fe4aa5fe6201e97335cd2a0e8ec9009a8a` | 53.803 |
| `2830H_E03P_precheck_section2.sql` | precheck do lote (SELECT) | `0fc2d83dff599fc6cc26e35399ebc519a5a51d0f` | `10457d87d4c25c93ab04d0fadf43dddc` | `3f0e540939e2528aae70fabf7c1a83aaa07421bf30a529710ea6b12c4bc68c5d` | 13.335 |
| `2830H_E03T_n1_controlled_probe.sql` | diagnóstico T1–T3 (DO, escreve) | `9523bf23f68fe78a1e126dff1f85ccc8ece5c2dc` | `34d3826e1e8b4a3d3871b87733c6538b` | `2eb3e2a46bd644dafeb2b2c8307fb1f39af9c5e2743a1ddebbd9011ae10ec1f0` | 25.029 |
| `2830H_E03_section2_profile_composition.sql` | lote L1, 13 casos (DO, escreve) | `4866eb970db18ef492cc4f362249856de1eab45e` | `2ef78e0ba4196d077dbfaae43f465c24` | `a6c17a61d5d0ae414401885c8180efcc62f744e1b150b7fedfbdf374bcd981de` | 91.852 |
| `2830H_E99_postcheck_residue.sql` | postcheck (SELECT, 3 marcadores) | `49a71ecb4525697858110ee71a3f61f5eee74a34` | `f0b91183a8649b990b080637dd56e74b` | `63f7e2e7fa2bd10fdd9bdd963e5e672d187580694bc467dabd1bc5af7165a66a` | 12.289 |
| `tools/static_check.py` | verificação local | `6b3689cc8ed959e5e78d46663d36b5ab13da27d0` | `8a5d4b611bceaa9873ff4af7b9af012d` | `d8aa016dec08b09ede7e3ec2b5b3c6982a1f7ea8fbc51efcf7cfa9b552b198de` | 92.217 |
| `L1-E03-IMPLEMENTATION-READINESS.md` | contrato de implementação v1.2 | `4a93a5450650c5a2511adb204e7881e7fd8f2f67` | `1bcf73f176bfa725bc47569ece6279f1` | `0c6087c4fa5d8f58527ca40185cf5a91758ab1d77be0134edbe7a63ccea744dd` | 60.888 |
| `../2830_validate_edition_context_foundation.sql` | contrato 2830 v7.0 | `b4647dcb59432405c8157e2733fd78678f35540e` | `7d816d18bf6376c1fc29bc91c8bee2e9` | `b2e00a89faf17eee2e969084a412249dfe15e4fc958a9897a069dba5c5c4b6d0` | 75.013 |

Consultas de canal do roteiro (`LIVE-STAGE1-RUNBOOK.md`, blocos SQL), recalculadas: **L1** md5 `0836c36a8d3749b1e7718223e064caf9` (2.458 B) e **L3** md5 `b7bc3700aeef278f6a79bd30e6a8d229` (1.526 B), iguais às usadas nas Etapas 2 e 3.

### 1.3 Textos que seriam submetidos ao banco no E03T

| Ordem | Texto | Identidade |
|---|---|---|
| S1 | L1 (canal) | md5 `0836c36a…` (bloco literal do roteiro) |
| S2, S7 | L3 (concorrência) | md5 `b7bc3700…` |
| S3 | E00 verbatim | blob `a4dd8438…` |
| S4 | E03P verbatim | blob `0fc2d83d…` |
| S5 | E03T verbatim | blob `9523bf23…` |
| S6 | E99 com os 3 marcadores do S3 | gerado de `49a71ecb…`; difere do arquivo só nas linhas dos marcadores (`__E00_D_BASELINE__`, `__E00_D_BASELINE_MD5__`, `__E00_ROLE_SETTING_ROWS__`, 1 ocorrência cada); md5 registrado antes da submissão |

### 1.4 Consistência estática (E)

`python3 tools/static_check.py`, duas execuções com saída idêntica:

| Bloco | Resultado |
|---|---|
| Baseline histórico | `TOTAL 444 PASS 444 FAIL 0` |
| Perfil E03/E03T/E03P | `E03-PERFIL TOTAL 85 PASS 85 FAIL 0` |
| Mutações inseguras | `E03-VERIFICADOR-NEG TOTAL 56 PASS 56 FAIL 0` |
| Controles positivos | `E03-VERIFICADOR-POS TOTAL 4 PASS 4 FAIL 0` |

O perfil cobre, entre outros: gabarito da sonda idêntico ao §2.6.2 da readiness v1.2; 13 casos = 2830 l. 453–477 (menos 2.6) = §3.2/§4 da readiness; IMMEDIATE por caso = matriz §2.6.5; E03P com os 11 gates do §5, pinos = md5 da 2206 = pinos do E00; E03T com 3 casos, 4 sondas, 4 IMMEDIATE e 5 DEFERRED.

Pontos de consistência conferidos à mão nesta rodada:
- a mensagem terminal esperada do E03T (§4.3) sai do próprio arquivo: `c_env = 'E03T_N1_CONTROLE'`, `c_expected = ARRAY['T1','T2','T3']`, gate `IF v_qn <> 4`, formato idêntico ao E01;
- o `RAISE … 'H283P'` do E03T está na linha 482 do arquivo e o `DO` na linha 29; o contexto esperado no canal é `PL/pgSQL function inline_code_block line 454 at RAISE` (mesma regra que conferiu o E01 na Etapa 3: 725 − 48 + 1 = 678). Para o E03: linhas 1747 e 54, contexto `line 1694`;
- o E99 detecta o marcador por `code LIKE '%H2830%'` em trait e profile: cobre as fixtures e as linhas de sonda (`v_marker ‖ '_Q' ‖ n`);
- a L3 cobre as tabelas escritas e `game` (FK).

## 2. Gate B — decisões (DP-1, DP-4, DP-5 e DP-7 decididas por Fabrício; registro na v1.3)

As matrizes abaixo são a análise que precedeu as decisões e ficam como estavam. A deliberação está no fim de cada subseção; o estado consolidado, no §2.5.

### 2.1 DP-1 — medição de tempo (P9)

**O que o contrato exige, pela letra (2830 v7.0, P9 e A2):**
- **P9(a):** `EXPLAIN (COSTS OFF)` das **consultas pesadas**, no LIVE. Não mede tempo.
- **P9(b):** tempo real medido em **ambiente isolado representativo (P14)**, 3 execuções (1 com cache frio), pior caso ≤ 60 s; "nenhum envelope vai ao LIVE sem a medição registrada".
- **A2** = auditoria estática + P9a + P9b, juntos.

**Aplicação ao lote L1 (E):**
- P9(a): **não aplicável** ao E03T e ao E03, pelo mesmo critério do `P9A-READINESS.md` para o E01: são blocos `DO` (o `EXPLAIN` não aceita `DO`) e só leem catálogo e tabelas pequenas (EC ≤ 196 linhas, `game`). O E03P é um SELECT de catálogo leve. Nenhum artefato do lote tem "consulta pesada".
- P9(b): **aplicável pela letra** e **não cumprível** hoje: o ambiente isolado pago foi recusado e D-1 (alternativa sem custo) está pendente.

**Precedente × exigência vigente (não aplicar automaticamente):**
- **H:** as Etapas 2 e 3 rodaram sob a adaptação AD-2 (tempo medido no próprio LIVE; teto 120 s pelo `statement_timeout`; aceite ≤ 60 s), **por mandato de cada etapa**. A decisão formal D-2 (aceitar AD-2 no lugar de P9b) **continua pendente** no protocolo §8. O E01 mediu `elapsed_ms = 251`.
- O precedente vale para o E01/E02. **Não se estende sozinho** ao L1.

| Alternativa | Compatível com o contrato? | Evidência disponível | Risco residual | Implicação operacional |
|---|---|---|---|---|
| **A** — estender AD-2 ao E03T e ao E03, por decisão expressa (tempo medido no LIVE; teto 120 s; aceite ≤ 60 s; E03P e E00/E99 medidos por execução) | por **adaptação** declarada; A2 continua não cumprido literalmente | H: E01 251 ms (12 casos, 11 INSERTs). E: E03T tem 3 casos, 7 INSERTs de fixture + 4 de sonda, 2 selos; E03 tem 13 casos, 54 INSERTs de fixture + 11 de sonda, 4 UPDATEs, 1 DELETE, 9 selos, 33 subtransações | sem medição prévia; se o tempo real exceder 60 s o resultado é não aceito (mas a escrita já ocorreu e foi desfeita); teto duro 120 s | E03T pode ir ao LIVE após DP-4/DP-5/DP-7; seu `elapsed_ms` é indício (não medição) para o E03 |
| **A′** — como A, só para o E03T; decidir o E03 depois de ver o `elapsed_ms` do E03T | idem | idem | idem, restrito ao E03T | exige decisão DP-1 nova antes do E03 |
| **B** — exigir P9b em ambiente isolado antes de qualquer envelope do L1 | **literal** | nenhuma: ambiente inexistente | nenhum risco LIVE; lote parado | L1 bloqueado até D-1 resolvida |
| **C** — aceitar formalmente D-2 (AD-2 no lugar de P9b) para todos os lotes leves | por adaptação, de alcance amplo | idem A | alcance maior que o do L1; seções pesadas (B, M, 5.x) continuam exigindo readiness própria (AD-2) | decisão de protocolo, não só do lote |

**Deliberação de Fabrício — DP-1: A′** (registrada na v1.3, `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`). Texto aprovado:
> Autorizar, exclusivamente para o E03T, a adaptação AD-2: medição direta de tempo no LIVE, com statement_timeout previamente comprovado de 120 segundos e aceite condicionado a elapsed_ms ≤ 60000. Essa adaptação não cumpre literalmente P9b, que exige medição prévia em ambiente isolado representativo. Não estender a decisão ao E03 nem a outros lotes.

- **Aplicação:** "previamente comprovado" = L1 da própria rodada (S1) com `statement_timeout = '2min'`, a forma que o PostgreSQL devolve para 120 s (valor observado nas Etapas 1–3). Qualquer outro valor, inclusive `0` ou maior, é STOP antes do E00; não se ajusta a sessão (DP-4). O aceite `elapsed_ms ≤ 60000` usa o valor da mensagem terminal, medido dentro do bloco.
- **Alcance:** só o E03T. D-2 do protocolo (§8) continua **pendente**; A2 e P9b continuam **não cumpridos literalmente**. O E03 exige nova DP-1 (§6, T-5); o `elapsed_ms` do E03T será só indício.

### 2.2 DP-4 — `lock_timeout` (P8 / A5)

**Contrato e protocolo:**
- 2830 P8: `SET LOCAL lock_timeout = '5s'` como primeira instrução, com asserção; A5: "uso autorizado explicitamente, ou o harness roda sem ele (decisão registrada)".
- Protocolo §2.3: nenhum `SET`/`set_config` de sessão; §5.1 item 5 e D-4: se a L1 mostrar `lock_timeout ≠ '0'`, STOP.
- **D-3/A5 (b)** foi decidida **só para o E01** ("E01 sem `SET LOCAL lock_timeout`"). Não cobre E03T nem E03.

**SQLs publicados (E):** E03T e E03 **não** contêm `SET LOCAL` (cabeçalho: "DECISÃO PENDENTE (DP-4) … NÃO emitido"); o perfil E03 do `static_check` **proíbe** `SET LOCAL` (E03-2) e só admite `SET CONSTRAINTS` nos dois selos (E03-5). O E99 exige `lock_timeout = '0'` (`g_lock_timeout_default`).

| Alternativa | Compatível? | Evidência | Risco residual | Implicação operacional |
|---|---|---|---|---|
| **A** — autorizar `SET LOCAL lock_timeout = '5s'` dentro do E03T/E03 | sim (transacional: desfeito no rollback; não persiste) | E: não existe no blob atual | exige **mandato de implementação**: novos blobs, asserção inicial, mudança nas regras E03-2/E03-5, nova auditoria. Não pode ser feito "operacionalmente" nesta fase | atrasa a execução por uma rodada de implementação |
| **B** — rodar sem `lock_timeout`, como no E01, com controles operacionais **sem SQL novo**: L3 imediatamente antes do E00 com `locks_on_scope = []`; E00 com `g_no_concurrency = true`; FREEZE; teto 120 s; `57014` = FAIL e STOP | sim (A5 "roda sem ele, decisão registrada") | H: L1 da Etapa 3 com `lock_timeout = '0'`, `statement_timeout = 2min`; L3 da Etapa 3 sem locks no escopo | uma espera por lock (improvável sob FREEZE) só termina em 120 s, com rollback integral | nenhum artefato muda; decisão registrada para E03T e E03 |
| **C** — `SET lock_timeout` de sessão via chamada separada, ou `set_config`, ou `ALTER ROLE` | **não** (protocolo §2.3; configuração persistente/ de sessão) | — | — | rejeitada |

**Deliberação de Fabrício — DP-4: B** (registrada na v1.3, `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`). Texto aprovado:
> Autorizar o E03T publicado sem SET LOCAL lock_timeout. Preservar os controles L1, L3, E00 e FREEZE, com lock_timeout = 0 e statement_timeout = 120 segundos. Nenhuma configuração persistente ou de sessão pode ser introduzida. Não presumir autorização equivalente para o E03.

- **Aplicação:** blob do E03T `9523bf23…` sem alteração; L1 com `lock_timeout = '0'` e `statement_timeout = '2min'`; L3 sem locks no escopo; E00 com `g_no_concurrency = true`; E99 com `g_lock_timeout_default = true`. Nenhum `SET`, `set_config` ou `ALTER ROLE`. D-4 continua obrigatório: `lock_timeout ≠ '0'` na L1 ⇒ STOP.
- **Alcance:** só o E03T. O E03 exige nova DP-4.
- **Texto histórico no SQL:** o cabeçalho do E03T ainda diz "P8 lock_timeout — DECISÃO PENDENTE (DP-4); NÃO emitido". O blob é imutável e não é alterado; a decisão vale por este registro, como no precedente do E01 (Etapa 3).

### 2.3 DP-5 — escritas transitórias

**Decisão necessária:** autorização expressa, por envelope, das escritas abaixo, sempre desfeitas (inventário completo no §3).

| Alternativa | Implicação |
|---|---|
| **A** — autorizar só o E03T (7 INSERTs de fixture, 4 de sonda, 2 selos) | E03T executável após DP-1/DP-4/DP-7; E03 precisa de nova autorização |
| **B** — autorizar E03T e E03 no mesmo ato, cada um em mandato próprio | reduz uma rodada de decisão; a transição do §6 continua obrigatória |
| **C** — não autorizar | nada vai ao LIVE; L1 parado |

- **Evidência:** H — a Etapa 3 escreveu no LIVE sob autorização equivalente e o E99 provou `d_diff = []`; E — o perfil estático prova que UPDATE/DELETE só atingem ids criados por `RETURNING id INTO` no próprio caso (E03-7) e que nenhum caminho do `DO` termina sem exceção (E03-12).
- **Risco residual:** §3.3.

**Deliberação de Fabrício — DP-5: A** (registrada na v1.3, `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`). Texto aprovado:
> Autorizar exclusivamente as escritas transitórias previstas no E03T publicado, sob rollback obrigatório e verificação posterior. Escopo previsto: 7 INSERTs de fixture; 4 INSERTs de sonda; 2 selos; 8 subtransações. Restringir as operações às três tabelas EC previstas no contrato. Nenhuma autorização de escrita para o E03.

- **Conferência com o §3.1 (E):** 7 INSERTs de fixture = 2 em `card_edition_context_trait` + 3 em `card_edition_context_profile` + 2 em `card_edition_context_profile_trait`; 4 INSERTs de sonda em `card_edition_context_profile`; 2 UPDATEs pelo selo da 2206 em profile de fixture; 8 subtransações (3 de caso + 4 de sonda + 1 negativo); 11 `INSERT INTO` no arquivo. Tabelas: as três acima; `game` só é lida (FK). Nenhum UPDATE ou DELETE do envelope.
- **Alcance:** só o blob `9523bf23…`, uma execução, sob mandato de execução próprio. O E03 não tem autorização de escrita.

### 2.4 DP-7 — execução do E03T

**O que o E03T é:** diagnóstico controlado, **fora dos 135 casos** da 2830. Não gera PASS de contrato, não altera a cobertura (17/135) e não substitui o E03.

**O que ele pode mostrar em runtime (R, hoje não demonstrado):**
- `SET CONSTRAINTS … IMMEDIATE/DEFERRED` funciona dentro do `DO` (N-1), inclusive quando o IMMEDIATE falha (T2);
- a sonda confirma DEFERRED e é descartada;
- o IMMEDIATE posterior a uma sonda **não é contaminado** (T3).

**Limite L-1 (readiness v1.2 §2.6.7):** o T3 comprova **ausência de contaminação observável**, **não** a remoção direta do evento diferido da sonda. Um evento remanescente encontraria o profile desfeito e o selo da 2206 (l. 70–74) retornaria sem efeito; remoção e no-op produzem o mesmo resultado. A remoção continua fundamentada só pela semântica de subtransação do PostgreSQL e pelos comentários de `trigger.c`.

| Alternativa | Implicação |
|---|---|
| **A** — autorizar o E03T antes do E03 | um mandato e uma rodada a mais; reduz a incerteza de N-1 com escrita mínima; o resultado alimenta a transição do §6 |
| **B** — dispensar o E03T e ir direto ao E03 (as 11 sondas do E03 cobrem o modo) | uma rodada a menos; a primeira execução de N-1 passa a ser o próprio lote de 13 casos, com 54 INSERTs de fixture |

- **Risco residual:** o mesmo do §3.3, em escala menor que o E03.

**Deliberação de Fabrício — DP-7: A** (registrada na v1.3, `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`). Texto aprovado:
> Aprovar a realização de E03T antes de considerar o E03. E03T é diagnóstico T1–T3, fora dos 135 casos da 2830. Não gera PASS contratual nem altera a cobertura LIVE. Preservar o limite L-1: o T3 demonstra ausência de contaminação observável, não a remoção direta do evento diferido da fila.

- **Aplicação:** a alternativa B (ir direto ao E03) fica descartada; T-1 do §6 passa a exigir o registro de execução do E03T. Aprovar a realização não é autorizar a execução: esta depende do mandato próprio (§8).

### 2.5 Estado consolidado das decisões (v1.3)

| Item | Decisão operacional | Implementação publicada | Autorização de execução | Evidência runtime |
|---|---|---|---|---|
| DP-1 — tempo | **A′ aprovada**, só E03T: AD-2 no LIVE, `statement_timeout` 120 s comprovado na L1, aceite `elapsed_ms ≤ 60000` | o E03T mede `elapsed_ms` no próprio bloco (blob `9523bf23…`) | **pendente** (mandato de execução) | **inexistente** |
| DP-4 — `lock_timeout` | **B aprovada**, só E03T: sem `SET LOCAL`; `lock_timeout = '0'`, `statement_timeout` 120 s | blob `9523bf23…` sem `SET LOCAL` (perfil E03-2 proíbe) | **pendente** | **inexistente** |
| DP-5 — escrita transitória | **A aprovada**, só E03T: 7 + 4 INSERTs, 2 selos, 8 subtransações, 3 tabelas EC | superfície do §3.1, provada estaticamente (E03-7, E03-12) | **pendente** | **inexistente** |
| DP-7 — E03T antes do E03 | **A aprovada** | E03T implementado, não executado | **pendente** | **inexistente** (N-1 não demonstrado) |
| E03 | nenhuma decisão aplicável | E03 implementado, não executado | **não autorizado** | **inexistente** |

Nenhuma decisão altera SQL, protocolo canônico, contrato 2830, critérios de PASS/FAIL ou a classificação fail-closed dos §4.4–§5. Nenhuma se estende ao E03 ou a outros lotes.

## 3. Superfície de escrita — E03T × E03 (E, contado dos arquivos)

### 3.1 Operações por tabela

| Tabela | Operação | E03T | E03 | Filtro / origem da linha | Triggers alcançados |
|---|---|---|---|---|---|
| `card_edition_context_trait` | INSERT | 2 | 19 (1 inativo, 2.5) | fixture: `code` e `name` com marcador; família `EVENT`; `display_order` = máx. da família + 1000 + k | nenhum trigger; FK para `game` |
| `card_edition_context_profile` | INSERT de fixture | 3 (1 desfeito no negativo T2) | 15 (2 desfeitos em negativos: 2.2 P, 2.7 Pb) | `code = v_marker ‖ …`; `display_order` = máx. do Game + 1000 + k | `trg_cecp_seal` (AFTER INSERT, DEFERRED) enfileira evento |
| `card_edition_context_profile` | INSERT de sonda | 4 | 11 | `v_marker ‖ '_Q' ‖ n`; ordem base + 1090; sempre desfeito por `H283S` | idem (evento desfeito com a sonda) |
| `card_edition_context_profile` | UPDATE pelo selo (função da 2206) | 2 | 9 (+2 tentativas que falham: 2.2, 2.7) | `WHERE id = NEW.id` do próprio evento | `trg_cecp_signature_write` (BEFORE UPDATE OF `traits_signature`) |
| `card_edition_context_profile` | UPDATE do envelope | 0 | 4 (3 negativos esperados em 2.11–2.13; 1 aceito em 2.14, `name`) | `WHERE id = v_p AND code = v_code_p` | `trg_cecp_signature_write` só em 2.11–2.13 |
| `card_edition_context_profile_trait` | INSERT | 2 | 20 (3 rejeições esperadas: 2.3, 2.5, 2.10; 2 aceitas e depois desfeitas no negativo de 2.7) | `(v_p…, v_t…, v_game)` | `trg_cecpt_immutable`, `trg_cecpt_trait_active` (BEFORE); FKs compostas |
| `card_edition_context_profile_trait` | DELETE | 0 | 1 (negativo esperado, 2.4) | `WHERE profile_id = v_p AND trait_id = v_t1` | `trg_cecpt_immutable` |
| `game` | leitura + `FOR KEY SHARE` implícito pela FK | sim | sim | `code = 'POKEMON'` (preflight = 1) | — |

- Nenhuma outra tabela é escrita (E03-7). `card_edition_context_external_mapping` só aparece no `SET CONSTRAINTS` (nome de `trg_cecem_seal`), sem evento.
- Subtransações: E03T = 3 de caso + 4 de sonda + 1 negativo = 8; E03 = 13 de caso + 11 de sonda + 9 negativos = 33. Todas terminam em exceção.
- `SET CONSTRAINTS`: E03T 4 IMMEDIATE / 5 DEFERRED; E03 11 / 13. Nenhum outro `SET`.

### 3.2 Eventos diferidos

- Única constraint `DEFERRABLE` nas 3 tabelas: `trg_cecp_seal` (E03P `g_deferrable_only_seal`). FKs são `NOT DEFERRABLE`.
- Cada INSERT de profile enfileira um evento; os IMMEDIATE processam exatamente os eventos da matriz da readiness v1.2 §2.6.4–§2.6.5 (**E** para o estado esperado; **R** para a observação).
- Eventos de 2.5, 2.8 e 2.11 (sem IMMEDIATE) e de sondas saem com a subtransação respectiva.

### 3.3 Riscos residuais

| Tema | Risco | Controle | Evidência |
|---|---|---|---|
| Locks | `RowExclusiveLock` nas 3 tabelas; locks de linha só nas fixtures; `FOR KEY SHARE` na linha POKEMON de `game`; entradas em índices únicos | FREEZE; L3 antes (sem locks no escopo) e depois; E00 `g_no_concurrency`; teto 120 s (DP-4) | H: Etapa 3 sem espera; R para o L1 |
| Concorrência | escritor concorrente das mesmas chaves (proibido sob FREEZE) colidiria em índice único e o caso falharia (FAIL, nunca PASS) | idem; chaves com marcador único por execução | E |
| Triggers | só os 4 da 2206, identidade por pino md5 no E00 e no E03P; nenhum evento DDL (nenhum DDL nos envelopes) | E00 P7 + D-9; E03P `g_s2_triggers`, `g_no_other_triggers_l1`, `g_s2_function_pins` | H (E00 Etapa 3); E |
| Rollback | um caminho que termine sem exceção deixaria resíduo | nenhum caminho do `DO` termina normalmente (E03-12); retorno `[]` = defeito grave | E; R |
| WAL e tuplas mortas | WAL das escritas abortadas; tuplas mortas até o autovacuum; contadores `pg_stat_*`; consumo de XIDs de subtransação (dezenas) | resíduo não-transacional declarado (protocolo §5.3); nenhum dado de negócio | declarado, não medido |
| Logs | statements e marcador nos logs do servidor | idem | declarado |
| Sequences | nenhuma (ids UUID) | E00 `g_no_sequences_touched_now` (trait, profile); E03P `g_nn_no_sequence` (N:N) | H + R |
| RLS | dono = `postgres` = `current_user`, sem FORCE | E00 `g_rls_bypass`; E03P `g_nn_rls_bypass` | H (L1 Etapa 3: `current_user = postgres`, `is_superuser = false`, donos `postgres`) |
| Canal | truncamento, SQLSTATE não exposto, queda | §4.5 | H: o canal expôs `H283P` e a mensagem integral na Etapa 3 |

### 3.4 Como verificar que nada persistiu

Três fontes independentes, todas obrigatórias (protocolo §5.3, readiness v1.2 §7):
1. **Mensagem terminal** com o marcador da execução (`H283P` ou `H283F`): prova que o `DO` terminou em exceção.
2. **E99 da mesma rodada:** `d_baseline` inteiro igual ao do E00 (inclui contagens de trait, profile, profile_trait, mapping), `d_diff = []`, `d_canon_diff = []`, `g_marker_absent = true` (marcador ausente em `trait.code`, `profile.code`, `mapping.normalized_token`), `g_lock_timeout_default = true`.
3. **L3 final:** nenhum lock no escopo e nenhuma sessão ativa ou em transação.

Ausência de erro **não** é prova de rollback, e `H283P` sozinho não é aceite.

## 4. Gate C — protocolo operacional do E03T (não executar)

### 4.1 Pré-condições do mandato de execução

1. DP-1, DP-4, DP-5 (para o E03T) e DP-7 decididas por Fabrício e registradas — **cumprida na v1.3** (§2.5).
2. Mandato de execução próprio, com baseline HEAD declarado.
3. Canal: MCP Supabase `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`; uma chamada = um statement; nunca Dashboard; nunca `apply_migration`.
4. Nenhum `SET` de sessão, nenhuma sonda experimental, nenhum retry automático.

### 4.2 Sequência

| Passo | Chamada | Pré-condição | Critério de continuidade | Saída integral a preservar |
|---|---|---|---|---|
| S0 | verificação local | mandato vigente | HEAD = baseline do mandato; `git status` limpo; blobs do §1.2 conferidos por `git hash-object`; `static_check` 444 + 85 + 56 + 4 PASS | saída de `git` e do `static_check` |
| S1 | **L1** (md5 `0836c36a…`) | S0 conforme | `transaction_read_only = off`; `default_transaction_read_only = off`; `in_recovery = false`; `lock_timeout = '0'` (D-4); `statement_timeout = '2min'` (DP-1/DP-4, v1.3); `server_version_num ≥ 170000`; donos EC = `current_user`; visibilidade de sessões provada (`reads_all_stats` ou equivalente, AD-9) | JSON integral |
| S2 | **L3** (md5 `b7bc3700…`) | S1 conforme | `locks_on_scope = []`; nenhuma sessão `active` ou `idle in transaction` além da própria | JSON integral |
| S3 | **E00** verbatim (`a4dd8438…`) | S2 conforme | `gate_pass = true` (24 gates), incluindo `g_no_residue`, `g_no_sequences_touched_now`, `g_rls_bypass`, `g_no_concurrency`, `g_freeze_canonical_equal`; `d_canon_diff = []` | JSON integral; `d_baseline`, `d_baseline_md5`, `db_role_setting_rows`, `checked_at` |
| S4 | **E03P** verbatim (`0fc2d83d…`) | S3 conforme | `gate_pass = true` (11 gates + `gate_pass`) | JSON integral; `d_session.checked_at` |
| S5 | **E03T** verbatim (`9523bf23…`), uma chamada, logo após S4 | S4 conforme | resposta conforme §4.3 | resposta integral do canal (erro com SQLSTATE e mensagem) |
| S6 | **E99** com os 3 marcadores do S3 | após S5 com resposta definida (qualquer SQLSTATE); após resposta ambígua do E03T, **só** depois que a L3 diagnóstica (§4.4) confirmar o encerramento do backend | §4.4 | texto submetido (md5) e JSON integral |
| S7 | **L3 final** | **sempre depois** do S6; nunca substituída pela L3 diagnóstica | nenhum lock no escopo; nenhuma sessão ativa ou em transação; nenhum pid desta rodada | JSON integral |

### 4.3 Resposta esperada do E03T

- **Conforme:** erro com SQLSTATE `H283P` e mensagem exatamente `H2830_ROLLBACK_PASS: envelope=E03T_N1_CONTROLE pass=3/3 casos=T1,T2,T3 marker=H2830_<32 hex maiúsculos> elapsed_ms=<N>`, não truncada; contexto esperado `PL/pgSQL function inline_code_block line 454 at RAISE`; `elapsed_ms` dentro do limite fixado em DP-1.
- **Falha:** SQLSTATE `H283F` e `H2830_FAIL: envelope=E03T_N1_CONTROLE caso=<T1|T2|T3|PREFLIGHT|GATE> <detalhe>`. Mensagem com "sonda" = falha do padrão N-1/sonda.
- **Qualquer outro SQLSTATE** (`P0001` escapando, `23505`, `57014`, `55P03`, `25006`, erro de sintaxe `42601`, etc.) = falha.

### 4.4 Vínculo, baseline e postcheck

- **Ordem temporal exigida:** `checked_at(L1) < checked_at(L3) < checked_at(E00) < checked_at(E03P) < S5 [< checked_at(L3-D)…] < checked_at(E99) < checked_at(L3 final)`, sem nenhuma outra chamada SQL entre o E00 e o E99 além do E03P, do E03T e, só no fluxo excepcional, da L3 diagnóstica. O canal não devolve horário para erro: a posição do S5 é dada pela sequência registrada.
- **Três consultas distintas (v1.2).** Não se confundem nem se substituem:

| Consulta | Quando | Texto | Para que serve | O que **não** demonstra |
|---|---|---|---|---|
| **L3 diagnóstica (L3-D)** | só depois de resposta ambígua do E03T (timeout do cliente, perda de conexão, HTTP sem corpo ou erro do canal sem texto do PostgreSQL), **antes** de qualquer E99 | a mesma L3 (md5 `b7bc3700…`), só leitura | verificar se o backend do E03T ainda está ativo ou em transação | resíduo zero; não é postcheck; não substitui o S7 |
| **S6 — E99** | após resposta definida do E03T; ou, no fluxo excepcional, só com evidência suficiente de encerramento dada pela L3-D | E99 com os 3 marcadores | postcheck de dados | estado de sessões e locks depois dele |
| **S7 — L3 final** | **obrigatoriamente depois** do S6 | a mesma L3 | verificação conclusiva de sessões e locks | — |

- **Evidência suficiente de encerramento (L3-D):** resposta completa, `locks_on_scope = []` e nenhuma sessão de cliente `active`, `idle in transaction` ou com `xact_start`/`backend_xid` além da própria consulta. Como o canal não devolve o pid do E03T, qualquer sessão ativa ou em transação, ou qualquer lock no escopo, impede confirmar o encerramento.
- **Sem confirmação:** se a L3-D mostrar sessão ativa ou em transação, lock no escopo, ou voltar incompleta, a L3-D só pode ser repetida, só leitura, para aguardar o fim do backend (protocolo §5.4), **sem** `pg_terminate_backend` e sem nenhum outro SQL entre elas. Se o encerramento não for confirmado, **não** se submete o E99 nem o S7: a rodada é **INCONCLUSIVA**, com resíduo **não verificado**, e há **STOP**.
- **E99:** gerado por script a partir da saída **desta** rodada: substituição dos 3 literais (exatamente uma ocorrência cada, sem apóstrofo nos valores); md5 do JSON capturado recalculado localmente igual a `d_baseline_md5`; md5 do texto final registrado antes da submissão.
- **Aceite do postcheck:** `gate_pass = true` (9 gates), `d_diff = []`, `d_canon_diff = []`, `g_marker_absent = true`, `g_captured_integrity = true`, `g_lock_timeout_default = true`, `g_role_setting_unchanged = true`, e `d_baseline_now_md5 = d_baseline_md5` do E00.
- **Classificação do postcheck (fail-closed, v1.1).** Vale para o par E99 (S6) + L3 final (S7), e só pelo que a resposta efetivamente mostrar. A L3-D não entra nessa classificação:

| Estado | Condição | Pode-se afirmar resíduo zero? |
|---|---|---|
| **ÍNTEGRO** | E99 com resposta completa e todos os critérios do item anterior; **e** L3 final completa, sem lock no escopo, sem sessão ativa ou em transação e sem pid desta rodada | **sim**, e só neste estado |
| **REPROVADO** | E99 com resposta completa e algum gate `false`, ou L3 final completa com sessão ou lock inesperado | **não** |
| **NÃO CONCLUÍDO** | E99 ou L3 final não submetido (inclusive por falta de confirmação de encerramento na L3-D), com erro SQL, retorno vazio, JSON incompleto ou truncado, timeout, perda de conexão, gate `NULL`, ou integridade dos marcadores capturados não provada | **não**: o resíduo fica **não verificado** |

- **Regra geral:** se o postcheck não for ÍNTEGRO, a rodada **não** é CONFORME, qualquer que tenha sido a resposta do E03T, e nenhum documento pode registrar "zero resíduo" ou "rollback provado" para ela.
- **Sem retry automático do postcheck.** Um E99 ou uma L3 que falhe não é reenviado na mesma rodada. Um postcheck novo, só leitura, exige mandato próprio e usa o mesmo `d_baseline` capturado no S3 (nunca um E00 novo como referência de comparação).

### 4.5 STOP / CONTINUE

| Evento | Classificação | Ação |
|---|---|---|
| S0 divergente | — | não conectar |
| L1 fora dos critérios (read-only, `lock_timeout ≠ '0'`, `statement_timeout ≠ '2min'`, visibilidade não provada, réplica) | STOP | não submeter o E00 |
| L3 com lock no escopo ou sessão em transação | STOP | não submeter o E00 |
| E00 com qualquer gate falso ou NULL | STOP | não submeter o E03P; única repetição admitida só pelo protocolo §3.4 (`g_no_concurrency`), com L3 e E00 novos |
| E03P com gate falso ou NULL | STOP | não submeter o E03T; E99 **não** é necessário (nada foi escrito), mas é recomendado para o registro |
| `H283P` conforme | CONTINUE | S6 e S7; aceite só com §4.4 e L3 final |
| `H283F` | NÃO CONFORME | E99 imediato; L3; STOP; sem retry |
| outro SQLSTATE, `57014`, `55P03`, `25006` | NÃO CONFORME | E99 imediato; L3; STOP |
| retorno `[]` (sem erro) | NÃO CONFORME (**defeito grave**) | E99 imediato; L3; STOP; se houver resíduo, INCIDENTE |
| mensagem truncada, SQLSTATE ausente ou `pass ≠ 3/3` | INCONCLUSIVO | E99 imediato; STOP; nunca conforme |
| timeout do cliente ou queda de conexão | INCONCLUSIVO | **não reenviar**; **L3-D** (§4.4); com encerramento confirmado: S6 (E99) e depois S7 (L3 final); sem confirmação: nem E99 nem S7, resíduo não verificado; STOP em qualquer caso |
| resposta ambígua (HTTP sem corpo, erro do canal sem texto do PostgreSQL) | INCONCLUSIVO | como queda de conexão: L3-D antes de qualquer E99 |
| E99 com `d_diff ≠ []` ou marcador presente | **INCIDENTE** | não apagar, não repetir; registrar marcador, linhas por marcador nas tabelas EC e `d_diff`; limpeza só com mandato explícito e SQL pareado |
| `elapsed_ms` acima do limite de DP-1 | NÃO CONFORME (não aceito) | registrar; investigar; não repetir |
| **(1)** E99 completo com `gate_pass = false`, mesmo com `d_diff = []` e marcador ausente | postcheck REPROVADO ⇒ **NÃO CONFORME**; **INCIDENTE** se o gate reprovado for de dado (`g_baseline_equal`, `g_keys_identical`, `g_freeze_canonical_equal`, `g_marker_absent`) | registrar o gate e o detalhe integral; L3; STOP; não afirmar resíduo zero; `g_lock_timeout_default` ou `g_role_setting_unchanged` falso = alteração de sessão ou papel, investigada como NÃO CONFORME |
| **(1)** E99 com `gate_pass = NULL` ou algum gate `NULL` | postcheck NÃO CONCLUÍDO ⇒ **INCONCLUSIVO** (ou INCIDENTE, se outro gate completo já mostrar dado divergente ou marcador presente) | registrar; L3; STOP; resíduo não verificado |
| **(2)** E99 com erro SQL, retorno vazio, JSON incompleto ou truncado, ou timeout | postcheck NÃO CONCLUÍDO ⇒ **INCONCLUSIVO** | **não reenviar** o E99 nesta rodada; L3 só leitura; STOP; resíduo não verificado; novo postcheck só por mandato |
| **(3)** divergência na integridade dos marcadores antes de submeter (valor com apóstrofo, ocorrência ≠ 1, md5 do JSON capturado ≠ `d_baseline_md5`) | postcheck NÃO CONCLUÍDO ⇒ **INCONCLUSIVO** | **não submeter** esse texto; regenerar só a partir da mesma saída do S3 e só se a causa for do script local; se persistir, STOP; nunca editar o JSON à mão |
| **(3)** E99 com `g_captured_present` ou `g_captured_integrity` falso | postcheck NÃO CONCLUÍDO ⇒ **INCONCLUSIVO**: `d_diff` e `g_baseline_equal` deixam de valer como prova | se `g_marker_absent = false`, **INCIDENTE** (o marcador não depende da captura); senão STOP, resíduo não verificado |
| **(4)** L3 final com erro, retorno vazio ou incompleto | postcheck NÃO CONCLUÍDO ⇒ **INCONCLUSIVO** | não reenviar automaticamente; STOP; estado de sessões e locks não verificado |
| **(4)** S7 (L3 final, já depois do E99) com sessão ativa ou em transação, ou lock no escopo, que possa ser do E03T | postcheck NÃO CONCLUÍDO ⇒ **INCONCLUSIVO**: o E99 pode ter lido antes do fim da transação e não prova resíduo zero | não repetir o S7 nem o E99; **sem** `pg_terminate_backend`; STOP; resíduo não verificado; escalar |
| **(4)** L3 final com sessão ou lock inesperado de outro pid no escopo | postcheck REPROVADO ⇒ **INCIDENTE operacional** (premissa de FREEZE/isolamento violada); o E03T fica no máximo INCONCLUSIVO | registrar integralmente; STOP; não repetir |
| **(5)** timeout ou perda de conexão do E03T **e** verificação impossível (a L3-D não confirma o encerramento do backend, ou o E99 ou o S7 não rodam ou não concluem) | **INCONCLUSIVO**, com resíduo **não verificado** | **não reenviar** o E03T; nenhuma limpeza; registrar tudo o que houver; STOP; escalar a Fabrício; um postcheck só leitura posterior exige mandato próprio |

**Classificação final da rodada (v1.1):** vale a mais grave aplicável, nesta ordem: **INCIDENTE** (há evidência de dado divergente, marcador presente ou violação do FREEZE) > **NÃO CONFORME** (evidência completa de falha sem resíduo) > **INCONCLUSIVO** (evidência insuficiente para concluir) > **CONFORME**. Qualquer resultado diferente de CONFORME encerra a rodada, impede reenvio do E03T e impede qualquer transição ao E03 (§6). Limpeza, em qualquer caso, só com mandato próprio e SQL pareado.

## 5. Critérios de aceite do E03T e limites da prova

- **Resultado possível:** `CONFORME`, `NÃO CONFORME`, `INCONCLUSIVO` ou `INCIDENTE` (diagnóstico), classificado pela regra do fim do §4.5. **Nunca** "PASS" de contrato; nenhum caso da 2830 muda de estado.
- **CONFORME exige todos:** §4.3 conforme; postcheck **ÍNTEGRO** (§4.4), o que inclui E99 completo e L3 final completa e limpa; `elapsed_ms` dentro de DP-1; ordem temporal registrada. Faltando qualquer um, a rodada não é CONFORME, mesmo com `H283P` conforme.
- **Resíduo zero** só é afirmado com postcheck ÍNTEGRO (S6 + S7). Com postcheck REPROVADO ou NÃO CONCLUÍDO o registro diz "resíduo não verificado" ou descreve o resíduo encontrado. A L3 diagnóstica nunca sustenta essa afirmação e nunca substitui o S7.
- **Fluxo excepcional** (resposta ambígua do E03T): a rodada é no máximo INCONCLUSIVA; se a L3-D não confirmar o encerramento do backend, não há E99 nem S7, o resíduo fica não verificado e há STOP.
- **Nenhum resultado do E03T autoriza o E03.** CONFORME é só a condição T-2 do §6; os demais resultados bloqueiam a transição até análise e mandato de correção.
- **O que um CONFORME demonstra (R):** `SET CONSTRAINTS` dentro do `DO` funciona no LIVE 17.6, inclusive com IMMEDIATE que falha capturado; a sonda confirma DEFERRED e é descartada; o IMMEDIATE posterior não é contaminado; o rollback deixou o estado igual ao baseline.
- **O que não demonstra:** a remoção do evento da sonda da fila (limite L-1); o comportamento dos 13 casos do E03 (caminhos, tokens e constraints do E03 não são exercidos no E03T, exceto `EMPTY_COMPOSITION`); tempo do E03; concorrência com escritor real.

## 6. Gate D — transição E03T → E03

O resultado do E03T **não** autoriza o E03. O E03 só pode ser considerado em mandato posterior, com todos os itens abaixo.

| # | Condição | Evidência exigida | Se não cumprida |
|---|---|---|---|
| T-1 | DP-7 decidida; se aprovada, E03T executado sob mandato | registro de execução do E03T | E03 só com DP-7 = dispensar (alternativa B) |
| T-2 | E03T `CONFORME` (§5) | mensagem terminal, E03P, E99 e L3 integrais | `NÃO CONFORME`/`INCONCLUSIVO` ⇒ análise e mandato de correção antes de qualquer E03 |
| T-3 | postcheck íntegro | E99 com `d_diff = []`, marcador ausente, `d_baseline_now_md5` igual | incidente; E03 bloqueado |
| T-4 | anomalias analisadas de forma independente | parecer da auditoria sobre o registro do E03T (inclui `elapsed_ms` e qualquer desvio de contexto ou canal) | E03 bloqueado |
| T-5 | decisões aplicáveis ao E03 | DP-1 para o E03 (o `elapsed_ms` do E03T é só indício); DP-4 para o E03; DP-5 para o E03. As decisões da v1.3 valem só para o E03T | E03 bloqueado |
| T-6 | autorização expressa de Fabrício | mandato de execução do E03, com baseline e blobs | E03 não roda |

A sequência do E03 é a da readiness v1.2 §7 (S0 → L1 → L3 → E00 → E03P → E03 → E99 → L3), com aceite `H283P` `pass=13/13` e as mesmas regras de §4.4–§4.5.

## 7. Evidência: histórica, estática e dependente de runtime

| Afirmação | H (LIVE, Etapas 1–3) | E (esta rodada) | R (pendente) |
|---|---|---|---|
| Canal gravável, `lock_timeout = '0'`, `statement_timeout = 2min`, PG 17.6 | sim (L1 Etapa 3) | — | reconfirmar na L1 de cada rodada |
| Canal expõe SQLSTATE custom e mensagem integral | sim (`H283P` do E01) | — | reconfirmar |
| Pinos das 4 funções da 2206 = LIVE | sim (E00 Etapa 3) | pinos = md5 da 2206 | E00 e E03P de cada rodada |
| Identidade e integridade dos artefatos | — | sim (§1) | S0 |
| 13 casos = 2830 = readiness | — | sim | — |
| Superfície de escrita e isolamento das fixtures | — | sim (§3) | execução |
| `SET CONSTRAINTS` no `DO` (N-1) | — | só fundamentação | **E03T** |
| Sonda confirma DEFERRED e é descartada | — | estrutura | **E03T** |
| IMMEDIATE posterior não contaminado | — | estrutura | **E03T T3** |
| Remoção do evento da sonda | — | só fundamentação (`trigger.c`) | **não demonstrável por SQL** (L-1) |
| Rollback integral e zero resíduo | sim para E01 | estrutura | E99 de cada rodada |
| Tempo | E01 251 ms | contagem de operações | `elapsed_ms` de cada envelope (DP-1) |

## 8. Pendências que impedem a execução segura

1. **DP-1** — decidida para o E03T (A′, v1.3); pendente para o E03.
2. **DP-4** — decidida para o E03T (B, v1.3); pendente para o E03.
3. **DP-5** — decidida para o E03T (A, v1.3); nenhuma autorização de escrita para o E03.
4. **DP-7** — decidida (A, v1.3).
5. **Mandato de execução** próprio do E03T — **pendente**; o plano `L1-E03T-LIVE-EXECUTION-PLAN.md` termina no gate "AGUARDANDO AUTORIZAÇÃO DE FABRÍCIO PARA EXECUÇÃO LIVE". O E03 exige mandato separado e as condições do §6.
6. Não há pendência técnica nos artefatos: nenhum blocker encontrado.

## 9. Limites desta rodada

- Nenhum SQL, nenhum acesso ao LIVE, nenhum envelope alterado; nada executado.
- As contagens do §3 vêm da leitura estática dos arquivos; o número real de linhas afetadas só é observável em execução.
- Nenhum PASS declarado. Cobertura LIVE **17/135**. FREEZE ATIVO.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L1-EXECUTION-READINESS-01`, baseline `7bb44ca4`), documental, sem SQL e sem LIVE.**<br>• Gate A: HEAD e blobs dos artefatos publicados conferidos; árvore limpa; `static_check` 444 + 85 + 56 + 4; textos a submeter com hashes completos;<br>• Gate B: matriz DP-1/DP-4/DP-5/DP-7 com alternativas, evidência, risco e campo de deliberação em branco;<br>• inventário de superfície de escrita E03T × E03;<br>• Gate C: protocolo S0–S7 do E03T, resposta esperada, vínculo E00 → E03T → E99, STOP/CONTINUE;<br>• critérios e limites do E03T (inclui L-1);<br>• Gate D: transição E03T → E03 em 6 condições.<br>Nenhuma decisão tomada. Sem STOP. FREEZE ATIVO. |
| 1.1 | **Fechamento fail-closed do protocolo (2026-09-27, `BATCH12-2830-P5-L1-EXECUTION-READINESS-CORRECTION-01`, baseline `7bb44ca4`), documental, sem SQL e sem LIVE.**<br>• §4.4: postcheck classificado em ÍNTEGRO, REPROVADO ou NÃO CONCLUÍDO; resíduo zero só com ÍNTEGRO; sem retry automático do postcheck;<br>• §4.5: tratamento explícito de E99 com `gate_pass` falso ou NULL, E99 com erro, vazio, truncado ou timeout, divergência na integridade dos marcadores, L3 final com falha, retorno incompleto, sessão ou lock inesperado, e verificação impossível após timeout ou perda de conexão do E03T; regra de classificação final INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME;<br>• §5: CONFORME exige postcheck ÍNTEGRO; nenhum resultado autoriza o E03.<br>Regras de não reenviar o E03T e de não limpar sem mandato preservadas. DP-1/4/5/7 inalteradas e não decididas. FREEZE ATIVO. |
| 1.2 | **Ordem do fluxo excepcional (2026-09-27, `BATCH12-2830-P5-L1-EXECUTION-READINESS-CORRECTION-02`, baseline `7bb44ca4`), documental, sem SQL e sem LIVE.**<br>• §4.4: três consultas distintas — L3 diagnóstica (L3-D, só após resposta ambígua do E03T, antes de qualquer E99), S6/E99 (só com encerramento confirmado) e S7/L3 final (sempre depois do E99); critério de encerramento suficiente; sem confirmação: nem E99 nem S7, INCONCLUSIVO, resíduo não verificado, STOP;<br>• §4.2: S6 sem o "sempre"; S7 nunca substituído pela L3-D;<br>• §4.5: linhas de timeout, resposta ambígua, (4) e (5) reordenadas;<br>• §5: L3-D não sustenta resíduo zero nem substitui o S7.<br>Nenhuma classe nova; critérios de ÍNTEGRO/REPROVADO/NÃO CONCLUÍDO e de classificação final inalterados. Proibições de reenvio do E03T, de repetir postcheck malsucedido e de limpeza sem mandato preservadas. DP-1/4/5/7 inalteradas. FREEZE ATIVO. |
| 1.3 | **Registro das decisões DP-1, DP-4, DP-5 e DP-7 (2026-09-27, `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`, baseline `d9e1b10e`), documental, sem SQL e sem LIVE.**<br>• §2: deliberações de Fabrício registradas literalmente — DP-1 = A′, DP-4 = B, DP-5 = A, DP-7 = A — todas restritas ao E03T; novo §2.5 separa decisão aprovada, implementação publicada, autorização de execução (pendente) e evidência runtime (inexistente);<br>• §4.2 S1 e §4.5: `statement_timeout = '2min'` passa a ser gate da L1, por DP-1/DP-4;<br>• §0, §4.1, §6 T-5 e §8 atualizados para o estado decidido;<br>• plano operacional em documento separado, `L1-E03T-LIVE-EXECUTION-PLAN.md`.<br>Matrizes de análise, histórico das versões anteriores, critérios de PASS/FAIL e classificação fail-closed inalterados. SQL, protocolo e 2830 inalterados. E03 não autorizado; E03T não executado; 17/135. FREEZE ATIVO. |
