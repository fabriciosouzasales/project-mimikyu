# P3-B — Histórico de Atividades do Fichário Digital

| Campo | Valor |
|---|---|
| Versão | 1.53 (2026-10-28, lint e build PASS na máquina do proprietário, com avisos não bloqueantes; pronta para commit) · 1.52 (2026-10-28, CLOSEOUT FINAL: P3-B concluída com ressalvas; S6 PASS PARCIAL — E17 (evento 105) e E18 (evento 104) comprovados, bloco B 7/7; 5290–5296 promovidas (md5 = LIVE); S7 local, visual homologado, não publicada; backlog residual §35) · 1.51 (2026-10-28, conclusão funcional S6/S7: "Coleção associada 17:10" era dado fictício da prévia estática, não do LIVE; E17/E18/E20 sem chamada nem evento; E20 sem caminho na interface; S7 validada por leitura — 85/85 leituras HTTP 200, isolamento por titular, 15/15 testes, typecheck limpo; lint/build pendentes) · 1.50 (2026-10-28, S7 fidelidade visual: ícones lineares sem formas quadradas, tipografia 12/10,5/10 px, datas compactas, detalhes mais leves, seletor discreto; 15/15 testes, typecheck limpo) · 1.49 (2026-10-28, S7 Activity Log minimalista: uma linha por evento, linha-guia, manchetes objeto + ação, detalhes em campos, filtro em seletor; 15/15 testes, typecheck limpo) · 1.48 (2026-10-28, S7 refinamento visual: timeline compacta — resumo sujeito + ação, hora à direita, ícones monocromáticos, chips compactos com alvo de 44 px, detalhes discretos; 14/14 testes, typecheck limpo) · 1.47 (2026-10-28, S7 implementada localmente: seção Histórico no Centro de Controle sobre a 5269; 13/13 testes, typecheck limpo; não publicada) · 1.46 (2026-10-28, S6 pós-check funcional: E01 PASS; E17/E18/E20 STOP — relatados como executados, sem chamada à RPC nem evento no LIVE; S6 NÃO encerrada, 5290–5296 não promovidas) · 1.45 (2026-10-28, S6 INSTALADA NO LIVE: 5290–5296 via apply_migration; LIVE_S6_90 bloco A 6/6; ledger 7/7 md5; Advisor sem achado novo; homologação funcional pendente) · 1.44 (2026-10-28, S6 implementada localmente: 5290–5296, static_check S6 82/82, LIVE_S6_00 6/6; nada aplicado) · 1.43 (2026-10-28, S5 homologada e encerrada parcialmente: E06a comprovado; E06b/E07 não exercitados; 5287–5289 promovidas) · 1.42 (2026-10-28, S5 INSTALADA NO LIVE: 5287–5289 via apply_migration; LIVE_S5_90 bloco A 7/7; ledger 3/3 md5; Advisor sem achado novo; homologação funcional pendente) · 1.41 (2026-10-28, S5 implementada localmente: 5287–5289, static_check S5 44/44, LIVE_S5_00 PASS; nada aplicado) · 1.40 (2026-10-28, S4 homologada e encerrada: LIVE_S4_90 bloco B PASS; 5279–5286 promovidas para database/schema/; pendências residuais §31.12) · 1.39 (2026-10-27, S4 INSTALADA NO LIVE: 5279–5284 via apply_migration; LIVE_S4_90 bloco A 7/7; ledger 6/6 md5; Advisor sem achado novo atribuível à S4; homologação funcional pendente) · 1.38 (2026-10-27, S4 implementada localmente: 5279–5284, static_check S4 51/51, LIVE_S4_00 6/6; nada aplicado) · 1.37 (2026-10-27, S3 homologada e encerrada parcialmente: LIVE_S3_90 v1.1 (errata B.6) bloco B 6/6; 5275–5278 promovidas para `database/schema/`; próxima: S4) · 1.36 (2026-10-27, S3 INSTALADA NO LIVE: 5275–5278 via apply_migration; LIVE_S3_90 bloco A 7/7; ledger 4/4 md5; Advisor sem achado novo atribuível à S3; homologação funcional pendente) · 1.35 (2026-10-27, S2 encerrada parcialmente e promovida para `database/schema/` (§29.11) com pendências explícitas; S3 implementada localmente: 5275–5278, static_check S3 31/31, LIVE_S3_00 6/6; nada aplicado) · 1.34 (2026-10-27, homologação S2: bloco B B.1–B.7 PASS; Desfazer corrigido no frontend (§29.10); ADD pela interface e REPLACE pendentes) · 1.33 (2026-10-27, S2 INSTALADA NO LIVE: 5271–5274; bloco A 7/7 (A.2 após errata do instrumento); ledger 4/4 md5; Advisor sem achado novo; homologação funcional pendente) · 1.32 (2026-10-27, S1 promovida para `database/schema/` e ENCERRADA; S2 implementada localmente: 5271–5274, static_check S2 30/30, LIVE_S2_00 6/6; nada aplicado) · 1.31 (2026-10-27, S1 INSTALADA NO LIVE: 5267–5270 via apply_migration; LIVE_90 12/12; ledger 4/4 com md5 idêntico ao aprovado; Advisor só com achados esperados) · 1.30 (2026-10-27, instalação definitiva 5267–5270: STOP antes da primeira migration — atividade de autenticação 1 min 32 s antes do G-PRE contradiz a janela sem uso; nada aplicado) · 1.29 (2026-10-27, ensaio v2.3 executado manualmente: MSDRYRUN; pós-check final PASS — G-POST 9/9, Q.08 = P.10, LIVE_00 6/6; ensaio PASS, rollback PASS) · 1.28 (2026-10-27, auditoria final do baseline MEP: PASS) · 1.27 (2026-10-27, reconciliação do baseline MEP: LIVE_00 v1.1, gate v1.2, ensaio v2.3; static_check 65/65) · 1.26 (2026-10-27, pré-check do v2.2: STOP — ledger LIVE avançou para migration fora do repositório) · 1.25 (2026-10-26, E3 atualizado para a v2.2: §28.13/§28.14, PowerShell com conferência da área de transferência) · 1.24 (2026-10-26, CATALOG_R1R3 v1.1 executada: PASS — R1 e R3 fechadas) · 1.23 (2026-10-26, CATALOG_R1R3 v1.1 preparada: ')' excedente removido; v1.0 preservada) · 1.22 (2026-10-26, execução de CATALOG_R1R3 v1.0: STOP — erro de sintaxe 42601, nada executado) · 1.21 (2026-10-26, R1/R3: consulta CATALOG_R1R3_readonly.sql proposta; R3 fechada estaticamente) · 1.20 (2026-10-26, auditoria estática da v2.2: PASS COM RESSALVA) · 1.19 (2026-10-26, ensaio v2.2 preparado: T8a pela lista canônica do LIVE_90; static_check 56/56; não executado) · 1.18 (2026-10-26, ensaio v2.1 executado: DRYRUN POSTCHECK FALHOU — defeito do T8a (90.3/90.10); rollback PASS: G-POST 9/9, LIVE_00 6/6) · 1.17 (2026-10-26, retomada controlada do pré-check: PASS — LIVE_00 6/6, G-PRE P.01–P.11 true, P.04 = 0) · 1.16 (2026-10-26, diagnóstico de sessões executado: 4 no P.04 — PostgREST/Storage transitórios e postgres_exporter intermitente) · 1.15 (2026-10-26, diagnóstico de sessões somente leitura proposto, não executado) · 1.14 (2026-10-26, renovação do pré-check para o ensaio: STOP em P.04 — sessões ativas e autenticação recente; ensaio não executado) · 1.13 (2026-10-26, pré-check LIVE PASS: LIVE_00 6/6, G-PRE P.01–P.11 true, P.10 preservado) · 1.12 (2026-10-25, `P3B-S1-E3-LIVE-DRYRUN-V21-01` preparação: hashes consolidados, instrumentos conferidos, §28.13 corrigido (referência de hash do gate e P.11/Q.09); READY para pré-check) · 1.11 (2026-10-25, `P3-B-S1-DASHBOARD-PROBE-CLOSEOUT`: sonda do Dashboard PASS no LIVE (relato do proprietário); executor SQL Editor homologado para o formato da v2.1; procedimento manual E3) · 1.10 (2026-10-25, auditoria estática da sonda do Dashboard: PASS de segurança; nada executado) · 1.9 (2026-10-25, `P3-B-S1-LIVE-DASHBOARD-EXECUTOR-READINESS-01`: E2 suspenso; executor por mensagem única avaliado — GO CONDICIONAL via SQL Editor, sonda somente leitura proposta; nada executado) · 1.8 (2026-10-25, `P3-B-S1-E2-PROBE-SECURITY-CORRECTION-01`: sonda E2 v1.1 — psql explícito, verify-full obrigatório, ambiente isolado no processo filho, senha pelo prompt do psql) · 1.7 (`P3-B-S1-LIVE-DRYRUN-EXECUTOR-E2-READINESS-02`: executor E2 — psql não interativo; scripts PowerShell preparados, não executados) · 1.6 (`P3-B-S1-LIVE-DRYRUN-EXECUTION-GATE-01`: preparação do ensaio — hashes, LIVE_00 do dia, executor E1, protocolo; sem execução) · 1.5 (`P3-B-S1-FINAL-READINESS-03`: readiness documental concluído — gates consolidados, G5 desdobrado, contrato do executor, garantias, evidências) · 1.4 (`P3-B-S1-LIVE-DRYRUN-STRUCTURAL-CORRECTION-02`: ensaio LIVE reestruturado; W1 demonstrado e reforçado) · 1.3 (`P3-B-S1-SECURITY-CORRECTION-01`: B1, W1, W2, W3, W8) · 1.2 (`P3-B-S1-FOUNDATION-READINESS-01`) · 1.1 (`P3-B-ACTIVITY-HISTORY-DECISION-CLOSEOUT-02`) · 1.0 (`P3-B-ACTIVITY-HISTORY-DECISION-CONSOLIDATION-01`) |
| Origem | `P3-B-ACTIVITY-HISTORY-DISCOVERY-01` → decisões D1–D8 → O1–O5 de Fabrício |
| Estado | **P3-B CONCLUÍDA COM RESSALVAS (2026-10-28, §35).** S1 encerrada; S2–S6 no LIVE, canônicas, encerradas parcialmente (§29.11, §30.10, §31.12, §32.9, §33.12 — S6 PASS PARCIAL); S7 implementada no frontend local, visual homologado, **não publicada** (§34.9). Cobertura dinâmica parcial; concorrência e desempenho não medidos. |
| Base factual | Inventário de funções, cascatas e gatilhos lido no LIVE em 2026-10-25 (só leitura: `pg_proc`, `pg_constraint`, `pg_trigger`, privilégios) |
| Autoridade conceitual | `concept-decisions.md` C-164, C-166 a C-186 (não reabertas) e **C-201 a C-209**; `logical-model.md` **LDM-196 a LDM-203**; P3-A D11 |
| Próximo passo | Desenvolvimento encerrado; lint e build PASS. Publicação (fora deste encerramento): revisão e commit pelo proprietário; deploy com autorização própria. Backlog: §35.3. |

---

## 1. Decisões consolidadas

| # | Decisão | Situação |
|---|---|---|
| D1 | Histórico **por fichário**; consulta futura por coleção continua possível | APROVADA |
| D2 | Operação em lote = um **evento agregado**, com os itens individuais preservados | APROVADA |
| D3 | Registrar saídas do fichário originadas no Meu acervo | APROVADA |
| D4 | Início explícito da cobertura; incorporação anterior da Chi-Yu só como **registro legado parcial**, sem inventar ator, posição ou outro atributo ausente | APROVADA COM CONDIÇÃO |
| D5 → O1 | Política-alvo de retenção **A1 + A3 + A5**: o histórico sobrevive à desmontagem, preservando a condição histórica; exclusão definitiva possível, respeitando obrigações de retenção aplicáveis; **sem expurgo automático por prazo** nesta fase | APROVADA |
| D6 | Lotes feitos no navegador → operações atômicas: **frente separada**; a P3-B não altera comportamento homologado para isso | APROVADA COMO FRENTE SEPARADA |
| D7 | Fixar e desfixar no MVP | APROVADA |
| D8 | Seção Histórico no Centro de Controle, experiência responsiva homologada, sem rota paralela | APROVADA |
| O2 | Interface de exclusão definitiva **pode vir depois do MVP**; vínculo, acesso e eliminação definidos agora (§6) e a estrutura da S1 já os comporta | APROVADA |
| O3 | Rede de segurança **não aprovada** para implementação; priorizar instrumentação explícita; anti-perda especificado em §7 | NÃO APROVADA (parecer em §7) |
| O4 | Interface **só publicada depois de comprovada** a cobertura obrigatória de S2–S6; aviso de início de cobertura e identificação dos legados preservados | APROVADA |
| O5 | Desmontagem preserva o histórico **com registro do encerramento**; transferência entre coleções do mesmo dono preserva o histórico integral; transferência futura entre usuários exige segregação dos períodos de propriedade; **comportamento atual da transferência não muda** | APROVADA COM CONDIÇÕES |
| P1 | E20 incluído: registro da transferência entre coleções do mesmo proprietário, sem alterar a transferência | APROVADA (2026-10-25) |

## 2. Fronteiras conceituais

| Camada | O que é | Na P3-B |
|---|---|---|
| **Histórico de atividades** (C-167) | Acontecimentos de domínio concluídos, em linguagem do colecionador | Objeto desta frente |
| **Auditoria técnica** (C-175/C-176) | Governança, segurança, investigação, tentativas negadas, acesso administrativo direto | **Fora.** Falha, recusa, leitura e SQL administrativo não entram no histórico |
| **Estado atual** (C-183) | Tabelas do fichário | Fonte da verdade. O histórico não reconstrói o estado; o estado não fabrica histórico |
| **Ciclo de vida do exemplar** (C-185) | Entrada, transferência e saída patrimonial | Não duplicado. A saída do acervo só aparece pelo efeito no fichário |

Regras:

- **R1.** Só operação concluída, gravada **na mesma transação**. Erro, recusa, rollback, prévia, leitura e repetição idempotente sem efeito não geram evento.
- **R2.** Nada é inferido de `created_at`, `updated_at` ou do estado atual. Única importação permitida: a linha real da Chi-Yu, como legado.
- **R3.** Cópia, não referência: carta, acabamento, posição e nome de coleção são gravados como texto e números no momento do evento.
- **R4.** Imutável (C-179): sem UPDATE; exclusão só pelos caminhos de §6.
- **R5.** Um evento por operação de mais alto nível. Chamadas internas (página nova dentro de "abrir espaço", deslocamento de bolsos dentro da incorporação) acrescentam itens ao evento da operação externa e nunca criam evento próprio (§7.2).

## 3. Especificação funcional

### 3.1 Escopo e visibilidade

- **Escopo:** o fichário. Cada evento guarda também a coleção afetada, quando houver (consulta futura por coleção, D1).
- **Leitura no V1:** o titular dos eventos (§6.1), que hoje é sempre o dono do fichário.
- **Conciliação com C-172 (sem revogação):** C-172 abre o histórico a dono e membros, mas a associação de membros não tem modelo físico e não há nenhum membro. Ler "só o dono" é o que C-172 produz nesse cenário. A autorização fica num único predicado "pode ler estes eventos", ampliável aos membros no futuro sem mudar o modelo.
- **Coleções convidadas:** são do mesmo dono (5229/5255); não há exposição entre usuários.
- **Público:** nunca.

### 3.2 Conteúdo de cada evento

| Campo lógico | Regra |
|---|---|
| Titular | Usuário dono do fichário **no momento do evento**, gravado no próprio evento (§6.1) |
| Chave do fichário | Identificador do fichário como valor **sem FK em cascata**: o evento sobrevive à desmontagem (A1) |
| Momento | Hora do servidor da transação; desempate por identificador crescente |
| Quem executou | Usuário autenticado; no V1 igual ao titular. Legado: sem ator |
| Tipo | Vocabulário fechado (§4) |
| Origem | `FICHARIO`, `ACERVO`, `COLECAO`, `CATALOGO`, `LEGADO` |
| Atomicidade | `ATOMICA`: um evento = uma transação |
| Coleção afetada | Quando aplicável, com cópia do nome |
| Itens | Por carta, reserva, bolso ou página: cópia da carta (nome, número, Set, acabamento), posição de origem e destino (página, linha, coluna) e efeito |
| Proibido | Preço, valor pago, vendedor, comprador, procedência, condição, graduação, favorito, wishlist (C-174) |

### 3.3 Experiência (D8, O4)

- **Onde:** seção recolhível "Histórico" no Centro de Controle, depois de Informações, com o mesmo componente, a mesma persistência de recolhimento e o mesmo comportamento responsivo homologado. Sem rota nova.
- **Lista:** do mais recente para o mais antigo, agrupada por dia; ícone, frase e hora. Exemplos:
  - "Mega Darkrai ex · 120 movida da página 3 (linha 2, coluna 4) para a página 5 (linha 1, coluna 1)"
  - "7 cartas retiradas · páginas 4 e 5", com **Ver detalhes**
  - "3 bolsos fixados"
  - "Chi-Yu · 059 · Holo Reversa saiu do fichário · mudou de local no Meu acervo"
- **Legado:** selo "Registro anterior ao histórico completo", sem posição nem ator.
- **Filtros:** Todas · Cartas · Reservas · Fixação · Páginas · Catálogo · Fichário.
- **Carregamento:** 20 por vez, "Mostrar mais", paginação por data e identificador.
- **Início da cobertura:** sempre ao fim da lista ("Histórico registrado a partir de [data]…"). Depois de uma exclusão definitiva, o início passa a ser a data da exclusão (§6.3).
- **Estados:** carregando, erro com "Tentar de novo", vazio, filtro sem resultado.
- **Acessibilidade:**
  - `ol` com `time datetime`;
  - filtros com `aria-pressed`;
  - "Ver detalhes" com `aria-expanded`;
  - anúncio educado no "Mostrar mais", sem mover o foco;
  - alvos de 44 px no celular;
  - contraste nos dois temas;
  - nenhum movimento novo.
- **Publicação:** só depois do gate de cobertura de §8 (O4).

## 4. Matriz final de eventos

Legenda de unidade: **A** = atômica, uma chamada é uma transação; **L** = lote atômico.

### 4.1 MVP — as 18 funções homologadas confirmadas (E01–E18)

Assinaturas lidas no LIVE. Quando há sobrecarga, só a **implementação** é instrumentada; o invólucro delega a ela e herda o evento.

| # | Evento | Função implementadora (LIVE) | Invólucro que delega | Unidade | Origem | Fatia |
|---|---|---|---|---|---|---|
| E01 | Fichário montado | `create_my_collection_binder(uuid,int,int,text,text)` | — | L | FICHARIO | S6 |
| E02 | Carta colocada no bolso (inclui "Desfazer remoção") | `place_my_physical_card_in_slot(uuid,uuid,uuid)` | — | A | FICHARIO | S2 |
| E03 | Carta movida | `move_slot_assignment(uuid,uuid)` → MOVE | — | A | FICHARIO | S2 |
| E04 | Cartas trocadas | `move_slot_assignment(uuid,uuid)` → SWAP | — | A | FICHARIO | S2 |
| E05 | Cartas retiradas | `remove_slot_assignment(uuid[])` | — | L | FICHARIO | S2 |
| E06a | Cartas saíram por mudança de local | `set_physical_cards_storage(uuid,uuid[],bool)` | — (a sobrecarga `(uuid,uuid[])` da 5024 não delega e não tira carta de bolso: a guarda 5256 recusa; §32.1) | L | ACERVO | S5 |
| E06b | Cartas saíram ao organizar a guarda da coleção | `organize_my_collection_storage(uuid,uuid,text,int,text,bool)` | — (a versão de 5 argumentos da 5222 idem; §32.1) | L | COLECAO | S5 |
| E07 | Carta saiu do fichário ao deixar o acervo | `remove_my_physical_card(uuid)` (o bolso cai por FK em cascata) | — | A | ACERVO | S5 |
| E08 | Bolso reservado | `set_slot_expected_content(uuid,uuid,uuid,uuid,uuid)` | — | A | FICHARIO | S3 |
| E09 | Reservas liberadas | `clear_slot_expected_content(uuid[])` | — | L | FICHARIO | S3 |
| E10 | Bolsos fixados / desfixados | `set_slot_lock(uuid[],bool)` | — | L | FICHARIO | S3 |
| E11 | Espaço aberto (com página nova embutida) | `insert_my_binder_gap(uuid,uuid,text,bool,bool)` | — | L | FICHARIO | S4 |
| E12 | Espaço fechado (com remoção da página embutida) | `close_my_binder_gap(uuid,uuid,uuid,text,uuid)` | — | L | FICHARIO | S4 |
| E13 | Páginas adicionadas | `add_layout_page(uuid)` | — | L | FICHARIO | S4 |
| E14 | Página removida | `remove_layout_page(uuid,int)` | `remove_layout_page(uuid)` | A | FICHARIO | S4 |
| E15 | Páginas reordenadas | `reorder_layout_pages(uuid,uuid[])` | — | L | FICHARIO | S4 |
| E16 | Novidades do Catálogo incorporadas (com deslocamento e página nova embutidos) | `apply_my_binder_catalog_reconciliation(uuid,text[],text,bool,bool)` | — | L | CATALOGO | S6 |
| E17 | Coleção associada | `attach_my_collection_to_binder(uuid,uuid)` | — | A | FICHARIO | S6 |
| E18 | Coleção desassociada (reservas dela liberadas, como itens) | `detach_my_collection_from_binder(uuid,text,bool)` | — | A | FICHARIO | S6 |
| L01 | Incorporação legada da Chi-Yu | `collection_layout_catalog_incorporation` (1 linha real) | — | — | LEGADO | S1 (importação) |

Contagem: **18 funções implementadoras distintas** (E06a e E06b são duas; E04 reusa a função de E03; L01 não é função).

### 4.2 Exigidos por O5 (somam-se às 18)

| # | Evento | Função | Unidade | Fatia | Observação |
|---|---|---|---|---|---|
| E19 | Fichário encerrado (desmontado) | `dismantle_my_collection_binder(uuid,text)` | L | S6 | O5: registro do encerramento; itens = cartas e reservas que saem. O histórico sobrevive (§6) |
| E19b | Fichário encerrado (remoção do fichário vazio) | `delete_collection_layout(uuid)` | A | S6 | Caminho real: exige zero páginas; executável por `authenticated` |
| E20 | Fichário passou a pertencer a outra coleção do mesmo dono | `transfer_my_binder_ownership(uuid,uuid)` | A | S6 | **Aprovado (P1, 2026-10-25).** Só registro: a função recebe apenas begin/add_item/end no caminho de sucesso; assinatura, retorno, códigos de erro, travas e `UNCHANGED` inalterados (prova em §14.7) |

### 4.3 Fora do MVP

Nome e logomarca (`set_my_binder_identity`), imagens e regiões (5233/5240), referências de espécie (5258), grade (`set_collection_layout_grid`, imutável após a montagem).

## 5. Caminhos conhecidos de alteração de bolsos (verificação 2)

Fonte: leitura no LIVE de todas as funções que escrevem em `collection_layout_slot_assignment`, `_slot_expected_content`, `_slot`, `_page`, `collection_layout`, `collection_layout_guest`, das FKs com ação em exclusão e dos gatilhos.

### 5.1 Funções públicas que escrevem

Todas as funções de §4.1 e §4.2, mais:

| Função | Escreve em | Situação na P3-B |
|---|---|---|
| `assign_card_to_slot(uuid,uuid)` (5131) | bolsos | **Caminho morto por construção:** insere sem `physical_card_id`, coluna NOT NULL desde 5256, então nunca conclui. Continua executável por `authenticated`. Fica na lista de exceções do gate estático (§7.3); revogar a permissão é frente separada |
| `create_collection_layout` | fichário | Não executável por clientes; só chamada por E01 |

### 5.2 Funções internas chamadas por funções instrumentadas

| Interna | Chamada por | Regra |
|---|---|---|
| `binder_gap_move_pocket(uuid,uuid)` | E11, E12, E16 | Não executável por clientes; desloca cartas e reservas. Gera **itens** do evento externo, nunca evento próprio |
| `add_layout_page(uuid)` | E11, E16 (embutida); E13 (direta) | Chamada direta = E13; chamada dentro de outra operação = item do evento externo (R5) |
| `remove_layout_page(uuid,int)` | E12 (embutida); E14 (direta) | Idem |

### 5.3 Cascatas e efeitos implícitos

| Origem | Efeito no fichário | Cobertura |
|---|---|---|
| Exclusão de `physical_card` (só por `remove_my_physical_card`) | **Apaga o bolso** (FK em cascata) | E07: a função captura os bolsos afetados **antes** da exclusão |
| Exclusão de `collection_allocation` | Só zera a referência no bolso (SET NULL); a carta continua no bolso | Não é atividade (sem mudança visível no fichário) |
| Exclusão de página | Apaga os bolsos da página por cascata; `remove_layout_page` só remove página **vazia** | E14 registra só a página; não há carta envolvida |
| Exclusão do fichário | Apaga marcos e incorporações por cascata | E19/E19b; o histórico novo não depende dessas linhas (sem FK em cascata) |
| Gatilhos do fichário | Só validam ou mantêm `updated_at` e marcos internos; nenhum muda bolsos | Nada a registrar |
| `delete_collection` | Recusa coleção com fichário (5226) | Não altera bolsos |
| Exclusão de conta | Cascata patrimonial | A5: o histórico do titular sai junto (§6.4) |
| SQL administrativo direto (`service_role`, painel) | Qualquer | **Fora do histórico** por definição (auditoria técnica). Risco residual R-A |

## 6. Política de retenção, titularidade e transferência (O1, O2, O5)

### 6.1 Titularidade e vínculo

- **Titular de cada evento:** o usuário dono do fichário no instante do evento, gravado no evento. A titularidade **nunca é recalculada** a partir do fichário atual.
- **Vínculo com o fichário:** chave do fichário guardada como valor, **sem FK em cascata**. Desmontar ou remover o fichário não apaga eventos (A1).
- **Vínculo com o titular:** FK para o usuário com **exclusão em cascata**, para atender A5.
- **Sem dados de terceiros:** o conteúdo é do titular (suas coleções, posições) ou do catálogo público. Nenhum campo de outro usuário é gravado.

### 6.2 Acesso durante o ciclo de vida

| Fase | Quem lê | Como |
|---|---|---|
| Fichário ativo | Titular | Seção Histórico do Centro de Controle |
| Fichário desmontado (A1) | Titular | Eventos preservados; consulta de fichários encerrados é tela pós-MVP. A S1 só garante que os dados ficam e são legíveis pela função de leitura por chave e titular |
| Transferência entre coleções do mesmo dono | Titular (o mesmo) | Histórico integral, sem corte (O5); E20 marca a mudança |
| Transferência futura entre usuários (não existe hoje) | Cada titular vê **só os seus** eventos | Segregação natural pelo titular gravado: o novo dono vê a partir do recebimento; os anteriores ficam protegidos e continuam do dono antigo. Exige, quando existir, um evento de entrega e um de recebimento |
| Membros (futuro, C-172) | A definir | Ampliação do predicado, limitada ao período do titular atual. Decisão futura |

A leitura é sempre por função com titular igual ao usuário logado; as tabelas não têm permissão para clientes.

### 6.3 Exclusão definitiva (A3; interface pós-MVP, estrutura já na S1)

- **Quem:** só o titular, por função própria; nunca por gatilho ou cascata de desmontagem.
- **Escopo:** todos os eventos de um fichário de que ele é titular, ativo ou encerrado.
- **Efeito:**
  - remove eventos e itens;
  - grava um **marco mínimo de início de cobertura**, só com chave do fichário, titular e data, sem conteúdo;
  - a interface passa a dizer "Histórico registrado a partir de [data da exclusão]".
- **Obrigações de retenção:** se surgir obrigação legal ou contratual de reter, a função a aplica antes de apagar (ex.: bloqueio por prazo). Nenhuma está identificada hoje; registrada como verificação jurídica antes da interface (P2, §11).
- **Não gera evento:** registrar o que acabou de ser apagado contradiria a exclusão; o marco mínimo basta.

### 6.4 Exclusão da conta (A5)

Os eventos do titular saem pela cascata da FK de titularidade. É obrigatória e independente de A3.

### 6.5 Prazos automáticos (A4)

Fora desta fase (O1). Nenhuma rotina de expurgo.

## 7. Parecer sobre O3 — como evitar perda sem rede de segurança

### 7.1 Parecer

A rede de segurança proposta antes (gatilho em DELETE de bolso) **não é recomendada** como solução principal. Mesmo condicionada, ela:

- capturaria estados intermediários, como a troca (SWAP) feita em vários passos;
- dependeria de um marcador de transação, fácil de esquecer em funções futuras;
- produziria eventos "origem não identificada", que são ruído técnico.

A recomendação é **instrumentação explícita de todos os caminhos conhecidos + prevenção de perda por verificação**, não por captura em tempo de execução.

### 7.2 Regras de instrumentação (sem duplicidade e sem estado intermediário)

1. **Contexto de operação por transação:** a função de mais alto nível abre o evento; funções instrumentadas chamadas dentro dela (§5.2) **acrescentam itens** ao evento aberto. Resultado: exatamente um evento por chamada do cliente.
2. **Captura no fim:** os itens são calculados a partir do estado inicial e final da própria função, nunca dos passos intermediários.
3. **Invólucros não gravam:** só a implementação grava.
4. **Captura antes da cascata:** em E07, os bolsos afetados são lidos antes da exclusão do exemplar.
5. **Repetição idempotente** que retorna sem efeito sai **antes** da gravação.
6. **Contexto encerrado ao sair:** chamadas sucessivas na mesma transação (harness) geram eventos distintos.

### 7.3 Prevenção de perda: gate estático de cobertura

Verificação só de leitura, executada em cada gate (S1–S8) e antes da publicação (O4):

