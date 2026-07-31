# ADR-022 — Catalog Editorial Admin-Only Access

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-022 |
| **Título** | Catalog Editorial Admin-Only Access |
| **Status** | Aprovado |
| **Data** | 2026-07-26 |
| **Decisores** | Fabrício Sales |
| **Decisão** | Todo o módulo Catálogo Editorial no frontend (`/catalogo` e as cinco rotas filhas) é restrito a administradores — menu, rota e dado. Leitura é liberada tabela a tabela via política RLS `USING (is_admin())`, apenas nas tabelas efetivamente consultadas por uma tela real, nunca de uma vez em todo o schema. Escrita administrativa nunca usa política de `UPDATE` ampla — passa por funções `SECURITY DEFINER` específicas, uma por operação, seguindo o mesmo padrão já estabelecido em ADR-021. Migrations que alteram o controle de acesso de entidades já existentes do Catálogo Editorial usam a faixa de evolução (`200`–`299`), nunca a faixa congelada por entidade (`000`–`199`). |
| **Documentos Relacionados** | `ADR-019-web-application-as-primary-interface.md`, `ADR-021-administrative-role-model.md`, `../05-modelo-de-dados.md`, `../standards/STD-001-database-standards.md` |

---

# Context

`ADR-019` adotou a aplicação web como interface principal do produto e definiu o Catálogo Editorial como um dos dois módulos iniciais do frontend, ao lado de Identidade e Acesso — sem, na época, decidir explicitamente quem poderia acessá-lo. As seis rotas (`/catalogo`, `/catalogo/jogos`, `/catalogo/expansoes`, `/catalogo/card-sets`, `/catalogo/cartas`, `/catalogo/importacoes`) foram criadas como placeholder, sem essa decisão travada.

Ao retomar o desenvolvimento do módulo — concepção funcional da tela "Visão Geral" —, uma verificação direta do banco (não presumida) confirmou que as 17 tabelas do Catálogo Editorial têm Row Level Security habilitado, mas nenhuma possui política: nem `anon` nem `authenticated` têm `GRANT` de leitura em nenhuma delas. Ou seja, hoje ninguém — administrador ou usuário comum — consegue ler o Catálogo Editorial pela API. Esse fechamento total é um efeito colateral de a implementação nunca ter avançado, não uma decisão.

Fabrício decidiu, nesta retomada, tornar esse fechamento uma decisão explícita e permanente: todo o módulo passa a ser exclusivo de administradores, na mesma linha de rigor já aplicada à Administração de Usuários (`ADR-021`) — nenhuma política ampla, sempre o mínimo necessário, funções vetadas para escrita.

---

# Decision

## Escopo do módulo: menu, rota e dado

A restrição administrativa é aplicada em três camadas, nenhuma delas suficiente sozinha:

- **Menu** — a seção `catalogo` em `nav-config.ts` recebe `adminOnly: true`, mesmo padrão já usado em `usuarios`. É só uma pista de UX; não é a autorização real.
- **Rota** — cada uma das seis páginas faz a checagem de sessão e `is_admin()` no servidor, mesmo padrão já validado em produção em `/usuarios/page.tsx`: sem sessão → redireciona para `/login`; sem papel administrativo → `Alert` de acesso restrito. Aplicado a todas as seis rotas desde já, inclusive as que ainda são placeholder — a guarda de servidor não depende da tela ter conteúdo real.
- **Dado** — política RLS `SELECT` com `USING (is_admin())`, adicionada apenas nas tabelas que uma tela real efetivamente consulta, nunca em todo o schema de uma vez.

## Leitura liberada tabela a tabela, nunca em bloco

Das 17 tabelas do Catálogo Editorial, apenas as que a Visão Geral aprovada consulta recebem política nesta rodada: `game`, `expansion`, `card_set`, `card`, `card_variant`, `card_asset`, `language`, `rarity`, `card_category`, `asset_import_run`. As sete restantes (`card_variant_type`, `card_asset_type`, `storage_bucket`, `asset_source`, `card_external_reference`, `card_set_external_reference`, `asset_import_failure`) permanecem sem nenhuma política — fechadas até que uma tela real precise delas. Aplicação direta de AP-004 (Simplicidade Inicial) ao controle de acesso: não abrir hoje o que só será necessário depois.

