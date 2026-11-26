# V1-13 · E3-6 — Edição colaborativa completa: avaliação e proposta de evolução contratual

| Campo | Valor |
|---|---|
| **Rodada** | `E3-6 — FULL COLLABORATIVE EDITING \| CONTRACT EVOLUTION ASSESSMENT-01` (2026-11-25) |
| **Status** | **PROPOSTO — NENHUM SQL ESCRITO OU EXECUTADO.** Decisões P0 aprovadas para detalhamento em 2026-11-26 (seção 0); S1/S2 não iniciados. |
| **Decisão de produto** | Edição colaborativa nas três modalidades (Livre, Master Set, Pokédex), incluindo posição e representante da Pokédex pelo EDITOR. Substitui a opção de retirar a edição da Pokédex da V1-13. |
| **Base conferida** | Versões protegidas implantadas (`e1e-security-evidence/g1/protected/`, manifesto `e1deploy/E1_DEPLOY_MANIFEST.txt`): 5373–5377, 5380, 5382, 5383, 5385–5388, 5323, 5324; funções do titular 5208, 5209, 6122–6126 (`database/schema/`). |
| **Restrições** | Sem SQL executado, sem migration, sem LIVE, barreira CLOSED, modo TEST não autorizado. |

---

## 0. Decisões P0 (2026-11-26, `E3-6 — P0 DECISIONS & F1 READ-ONLY GALLERIES | CONTROLLED CLOSEOUT-01`)

Aprovadas pelo proprietário **para detalhamento** (nenhuma execução):

- **P0-A — identificador opaco (alternativa A), com condições:**
  1. **Geração segura:** HMAC-SHA256 com segredo só do servidor (tabela interna sem políticas nem grants, como a 5389; segredo gerado por `gen_random_bytes`), sobre `allocation_id`, `membership_id` e a **época do papel** (abaixo). Nada derivável só de ids que o EDITOR possa conhecer.
  2. **Escopo:** só a coleção X, a alocação vigente e a participação vigente; aceito só pelas novas RPCs (5391/5392); nenhuma outra função o aceita.
  3. **Não é autorização:** toda escrita reconfere `assert_collection_editor` (EDITOR ACTIVE de X, coleção ativa, barreira); o token só **identifica** o exemplar.
  4. **Invalidação:** desalocar/realocar (nova alocação), remover ou sair (a linha de participação é apagada — 5305/5306 — e o reconvite cria outra), troca de papel e reconvite.
  5. **Reconvite/reutilização da participação (resolvido no desenho):** conferido no código implantado que a mesma linha de participação é reutilizada em dois casos — reconvite com o mesmo papel após recusa (5369: DECLINED → PENDING, mesmo `membership_id`) e troca de papel de membro ativo (5370: `SET role`, sem carimbo de tempo). Nenhuma coluna atual distingue esses ciclos; por isso o token inclui uma **época do papel** (`role_epoch`, inteiro incrementado por gatilho sempre que `role` ou `status` da participação mudam), a criar no pacote S2 sem alterar as funções 5369/5370. Rebaixar e promover de novo, ou recusar e aceitar de novo, invalida todos os tokens anteriores.
- **P0-B — D-E3-8: auditoria obrigatória** das mudanças de posição e de representante da Pokédex. A edição colaborativa da Pokédex não é liberada sem ela. A definir no S2: eventos (posição atribuída, movida, retirada; representante escolhida, substituída, restaurada para a automática); autor (titular ou participante, com o nome de exibição público, como C-241); estado anterior e posterior só com dados autorizados (número da posição e espécie; carta por nome, número e Set — nunca exemplar, alocação, local, condição, valores); operações sem mudança (`UNCHANGED`) não geram evento; visibilidade: titular vê tudo da coleção; participantes de X veem os eventos de X, nas regras de C-241. Aplicável também às ações do titular (fecha, para a Pokédex, a lacuna de autor da 5269).
- **P0-C — D-E3-6: remoção controlada** das capacidades de imagem do EDITOR (preferência por remover, não só esconder). Antes de escolher `DROP` ou `REVOKE` (S1/5390): comprovar dependências (nenhuma função, visão ou política usa `editor_set_collection_cover_logo`; políticas da 5377 isoladas das do titular), privilégios efetivos (`has_function_privilege`, `pg_policies` do bucket) e ausência de regressão do titular (md5 das funções e políticas do titular, envio/troca/remoção pelo titular). Nada executado nesta rodada.

