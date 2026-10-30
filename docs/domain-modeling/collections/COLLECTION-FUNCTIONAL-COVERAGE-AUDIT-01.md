# COLLECTION-FUNCTIONAL-COVERAGE-AUDIT-01 — Auditoria de cobertura funcional de Collection

| Campo | Valor |
|--------|-------|
| **Documento** | Relatório de auditoria (gate de decisão do proprietário) |
| **Arquivo** | `docs/domain-modeling/collections/COLLECTION-FUNCTIONAL-COVERAGE-AUDIT-01.md` |
| **Versão** | 1.0 |
| **Data** | 2026-10-29 |
| **Natureza** | **Histórico-factual e de recomendação. Não é fonte normativa.** Nenhuma decisão foi aprovada, revogada ou reaberta por este documento. Prioridades P0–P3 são recomendações sujeitas à decisão do proprietário. |
| **Escopo** | Módulo Collection (Acervo, Coleções, Fichário Digital, Locais, Favoritos, Wishlist, Relatórios e colaboração). Pokédex P7–P9, Dashboard e Conexão Inteligente só onde tocam Collection. |
| **Estado de referência** | Repositório em `c755289` (árvore limpa, sincronizada com `origin/main`), 2026-10-29. |
| **Restrições cumpridas** | Sem alteração de banco, migrations, frontend ou ROADMAP; sem SQL; sem commit, push ou deploy. BULK-05/BULK-06 e `BINDER-GRID-RECONFIGURATION` não reabertos. |

**Fontes lidas.**
- **Normativas:**
  - `concept-decisions.md`: C-01 a C-209, lido integralmente.
  - `logical-model.md`: banner de superação e LDM-25 a LDM-27.
  - `north-star-2026-10-16.md` (v1.19): NS-01–NS-18, fluxos, nomenclatura, B1–B8 e §7.
  - `05d-colecoes-e-usuarios.md`, `ROADMAP.md` (2.54) e `HANDOFF-2026-10-15.md` (1.80).
  - `architecture/ubiquitous-language.md`.
- **Históricas:** checkpoints 2026-08-28, 08-29, 08-30 e 10-15; `ux-exploration-2026-08-29.md`; `pkmnbindr-benchmark.md`; READMEs de `database/proposals/*` de Collection.
- **Implementação:**
  - rotas `web/app/colecoes/**`, componentes e `actions.ts`;
  - chamadas `.rpc()` do frontend;
  - funções em `database/schema/`;
  - `5030_create_collection_table.sql`;
  - `git log` e `git status` (somente leitura).

**Método.**
1. Inventário por leitura contextual completa das fontes normativas, não por busca textual isolada.
2. Cruzamento de cada capacidade com:
   - as chamadas reais do frontend (evidência de implementação);
   - os registros de homologação no `docs/log.md` e no `05d` (evidência de homologação);
   - o estado do git (evidência de publicação: tudo o que está implementado está commitado e no `origin/main`).
3. Classificação contra a Etapa 1 do ROADMAP 2.54.

Ideias recorrentes em vários documentos foram consolidadas em uma única linha.

---

## 8.1 Resumo executivo

Foram identificadas **69 capacidades distintas** de Collection, já consolidadas entre os documentos.

| Classificação | Qtde | Leitura |
|---|---:|---|
| IMPLEMENTADO | 19 | Entregue, commitado e no `origin/main`; não volta ao backlog. |
| COBERTO | 8 | Já está explicitamente na Etapa 1 do ROADMAP 2.54. |
| **LACUNA CONFIRMADA** | **9** | Aprovado no passado, não implementado e ausente do plano vigente. |
| COBERTURA PARCIAL | 5 | Há implementação ou previsão, mas incompleta. |
| HOLD / ADIADO | 12 | Postergação explícita: HOLD, "Later", "rodada própria", pós-MVP ou fora do V1. |
| SUPERADO / REVOGADO | 4 | Decisão histórica substituída. |
| PROPOSTA NÃO APROVADA | 6 | Benchmark ou spike sem compromisso. |
| INDETERMINADO | 6 | Documentação insuficiente ou contraditória. |

**Lacunas principais**, aprovadas e fora do plano:
1. **Compartilhamento de coleção com outros usuários** (C-141–C-165) e **visibilidade pública** (C-15, C-151, C-152): aprovados em 2026-08-30, sem modelo físico e sem nenhuma menção na sequência vigente. Ver §8.4.
2. **Arquivar, reativar e excluir coleção** (C-06, C-13, C-37; nomenclatura N26 homologada): backend no LIVE desde 2026-09-01, sem interface e fora da Etapa 1. A Etapa 1 inclui desmontar fichário, mas não o ciclo de vida da própria coleção.
3. **Fluxos 2 e 5 da North Star dentro da coleção:** adicionar cartas e Set inteiro a partir da própria coleção, e continuidade após a criação (Fluxo 1.6). São normativos (NS §2), mas hoje só existem no Meu acervo.
4. **Condição do exemplar** (C-103–C-120) e **Graduação** (C-121–C-140): conceitos fechados, sem modelo físico, fora da Etapa 1. A condição influencia preço e a Conexão Inteligente.
5. **Critérios B1–B8 da North Star:** gate normativo da "base funcional" que condiciona P7–P9 (NS-10). Nenhum foi registrado como aprovado, e a Etapa 1 não os cita como critério de encerramento.

