# V1-13 · E1-E · G1 — Barreira de acesso no servidor (preparação)

| Campo | Valor |
|-------|-------|
| **Rodada** | `V1-13 / E1-E \| G1 SERVER-SIDE BARRIER PREPARATION-01` (2026-11-15) |
| **Status** | **G1 PREPARADO — NÃO EXECUTADO.** Nenhum SQL (nem SELECT), nenhuma migration aplicada, nenhum harness em banco, nenhuma conta, nenhuma ativação, sem commit. Mecanismo **não homologado**. G2/G3 não iniciados. |
| **Decisões** | D-E1 opção A (APROVADA). Alternativa C aprovada como arquitetura candidata do G1. C-234–C-244, D9–D14 inalterados. |
| **Base** | `main` em `dbfdbaa`; arquivos auditados de E1-A … E1-D **não alterados** (as versões protegidas são geradas ao lado). |

## Arquivos

| Arquivo | Papel |
|---|---|
| `5389_create_v1_13_capability_barrier.sql` | infraestrutura da porta (estado, registro, `v1_13_capability_open`, `v1_13_assert_capability`), criada em CLOSED |
| `build_g1_protected.py` | gerador determinístico das versões protegidas, do STOP e do manifesto; `--check` confere |
| `protected/` (16 arquivos) | versões protegidas de 5369, 5370, 5373–5377, 5380, 5382, 5383, 5385–5387, 5323, 5324, 5388 |
| `G1_MANIFEST.json` | por arquivo: sha256 da base auditada e da protegida; por capacidade: tipo, assinatura, md5 do corpo antes/depois |
| `EMERGENCY_STOP_V1_13.sql` | segunda camada de STOP (gerado) |
| `ROLLBACK_G1.sql` | reversão da porta (por último) |
| `5895_validate_v1_13_barrier_HARNESS.sql` | prova da barreira para o G2 (21) |
| `static_check_g1.py` | verificação estática independente |

## 1. Inventário fechado (37 capacidades)

Critério: **toda** função criada pela cadeia E1-A … E1-D com `GRANT EXECUTE … TO authenticated`. A varredura (verificação 4.1) encontrou 40: 37 capacidades novas + 3 leituras da V1-12 substituídas pela 5368 (`get_my_collection_invites`, `get_collections_shared_with_me`, `get_shared_collection`, que continuam abertas). Todas as demais funções da cadeia revogam `authenticated` explicitamente, e as três substituídas por `CREATE OR REPLACE` (`binder_activity_add_item`, `binder_slot_editor_scope`, gatilho de tipos) herdam a ACL já revogada (5268, 5371, 5381). **Não há ponto de entrada novo além dos 37.** As políticas RLS que usam participação são só as da 5329 (V1-12, leitura) e as 3 novas da 5377 (protegidas pelos ajudantes).

| Tipo | Qtde | Entradas | CLOSED | TEST, registrado | TEST, não registrado | OPEN |
|---|---|---|---|---|---|---|
| escrita | 29 | 28 `editor_*` (5374, 5375, 5376, 5380, 5382, 5383, 5385, 5386, 5387) + `set_collection_member_role` (5370) | 42501 `CAPABILITY_NOT_ENABLED` | regra do produto | 42501 | regra do produto |
| leitura | 5 | `get_shared_binder_placeable_cards` (5373), `get_shared_master_set_positions` (5323), `get_shared_pokedex_positions` (5324), `get_shared_binder_activity`, `…_status` (5388) | zero linhas | regra do produto | zero linhas | regra do produto |
| ajudante do Storage | 2 | `collection_cover_editor_folder_ok`, `…_can_upload` (5377) | falso → políticas novas não concedem | regra do produto | falso | regra do produto |
| convite | 1 | `invite_collection_member(uuid, text, text)` (5369) | papel EDITOR → 42501; VIEWER → V1-12 | regra do produto | EDITOR → 42501; VIEWER → V1-12 | regra do produto |

Todas são `SECURITY DEFINER`, `search_path = ''`, EXECUTE só para `authenticated` (anon e PUBLIC revogados — os privilégios padrão do Supabase concederiam). A porta é chamada **como dono** (definer → definer), por isso ela própria não tem EXECUTE para nenhum papel de cliente. Chamadas indiretas: as capacidades chamam internas sem EXECUTE para a API (`assert_*`, `binder_*`, `editor_binder_exclusive_read`, planos do titular); nenhuma função do titular chama uma capacidade nova. Resposta neutra por tipo: escrita levanta 42501 com mensagem fixa (não revela dado); leitura devolve zero linhas, indistinguível de "sem acesso"; ajudante devolve falso (a política simplesmente não concede). A porta vem **antes** de qualquer validação de parâmetro, então em CLOSED nem erros de validação são distinguíveis.

