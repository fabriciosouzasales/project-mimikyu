# STD-001 — Database Standards

| Campo | Valor |
|--------|-------|
| **Documento** | STD-001 |
| **Título** | Database Standards |
| **Versão** | 1.15 |
| **Status** | Aprovado |
| **Objetivo** | Definir os padrões permanentes utilizados na modelagem e implementação do banco de dados do Project Mimikyu. |
| **Escopo** | Todas as entidades, tabelas, relacionamentos e scripts SQL do projeto. |

---

# Purpose

Este documento define os padrões oficiais de banco de dados do Project Mimikyu.

Toda decisão relacionada à modelagem deverá obedecer às regras descritas neste documento.

Este documento representa a "Constituição" do banco de dados.

---

# 1. Technical Language

Toda a modelagem será desenvolvida utilizando inglês.

Inclui:

- nomes de tabelas;
- colunas;
- constraints;
- índices;
- funções;
- triggers;
- views.

Comentários e cabeçalhos explicativos dentro dos scripts SQL (descrição, regras de negócio, autor, data) são escritos em **português**, como o restante da documentação do projeto — apenas os identificadores técnicos (nomes de objetos do banco) seguem o inglês. Ver Seção 10 (Migration Standards) para o modelo de cabeçalho.

---

# 2. Naming Conventions

O banco de dados é tratado como um produto do projeto, não apenas como suporte da aplicação — por isso a nomenclatura abaixo é uma convenção permanente e única para todo o projeto, nunca misturando estilos entre tabelas ou módulos.

## Tabelas

Nome no singular, em inglês, minúsculas, no formato `snake_case`.

Exemplos: `game`, `expansion`, `set`, `card`, `collection`, `collection_item`.

## Colunas

Minúsculas, no formato `snake_case`. Nunca `camelCase`, `PascalCase` ou notação húngara.

Proibido: `gameId`, `GameID`, `idGame`.

Correto: `game_id`.

## Colunas Reservadas Comuns

`id`, `status`, `created_at`, `updated_at`, `deleted_at`, `created_by`, `updated_by`, `deleted_by` (ver Seção 4 — Audit Model) possuem significado padronizado em todo o projeto e não devem ser reutilizadas com outro propósito.

## Palavras Reservadas do SQL

Quando o nome conceitual de uma entidade colide com uma palavra reservada do SQL (ex.: `SET` no PostgreSQL), a tabela física deve adotar um nome qualificado que evite a ambiguidade — mesmo que o conceito de domínio continue com seu nome original na documentação e na aplicação.

Exemplo: o conceito **Set (Set)** — ver `04-domain-model.md` — é implementado fisicamente como a tabela `card_set`.

---

# 3. Data Types

## Tipos de Texto

- `VARCHAR(n)` — quando houver um limite de negócio claro e conhecido (ex.: um código com tamanho máximo definido).
- `TEXT` — quando o conteúdo for naturalmente livre, sem limite de negócio conhecido.

Não adotaremos limites arbitrários por tradição (ex.: `VARCHAR(255)` em todos os campos de texto, sem relação com uma regra de negócio real).

## Identificadores Técnicos

`UUID` para toda chave primária técnica (ver Seção 5 — Primary Keys).

## Datas de Auditoria

`TIMESTAMPTZ` (timestamp com fuso horário) para todos os campos de data/hora de auditoria (`created_at`, `updated_at`, e demais quando existirem). Nunca armazenar apenas data local ou horário sem fuso.

## Colunas `JSONB` de `metadata`

Quando uma entidade tiver uma coluna `metadata JSONB` para guardar informação adicional de uma fonte externa (ex.: `card_set_external_reference.metadata`, `card_external_reference.metadata`), **`metadata` nunca deve duplicar um atributo que já existe em uma coluna relacional** — nem da própria tabela, nem de uma tabela relacionada acessível por `JOIN`. `metadata` existe apenas para propriedades específicas da fonte externa, sem equivalente relacional, e que não justificam uma coluna própria.

Nasceu de um caso real: o cadastro de `MEP` em `card_set_external_reference` inicialmente guardou em `metadata` quatro campos (`official_code`, `external_name`, `release_date`, `card_count_at_registration`) — três já existiam como colunas relacionais (`card_set.code`, `card_set.name`, `card_set.release_date`, acessíveis por `JOIN`) e o quarto (`card_count_at_registration`) ficaria desatualizado rapidamente, por natureza (o `card_set.total_set_size` já é a fonte de verdade para a contagem atual, ver `05-modelo-de-dados.md`, seção "Set", "Migration `265`–`268`"). Padronizado para `metadata = '{}'::JSONB`, mesmo padrão já usado por todos os demais registros da tabela.

---

# 4. Audit Model

## Padrão Mínimo

Toda entidade de negócio deverá possuir obrigatoriamente:

