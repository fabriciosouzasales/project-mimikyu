# 2830H — Lote L1: readiness de execução LIVE do E03 (Seção 2, 13 casos)

| Campo | Valor |
|---|---|
| **Natureza** | Adjudicação técnica e operacional do E03, documental e local. **Nenhum SQL executado**, nem SELECT; nenhum acesso ao LIVE; contrato e protocolo não alterados. v1.0: nenhum envelope alterado. v1.1: o E03 e o `static_check` foram alterados localmente pela DP-4 = A (§1.1, §5.6). v1.2: correção só documental. |
| **Mandato** | `BATCH12-2830-P5-L1-E03-EXECUTION-READINESS-01`. Baseline HEAD `a83f539e6ca36a1c0d8fc8947b4f3ddd586a22bc`. v1.1: `BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01`, baseline HEAD `aeeed59aadcf1797ee77a4d63b43aac0d80348b6` (decisões de Fabrício e implementação local da DP-4 = A). |
| **Autoridades** | 2830 v7.0 (blob `b4647dcb…`, imutável) · `L1-EXECUTION-READINESS.md` v1.3 (blob `76cca828…`) · `L1-E03-IMPLEMENTATION-READINESS.md` v1.2 (blob `4a93a545…`; v1.3 local desde a v1.1 desta readiness, regra E03-20) · `LIVE-VALIDATION-PROTOCOL.md` (blob `abe806d6…`) · `LIVE-STAGE1-RUNBOOK.md` (blob `9f454a96…`) · `LIVE-L1-E03T-EXECUTION-RECORD.md` v1.1 (blob `eaffdb27…`). Em divergência, prevalecem estas autoridades; este documento não cria critério de PASS/FAIL nem classe de resultado. |
| **Estado** | **v1.2 — correção documental da auditoria da DP-4 = A (`BATCH12-2830-P5-L1-E03-DP4A-AUDIT-CORRECTION-01`); v1.1 — decisões registradas e DP-4 = A implementada localmente; para auditoria independente.** DP-1 = A, DP-4 = A, DP-5 = A, `MAX_L3_D = 2` e reconhecimento contratual = SIM, só para o E03 (§4, §5). Novo blob do E03: **`ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e`**. **E03 não executado e não autorizado:** a autorização de escrita (DP-5) depende da auditoria independente e da publicação deste blob e de um mandato de execução próprio. E03T CONFORME, auditado e publicado. Cobertura LIVE **17/135** (30/135 é só cobertura potencial). **FREEZE ATIVO.** |

---

## 0. Resultado

- **STOP: não houve.** Nenhuma divergência material de segurança, integridade, semântica, performance ou concorrência foi encontrada nos artefatos publicados.
- **Execução do E03: não permitida.** v1.0: faltavam as decisões DP-1, DP-4 e DP-5 do E03 (T-5) e o mandato (T-6). **v1.1:** T-5 decidida; a DP-4 = A mudou o blob do E03, que ainda precisa de auditoria independente e publicação; T-6 (mandato de execução) continua inexistente.
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

### 1.1 Identidade vigente depois da DP-4 = A (v1.1)

A tabela acima é o gate da v1.0 (HEAD `a83f539e`). Em `aeeed59a` (HEAD `aeeed59aadcf1797ee77a4d63b43aac0d80348b6`, árvore e índice limpos antes desta rodada) os blobs eram os mesmos. Esta rodada alterou localmente, ainda sem commit:

| Arquivo | Papel | blob | md5 | sha256 | Bytes |
|---|---|---|---|---|---|
| **`2830H_E03_section2_profile_composition.sql`** | E03 com preâmbulo P8 (DP-4 = A) | **`ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e`** | **`e0aeb7e3dc4143d171cb4364d99069d8`** | **`e2949dc65a8215800af05bac209b5745287a755ad9e6a488e2ed00d08ce5215e`** | **93.188** (1.772 linhas) |
| `tools/static_check.py` | perfil E03 com E03-20 e vetores novos | `79c4fd42335567caaac436370633c0302875e7d3` | `052748be05f12636021ce0626090313e` | `759b8fe1eea946e5540f15a5715f875ce30b3a71a74f09538de93be5f8467b9c` | 99.493 |

- O blob anterior do E03 (`4866eb97…`) fica **superado** e não pode ser submetido.
- `static_check`: `TOTAL 444 PASS 444 FAIL 0` · `E03-PERFIL TOTAL 88 PASS 88 FAIL 0` · `E03-VERIFICADOR-NEG TOTAL 79 PASS 79 FAIL 0` · `E03-VERIFICADOR-POS TOTAL 6 PASS 6 FAIL 0` (antes: 444/85/56/4). Os novos: 3 verificações de perfil (E03-20 no E03 ×2, no E03T ×1), 23 mutações inseguras e 2 controles positivos.
- E03T, E03P, E00, E99, 2830, protocolo e roteiro: blobs inalterados.

## 2. Transição E03T → E03 (readiness v1.3 §6), estado corrente