## Escrita administrativa nunca por política de `UPDATE` ampla

Nenhuma tabela do Catálogo Editorial recebe política de `UPDATE`/`INSERT`/`DELETE` neste ADR. Toda escrita administrativa passa por uma função `SECURITY DEFINER` específica, restrita ao campo que ela existe para alterar — primeiro caso concreto: `admin_set_card_set_logo()`, que só é capaz de gravar `card_set.logo_storage_path`, nada além disso. Mesmo raciocínio já registrado em `ADR-021` para `admin_user`: uma política de linha ampla autoriza qualquer coluna da tabela, inclusive colunas futuras ainda não pensadas; uma função específica limita o alcance de cada operação administrativa ao que ela foi desenhada para fazer.

## Numeração das migrations na faixa de evolução do Catálogo Editorial

Como estas mudanças alteram o controle de acesso de entidades **já existentes** do Catálogo Editorial (não criam uma nova entidade nem um novo módulo), suas Queries usam a faixa `200`–`299` ("Evoluções e migrations complementares do Catálogo Editorial", `STD-001`, Seção 10) — mesma faixa já usada para o precedente direto mais próximo (`272`, correção de `GRANT` em `asset_import_run`). A faixa congelada por entidade (`card_set` = bloco `120`–`129`) não é usada para esta mudança.

## Emenda (2026-07-31) — `Expansion` ganha logo, mesmo padrão de `Card Set`

Fabrício pediu logo por Expansão ("vamos incluir uma imagem para cada expansão"). Mesma arquitetura de `card_set.logo_storage_path` já decidida acima: coluna opcional com `CHECK` contra URL absoluta, escrita restrita a uma função `SECURITY DEFINER` (`admin_set_expansion_logo()`, nunca política de `UPDATE` ampla), bucket privado (`expansion-logo`) com quatro políticas distintas em `storage.objects`, todas `bucket_id = 'expansion-logo' AND is_admin()`, e leitura só via URL assinada — nunca `getPublicUrl()`. Bucket fora da tabela `storage_bucket`, mesmo padrão de `card-set-logo`/`avatars`.

**Desvio deliberado da numeração prescrita acima**: a seção "Numeração das migrations..." deste ADR manda usar a faixa `200`–`299` para evoluções do Catálogo Editorial. Essa faixa foi congelada para novas Queries depois que este ADR foi escrito (`STD-001`, "Faixas de Numeração — Esquema Legado — Congelado"). As Queries da logo de Expansão (`2045` coluna, `2046` função, `2047` bucket/políticas, validação `2810`) foram numeradas no milhar `2000`–`2999` (Catálogo Editorial — Escrita e Ingestão, `ADR-023`) em vez de `200`–`299` — mesmo critério já aplicado à emenda de exclusão de `Expansion`/`Game` (`ADR-023`): a faixa legada está congelada, o milhar modular é o destino correto para qualquer Query nova do Catálogo Editorial hoje, independente do ADR que motivou a mudança.

## Reversibilidade

Este ADR não impede uma decisão futura de abrir o Catálogo Editorial (total ou parcialmente) a usuários comuns — por exemplo, se o produto adotar um modo de navegação pública do catálogo. Se isso acontecer, será uma nova decisão explícita, com seu próprio ADR complementar ou substituto, nunca uma reinterpretação silenciosa deste documento.

---

# Consequences

## Benefícios

- Transforma um fechamento acidental (RLS habilitado sem política, por implementação inacabada) em uma decisão explícita, documentada e rastreável.
- Consistente com o padrão de segurança já validado em produção no módulo de Identidade e Acesso: leitura mínima necessária via RLS, escrita sensível sempre por função vetada.
- Simples de estender: cada nova tela do Catálogo Editorial adiciona exatamente a política de que precisa, quando precisa — sem reabrir este ADR.
- Simples de reverter/ampliar no futuro: a restrição vive em RLS e em guardas de página, não espalhada pelo código da aplicação.