- lista no catálogo do banco **toda** função que escreve nas tabelas de §5;
- cada uma precisa estar em exatamente uma categoria:
  - **(a) instrumentada**, com o tipo de evento declarado;
  - **(b) interna**, chamada só por funções instrumentadas e sem permissão para clientes;
  - **(c) exceção documentada**, com motivo (hoje: `assign_card_to_slot`, caminho morto; `create_collection_layout`, interna de E01);
- qualquer função nova ou alterada fora dessas categorias **reprova o gate**. É a proteção contra perda futura, sem ruído em tempo de execução.

### 7.4 Matriz de cobertura e riscos residuais

| Caminho | Cobertura | Risco residual |
|---|---|---|
| 18 funções de §4.1 + E19/E19b/E20 | Explícita | Erro de implementação → mitigado por harness por evento (I1–I9) |
| Internas (§5.2) | Itens do evento externo | Chamada direta futura por nova função → gate estático |
| Cascata do exemplar (E07) | Captura antes da exclusão | Nova função que exclua exemplar → gate estático (lista também exclusões de `physical_card`) |
| `assign_card_to_slot` | Exceção (nunca conclui) | Se alguém corrigir a função sem instrumentar → gate estático reprova |
| **R-A** SQL administrativo direto | Não coberto, por definição | Aceito: é auditoria técnica, não atividade do colecionador |
| **R-B** Lotes do navegador (D6) | Eventos individuais corretos | Agrupamento visual impossível até a frente D6; documentado |
| **R-C** Fichários anteriores à cobertura | Sem eventos | Aviso de início de cobertura (O4) |

## 8. Cobertura prometida, implementada e comprovada (verificação 6)

| Evento | Prometida | Implementada | Comprovada |
|---|---|---|---|
| E01–E18 | sim (esta especificação) | não | não |
| E19, E19b | sim (O5) | não | não |
| E20 | sim (P1 aprovado) | não | não |
| L01 | sim (D4) | não | não |

Definições:

- **Implementada** = migration da fatia aplicada no LIVE com o diff mínimo provado.
- **Comprovada** = harness da fatia PASS (I1–I9 para cada evento) + gate estático PASS + pós-checagem LIVE.

O README é atualizado a cada fatia. A interface (S7) só é publicada com **todas as linhas obrigatórias comprovadas**.

## 9. Riscos de regressão da instrumentação (verificação 7)

| Risco | Mitigação |
|---|---|
| Divergência entre a função recriada e a homologada | Partir do texto LIVE, verificado igual ao canônico; diff = só as chamadas de gravação (prova estática) |
| Sobrecargas e invólucros | Instrumentar só a implementação; o harness chama também o invólucro e verifica um único evento |
| Assinatura, retorno, códigos de erro, permissões | `CREATE OR REPLACE` mantém permissões; o harness compara retorno e erros com a linha de base |
| Ordem de travas e concorrência | Gravação só insere linhas novas; nenhuma trava nova sobre tabelas do fichário; I4 com duas sessões |
| Contexto de operação vazando entre chamadas | Regra 7.2.6 + caso de harness com duas operações na mesma transação |
| Falha da gravação derrubando a operação | Desejado (R1); harness cobre todos os tipos com dados reais |
| Custo nas operações frequentes | Medido contra metas (§10.3), sem aceitação por suposição |
| Função do acervo (`remove_my_physical_card`) e de guarda (5249/5222) | Fatia própria S5 com regressão do acervo e de "Meus locais" |
| Regressão da reconciliação (5266) | Reexecutar o harness 5859 na S6 |

## 10. Critérios de implementação

### 10.1 Segurança

- S1. Tabelas sem permissão para `anon`, `authenticated` e `service_role`; RLS ativo, sem política para clientes.
- S2. A leitura devolve só eventos com titular igual ao usuário logado; zero linhas, indistinguíveis, para outro usuário, chave inexistente ou sem sessão.
- S3. Funções de gravação e o contexto não executáveis por clientes.
- S4. Sem campos proibidos (verificação estática).
- S5. `search_path` vazio, objetos qualificados; nenhum alerta novo no Security Advisor.
- S6. O titular gravado não muda após transferência ou desmontagem; titular B não lê eventos do titular A em nenhuma fase.

### 10.2 Integridade

- I1. Por evento: 1 evento e N itens após sucesso; zero resíduo após erro ou rollback.
- I2. Recusa não grava.
- I3. Repetição idempotente sem efeito não duplica.
- I4. Concorrência: só a transação vencedora registra.
- I5. Cópias legíveis após renumerar ou apagar bolsos e páginas e após mudanças no catálogo.
- I6. Sem UPDATE; DELETE só pela exclusão definitiva e pela exclusão de conta.
- I7. Lotes do navegador geram eventos individuais.
- I8. Legado com exatamente os campos reais.
- I9. Uma chamada do cliente = um evento, inclusive com internas e invólucros (R5).
- I10. Desmontagem (E19) preserva todos os eventos anteriores e registra o encerramento.
- I11. Gate estático de cobertura PASS.

### 10.3 Performance — **metas**, não resultados

Nenhuma destas metas foi medida. Serão confirmadas ou revistas com dados na S1, e só então tratadas como critério de aceite.

- P1. Volume real hoje (leitura no LIVE): 3 fichários, 146 páginas, 1.776 bolsos, 349 cartas posicionadas, 351 reservas, 1 dono.
- P2. Meta: primeira página da leitura em até 50 ms, com 100 mil eventos num fichário e 1 milhão no total, usando índice.
- P3. Meta: custo extra da gravação em E03, E05 e E16 de até 10% ou 5 ms, o que for maior, sobre a mesma operação sem histórico.

### 10.4 UX

- U1. Seção recolhível no Centro de Controle, sem rota nova.
- U2. Frases para todos os tipos, legado e encerramento; agregados com detalhe.
- U3. Filtros, "Mostrar mais", início de cobertura, estados.
- U4. 375/768/1280 px, claro e escuro, teclado, leitor de tela, movimento reduzido.
- U5. Sem regressão no Centro de Controle homologado.

## 11. Sequência definitiva S0–S8

| Fatia | Conteúdo | Depende de | Gate de saída |
|---|---|---|---|
| **S0** | Auditoria independente da v1.1; promoção a C-*/LDM-* (histórico por fichário, titularidade por evento, A1+A3+A5, legado, R5) | — | G1, G2 |
| **S1** | Fundação: tabelas append-only com titular e chave sem cascata; contexto de operação; função de gravação interna; leitura paginada; marco de cobertura; função de exclusão definitiva **sem permissão para clientes** (estrutura de O2); importação de L01; gate estático; **nenhuma função homologada alterada** | S0 | G3–G8 |
| **S2** | E02–E05 (5250, 5132, 5133) | S1 | I1–I11 por evento; regressão |
| **S3** | E08–E10 (5128, 5129, 5130) | S1 | Idem |
| **S4** | E11–E15 (5243 ×2, 5125, 5126 + invólucro, 5127), com regra R5 para as embutidas | S1 | Idem + I9 com página embutida |
| **S5** | E06a, E06b, E07 (5249 ×2 + invólucros, 5222, `remove_my_physical_card`) | S1 | Idem + regressão do acervo e de Meus locais |
| **S6** | E16–E18, E01, E19, E19b, E20 | S1 | Idem + harness 5859 + I10 |
| **S7** | Frontend da seção Histórico | S1; publicação só após S2–S6 comprovadas | Gate de cobertura (§8) PASS; typecheck, lint, build, testes; homologação U1–U5 |
| **S8** | Encerramento: promoção canônica, 05d, INDEX, ROADMAP, handoff, log | S2–S7 | Equivalência proposta × canônica × LIVE |

S2–S6 são independentes entre si, cada uma com o seu gate. A interface de exclusão definitiva vem depois do MVP, sobre a estrutura da S1.

## 12. Gates objetivos para autorizar a S1

| Gate | Critério verificável |
|---|---|
| G1 | Auditoria independente desta v1.1 com parecer PASS (ou ressalvas resolvidas) |
| G2 | Decisões de §1, §6 e R5 promovidas a `concept-decisions.md` / `logical-model.md`, com log |
| G3 | Numeração livre confirmada em `database/schema/` e no ledger LIVE (só leitura) |
| G4 | SQL da S1 escrito em `database/proposals/` + verificação estática: só objetos novos; zero `CREATE OR REPLACE` de função existente |
| G5 | Harness da S1 executado no protocolo vigente: S1–S6, I6, I8, I11; marco de cobertura; exclusão definitiva por titular; cascata da conta; medições P2 registradas contra a meta *(exigência original, preservada; desdobrada em G5a/G5b/G5c na v1.5 — §17)* |
| G6 | Security Advisor sem alerta novo atribuível à S1 |
| G7 | Plano de reversão da S1: remoção apenas dos objetos novos, sem tocar em estado do fichário |
| G8 | Autorização expressa de Fabrício para aplicar no LIVE |

## 13. Pendências

**Bloqueantes para aplicar a S1 no LIVE:**

1. **G5b (comportamento) e G5c (desempenho)** — FECHADOS. Dependem de decisão de Fabrício sobre o protocolo: o container local `b12-pg17` e ambientes alternativos estão vetados, e o harness 5860 não pode rodar no LIVE (cria usuários e catálogo). Resultado exigido quando houver protocolo: GATE 47/47; P.3/P.4 PASS com P.1/P.2 registradas.
2. **Ensaio LIVE** — preparado (v2.1), sem autorização.
3. **G8** — autorização operacional expressa para o LIVE (FECHADO).
4. Evidências completas para eventual autorização: §25.

**Não bloqueantes:**

- **P2.** Verificar obrigação legal ou contratual de retenção antes de liberar a exclusão definitiva a clientes (ponto de extensão já marcado na 5270).
- **P3.** Revogar a permissão de `assign_card_to_slot` (caminho morto). Frente separada.
- **P4.** Frente D6 (lotes atômicos no servidor). Separada.
- **P5.** Pendência herdada da P3-A: harness 5853 e prova de concorrência não executados. Independente.
- **P6.** Fluxo de exclusão de conta: hoje inexistente, e `inventory`/`collection` têm FK RESTRICT para `auth.users`. A cascata A5 do histórico só atua quando esse fluxo existir; o histórico não bloqueia nem sobrevive a ele.

## 14. Ajustes obrigatórios 1–7 (v1.2)

| # | Ajuste | Resolução | Onde |
|---|---|---|---|
| 1 | Exclusão definitiva como exceção controlada à imutabilidade | Única porta de DELETE: configuração de transação `mmkyu.binder_activity_purge = '<titular>:<chave>'`, que só a `purge_my_binder_activity` define; o gatilho recusa qualquer outra exclusão, salvo a cascata da conta. Sem permissão para clientes até a interface | C-203, LDM-201; 5267 §5, 5270 A |
| 2 | Marco remanescente sem conteúdo recuperável | `binder_activity_coverage` com 5 colunas: titular, chave, data, motivo, `updated_at`. Nada de contagem, tipos, cartas, posições ou datas dos eventos apagados | C-203, LDM-202; 5267 §3; harness 8.3 |
| 3 | Exclusão de histórico ≠ exclusão de conta | Histórico: função do titular, um fichário, deixa marco. Conta: cascata das FKs de titularidade (eventos, itens e marcos), sem marco, sem função; ator de outros titulares permanece inalterado como valor opaco, sem FK (B1, §19.1) | C-203; 5267 §1/§3; harness 8.x e 9.x |
| 4 | Autorização e consulta de fichários desmontados | Leitura sempre por titular, independe de o fichário existir; `list_my_closed_binder_histories` lista os fichários do titular que não existem mais ou não são mais dele | C-204, C-208, LDM-198; 5269; harness 6.x |
| 5 | Evento composto = uma operação lógica | Contexto por transação com profundidade; internas viram itens; cabeçalho só no primeiro item; operação em outro fichário recusada | C-205, LDM-199; 5268; harness 2.3–2.5 |
| 6 | Estrutura de segregação por proprietário | Titular gravado em cada evento (FK própria) e chave do fichário sem FK; marco por (titular, chave) com motivo `OWNERSHIP_RECEIVED` reservado; leitura filtra por titular | C-207, LDM-198/202; 5267; harness 7.1 |
| 7 | E20 não altera a transferência homologada | Ver §14.7 | C-207 |

### 14.7 Prova de não alteração da transferência (E20)

A instrumentação da S6 em `transfer_my_binder_ownership(uuid,uuid)` (5254) se limita a:

1. `binder_activity_begin(layout, 'BINDER_OWNERSHIP_TRANSFERRED', 'FICHARIO', destino)` depois das validações e travas existentes;
2. um `binder_activity_add_item('BINDER','TRANSFERRED', …, detail = {origem, destino})` depois da troca de proprietária;
3. `binder_activity_end()` antes de cada retorno do caminho de sucesso.

Não muda assinatura, retorno, mensagens, códigos de erro, ordem de travas (origem → layout → destino), a exceção controlada da 5136 nem o resultado `UNCHANGED` da repetição — que sai **antes** do begin e, portanto, não grava (C-206). Como a transferência é só entre coleções do mesmo dono, o titular dos eventos não muda e o histórico segue integral. Prova exigida na S6: diff estático = só as três chamadas; harness compara retorno e erros com a linha de base, inclusive `UNCHANGED`.

## 15. Proposta técnica da S1 (fundação)

### 15.1 Objetos novos (nenhum existente é tocado)

| Arquivo | Objetos |
|---|---|
| `5267_create_binder_activity_structures.sql` | Tabelas `binder_activity_event`, `binder_activity_item`, `binder_activity_coverage`, `binder_activity_setting` (linha única, `full_coverage_from` NULL); índice `ix_bae_owner_layout_time`; sequência da identidade com REVOKE explícito (W8); gatilhos `trg_bae_immutable`, `trg_bae_no_truncate`, `trg_bai_immutable`, `trg_bai_no_truncate` e as funções de guarda |
| `5268_create_binder_activity_recording_functions.sql` | Internas `binder_activity_begin`, `binder_activity_add_item`, `binder_activity_end` |
| `5269_create_binder_activity_reads.sql` | `binder_activity_category` (SQL pura, interna); `get_my_binder_activity`, `get_my_binder_activity_coverage`, `list_my_closed_binder_histories` (clientes autenticados) |
| `5270_create_binder_activity_purge_and_legacy.sql` | `purge_my_binder_activity` (sem permissão para clientes); importação única do legado L01 |

### 15.2 Contratos de segurança e autorização

- Tabelas: RLS ativo, nenhum privilégio para `anon`, `authenticated` ou `service_role`.
- Funções: `search_path` vazio e objetos qualificados; 9 SECURITY DEFINER; EXECUTE revogado de PUBLIC, `anon`, `authenticated` e `service_role`, exceto as 3 leituras, liberadas só a `authenticated`.
- Gravação: exige sessão; o titular (dono do fichário no momento) precisa ser o usuário da sessão; bolso de outro fichário é recusado.
- Leitura: filtro por titular; não-titular, chave inexistente e sem sessão → zero linhas.

### 15.3 Retenção e exclusão

Como em §6 e §14 (C-202, C-203). Na S1: exclusão definitiva existe, mas sem permissão para clientes; sem expurgo automático; exclusão de conta via cascata.

### 15.4 Modelo de eventos e itens

- **Evento:** `id` identity; titular; chave; momento; ator; tipo (24 valores, E01–E20 e L01); origem; coleção e cópia do nome; cópia do nome do fichário; resumo ≤ 2 KB; `created_xact`.
- **Item:** (evento, ordinal); tipo; efeito (18 valores); cópia da carta (nome, número, Set, acabamento: código e nome); origem e destino (página, linha, coluna; trincas completas ou ausentes); detalhe ≤ 1 KB.
- **Limites:** textos com tamanho máximo; itens por evento limitados pela **capacidade do fichário mais uma folga de repetição** — páginas × (8 × linhas × colunas + 2) + 8 + 600, recalculado em cada página criada na operação e quando excedido, nunca reduzido (W1, §19.2); acima disso, erro explícito `BINDER_ACTIVITY_ITEM_LIMIT`.
- **Ator:** valor sem FK, validado na gravação (`auth.uid()` = titular na V1), nunca reescrito (B1).

### 15.5 Ordenação e paginação

`occurred_at desc, id desc`; cursor composto (`p_before_occurred_at`, `p_before_id`), ambos ou nenhum; 1–50 por página (padrão 20); até 50 itens por evento, com `item_count` e `items_truncated`. Eventos da mesma transação têm o mesmo momento e se ordenam pelo `id`.

### 15.6 Idempotência

- Cabeçalho só no primeiro item: operação sem efeito não grava.
- Repetições idempotentes das funções homologadas (`ALREADY_APPLIED`, `UNCHANGED`, listas vazias) saem antes do begin nas fatias S2–S6.
- Legado: importação não repete o que já existe (chave, fichário, coleção, titular).

### 15.7 Atomicidade

Gravação na transação da operação; contexto em configuração local da transação, desfeito junto com a subtransação que falhar (harness 2.10). Uma chamada do cliente = um evento (C-205); duas operações na mesma transação = dois eventos (harness 2.4).

### 15.8 Índices e hipóteses de desempenho

| Índice | Hipótese (a medir, não comprovada) |
|---|---|
| `ix_bae_owner_layout_time (owner_user_id, layout_key, occurred_at desc, id desc)` | Primeira página e cursor sem Seq Scan, ≤ 50 ms com 100 mil eventos num fichário (meta P2); prefixo atende à cascata da conta e à listagem de encerrados |
| PK do item `(event_id, ordinal)` | Itens de uma página de 20 eventos por busca indexada |

Filtro por categoria aplicado sobre o índice principal. Índice por tipo só se a medição P2 mostrar necessidade.

### 15.9 Dependências e reversão

- **Ordem:** 5267 → 5268 → 5269 → 5270. Cada arquivo tem precheck: recusa se o objeto já existe ou se o anterior falta.
- **Dependências externas:** `auth.users`, `collection_layout`, `collection`, `collection_layout_page`, `collection_layout_slot`, `card`, `card_set`, `card_variant_type`, `collection_layout_catalog_incorporation`.
- **Reversão:** `R0_rollback_s1.sql` v1.1 remove exatamente os 14 objetos novos, em estado PARTIAL ou COMPLETE, e recusa ANOMALY. Precheck recusa a reversão se alguma função fora da S1 já referenciar o histórico (a partir da S2, reverter as fatias antes). O legado sai junto, e a linha original da 5263 permanece. **Não toca o ledger**; política de numeração e correção para frente no próprio arquivo (W2, §19.3).

### 15.10 Harness e verificações preparados (sem execução)

| Artefato | Conteúdo | Estado |
|---|---|---|
| `5860_validate_binder_activity_foundation.sql` v1.1 | `wh_5860_validate()`: 47 checagens (+0.6 W8, +0.7 B1, +2.11/2.12 W1; 9.2 reescrito); `wh_5860_perf()`: volume de 300 mil eventos, 2 medições contra a meta e 2 PASS/FAIL de plano | **OFICIALMENTE NÃO EXECUTADO** |
| `LIVE_00_precheck_readonly.sql` | 6 checagens de leitura antes da 5267 | PREPARADO |
| `LIVE_90_postcheck_readonly.sql` v1.1 | 12 checagens de leitura depois da 5270 (+90.11 W8, +90.12 B1) | PREPARADO |
| `R0_rollback_s1.sql` v1.1 | Reversão por estado, sem tocar o ledger (W2) | PREPARADO, NÃO EXECUTADO |
| `LIVE_DRYRUN_S1_rollback.sql` v2.1 (só cabeçalho mudou desde a v2.0) + `build_live_dryrun_s1.py` + `sql_lexer_p3b.py` | Ensaio LIVE: migrations no nível superior, uma transação, trava de COMMIT, guarda de autocommit, sentinela (§21) | PREPARADO, NÃO EXECUTADO |
| `static_check_p3b_s1.py` | 47 checagens estáticas (G4 + B1/W1/W2/W3/W8 + verificador W3 com 7 mutações + verificador do ensaio D-0..D-9 com 10 mutações) | **EXECUTADO localmente: 47/47 PASS** (só leitura de arquivos) |

## 16. Matriz de decisões e rastreabilidade

| Decisão | Canônico | Objeto da S1 | Prova (harness 5860 / estática) |
|---|---|---|---|
| D1 histórico por fichário | C-201, LDM-196 | `layout_key`, `collection_id` no evento | 2.2, 5.1 |
| D2 agregado com itens | C-205, LDM-197/199 | contexto e itens | 2.3 |
| D3 saídas do Meu acervo | C-201 | origem `ACERVO`/`COLECAO`, tipos E06/E07 | (S5) |
| D4 legado parcial | C-209, LDM-203 | 5270 B | 0.5; LIVE_90 90.6–90.7 |
| D5/O1 A1+A3+A5 | C-202, C-203 | chave sem FK; FK de titular em cascata; purge | 6.2, 8.x, 9.1 |
| D6 lotes do navegador | C-205 | (nenhum na S1) | (S3, I7) |
| D7 fixar/desfixar | C-201 | tipos `POCKETS_LOCKED/UNLOCKED` | 2.4 |
| D8 seção no Centro de Controle | C-201 | leituras 5269 | (S7) |
| O2 estrutura da exclusão | C-203 | purge sem permissão de cliente | 1.2, 8.x; S.8 |
| O3 instrumentação explícita | — (engenharia, §7) | gate estático (S2–S6) | S.2–S.4 |
| O4 cobertura | C-209, LDM-202 | `binder_activity_setting`; leitura de cobertura | 5.6; LIVE_90 90.9 |
| O5 encerramento e transferência | C-202, C-207 | tipos E19/E19b/E20; segregação | 6.x, 7.1 |
| P1 E20 | C-207 | tipo `BINDER_OWNERSHIP_TRANSFERRED` | §14.7 (S6) |
| Imutabilidade (C-179) | C-203, LDM-201 | gatilhos | 3.1–3.4 |
| Só o concluído (C-206) | C-206, LDM-199/200 | cabeçalho preguiçoso | 2.1, 2.8–2.10 |
| Titular e acesso (C-172, C-204) | C-204, LDM-198 | filtro por titular | 1.x, 5.5, 6.4 |

## 17. Gates G1–G8 — estado consolidado (v1.5)

| Gate | Situação | Evidência / falta |
|---|---|---|
| G1 — auditoria | **ATENDIDO POR INSPEÇÃO, com condição** | B1, W2, W8 aceitos (`P3-B-S1-LIVE-DRYRUN-STRUCTURAL-CORRECTION-02`); ensaio v2.0 aceito; W1 aceito condicionado a I-7/I-10 e às provas das fatias (§19.2). Os ajustes documentais desta v1.5 não mudam SQL |
| G2 — promoção conceitual | **ATENDIDO** | C-201 a C-209 e LDM-196 a LDM-203, com esclarecimento do ator (C-203/LDM-196) |
| G3 — numeração livre | **ATENDIDO** (reconfirmar) | Ledger lido em 2026-10-25: último `5266_…`; 5267–5270 livres. Reconfirmação obrigatória por LIVE_00 imediatamente antes de qualquer execução |
| G4 — SQL escrito + só objetos novos | **ATENDIDO (estático)** | `static_check_p3b_s1.py` 47/47 PASS; migrations 5267, 5269, 5270 inalteradas desde a v1.3 e 5268 desde a v1.4 |
| G5 (original) | **DESDOBRADO** | Exigência original preservada em §12; dividida abaixo sem afrouxar nenhum item |
| G5a — prontidão estrutural | **ATENDIDO (estático, por inspeção)** | Harness 5860 v1.2 revisado (47 checagens); ensaio v2.1 gerado e conforme D-0..D-9; R0, LIVE_00/90 prontos; S.1–S.18 PASS |
| G5b — comportamento | **FECHADO — NÃO EXERCITADO** | Harness 5860 (47 checagens funcionais/segurança) sem protocolo; ensaio LIVE (compilação, privilégios, gatilhos, legado, reversão) sem autorização |
| G5c — desempenho | **FECHADO — NÃO EXERCITADO** | `wh_5860_perf` (P.3/P.4 PASS/FAIL de plano; P.1/P.2 medições contra a meta P2 ≤ 50 ms) sem protocolo |
| G6 — Security Advisor | **PARCIAL** | Revisão estática feita; leitura do Advisor só após aplicação real |
| G7 — plano de reversão | **ATENDIDO (estático)** | R0 v1.1 (estados, ledger intocado, forward fix); não exercitado |
| G8 — autorização LIVE | **FECHADO** | — |

## 18. Parecer (v1.5)

- **GO para encerrar o readiness documental da S1** (nada mais a preparar sem novos mecanismos).
- **NO-GO para qualquer execução** — S1, harness, ensaio LIVE, R0 — até as evidências de §25 e as decisões de Fabrício sobre G5b/G5c e G8.

## 19. Correções da auditoria estática (v1.3)

### 19.1 B1 — imutabilidade × exclusão de conta

**Problema.** `actor_user_id … REFERENCES auth.users ON DELETE SET NULL`: a ação referencial é um UPDATE no evento, que o gatilho `trg_bae_immutable` recusa. Excluir a conta de quem foi ator num evento de outro titular falharia (e o harness 9.2 esperava NULL).

**Alternativas comparadas.**

| Critério | A — exceção controlada de UPDATE (ator → NULL quando a conta não existe mais) | **B — ator como valor, sem FK (escolhida)** |
|---|---|---|
| Segurança | Abre um ramo de UPDATE no gatilho; precisa provar que só `actor_user_id` muda, só para NULL, só se a conta sumiu — superfície nova, sujeita a erro de comparação coluna a coluna | Gatilho continua recusando **todo** UPDATE, sem exceção. Nenhuma ação referencial pode reescrever evento |
| Integridade | Modifica linha histórica (perde o dado original do ator) | Linha histórica nunca muda. O ator foi validado na gravação (`auth.uid()` = titular, 5268) |
| Simplicidade | +1 ramo de gatilho, +1 índice para o SET NULL, +casos de teste | −1 FK, −1 índice (`ix_bae_actor`), gatilho inalterado |
| Manutenção | Toda coluna nova do evento exige revisar o ramo de exceção | Nada a manter |
| Segregação por titular | Igual | Igual: leitura filtra por titular (C-207); ator não é exposto pelas leituras da S1 |
| Eliminação na exclusão da conta | Igual (cascata do titular) | Igual: FK do titular em cascata apaga eventos, itens e marcos do titular (porta (b) do gatilho) |

**Prova de que não há alteração arbitrária do histórico.** (i) A guarda trata `tg_op = 'UPDATE'` com `raise` incondicional e não tem `RETURN NEW` (S.13); (ii) a única FK do evento é a do titular, com `ON DELETE CASCADE` (harness 0.7; LIVE_90 90.12) — cascata é DELETE, não UPDATE; (iii) o item só sai em cascata do evento; (iv) harness 3.1 (UPDATE recusado) e 9.2 (exclusão da conta de C conclui, e o evento de B em que C era ator fica com `actor_user_id = C`, mesmo `created_xact`, mesmo item).

**Consequência aceita.** Em eventos de outro titular, o ator excluído permanece como identificador opaco, sem resolução para `auth.users`. Na V1 isso não ocorre (ator = titular, 5268; o evento sai com a conta). Só passa a existir com colaboração futura; se for exigida anonimização, será decisão própria e executada por DELETE/regravação autorizada, nunca por UPDATE silencioso. Contratos homologados de outros módulos: intocados.

### 19.2 W1 — limite de itens fundamentado (v1.4: demonstração e reforço)

**Teto (5268 v1.2):** `páginas × (8 × linhas × colunas + 2) + 8 + c_repeat_slack (600)`, calculado no primeiro item, **recalculado em todo item `PAGE`/`PAGE_ADDED`** (gravado depois de criar a página, I-10) e sempre que excedido; guarda o máximo observado.

**Base factual (leitura LIVE 2026-10-25):** por bolso há no máximo 1 carta (`UNIQUE(slot_id)` em `collection_layout_slot_assignment`), 1 reserva (PK `slot_id` em `_slot_expected_content`), 1 imagem (PK `slot_id` em `_slot_image`) e a trava (`locked`, coluna do bolso). A grade é imutável (5107). Limites das funções homologadas lidos do canônico: 5264 `c_row_limit = 500` (soma de linhas movidas em todos os deslocamentos) e `c_item_limit = 100`; 5243 `c_row_limit = 500`; 5133/5129/5130/5249 500 por chamada; 5224 10.000 alocações e 20.000 bolsos.

**Lema.** Seja S o número de bolsos do fichário no momento de qualquer recálculo. Para cada tipo de objeto, os objetos distintos tocados por uma operação são no máximo os ocupantes antes (≤ S) mais os ocupantes depois (≤ S); com um item por objeto e efeito, os itens de bolso são ≤ 4 × 2S = 8S. Páginas: ≤ 2 efeitos cada. Coleção/fichário: ≤ 8. Deslocamentos **repetidos** do mesmo objeto (só a reconciliação E16, que abre um espaço por novidade e cujos itens vêm das chamadas aninhadas, R5) somam no máximo `c_row_limit` da 5264 = 500, mais ≤ 100 novidades → folga de 600. S.14 confere que a folga continua ≥ os limites reais da 5264 e da 5243.

