# V1-13 · E1-E1 — D-E1: viabilidade da barreira de acesso no servidor

| Campo | Valor |
|-------|-------|
| **Rodada** | `V1-13 / E1-E1 \| D-E1 FORMALIZATION AND SERVER-SIDE BARRIER FEASIBILITY-03` (2026-11-15) |
| **DECISÃO APROVADA** | **D-E1, opção A** (proprietário, 2026-11-15, definitiva): persistência técnica **restrita** das capacidades E1, protegida por **barreira de acesso no servidor**, para viabilizar provas dinâmicas com identidades e sessões reais, **antes** da habilitação pública. |
| **MECANISMO NÃO APROVADO** | A barreira descrita aqui é **candidata**. Só pode ser implementada com autorização própria e só pode ser persistida depois de demonstrada (gates G0–G5, §9). |
| **EXECUÇÃO NÃO AUTORIZADA** | Nenhuma operação no banco: sem SQL (nem SELECT), S0, P1, harness, conta, sessão, fixture, migration, política ou privilégio. |
| **Base** | `main` em `dbfdbaa`; propostas E1-A … E1-D intactas; investigação **estática** (textos das propostas e de `database/schema/`). |

---

## 1. Conteúdo normativo da D-E1

1. **Persistência técnica restrita** das capacidades E1 só para provas reais; não é habilitação funcional.
2. **Controle de acesso efetivo no servidor**: decidido dentro do banco, a cada chamada, a partir da identidade autenticada (`auth.uid()` do JWT), nunca por configuração do frontend nem por declaração do cliente.
3. **Nenhuma habilitação pública** antes das provas obrigatórias (S1–S10, PR-04B, JWT real, Storage pela API real).
4. **Autorização explícita e individualizada** do proprietário para cada intervenção futura (persistir, incluir/retirar identidade de teste, abrir, fechar, reverter).
5. **Barreira validada antes da exposição** de qualquer capacidade nova.
6. **STOP e recuperação** sempre possíveis, com desligamento imediato no servidor.
7. **Separação** entre persistência para comprovação e habilitação funcional (abertura).
8. **Etapa 7 preservada** como marco oficial posterior ao parecer de segurança; nada aqui a inicia ou conclui.

**Compatibilidade normativa.** A C-244 bloqueia a **publicação** sem prova e exige, no banco existente, protocolo controlado, autorização específica, dados sintéticos e efeitos reversíveis ou compensáveis — **compatível** com a persistência restrita (identidades de teste são sintéticas; capacidades persistidas são reversíveis pelos rollbacks e desligáveis pela barreira). **Não há conflito com C-234–C-244 nem com D9–D14.** O único texto que impedia a estratégia é a sequência do `05d` ("Dependências e ordem": prova S1–S10 no item 4, autorização de aplicação no item 6): recebeu **refinamento explícito marcado "D-E1"** (prova transacional → persistência restrita → provas persistentes → parecer → aplicação para todos), sem retirar nenhuma prova.

---

## 2. Superfície de exposição (estática)

Papel de banco de toda chamada pela API = `authenticated` (JWT de usuário) ou `anon`; identidade de aplicação = `auth.uid()`. Nenhuma tabela nova ou alterada tem privilégio direto para clientes (`collection_membership`: `REVOKE ALL` e RLS sem política de cliente, 5300; histórico: só funções); as únicas políticas RLS que usam participação são as de leitura de imagens compartilhadas (5329) e as novas da 5377.

### 2.1 Capacidades novas (bloqueáveis pela barreira)

