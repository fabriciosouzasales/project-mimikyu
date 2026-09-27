# 2830H — Fase 5: readiness da cobertura automática (135 posições)

| Campo | Valor |
|---|---|
| **Natureza** | Auditoria e planejamento documental. **Sem execução**: nenhum SQL, nenhum acesso ao LIVE, nenhuma alteração em schema, migrations, funções, validações ou envelopes. |
| **Mandato** | `BATCH12-2830-PHASE5-AUTOMATED-COVERAGE-READINESS-01`. Baseline HEAD `0ec2f5dc1d0e6a4f1aaba9b7edfd1f9b3e7ca9a2`. |
| **Autoridade** | 2830 v7.0, blob `b4647dcb59432405c8157e2733fd78678f35540e` (imutável). Protocolo `LIVE-VALIDATION-PROTOCOL.md` (blob `abe806d6…`) como regra operacional das etapas LIVE. |
| **Estado** | **PROPOSTA — para auditoria independente.** Cobertura automática LIVE publicada: **17/135** (Seção 1 e D1–D5). Restam **118**. Nenhum lote foi implementado nem autorizado. 6.1/6.2 não adjudicados; P9A-05 e P9b não executados. **FREEZE ATIVO.** |
| **Papéis** | **Claude**: auditoria e planejamento. **ChatGPT**: auditoria independente. **Fabrício**: decisões, autorizações, commit e push. |

---

## 0. Resultado dos gates e STOP

| Gate | Resultado |
|---|---|
| **A** — baseline e integridade | **Conforme.** HEAD, árvore, contrato, envelopes e registros conferem (§1). Achados documentais O-1 a O-4, sem efeito sobre segurança, integridade, semântica, concorrência, desempenho ou identidade contratual. |
| **B** — matriz 135 | **Conforme.** 135 posições automáticas extraídas do texto da 2830, distintas, na ordem contratual; 17 PASS publicados + 118 restantes (§2, §3). |
| **C** — inventário | Envelopes E00/E01/E02/E99 reaproveitáveis sem alteração; faltam 13 envelopes e 6 componentes de infraestrutura (§4). |
| **D** — DAG e lotes | 13 lotes em ordem contratual, com um desvio declarado (2.6 e 3.3) (§5). |
| **E** — validação 960 | Divergência confirmada e delimitada. Nenhum dos 135 casos depende da 960 (§6). |
| **F** — primeiro lote | L1 (Seção 2 sem 2.6, 13 casos) especificado caso a caso (§7). |

**STOP: não houve.** Nenhuma divergência encontrada afeta segurança, integridade, semântica, concorrência, desempenho ou identidade contratual. As decisões que dependem de Fabrício estão em §8.

## 1. Gate A — baseline e integridade

| Item | Verificação | Resultado |
|---|---|---|
| HEAD | `git rev-parse HEAD` | `0ec2f5dc1d0e6a4f1aaba9b7edfd1f9b3e7ca9a2` = baseline do mandato |
| Árvore | `git status --porcelain --untracked-files=all` | 0 linhas antes desta rodada |
| Contrato 2830 v7.0 | `git hash-object` = `HEAD:` | `b4647dcb…` |
| E00 | idem | `a4dd8438…` (md5 `45b6c35c…`) |
| E01 | idem | `c4118b8c…` (md5 `a6683376…`, o executado na Etapa 3) |
| E02 | idem | `3357ed46…` (md5 `c7c93dc1…`, o executado na Etapa 2) |
| E99 | idem | `49a71ecb…` |
| `tools/static_check.py` | idem + execução local | `37815450…`; **444/444 PASS** |
| Registro da Etapa 2 | `LIVE-STAGE2-EXECUTION-RECORD.md` `4ec35e78…` | `H283P` · `pass=5/5 casos=D1,D2,D3,D4,D5 elapsed_ms=20` · E99 `gate_pass = true`, `d_diff = []` (l. 7, 31, 310) |
| Registro da Etapa 3 | `LIVE-STAGE3-EXECUTION-RECORD.md` `974674f9…` | `H283P` · `pass=12/12 casos=1.1,…,1.12` · marcador `H2830_402EEFCD…` · `elapsed_ms=251` · E99 limpo (l. 8, 34, 371) |
| Registro da Etapa 1 | `LIVE-STAGE1-EXECUTION-RECORD.md` | nenhum PASS de caso (por definição do protocolo §3) |
| Adjudicação 6.2 | `INDEX-6.2-ADJUDICATION-READINESS.md` v1.1 `40be237c…` | publicada; nenhuma alternativa aprovada |

**Cobertura registrada:** 17 casos, e só 17: D1–D5 (Etapa 2) e 1.1–1.12 (Etapa 3). P9a básico (E00/E99 `REGISTRADO`) não é caso automático e não entra na contagem.

**Achados documentais (sem STOP; nada foi alterado):**

| # | Onde | Achado | Efeito |
|---|---|---|---|
| O-1 | `LIVE-VALIDATION-PROTOCOL.md`, cabeçalho (l. 6) | diz "v1.6 incorporada LOCALMENTE, não commitada", mas a versão está publicada | status desatualizado; o conteúdo normativo não muda |
| O-2 | `EXECUTION-BATCHES.md`, Batch 12 (l. 1255–1262) | diz que o harness executável "não foi escrito: NÃO INICIADA / NÃO AUTORIZADA" | desatualizado: E00/E01/E02/E99 existem e 17 casos passaram |
| O-3 | `2832`/`2833`, cabeçalhos | dizem "NÃO EXECUTADA", enquanto a 2830 (l. 748, 805) e o EXECUTION-BATCHES (l. 660–661) registram 14/14 e 11/11 no Batch 6 | não afeta a Fase 5: nenhum resultado do Batch 6 conta nos 135; o Batch 12 reempacota os casos (§4) |
| O-4 | cabeçalhos do E00 (l. 4–5), E01 (l. 4) e E99 (l. 4) | dizem "NÃO EXECUTADO"; os envelopes já rodaram no LIVE | os blobs são pinados; o estado vale pelos registros de execução, não pelo comentário |
| — | `database/validations/960_validate_card_variant.sql` | divergência S2 | analisada no §6 |

## 2. Gate B — matriz de rastreabilidade 135/135

**Extração reprodutível.** Linhas 428–992 da 2830 v7.0; regex `^--\s{2,}(ID)\s+\[(TAG)\]`; conta-se o ID quando `TAG` começa por `AUTO`. Resultado: **135 IDs distintos**, na mesma ordem desta matriz. Os demais IDs com tag ficam **fora do denominador**:
- MANUAL: K1, K2 (com K2.c = K3-B e K2.d = K4-B), K8b, 6.1, 6.2, 6.3;
- HIST: D6, D7, D8;
- requisitos da 2213: K5, K6, K7, 5.4, 5.5 (→ L5–L9).

L1–L4 da Seção L não têm tag e também ficam fora.

**Estados usados:**
- **PASS-LIVE** — executado no LIVE com evidência publicada;
- **PARCIAL** — existe no repositório código de prova do próprio caso, reaproveitável, mas nenhum envelope P2;
- **NÃO-IMPL** — nenhum código do caso.

Não houve caso "implementado sem execução": não há envelope escrito e não executado.

**Colunas abreviadas:**
- **Fixture:** `—` sem escrita; `EC` tabelas Edition Context; `FXd` com trigger DEFERRED forçado (P4); `Game` Game sentinela; `CV` `card_variant`; `JOB+ROW` job e rows de staging.
- **Risco operacional:** `B` baixo, `M` médio, `A` alto.
- **Próximo mandato:** lote do §5, sempre com readiness própria, implementação, auditoria e mandato de execução separados.