### Observações obrigatórias para o S2 (2026-11-26, `E3-6 — P0/F1 | FINAL REVIEW & LOCAL CLOSEOUT-01`)

Registradas para a proposta SQL; nada implementado.

- **O1 — época do papel:** a proposta S2 precisa provar, no harness, a invalidação dos identificadores em **todas** as transições relevantes: rebaixamento (EDITOR → VIEWER), promoção (VIEWER → EDITOR), rebaixamento seguido de promoção, recusa, reconvite com o mesmo papel (mesma linha, 5369), reconvite com outro papel (linha nova), remoção, saída e mudança de elegibilidade do exemplar (desalocação, realocação para outra coleção, nova alocação na mesma coleção). Em cada caso, um identificador emitido antes deve ser recusado com a recusa neutra, e um emitido depois deve funcionar só se a autorização vigente permitir.
- **O2 — autoria do titular:** gravar eventos com autor (D-E3-8) **não encerra**, por si só, a pendência do autor ausente na leitura 5269. Ela só se encerra quando a experiência do titular conseguir consultar a autoria autorizada (leitura e interface do titular), o que fica explícito como entrega separada no plano.
- **O3 — concorrência:** a comparação do estado esperado (`p_expected_*`) acontece **dentro da mesma transação da escrita, depois das travas** (coleção → alocação → representante, na ordem da 5380), e a escrita só ocorre se o estado travado for igual ao esperado. Uma conferência feita antes, fora da transação ou por leitura separada (padrão TOCTOU, como a mitigação de interface da 5376) **não é aceita** como solução definitiva para a Pokédex.

## 1. Matriz de capacidades por modalidade

Legenda: **T** titular · **E** EDITOR hoje (E2/E3 implementados) · **lacuna** = o que falta e de que tipo.

### 1.1 Fichário (todas as modalidades que têm fichário)

| Operação | T | E (contrato) | E (interface) | Observação |
|---|---|---|---|---|
| Colocar, mover/trocar, retirar | ✔ | ✔ 5374 | ✔ E2-1 | só exemplar alocado a X e guardado no fichário (C-235/C-236) |
| Reservar, liberar, fixar/soltar | ✔ | ✔ 5375 | ✔ E2-2 | |
| Páginas (adicionar, remover, reordenar) | ✔ | ✔ 5382 | ✔ E2-3A | só fichário exclusivo de X (C-237) |
| Abrir/fechar espaço | ✔ | ✔ 5385 | ✔ E2-3B | idem |
| Organização automática | ✔ | ✔ 5386 | ✔ E2-3C | Set, Master Set, Pokédex; Livre não tem (nem o titular) |
| Novidades do Catálogo | ✔ | ✔ 5387 | ✔ E2-3D | só Master Set |
| Referências de espécie (aplicar, remover, mostrar/ocultar) | ✔ 5258 | ✔ **5383** | **✘** | **lacuna de interface** (só Pokédex, fichário exclusivo) — sem SQL novo |

### 1.2 Galeria / posições da coleção