| Capacidade | Migration | Ponto de entrada | Controle atual | Exposição potencial se persistida sem barreira | Bloqueio necessário |
|---|---|---|---|---|---|
| Convidar com papel EDITOR | 5369 | RPC `invite_collection_member(uuid,text,text)` | titular da coleção | qualquer titular cria EDITOR → abre todas as RPCs do EDITOR ao convidado | barreira quando `p_role = 'EDITOR'` (caminho VIEWER inalterado) |
| Trocar papel | 5370 | RPC `set_collection_member_role` | titular, só ACTIVE | idem | barreira na chamada |
| Aceitar convite EDITOR | 5304 (V1-12, inalterada) | RPC de resposta | convidado | aceitar cria EDITOR ativo | coberto indiretamente: só existe convite EDITOR criado pela 5369 com barreira; e toda capacidade do EDITOR verifica a barreira na chamada |
| Escritas do fichário pelo EDITOR | 5374, 5375, 5382, 5383, 5385–5387 | 20 RPCs `editor_*` | 5371/5382 (papel, coleção, bolsos) | escrita entre contas antes de S1–S10 | barreira na entrada de cada RPC |
| Metadados e capa pelo EDITOR | 5376 | 4 RPCs `editor_*` | `assert_collection_editor` | idem | idem |
| Pokédex pelo EDITOR | 5380 | 4 RPCs `editor_*_pokedex_*` | 5380 | idem | idem |
| Leitura de exemplares colocáveis | 5373 | RPC `get_shared_binder_placeable_cards` | EDITOR ativo | leitura nova antes de S9 | idem |
| Envio, leitura e exclusão de capa pelo EDITOR | 5377 | API do Storage → políticas `collection_cover_*_editor` em `storage.objects` | ajudantes `collection_cover_editor_folder_ok/can_upload` | gravação no Storage do titular | barreira **dentro dos ajudantes** (as políticas permissivas se somam às do dono por OR; com o ajudante negando, a política nova não concede nada) |
| Grade Master Set / Pokédex do participante | 5323, 5324 | RPCs `get_shared_*_positions` | 5302 OWNER/VIEWER | **todo VIEWER da V1-12** ganharia leitura nova antes de S9 | barreira na entrada (leitura: zero linhas) |
| Histórico compartilhado | 5388 | 2 RPCs `get_shared_binder_activity*` | 5302 + C-241/D12–D14 | idem | idem |
| Internas (`collection_member_role`, `binder_*`, `assert_*`, `editor_*_exclusive`, etc.) | 5367, 5371, 5378, 5382, 5385, 5387 | sem EXECUTE para a API | — | só por funções acima | nenhuma (já sem EXECUTE) |

### 2.2 Mudanças em objetos compartilhados (afetam usuários existentes sem nenhuma chamada do EDITOR; **não bloqueáveis por barreira de identidade**)

| Mudança | Migration | Quem é afetado | Natureza | Como se comprova antes de persistir |
|---|---|---|---|---|
| CHECK de papel aceita EDITOR | 5366 | ninguém diretamente; ACCESS EXCLUSIVE na aplicação (O1) | estrutura | 5888 em ensaio |
| Leituras V1-12 com chave `role` | 5368 (5309/5311/5312) | todo participante e titular | aditiva | 5861 v1.4, 5888 em ensaio |
| Convite com papel substitui a assinatura antiga | 5369 (5303) | todo titular que convida (chamada de 2 argumentos segue válida pelo padrão `'VIEWER'`) | substituição | 5888, 5861 v1.4 |
| Gravação do histórico | 5372 → 5379 (`binder_activity_add_item`) | **toda** operação do titular no fichário | regra do ator, coleção por item, recusa de contexto forjado, custo extra por item | 5889 (aceita os dois), 5891, regressão do titular, M2/M6 |
| Colunas novas no histórico | 5379 | todos (só catálogo) + ACCESS EXCLUSIVE na aplicação (O3) | estrutura | 5891, 5894 |
| Gatilho de tipos de evento | 5381 → 5384 | toda gravação de evento (só age se ator ≠ titular) | verificação extra por evento | 5892, 5893 |
| Políticas novas em `storage.objects` | 5377 | **todo** acesso ao Storage na aplicação (O2); depois, avaliação de mais políticas por requisição | estrutura | ST-AUT/ST-INT em ensaio; M (custo) a medir |

Essas mudanças entram em vigor para todos no momento da persistência. A D-E1 só é satisfeita se elas forem **provadas em ensaio transacional antes** (G1→G2, §9) e **não** forem consideradas cobertas pela barreira.

### 2.3 Caminhos indiretos verificados

- Funções do titular **não** chamam funções do EDITOR; as do EDITOR reusam internas do titular (planos, tokens) sem EXECUTE para a API.
- `collection_share_role` (5302, inalterada) trata EDITOR como VIEWER: um EDITOR ativo lê o que um VIEWER lê **pela V1-12** (já publicado). Participação EDITOR só nasce pela 5369/5370 com barreira.
- Gatilhos novos: só o da 5381/5384 (verificação, sem efeito externo).
- PostgREST expõe toda função `public` com EXECUTE para `authenticated`; a ausência de interface **não** protege.

---

## 3. Alternativas