**Resposta ao critério de sucesso.** Para encerrar Collection sem compromissos esquecidos, o proprietário precisa decidir sobre os itens de §8.8:
- colaboração multiusuário;
- ciclo de vida da coleção;
- Fluxos 2 e 5 na coleção;
- condição e graduação;
- B1–B8 como critério de saída;
- a sobreposição Coleção Pokédex × P7.

O restante já está implementado, coberto, adiado de forma explícita ou é proposta sem compromisso.

---

## 8.2 Matriz de rastreabilidade

**Legenda de status:**
- **IMPL** = implementado e publicado no git;
- **BE** = só backend (LIVE, sem UI);
- **—** = inexistente.

Fontes abreviadas:
- **CD** = `concept-decisions.md`
- **NS** = North Star
- **RM** = ROADMAP
- **HO** = HANDOFF
- **BM** = benchmark
- **CP** = checkpoint

### Acervo e exemplares

| ID | Funcionalidade | Fonte (decisão) | Status normativo | Implementação | Roadmap 2.54 | Classificação |
|---|---|---|---|---|---|---|
| AC-01 | Registrar exemplares, um a um ou em lote, com prévia | CD C-03, C-47/48, C.4; NS Fluxo 2 | Aprovado | IMPL: `/colecoes/acervo`, `register_physical_cards_bulk`, `preview_bulk_operation` | — | IMPLEMENTADO |
| AC-02 | Adicionar Set inteiro (BULK-04) | 05d 1.30; NS Fluxo 5 | Aprovado | IMPL: `register_card_set_bulk` | — | IMPLEMENTADO |
| AC-03 | Ajustar cópias e remover exemplar cadastrado por engano | 05d 1.31 (5165) | Função aprovada; "correção de cadastro" sem C-*/LDM-* (RM l.65) | IMPL | — | IMPLEMENTADO (pendência só documental) |
| AC-04 | Busca, filtros (Set, idioma, coleção, local) e ordem no acervo | NS N-*; 5160 | Aprovado | IMPL | — | IMPLEMENTADO |
| AC-05 | **Condição do exemplar** (escala M/NM/LP/MP/HP/DMG; filtro "NM ou superior") | CD C-103–C-120 (2026-08-30; ajustes em 08-31) | Aprovado | — (`physical_card` não tem coluna de condição; `card_condition` só existe em Pricing) | Ausente | **LACUNA CONFIRMADA** |
| AC-06 | **Graduação/certificação** (empresa, grade, nº, raw/graded) | CD C-121–C-140 | Aprovado | — | Ausente | **LACUNA CONFIRMADA** |
| AC-07 | Dados de aquisição (valor pago, data, origem) | CD C-70 | Aprovado | — | RM "Later: Aquisição e movimentação" (não comprometido) | HOLD / ADIADO |
| AC-08 | Saída patrimonial (venda externa, descarte) | CD C-72 | Aprovado | — | RM "Later" | HOLD / ADIADO |
| AC-09 | Transferência de exemplar entre usuários MMKYU | CD C-71; CP28 §9.1 (mecanismo não modelado) | Aprovado como conceito | — | RM "Later" | HOLD / ADIADO |
| AC-10 | Custódia: emprestado, em graduação, perdido/recuperado | CD C-49–C-52 | Aprovado (Custodian e "em trânsito" são futuros) | — | Ausente | **LACUNA CONFIRMADA** (baixa prioridade) |
| AC-11 | Disponibilidade para troca/venda | CD C-53/C-54 | Aprovado ("não é enum definitivo") | — | Implícita na Etapa 4, Nível 2 ("exemplares voluntariamente disponibilizados") | COBERTURA PARCIAL |
| AC-12 | Proteção (sleeve/toploader/slab) | CD Parte D; CP30 | Reconhecido, não modelado | — | — | HOLD / ADIADO |

### Coleções