O §6 da readiness v1.3 e o §5 do registro do E03T continuam como registro histórico: foram escritos antes da execução e da auditoria. Esta tabela registra o estado **em `a83f539e`**, sem apagar aquele texto.

| # | Condição | Evidência | Estado em `a83f539e` |
|---|---|---|---|
| T-1 | DP-7 decidida e E03T executado sob mandato, com registro publicado | DP-7 = A (readiness v1.3 §2.4); `LIVE-L1-E03T-EXECUTION-RECORD.md` v1.1 publicado (blob `eaffdb27…`, modo 100644) | **cumprida** |
| T-2 | E03T CONFORME | `H283P` `pass=3/3`, marcador `H2830_4C4BA06675344B72ABCFA4D9995B4F7F`, `elapsed_ms=133`; classificação CONFORME (diagnóstico) | **cumprida** |
| T-3 | postcheck íntegro | E99 9/9, `d_diff = []`, marcador ausente, `d_baseline_now_md5 = d_baseline_md5`; L3 final limpa | **cumprida** |
| T-4 | parecer da auditoria independente sobre o registro | parecer independente: auditoria técnica **PASS**, registrado na v1.1 do registro e no fechamento `…-E03T-PUBLICATION-CORRECTION-01`. **Histórico:** até a v1.0 do registro, T-4 constava como pendente | **cumprida** |
| T-5 | decisões aplicáveis ao E03 | DP-1, DP-4 e DP-5 decididas para o E03T **não se estendem** ao E03 (readiness v1.3 §2.5). **v1.1:** DP-1 = A, DP-4 = A e DP-5 = A decididas para o E03 (§4); a DP-4 = A foi implementada no novo blob `ef24a3be…` | **decidida (v1.1)**; implementação pendente de auditoria e publicação |
| T-6 | autorização expressa de Fabrício | mandato de execução do E03, com baseline e blobs | **inexistente** (v1.1 inclusive) |

**O que o E03T sustenta e o que não sustenta para o E03:**
- sustenta (R, observado no LIVE 17.6): `SET CONSTRAINTS … IMMEDIATE/DEFERRED` funciona dentro do `DO`, inclusive com IMMEDIATE que falha e é capturado; a sonda confirma DEFERRED e é descartada; o IMMEDIATE posterior à sonda não foi contaminado; rollback integral;
- **limite L-1, preservado:** o T3 demonstrou ausência de contaminação observável, **não** a remoção direta do evento diferido da fila;
- **não sustenta:** os 13 casos do E03, seus caminhos, tokens, constraints e o caso 2.7 (IMMEDIATE depois de sonda, isolado por Q1 — readiness de implementação §2.6.4); o tempo do E03. **`elapsed_ms = 133` não é medição representativa do E03.**

## 3. Superfície de escrita do E03 (E, extraída do blob `4866eb97…`; confirmada no blob `ef24a3be…` na v1.1)

### 3.1 Por caso

Contagem feita por script sobre o SQL (código sem comentários), por intervalo de linhas de cada caso. **v1.1:** as linhas abaixo são as do novo blob `ef24a3be…`; o texto de cada caso é byte a byte o do blob `4866eb97…` (a DP-4 = A só acrescentou o preâmbulo P8 e comentários do cabeçalho), então as contagens não mudam. Coincide com a readiness v1.3 §3.1 e com a readiness de implementação §2.6.5 e §3.2.

| Caso | Linhas | Contrato 2830 (l. 453–477) | INSERT trait | INSERT profile fixture | INSERT sonda | INSERT N:N | UPDATE | DELETE | IMMEDIATE / DEFERRED | Negativo (aceite) |
|---|---|---|---|---|---|---|---|---|---|---|
| 2.1 | 126–249 | selo ordenado após IMMEDIATE | 2 | 1 | 1 | 2 | — | — | 1 / 1 | — |
| 2.2 | 250–364 | `EMPTY_COMPOSITION` | — | 1 | 1 | — | — | — | 1 / 2 | `P0001` + `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:`, `v_step = IMMEDIATE` |
| 2.3 | 365–503 | `COMPOSITION_IMMUTABLE` (INSERT) | 2 | 1 | 1 | 2 | — | — | 1 / 1 | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` |
| 2.4 | 504–646 | `COMPOSITION_IMMUTABLE` (DELETE) | 2 | 1 | 1 | 2 | — | 1 | 1 / 1 | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` |
| 2.5 | 647–731 | `TRAIT_INACTIVE` | 1 (inativo) | 1 | — | 1 | — | — | 0 / 0 | `P0001` + `EDITION_CONTEXT_TRAIT_INACTIVE:` |
| 2.7 | 732–946 | `uq_cecp_game_signature` (23505) | 2 | 2 | 2 | 4 | — | — | 2 / 3 | `23505` + `uq_cecp_game_signature` + tabela, `v_step = IMMEDIATE` |
| 2.8 | 947–1006 | NULL não colide | — | 2 | — | — | — | — | 0 / 0 | — |
| 2.9 | 1007–1130 | selo ascendente | 3 | 1 | 1 | 3 | — | — | 1 / 1 | — |
| 2.10 | 1131–1264 | PK N:N (23505) + cardinality | 1 | 1 | 1 | 2 | — | — | 1 / 1 | `23505` + `pk_cecpt` + tabela |
| 2.11 | 1265–1352 | `SIGNATURE_MISMATCH` | 2 | 1 | — | 1 | 1 | — | 0 / 0 | `P0001` + `EDITION_CONTEXT_SIGNATURE_MISMATCH:` |
| 2.12 | 1353–1489 | `SIGNATURE_IMMUTABLE` | 2 | 1 | 1 | 1 | 1 | — | 1 / 1 | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` |
| 2.13 | 1490–1624 | `SIGNATURE_IMMUTABLE` (NULL) | 1 | 1 | 1 | 1 | 1 | — | 1 / 1 | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` |
| 2.14 | 1625–1751 | UPDATE sem selo permitido | 1 | 1 | 1 | 1 | 1 (`name`) | — | 1 / 1 | — (`ROW_COUNT = 1`) |
| **Total** | | **13 casos** (2.6 no lote L5) | **19** | **15** | **11** | **20** | **4** | **1** | **11 / 13** | **9 negativos** |

