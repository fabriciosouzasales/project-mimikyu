# 2830H — Lote L1: readiness de execução LIVE do E03 (Seção 2, 13 casos)

| Campo | Valor |
|---|---|
| **Natureza** | Adjudicação técnica e operacional do E03, documental e local. **Nenhum SQL executado** nesta rodada, nem SELECT; nenhum acesso ao LIVE; nenhum envelope, protocolo, readiness anterior ou contrato alterado. |
| **Mandato** | `BATCH12-2830-P5-L1-E03-EXECUTION-READINESS-01`. Baseline HEAD `a83f539e6ca36a1c0d8fc8947b4f3ddd586a22bc`. |
| **Autoridades** | 2830 v7.0 (blob `b4647dcb…`, imutável) · `L1-EXECUTION-READINESS.md` v1.3 (blob `76cca828…`) · `L1-E03-IMPLEMENTATION-READINESS.md` v1.2 (blob `4a93a545…`) · `LIVE-VALIDATION-PROTOCOL.md` (blob `abe806d6…`) · `LIVE-STAGE1-RUNBOOK.md` (blob `9f454a96…`) · `LIVE-L1-E03T-EXECUTION-RECORD.md` v1.1 (blob `eaffdb27…`). Em divergência, prevalecem estas autoridades; este documento não cria critério de PASS/FAIL nem classe de resultado. |
| **Estado** | **PROPOSTA v1.0 — para auditoria independente.** E03T CONFORME (diagnóstico), auditado e publicado. **E03 implementado, não executado e não autorizado.** DP-1, DP-4 e DP-5 **para o E03** não decididas (campos em branco no §4). Cobertura LIVE **17/135**. **FREEZE ATIVO.** |

---

## 0. Resultado

- **STOP: não houve.** Nenhuma divergência material de segurança, integridade, semântica, performance ou concorrência foi encontrada nos artefatos publicados.
- **Execução do E03: não permitida.** Faltam as decisões DP-1, DP-4 e DP-5 específicas do E03 (T-5) e um mandato de execução próprio (T-6).
- Evidência classificada como no resto do harness: **H** = histórica (LIVE); **E** = estática, reproduzida nesta rodada; **R** = depende de runtime, ainda não demonstrada para o E03.

## 1. Gate inicial — identidade e rastreabilidade (E)

- HEAD = `a83f539e6ca36a1c0d8fc8947b4f3ddd586a22bc` ("docs: close out audited E03T live diagnostic execution"); `git status --porcelain --untracked-files=all` vazio e índice vazio antes desta rodada.
- `git ls-files -s harness/LIVE-L1-E03T-EXECUTION-RECORD.md` → **`100644 eaffdb279006bc9751f1a42bb1cd92ab2c6a7d09`**: modo 100644 e blob esperado. Registro do E03T publicado.
- Todos os blobs abaixo são iguais no HEAD e na árvore:

| Arquivo | Papel | blob | md5 | sha256 | Bytes |
|---|---|---|---|---|---|
| `../2830_validate_edition_context_foundation.sql` | contrato v7.0 | `b4647dcb59432405c8157e2733fd78678f35540e` | `7d816d18bf6376c1fc29bc91c8bee2e9` | `b2e00a89faf17eee2e969084a412249dfe15e4fc958a9897a069dba5c5c4b6d0` | 75.013 |
| `2830H_E00_precheck_inventory.sql` | precheck | `a4dd84381b928727611a51147ba1a4c1d11b89ab` | `45b6c35cca849ffbf49d22ec18e8283c` | `2a9539fb48d2d8231da59240b7c9d8fe4aa5fe6201e97335cd2a0e8ec9009a8a` | 53.803 |
| `2830H_E03P_precheck_section2.sql` | precheck do lote | `0fc2d83dff599fc6cc26e35399ebc519a5a51d0f` | `10457d87d4c25c93ab04d0fadf43dddc` | `3f0e540939e2528aae70fabf7c1a83aaa07421bf30a529710ea6b12c4bc68c5d` | 13.335 |
| `2830H_E03T_n1_controlled_probe.sql` | diagnóstico (executado) | `9523bf23f68fe78a1e126dff1f85ccc8ece5c2dc` | `34d3826e1e8b4a3d3871b87733c6538b` | `2eb3e2a46bd644dafeb2b2c8307fb1f39af9c5e2743a1ddebbd9011ae10ec1f0` | 25.029 |
| **`2830H_E03_section2_profile_composition.sql`** | **lote L1, 13 casos** | **`4866eb970db18ef492cc4f362249856de1eab45e`** | **`2ef78e0ba4196d077dbfaae43f465c24`** | **`a6c17a61d5d0ae414401885c8180efcc62f744e1b150b7fedfbdf374bcd981de`** | **91.852** |
| `2830H_E99_postcheck_residue.sql` | postcheck | `49a71ecb4525697858110ee71a3f61f5eee74a34` | `f0b91183a8649b990b080637dd56e74b` | `63f7e2e7fa2bd10fdd9bdd963e5e672d187580694bc467dabd1bc5af7165a66a` | 12.289 |
| `tools/static_check.py` | verificação local | `6b3689cc8ed959e5e78d46663d36b5ab13da27d0` | `8a5d4b611bceaa9873ff4af7b9af012d` | `d8aa016dec08b09ede7e3ec2b5b3c6982a1f7ea8fbc51efcf7cfa9b552b198de` | 92.217 |
| `LIVE-VALIDATION-PROTOCOL.md` | protocolo | `abe806d6b63943890bdd965ab00682fcf03890ac` | `75fa32c60c3b64184752ec7e2cbc02e0` | `7e067b5529f57d60735ef0755ce2a6fe6c468c55d8c6f04caa43476ccb53042a` | 49.998 |
| `LIVE-STAGE1-RUNBOOK.md` | textos L1/L3 | `9f454a9632f579607acadef1bfa076e3e5331e95` | `9ee3e8440ad86aeaa5aec51110a8a8e5` | `564702ba5bd1640a3c6e5e211a0c37244d8332a03c6edefdec4c880da64739d4` | 27.111 |
| `L1-EXECUTION-READINESS.md` | readiness v1.3 | `76cca8281abc4ac3069e9bff611d8cd06a345a48` | `6e07fcbc7e01fdd1f8f0a71e9c2b95c0` | `154e23b919e1f2a9c42d4c34ffb1771c80ea5493f20a2fd205f00d241fd6ac34` | 45.713 |
| `L1-E03-IMPLEMENTATION-READINESS.md` | readiness v1.2 | `4a93a5450650c5a2511adb204e7881e7fd8f2f67` | `1bcf73f176bfa725bc47569ece6279f1` | `0c6087c4fa5d8f58527ca40185cf5a91758ab1d77be0134edbe7a63ccea744dd` | 60.888 |
| `L1-E03T-LIVE-EXECUTION-PLAN.md` | plano do E03T | `f71e6b38f6517a760cc89a9c40de10535f585f48` | `6fa859ef458470e21fbfa9aa4c02e77f` | `dbd3694c3075f2cbd35ed4e98c66ff97b95f381738d94dd9831ed7de9228191d` | 16.403 |
| `PHASE5-AUTOMATED-COVERAGE-READINESS.md` | readiness da Fase 5 | `1aa8d71dc8c5fb499b6192d0cf341e753c0884a1` | `d8e9681784d2bbd0d77e19fe75777195` | `8cd96ca446dadef16e912a61476afa0bf61fd3d725e0cb91024ec6b00f0110df` | 60.188 |
| `LIVE-L1-E03T-EXECUTION-RECORD.md` | registro do E03T v1.1 | `eaffdb279006bc9751f1a42bb1cd92ab2c6a7d09` | `2975a6560716dd4754ee7a6201251454` | `79de28d7022f581e75fd4cc87f266d30d8ca55a12ab56e89ca09042c244ac4f5` | 63.237 |

- `static_check`, duas execuções idênticas: `TOTAL 444 PASS 444 FAIL 0` · `E03-PERFIL TOTAL 85 PASS 85 FAIL 0` · `E03-VERIFICADOR-NEG TOTAL 56 PASS 56 FAIL 0` · `E03-VERIFICADOR-POS TOTAL 4 PASS 4 FAIL 0`.
- L1 e L3: blocos do roteiro com md5 `0836c36a8d3749b1e7718223e064caf9` (2.458 B) e `b7bc3700aeef278f6a79bd30e6a8d229` (1.526 B).

## 2. Transição E03T → E03 (readiness v1.3 §6), estado corrente

O §6 da readiness v1.3 e o §5 do registro do E03T continuam como registro histórico: foram escritos antes da execução e da auditoria. Esta tabela registra o estado **em `a83f539e`**, sem apagar aquele texto.