| Modalidade | Operação de organização do titular | Patrimonial? | E (contrato) | E (interface) | Lacuna |
|---|---|---|---|---|---|
| **Livre** | nenhuma além de metadados e fichário (sem posições de catálogo, C-242) | — | metadados 5376 | ✔ E3-3 | **nenhuma** |
| **Master Set** | vincular posições do acervo (`linkMasterSetPositions`), fora do escopo, objetivo | **sim** (alocação) / estrutural (objetivo, C-239) | leitura 5323 | ✔ leitura E3-6 (local) | **nenhuma de organização**: a satisfação deriva do acabamento do exemplar; não há posição atribuível nem representante no Master Set |
| **Pokédex** | vincular do acervo (`link_my_pokedex_copy`, lote 5046) | **sim** (alocação; 6119) | — (só titular, C-242) | — | fora do escopo por contrato |
| | mover a posição de um exemplar já alocado (6122/6123) | não | 5380 `editor_set_pokedex_position_assignment` | ✘ | **lacuna contratual** (identificação do exemplar) |
| | retirar a posição sem desalocar (6124) | não | 5380 `editor_remove_pokedex_position_assignment` | ✘ | **lacuna contratual** |
| | escolher/substituir representante (6125/6126) | não | 5380 `editor_set_pokedex_position_primary_representative` | ✘ | **lacuna contratual** |
| | voltar à escolha automática (clear 6125) | não | 5380 `editor_clear_pokedex_position_primary_representative` | ✘ | **lacuna contratual parcial** (o estado "escolhida × automática" não é legível) |
| | listar exemplares da posição (5209) | leitura com local (`storage_name`) | **nenhuma leitura** | — | **lacuna contratual** |
| | candidatos para a posição (5208, escopo ACERVO) | leitura do acervo | **nenhuma leitura** | — | **lacuna contratual** (só exemplares de X) |

Administração física dos exemplares (alocar, desalocar, local, condição, saída do acervo): **titular em todas as modalidades** (C-243); nenhuma proposta abaixo toca nisso.

## 2. Lacunas comprovadas

**L1 — Pokédex: identificação do exemplar (contratual).** Três das quatro funções da 5380 exigem `p_physical_card_id`; o EDITOR não tem leitura autorizada que diga quais exemplares estão em cada posição nem quais exemplares de X podem ir para ela:

| Função 5380 | Exige | Disponível ao EDITOR hoje | Falta |
|---|---|---|---|
| `editor_set_pokedex_position_assignment(coleção, exemplar, posição, confirmar)` | exemplar de X; posição; espécie (para antecipar `CONFIRMATION_REQUIRED`) | posição (`pokedex_position_id` da 5324) | exemplar; posição atual do exemplar; correspondência de espécie |
| `editor_remove_pokedex_position_assignment(coleção, exemplar)` | exemplar com posição | — | exemplar; lista da posição |
| `editor_set_pokedex_position_primary_representative(coleção, exemplar)` | exemplar com posição | — | exemplares da posição |
| `editor_clear_pokedex_position_primary_representative(coleção, posição)` | posição | posição | saber se há representante escolhida (verificação) |

A 5324 não devolve id de exemplar; a 5373 só lista exemplares guardados no fichário e sem bolso, sem posição Pokédex; a 5386 traz `physical_card_id` só na prévia (descartado no servidor).

**L2 — Pokédex: estado do representante (contratual).** A 5324 devolve a representante efetiva sem dizer se é escolhida (`primary`) ou automática (atribuição mais antiga). Sem isso, "voltar à escolha automática" não pode ser apresentado nem verificado.

**L3 — Pokédex: concorrência de intenção (contratual).** As escritas travam coleção, alocação e representante (sem corrida de dados), mas não recebem o estado que a tela viu: um "mover" sobre uma posição já mudada pelo titular é gravado sem aviso (última escrita vence).

**L4 — Pokédex: auditoria (contratual, decisão).** Posição e representante são dados da coleção, não do fichário: nem o titular (6122–6126) nem a 5380 gravam evento. `assigned_by_user_id` só é gravado em `USER_OVERRIDE`. O titular não saberia o que o EDITOR mudou (soma-se à lacuna do autor na 5269).

**L5 — Referências de espécie pelo EDITOR (interface).** 5383 pronta e implantada; falta interface. Sem SQL.

**L6 — D-E3-6 (segurança, separada).** 5376 `editor_set_collection_cover_logo` e as políticas `collection_cover_insert_editor`, `collection_cover_select_editor`, `collection_cover_delete_editor` da 5377 ainda permitem ao EDITOR gravar, trocar e apagar a imagem da capa por chamada direta. Bloqueia a abertura funcional.

Master Set e Livre: **nenhuma lacuna de organização** além das já cobertas pela E2.

## 3. Proposta — identificação de exemplares na Pokédex

### 3.1 Identificador: token opaco × `physical_card_id`

