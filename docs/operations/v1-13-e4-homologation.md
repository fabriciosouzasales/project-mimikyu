# V1-13 — Matriz de homologação E4 (Compartilhamento com EDITOR)

| Campo | Valor |
|---|---|
| **Documento** | Roteiro operacional da E4 (homologação integrada da V1-13) |
| **Versão** | 1.3 (2026-11-27, abertura funcional) |
| **Status** | **EXECUTADA — PASS (2026-11-27), com pendências não bloqueantes (D-E4-4 parcial, higiene do Storage).** TEST aberto e encerrado pelo executor; barreira CLOSED com 0 identidades ao fim; D1 desligada. Resultado na seção "Resultado". Roteiro executável (sequência, identidades, ativação e encerramento, sonda, critérios, autorizações): `database/proposals/2026-11-27-v1-13-e4-homologation/README.md`. |
| **Normas** | C-234–C-244 (matriz de papéis, segurança); `05d` §"E2–E4"; STD-005 §6 (homologação progressiva) |

## Pré-requisitos

1. **Autorização expressa** da E4. Ela abre o modo TEST da barreira 5389 só para as identidades de teste registradas: titular T, EDITOR E, VIEWER V e um segundo EDITOR E2 para concorrência. Ao fim, a barreira volta a CLOSED com zero identidades. Nada disso é automático.
2. **Front publicado** com a configuração `MMKYU_V113_EDITOR_CURATION` ligada **só no ambiente da homologação**.
3. **Dados:** coleções de teste do próprio T, nas quatro modalidades (Standard Set, Master Set, Pokédex e coleção livre), com fichário, exemplares fora de bolso e volume representativo. Fotos antes e depois para a restauração.
4. **Registro:** cada caso ganha resultado (PASS, FAIL ou NÃO EXECUTADO), papel, horário UTC e evidência, sem dados pessoais. Nada vira PASS sem execução registrada.

## Matriz

**O** = obrigatório para a liberação; **N** = não bloqueante (melhoria ou observação).

