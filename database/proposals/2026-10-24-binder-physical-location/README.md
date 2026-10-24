# BINDER-PHYSICAL-LOCATION — Fichário Digital = fichário físico; posição = exemplar

| Campo | Valor |
|---|---|
| Rodadas | ELIGIBILITY-DECISIONS-01 (proposta) → **IMPLEMENTATION-READINESS-01** (2026-10-24: decisões D1–D3, expand/contract, recuperação, frontend local) |
| Status | **FASE A CONFIRMADO EXECUTADO NO LIVE (2026-10-24)** — 5247–5255 aplicadas (ledger `20261024120931`…`20261024121921`), LIVE_50 (1ª) PASS, ver `LIVE-PHASE-A-2026-10-24.md`. **Fase B (5256) CONFIRMADO EXECUTADO** (ledger `20261024132349`, LIVE_90 7/7 PASS, ver `LIVE-PHASE-B-2026-10-24.md`); frontend publicado em `0389498`; harness 5854 não rodou. **ENCERRADA (2026-10-24, `BINDER-PHYSICAL-LOCATION-FINAL-CLOSEOUT-01`)**: 5247–5256 promovidas para `database/schema/` (só o bloco Status difere; ver §Encerramento). |
| Depende de | P3-A (5244–5246) no LIVE; canônicas 5024, 5046/5047, 5118, 5122, 5136, 5221/5222, 5224, 5229, 5230 |

## 1. Regra de produto

O Fichário Digital representa um fichário físico. Pode ocupar um bolso todo exemplar **guardado** nele — da proprietária, de convidada, de outra coleção, de nenhuma coleção ou de coleção arquivada. Hoje F001 tem 182 exemplares: 155 posicionados e 27 (incl. Mudkip MEP 057) invisíveis para o fichário.

Decisões de Fabrício incorporadas:

| Decisão | Onde |
|---|---|
| D1 (2ª rodada) arquivada posicionável · D2 desassociar mantém posições · D3 mudar local de carta posicionada exige confirmação e tira do bolso na mesma transação; bolso travado recusa | 5248/5250 · 5253 · 5249/5256 |
| **D1 (readiness)** Organizar armazenamento (5222) com confirmação prévia: informa quantos saem dos bolsos, atômico, trava explícita | 5249 (prévia por coleção + sobrecarga da 5222) |
| **D2 (readiness)** associação de convidadas pelo local físico PRÓPRIO do fichário | **5255** |
| **D3 (readiness)** "Cartas disponíveis": **Todas** por padrão; Desta coleção · Outras coleções · Sem coleção; filtros não mudam a elegibilidade | 5252 (`p_origin`) + frontend |

## 2. Contratos

| # | Contrato | Migration | Fase |
|---|---|---|---|
| C1 | `collection_layout.storage_container_id` NOT NULL, UNIQUE, FK RESTRICT, imutável; local BINDER do mesmo dono; herda o padrão da proprietária na montagem; o local não deixa de ser BINDER. | 5247 | A |
| C2 | Posição pelo **exemplar** (`physical_card_id` NOT NULL, UNIQUE global, FK CASCADE). `collection_allocation_id` legado (NULL permitido, FK SET NULL); na inserção só com o exemplar (5250) grava a alocação vigente — mantém corretas as leituras antigas durante a implantação. | 5248 v1.1 | A |
| C3 | Integridade em qualquer caminho: exemplar do dono do fichário (`PHYSICAL_CARD_NOT_FOUND`) e guardado no local do fichário (`CARD_NOT_IN_BINDER_LOCATION`). | 5248 | A |
| C4 | Escritores com confirmação (D3/D1): `set_physical_cards_storage(local, ids, p_unplace_from_binder)` e `organize_my_collection_storage(..., p_unplace_from_binder)` — **sobrecargas sem DEFAULT**; travam exemplares → posições; bolso travado → `BINDER_POSITION_LOCKED`; sem confirmação → `BINDER_POSITION_CONFIRMATION_REQUIRED`; com confirmação removem a posição antes do UPDATE de local. Prévias: `preview_my_physical_cards_binder_impact(ids, local)` e `preview_my_collection_storage_binder_impact(coleção, local, modalidade)`. | 5249 v2.0 | A |
| C5 | Posicionar `place_my_physical_card_in_slot(coleção, bolso, exemplar)` ADD/REPLACE/UNCHANGED; não grava coleção/alocação/valor. | 5250 | A |
| C6 | Montagem (plano v2) só posiciona exemplares guardados no fichário. | 5251 | A |
| C7 | Leituras: cabeçalho e páginas ganham colunas no fim; **nova** `get_my_collection_binder_unplaced(coleção, limite, início, origem)` (4 args, sem DEFAULT) coexistindo com a de 3 args. | 5252 v1.1 | A |
| C8 | Desassociar mantém posições. | 5253 | A |
| C9 | Transferência da âncora antes de excluir a proprietária. | 5254 | A |
| C10 | Associação e candidatos pelo local do fichário (`NOT_SAME_LOCATION` se o padrão da convidada ≠ local do fichário). | **5255** | A |
| C11 | Proteção sem bypass: gatilho em `physical_card` recusa mudança de local de exemplar posicionado (quem confirmou já removeu a posição); remove a leitura de 3 args. | **5256** | **B** |