| Critério | `physical_card_id` direto | **Token opaco (recomendado)** |
|---|---|---|
| Alcance | identificador global e permanente do exemplar | válido só para a coleção X, a alocação vigente e a participação do EDITOR |
| Uso fora do escopo | nenhuma função do titular aceita o EDITOR (todas conferem o dono), mas o id é estável: permite correlacionar o mesmo exemplar entre coleções e no tempo (por exemplo, se o titular movê-lo para outra coleção também compartilhada) | não correlaciona: outra coleção, outra alocação ou outra participação dão outro token; nenhuma função aceita o token fora das novas RPCs |
| Revogação | não expira | morre com a desalocação, a realocação, a remoção ou o reconvite (ver ressalva) |
| Custo | 5380 reaproveitada | escritas novas (wrappers por token) e resolução do token no servidor |
| Coerência | igual à 5373/5374 (o EDITOR já recebe `physical_card_id` dos exemplares colocáveis) | diferente da 5373/5374 (registrar endurecimento futuro dessas) |

Construção (substituída pela P0-A, seção 0): HMAC-SHA256 com segredo do servidor sobre `allocation_id`, `membership_id` e `role_epoch`. A primeira versão desta proposta (hash sem segredo, sem época) foi descartada: a reutilização da linha de participação (5369/5370) reativaria tokens antigos. Resolução: dentro das alocações de X (já travada pela autorização), comparar o HMAC; custo O(n) nas alocações de X, limitado pela posição nas operações de representante/retirada.

### 3.2 Contratos propostos

**5391 — `get_editor_pokedex_position_copies(p_collection_id, p_pokedex_position_id, p_scope, p_limit, p_offset)`** (leitura, STABLE, SECURITY DEFINER, porta 5389)
- Quem: papel real `collection_member_role(X) = 'EDITOR'` (5367: participação ACTIVE com role EDITOR), conferido antes de qualquer leitura e sem travas (função STABLE); qualquer outro → zero linhas. VIEWER não precisa desta leitura (a grade da 5324 basta). As escritas (5392) conferem de novo, com travas, pela `assert_collection_editor` (5376).
- Modalidade Pokédex; posição da Pokédex de X (senão zero linhas).
- `p_scope`: `AT_POSITION` (exemplares de X com esta posição) | `ASSIGNABLE` (exemplares **alocados a X** que podem ir para esta posição: sem posição ou em outra; nunca o acervo).
- Retorno: `copy_token`, `card_name`, `collector_number`, `card_set_code`, `variant_label`, `language_code`, `image_path`, `species_match` (boolean), `current_position_number` (ASSIGNABLE; nulo = sem posição), `assignment_basis` (AT_POSITION), `is_primary_representative`, `is_effective_representative` (AT_POSITION), `total_count`.
- **Nunca:** `physical_card_id`, `collection_allocation_id`, local (`storage_name`), condição, certificação, proveniência, valores, data de entrada no acervo, exemplares fora de X.
- Limite 1–100, deslocamento ≤ 10.000; ordem: AT_POSITION por representante efetiva primeiro e `assigned_at`; ASSIGNABLE por correspondência de espécie, depois nome/Set/número.