| ID | Funcionalidade | Fonte | Status normativo | Implementação | Roadmap | Classificação |
|---|---|---|---|---|---|---|
| CO-01 | Coleção de Set | CD C-01, C-32; NS Fluxo 1 | Aprovado | IMPL (5167) | — | IMPLEMENTADO |
| CO-02 | Coleção livre (CT-01, cor, capa, código) | NS-16, CT-01 | Aprovado | IMPL (5175–5180) | — | IMPLEMENTADO |
| CO-03 | Coleção Pokédex ("Completar a Pokédex") | 05d PKX-01/02/03; log 2026-10-19 | Aprovado e homologado localmente | IMPL (5201–5211) | **Etapa 2 ainda lista "P7 — Minha Collection Pokédex"** | IMPLEMENTADO (contradição: ver D6) |
| CO-04 | Master Set com objetivo configurável e prévia | CD C-23, C-187–C-190 | Aprovado | IMPL (5184–5200) | — | IMPLEMENTADO |
| CO-05 | Renomear e editar capa, logo e código | CD C-150 | Aprovado | IMPL (`update_collection_metadata`) | — | IMPLEMENTADO |
| CO-06 | Biblioteca com três modos e ordem manual | Decisão 29/08; 5181–5183 | Aprovado | IMPL | — | IMPLEMENTADO |
| CO-07 | Vincular/desvincular exemplares; sugerir elegíveis | CD C-19, C-29; NS Fluxo 3.5 | Aprovado | IMPL (5046/5047, `linkOneOfEach`, candidatos) | — | IMPLEMENTADO |
| CO-08 | **Arquivar e reativar coleção** | CD C-06, C-30, C-37; NS N26 "Arquivar/Arquivadas" (HOMOLOGADO) | Aprovado | BE: 5037/5038, sem chamador no `web/` | Ausente | **LACUNA CONFIRMADA** |
| CO-09 | **Excluir coleção** (só sem exemplares; recusa se houver fichário) | CD C-13, C-194 | Aprovado | BE: 5039/5226/5229, sem chamador no `web/` | Ausente (a Etapa 1 só traz "excluir fichário") | **LACUNA CONFIRMADA** |
| CO-10 | **Fluxo 1.6 + Fluxo 2 e Fluxo 5 dentro da coleção** ("Adicionar cartas" sempre presente; sucesso leva ao Fluxo 2/5) | NS §2 (normativo), NS §7 l.440–442 | Aprovado (normativo) | Parcial: na coleção só se vinculam exemplares já no acervo; registro novo só no Meu acervo | Ausente | **LACUNA CONFIRMADA** |
| CO-11 | Progresso Tenho/Faltam e repetidas visíveis | NS Fluxo 3 (3.3 [D C-21]); N12 | Aprovado (Tenho/Faltam é [H]) | Tenho/Faltam IMPL; exibição de repetidas na coleção não verificada; sem homologação formal | — | COBERTURA PARCIAL |
| CO-12 | Busca, filtro e ordem na Biblioteca | BM §24, PX-06 | Candidato | Só modos e ordem manual | — | PROPOSTA NÃO APROVADA |
| CO-13 | Conversão de modo/referência após o lock | CD C-09, C-11 | Exige "fluxo explícito", nunca modelado | — | — | INDETERMINADO |
| CO-14 | Escopo dinâmico com aprovação da expansão pelo usuário | CD C-02 | Aprovado | Parcial: só "Novidades do Catálogo" no fichário Master Set (C-200) | — | COBERTURA PARCIAL |
| CO-15 | Rule-Based Membership (inclusão automática por regra) | RM l.392 (de ADR-014, Substituído) | "Lacuna a esclarecer" | — | — | INDETERMINADO |
| CO-16 | Retirar exemplares da coleção em lote | 05d l.1880; NS l.449 | Fora de escopo por escolha (um a um) | — | — | HOLD / ADIADO |
| CO-17 | Cascata da 5047: desvincular remove a posição do fichário e da Pokédex | 05d l.1874; NS l.449 ("bloqueante antes do Fichário aberto") | Risco registrado | O fichário foi publicado; não há registro de resolução | — | INDETERMINADO (verificar) |

### Compartilhamento, colaboração e visibilidade (detalhe em §8.4)

| ID | Funcionalidade | Fonte | Status normativo | Implementação | Roadmap | Classificação |
|---|---|---|---|---|---|---|
| SH-01 | **Membros da coleção (EDITOR/VIEWER): convite, aceite, saída, remoção; histórico visível aos membros** | CD C-08 (vigente em parte), C-141–C-165, C-172 | Aprovado (2026-08-30) | — (sem tabela, RPC ou UI; todas as leituras são `get_my_*`, só do dono) | **Ausente** | **LACUNA CONFIRMADA** |
| SH-02 | **Coleção PUBLIC e acesso público** | CD C-15, C-151, C-152 | Aprovado | — (`chk_collection_visibility CHECK (visibility IN ('PRIVATE'))`; `set_collection_visibility()` adiada) | **Ausente** | **LACUNA CONFIRMADA** |
| SH-03 | Link privado para coleção PRIVATE | CD C-163 | "Possibilidade futura, sem mecanismo" | — | — | PROPOSTA NÃO APROVADA |
| SH-04 | Transferir a titularidade da coleção para outro usuário | CD C-12 (SUPERSEDED), C-156 | Superado; "fluxo futuro não decidido" | — | — | SUPERADO / REVOGADO |
| SH-05 | Coleção compartilhada com exemplares de vários membros e aprovação patrimonial do dono do exemplar | LDM-25/26/27 (2026-08-10) | **SUPERSEDED em 2026-08-28** (CP28 §2.6/2.7) | — | — | SUPERADO / REVOGADO |
| SH-06 | Permissões customizadas por usuário e coleção | CD C-08 (frases riscadas) | SUPERSEDED em 2026-08-30 | — | — | SUPERADO / REVOGADO |
| SH-07 | Fichário compartilhado entre coleções **do mesmo dono** | CD C-195–C-197 | Aprovado | IMPL (5229/5230); **não é multiusuário** | — | IMPLEMENTADO |