| Operação | Itens máximos (I-7, efeitos distintos) | Teto disponível | Coberto |
|---|---|---|---|
| E01 montagem (5224) | cartas colocadas ≤ min(10.000, S) + reservas ≤ S + páginas ≤ P + ≤ 8. Itens gravados depois de criar páginas/bolsos (I-10) → o recálculo vê S final | 8S + 2P + 8 + 600 | sim (2S + P + 8 ≤ 8S + 2P + 8) |
| E11 abrir espaço (5243) | linhas movidas ≤ 500 (cada objeto 1 vez; carta/reserva/imagem) + página embutida 1 (PAGE_ADDED → recálculo) + ≤ 8 | idem | sim (≤ 3S ou ≤ 500 dentro da folga) |
| E12 fechar espaço (5243) | linhas movidas ≤ 500 + página removida 1 + ≤ 8. Itens de origem antes de apagar a página (I-10) → o teto calculado antes não diminui | idem | sim |
| E16 novidades (5266) | linhas movidas somadas ≤ 500 (com repetição) + reservas novas ≤ 100 + páginas novas ≤ 100 (cada uma com PAGE_ADDED → recálculo) + ≤ 8 | ≥ 8S + 2P + 8 + 600 | sim: 500 + 100 cabem na folga; páginas no termo 2P recalculado. **Sem a folga não cobria**: num fichário de 50 bolsos com 10 novidades, até 500 + 20 + 8 = 528 itens contra 408 de capacidade — lacuna da v1.3, corrigida |
| E03 mover / E04 trocar | 1 / 2 itens de carta (+ reservas, se a função as mover junto: ≤ 2) | ≥ 8·S | sim |
| E05 retirar (5133) | ≤ 500 por chamada e ≤ cartas no fichário ≤ S | ≥ 8·S | sim |
| E06a/E06b saída por local | cartas que saem ≤ min(500 ou 10.000, cartas no fichário ≤ S) | ≥ 8·S | sim |
| E07 saída do acervo | 1 | ≥ 8 + 600 | sim |
| E08 / E09 / E10 | 1 / ≤ min(500, S) / ≤ min(500, S) | ≥ 8·S | sim |
| E13 páginas adicionadas | 1 página por chamada (PAGE_ADDED → recálculo) | idem | sim |
| E14 página removida | 1 página + objetos da página ≤ 4·L·C (antes de apagar) + renumeradas ≤ P | ≥ 8·L·C·P + 2P | sim |
| E15 reordenar | ≤ P renumeradas | ≥ 2P | sim |
| E17 / E18 | 1 / reservas liberadas ≤ S + 1 | ≥ 8·S | sim |
| E19 desmontagem (5226) | cartas + reservas + travas + imagens que saem ≤ 4S + 1, registrados antes de apagar | ≥ 8·S | sim |
| E19b / E20 | 1 / 1 | ≥ 8 + 600 | sim |

**Condições que permanecem** (por isso W1 segue condicionado à cobertura das fatias): (i) I-10 — itens de origem antes de apagar, de destino depois de criar, PAGE_ADDED depois da página; (ii) I-7 — fora da E16, um item por objeto e efeito; (iii) se uma fatia futura repetir deslocamentos em outra função, a folga precisa ser revista (S.14 só acompanha 5264 e 5243). Prova dinâmica: harness 2.11 (676 aceitos, 677º recusado num 2×2 de 2 páginas) e 2.12 (PAGE_ADDED recalcula); prova por operação fica com o harness de cada fatia S2–S6. Nenhuma função homologada foi alterada.

### 19.3 W2 — R0 e ledger

R0 v1.1 classifica o estado antes de agir (NONE, PARTIAL, COMPLETE, ANOMALY → recusa), remove só objetos da S1 por `DROP … IF EXISTS`, nunca escreve no ledger e documenta: linhas de 5267–5270 permanecem; R0 é aplicado com número novo para o ledger registrar a reversão; reaplicar com a mesma numeração é vedado (LIVE_00 00.3 recusa); migration que falhou não consome número; correção para frente com nova faixa, após (a)–(f); intervenção no ledger só com autorização específica. Nada foi executado.

### 19.4 W8 — sequência da identidade

`REVOKE ALL ON SEQUENCE public.binder_activity_event_id_seq FROM PUBLIC, anon, authenticated, service_role`, com conferência do nome via `pg_get_serial_sequence` (falha alto se divergir). Independe dos privilégios padrão do executor (leitura LIVE: padrões de `postgres` em sequências não concedem a clientes; os de `supabase_admin` concedem — por isso o REVOKE explícito). Provas: S.12; harness 0.6; LIVE_90 90.11.

## 20. Contrato obrigatório de instrumentação (W3, para S2–S6)

Vale para toda função homologada que as fatias S2–S6 recriarem. Verificado por `w3_violations()` no `static_check` (S.16/S.17); as regras marcadas "harness" exigem prova dinâmica na fatia.

| Regra | Conteúdo | Verificação |
|---|---|---|
| I-1 Abertura | Exatamente **um** `binder_activity_begin` por função, no bloco externo, depois das validações e travas e **depois** de todo retorno idempotente (`ALREADY_APPLIED`, `UNCHANGED`, lista vazia) | estática |
| I-2 Fechamento | `binder_activity_end()` imediatamente antes de **cada** `RETURN` que sai da função após o begin (RETURN NEXT/QUERY não contam) e no fim do corpo se houver queda | estática |
| I-3 Exceções | Begin nunca dentro de handler `EXCEPTION`. Erro não capturado aborta a transação e leva contexto e evento junto (R1, harness 2.10) | estática + harness |
| I-4 Sem perda silenciosa | `add_item` não pode ficar em bloco cujo `EXCEPTION` engula o erro: o handler precisa re-lançar (`RAISE`) | estática |
| I-5 Gravação única | Só via `add_item`; nenhum `INSERT` direto em `binder_activity_event/item` | estática |
| I-6 Contexto | Ninguém fora da 5268 lê ou escreve `mmkyu.binder_activity_ctx` | estática (S.17) |
| I-7 Sem duplicidade | Um evento por operação; um item por (objeto, efeito), exceto deslocamentos repetidos do mesmo objeto na E16 (chamadas aninhadas de 5243, R5), cobertos pela folga do teto (§19.2); chamadas internas **aninham** (begin aumenta a profundidade) e só acrescentam itens ao evento externo | harness (2.3) + revisão do diff |
| I-8 Sem efeito, sem evento | Operação sem item não grava (cabeçalho preguiçoso) | harness (2.1) |
| I-9 Isolamento na transação | Profundidade 0 limpa o contexto: duas operações na mesma transação = dois eventos; operação aninhada em outro fichário é recusada | harness (2.4, 2.5) |
| I-10 Ordem | `add_item` de origem antes de apagar/renumerar o bolso ou a página; de destino depois de gravá-lo (cópia R3) | revisão do diff + harness da fatia |

## 21. Ensaio LIVE com reversão (v2.1 — preparado, não autorizado)

*v2.1 (2026-10-25): só o cabeçalho mudou — descrição exata dos locks em `auth.users`, alcance do `lock_timeout`, contrato do executor (§23) e restauração de `default_transaction_read_only` por caminho. SQL executável idêntico ao da v2.0.*

**Causa-raiz do defeito da v1.0.** O gerador embutia o texto das 5267–5270 dentro de um único `DO $dryrun$` PL/pgSQL. Assim o DDL era executado indiretamente pelo interpretador PL/pgSQL (cada comando reanalisado como statement de função e despachado via SPI, com DO e CREATE FUNCTION aninhados), não como SQL de nível superior — que é como as migrations rodam de fato. O ensaio deixava de testar as migrations aprovadas e passava a depender de o PL/pgSQL aceitar cada comando utilitário, o que nunca foi provado. A verificação estática só comparava texto ("gerado sem divergência"), não estrutura. Não havia trava contra COMMIT além da sentinela.

**Correção (v2.0).** Estrutura completa no cabeçalho do arquivo (A–D e itens 1–9):

```
T0  SET SESSION default_transaction_read_only = on     -- autocommit não escreve
T1  BEGIN ; T2 SET TRANSACTION READ WRITE
T3  SET LOCAL statement_timeout 20s, lock_timeout 2s, idle_in_transaction 15s, transaction_timeout 60s
T4  trava de COMMIT (FK temporária DEFERRABLE INITIALLY DEFERRED violada)
T5  tabela temporária de evidência
T6  DO precheck (só leitura)
T7  5267 → 5270 no NÍVEL SUPERIOR, statement a statement, texto aprovado sem begin;/commit;
T8  DO postcheck + DO sondas (só verificação)
T9  DO sentinela → RAISE 'MSDRYRUN {json}' (sempre)
T10 ROLLBACK ; T11 RESET default_transaction_read_only
```

**Por que não pode confirmar:** o caminho normal termina em erro (T9); COMMIT em transação abortada vira ROLLBACK; COMMIT em transação ativa falha na verificação adiada de T4; executor que ignora o BEGIN roda tudo em somente leitura (T0) e o DDL falha com 25006; script inteiro numa só mensagem é atômico e T0 é desfeito junto. Erros antes, durante e depois da aplicação, interrupção, perda de conexão e transação abortada: tabela C/D do cabeçalho.

**Sondas (semântica confirmada por leitura do LIVE, 2026-10-25):** `postgres` é membro de `anon`, `authenticated` e `service_role` (SET ROLE válido); `auth.uid()` = `request.jwt.claim.sub` ou `request.jwt.claims->>'sub'` (vazios → NULL → zero linhas); `session_replication_role = origin` (gatilhos disparam; o precheck exige isso); `postgres` é dono das tabelas novas (UPDATE/DELETE/TRUNCATE chegam ao gatilho, que recusa com `BINDER_ACTIVITY_IMMUTABLE`); anon sem EXECUTE → 42501. Servidor PostgreSQL 17.6 (`transaction_timeout` disponível).

**Verificação estática:** `sql_lexer_p3b.py` separa statements respeitando comentários aninhados, strings, identificadores e delimitadores dólar (não é parser). `dryrun_violations()` aplica D-0..D-9; S.18d prova que ele recusa 10 mutações, entre elas COMMIT no lugar do ROLLBACK, trava removida, SET CONSTRAINTS, guarda removida, migrations dentro de DO e comentário fechado cedo por `*/` (defeito encontrado e corrigido no próprio cabeçalho gerado durante esta rodada).

## 22. Riscos residuais classificados (v1.5)

| # | Risco | Classe | Mitigação / estado |
|---|---|---|---|
| R1 | SQL (migrations e ensaio) nunca analisado por parser do PostgreSQL nem executado | **Alto — bloqueia aplicação** | Ensaio LIVE (erro de sintaxe vira STOP, sem efeito) e/ou G5b |
| R2 | Comportamento (47 checagens) e desempenho sem prova dinâmica | **Alto — bloqueia aplicação** | G5b/G5c dependem de decisão de protocolo |
| R3 | Lock SHARE ROW EXCLUSIVE em `auth.users` durante o ensaio e a aplicação: escritas (cadastro, login que grava `last_sign_in_at`, alterações de conta) esperam até o fim da transação | **Médio — operacional** | Janela fora de uso; duração esperada < 2 s; `lock_timeout` só limita a espera para obter o lock; a duração é limitada por statement 20 s / ocioso 15 s / transação 60 s |
| R4 | Executor fora do contrato (trechos selecionados, troca de conexão, sessão mantida após erro) | **Médio — operacional** | Contrato §23; S.18 garante o arquivo, não o executor |
| R5 | `default_transaction_read_only` remanescente na sessão quando o executor para no erro e mantém a conexão (psql `\i` interativo, ferramenta que reaproveita a sessão, executor que ignora o BEGIN) | **Baixo — falha segura** | A sessão só fica somente leitura, nunca escreve; D5 obriga fechar a conexão ou RESET + SHOW; item do pós-estado |
| R6 | `transaction_timeout` definido dentro da transação: contagem a partir do SET (PG 17) não comprovada | **Baixo** | Statement 20 s e ocioso 15 s cobrem; duração real esperada < 2 s |
| R7 | W1 depende de I-7/I-10 e da folga só acompanhar 5264/5243 | **Médio — condicional** | Provas por fatia S2–S6 (§25 item 9); revisão da folga se outra função repetir deslocamentos |
| R8 | Verificadores estáticos (lexer, W3, D-0..D-9) são sintáticos | **Baixo** | Mutações provam detecção; não substituem execução |
| R9 | Ator opaco com colaboração futura (B1) | **Baixo — futuro** | Sem efeito na V1 |
| R10 | Herdados: ordenação por início da transação; guardas DEFINER; superusuário pode desativar gatilhos; legado com nome de coleção NULL; ausência de fluxo de exclusão de conta (P6) | **Baixo / aceitos** | Documentados desde a v1.2 |

## 23. Contrato operacional do executor do ensaio

| Item | Regra |
|---|---|
| D1 Conexão única | Do T0 ao T11 na mesma conexão; proibido pooler em modo transação/statement |
| D2 Execução integral | Arquivo inteiro, na ordem, sem edição nem seleção de trechos; hash conferido com `build_live_dryrun_s1.py --check` antes |
| D3 Forma | E1: mensagem simple-query única (SQL Editor do Supabase, execute_sql), sem parâmetros; ou E2: `psql -X -v ON_ERROR_STOP=1 -f LIVE_DRYRUN_S1_rollback.sql`, não interativo, sem `-1`/`--single-transaction` |
| D4 Erros | Parar no primeiro erro. Esperado: só `MSDRYRUN …` (T9). Qualquer outro = STOP; não repetir, não completar à mão, não enviar COMMIT |
| D5 Recuperação | Ao fim, sempre: fechar a conexão. Se a sessão continuar aberta: `ROLLBACK;` `RESET default_transaction_read_only;` e `SHOW default_transaction_read_only` = `off` |
| D6 Interrupção | Queda de conexão: o servidor desfaz ao fim do statement corrente; ocioso em transação: 15 s; depois conferir o pós-estado; não repetir |
| D7 Pré e pós | LIVE_00 imediatamente antes e imediatamente depois (todos `true`); `pg_stat_activity`/`pg_locks` sem sessão nem lock do ensaio |
| D8 Janela | Fora de uso (escritas em `auth.users` esperam durante o ensaio) |

Restauração de `default_transaction_read_only` por caminho: cabeçalho do ensaio, seção E. Resumo: sem resíduo em E1 (T0 é desfeito com a transação), em E2 não interativo (a conexão fecha) e em executores que continuam após erro (T11); **com resíduo** — sempre de somente leitura — quando o executor para no erro e mantém a sessão; por isso D5 é obrigatório.

## 24. Garantias: demonstradas por inspeção × não exercitadas

| Garantia | Demonstrada por inspeção / estática | Ainda não exercitada |
|---|---|---|
| S1 só cria objetos novos; nada homologado alterado | S.2–S.4, S.17 | Aplicação real |
| Privilégios: tabelas sem acesso de cliente; EXECUTE só nas 3 leituras; sequência revogada | S.5–S.8, S.12; LIVE_90 90.2–90.4, 90.11 | Ensaio (T8a) / harness 0.x / Advisor |
| Imutabilidade (UPDATE/DELETE/TRUNCATE recusados; porta só da 5270 e da cascata da conta) | S.13; leitura do código da guarda | Ensaio (sondas T8b), harness 3.x, 8.x, 9.x |
| B1: exclusão de conta não reescreve histórico | S.13; harness 0.7/9.2 escritos | Harness 9.x |
| Segregação por titular nas leituras | Revisão da 5269 | Harness 5.x, 6.x, 7.1 |
| W1: teto cobre operações válidas | Demonstração por operação (§19.2); S.14 contra 5264/5243 | Harness 2.11/2.12; provas por fatia S2–S6 |
| W3: contrato de instrumentação verificável | S.16 (7 mutações), S.17 | Diffs e harness das fatias |
| Ensaio não confirma alterações | Estrutura A/B; D-0..D-9; 10 mutações (S.18d); trava de COMMIT; T0 | Execução do ensaio |
| Ensaio executa as migrations como aprovadas | S.18b D-4 (statements idênticos, nível superior) | Execução do ensaio |
| Reversão R0 por estado, sem ledger | S.11, S.15 | Nunca exercitada |
| Locks e tempo do ensaio | Análise de modos de lock (§21, item 3) | Medição real |
| Semântica das sondas | Leitura do LIVE: papéis, `auth.uid()`, `session_replication_role`, PG 17.6 | Execução do ensaio |
| Desempenho (meta P2 ≤ 50 ms, P3) | Hipóteses de índice (§15.8) | G5c |

## 25. Evidências necessárias para eventual autorização

**Para autorizar o ensaio LIVE (não abre G8):**

1. Arquivo do ensaio idêntico ao gerado (`build_live_dryrun_s1.py --check` = EM DIA) e `static_check_p3b_s1.py` 47/47 na revisão final, com hashes dos arquivos registrados.
2. LIVE_00 lido no dia: ledger termina em `5266_…`, nenhum objeto `binder_activity_*`, 5267–5270 livres, 1 incorporação.
3. Executor e forma declarados conforme §23 (E1 ou E2), janela definida e autorização específica de Fabrício.
4. Resultado do ensaio: erro único `MSDRYRUN` com `"ok": true`, todas as verificações `true`, `duration_ms` ≤ 5000.
5. Pós-estado: LIVE_00 inteiro `true`; nenhuma sessão nem lock do ensaio; conexão fechada ou `SHOW default_transaction_read_only = off`.

**Para pedir G8 (aplicação da S1):**

6. Itens 1–5 cumpridos (ou decisão expressa de Fabrício dispensando o ensaio, com R1 aceito por escrito).
7. G5b: harness 5860 com GATE 47/47 num protocolo aprovado por Fabrício — ou decisão formal registrando a dispensa e os riscos R2 aceitos.
8. G5c: `wh_5860_perf` com P.3/P.4 PASS e P.1/P.2 registradas contra a meta — ou dispensa formal equivalente.
9. W1: compromisso registrado de que cada fatia S2–S6 traz diff conforme I-7/I-10 e S.16, e harness próprio cobrindo o volume máximo das suas operações (as fatias não fazem parte da S1).
10. Plano de execução: LIVE_00 → 5267 → 5268 → 5269 → 5270 → LIVE_90 (12/12) → Security Advisor sem alerta novo atribuível à S1 (G6), parando no primeiro desvio; R0 v1.1 como contingência.
11. Reconfirmação do ledger (G3) no momento da execução.
12. Autorização operacional expressa de Fabrício para o LIVE (G8).

## 26. Gate de execução do ensaio — preparação (`P3-B-S1-LIVE-DRYRUN-EXECUTION-GATE-01`, 2026-10-25)

Autorização desta rodada: **só preparação e leituras**. Ensaio NÃO executado; G8 FECHADO.

### 26.1 Artefatos congelados (SHA-256, 2026-10-25)

| Arquivo | SHA-256 |
|---|---|
| `5267_create_binder_activity_structures.sql` | `e8e69f4c5020656ea3778872f8c45b02319bc2f97dcaec4e5f49c37a845b69dc` |
| `5268_create_binder_activity_recording_functions.sql` | `76e2bac4de3dffed83b6010a8b50c9c7888cb5d2cf39683c229b5313c947c6db` |
| `5269_create_binder_activity_reads.sql` | `98d83f701c9d3b1d45bf2d21900cca5066854648ef2947aa52cded2053b3e435` |
| `5270_create_binder_activity_purge_and_legacy.sql` | `53dc5fd526315b56445337b39e336770bdefe904e6e3e866bb5c5f4799458c9d` |
| `LIVE_DRYRUN_S1_rollback.sql` (v2.1) | `ddd0dbf2ef5346f5c3536d8b2d1d62ee3eab1cbc5ecc9d732d9a598e1322f74b` |
| `build_live_dryrun_s1.py` | `4f3bacaa1668a79c7f24f3b823d8285c7bcb7b48b88e5ead49b0451cbc32a2e9` |
| `static_check_p3b_s1.py` | `99e9b69d6625d0b498cf516d466bf6d6705014196a9fec787dd70de08c20b372` |
| `sql_lexer_p3b.py` | `e1c25043bfcc9281d5536be6d88cc039e49155a245d6e7538f2aad063881e5bc` |
| `5860_validate_binder_activity_foundation.sql` (v1.2) | `38d095db6e567cf5f316ce395c2ddd4f7ff1be3597c86f783b03e872166e9532` |
| `R0_rollback_s1.sql` (v1.1) | `206b3077fe90d778f20278dfcf73fb556a6c0015bfcf287ea6d914dd6fcb6da8` |
| `LIVE_00_precheck_readonly.sql` | `3868c4e42728dc16566649f18f799037085f3655ce1e26cc9a0579f91c3d2d7b` |
| `LIVE_90_postcheck_readonly.sql` | `8b0dacd70965b5f26b367af9f09254b44fa35f2acfa2ff58fba38dc29fda4e4d` |
| `LIVE_DRYRUN_S1_gate_readonly.sql` (novo, só SELECT) | `53f4b3f038108f0069014f72923ca9fa73a2f9f5f397c2a8b024cd1f564a798b` |

O cabeçalho do ensaio registra as fontes `5267@e8e69f4c5020656e, 5268@76e2bac4de3dffed, 5269@98d83f701c9d3b1d, 5270@53dc5fd526315b56`, iguais aos prefixos acima. `build_live_dryrun_s1.py --check` = EM DIA; `static_check_p3b_s1.py` 47/47 PASS.

### 26.2 Leituras LIVE do dia (resumo; valores literais no relatório da rodada)

LIVE_00 00.1–00.6 = true (ledger `20261025145504` / `5266_…`, 534 linhas). PG 17.6; sessão `postgres`; `default_transaction_read_only = off`; `session_replication_role = origin`; timeouts do servidor 2min/0/0/0; GUCs `mmkyu.*` nulas; 6 event triggers ativos (só `pgrst_ddl_watch` dispara em DDL; NOTIFY transacional); `postgres` membro de anon/authenticated/service_role. `auth.users`: 3 linhas, 2 gatilhos (`on_auth_user_created`, `on_auth_user_created_inventory`), 20 FKs de `public`; última atualização 2026-10-25 20:18:31 UTC (≈ 27 min antes da leitura — há uso real). Concorrência: 0 sessões ativas além da leitura, 0 transações ociosas/abortadas, 0 locks em `auth.users`, 0 locks aguardando, 0 DDL/autovacuum. Estruturas homologadas: incorporação Chi-Yu íntegra, dono coerente, 7 funções relevantes presentes, 24 colunas usadas pela 5268 presentes, maior fichário 1.056 bolsos. G-PRE P.01–P.10 = true; linha de base P.10 registrada.

### 26.3 Executor E1 via `execute_sql` — SUBSTITUÍDO por E2 em §27 (a sonda não prova o comportamento diante do erro `MSDRYRUN`)

Sonda somente leitura (3 SELECTs numa chamada, com `pg_sleep(0.3)`): resultado só do último statement, `now() = statement_timestamp()` verdadeiro e 316 ms desde a mensagem → os statements chegam numa **única mensagem simple-query** e rodam numa **única transação**, sem transação externa da ferramenta. Logo: uma conexão por construção (D1), arquivo inteiro numa chamada, sem seleção de trechos (D2), erro devolvido em texto (evidência `MSDRYRUN`). Ressalva: o estado em que a ferramenta deixa a conexão após erro não é observável; se a conexão voltar ao pool em "transação abortada", ela não tem locks nem escreve, e Q.03 a detecta. Alternativa: E2 (`psql -X -v ON_ERROR_STOP=1 -f`) por Fabrício.

### 26.4 Protocolo exato (quando autorizado)

1. Estático: `build_live_dryrun_s1.py --check` = EM DIA; `static_check_p3b_s1.py` = 47/47; SHA-256 do ensaio = `ddd0dbf2…74b`.
2. Leituras imediatamente antes: LIVE_00 (6 true) e G-PRE (P.01–P.10 true; guardar P.10). Fabrício confirma que ninguém está usando o app. Qualquer false = STOP.
3. Uma única chamada `execute_sql` com o conteúdo integral do arquivo, sem nenhuma alteração.
4. Esperado: erro P0001 `MSDRYRUN {"ok": true, …}` com todas as verificações true e `duration_ms` ≤ 5000. Qualquer outro resultado = STOP (inclusive sucesso sem erro).
5. Leituras imediatamente depois: G-POST (Q.01–Q.07 true; Q.08 = P.10) e LIVE_00 (6 true).
6. Registrar resultados literais; não repetir o ensaio sem nova autorização.

## 27. Executor E2 (psql não interativo) — prontidão (`P3-B-S1-LIVE-DRYRUN-EXECUTOR-E2-READINESS-02`, 2026-10-25)

Decisão de Fabrício: E2 substitui E1 (§26.3). Ensaio NÃO executado; G8 FECHADO.

### 27.1 Cliente psql

- **Disponibilidade na máquina de Fabrício: NÃO VERIFICADA** — o ambiente do agente não acessa o Windows do proprietário. Dependência registrada. Verificação (PowerShell):
  `Get-Command psql` e `psql --version` → exigido `psql (PostgreSQL) 17.x` (mesma major do servidor 17.6; o script recusa < 17).
  Instalação, se faltar: instalador oficial PostgreSQL 17 para Windows (EDB) com o componente "Command Line Tools", ou `winget install PostgreSQL.PostgreSQL.17`, e incluir `C:\Program Files\PostgreSQL\17\bin` no PATH. Só o cliente é usado; nenhum servidor/banco local é criado ou iniciado.
- **Conexão:** direta `db.<ref>.supabase.co:5432`, usuário `postgres` (exige IPv6 ou add-on IPv4) **ou** Supavisor em **modo sessão** `<região>.pooler.supabase.com:5432`, usuário `postgres.<ref>` (uma conexão de servidor dedicada por conexão de cliente: preserva sessão, temporárias e transação). **Proibido:** porta 6543 (modo transação). Os scripts fixam a porta 5432.
- **Credenciais:** senha digitada na tela (`Read-Host -AsSecureString`), mantida só em `PGPASSWORD` do processo e apagada no `finally`. Nada em arquivo, log ou documento. SSL `verify-full` com o certificado do projeto (Dashboard → Database → SSL) ou, sem ele, `require`.

### 27.2 Artefatos E2 (preparados, não executados)

| Arquivo | Papel | SHA-256 |
|---|---|---|
| `E2_probe_readonly.ps1` v1.1 | Sonda **somente leitura**: psql por caminho explícito (padrão `C:\Program Files\PostgreSQL\17\bin\psql.exe`, sem PATH); SSL `verify-full` obrigatório (sem fallback); psql em processo filho com ambiente próprio (PG*/PSQLRC herdados descartados, pgpass e certificado de cliente neutralizados; sessão do PowerShell intocada); senha no prompt do psql (`-W`); só os 3 SELECTs de `$Queries`, sessão forçada a somente leitura; conferência automática de PID, usuário, banco, porta, versão, encoding, somente leitura, SSL, ledger e impressão digital | `719cef283136546dc024f79f9b9a2ad2992ee2992b5b3e8dea2142775b1c2bcb` |
| `static_check_e2_probe.py` | Verificação estática da sonda (P-0..P-7 + 13 mutações) — não é o parser do PowerShell | `74a67d293250fec3806000d282bc38c53bf9cabaae7dee197bfafb2e318f15d6` |
| `E2_run_live_dryrun_s1.ps1` | Procedimento definitivo: hash → psql 17+ → ambiente limpo → confirmação digitada → **um** processo `psql` → classificação → resumo; sem repetição | `7cd41797cbd1d0251d67a07dd1e8fdcef4459e1a32bd955d8284524164a129c2` |
| `LIVE_DRYRUN_S1_gate_readonly.sql` v1.1 | +P.11 (nenhuma sessão `mmkyu_dryrun_s1_e2` antes), +P.12 informativo, +Q.09 (sessão E2 encerrada) | `bc40ac84c88cee4cf3d18d111e765f560a259c12bbfdeedfb393d5c71e3199a5` |

Comando efetivo dentro do script (não executado):
`psql -X -v ON_ERROR_STOP=1 -v ON_ERROR_ROLLBACK=off -v VERBOSITY=verbose -f C:\mmkyu\dryrun\LIVE_DRYRUN_S1_rollback.sql`
com `PGAPPNAME=mmkyu_dryrun_s1_e2`, `PGCLIENTENCODING=UTF8`, `PGPORT=5432`, `PGOPTIONS`/`PSQLRC` removidos. O arquivo é copiado para um caminho ASCII sem espaços e o SHA-256 é reconferido ali (o caminho do repositório tem acentos e espaços).

Verificação estática do arquivo para o psql: sem BOM, LF, 70.619 bytes (1.902 não ASCII — por isso `PGCLIENTENCODING=UTF8` é obrigatório); nenhuma barra invertida (meta-comando) nem `:variável` fora de comentários e literais.

### 27.3 Semântica E2 (por documentação do psql/PostgreSQL; não exercitada)

| Situação | Comportamento | Código de saída | Decisão |
|---|---|---|---|
| Sentinela `MSDRYRUN` (caminho normal) | psql para no erro (ON_ERROR_STOP), sai, a conexão fecha, o servidor desfaz | **3** | só é válida se: 1 único ERROR, SQLSTATE **P0001**, mensagem `MSDRYRUN {json}`, todas as chaves presentes e `true`, legado 1/1, `duration_ms` ≤ 5000, nenhum `COMMIT` na saída → "SENTINELA_VALIDA" (não é PASS) |
| Erro inesperado / sintaxe (42601) / lock (55P03) / statement timeout (57014) | idem, sai no primeiro erro | 3 | STOP |
| `transaction_timeout` (25P04) ou ocioso (25P03) | servidor encerra a sessão (FATAL) | 2 | STOP |
| Perda de conexão | psql sai; servidor desfaz ao detectar | 2 | STOP |
| Ctrl+C | cancela o statement (57014) e o psql sai; PowerShell interrompe o script e apaga a senha | 3 (ou processo interrompido) | STOP |
| Sem exceção final | impossível sem edição do arquivo | 0 | STOP |
| psql não acha o arquivo / falha interna | — | 1 | STOP |

Nenhuma repetição automática: o script chama o psql uma vez, sem laço, job ou agendamento; qualquer STOP termina o script.

### 27.4 Sequência no dia da autorização

1. `sha256` dos 5 arquivos aprovados, `build_live_dryrun_s1.py --check`, `static_check_p3b_s1.py` 47/47, `git diff --check`.
2. `E2_probe_readonly.ps1` (Fabrício) → mesmo pid nos 3 comandos, `postgres`, porta 5432, 17.6, UTF8, SSL `t`, ledger `5266_…`, impressão digital = 1.
3. Leituras imediatamente antes (agente, `execute_sql` só SELECT): LIVE_00 (6 true); G-PRE P.01–P.11 true e P.12 registrado; contagens P.10 guardadas.
4. Duas condições distintas: (a) **sem concorrência incompatível no instante** (P.04–P.08, P.11) — o pré-check prova; (b) **sem uso planejado do app na janela** — só Fabrício atesta; (a) não prova (b).
5. Ensaio: `E2_run_live_dryrun_s1.ps1` uma vez. Pré-check aprovado não dispara o ensaio.
6. Imediatamente depois: G-POST Q.01–Q.09 true, Q.08 = P.10, e LIVE_00 (6 true). Só então se pode declarar PASS do ensaio.
7. STOP em qualquer ponto → não repetir; registrar saída integral (stdout, stderr, resumo); rodar G-POST e LIVE_00 para provar resíduo zero.