- **INSERTs:** 65 no arquivo (19 + 15 + 11 + 20). Dos 20 INSERTs de N:N, 3 são rejeições esperadas (2.3, 2.5, 2.10) e 2 são aceitos e depois desfeitos pelo negativo de 2.7.
- **Selos** (UPDATE feito pela função da 2206, disparado pelo IMMEDIATE): **9** efetivos (2.1, 2.3, 2.4, 2.7 Pa, 2.9, 2.10, 2.12, 2.13, 2.14) e **2** tentativas que falham por desenho (2.2 `EMPTY_COMPOSITION`; 2.7 Pb `23505`). Os 4 eventos de fixture sem IMMEDIATE (2.5; 2.8 ×2; 2.11) e os 11 eventos de sonda saem com a subtransação respectiva. Fonte: matriz da readiness de implementação §2.6.4–§2.6.5 (E para o estado esperado; R para o observado).
- **Subtransações:** 33 = 13 de caso + 11 de sonda + 9 sub-blocos negativos (34 `BEGIN` no arquivo, contando o do `DO`). **Todas terminam em exceção.**
- **Envelope (v1.1):** 1 `DO` (l. 65), preâmbulo P8 (l. 103–111, antes de qualquer leitura ou escrita), gate final `v_done = c_expected` e `v_qn = 11`, terminal `H283P` na l. 1767. (v1.0: `DO` l. 54, terminal l. 1747.)

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

**Vigente (v1.1/v1.2, blob `ef24a3be…`, `static_check` `79c4fd42…`):**

| Garantia | Fonte |
|---|---|
| todo caminho do `DO` termina em exceção (`H283C` por caso, `H283P`/`H283F` no envelope) | E03-12; perfil E03 **88/88** |
| UPDATE/DELETE só em ids criados pelo próprio caso | E03-3, E03-4, E03-7 |
| INSERT de trait/profile sempre com marcador em `code` e `name` | E03-7 |
| **único** `SET LOCAL` permitido: o preâmbulo P8 `SET LOCAL lock_timeout = '5s'` + asserção fail-closed, exatos e como primeira instrução executável do bloco principal | **E03-20** (autoriza exclusivamente esse preâmbulo) |
| nenhum outro `SET LOCAL` (outro valor, outra GUC, adicional, dentro de caso, depois de leitura ou escrita); nenhum `SET` de sessão, `SET SESSION`, `set_config`, `ALTER`, `EXECUTE`, `COMMIT`, `TEMP` | E03-2, E03-20 |
| nenhum outro `SET` além dos dois `SET CONSTRAINTS` dos selos | E03-5 |
| 11 sondas no formato exato, uma por IMMEDIATE, fora de sub-bloco negativo | E03-15, E03-17, E03-18 |
| negativos com SQLSTATE e token exato, ou constraint e tabela exatas; nunca `LIKE` | E03-8, E03-9, E03-10 |
| casos na ordem, `2.6` ausente | E03-11 |
| mutações inseguras rejeitadas pelo verificador | **79/79** (23 delas sobre o P8) |
| controles positivos do verificador | **6/6** |

**HISTÓRICO (v1.0, blob `4866eb97…`, `static_check` `6b3689cc…`; não vigente):** a garantia era "nenhum `SET` além dos `SET CONSTRAINTS`; nenhum `SET LOCAL`" (E03-2, E03-5), com perfil 85/85, mutações 56/56 e positivos 4/4. Ela descrevia corretamente o E03 anterior à DP-4 = A e deixou de valer quando o preâmbulo P8 entrou.

**Caminhos de rollback:** sonda → `H283S` desfaz a linha e o evento da sonda; sub-bloco negativo → o erro esperado desfaz o que foi escrito nele; caso → `H283C` desfaz todas as fixtures do caso e os eventos pendentes; envelope → `H283P` ou `H283F` desfaz tudo; qualquer erro não previsto, `57014` ou `55P03` também aborta a transação (tratamento do `55P03` no §5.6).