#### Seção 1

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `1.1` | RO | 5 tabelas EC existem | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | — | B | — (concluído) |
| `1.2` | RO | trait: 11 entradas em pg_constraint | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | — | B | — (concluído) |
| `1.3` | FX | ck_cect_code_family_prefix rejeita DECK_PLAYER sem prefixo (23514) | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | EC | B | — (concluído) |
| `1.4` | RO+FX | uq_cect_game_family_order por família; 23505 na mesma família | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | EC | B | — (concluído) |
| `1.5` | RO | uq_cecp_game_signature existe e é parcial | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | — | B | — (concluído) |
| `1.6` | FX | ck_cecp_signature_not_empty rejeita '{}' | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | EC | B | — (concluído) |
| `1.7` | FX | ck_cecp_signature_shape rejeita array 2-D | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | EC | B | — (concluído) |
| `1.8` | RO | N:N com as duas FKs compostas (same-Game) | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | — | B | — (concluído) |
| `1.9` | FX | ck_cecem_raw_field rejeita 'type' e 'size' | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | EC | B | — (concluído) |
| `1.10` | FX+RO | ck_cecem_raw_field rejeita 'foil'; ck_cecem_foil_allowlist ausente | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | EC | B | — (concluído) |
| `1.11` | RO | uq_cecem_active_global/_scoped disjuntos e parciais; ix_cecem_token total | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | — | B | — (concluído) |
| `1.12` | RO | grants: anon nenhum; authenticated só SELECT | E00 `gate_pass` | PASS-LIVE | E01 `c4118b8c…` | H283P `pass=12/12` + E99 limpo (Etapa 3) | — | B | — (concluído) |

#### Seção 2

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `2.1` | FXd | selo = ARRAY(N:N ORDER BY trait_id) após IMMEDIATE | P4 | NÃO-IMPL | — | efeito: selo NOT NULL = esperado | EC FXd | B | L1 |
| `2.2` | FXd | profile sem N:N ⇒ EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION no IMMEDIATE | P4 | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L1 |
| `2.3` | FXd | 2º INSERT na N:N de profile selado ⇒ COMPOSITION_IMMUTABLE | P4; trait diferente (reinserção idêntica passa pelo guard) | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L1 |
| `2.4` | FXd | DELETE na N:N de profile selado ⇒ COMPOSITION_IMMUTABLE | P4; DELETE só em linha de fixture | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L1 |
| `2.5` | FX | trait inativo (fixture) ⇒ TRAIT_INACTIVE | — | NÃO-IMPL | — | P0001 + prefixo | EC | B | L1 |
| `2.6` | FX | trait de outro Game (Game fixture) ⇒ 23503 FK composta | Game sentinela (P5); `game` no escopo de E00/E99 | NÃO-IMPL | — | 23503 + constraint | Game+EC | M | L5 |
| `2.7` | FXd | dois profiles com a mesma assinatura ⇒ uq_cecp_game_signature (23505) | P4 | NÃO-IMPL | — | 23505 + constraint | EC FXd | B | L1 |
| `2.8` | FX | assinatura NULL não colide (índice parcial) | — | NÃO-IMPL | — | efeito: 2 profiles NULL coexistem | EC | B | L1 |
| `2.9` | FXd | N:N em ordem decrescente ⇒ selo ascendente | P4 | NÃO-IMPL | — | efeito: selo ordenado | EC FXd | B | L1 |
| `2.10` | FXd | repetição na N:N ⇒ PK (23505) e cardinality(selo) = COUNT(N:N) | P4 | NÃO-IMPL | — | 23505 + constraint; efeito | EC FXd | B | L1 |
| `2.11` | FX | UPDATE falsificando selo em montagem ⇒ EDITION_CONTEXT_SIGNATURE_MISMATCH | UPDATE só em fixture | NÃO-IMPL | — | P0001 + prefixo | EC | B | L1 |
| `2.12` | FXd | UPDATE alterando selo gravado ⇒ EDITION_CONTEXT_SIGNATURE_IMMUTABLE | P4 | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L1 |
| `2.13` | FXd | UPDATE voltando selo a NULL ⇒ EDITION_CONTEXT_SIGNATURE_IMMUTABLE | P4 | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L1 |
| `2.14` | FXd | UPDATE sem tocar o selo (ex.: name) em fixture selada é permitido; nunca profile real | P4 | NÃO-IMPL | — | efeito: name alterado, selo intacto | EC FXd | B | L1 |

#### Seção 2-BIS

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `2B.1` | FXd | selo do mapping = ARRAY(N:N ORDER BY trait_id) | P4 (trg_cecem_seal) | NÃO-IMPL | — | efeito: selo | EC FXd | B | L2 |
| `2B.2` | FXd | mapping sem N:N ⇒ EDITION_CONTEXT_EXTERNAL_MAPPING_EMPTY_COMPOSITION | P4 | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L2 |
| `2B.3` | FX | UPDATE falsificando selo ⇒ EDITION_CONTEXT_MAPPING_SIGNATURE_MISMATCH | UPDATE só em fixture | NÃO-IMPL | — | P0001 + prefixo | EC | B | L2 |
| `2B.4` | FXd | UPDATE alterando selo gravado ⇒ EDITION_CONTEXT_MAPPING_SIGNATURE_IMMUTABLE | P4 | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L2 |
| `2B.5` | RO | mappings com traits_signature NULL = 0 (LIVE: 122/122) | P13: universo emitido e > 0 | NÃO-IMPL | — | asserção + universo | — | B | L2 |
| `2B.6` | RO | todo mapping: selo = ARRAY(N:N ORDER BY trait_id) | P13: universo emitido e > 0 | NÃO-IMPL | — | asserção + universo | — | B | L2 |

#### Seção 2-TER

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `2T.1` | FXd | M1 selado → inativo → M2 ativo com outra composição → IMMEDIATE sem erro | P4 | NÃO-IMPL | — | efeito | EC FXd | B | L2 |
| `2T.2` | FXd | após 2T.1: 2 linhas no token, exatamente 1 ativa | cenário de 2T.1 no mesmo caso ou refeito | NÃO-IMPL | — | efeito | EC FXd | B | L2 |
| `2T.3` | FXd | composição de M1 intacta e selada | cenário de 2T.1 | NÃO-IMPL | — | efeito | EC FXd | B | L2 |
| `2T.4` | FX | dois ativos GLOBAIS do mesmo token ⇒ uq_cecem_active_global (23505) | — | NÃO-IMPL | — | 23505 + constraint | EC | B | L2 |
| `2T.5` | FX | dois ativos SCOPED (token, mesmo Set) ⇒ uq_cecem_active_scoped (23505) | — | NÃO-IMPL | — | 23505 + constraint | EC | B | L2 |
| `2T.6` | FXd+RC | 1 GLOBAL + 1 SCOPED coexistem e a 2211 escolhe o SCOPED | P4; p_external_set_id declarado da fixture | NÃO-IMPL | — | efeito (saída da 2211) | EC FXd | B | L2 |
| `2T.7` | FXd+RC | token só com histórico inativo ⇒ NEEDS_REVIEW_INACTIVE_EC_MAPPING | idem | NÃO-IMPL | — | efeito (saída da 2211) | EC FXd | B | L2 |
| `2T.8` | FXd+RC | ativo SCOPED de outro Set não conta como known: residual de Finish, não INACTIVE | idem | NÃO-IMPL | — | efeito (saída da 2211) | EC FXd | B | L2 |

#### Seção 2-QUATER

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `2Q.1` | FXd | UPDATE de normalized_token em mapping selado ⇒ EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE | P4; UPDATE só em fixture | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L3 |
| `2Q.2` | FXd | UPDATE de external_set_id (GLOBAL → SCOPED) ⇒ idem | P4; UPDATE só em fixture | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L3 |
| `2Q.3` | FXd | UPDATE de raw_field ('stamp' → 'subtype') ⇒ idem | P4; UPDATE só em fixture | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L3 |
| `2Q.4` | FXd | UPDATE de game_id ou asset_source_id ⇒ idem | P4; UPDATE só em fixture | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L3 |
| `2Q.5` | FXd | is_active TRUE → FALSE permitido | P4; UPDATE só em fixture | NÃO-IMPL | — | efeito | EC FXd | B | L3 |
| `2Q.6` | FXd | is_active FALSE → TRUE ⇒ EDITION_CONTEXT_MAPPING_REACTIVATION_FORBIDDEN | P4; UPDATE só em fixture | NÃO-IMPL | — | P0001 + prefixo | EC FXd | B | L3 |
| `2Q.7` | FXd | TRUE → TRUE e FALSE → FALSE são no-op sem erro | P4; UPDATE só em fixture | NÃO-IMPL | — | efeito | EC FXd | B | L3 |
| `2Q.8` | FX | token não canônico persiste normalizado ('set-logo' → 'SET-LOGO' etc.) | literal sem marcador: ver N-3 | NÃO-IMPL | — | efeito | EC | M | L3 |
| `2Q.9` | FX | token que normaliza para vazio ⇒ EDITION_CONTEXT_MAPPING_EMPTY_TOKEN | — | NÃO-IMPL | — | P0001 + prefixo | EC | B | L3 |
| `2Q.10` | FX | external_set_id só aparado, nunca uppercased ('  dp1  ' → 'dp1') | literal sem marcador: ver N-3 | NÃO-IMPL | — | efeito | EC | M | L3 |

