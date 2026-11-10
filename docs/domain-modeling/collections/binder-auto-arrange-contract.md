# Fichário — Contrato funcional da organização automática (P2)

| Campo | Valor |
|--------|-------|
| **Documento** | Contrato funcional e SQL da organização automática do fichário |
| **Arquivo** | `docs/domain-modeling/collections/binder-auto-arrange-contract.md` |
| **Versão** | 1.6 |
| **Status** | Decisões APROVADAS (C-220–C-226). **Fundação SQL HOMOLOGADA no LIVE** (`P2 SQL FOUNDATION CLOSEOUT-16`, 2026-11-01): 5341–5344 canônicas em `database/schema/`, evidências em `database/proposals/2026-11-01-binder-auto-arrange/README.md`. **Interface P2 UI E1–E4 implementada localmente e homologada visualmente** (`P2 UI E4 FINAL CLOSEOUT-05`, 2026-11-01); `npm run lint`/`npm run build` da E4 pendentes no Windows. **Primeira aplicação real executada** no ME3 (147 inserções, `POST-APPLICATION INTEGRITY PASS`). Sem feature flag adicional (decisão do proprietário, §9). **Extensão à Pokédex CONFIRMADA EXECUTADA no LIVE e homologada por Fabrício** (2026-11-09, 5360; §10). |
| **Criado em** | 2026-11-01 (`Binder · P2 AUTO-ARRANGE SQL FOUNDATION-06`) |
| **Base** | `AUTO-ARRANGE PRODUCT DECISION-02A`; `P2 LIVE ELIGIBILITY DIAGNOSIS-05` (read-only); C-42–C-44, C-191–C-197, C-201–C-209 |
| **Relacionados** | `concept-decisions.md` (C-220–C-226), `docs/05d-colecoes-e-usuarios.md` (seção "Fichário — Organização automática (P2)"), `place_my_physical_card_in_slot` (5272), histórico 5267–5271 |

---

## 1. O que é

Uma ação do fichário que posiciona, de uma vez, os exemplares do colecionador nos bolsos que já estão reservados para eles — só quando a correspondência é inequívoca. O colecionador vê a prévia, confirma, e o sistema cria as posições. Nada é substituído, removido, movido ou reservado.

## 2. Elegibilidade

| Elemento | Regra |
|---|---|
| Coleção | Set, Master Set ou Pokédex (`REFERENCE_BASED` + `STANDARD_SET`/`MASTER_SET`/`REFERENCE_POSITION`), ativa, do titular. Livre → recusa. Regras da Pokédex na §10. |
| Fichário | O da própria coleção (proprietária). Coleção convidada → recusa. |
| Exemplar candidato | Alocado à coleção proprietária; guardado no local do fichário; inventário do titular; fora de qualquer bolso. |
| Bolso destino | Página do fichário; reserva da proprietária (`collection_id` nulo ou igual à proprietária); vazio; não travado; sem imagem; fora de mesclagem. |
| Compatibilidade | Mesma carta; e variante exata quando a reserva fixa variante; e acabamento quando a reserva fixa acabamento. |
| Correspondência | 1:1 estrito nos dois sentidos, sobre todos os pares compatíveis. Variante inativa conta para ambiguidade e nunca é posicionada. |

Motivos devolvidos na prévia — exemplares: `INACTIVE_VARIANT`, `NO_COMPATIBLE_RESERVATION`, `MULTIPLE_DESTINATIONS`, `COMPETING_CANDIDATES`, `NOT_REPRESENTATIVE` (só Pokédex, §10); bolsos: `NO_CANDIDATE`, `COMPETING_CANDIDATES`, `MULTIPLE_DESTINATIONS`, `INACTIVE_VARIANT`. A interface traduz para linguagem de colecionador (ex.: "duas cópias disputam este bolso — escolha uma manualmente").

## 3. Contrato SQL (homologado)