| # | Condição | Evidência | Estado em `a83f539e` |
|---|---|---|---|
| T-1 | DP-7 decidida e E03T executado sob mandato, com registro publicado | DP-7 = A (readiness v1.3 §2.4); `LIVE-L1-E03T-EXECUTION-RECORD.md` v1.1 publicado (blob `eaffdb27…`, modo 100644) | **cumprida** |
| T-2 | E03T CONFORME | `H283P` `pass=3/3`, marcador `H2830_4C4BA06675344B72ABCFA4D9995B4F7F`, `elapsed_ms=133`; classificação CONFORME (diagnóstico) | **cumprida** |
| T-3 | postcheck íntegro | E99 9/9, `d_diff = []`, marcador ausente, `d_baseline_now_md5 = d_baseline_md5`; L3 final limpa | **cumprida** |
| T-4 | parecer da auditoria independente sobre o registro | parecer independente: auditoria técnica **PASS**, registrado na v1.1 do registro e no fechamento `…-E03T-PUBLICATION-CORRECTION-01`. **Histórico:** até a v1.0 do registro, T-4 constava como pendente | **cumprida** |
| T-5 | decisões aplicáveis ao E03 | DP-1, DP-4 e DP-5 decididas para o E03T **não se estendem** ao E03 (readiness v1.3 §2.5) | **pendente** — §4 |
| T-6 | autorização expressa de Fabrício | mandato de execução do E03, com baseline e blobs | **inexistente** |

**O que o E03T sustenta e o que não sustenta para o E03:**
- sustenta (R, observado no LIVE 17.6): `SET CONSTRAINTS … IMMEDIATE/DEFERRED` funciona dentro do `DO`, inclusive com IMMEDIATE que falha e é capturado; a sonda confirma DEFERRED e é descartada; o IMMEDIATE posterior à sonda não foi contaminado; rollback integral;
- **limite L-1, preservado:** o T3 demonstrou ausência de contaminação observável, **não** a remoção direta do evento diferido da fila;
- **não sustenta:** os 13 casos do E03, seus caminhos, tokens, constraints e o caso 2.7 (IMMEDIATE depois de sonda, isolado por Q1 — readiness de implementação §2.6.4); o tempo do E03. **`elapsed_ms = 133` não é medição representativa do E03.**

## 3. Superfície de escrita do E03 (E, extraída do blob `4866eb97…`)

### 3.1 Por caso

Contagem feita por script sobre o SQL publicado (código sem comentários), por intervalo de linhas de cada caso. Coincide com a readiness v1.3 §3.1 e com a readiness de implementação §2.6.5 e §3.2.

| Caso | Linhas | Contrato 2830 (l. 453–477) | INSERT trait | INSERT profile fixture | INSERT sonda | INSERT N:N | UPDATE | DELETE | IMMEDIATE / DEFERRED | Negativo (aceite) |
|---|---|---|---|---|---|---|---|---|---|---|
| 2.1 | 106–229 | selo ordenado após IMMEDIATE | 2 | 1 | 1 | 2 | — | — | 1 / 1 | — |
| 2.2 | 230–344 | `EMPTY_COMPOSITION` | — | 1 | 1 | — | — | — | 1 / 2 | `P0001` + `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:`, `v_step = IMMEDIATE` |
| 2.3 | 345–483 | `COMPOSITION_IMMUTABLE` (INSERT) | 2 | 1 | 1 | 2 | — | — | 1 / 1 | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` |
| 2.4 | 484–626 | `COMPOSITION_IMMUTABLE` (DELETE) | 2 | 1 | 1 | 2 | — | 1 | 1 / 1 | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` |
| 2.5 | 627–711 | `TRAIT_INACTIVE` | 1 (inativo) | 1 | — | 1 | — | — | 0 / 0 | `P0001` + `EDITION_CONTEXT_TRAIT_INACTIVE:` |
| 2.7 | 712–926 | `uq_cecp_game_signature` (23505) | 2 | 2 | 2 | 4 | — | — | 2 / 3 | `23505` + `uq_cecp_game_signature` + tabela, `v_step = IMMEDIATE` |
| 2.8 | 927–986 | NULL não colide | — | 2 | — | — | — | — | 0 / 0 | — |
| 2.9 | 987–1110 | selo ascendente | 3 | 1 | 1 | 3 | — | — | 1 / 1 | — |
| 2.10 | 1111–1244 | PK N:N (23505) + cardinality | 1 | 1 | 1 | 2 | — | — | 1 / 1 | `23505` + `pk_cecpt` + tabela |
| 2.11 | 1245–1332 | `SIGNATURE_MISMATCH` | 2 | 1 | — | 1 | 1 | — | 0 / 0 | `P0001` + `EDITION_CONTEXT_SIGNATURE_MISMATCH:` |
| 2.12 | 1333–1469 | `SIGNATURE_IMMUTABLE` | 2 | 1 | 1 | 1 | 1 | — | 1 / 1 | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` |
| 2.13 | 1470–1604 | `SIGNATURE_IMMUTABLE` (NULL) | 1 | 1 | 1 | 1 | 1 | — | 1 / 1 | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` |
| 2.14 | 1605–1731 | UPDATE sem selo permitido | 1 | 1 | 1 | 1 | 1 (`name`) | — | 1 / 1 | — (`ROW_COUNT = 1`) |
| **Total** | | **13 casos** (2.6 no lote L5) | **19** | **15** | **11** | **20** | **4** | **1** | **11 / 13** | **9 negativos** |

