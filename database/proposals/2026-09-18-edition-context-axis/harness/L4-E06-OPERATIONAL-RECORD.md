# L4 · E06P + E06 — Registro operacional compacto (Seção 3, sem 3.3)

| Campo | Valor |
|---|---|
| **Documento** | Readiness + registro operacional do lote L4 (routing fail-closed da 2211) para uma FUTURA execução LIVE |
| **Versão** | 1.0 |
| **Status** | IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no PostgreSQL. Aguarda auditoria independente e mandato próprio de execução. |
| **Mandato** | BATCH12-2830-P5-L3-CLOSEOUT-AND-L4-IMPLEMENTATION-01 (baseline Git `89736a60`) |
| **Contrato** | `2830_validate_edition_context_foundation.sql` v7.0, blob `b4647dcb…`, l. 539–551 (inalterado); matriz `PHASE5-AUTOMATED-COVERAGE-READINESS.md` (L4 = 3.1, 3.2, 3.4–3.7; 3.3 no L5) |
| **Decisões vigentes** | D-2 = C (AD-2: `elapsed_ms ≤ 60000` operacional), DP-2 = B (3.3 no L5), DP-3 = C (E00 + precheck do lote), DP-4 = A (preâmbulo P8), DP-5 = B (tier R1) |

## 1. Artefatos

| Artefato | Blob | md5 | Bytes / linhas |
|---|---|---|---|
| `2830H_E06P_precheck_section3.sql` | `486e3035d8a966c610633aa11d00f4ac03d5e75b` | `0082e75bf4a9cf34f489ca1fea5dc40f` | 23.197 / 337 |
| `2830H_E06_section3_routing_fail_closed.sql` | `33079480a70aec97a513f052c1ac18f763de34b9` | `9f60c532c972bd29df30d9e0f194fb8d` | 56.403 / 885 |
| `tools/static_check.py` (baseline `6a44ee7a…` + perfil E06 aditivo, +337 linhas) | `574d7927565479770631fd7cd3fab3175a480a8a` | — | 2.239 linhas |

Reutilizados sem alteração: E00 `a4dd8438…`, E99 `49a71ecb…`, L1/L3 do runbook. E03, E04, E05, seus prechecks e a 2830 intactos (conferido pelo `static_check`). Contexto terminal esperado do E06: `PL/pgSQL function inline_code_block line 807 at RAISE` (o `DO` está na linha 74 do arquivo e o RAISE `H283P` na linha 880 ⇒ linha 807 do corpo).

## 2. Sequência de uma futura execução (uma chamada por statement, conferência integral entre elas)

| Passo | Texto | Aceite | Falha |
|---|---|---|---|
| S0 | preflight local: HEAD, blobs do §1, `static_check` 444 · 88/79/6 · 65/94/7 · 58/54/6 · 64/54/6 | tudo igual | STOP |
| S1 | L1 | gravável, `statement_timeout=2min`, `lock_timeout=0`, visibilidade | STOP |
| S2 | L3 | sem locks no escopo; nenhuma sessão em transação | STOP |
| S3 | E00 | 24/24, `gate_pass=true`, `d_canon_diff=[]` | STOP |
| S4 | E06P | 20/20, `gate_pass=true` (inclui `g_rc_identity` com a 2192, `g_35_candidate`, `g_37_h2`, `g_37_scope_resolvable`, `g_37_profile`, `g_37_no_printing`, `g_37_out_of_scope_control`) | STOP — não submeter E06 |
| S5 | E06 (submissão única) | `H283P`, `H2830_ROLLBACK_PASS: envelope=E06_SECAO3_ROUTING_FAIL_CLOSED pass=6/6 casos=3.1,3.2,3.4,3.5,3.6,3.7 marker=H2830_<32 hex> elapsed_ms≤60000 c35_token=<token> c35_overlap=<bool> u37=3`, CONTEXT `line 807`; `c35_token` = candidato do E06P (`d_35_candidate`) | `H283F`/`55P03`/`57014`/ambíguo ≠ PASS; sem retry |
| S6 | E99 com os 3 valores do S3 desta rodada | 9/9, `d_diff=[]`; contagens de trait e mapping iguais às do E00 | classificação conforme protocolo |
| S7 | L3 final, só depois de conferir o S6 | limpa | idem |

## 3. Matriz caso → operação → aceite → rollback