## Restrições / Pendências

- Hoje nenhum usuário comum vê o catálogo editorial do produto, mesmo sendo um sistema de gestão de coleções para colecionadores — essa pode não ser a direção final do produto. Decisão de abrir o catálogo (todo ou em parte) a usuários comuns fica para uma decisão futura e explícita de Fabrício, fora do escopo deste ADR.
- As sete tabelas do catálogo ainda sem política nenhuma vão precisar da sua própria política quando uma tela real as consultar — não antecipado aqui.
- O bucket `card-set-logo` (ver `05-modelo-de-dados.md`, seção Set) fica fora da tabela `storage_bucket`, mesmo padrão já usado por `avatars` — registrado aqui para não se perder, já que diverge do padrão usado por `card-front`/`card-back`/`artwork`.

---

# Alternatives Considered

## Política de `UPDATE` ampla em `card_set` com `is_admin()`

Considerada na proposta inicial, rejeitada por Fabrício. Mesmo risco já identificado em `ADR-021` para `user_profile`: uma política de linha ampla autoriza a alteração de qualquer coluna da tabela, inclusive colunas futuras não previstas hoje. Uma função `SECURITY DEFINER` restrita a `logo_storage_path` elimina esse risco por construção.

## Manter o Catálogo Editorial acessível a qualquer usuário autenticado

Era a suposição implícita desde que as rotas foram criadas como placeholder (`ADR-019`). Rejeitada nesta revisão: o produto ainda não definiu um modelo de exposição pública do catálogo, e é mais seguro reduzir o escopo agora e ampliar depois — com uma decisão própria — do que o inverso.

## Liberar política `SELECT` em todas as 17 tabelas do Catálogo Editorial de uma vez

Rejeitada por não ter necessidade concreta hoje (AP-004). Políticas são adicionadas tabela a tabela, conforme cada tela real precisar, não antecipadamente para o módulo inteiro.

## Numerar a alteração de `card_set` dentro do bloco `120`–`129`

Considerada, rejeitada por Fabrício. O bloco por entidade da faixa legada (`000`–`199`) está congelado para novas implementações (`STD-001`, revisão `1.15`); esta é uma evolução de controle de acesso, não uma nova característica estrutural da entidade Set, e pertence à faixa `200`–`299` já usada para esse tipo de ajuste.

---

# Related Documents

- `ADR-019-web-application-as-primary-interface.md`
- `ADR-021-administrative-role-model.md`
- `../05-modelo-de-dados.md`
- `../standards/STD-001-database-standards.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza o Catálogo Editorial como módulo exclusivo de administradores (menu, rota e dado), leitura liberada tabela a tabela via RLS `is_admin()` apenas onde uma tela real consulta, escrita administrativa sempre por função `SECURITY DEFINER` específica (nunca política de `UPDATE` ampla), e migrations de controle de acesso numeradas na faixa de evolução (`200`–`299`), não na faixa congelada por entidade. Motivado pela retomada do desenvolvimento do módulo e pela descoberta de que as 17 tabelas do Catálogo Editorial já estavam de fato fechadas (RLS sem política), sem que isso fosse uma decisão registrada. |
| 1.1 | **Emenda: `Expansion` ganha logo (`admin_set_expansion_logo()`, Queries `2045`/`2046`/`2047`, validação `2810`), 2026-07-31.** Pedido de Fabrício — mesma arquitetura de `card_set.logo_storage_path`: coluna opcional com `CHECK` contra URL absoluta, escrita só via função `SECURITY DEFINER`, bucket privado `expansion-logo` com quatro políticas admin-only, leitura via URL assinada. Numeração no milhar `2000`–`2999`, não em `200`–`299` (faixa legada congelada desde `STD-001`, depois da redação original deste ADR) — desvio documentado na nova seção "Emenda". Todas as Queries confirmadas executadas e validadas por Fabrício no mesmo dia. |