- **INSERTs:** 65 no arquivo (19 + 15 + 11 + 20). Dos 20 INSERTs de N:N, 3 são rejeições esperadas (2.3, 2.5, 2.10) e 2 são aceitos e depois desfeitos pelo negativo de 2.7.
- **Selos** (UPDATE feito pela função da 2206, disparado pelo IMMEDIATE): **9** efetivos (2.1, 2.3, 2.4, 2.7 Pa, 2.9, 2.10, 2.12, 2.13, 2.14) e **2** tentativas que falham por desenho (2.2 `EMPTY_COMPOSITION`; 2.7 Pb `23505`). Os 4 eventos de fixture sem IMMEDIATE (2.5; 2.8 ×2; 2.11) e os 11 eventos de sonda saem com a subtransação respectiva. Fonte: matriz da readiness de implementação §2.6.4–§2.6.5 (E para o estado esperado; R para o observado).
- **Subtransações:** 33 = 13 de caso + 11 de sonda + 9 sub-blocos negativos (34 `BEGIN` no arquivo, contando o do `DO`). **Todas terminam em exceção.**
- **Envelope:** 1 `DO` (l. 54), gate final `v_done = c_expected` e `v_qn = 11`, terminal `H283P` na l. 1747.

### 3.2 Tabelas, triggers e locks

| Tabela | Escrita | Triggers alcançados | Observações |
|---|---|---|---|
| `card_edition_context_trait` | 19 INSERT (1 com `is_active = false`, 2.5) | nenhum | FK para `game`; `code` e `name` com marcador; família `EVENT`; `display_order` = máx. + 1000 + k |
| `card_edition_context_profile` | 15 INSERT de fixture + 11 de sonda; 4 UPDATE do envelope (2.11–2.14); 9 selos | `trg_cecp_seal` (AFTER INSERT, constraint trigger DEFERRABLE INITIALLY DEFERRED); `trg_cecp_signature_write` (BEFORE UPDATE OF `traits_signature`: nos selos e em 2.11–2.13) | UPDATE só `WHERE id = v_p… AND code = v_code_p…` (E03-3); índice parcial `uq_cecp_game_signature` exercido em 2.7 |
| `card_edition_context_profile_trait` | 20 INSERT; 1 DELETE (2.4) | `trg_cecpt_immutable` (BEFORE INSERT/UPDATE/DELETE); `trg_cecpt_trait_active` (BEFORE INSERT) | FKs compostas para profile e trait; PK `pk_cecpt` exercida em 2.10; DELETE só `WHERE profile_id = v_p AND trait_id = v_t…` (E03-4) |
| `game` | nenhuma | — | leitura (`code = 'POKEMON'`, preflight = 1) e `FOR KEY SHARE` implícito pelas FKs |

- Nenhuma outra tabela é escrita (E03-7). `card_edition_context_external_mapping` aparece só no `SET CONSTRAINTS` (nome de `trg_cecem_seal`), sem evento.
- Locks: `RowExclusiveLock` nas 3 tabelas; locks de linha nas fixtures; `FOR KEY SHARE` na linha POKEMON de `game`; entradas novas em índices únicos (inclusive `uq_cecp_game_signature`). Sob FREEZE não há escritor concorrente legítimo; uma colisão só ocorreria com escritor das mesmas chaves, que o marcador por execução torna impossível fora de concorrência real.
- 26 leituras `max(display_order)` em trait/profile (tabelas de 115 e 144 linhas no baseline).