### Fichário Digital

| ID | Funcionalidade | Fonte | Status normativo | Implementação | Roadmap | Classificação |
|---|---|---|---|---|---|---|
| FI-01 | Criar/montar, páginas, bolsos, cadeado, bandeja, seleção, fixar carta presente | CD C-38–C-46, C-191–C-193 | Aprovado | IMPL | — | IMPLEMENTADO |
| FI-02 | Imagens personalizadas e regiões mescladas | CD C-198 | Aprovado | IMPL | — | IMPLEMENTADO |
| FI-03 | Identidade (nome, cor, contracapa) | P3-A | Aprovado | IMPL | — | IMPLEMENTADO |
| FI-04 | Referência de espécie nos bolsos (Pokédex) | CD C-199 | Aprovado | IMPL | — | IMPLEMENTADO |
| FI-05 | Novidades do catálogo (Master Set) | CD C-200 | Aprovado | IMPL | — | IMPLEMENTADO |
| FI-06 | Histórico do fichário | CD C-201–C-209 | Aprovado | IMPL (`2ca2b19`, no `origin/main`; o README da P3-B registra "deploy da S7 não realizado") | — | IMPLEMENTADO (publicação a confirmar) |
| FI-07 | Reserva de bolso **vazio** para uma carta específica | CD C-42 | Aprovado | Só existe "fixar" a carta presente (`reserveSlot`) | Etapa 1 | COBERTO |
| FI-08 | Lupa e detalhe da carta no fichário | UX spike Card Detail | — | — | Etapa 1 | COBERTO |
| FI-09 | Desmontar/excluir fichário (E19/E19b) | CD C-194 | Aprovado | BE (5226) | Etapa 1 | COBERTO |
| FI-10 | Transferir a âncora do fichário (E20) | CD C-197 | Aprovado | Server action `transferBinderOwnership` existe, **sem componente que a chame** | Etapa 1 | COBERTO |
| FI-11 | Reconfigurar a grade de fichário existente | CD C-40 | Mecanismo não decidido | — | **HOLD** | HOLD / ADIADO |
| FI-12 | Desfazer/Refazer | CD C-44, C-182 | Futuro | — | — | HOLD / ADIADO |
| FI-13 | Lista de históricos encerrados (C-208); exclusão definitiva do histórico (C-203) | CD | Pós-MVP | BE (5269); 5270 revogada de `authenticated` | — | HOLD / ADIADO |
| FI-14 | Favoritar, Substituir, Buscar, Exportar/Imprimir e Compartilhar dentro do fichário | UX 2026-08-29; `binder-tool-rail.tsx` l.47–48 | Spike, "sem contrato" | — | — | PROPOSTA NÃO APROVADA |
| FI-15 | Estratégia mobile do Tool Rail / K6 | NS l.375/407; HO §7 | Decisão em aberto | — | — | INDETERMINADO |

### Locais (Onde guardo)

| ID | Funcionalidade | Fonte | Status | Implementação | Roadmap | Classificação |
|---|---|---|---|---|---|---|
| ST-01 | Locais, local padrão, mover em lote, organizar a coleção, fichário por local físico | CD C-16–C-28, C-36, C-55–C-64; NS-13 | Aprovado | IMPL (`/colecoes/locais`, WHERE-02 a 05B, 5247–5256) | — | IMPLEMENTADO |
| ST-02 | Hierarquia e reparent de locais | CD C-60, C-65 | Aprovado; "comportamento de produto para rodada própria" | — | — | HOLD / ADIADO |
| ST-03 | Capacidade, histórico de movimentação, divisórias | CD Parte D; WHERE-05A D5 | Fora de escopo | — | — | HOLD / ADIADO |

### Favoritos, Wishlist, valor e relatórios