## 2. Arquitetura (Alternativa C)

- **Camada 1 — porta no banco (5389):** `v1_13_capability_open()` = `auth.uid()` presente **e** (modo OPEN **ou** modo TEST com o usuário no registro); linha ausente ou modo desconhecido → falso. Tabelas com RLS sem política e `REVOKE ALL` de PUBLIC/anon/authenticated/service_role: ninguém se inscreve nem muda o modo pela API. Mudança de modo e de registro só por SQL do proprietário, com autorização específica.
- **Camada 2 — privilégio (`EMERGENCY_STOP_V1_13.sql`):** independe da porta.

## 3. Diffs das propostas (por artefato)

Mudança única, gerada e reversível: cabeçalho de rastreabilidade + 1 linha de porta por capacidade + 1 linha de precheck ("barreira 5389 ausente") + troca das constantes md5 do próprio corpo na 5369 e na 5370. Toda linha inserida termina com `-- G1 (D-E1)`; a verificação 5.x desfaz as mudanças e exige igualdade byte a byte com o arquivo auditado. Versões anteriores preservadas (arquivos originais intactos; sha256 no manifesto).

| Artefato | Capacidades | md5 alterado no próprio arquivo | Verificações afetadas |
|---|---|---|---|
| 5369 | convite (ramo EDITOR) | sim (`52b17e64…` → `5a5ea206…`) | `static_check_e1a` continua sobre o auditado; P1 precisa ser regerado com a protegida (E1-E2) |
| 5370 | troca de papel | sim | idem |
| 5373, 5374, 5375, 5376, 5377, 5380, 5382, 5383, 5385, 5386, 5387, 5323, 5324, 5388 | 35 | não | harnesses não fixam o md5 dessas funções (verificado); estáticos anteriores seguem sobre os auditados |

md5 por função: `G1_MANIFEST.json`.

## 4. Preservação da V1-12 e mudanças compartilhadas

| Mudança | Protegida? | Comportamento em CLOSED |
|---|---|---|
| 5366 CHECK de papel | não (estrutura) | sem efeito para usuários; trava O1 na aplicação |
| 5368 leituras com `role` | não (leitura V1-12) | idêntico, com a chave `role` (o membro vê o próprio papel) |
| 5369 convite | **só o ramo EDITOR** | convite VIEWER (inclusive chamada de 2 argumentos, padrão `'VIEWER'`) inalterado |
| 5372/5379 gravação do histórico | não (caminho do titular) | o titular grava como hoje, com a coleção por item e a recusa de contexto forjado (provadas em ensaio: 5889, 5891) |
| 5381/5384 gatilho de tipos | não | só age quando ator ≠ titular |
| 5377 políticas | **pelos ajudantes** | políticas do dono (5176) e de leitura (5329) intactas; as novas não concedem nada; trava O2 na aplicação |
| 5304/5305/5306 (aceite, remoção, saída) | não (V1-12) | um convite EDITOR criado em TEST pode ser aceito em CLOSED: a participação existe, mas toda capacidade do EDITOR fica fechada e a leitura V1-12 segue no nível VIEWER (5895 3.6) |

**Limitação registrada:** as mudanças compartilhadas não podem ser protegidas pela porta sem alterar o comportamento legado; valem para todos na persistência e dependem de prova transacional prévia (G2).

## 5. STOP emergencial (segunda camada)

`EMERGENCY_STOP_V1_13.sql`, três blocos independentes: **E1** modo CLOSED (sem trava; efeito na chamada seguinte); **E2** `REVOKE EXECUTE` das 34 RPCs novas (29 escritas + 5 leituras) de PUBLIC/anon/authenticated — corta inclusive as contas de teste, não depende da porta, não afeta titular nem VIEWER da V1-12; **E3** `DROP POLICY` das 3 políticas novas com `LOCK storage.objects … NOWAIT` (O2). Exceções: **convite** (5369) não é revogado porque é o convite da V1-12 — contingência: R5369 do `ROLLBACK_E1A` (volta à 5303); **ajudantes do Storage** não são revogados porque a avaliação das políticas falharia para todos os usuários do bucket. Nada disso cancela chamadas em curso (encerrar sessões é decisão do operador) nem desfaz o que foi gravado. Privilégio necessário: dono das funções e das políticas (o mesmo executor das migrations; confirmar na S0 para `storage.objects`).