**Resíduo não-transacional possível (declarado, não verificado pelo E99):** contadores `pg_stat_*`, tuplas mortas até o autovacuum, WAL das escritas abortadas, XIDs de subtransação (dezenas) e linhas de log com o marcador. Sequences: nenhuma (ids UUID; E00 `g_no_sequences_touched_now`, E03P `g_nn_no_sequence`).

## 4. Decisões próprias do E03

**HISTÓRICO (v1.0):** esta seção foi escrita com as decisões **pendentes** ("nenhuma decidida aqui") e com o E03 ainda sem `SET LOCAL`. As análises, matrizes e alternativas abaixo ficam como registro dessa deliberação, sem alteração. **Vigente (v1.1):** a deliberação de Fabrício está no fim de cada subseção (DP-1 = A, DP-4 = A, DP-5 = A).

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

**Deliberação de Fabrício — DP-1 (E03): A** (registrada na v1.1, `BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01`). AD-2 específica do E03:
- medição durante a execução autorizada no LIVE;
- `statement_timeout = '2min'`, comprovado previamente na L1 da rodada;
- aceite somente se `elapsed_ms ≤ 60000`;
- P9b e A2 **não** cumpridos literalmente;
- o resultado de 133 ms do E03T **não** é medição representativa do E03.

### 4.2 DP-4 — `lock_timeout` do E03

**Requisito (2830 P8/A5):** `SET LOCAL lock_timeout = '5s'` como primeira instrução, com asserção de aplicação e prova de não persistência; ou o harness roda sem ele, com decisão registrada. Protocolo §2.3: nenhum `SET`/`set_config` de sessão; D-4: `lock_timeout ≠ '0'` na L1 ⇒ STOP.

**HISTÓRICO (v1.0) — envelope então publicado (E, blob `4866eb97…`):** o E03 não continha `SET LOCAL` (cabeçalho: "DECISÃO PENDENTE (DP-4)… NÃO é emitida"); o perfil E03 proibia `SET LOCAL` (E03-2) e só admitia os dois `SET CONSTRAINTS` (E03-5). O E99 exige `lock_timeout = '0'` (continua valendo). **Vigente (v1.1):** o E03 `ef24a3be…` contém exatamente o preâmbulo P8, autorizado só pela E03-20 (§3.3, §5.6).

| Alternativa | Compatível? | Evidência | Risco residual | Implicação |
|---|---|---|---|---|
| **A** — implementar `SET LOCAL lock_timeout = '5s'` no E03 | sim (transacional; desfeito no rollback) | E (v1.0, histórico): não existia no blob de então; implementada na v1.1 | exige **mandato de implementação**: primeira instrução e asserção inicial; mudança nas regras E03-2/E03-5 e nos controles negativos; novo blob do E03; nova auditoria; readiness de execução refeita sobre o blob novo | uma rodada de implementação antes da execução |
| **B** — E03 publicado, sem `SET LOCAL`, por decisão expressa, com controles operacionais: L1 (`lock_timeout = '0'`, `statement_timeout = '2min'`), L3 sem locks no escopo, E00 `g_no_concurrency`, E03P, FREEZE | sim (A5 "roda sem ele, decisão registrada") | H: E01 e E03T executados assim, sem espera | uma espera por lock (improvável sob FREEZE) só termina em 120 s, com rollback integral; `57014` = NÃO CONFORME | nenhum artefato muda |
| — `SET` de sessão, `set_config` ou `ALTER ROLE` | **não** (configuração de sessão ou persistente) | — | — | rejeitada |

A decisão DP-4 = B aprovada para o E03T **não se transfere** ao E03.

**Deliberação de Fabrício — DP-4 (E03): A** (registrada na v1.1, `BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01`):
- implementar `SET LOCAL lock_timeout = '5s'` como primeira instrução executável do bloco `DO`, depois das declarações;
- verificar a aplicação antes de qualquer mutação;
- provar a não persistência pelo rollback e pelo E99;
- proibidos `SET` persistente, `ALTER ROLE` e alteração de sessão.

**Implementação (v1.1, local):** ver §5.6. O blob do E03 passou de `4866eb97…` a `ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e`.

### 4.3 DP-5 — escritas transitórias do E03

**Escopo exato que uma autorização teria de nomear** (§3): 19 INSERTs em `card_edition_context_trait`; 15 INSERTs de fixture e 11 de sonda em `card_edition_context_profile`; 20 INSERTs em `card_edition_context_profile_trait`; 4 UPDATEs em profile de fixture (`traits_signature` em 2.11–2.13, `name` em 2.14); 1 DELETE em profile_trait de fixture (2.4); 9 selos efetivos e 2 tentativas que falham; 33 subtransações; só as três tabelas EC; `game` só lida. Tudo com rollback obrigatório e verificação posterior (E99 + L3 final).

| Alternativa | Implicação |
|---|---|
| **A** — autorizar exclusivamente as escritas do E03 (v1.0: blob `4866eb97…`; v1.1: blob resultante da DP-4 = A), uma execução, sob mandato próprio | E03 executável quando DP-1 e DP-4 também estiverem decididas e houver mandato |
| **B** — não autorizar | nada vai ao LIVE; L1 parado |