## 3. Compatibilidade contratos antigos × novos

| Chamado hoje pelo frontend atual | Depois da fase A | Depois da fase B |
|---|---|---|
| `get_my_collection_binder`, `..._pages` | mesmas colunas + novas no fim (aditivo) | idem |
| `get_my_collection_binder_unplaced(c, l, o)` | **intacta** (5230); continua correta: posição nova grava alocação (C2) | removida (frontend novo não usa) |
| `assign_card_to_slot` | intacta; gatilho só exige que a carta esteja no fichário — no LIVE todas as cartas de participantes sem bolso: 0 | idem |
| `set_physical_cards_storage(local, ids)` (5024) | intacta (carta posicionada ainda se move como hoje) | recusa carta posicionada (gatilho) |
| `organize_my_collection_storage` (5 args) | intacta | recusa carta posicionada (gatilho) |
| `attach_my_collection_to_binder`, candidatos | regra pelo local do fichário (no LIVE: resultado idêntico — F001 = padrão da proprietária) | idem |
| `detach_*` | prévia/resultado com 0 posições removidas (mesmo formato) | idem |
| prévia/montagem do fichário | token `p2a1-plan-v2` (prévia aberta durante o deploy → refazer) | idem |

Ambiguidade de sobrecarga: impossível — as novas assinaturas têm um parâmetro a mais **sem DEFAULT**, então chamadas com os argumentos antigos só casam com as funções antigas (static check S8).

## 4. Sequência segura de ativação (sem janela de incompatibilidade)

1. `LIVE_00` (todas PASS; anotar baseline/md5).
2. **Fase A** — aplicar 5247 → 5248 → 5249 → 5250 → 5251 → 5252 → 5253 → 5254 → 5255 (uma transação por migration; falhou → para; nada parcial).
3. `LIVE_50` (1ª execução): compatibilidade (q03), contratos novos (q04), 155 posições (md5 = LIVE_00), 27 disponíveis.
4. Deploy do **frontend novo** (este diretório `web/`). O frontend antigo continuava funcionando durante 2–4.
5. `LIVE_50` (2ª execução): q05 garante que nenhuma posição ficou fora do local na janela (único efeito possível do frontend antigo: mover carta posicionada pela 5024/5222 antigas).
6. **Fase B** — 5256 (só se q05 PASS).
7. `LIVE_90` + homologação pela interface.

## 5. Recuperação (v2 — FINAL-CORRECTIONS-01)

Três níveis, do menos ao mais invasivo. **Nenhum apaga posição, desaloca, realoca ou exclui dados**; R0 diz qual é admissível no momento.

| Nível | O que é | Scripts | Pré-condição | Dados |
|---|---|---|---|---|
| N1 — recuperação operacional | voltar o frontend à versão anterior; se a fase B existir, R1 antes | R1 (se 5256) | nenhuma | intactos; todas as posições continuam válidas e visíveis (leituras 5252 ficam) |
| N2 — rollback de contratos | remover/restaurar os contratos novos que não dependem do modelo de dados: 5255, 5254, 5253, 5250, 5249 | R1 (se 5256) → **R2A** | nenhuma relativa a dados — **sempre possível**, mesmo com posições de exemplar sem coleção ou de coleção não participante | intactos (R2A não lê nem altera linhas) |
| N3 — rollback do modelo de dados | voltar à posição pela alocação e ao fichário sem local próprio: 5252, 5251, 5248, 5247 | R2A → **R2B** | R0: d03 = 0 e d04 = 0 (o modelo antigo representa todas as posições) | preservados (mesmo id, bolso, alocação, updated_at) |
| Correção posterior | quando N3 é necessário mas inadmissível (d03/d04 > 0) | migration nova, para frente | — | o modelo novo permanece; o defeito é corrigido no lugar |