| Objeto | Papel | Acesso |
|---|---|---|
| `binder_auto_arrange_plan(collection, layout, container)` (5342) | Plano determinístico, somente leitura, com token `aa1:` | Interna — sem EXECUTE para nenhum papel de API |
| `preview_my_binder_auto_arrange(collection) → jsonb` (5343) | Prévia: `status` READY/EMPTY/LIMIT_EXCEEDED, `insert_count`, `limit` 500, `plan_token`, contagens por motivo, `pages`, `items` (≤ 500) | `authenticated` |
| `apply_my_binder_auto_arrange(collection, token) → jsonb` (5344) | Confirmação atômica: `APPLIED` (`inserted`, `event_id`, `pages`) / `NOTHING_TO_DO` / `ALREADY_APPLIED` (`inserted` 0, `event_id` da aplicação original) | `authenticated` |
| Tipo `CARDS_AUTO_ARRANGED` (5341) | Evento do histórico, categoria Cartas | — |

Erros: `28000` sem sessão; `22023 INVALID_ARGUMENT`; `P0002 COLLECTION_NOT_FOUND` (inexistente ou alheia, colapsadas); `55000 COLLECTION_ARCHIVED`; `22023 AUTO_ARRANGE_UNSUPPORTED_COLLECTION`; `42501 AUTO_ARRANGE_NOT_BINDER_OWNER`; `P0002 BINDER_NOT_FOUND`; `40001 AUTO_ARRANGE_PLAN_CHANGED`; `54000 AUTO_ARRANGE_LIMIT_EXCEEDED`; `55P03` (trava ocupada além de 5 s). Todo erro desfaz a transação inteira. `40P01` (deadlock) não foi observado; se ocorrer, também desfaz tudo. Os três erros de concorrência têm tratamentos distintos na interface (§7): `40001` = plano alterado; `55P03` = trava ocupada (contenção temporária); `40P01` = falha transitória de concorrência. A semântica SQLSTATE das RPCs não muda.

## 4. Token e identidade da operação

`aa1:` + SHA-256 de versão, coleção, fichário, local, **época**, quantidade e lista ordenada de pares `slot|exemplar` a inserir. Exclusões não entram: o usuário confirma exatamente o conjunto de inserções. **Época** = id do último evento `CARDS_AUTO_ARRANGED` do fichário e titular (0 se nenhum) + marco de cobertura do histórico (`binder_activity_coverage`: motivo e instante). Toda aplicação muda o id; toda limpeza do histórico (5270) apaga os eventos e regrava o marco na mesma transação. Assim um token já emitido nunca volta a coincidir com um plano recalculado depois de uma aplicação ou de uma limpeza.

| Conceito | Representação |
|---|---|
| Plano determinístico | resultado da 5342 sobre o estado atual + época |
| Tentativa de confirmação | chamada da 5344 com um token |
| Operação aplicada | evento `CARDS_AUTO_ARRANGED` com `summary.plan_token` |
| Repetição da mesma confirmação | token ≠ plano atual **e** presente num evento do fichário → `ALREADY_APPLIED`, nada escrito |
| Nova intenção após mudanças legítimas | exige nova prévia (token novo, porque a época mudou), mesmo que os pares sejam iguais |

Casos: repetição imediata, resposta perdida e duas confirmações simultâneas (a segunda espera a trava da coleção e vê o commit da primeira) → `ALREADY_APPLIED`; token desconhecido ou estado mudado → `PLAN_CHANGED`. Depois de uma limpeza do histórico, qualquer token anterior recebe `PLAN_CHANGED` (o evento que provaria a aplicação foi apagado): nunca é tratado como nova autorização; a nova intenção exige nova prévia. A aplicação recalcula o token duas vezes (depois da trava da coleção e depois das travas de bolsos e exemplares).

## 5. Concorrência

Ordem de travas: coleção proprietária `FOR UPDATE` (via `assert_collection_layout_mutable`) → bolsos do plano `FOR UPDATE` por id → exemplares do plano `FOR UPDATE` por id → evento → inserções. `lock_timeout` 5 s; exige READ COMMITTED.

- **Escritores que podem invalidar um par** serializam conosco: pela coleção proprietária (todos os escritores do fichário, inclusive os de convidadas, novidades do catálogo, lacunas, mesclagem/imagem, desmontagem, transferência; alocar e desalocar travam a coleção-alvo) ou pelo exemplar (mudança de local, organização de local da coleção, remoção do exemplar).
- **Escritores que só acrescentam candidatos ou liberam bolsos** (cadastro em lote no local, entrada/saída de outros exemplares, desativação de variante pelo catálogo) não bloqueiam; se confirmarem depois do 2º recálculo, o resultado equivale à ordem serial "organizar, depois a outra operação".
- **Integridade física** independe disso: UNIQUE de exemplar (imediata), UNIQUE de bolso (verificada no COMMIT) e o gatilho 5248 (dono e local do exemplar) impedem dupla atribuição ou posição inválida em qualquer intercalação.
- A ambiguidade (regra 1:1) é avaliada no ponto de serialização; um exemplar novo que chegue depois não desfaz uma posição já criada.