```text
id (UUID)
created_at (TIMESTAMPTZ)
updated_at (TIMESTAMPTZ)
```

`updated_at` deve ser atualizado automaticamente pelo banco (ex.: função/trigger reutilizável), sem depender de aplicações ou importadores lembrarem de alterá-lo manualmente.

## Campos Adicionais (sob demanda)

Os campos `created_by` e `updated_by` **não** são adicionados por padrão a todas as tabelas. Só devem ser adicionados quando houver necessidade real: múltiplos administradores, edição colaborativa, necessidade concreta de rastrear alterações, ou governança sobre o catálogo (Princípio da Simplicidade Inicial — ver AP-004).

`deleted_at`/`deleted_by` seguem a mesma lógica de "sob demanda" — ver Seção 8 (Logical Delete).

---

# 5. Primary Keys

Toda tabela possui uma chave primária técnica chamada `id`, do tipo UUID (ver Seção 4 — Audit Model).

O `id` é a identidade técnica permanente do registro: não deve ser reaproveitado, reordenado, nem carregar significado de negócio.

Chaves de negócio (ex.: código do Set; Set + Número da Card) representam a identidade de domínio (ver `04-domain-model.md`) e podem receber restrições de unicidade próprias, mas não substituem o `id` técnico como chave primária da tabela.

## Versão do UUID

Para o MVP, utiliza-se **UUID v4**, gerado pelo próprio banco (ex.: `gen_random_uuid()`, extensão `pgcrypto` no PostgreSQL). UUID v7 (com ordenação temporal) é preferível quando a camada tecnológica oferecer suporte adequado, mas não é um requisito do MVP — essa escolha é puramente técnica, não afeta o domínio, e pode ser revista futuramente sem impacto conceitual.

## Identidade de Negócio (code)

Além do `id` técnico, uma entidade pode possuir um `code`: um identificador curto, estável e legível, usado por pessoas, integrações ou regras editoriais (ex.: `game.code = POKEMON`; `card_set.code = ME2.5`). O `code` nunca substitui o `id` como chave primária, mas normalmente recebe uma restrição de unicidade própria.

### Código Internacional, Nome Localizável

O `code` é editorial e internacional — não muda entre idiomas (ex.: a Expansion `SV` continua sendo `SV` em qualquer idioma). O `name` pode ser localizado futuramente, quando houver necessidade concreta, seguindo o mesmo padrão já estabelecido para conteúdo editorial em Card Translation (ver `04-domain-model.md` e ADR-007). Este padrão — código internacional, nome localizável — tende a se repetir em todo o catálogo editorial.

---

# 6. Foreign Keys

Toda chave estrangeira segue o padrão `<entidade_referenciada>_id`, referenciando a coluna `id` (UUID) da tabela relacionada.

Exemplos: `game_id` (em `expansion`), `set_id` (em `card`), `card_id` (em `card_finish`, `collection_entry`).

---

# 7. Indexes

*Documentação pendente.*

---

# 8. Logical Delete

A exclusão lógica generalizada (`deleted_at` em todas as tabelas) **não** é adotada por padrão. Soft delete generalizado aumenta a complexidade do sistema: todas as consultas precisam ignorar registros excluídos; índices e restrições de unicidade ficam mais difíceis; relacionamentos podem manter dados aparentemente ativos; erros de implementação podem fazer registros "apagados" reaparecerem.

Exclusão lógica (`deleted_at`/`deleted_by`) só deve ser aplicada onde houver necessidade concreta de restauração ou preservação histórica.

Para o catálogo editorial, o padrão recomendado é um campo `status`, representando um estado de negócio — não uma exclusão:

```text
status: ACTIVE, INACTIVE
```

ou estados específicos do domínio, quando fizerem sentido:

```text
status: ANNOUNCED, RELEASED, CANCELLED
```

Isso não é soft delete — é estado de negócio, com semântica própria de cada entidade.

---

# 9. SQL Standards

Regras estruturais importantes devem existir no próprio banco de dados, e não apenas na camada de aplicação. A aplicação oferece mensagens amigáveis; o banco garante que dados inválidos não sejam persistidos, mesmo em caso de falha ou bypass da aplicação.

Exemplos de restrições implementadas no banco:

- unicidade de códigos de negócio (ex.: `game.code` não pode se repetir — `UNIQUE`);
- obrigatoriedade de relacionamentos hierárquicos (ex.: uma Expansion deve pertencer a um Game; uma Card deve pertencer a um Card Set — `NOT NULL` + `FOREIGN KEY`);
- valores numéricos com regra de negócio (ex.: uma ordem de lançamento deve ser positiva — `CHECK`);
- formato de campos de negócio (ex.: um `code` deve seguir um padrão normalizado — `CHECK` com expressão regular).

## Row Level Security (RLS)