### 27.5 Correção de segurança da sonda (`P3-B-S1-E2-PROBE-SECURITY-CORRECTION-01`)

Sonda v1.1 substitui a v1.0 antes da primeira execução. `static_check_e2_probe.py` 14/14 PASS. Sintaxe PowerShell **não** validada por parser (sem PowerShell no ambiente do agente); validação sem executar, pelo proprietário:

```powershell
$t = $null; $e = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\E2_probe_readonly.ps1), [ref]$t, [ref]$e) | Out-Null
$e   # vazio = sem erro de sintaxe
```

O script de execução do ensaio (`E2_run_live_dryrun_s1.ps1`) ainda usa PATH, `PGPASSWORD` em variável do processo e fallback `require`: precisa da mesma correção antes de qualquer uso (fora do escopo desta rodada).

## 28. Executor por mensagem única (Dashboard SQL Editor / `execute_sql`) — avaliação (`P3-B-S1-LIVE-DASHBOARD-EXECUTOR-READINESS-01`, 2026-10-25)

**E2 (psql) suspenso:** o proprietário não tem a senha do PostgreSQL e não autoriza redefini-la para o ensaio. §27 fica como referência; `E2_*.ps1` não serão usados. Esta seção avalia o acesso já existente. **Nada foi executado nesta rodada.**

### 28.1 Contrato inspecionado (documentação e código-fonte público)

| Camada | Evidência | Conclusão |
|---|---|---|
| MCP `execute_sql` (`supabase-community/supabase-mcp`, `api-platform.ts`, `database-operation-tools.ts`) | envia `{query, read_only}` em **um** `POST /v1/projects/{ref}/database/query`; não divide, não envolve em transação; em erro lança `Error(message)` com a mensagem da API | uma chamada = um texto SQL inteiro |
| Management API `database/query` | código fechado; executa via postgres-meta (pg-meta). Impressões compatíveis: só o último resultado não vazio volta (`res.reverse().find(...)` do pg-meta) e conexão `mgmt-api` própria em `pg_stat_activity` (leitura de 2026-10-25) | **inferido, não documentado** |
| pg-meta (`supabase/postgres-meta`, `src/lib/db.ts`) | `pool.query(sql)` sem parâmetros → protocolo simples, **uma mensagem `Query`, uma conexão**; pode prefixar `SET statement_timeout…; SET idle_session_timeout…;` na mesma mensagem; erro de banco devolvido como `formattedError` (severidade, SQLSTATE, mensagem, DETAIL, HINT, CONTEXT) | multi-statement em ordem, na mesma sessão |
| node-postgres `pg-pool` (`_release`) | `client.release(err)` com erro → `_remove` → `client.end()` | **a conexão é fechada depois de qualquer erro**; não volta ao pool em estado abortado |
| PostgreSQL 17 (`exec_simple_query`, docs do protocolo 53.2.2.1) | a mensagem inteira é analisada antes de executar; um BEGIN converte retroativamente o bloco implícito em explícito; erro descarta o resto da mensagem; `statement_timeout` vale por comando (PG ≥ 13) | erro de gramática ⇒ **nada executa**; T0 e o prefixo do pg-meta ficam dentro da transação e são desfeitos |
| Dashboard SQL Editor | usa o mesmo caminho pg-meta (arquitetura pública do Studio); código do editor **não inspecionado** | contrato igual + riscos de operação manual (28.4) |

### 28.2 Respostas aos 10 pontos

1. Arquivo inteiro numa chamada: sim (70.619 bytes, um texto).
2. Mesma conexão: sim — uma mensagem `Query` numa conexão do pool.
3. BEGIN / SET TRANSACTION / erro / ROLLBACK: semântica do protocolo simples; o erro P0001 de T9 aborta, T10/T11 não executam, a conexão é fechada pelo pool.
4. Transação externa implícita: só o bloco implícito do protocolo, convertido pelo BEGIN do T1; nenhum `BEGIN…COMMIT` adicionado nas camadas inspecionadas (a Management API não é inspecionável).
5. DDL e DO: suportados (protocolo simples, sem parâmetros).
6. Ordem: sequencial, na ordem do texto.
7. Evidência do erro: o pg-meta monta o texto completo; se a API/MCP o repassa **sem cortes** não está documentado → a sonda 28.5 decide.
8. Transação após erro: abortada no servidor (locks e `SET LOCAL` liberados no aborto) e conexão encerrada.
9. SQL Editor × `execute_sql`: mesmo motor; diferem em quem transmite o texto, como a evidência é capturada e nos riscos manuais.
10. Proteções da v2.1: nenhuma é invalidada. T0 fica redundante (o aborto e o fechamento da conexão já o desfazem), mas inofensivo; P.11/Q.09 (`mmkyu_dryrun_s1_e2`) passam a ser não discriminantes — Q.03 continua cobrindo sessão residual pelo texto `MSDRYRUN`/`mmkyu_dryrun`.

### 28.3 Compatibilidade com a v2.1 — **sem alterar SQL**

Compatível tal como está (SHA `ddd0dbf2…f74b`). A segurança não depende do cliente: T4 (veto por FK adiada), T9 (exceção sempre) e o aborto estão **no servidor, na mesma mensagem** — mesmo que o cliente caia, o servidor termina a mensagem e desfaz. Persistência só seria possível se o executor dividisse os comandos entre conexões diferentes; isso é contrariado pelo código do pg-meta e pela leitura anterior (`statement_timestamp()` comum aos comandos e 316 ms decorridos desde a mensagem).

**Fidelidade do texto (não é segurança, é validade da prova):** nenhum dos dois caminhos confere o SHA no servidor. `execute_sql` exigiria que o agente reproduzisse 70.619 bytes (1.902 não ASCII) num argumento — não verificável, **não recomendado para o ensaio**. Proposta separada, **não aplicada** (exigiria nova versão v2.2 e nova auditoria): T6 conferir `md5` do trecho de `current_query()` após um marcador contra a constante gerada pelo builder.

### 28.4 Riscos operacionais

| Risco | Classificação | Controle |
|---|---|---|
| COMMIT parcial | não plausível no contrato inspecionado | G-POST Q.01/Q.02/Q.08 objetivos |
| Erro de sintaxe | nada executa (análise da mensagem inteira) | STOP, não repetir |
| Timeout / interrupção HTTP | servidor conclui a mensagem e desfaz; evidência pode se perder | G-POST decide; sem reexecução automática |
| Lock em `auth.users` | SHARE ROW EXCLUSIVE da FK da 5267 até o aborto em T9 (esperado < 5 s; teto `transaction_timeout` 60 s); bloqueia escrita (login/cadastro), não leitura/JWT | janela sem uso planejado (atestada por Fabrício) + G-PRE P.04–P.08 |
| Sessão residual abortada | o pool fecha a conexão em erro | G-POST Q.03; encerrar sessão exige autorização à parte |
| Configuração persistente | T0 e prefixo do pg-meta desfeitos no aborto; conexão fechada | G-POST Q.06 |
| Texto truncado/alterado no envio | validade da prova | copiar do arquivo conferido (28.6 passo 4); SHA no cliente |
| Execução de seleção parcial no SQL Editor | ensaio incompleto (seguro, inválido) | nenhum texto selecionado ao executar |
| Papel diferente de `postgres` no seletor do editor | precheck T6 falha → aborto | conferir seletor = `postgres` |
| Aviso de operação destrutiva do editor/MCP | interrupção, não risco | confirmar só se o texto for o conferido |
| Snippet salvo no Dashboard | resíduo fora do banco | pode ser mantido como evidência ou apagado |
| Uso de `apply_migration` | **gravaria no ledger** | proibido para o ensaio |

### 28.5 Sonda somente leitura (`DASH_probe_readonly.sql` v1.0 — proposta, não executada)

SHA-256 `166581ed779a669236c44c489b9543ee085cd4c2519037105a3744a6c0418826`. Mesmo formato do ensaio, transação READ ONLY, sem escrita (10 comandos conferidos com `sql_lexer_p3b`). Bloco A → erro P0001 `MSPROBE {json}` com DETAIL/HINT/CONTEXT, `mesma_mensagem=true`, `elapsed_ms ≥ 200`, `transacao_somente_leitura=on`, `usuario=postgres`, acentos intactos. Bloco B (outra execução) → `pid_a` ausente de `client_pids`, `idle_in_transaction=0`, `sessoes_com_msprobe=0`, `default_read_only=off`. Rodar no SQL Editor (Fabrício) e, se autorizado, também por `execute_sql` (texto curto, fiel), para comparar a evidência devolvida.

### 28.6 Protocolo no dia da autorização

1. Hashes dos artefatos congelados, `build_live_dryrun_s1.py --check`, `static_check_p3b_s1.py` 47/47.
2. Sonda 28.5 aprovada em todos os itens (pré-requisito; não dispara o ensaio).
3. Agente, `execute_sql` só SELECT, conexões independentes: LIVE_00 (6 true), G-PRE P.01–P.10 true, P.12 registrado, P.10 guardado. Fabrício atesta a janela sem uso do app.
4. Fabrício, PowerShell: `$p='<caminho>\LIVE_DRYRUN_S1_rollback.sql'; (Get-FileHash $p -Algorithm SHA256).Hash; Get-Content -LiteralPath $p -Raw -Encoding UTF8 | Set-Clipboard` → hash deve ser `DDD0DBF2…F74B`.
5. SQL Editor: nova aba vazia, seletor de papel `postgres`, colar, **nenhuma seleção**, executar **uma vez**.
6. Registrar o painel de erro completo (texto e captura). Válido somente se: um erro, SQLSTATE P0001, `MSDRYRUN {json}` com todas as chaves de §27.3 presentes e `true`, legado 1/1, `duration_ms` ≤ 5000. Válido ≠ PASS.
7. Agente, imediatamente: G-POST Q.01–Q.08 true, Q.08 = P.10, LIVE_00 6 true. Só então PASS do ensaio.

### 28.7 Critérios de STOP

Qualquer item da sonda divergente; qualquer false em LIVE_00/G-PRE/G-POST; hash divergente; executor devolve sucesso (sem erro); SQLSTATE ≠ P0001 ou mensagem sem `MSDRYRUN`; JSON truncado/ilegível ou com `false`; timeout/queda sem resposta; sessão residual (Q.03) ou lock remanescente (Q.04/Q.05); qualquer sugestão de usar `apply_migration`. Em todo STOP: não repetir, registrar, rodar G-POST e LIVE_00.

### 28.8 Diferenças em relação ao E2

| Aspecto | E2 (psql) | Mensagem única |
|---|---|---|
| Credencial | senha do banco | acesso já existente (Dashboard/token do MCP) |
| Envio | comando a comando | texto inteiro numa mensagem |
| Erro de sintaxe | executa até o erro | nada executa |
| Fim da sessão | psql sai | pool fecha a conexão em erro |
| Classificação | código de saída + stderr | painel de erro / mensagem do MCP (completude a provar pela sonda) |
| Identificação da sessão | `application_name` próprio | não controlável (P.11/Q.09 não discriminam) |
| Conferência do arquivo | SHA no cliente antes do envio | SHA no cliente + área de transferência; sem prova no servidor |

### 28.9 Classificação

**GO CONDICIONAL** para pedir a autorização operacional do ensaio pelo **Dashboard SQL Editor** (executado por Fabrício), com as leituras de LIVE_00/G-PRE/G-POST pelo agente via `execute_sql`. Condições: sonda 28.5 aprovada (exige autorização própria), janela atestada, protocolo 28.6 e STOP 28.7. Se a sonda não for autorizada ou divergir em qualquer item → **NO-GO**. `execute_sql` como transmissor do ensaio: **NO-GO** (fidelidade do texto não verificável) enquanto não houver a conferência de hash proposta em 28.3.

### 28.10 Auditoria estática da sonda (`P3-B-S1-DASHBOARD-PROBE-STATIC-AUDIT`, 2026-10-25)

Sonda inalterada (SHA `166581ed…8826`). Parecer de segurança: **PASS** — nenhum comando grava dados, esquema, privilégios ou configuração persistente do servidor; a proteção vem primeiro do conteúdo (só SET, BEGIN/ROLLBACK, SELECT de funções sem efeito colateral e DO que só levanta exceção), depois da transação READ ONLY e do aborto. Rastros fora do banco de dados: log de erro do servidor, estatísticas (`pg_stat_statements`) e o snippet do Dashboard. Resíduo possível só se o editor dividir comandos entre mensagens: `default_transaction_read_only = on` na sessão do pool do Dashboard (efeito restrito à conexão, sem dados) — detectado por `pid_b = pid_a` ou `default_read_only = on` no bloco B → STOP.

O que a sonda prova **somente para o executor em que rodar**: texto do erro devolvido (SQLSTATE, mensagem, DETAIL, HINT, CONTEXT), comandos na mesma mensagem e transação, UTF-8, papel `postgres`, conexão descartada após erro. O que **não** prova: atomicidade de DDL/escrita, veto por FK adiada, locks em `auth.users`, duração, envio de 70.619 bytes sem corte, mensagem `MSDRYRUN` longa, comportamento em timeout HTTP, fidelidade do texto colado, estabilidade futura do editor. Resultado inconclusivo (resposta perdida, bloco B não executado, `pid_a` presente) = STOP com verificação independente. Sucesso da sonda **não** é GO do ensaio. Artefatos congelados conferidos por SHA, inalterados; `static_check` 47/47; builder EM DIA.

### 28.11 Resultado da sonda no LIVE (`P3-B-S1-DASHBOARD-PROBE-CLOSEOUT`, 2026-10-25) — **PASS**

Executada manualmente por Fabrício no Supabase Dashboard SQL Editor (LIVE), arquivo SHA-256 `166581ED…8826` (conferido). Evidências **relatadas pelo proprietário** (o agente não executou nem observou; capturas não anexadas ao repositório):

| Bloco | Critério (§28.10) | Obtido | Situação |
|---|---|---|---|
| A | um erro, SQLSTATE P0001 | P0001 | ✔ |
| A | `MSPROBE {json}` completo | recebido integralmente | ✔ |
| A | DETAIL, HINT, CONTEXT | presentes | ✔ |
| A | `usuario = postgres` | `postgres` | ✔ |
| A | `transacao_somente_leitura = on` | `on` | ✔ |
| A | `mesma_mensagem = true` | `true` | ✔ |
| A | `elapsed_ms ≥ 200` | 220 | ✔ |
| A | acentos exatos | preservados | ✔ |
| A | `application_name` (informativo) | `supabase/dashboard-query-editor` | registrado |
| B | `pid_b ≠ pid_a`; `pid_a` fora de `client_pids` | 2487365 ≠ 2487333; ausente | ✔ |
| B | `default_read_only = off` | `off` | ✔ |
| B | `idle_in_transaction = 0`, `sessoes_com_msprobe = 0` | 0 / 0 | ✔ |

**Demonstrado para o SQL Editor:** texto inteiro numa mensagem e numa transação; BEGIN/READ ONLY/SET LOCAL efetivos; exceção P0001 devolvida com DETAIL/HINT/CONTEXT; UTF-8 preservado; papel `postgres`; conexão descartada após o erro, sem sessão residual nem configuração persistente.
**Continua não demonstrado:** envio de 70.619 bytes sem corte; `MSDRYRUN` longa exibida inteira; atomicidade de DDL e veto por FK adiada; locks e duração em `auth.users`; comportamento em timeout HTTP; fidelidade do texto colado.

### 28.12 Gate de homologação do executor

| Item | Situação |
|---|---|
| E1 `execute_sql` como transmissor do ensaio | **NO-GO** (fidelidade de 70 KB não verificável) — mantido só para leituras SELECT |
| E2 psql | **SUSPENSO** (sem credencial; redefinição não autorizada) |
| **E3 Dashboard SQL Editor** | **HOMOLOGADO PARA O FORMATO DA v2.1 (contrato de mensagem única demonstrado pela sonda)**, com as condições de 28.13 |
| G5b / G5c / G8 | inalterados: FECHADOS. O ensaio não abre G8 |

Condições operacionais ainda necessárias antes do ensaio:
1. **Autorização específica do ensaio** por Fabrício (identificador), distinta da sonda e de G8.
2. **Janela sem uso planejado do app** atestada por Fabrício (o lock SHARE ROW EXCLUSIVE em `auth.users` bloqueia login/cadastro até o aborto; teto 60 s).
3. Hashes e verificações estáticas reconfirmados no dia (28.13 passo 1).
4. LIVE_00 6/6 e G-PRE P.01–P.10 true imediatamente antes; P.10 guardado.
5. Texto transferido do arquivo conferido para a área de transferência pelo próprio PowerShell (hash e cópia no mesmo comando) — controle da lacuna de fidelidade.
6. Captura integral do painel de erro (texto copiado + imagem), para validar o JSON contra a lista de chaves.
7. Plano de espera para resposta ausente/sucesso inesperado (90 s antes do G-POST — cobre `transaction_timeout` 60 s e `idle_in_transaction_session_timeout` 15 s caso o texto chegue truncado num limite de comando).
8. Nenhuma ação corretiva (ex.: encerrar sessão) sem nova autorização.

Observação: `application_name = supabase/dashboard-query-editor` permitiria checagem dirigida da sessão do editor; P.11/Q.09 continuam com o nome do E2 (não discriminantes). Alterar o gate exigiria v1.2 e nova auditoria — **não aplicado**; Q.03/Q.04/Q.05 cobrem sessão e locks residuais.

### 28.13 Procedimento de execução manual (E3) — SQL congelado, sem alteração

> **Vigente para o ensaio v2.3** (`LIVE_DRYRUN_S1_rollback_v2.3.sql`, SHA `b537e943…a262`), com `LIVE_00_precheck_readonly_v1.1.sql` e `LIVE_DRYRUN_S1_gate_readonly_v1.2.sql`, desde 2026-10-27 (baseline do ledger = `20261026124224 fix_mep_bootstrap_preserve_confirmed_primary_identity`, §28.29). Históricos, **não usar**: v2.1 (executada, não aprovada, rollback comprovado — §28.20), v2.2 (preparada, nunca executada — baseline 5266 superado), LIVE_00 v1.0 e gate v1.1 (baseline 5266).

Papéis: **F** = Fabrício (Dashboard e PowerShell); **A** = agente (`execute_sql`, só SELECT dos arquivos aprovados). Nenhum passo dispara o seguinte automaticamente.

1. **A — estático:** SHA-256 de 5267–5270, 5860, R0, LIVE_00, LIVE_90, gate v1.1, **ensaio v2.3**, LIVE_00 v1.1, gate v1.2, v2.1/v2.2 e LIVE_00 v1.0/gate v1.1 (históricos, intactos), builder, static_check, lexer = tabela consolidada da §28.14 (a §26 traz o hash do gate v1.0, superado); `build_live_dryrun_s1.py --check` → `LIVE_DRYRUN_S1_rollback_v2.3.sql EM DIA`; `static_check_p3b_s1.py` **65/65**. Divergência → STOP.
2. **F — atesta** a janela sem uso do app e informa o identificador da autorização.
3. **A — pré-checagem LIVE** (imediatamente antes): `LIVE_00_precheck_readonly_v1.1.sql` → 00.1–00.6 true; bloco G-PRE de `LIVE_DRYRUN_S1_gate_readonly_v1.2.sql` → P.01–P.11 true (P.11 não discriminante no E3); registrar P.10 e P.12. Qualquer false → STOP.
4. **F — PowerShell**, na pasta da proposta (valida o SHA do arquivo **antes** de copiar; lê os bytes como UTF-8 estrito; copia; relê a área de transferência e exige o **mesmo SHA-256**; em divergência limpa a área de transferência e para):
   ```powershell
   $p = '.\LIVE_DRYRUN_S1_rollback_v2.3.sql'
   $esperado = 'B537E943A5B92748440D48DF0EF58996068A5540731623B7ECBC366CD6E9A262'
   $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
   if ($h -ne $esperado) { throw "STOP: SHA do arquivo divergente: $h" }
   $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $p).ProviderPath)
   $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
   $texto = $utf8.GetString($bytes)
   Set-Clipboard -Value $texto
   $volta = Get-Clipboard -Raw
   $sha = [System.Security.Cryptography.SHA256]::Create()
   $hc = -join ($sha.ComputeHash($utf8.GetBytes($volta)) | ForEach-Object { $_.ToString('X2') })
   if ($hc -ne $esperado) { Set-Clipboard -Value ' '; throw "STOP: area de transferencia difere do arquivo (SHA $hc)" }
   "OK: arquivo e area de transferencia identicos - $h ($($bytes.Length) bytes)"
   ```
   Esperado: `OK: … B537E943… (71552 bytes)`. Qualquer `STOP:` → não colar, não executar.
5. **F — SQL Editor:** nova aba vazia; seletor de papel `postgres`; colar (Ctrl+V); clicar no fim do texto (**nenhuma seleção**); se houver aviso de operação destrutiva, confirmar apenas se a aba contém só o texto colado; **Run uma única vez**. Anotar horário (UTC).
6. **F — capturar** o painel inteiro (copiar texto + imagem). Não reexecutar em nenhum caso.
7. **Classificação (A, sobre o texto de F):** SENTINELA VÁLIDA somente se: exatamente um erro; SQLSTATE `P0001`; mensagem `MSDRYRUN {json}` legível e completa; presentes e `true` todos os booleanos e presentes as chaves `ok, precheck, txid, 90.2…90.12, probe_anon_42501, probe_no_session_zero_rows, probe_update_immutable, probe_delete_immutable, probe_truncate_immutable, legacy_events, legacy_items, role_restored, duration_ms`; `legacy_events = 1` e `legacy_items = 1`; `duration_ms ≤ 5000`. Sentinela válida **não** é PASS.
8. **A — pós-checagem** (logo após o passo 6; se o passo 6 não trouxe erro ou não trouxe resposta, esperar **90 s** antes): bloco G-POST → Q.01–Q.09 true (Q.09 não discriminante no E3) e Q.08 = P.10; `LIVE_00` → 6/6 true.
9. **PASS do ensaio** somente com 7 e 8 integralmente atendidos. Registrar em README/log (A) com as evidências.

**STOP** (não repetir; executar o passo 8 se o ensaio tiver sido enviado; registrar tudo): hash divergente do arquivo ou da área de transferência; uso de arquivo histórico (v2.1, v2.2, LIVE_00 v1.0, gate v1.1); qualquer false em LIVE_00/G-PRE/G-POST; editor sem erro ou sem resposta; mais de um erro; SQLSTATE ≠ P0001 (ex.: 42601 sintaxe, 55P03 lock, 57014 timeout, 25P04 transação); mensagem sem `MSDRYRUN`, truncada ou com `false`; `duration_ms > 5000`; Q.03/Q.04/Q.05 indicando sessão ou lock residual (sem encerrar nada sem autorização); qualquer uso de `apply_migration`.

### 28.14 Preparação operacional E3 (`P3B-S1-E3-LIVE-DRYRUN-V21-01`, 2026-10-25) — sem execução

Identificador reservado por Fabrício: **`P3B-S1-E3-LIVE-DRYRUN-V21-01`** (autoriza só a preparação; não autoriza LIVE_00, G-PRE nem o ensaio).

Hashes consolidados (SHA-256 integral; atualizados para a v2.3 e o baseline MEP em 2026-10-27 — §28.29; referência única para o passo 1 de §28.13):

| Artefato | SHA-256 |
|---|---|
| `5267_create_binder_activity_structures.sql` | `e8e69f4c5020656ea3778872f8c45b02319bc2f97dcaec4e5f49c37a845b69dc` |
| `5268_create_binder_activity_recording_functions.sql` (v1.2) | `76e2bac4de3dffed83b6010a8b50c9c7888cb5d2cf39683c229b5313c947c6db` |
| `5269_create_binder_activity_reads.sql` | `98d83f701c9d3b1d45bf2d21900cca5066854648ef2947aa52cded2053b3e435` |
| `5270_create_binder_activity_purge_and_legacy.sql` | `53dc5fd526315b56445337b39e336770bdefe904e6e3e866bb5c5f4799458c9d` |
| **`LIVE_DRYRUN_S1_rollback_v2.3.sql` (v2.3 — único arquivo do ensaio; baseline MEP)** | `b537e943a5b92748440d48df0ef58996068a5540731623b7ecbc366cd6e9a262` |
| **`LIVE_00_precheck_readonly_v1.1.sql` (vigente)** | `fbab814eaa849fd125b1f69f813a5f8914ac5ca4a919f8646f1ae772c71b9f5e` |
| **`LIVE_DRYRUN_S1_gate_readonly_v1.2.sql` (vigente)** | `8dcc285ae38a0c5fe7613ba9b9f4d8ffb504093826f5ce86e87f6a38306c34dc` |
| `LIVE_DRYRUN_S1_rollback_v2.2.sql` (v2.2 — histórico: nunca executada; baseline 5266 superado; não usar) | `ece95392c0af14e35f690f544d8a3e524561d93a31f9c656a0653413c4757e40` |
| `LIVE_DRYRUN_S1_rollback.sql` (v2.1 — histórico: executada, não aprovada, rollback PASS; não usar) | `ddd0dbf2ef5346f5c3536d8b2d1d62ee3eab1cbc5ecc9d732d9a598e1322f74b` |
| `5860_validate_binder_activity_foundation.sql` (v1.2, não executar) | `38d095db6e567cf5f316ce395c2ddd4f7ff1be3597c86f783b03e872166e9532` |
| `R0_rollback_s1.sql` (v1.1) | `206b3077fe90d778f20278dfcf73fb556a6c0015bfcf287ea6d914dd6fcb6da8` |
| `LIVE_00_precheck_readonly.sql` (v1.0 — histórico, baseline 5266; não usar) | `3868c4e42728dc16566649f18f799037085f3655ce1e26cc9a0579f91c3d2d7b` |
| `LIVE_90_postcheck_readonly.sql` | `8b0dacd70965b5f26b367af9f09254b44fa35f2acfa2ff58fba38dc29fda4e4d` |
| `LIVE_DRYRUN_S1_gate_readonly.sql` (v1.1 — histórico, baseline 5266; não usar) | `bc40ac84c88cee4cf3d18d111e765f560a259c12bbfdeedfb393d5c71e3199a5` |
| `DASH_probe_readonly.sql` (v1.0, executada — PASS) | `166581ed779a669236c44c489b9543ee085cd4c2519037105a3744a6c0418826` |
| `build_live_dryrun_s1.py` (v2.3) | `c4264eb7af05fafc66466e2fff385b5144630d4accf4be7f4e1dc30d359b8ba6` |
| `static_check_p3b_s1.py` (65 checagens) | `215179c4021853480f9c294120d3251e66f9d595537315aa721e4e8a4332e351` |
| `CATALOG_R1R3_readonly_v1.1.sql` (executada — PASS) | `95b0fc44a897b302340d710b041aa78bc5cdaa321b3dbf598cc4e705feb2f020` |
| `sql_lexer_p3b.py` | `e1c25043bfcc9281d5536be6d88cc039e49155a245d6e7538f2aad063881e5bc` |

Verificações: `build_live_dryrun_s1.py --check` → EM DIA (saída 0); `static_check_p3b_s1.py` → 47/47 PASS. Instrumentos: LIVE_00 (1 SELECT, itens 00.1–00.6) e gate v1.1 (2 SELECT: G-PRE P.01–P.12, G-POST Q.01–Q.09) presentes e só leitura (lexer). Inconsistências documentais encontradas e corrigidas nesta seção e em §28.13: hash do gate na §26 era o da v1.0; P.11/Q.09 não estavam explícitos no procedimento. Nenhum artefato congelado alterado.

### 28.15 Pré-check LIVE (`P3B-S1-E3-LIVE-DRYRUN-V21-01 / PRECHECK`, 2026-10-26 ~01:02 UTC) — **PASS**

Autorização específica de Fabrício para LIVE_00 e G-PRE. SHA-256 reconferidos antes: LIVE_00 `3868c4e4…2d7b`, gate v1.1 `bc40ac84…99a5`. Executados pelo agente via `execute_sql` (projeto `qjfutqujxrbzgrtkpgkg`), duas chamadas, só SELECT, texto dos comandos copiado dos arquivos aprovados (do LIVE_00 omitido apenas o bloco de comentário do cabeçalho; G-PRE enviado com seu comentário de abertura). Ensaio, G-POST, migrations e harness **não** executados.

LIVE_00: 00.1 `20261025145504` true · 00.2 true · 00.3 true · 00.4 `incorporações legadas = 1` true · 00.5 true · 00.6 true → **6/6**.

G-PRE: P.01 `off` true · P.02 `origin` true · P.03 `|` true · P.04 `0` true · P.05 `0` true · P.06 `0` true · P.07 `0` true · P.08 `0` true · P.09 `-` true · P.11 `0` true (não discriminante no E3) · P.12 informativo `auth.users 2026-10-26 00:11:50.887974+00 | sessões: 2026-10-26 00:11:50.92113+00`.

**P.10 — linha de base para Q.08 (preservada literalmente):**
`{"card": 21246, "card_set": 201, "auth_users": 3, "collection": 10, "ledger_last": "5266_create_binder_catalog_reconciliation_apply", "ledger_count": 534, "incorporation": 1, "public_functions": 423, "public_relations": 488, "card_variant_type": 97, "collection_layout": 3, "collection_layout_page": 146, "collection_layout_slot": 1776}` — idêntica à leitura de 2026-10-25 ~20:45 UTC.

Observação P.12: houve atividade de autenticação ~50 min antes do pré-check (00:11:50 UTC; login/refresh). Não reprova o gate (informativo), mas reforça que a janela sem uso do app precisa ser atestada por Fabrício antes do ensaio. O pré-check vale para o instante da leitura: se o ensaio não ocorrer logo em seguida, LIVE_00 e G-PRE devem ser repetidos (nova autorização de leitura).