| ID | Funcionalidade | Fonte | Status | Implementação | Roadmap | Classificação |
|---|---|---|---|---|---|---|
| WF-01 | Favoritos de cartas | CD C-82–C-90 | Aprovado | — (só existe o favorito de espécie, P6) | Etapa 1 | COBERTO |
| WF-02 | Wishlist pessoal com contexto opcional de coleção | CD C-91–C-97, C-95 | Aprovado | — | Etapa 1 | COBERTO |
| WF-03 | Wishlist: quantidade, prioridade, preço-alvo, alertas, refinamento por condição | CD C-98, C-100 | Fora do V1 | — | — | HOLD / ADIADO |
| WF-04 | Grail, ranking, recomendações, notificações | CD C-86 | Futuro | — | — | HOLD / ADIADO |
| VR-01 | Preço nas cartas (Acervo, Coleções, Fichário) | RM; Débito Card Variants item 2 | Comprometido | — | Etapa 1 | COBERTO |
| VR-02 | Valor total do acervo e de cada coleção | Memória de produto 2026-08-23 ("o app existe para o usuário registrar e ver o valor da própria coleção"); RM "Later: Analytics/Valuation" | Sem decisão formal | — | Só implícito em "Relatórios — escopo a definir" | COBERTURA PARCIAL |
| VR-03 | Relatórios de Collection | RM 2.53 | Comprometido, escopo a definir | — | Etapa 1 | COBERTO |
| VR-04 | Importar/exportar arquivo (CSV, outros trackers) | BM PX-04 | Candidato | — | — | PROPOSTA NÃO APROVADA |
| VR-05 | Imprimir placeholders de faltantes | BM PX-07 | Candidato | — | — | PROPOSTA NÃO APROVADA |
| VR-06 | Busca transversal "objeto na mão" (onde está esta carta?) | BM PX-06 | Candidato | Parcial no acervo | — | PROPOSTA NÃO APROVADA |

### Histórico, qualidade e governança

| ID | Funcionalidade | Fonte | Status | Implementação | Roadmap | Classificação |
|---|---|---|---|---|---|---|
| HI-01 | Histórico de atividades da coleção (e não só do fichário) | CD C-166–C-186 | Aprovado | Só o histórico do fichário (P3-B) | — | COBERTURA PARCIAL |
| GQ-01 | **Critérios B1–B8**: fluxos em produção, visual premium homologado, responsivo, desempenho medido, a11y, estados, segurança (`/experimental`), docs reconciliados | NS §4, NS-10 | Aprovado (gate de P7–P9) | Nenhum registrado como aprovado; B4 nunca medido | Não citado como critério de saída da Etapa 1 | **LACUNA CONFIRMADA** |
| GQ-02 | R3: medir B4 em ambiente isolado × "o projeto não usa ambiente isolado" | NS l.55/247; HO l.79 | Contraditório | — | — | INDETERMINADO |
| GQ-03 | Rótulo administrativo "Coleções" → "Sets" (N4/K1-A) | NS (decidido); HO/RM ("pendente") | Contraditório | — | — | INDETERMINADO |
| BU-01 | BULK-05 / BULK-06 | RM 2.54 | **Retirados em 2026-10-29** | — | — | SUPERADO / REVOGADO |

---

## 8.3 Lacunas confirmadas

Todas foram aprovadas no passado e estão ausentes ou insuficientemente contempladas no plano vigente.

| # | Lacuna | Valor para o colecionador | Impacto na experiência | Relevância para fechar Collection | Retenção / monetização | Dependências | Esforço relativo | Riscos | Encaixe possível | Prioridade recomendada |
|---|---|---|---|---|---|---|---|---|---|---|
| L1 | **CO-08/CO-09 Arquivar, reativar e excluir coleção** | Alto: hoje uma coleção criada por engano não sai da Biblioteca | Ciclo de vida incompleto; quebra a expectativa básica de controle | Alta: é CRUD elementar | Indireto | FI-09 (excluir coleção com fichário é recusado, C-194) | **Baixo**: as RPCs estão no LIVE e validadas (5804) | Baixos: exclusão destrutiva pede confirmação; arquivada é só leitura (C-37) e a UI deve respeitar | Junto com E19/E19b (desmontar fichário), no mesmo incremento de "gestão de ciclo de vida" | **P0** |
| L2 | **CO-10 Fluxos 2/5 dentro da coleção + Fluxo 1.6** | Alto: "adicionar cartas" é a operação mais frequente | Hoje o usuário precisa ir ao Meu acervo, registrar e voltar para vincular | Alta: é normativo na NS e está no núcleo da baixa fricção | Alto (ativação do primeiro minuto) | Envelopes 5150/5157 já aceitam alocação | Médio: só frontend, reaproveita os seletores do acervo | Integridade: idempotência já provada (BULK-02/04) | Etapa 1, antes de Relatórios | **P1** (P0 se a North Star for mantida como critério de saída) |
| L3 | **GQ-01 Critérios B1–B8** | Indireto | Garante o "premium" e o desempenho com volume real | **Define o que é "Collection concluída"** | — | Resolver GQ-02 (R3) | Médio: homologação e medições, não features | Desempenho com milhares de cartas nunca medido no fluxo real (B4) | Gate final da Etapa 1 | **P0 como critério de saída** |
| L4 | **SH-01/SH-02 Compartilhamento multiusuário e visibilidade pública** | Alto para famílias e grupos; diferencial social | Novo eixo: "minha coleção" vira "nossa coleção" | Média: aprovado, mas só se o proprietário o considerar parte da Etapa 1 | **Alto**: efeito de rede e base para a Etapa 4 | Perfil e username (ADR-020); caixa de convites; revisar todas as leituras `get_my_*` | **Alto**: tabela, RLS, convites, UI e leituras para não-donos | **Alto**: vazamento entre contas (C-157–C-159 restringem o acervo, os locais e a proveniência) | Incremento próprio, com modelagem física e harness de autorização dedicados | **P1** (decisão D1) |
| L5 | **AC-05 Condição do exemplar** | Alto para colecionadores avançados | Exige campo opcional no detalhe do exemplar e no registro em lote (sem bloquear, C-108) | Média | Alto: valor por condição e matching | Pricing já tem o vocabulário `card_condition` | Médio | Baixo; não pode bloquear o bulk (C-70/C-108) | Etapa 1 junto com Preços, ou antes da Etapa 4 | **P2** |
| L6 | **AC-06 Graduação** | Médio/alto (nicho de alto valor) | Selo graduado na carta | Baixa para "fechar" Collection | Alto por valor unitário | AC-05 | Médio | Baixo | Depois da condição | **P3** |
| L7 | **AC-10 Custódia (emprestado, perdido)** | Baixo/médio | — | Baixa | Baixo | — | Médio | Baixo | Futuro | **P3** |