**Limites (não é contenção instantânea nem ausência de impacto):**
- CLOSED **contém** chamadas novas, a partir da seguinte; não interrompe as que já começaram (a porta é avaliada no início de cada chamada).
- O REVOKE (E2) só vale para chamadas iniciadas depois do seu COMMIT; pode esperar por `lock_timeout` se houver trava concorrente no catálogo; se falhar, nada daquele bloco vale e E1 continua em vigor.
- O DROP POLICY (E3) **exige** ACCESS EXCLUSIVE em `storage.objects`: o `NOWAIT` só evita a fila de aquisição (se ocupado, falha com `55P03` e precisa ser repetido em janela) e **não** limita quanto a transação dura depois de adquirir; enquanto vigora, o Storage inteiro espera.
- As mudanças compartilhadas da V1-12 (5366, 5368, 5369 VIEWER, 5372/5379, 5381/5384) **não** são revertidas pelo STOP.
- O STOP **não** equivale ao rollback da cadeia (`ROLLBACK_E1D` … `ROLLBACK_E1A` + `ROLLBACK_G1`), que remove funções e políticas e tem seus próprios limites (dados gravados permanecem).

## 6. Ordem segura de aplicação (para pedido futuro de G3; não executar)

1. `5389` (CLOSED, registro vazio) — **antes de qualquer migration da V1-13**; o precheck recusa se a cadeia já existir.
2. Confirmar CLOSED e registro vazio (só leitura).
3. Cadeia com as versões **protegidas**: 5366 → 5367 → 5368 → P5369 → P5370 → 5371 → 5372 → P5373 → P5374 → P5375 → P5376 → P5377 → 5378 → 5379 → P5380 → 5381 → P5382 → P5383 → 5384 → P5385 → P5386 → P5387 → P5323 → P5324 → P5388. Cada protegida recusa sem a 5389.
4. Validação negativa com JWT real (G3): toda capacidade nova negada, inclusive para contas que depois serão de teste.
5. Inclusão de identidades de teste (autorização própria).
6. Modo TEST (autorização própria).
7. Provas reais (G4).
8. OPEN só depois de G5 e da autorização da etapa 7.

**Primeira aplicação:** cada capacidade nasce dentro de uma migration transacional, já com a porta e com o modo CLOSED vigente; só fica visível ao PostgREST depois do COMMIT e depois da recarga do cache, sempre fechada. Commits intermediários deixam a cadeia parcial **fechada**. **Nenhuma janela de exposição de capacidade nova identificada.** A janela que existe é a das mudanças compartilhadas (§4), tratada como requisito de prova prévia. Demonstrável estaticamente: ordem, porta primeiro, ACLs. Só por execução real: ausência de exposição pelo PostgREST e pela API do Storage (G3).

## 7. Provas da barreira (5895) e compatibilidade dos harnesses

5895 (21, ensaio): estrutura da porta (0.1), cobertura das 37 e nenhuma `editor_*` sem porta (0.2), estado inicial (0.3), compartilhadas intactas (0.4), CLOSED para registrado (1.1), Storage em CLOSED (1.2), V1-12 em CLOSED (1.3), TEST não registrado (2.1), TEST registrado (2.2), barreira × autorização funcional com VIEWER/estranho/removido/pendente registrados (2.3), leituras em TEST incl. titular registrado e não registrado (2.4), convite EDITOR por titular não registrado (2.5), revogação no registro e troca de papel (2.6), OPEN futuro (3.1), configuração ausente (3.2), anon sem EXECUTE (3.3, 3.4), tabelas administrativas e autoinscrição (3.5), EDITOR aceito em CLOSED (3.6), resíduo (99.1).

| Harness | Modo no ensaio | Por quê |
|---|---|---|
| 5861 v1.4, 5862, 5863, 5864 (V1-12) | **CLOSED** | prova de que a barreira não afeta a V1-12 |
| 5888, 5889, 5890, 5891, 5892, 5893, 5894 (funcionais) | **OPEN**, só dentro da transação abortada (`UPDATE` antes do harness) | a regra funcional é exercitada; com CLOSED a barreira recusaria antes e a prova seria inválida |
| 5895 | troca de modo internamente | prova da barreira |
| P1 (E1-A) | — | precisa ser **regerado** com 5389 + 5369/5370 protegidas + modo OPEN para a 5888 + 5895 (E1-E2) |

Em ensaio só se prova o banco (SET LOCAL ROLE); JWT real, PostgREST e API do Storage ficam para G3/G4.

## 8. Rollback e governança

- Ordem: `ROLLBACK_E1D` … `ROLLBACK_E1A` (assinaturas iguais nas protegidas) e por último `ROLLBACK_G1` (recusa se restar capacidade protegida).
- **Ativar TEST** exige: G3 aprovado; identidades de teste criadas pelo proprietário; autorização específica.
- **Desativar** (CLOSED ou STOP): a qualquer momento, por decisão do proprietário; não exige gate.
- **Antes de qualquer pedido de execução:** G1 revisado por auditoria independente; P1/ensaio da cadeia regerados com as protegidas (E1-E2); S0 autorizada.
- O1–O7, B1–B7 e os riscos residuais da D-E1 (R-B1…R-B5) mantidos. S1–S10, PR-04B, P4-A/P4-B e Storage pela API **sem mudança de estado** (todos NÃO COMPROVADOS).

