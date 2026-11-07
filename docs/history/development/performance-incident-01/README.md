# PERFORMANCE INCIDENT-01 — timeouts 57014 no Meu acervo

| Campo | Valor |
|--------|-------|
| **Documento** | Registro do incidente e evidências (diagnóstico, E0/E1, recorrência, capacidade) |
| **Arquivo** | `docs/history/development/performance-incident-01/README.md` |
| **Status** | **EM MONITORAMENTO** — E1 concluída localmente; Nano → Micro concluída; 7 dias de acompanhamento antes de qualquer encerramento |
| **Criado em** | 2026-11-07 |

Evidência histórica, sem decisão permanente nova. Medições sem dados pessoais (só contagens e tempos agregados dos logs do LIVE). Duas frentes distintas, que **não** devem ser confundidas: (A) ineficiência da aplicação — corrigida pela E1; (B) pressão de recursos do Supabase — tratada pela migração de compute. Os ganhos medidos da E1 aconteceram ainda no Nano e não são atribuíveis ao Micro.

## 1. Sintomas originais

- 52 erros PostgreSQL `57014` (`canceling statement due to statement timeout`, role `authenticator`, 8 s) em 2026-11-07, com 500 no gateway entre 9,9 e 23,4 s.
- Mais visíveis no Meu acervo (`get_my_inventory_summary`, `get_my_inventory_items`, `get_my_inventory_filter_options`), mas também em Coleções, Master Set, busca de cartas e preços.
- Nas mesmas janelas, leituras triviais lentas (`is_admin` até 10,5 s; `/auth/v1/user` até 9 s): lentidão do banco inteiro, não de uma consulta. Consultas do Acervo baratas em condição normal (mediana < 200 ms); aumentar `statement_timeout` não se justifica.
- Sem periodicidade de 5 min e sem dependência necessária do JustTCG (JustTCG pesado sem usuário → zero erros). Sem espera por lock no dia (`log_lock_waits` ligado, nenhum registro).

## 2. Diagnóstico da duplicação (frente A)

Confirmado no código do Next.js 15.5.22 instalado:
- `server/web/spec-extension/revalidate.js`: qualquer `revalidatePath` marca `pathWasRevalidated = true` (o próprio Next comenta "TODO: only revalidate if the path matches");
- `server/app-render/action-handler.js`: a resposta da Server Action passa a trazer a rota atual renderizada de novo;
- `client/.../server-action-reducer.js`: o cliente aplica essa árvore.

Os componentes do Acervo ainda chamavam `router.refresh()` depois da ação → uma segunda renderização completa (≈ 14 leituras ao banco com o detalhe aberto) por mutação.

## 3. Baseline anterior (E0, logs de borda do LIVE)

Janela de 2,5 s após cada mutação; `get_my_inventory_summary` = uma renderização do Acervo.

| Mutação | Mutações | Exatamente 2 renderizações | Leituras (p50) | Fim da 1ª / 2ª renderização (p50) | 2ª (p90) |
|---|---|---|---|---|---|
| `register_physical_cards_bulk` | 276 | 248 (90%) | 28 | 440 / 596 ms | 1.855 ms |
| `set_physical_cards_storage` | 475 | 339 (71%) | 28 | 399 / 571 ms | 1.543 ms |
| `remove_my_physical_card` | 12 | 9 | 28 | 468 / 669 ms | 2.076 ms |

28 = 2 × 14, igual à estimativa estática pelo código. Limitação: uso real (sem teste de carga); a janela pode incluir navegação do próprio usuário; mover pela seleção sem volume isolável.

Instrumentação E0: `app/colecoes/acervo/page.tsx` registra `acervo.render` por renderização (`ms`, `detail`, `plannedReads`). `plannedReads` é previsão pelo caminho do código, **não** contagem medida.

## 4. Alterações E1 (C2a)

Removido só o `router.refresh()` que repetia a renderização já entregue pela ação. Mutações, `revalidatePath`, RPCs, Server Actions, autorização, idempotência e regras de posse/alocação inalterados. Regras centralizadas em `web/lib/colecoes/acervo-refresh.ts`.

| Fluxo | Antes | Depois |
|---|---|---|
| Quantidade + / − (inclusive falha parcial com remoção) | ação + refresh | só a ação |
| Lixeira (não é o último exemplar) | ação + refresh | só a ação |
| Lixeira (último exemplar) | ação + `replace` de fechamento | **inalterado** — navegação legítima (muda a URL) |
| Localização (sucesso, `storage_gone`, `copies_gone`) | ação + refresh | só a ação |
| Mover — sucesso, `plan_changed`, `storage_gone` | ação + refresh | só a ação |
| Mover — `unresolved` (ação não revalida) e `unknown` (pode vir de falha de rede) | ação + refresh | **inalterado** — exceção legítima |
| Mover — prévia com `storage_gone` (prévia não revalida) | refresh | **inalterado** — exceção legítima |
| Adicionar no Meu acervo (sem destino) | ação + refresh | só a ação |
| Adicionar em coleção ou fichário (painel reutilizado; passo do bolso) | ação + refresh | **inalterado** — fora do escopo medido |

## 5. Resultados medidos depois da correção (ainda no Nano)

Mesmo recorte; uso normal do proprietário com a E1 no servidor local a partir de 21:20 UTC.