Tratadas como **parciais**, sem virar lacuna nova:
- **AC-11 Disponibilidade:** pré-requisito da Etapa 4, Nível 2.
- **HI-01 Histórico da coleção.**
- **VR-02 Valor total:** recomenda-se que entre explicitamente no escopo de Relatórios (D7).
- **CO-11 Repetidas visíveis.**
- **CO-14 Escopo dinâmico.**

---

## 8.4 Compartilhamento multiusuário (coleção familiar)

### Distinção obrigatória

O **fichário compartilhado** (C-195–C-197, 5229/5230) já implementado é entre **coleções do mesmo dono**. O código recusa um dono diferente ("convidada e proprietária precisam ser do mesmo dono"), então ele **não** é colaboração entre usuários.

### O exemplo da família não está documentado

Busquei "família", "familiar", "filho", "criança" e "kids" nos documentos, nas propostas, no histórico e na memória do projeto. Nada aparece no contexto de Collection.

O conceito aprovado é genérico: coleção compartilhada com zero ou mais usuários (C-08, 2026-08-10). O caso concreto da coleção familiar provavelmente foi discutido fora do repositório e nunca foi registrado. Isso também é um achado: a decisão que o proprietário recorda depende de um registro que não existe.

### Evolução do conceito

| Data | Fonte | Conteúdo | Status |
|---|---|---|---|
| 2026-08-10 | CD C-08, Parte B ("Shared Users"), itens 22/23 | Coleção com um Owner, compartilhada com 0..N usuários; permissões definidas pelo Owner por usuário; ownership transferível só a um membro compartilhado | Parcialmente superado |
| 2026-08-10 | LDM-25/26/27 | **Uma coleção compartilhada pode conter exemplares de vários membros**; operações patrimoniais sobre o exemplar de outro membro exigem pedido de aprovação na caixa de entrada do dono do exemplar | **SUPERSEDED em 2026-08-28** |
| 2026-08-28 | CP28 §2.6/§2.7 | **Uma coleção só aloca exemplares do acervo do seu dono**; membros colaboram, mas **nunca trazem cartas próprias** | Vigente |
| 2026-08-30 | CD C-141–C-165 | Modelo V1 fechado (detalhe abaixo) | **Vigente (aprovado)** |
| 2026-08-30 | CD C-166–C-186 | Histórico da coleção visível a Owner, EDITOR e VIEWER; Public User não vê | Vigente |
| 2026-08-31 a 09-01 | 5030 / 05d | `visibility` fisicamente restrita a `'PRIVATE'`; `set_collection_visibility()` e Public Access "permanecem fora" | Implementação deliberadamente adiada |
| 2026-10-26 | CD C-204 | O histórico do **fichário** é lido só pelo titular no V1, porque "não há membros físicos hoje" | Vigente |

### Modelo V1 aprovado (C-141–C-165)

- **Titular:** exatamente um Owner estrutural, que não é linha de Membership (C-141, C-156).
- **Membros:** 0..N usuários não-donos com papel **EDITOR** ou **VIEWER** (C-142, C-143). Não há permissões customizadas (C-165).
- **Entrada:** convite do Owner e **aceite explícito** do usuário. Notificações ficam fora de escopo, mas o convite precisa chegar ao convidado de alguma forma (C-153).
- **Gestão:** só o Owner convida e remove; o membro pode sair por conta própria. A saída não desfaz edições nem transfere cartas (C-154, C-155).
- **VIEWER:** vê a coleção, o layout, as reservas e o progresso, sem editar (C-145).
- **EDITOR:**
  - pode editar metadados (nome, capa), layout, reservas, páginas e grade, mesclar e travar, e mover cartas já alocadas entre bolsos (C-146, C-148–C-150);
  - **não** pode alocar ou desalocar cartas, nem alterar local, condição, certificação ou disponibilidade (C-146, C-147).