## 6. Histórico

Um evento `CARDS_AUTO_ARRANGED` (fonte Fichário, coleção proprietária, resumo `{plan_token, inserted}`) com um item `CARD/PLACED` por carta, na ordem física. Teto de itens da 5268 cobre 500. Prévia, vazio, limite, divergência e repetição não geram evento. **Dependência de frontend:** `web/lib/colecoes/binder-activity.ts` precisa aprender o novo tipo antes da publicação do botão.

## 7. Experiência (implementada em P2 UI E1–E4)

Ação "Organizar automaticamente" no fichário de Set/Master Set → prévia com contagem do que entra, do que fica de fora agrupado por motivo e páginas afetadas → confirmar → feedback com quantidade posicionada e atalho para a primeira página afetada. Plano vazio: mensagem explicando que não há correspondência inequívoca. Limite: explicar que mais de 500 cartas exigem organização em etapas (travar páginas ou organizar parte manualmente). Erros de concorrência — nenhum deles grava nada, e a interface nunca repete uma escrita automaticamente:

- **`40001 AUTO_ARRANGE_PLAN_CHANGED` (plano alterado):** informar que a prévia perdeu a validade ("o fichário mudou desde a prévia"); obter uma nova prévia; exigir nova confirmação explícita antes de aplicar.
- **`55P03` (timeout de trava):** informar indisponibilidade temporária ("o fichário está sendo alterado agora"); oferecer "Tentar novamente", que começa por revalidação (nova prévia); não repetir a escrita sozinha.
- **`40P01` (deadlock):** informar falha temporária; oferecer nova tentativa controlada, iniciada por revalidação (nova prévia); não repetir a escrita sozinha.

Em qualquer nova tentativa: se a revalidação devolver um plano diferente (outro `plan_token`), mostrar a prévia revista e exigir confirmação explícita; a aplicação só é chamada depois de uma ação explícita do usuário. Nunca reenviar o mesmo token em laço.

## 8. Fora do escopo

Desempate automático, substituição/troca, movimentação, criação de reservas, Livre, coleções convidadas, organização parcial acima do limite.

## 9. Homologação, evidências e riscos residuais

**Estado:** fundação SQL homologada (`P2 SQL FOUNDATION CLOSEOUT-16`, 2026-11-01). Detalhe e números completos no README da proposta (seções GATE 01–04).

| Gate | Resultado |
|---|---|
| GATE 01 — preflight somente leitura | PASS (baseline FP de 17 tabelas) |
| GATE 02 / RESUME-13 — migrations | 5341–5344 aplicadas (ledger `20261101135916`, `…140019`, `…140115`, `…141543`); 5344 v1.3 corrige o tratamento de `55P03` |
| GATE 03 — harness 5872 v1.4 | **FAIL 48/54** (histórico preservado): C.1–C.6 não chegaram à 5344 por defeito do próprio harness |
| GATE 03 RERUN-15 — harness 5872 v1.5 | **PASS 54/54**, rollback integral (TR000), resíduo zero, C.1–C.6 com `40001 AUTO_ARRANGE_PLAN_CHANGED` e zero escrita |
| GATE 04 — postcheck + medição | POST-1…7 PASS; corpos = arquivos; FP das 17 tabelas idêntico; advisors sem achado novo; ME3 somente leitura |

Evidências:
- **Segurança:** anon recebe 42501; sem identidade, 28000; outro usuário recebe `COLLECTION_NOT_FOUND` sem escrita; a função interna 5342 não tem EXECUTE para nenhum papel de API; DEFINER com `search_path` vazio.
- **Integridade:** idempotência (`ALREADY_APPLIED`) e época do token, inclusive após limpeza do histórico; limite 500 com `54000` sem escrita; não interferência em reservas, travas, alocações, locais e posições anteriores.
- **Desempenho:** prévia sintética de 501 × 504 em 86 ms; aplicação de 500 em 500 ms; ME3 real com 148 inserções previstas (= diagnóstico 05), 31 bolsos `NO_CANDIDATE`, execução em 43,3 ms e 1.088 buffers em cache.