**5392 — escritas por token** (VOLATILE, SECURITY DEFINER, porta 5389, `assert_collection_editor` 5376, mesmas travas e regras da 5380):
- `editor_move_pokedex_copy(p_collection_id, p_copy_token, p_pokedex_position_id, p_expected_position_id, p_confirm_override default false)` → `(operation CREATED|MOVED|UNCHANGED, pokedex_position_id, previous_position_id, assignment_basis, representative_cleared boolean)`;
- `editor_unassign_pokedex_copy(p_collection_id, p_copy_token, p_expected_position_id)` → `(operation REMOVED|UNCHANGED, previous_position_id, representative_cleared)`;
- `editor_choose_pokedex_representative(p_collection_id, p_copy_token, p_expected_representative_token default null)` → `(operation SET|REPLACED|UNCHANGED, pokedex_position_id)`;
- `editor_restore_pokedex_automatic_representative(p_collection_id, p_pokedex_position_id, p_expected_representative_token default null)` → `(operation CLEARED|UNCHANGED)`.
- Concorrência (L3): `p_expected_*` = o que a tela viu; diferente do estado travado → `STATE_CHANGED` (22023), nada gravado. `UNCHANGED` antes da checagem de espécie (regra 6122 v1.1). Mover = DELETE + INSERT na mesma transação; a representante da posição antiga sai em cascata (6120) e o retorno diz isso.
- Recusas neutras: `COLLECTION_NOT_FOUND` (sem permissão, indistinguível), `COLLECTION_ARCHIVED`, `NOT_POKEDEX_COLLECTION`, `COPY_NOT_FOUND` (token inválido/obsoleto — mesma recusa para qualquer causa), `POKEDEX_POSITION_NOT_FOUND`, `CONFIRMATION_REQUIRED`, `POKEDEX_ASSIGNMENT_NOT_FOUND`, `STATE_CHANGED`, `CAPABILITY_NOT_ENABLED`.
- Na mesma migration: **revogar `EXECUTE` de `authenticated`** nas quatro funções da 5380 (nunca usadas pela interface; barreira CLOSED desde a implantação) — o EDITOR passa a ter um único caminho, por token. Funções do titular (6123/6124/6126/6125): md5 conferido antes e depois, intocadas.
- Idempotência: repetir a mesma escrita dá `UNCHANGED`; resultado incerto na interface → releitura da posição (5391) e da grade (5324), nunca repetição automática.
- Auditoria (L4): **D-E3-8 decidida (P0-B): obrigatória.** As escritas da 5392 gravam o evento na mesma transação; o desenho da tabela/leitura de eventos entra no S2.

**L2 sem leitura nova da grade:** o estado "escolhida × automática" vem da 5391 (AT_POSITION) no painel da posição; a 5324 não muda.

## 4. Alternativas e riscos

| Alternativa | Prós | Riscos |
|---|---|---|
| **A. Tokens opacos (5391 + 5392, revoga 5380)** — recomendada | menor exposição; sem correlação entre coleções; revogação natural | custo de resolução O(n) por escrita (não medido); mais uma família de funções para homologar |
| B. `physical_card_id` (só a leitura 5391; reutiliza 5380 + parâmetros esperados numa 5392 menor) | menos SQL; coerente com 5373/5374 | id global e permanente no navegador do EDITOR; correlação entre coleções |
| C. Só "voltar à escolha automática" (5380 clear) + leitura do estado | quase sem SQL | não atende a decisão de produto (sem mover nem escolher) |

Riscos comuns: (R-a) desempenho das leituras e da resolução não medido; (R-b) a cascata da representante ao mover surpreende — a interface precisa dizer; (R-c) sem auditoria (L4) o titular não vê mudanças do EDITOR; (R-d) S1–S10 e S8 concorrente continuam pendentes para toda a V1-13.

## 5. SQL necessário (a escrever só depois da aprovação)

| Nº | Pacote | Conteúdo | Depende de | Validação |
|---|---|---|---|---|
| **5390** | **D-E3-6 (separado)** | `revoke execute` de `authenticated` em `editor_set_collection_cover_logo` (ou `drop function`, decisão na proposta); `drop policy` `collection_cover_insert_editor`, `collection_cover_select_editor`, `collection_cover_delete_editor`; precheck: nenhum objeto enviado por EDITOR no bucket (contagem somente leitura) e md5 das funções/políticas do titular | 5376, 5377 | harness: EDITOR recusado na função e no Storage (insert/select/delete); titular envia, troca e remove; nome/descrição/cor/código do EDITOR intactos; barreira e registro inalterados |
| **5391** | Pokédex — leitura | `get_editor_pokedex_position_copies` (§3.2) + ajudante interno de token (sem EXECUTE para a API) | 5324 (escopo), 5367 (papel), 5389 | harness: matriz de papéis, privacidade das colunas, escopo ASSIGNABLE só de X, token estável na sessão e inválido após desalocar/remover/reconvidar |
| **5392** | Pokédex — escritas | quatro escritas por token (§3.2) + `revoke` das quatro da 5380 | 5380 (regras), 5391 (token), 6118–6121 (gatilhos) | harness: operações, `UNCHANGED`, `STATE_CHANGED`, `CONFIRMATION_REQUIRED`, cascata da representante, rebaixamento entre leitura e escrita, coleção arquivada, outra coleção, token de outro membro, md5 do titular |