Nenhuma autorização de escrita é presumida. A autorização do E03T está esgotada e não cobre UPDATE, DELETE nem o volume do E03.

**Deliberação de Fabrício — DP-5 (E03): A** (registrada na v1.1, `BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01`):
- aprovada a superfície já inventariada: 65 INSERTs, 4 UPDATEs, 1 DELETE, 9 selos efetivos, 2 tentativas que falham, 33 subtransações, somente as três tabelas Edition Context;
- autorização **restrita ao E03 resultante desta implementação** (blob `ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e`), e só **depois** da auditoria independente e da publicação desse blob e de um mandato operacional específico;
- não amplia o escopo de nenhuma outra execução.

A DP-4 = A acrescentou só o `SET LOCAL` transacional e uma leitura de `current_setting`; nenhuma escrita em tabela foi acrescentada, e a superfície do §3 continua exata.

## 5. Readiness operacional do E03 (proposta; não é autorização)

### 5.1 Condições de entrada do mandato futuro

1. DP-1, DP-4 e DP-5 do E03 decididas e registradas (T-5) — **cumprida na v1.1** (§4).
2. Blob do E03 `ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e` auditado de forma independente e publicado (commit e push por Fabrício); esta readiness e o `static_check` publicados no mesmo baseline.
3. Mandato de execução próprio, com baseline HEAD, citando este documento e a readiness v1.3 pelo blob (T-6).
4. **`MAX_L3_D = 2`** (decisão de Fabrício, v1.1): no máximo duas L3 diagnósticas, só leitura, no fluxo excepcional (§5.3).
5. Canal: MCP Supabase `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`; uma chamada por statement; nunca Dashboard, nunca `apply_migration`.

### 5.2 Identidade e resposta esperada

- Texto submetido no S5 (v1.1): o E03 integral, blob **`ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e`**, md5 `e0aeb7e3dc4143d171cb4364d99069d8`, sha256 `e2949dc65a8215800af05bac209b5745287a755ad9e6a488e2ed00d08ce5215e`, 93.188 B, uma única submissão. O blob `4866eb97…` (v1.0) está superado.
- **Resposta conforme:** SQLSTATE `H283P`; mensagem, não truncada, casando com `^H2830_ROLLBACK_PASS: envelope=E03_SECAO2_COMPOSICAO_PROFILE pass=13/13 casos=2\.1,2\.2,2\.3,2\.4,2\.5,2\.7,2\.8,2\.9,2\.10,2\.11,2\.12,2\.13,2\.14 marker=H2830_[0-9A-F]{32} elapsed_ms=[0-9]+$`; contexto **`PL/pgSQL function inline_code_block line 1703 at RAISE`** (v1.1: RAISE terminal na l. 1767, `DO` na l. 65: 1767 − 65 + 1; a `line 1694` da v1.0 não vale mais); `elapsed_ms` dentro do limite que DP-1 fixar.
- **Falha:** SQLSTATE `H283F`, `H2830_FAIL: envelope=E03_SECAO2_COMPOSICAO_PROFILE caso=<id|PREFLIGHT|GATE> …` (v1.1: `caso=PREFLIGHT lock_timeout=<v> (esperado 5s)` = a asserção P8 falhou, antes de qualquer escrita); mensagem com "sonda" = falha do padrão N-1/sonda (FAIL de harness). Qualquer outro SQLSTATE é falha.
- **Resposta definida** traz SQLSTATE e texto do PostgreSQL, ou retorno sem erro. **Ambígua:** timeout do cliente, perda de conexão, HTTP sem corpo, erro do canal sem texto do PostgreSQL.

### 5.3 Sequência S0–S7

Idêntica à do E03T (readiness v1.3 §4.2; plano do E03T §4), trocando o S5 pelo E03:

| Passo | Chamada | Continua se (todos) |
|---|---|---|
| S0 | local | HEAD = baseline do mandato; árvore e índice limpos; blobs do §1.1 conferidos (E03 `ef24a3be…`); `static_check` 444/88/79/6 (ou os totais do blob publicado); md5 de L1 e L3 |
| S1 | L1 | `transaction_read_only = off`, `default_transaction_read_only = off`, `in_recovery = false`, `lock_timeout = '0'` na **sessão** (o `'5s'` da DP-4 = A existe só dentro da transação do envelope), `statement_timeout = '2min'`, PG ≥ 170000, `standard_conforming_strings = on`, donos EC = `current_user`, visibilidade provada |
| S2 | L3 | `locks_on_scope = []`; nenhuma outra sessão `client backend` ativa ou em transação |
| S3 | E00 | 24/24 gates, `gate_pass = true`, `d_canon_diff = []`; capturar `d_baseline`, `d_baseline_md5`, `db_role_setting_rows`, `checked_at`, `backend_pid` |
| S4 | E03P | 11/11 gates e `gate_pass = true` |
| S5 | **E03** | resposta definida (§5.2) |
| S6 | E99 com os 3 valores do S3 **desta** rodada | aceite do postcheck (readiness v1.3 §4.4) |
| S7 | L3 final, sempre depois do S6 | nenhum lock no escopo; nenhuma sessão ativa ou em transação; nenhum pid da rodada |