**Não provado (não é PASS):** concorrência real entre sessões K-M1–K-M3 (o harness cobre só equivalentes seriais) e a espera de trava / `55P03` sob contenção real.

| # | Risco residual | Mitigação | Consequência |
|---|---|---|---|
| R1 | Espera real sob contenção não medida | `lock_timeout` 5 s; travas curtas | `55P03`, nada escrito; indisponibilidade temporária, nova tentativa oferecida, iniciada por revalidação (§7) |
| R2 | Deadlock com escritor fora da matriz auditada | ordem coleção → bolsos → exemplares; par K-M3 acíclico | `40P01`, nada parcial; falha temporária, nova tentativa controlada, iniciada por revalidação (§7) |
| R3 | Candidato acrescentado entre o 2º recálculo e o INSERT | equivale a "organizar, depois a outra operação" | fica para a próxima prévia |
| R4 | Uma subtransação por INSERT (até 500) | transação curta; medido em P.6/L.3 | custo de CPU proporcional |
| R5 | Volume real futuro maior que o ME3; estimativa baixa do planejador em `ins` (laço aninhado quadrático) | teto de 500; M2 no ME3 + P.6 sintético | reavaliar se o limite mudar ou surgirem fichários muito maiores |

**Condição de uso real (histórico):** a primeira aplicação sobre exemplares reais (inclusive no ME3) exigia interface implementada e homologada e autorização explícita do proprietário. Ela ocorreu durante a homologação da E4, antes da autorização específica de execução real, e foi auditada a seguir (abaixo).

### Interface (P2 UI E1–E4) e primeira aplicação real

- **Interface:** prévia somente leitura no painel lateral/faixa inferior (E3); revisão no próprio painel com quantidade, páginas e garantias e a confirmação explícita "Confirmar e posicionar" (E4), única chamada a `applyAutoArrange` (coleção + token); bloqueio de duplo clique; escritas do fichário travadas durante a aplicação; resultado incerto revalidado só por leitura; `40001` → nova prévia; `55P03`/`40P01`/`57014` → nova tentativa pedida que começa por revalidação; nenhum plano novo confirmado sozinho. "Posicionar cartas" e "Confirmar e posicionar" ficam indisponíveis, com o motivo, enquanto outra escrita local estiver em curso (`CLOSEOUT-05`).
- **Homologação visual da E4:** aprovada pelo proprietário (2026-11-01). `npm run lint` e `npm run build` da E4 **pendentes** no Windows (não declarados PASS).
- **Primeira aplicação real** (ME3, 2026-11-01, `P2 REAL APPLICATION POSTCHECK-03`, auditoria somente leitura): 1 evento `CARDS_AUTO_ARRANGED`; **147 inserções** em 20 páginas, todas em bolsos reservados compatíveis; 25 posições anteriores preservadas; 172 bolsos ocupados; 31 reservas vazias (= `NO_CANDIDATE` do GATE 04); 0 disponíveis; 0 duplicidades; Histórico = posições (0 divergência); nenhuma escrita em exemplares, alocações, locais, bolsos, reservas, páginas ou coleção na transação. Diferença em relação às 148 previstas no GATE 04: uma colocação manual legítima, anterior, num bolso do plano. **`POST-APPLICATION INTEGRITY PASS`.**
- **Decisão (proprietário, definitiva):** **não** implementar feature flag adicional para a organização automática. Controles obrigatórios: proteção no servidor (DEFINER, titularidade, `search_path` vazio), token do plano com época, correspondência 1:1, atomicidade e confirmação explícita em duas etapas na interface. Só reabrir diante de um novo risco concreto.
- **Riscos residuais conhecidos (NÃO PROVADOS, não são PASS):** concorrência real entre sessões (K-M1–K-M3) e espera de trava / `55P03` sob contenção real. A primeira aplicação foi de uma única sessão.

---

## 10. Pokédex (2026-11-09, 5360)

Decisão do proprietário (2026-11-09): replicar a organização automática na Pokédex, usando as cartas guardadas no fichário da coleção; com várias cópias da mesma espécie, vai para o bolso a **representante**.