#### Seção 3

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `3.1` | RC | token sem mapping ativo permanece no residual de Finish | — | NÃO-IMPL | — | efeito (saída da 2211) | — | B | L4 |
| `3.2` | FX+RC | mapping inativo (fixture) não resolve | — | NÃO-IMPL | — | efeito | EC | B | L4 |
| `3.3` | FX+RC | mapping de outro Game (Game fixture) não resolve | Game sentinela (P5) | NÃO-IMPL | — | efeito | Game+EC | M | L5 |
| `3.4` | FX+RC | precedência scoped > global, um nível, sem desempate | — | NÃO-IMPL | — | efeito | EC | B | L4 |
| `3.5` | RC | token consumido por Printing não reaparece em EC | — | NÃO-IMPL | — | efeito | — | B | L4 |
| `3.6` | FX | raw_field='type' impossível por CHECK (redundante com 1.9, declarado) | — | NÃO-IMPL | — | 23514 + constraint | EC | B | L4 |
| `3.7` | RC | SET-LOGO só resolve em dp1/swsh9/svp (H2), escopo por resolve_variant_mapping_scope | leitura de Sets reais | NÃO-IMPL | — | efeito | — | B | L4 |

#### Seção 4

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `4.1` | RO | uq_card_variant_identity UNIQUE NULLS NOT DISTINCT (4 colunas), constraint u validada | — | NÃO-IMPL | — | catálogo | — | B | L6 |
| `4.2` | FX | (card, vt, NULL, NULL) duplicado ⇒ 23505 na identidade | Card real ORDER BY id; variant_order sintético; card_variant no escopo E00/E99 | NÃO-IMPL | — | 23505 + constraint | CV | A | L6 |
| `4.3` | FX | (card, vt, pp, NULL) duplicado ⇒ 23505 | idem + profile de Printing existente | NÃO-IMPL | — | 23505 + constraint | CV | A | L6 |
| `4.4` | FX | (card, vt, NULL, ec) duplicado ⇒ 23505 | idem + profile EC do mesmo Game (trigger 2224) | NÃO-IMPL | — | 23505 + constraint | CV | A | L6 |
| `4.5` | FX | (card, vt, pp, ec) duplicado ⇒ 23505 | idem | NÃO-IMPL | — | 23505 + constraint | CV | A | L6 |
| `4.6` | FX | mesma Card, mesmo finish, contextos diferentes ⇒ coexistem | idem | NÃO-IMPL | — | efeito | CV | A | L6 |
| `4.7` | RO | uq_card_variant_card_order preservado | — | NÃO-IMPL | — | catálogo | — | B | L6 |
| `4.8` | RO | uq_card_variant_one_default_per_card preservado | — | NÃO-IMPL | — | catálogo | — | B | L6 |

#### Seção S

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `S1` | RC | axis_identity_token: ausente 'A'; JSON null 'N'; uuid 'U:<uuid>'; ->> NULL em A e N | — | NÃO-IMPL | — | efeito | — | B | L7 |
| `S2` | RO | axis_identity_token IMMUTABLE + PARALLEL SAFE + search_path='' e não STRICT | — | NÃO-IMPL | — | catálogo | — | B | L7 |
| `S2-BIS` | RO | COMMENT contém 'REINDEX' e a proibição de STRICT | — | NÃO-IMPL | — | catálogo | — | B | L7 |
| `S3` | RO | uq_cvir_row_identity UNIQUE com 5 expressões; nomes antigos ausentes; UNIQUE = {pkey, uq_cvir_row_identity} | — | NÃO-IMPL | — | catálogo | — | B | L7 |
| `S4` | FX | 2 rows do mesmo job/card/vt/printing coexistem diferindo só em EC ('N' × 'U'); contraprova de 3 componentes | job+rows de fixture (P5); job/row no escopo E00/E99 | PARCIAL (padrão 2216 v4.1 α/β/γ) | — | efeito + contraprova | JOB+ROW | A | L7 |
| `S5` | FX | duplicata real nos 5 componentes ⇒ 23505 em uq_cvir_row_identity | idem | NÃO-IMPL | — | 23505 + constraint | JOB+ROW | A | L7 |
| `S6` | FX | 'A' × 'N' coexistem | idem | NÃO-IMPL | — | efeito | JOB+ROW | A | L7 |
| `S7` | FX | 'N' × 'U' coexistem no eixo printing_profile_id | idem | NÃO-IMPL | — | efeito | JOB+ROW | A | L7 |
| `S8` | FX | tipo inválido no eixo ⇒ CVIR_SHAPE_INVALID_EDITION_CONTEXT / _PRINTING | idem | NÃO-IMPL | — | SQLSTATE + prefixo | JOB+ROW | A | L7 |
| `S9` | FX | string não-UUID ('banana') ⇒ CVIR_SHAPE_INVALID_* | idem | NÃO-IMPL | — | SQLSTATE + prefixo | JOB+ROW | A | L7 |
| `S10` | FX | VALID exige chaves (a)–(d): job-aware para EC, não para printing | idem; jobs operacional e terminal | NÃO-IMPL | — | SQLSTATE + prefixo; efeito | JOB+ROW | A | L7 |
| `S11` | FX | row NEEDS_REVIEW em job operacional sem as duas chaves: permitido | idem | NÃO-IMPL | — | efeito | JOB+ROW | A | L7 |

#### Seção R

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `R1` | RO | resolve_variant_row_axes(jsonb,uuid,uuid,text): STABLE, SECURITY DEFINER, search_path='', 10 OUT | — | NÃO-IMPL | — | catálogo | — | B | L8 |
| `R2` | ST | prosrc chama internal.compute_variant_residual_signature | — | NÃO-IMPL | — | prosrc estático (declarado) | — | B | L8 |
| `R3` | RC | size fora de STANDARD ⇒ BLOCKED_* propagado, EC intocado | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | — | B | L8 |
| `R4` | RC | token consumido por Printing sai do residual e não alimenta EC | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | — | B | L8 |
| `R5` | RC | token consumido por EC sai do residual de Finish | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | — | B | L8 |
| `R6` | RC+RO | token desconhecido: ambos UNRESOLVED; contagens de trait/profile/mapping inalteradas | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito + contagem | — | B | L8 |
| `R7` | FX+RC | precedência scoped > global aplicada uma vez | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | EC | B | L8 |
| `R8` | RC | todo token de entrada aparece uma vez em Printing ∪ EC ∪ residual | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | — | B | L8 |
| `R9` | FX+RC | mapping scoped ao Set X não resolve row do Set Y, nem com p_external_set_id NULL | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | EC | B | L8 |
| `R10` | ST | prosrc testa p IS NULL OR p.printing_state IS NULL antes do eixo 3; reler o prosrc da 2176 | — | NÃO-IMPL | — | prosrc estático (declarado) | — | B | L8 |
| `R11` | FX+RC | subtype com mapping conhecido e INATIVO ⇒ NEEDS_REVIEW_INACTIVE_EC_MAPPING | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | EC | B | L8 |
| `R12` | FX+RC | nas saídas NEEDS_REVIEW_*, residual_subtype/stamp preservam o token real | p_external_set_id via resolve_variant_mapping_scope; insumo reutilizável: vetores 2834 | NÃO-IMPL | — | efeito | EC | B | L8 |

