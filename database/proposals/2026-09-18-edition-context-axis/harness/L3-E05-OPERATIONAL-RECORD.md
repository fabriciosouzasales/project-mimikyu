# L3 · E05P + E05 — Registro operacional compacto (Seção 2-QUATER)

| Campo | Valor |
|---|---|
| **Documento** | Readiness + registro operacional do lote L3 (lifecycle do cabeçalho do external mapping) para uma FUTURA execução LIVE |
| **Versão** | 1.0 |
| **Status** | IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no PostgreSQL. Aguarda auditoria independente e mandato próprio de execução. |
| **Mandato** | BATCH12-2830-P5-L2-CLOSEOUT-AND-L3-IMPLEMENTATION-01 (baseline Git `8e13354f`) |
| **Contrato** | `2830_validate_edition_context_foundation.sql` v7.0, blob `b4647dcb…`, l. 518–537 (inalterado) |
| **Decisões vigentes** | D-2 = C (AD-2: `elapsed_ms ≤ 60000` operacional), DP-2 = B, DP-3 = C (E00 + precheck do lote), DP-4 = A (preâmbulo P8), DP-5 = B (tier R1) |

## 1. Artefatos

| Artefato | Blob | md5 | Bytes / linhas |
|---|---|---|---|
| `2830H_E05P_precheck_section2q.sql` | `e5c27a569ab96937811b55bed4cfba39b85e9e1d` | `f27cde7c67c649668cffa74a5ce66f27` | 17.539 / 244 |
| `2830H_E05_section2q_mapping_header.sql` | `03a9ff029e38779338c308a847b4e3a26a773b44` | `1625ada6431e2a6246e136c84a5b5559` | 79.252 / 1.366 |
| `tools/static_check.py` (baseline `008c9788…` + perfil E05 aditivo, +303 linhas) | `6a44ee7aa12778f0e676c1598525c03e125dfc83` | — | 1.902 linhas |

Reutilizados sem alteração: E00 `a4dd8438…`, E99 `49a71ecb…`, L1/L3 do runbook. E03, E04 e a 2830 intactos (conferido pelo `static_check`). Contexto terminal esperado do E05: `PL/pgSQL function inline_code_block line 1302 at RAISE` (o `DO` está na linha 60 do arquivo e o RAISE `H283P` na linha 1361 ⇒ linha 1302 do corpo).

## 2. Sequência de uma futura execução (uma chamada por statement, conferência integral entre elas)

| Passo | Texto | Aceite | Falha |
|---|---|---|---|
| S0 | preflight local: HEAD, blobs do §1, `static_check` 444 · 88/79/6 · 65/94/7 · 58/54/6 | tudo igual | STOP |
| S1 | L1 | gravável, `statement_timeout=2min`, `lock_timeout=0`, visibilidade | STOP |
| S2 | L3 | sem locks no escopo; nenhuma sessão em transação | STOP |
| S3 | E00 | 24/24, `gate_pass=true`, `d_canon_diff=[]` | STOP |
| S4 | E05P | 14/14, `gate_pass=true` (inclui `g_n3_normalization` e `g_marker_absent_now`) | STOP — não submeter E05 |
| S5 | E05 (submissão única) | `H283P`, `H2830_ROLLBACK_PASS: envelope=E05_SECAO2Q_MAPPING_HEADER pass=10/10 casos=2Q.1,…,2Q.10 marker=H2830_<32 hex> elapsed_ms≤60000`, CONTEXT `line 1302` | `H283F`/`55P03`/`57014`/ambíguo ≠ PASS; sem retry |
| S6 | E99 com os 3 valores do S3 desta rodada | 9/9, `d_diff=[]` | classificação conforme protocolo |
| S7 | L3 final, só depois de conferir o S6 | limpa | idem |

## 3. Matriz caso → operação → aceite → rollback