- **Fluxo excepcional (resposta ambígua do S5), `MAX_L3_D = 2`:** não reenviar o E03 (nenhum retry); até **duas** L3-D, só leitura e sem outro SQL entre elas; nenhuma delas é postcheck nem equivale ao S7; com encerramento do backend comprovado (readiness v1.3 §4.4), S6 e depois S7; sem confirmação depois da segunda L3-D: nem E99 nem S7, **INCONCLUSIVO**, resíduo não verificado, **STOP**. Sem `pg_terminate_backend`.
- **E99:** gerado só com os três valores do S3 da mesma rodada, na forma literal devolvida pelo canal ("colar, nunca redigitar"); cada marcador substituído exatamente uma vez; md5 do JSON recalculado igual a `d_baseline_md5`; texto difere do blob só nas linhas 56–58; md5 registrado antes de submeter. Nunca baseline de outra rodada, nunca edição manual.

### 5.4 Postcheck, classificação e STOP

- **Postcheck ÍNTEGRO:** E99 completo com os 9 gates `true`, `d_diff = []`, `d_canon_diff = []`, `g_marker_absent = true`, `d_baseline_now_md5 = d_baseline_md5`, **e** S7 completo e limpo. Só então se afirma resíduo zero (readiness v1.3 §4.4).
- **Classificação:** integralmente a da readiness v1.3 §4.4–§5, aplicada ao E03 pelo §6 da mesma readiness: INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME. `H283P` sozinho não é aceite; `pass ≠ 13/13` ou mensagem truncada é INCONCLUSIVO; `elapsed_ms` acima de DP-1 é NÃO CONFORME.
- **Efeito contratual — reconhecimento contratual = SIM (decisão de Fabrício, v1.1):** diferente do E03T, o E03 implementa casos da 2830. Depois de execução **CONFORME**, postcheck **ÍNTEGRO** e **auditoria independente**, o registro pode propor `2.1–2.5, 2.7–2.14 PASS`. A cobertura atual continua **17/135**; **30/135 é só a cobertura potencial**, nunca o resultado atual, até existir registro auditado.
- **STOP:** todos os da readiness v1.3 §4.5 e do plano do E03T §9–§10, mais: blob do E03 diferente de `ef24a3be…` (ou do blob que a auditoria aprovar e for publicado); asserção P8 falha (`caso=PREFLIGHT lock_timeout`); `55P03` em qualquer ponto; decisão T-5 ausente; `statement_timeout ≠ '2min'`; qualquer necessidade de `SET`, alteração de SQL ou de critério; nenhum retry do E03; nenhuma limpeza sem mandato; nenhum avanço automático a outro lote.

### 5.5 Riscos residuais e limitações

| Risco | Tratamento | Evidência |
|---|---|---|
| escrita real no LIVE sob FREEZE, em volume ~6× o do E03T | rollback estrutural (todo caminho termina em exceção) e prova tripla | E; H (E01, E03T) |
| tempo sem medição prévia | DP-1; teto de 120 s | nenhuma medição do E03 |
| espera por lock | DP-4 = A: `lock_timeout` 5 s dentro do envelope (`55P03` ⇒ `H283F` se capturado, SQLSTATE original fora de handler; sempre falha, nunca PASS — §5.7); FREEZE; L3; `g_no_concurrency` | H: E01 e E03T sem espera; R: `SET LOCAL` dentro do `DO` ainda não executado |
| limite L-1 | não demonstrável por SQL; resultado aceito de 2.7 depende só do selo de Pb | readiness de implementação §2.6.4, §2.6.7 |
| 2.7 (IMMEDIATE depois de sonda, erro `23505` em índice) nunca executado | FAIL de harness se divergir; nunca PASS | R |
| `CONSTRAINT_NAME` de violação de índice único = nome do índice | esperado pela documentação; não observado neste harness; divergência = FAIL | R |
| ramos PL/pgSQL de falha nunca percorridos | só verificados estaticamente (C-5) | E |
| nota de contexto: correção do PostgreSQL de 2026-08-19 em `AfterTriggerSetState` (backpatch só até 19; LIVE 17.6) | sondas cobrem o sintoma observável; o E03T não observou o sintoma | readiness de implementação §2.7; H (E03T) |
| canal caixa-preta: sem pid nem horário do erro | fluxo excepcional com L3-D | H |
| resíduo não-transacional | declarado (§3.3) | declarado |

### 5.6 DP-4 = A: implementação e provas distintas (v1.1)

**Diff exato no E03** (além de comentários do cabeçalho): logo depois do `BEGIN` do bloco principal (l. 102), antes do preflight de `game`:

```sql
    SET LOCAL lock_timeout = '5s';
    IF current_setting('lock_timeout') IS DISTINCT FROM '5s' THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT lock_timeout=%s (esperado 5s)', c_env, current_setting('lock_timeout'));
    END IF;
```

