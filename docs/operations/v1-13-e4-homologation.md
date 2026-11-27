# V1-13 — Matriz de homologação E4 (Compartilhamento com EDITOR)

| Campo | Valor |
|---|---|
| **Documento** | Roteiro operacional da E4 (homologação integrada da V1-13) |
| **Versão** | 1.0 (2026-11-27, `E3-7b / 5397 — PASS-LIVE CLOSEOUT & E4 HANDOFF-01`) |
| **Status** | **PREPARADA — NÃO EXECUTADA.** Exige autorização própria para o modo TEST da barreira. |
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
| H1 | Histórico | Cada operação efetiva de C, D e espécies aparece com o autor certo; as sem efeito não aparecem | T, E, V | Autor e tipo corretos; V vê o escopo permitido; sem resumo patrimonial | O |
| H2 | Histórico | Filtros (incluindo `SPECIES`) e paginação "ver mais" | T, E | Coerentes com os eventos gravados | N |
| I1 | Mobile e acessibilidade | Fluxos C1–C4 e D1 no celular (toque, alvos de 44 px), teclado, foco visível, leitor de tela nos avisos | E | Utilizável sem mouse; avisos anunciados | O |
| I2 | Visual | Light e Dark, desktop e celular, Design System MMKYU | todos | Sem quebra visual | O |
| I3 | Visual | Refinamentos de microcópia, densidade e motion | todos | Registrar sugestões | N |
| J1 | Regressão | T faz posicionar, mover e retirar, organização automática, Pokédex, Acervo, Locais e compartilhamento V1-12 | T | Inalterados (o titular continua com o próprio acervo) | O |
| J2 | Regressão | Configuração desligada: nenhuma função do EDITOR aparece | E | Coleção compartilhada só de leitura, como na V1-12 | O |
| K1 | Desempenho | Tempo da lista de elegíveis (5397) e da colocação com coleção grande (1 HMAC por alocação) | E | Dentro do limite combinado; registrar o tempo | O |
| K2 | Desempenho | Tempos das demais RPCs com volume real | E, T | Registrar | N |
| L1 | Segurança da E1 | Prova S1–S10 da E1 (S8 concorrente, S10, PR-04B) executada e aprovada | — | C-244: a publicação fica bloqueada sem ela | O |

## Encerramento

- Barreira volta a CLOSED com zero identidades TEST, conferida por leitura.
- Configuração desligada fora da homologação, até a decisão de publicação.
- Dados de teste restaurados.
- O resultado vai para `docs/log.md` e para o `05d`. Qualquer FAIL obrigatório bloqueia a liberação e abre uma rodada de correção.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-11-27).** Matriz enxuta da E4 depois da 5397 (P0 do fichário): 31 casos (28 obrigatórios, 3 não bloqueantes), pré-requisitos e encerramento. |