### 28.16 Renovação do pré-check para o ensaio (`P3B-S1-E3-LIVE-DRYRUN-V21-01 — EXECUTION GATE`, 2026-10-26 ~01:20 UTC) — **STOP**

Autorização específica do ensaio condicionada à renovação dos pré-checks. Etapa 1 executada; **ensaio não executado**.

- Hashes integrais: 14/14 conferem com §28.14. `build_live_dryrun_s1.py --check` EM DIA; `static_check_p3b_s1.py` 47/47.
- LIVE_00 (execute_sql, só SELECT, texto do arquivo aprovado): 00.1 `20261025145504` · 00.2–00.6 → **6/6 true**.
- G-PRE (idem): P.01 `off` ✔ · P.02 `origin` ✔ · P.03 `|` ✔ · **P.04 `2` — false** · P.05 `0` ✔ · P.06 `0` ✔ · P.07 `0` ✔ · P.08 `0` ✔ · P.09 ✔ · P.10 ✔ · P.11 `0` ✔ · P.12 informativo `auth.users 2026-10-26 01:19:16.302111+00 | sessões: 2026-10-26 01:19:16.231433+00`.
- P.10 desta leitura (preservado; idêntico ao de §28.15): `{"card": 21246, "card_set": 201, "auth_users": 3, "collection": 10, "ledger_last": "5266_create_binder_catalog_reconciliation_apply", "ledger_count": 534, "incorporation": 1, "public_functions": 423, "public_relations": 488, "card_variant_type": 97, "collection_layout": 3, "collection_layout_page": 146, "collection_layout_slot": 1776}`.

**Resultado: STOP** — P.04 false (duas outras sessões cliente não ociosas no instante da leitura) e P.12 com autenticação ~30 s antes da leitura, indicando uso do app. Etapa 2 (gate operacional) não iniciada. Nenhuma consulta diagnóstica adicional (fora dos instrumentos aprovados) foi executada; nenhuma ação corretiva. Retomar exige: janela sem uso confirmada por Fabrício e nova renovação de LIVE_00 + G-PRE com P.04 true.

### 28.17 Diagnóstico de sessões (`P3-B S1 SESSION DIAGNOSTIC READONLY`, 2026-10-26) — proposto, não executado

`DIAG_sessions_readonly.sql` v1.0, SHA-256 `b5b688f0abb9c397764f267de78543683faced38a2d5e5ece019bb8df7e54377`. Um SELECT sobre `pg_stat_activity` (lexer: 1 comando, nenhuma palavra de escrita/controle; não lê `query`, `client_addr`, `client_hostname`, `client_port` nem tabela de dados). Uma linha por sessão `client backend` com papel, `application_name`, estado, evento de espera e idades (sessão, transação, comando, mudança de estado); `e_o_proprio_diagnostico` marca a própria conexão.

Fidelidade ao P.04: `conta_no_p04` e `total_p04` usam o predicado do gate v1.1 sem alteração (`pid <> pg_backend_pid() and backend_type = 'client backend' and state is not null and state <> 'idle'`), igualdade textual conferida por script contra o arquivo do gate (inalterado, `bc40ac84…99a5`); o filtro da CTE (`backend_type = 'client backend'`) contém toda a população do P.04. Todas as linhas vêm do mesmo snapshot. Limite: reproduz o filtro, não a população histórica de ~01:20 UTC — sessões curtas podem já ter terminado.

Interpretação: (a) `total_p04 = 0` → condição transitória; renovar LIVE_00/G-PRE; (b) sessões de `authenticator`/PostgREST, Auth ou Storage com comando recente → tráfego do app: estabelecer a janela; (c) `supabase/dashboard-*` → abas do Dashboard de Fabrício executando algo: aguardar ou fechar; (d) sessão de infraestrutura persistentemente não ociosa (ex.: `active` com `desde_inicio_do_comando` longo, `wait_event` de LISTEN/replicação) → P.04 pode ser estruturalmente falso: reportar; qualquer ajuste do gate exige v1.2 e nova auditoria; (e) papel ou aplicação desconhecidos → STOP e decisão de Fabrício. Nenhum encerramento de sessão sem autorização.

### 28.18 Resultado do diagnóstico de sessões (`P3B-S1-E3-SESSION-DIAGNOSTIC-01`, 2026-10-26 01:45:21 UTC)

Autorização específica de Fabrício. SHA-256 conferido (`b5b688f0…4377`); consulta executada uma vez, exatamente como aprovada, via `execute_sql`. Nenhuma outra consulta, encerramento ou ajuste.

`total_clientes = 20`; **`total_p04 = 4`**:

| PID | Papel | application_name | Estado | Sessão | Transação | Comando |
|---|---|---|---|---|---|---|
| 2819351 | supabase_admin | postgres_exporter | active | 34 d 23:51 | 0 s | 0 s |
| 2492197 | authenticator | PostgREST 14.5 | active | 15 s | 1 s | 0 s |
| 2492207 | supabase_storage_admin | Supabase Storage API | active | 0 s | 0 s | 0 s |
| 2492208 | supabase_storage_admin | Supabase Storage API | active | 0 s | 0 s | 0 s |

Fora do P.04: o próprio diagnóstico (2492204, `mgmt-api`, postgres); 10 sessões PostgREST ociosas criadas há 15–18 s; 1 PostgREST ociosa há 34 dias (conexão de longa duração); 2 `supabase_auth_admin` ociosas criadas há 2 s; 2 `pgbouncer` ociosas criadas há 0 s; 1 `supabase_admin` ociosa há 18 h (sessão de 34 dias). Nenhum `wait_event` nas sessões ativas; nenhuma sessão do Dashboard (`supabase/dashboard-*`).

Classificação: **transitória, atribuível a tráfego de serviços da API** (PostgREST, Storage, Auth — rajada de conexões novas em ~20 s, padrão de uso do app ou de cliente conectado ao LIVE) **mais monitoramento intermitente** (`postgres_exporter`, coleta periódica de métricas, sessão permanente que fica `active` só durante cada coleta). Não atribuível ao Dashboard. Origem exata do tráfego da API: indeterminada (sem texto de consulta nem endereço, por escopo). A contagem variou entre leituras (0 às 01:02, 2 às 01:20, 4 às 01:45), o que reforça o caráter transitório.

Recomendação para retomar sem alterar o gate: (1) Fabrício encerra todo uso do app no LIVE — abas logadas, outros dispositivos e qualquer servidor de desenvolvimento local apontado para o LIVE — e aguarda ≥ 5 min; (2) nova autorização de leitura e renovação de LIVE_00 + G-PRE; aceitar somente P.04 = true; P.12 deve mostrar a última autenticação anterior ao início da janela; (3) se P.04 falhar de novo apenas por `postgres_exporter`, não repetir indefinidamente: registrar como falso positivo estrutural intermitente e decidir entre nova leitura pré-acordada (número fixo) ou gate v1.2 com exclusão auditada — decisão de Fabrício.

### 28.19 Retomada controlada do pré-check (`P3B-S1-E3-LIVE-DRYRUN-V21-01`, 2026-10-26 ~02:08 UTC) — **PASS**

Fabrício confirmou o encerramento de todas as janelas do app. Leitura feita após espera ≥ 5 min contada a partir da instrução (que já sucedia o encerramento). SHA-256 de LIVE_00 (`3868c4e4…2d7b`) e gate v1.1 (`bc40ac84…99a5`) conferidos; demais artefatos congelados 14/14 OK. Uma execução de cada instrumento via `execute_sql`, só SELECT, texto dos arquivos aprovados.

LIVE_00: 00.1 `20261025145504` · 00.2–00.6 → **6/6 true**.
G-PRE: P.01 `off` · P.02 `origin` · P.03 `|` · **P.04 `0`** · P.05 `0` · P.06 `0` · P.07 `0` · P.08 `0` · P.09 `-` · P.10 ✔ · P.11 `0` → **todos true**. P.12 informativo: `auth.users 2026-10-26 01:19:16.302111+00 | sessões: -` (nenhuma sessão de autenticação registrada — coerente com o encerramento/logout; última atividade ~49 min antes).

P.10 — linha de base vigente para Q.08 (preservada literalmente; idêntica às leituras anteriores):
`{"card": 21246, "card_set": 201, "auth_users": 3, "collection": 10, "ledger_last": "5266_create_binder_catalog_reconciliation_apply", "ledger_count": 534, "incorporation": 1, "public_functions": 423, "public_relations": 488, "card_variant_type": 97, "collection_layout": 3, "collection_layout_page": 146, "collection_layout_slot": 1776}`

Interrompido antes da execução manual. O pré-check vale para o instante da leitura; a janela precisa permanecer sem uso até o ensaio e o G-POST.

### 28.20 Execução manual do ensaio v2.1 e pós-check (`P3B-S1-E3-LIVE-DRYRUN-V21-01`, 2026-10-26) — **ENSAIO NÃO APROVADO; ROLLBACK PASS**

**Execução (relato de Fabrício):** uma única execução no SQL Editor. Resposta: SQLSTATE `P0001`, mensagem `DRYRUN POSTCHECK FALHOU {json}` (ramo de `ok = false` do T9). Texto do JSON recebido sem os valores booleanos; valores numéricos: `txid` 654781, `duration_ms` 339, `legacy_events` 1, `legacy_items` 1. Decisão de Fabrício: STOP, ensaio não aprovado. Não reexecutado.

**Pós-check (agente, `execute_sql`, só SELECT dos arquivos aprovados):** G-POST Q.01 ✔ · Q.02 `534 | 5266_…` ✔ · Q.03 `0` ✔ · Q.04 `0` ✔ · Q.05 `0` ✔ · Q.06 `off` ✔ · Q.07 `1` ✔ · Q.08 = P.10 de §28.19 (idêntico campo a campo) ✔ · Q.09 `0` ✔. LIVE_00 6/6 true. → **Rollback efetivo: nenhum objeto `binder_activity_*`, ledger inalterado, contagens iguais à linha de base, nenhuma sessão residual, nenhum lock em `auth.users` nem aguardando.**

**Diagnóstico estático (artefatos congelados, sem consulta adicional):** as migrations criam **10** funções; 9 contêm `binder_activity` no nome e 1 não — `list_my_closed_binder_histories` (5269). O T8a do ensaio (gerado pelo builder) substituiu a lista explícita de nomes do LIVE_90 (`fns`, 10 nomes) pelo padrão `p.proname like '%binder_activity%'`. Consequências determinísticas:
- **90.3** (`count(*) = 10 and bool_and(search_path vazio e SECURITY DEFINER exceto binder_activity_category)`): o padrão encontra 9 funções → `count(*) = 10` falso → **90.3 = false**, independentemente das propriedades das funções.
- **90.10** (nenhuma função *fora* do conjunto referencia `binder_activity_`): `list_my_closed_binder_histories` fica fora do conjunto pelo nome e referencia as tabelas do histórico → **90.10 = false**.
- 90.4 não falha, mas deixa de cobrir `list_my_closed_binder_histories` (cobertura menor que a do LIVE_90).
O LIVE_90 (lista explícita; 90.10 exclui por `oid`) não tem o defeito. É falha do instrumento do ensaio, não das migrations; nenhum outro item é previsto como false pela inspeção. Confirmação de quais chaves vieram false depende do texto bruto da resposta (pendente).

**Separação:** (1) falha interna do ensaio — predicado de T8a (90.3/90.10) inconsistente com o conjunto de funções; (2) evidência de rollback — G-POST 9/9 e LIVE_00 6/6; (3) inconsistências persistentes — nenhuma detectada. Evidência positiva incidental: a resposta veio do T9 (todas as etapas T0–T8 executadas sem erro, legado 1/1, 339 ms), mas sem a sentinela válida isso **não** conta como PASS. Correção (v2.2 do builder/ensaio alinhando T8a ao LIVE_90 e checagem estática cruzada T8a × LIVE_90) exige rodada própria e nova auditoria; nada alterado nesta rodada.

### 28.21 Ensaio v2.2 — correção dirigida do T8a (`P3-B S1 E3 DRY-RUN v2.2`, 2026-10-26) — preparado, não executado

**Causa-raiz (comprovada estaticamente; JSON bruto da v2.1 com `"90.3": false` e `"90.10": false`):** as migrations criam 10 funções; o LIVE_90 as identifica por lista explícita (CTE `fns`), mas o T8a da v2.1 usava `p.proname like '%binder_activity%'`, que não alcança `list_my_closed_binder_histories` → 90.3 contava 9 (≠ 10) e 90.10 tratava essa função como "externa que referencia o histórico"; 90.4 deixava de cobri-la.

**Correção (só instrumento e verificadores):**
- `build_live_dryrun_s1.py`: nova `canonical_functions()` lê a lista da CTE `fns` do LIVE_90 (fonte única; nada redigitado); o T8a declara `v_fns text[]` uma vez e 90.3 (`count(*) = cardinality(v_fns)`), 90.4 e 90.10 (`not (p.proname = any(v_fns))`) passam a usá-la; saída em `LIVE_DRYRUN_S1_rollback_v2.2.sql`; cabeçalho v2.2. Demais itens, prólogo, migrations, sondas e sentinela inalterados.
- `static_check_p3b_s1.py`: S.18a confere o arquivo v2.2; **S.18e** v2.1 intacta (SHA `ddd0dbf2…`); **S.19a** conjunto criado pelas migrations = `NEW_FUNCTIONS` = lista `fns` do LIVE_90 (10); **S.19b** T8a: uma única declaração `v_fns` igual ao LIVE_90, sem `like`/`~` em `proname`, 90.3/90.4/90.10 por `any(v_fns)`, sem contagem literal; **S.19c** 6 mutações (inclui o defeito da v2.1) — todas detectadas. Aplicado à v2.1, o verificador S.19b acusa P-1, P-3, P-4 (×3) e P-5.

**Resultados:** `build_live_dryrun_s1.py --check` → EM DIA; `static_check_p3b_s1.py` → **56/56 PASS** (47 anteriores + S.18e + S.19a + S.19b + 6×S.19c). v2.2: 71.267 bytes, LF, sem BOM, 1.910 bytes não ASCII.

| Artefato | SHA-256 anterior | SHA-256 v2.2 |
|---|---|---|
| `LIVE_DRYRUN_S1_rollback.sql` (v2.1, histórico, executada e não aprovada) | `ddd0dbf2ef5346f5c3536d8b2d1d62ee3eab1cbc5ecc9d732d9a598e1322f74b` | inalterado |
| `LIVE_DRYRUN_S1_rollback_v2.2.sql` | — | `ece95392c0af14e35f690f544d8a3e524561d93a31f9c656a0653413c4757e40` |
| `build_live_dryrun_s1.py` | `4f3bacaa1668a79c7f24f3b823d8285c7bcb7b48b88e5ead49b0451cbc32a2e9` | `a474a3a36fa6b6a6c32149828c816f585a13d0f36793df26d65374d47becb8d7` |
| `static_check_p3b_s1.py` | `99e9b69d6625d0b498cf516d466bf6d6705014196a9fec787dd70de08c20b372` | `0fef13177845000df3a6f69ba9ae2183d7e674af443654f5cbc6c4a70b6f8ffd` |

Preservados (SHA conferidos): 5267–5270, LIVE_00, LIVE_90, gate v1.1, R0, harness 5860, sonda Dashboard, lexer. Nenhum SQL executado. O procedimento §28.13 (passo 4: arquivo e SHA) e a tabela §28.14 referem-se à v2.1; só serão atualizados para a v2.2 após auditoria independente e nova autorização.

### 28.22 Auditoria estática independente da v2.2 (2026-10-26) — **PASS COM RESSALVA**

- Causa-raiz reconfirmada: 10 `create function` nas migrations, 9 com `binder_activity` no nome; `list_my_closed_binder_histories` fora do `like` da v2.1.
- `canonical_functions()` extrai os 10 nomes da CTE `fns`; falha fechada (SystemExit) para CTE ausente, lista vazia ou repetida; para entrada malformada (maiúscula, nome qualificado, comentário com `)`, omissão) devolve subconjunto — barrado por S.19a (exige igualdade com as migrations e 10 itens), não pelo builder sozinho.
- Equivalência com o LIVE_90: mesmo conjunto (`nspname = 'public'` + nomes da lista, incluindo eventuais sobrecargas); 90.3 (`count = cardinality(v_fns)` ≡ `count(fns) = 10`), 90.4 (mesmo `bool_and` sobre o mesmo conjunto) e 90.10 (exclusão por nome no `public` ≡ exclusão por `oid in fns`) equivalentes.
- Sem alteração funcional fora do T8a: prólogo, migrations (T7), T8b, T9, T10, T11 idênticos à v2.1; diferenças só no cabeçalho, na linha do E2 e no T8a. v2.1 byte a byte preservada (`ddd0dbf2…`). SHA v2.2 `ece95392…`, builder EM DIA, static_check 56/56.
- Ressalvas (riscos residuais de falso negativo, comuns ao LIVE_90, não defeitos da v2.2): R1 função pública preexistente que referencie `binder_activity_` (90.10) ou sobrecarga preexistente de `list_my_closed_binder_histories` (90.3/90.4) — não coberta por LIVE_00/T6 (só `like`); ausente no repositório, não verificada no LIVE; R2 o builder aceita lista malformada como subconjunto — o `static_check` (passo 1 do E3) é obrigatório; R3 a forma `search_path=""` em `proconfig` ainda não foi exercitada no ensaio (na v2.1, 90.3 falhou antes pela contagem); há precedentes no repositório.

### 28.23 Fechamento das ressalvas R1 e R3 (2026-10-26) — consulta proposta, não executada

**R1 — `CATALOG_R1R3_readonly.sql` v1.0** (SHA-256 `04bad8f4d92b66263053f362ef194a0283d911ff4b01f6f46b64adb8866d39f0`): um único `WITH … SELECT` (lexer: 1 comando, nenhuma palavra de escrita/controle), lista canônica idêntica à de `canonical_functions()` (conferida por script). Linhas: C.1 (90.10) nenhuma função `public` fora da lista cita `binder_activity_` — mesmo predicado do 90.10; C.2 (90.3/90.4) nenhuma função `public` com nome canônico (sobrecarga prévia); C.3 `list_my_closed_binder_histories` inexistente em qualquer schema; C.4 informativo (nomes canônicos fora de `public`); C.5 (90.4) nenhum EXECUTE herdado por anon/authenticated via default ACL de funções ou pertença ao dono `postgres`; C.6 informativo (formas de `search_path` em `proconfig`); C.7 (R3) existe `proconfig @> array['search_path=""']` em `public` e nenhuma forma alternativa (`search_path=` / `search_path=''`). **PASS:** C.1, C.2, C.3, C.5, C.7 true. **STOP:** qualquer false (o ensaio v2.2 produziria falso negativo; decisão de Fabrício antes de qualquer mudança) ou erro da consulta.

**R3 — revisão estática:** predicado 90.3 `p.proconfig @> array['search_path=""']`; as 10 funções das migrations declaram `set search_path = ''` (2+3+4+1 ocorrências); o PostgreSQL grava esse valor como `search_path=""` (lista com aspas), que é o elemento literal procurado. Precedentes do repositório executados no LIVE: `2186` (`v_config @> ARRAY['search_path=""']`, mesma expressão) e `6821` v1.1 (`cfg = 'search_path=""'`, "forma real armazenada … neste Postgres 17, confirmada por auditoria física direta", PASS em 2026-09-05); `5812` registra o falso negativo inverso (`'search_path='`) já corrigido. Consistente; C.7 confirma empiricamente. **R3 fechada estaticamente; confirmação no LIVE junto com R1.**

### 28.24 Execução de `CATALOG_R1R3_readonly.sql` v1.0 (`P3B-S1-E3-CATALOG-R1R3-01`, 2026-10-26) — **STOP**

Autorizada por Fabrício. SHA-256 conferido (`04bad8f4…39f0`); SELECT enviado uma vez, exatamente como no arquivo, via `execute_sql`. Resposta: `ERROR 42601: syntax error at or near ")"` na linha 60 (fim de C.7). Erro de análise sintática: o PostgreSQL rejeita a mensagem inteira antes de executar — nenhuma linha C.1–C.7 foi produzida; nada lido nem alterado. Causa (estática): **um `)` excedente** no fecho de C.7 (saldo de parênteses −1 fora de literais); a verificação estática da proposta usou o lexer de comandos, que não confere balanceamento de parênteses. Não reexecutado, não corrigido nesta rodada. R1 permanece **aberta**; R3 continua fechada estaticamente, sem a confirmação empírica de C.7. Correção proposta (não aplicada): v1.1 removendo o `)` final de C.7, com verificação de balanceamento de parênteses, novo SHA, auditoria e nova autorização.

### 28.25 `CATALOG_R1R3_readonly_v1.1.sql` — correção mínima (2026-10-26) — preparada, não executada

v1.0 preservada sem alteração (`CATALOG_R1R3_readonly.sql`, SHA `04bad8f4…39f0`, evidência do STOP 42601). v1.1 em arquivo próprio, SHA-256 `95b0fc44a897b302340d710b041aa78bc5cdaa321b3dbf598cc4e705feb2f020`. Diferenças: linha de versão no cabeçalho (comentário) e o fecho de C.7 `…'search_path=''''')));` → `…'search_path='''''));` — única linha do SELECT alterada. Balanceamento de parênteses com reconhecimento de literais (`''`), identificadores entre aspas, comentários `--` e `/* */` e delimitadores `$…$`: v1.0 saldo −1; v1.1 saldo 0, mínimo 0, um `;`; controles do verificador (remoção de `(` detectada; `)` em literal e em comentário ignorados). Lexer: 1 comando `WITH … SELECT`, nenhuma palavra de escrita/controle. C.1–C.7 e critérios PASS/STOP (§28.23) inalterados. Limite: análise léxica, não parser do PostgreSQL. Execução exige nova autorização específica de leitura.

### 28.26 Execução de `CATALOG_R1R3_readonly_v1.1.sql` (`P3B-S1-E3-CATALOG-R1R3-V11-01`, 2026-10-26) — **PASS**

Autorizada por Fabrício. SHA-256 conferido (`95b0fc44…f020`); SELECT executado uma vez via `execute_sql`, sem erro.

| Linha | Detalhe | ok |
|---|---|---|
| C.1 (90.10) | `-` (nenhuma função `public` fora da lista cita `binder_activity_`) | true |
| C.2 (90.3/90.4) | `-` (nenhum nome canônico em `public`; sem sobrecarga prévia) | true |
| C.3 | `-` (`list_my_closed_binder_histories` inexistente em qualquer schema) | true |
| C.4 informativo | `-` (nenhum nome canônico fora de `public`) | true |
| C.5 (90.4) | default ACL de funções concede EXECUTE a `anon, authenticated, postgres, service_role` — os três primeiros são revogados explicitamente pelas migrations; anon/authenticated não pertencem a `postgres` | true |
| C.6 informativo (R3) | `search_path="" ×349 \| search_path=public ×42 \| search_path=public, pg_temp ×31` | true |
| C.7 (R3/90.3) | 349 funções casadas por `proconfig @> array['search_path=""']`; nenhuma forma alternativa | true |

**R1 fechada** (nenhum objeto preexistente interfere em 90.3, 90.4 ou 90.10). **R3 fechada** com confirmação empírica no LIVE. Nada alterado.

### 28.27 Preparação operacional final do ensaio v2.2 (2026-10-26) — sem execução

§28.13 passa a referenciar só `LIVE_DRYRUN_S1_rollback_v2.2.sql` (passo 1 com `static_check` 56/56; passo 4 com novo comando PowerShell); §28.14 traz o SHA da v2.2, os novos SHA do builder e do `static_check`, a v2.1 marcada como histórica e a consulta R1/R3 v1.1. O comando do passo 4 valida o SHA do arquivo antes de copiar, decodifica UTF-8 estrito (sem BOM) e confere o SHA-256 do texto relido da área de transferência contra o esperado; em divergência limpa a área de transferência e para. Observação: a falha da v2.1 foi do predicado T8a, não da cópia; a conferência da área de transferência fecha a lacuna de fidelidade entre arquivo e colagem (§28.3). Limite que permanece: o que o SQL Editor recebe após colar não é verificável por hash — por isso o passo 5 exige aba vazia, nenhuma seleção e execução única. Sentinela `MSDRYRUN`, critérios do passo 7, pós-checks (G-POST Q.01–Q.09, Q.08 = P.10, LIVE_00) e STOP preservados. Arquivo v2.2: 71.267 bytes, LF, sem BOM.

### 28.28 Renovação do pré-check do ensaio v2.2 (`P3B-S1-E3-LIVE-DRYRUN-V22-01`, 2026-10-27 ~02:06 UTC) — **STOP**

Estático: 16/16 SHA conforme §28.14; builder `LIVE_DRYRUN_S1_rollback_v2.2.sql EM DIA`; `static_check` 56/56. LIVE (execute_sql, só SELECT dos instrumentos congelados, uma execução cada):

- LIVE_00: **00.1 false** — último ledger `20261026124224` (≠ `5266_…`); 00.2–00.6 true.
- G-PRE: P.01 `off` · P.02 `origin` · P.03 `|` · P.04 `0` · P.05 `0` · P.06 `0` · P.07 `0` · P.08 `0` · P.09 `-` · P.11 `0` → todos true. P.12 informativo: `auth.users 2026-10-26 23:12:38.507426+00 | sessões: 2026-10-26 23:12:38.395044+00`.
- P.10 (preservado): `{"card": 21246, "card_set": 201, "auth_users": 3, "collection": 10, "ledger_last": "fix_mep_bootstrap_preserve_confirmed_primary_identity", "ledger_count": 535, "incorporation": 1, "public_functions": 423, "public_relations": 488, "card_variant_type": 97, "collection_layout": 3, "collection_layout_page": 146, "collection_layout_slot": 1776}`.

**Divergência:** uma migration nova foi registrada no ledger LIVE depois do último pré-check — versão `20261026124224`, nome `fix_mep_bootstrap_preserve_confirmed_primary_identity` (534 → 535). O nome não existe no repositório (nenhum `.sql`/`.md` o cita). Contagens de funções e relações de `public` inalteradas (423/488), compatível com substituição de função existente — não verificado. Impacto nos instrumentos congelados: LIVE_00 00.1, o precheck T6 do ensaio v2.2 e o G-POST Q.02 fixam `5266_create_binder_catalog_reconciliation_apply` como último ledger; com o ledger atual, **o ensaio v2.2 abortaria no T6** (`DRYRUN PRECHECK FALHOU`) e Q.02 falharia. Ensaio não executado; nenhuma consulta adicional; nada alterado. Decisão de Fabrício: confirmar origem/legitimidade da migration (e reconciliá-la ao repositório) e decidir a revisão dos instrumentos que fixam o ledger (LIVE_00, gate, T6 do builder) — nova versão, auditoria e autorização.

### 28.29 Reconciliação do baseline do ledger — MEP-01 (2026-10-27) — preparada, não executada

**Decisão de Fabrício:** a migration `20261026124224 fix_mep_bootstrap_preserve_confirmed_primary_identity` é correção intencional e autorizada (MEP: proteção `NOT EXISTS` em `public.persist_pricing_bootstrap_card_batch` contra segunda identidade PRIMARY ativa). Investigação funcional não reaberta.

**Inventário de dependências do baseline antigo** (`5266_create_binder_catalog_reconciliation_apply`; nenhuma comparação com a contagem 534): LIVE_00 00.1; precheck T6 do ensaio (via `PROLOGUE` do builder) e texto do item 8 do cabeçalho; gate Q.02. Sem dependência: LIVE_90 (conta 5267–5270 = 4), R0 (lê só 5267–5270), harness 5860, sonda Dashboard, DIAG, CATALOG; P.10/Q.08 são dinâmicos. Fora do caminho E3 (E2 suspenso, não alterados): `E2_probe_readonly.ps1` (`ledger_5266`) e `E2_run_live_dryrun_s1.ps1`.

**Proveniência MEP:** a função tem origem em `database/migrations/3958_create_persist_pricing_bootstrap_card_batch.sql` e a restrição em `3923_create_pricing_source_card_identity_foundation.sql`; a migration `20261026124224` **não está no repositório** — lacuna documental (SQL não reconstruído). As migrations 5267–5270 não citam pricing/bootstrap. Contagens `public` inalteradas (423/488). Sem evidência de incompatibilidade com a P3-B.

**Correção mínima:** `LIVE_00_precheck_readonly_v1.1.sql` (00.1 = `version || '|' || name` da última migration igual a `20261026124224|fix_mep_bootstrap_preserve_confirmed_primary_identity`), `LIVE_DRYRUN_S1_gate_readonly_v1.2.sql` (Q.02, idem; `not exists 5267–5270` mantido), builder com `LEDGER_BASELINE` (fonte única) gerando `LIVE_DRYRUN_S1_rollback_v2.3.sql` (T6 com a mesma igualdade; item 8 do cabeçalho). Igualdade exata de versão e nome — nenhuma comparação genérica. Demais controles inalterados (concorrência, locks, P.10/Q.08, `MSDRYRUN`, rollback, duração, STOP). Anteriores preservados: LIVE_00 v1.0 (`3868c4e4…`), gate v1.1 (`bc40ac84…`), v2.2 (`ece95392…`), v2.1 (`ddd0dbf2…`).

**Verificação estática nova:** S.20a (baseline do builder = literal único em LIVE_00 v1.1, T6 e gate v1.2; nenhuma referência executável a 5266; comparação por versão e nome; controle 5267–5270 presente; sem comparação de ordem) + S.20b (5 mutações detectadas); S.18f (v2.2 intacta); S.10 cobre LIVE_00 v1.1 e gate v1.2 (só SELECT). `static_check` 65/65; builder EM DIA; v2.3 71.552 bytes, LF, sem BOM; parênteses balanceados nos três instrumentos. Limite: coerência estática — o estado do ledger só é comprovado pelo LIVE_00 no LIVE. Migrations 5267–5270 com SHA inalterados.