- **Posição:** primeira instrução executável (l. 106); a asserção vem em seguida (l. 107–110). Antes dela só há o `DECLARE`, cujos inicializadores (`v_marker`, `v_t0`, `v_qn`) não leem nem escrevem tabela.
- **Semântica (fundamentação estática, R):**
  - dentro de um `DO`, o PL/pgSQL executa o `SET` pelo SPI, isto é, fora do nível superior; o aviso "SET LOCAL só em bloco de transação" não se aplica, e o valor vale até o fim da transação do `DO`;
  - o bloco principal **não tem** `EXCEPTION` (verificado por script: nenhum `EXCEPTION` no nível 1), então o `SET` não fica dentro de subtransação;
  - as subtransações dos casos, sondas e negativos herdam 5 s; o abort de cada uma restaura o valor que vigorava no seu início (5 s);
  - o envelope termina **sempre** em exceção (`H283P`/`H283F`), o que aborta a transação e desfaz o `SET LOCAL`; nada depende de a próxima chamada cair na mesma conexão;
  - estouro de espera ⇒ `55P03`. O resultado observado depende de onde ocorre (§5.7):
    - dentro de caso, sonda ou sub-bloco negativo: capturado pelo handler aplicável e convertido em `H283F` (`H2830_FAIL … sqlstate=55P03 …`, ou, no negativo, `rejeição errada sqlstate=55P03`);
    - fora de handler — no nível superior do bloco, isto é, nas leituras de preflight de `game` antes do primeiro caso: o `55P03` escapa com o **SQLSTATE original**;
    - nos dois casos é falha, exige avaliação fail-closed e nunca permite PASS.
- **Provas, separadas:**

| Prova | O que demonstra | Onde |
|---|---|---|
| asserção interna | o `SET LOCAL` foi aplicado (`current_setting('lock_timeout') = '5s'`) antes de qualquer leitura ou escrita; senão `H283F caso=PREFLIGHT` | S5, dentro do envelope |
| `H283P` | o envelope chegou ao fim (13/13, 11 sondas) e terminou em exceção, com rollback | S5, mensagem terminal |
| E99 | `g_lock_timeout_default` (`lock_timeout = '0'`) e `g_role_setting_unchanged` (nenhuma entrada nova em `pg_db_role_setting`); baseline íntegro | S6 |
| L3 final | nenhum lock no escopo e nenhuma sessão remanescente ativa ou em transação | S7 |

- **Limite:** o E99 roda em outra chamada e pode cair em outro backend. Sozinho, ele prova que a sessão dele está em `'0'` e que não houve configuração persistente por papel ou banco. A não persistência do `SET LOCAL` na conexão do envelope se sustenta na semântica transacional (o `DO` sempre aborta) e na prova estática E03-20; não é observável por SQL em outra conexão.
- **Verificação estática (E03-20 e vetores):** o preâmbulo tem de ser exatamente esse e estar nessa posição; `SET LOCAL` adicional, com outro valor, dentro de caso, depois de uma escrita ou depois do preflight, `SET` de sessão, `SET SESSION`, `set_config`, `ALTER ROLE`, asserção removida, neutralizada, com outro valor, com `<>` ou sem `H283F`, e `SET LOCAL` no E03T são todos rejeitados (23 mutações; E03-PERFIL 88/88, NEG 79/79, POS 6/6).
- **Lógica dos 13 casos:** o texto do bloco principal, do comentário `PREFLIGHT` até o fim, e todo o `DECLARE` são byte a byte iguais aos do blob `4866eb97…` (verificado por script). Casos, fixtures, sondas, contratos de erro, ordem, marcadores e rollback inalterados.

### 5.7 `55P03` e a classificação vigente (v1.2)

| Onde a espera estoura | O que o canal devolve | Classificação da resposta (readiness v1.3 §4.5) |
|---|---|---|
| dentro de caso (subtransação), inclusive `SET CONSTRAINTS … IMMEDIATE` e INSERT/UPDATE/DELETE de fixture | `H283F` (`caso=<id> erro inesperado sqlstate=55P03 …`) | linha `H283F` ⇒ **NÃO CONFORME**, E99 imediato, L3, STOP, sem retry |
| dentro de sonda | `H283F` (`sonda n=… modo não DEFERRED ou erro inesperado sqlstate=55P03 …`) | idem |
| dentro de sub-bloco negativo | `H283F` (`rejeição errada sqlstate=55P03 …`) | idem |
| fora de handler (nível superior: leituras de preflight de `game`) | SQLSTATE original `55P03` | linha "outro SQLSTATE, `57014`, `55P03`, `25006`" ⇒ **NÃO CONFORME**, E99 imediato, L3, STOP |