### 3.3 Garantias estáticas e caminhos de rollback

| Garantia | Fonte |
|---|---|
| todo caminho do `DO` termina em exceção (`H283C` por caso, `H283P`/`H283F` no envelope) | E03-12; perfil E03 85/85 |
| UPDATE/DELETE só em ids criados pelo próprio caso | E03-3, E03-4, E03-7 |
| INSERT de trait/profile sempre com marcador em `code` e `name` | E03-7 |
| nenhum `SET` além dos `SET CONSTRAINTS` dos dois selos; nenhum `SET LOCAL`, `set_config`, `EXECUTE`, `COMMIT`, `TEMP` | E03-2, E03-5 |
| 11 sondas no formato exato, uma por IMMEDIATE, fora de sub-bloco negativo | E03-15, E03-17, E03-18 |
| negativos com SQLSTATE e token exato, ou constraint e tabela exatas; nunca `LIKE` | E03-8, E03-9, E03-10 |
| casos na ordem, `2.6` ausente | E03-11 |
| mutações inseguras rejeitadas pelo verificador | 56/56 |

**Caminhos de rollback:** sonda → `H283S` desfaz a linha e o evento da sonda; sub-bloco negativo → o erro esperado desfaz o que foi escrito nele; caso → `H283C` desfaz todas as fixtures do caso e os eventos pendentes; envelope → `H283P` ou `H283F` desfaz tudo; qualquer erro não previsto, `57014` ou `55P03` também aborta a transação.

**Resíduo não-transacional possível (declarado, não verificado pelo E99):** contadores `pg_stat_*`, tuplas mortas até o autovacuum, WAL das escritas abortadas, XIDs de subtransação (dezenas) e linhas de log com o marcador. Sequences: nenhuma (ids UUID; E00 `g_no_sequences_touched_now`, E03P `g_nn_no_sequence`).

## 4. Decisões próprias do E03 (para Fabrício; nenhuma decidida aqui)

### 4.1 DP-1 — performance do E03

**Requisito literal (2830 P9b e A2):** tempo real medido em ambiente isolado representativo (P14), 3 execuções com 1 de cache frio, pior caso ≤ 60 s, "nunca no LIVE". Não existe essa medição para o E03: o ambiente isolado pago foi recusado e D-1 (alternativa sem custo) está pendente. P9a não se aplica: o E03 é um `DO` (o `EXPLAIN` não aceita `DO`) sem consulta pesada.

**Evidência disponível, separada:**

| Fonte | O que é | O que não é |
|---|---|---|
| E01 (Etapa 3): `elapsed_ms = 251` | H: 12 casos, 11 INSERTs, sem `SET CONSTRAINTS` | medição do E03 |
| E03T: `elapsed_ms = 133` | H: 3 casos, 11 INSERTs, 2 selos, 8 subtransações, 4 IMMEDIATE | medição do E03; **não** representativa (superfície ~6× menor em INSERT e ~4× em subtransações) |
| Superfície do E03 (§3) | E: 65 INSERTs, 4 UPDATE, 1 DELETE, 9 + 2 selos, 33 subtransações, 11 IMMEDIATE, 13 DEFERRED, 26 leituras de `max` | tempo |

Nenhuma extrapolação a partir do E01 ou do E03T é medição. O desempenho do E03 **não** está aprovado.

| Alternativa | Compatível com o contrato? | Evidência | Risco residual | Implicação |
|---|---|---|---|---|
| **A** — AD-2 específica para o E03, por decisão expressa: tempo medido no próprio LIVE; `statement_timeout = '2min'` comprovado na L1 da rodada; aceite `elapsed_ms ≤ 60000` | por **adaptação** declarada; P9b e A2 não cumpridos literalmente | H (E01, E03T) + E (§3) | sem medição prévia; se o tempo real passar de 60 s, o resultado não é aceito mas a escrita já ocorreu e foi desfeita; teto duro 120 s (`57014` = NÃO CONFORME) | E03 executável após DP-4, DP-5 e mandato |
| **B** — exigir P9b literal em ambiente isolado representativo antes do LIVE | literal | nenhuma: ambiente inexistente | nenhum risco LIVE | E03 bloqueado até D-1 resolvida e medição registrada |
| **C** — outra alternativa tecnicamente demonstrável | — | **nenhuma identificada** que produza medição sem ambiente isolado ou sem nova implementação. Candidatas avaliadas e **não** propostas: (i) `EXPLAIN` — não mede tempo e não aceita `DO`; (ii) extrapolar do E03T/E01 — não é medição; (iii) dividir o E03 em envelopes menores — exige mandato de implementação, novos blobs e nova auditoria; (iv) ambiente isolado sem custo — é a própria D-1, pendente, com P14 (a, b, c) obrigatório | — | — |

