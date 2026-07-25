# ADR-019 — Web Application as the Primary User Interface

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-019 |
| **Título** | Web Application as the Primary User Interface |
| **Status** | Aprovado |
| **Data** | 2026-07-25 |
| **Decisores** | Fabrício Sales |
| **Decisão** | O Project Mimikyu adotará uma **aplicação web própria (React/Next.js)** como interface principal do produto, com código no mesmo repositório. Soluções baseadas em **Power Apps, SharePoint e Power BI não fazem mais parte da arquitetura-alvo** e não serão utilizadas nem mesmo como etapa provisória de implementação — permanecem apenas como alternativas históricas já descartadas, registradas aqui para rastreabilidade. |
| **Documentos Relacionados** | `../01-technical-identity.md`, `../ROADMAP.md`, `../README.md`, `ADR-014-collection-and-collection-entry-model.md`, `ADR-018-single-function-import-pipeline.md` |

---

# Context

O `ROADMAP.md` (seção "Later — Direção Futura Provável, Não Comprometida") registrava, desde sua criação, que a camada de apresentação do produto havia sido mencionada em propostas anteriores como Power Apps, **sem nenhuma decisão vigente sobre a tecnologia**. Nenhum ADR jamais formalizou uma escolha de stack de front-end — a arquitetura do projeto, até esta revisão, cobria apenas backend (Supabase: PostgreSQL, Storage, Edge Functions).

Fabrício propôs, nesta revisão, iniciar a construção do front-end do sistema imediatamente, sem esperar a conclusão de toda a modelagem de dados (em particular, sem esperar o módulo de Coleções, ainda não modelado fisicamente) — priorizando entregas que agreguem valor de forma incremental. O primeiro módulo escolhido é o de cadastro/importação do Catálogo Editorial, hoje maduro o suficiente (927 Cards, 1.653 Card Variants, pipeline de importação funcional, `asset_import_run` com rastreamento de status corrigido nesta mesma sessão).

Ao definir o escopo desse primeiro módulo, Fabrício esclareceu o objetivo comercial do produto: o Project Mimikyu será **uma plataforma direcionada a colecionadores do mundo inteiro, comercializada**, não uma ferramenta de uso pessoal ou administrativo interno. Isso muda a natureza da decisão de stack: uma solução low-code (Power Apps) ou baseada em ferramentas de produtividade corporativa (SharePoint, Power BI) não se sustenta como interface de um produto comercial multiusuário com centenas ou milhares de usuários externos — essas ferramentas foram descartadas como direção provisória, para não acumular dívida técnica de uma solução que já se sabe não ser a definitiva (ver `AP-004`/`AP-006`).

Como consequência direta de o produto ser multiusuário e comercial, torna-se necessário um módulo de **Gestão de Usuários** — fundação transversal da aplicação, hoje inexistente no domínio modelado. Ele deve fornecer: cadastro, login e logout, recuperação de senha, confirmação de e-mail, perfil básico, papéis e permissões, ativação e bloqueio de usuários, e uma trilha mínima de auditoria.

---

# Decision

## Aplicação web própria como interface principal

Front-end construído como aplicação web (React/Next.js), código no mesmo repositório do backend. Nenhuma ferramenta low-code (Power Apps) ou de produtividade corporativa (SharePoint, Power BI) integra a arquitetura-alvo, em nenhuma capacidade — nem como solução definitiva, nem como etapa provisória.

## Arquitetura macro resultante

```text
Usuário
   │
   ▼
Frontend Web
   │
   ├── autenticação
   ├── catálogo
   ├── coleções
   ├── inventário
   ├── aquisições e movimentações
   └── análises
   │
   ▼
Supabase
   ├── Auth
   ├── PostgreSQL
   ├── Storage
   ├── Row Level Security
   └── Edge Functions
```

## Autenticação via Supabase Auth + `user_profile`

A autenticação usará **Supabase Auth**. O domínio da aplicação, no entanto, precisará de uma entidade própria de perfil (`user_profile`), relacionada a `auth.users`:

```text
auth.users
    │
    └── user_profile
```

Essa separação distingue explicitamente: identidade de autenticação, informações de negócio do usuário, permissões, preferências e status dentro da plataforma — nenhuma dessas quatro camadas pertence à tabela gerida pelo Supabase Auth. `user_profile` ainda não foi modelada fisicamente; é trabalho de modelagem pendente, a tratar com a mesma disciplina (uma entidade por vez, validada com dados reais) já aplicada ao restante do catálogo em `05-modelo-de-dados.md`.

## Primeiro sketch de telas, sujeito a refinamento