## 9. Encerramento das identidades e dos dados de teste (procedimento futuro; nada executado)

Pré-condição permanente: as provas usam **só** contas de teste criadas pelo proprietário e coleções delas; nunca coleções ou fichários de usuários reais (eventos do histórico são imutáveis e não poderiam ser compensados num fichário real — por isso essa hipótese fica **bloqueada**).

Ordem de compensação, cada passo com autorização e com conferência antes/depois:

1. **Fechar:** modo CLOSED (`EMERGENCY_STOP_V1_13.sql` E1 ou UPDATE equivalente).
2. **Retirar autorização:** apagar todas as linhas de `v1_13_barrier_identity` das contas de teste.
3. **Convites EDITOR pendentes:** removê-los pelo titular de teste (`remove_collection_member`, 5305, que apaga a participação em qualquer estado).
4. **Participações EDITOR experimentais:** removê-las (5305) ou rebaixá-las a VIEWER (5370) antes da remoção.
5. **Arquivos no Storage:** apagar pela API do Storage os objetos enviados pelos EDITORs de teste e pelos titulares de teste no bucket `collection-cover` (`storage.objects.owner_id` não tem cascata com a conta: precisa ser feito **antes** de excluir as contas).
6. **Dados de produto e histórico:** excluir as contas de teste no Auth; a cascata remove coleções, participações, fichários, alocações e os eventos do histórico dos titulares de teste (C-203) e as linhas do registro (FK da 5389).
7. **Conferência final (só leitura):** modo CLOSED; registro vazio; nenhuma participação, convite, objeto de Storage ou evento ligado aos ids da lista fechada de contas de teste; nenhuma conta de teste restante; resíduo zero conforme a lista definida antes do início.

Não compensável automaticamente: logs, WAL, contadores, sequências consumidas e esperas impostas a usuários.

## 10. Governança dos gates (estado em 2026-11-15)

| Gate | Estado |
|---|---|
| D-E1 | **APROVADA** (opção A) |
| Mecanismo | **Alternativa C selecionada** como candidata; não homologada |
| E1-E1 | plano de evidências e viabilidade documentados |
| G0 | viabilidade estática documentada (`../BARRIER-FEASIBILITY-D-E1.md`) |
| G1 | implementação local **preparada, não executada** (esta pasta) |
| G2 | **não iniciado** |
| G3 | **não iniciado** |
| G4 | **não iniciado** |
| G5 | **não iniciado** |

A etapa 6 (E1-E) **não** está concluída; a etapa 7 continua bloqueada; as dez etapas oficiais do roadmap são preservadas.

## 11. Proteção contra substituição inadvertida

- Editar um arquivo auditado muda o sha256 da base → `build_g1_protected.py --check` e `static_check_g1.py` (3.1, 5.x) falham até regerar.
- Editar uma versão protegida à mão → `--check` e 5.x/6.x falham.
- Nova migration na cadeia que redefina uma capacidade: a verificação 4.1 a acusa se não tiver GRANT nem REVOKE; com GRANT, entra no inventário e diverge do manifesto. Conferência desta rodada: **nenhuma** migration não protegida da cadeia (5366–5368, 5371, 5372, 5378, 5379, 5381, 5384) redefine qualquer uma das 37.
- No banco: o harness 5895 (0.2) exige que as 37 chamem a porta e que nenhuma `editor_*` exposta deixe de chamá-la; a 5369/5370 protegidas têm o md5 do próprio corpo nos pre/postchecks.
- Fora da cadeia (migrations futuras em outras pastas) a detecção estática não alcança: qualquer migration futura que toque essas funções deve regerar as protegidas e repetir 5895.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **G1 preparado (2026-11-15, `V1-13 / E1-E \| G1 SERVER-SIDE BARRIER PREPARATION-01`).** 5389 (porta em CLOSED), 16 versões protegidas geradas (37 capacidades), STOP emergencial, ROLLBACK_G1, harness 5895 (21), verificação estática. Nada executado; mecanismo não homologado. |
| 1.1 | **Encerramento local (2026-11-15, `G1 BARRIER LOCAL CLOSEOUT AND COMMIT-02`).** Limites do STOP explicitados (§5); encerramento de identidades e dados de teste (§9); governança dos gates (§10); proteção contra substituição (§11). Nenhuma lógica alterada; nada executado. |