- **Exclusivo do Owner:**
  - membros e visibilidade;
  - arquivar e excluir;
  - alocação;
  - local, condição, certificação e disponibilidade;
  - acervo e dados privados (C-162).
- **Privacidade:**
  - o membro vê só os exemplares alocados àquela coleção, nunca o acervo inteiro (C-157);
  - não vê valor pago, transações, favoritos, wishlist, locais nem proveniência (C-158, C-159, C-161);
  - condição e certificação são visíveis, mas só o Owner edita (C-160).
- **Visibilidade:**
  - toda coleção nasce privada, e só o Owner publica (C-15, C-151);
  - quem vê uma coleção pública não vira membro (C-152);
  - link compartilhável não cria Membership; link privado é futuro sem mecanismo (C-163).
- **Auditoria:** a necessidade de auditar ações de colaboradores está registrada, sem modelo (C-164). O histórico é visível aos membros (C-172).
- **Transferência de titularidade:** fluxo futuro, não decidido (C-156).

### Titular, colaboradores e exemplares físicos

As cartas físicas pertencem sempre ao acervo do titular. Isso tem uma consequência direta para o caso familiar: **se os filhos têm cartas próprias no acervo deles, o modelo vigente não permite colocá-las na coleção da família**.

Alternativas compatíveis com o modelo atual:
- (a) todas as cartas da família ficam no acervo do pai, e os filhos são EDITOR ou VIEWER;
- (b) cada filho mantém a própria coleção.

O cenário "cada membro contribui com cartas próprias" é justamente o que LDM-25/27 previam e que foi **superado em 2026-08-28**. Reabri-lo seria uma **nova decisão**, não a recuperação de uma pendência. Ela traria de volta a aprovação patrimonial, a caixa de entrada e a regra de saída de membro com cartas alocadas (o antigo LDM-28, hoje void).

### Implementado × pendente

| Item | Situação |
|---|---|
| Membership, convites, papéis | **Não iniciado.** Sem tabela, RPC, rota ou componente |
| Visibilidade pública | **Não iniciado.** Bloqueado fisicamente pelo CHECK `'PRIVATE'` |
| Leituras para quem não é dono | **Não iniciado.** Todas as leituras de Collection são `get_my_*` e filtram pelo dono via RLS |
| Fichário compartilhado (mesmo dono) | Implementado; não atende o caso multiusuário |
| Base de identidade | Existe: `user_profile` com username (ADR-020), útil para convidar por username |

### Riscos e governança para quando for implementado

- **Segurança:**
  - cada leitura existente precisa ganhar uma variante de leitura para membros, ou uma checagem de pertencimento, sem expor o acervo, os locais (Meus locais, "organizar locais" nos Ajustes, local do fichário) nem a proveniência;
  - é preciso garantir **não enumeração**: um usuário não pode descobrir coleções ou convites de outros.
- **Fichário compartilhado:** um fichário pode reunir coleções convidadas do mesmo dono. Um membro da coleção A não pode ver as cartas da coleção B no mesmo fichário.
- **Histórico:** C-172 (membros leem) e C-204 (só o titular, no V1) precisam ser reconciliados.
- **Integridade:**
  - concorrência entre EDITOR e Owner no mesmo fichário (os cadeados e as operações já usam bloqueios);
  - a remoção de um membro não pode desfazer edições.
- **Desempenho:** as políticas de RLS para membros não podem degradar as leituras hoje medidas entre 5 e 150 ms.

---

## 8.5 Funcionalidades já atendidas

Estas capacidades não devem voltar ao backlog:
- **Acervo:**
  - registro unitário e em lote com prévia, e Set inteiro (BULK-01 a 04);
  - ajustar cópias e remover exemplar;
  - busca, filtros e ordem;
  - detalhe por exemplar com local e acabamento holográfico.
- **Coleções:**
  - de Set, livre (com cor, capa e código) e Pokédex (com gerações, vínculo normal e excepcional, representante e lote);
  - Master Set configurável (objetivo, acabamentos, fora do objetivo, adicionar do acervo);
  - Biblioteca com três modos e ordem manual;
  - renomear e editar metadados;
  - Tenho/Faltam;
  - vincular "uma de cada" e manualmente, e desvincular.
- **Locais:** Meus locais, local padrão, mover em lote, organizar a coleção por local, fichário por local físico.
- **Fichário Digital:**
  - criação e montagem automática;
  - páginas;
  - bolsos com arrastar e soltar, bandeja, seleção múltipla e cadeado;
  - fixar a carta presente;
  - inserir e fechar lacunas;
  - imagens personalizadas e mescladas;
  - identidade;
  - fichário compartilhado entre coleções do mesmo dono, com saída e prévia;
  - referência de espécie;
  - novidades do catálogo;
  - histórico de atividades.
- **Bulk:** BULK-01 a 04 concluídos. BULK-05/06 foram retirados.