| Critério | **A — porta central no banco** (registro de identidades de teste + verificação na entrada de cada capacidade nova, incluindo os ajudantes do Storage) | **B — só privilégios/pontos de entrada** (REVOKE EXECUTE, esquema não exposto, papel de banco próprio) | **C — combinada** (A + segunda camada de privilégio como desligamento de emergência + procedimento de abertura) |
|---|---|---|---|
| Cobertura | RPCs, leituras novas e Storage (pelo ajudante) | RPCs sim; Storage **não** (a API usa o papel `authenticated` para todos) | a de A |
| Distingue contas de teste? | **sim** (`auth.uid()` no registro) | **não**: EXECUTE é por papel de banco; todo JWT de usuário é `authenticated`. Papel próprio exige gancho de token no Auth (configuração global, fora do banco) | sim |
| Bypass | só por quem escreve no registro (sem privilégio para clientes) ou por função nova esquecida (mitigado por verificação estática) | REVOKE bloqueia também as contas de teste → inviabiliza P4-B, ST-API, S8/S10 | idem A |
| JWT real | compatível | incompatível sem mudar o Auth | compatível |
| Storage | compatível (política avalia o ajudante sob o JWT) | incompatível | compatível |
| Funções preexistentes | intactas | intactas | intactas |
| Complexidade | moderada: 1 migration nova + verificação nas ~37 entradas novas | baixa, mas não atende 2, 12, 13 | moderada |
| Reversão | esvaziar o registro / fechar o interruptor (efeito na chamada seguinte) | REVOKE/GRANT | dupla: interruptor no banco **e** REVOKE EXECUTE |
| Novas migrations | sim (porta) + nova versão das propostas E1-A…E1-D | só GRANT/REVOKE | sim |
| Impacto operacional | leitura de 1 linha por PK por chamada nova; nenhuma trava extra em tabela compartilhada | nenhum | igual a A |
| Risco de bloquear usuários | nenhum sobre a V1-12 (só capacidades novas) | idem | idem |
| Manutenção | a abertura vira "interruptor aberto"; remoção posterior exige nova migration | — | idem A |
| Atende os 14 critérios? | sim, exceto contingência de segunda camada | **não** (2, 4, 12, 13) | **sim** |

**Recomendação: C.** A é o mecanismo de controle; a camada de privilégio de B é mantida **só** como desligamento de emergência (REVOKE EXECUTE das RPCs novas em uma transação, que corta inclusive as contas de teste). B sozinha foi descartada porque não distingue identidades nem cobre o Storage; A sozinha foi descartada porque depende de um único ponto (o registro) para o STOP.

### 3.1 Forma da porta (candidata, não implementada)

- **Migration nova anterior a toda a cadeia** (número a reservar): tabela de estado da barreira (modo `CLOSED`/`TEST`/`OPEN`, uma linha) e tabela de identidades de teste (`user_id`, quem incluiu, quando); RLS ativa **sem nenhuma política**; `REVOKE ALL` de PUBLIC/anon/authenticated; escrita só pelo proprietário por SQL autorizado. Modo inicial `CLOSED`; ausência de linha = `CLOSED` (negação por padrão).
- **Função interna** `v1_13_capability_open()` (STABLE, SECURITY DEFINER, `search_path=''`): verdadeiro só se modo = `OPEN`, ou modo = `TEST` **e** `auth.uid()` está no registro. `auth.uid()` nulo → falso. Sem EXECUTE para a API.
- **Cada capacidade nova** chama a porta **antes de qualquer leitura**: escrita → recusa neutra `42501` (`FEATURE_NOT_AVAILABLE`); leitura → zero linhas (indistinguível de "sem acesso"); ajudantes do Storage → falso. A 5369 só consulta a porta quando o papel pedido é `EDITOR`.
- **Autorização funcional inalterada**: a porta é verificada **além** das regras de papel/coleção, nunca no lugar delas.
- **Verificação estática obrigatória**: toda função com EXECUTE para `authenticated` criada pela cadeia chama a porta como primeira instrução após validação de parâmetros; nenhuma é esquecida.

---

## 4. Primeira aplicação

