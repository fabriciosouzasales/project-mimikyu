# CLAUDE.md — Schema do Projeto Mimikyu

| Campo | Valor |
|--------|-------|
| **Documento** | Schema do Agente (convenções operacionais para qualquer LLM que trabalhe neste repositório) |
| **Arquivo** | `CLAUDE.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Criado em** | 2026-08-06, a partir da adequação ao padrão LLM Wiki (Andrej Karpathy) |
| **Objetivo** | Documentar, de forma versionada e portável, como qualquer agente de IA deve operar neste repositório — convenções que antes existiam apenas na memória privada de sessão de um assistente específico. |

---

## Por que este arquivo existe

Este projeto é mantido continuamente por um agente de IA atuando como engenheiro de software e guardião permanente da documentação. Até 2026-08-06, as convenções operacionais (como propor SQL, como registrar histórico, como nomear handoffs, etc.) existiam apenas na memória de sessão privada do assistente — não em um arquivo versionado, visível e portável. Isso já causou um incidente real: uma ferramenta de IA diferente (ChatGPT Codex), sem acesso a essas convenções, criou artefatos soltos no repositório por não saber onde ler as regras do projeto.

Este arquivo resolve isso: qualquer agente (Claude, Codex, ou outro) deve ler `CLAUDE.md` no início de uma sessão de trabalho neste repositório, antes de propor qualquer mudança.

**Leitura obrigatória, nesta ordem, ao iniciar uma sessão nova:**
1. Este arquivo (`CLAUDE.md`).
2. `docs/INDEX.md` — catálogo de tudo que existe na documentação, com um resumo de uma linha cada.
3. `docs/README.md`, seção "Status Atual do Projeto" — fase atual e handoff vigente.
4. O handoff vigente em `docs/development/HANDOFF-AAAA-MM-DD.md`.
5. `docs/log.md` (últimas entradas) — o que aconteceu recentemente.
6. A partir daí, aprofundar nos documentos numerados (`00`–`07`) e ADRs/Standards relevantes ao pedido em questão — não é preciso ler tudo de imediato, `docs/INDEX.md` existe justamente para evitar isso.

---

## As três camadas

- **Fontes brutas** — `assets/reference-sources/` (checklists oficiais em PDF por Card Set) e `database/seeds/` (dados de referência). Imutáveis: o agente lê, nunca edita.
- **A documentação (`docs/`)** — o equivalente ao "wiki": páginas markdown geradas e mantidas pelo próprio agente. O agente é o único autor real deste conteúdo; Fabrício lê, direciona e aprova.
- **Este arquivo (`CLAUDE.md`)** — o "schema": como o agente deve operar, não o que está documentado.

---

## Fluxo obrigatório por ciclo de trabalho

Para qualquer mudança real no projeto (schema, migration, Edge Function, frontend, correção de dado):

1. Analisar o pedido e, se vier de um histórico externo (print, conversa colada, PDF), ler o conteúdo por completo antes de agir.
2. Confrontar contra o estado real do repositório — nunca assumir a partir de memória ou de documentação desatualizada. Se a evidência direta do repositório contradiz a premissa do pedido, sinalizar a divergência explicitamente antes de prosseguir (nunca aplicar a divergência silenciosamente).
3. Separar decisões permanentes de hipóteses intermediárias.
4. Identificar quais documentos precisam ser criados ou atualizados.
5. Implementar e escrever a documentação **no mesmo ciclo** — nunca como recomendação para depois. Nenhum ciclo de implementação está concluído até a documentação correspondente estar atualizada.
6. Rodar verificação final (ver seção própria abaixo).
7. Registrar uma linha nova em `docs/log.md` (ver formato abaixo).
8. Reportar ao final: arquivos alterados, resumo curto, descrição objetiva.

## Escrita de SQL (pareamento obrigatório)

Mudanças de schema/dado no Supabase seguem o "Padrão Oficial de Queries SQL" (`docs/standards/STD-001-database-standards.md`, Seção 10): **Query** (número + nome curto) → **Objetivo** (o que faz, em português) → **Script SQL** → **Resultado esperado** → **Como validar** (uma query de confirmação). Uma etapa por vez, sempre confirmada antes de avançar.

Scripts só entram em `database/` depois de **confirmadamente executados** — nunca antes. Distinguir sempre "CONFIRMADO EXECUTADO" de "proposto/planejado" na documentação.

Quem executa o SQL no Supabase, por padrão, é Fabrício — o agente apresenta a Query pronta e aguarda a execução e confirmação, salvo instrução explícita em contrário.

## Estilo de histórico na documentação do repositório

A partir de 2026-07-24: a documentação em `docs/*.md` registra **apenas a solução final e correta de cada etapa**, não o histórico completo de hipóteses erradas e tentativas dentro de uma mesma rodada. Decisões reais, divergências ainda não resolvidas e incidentes que mudam o entendimento do projeto continuam sendo registrados — a poda é de ruído (tentativa errada, nome de coluna incorreto, query refeita), não de sinal (decisão, pendência real).

Isso não se aplica à memória de sessão do próprio agente, que pode ficar tão detalhada quanto for útil para sua própria continuidade — só ao que é escrito no repositório.

## Convenção de Revision History

Cada documento numerado mantém sua própria tabela de Revision History, em ordem cronológica **ascendente** (mais antiga no topo). Entradas seguem o formato `| X.Y | **Resumo em negrito, com data.** Corpo explicando o quê/por quê. |`.

**A partir de 2026-08-06**: toda entrada nova de Revision History também gera uma linha correspondente em `docs/log.md` (ver formato abaixo) — o log é o índice cronológico rápido de tudo; a tabela de Revision History de cada documento continua sendo o registro completo e detalhado daquele documento especificamente. Histórico já existente nas tabelas de Revision History não foi migrado retroativamente linha a linha para o log (ver `docs/log.md` para o porquê) — só passou a ser espelhado a partir desta data.

## Ciclo de vida dos handoffs

Apenas um handoff vigente por vez, em `docs/development/HANDOFF-AAAA-MM-DD.md`. Ao criar um novo, o anterior é movido para `docs/history/development/`. Nenhuma decisão permanente deve existir apenas em um handoff — decisões arquiteturais/de modelagem/de processo vão para seu artefato normativo (ADR, Standard, documento de arquitetura) no mesmo ciclo.

## Onde cada tipo de conteúdo mora

Governança completa em `docs/03-documentation-architecture.md` — não duplicada aqui. Resumo rápido: `04-domain-model.md` (conceitual, sem SQL) · `05-modelo-de-dados.md` e as páginas que o sucedem (físico/SQL, ver nota de divisão abaixo) · `06-pipeline-importacao.md` (estratégia de importação) · `07-catalogo-editorial.md` (fluxo de ingestão administrativa) · `adr/` (por que uma decisão foi tomada) · `standards/` (como um padrão permanente é aplicado) · `operations/` (passo a passo de uso, sem racional) · `history/` (diário de tentativas/evolução, sem novas decisões) · `development/` (handoffs, operacional).

**Divisão de `05-modelo-de-dados.md` (2026-08-06)**: o documento único cresceu além do que as ferramentas de leitura conseguem processar em uma chamada (passou de 700 KB). Foi dividido por área de domínio — ver `docs/INDEX.md` para a lista atual dos arquivos resultantes e `docs/05-modelo-de-dados.md` (mantido como índice de redirecionamento). Documentos novos de física/SQL devem ser criados já no tamanho certo por área, evitando reconstituir um único arquivo monolítico.

## docs/log.md — formato

Uma linha por evento, ordem cronológica, prefixo consistente para permanecer `grep`-ável:

```
## [AAAA-MM-DD] tipo | Resumo curto
```

Tipos usados: `ingest` (nova fonte/decisão incorporada), `fix` (correção real), `feature` (implementação nova), `docs` (mudança só de documentação), `lint` (auditoria de consistência). Sem parágrafos — o detalhe completo mora no documento normativo correspondente (Revision History, ADR, handoff); o log só aponta para lá.

## docs/INDEX.md — manutenção

Atualizar `docs/INDEX.md` sempre que um documento novo for criado, removido, ou tiver seu título/resumo alterado de forma relevante. Mesma disciplina já aplicada a `ADR-INDEX.md`/`STD-INDEX.md`.

## Operação de Lint

Periodicamente (a pedido de Fabrício ou quando o agente perceber sinais de deriva — contagens divergentes, status desatualizado, pendência que já foi resolvida mas ainda aparece como aberta), rodar uma auditoria de consistência: contradições entre documentos, alegações obsoletas, links quebrados, documentos importantes sem entrada em `docs/INDEX.md`. Registrar o resultado como entrada `lint` em `docs/log.md`, com correções aplicadas diretamente nos documentos afetados no mesmo ciclo.

## Ambiente local e execução

- Repositório canônico: `project-mimikyu` (`origin` = `github.com/fabriciosouzasales/project-mimikyu`, branch `main`). Existe uma segunda pasta local (`Project-Mimikyu`, sem o hífen antes de "Mimikyu") **não versionada** — não confundir; comandos sempre no caminho completo do repositório canônico.
- Em `web/`, `node_modules`/`.next` já existem localmente: `npm run typecheck` (`tsc --noEmit`) funciona diretamente e deve ser rodado a cada incremento de frontend. `npm run lint`/`npm run build` não funcionam no sandbox de execução do agente (binário SWC ausente, sem acesso a `registry.npmjs.org`) — isso é uma limitação do sandbox, não necessariamente da máquina de Fabrício; pedir a ele para rodar localmente quando a verificação for necessária.
- Nunca commitar sem autorização explícita de Fabrício. Ele revisa e faz o commit final, salvo instrução em contrário.
- Artefatos locais de sessão/ferramentas de IA (`.agents/`, `.codex/`) nunca pertencem ao repositório — já cobertos por `.gitignore`.

## Idioma

Toda comunicação em chat com Fabrício é em português do Brasil (pt-BR). Documentação, código, comentários e mensagens de commit seguem a mesma convenção já estabelecida no repositório (pt-BR).

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste documento (2026-08-06), como parte da adequação do projeto ao padrão LLM Wiki descrito por Andrej Karpathy — consolida em um arquivo versionado convenções que antes existiam apenas na memória de sessão privada do agente. |