---

## 8.6 Propostas históricas não aprovadas

São oportunidades registradas, sem compromisso:
- **PX-04:** importar/exportar (CSV, outros trackers, registros sem correspondência).
- **PX-07:** imprimir placeholders de faltantes.
- **PX-06:** busca "objeto na mão" transversal a Coleções, Locais e Fichário.
- **PX-03 e PX-05:** recuperabilidade e entrada guiada por exceções.
- **Biblioteca:** busca, filtro e ordem; ordenação automática além da manual (BM §24).
- **Spikes do fichário** (sem contrato): Favoritar e Substituir no bolso, Buscar, Exportar/Imprimir, Compartilhar.
- **Link privado de compartilhamento** (C-163), share link, QR (BM P1).
- **Hipóteses [H] da NS:** celebração ao completar ou adicionar um Set inteiro; máquina de estados Estante → Foco → Abrir; Wave em redes sociais.
- **Notificações, inbox, grail e ranking** (C-86, C-153).

---

## 8.7 Recomendações de consolidação na Etapa 1

São recomendações e não alteram a ordem das quatro macroetapas.

1. **Incremento "Ciclo de vida"** (P0): arquivar, reativar e excluir coleção (L1), junto com desmontar e excluir fichário (E19/E19b, já na Etapa 1). Os dois compartilham a regra C-194 e a mesma superfície em Ajustes. Também caberia aqui ligar a transferência de âncora (E20), cuja server action já existe.
2. **Incremento "Adicionar a partir da coleção"** (P1): Fluxos 2 e 5 dentro da coleção, mais o Fluxo 1.6, reaproveitando os seletores do acervo e os envelopes 5150/5157 com alocação. Pode ir junto com a Reserva de bolso vazio, que usa o mesmo seletor de carta.
3. **Preços + valor + condição** (P2): ao fazer "Preços nas cartas", decidir se a condição (L5) entra junto, porque o preço por condição faz mais sentido com ela. O "valor total" (VR-02) deveria ser explicitado no escopo de Relatórios.
4. **Colaboração** (P1, condicionada a D1): se incluída, como incremento próprio depois de Favoritos e Wishlist e antes de Relatórios, com ciclo completo de modelagem física, harness de autorização com cinco papéis (anon, dono, EDITOR, VIEWER, outro usuário) e testes de não enumeração. Começar só com VIEWER e PUBLIC reduz bastante o risco.
5. **Critério de saída da Etapa 1** (P0): adotar B1–B8 (NS §4), resolvendo antes a contradição R3 (GQ-02), e só então liberar a Etapa 2.
6. **Higiene documental** (sem implementação), na rodada de atualização do backlog:
   - atualizar a matriz §7 da NS e NS-18 (Coleção Pokédex já publicada);
   - HANDOFF §3.1, §4 e §7 (P2-B, histórico, Bandeja);
   - registrar a resolução da cascata 5047 (CO-17);
   - registrar o caso da coleção familiar, se for decidido.

---

## 8.8 Decisões necessárias do proprietário

- **D1. Coleção multiusuário:**
  - entra na Etapa 1?
  - Se sim, com qual escopo inicial: (a) só VIEWER + coleção PUBLIC; (b) EDITOR e VIEWER completos (C-141–C-165); (c) também membros contribuindo cartas próprias, o que **reabre a decisão superada em 2026-08-28** (LDM-25/27) e exige nova modelagem.
- **D2. Ciclo de vida da coleção:** arquivar, reativar e excluir entram na Etapa 1?
- **D3. Fluxos 2/5 dentro da coleção:** entram na Etapa 1, ou a North Star é revisada para aceitar o caminho "Meu acervo → vincular" como suficiente?
- **D4. Critério de encerramento da Etapa 1:**
  - B1–B8 são o gate formal?
  - Como resolver R3: medir B4 no LIVE com dados sintéticos isolados, aceitar medição no ambiente local PG17, ou dispensar formalmente?
- **D5. Condição e Graduação:**
  - entram na Etapa 1 (junto com Preços)?
  - Ficam para antes da Etapa 4?
  - Ou permanecem fora do plano?
- **D6. Coleção Pokédex × P7:** "Completar a Pokédex" já foi publicada (PKX-01/02/03, 2026-10-19), mas a Etapa 2 ainda lista "P7 — Minha Collection Pokédex" e NS-18 a condiciona à P7. É preciso redefinir o que P7 ainda entrega.
- **D7. Escopo dos Relatórios de Collection:** inclui valor total do acervo e por coleção, e quais outros relatórios?

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | **Criação (2026-10-29, `COLLECTION-FUNCTIONAL-COVERAGE-AUDIT-01`).** Auditoria retrospectiva de cobertura funcional de Collection: 69 capacidades classificadas, 9 lacunas confirmadas, análise do compartilhamento multiusuário e 7 decisões para o proprietário. Documento não normativo; nenhuma decisão alterada. |