#### Seção K

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `K3` | ST | K3-S: prosrc do confirm — WHEN unique_violation antes de OTHERS; CONSTRAINT_NAME; releitura IS NOT DISTINCT FROM; UNRESOLVED sem re-raise | nenhuma chamada ao confirm (P7, decisão 3) | NÃO-IMPL | — | prosrc estático (declarado) | — | B | L9 |
| `K4` | ST | K4-S: matching do confirm usa IS NOT DISTINCT FROM nos dois eixos nuláveis (match e releitura) | nenhuma chamada ao confirm (P7, decisão 3) | NÃO-IMPL | — | prosrc estático (declarado) | — | B | L9 |
| `K8` | ST | K8a: confirm adquire FOR UPDATE das Cards com ORDER BY c.id | nenhuma chamada ao confirm (P7, decisão 3) | NÃO-IMPL | — | prosrc estático (declarado) | — | B | L9 |

#### Seção B

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `V1` | EX | UUID gravado = UUID do routing; COUNT = 0 ⇒ FAIL (asserção v7.0) | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V2` | EX | JSON null só onde o routing confirma RESOLVED_NO_EDITION_CONTEXT | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V3` | EX | eixo EC não-terminal não recebeu chave | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V4` | EX | zero row operacional VALID+PENDING sem chave | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V5` | EX | ≥ 1 row histórica VALID legitimamente sem chave | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V6` | EX | destino observado = recomputado, row a row | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V7` | EX | estados e lineage por classe (4 regras) | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V8` | EX | lineage 1:N sem destinos divergentes | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V9` | EX | write-set operacional de reavaliação = 0, sem escrita | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V10` | RO | guard ESTRITO presente (trigger, tgfoid, tokens; token obsoleto ausente) | — | PARCIAL (2832 v3.1) | — | catálogo/prosrc + asserção | — | M | L10 |
| `V11` | EX | tri-estado não degradado; A/N/U distintos | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V12` | RO | partição fechada + zero UUID órfão (≥ 1 UUID) | — | PARCIAL (2832 v3.1) | — | catálogo/prosrc + asserção | — | M | L10 |
| `V13` | EX | histórico intocado; universo medido (P13) | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |
| `V14` | EX | CANCELLED terminal; universo CANCELLED VALID+PENDING > 0 (P13) | P13 universo > 0; escopo por resolve_variant_mapping_scope | PARCIAL (2832 v3.1) | — | asserção + universo | — | M | L10 |

#### Seção M

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `SM1` | EX | vocabulário de job.status (8 valores do CHECK) | P13: universo emitido | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | — | M | L11 |
| `SM2` | EX | vocabulário de persistence_status | P13: universo emitido | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | — | M | L11 |
| `SM3` | EX | nenhuma row terminal sem efeito, por classe | P13: universo emitido | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | — | M | L11 |
| `SM4` | EX+FX | nenhuma row confirmável com resulting_variant_id; controle negativo (P13) | P13: universo confirmável vazio sob FREEZE | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | JOB+ROW | A | L11 |
| `SM5` | EX | nenhuma row mutável em job terminal | P13: universo emitido | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | — | M | L11 |
| `SM6` | EX+FX | todo confirmável está no universo mutável; enumeração em fixture (P13) | P13: universo confirmável vazio sob FREEZE | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | JOB+ROW | A | L11 |
| `SM7` | EX | zero row mutável VALID sem a chave | P13: universo emitido | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | — | M | L11 |
| `SM8` | EX | toda row sem chave é histórica ou não-VALID (declarado equivalente a SM7) | P13: universo emitido | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | — | M | L11 |
| `SM9` | EX | nenhuma row CANCELLED mutável ou confirmável | P13: universo emitido | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | — | M | L11 |
| `SM10` | FX | classificador pode_confirmar em fixture (i) + universo real / controle em memória (ii) | P13: universo confirmável vazio sob FREEZE | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | JOB+ROW | A | L11 |
| `SM11` | EX+FX | nenhuma row histórica sem chave é confirmável; controle negativo (P13) | P13: universo confirmável vazio sob FREEZE | PARCIAL (2833 v2.0) | — | asserção + universo / controle negativo | JOB+ROW | A | L11 |

#### Seção G

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `G1` | FX | STAGED · PENDING · NEEDS_REVIEW · ausente ⇒ permitido | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |
| `G2` | FX | STAGED · PENDING · VALID · ausente ⇒ CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |
| `G3` | FX | STAGED · PENDING · VALID · JSON null ou UUID existente ⇒ permitido | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |
| `G4` | FX | CONFIRMING (e RECEIVED/PROCESSING) · PENDING · VALID · ausente ⇒ mesmo código | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |
| `G5` | FX | COMPLETED / COMPLETED_WITH_ERRORS / FAILED · VALID · PENDING · ausente ⇒ permitido | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |
| `G6` | FX | CANCELLED · VALID · PENDING · ausente ⇒ permitido | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |
| `G7` | FX | job fixture CANCELLED → STAGED não barrado; 1ª escrita na row sem chave recusada; G-BIS no-lockout | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |
| `G8` | FX | remover a chave de row VALID ⇒ CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN, inclusive em job terminal | jobs/rows de fixture (P5); guard 2214 exercido diretamente; padrão reutilizável: 2214 v3.1 PASSO 4 | NÃO-IMPL | — | SQLSTATE + prefixo / efeito | JOB+ROW | A | L12 |

#### Seção D

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `D1` | RO | uq_card_variant_card_type_no_printing não existe | E00 `gate_pass` | PASS-LIVE | E02 `3357ed46…` | H283P `pass=5/5` + E99 limpo (Etapa 2) | — | B | — (concluído) |
| `D2` | RO | uq_card_variant_card_type_printing não existe | E00 `gate_pass` | PASS-LIVE | E02 `3357ed46…` | H283P `pass=5/5` + E99 limpo (Etapa 2) | — | B | — (concluído) |
| `D3` | RO | uq_cvir_job_card_type_no_printing e _printing não existem | E00 `gate_pass` | PASS-LIVE | E02 `3357ed46…` | H283P `pass=5/5` + E99 limpo (Etapa 2) | — | B | — (concluído) |
| `D4` | RO | 1 índice único com variant_type_id (= uq_card_variant_identity); 1 com job_id (= uq_cvir_row_identity) | E00 `gate_pass` | PASS-LIVE | E02 `3357ed46…` | H283P `pass=5/5` + E99 limpo (Etapa 2) | — | B | — (concluído) |
| `D5` | RO | ortogonais preservados (card_order, one_default, id_card) | E00 `gate_pass` | PASS-LIVE | E02 `3357ed46…` | H283P `pass=5/5` + E99 limpo (Etapa 2) | — | B | — (concluído) |

#### Seção 5

| Id | Tipo | Requisito (2830 v7.0) | Pré-condições / dependências | Estado | Envelope | Evidência exigida | Fixture | Risco | Próximo mandato |
|---|---|---|---|---|---|---|---|---|---|
| `5.1` | RO | hold_frozen = 107 exato (PASSO 0 da 2831) | A4: 107 medido e registrado antes | PARCIAL (derivação 2831 v2.0, sem TEMP) | — | asserção + universo | — | M | L13 |
| `5.2` | RO | READY_STRUCTURAL 365 · UNCONDITIONED 285 · PRICING_CONDITIONED 80 | A4: 365/285/80 medidos antes; divergência = STOP | PARCIAL (derivação 2831 v2.0, sem TEMP) | — | asserção + universo | — | M | L13 |
| `5.3` | RO | plano (285) ∩ HOLD (107) = 0 | A4; P13 universo 285 | PARCIAL (derivação 2831 v2.0, sem TEMP) | — | asserção + universo | — | M | L13 |
| `5.6` | RO | lineage: resulting 23.955 · matched 1.129 (baseline de FREEZE) | A4: recapturado no precheck; divergência = STOP | PARCIAL (derivação 2831 v2.0, sem TEMP) | — | asserção + universo | — | M | L13 |
| `5.7` | RO | plano ∩ PRICING_CONDITIONED = 0; 80 = STAFF_HOLO 40 + SET_LOGO_REVERSE 40; dois conceitos separados | A4: composição 40/40 medida antes; divergência = STOP | PARCIAL (derivação 2831 v2.0, sem TEMP) | — | asserção + universo | — | M | L13 |

