# Collection — Checkpoint de Pausa da Fase Visual/Experimental (2026-08-29)

| Campo | Valor |
|--------|-------|
| **Documento** | Checkpoint de Pausa — Fase Visual/Experimental de Collections |
| **Arquivo** | `docs/domain-modeling/collections/checkpoint-2026-08-29.md` |
| **Data** | 2026-08-29 (nome de arquivo pedido explicitamente por Fabrício; produzido em 2026-08-30, ver nota de data em `ux-exploration-2026-08-29.md`) |
| **Origem** | `COLLECTIONS-UX-EXPLORATION-CLOSEOUT-01` — instrução explícita de Fabrício para encerrar temporariamente a exploração visual e consolidar o aprendizado antes de retomar a modelagem de domínio. |
| **Objetivo** | Registrar: (1) a fase visual experimental como pausada; (2) que a Collection Library está suficientemente definida; (3) que a UX do Binder está suficientemente validada para informar o domínio; (4) a próxima frente oficial e seu primeiro foco. |
| **Documentos Relacionados** | `checkpoint-2026-08-28.md` (checkpoint anterior, reconciliação de ownership — não superado, complementar a este), `ux-exploration-2026-08-29.md` (mesma pasta, consolidação completa do aprendizado), `concept-decisions.md`, `logical-model.md`. |

---

## 1. Estado que este checkpoint assume como ponto de partida

- Conceitual: `concept-decisions.md`, C-01 a C-37 — CLOSED, inalterado.
- Lógico: `logical-model.md`, LDM-01 a LDM-27 — inalterado desde `checkpoint-2026-08-28.md` (LDM-25/26/27 seguem superseded; novo tópico de LDM-28 segue void/aberto, ver aquele checkpoint §4/§9).
- Físico: NÃO iniciado — continua não iniciado após este checkpoint.
- Visual/experimental: `app/experimental/collection-*` (Collection Library) e `app/experimental/binder-nav-01` (Binder Workspace) — ambos com múltiplas rodadas concluídas, ver `ux-exploration-2026-08-29.md` para o inventário completo.

---

## 2. Fase visual experimental — PAUSADA

A partir desta data, nenhuma nova rodada de exploração visual/experimental de Collections será aberta sem pedido explícito novo de Fabrício. Isso inclui: nenhum modo novo de Collection Library, nenhuma reabertura de Hero Card/Hero Artwork/Complete Shelf/Character Wave para os contextos já decididos, nenhuma nova funcionalidade no Binder Workspace, nenhum novo spike. Correções de bug pontuais isoladas (não visuais/exploratórias) permanecem fora deste escopo de pausa, a critério de Fabrício quando surgirem.

---

## 3. Collection Library — suficientemente definida

Fechamento formal já registrado em `docs/log.md` (2026-08-29, `COLLECTION-LIBRARY-VIEW-MODES-01`) e detalhado em `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` §13: três modos oficiais (Lista/Cards/Carrossel), Cards como padrão inicial, mesmo núcleo de dado nos três. Nenhuma decisão de apresentação pendente para retomar — ver `ux-exploration-2026-08-29.md`, Seção A, para o detalhamento.

## 4. Binder UX — suficientemente validado para informar o domínio

O spike `binder-nav-01` validou, por implementação e uso repetido (não só desenho), os seguintes comportamentos que a modelagem lógica/física de Collections vai precisar suportar: posicionamento livre de carta em slot (Placement), troca atômica entre dois slots (Swap), bloqueio de posição (Lock), remoção sem destruição de identidade (Remove), estado transitório de "fora de slot" (Bandeja), seleção múltipla e operação em lote, e navegação puramente estrutural (sem afetar dado). Ver `ux-exploration-2026-08-29.md`, Seções B–F e "Implicações dos spikes para o modelo de Collections" (12 itens), para o detalhamento completo — este checkpoint não repete o conteúdo, só confirma que ele está pronto para ser consultado quando a modelagem lógica for retomada.

Nenhuma dessas validações é, em si, uma decisão de modelagem — são evidência de comportamento observado, que a modelagem formal ainda precisa traduzir em entidades/campos quando retomada (ver `ux-exploration-2026-08-29.md`, Seção "Classificação dos aprendizados", para o que já foi filtrado como DOMAIN vs. o que é só produto/UX).

## 5. Próxima frente oficial

**Collections Domain Modeling** — retomada da modelagem lógica/física interrompida em `checkpoint-2026-08-28.md` (LDM-25/26/27 superseded, novo tópico de LDM-28 ainda não aberto).

**Primeiro foco declarado**: Binder Layout / Slot / Placement / operations — nesta ordem de prioridade, por ser a área com mais evidência de comportamento fresca (spike `binder-nav-01`) e a que mais implicações novas gerou nesta rodada (12 itens em `ux-exploration-2026-08-29.md`, a maioria tocando exatamente esses quatro conceitos).

Pontos que a modelagem lógica precisará resolver quando retomada, combinando o que já estava aberto em `checkpoint-2026-08-28.md` §9 com o que emergiu desta rodada:

1. Transferência de Inventory Item entre Inventories de usuários diferentes (já aberto em `checkpoint-2026-08-28.md`).
2. Modelo físico de `Inventory` — cardinalidade, criação automática vs. explícita (já aberto).
3. Modelo de `Favorite` — cardinalidade, dono, uso (já aberto; `ux-exploration-2026-08-29.md` reforça com evidência de comportamento que a referência é a `Card`, não a `Placement`).
4. **Novo, desta rodada**: modelo formal de `Slot`/`Placement` — como um Slot se relaciona com uma Page/Binder, como um Placement referencia Inventory Item + Slot, e como Lock se anexa a um Placement (não a uma carta nem a uma Collection inteira).
5. **Novo, desta rodada**: se e como a Bandeja/estado "sem placement" precisa de representação formal, ou se permanece puramente client-side (indicação do spike: provavelmente a segunda opção, ver `ux-exploration-2026-08-29.md` item 8).
6. Pontos já listados em `logical-model.md` §7 e reafirmados em `checkpoint-2026-08-28.md` §9.4, não afetados por este checkpoint: Storage (ownership, sharing, movimentação), matriz de permissões completa de Collection Member, Audit Log transversal.

---

## 6. O que este checkpoint explicitamente NÃO faz

Por instrução direta de Fabrício:

- não altera `concept-decisions.md` nem `logical-model.md` — fica para quando a modelagem lógica for de fato retomada;
- não implementa código, migration, tabela, RPC, rota ou componente;
- não resolve nenhum dos pontos listados na Seção 5 acima — só os enumera como próximo foco;
- não inventa decisões além das já registradas em `ux-exploration-2026-08-29.md` e nos checkpoints anteriores.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste checkpoint (2026-08-30, nome de arquivo datado 2026-08-29 por pedido explícito) — registra a pausa formal da fase visual/experimental de Collections, confirma Collection Library e Binder UX como suficientemente definidos/validados para informar o domínio, e declara a próxima frente oficial (Collections Domain Modeling, primeiro foco Binder Layout/Slot/Placement/operations). Complementar a `checkpoint-2026-08-28.md`, não o substitui. |