| Caso | Classe | Operação | Aceite | Rollback |
|---|---|---|---|---|
| 3.1 | RC | tokens marcados (subtype + 2 stamps) SEM mapping algum (EC e Printing, provado no caso); 2211 sem escopo e com Set de fixture | Printing `RESOLVED_NO_PRINTING`; EC `RESOLVED_NO_EDITION_CONTEXT`, sem trait/profile; residual de subtype = token; residual de stamp = os 2 tokens ordenados | nada escrito; H283C |
| 3.2 | FX+RC | trait T1 + mapping GLOBAL + N:N; 2211 com mapping ATIVO (controle); `UPDATE is_active = false` só em M1 (ROW_COUNT 1, identidade reconferida); 2211 de novo | controle: EC `NEEDS_REVIEW_NO_EC_PROFILE` com `[T1]`, token consumido; aposentado: EC `NEEDS_REVIEW_INACTIVE_EC_MAPPING`, sem trait/profile, token no residual | H283C |
| 3.4 | FX+RC | T1/T2/T3; GLOBAL [T1], SCOPED S1 [T2], SCOPED S2 [T3] do mesmo token; 2211 em S1, S2, S3 e sem escopo; 2º ativo SCOPED em S1 | S1 → `[T2]`, S2 → `[T3]`, S3 → `[T1]`, sem escopo → `[T1]` (sempre UM mapping); 23505 `uq_cecem_active_scoped`; S1 → `[T2]` de novo | H283C |
| 3.5 | RC | candidato real de Printing (E06P = E06); 2211 sem escopo | Printing `RESOLVED_WITH_PROFILE` (profile e traits do candidato); EC `RESOLVED_NO_EDITION_CONTEXT`, sem trait; residual vazio | nada escrito; H283C |
| 3.6 | FX | controle: mapping `raw_field='stamp'` aceito; `raw_field='type'` | 23514 `ck_cecem_raw_field`; 1 linha com o token (só o controle) | evento pendente descartado pelo H283C |
| 3.7 | RC | universo H2 = 3 (SET-LOGO só em dp1/swsh9/svp, nenhum GLOBAL); para cada Set: `card_set_external_reference` ativa → `resolve_variant_mapping_scope` → 2211 com raw `'set-logo'`; controle com Card Set real fora dos três e sem escopo | nos três: EC `RESOLVED_WITH_EC_PROFILE` com o profile ativo da assinatura do mapping; fora/sem escopo: `RESOLVED_NO_EDITION_CONTEXT`, `SET-LOGO` no residual de stamp | nada escrito; H283C |

Todo caminho do `DO` termina em exceção (H283P ou H283F): rollback estrutural integral.

## 4. Superfície de escrita (tier R1)

| Tabela | INSERT | UPDATE | DELETE |
|---|---|---|---|
| `card_edition_context_trait` | 4 (3.2: 1; 3.4: 3; `code`/`name` com marcador) | 0 | 0 |
| `card_edition_context_external_mapping` | 7 tentativas: 3.2: 1; 3.4: 3 + 1 recusada (23505); 3.6: 1 + 1 recusada (23514). Token e Sets sempre com marcador | 1 (3.2, `WHERE id = v_m1 AND normalized_token = v_tok`) | 0 |
| `card_edition_context_external_mapping_trait` | 4 (3.2: 1; 3.4: 3) | 0 | 0 |

Leitura sem escrita: `card_printing_*` (3.1 e 3.5), `card_edition_context_profile` (3.7), `card_set_external_reference` (3.7). Sem LOOP, sem `SET CONSTRAINTS`, sem sonda (não há caso FXd no L4). Nenhuma linha pré-existente é alvo de escrita; ids de fixture só por `RETURNING INTO`.

## 5. Leitura dos casos (literal do contrato + 2211 pinada)

- **3.1** cobre o token SEM nenhum mapping. O token com mapping só inativo NÃO volta ao residual (2211 v1.1, achado A3; contrato R11) e é exatamente o 3.2.
- **3.4** "sem desempate": o desempate por `m.id` da 2211 é inalcançável porque os índices parciais da 2207 impedem dois ativos no mesmo (escopo, token); o caso prova a recusa (23505) e que o resultado não muda.
- **3.5** usa dado real (RC). Para não ser vácuo, a seleção prefere token que também tem mapping EC GLOBAL ativo; `c35_overlap` informa se isso ocorreu. A asserção (token fora do residual e EC sem trait) vale nos dois casos.
- **3.6** é redundante com 1.9 (declarado no contrato); mantido.
- **3.7**: o escopo vem da autoridade 2192 a partir do Card Set real, nunca de `card_set.code` (contrato da 2211). Escopo não resolvível ⇒ `INTO STRICT` falha ⇒ H283F (STOP, PHASE5).

## 6. Limitações declaradas

- Sem PostgreSQL local: E06/E06P não foram compilados. As provas são estáticas (perfil E06 do `static_check`); erro de sintaxe só aparece no primeiro E06P/E06 real e resulta em STOP, nunca em PASS. Nesta rodada o perfil ganhou a regra de mensagem bem formada (E06-16) depois de um defeito real de aspas encontrado e corrigido antes da entrega.
- A identidade da 2192 (`internal.resolve_variant_mapping_scope`) NÃO foi demonstrada no LIVE: o E06P usa o pino do corpo canônico (`database/schema/2192`, md5 LF `21a57ebf…`). Divergência ⇒ STOP para adjudicação.
- 3.5 e 3.7 dependem de dados reais sob FREEZE (candidato de Printing; H2; referências de Set; profiles de EC). Os gates do E06P tornam qualquer ausência um STOP antes do E06.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L3-CLOSEOUT-AND-L4-IMPLEMENTATION-01`, baseline `89736a60`).** Readiness e registro operacional do L4 (E06P + E06, 3.1, 3.2, 3.4–3.7), produzidos junto da implementação local. Nada executado. FREEZE ATIVO. |