| ID | Área | Caso | Papéis | Esperado | |
|---|---|---|---|---|---|
| A1 | Papéis | Cada papel abre as quatro modalidades da coleção compartilhada | T, E, V | T vê tudo; E vê os controles de curadoria; V só lê; nenhum vê dado patrimonial de outro usuário | O |
| A2 | Papéis | Usuário sem participação abre a URL direta e chama a RPC direto | externo | Recusa neutra, sem revelar se a coleção existe | O |
| B1 | Convites | T convida como EDITOR e como VIEWER; aceite; recusa; convite expirado ou revogado | T, E, V | Papel correto depois do aceite; convite revogado não vale | O |
| B2 | Convites | T troca o papel E→VIEWER e VIEWER→EDITOR | T, E | Controles mudam no próximo carregamento; escrita antiga recusada | O |
| B3 | Convites | T remove a participação de E | T, E | E perde o acesso de leitura e de escrita imediatamente | O |
| C1 | Fichário | E coloca uma carta elegível num bolso livre (ADD) e substitui uma carta de X (REPLACE) | E | Bolso atualizado; evento com autor E | O |
| C2 | Fichário | E move e troca cartas entre bolsos permitidos; tenta um bolso de outra coleção ou travado | E | Permitido conclui; proibido recebe `SLOT_NOT_EDITABLE` ou `SLOT_LOCKED` | O |
| C3 | Fichário | E retira uma carta e usa "Desfazer" | E | A carta volta ao mesmo bolso pelo token; a lista de elegíveis fica coerente | O |
| C4 | Fichário | E faz a prévia e aplica a organização automática; T altera o fichário entre a prévia e a aplicação | E, T | Aplicação concluída com o plano válido; plano obsoleto recusado | O |
| C5 | Fichário | Reservas, fixação, páginas (adicionar, remover, reordenar), abrir e fechar espaço, novidades do Catálogo | E | Comportamento da E2-2 e E2-3; recusa nos bolsos do titular | O |
| D1 | Pokédex | E move, desvincula e escolhe a representante; restaura a escolha automática | E | Estado esperado conferido; recusa quando a tela está desatualizada; evento por resultado efetivo | O |
| D2 | Pokédex | E tenta uma posição fora do escopo de gerações | E | Recusa | O |
| E1 | Tokens | Reenviar um token alterado, um UUID ou um token de outra coleção (fichário e Pokédex) | E | `PHYSICAL_CARD_NOT_ELIGIBLE` ou recusa equivalente, sem o motivo | O |
| E2 | Tokens | E2 usa um token emitido para E | E2 | Recusado (outra participação) | O |
| E3 | Tokens | Trocar o papel de E (EDITOR→VIEWER→EDITOR) e reenviar o token anterior | T, E | Recusado (época anterior); a lista nova traz tokens novos | O |
| F1 | Privacidade | Chamar a 5373 e a 5374 antigas como E e como V | E, V | Sem EXECUTE (erro de permissão) | O |
| F2 | Privacidade | Inspecionar as respostas da 5397, da prévia 5386, da Pokédex 5391 e dos históricos | E, V | Nenhum `physical_card_id`, alocação, inventário, local ou dado de outro usuário | O |
| F3 | Privacidade | VIEWER chama qualquer RPC de escrita do EDITOR | V | Recusa; nada gravado | O |
| F4 | Privacidade | Fora do TEST (barreira CLOSED), chamar as RPCs de leitura e de escrita do EDITOR | E | Leituras vazias e escritas com `CAPABILITY_NOT_ENABLED` | O |
| G1 | Concorrência | E e E2 colocam no mesmo bolso, ou o mesmo exemplar em bolsos diferentes, ao mesmo tempo | E, E2 | Uma conclui; a outra recebe recusa clara; sem duplicata | O |
| G2 | Concorrência | E e T editam a mesma posição da Pokédex e a mesma página ao mesmo tempo | E, T | Estado esperado protege; tela informa e recarrega | O |
| H1 | Histórico | Cada operação efetiva de C, D e espécies aparece com o tipo certo, e com o autor onde o contrato o entrega (5388 para participantes; `get_collection_activity` para titular e participantes); as sem efeito não aparecem | T, E, V | Tipo e autor corretos; V vê o escopo permitido; sem resumo patrimonial. No histórico do **fichário do titular** (5269) o autor não é exibido: registrar "D-E3-2", sem FAIL (pendência de publicação). *Resolvido no reteste pela 5398 (2026-11-27).* | O |
| H2 | Histórico | Filtros (incluindo `SPECIES`) e paginação "ver mais" | T, E | Coerentes com os eventos gravados | N |
| I1 | Mobile e acessibilidade | Fluxos C1–C4 e D1 no celular (toque, alvos de 44 px), teclado, foco visível, leitor de tela nos avisos | E | Utilizável sem mouse; avisos anunciados | O |
| I2 | Visual | Light e Dark, desktop e celular, Design System MMKYU | todos | Sem quebra visual | O |
| I3 | Visual | Refinamentos de microcópia, densidade e motion | todos | Registrar sugestões | N |
| J1 | Regressão | T faz posicionar, mover e retirar, organização automática, Pokédex, Acervo, Locais e compartilhamento V1-12 | T | Inalterados (o titular continua com o próprio acervo) | O |
| J2 | Regressão | Configuração desligada: nenhuma função do EDITOR aparece | E | Coleção compartilhada só de leitura, como na V1-12 | O |
| K1 | Desempenho | Tempo da lista de elegíveis (5397) e da colocação com coleção grande (≥ 500 alocações; 1 HMAC por alocação), medido pela sonda | E | ≤ 1500 ms cada = PASS; 1500–3000 ms = observação; > 3000 ms = FAIL | O |
| K2 | Desempenho | Tempos das demais RPCs com volume real | E, T | Registrar | N |
| L1 | Segurança da E1 | Prova S1–S10 da E1 (S8 concorrente, S10, PR-04B) executada e aprovada | — | C-244: a publicação fica bloqueada sem ela | O |

## Encerramento

- Barreira volta a CLOSED com zero identidades TEST, conferida por leitura.
- Configuração desligada fora da homologação, até a decisão de publicação.
- Dados de teste restaurados.
- O resultado vai para `docs/log.md` e para o `05d`. Qualquer FAIL obrigatório bloqueia a liberação e abre uma rodada de correção.

## Resultado (2026-11-27)

Executada com as quatro contas reais do conjunto (titular, dois EDITOR e um VIEWER; identificadas no pacote só por md5), sobre coleções existentes do titular, pelo frontend e pela sonda de JWT real. Detalhe cronológico em `docs/log.md` (entradas "V1-13 / E4").