### 28.30 Auditoria final do baseline MEP (2026-10-27) — **PASS**

Mesma identidade nos três pontos — LIVE_00 v1.1 00.1 (`= …`), T6 da v2.3 (`<> …` → aborta) e gate v1.2 Q.02 (`= …`): `coalesce(version || '|' || name da última migration, '') = '20261026124224|fix_mep_bootstrap_preserve_confirmed_primary_identity'`; ledger vazio ou nome nulo não passam. Controle `name ~ '^(5267|5268|5269|5270)_'` intacto nos três. v2.2 → v2.3: 14 linhas de diff, só cabeçalho, linha do E2, item 8 e T6. 19/19 SHA da §28.14 conferem; históricos preservados; builder EM DIA; `static_check` 65/65; §28.13 e o PowerShell referenciam só v2.3 / LIVE_00 v1.1 / gate v1.2 (SHA do PowerShell = arquivo). Pendência de rastreabilidade, não bloqueante: SQL da migration `20261026124224` ausente do repositório. Recomendação: READY para renovar LIVE_00 v1.1 + G-PRE (gate v1.2), mediante autorização.

### 28.31 Pré-check do ensaio v2.3 (`P3B-S1-E3-LIVE-DRYRUN-V23-01`, 2026-10-27 ~02:21 UTC) — **PASS**

Estático: 19/19 SHA (§28.14); builder `v2.3 EM DIA`; `static_check` 65/65. LIVE (execute_sql, só SELECT dos instrumentos vigentes): LIVE_00 v1.1 6/6 (00.1 `20261026124224|fix_mep_bootstrap_preserve_confirmed_primary_identity`); G-PRE (gate v1.2) P.01–P.11 true, **P.04 = 0**; P.12 informativo `2026-10-26 23:12:38 UTC` (auth.users e sessões).
P.10 — linha de base para Q.08: `{"card": 21246, "card_set": 201, "auth_users": 3, "collection": 10, "ledger_last": "fix_mep_bootstrap_preserve_confirmed_primary_identity", "ledger_count": 535, "incorporation": 1, "public_functions": 423, "public_relations": 488, "card_variant_type": 97, "collection_layout": 3, "collection_layout_page": 146, "collection_layout_slot": 1776}`.
Próximo: execução manual única pelo proprietário (§28.13 passos 4–6).

### 28.32 Execução manual do ensaio v2.3 e pós-check final (`P3B-S1-E3-LIVE-DRYRUN-V23-01`, 2026-10-27) — **ENSAIO PASS; ROLLBACK PASS**

Execução única pelo proprietário no SQL Editor (relato): SQLSTATE `P0001`, mensagem `MSDRYRUN {…}`, CONTEXT `PL/pgSQL function inline_code_block line 14 at RAISE`; JSON com `ok`, 90.2–90.12, `precheck`, `probe_*`, `role_restored`; txid 662032; `duration_ms` 1679; `legacy_items` 1; `legacy_events` 1.
Sentinela válida: a linha 14 do `dry_end` é o `raise 'MSDRYRUN'`, alcançável só quando `ok` = true, e `ok` é a ausência de qualquer booleano `false` no JSON — logo todos os booleanos do pós-check e das sondas foram true. Ressalva: os valores booleanos não foram transcritos no relato; a conclusão vem do ramo da sentinela, não de leitura direta.
Pós-check (execute_sql, só SELECT dos instrumentos vigentes, uma execução cada): G-POST (gate v1.2) **Q.01–Q.09 true** — Q.02 `535 | fix_mep_bootstrap_preserve_confirmed_primary_identity`, Q.03/Q.04/Q.05/Q.09 = 0, Q.06 `off`, Q.07 = 1; **Q.08 idêntico a P.10 em todos os 13 campos** (§28.31); LIVE_00 v1.1 **6/6**.
Sem objetos `binder_activity_*`, sem 5267–5270 no ledger, sem sessões, locks ou conexão do ensaio residuais. Nada corrigido, nada reexecutado, nenhuma migration aplicada, harness 5860 não executado, nenhuma operação Git.

### 28.33 Instalação definitiva 5267–5270 (`apply_migration`, 2026-10-27 ~02:40 UTC) — **STOP antes da primeira migration; nada aplicado**

Autorização do proprietário: G5b/G5c dispensados sob H-A (R2 aceito só para a S1), G8 concedido, janela declarada "aplicativo fechado e sem uso há pelo menos cinco minutos".
Passo 1 PASS: 8/8 SHA da §28.14, builder `v2.3 EM DIA`, `static_check` 65/65; corpos sem `begin;`/`commit;` externos preparados (5267 linhas 62/299, 5268 81/302, 5269 34/235, 5270 52/162).
Passo 2 PASS: LIVE_00 v1.1 6/6.
Passo 3: G-PRE (gate v1.2) P.01–P.11 true, P.04 = 0, P.10 idêntico à linha de base da §28.31. **Desvio:** P.12 informativo = `2026-10-27 02:39:08 UTC` (auth.users e auth.sessions); leitura de `now()` às `02:40:41 UTC` → atividade de autenticação **1 min 32 s** antes, o que contradiz a premissa da janela (sem uso há ≥ 5 min). Como a 5267 cria FK para `auth.users` (SHARE ROW EXCLUSIVE, sem `lock_timeout` na migration), a instalação foi interrompida antes do passo 4.
Estado: nenhuma migration aplicada; ledger intacto (535, MEP); nada repetido; harness 5860 não executado; nenhuma operação Git.
Retomada: confirmar origem da autenticação, aguardar ≥ 5 min sem atividade e repetir os passos 1–3 desde o início; a autorização G8 e a dispensa H-A seguem válidas salvo decisão em contrário.

### 28.34 Instalação definitiva da S1 no LIVE (`apply_migration`, 2026-10-27 02:46–02:50 UTC) — **PASS**

Autorização: G8 concedido; G5b/G5c dispensados sob H-A só para a S1 (R2 aceito). Retomada após o STOP da §28.33; auditorias estáticas não refeitas (aprovadas na §28.33).
Pré: LIVE_00 v1.1 6/6. G-PRE (gate v1.2) P.01–P.11 true, **P.04 = 0**, P.10 idêntico à linha de base (§28.31). Janela: última autenticação `02:39:08 UTC` (auth.users, auth.sessions e auth.refresh_tokens); a primeira leitura (`02:43:54`) mostrou 4 min 45 s, sem nova atividade — aguardada a passagem do tempo e renovado o G-PRE uma vez às `02:45:01` com P.01–P.11 true, P.04 = 0, P.10 idêntico e janela ≥ 5 min true.
Aplicação (uma `apply_migration` por arquivo, corpo aprovado sem `begin;`/`commit;` externos), todas sem erro:

| Ledger | Nome | md5 do texto gravado |
|---|---|---|
| 20261027024607 | `5267_create_binder_activity_structures` | `03db4ef3…` |
| 20261027024731 | `5268_create_binder_activity_recording_functions` | `1cc7c249…` |
| 20261027024829 | `5269_create_binder_activity_reads` | `fee6499f…` |
| 20261027024918 | `5270_create_binder_activity_purge_and_legacy` | `0a37d11b…` |

Integridade: md5 do texto no ledger = md5 do corpo aprovado (arquivo sem as linhas `begin;`/`commit;` e sem a última quebra de linha) nas 4; ordem 5267 → 5270; versões posteriores a `20261026124224`.
Pós: **LIVE_90 v1.1 12/12 true** (90.6: 1 evento legado L01, sem ator, 1 item, sem posição).
Security Advisor (02:50 UTC), achados atribuíveis à S1: `rls_enabled_no_policy` nas 4 tabelas (intencional — §10.1 S1: RLS ativo, sem política para clientes; acesso só pelas funções) e WARN `authenticated_security_definer_function_executable` nas 3 leituras (esperado, mesmo precedente das 5263–5266). Nenhum outro achado da S1 (nada executável por `anon`, nenhum `search_path` mutável).
Não executados: harness 5860 (dispensado, H-A), R0, operações Git. Funções de gravação (5268) e exclusão (5270) sem permissão para clientes; nenhuma função homologada as chama (90.10).

### 28.35 Encerramento da S1 — promoção canônica (2026-10-27)

5267–5270 copiadas para `database/schema/` com o padrão das 5263–5266: só o bloco `Status` difere (EXECUTADA / CANÔNICA, ledger e md5); do `begin;` ao `commit;` idênticas à proposta (verificado por script, 4/4). `static_check_p3b_s1.py` ajustado em uma linha para não contar as próprias 5267–5270 promovidas como "funções existentes" no S.2 (SHA `215179c4…` → `86405bd0…`); continua 65/65. 05d, ROADMAP e HANDOFF atualizados.

## 29. S2 — instrumentação de E02–E05 (2026-10-27) — IMPLEMENTADA LOCALMENTE, NÃO APLICADA

### 29.1 Escopo (de §4.1 e §11)

| Evento | Função (LIVE = canônica, md5 de `prosrc` conferido em 2026-10-27) | Migration |
|---|---|---|
| — | helper interno `binder_activity_add_card_item(text,uuid,uuid,uuid)` | 5271 (nova) |
| E02 Carta colocada (inclui "Desfazer remoção") | `place_my_physical_card_in_slot(uuid,uuid,uuid)` — 5250, `caecf1bd…` | 5272 |
| E03 Carta movida / E04 Cartas trocadas | `move_slot_assignment(uuid,uuid)` — 5132, `4e71adc2…` | 5273 |
| E05 Cartas retiradas | `remove_slot_assignment(uuid[])` — 5133, `6bf6a90e…` | 5274 |

Dependências: S1 no LIVE (5267–5270); `physical_card` → `card_variant` (cópia de carta e acabamento). Fora da S2: frontend (S7), demais eventos (S3–S6).

### 29.2 Pontos exatos de instrumentação (linhas marcadas `-- P3B-S2`)

- **5272 / E02** — `begin(layout,'CARD_PLACED','FICHARIO',coleção)` logo antes do passo 6, depois de todas as validações, travas e do retorno `UNCHANGED` (que, portanto, não grava). REPLACE: item `CARD/REMOVED` do exemplar anterior (origem = bolso) **antes** do DELETE. Depois do INSERT: `CARD/PLACED` (destino = bolso). `end()` depois do `RETURN QUERY`.
- **5273 / E03–E04** — depois das escritas e antes do `RETURN QUERY`: `begin` com tipo `CARD_MOVED` ou `CARDS_SWAPPED` conforme a operação já decidida; MOVE = 1 item `MOVED` (origem → destino); SWAP = 2 itens `SWAPPED` (A: origem → destino; B: destino → origem). Os dois bolsos existem antes e depois; o estado intermediário do SWAP nunca é observado. `end()` no fim do corpo.
- **5274 / E05** — depois da checagem de travas e antes do DELETE: `begin`, laço sobre as cartas dos bolsos pedidos (sob as travas de bolso já adquiridas, mesmo predicado do DELETE), ordenado por página/linha/coluna, 1 item `REMOVED` por carta; `end()` antes do `RETURN`. Pedido só com bolsos vazios → nenhum item → nenhum evento.
- **5271** — resolve exemplar → (carta, acabamento), delega a `binder_activity_add_item` com `detail = {physical_card_id}`; sem begin/end, sem INSERT direto, sem EXECUTE para clientes.

### 29.3 Integridade

- Diff mínimo provado: retiradas as linhas marcadas e voltando `$fn$` → `$$`, os três corpos têm exatamente o md5 do canônico/LIVE; cabeçalhos (assinatura, retorno, SECURITY, SET — inclusive `lock_timeout=5s` da 5250) e REVOKE/GRANT idênticos. Precheck de cada migration recusa se a função LIVE divergir da base.
- W3 I-1..I-6 sem violações (mesmo verificador da S1) + 4 mutações detectadas.
- Atomicidade: gravação na transação da operação; qualquer erro aborta operação e evento (R1). Erros de negócio saem antes do begin.
- Concorrência: nenhuma trava nova; os itens são lidos sob as travas que as funções já adquirem.
- I-7: um item por (exemplar, efeito); SWAP gera dois exemplares distintos. W1: E02 ≤ 2, E03 = 1, E04 = 2, E05 ≤ 500 itens (≤ cartas no fichário), dentro do teto.

### 29.4 Segurança

Nenhum privilégio novo para clientes. Helper interno com EXECUTE revogado de PUBLIC/anon/authenticated/service_role. Titular = dono do fichário (5268 recusa ator ≠ titular); ownership das três funções inalterado (owner-scoped). `detail` só leva `physical_card_id` (do próprio titular). Leitura continua só pelas 3 funções da 5269.

### 29.5 Performance (metas P3 — a medir, não comprovadas)

Custo por item: 1 leitura do exemplar + as leituras da 5268 (bolso→página, carta→Set, acabamento) + 1 INSERT, todas por chave. E02/E03/E04 (1–2 itens): previsto dentro de 5 ms. **E05 em lote grande é o risco:** 500 itens ≈ 2.500 buscas indexadas na mesma transação; maior fichário do LIVE hoje = 191 cartas. Medição obrigatória no gate (custo de E05 com 1, 20 e 191 bolsos); otimizar exige mudar o contrato I-5 (gravação em lote na 5268), decisão própria se a meta falhar.

### 29.6 Gate da S2 — critérios objetivos

| Etapa | PASS | STOP |
|---|---|---|
| Estático | `static_check_p3b_s2.py` 30/30 (inclui S1 65/65) | qualquer FAIL |
| Pré | LIVE_S2_00 6/6 + G-PRE (gate v1.2) com P.04 = 0 e P.12 ≥ 5 min | qualquer false |
| Aplicação | 5271 → 5272 → 5273 → 5274, uma `apply_migration` cada, corpo sem `begin;`/`commit;` | qualquer erro: não aplicar a seguinte |
| Pós estrutural | LIVE_S2_90 bloco A 7/7; ledger 4/4 com md5 do texto = corpo; Advisor sem achado novo da S2 | qualquer false / achado novo |
| Funcional | operações reais do proprietário pela interface (ADD, REPLACE, mover, trocar, retirar ≥ 2, desfazer) → bloco B: B.1–B.7 true; B.8 conferido | qualquer false; recusa de operação que antes funcionava |
| Regressão | as mesmas operações continuam com o resultado anterior na interface (fluxos homologados P2-B) | qualquer divergência |

Reversão: reaplicar as definições canônicas 5250/5132/5133 por migration nova (corpo idêntico ao canônico) e remover o helper; o histórico já gravado permanece (imutável, C-179).

### 29.7 Validação dinâmica — decisão pendente

O harness da fatia (I1–I11 por evento) segue o mesmo impedimento do 5860: cria usuários e catálogo, logo não roda no LIVE, e não há ambiente isolado. Caminho proposto, no padrão H-A: validação por **operações reais do proprietário** + bloco B somente leitura (eventos reais, sem dados sintéticos), mais a prova estática de diff mínimo. Não cobertos dinamicamente nesse caminho: concorrência de duas sessões e o volume máximo de E05 (medido só no volume real). Decisão de Fabrício.

### 29.8 Artefatos (SHA-256)

| Arquivo | SHA-256 |
|---|---|
| 5271_create_binder_activity_add_card_item.sql | `11dcc0d6…` |
| 5272_instrument_place_my_physical_card_in_slot.sql | `99f23420…` |
| 5273_instrument_move_slot_assignment.sql | `c03b1a32…` |
| 5274_instrument_remove_slot_assignment.sql | `9ed38d25…` |
| static_check_p3b_s2.py | `a3cd3c9c…` |
| static_check_p3b_s1.py (v pós-promoção) | `86405bd0…` |
| LIVE_S2_00_precheck_readonly.sql | `7727e5ee…` |
| LIVE_S2_90_postcheck_readonly.sql (v1.1, errata A.2) | `14ac4760…` (v1.0 `69df3a9c…`) |

LIVE_S2_00 executado em 2026-10-27 (só leitura): **6/6 true** — ledger termina na 5270, S1 presente, as três funções-base iguais ao canônico, 5271–5274 livres, histórico só com o legado, nenhuma função fora da S1 referencia o histórico. LIVE_S2_90 rodado uma vez só para conferir sintaxe (resultados pré-instalação esperados: A.1/A.2/A.6 falsos, B.1 falso).

### 29.9 Instalação da S2 no LIVE (`apply_migration`, 2026-10-27 03:06–03:09 UTC) — estrutural PASS; homologação funcional pendente

Autorização: instalação de 5271–5274 + pós-checks + homologação funcional; H-A (sem harness) só para a S2; riscos de concorrência e desempenho aceitos provisoriamente, não resolvidos.
Pré: SHA dos 4 arquivos = §29.8; `static_check_p3b_s2` 30/30 (S1 65/65); LIVE_S2_00 6/6; janela: 0 sessões cliente ativas, 0 locks aguardando, última autenticação 02:39:08 UTC (27 min antes).

| Ledger | Nome | md5 do texto gravado |
|---|---|---|
| 20261027030638 | `5271_create_binder_activity_add_card_item` | `df6b3b2c…` |
| 20261027030713 | `5272_instrument_place_my_physical_card_in_slot` | `7d8ed7e1…` |
| 20261027030813 | `5273_instrument_move_slot_assignment` | `55c78148…` |
| 20261027030849 | `5274_instrument_remove_slot_assignment` | `6ee5b83b…` |

md5 do texto no ledger = corpo aprovado (sem `begin;`/`commit;` e sem a quebra de linha final) nas 4.
Pós (LIVE_S2_90 bloco A): A.1, A.3–A.7 true na primeira leitura. **A.2 deu false por defeito do instrumento, não da instalação:** os md5 esperados de 5272–5274 tinham sido extraídos a partir do "$fn$" citado no cabeçalho de comentário. Os `prosrc` LIVE (`2672da17…`, `fe149c75…`, `e4b6c8cd…`; helper `c5f9b7bd…`) são exatamente os corpos entre `as $fn$` e `$fn$;` dos arquivos aprovados. LIVE_S2_90 corrigido para v1.1 (errata só das 3 constantes) e A.2 reexecutado uma vez: true. **Bloco A 7/7.**
Security Advisor (03:09 UTC): helper sem nenhum achado; as 3 funções instrumentadas mantêm o WARN `authenticated_security_definer_function_executable` que já tinham (ACL inalterado); saída do Advisor com o mesmo tamanho da leitura anterior — nenhum achado novo atribuível à S2.
Não executados: harness, R0, operações Git. Nenhuma operação funcional executada por SQL.

**Homologação funcional — pendente (proprietário, pela interface):** (1) colocar 1 carta num bolso vazio; (2) substituir a carta de um bolso ocupado; (3) mover 1 carta para bolso vazio; (4) trocar 2 cartas de lugar; (5) retirar ≥ 2 cartas de uma vez (seleção múltipla); (6) desfazer uma retirada. Depois: bloco B (B.1–B.7 true, B.8 conferido), regressão visual (mesmos resultados de antes) e medição de desempenho (tempo das funções em `pg_stat_statements`, somente leitura).

### 29.10 Homologação funcional da S2 — resultado parcial e correção do Desfazer (2026-10-27)

Operações do proprietário após a instalação (9 eventos instrumentados). **Bloco B: B.1–B.7 PASS**; sem itens duplicados nem exemplar em dois bolsos. Mover, trocar, retirar e restaurar: **homologados**.
Falha observada no Desfazer: o banco restaurou as duas cartas (Jirachi ex 155 → p18 l2 c1; Mewtwo ex 157 → p18 l2 c3, eventos 9 e 10), mas a lista "Cartas disponíveis" continuou exibindo-as. Causa: `runUndo` (`binder-workspace.tsx`, anterior à S2) atualizava só as páginas, nunca a lista do painel. Não é defeito da S2 nem do banco.
Correção local (só frontend, `runUndo`): exemplares restaurados saem da lista e do contador (mesma regra de `placeAvailableCard`); restauração parcial ou recusada relê a lista do banco (`loadAvailable(0)`). typecheck PASS; testes `lib/colecoes/binder*.test.ts` 117/117. Pendente: validação visual pelo proprietário.
Pendentes: **ADD pela interface** (colocar a partir de "Cartas disponíveis" num bolso vazio) e **REPLACE** — o fichário atual não oferece substituição de carta ocupada (o painel só coloca em bolso vazio; "Substituir" existe só no protótipo experimental `binder-nav-01`), logo o ramo REPLACE de `place_my_physical_card_in_slot` não é alcançável pela interface hoje. Desempenho: não medido.
Decisões do proprietário (2026-10-27, fechamento objetivo): (1) REPLACE não será exigido pela interface atual — **cenário não testado**, sem PASS dinâmico (cobertura só estática, S2.1–S2.8); (2) ADD pela interface não exigido agora (sem cartas novas disponíveis) — **pendência funcional**; (3) mover/trocar/retirar não serão repetidos; (4) P2/P3 pendentes até medição válida; (5) correção do Desfazer restrita a `runUndo`. Parecer de encerramento parcial da S2 condicionado à validação visual do Desfazer.
Correção complementar (2026-10-27): Desfazer validado visualmente pelo proprietário; defeito inverso observado — após retirar, "Cartas disponíveis" não recebia as cartas (contador 0). Causa: `runRemove` (anterior à S2) nunca atualizava o painel. Correção local mínima: `runRemove` relê a lista do banco (`loadAvailable(0)`) após a retirada (sucesso ou falha); `runUndo` mantém a remoção imediata e passa a confirmar sempre com o banco; `loadAvailable` ganhou número de sequência que descarta respostas fora de ordem. typecheck PASS (sem `.next/types`, regenerado pelo servidor local em execução); testes binder 117/117. Pendente: validação visual.

### 29.11 Encerramento parcial da S2 e promoção canônica (2026-10-27)

Homologação visual do proprietário após a correção complementar do frontend (`runRemove` relê "Cartas disponíveis"; `loadAvailable` descarta respostas fora de ordem; `runUndo` preservado): retirar 2 cartas, atualização imediata do painel, Desfazer, restauração dos bolsos e contador/lista — **PASS**. Bloco B do LIVE_S2_90: B.1–B.7 PASS.
**Promoção:** `5271`–`5274` copiadas para `database/schema/`; só o bloco Status difere (corpo do `begin;` ao `commit;` idêntico ao da proposta, conferido por diff). `static_check_p3b_s1.py` 65/65 e `static_check_p3b_s2.py` 30/30 sem alteração (as cópias canônicas não interferem nas varreduras).
**Pendências explícitas (sem PASS atribuído):**

| Item | Situação |
|---|---|
| ADD pela interface (carta de "Cartas disponíveis" para bolso vazio) | **Não comprovado** — sem cartas novas disponíveis; cobertura estática (S2.1–S2.8) |
| REPLACE (carta em bolso ocupado) | **Não testado** — a interface atual não oferece a operação |
| Desempenho P2/P3 | **Sem medição conclusiva** |
| Concorrência | **Risco residual aceito provisoriamente** (sem harness, H-A) |

## 30. S3 — instrumentação de E08–E10 (2026-10-27) — IMPLEMENTADA LOCALMENTE, NÃO APLICADA

### 30.1 Escopo (de §4.1 e §11)

E08 `set_slot_expected_content(uuid,uuid,uuid,uuid,uuid)` (base 5229) → `POCKET_RESERVED`; E09 `clear_slot_expected_content(uuid[])` (5129) → `RESERVATIONS_RELEASED`; E10 `set_slot_lock(uuid[],bool)` (5130) → `POCKETS_LOCKED` / `POCKETS_UNLOCKED`. Tipos, `item_kind` (`RESERVATION`, `POCKET`) e efeitos (`RESERVED`, `RELEASED`, `LOCKED`, `UNLOCKED`) já existem nos CHECKs da 5267. Bases conferidas no LIVE (md5 de `prosrc` = canônico) em 2026-10-27. Dependências: S1 e helper novo `5275`; independente da S2. Fora da S3: frontend (S7) e demais eventos (S4–S6).

### 30.2 Convenções de itens — **APROVADAS (2026-10-27)**

A matriz (§4.1) fixa eventos e tipos, mas não a posição de cada item. Regra adotada, coerente com a S2 (REMOVED = origem, PLACED = destino): **efeito que entra no bolso = destino; efeito que sai = origem.**

- **E08:** bolso sem reserva → 1 `RESERVATION/RESERVED` (destino). Reserva diferente → `RELEASED` da anterior (origem, lida antes do upsert) + `RESERVED` da nova (destino, lida depois) — mesmo desenho do REPLACE. Reserva idêntica (carta, variante, acabamento e coleção) → nenhum item e nenhum evento (C-206). Coleção do evento = dona da reserva (D8).
- **E09:** 1 `RELEASED` (origem) por reserva efetivamente apagada, em ordem de página/linha/coluna; bolsos sem reserva não geram item.
- **E10:** 1 `POCKET/LOCKED` (destino) ou `POCKET/UNLOCKED` (origem) por bolso que muda de estado, com o mesmo predicado do UPDATE (`locked IS DISTINCT FROM p_locked`); bolsos já no estado pedido não geram item.
- **Item de reserva (5275):** carta e acabamento copiados no momento (acabamento pedido; senão o da variante reservada); `detail` = `{collection_id, card_variant_id}` (nulos omitidos).

### 30.3 Integridade

Diff mínimo provado por md5 (linhas `-- P3B-S3`); contrato W3 I-1..I-6 sem violações; itens lidos sob as travas de bolso já adquiridas pela função, com o mesmo predicado da escrita (itens = linhas alteradas); I-7 (um item por bolso e efeito) e I-10 (origem antes, destino depois). Assinaturas, retornos, mensagens, ordem de travas e ACL preservados. Cabeçalho preguiçoso: operação sem efeito não grava.

### 30.4 Segurança

`5275` interna (DEFINER, `search_path` vazio, EXECUTE revogado de PUBLIC/anon/authenticated/service_role), não abre/fecha operação nem grava direto. Titularidade e ator continuam verificados pela 5268 (dono = `auth.uid()`). Funções instrumentadas mantêm EXECUTE só para `authenticated`.

### 30.5 Performance — metas, não medidas

E08: 1–2 itens e uma leitura por PK do bolso. E09/E10: até 500 itens (teto das próprias funções), uma varredura por `slot_id = ANY` já usada pela função + ordenação; teto W1 ≥ 8·S (§19.2). **Não medido.**

### 30.6 Gate da S3

| Critério | Estado |
|---|---|
| Convenções de §30.2 confirmadas pelo proprietário | **aprovadas** — origem/destino como transição de estado do bolso, não movimentação física da carta |
| Validação dinâmica (harness) ou dispensa formal H-A para a S3 | **dispensa H-A recomendada, só para a S3**; riscos residuais (concorrência, desempenho, ramos não exercitados pela interface) documentados |
| LIVE_S3_00 6/6 na janela da instalação | 6/6 em 2026-10-27 (renovar no dia) |
| Autorização expressa para aplicar 5275–5278 | **concedida (2026-10-27); H-A dispensado só para a S3** |
| Pós: LIVE_S3_90 bloco A 7/7; ledger 4/4 md5; Advisor sem achado novo | **PASS** (§30.8) |
| Homologação: LIVE_S3_90 bloco B (reservar, trocar reserva, liberar ≥ 2, fixar/desfixar ≥ 2) | — |

### 30.7 Artefatos (SHA-256)

| Arquivo | SHA-256 |
|---|---|
| 5275_create_binder_activity_add_reservation_item.sql | `c98feeee…` |
| 5276_instrument_set_slot_expected_content.sql | `65bf0872…` |
| 5277_instrument_clear_slot_expected_content.sql | `035e8e9f…` |
| 5278_instrument_set_slot_lock.sql | `5a7e5bc3…` |
| static_check_p3b_s3.py | `eac97c6f…` |
| LIVE_S3_00_precheck_readonly.sql | `ef54582a…` |
| LIVE_S3_90_postcheck_readonly.sql | `e1d495ab…` |

`static_check_p3b_s3.py` **31/31 PASS** (diff mínimo por md5, cabeçalho, W3, tipos/efeitos, ACL, precheck, helper, 4 mutações detectadas, S1 65/65 e S2 30/30). LIVE_S3_00 executado em 2026-10-27 (só leitura): **6/6 true**. A S1 (S.17) já reconhece as 6 funções instrumentadas S2+S3 sem violação de W3.

### 30.8 Instalação da S3 no LIVE (`apply_migration`, 2026-10-27 22:15–22:18 UTC) — estrutural PASS; homologação funcional pendente

Pré: static_check S3 31/31; SHA-256 dos 4 arquivos iguais aos de §30.7; LIVE_S3_00 6/6; janela quieta (0 sessões cliente; última autenticação 15:01 UTC, ~7 h antes).
Aplicação uma a uma, corpo do arquivo sem as linhas `begin;`/`commit;`, conferência do ledger após cada uma; nenhum erro.

| Ledger | Migration | md5 do texto gravado (= corpo enviado) |
|---|---|---|
| 20261027221555 | `5275_create_binder_activity_add_reservation_item` | `fb8946d4…` |
| 20261027221642 | `5276_instrument_set_slot_expected_content` | `d9b1f704…` |
| 20261027221717 | `5277_instrument_clear_slot_expected_content` | `4a79ab48…` |
| 20261027221757 | `5278_instrument_set_slot_lock` | `32f7700d…` |

LIVE_S3_90 bloco A: **7/7 true** (ordem do ledger, md5 dos corpos, helper sem EXECUTE de cliente, DEFINER/search_path/ACL das instrumentadas, assinaturas e retornos, gate de cobertura S1+S2+S3, nenhum evento S3 gravado pela instalação). Security Advisor: nenhum achado para a 5275; para as três instrumentadas, apenas o WARN já existente de função `SECURITY DEFINER` executável por `authenticated` (contrato inalterado) — nenhum achado novo atribuível à S3.
**Pendente:** homologação funcional pelo proprietário e LIVE_S3_90 bloco B. Riscos residuais: concorrência e desempenho (sem harness, H-A).

### 30.9 Homologação funcional da S3 — bloco B do LIVE_S3_90 (2026-10-27) — **STOP (B.6)**