## 3. Reconciliação 17 + 118

| Seção | AUTO | PASS-LIVE | Restantes | Lote(s) |
|---|---|---|---|---|
| 1 | 12 | 12 | 0 | — |
| 2 | 14 | 0 | 14 | L1 (13), L5 (2.6) |
| 2-BIS | 6 | 0 | 6 | L2 |
| 2-TER | 8 | 0 | 8 | L2 |
| 2-QUATER | 10 | 0 | 10 | L3 |
| 3 | 7 | 0 | 7 | L4 (6), L5 (3.3) |
| 4 | 8 | 0 | 8 | L6 |
| S | 12 | 0 | 12 | L7 |
| R | 12 | 0 | 12 | L8 |
| K | 3 | 0 | 3 | L9 |
| B | 14 | 0 | 14 | L10 |
| M | 11 | 0 | 11 | L11 |
| G | 8 | 0 | 8 | L12 |
| D | 5 | 5 | 0 | — |
| 5 | 5 | 0 | 5 | L13 |
| **Total** | **135** | **17** | **118** | 13 lotes |

- **Aritmética:** 12+14+6+8+10+7+8+12+12+3+14+11+8+5+5 = 135. PASS: 12 + 5 = 17. Restantes: 135 − 17 = 118.
- **Pelos lotes:** 13+14+10+6+2+8+12+12+3+14+11+8+5 = 118.
- **Por estado:** PASS-LIVE 17 · PARCIAL 31 (S4, B 14, M 11, Seção 5 5) · NÃO-IMPL 87. Soma 135.
- **Sem duplicidade nem lacuna:** cada ID aparece uma única vez na matriz; o conjunto é igual ao extraído do contrato, na mesma ordem; cada restante está em exatamente um lote.
- **Conferência com o contrato:** a contagem por seção bate com a CONTAGEM v7.0 (l. 1093–1116), e 5.7 é a posição nova que leva 134 a 135.

## 4. Gate C — inventário de implementação

### 4.1 Artefatos existentes

| Artefato | Estado | Uso na Fase 5 |
|---|---|---|
| E00 `a4dd8438…` | executado nas Etapas 2 e 3 | **reutilizado sem alteração** como precheck JIT de todos os lotes. O gate P7 cobre as 5 tabelas EC (`gate_scope`); `card_variant`, job, row, action log e `game` só são inventariados (l. 97–112). Os gates de objeto cobrem 1.x e D (`g_objects_1x`, `g_objects_D`). `touched_now` é `false` para as duas N:N. |
| E99 `49a71ecb…` | executado nas Etapas 2 e 3 | **reutilizado sem alteração** nos lotes só-EC. Compara contagens de EC, `card_variant`, job, row e action log (l. 67–106). O marcador só é procurado em `trait.code`, `profile.code` e `mapping.normalized_token`. **Não** cobre `game`. |
| E01 `c4118b8c…`, E02 `3357ed46…` | PASS | concluídos; **não** são reconstruídos. Servem de padrão (estrutura de caso, sinais H283C/F/P, marcador) |
| `tools/static_check.py` | 444/444 | o perfil de envelope proíbe `UPDATE`, `DELETE`, `SET LOCAL`, `EXECUTE`, `PERFORM` e `LOCK` (l. 25–27), e reconhece negativos só por 23514/23505 + constraint (l. 48–50) |
| 2832 v3.1 `ef28b52d…` | fonte de V1–V14 | reaproveitável como lógica; usa TEMP (2×), NOTICE e o V10 obsoleto; o reempacotamento deve aplicar V1/V10/V12/V13/V14 da v7.0 |
| 2833 v2.0 `603fb70a…` | fonte de SM1–SM11 | idem (TEMP 2×); SM4/SM6/SM10/SM11 ganham fixture ou controle negativo (P13) |
| 2831 v2.0 `2ef53d02…` | derivação de 5.1–5.3/5.7 | reaproveitável como derivação; usa `CREATE TEMP TABLE hold_frozen` (l. 65), que o P2 proíbe |
| 2216 v4.1 `fafd4612…` | padrão α/β/γ | base de S4 (l. 662–770) |
| 2214 v3.1 `7961d202…` | PASSO 4 (l. 269) | padrão de fixture para G1–G8 |
| 2834 + `test-vectors/edition-context-axis-vectors.json` | PASS no Batch 7 (18/18) | insumos para R3–R8/R11/R12; o runner usa TEMP e não é reaproveitável como envelope |

### 4.2 Faltantes

| # | Componente | Necessário para | Observação |
|---|---|---|---|
| F-1 | 13 envelopes novos (E03–E15), um por lote | todos os lotes | cada um com mandato de implementação e de execução separados (A1) |
| I-1 | precheck complementar por lote (`E0xP`, SELECT) **ou** sucessor do E00 | todos os lotes | gates de objetos e códigos de erro do lote (P11), sequences e RLS das tabelas tocadas fora do `touched_now` atual, universos P13, constantes A4. Escolha em DP-3 |
| I-2 | perfil de envelope por lote no `tools/static_check.py` | todos os lotes | UPDATE/DELETE só em linha de fixture; `SET CONSTRAINTS` só nos dois triggers de selo; negativos P0001 + prefixo e 23503; casos esperados por lote |
| I-3 | sucessor do E99 (resíduo) | L5 (`game`); L6 (`card_variant`); L7, L11, L12 (job/row) | contagem de `game`; marcador nos campos usados pelas fixtures (`external_set_id`, `name`, `normalized_data`); P10(a)/(b) |
| I-4 | extensão do `gate_scope` P7 do E00 (allowlist com identidade) | L5 (`game`, trigger 101); L6 (`card_variant`, triggers 161 e 2224); L7, L11, L12 (job, row, guard 2214) | sem isso, escrever nessas tabelas fica fora do fecho P7 exigido pela 2830 P7 |
| I-5 | mandato de medição A4 (só SELECT) | L13 | 107 · 365/285/80 · 40/40 · 23.955/1.129 medidos e registrados antes de virarem asserção |
| I-6 | readiness de seção pesada com P9a (EXPLAIN) | L10, L11, L13 | exigido pelo AD-2 para B, M e 5.x |

**Dependências entre implementações:**
- L5 depende de I-3 e I-4 para `game`;
- L6 depende de I-3 e I-4 para `card_variant`;
- L7, L11 e L12 compartilham I-3 e I-4 para job/row, que se constroem uma vez (no L7) e se reaproveitam;
- L13 depende de I-5;
- L10, L11 e L13 dependem de I-6.

## 5. Gate D — DAG e ordem dos lotes

### 5.1 Grafo de dependências

```text
Decisões:  DP-1 (tempo: P9b × AD-2) ─┐   DP-4 (lock_timeout)   DP-5 (escrita transitória)
                                     ▼
Infra:  I-1 ─┬─ I-2 ─┬──────────────────────────────────────────────┐
             │       │                                              │
Lotes:       │       ├─► L1 (Seção 2 −2.6) ─► L2 (2-BIS+2-TER) ─► L3 (2-QUATER) ─► L4 (Seção 3 −3.3)
             │       │                                                                  │
             │       │         I-3a + I-4a (game) ──────────────────────────────────► L5 (2.6, 3.3)
             │       │         I-3b + I-4b (card_variant) ──────────────────────────► L6 (Seção 4)
             │       │         I-3c + I-4c (job/row) ───────────────────────────────► L7 (Seção S)
             │       ├─► L8 (Seção R)          [só EC; independe de L5–L7]
             │       ├─► L9 (K3, K4, K8)       [sem escrita; independe de tudo]
             │       │   I-6 ───────────────────────────────────────────────────────► L10 (Seção B)
             │       │   I-3c + I-4c + I-6 ─────────────────────────────────────────► L11 (Seção M)
             │       │   I-3c + I-4c ───────────────────────────────────────────────► L12 (Seção G)
             │       │   I-5 + I-6 ─────────────────────────────────────────────────► L13 (Seção 5)
```