Regras: falhou durante uma migration → a própria transação desfaz. R2B nunca é forçado: se houver posições não representáveis, o sistema opera em N2 (modelo novo + contratos antigos + frontend anterior) até a correção posterior. Em N2, o frontend antigo pode tentar posicionar carta de participante guardada fora do fichário e receberá recusa do gatilho 5248 (mensagem genérica) — sem efeito sobre dados.

## 6. Frontend local (implementado, não publicado)

- "Cartas disponíveis" e "Adicionar carta" no bolso vazio leem a 5252 com origem; chips **Todas** (padrão) · Desta coleção · Outras coleções · Sem coleção; legenda de origem (inclui "arquivada"); posicionar e "Desfazer" pela 5250 (pelo exemplar). Bolso reservado: só a coleção da reserva.
- Meu acervo › mover em lote: prévia mostra "No fichário digital: N saem dos bolsos" e bloqueia com cadeado; a confirmação envia a contagem vista (`expectedUnplace`) e o servidor recusa se mudou.
- Meu acervo › local do exemplar: recusa do banco abre a confirmação "Tirar do fichário e guardar".
- Organizar armazenamento: a prévia traz o impacto por modalidade; aviso/bloqueio na confirmação; servidor confere a contagem antes da 5222 nova.
- Transferência (5254): server action + lib prontas; **sem UI** (o produto ainda não expõe exclusão de coleção).
- Contracapa, Centro de Controle e demais experiências: sem alteração visual.

## 7. Arquivos

5247–5256 · `5854_validate_binder_physical_location.sql` (53 checagens, fases A+B; NUNCA no LIVE) · `LIVE_00/50/90` · `R0_post_activation_diagnostic_readonly.sql` · `R1_rollback_phase_b.sql` · `R2A_rollback_contracts.sql` · `R2B_rollback_data_model.sql` · `VALIDATION-LOCAL-PG17.md` · `static_check_binder_physical_location.py` (44 itens) · `LIVE_01_precheck_canonical_fingerprint_readonly.sql` · `LIVE-DEPLOYMENT-PLAN.md` · `pg17-validation/` (DESCARTADO — não executado, não é requisito).

## 8. Riscos e bloqueadores

1. **Risco aceito (não bloqueador):** nenhum SQL desta pasta foi executado por um PostgreSQL real; a validação isolada foi descartada pelo proprietário (`pg17-validation/` fica NÃO EXECUTADO, não é requisito). A implantação segue `LIVE-DEPLOYMENT-PLAN.md`: prechecks LIVE_00 + LIVE_01 (somente leitura), migrations uma por vez em transação própria, STOP objetivo por fase. Não há PostgreSQL/parser no ambiente do agente e, por decisão desta rodada, nenhum ambiente Supabase adicional foi criado. A estática (44/44) não prova execução: harness 5854 e R1/R2 precisam rodar num banco descartável antes da janela de implantação.
2. Durante a janela entre fase A e fase B, o frontend antigo ainda move carta posicionada (comportamento de hoje); LIVE_50 q05 detecta e a 5256 aborta se houver caso.
3. A 5222 original continua existindo; após a 5256 ela recusa carta posicionada (seguro).
4. (resolvido em FINAL-CORRECTIONS-01) bolso reservado por outra coleção: recorte, total e paginação passam a ser feitos no servidor (5252 v1.2, `p_origin_collection_id`).
5. Concorrência entre sessões só foi verificada por revisão da ordem de travas.
6. Desmontar continua removendo posições de todas as origens (ação explícita existente); reservas da convidada continuam saindo na desassociação.

## 9. Verificação desta rodada