**Deliberação de Fabrício — DP-1 (E03):** `____` (não preenchida).

### 4.2 DP-4 — `lock_timeout` do E03

**Requisito (2830 P8/A5):** `SET LOCAL lock_timeout = '5s'` como primeira instrução, com asserção de aplicação e prova de não persistência; ou o harness roda sem ele, com decisão registrada. Protocolo §2.3: nenhum `SET`/`set_config` de sessão; D-4: `lock_timeout ≠ '0'` na L1 ⇒ STOP.

**Envelope publicado (E):** o E03 não contém `SET LOCAL` (cabeçalho: "DECISÃO PENDENTE (DP-4)… NÃO é emitida"); o perfil E03 proíbe `SET LOCAL` (E03-2) e só admite os dois `SET CONSTRAINTS` (E03-5). O E99 exige `lock_timeout = '0'`.

| Alternativa | Compatível? | Evidência | Risco residual | Implicação |
|---|---|---|---|---|
| **A** — implementar `SET LOCAL lock_timeout = '5s'` no E03 | sim (transacional; desfeito no rollback) | E: não existe no blob atual | exige **mandato de implementação**: primeira instrução e asserção inicial; mudança nas regras E03-2/E03-5 e nos controles negativos; novo blob do E03; nova auditoria; readiness de execução refeita sobre o blob novo | uma rodada de implementação antes da execução |
| **B** — E03 publicado, sem `SET LOCAL`, por decisão expressa, com controles operacionais: L1 (`lock_timeout = '0'`, `statement_timeout = '2min'`), L3 sem locks no escopo, E00 `g_no_concurrency`, E03P, FREEZE | sim (A5 "roda sem ele, decisão registrada") | H: E01 e E03T executados assim, sem espera | uma espera por lock (improvável sob FREEZE) só termina em 120 s, com rollback integral; `57014` = NÃO CONFORME | nenhum artefato muda |
| — `SET` de sessão, `set_config` ou `ALTER ROLE` | **não** (configuração de sessão ou persistente) | — | — | rejeitada |

A decisão DP-4 = B aprovada para o E03T **não se transfere** ao E03.

**Deliberação de Fabrício — DP-4 (E03):** `____` (não preenchida).

### 4.3 DP-5 — escritas transitórias do E03

**Escopo exato que uma autorização teria de nomear** (§3): 19 INSERTs em `card_edition_context_trait`; 15 INSERTs de fixture e 11 de sonda em `card_edition_context_profile`; 20 INSERTs em `card_edition_context_profile_trait`; 4 UPDATEs em profile de fixture (`traits_signature` em 2.11–2.13, `name` em 2.14); 1 DELETE em profile_trait de fixture (2.4); 9 selos efetivos e 2 tentativas que falham; 33 subtransações; só as três tabelas EC; `game` só lida. Tudo com rollback obrigatório e verificação posterior (E99 + L3 final).

| Alternativa | Implicação |
|---|---|
| **A** — autorizar exclusivamente as escritas do E03 publicado (blob `4866eb97…`), uma execução, sob mandato próprio | E03 executável quando DP-1 e DP-4 também estiverem decididas e houver mandato |
| **B** — não autorizar | nada vai ao LIVE; L1 parado |

Nenhuma autorização de escrita é presumida. A autorização do E03T está esgotada e não cobre UPDATE, DELETE nem o volume do E03.

**Deliberação de Fabrício — DP-5 (E03):** `____` (não preenchida).

## 5. Readiness operacional do E03 (proposta; não é autorização)

### 5.1 Condições de entrada do mandato futuro

1. DP-1, DP-4 e DP-5 do E03 decididas e registradas (T-5).
2. Mandato de execução próprio, com baseline HEAD, citando este documento e a readiness v1.3 pelo blob (T-6). Se DP-4 = A, o blob do E03 muda e esta readiness deve ser refeita.
3. Campo obrigatório no mandato: número máximo de L3-D no fluxo excepcional.
4. Canal: MCP Supabase `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`; uma chamada por statement; nunca Dashboard, nunca `apply_migration`.