Toda tabela do schema `public` deve ter Row Level Security habilitado no momento da criação (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`), já que esse schema é exposto pela API automática do Supabase (ver `01-technical-identity.md`) a clientes anônimos ou autenticados. Políticas de acesso específicas são criadas posteriormente, apenas quando houver necessidade concreta — até lá, o RLS habilitado sem políticas impede qualquer leitura ou escrita externa à administração direta do banco.

---

# 10. Migration Standards

## Ferramenta

Migrations são sempre executadas via SQL Editor (Supabase), nunca pelo menu visual de criação de tabelas. O menu visual é adequado para protótipos, mas o Project Mimikyu depende de constraints, triggers, funções, índices e checks — recursos mais bem organizados, documentados e rastreáveis em SQL.

A ideia inicial era organizar migrations em arquivos numerados (`000_initial_database.sql`, `001_create_game.sql`, ...). Na prática, com o uso direto do SQL Editor, essa organização evoluiu para **Queries nomeadas e numeradas dentro da própria ferramenta**, seguindo a mesma lógica sequencial.

## Padrão Oficial de Queries SQL do Project Mimikyu

O SQL Editor é tratado como o diário de construção do Project Mimikyu: qualquer pessoa deve conseguir acompanhar a evolução do banco apenas lendo a sequência de Queries, mesmo anos depois.

Toda Query deve possuir:

- **Número** — dentro da faixa oficial correspondente (ver "Faixas de Numeração", abaixo);
- **Nome** — curto, descritivo, em inglês (ex.: `Create Game table`);
- **Descrição** — em português, explicando o objetivo da Query;
- **Cabeçalho** — bloco de comentário no início do script (ver modelo abaixo);
- **SQL** — o script propriamente dito;
- **Validação** — uma ou mais consultas que confirmam que a execução funcionou corretamente (ver "Validação", abaixo).

### Faixas de Numeração (Esquema Legado — Congelado)

| Faixa | Finalidade |
|-------|------------|
| 000–099 | Infraestrutura do banco (extensões, funções compartilhadas, configurações globais) |
| 100–199 | Catálogo Editorial |
| 200–299 | Evoluções e migrations complementares do Catálogo Editorial — esquema legado (inclui as migrations `250`–`271`, já executadas) |
| 300–399 | (histórico — sem Queries executadas) |
| 400–499 | (histórico — sem Queries executadas) |
| 500–599 | (histórico — sem Queries executadas) |
| 600–699 | (histórico — sem Queries executadas) |
| 700–799 | (histórico — sem Queries executadas) |
| 800–899 | Dados iniciais (Seeds) — das entidades numeradas em 000–299 |
| 900–999 | Validações e consultas — das entidades numeradas em 000–299 |

Deixar intervalos entre os grupos permitiu inserir novas migrations sem perder a organização. Exemplo real (entidade Game): `000 - Enable pgcrypto`, `001 - Create updated_at function`, `100 - Create Game Table`, `101 - Create Game Trigger`, `800 - Seed Game`, `900 - Validate Game`.

**Todo o intervalo `000–999` está congelado para novas implementações** — cobre exclusivamente as Queries já executadas do Catálogo Editorial, suas evoluções (`200`–`271`) e a infraestrutura inicial. Nenhuma faixa acima, usada ou não, está reservada para futuros módulos (Coleções, Inventário, Aquisições, Armazenamento, Analytics, Views ou qualquer outro) — os nomes que aparecem nesta tabela refletem apenas o planejamento original, não uma reserva vigente. Todo módulo novo, a partir de Identidade e Acesso, segue o Modelo Modular de Numeração abaixo.

### Modelo Modular de Numeração (a partir de 4 dígitos)

Todo módulo novo recebe um milhar inteiro (`X000`–`X999`), sem colisão com o esquema legado ou com outros módulos:

| Faixa (relativa ao milhar `X000`) | Finalidade |
|---|---|
| `X000–X699` | Estrutura do módulo: tabelas, triggers, functions, Storage, e evoluções futuras — inclusive extensões conceitualmente distintas que pertençam ao mesmo módulo |
| `X700–X799` | Seeds |
| `X800–X899` | Validações |
| `X900–X999` | Reserva |

Dentro de `X000–X699`, cada entidade persistente continua ocupando um **bloco de dez** (`X0` cria a tabela, `X1` cria o trigger, `X2`/`X3`... reservados para evoluções da mesma entidade) — o mesmo princípio do esquema legado, descrito a seguir.

**Offset `+700`/`+800`:** deixa de ser obrigatório no modelo modular. Quando uma Seed ou Validação corresponde diretamente a uma única entidade e o número resultante do deslocamento não colide com nada já numerado, ele pode ser usado como conveniência. Nos demais casos — funções sem tabela própria, triggers transversais, Storage, validações sem correspondência 1:1 — Seed e Validação recebem o **próximo número sequencial livre** dentro de suas faixas, associados ao objeto correspondente pelo nome e pelo cabeçalho da Query, não pela aritmética do número.

**Módulos definidos:** `1000–1999` = Identidade e Acesso, incluindo papéis e permissões futuros (permanecem no mesmo milhar, não abrem um novo). Nenhum outro milhar está comprometido como decisão definitiva — novos módulos recebem milhar próprio quando efetivamente aprovados, não por reserva antecipada.

### Bloco por Entidade e Regra de Deslocamento (offset) — esquema legado

Dentro do Catálogo Editorial (100–199), cada entidade ocupa um bloco de 10 números: `X0` cria a tabela (`Create <Entity> Table`), `X1` cria o trigger (`Create <Entity> Trigger`), com os números seguintes reservados para evoluções futuras da mesma entidade (ex.: `X2`, `X3`...).

O Seed e a Validação de uma entidade são derivados do número da sua Query de criação de tabela por um deslocamento fixo:

```text
Seed      = (número de criação da tabela) + 700
Validate  = (número de criação da tabela) + 800
```

Exemplo real:

```text
Game       100 - Create Game Table       →  800 - Seed Game       →  900 - Validate Game
           101 - Create Game Trigger

Expansion  110 - Create Expansion Table  →  810 - Seed Expansion  →  910 - Validate Expansion
           111 - Create Expansion Trigger

Set        120 - Create Set Table        →  820 - Seed Set        →  920 - Validate Set
Rarity     130 - Create Rarity Table     →  830 - Seed Rarity     →  930 - Validate Rarity
Card       140 - Create Card Table       →  840 - Seed Card       →  940 - Validate Card
```

Essa regra elimina qualquer ambiguidade sobre qual número usar para o Seed ou a Validação de uma nova entidade.

> **Nota:** o número de uma entidade é atribuído na ordem em que ela é efetivamente modelada e aprovada, não necessariamente na ordem inicialmente imaginada — Rarity, por exemplo, precisou ser criada antes de Card por dependência de chave estrangeira (`card.rarity_id → rarity.id`), e por isso ocupa `130` em vez do `140` inicialmente cogitado para Card (ver `05-modelo-de-dados.md`, seções Rarity e Card).

### Seeds

Cada entidade possui sua própria Query de Seed (faixa 800–899), separada da Query que cria a tabela (faixa correspondente ao módulo, ex. 100–199). Estrutura e dados iniciais são responsabilidades diferentes.

Seeds devem ser **idempotentes** — executáveis múltiplas vezes sem criar registros duplicados, usando `INSERT ... ON CONFLICT (<coluna_única>) DO NOTHING` em vez de um `INSERT` simples:

```sql
INSERT INTO public.game (code, name)
VALUES ('POKEMON', 'Pokémon Trading Card Game')
ON CONFLICT (code) DO NOTHING;
```

Isso garante que reinstalar o banco do zero baste executar novamente todas as Seeds, sem falhas.

Quando um Seed depende de uma entidade relacionada, a chave estrangeira é resolvida por um `SELECT` no código de negócio da entidade relacionada — nunca um UUID fixo no script, já que o UUID real varia a cada execução:

```sql
INSERT INTO public.expansion (game_id, code, name, release_order)
SELECT game.id, 'ME', 'Mega Evolution', 1
FROM public.game
WHERE game.code = 'POKEMON'
ON CONFLICT (game_id, code) DO NOTHING;
```

Quando uma Seed precisa inserir mais de um registro relacionado à mesma entidade pai, um `CROSS JOIN` com uma lista `VALUES` é uma alternativa válida ao padrão de um `SELECT` por registro — resolvendo a chave estrangeira uma única vez e reaproveitando-a para todas as linhas (ver exemplo real em `05-modelo-de-dados.md`, seção Set — Query `820 - Seed Card Set`).

**Regra de confiabilidade dos dados de Seed:** uma Seed nunca deve inserir dados estimados como se fossem oficiais. Se a existência de um registro é conhecida, mas algum de seus atributos de negócio (quantidades, datas, contagens) ainda não foi validado contra uma fonte confiável, o registro fica de fora da Seed até que a validação aconteça — não se insere um valor aproximado apenas para completar o cadastro. Exemplo real: ao popular `card_set`, o Set `ME3` (`Equilíbrio Perfeito`) foi inicialmente deixado fora de uma versão preliminar da Seed `820` por falta de quantidades confirmadas; a Seed só foi de fato executada depois que Fabrício forneceu as folhas oficiais de verificação de todos os Sets, eliminando a necessidade de estimativa (ver `05-modelo-de-dados.md`, seção Set — "Fontes Primárias").

**Cuidado com `ON CONFLICT ... DO NOTHING` em correções:** essa cláusula garante que reexecutar uma Seed não crie duplicatas, mas ela também significa que **não atualiza** uma linha já existente. Se uma Seed for corrigida (ex.: um nome ou uma data errada) depois de já ter sido executada com sucesso, simplesmente reexecutar a versão corrigida não corrige os dados já gravados — é necessário um `UPDATE` explícito ou uma nova migration. Esse risco só se aplica a Seeds já executadas; corrigir uma Seed antes de sua primeira execução é seguro.

**`DO NOTHING` vs. `DO UPDATE`:** o padrão (`DO NOTHING`) é adequado para Seeds de carga inicial única. Para Seeds que representam o **estado atual e reaplicável de uma entidade** — por exemplo, o conjunto completo de Card Sets de uma Expansion, incluindo o Set promocional cuja quantidade cresce ao longo do tempo — prefira `ON CONFLICT ... DO UPDATE`, atualizando as colunas relevantes. Assim, reexecutar a Seed não apenas evita duplicidade, mas também corrige os registros existentes caso a fonte oficial seja atualizada. Critério: se a Seed representa "os dados iniciais que só existem uma vez", use `DO NOTHING`; se representa "o retrato mais atual e correto que conhecemos desta entidade", use `DO UPDATE`.

**Bloco `DO $$ ... END $$` com verificação explícita de pré-requisito:** quando a ausência de uma entidade-pai deve ser um erro visível — não um `INSERT` que silenciosamente insere zero linhas — a Seed pode ser escrita como um bloco PL/pgSQL, resolvendo a chave estrangeira uma única vez em uma variável e usando `RAISE EXCEPTION` caso o pré-requisito não exista:

```sql
DO $$
DECLARE
    v_game_id UUID;
BEGIN
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'Game POKEMON não está cadastrado.';
    END IF;

    INSERT INTO public.rarity (game_id, code, name, display_order)
    VALUES (v_game_id, 'COMMON', 'Comum', 1)
    ON CONFLICT (game_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        display_order = EXCLUDED.display_order;
END;
$$;
```

Alternativa válida ao padrão `INSERT ... SELECT ... WHERE` já documentado acima — usar quando a falha silenciosa (zero linhas inseridas, sem aviso) for um risco maior do que a verbosidade de um bloco `DO`. Exemplo real: `830 - Seed Rarity`.

### Convenções de Apresentação da Query

Além do cabeçalho oficial (ver "Modelo de Cabeçalho", abaixo), cada Query deve ser acompanhada de uma **descrição resumida** — uma linha curta, sem o detalhamento completo do cabeçalho, usada para organizar e indexar visualmente o SQL Editor do Supabase à medida que o número de Queries cresce (dezenas ou centenas de scripts). Ao apresentar uma Query durante o par de execução, a resposta deve começar por `Query: NNN - Título` seguido de um `Objetivo:` de uma ou duas frases, antes do SQL propriamente dito — convenção adotada a partir da entidade Rarity, a pedido de Fabrício ("Isso me ajuda a manter o SQL Editor organizado e padronizado").

### Registro em `database/`

Depois que uma Query for executada e confirmada no Supabase, o mesmo SQL (com o cabeçalho oficial completo) deve ser copiado como arquivo `.sql` para o subdiretório correspondente em `database/` (fora de `docs/`), organizada pela mesma faixa de numeração desta seção — ver `database/README.md`. Isso garante que o histórico de execução exista de forma versionada no Git, não apenas dentro do Supabase ou embutido em prosa em `05-modelo-de-dados.md`. Este passo é posterior à execução — nunca usar `database/` como fonte para rodar migrations automaticamente (a execução real continua manual, via SQL Editor).

### Validação

Toda alteração estrutural recebe sua própria Query de validação (faixa 900–999), reutilizável sempre que a tabela correspondente for alterada novamente (ex.: `900 - Validate Game`, `901 - Validate Expansion`). As Queries 900+ funcionam, na prática, como um conjunto de testes manuais do banco.

Nunca se assume que uma operação funcionou apenas porque o Supabase retornou "Success" — cada tipo de mudança tem sua própria forma de confirmação: criar uma tabela é validado com um `SELECT`; criar um índice é validado confirmando sua existência; criar um trigger é validado confirmando que está corretamente associado à tabela.

**Padrão de cinco categorias para toda Query `9xx - Validate`:** a partir da entidade Card Set, toda Query de validação passa a cobrir cinco categorias, transformando-a em um verdadeiro teste de integridade, não apenas uma consulta de inspeção. Uma primeira proposta agrupava isso em três seções (estrutural / dados / regras derivadas); na prática, ao aplicar o padrão em Card Set, ele se mostrou mais útil dividido em cinco:

1. **Dados persistidos** — os valores realmente gravados nas colunas, com JOIN até as entidades relacionadas para leitura por código de negócio, não por UUID.
2. **Regras de negócio derivadas** — valores que não existem como coluna na tabela, mas fazem parte do domínio (ex.: `secret_set_size = total_set_size - base_set_size` em Card Set). Inclui também consultas de resumo/contagem por categoria (ex.: quantos Sets de cada `set_type` existem).
3. **Inconsistências** — consultas que devem retornar **zero linhas** quando tudo está correto (ex.: lacunas na sequência editorial, um Set promocional com data diferente da esperada, mais de um Set promocional na mesma Expansion). Esse é o formato mais forte de teste: o "resultado esperado" é a ausência de resultado.
4. **Constraints** — confirmar via `information_schema.table_constraints`/`check_constraints` que as constraints esperadas existem, com a definição exata de cada `CHECK`.
5. **Trigger** — confirmar via `information_schema.triggers` que o trigger de `updated_at` está associado à tabela correta.

Nem toda entidade precisará das cinco categorias completas (a categoria "inconsistências" só se aplica quando há regras condicionais, como as de Card Set promocional) — mas a ordem e a nomenclatura das categorias usadas devem seguir este padrão.

**Migrations que alteram constraints e dados existentes juntas devem ser transacionais:** envolver a Query inteira em `BEGIN; ... COMMIT;`, garantindo que uma falha em qualquer etapa não deixe o banco em estado intermediário (ex.: constraint alterada mas dados ainda não ajustados). Exemplo real: `122 - Adapt Card Set for Promo`, que remove e recria uma constraint, executa dois `UPDATE`s em sequência e adiciona uma nova constraint, tudo dentro de uma única transação.

### Princípio da Fonte Canônica

**Cada Query do repositório deve representar a forma correta e definitiva de criar aquela entidade em uma instalação nova do sistema.** Consequências diretas:

- não se mantêm migrations corretivas permanentes no fluxo padrão de instalação — quando o modelo de uma entidade evolui (ex.: um novo `set_type`, uma nova constraint), a **Query original de criação é atualizada em lugar** (mesmo número, nova `Versão` no cabeçalho), passando a já nascer correta;
- o histórico de como o modelo evoluiu passa a pertencer ao **controle de versão (Git)**, não à sequência de Queries — quem precisar consultar uma versão anterior de uma Query usa o histórico do repositório, não uma migration antiga ainda "ativa";
- uma migration que altera um banco **já existente** (ex.: `122 - Adapt Card Set for Promo`) continua registrada e preservada — não é apagada — mas passa a ser classificada como **histórica**: aplicável apenas a instalações antigas que já passaram por aquele estado intermediário, e explicitamente **fora** do fluxo de instalação limpa;
- o repositório deve sempre conseguir reconstruir o banco do zero executando apenas as Queries `CANÔNICA`s, na ordem de suas faixas — nunca dependendo de uma sequência de migrations históricas.

Este princípio foi adotado a partir da consolidação da entidade Card Set (Queries `120`/`820`, ver `05-modelo-de-dados.md`, seção Set): a Query `120 - Create Card Set Table` e a Query `820 - Seed Card Set` foram atualizadas em lugar (para `Versão 2.0`) para já nascerem com suporte nativo a `PROMO`, e as Queries `122`/`821` (que originalmente introduziram esse suporte em um banco já existente) foram reclassificadas como históricas.

**Atenção:** atualizar a Query canônica no repositório não executa nada automaticamente contra o banco físico. Se o banco atual já foi construído pelo caminho antigo (Query original + migration histórica), ele deve ser conferido individualmente contra a nova versão canônica — pode haver uma diferença estrutural entre "o que o banco atual tem" e "o que a Query canônica descreveria em uma instalação nova" até que essa conferência seja feita (ver nota concreta em `05-modelo-de-dados.md`, seção Set, sobre o índice único parcial de Card Set).

### Modelo de Cabeçalho

```sql
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 100 - Create Game table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: [nome]
Data........: AAAA-MM-DD

Descrição...:
[o que este script cria ou altera]

Regras de Negócio:
- [regra 1]
- [regra 2]
================================================================
*/
```

O campo **Versão** identifica a evolução do próprio script (ex.: uma Query canônica que evolui de `1.0` para `2.0` preserva o número da Query, apenas incrementando a versão).

O campo **Status** identifica o papel da Query frente ao Princípio da Fonte Canônica (acima):

- **CANÔNICA** — representa a forma correta e mais atual de criar aquela estrutura; é o que uma instalação nova deve executar.
- **MIGRATION** — uma alteração histórica, já aplicada a um banco que existia antes da versão canônica correspondente; não faz parte do fluxo de instalação limpa, mas é preservada como registro.

## Execução

Uma etapa por vez, sempre validada antes de avançar: instalar extensão → validar → criar função → validar → criar tabela → validar. Isso facilita identificar exatamente onde algo deu errado, em vez de executar dezenas de comandos de uma só vez.

## Rollback de Alterações Estruturais

Toda alteração estrutural (tabela, trigger, function, política de RLS, configuração de Storage) segue o mesmo princípio de rollback: a reversão padrão **nunca remove nem desabilita imediatamente** o objeto alterado. O procedimento padrão é:

1. Impedir que a aplicação continue gerando novos dados dependentes do comportamento a ser revertido — a forma concreta desse bloqueio é específica de cada mudança e deve ser documentada onde a mudança é descrita (`05-modelo-de-dados.md`, ADR do módulo), não neste Standard.
2. Reverter o deploy da aplicação (frontend/Edge Function) que depende do objeto.
3. Preservar dados e infraestrutura já existentes no banco — tabelas, triggers e functions permanecem intactos, sem `DROP` nem `DISABLE`.

A remoção definitiva de um objeto de banco é um **processo separado de abandono arquitetural**, com Queries próprias, nomeadas e revisadas individualmente — nunca o procedimento padrão de rollback.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do documento. |
| 1.1 | Preenchidas as Seções 2 (Naming Conventions), 5 (Primary Keys) e 6 (Foreign Keys): tabelas em `snake_case` singular, colunas em `snake_case` (nunca camelCase/PascalCase), chave primária `id` (UUID) como identidade técnica, chave estrangeira no padrão `<entidade_referenciada>_id`. |
| 1.2 | Adicionada nota sobre palavras reservadas do SQL na Seção 2 (ex.: Set → `card_set`). Preenchida a Seção 3 (Data Types: VARCHAR vs. TEXT, UUID, TIMESTAMPTZ). Refinada a Seção 4 (Audit Model): `created_by`/`updated_by`/`deleted_at`/`deleted_by` deixam de ser obrigatórios por padrão, passando a ser adicionados apenas sob necessidade concreta (Princípio da Simplicidade Inicial, AP-004); padrão mínimo agora é `id`/`created_at`/`updated_at`. Adicionada à Seção 5 a versão do UUID (v4 no MVP, v7 quando houver suporte adequado) e a distinção entre identidade técnica (`id`) e identidade de negócio (`code`). Preenchida a Seção 8 (Logical Delete: preferir `status` de negócio a soft delete generalizado) e a Seção 9 (SQL Standards: restrições de integridade também no banco, não só na aplicação). |
| 1.3 | Refinada a Seção 1 (Technical Language): cabeçalhos e comentários explicativos dos scripts SQL passam a ser em português; apenas identificadores técnicos seguem o inglês. Adicionado à Seção 9 o requisito de Row Level Security (RLS) habilitado em toda tabela do schema `public`. Preenchida a Seção 10 (Migration Standards): uso exclusivo do SQL Editor (nunca o menu visual), Padrão Oficial de Queries SQL (Número/Nome/Descrição/Cabeçalho/SQL/Validação, com modelo de cabeçalho incluindo Versão) e execução validada passo a passo. |
| 1.4 | Adicionada à Seção 5 a regra "código internacional, nome localizável" (code nunca muda entre idiomas; name pode ser localizado, mesmo padrão de Card Translation/ADR-007). Substituída, na Seção 10, a numeração sequencial simples pela convenção oficial de Faixas de Numeração (000–999, por módulo do projeto); adicionadas as subseções Seeds (idempotência via `ON CONFLICT ... DO NOTHING`, Query própria por entidade) e Validação (Queries de validação reutilizáveis na faixa 900–999; nunca assumir que "Success" significa que o resultado está correto). |
| 1.5 | Adicionada à Seção 10 a regra de bloco por entidade e deslocamento fixo (Seed = criação da tabela + 700; Validate = criação da tabela + 800), confirmada com Game e Expansion. Adicionada orientação para Seeds com dependência de entidade relacionada: resolver a chave estrangeira por `SELECT` no código de negócio, nunca por UUID fixo no script. |
| 1.6 | Adicionada à Seção 10 (Seeds) a alternativa de `CROSS JOIN` com `VALUES` para inserir múltiplos registros relacionados à mesma entidade pai em uma única Query, confirmada com Card Set. Adicionada a regra de confiabilidade dos dados de Seed: nunca inserir dados estimados como oficiais — registros com atributos ainda não validados ficam de fora até a validação (exemplo real: Set `ME3` deixado fora de uma versão preliminar da Seed `820` por falta de quantidades confirmadas). |
| 1.7 | Atualizado o exemplo de `ME3`: a Seed `820` foi de fato executada com todos os cinco Sets (`ME1`–`ME4`) após Fabrício fornecer as folhas oficiais de verificação de cada um. Adicionado alerta permanente: `ON CONFLICT ... DO NOTHING` não atualiza linhas já existentes — corrigir uma Seed já executada exige `UPDATE` explícito ou nova migration, não apenas reexecutar a Query. |
| 1.8 | Adicionado à Seção 10 (Validação) o padrão de três seções para toda Query `9xx - Validate`: validação estrutural, validação dos dados persistidos e validação das regras de negócio derivadas (valores que não existem como coluna, mas fazem parte do domínio — ex.: `secret_set_size`). Adotado a partir da entidade Card Set. |
| 1.9 | Revisado o padrão de validação (1.8) de três para cinco categorias, após aplicação real em Card Set: dados persistidos, regras derivadas, inconsistências (consultas que devem retornar zero linhas), constraints, trigger. Adicionada recomendação de envolver migrations que alteram constraints e dados juntas em uma transação explícita (`BEGIN`/`COMMIT`), com `122 - Adapt Card Set for Promo` como exemplo real. Adicionada à Seção 10 (Seeds) a distinção entre `DO NOTHING` (carga inicial única) e `DO UPDATE` (Seeds que representam o estado atual e reaplicável de uma entidade). |
| 1.10 | Adicionada à Seção 10 a subseção "Registro em `database/`": toda Query executada e confirmada deve ser copiada como arquivo `.sql` versionado em `database/`, fora de `docs/` — registrado durante auditoria de saúde do repositório (2026-07-23). |
| 1.11 | Adicionado o "Princípio da Fonte Canônica": Queries de criação/seed representam sempre a forma correta e mais atual para uma instalação nova; migrations que alteram um banco já existente são preservadas, mas reclassificadas como históricas, fora do fluxo de instalação limpa. Adicionado o campo `Status` (`CANÔNICA`/`MIGRATION`) ao Modelo de Cabeçalho oficial. Aplicado pela primeira vez em Card Set (`120`/`820` atualizadas para v2.0; `122`/`821` reclassificadas). |
| 1.12 | Atualizado o exemplo real da Seção 10 (Bloco por Entidade e Regra de Deslocamento): inserida a entidade Rarity em `130` (Seed `830`, Validate `930`), criada antes de Card por dependência de chave estrangeira (`card.rarity_id`). Card deslocada de `130` para `140` (Seed `840`, Validate `940`). Adicionada nota explicando que a numeração segue a ordem real de modelagem/aprovação, não a ordem originalmente cogitada. |
| 1.13 | Adicionado à Seção 10 (Seeds) o padrão de bloco `DO $$ ... END $$` com verificação explícita de pré-requisito via `RAISE EXCEPTION`, alternativa ao padrão `INSERT ... SELECT ... WHERE` para quando a ausência de uma entidade-pai deve ser um erro visível (exemplo real: `830 - Seed Rarity`). Adicionada nova subseção "Convenções de Apresentação da Query": toda Query deve ter uma descrição resumida para organizar o SQL Editor, e a apresentação de cada Query no par de execução deve começar por `Query: NNN - Título` + `Objetivo:`, a pedido de Fabrício. |
| 1.14 | Adicionada à Seção 3 a subseção "Colunas `JSONB` de `metadata`": `metadata` nunca deve duplicar um atributo já existente em coluna relacional (própria ou de tabela relacionada) — existe apenas para propriedades específicas de uma fonte externa, sem equivalente relacional. Nasceu de um caso real: `card_set_external_reference.metadata` de `MEP` guardava campos já cobertos por `card_set` (`code`/`name`/`release_date`) e um campo (contagem de cartas) que ficaria desatualizado rapidamente — corrigido para `{}`, mesmo padrão dos demais registros. |
| 1.15 | Motivada pelo incremento de Identidade e Acesso (User Profile, ver ADR-020): a Seção 10 (Faixas de Numeração) foi reclassificada como **esquema legado e congelado** — `200`–`299` passa a ser descrita como "Evoluções e migrations complementares do Catálogo Editorial" (contém as migrations `250`–`271`, já executadas), e todo o intervalo `000`–`999` é declarado congelado para novas implementações, sem reserva antecipada para Coleções/Inventário/Aquisições/etc. Adicionado o **Modelo Modular de Numeração**: todo módulo novo recebe um milhar inteiro (`X000`–`X999`), com `X000–X699` para estrutura, `X700–X799` para Seeds, `X800–X899` para validações e `X900–X999` de reserva; o deslocamento `+700`/`+800` deixa de ser obrigatório, valendo como conveniência quando não colide. `1000–1999` aprovado para Identidade e Acesso (incluindo papéis/permissões futuros, sem abrir milhar próprio). Adicionada a subseção "Rollback de Alterações Estruturais" (Seção 10): rollback padrão nunca remove/desabilita objetos imediatamente — bloqueia a origem de novos dados, reverte a aplicação e preserva banco; remoção definitiva é processo separado de abandono arquitetural. Corrigido também o campo **Versão** do cabeçalho, que permanecia em `1.0` desde a criação do documento, dessincronizado do Revision History (já em `1.14`). |