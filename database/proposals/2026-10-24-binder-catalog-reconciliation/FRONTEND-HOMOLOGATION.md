# Novidades do Catálogo no fichário — testes de interface e homologação controlada

| Campo | Valor |
|---|---|
| Rodada | `BINDER-CATALOG-RECONCILIATION-FRONTEND-01` (2026-10-25) |
| Escopo | Interface local sobre as RPCs LIVE 5265 (aviso, prévia) e 5266 (incorporação) |
| Estado | **Homologado pelo proprietário (funcional e visual), 2026-10-25** — registrado em `BINDER-CATALOG-RECONCILIATION-FINAL-CLOSEOUT-01` (README §18). Roteiro original preservado abaixo. |

A incorporação (passo H5 em diante) grava reservas no LIVE. Só com autorização expressa de Fabrício, na ordem abaixo, parando no primeiro desvio.

## 1. Preparação (somente leitura)

- `npm run typecheck`, `npm run lint`, `npm run build` em `web/` (lint/build rodados pelo proprietário).
- Q90.7 e Q90.8 do `LIVE-RUNBOOK-H-A.md` antes de começar (estado de referência: 1 novidade — Chi-Yu 059 Holo Reversa —, prévia IN_PLACE em 13·1·3, 360 bolsos, 164 livres). Divergiu → parar e reavaliar.

## 2. Caso Chi-Yu (Escuridão Absoluta, coleção `223eb120-…`) — ordem obrigatória

| # | Passo | Esperado | Grava? |
|---|---|---|---|
| H1 | Abrir o fichário (rota `/fichario` e overlay da coleção) | Trilho mostra "Novidades do Catálogo" com contador **1**; leitor de tela anuncia uma vez | não |
| H2 | Abrir o diálogo | 1 item "Chi-Yu · 059 · Holo Reversa", marcado, com selo "Já no fichário"; nota sobre liberadas | não |
| H3 | "Ver prévia" | "1 novidade pronta para incorporar; nenhum bolso com conteúdo se move."; Capacidade 360; Livres depois 164; Itens que mudam 0; Página afetada 13; item "Reserva no bolso livre página 13, linha 1, coluna 3. Nada se move."; nenhuma confirmação extra | não |
| H4 | Desmarcar, Esc, Voltar, Tab/Shift+Tab, setas | Botão de prévia desliga sem seleção; Esc fecha; foco preso no diálogo e devolvido ao botão do trilho; setas não viram a página | não |
| H5 | **(autorizado)** "Incorporar 1 novidade" | Aviso "1 novidade foi incorporada ao fichário."; página 13 relida com reserva em 13·1·3; botão some do trilho | **sim** |
| H6 | Q90.4/Q90.7 depois | 1 linha em `collection_layout_catalog_incorporation`; novidade com `is_reserved` true / `is_novelty` false | não |
| H7 | Reabrir o fichário | Sem botão de novidades (lista vazia) | não |
| H8 | Liberar a reserva de 13·1·3 pelo fichário (fluxo existente) | Reserva some; **a novidade não volta** ao trilho (W5) | sim (liberar) |
| H9 | Prévia antiga reaproveitada (duas abas: incorporar numa, confirmar na outra) | Segunda aba: "já estavam incorporadas" (ALREADY_APPLIED) ou recusa com prévia refeita; nada duplicado | não |

## 3. Casos de interface sem gravação

| Caso | Como provocar | Esperado |
|---|---|---|
| Pokédex | Abrir fichário de coleção Pokédex (ex.: Minha Pokédex) | Nenhuma chamada a `get_my_binder_catalog_novelties` (aba Rede) e nenhum botão |
| Set / Livre | Coleção STANDARD_SET (Celebração de 30 Anos) | Nenhuma chamada, nenhum botão |
| Arquivada | Coleção MASTER_SET arquivada | Nenhuma chamada, nenhum botão |
| Convidada Master Set em fichário de dona Pokédex | — | RPC responde inelegível → nenhum botão |
| PLAN_CHANGED | Ver prévia; em outra aba mover/fixar um bolso da cadeia; incorporar | Mensagem "O fichário ou o Catálogo mudou…"; lista e prévia relidas automaticamente |
| BLOCKED / NEEDS_REVIEW / NO_ANCHOR | Fixar o bolso de destino (ou cadeia) antes da prévia | Resumo com o motivo, item com selo "Bloqueada"/"Precisa de revisão", botão Incorporar desligado, atalho "Desmarcar e ver a prévia de novo" quando houver outras |
| Página / página nova | Fichário sem bolso livre após o destino | Caixas "Entendi que bolsos passam para a página seguinte" e/ou "Adicionar a página N"; Incorporar só acende com as exigidas marcadas |
| Sessão expirada | Expirar a sessão e pedir prévia | "Sua sessão expirou…" |
| Responsivo | 375 px, 768 px, ≥ 1280 px; tema claro e escuro do app | Diálogo cabe (lista rolável), alvos ≥ 18 px nas caixas, contraste do selo e das mensagens legível |
| Movimento reduzido | `prefers-reduced-motion` | Sem animações novas além das herdadas do diálogo |

## 4. Critério de GO para publicação

H1–H9 conformes (H5/H8 só com autorização), casos da §3 conformes, lint e build PASS na máquina do proprietário. Qualquer desvio → parar, registrar, decidir.