### 5.2 Identidade e resposta esperada

- Texto submetido no S5: o E03 integral, blob `4866eb970db18ef492cc4f362249856de1eab45e`, md5 `2ef78e0ba4196d077dbfaae43f465c24`, 91.852 B, uma única submissão.
- **Resposta conforme:** SQLSTATE `H283P`; mensagem, não truncada, casando com `^H2830_ROLLBACK_PASS: envelope=E03_SECAO2_COMPOSICAO_PROFILE pass=13/13 casos=2\.1,2\.2,2\.3,2\.4,2\.5,2\.7,2\.8,2\.9,2\.10,2\.11,2\.12,2\.13,2\.14 marker=H2830_[0-9A-F]{32} elapsed_ms=[0-9]+$`; contexto `PL/pgSQL function inline_code_block line 1694 at RAISE` (RAISE terminal na l. 1747, `DO` na l. 54: 1747 − 54 + 1); `elapsed_ms` dentro do limite que DP-1 fixar.
- **Falha:** SQLSTATE `H283F`, `H2830_FAIL: envelope=E03_SECAO2_COMPOSICAO_PROFILE caso=<id|PREFLIGHT|GATE> …`; mensagem com "sonda" = falha do padrão N-1/sonda (FAIL de harness). Qualquer outro SQLSTATE é falha.
- **Resposta definida** traz SQLSTATE e texto do PostgreSQL, ou retorno sem erro. **Ambígua:** timeout do cliente, perda de conexão, HTTP sem corpo, erro do canal sem texto do PostgreSQL.

### 5.3 Sequência S0–S7

Idêntica à do E03T (readiness v1.3 §4.2; plano do E03T §4), trocando o S5 pelo E03:

| Passo | Chamada | Continua se (todos) |
|---|---|---|
| S0 | local | HEAD = baseline do mandato; árvore e índice limpos; blobs do §1 conferidos; `static_check` 444/85/56/4; md5 de L1 e L3 |
| S1 | L1 | `transaction_read_only = off`, `default_transaction_read_only = off`, `in_recovery = false`, `lock_timeout = '0'` (ou o valor que DP-4 = A exigir **dentro** do envelope; a sessão continua `'0'`), `statement_timeout = '2min'`, PG ≥ 170000, `standard_conforming_strings = on`, donos EC = `current_user`, visibilidade provada |
| S2 | L3 | `locks_on_scope = []`; nenhuma outra sessão `client backend` ativa ou em transação |
| S3 | E00 | 24/24 gates, `gate_pass = true`, `d_canon_diff = []`; capturar `d_baseline`, `d_baseline_md5`, `db_role_setting_rows`, `checked_at`, `backend_pid` |
| S4 | E03P | 11/11 gates e `gate_pass = true` |
| S5 | **E03** | resposta definida (§5.2) |
| S6 | E99 com os 3 valores do S3 **desta** rodada | aceite do postcheck (readiness v1.3 §4.4) |
| S7 | L3 final, sempre depois do S6 | nenhum lock no escopo; nenhuma sessão ativa ou em transação; nenhum pid da rodada |

- **Fluxo excepcional (resposta ambígua do S5):** não reenviar; L3-D só leitura até o limite do mandato; com encerramento comprovado, S6 e depois S7; sem confirmação, nem E99 nem S7, INCONCLUSIVO, resíduo não verificado, STOP (readiness v1.3 §4.4).
- **E99:** gerado só com os três valores do S3 da mesma rodada, na forma literal devolvida pelo canal ("colar, nunca redigitar"); cada marcador substituído exatamente uma vez; md5 do JSON recalculado igual a `d_baseline_md5`; texto difere do blob só nas linhas 56–58; md5 registrado antes de submeter. Nunca baseline de outra rodada, nunca edição manual.

### 5.4 Postcheck, classificação e STOP