| | Antes (20:30–21:20) | Depois (21:20–21:33) |
|---|---|---|
| Mutações analisadas | 125 | 41 |
| Renderizações por mutação (média) | 2,26 | 1,32 |
| Leituras ao banco por mutação (p50) | 28 | 14 |
| Fim da última renderização (p50 / p90) | 617 / 2.407 ms | 484 / 2.120 ms |

- **Amostra posterior menor que a anterior** (41 × 125 mutações, 13 minutos): a redução de leituras está observada; a melhora de latência é modesta e não deve ser generalizada.
- Das 13 mutações "depois" com 2 renderizações: 11 com a 2ª renderização sem o detalhe (fechamento da carta — navegação) e 2 mutações a 1,3 s uma da outra (uma renderização cada). Nenhum refresh redundante.
- Fluxos observados em uso real: cadastro (Adicionar / quantidade +, indistinguíveis no log) e localização pelo detalhe.

## 6. Correções de consistência

Sem o refresh extra, a leitura nova chega na resposta da ação e pode ser aplicada antes ou depois do estado provisório do cliente:
- **Quantidade — `quantityToSyncAfterSave`:** ao fim do envio, o número exibido volta ao total do servidor **só se ele mudou** durante o envio; numa falha sem alteração, a escolha do colecionador permanece para nova tentativa com a mesma chave de idempotência; falha parcial mostra a mensagem de erro com quantos saíram e sincroniza o total real.
- **Localização — `activeProvisional`:** o provisório guarda a leitura do servidor vigente no início da gravação (`basis`) e só vale enquanto ela for a exibida; qualquer leitura nova prevalece, em qualquer ordem de chegada, sem depender de outra operação.
- Lixeira e mover: sem estado provisório próprio.

## 7. Testes executados

- `lib/colecoes/acervo-refresh.test.ts` 9/9 (regras + guardas que leem `actions.ts` e os componentes: todo desfecho sem refresh no cliente continua revalidado pela ação; nenhum `router.refresh()` fora das exceções; uso das regras determinísticas). Prova negativa feita: refresh reintroduzido → teste falha.
- Diretamente afetados: `acervo-quantity` 4/4, `copy-storage` 4/4, `acervo-storage-filter` 8/8, `acervo-move` 18/18, `acervo-move-queries` 19/19, `acervo-add` 15/15, `acervo-selection` 5/5, `acervo` 17/17, `collection-add` 3/3.
- `typecheck` e `git diff --check` limpos no snapshot final. `lint` e `build` (Windows) a confirmar pelo proprietário no snapshot final antes do commit.

## 8. Homologação funcional pós-migração (proprietário)

PASS: carregamento do Meu acervo; integridade das cartas e quantidades; abertura e fechamento dos detalhes; cadastro e atualização de exemplares; consulta de referências de preços.

Ainda não exercitados manualmente (cobertos só por testes automatizados): diminuir quantidade, lixeira (inclusive o último exemplar), mover pela seleção, operações parcialmente concluídas e falhas sem alteração efetiva.

## 9. Pressão de recursos (frente B) e migração Nano → Micro

- Recorrência às 21:43 UTC com a E1 ativa: uma renderização por mutação, carga menor que a da janela saudável anterior, sem JustTCG e sem lock → lentidão do ambiente, não regressão da E1.
- Evidências do Nano: RAM de 408 MB com memória compartilhada do Postgres de 270 MB (`huge_pages` off), swap ≈ 800 MB, memory commitment 1,71 GB × 1,40 GB (SEVERE), banco de 1,27 GB contra 500 MB recomendados; disco com base de 5 MB/s / 250 IOPS. O domínio Pricing responde por ≈ 70% das leituras físicas e ≈ 88% do WAL acumulados.
- Causa raiz da frente B **não comprovada** (sem swap-in/saldo de I/O em resolução de segundos). Migração para **Micro** concluída pelo proprietário. Não há ainda evidência de estabilidade prolongada: não se afirma que a migração eliminou os `57014`.

## 10. Limitações ainda existentes

- Ações em sequência rápida ainda podem sobrepor renderizações (o painel é liberado quando o resultado da ação chega, antes de a página terminar de chegar) — mitigação prevista em C1/C2b.
- Cada renderização do Acervo continua com ≈ 11–14 leituras (resumo e filtros invariáveis relidos a cada navegação) — C2b.
- Pressão de I/O do Pricing/JustTCG (paginação por OFFSET, índices de `pricing_observation`, crescimento ≈ 9–12 MB/dia) — C5, trilha separada.
- `admin_list_card_conditions` com ≈ 20 MB lidos por chamada — a investigar.
- Mudança futura do Next.js (revalidar só o caminho correspondente) exigiria revisar as regras de `acervo-refresh.ts`.

## 11. Estado: EM MONITORAMENTO

Acompanhar por 7 dias de uso representativo (sem novas automações; logs e Dashboard existentes):
- ocorrências de `57014` (`postgres_logs`, `sql_state_code = 57014`);
- latência das RPCs do Acervo (gateway: p50/p95 de `get_my_inventory_*`; meta p95 < 500 ms);
- lentidão perceptível durante cadastro normal (renderizações e leituras por mutação no mesmo recorte da seção 3);
- comportamento durante os lotes do JustTCG (mediana a cada 10 s sem picos > 1 s);
- memória, swap e IOWait do Micro (Dashboard → Observability; Disk IO balance em Infrastructure);
- falhas de autenticação ou PostgREST (5xx no gateway; erros no `auth_logs`).

Encerramento só com 7 dias sem `57014` e métricas estáveis; pendentes de contrato: C1, C2b, C5.