| Passo | Estado | Janela de exposição? |
|---|---|---|
| 1. Porta persistida em `CLOSED`, registro vazio | nenhuma capacidade nova existe | não |
| 2. Cada migration da cadeia, em transação própria, cria funções **já com a porta** e políticas cujo ajudante já consulta a porta | a função só fica visível ao PostgREST depois do COMMIT daquela migration (DDL transacional), e nasce fechada | **não** para capacidades novas |
| 3. Estados intermediários (cadeia parcial) | porta `CLOSED` nega tudo o que existir | não |
| 4. Mudanças compartilhadas (§2.2) | entram em vigor para todos no COMMIT de cada uma | **sim, por natureza** — não é capacidade nova; exige prova transacional prévia (G2) e janela operacional (O1–O3, O2) |
| 5. Validação do estado fechado (G3) com JWT real de contas **não** registradas e do registro ainda vazio | só leitura de resultados de chamadas negadas | não |

Não se presume atomicidade entre banco, PostgREST, Storage ou serviços externos: a segurança **não** depende dela, porque o controle está dentro de cada função e de cada ajudante e nasce fechado. O atraso de recarga do cache do PostgREST só adia a visibilidade de funções já fechadas.

**Janela inevitável para capacidades novas: nenhuma identificada.** A janela do item 4 é de **mudança de comportamento compartilhado**, não de capacidade, e é tratada como requisito de prova anterior — não como STOP da D-E1.

---

## 5. Compatibilidade com as provas

| Prova | Como a barreira a permite | Como não mascara a autorização funcional |
|---|---|---|
| S1 (OWNER/EDITOR legítimos) | contas de teste no registro, modo `TEST` | — |
| S2–S7 (recusas) | executar **com contas registradas** que não têm o papel (estranho registrado, VIEWER registrado, pendente registrado, removido registrado) | a recusa vem da regra funcional, não da porta (a conta está liberada) |
| Prova da porta | mesmas chamadas com contas **não** registradas que **têm** papel válido (EDITOR aceito de um titular registrado) | recusa vem da porta; comparar com o caso registrado |
| S8 seq./conc. | retirar do registro e trocar papel durante a sessão; a porta é avaliada por chamada (STABLE, mesmo instantâneo) | duas variáveis testadas separadamente: papel e registro |
| S9 / D12–D14 / Master Set / Pokédex | leituras com contas registradas; leituras de não registradas → zero linhas | idem |
| S10, C1–C7 | duas sessões reais com contas registradas | — |
| PR-04B (5364) | fora da barreira (já aplicada) | — |
| ST-API, ST8, ST6 | ajudantes do Storage consultam a porta sob o JWT real | não registrada com papel válido → recusa da porta |
| Harnesses em ensaio (SET LOCAL ROLE) | a fixture abre `TEST` e registra suas identidades sintéticas dentro da transação | cada harness ganha um caso "não registrado" |

---

## 6. Impactos sobre a V1-12

- Coleções, cartas, fichários e capas existentes: nenhuma capacidade da V1-12 passa pela porta.
- Uploads existentes: políticas do dono (5176) e de leitura compartilhada (5329) inalteradas; as novas só concedem com a porta aberta.
- Desempenho: avaliação de mais políticas em `storage.objects` por requisição e o custo extra da 5379 por item — **a medir** (M2, M6 + nova medição de Storage); nenhuma ausência de impacto declarada.
- Travas: O1–O7 mantidos; a 5377 continua exigindo `LOCK … NOWAIT`, ensaio curto e janela sem tráfego de Storage.

---

## 7. Reversão e contingência

| Situação | Ação | Efeito | Não desfaz |
|---|---|---|---|
| Parar novas chamadas já | modo `CLOSED` (1 UPDATE autorizado) | todas as capacidades novas negadas na chamada seguinte | o que já foi gravado |
| Emergência (falha da porta suspeita) | **segunda camada**: REVOKE EXECUTE de `authenticated` em todas as RPCs novas + DROP das políticas da 5377 (uma transação) | corte independente da porta, inclusive para contas de teste | idem |
| Revogar identidade de teste | DELETE no registro | negação na chamada seguinte | — |
| Interromper ensaio | aborto (sentinela) | nada confirmado | marcas de O6 |
| Desabilitar capacidades (definitivo) | `ROLLBACK_E1D` … `ROLLBACK_E1A` em ordem inversa | funções e políticas removidas; dados gravados preservados (C-155, C-179) | objetos do Storage enviados por teste (compensação manual), eventos de teste no histórico (só somem com a exclusão da conta de teste, C-203) |
| Recuperar o estado anterior | reversões + exclusão das contas de teste (cascata) + verificação de resíduo zero | estado sem V1-13 | logs, WAL, sequências, esperas sentidas |