| Bloco | Casos | Resultado |
|---|---|---|
| Barreira e negação | F4 (sonda G3 antes e depois, 15/15 cada) | PASS |
| Papéis e convites | A1, A2, B1–B3 | PASS |
| Fichário pelo EDITOR | C1–C5 | PASS (achados de interface corrigidos; ver abaixo) |
| Pokédex pelo EDITOR | D1 | PASS |
| | D2 | Não aplicável (coleções do conjunto cobrem todas as gerações) |
| Tokens e privacidade | E1–E3, F1–F3 (sonda TEST 47/47; E4-33 trocado por `editor_set_collection_cover_logo` → recusa, com aprovação do proprietário) | PASS |
| Concorrência | G1, G2 | PASS |
| Histórico | H1, H2 | PASS; autor no fichário do titular entregue pela 5398 (D-E3-2) e confirmado no reteste |
| Celular e visual | I1, I2 | PASS depois do reteste (D-E4-7, D-E4-8 e responsividade dos heróis) |
| | I3 | Observações aplicadas (404 com identidade MMKYU, textos de recusa e de recusados) |
| Regressão | J1, J2 | PASS |
| Desempenho | K1 (112 e 126 ms) | PASS |
| Segurança da E1 | L1: S1–S10 e PR-04B na mesma conta | PASS; PR-04B entre contas não aplicável |

**Achados de interface (rodada de correção e reteste, TEST reaberto pelo mesmo manifesto):** D-E4-1 (o EDITOR organiza dentro da sobreposição), D-E4-2, D-E4-3, D-E4-5, D-E4-6 (painel Compartilhar reorganizado: nome de usuário primeiro), D-E4-7 e D-E4-8 corrigidos e confirmados pelo proprietário. Também no reteste: cabeçalho da Pokédex compartilhada com o mesmo palco do titular (equipe pelos favoritos de quem vê).

**Pendências registradas (não bloqueiam a E4):**

- **D-E4-4 (parcial):** a aplicação da organização automática pelo EDITOR grava no banco, mas a resposta HTTP às vezes não volta ao servidor do app. A espera foi limitada a 15 s, e a tela cai no aviso "pode ter sido concluída", com "Atualizar prévia". Causa da resposta perdida em aberto; o banco respondeu em menos de 1 s.
- **Higiene do Storage:** `collection_cover_insert_own` valida só a primeira pasta do caminho; um usuário consegue enviar para a própria pasta fora do formato esperado. Não é escrita entre contas.
- **Palco da Pokédex compartilhada (limitação conhecida):** o escopo do sorteio da equipe usa as gerações da primeira página lida da grade (5324, com o filtro da URL). Numa Pokédex parcial com várias gerações, a equipe pode sair de parte delas; não envolve dado de outro usuário.
- **Dados de teste:** papéis e convites usados na homologação continuam como ficaram; limpeza opcional, a critério do proprietário.

**Abertura funcional (etapa 7):** G5 = GO; barreira OPEN pelo executor (run-20261128T024029Z), D1 em Production e conferência em produção PASS. Pacote e reversão: `database/proposals/2026-11-27-v1-13-g5-barrier-open/`.

**Encerramento conferido:** run-20261128T020010Z (PRE PASS, escrita exit 0, POST PASS) e conferência só leitura depois: barreira CLOSED, 0 identidades TEST, funções da barreira canônicas. D1 removida do `.env.local`; no Vercel nunca esteve ligada.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-11-27).** Matriz enxuta da E4 depois da 5397 (P0 do fichário): 31 casos (28 obrigatórios, 3 não bloqueantes), pré-requisitos e encerramento. |
| 1.1 | **Prontidão de execução (2026-11-27).** H1 alinhado ao contrato (autor do fichário do titular = D-E3-2, pendência de publicação, não FAIL da E4); K1 com limite objetivo; vínculo ao roteiro executável do pacote E4. |
| 1.2 | **Encerramento da E4 (2026-11-27).** Status EXECUTADA — PASS; seção Resultado por bloco, achados corrigidos no reteste, pendências não bloqueantes (D-E4-4 parcial, higiene do Storage, dados de teste) e conferência do encerramento. |
| 1.3 | **Abertura funcional (2026-11-27).** Registro da etapa 7: G5 = GO, barreira OPEN, D1 em Production, conferência em produção PASS. |