- **Postcheck ÍNTEGRO:** E99 completo com os 9 gates `true`, `d_diff = []`, `d_canon_diff = []`, `g_marker_absent = true`, `d_baseline_now_md5 = d_baseline_md5`, **e** S7 completo e limpo. Só então se afirma resíduo zero (readiness v1.3 §4.4).
- **Classificação:** integralmente a da readiness v1.3 §4.4–§5, aplicada ao E03 pelo §6 da mesma readiness: INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME. `H283P` sozinho não é aceite; `pass ≠ 13/13` ou mensagem truncada é INCONCLUSIVO; `elapsed_ms` acima de DP-1 é NÃO CONFORME.
- **Efeito contratual:** diferente do E03T, o E03 implementa casos da 2830. O aceite de contrato é o da 2830 (B1–B5) e o do protocolo, como na Etapa 3 (E01 ⇒ `1.1–1.12 PASS`). A atribuição de PASS aos 13 casos e a mudança da cobertura só existem em registro de execução auditado; este documento não as antecipa.
- **STOP:** todos os da readiness v1.3 §4.5 e do plano do E03T §9–§10, mais: blob do E03 diferente de `4866eb97…`; decisão T-5 ausente; `statement_timeout ≠ '2min'`; qualquer necessidade de `SET`, alteração de SQL ou de critério; nenhum retry do E03; nenhuma limpeza sem mandato; nenhum avanço automático a outro lote.

### 5.5 Riscos residuais e limitações

| Risco | Tratamento | Evidência |
|---|---|---|
| escrita real no LIVE sob FREEZE, em volume ~6× o do E03T | rollback estrutural (todo caminho termina em exceção) e prova tripla | E; H (E01, E03T) |
| tempo sem medição prévia | DP-1; teto de 120 s | nenhuma medição do E03 |
| espera por lock | DP-4; FREEZE; L3; `g_no_concurrency` | H: E01 e E03T sem espera |
| limite L-1 | não demonstrável por SQL; resultado aceito de 2.7 depende só do selo de Pb | readiness de implementação §2.6.4, §2.6.7 |
| 2.7 (IMMEDIATE depois de sonda, erro `23505` em índice) nunca executado | FAIL de harness se divergir; nunca PASS | R |
| `CONSTRAINT_NAME` de violação de índice único = nome do índice | esperado pela documentação; não observado neste harness; divergência = FAIL | R |
| ramos PL/pgSQL de falha nunca percorridos | só verificados estaticamente (C-5) | E |
| nota de contexto: correção do PostgreSQL de 2026-08-19 em `AfterTriggerSetState` (backpatch só até 19; LIVE 17.6) | sondas cobrem o sintoma observável; o E03T não observou o sintoma | readiness de implementação §2.7; H (E03T) |
| canal caixa-preta: sem pid nem horário do erro | fluxo excepcional com L3-D | H |
| resíduo não-transacional | declarado (§3.3) | declarado |

## 6. Questões para deliberação expressa de Fabrício

1. **DP-1 (E03):** A, B ou outra; se A, confirmar teto 120 s e aceite `elapsed_ms ≤ 60000`, restritos ao E03.
2. **DP-4 (E03):** A (mandato de implementação e novo blob) ou B (blob publicado sem `SET LOCAL`), restrita ao E03.
3. **DP-5 (E03):** autorizar ou não exatamente a superfície do §4.3, restrita ao blob `4866eb97…`.
4. **Número máximo de L3-D** para o mandato de execução.
5. **Registro do resultado:** se o E03 for CONFORME, se o registro pode propor `2.1–2.5, 2.7–2.14 PASS` e a nova cobertura, sujeitos à auditoria (§5.4).

## 7. Limites desta rodada

- Nenhum SQL, nenhum LIVE, nenhum envelope ou documento anterior alterado; contagens do §3 vêm da leitura estática do blob.
- Nenhuma decisão tomada; nenhum PASS; cobertura **17/135**; E03 **não autorizado**. **FREEZE ATIVO.**

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L1-E03-EXECUTION-READINESS-01`, baseline `a83f539e`), documental, sem SQL e sem LIVE.**<br>• gate inicial: HEAD, árvore e índice limpos, blobs, modo 100644 e blob `eaffdb27…` do registro do E03T;<br>• T-1 a T-6: T-1–T-4 cumpridas (T-4 atualizada sem apagar o histórico), T-5 pendente, T-6 inexistente; limite L-1 preservado; `elapsed_ms = 133` não representativo;<br>• inventário da superfície de escrita do E03 por caso, extraído do blob `4866eb97…`;<br>• matrizes DP-1, DP-4 e DP-5 do E03 com campos em branco;<br>• readiness operacional S0–S7, resposta esperada (contexto `line 1694`), fluxo excepcional, E99, classificação por referência à readiness v1.3, STOP e riscos. Nenhuma decisão tomada. FREEZE ATIVO. |