**Sinais de falha da barreira:** qualquer chamada bem-sucedida de conta não registrada em capacidade nova; qualquer linha nova em participação EDITOR, histórico com ator EDITOR ou objeto de capa enviado por EDITOR que não pertença ao registro; função nova com EXECUTE sem a porta. Qualquer um → STOP, modo `CLOSED` e segunda camada.

---

## 8. Artefatos a adaptar (não alterados nesta rodada)

- Migration nova da porta (antes de 5366).
- Novas versões: 5369 (EDITOR), 5370, 5373–5376, 5377 (ajudantes), 5380, 5382, 5383, 5385–5387, 5323, 5324, 5388 — porta na entrada; md5 e verificações estáticas atualizados.
- Harnesses 5888–5894: abrir `TEST` e registrar identidades na fixture; acrescentar o caso "não registrado com papel válido".
- Verificação estática nova: "toda RPC nova chama a porta primeiro" e "registro sem privilégio para clientes".
- Rollback: reversão da porta por último.
- Procedimentos operacionais: incluir/retirar identidade, mudar modo, segunda camada.

---

## 9. Gates

| Gate | Critério objetivo | Autoriza |
|---|---|---|
| **G0 — viabilidade estática** | superfície inventariada sem lacuna conhecida (§2); alternativa com os 14 critérios (§3); ordem sem janela de capacidade (§4) | nada além de preparar G1 |
| **G1 — barreira preparada** | artefatos do §8 escritos, revisados e com verificação estática PASS (inclusive "porta primeiro" em 100% das entradas novas); nada executado | nada além de pedir autorização de ensaio |
| **G2 — barreira e cadeia provadas em ensaio** | S0 autorizada; ensaio transacional (P1 e cadeia) com a porta: casos registrados e não registrados em todos os harnesses, regressão do titular e das mudanças compartilhadas (§2.2) PASS; `txid = aborted` | pedido de autorização de persistência |
| **G3 — persistência restrita** | porta persistida em `CLOSED` **antes** da cadeia; cadeia persistida; prova com JWT real de que contas não registradas (e o registro vazio) são negadas em todas as RPCs novas e no Storage | inclusão de contas de teste (autorização própria) |
| **G4 — provas integradas** | modo `TEST` com contas de teste: S1–S10 (inclusive S8 conc. e S10), PR-04B, P4-A/P4-B, ST1–ST9, M1–M7 com evidências | parecer |
| **G5 — parecer GO/NO-GO** | todas as anteriores PASS e parecer de segurança favorável | **considerar** a etapa 7 (que decide abrir, `OPEN`, ou reverter) |

**Ordem segura entre G2 e G3:** a barreira **não** pode ser comprovada com JWT real antes de existir. Por isso G3 persiste primeiro a porta fechada e só então a cadeia, e a primeira prova real é **de negação** (ninguém registrado). A prova positiva da porta só vem em G4. G0/G1 não autorizam G2/G3; a D-E1 aprovada não aprova nenhum gate.

---

## 10. Bloqueios residuais

| # | Bloqueio | Situação |
|---|---|---|
| R-B1 | mudanças compartilhadas (§2.2) entram em vigor para todos na persistência | não é capacidade nova; só aceitável depois de G2 (prova transacional) e com janela operacional; **não** é coberto pela barreira |
| R-B2 | barreira não implementada; propostas E1-A…E1-D precisam de nova versão | G1 |
| R-B3 | privilégio do executor para `LOCK`/`CREATE POLICY` em `storage.objects` e versão do PostgreSQL | S0 |
| R-B4 | a porta depende de `auth.uid()`; o comportamento do Storage sob o JWT real (dono gravado, avaliação dos ajudantes) só se prova pela API | G3/G4 |
| R-B5 | segunda camada (REVOKE EXECUTE) corta também o titular? Não: só RPCs novas do EDITOR/leituras novas; a 5369 é compartilhada — a segunda camada a mantém e conta com a porta para o papel EDITOR | registrar no procedimento (G1) |

**Nenhum** desses itens demonstra impossibilidade material da D-E1. Os bloqueios B1–B7 do plano continuam válidos.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Viabilidade estática da barreira (2026-11-15, `D-E1 FORMALIZATION AND SERVER-SIDE BARRIER FEASIBILITY-03`).** D-E1 (opção A) formalizada; superfície de exposição; alternativas A/B/C; recomendação C (porta no banco + desligamento por privilégio); primeira aplicação sem janela de capacidade nova; gates G0–G5. Nada executado nem implementado. |