Eventos: POCKET_RESERVED 8 (todos com 1 item RESERVED/destino), RESERVATIONS_RELEASED 7 (8 itens; um lote de 2), POCKETS_LOCKED 2 (um lote de 2), POCKETS_UNLOCKED 2 (um lote de 2). B.1–B.5 **PASS**; B.6 **FALSE**.
Causa do B.6: 3 itens RELEASED (eventos 34 e 36) de reservas **anteriores à 5229**, com `collection_id` nulo — `detail = {}`. No LIVE, 348 de 351 reservas têm `collection_id` nulo (coluna anulável); nenhum item RESERVED ficou sem coleção. O critério B.6 presumiu coleção sempre presente: defeito do instrumento, não da gravação (5275 copia o estado real). Nenhum dado divergente.
Observação: a troca de reserva foi feita como liberar + reservar (eventos separados); o ramo E08 com RELEASED+RESERVED no mesmo evento (n = 2) não foi exercitado.
Proposta (não aplicada): errata LIVE_S3_90 v1.1 — B.6 exige `collection_id` só em RESERVED; rodar uma vez só o bloco B. Parecer da S3 pendente.

### 30.10 Errata B.6 e encerramento parcial da S3 (2026-10-27) — **PASS**

`LIVE_S3_90_postcheck_readonly_v1.1.sql` (SHA-256 `743b4201…`; v1.0 `e1d495ab…` preservada): só o cabeçalho e o B.6 mudam (diff conferido). B.6 v1.1: carta copiada em todo item de reserva; RESERVED com destino e coleção; RELEASED com origem, coleção opcional (reserva legada sem `collection_id`). Blocos A e B.1–B.5 idênticos.
Execução única do bloco B v1.1 (só leitura): **B.1–B.6 PASS** — POCKET_RESERVED 8 (1 item cada), RESERVATIONS_RELEASED 7 (8 itens; lote de 2), POCKETS_LOCKED 2 e POCKETS_UNLOCKED 2 (lotes de 2), sem duplicidade.
**Promoção:** `5275`–`5278` copiadas para `database/schema/` (só o bloco Status difere; corpo conferido por diff). static_check S1 65/65, S2 30/30, S3 31/31 sem alteração.
**Pendências (sem PASS):** troca de reserva no mesmo evento (RELEASED+RESERVED, n = 2) não exercitada dinamicamente; concorrência e desempenho não medidos; S2 — ADD pela interface e REPLACE inalterados. Observação de produto (fora do escopo): reservar bolso vazio para carta escolhida não existe na interface.

## 31. S4 — instrumentação de E11–E15 (2026-10-27) — IMPLEMENTADA LOCALMENTE, NÃO APLICADA

### 31.1 Escopo e bases (conferidas no LIVE em 2026-10-27)

| Migration | Função | Base (md5 `prosrc` LIVE) | Evento |
|---|---|---|---|
| 5279 | `binder_activity_add_pocket_shift_items(uuid,uuid)` — **interna nova** | — | (itens SHIFTED) |
| 5280 | `add_layout_page(uuid)` | 5125 `cdcf89d3…` | E13 `PAGES_ADDED` |
| 5281 | `remove_layout_page(uuid,integer)` — o invólucro `(uuid)` não muda (§7.2-3) | 5260 `4baf044d…` | E14 `PAGE_REMOVED` |
| 5282 | `reorder_layout_pages(uuid,uuid[])` | 5127 `39b8b80f…` | E15 `PAGES_REORDERED` |
| 5283 | `insert_my_binder_gap(...)` | 5243 `a99a90c5…` | E11 `GAP_OPENED` |
| 5284 | `close_my_binder_gap(...)` | 5243 `eef3073f…` | E12 `GAP_CLOSED` |

**Achado (documental, sem efeito funcional):** o corpo LIVE de `insert_my_binder_gap`, `close_my_binder_gap` e `binder_gap_move_pocket` não tem os comentários `--` presentes em `database/schema/5243_*.sql` (md5 do arquivo ≠ md5 LIVE; código idêntico sem comentários). A S4 usa o **corpo do LIVE** como base do diff mínimo; o cabeçalho é o canônico.

### 31.2 Caminhos reais (frontend e banco)

| Operação | Interface | Chamadas internas |
|---|---|---|
| E13 adicionar páginas | Fichário → "Adicionar páginas" (`addPages`: N chamadas de 1 página → N eventos, I7/D6) | também embutida em E11 e na E16 (`apply_my_binder_catalog_reconciliation`) |
| E15 reordenar | Visão geral → "Organizar páginas" (`reorderPages`) | — |
| E11 abrir espaço | Bolso → "Abrir espaço antes deste bolso" (`insertGap`) | `add_layout_page` (NEEDS_PAGE), `binder_gap_move_pocket` |
| E12 fechar espaço | "Desfazer" depois de abrir (`closeGap`) | `binder_gap_move_pocket`, `remove_layout_page(uuid)` → `(uuid,int)` |
| E14 remover página | **sem caminho na interface** (só embutida em E12) | — |

### 31.3 Convenções de itens — **a confirmar**

- Deslocamento de bolso: um item por objeto, **SHIFTED** com origem → destino: `CARD` (exemplar), `RESERVATION` (reserva) e `POCKET` com `detail {"content":"IMAGE"}` (imagem). Fixação e referência de espécie ficam no bolso e não geram item.
- Páginas: `PAGE/PAGE_ADDED` (destino = número novo), `PAGE/PAGE_REMOVED` (origem = número removido; detalhe com referências de espécie removidas), `PAGE/PAGE_RENUMBERED` (origem n → destino m).

### 31.4 R5 e não duplicidade

- Um evento por chamada do cliente: `begin` dentro de uma operação aberta só aumenta a profundidade (5268); o tipo e o cabeçalho são os da operação externa. `add_layout_page` embutida vira item `PAGE_ADDED` do `GAP_OPENED`; `remove_layout_page` embutida vira itens do `GAP_CLOSED`.
- Itens de deslocamento lidos **depois** de todos os movimentos (estado final; `binder_gap_move_pocket` não é instrumentada) — um item por objeto, sem repetição intermediária. Em E12, gravados **antes** da remoção da página (I-10: a origem pode estar nela).
- Sem efeito, sem evento: `ALREADY_FREE` sai antes do `begin`; reordenação idêntica não gera item; cabeçalho preguiçoso.

### 31.5 Integridade, segurança e performance

Diff mínimo por md5; W3 I-1..I-6; assinaturas, retornos, travas, mensagens e ACL preservados; `5279` interna (DEFINER, `search_path` vazio, sem EXECUTE de clientes). Volume: E11/E12 até 500 linhas por operação (teto da 5243) → até ~3 itens por bolso deslocado, cada item = leituras por chave; E15 ≤ nº de páginas; W1 cobre (≥ 8·S + folga). **Não medido.**

### 31.6 Riscos

| # | Risco | Tratamento |
|---|---|---|
| R-S4-1 | Entre a S4 e a S6, a incorporação de novidades (E16, ainda sem `begin`) que precise de página nova gera um evento `PAGES_ADDED` próprio (fato verdadeiro, enquadramento incompleto; os deslocamentos da E16 ficam sem registro até a S6) | Decisão do proprietário: aceitar como interino documentado, ou evitar incorporar novidades com página nova até a S6 |
| R-S4-2 | E14 direta sem caminho na interface | Coberta pela E12 com página embutida + estático |
| R-S4-3 | Desempenho com cadeias longas (até 500 linhas) | Não medido (H-A) |
| R-S4-4 | Concorrência | Herdada das funções-base (travas inalteradas); não exercitada |

### 31.7 Gate da S4

| Critério | Estado |
|---|---|
| static_check S4 | **51/51 PASS** (inclui S1 65/65, S2 30/30, S3 31/31) |
| LIVE_S4_00 | **6/6** em 2026-10-27 (renovar no dia) |
| Convenções §31.3 confirmadas | pendente |
| Decisão sobre R-S4-1 | pendente |
| Validação dinâmica ou H-A para a S4 | pendente |
| Autorização expressa para aplicar 5279–5284 (nessa ordem) | pendente |
| Pós: LIVE_S4_90 bloco A 7/7; ledger 6/6 md5; Advisor | — |
| Homologação: bloco B (adicionar 2 páginas; abrir espaço simples; abrir espaço com página nova e desfazer; reordenar) | — |

### 31.8 Artefatos (SHA-256)

| Arquivo | SHA-256 |
|---|---|
| 5279_create_binder_activity_add_pocket_shift_items.sql | `44f2e7a5…` |
| 5280_instrument_add_layout_page.sql | `c5e975f3…` |
| 5281_instrument_remove_layout_page.sql | `1073cda8…` |
| 5282_instrument_reorder_layout_pages.sql | `6e17466a…` |
| 5283_instrument_insert_my_binder_gap.sql | `d70f31b7…` |
| 5284_instrument_close_my_binder_gap.sql | `30fb189c…` |
| static_check_p3b_s4.py | `d5d157f3…` |
| LIVE_S4_00_precheck_readonly.sql | `bc0023af…` |
| LIVE_S4_90_postcheck_readonly.sql | `aeccfda9…` (bloco B executado uma vez só para conferir sintaxe) |

### 31.9 Instalação no LIVE (2026-10-27) — autorização expressa do proprietário

Decisões aprovadas: convenções §31.3; H-A para a S4 (concorrência e desempenho seguem não medidos); **R-S4-1 — restrição operacional até a S6:** não fazer incorporações de catálogo que exijam criação automática de páginas. Enquanto a restrição não puder ser garantida, a cobertura do histórico **não é declarada completa**: uma incorporação desse tipo gera `PAGES_ADDED` próprio e deslocamentos sem registro (exposição residual conhecida).

| Etapa | Resultado |
|---|---|
| SHA-256 dos artefatos (§31.8) | conferidos |
| static_check S4 | 51/51 PASS |
| LIVE_S4_00 (renovado) | 6/6 |
| Janela quieta | 0 sessões cliente ativas; 0 transações ociosas; 0 locks aguardando; última autenticação 38 min antes |
| `apply_migration` 5279 → 5284 | 6/6 sucesso, sem erro, sem repetição |
| LIVE_S4_90 bloco A | 7/7 (A.1 ordem do ledger; A.2 md5 dos corpos, invólucro e `binder_gap_move_pocket` inalterados; A.3 helper privado; A.4 ACL/`lock_timeout`; A.5 retornos; A.6 cobertura 14 funções; A.7 sem eventos) |
| Ledger | versões 20261027231843, …231909, …231944, …232019, …232052, …232123; md5(statements) = md5 do corpo enviado nas 6 |
| Security Advisor | nenhum achado novo atribuível: só `authenticated_security_definer_function_executable` das 5 funções já expostas a `authenticated` antes (ACL inalterada); o helper 5279 não aparece |
| Homologação funcional + bloco B | **pendente** (roteiro §31.7) |

### 31.10 Hotfix 5285 — colisão de nome em `remove_layout_page` (2026-10-27) — NO LIVE

Defeito da 5281 (no LIVE): a variável RECORD `r` do laço de renumeração colide com o alias `r` de `collection_layout_region` (corpo 5235/5260); `remove_layout_page(uuid, integer)` falha em toda chamada com 55000 `record "r" is not assigned yet` (log de 23:29:09 do Desfazer com página nova). Rollback atômico, sem dado corrompido.

Correção 5285: só `r → v_renum` nas 3 linhas acrescentadas pela 5281; resto byte a byte igual; 5281 preservada. Proteção estática nova: lint de colisão variável × alias em 5271–5285 (com controles negativos). Artefatos: `5285_fix_remove_layout_page_variable_collision.sql` (SHA-256 `ee787a7d…`, md5 prosrc `e4823996…`), `static_check_p3b_s4_5285.py` (17/17), `LIVE_S4_5285_checks_readonly.sql` (PRE 5/5 + informativo em 2026-10-27; POST Q.1–Q.5). Validação pós-aplicação: Desfazer sem e com página nova, remoção da página adicionada, bloco B de LIVE_S4_90 (R5).

**Aplicação no LIVE (2026-10-27, autorização expressa):** SHA-256 e static_check 17/17 conferidos; PRE 5/5 (janela quieta); `apply_migration` única, sem erro (ledger 20261027235513, md5(statements) = md5 do corpo enviado `0b4f4a2e…`); POST Q.1–Q.5 PASS; nenhum evento gravado pela instalação (máx. id 67); Security Advisor idêntico ao anterior (só os achados preexistentes de EXECUTE autenticado). Homologação pela interface (Desfazer sem/com página nova) e bloco B de LIVE_S4_90: pendentes.

### 31.11 Hardening 5286 — remove_layout_page: mínimo de páginas e bolso fixado (2026-10-27) — NO LIVE

Diagnóstico (LIVE, só leitura): 0 fichários com 1 página; 0 páginas vazias com cadeado; 0 referências de espécie de outra coleção. Riscos 1 e 2 reais no contrato (o banco aceitaria); risco 3 não procede como exclusão indevida: só a proprietária grava referências (5258) e as de outra coleção só existem como resíduo invisível de proprietária anterior, que a 5260 (ajuste B) decidiu apagar com a página — sem mudança.

5286: corpo da 5285 + recusas 4b (`layout has only N page(s) — a binder must keep at least one page`) e 5a (`page has N locked slot(s) — unlock them before deleting the page`), sob a trava 5122, antes de qualquer exclusão e de qualquer item E14. Contrato, E14, 5260 e ACL inalterados; close_my_binder_gap/insert_my_binder_gap não são afetados. Interface: `classifyPageRemovalFailure` reconhece as duas mensagens. Artefatos: `5286_harden_remove_layout_page.sql` (SHA-256 `6a57d21a…`, md5 prosrc `ed4215f4…`), `static_check_p3b_s4_5286.py` (15/15), `LIVE_5286_checks_readonly.sql` (PRE 5/5 em 2026-10-27; POST Q.1–Q.5).

**Aplicação no LIVE (2026-10-28 00:27 UTC, autorização expressa):** SHA-256 `6a57d21a…` e static_check 15/15 conferidos; PRE 5/5 (0 sessões ativas; última autenticação 48 min antes); `apply_migration` única, sem erro (ledger 20261028002709; md5(statements) = md5 do corpo enviado `225e9d52…`); POST Q.1–Q.5 PASS (md5 prosrc `ed4215f4…`; invólucro, insert/close e binder_gap_move_pocket inalterados; ACL preservada); nenhum evento gravado pela instalação (máx. id 78); Security Advisor idêntico ao anterior. Pendente para encerrar a S4: bloco B de LIVE_S4_90 (E11–E15 e R5) e promoção de 5279–5286 para `database/schema/`.

### 31.12 Encerramento da S4 (2026-10-28) — **PASS, com pendências residuais**

**Bloco B do LIVE_S4_90 (só leitura, execução única): B.1–B.9 PASS.** Eventos: PAGES_ADDED 2, GAP_OPENED 4, GAP_CLOSED 2, PAGE_REMOVED 3, PAGES_REORDERED 2 — cada um corresponde a uma operação feita pelo proprietário:

- páginas 41 e 42 adicionadas (E13);
- espaço simples aberto; espaço com página nova (p43) aberto antes da 5285;
- espaço de 4 cartas na p23 aberto e desfeito sem página nova (E11/E12 depois da 5285);
- espaço com página nova (p44) aberto e desfeito, com SHIFTED e PAGE_REMOVED da p44 **dentro** do GAP_CLOSED (R5 comprovada);
- duas reordenações (troca p25/p26 e volta) (E15);
- três remoções avulsas de página final (p43, p42, p41), sem renumeração (E14).

**Promoção:** 5279–5286 copiadas para `database/schema/` (só o bloco Status difere; corpo `begin;`…`commit;` conferido idêntico). A 5281 canônica registra o defeito e a substituição pela 5285, e esta pela 5286.

**Pendências residuais (sem PASS):**

| Item | Situação |
|---|---|
| PAGE_REMOVED com PAGE_RENUMBERED (remoção de página do meio) | não exercitado |
| SHIFTED de reserva e de imagem | só cartas exercitadas |
| Espaço que atravessa páginas sem página nova | não exercitado isoladamente |
| Recusas da 5286 (última página, bolso fixado) pelo banco | não exercitadas — a interface bloqueia antes |
| R-S4-1 (E16 interina) | restrição operacional vigente até a S6 |
| Concorrência e desempenho (H-A) | não medidos |

## 32. S5 — instrumentação de E06a, E06b e E07 (2026-10-28) — IMPLEMENTADA LOCALMENTE, NÃO APLICADA

### 32.1 Escopo e bases (conferidas no LIVE em 2026-10-28)

| Migration | Função | Base (md5 `prosrc` LIVE = canônico) | Evento / origem |
|---|---|---|---|
| 5287 | `set_physical_cards_storage(uuid,uuid[],boolean)` | 5249 `c68a460c…` | E06a `CARDS_LEFT_BY_STORAGE` / ACERVO |
| 5288 | `organize_my_collection_storage(uuid,uuid,text,integer,text,boolean)` | 5249 `083dc242…` | E06b `CARDS_LEFT_BY_COLLECTION_STORAGE` / COLECAO |
| 5289 | `remove_my_physical_card(uuid)` | 5165 `1322db02…` | E07 `CARD_LEFT_BY_INVENTORY_EXIT` / ACERVO |

Nenhum helper novo: os itens usam a 5271 (`CARD/LEFT`, origem = bolso).

**Correção da matriz §4.1:** as sobrecargas antigas — `set_physical_cards_storage(uuid,uuid[])` (5024) e `organize_my_collection_storage` de 5 argumentos (5222) — **não delegam** às novas. Também não tiram carta de bolso: exemplar posicionado que muda de local é recusado pela guarda 5256. Por isso não são instrumentadas. O frontend só chama as sobrecargas com confirmação.

Premissas conferidas no LIVE (LIVE_S5_00 00.4):

- só as duas funções da 5249 apagam bolso ao mudar o local;
- só a 5165 exclui exemplar;
- o bolso cai em cascata com o exemplar;
- cada exemplar ocupa no máximo um bolso.

E07 é real: 8 bolsos guardam exemplar sem alocação, e a remoção desse exemplar apaga o bolso.

### 32.2 Pontos de instrumentação (linhas `-- P3B-S5`)

- **E06a / E06b:** dentro do `if v_pos > 0` (saída confirmada), antes do `DELETE`, há um laço por fichário afetado: begin → itens em ordem página/linha/coluna → end. O predicado é o mesmo do `DELETE`, e as posições já estão travadas pela função (`for update` / `NOWAIT`). O end de cada fichário vem antes do begin do seguinte, porque a 5268 recusa operação aninhada em outro fichário.
- **E07:** a posição é lida e travada (`for update of a`) antes da exclusão do exemplar, na mesma ordem de travas da cascata. Begin e item são gravados antes do `DELETE`, enquanto o exemplar ainda existe para a cópia da carta. O end fica imediatamente antes do `RETURN true`. As três chamadas são condicionadas por `WHERE v_act_layout IS NOT NULL`: exemplar fora do fichário não faz nenhuma chamada e não gera evento.

### 32.3 Convenções — **a confirmar pelo proprietário**

- **Um evento por fichário afetado.** O histórico é por fichário; mover cartas de dois fichários numa só ação gera dois eventos na mesma transação.
- **Itens.** Cada exemplar que sai gera um item `CARD/LEFT` com origem no bolso e sem destino.
- **Resumo de E06a/E06b.** Guarda o destino copiado no momento (`storage_container_id`, `storage_container_name`; ambos nulos quando o exemplar fica sem local).
- **Coleção do evento.** Em E06b, é a coleção organizada (D8), mesmo quando o fichário pertence a outra coleção do mesmo dono. Em E06a e E07, não há coleção.
- **Bolso fixado em E07.** Não impede a saída, porque a trava aceita a cascata do acervo (5248); a saída é registrada.

### 32.4 Integridade, segurança e performance

- **Integridade:**
  - diff mínimo provado por md5;
  - W3 I-1..I-6 cumprido (begin textual único);
  - I-10 cumprido: itens antes do `DELETE`, com o mesmo predicado;
  - assinaturas, retornos, mensagens, travas e ACL preservados;
  - erro depois do begin desfaz evento e mudança juntos;
  - sem efeito, sem evento.
- **Segurança:** a titularidade é verificada pela 5268 (`auth.uid()` = dono do fichário). EXECUTE continua só para `authenticated`.
- **Performance (não medida):**
  - itens = exemplares posicionados que saem (≤ 500 em E06a; ≤ capacidade dos fichários em E06b; 1 em E07);
  - por fichário, 2 leituras indexadas a mais;
  - por item, leituras por chave;
  - o teto W1 cobre.

### 32.5 Riscos

| # | Risco | Tratamento |
|---|---|---|
| R-S5-1 | Organizar a guarda de coleção grande (até 10.000 exemplares) com muitos posicionados gera evento grande | Itens limitados pela capacidade do fichário (W1); desempenho não medido (H-A) |
| R-S5-2 | Concorrência | Herdada das travas existentes; E07 passa a travar a posição antes da exclusão (mesma ordem da cascata) |
| R-S5-3 | Sobrecargas antigas executáveis por `authenticated` | Não tiram carta de bolso (5256); fora do histórico por construção |

### 32.6 Artefatos (SHA-256)

| Arquivo | SHA-256 |
|---|---|
| 5287_instrument_set_physical_cards_storage.sql | `d9ecfe6b…` |
| 5288_instrument_organize_my_collection_storage.sql | `4bbfc3d7…` |
| 5289_instrument_remove_my_physical_card.sql | `db411b40…` |
| static_check_p3b_s5.py | `87e53128…` |
| LIVE_S5_00_precheck_readonly.sql | `b4987fce…` |
| LIVE_S5_90_postcheck_readonly.sql | `7fdfe668…` |

`static_check_p3b_s5.py`: **44/44 PASS**. Cobre:

- diff mínimo, cabeçalho, W3, tipos e efeitos, ACL e precheck;
- lint de colisão;
- I-10 por predicado;
- laço por fichário;
- E07 condicionado;
- sobrecargas antigas não recriadas;
- 5 mutações negativas;
- regressões S1 65/65, S2 30/30, S3 31/31, S4 51/51, 5285 17/17 e 5286 15/15.

**LIVE_S5_00 em 2026-10-28 (só leitura): 7/7 true + informativo** (357 bolsos com carta; 8 sem alocação; máx. evento 78). Bloco B do LIVE_S5_90 conferido só por `EXPLAIN`.

### 32.7 Gate da S5

| Critério | Estado |
|---|---|
| static_check S5 | **44/44 PASS** |
| LIVE_S5_00 | 7/7 em 2026-10-28 (renovar no dia) |
| Convenções §32.3 confirmadas | pendente |
| Validação dinâmica ou H-A para a S5 | pendente |
| Autorização expressa para aplicar 5287–5289 (nessa ordem) | pendente |
| Pós: LIVE_S5_90 bloco A 7/7; ledger 3/3 md5; Advisor | — |
| Homologação: bloco B (E06a com ≥ 2 exemplares; E06b com posicionados; E07) + regressão de Meu acervo e Meus locais | — |

### 32.8 Instalação da S5 no LIVE (2026-10-28) — autorização operacional do proprietário

Decisões aprovadas: convenções §32.3 (um evento por fichário; um item por exemplar; destino no resumo; coleção organizada no evento; saída de bolso fixado por exclusão do exemplar registrada); H-A só para a S5.

| Etapa | Resultado |
|---|---|
| SHA-256 dos artefatos (§32.6) e static_check S5 | conferidos; 44/44 PASS |
| LIVE_S5_00 (renovado) | 7/7 + informativo (357 bolsos com carta; 8 sem alocação; máx. evento 78) |
| Janela quieta | 0 sessões cliente ativas; 0 transações ociosas; última autenticação 2 h 14 min antes |
| `apply_migration` 5287 → 5289 | 3/3 sucesso, sem erro, sem repetição |
| Ledger | 20261028005513, …005559, …005621; md5(statements) = md5 do corpo enviado nas 3 (`dead6e1c…`, `d173c9d1…`, `088cef86…`) |
| LIVE_S5_90 bloco A | 7/7 (ordem do ledger; md5 dos corpos `09e342a1…`/`26ea92ac…`/`d51b9264…`; sobrecargas 5024/5222 inalteradas; DEFINER/search_path/ACL/`lock_timeout`; retornos; cobertura 17 funções; nenhum evento gravado; guarda 5256 ativa) |
| Security Advisor | nenhum achado novo: só o WARN preexistente `authenticated_security_definer_function_executable` das funções já expostas a `authenticated` (ACL inalterada) |
| Homologação funcional + bloco B | **pendente** |

**Roteiro de homologação (pela interface, operações reais do proprietário):**
- **E06a** — Meu acervo: selecionar ≥ 2 exemplares que estão em bolsos do fichário (bolsos não fixados) e movê-los para outro local, confirmando a saída dos bolsos. Opcional: exemplares de dois fichários diferentes na mesma ação (prova "um evento por fichário").
- **E06b** — Coleção com local padrão definido → Organizar armazenamento, com ao menos um exemplar elegível posicionado no fichário, confirmando na prévia.
- **E07** — só se houver um exemplar realmente cadastrado por engano, fora de coleção e ainda num bolso (8 nessa situação): removê-lo em Meu acervo. Sem exclusão real, E07 fica registrado como não exercitado.
- **Regressão:** Meu acervo (mover sem fichário, remover exemplar fora de bolso) e Meus locais devem seguir idênticos; sem confirmação, a recusa `BINDER_POSITION_CONFIRMATION_REQUIRED` continua.

### 32.9 Homologação e encerramento da S5 (2026-10-28) — **PASS para E06a; E06b e E07 não testados**

Bloco B do LIVE_S5_90 (só leitura, execução única): **B.2–B.7 PASS**; **B.1 = false apenas por cobertura** (o instrumento exige os três tipos; só E06a ocorreu) — limitação registrada, nenhum dado alterado e nenhum critério enfraquecido.

| Evento | Comprovação |
|---|---|
| 79 CARDS_LEFT_BY_STORAGE (ACERVO) | Exeggcute, p1 l1 c1 → "Local padrão"; 1 item CARD/LEFT; fichário "Celebração de 30 Anos - Clasic Collection" |
| 80 CARDS_LEFT_BY_STORAGE (ACERVO) | Exeggutor de Alola, p1 l2 c1 → "Local padrão"; 1 item CARD/LEFT |

Dois movimentos individuais (transações distintas, 14 s) → um evento cada, como previsto. Ator = titular; origem preenchida, sem destino; cópia da carta e exemplar no detalhe; destino copiado no resumo; sem duplicidade; nenhum evento de bolso extra na mesma transação. Depois disso o proprietário recolocou as duas cartas nos mesmos bolsos pela interface (eventos 81/82 CARD_PLACED, FICHARIO, destino p1 l1 c1 / p1 l2 c1) — **evidência dinâmica do ADD pela interface, pendente da S2 (§29.11)**.

**Promoção:** 5287–5289 copiadas para `database/schema/` (só o bloco Status difere; corpo `begin;`…`commit;` idêntico).

**Pendências residuais (sem PASS):** E06b (organizar armazenamento com posicionados) e E07 (remoção de exemplar fora de coleção ainda em bolso) não exercitados dinamicamente — sem exemplares elegíveis e sem alteração artificial; vários fichários na mesma ação (um evento por fichário) não exercitado; concorrência e desempenho não medidos (H-A).

## 33. S6 — instrumentação de E01, E16–E20 (2026-10-28) — IMPLEMENTADA LOCALMENTE, NÃO APLICADA

### 33.1 Escopo e bases (conferidas no LIVE em 2026-10-28)

| Migration | Função | Base (md5 `prosrc` LIVE) | Evento |
|---|---|---|---|
| 5290 | `attach_my_collection_to_binder(uuid,uuid)` | 5255 `1b87933c…` | E17 `COLLECTION_ATTACHED` |
| 5291 | `detach_my_collection_from_binder(uuid,text,boolean)` | 5253 `09570bf9…` | E18 `COLLECTION_DETACHED` |
| 5292 | `transfer_my_binder_ownership(uuid,uuid)` | 5254 `4755a772…` | E20 `BINDER_OWNERSHIP_TRANSFERRED` |
| 5293 | `delete_collection_layout(uuid)` | 5124 `1b4bf897…` | E19b `BINDER_DELETED_EMPTY` |
| 5294 | `dismantle_my_collection_binder(uuid,text)` | 5242 — corpo LIVE `6aa90085…` | E19 `BINDER_DISMANTLED` |
| 5295 | `create_my_collection_binder(uuid,int,int,text,text)` | 5224 `5ba7941f…` | E01 `BINDER_ASSEMBLED` |
| 5296 | `apply_my_binder_catalog_reconciliation(uuid,text[],text,bool,bool)` | 5266 `aa58b231…` | E16 `CATALOG_NOVELTIES_INCORPORATED` |

Nenhum helper novo (5271, 5275, 5279 cobrem carta, reserva e deslocamento). **Achado documental (sem efeito funcional):** o corpo LIVE de `dismantle_my_collection_binder` não tem os comentários `--` da canônica 5242 (md5 normalizado igual; mesmo fenômeno da 5243 na S4); a S6 usa o corpo do LIVE como base. **Caminhos na interface:** E01, E16, E17, E18 e E20 têm ação no aplicativo; **E19 e E19b não têm caminho na interface atual** (homologação dinâmica só quando houver).

### 33.2 Pontos de instrumentação (linhas `-- P3B-S6`)

- **Idempotência antes do begin (C-206):** ALREADY_ATTACHED, ALREADY_DETACHED, UNCHANGED, ALREADY_ABSENT, ALREADY_EXISTS, NOTHING_TO_DO e ALREADY_APPLIED saem sem gravar.
- **Saídas (origem) antes das escritas destrutivas (I-10):** E18 (bolsos soltos e reservas da convidada, mesmos predicados do UPDATE/DELETE), E19 (cartas, reservas e encerramento antes de qualquer exclusão — o cabeçalho e as posições leem o fichário), E19b (item antes do DELETE).
- **Entradas (destino) depois das escritas:** E01 (páginas, cartas e reservas depois da conferência), E16 (SHIFTED logo após cada movimento da cadeia; reserva nova depois do INSERT; conversão depois do UPDATE), E17 e E20 (marco depois da associação/troca).
- **R5 na E16:** a página nova chamada por `add_layout_page` (S4) entra como item PAGE_ADDED do evento externo — **encerra R-S4-1** quando aplicada.
- **E20 (§14.7):** só begin/add_item/end; UNCHANGED, assinatura, erros, travas e a exceção controlada da 5136 inalterados.