Fabrício propôs uma primeira lista de telas para os dois módulos iniciais — registrada aqui como ponto de partida da concepção funcional, **não como escopo fechado**: a concepção funcional e arquitetural detalhada do front-end é o próximo trabalho real, não esta ADR.

**Gestão de Usuários**: login; cadastro; recuperação de senha; perfil do usuário; lista administrativa de usuários; detalhes e status do usuário.

**Catálogo Editorial**: página inicial do catálogo; lista de expansões; lista de Card Sets; detalhe do Card Set; busca e filtros de Cards; detalhe da Card; visualização das variantes; painel de integridade editorial; histórico de importações; detalhes das falhas de importação.

---

# Consequences

## Benefícios

- Elimina a possibilidade de investir esforço em uma solução (Power Apps/SharePoint/Power BI) já sabida como não-definitiva para um produto comercial multiusuário — reduz dívida técnica, retrabalho e fragmentação arquitetural (`AP-004`).
- Desbloqueia entrega incremental de valor: o Catálogo Editorial está maduro o suficiente para sustentar uma UI real sem esperar a modelagem de Coleções.
- Formaliza, pela primeira vez, uma arquitetura macro de ponta a ponta (usuário → front-end → Supabase), servindo de referência para todos os módulos futuros (coleções, inventário, aquisições, análises), não apenas os dois iniciais.

## Restrições / Pendências

- **Nenhum código de front-end existe ainda** — esta ADR é só a decisão de direção tecnológica, não uma implementação. O próximo trabalho real é a concepção funcional e arquitetural do módulo de Gestão de Usuários e do Catálogo Editorial (fluxos, telas detalhadas, contratos de API/Edge Functions necessários), não a escolha de framework (já decidida aqui).
- **Sequenciamento entre Gestão de Usuários e Catálogo Editorial ainda não decidido explicitamente.** Gestão de Usuários é fundação transversal (nada mais funciona sem autenticação real), o que sugere que precisa vir primeiro ou em paralelo — mas esta ADR não assume essa ordem como decisão; cabe a Fabrício confirmar antes do próximo ciclo de implementação.
- `user_profile` precisa de modelagem física própria em `05-modelo-de-dados.md`, com o mesmo rigor (SQL real, RLS, triggers de governança) já aplicado a toda entidade do catálogo — não coberta por esta ADR.
- O fluxo hoje manual de criar/disparar uma `asset_import_run` (ver `../operations/import-card-assets.md`) precisará ser revisitado para ser acionável pela UI (hoje é SQL + chamada HTTP separada) — identificado, não resolvido nesta ADR.
- `LANGUAGE_CODE`/`TCGDEX_LANGUAGE` continuam como constantes fixas no código da Edge Function `import-card-assets`, não parâmetros de requisição (limitação já registrada desde o Sprint B3.21) — uma tela de importação por idioma depende dessa mudança, ainda não feita.
- Decisões de detalhe de stack (hospedagem do front-end, biblioteca de componentes, gerenciamento de estado, etc.) permanecem em aberto — esta ADR fixa apenas React/Next.js como framework.

---

# Alternatives Considered

## Manter Power Apps como opção viável, mesmo que provisória

Rejeitada. O produto mudou de escopo percebido — de uma ferramenta pessoal/administrativa para uma plataforma comercial multiusuário voltada a colecionadores do mundo inteiro. Uma solução low-code não sustenta esse nível de controle de UX, lógica de negócio e escala de usuários externos. Adotá-la mesmo que provisoriamente violaria `AP-004`/`AP-006`: investir em algo que já se sabe não ser a direção final.

## Adiar a decisão de stack até o módulo de Coleções estar modelado

Rejeitada por Fabrício. O objetivo comercial do produto já é conhecido agora — adiar a decisão de tecnologia não traria nenhum benefício adicional, apenas atrasaria a entrega de valor incremental que motivou esta proposta.

---

# Related Documents

- `../01-technical-identity.md`
- `../ROADMAP.md`
- `../README.md`
- `ADR-014-collection-and-collection-entry-model.md`
- `ADR-018-single-function-import-pipeline.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza a aplicação web (React/Next.js) como interface principal do produto, substituindo Power Apps/SharePoint/Power BI como direção-alvo. Motivada pela proposta de Fabrício de iniciar o front-end pelo módulo de Catálogo Editorial (CRUD completo) sem esperar a modelagem de Coleções, e pelo esclarecimento de que o produto será uma plataforma comercial multiusuário — o que torna necessário também um módulo de Gestão de Usuários (Supabase Auth + nova entidade `user_profile`). Nenhuma implementação de front-end ainda existe. |