| Elemento | Regra na Pokédex |
|---|---|
| Bolso destino | Bolso de espécie (`collection_layout_slot_species_reference`, 5257–5260) da própria coleção; vazio; não travado; sem imagem; sem reserva de carta; fora de mesclagem. |
| Exemplar candidato | Mesmas regras do §2, vinculado a uma espécie da Pokédex. |
| Par | (bolso da espécie, representante da espécie). Representante = a mesma da grade (5204): a escolhida pelo colecionador, senão o vínculo mais antigo (`assigned_at`, alocação). 1:1 por construção. |
| Cópias extras | Ficam fora com `NOT_REPRESENTATIVE` e continuam em Cartas disponíveis. Representante fora do fichário ou já em outro bolso → a espécie não recebe carta (nenhuma outra cópia a substitui). |
| Bolsos vazios | Bolsos de espécie sem carta **não** geram `UNFILLED_SLOT` (seriam até 1.025 linhas sem valor para o colecionador). |

Set/Master Set: plano e token inalterados (assinatura de todas as linhas idêntica antes e depois, no dry-run e após a aplicação). Fórmula do token inalterada (`aa1.2`). Interface: a ação aparece também na Pokédex da proprietária; textos falam em bolso de espécie e representante; sem a contagem de reservas vazias.

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | **Criação (2026-11-01, `Binder · P2 AUTO-ARRANGE SQL FOUNDATION-06`).** Contrato funcional e SQL da organização automática, a partir das 13 decisões finais do proprietário (C-220–C-226). SQL proposto, não executado. |
| 1.1 | **Auditoria direcionada (2026-11-01, `Binder · P2 TARGETED SQL SAFETY AUDIT-07`).** Token passa a incluir a época da última organização aplicada (regra verificável para `ALREADY_APPLIED` × nova intenção); seção de concorrência com a matriz de escritores auditada. Decisões C-220–C-226 inalteradas. |
| 1.2 | **Fechamento do token (2026-11-01, `Binder · P2 TOKEN & CONCURRENCY CLOSEOUT-08`).** A época passa a incluir o marco de cobertura do histórico: limpeza do histórico não permite reautorização silenciosa de token antigo. Sem nova infraestrutura; C-220–C-226 inalteradas. |
| 1.3 | **Fundação SQL homologada (2026-11-01, `P2 SQL FOUNDATION CLOSEOUT-16`).** Status e §3 passam a homologado; retorno da confirmação detalhado; tratamento de `55P03`/`40P01` na interface; nova §9 com gates, evidências, riscos R1–R5, provas não demonstradas (K-M1–K-M3, `55P03`) e a condição para o primeiro uso real. Contrato funcional inalterado; C-220–C-226 inalteradas. |
| 1.4 | **Tratamento de erros de concorrência na interface (2026-11-01, `P2 SQL FOUNDATION RELEASE-17 CORRECTION-18`).** §3, §7 e linhas R1/R2 da §9: `40001` (plano alterado → nova prévia e nova confirmação), `55P03` (indisponibilidade temporária → nova tentativa iniciada por revalidação) e `40P01` (falha temporária → nova tentativa controlada iniciada por revalidação) passam a ter tratamentos distintos; nenhuma escrita repetida automaticamente; plano mudado exige revisão e confirmação. Sem mudança de SQLSTATE, token, backend ou C-220–C-226. |
| 1.5 | **Interface homologada e primeira aplicação real (2026-11-01, `P2 UI E4 FINAL CLOSEOUT-05`).** Status e §7 passam a implementado (E1–E4); §9 ganha a subseção da interface, a homologação visual da E4 (lint/build pendentes no Windows), a primeira aplicação real no ME3 (147 inserções, `POST-APPLICATION INTEGRITY PASS`), a decisão do proprietário de não implementar feature flag adicional e os riscos residuais não provados (K-M1–K-M3, `55P03`). SQL, token e C-220–C-226 inalterados. |
| 1.6 | **Extensão à Pokédex (2026-11-09).** 5360 (CONFIRMADO EXECUTADO): a Pokédex passa a ser elegível; o bolso de cada espécie recebe a representante da espécie; novo motivo `NOT_REPRESENTATIVE`; bolsos de espécie vazios fora da lista de não preenchidos. Nova §10; §2 atualizada. Set/Master Set inalterados (plano e token). Homologada pelo proprietário ("tudo funcionando perfeitamente bem"). |