### 33.3 Convenções — **a confirmar pelo proprietário**

| Evento | Coleção do evento | Itens |
|---|---|---|
| E17 | convidada | 1 COLLECTION/ATTACHED |
| E18 | convidada | POCKET/UNLOCKED por bolso solto; RESERVATION/RELEASED por reserva; 1 COLLECTION/DETACHED (posições de cartas permanecem — 5253) |
| E20 | destino | 1 BINDER/TRANSFERRED {origem, destino} |
| E19b | — | 1 BINDER/CLOSED {reason: EMPTY} |
| E19 | proprietária | CARD/REMOVED por carta; RESERVATION/RELEASED por reserva; 1 BINDER/CLOSED {reason: DISMANTLED}; resumo: páginas, bolsos, regiões, cadeados |
| E01 | montada | PAGE/PAGE_ADDED por página; CARD/PLACED por carta; RESERVATION/RESERVED por reserva; resumo: grade, política e extras fora |
| E16 | reconciliada (origem CATALOGO) | SHIFTED por objeto deslocado (repetição permitida, I-7/W1); PAGE_ADDED da página embutida; RESERVATION/RESERVED por reserva nova; RESERVATION/INCORPORATED por reserva genérica convertida |

### 33.4 Integridade, segurança e performance

Diff mínimo por md5; W3 I-1..I-6; begin textual único antes de toda gravação; erro depois do begin desfaz evento e operação (I-3); assinaturas, retornos, mensagens, travas e ACL preservados. Titularidade verificada pela 5268. **Performance (não medida):** E01 até 2·S + P itens (cópia por chave; teto recalculado a cada PAGE_ADDED); E16 ≤ 500 deslocamentos com repetição + 100 reservas + páginas (folga W1 600); E19 ≤ 2·S + 1; demais 1–S+1.

### 33.5 Riscos

| # | Risco | Tratamento |
|---|---|---|
| R-S6-1 | E19/E19b sem caminho na interface → sem homologação dinâmica | Estático + I10 por inspeção; harness 5860 opcional |
| R-S6-2 | E16 exige novidades reais do Catálogo para homologar | Homologar quando houver novidade; até lá, PASS só estrutural |
| R-S6-3 | Montagem de fichário grande gera evento grande (≤ 2·S + P itens) | Dentro do W1; desempenho não medido (H-A) |
| R-S6-4 | Concorrência | Herdada das travas existentes; nenhuma trava nova |

### 33.6 Artefatos (SHA-256)

| Arquivo | SHA-256 |
|---|---|
| 5290_instrument_attach_my_collection_to_binder.sql | `87dc57e2…` |
| 5291_instrument_detach_my_collection_from_binder.sql | `21fce724…` |
| 5292_instrument_transfer_my_binder_ownership.sql | `dfc1cb63…` |
| 5293_instrument_delete_collection_layout.sql | `4eb4b95b…` |
| 5294_instrument_dismantle_my_collection_binder.sql | `cb9ce0bb…` |
| 5295_instrument_create_my_collection_binder.sql | `3a42d9fd…` |
| 5296_instrument_apply_my_binder_catalog_reconciliation.sql | `5bb0c173…` |
| static_check_p3b_s6.py | `b889ba4d…` |
| LIVE_S6_00_precheck_readonly.sql | `c8cc8cd8…` |
| LIVE_S6_90_postcheck_readonly.sql | `7172194a…` |

`static_check_p3b_s6.py` **82/82 PASS** (diff mínimo, cabeçalho, W3, tipos/origens/efeitos, ACL, precheck, ordem por evento, lint, 5 mutações negativas, regressões S1–S5). **LIVE_S6_00 em 2026-10-28 (só leitura): 6/6 + informativo** (3 fichários, 1 convidada, máx. evento 82).

### 33.7 Gate da S6

| Critério | Estado |
|---|---|
| static_check S6 | **82/82 PASS** |
| LIVE_S6_00 | 6/6 em 2026-10-28 (renovar no dia) |
| Convenções §33.3 confirmadas | pendente |
| Validação dinâmica (harness 5859/5860, previsto em §11) ou H-A para a S6 | pendente |
| Autorização expressa para aplicar 5290–5296 (nessa ordem) | pendente |
| Pós: LIVE_S6_90 bloco A 6/6; ledger 7/7 md5; Advisor | — |
| Homologação: bloco B (E17, E18, E20, E01 e E16 pela interface quando houver caso real; E19/E19b sem caminho) | — |

### 33.8 Gate final da S6 (2026-10-28) — PRONTA, aguardando autorização expressa

Decisões do proprietário: plano original mantido; **H-A para a S6** (harnesses 5859/5860 dispensados no LIVE); nenhuma operação destrutiva artificial; caminhos sem interface (E19, E19b) e sem caso real (E16) ficam **não testados**.

| Verificação | Resultado |
|---|---|
| SHA-256 dos 10 artefatos (§33.6) | conferidos, sem alteração |
| static_check S6 | 82/82 PASS |
| LIVE_S6_00 (renovado, 21:46 UTC) | 6/6 + informativo (3 fichários, 1 convidada, máx. evento 82) |
| Janela | 0 sessões cliente ativas; 0 transações ociosas; última autenticação há ~23 h |
| FKs do evento | só titular → auth.users (cascata da conta); nenhuma FK para fichário ou coleção → E19/E19b não apagam histórico |
| Convenções §33.3 | **sem divergência material**: autoria pelo ator validado (5268); coleção de origem e destino da E20 no detalhe; E18 registra também os cadeados soltos (aditivo, coerente com a S3); E19 itemiza cartas e reservas (imagens/regiões só no resumo de contagens) |

Execução preparada: 5290 → 5296 via `apply_migration`, uma a uma, corpo sem `begin;`/`commit;`, conferência do ledger após cada uma, STOP no primeiro erro; depois LIVE_S6_90 bloco A, ledger 7/7 md5 e Security Advisor. **Não aplicada: falta a autorização expressa.**

### 33.9 Instalação no LIVE (2026-10-28) — INSTALADA, homologação funcional pendente

Autorização expressa do proprietário para 5290–5296. Gate §33.8 válido (mesma sessão, hashes inalterados; a reexecução do static_check estourou o limite de tempo do sandbox — arquivos byte-idênticos à execução 82/82, conferidos por SHA-256). Aplicação uma a uma via `apply_migration`, sem erro, sem repetição.

| Migration | Ledger | md5(statements) = md5 do corpo | md5(prosrc) |
|---|---|---|---|
| 5290 attach | 20261028215521 | 95d94417… | 20a8a252… |
| 5291 detach | 20261028215554 | cd767e4a… | 535e7b78… |
| 5292 transfer | 20261028215622 | 1e259ff9… | d501c1e8… |
| 5293 delete_collection_layout | 20261028215642 | 556c07d7… | 28e9cc29… |
| 5294 dismantle | 20261028215721 | a3beae78… | ec946297… |
| 5295 create binder | 20261028215809 | 577cd6b5… | 332eb949… |
| 5296 apply novidades | 20261028215957 | 1cf368f2… | 0f25fc93… |

| Pós-verificação | Resultado |
|---|---|
| LIVE_S6_90 bloco A | 6/6 true (ordem do ledger, corpos, DEFINER/search_path/grants/lock_timeout, retornos, cobertura 24 funções, nenhum evento S6 criado pela instalação) |
| Ledger | 7/7, na ordem, depois da 5289 |
| Security Advisor | sem categoria nova; as 7 funções aparecem só em `authenticated_security_definer_function_executable` (classe preexistente e esperada: RPCs do proprietário) |

Homologação disponível pela interface (ações reais do proprietário, nenhuma executada pelo agente): **E01** montar fichário; **E17** usar fichário existente; **E18** desassociar; **E20** transferir propriedade; **E16** só com novidade real do Catálogo. **E19/E19b** sem caminho de interface → não testados. Depois: LIVE_S6_90 bloco B (só leitura).

### 33.10 Pós-check funcional (2026-10-28) — PASS parcial (E01) · STOP (E17, E18, E20)

LIVE_S6_90 bloco B executado sem alteração, só leitura:

| Linha | Resultado |
|---|---|
| B.1 cobertura | `BINDER_ASSEMBLED=1` — nenhum COLLECTION_ATTACHED, COLLECTION_DETACHED ou BINDER_OWNERSHIP_TRANSFERRED |
| B.2–B.7 | true (avaliam só o evento existente) |
| B.8 | evento 83 · 28/10 19:07:20 · BINDER_ASSEMBLED · "Caos Ascendente" · 220 itens |

**E01 comprovado (evento 83):** ator = titular; origem FICHARIO; coleção "Caos Ascendente"; 22 PAGE_ADDED (páginas 1–22) + 198 RESERVED, sem PLACED (0 posições no fichário recém-montado, conferido no LIVE); 198 reservas no fichário hoje = 198 itens; resumo com grade 3×3, `PRINCIPAL_ONLY`, 0 extras; ordinais contíguos; sem duplicidade; nenhum outro evento S6 no mesmo fichário. Em seguida, 18 eventos PAGES_ADDED independentes (84–101, 22:07:41–44), um por chamada a `add_layout_page` — comportamento da S4, coerente (o fichário tem 40 páginas).

**Divergência material E17/E18/E20:** relatados como executados, mas (a) não há evento; (b) os logs da API das últimas 24 h não registram nenhuma chamada a `attach_my_collection_to_binder`, `detach_my_collection_from_binder` ou `transfer_my_binder_ownership` — só `preview_my_collection_binder_detach` (prévia, sem gravação) às 22:06, 22:08 e 22:09 UTC; (c) o estado bate com o anterior (a única convidada continua "Coleção Clássica" em "Celebração de 30 Anos"; nenhuma proprietária mudou). As actions do frontend chamam essas RPCs (`fichario/actions.ts`). Conclusão: falha de cobertura, não funcional — as operações não chegaram ao banco (provavelmente paradas na prévia). Nenhum critério do instrumento alterado.

Decisão: S6 **não** encerrada; 5290–5296 **não** promovidas. Pendente: refazer pela interface Usar fichário existente (E17), Desassociar em Ajustes até a confirmação (E18) e Transferir (E20); reexecutar o bloco B. E16, E19, E19b continuam não testados.

### 33.11 Verificação de evidências recentes (2026-10-28, só leitura) — S6 continua aberta

| Verificação | Resultado |
|---|---|
| "Coleção associada" ~17:10 na captura | **Não é do LIVE.** O texto e o horário são dados fictícios das prévias estáticas da S7 (`historico-activity-log.html`, `historico-v4.html`, item "Coleção associada · 17:10"). O LIVE não tem nenhum `COLLECTION_ATTACHED` |
| Bloco B (sem alteração) | B.1 `BINDER_ASSEMBLED=1`; B.2–B.7 true (só avaliam o evento 83); nenhum E17/E18/E20/E16/E19/E19b |
| Eventos desde o pós-check | 102 e 103 `CARDS_SWAPPED` (S2), ator = titular; maior id 103, uma lacuna antiga (63, de 27/10, anterior à S6) |
| Chamadas às RPCs (logs da API, 24 h) | 0 a `attach_my_collection_to_binder`, `detach_my_collection_from_binder` e `transfer_my_binder_ownership`; 10 a `preview_my_collection_binder_detach` (só prévia) |
| Convidada existente | "Coleção Clássica" em "Celebração de 30 Anos", criada em 2026-10-23 — antes da 5290 (2026-10-28 21:55 UTC); por isso sem E17 |

**Caminho exato para E18 (desassociar) — reversível, sem perda de cartas:** Coleções → "Coleção Clássica" → Ajustes → seção "Fichário compartilhado" → "Sair do fichário compartilhado" → painel de confirmação → "Sair do fichário" (botão vermelho). Estado lido agora: 0 reservas, 0 bolsos fixados (sem caixa de confirmação de cadeados); as 7 cartas posicionadas permanecem nos bolsos (5253, D2). Efeito esperado: 1 evento `COLLECTION_DETACHED` com 1 item COLLECTION/DETACHED.

**Caminho exato para E17 (associar), logo depois do E18:** Coleções → "Coleção Clássica" → no topo, cartão "Fichário digital" com "Usar fichário existente" → diálogo → "Usar o fichário de Celebração de 30 Anos". (Alternativa: rota `/fichario` da coleção → mesmo botão.) Pré-condição satisfeita depois do E18: coleção ativa, local padrão F001 (BINDER), 1 candidato. Efeito esperado: 1 evento `COLLECTION_ATTACHED` com 1 item COLLECTION/ATTACHED; o estado volta ao de hoje.

**E20 sem caminho na interface:** a action `transferBinderOwnership` existe (`fichario/actions.ts`), mas nenhum componente a chama. Não há como o proprietário exercitá-lo sem criar interface nova ou chamar a RPC fora do app. Classificação proposta: **não exercitado dinamicamente (sem caminho)**, como E19/E19b — instrumentação provada só por inspeção (§14.7, static_check 82/82, md5 do bloco A). Decisão do proprietário.

Parecer: S6 **não encerrada**; 5290–5296 **não promovidas**. Encerramento: E17 e E18 comprovados no bloco B + aceite de E20 como não exercitado.

### 33.12 Pós-check funcional final (2026-10-28) — S6 ENCERRADA (PASS PARCIAL)

LIVE_S6_90 bloco B, só leitura, sem alteração: B.1 `BINDER_ASSEMBLED=1, COLLECTION_ATTACHED=1, COLLECTION_DETACHED=1`; B.2–B.7 true.

| Evento | Resultado |
|---|---|
| 104 `COLLECTION_DETACHED` (E18), 28/10 21:15:20 | ator = titular; origem FICHARIO; coleção "Coleção Clássica" (id confere); fichário "Celebração de 30 Anos - Clasic Collection" (layout `0d550088…`); 1 item COLLECTION/DETACHED com `collection_id` correto; sozinho na transação; 0 reservas e 0 bolsos fixados no estado anterior, logo sem RELEASED/UNLOCKED — coerente |
| 105 `COLLECTION_ATTACHED` (E17), 28/10 21:17:04 | ator = titular; mesma coleção e mesmo layout; 1 item COLLECTION/ATTACHED; sozinho na transação |
| Estado final | "Coleção Clássica" novamente convidada do mesmo layout; 7 posições preservadas (5253, D2); maior id 105; sem duplicidade |
| Integridade | ledger 5290–5296 na ordem; md5 dos 7 corpos no LIVE = proposta = `database/schema/` |

Cobertura: E01, E17, E18 **comprovados**. E16: prévia validada, incorporação **não executada**. E19, E19b, E20: implementados, **sem caminho no frontend** — não exercitados. Promoção: 5290–5296 copiadas para `database/schema/` (só o bloco Status difere, padrão da S5).

## 34. S7 — seção Histórico (frontend) (2026-10-28) — IMPLEMENTADA LOCALMENTE, NÃO PUBLICADA

Decisões do proprietário: S7 local sem esperar a homologação de E17/E18/E20; S6 continua aberta; publicação futura admite cenários implementados e não exercitados com avaliação explícita de risco (ausência de evidência ≠ PASS); páginas adicionadas seguem como eventos individuais (sem agrupamento D6). Nenhuma migration, SQL de escrita, deploy ou Git.

### 34.1 Arquivos

| Arquivo | Conteúdo |
|---|---|
| `web/lib/colecoes/binder-activity.ts` (novo) | Regras puras: parse fail-closed das linhas da 5269, categorias e filtros (§3.3), frases pt-BR dos 24 tipos e dos itens, agrupamento por dia (America/Sao_Paulo), cursor e junção sem duplicar, nota de cobertura, truncamento honesto (contagens por efeito só com a lista completa) |
| `web/lib/colecoes/binder-activity.test.ts` (novo) | 13 testes (`node --experimental-strip-types --test`) |
| `web/app/colecoes/colecoes/[id]/fichario/actions.ts` | `readBinderActivity` (`get_my_binder_activity`, 20 por vez, cursor) e `readBinderActivityCoverage` (`get_my_binder_activity_coverage`) — só leitura, entrada validada, log sem dados do usuário |
| `web/components/colecoes/fichario/binder-history.tsx` (novo) | Seção: filtros `aria-pressed`, `ol` por dia com `time datetime`, "Ver detalhes" `aria-expanded`, "Mostrar mais" com anúncio educado sem mover o foco, estados carregando / erro + Tentar de novo / vazio / filtro sem resultado / fim + início da cobertura |
| `binder-control.tsx` / `binder-control.module.css` | Seção "Histórico" depois de Informações, mesmo `Section` e persistência de recolhimento; montada só aberta; alvos de 44 px em toque; sem animação nova |
| `binder-identity.ts` | `CONTROL_SECTIONS` + `history` (preferências antigas continuam válidas) |
| `binder-workspace.tsx` | `activityVersion` incrementado após cada releitura pós-escrita (`refreshPages`) → o Histórico relê a 1ª página em silêncio e junta só o que é novo |

### 34.2 Contratos preservados

Nenhuma função, permissão ou tabela nova; leitura owner-scoped pela própria 5269 (chave alheia ou inexistente → lista vazia). Centro de Controle: Identidade, Organização e Informações inalterados.

### 34.3 Verificação

| Item | Resultado |
|---|---|
| `binder-activity.test.ts` | 13/13 PASS |
| `binder-identity.test.ts` (regressão) | 20/20 PASS |
| `npm run typecheck` (`tsc --noEmit`) | limpo (`tsconfig.tsbuildinfo` restaurado depois) |
| `git diff --check` em `web/` | limpo |
| lint / build | não executáveis no sandbox — pendentes na máquina do proprietário |
| Visual (temas, 375/768/1280, teclado, leitor de tela, movimento reduzido) | pendente — §34.4 |

### 34.4 Homologação visual (proprietário)

Fichário "Caos Ascendente" (tem E01 + 18 páginas adicionadas) → Centro de Controle → Histórico: (1) lista "Hoje" com "Fichário montado" e "Página N adicionada"; (2) Ver detalhes do E01 mostra a nota "Mostrando 50 de 220…"; (3) filtros Fichário/Páginas/Cartas (vazio em Cartas); (4) Mostrar mais até "Histórico registrado a partir de…"; (5) fazer uma mudança no fichário com a seção aberta → nova linha aparece; (6) recolher/reabrir a seção e recarregar a página (preferência mantida); (7) 375/768/1280 px, claro e escuro, só teclado (Tab, Enter/Espaço), leitor de tela e movimento reduzido. Rodar `npm run lint` e `npm run build`.

### 34.5 Publicação (registro de riscos residuais)

Exercitados no LIVE: E01–E05, E06a, E08–E15, L01. Implementados e não exercitados dinamicamente: E06b, E07, E16, E19, E19b; E17, E18 e E20 aguardando confirmação (§33.10); REPLACE da S2. Risco residual dessas linhas é de apresentação (frase/itens) e não de segurança — a leitura é a mesma para todos os tipos; cada uma tem frase coberta por teste unitário. A decisão de publicar fica com o proprietário sobre esta lista.

### 34.6 Refinamento visual (2026-10-28) — timeline compacta

Só apresentação; leituras, filtros, paginação, privacidade e atualização automática inalterados.

- Resumo por evento (`summarizeEvent`, novo em `binder-activity.ts`): **sujeito** (carta, nº de cartas/bolsos, página, fichário, coleção — 12,5 px, peso 500) + **ação/local** curtos em texto secundário (12 px), **hora** à direita (11 px, tabular). Ex.: "Mega Darkrai ex · 120 · Movida · p. 3 → p. 5". Páginas não são inferidas de lista truncada.
- Detalhes: seta discreta (20 px visível, área de toque 44 px via `::after`), `aria-expanded` + `aria-controls` e rótulo acessível com o resumo e a hora. A expansão mostra a frase completa (`describeEvent`: linha/coluna, acabamento), o contexto, os itens e a nota de truncamento — nada da versão anterior foi perdido.
- Ícones 13 px monocromáticos sem fundo; divisores de 1 px a 30 % de opacidade; espaçamento vertical de 6 px.
- Filtros: chips de 24 px visíveis com área de clique de 44 px de altura; ativo em neutro (sem dourado). Selo de legado em linha própria, compacto.
- Sem truncamento por reticências: textos longos quebram linha.
- Temas: o Centro de Controle é escuro nos dois temas por desenho (classe `dark` no painel) — a seção herda os mesmos tokens em claro e escuro.
- Verificação: `binder-activity.test.ts` 14/14 (novo teste do resumo para os 24 tipos); typecheck limpo; prévia estática do CSS real em 375 e 352 px (largura do painel em 768/1280) conferida por captura. Homologação no app pendente com o proprietário.

### 34.7 Activity Log minimalista (2026-10-28) — substitui a apresentação de §34.6

Só apresentação/redação; contratos de leitura, filtros, paginação, privacidade e atualização automática inalterados; sem D6.

- Lista: `[ícone 13 px] [manchete] [hora 11 px tabular] [chevron]`, uma linha (~30 px; 44 px com `pointer: coarse`), reticências no texto longo (texto integral no DOM para leitor de tela e em `title`), sem divisores; linha-guia vertical de 1 px ligando os ícones de cada dia; linha inteira é um botão `aria-expanded`/`aria-controls`; hover/active/focus discretos; chevron gira (sem animação com movimento reduzido).
- Manchetes (`headlineEvent`, 24 tipos, ≤ 40 caracteres sem o nome da carta): "Exeggutor de Alola movida", "7 cartas retiradas", "Página 41 removida", "Páginas reordenadas", "Reserva criada", "Bolso fixado", "Fichário montado", "Coleção associada". Totais de eventos coletivos vêm de `item_count` (nunca da lista truncada).
- Detalhes (`detailFields` + `detailItems`): Ação (frase completa), Carta (nome · nº · Set · acabamento), De/Para, Coleção, Fichário, Destino, Observação, Por, Quando (data e hora completas), Itens (N) e aviso de truncamento. "Por" = "Você" (V1: o executor é sempre o titular, §3.2/B.2; a 5269 só devolve eventos do titular) e "Não registrado" no legado — nenhum campo inventado.
- Filtro: seletor nativo do Design System (`Select`) "Mostrar: Todas as atividades / Cartas / Reservas / Fixação / Páginas / Catálogo / Fichário" — menos protagonismo que 7 chips, teclado/leitor de tela nativos, 44 px em telas pequenas.
- Verificação: `binder-activity.test.ts` 15/15; typecheck limpo; captura da prévia estática do CSS real. Avaliação no app real pendente com o proprietário (o sandbox não executa `next dev/build`).

### 34.8 Fidelidade visual (2026-10-28)

Diferenças encontradas entre a prévia e a renderização real, e correções (só apresentação):

| Item | Causa | Correção |
|---|---|---|
| Ícones que pareciam "quadrados vazios" | Escolha de ícones de contorno quadrado (`SquarePlus`, `SquareMinus`, `Rows3`, `FilePlus2` para remoção) que a 13 px viram caixas; a prévia usava um marcador genérico | Ícones lineares abertos do `lucide-react` já usado: Plus, Minus, ArrowRight, ArrowLeftRight, LogOut, Bookmark/BookmarkMinus, Lock/LockOpen, FilePlus2/FileMinus2 (novo tipo `pageRemove`), MoveHorizontal, ListOrdered, Sparkles, BookOpen, Link2/Unlink, Repeat, Archive; traço 1,75; sem fundo visível |
| Texto mais "pesado" no app | Fonte real (Inter) com x-height maior que a da prévia (system-ui) a 12,5 px e cor plena | 12 px, peso 400, cor 82 % |
| Hora | 11 px | 10,5 px, coluna de largura mínima fixa, alinhada à direita, tabular |
| Separadores de dia longos | "27 de outubro" | `HOJE`, `ONTEM`, `27 OUT`, `27 OUT 2025` (maiúsculas por CSS, 10 px, peso 500); `<time datetime>` + `aria-label` com a data completa |
| Data nos detalhes | "28 de outubro de 2026, 21:42" | `28 out 2026 · 21:42` (America/Sao_Paulo) |
| Coluna do ícone/chevron | 22 px / 12 px | 18 px / 10 px → mais largura para a descrição |
| Detalhes densos | Fundo 3,5 %, rótulo 68 px, itens com mesmo peso dos campos | Fundo 2,5 %, rótulo 64 px a 75 %, valores 85 %, itens 10,5 px a 72 % separados por fio sutil |
| Seletor | Caixa do controle com borda e fundo | Mesmo `Select` do Design System, transparente, 11 px, tom secundário, 24 px (44 px em telas pequenas); primeiro grupo a 6 px do seletor |

Verificação: `binder-activity.test.ts` 15/15 (datas compactas e nome completo acessível incluídos); typecheck limpo; prévia estática com os SVGs reais do `lucide-react` (renderizados pelo próprio pacote) e o CSS real. **Equivalência visual no app real não comprovada**: o sandbox não executa `next dev/build` — homologação nas larguras 375/768/1280 pendente com o proprietário.

### 34.9 Validação final (2026-10-28) — visual homologado; funcional validado por leitura

| Critério | Situação | Evidência |
|---|---|---|
| Leitura e isolamento por titular | comprovado (LIVE) | 5269: `owner_user_id = auth.uid()`, DEFINER, `anon` sem EXECUTE; tabelas com RLS ligada, 0 políticas e sem SELECT para `authenticated`/`anon` (acesso só pelas RPCs); 85/85 chamadas reais `get_my_binder_activity`/`_coverage` com HTTP 200 (22:37–00:00 UTC) |
| Ordenação | comprovado (código + LIVE) | `order by occurred_at desc, id desc`; índice `ix_bae_owner_layout_time (owner, layout, occurred_at desc, id desc)` |
| Paginação sem duplicidade | comprovado por teste | cursor (occurred_at, id), limite 1–50; `mergeActivity`/`cursorAfter` em `binder-activity.test.ts` 15/15 |
| Filtros | comprovado por teste; dinâmico só por uso | 6 categorias + todas; testes de `categoryOf` |
| Expansão dos detalhes | implementado, homologado visualmente | botão por linha com `aria-expanded`/`aria-controls` |
| Atualização automática | implementado, sem prova dinâmica isolada | `activityVersion` incrementado em `refreshPages` |
| Vazio, carregamento e erro | implementado, sem prova dinâmica | `emptyMessage`, `aria-busy`, `role="alert"` com nova tentativa |
| Responsividade e acessibilidade | homologado visualmente; teclado por inspeção | alvos de 44 px em toque; combobox WAI-ARIA no filtro; movimento reduzido |
| Typecheck | PASS | `tsc --noEmit` limpo; tsbuildinfo restaurado |
| Testes | PASS | 15/15 |
| Lint / build | **PASS** (proprietário, 2026-10-28) | executados na máquina do proprietário; avisos não bloqueantes; build de produção com verificação de tipos e 76 páginas estáticas (o sandbox não roda o Next.js) |

Falhas materiais: nenhuma. Gate de publicação: depende de lint/build e da S6 (o Histórico exibe tipos da S6; sem a S6 encerrada, E17/E18/E20 aparecem só quando ocorrerem — risco baixo, leitura não muda).

Atualização do closeout (2026-10-28): testes 15/15 e typecheck reexecutados — PASS. `npm run lint` e `npm run build` **não executados** (o sandbox não roda o Next.js); comandos para o proprietário, em `web/`: `npm run lint` e `npm run build` (opcional: `npm run typecheck`).

## 35. Encerramento da P3-B (2026-10-28) — CONCLUÍDA COM RESSALVAS

### 35.1 Parecer por fatia

| Fatia | Parecer | Referência |
|---|---|---|
| S1 fundação (5267–5270) | ENCERRADA | §28.34 |
| S2 cartas (5271–5274) | PASS PARCIAL — ADD comprovado; REPLACE não exercitado | §29.11, §32.9 |
| S3 reservas e fixação (5275–5278) | PASS PARCIAL — troca de reserva no mesmo evento não exercitada | §30.10 |
| S4 páginas e espaços (5279–5286) | PASS PARCIAL — remoção de página do meio, deslocamento de reserva/imagem e recusas da 5286 não exercitados | §31.12 |
| S5 saídas (5287–5289) | PASS PARCIAL — E06a comprovado; E06b e E07 não exercitados | §32.9 |
| S6 montagem, coleções, encerramento (5290–5296) | PASS PARCIAL — E01, E17, E18 comprovados; E16 só prévia; E19, E19b, E20 sem interface | §33.12 |
| S7 seção Histórico (frontend) | Implementada no frontend local; visual homologado (FREEZE VISUAL); 15/15 testes, typecheck PASS; lint e build PASS (proprietário); **não publicada** | §34.9 |

### 35.2 Publicação (separada do encerramento de desenvolvimento)

Banco: S1–S6 no LIVE. Frontend: Histórico disponível só no app local; nada commitado, publicado ou implantado. Lint e build: **PASS** na máquina do proprietário (2026-10-28), com avisos não bloqueantes; build de produção concluído (verificação de tipos e 76 páginas estáticas). Pendentes para publicar: revisão e commit pelo proprietário; deploy com autorização própria.

### 35.3 Backlog aceito (não implementar sem nova rodada)

- E20, E19 e E19b — operações sem interface (instrumentação provada por inspeção).
- E16 — incorporação de novidades não executada (só prévia).
- E06b e E07 — sem homologação dinâmica.
- REPLACE (S2) — cenário não exercitado.
- Concorrência e desempenho (P2/P3) — sem comprovação dinâmica completa; H-A dispensou os harnesses 5859/5860 no LIVE.
- Demais ressalvas das S1–S6 (§29.11, §30.10, §31.12, §32.9).
- Evoluções futuras: interface de transferência/desmontagem/exclusão de fichário; agrupamento de eventos de página (D6), hoje mantidos individuais por decisão.