Cada pacote segue STD-001 §10 (Query → Objetivo → Script → Resultado esperado → Como validar), com versão protegida pela porta 5389, rollback próprio, static check e harness em ensaio local antes de qualquer pedido de execução.

## 6. Plano incremental

1. **P0 — aprovação** desta proposta e das decisões: identificador (A/B), auditoria (D-E3-8), `revoke` × `drop` na 5390.
2. **F1 — versionar a leitura já pronta** (galerias de Master Set e Pokédex do participante, E3-6 local): compatível com tudo abaixo; sem SQL.
3. **F2 — referências de espécie pelo EDITOR** (5383) no fichário compartilhado da Pokédex: só interface (L5).
4. **S1 — proposta SQL 5390** (D-E3-6), pacote isolado.
5. **S2 — proposta SQL 5391/5392** (Pokédex), static check + harness local.
6. **D — implantação** de 5390–5392 com autorização específica (barreira continua CLOSED).
7. **F3 — painel da posição para o EDITOR** na Pokédex compartilhada: `PokedexGrid` ganha um painel injetável (como `loadMoreAction`), lista AT_POSITION/ASSIGNABLE, mover, retirar a posição, escolher e voltar à escolha automática; nada otimista, releitura depois de cada escrita.
8. **E4 — homologação** conjunta (modo TEST autorizado à parte): toda a V1-13, incluindo 5390–5392.

## 7. Testes e homologação

- **Harness SQL (ensaio local, simulado):** papéis (anon, não membro, convite pendente/recusado, VIEWER, EDITOR ativo, EDITOR rebaixado, removido, titular), coleção arquivada, outra modalidade, outra coleção, barreira CLOSED (zero linhas / `CAPABILITY_NOT_ENABLED`), colunas proibidas ausentes, tokens (estáveis, opacos, inválidos fora do contexto), concorrência em duas sessões (dois movimentos do mesmo exemplar; titular × EDITOR na representante), idempotência, cascata, md5 do titular.
- **Interface (simulada):** estados de carregamento, vazio, erro, `STATE_CHANGED`, `CONFIRMATION_REQUIRED`, resultado incerto sem repetição, VIEWER sem controles, configuração desligada = página atual.
- **Homologação real (E4):** S1–S10 da E1 + cenários acima com JWT real, desktop e celular, temas claro e escuro. Nada disso é declarado validado antes de executado.

**Critérios de aceitação (Pokédex):** EDITOR ativo move, retira a posição, escolhe e restaura a representante só com exemplares de X; VIEWER, ex-membro e outra coleção recusados ou sem linhas; nenhum dado protegido nas respostas; nenhuma alocação criada ou desfeita; titular inalterado; recusas neutras; nenhuma escrita repetida automaticamente.

## 8. D-E3-6 — tratamento separado

Reconfirmado: produto = imagem da capa **só do titular** (D-E3-6); contrato técnico = 5376/5377 ainda autorizam o EDITOR. Correção mínima = **5390** (§5), pacote próprio, independente da Pokédex, podendo entrar na mesma janela de implantação e de homologação. Até lá a restrição é só da interface e **não é garantida pelo servidor**; continua bloqueando qualquer abertura funcional da barreira.

## 9. Impacto no cronograma

Sem datas: em rodadas. Antes: E3-6 (leitura) → E3-7 → E4. Agora: F1 e F2 (interface, 1–2 rodadas) podem seguir em paralelo a S1/S2 (2 rodadas de proposta + revisão); implantação D (1 rodada controlada); F3 (1–2 rodadas); E3-7 depois de F3 ou em paralelo, por decisão; E4 recebe 5390–5392 no escopo. Acréscimo estimado: 4–6 rodadas até a E4.

## 10. Implementação parcial existente

As galerias da E3-6 (local, não versionadas) continuam como estão e são compatíveis: a grade da Pokédex já aceita fonte de "Mostrar mais" injetada e pode receber o painel do EDITOR do mesmo modo (F3); o Master Set não muda (sem lacuna de organização).