| Caso | Classe | Operação | Aceite | Rollback |
|---|---|---|---|---|
| 2Q.1 | FXd | M1 GLOBAL selado [T1] (IMMEDIATE + sonda); `UPDATE normalized_token = v_tok || '_X'` | P0001 `EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE:`; identidade + selo intactos | H283C |
| 2Q.2 | FXd | idem; `UPDATE external_set_id = v_set1` (GLOBAL → SCOPED de fixture) | idem | H283C |
| 2Q.3 | FXd | M1 com `raw_field='stamp'`; `UPDATE raw_field = 'subtype'` | idem | H283C |
| 2Q.4 | FXd | idem; `UPDATE game_id = c_nil` e, em outro sub-bloco, `UPDATE asset_source_id = c_nil` | 2× IDENTITY_IMMUTABLE (o guard BEFORE ROW recusa antes da FK) | H283C |
| 2Q.5 | FXd | `UPDATE is_active = false` | ROW_COUNT 1; `is_active=false`; identidade + selo intactos | H283C |
| 2Q.6 | FXd | aposenta M1; confirma 0 ativos no token; `UPDATE is_active = true` | P0001 `EDITION_CONTEXT_MAPPING_REACTIVATION_FORBIDDEN:`; continua `false` | H283C |
| 2Q.7 | FXd | `is_active = true` (TRUE→TRUE), `= false`, `= false` (FALSE→FALSE) | 3× ROW_COUNT 1 sem erro; valores e identidade conferidos | H283C |
| 2Q.8 | FX | guarda de colisão no escopo `v_set1`; INSERT `'set-logo'`, `'Pokébola'`, `'BLUE  BORDER'` SCOPED em `v_set1` | persistem `SET-LOGO`, `POKEBOLA`, `BLUE BORDER`; 3 linhas no escopo | evento pendente descartado pelo H283C |
| 2Q.9 | FX | INSERT token `'   '` em `v_set1` | P0001 `EDITION_CONTEXT_MAPPING_EMPTY_TOKEN:`; 0 linhas | sub-bloco + H283C |
| 2Q.10 | FX | guarda de colisão no token `v_tok`; INSERT com `external_set_id = '  dp1  '` | persiste `dp1` (só aparado, nunca `DP1`) | H283C |

Todo caminho do `DO` termina em exceção (H283P ou H283F): rollback estrutural integral.

## 4. Superfície de escrita (tier R1)

| Tabela | INSERT | UPDATE | DELETE |
|---|---|---|---|
| `card_edition_context_trait` | 7 (2Q.1–2Q.7; `code`/`name` com marcador) | 0 | 0 |
| `card_edition_context_external_mapping` | 19: 7 M1 (token marcado, GLOBAL) + 7 sondas + 3 literais N-3 (2Q.8) + 1 tentativa recusada (2Q.9) + 1 (2Q.10) | 11, só em M1 (`WHERE id = v_m1 AND normalized_token = v_tok`): 6 recusados + 5 aceitos (`is_active`) | 0 |
| `card_edition_context_external_mapping_trait` | 7 (M1 × T1 de fixture) | 0 | 0 |

Sem LOOP: superfície estática. Depois de cada um dos 11 UPDATEs a identidade integral e o selo de M1 são reconferidos (regra E05-22). Nenhuma linha pré-existente é lida como alvo de escrita; ids só por `RETURNING INTO`.

## 5. N-3 — tokens literais sem marcador

- **2Q.8:** os três literais vivem em escopo SCOPED no Set `v_marker || '_S1'`. A chave de `uq_cecem_active_scoped` inclui `external_set_id` ⇒ disjunta de todo mapping LIVE (inclusive dos `SET-LOGO` reais de dp1/swsh9/svp). Guarda no envelope: qualquer linha já existente nesse escopo ⇒ `H2830_FAIL` (STOP).
- **2Q.10:** Set literal `'  dp1  '` com token marcado ⇒ chave disjunta. Guarda: qualquer linha já existente com o token ⇒ STOP.
- **Resíduo:** as linhas de 2Q.8 não têm marcador em `normalized_token` (onde o E99 procura). A prova de resíduo zero é a **contagem** (`g_baseline_equal` do E99, chave `mapping` = 122) somada ao gate do E05P/E00 sobre marcador em token **e** em `external_set_id`.
- **E05P:** `g_n3_normalization` executa a própria função pinada (2095) sobre os literais do contrato antes de qualquer escrita; `d_n3_live` informa quantos mappings LIVE usam os literais e o Set `dp1` (sem gate: as chaves são disjuntas por construção).

## 6. Limitações declaradas

- Sem PostgreSQL local: E05/E05P não foram compilados. As provas são estáticas (perfil E05 do `static_check`); erro de sintaxe só aparece no primeiro E05P/E05 real e resulta em STOP, nunca em PASS. Mitigação: E05 reutiliza literalmente os blocos já compilados e executados no LIVE pelo E04 (sonda, handlers, preâmbulo P8, estrutura de caso).
- `c_nil` nunca é gravado: o guard BEFORE ROW da 2207 recusa antes; se o PostgreSQL avaliasse a FK antes do trigger, o erro seria 23503 ⇒ H2830_FAIL (nunca PASS).

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L2-CLOSEOUT-AND-L3-IMPLEMENTATION-01`, baseline `8e13354f`).** Readiness e registro operacional do L3 (E05P + E05, 2Q.1–2Q.10), produzidos junto da implementação local. Nada executado. FREEZE ATIVO. |
