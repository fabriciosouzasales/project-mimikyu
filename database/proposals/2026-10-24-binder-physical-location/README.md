# BINDER-PHYSICAL-LOCATION — Fichário Digital = fichário físico; posição = exemplar

| Campo | Valor |
|---|---|
| Rodadas | ELIGIBILITY-DECISIONS-01 (proposta) → **IMPLEMENTATION-READINESS-01** (2026-10-24: decisões D1–D3, expand/contract, recuperação, frontend local) |
| Status | **FASE A CONFIRMADO EXECUTADO NO LIVE (2026-10-24)** — 5247–5255 aplicadas (ledger `20261024120931`…`20261024121921`), LIVE_50 (1ª) PASS, ver `LIVE-PHASE-A-2026-10-24.md`. **Fase B (5256) NÃO aplicada**; harness 5854 não rodou; frontend novo só local (sem deploy, sem commit). Promoção para `database/schema/` só após LIVE_90. |
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