**Arestas complementares, não bloqueantes (o contrato cita uma prova na outra, sem exigir ordem):**
- V10 ↔ G2/G8;
- SM10(ii) ↔ G2;
- S10(d) ↔ G5/G6;
- K4 ↔ 4.2;
- 3.6 ↔ 1.9 (já PASS).

**Nenhum lote depende de K1, K2, K8b, 6.1, 6.2, 6.3, P14 ou D-1 para executar os seus casos.** A 2830 só exige P14 de K1/K2/K8b (l. 367–417), que são manuais da fase 6.

### 5.2 Ambiente isolado: o que depende dele

| Dimensão | Casos afetados | Base contratual |
|---|---|---|
| Execução dos casos em ambiente isolado (P14) | **0 / 118** | P14 vale só para K1/K2/K8b |
| Medição de tempo antes do LIVE (P9b, A2) | **118 / 118, pela letra** | P9(b), l. 310–328: "nenhum envelope vai ao LIVE sem a medição registrada" |
| Mesma medição sob a adaptação AD-2 (proposta, D-2 pendente) | nenhum bloqueio para lotes leves; **B, M e 5.x** exigem readiness própria e P9a no LIVE | protocolo §7 AD-2; as Etapas 2 e 3 rodaram sob essa adaptação, por mandato |

Conclusão: nenhum dos 118 precisa do ambiente isolado para **executar**. Todos dependem dele para a **medição de tempo**, salvo se Fabrício estender a adaptação AD-2 aos novos lotes (DP-1). Isso não é antecipar manual da fase 6: é o P9(b), válido para todo envelope.

### 5.3 Protocolo comum a todos os lotes

Herdado do protocolo §5 e dos registros das Etapas 2 e 3:

| Passo | Chamada | Gate |
|---|---|---|
| S0 | verificação local | HEAD = baseline do mandato; árvore limpa; blobs do lote = auditados; `static_check` PASS |
| S1 | L1 (canal), se o lote escreve | `transaction_read_only = off`; `lock_timeout` conforme DP-4 |
| S2 | L3 | nenhuma sessão/lock concorrente |
| S3 | E00 verbatim | `gate_pass = true` |
| S4 | precheck do lote (I-1) | `gate_pass = true` |
| S5 | envelope do lote, uma chamada, imediatamente após S4 | `H283P` com `pass=n/n` e a lista exata de casos; `elapsed_ms ≤ 60000` |
| S6 | E99 (ou sucessor) com os marcadores do S3 | `gate_pass = true`, `d_diff = []`, marcador ausente |
| S7 | L3 | limpo |

- **Prova de rollback** tripla: mensagem terminal com marcador, E99 e L3.
- **STOP** (protocolo §5.4, sem retry):
  - `H283F`, outro SQLSTATE, `57014` ou `55P03`: FAIL, E99 imediato, STOP;
  - retorno `[]`: defeito grave;
  - E99 com diferença: incidente, sem limpeza automática.
- **Autorização LIVE:** mandato próprio por lote, nomeando as tabelas escritas transitoriamente.

### 5.4 Lotes

| Lote | Casos (n) | Arquivos | Dependências | Controles específicos | Autorização LIVE | PASS / STOP específicos |
|---|---|---|---|---|---|---|
| **L1** | 2.1–2.5, 2.7–2.14 (13) | E03 (DO) + E03P (SELECT); perfil E03 no static_check | I-1, I-2, P4, DP-1, DP-4, DP-5 | fixtures só em trait, profile, profile_trait; UPDATE/DELETE só em id de fixture; `SET CONSTRAINTS` IMMEDIATE→DEFERRED nos dois triggers de selo | escrita transitória em 3 tabelas EC | §7 |
| **L2** | 2B.1–2B.6, 2T.1–2T.8 (14) | E04 + E04P | L1 infra; RC na 2211 | fixtures em mapping, mapping_trait e trait; `p_external_set_id` declarado da fixture; 2B.5/2B.6 emitem universo (122) | escrita transitória em 3 tabelas EC | universo 2B.5/2B.6 > 0 senão FAIL (P13) |
| **L3** | 2Q.1–2Q.10 (10) | E05 + E05P | L2 infra; N-3 | UPDATE do cabeçalho só em fixture; tokens literais de 2Q.8/2Q.10 (N-3) | idem | colisão com mapping LIVE ativo ⇒ STOP de desenho, nunca PASS |
| **L4** | 3.1, 3.2, 3.4–3.7 (6) | E06 + E06P | L2 infra | 3.7 lê Sets reais via `resolve_variant_mapping_scope` | escrita transitória EC + leitura de catálogo | escopo de 3.7 não resolvível ⇒ STOP |
| **L5** | 2.6, 3.3 (2) | E07 + E07P; sucessor de E00/E99 para `game` | I-3a, I-4a | Game sentinela nova (P5); nunca Game real alterado | escrita transitória em `game` + EC | `game` fora do fecho P7 ⇒ não executar |
| **L6** | 4.1–4.8 (8) | E08 + E08P; E00/E99 para `card_variant` | I-3b, I-4b | Card real `ORDER BY id`; `variant_order` sintético fora da faixa; profile EC do mesmo Game (2224); nenhum UPDATE em linha existente | escrita transitória em `card_variant` | qualquer UPDATE em linha pré-existente ⇒ FAIL de harness |
| **L7** | S1–S11, com S2-BIS (12) | E09 + E09P; E00/E99 para job/row | I-3c, I-4c | jobs de fixture `source='TCGDEX'`, `external_set_id` sintético distinto; nunca job real (P5) | escrita transitória em job/row | índice de fingerprint ativo em conflito ⇒ STOP |
| **L8** | R1–R12 (12) | E10 + E10P | L2 infra | RC na 2211 com escopo por `resolve_variant_mapping_scope`; R2/R10 estáticos declarados | escrita transitória EC | R10 nunca PASS comportamental sem provocar a condição |
| **L9** | K3, K4, K8 (3) | E11 (DO sem DML, como o E02) | I-1, I-2 | só prosrc do confirm; nenhuma chamada | nenhuma escrita | — |
| **L10** | V1–V14 (14) | E12 (possivelmente dividido); readiness de seção pesada | I-6; DP-1 | zero escrita; universos P13 medidos e > 0 | só leitura | divisão definida pela readiness após o P9a |
| **L11** | SM1–SM11 (11) | E13 + E13P | I-3c, I-4c, I-6 | controles negativos em fixture (SM4, SM6, SM11) e em memória (SM10(ii)) | escrita transitória em job/row | universo confirmável ≠ vazio ⇒ reavaliar o P13 antes de executar |
| **L12** | G1–G8 (8) | E14 + E14P | I-3c, I-4c | guard 2214 exercido diretamente; transições de status só em job de fixture | escrita transitória em job/row | — |
| **L13** | 5.1–5.3, 5.6, 5.7 (5) | E15; mandato de medição A4 | I-5, I-6 | derivação 2831 sem TEMP; constantes medidas antes | só leitura | constante medida ≠ documento ⇒ STOP e adjudicação (5.2/5.7) |

**Ordem recomendada:** L1 → L2 → L3 → L4 → L5 → L6 → L7 → L8 → L9 → L10 → L11 → L12 → L13.
- É a ordem contratual (1, 2, 2B, 2T, 2Q, 3, 4, S, R, K, B, M, G, D, 5), com **um desvio declarado**: 2.6 e 3.3 ficam no L5, logo após o L4, porque exigem a infraestrutura de `game`. Esse desvio exige aceite (DP-2).
- L8 e L9 não dependem de L5–L7 e poderiam ser antecipados; isso seria outro desvio da ordem contratual, também sujeito a DP-2.
- Nenhum lote roda em transação única com outro: cada envelope é um statement, com o seu próprio E00, precheck e E99.

## 6. Gate E — divergência da validação 960 (S2)

### 6.1 Identidade