- **Nenhuma classe nova.** O protocolo vigente já distingue o resultado final pela integridade do postcheck, pela regra "vale a mais grave aplicável" (readiness v1.3 §4.5): falha com postcheck **ÍNTEGRO** = **NÃO CONFORME**; E99 com `d_diff ≠ []`, marcador presente ou violação do FREEZE = **INCIDENTE**; postcheck **NÃO CONCLUÍDO** = **INCONCLUSIVO**. Isso vale igualmente para `H283F` e para o `55P03` original.
- **Texto do cabeçalho do SQL:** o comentário do E03 diz "Espera de lock > 5s ⇒ 55P03 ⇒ H2830_FAIL (nunca PASS)". Ele é exato para esperas dentro dos casos, mas simplifica o caso do preflight, em que o SQLSTATE sai original. É só comentário, sem efeito executável; esta tabela prevalece. O SQL não é alterado nesta rodada (mandato só documental).

## 6. Questões para deliberação expressa de Fabrício

Respondidas por Fabrício e registradas na v1.1 (histórico da v1.0 no Revision History):

1. **DP-1 (E03): A** — AD-2 específica, teto 120 s, aceite `elapsed_ms ≤ 60000` (§4.1).
2. **DP-4 (E03): A** — `SET LOCAL lock_timeout = '5s'` implementado (§4.2, §5.6).
3. **DP-5 (E03): A** — superfície do §4.3, restrita ao novo blob e condicionada à auditoria, publicação e mandato.
4. **`MAX_L3_D = 2`** (§5.3).
5. **Reconhecimento contratual = SIM** — proposta de PASS dos 13 casos só depois de CONFORME, postcheck ÍNTEGRO e auditoria (§5.4).

Pendente: auditoria independente do novo blob, publicação e mandato de execução (T-6).

## 7. Limites desta rodada

- **HISTÓRICO (v1.0):** nenhum envelope ou documento anterior alterado; nenhuma decisão tomada.
- **Vigente (v1.1/v1.2):** decisões registradas (§4); E03, `static_check` e readiness de implementação alterados localmente pela DP-4 = A; a v1.2 só corrige documentação. Contagens do §3 vêm da leitura estática do blob.
- Em todas as versões: nenhum SQL, nenhum LIVE; nenhum PASS; cobertura **17/135**; E03 **não autorizado**. **FREEZE ATIVO.**

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L1-E03-EXECUTION-READINESS-01`, baseline `a83f539e`), documental, sem SQL e sem LIVE.**<br>• gate inicial: HEAD, árvore e índice limpos, blobs, modo 100644 e blob `eaffdb27…` do registro do E03T;<br>• T-1 a T-6: T-1–T-4 cumpridas (T-4 atualizada sem apagar o histórico), T-5 pendente, T-6 inexistente; limite L-1 preservado; `elapsed_ms = 133` não representativo;<br>• inventário da superfície de escrita do E03 por caso, extraído do blob `4866eb97…`;<br>• matrizes DP-1, DP-4 e DP-5 do E03 com campos em branco;<br>• readiness operacional S0–S7, resposta esperada (contexto `line 1694`), fluxo excepcional, E99, classificação por referência à readiness v1.3, STOP e riscos. Nenhuma decisão tomada. FREEZE ATIVO. |
| 1.1 | **Decisões e DP-4 = A (2026-09-27, `BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01`, baseline `aeeed59a`), local, sem SQL e sem LIVE.**<br>• §4: DP-1 = A, DP-4 = A e DP-5 = A registradas para o E03; `MAX_L3_D = 2`; reconhecimento contratual = SIM (30/135 só potencial; 17/135 atual);<br>• §1.1, §5.2: novo blob do E03 `ef24a3be…` (preâmbulo `SET LOCAL lock_timeout = '5s'` + asserção), contexto `line 1703`; `static_check` 444/88/79/6;<br>• §2: T-5 decidida; T-6 inexistente;<br>• §3.1: linhas recalculadas no novo blob; contagens inalteradas;<br>• §5.3: fluxo excepcional com até 2 L3-D; §5.6 novo: implementação, semântica e provas separadas (asserção, `H283P`, E99, L3 final).<br>Classificação fail-closed inalterada. E03 não executado e não autorizado. FREEZE ATIVO. |
| 1.2 | **Correção documental da auditoria da DP-4 = A (2026-09-27, `BATCH12-2830-P5-L1-E03-DP4A-AUDIT-CORRECTION-01`, baseline `aeeed59a`), sem SQL e sem LIVE.**<br>• D-1: §3.3 separa garantias vigentes (E03-20 autoriza só o preâmbulo P8; nenhum outro `SET LOCAL`; 88/88, 79/79, 6/6) e históricas da v1.0 (85/85, 56/56, 4/4);<br>• D-2: textos da v1.0 que diziam E03 sem `SET LOCAL` ou decisões pendentes marcados como HISTÓRICO (Natureza, §4, §4.2, §7), com alternativas e deliberação preservadas;<br>• D-3: `55P03` corrigido (§5.6, §5.5, §3.3) e novo §5.7: `H283F` quando capturado, SQLSTATE original fora de handler; ambos falha, fail-closed, nunca PASS; NÃO CONFORME × INCIDENTE × INCONCLUSIVO pela integridade do postcheck, sem classe nova.<br>E03 (`ef24a3be…`), `static_check` (`79c4fd42…`) e 2830 inalterados. FREEZE ATIVO. |