| Item | Estado |
|---|---|
| static check (44): forma, ACL, aditividade da fase A, sobrecargas sem DEFAULT, 5249/5251/5252/5253/5255 × canônicas, R1/R2 = canônicas, harness | **validado automaticamente — PASS 44/44** |
| typecheck (`tsc --noEmit`) | **validado automaticamente — PASS** |
| testes unitários (`node --test`, 42 arquivos) | **validado automaticamente — PASS** (ver relatório) |
| ESLint nos arquivos alterados | **validado automaticamente — 0 achados** |
| `next lint` / `next build` | pendente (Fabrício, máquina local) |
| LIVE_00/01/50/90, R0/R1/R2A/R2B | não executados — roteiro em `LIVE-DEPLOYMENT-PLAN.md` (prechecks somente leitura aguardam autorização) |
| harness 5854 | não executado; proibido no LIVE; sem ambiente isolado (decisão do proprietário) |
| validação visual (light/dark, mobile) | pendente (sem deploy) |

## Encerramento (BINDER-PHYSICAL-LOCATION-FINAL-CLOSEOUT-01, 2026-10-24)

**Canônicas.** `database/schema/5247_…` a `5256_…`: cópias destes arquivos com **só o bloco `Status`** do cabeçalho alterado; os arquivos desta pasta permanecem byte a byte os aplicados. Equivalência tripla — trecho `begin;`…`commit;` idêntico em proposta e canônica, e md5 do corpo (sem as linhas `begin;`/`commit;`, como enviado ao `apply_migration`) igual ao md5 do texto gravado no ledger do LIVE (leitura de 2026-10-24):

| Migration | Ledger | sha256(16) `begin;`…`commit;` | md5 corpo = ledger |
|---|---|---|---|
| 5247 | `20261024120931` | `4540264c12f25d28` | `db44b9dbf74ad49798c838fb5ae6e146` |
| 5248 | `20261024121040` | `2966699c34d83732` | `5f7b4b59f5ca15a46ab134388010efaa` |
| 5249 | `20261024121212` | `6ed114758c943a94` | `d745677774d3ffab6c8015b3078e209b` |
| 5250 | `20261024121312` | `1dc7e9c3621c9d03` | `842d80bf744f44e179a3c3c596b22ce2` |
| 5251 | `20261024121421` | `13e91f648b41a445` | `cc87d51c394a71e1752d70a2f7511b5a` |
| 5252 | `20261024121613` | `ee523687ad9ed207` | `fad9adda3e0a896a765256230c807b46` |
| 5253 | `20261024121715` | `6151ed192c618290` | `d9a3a70c768a4369b801e70f1f8731aa` |
| 5254 | `20261024121820` | `9797ac7cc6ae5d76` | `213f1a358260b4180e11c536f674f18a` |
| 5255 | `20261024121921` | `f380801a301191ab` | `07e7355413d2b7103d8865af8c2cc60b` |
| 5256 | `20261024132349` | `b48415c96c216725` | `7d32fce9f55f78727caaa3635f72858a` |

**Evidências.** Fase A 9/9 + LIVE_50 (1ª) 9/9 (`LIVE-PHASE-A-2026-10-24.md`); frontend publicado no commit `0389498` e homologado pela interface (Fabrício), incluindo o posicionamento das 27 cartas MEP em F001; LIVE_50 (2ª) q01–q08 PASS, q09 = baseline histórico de disponibilidade (§5 do mesmo arquivo); Fase B 5256 + LIVE_90 7/7 PASS (`LIVE-PHASE-B-2026-10-24.md`). Estado final: F001 40 páginas / 360 bolsos / 182 posições; F002 1 página / 16 bolsos / 0 posições; 158 reservas; 211 alocações; 0 travados; fingerprints `assignments` `b010d1de3453373f741d994e3f2f839b`, `layouts` `b0906e79695b8a049b9120d99d4f7079`, `allocations` `a180e923764e3b5a9cb225ee68f873c0`, local dos exemplares `b7f9597e7b042d60fc7475ef5ffedb3b`.

**Não executado (sem prova correspondente):** harness `5854`; recuperação `R0`/`R1`/`R2A`/`R2B`; pacote `pg17-validation/` (descartado pelo proprietário). A proteção da 5256 não foi provocada no LIVE.

**Pendências residuais:** emenda formal em `docs/domain-modeling/collections/concept-decisions.md` (C-195 cita "local padrão de algum participante" e C-197 "desassociar remove as posições") fora do escopo desta rodada — a regra vigente está registrada em `05d` (revisão 2.14) com a supersessão explícita; concorrência real e desempenho com volume não medidos; `static_check` e arquivos `LIVE_*`/`R*` permanecem como evidência/ferramenta nesta pasta.