| Item | Valor |
|---|---|
| Arquivo | `database/validations/960_validate_card_variant.sql`, blob `6fe5ecd7…`, 732 linhas |
| Versão | **2.2 — "CANÔNICA — versão 2.2 STAGED, NÃO EXECUTADA"** (cabeçalho, l. 5–6), de 2026-09-12 (commit `83e6bad`). A última versão executada é a v2.1 (2026-07-24, `c038744`). |
| Forma | `BEGIN; DO $$ … $$; SELECT …; COMMIT;`, só leitura, fail-fast por `RAISE EXCEPTION` |
| Referências no harness | nenhuma: E00, E01, E02, E99 e `tools/static_check.py` não citam a 960 |

### 6.2 Alcance

| # | Trecho da 960 | Estado exigido pela 2830 v7.0 / LIVE | Efeito |
|---|---|---|---|
| E-1 | l. 161–166 exige `uq_card_variant_card_type_no_printing` e `uq_card_variant_card_type_printing` | D1/D2 exigem a **ausência** deles; PASS na Etapa 2; ausentes no inventário P9A-00 | a 960 falharia no primeiro bloco de índices |
| E-2 | l. 197–224 confere os predicados desses dois índices | idem | inalcançável depois de E-1; também diverge |
| E-3 | l. 386–402 procura duplicata por `(card_id, variant_type_id, printing_profile_id)` | a identidade é de 4 componentes (4.1, D4) | depois da 2213, Variants que diferem só em Contexto de Edição seriam acusadas como duplicatas. Hoje `card_variant_ec_nonnull = 0` (canon do E99), então não há falso positivo atual |
| E-4 | não exige `uq_card_variant_identity`, `edition_context_profile_id`, a FK ao profile EC nem o trigger 2224 | presentes (4.1, D4; Batches 4, 9 e 10) | lacuna de cobertura, não falha |
| E-5 | l. 165 exige `ix_card_variant_card_id` | objeto da decisão 6.2 (pendente) | acoplamento: se 6.2 resultar em remoção futura, a 960 precisa acompanhar |
| E-6 | l. 464–470 e 603–636: contagens de 7 Card Sets (927 Cards / 1.653 Variants e distribuição por tipo) | **não verificado** nesta rodada | não se sabe se ainda batem com o LIVE |

### 6.3 Casos automáticos afetados

**Nenhum dos 135 depende da 960 para executar ou passar:**
- os casos da 2830 são autocontidos e o harness não chama a 960;
- há **sobreposição semântica**: a 960 contradiz D1/D2 (já PASS) e não conhece 4.1/D4;
- 4.7 e 4.8 são coerentes com ela (`uq_card_variant_card_order` e `…one_default_per_card` exigidos nos dois lados).

A divergência é de consistência do repositório canônico, não do LIVE nem do harness. Por isso não é STOP.

### 6.4 Correção mínima proposta (não aplicada)

1. 960 v2.3: remover E-1 e E-2 da lista exigida.
2. Exigir `uq_card_variant_identity` com a definição de 4.1 (UNIQUE NULLS NOT DISTINCT nas 4 colunas).
3. Exigir a coluna `edition_context_profile_id`, a sua FK e o trigger 2224.
4. Trocar E-3 por agrupamento nos 4 componentes. `GROUP BY` já trata NULL como igual, o que reproduz NULLS NOT DISTINCT.
5. Manter `ix_card_variant_card_id` até a decisão 6.2 e registrar o acoplamento.
6. Recontar E-6 por leitura LIVE autorizada antes de fixar as constantes. Se divergirem, adjudicar; nunca ajustar em silêncio.

**Dependências:** mandato próprio de correção de validação canônica (proibida neste mandato) e mandato de execução com leitura LIVE. Nenhum lote da Fase 5 depende dessa correção. Recomenda-se tratá-la em trilha paralela, antes do UNFREEZE, por consistência do repositório.

## 7. Gate F — readiness do primeiro lote (L1)

### 7.1 Escopo

| Campo | Valor |
|---|---|
| Lote | **L1** — Seção 2, composição do profile, **sem 2.6** |
| Casos, em ordem | 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14 (13) |
| Arquivos a criar (implementação) | `harness/2830H_E03_section2_profile_composition.sql` (1 DO); `harness/2830H_E03P_precheck_section2.sql` (1 SELECT); perfil E03 em `tools/static_check.py` |
| Reutilizados sem alteração | E00 `a4dd8438…`; E99 `49a71ecb…` (conta trait/profile/profile_trait e procura o marcador em `trait.code`/`profile.code`) |
| Tabelas escritas (transitório) | `card_edition_context_trait`, `card_edition_context_profile`, `card_edition_context_profile_trait` |
| Objetos LIVE exercitados (2206, pinados por md5 no P7 do E00) | `trg_cecp_seal` (CONSTRAINT, AFTER INSERT, DEFERRABLE INITIALLY DEFERRED); `trg_cecpt_immutable` (BEFORE INSERT/UPDATE/DELETE); `trg_cecpt_trait_active` (BEFORE INSERT); `trg_cecp_signature_write` (BEFORE UPDATE OF traits_signature); `pk_cecpt`; `fk_cecpt_*`; `uq_cecp_game_signature` (parcial) |
| Contratos de erro LIVE (2206 blob `2fcd4d74…`; `RAISE EXCEPTION` sem ERRCODE ⇒ SQLSTATE `P0001`) | `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:` (l. 88) · `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` (l. 165) · `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` (l. 201) · `EDITION_CONTEXT_SIGNATURE_MISMATCH:` (l. 217) · `EDITION_CONTEXT_TRAIT_INACTIVE:` (l. 244) |

### 7.2 Fixtures comuns (recriadas dentro de cada caso e desfeitas pela subtransação do caso)

- **Game:** `POKEMON` por `code`, com preflight de exatamente uma linha (padrão do E01, l. 85).
- **Marcador:** o padrão do E01 (AD-6), `H2830_` + uuid sem hífens em maiúsculas, em todo `code`.
- **Traits:** família `EVENT`, ativos, `code = marcador || '_T<k>'`, `display_order = max(display_order da família no Game) + 1000 + k`, porque `uq_cect_game_family_order` é por família. Um trait inativo (`is_active = false`) só em 2.5.
- **Profiles:** `code = marcador || '_P<caso>_<k>'` e `display_order = max(display_order do Game) + 1000 + k`, porque `uq_cecp_game_order` é por Game.
- **P4, sequência fixa em todo caso FXd:**
  - selar: `SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE`;
  - medir;
  - voltar: `SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED`, no caminho normal **e** no handler do negativo.
- Nenhum UPDATE ou DELETE fora das linhas criadas no próprio caso (P1). Nenhuma RPC. Nenhum `set_config`, TEMP ou `SET ROLE`.

### 7.3 Casos

| Caso | Preparação | Ação | Aceite (P3) |
|---|---|---|---|
| 2.1 | P + N:N (T2, T1) | P4 IMMEDIATE | `traits_signature` NOT NULL **e** = `ARRAY(SELECT trait_id … WHERE profile_id = P ORDER BY trait_id)`; `cardinality = 2` |
| 2.2 | P sem N:N | P4 IMMEDIATE | `P0001` e MESSAGE_TEXT começa por `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:` |
| 2.3 | P + N:N (T1), selado por P4 | INSERT N:N (P, **T2**) | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:`. A reinserção **idêntica** (P, T1) passa pelo guard e cai na PK (2206, l. 149–163); por isso o caso usa outro trait |
| 2.4 | P + N:N (T1, T2), selado | DELETE N:N (P, T1) | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` |
| 2.5 | P em montagem + trait inativo Ti | INSERT N:N (P, Ti) | `P0001` + `EDITION_CONTEXT_TRAIT_INACTIVE:`. O guard de imutabilidade dispara antes (ordem alfabética) e deixa passar, porque o profile não está selado |
| 2.7 | Pa e Pb, ambos com N:N (T1, T2) | P4 IMMEDIATE | `23505` e `CONSTRAINT_NAME = 'uq_cecp_game_signature'` |
| 2.8 | Pa e Pb sem N:N e **sem** IMMEDIATE | contagem | 2 profiles de fixture com `traits_signature IS NULL`, zero exceção |
| 2.9 | P + N:N inserida em ordem **decrescente** de `trait_id` (T1..T3) | P4 IMMEDIATE | selo = array ascendente e igual ao `ORDER BY trait_id` |
| 2.10 | P + N:N (T1) | INSERT duplicado (P, T1) em sub-bloco; depois P4 IMMEDIATE | `23505` com `CONSTRAINT_NAME = 'pk_cecpt'`; depois `cardinality(selo) = COUNT(N:N de P) = 1` |
| 2.11 | P + N:N (T1), em montagem (sem IMMEDIATE) | `UPDATE … SET traits_signature = ARRAY[T2] WHERE id = P` | `P0001` + `EDITION_CONTEXT_SIGNATURE_MISMATCH:` |
| 2.12 | P + N:N (T1), selado | `UPDATE … SET traits_signature = ARRAY[T2] WHERE id = P` | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` |
| 2.13 | idem | `UPDATE … SET traits_signature = NULL WHERE id = P` | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` |
| 2.14 | idem | `UPDATE … SET name = '<fixture>' WHERE id = P` | zero exceção; `name` alterado; `traits_signature` igual ao selado |

**Mensagem terminal:** `H2830_ROLLBACK_PASS: envelope=E03_SECAO2_COMPOSICAO_PROFILE pass=13/13 casos=2.1,2.2,2.3,2.4,2.5,2.7,2.8,2.9,2.10,2.11,2.12,2.13,2.14 marker=H2830_… elapsed_ms=N`, SQLSTATE `H283P`. Estrutura igual à do E01 (H283C por caso, H283F aborta, H283P terminal).

### 7.4 Precheck complementar E03P (1 SELECT, `gate_pass` = conjunção)

| Gate | Condição |
|---|---|
| `g_game_pokemon_one` | exatamente um `game` com `code = 'POKEMON'` |
| `g_s2_triggers` | os quatro triggers do §7.1 existem na tabela certa, não internos, `tgenabled = 'O'`, função = a esperada; `trg_cecp_seal` e `trg_cecem_seal` com `tgdeferrable` e `tginitdeferred` = true |
| `g_s2_constraints` | `pk_cecpt`, `fk_cecpt_profile`, `fk_cecpt_trait` e `uq_cecp_game_signature` (índice único parcial em `traits_signature IS NOT NULL`) presentes |
| `g_s2_error_tokens` | o `prosrc` das 4 funções da 2206 contém os 5 tokens do §7.1. É redundante com o pino md5 do P7, mas literal ao P11 |
| `g_nn_no_sequence` | nenhuma sequence com default ou OWNED BY em `card_edition_context_profile_trait` (P6; esta tabela tem `touched_now = false` no E00) |
| `g_nn_rls_bypass` | `card_edition_context_profile_trait` sem `FORCE RLS` e com dono = `current_user` (mesma regra de `g_rls_bypass` do E00) |

### 7.5 Perfil E03 no `tools/static_check.py`

Mantém todas as regras do perfil E01, com quatro ajustes:
- **UPDATE e DELETE:** aceitos só na forma `UPDATE public.card_edition_context_profile … WHERE id = v_<fixture>` e `DELETE FROM public.card_edition_context_profile_trait WHERE profile_id = v_<fixture> AND trait_id = v_<fixture>`.
- **`SET CONSTRAINTS`:** aceito só com exatamente `public.trg_cecp_seal, public.trg_cecem_seal` e `IMMEDIATE` ou `DEFERRED`; todo `IMMEDIATE` tem um `DEFERRED` correspondente no mesmo caso.
- **Negativos:** `P0001` + prefixo do §7.1, ou `23505` + constraint.
- **Casos:** exatamente os 13 do §7.1, em ordem; `c_expected` igual; INSERTs com marcador.

`SET LOCAL`, `EXECUTE`, `PERFORM`, TEMP, `set_config` e `SET ROLE` continuam proibidos.

### 7.6 Pontos abertos do L1

| # | Ponto | Tratamento |
|---|---|---|
| N-1 | P4: a 2830 marca como pendente "confirmar que SET CONSTRAINTS funciona dentro do PL/pgSQL do envelope" (l. 236–238) | Ainda não confirmado no LIVE: não há evidência de execução deste envelope. Verificar na auditoria estática do E03. Se falhar em execução, o caso é FAIL de harness, nunca PASS |
| N-2 | Nomes abreviados no contrato (2.3/2.4 "COMPOSITION_IMMUTABLE", 2.5 "TRAIT_INACTIVE") × tokens LIVE `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` / `EDITION_CONTEXT_TRAIT_INACTIVE:` | O P3 exige prefixo de MESSAGE_TEXT; o prefixo usado é o token LIVE completo, que contém o nome do contrato. Leitura a confirmar pelo auditor; não é alteração do contrato |
| N-3 | (L3) 2Q.8 e 2Q.10 exigem tokens literais sem marcador | Registrado aqui para o L3: `external_set_id` marcado ou `is_active = false`, sem colisão com mapping ativo do LIVE; o resíduo é provado por contagem (o E99 procura o marcador só em `normalized_token`) |
| N-4 | Decisões aplicáveis ao L1 | DP-1 (tempo), DP-4 (`lock_timeout`), DP-5 (autorização de escrita transitória nas 3 tabelas) |

**Tempo esperado:** da ordem do E01 (251 ms: 12 casos, 11 INSERTs), sem medição prévia. O aceite continua ≤ 60 000 ms (AD-2, se estendida pelo DP-1).

## 8. Decisões que dependem de Fabrício

| # | Decisão | Afeta |
|---|---|---|
| DP-1 | Estender a adaptação AD-2 (tempo medido no próprio LIVE, limite duro de 120 s, aceite ≤ 60 s) aos novos lotes, ou exigir P9b em ambiente isolado (D-1), como diz a letra do P9(b) | todos os 13 lotes |
| DP-2 | Aceitar o desvio de ordem de 2.6 e 3.3 (L5); e, se quiser, antecipar L8/L9 | ordem dos lotes |
| DP-3 | Precheck complementar por lote (E00 intacto) **ou** sucessor versionado do E00 | I-1, I-4 |
| DP-4 | `SET LOCAL lock_timeout` nos novos envelopes. A decisão D-3 (opção b) cobriu só o E01 | todos os lotes que escrevem |
| DP-5 | Autorização de escrita transitória com rollback integral, lote a lote, nomeando as tabelas | L1–L8, L11, L12 |
| DP-6 | Trilha de correção da 960 (§6.4) e, se quiser, dos achados O-1 a O-4 | consistência documental; não bloqueia lotes |

## 9. Limites desta rodada

- Nenhum SQL executado, nenhum acesso ao LIVE; nenhuma alteração em schema, migrations, funções, validações, envelopes ou na 2830 v7.0.
- 6.1/6.2 não adjudicados; P9A-05 e P9b não executados.
- Nenhum caso declarado PASS além dos 17 publicados.
- As afirmações sobre comportamento do PostgreSQL (ordem de triggers, SQLSTATE `P0001` de `RAISE EXCEPTION` sem ERRCODE, `GROUP BY` com NULL) vêm da documentação do motor e do código do repositório. Nesta rodada, elas **não** foram observadas no LIVE.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-PHASE5-AUTOMATED-COVERAGE-READINESS-01`, baseline `0ec2f5dc`), documental, sem SQL e sem acesso ao LIVE.**<br>• Gate A conforme, com achados O-1 a O-4;<br>• matriz 135/135 extraída do contrato: 17 PASS-LIVE, 31 PARCIAL, 87 NÃO-IMPL;<br>• inventário: 13 envelopes e 6 componentes de infraestrutura faltantes;<br>• DAG e 13 lotes em ordem contratual, com desvio declarado (2.6/3.3);<br>• separação ambiente isolado × P9b;<br>• análise da 960 (E-1 a E-6, correção mínima proposta);<br>• readiness do L1 (13 casos);<br>• decisões DP-1 a DP-6.<br>Sem STOP. FREEZE ATIVO. |
