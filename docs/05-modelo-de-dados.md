# Modelo de Dados

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados |
| **Arquivo** | `docs/05-modelo-de-dados.md` |
| **Versão** | 0.1 |
| **Status** | Em elaboração |
| **Objetivo** | Definir o modelo lógico e físico de cada entidade do domínio, um bloco de cada vez, validado com dados reais antes de avançar. |
| **Escopo** | Modelagem lógica e física (SQL) das entidades já conceitualmente definidas em `04-domain-model.md`. Não redefine conceitos de domínio nem decisões arquiteturais (ver ADRs). |
| **Dependências** | `04-domain-model.md`, `standards/STD-001-database-standards.md` |
| **Documentos Relacionados** | `01-technical-identity.md`, `adr/ADR-004-set-identity.md` |

---

# Purpose

Este documento registra o modelo lógico e físico de cada entidade do domínio do Project Mimikyu, entidade por entidade, seguindo o processo da Fase 2 (Modelo Lógico) do projeto: cada bloco é modelado, implementado, populado com dados reais e validado antes de avançar para o próximo (ver "Status Atual do Projeto" em `README.md`).

Os padrões gerais e permanentes (nomenclatura, tipos de dado, chaves, auditoria, exclusão lógica, restrições) estão definidos em `standards/STD-001-database-standards.md` e não são repetidos aqui — este documento aplica esses padrões a cada entidade específica.

> **Nota importante:** o banco físico do Project Mimikyu (Supabase, projeto `mimikyu-core`) já possui 17 tabelas com carga inicial de dados, construídas antes do início desta fase de consolidação documental (ver "Status Atual do Projeto" em `README.md`). Para a maioria das entidades a seguir, o roteiro abaixo não representa uma sequência de criação do zero — representa a documentação retroativa da estrutura já existente, confirmada contra o banco real à medida que os lotes históricos forem processados. Game foi a exceção: sua tabela foi recriada/validada junto com o restante desta documentação, e por isso já segue o roteiro completo do início ao fim.

---

# Roteiro por Entidade

Cada entidade documentada aqui segue o mesmo roteiro:

1. **Modelo lógico** — atributos, sem pensar em SQL ainda, organizados por grupo (como um analista de dados faria, não como um DBA): Identidade (`id`, `code`), Descrição (`name` e demais campos descritivos), Relacionamento (chaves estrangeiras, ex. `game_id`), Ordenação (quando aplicável, ex. `release_order`), Auditoria (`created_at`, `updated_at`). Só depois desse desenho a migration é escrita — essa disciplina garante que o SQL seja apenas a implementação de um modelo já validado, não o lugar onde decisões de negócio são tomadas.
2. **Atributos** — descrição de cada campo.
3. **Campos que não incluiremos agora** — aplicação do Princípio da Simplicidade Inicial (AP-004).
4. **Regras de negócio.**
5. **Modelo físico (SQL)** — DDL, incluindo constraints e triggers, seguindo o Padrão Oficial de Queries SQL (ver STD-001, Seção 10: Faixas de Numeração, Seeds idempotentes, Validação reutilizável).
6. **Testes mínimos de integridade.**
7. **Definition of Done** — critérios para considerar a entidade concluída.

Uma entidade só é considerada concluída quando todos os itens de sua Definition of Done forem atendidos. A pergunta orientadora para congelar uma entidade é: *"Se amanhã o sistema entrar em produção, eu mudaria essa tabela?"* — se a resposta for não, a entidade é congelada e o trabalho avança para a próxima.

---

# Game (Jogo)

Status: **Concluído** — pronto para implementação.

## Modelo Lógico

```text
Game
  id
  code
  name
  created_at
  updated_at
```

## Atributos

**id** — Identificador técnico e permanente (UUID). Não possui significado de negócio e não é normalmente exibido ao usuário (ver STD-001, Seção 5).

**code** — Código curto e estável, utilizado internamente e em integrações (ex.: `POKEMON`). Obrigatório, único, escrito em letras maiúsculas, não muda quando o nome de exibição muda (ver STD-001, Seção 5 — Identidade de Negócio).

**name** — Nome oficial ou comercial do jogo (ex.: `Pokémon Trading Card Game`). Obrigatório, destinado à apresentação; pode conter espaços, acentos e caracteres especiais.

**created_at** — Momento em que o registro foi criado (`TIMESTAMPTZ`).

**updated_at** — Momento da última alteração do registro (`TIMESTAMPTZ`), atualizado automaticamente por trigger.

## Campos que Não Incluiremos Agora

Aplicando o Princípio da Simplicidade Inicial (AP-004): `description`, `publisher`, `release_date`, `logo_url`, `website_url`, `status`, `deleted_at`, `created_by`, `updated_by`, `version`.

Nenhum desses campos é necessário para criar a hierarquia editorial inicial. Quando alguma funcionalidade real exigir um deles, a tabela evoluirá por meio de uma nova migration.

## Regras de Negócio

**Regra 1 — Código obrigatório e único.** Não podem existir dois jogos com o mesmo `code` (ex.: `POKEMON` duplicado é inválido).

**Regra 2 — Nome obrigatório.** O Game precisa possuir um nome de apresentação.

**Regra 3 — Código normalizado.** O `code` deve usar apenas `A-Z`, `0-9` e `_`. Exemplos válidos: `POKEMON`, `MAGIC`, `ONE_PIECE`, `LORCANA`. Exemplos inválidos: `pokemon`, `POKÉMON`, `ONE PIECE`, `ONE-PIECE`.

**Regra 4 — Identidade técnica independente.** Mudanças no `name` não alteram o `id` nem o `code`. A entidade continua sendo a mesma.

**Regra 5 — Exclusão restrita.** Um Game que já possua Expansions não deve ser excluído. Implementada pela chave estrangeira da tabela `expansion`, com comportamento restritivo (`ON DELETE RESTRICT`).

## Modelo Físico (PostgreSQL)

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE game (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_game_code
        UNIQUE (code),

    CONSTRAINT ck_game_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_game_name_not_blank
        CHECK (btrim(name) <> '')
);
```

### Atualização automática de `updated_at`

O PostgreSQL não atualiza esse campo automaticamente. Para não depender de todas as aplicações e importadores lembrarem de alterá-lo, usa-se uma função reutilizável:

```sql
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_game_set_updated_at
BEFORE UPDATE ON game
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
```

`set_updated_at()` é reutilizável e será associada às próximas tabelas da mesma forma.

### Verificação do Trigger

Após criar o trigger (Query `101 - Create Game trigger`), a associação é confirmada consultando o catálogo do PostgreSQL — não basta o "Success" da execução:

```sql
SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    event_object_schema,
    event_object_table
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'game'
  AND trigger_name = 'trg_game_set_updated_at';
```

Resultado esperado: uma linha com `trigger_name = trg_game_set_updated_at`, `event_manipulation = UPDATE`, `action_timing = BEFORE`, `event_object_schema = public`, `event_object_table = game`.

### Row Level Security

Toda tabela do schema `public` deve ter RLS habilitado no momento da criação (ver STD-001, Seção 9):

```sql
ALTER TABLE game ENABLE ROW LEVEL SECURITY;
```

Sem políticas de acesso definidas ainda, isso impede qualquer leitura ou escrita pela API automática do Supabase — apenas a administração direta do banco tem acesso, até que políticas específicas sejam criadas.

## Testes Mínimos de Integridade

**Código duplicado — deve falhar** (viola `uq_game_code`):

```sql
INSERT INTO game (code, name) VALUES ('POKEMON', 'Outro Pokémon');
```

**Código fora do padrão — deve falhar** (viola `ck_game_code_format`):

```sql
INSERT INTO game (code, name) VALUES ('pokemon', 'Pokémon');
```

**Nome vazio — deve falhar** (viola `ck_game_name_not_blank`):

```sql
INSERT INTO game (code, name) VALUES ('MAGIC', '   ');
```

**Inserção válida (primeiro dado real):**

```sql
INSERT INTO game (code, name) VALUES ('POKEMON', 'Pokémon Trading Card Game');
```

**Atualização — deve funcionar, preservando identidade:**

```sql
UPDATE game SET name = 'Pokémon TCG' WHERE code = 'POKEMON';
```

Após essa atualização: `id` permanece igual; `code` permanece igual; `updated_at` é atualizado automaticamente.

## Definition of Done

A entidade é considerada concluída quando:

- [x] o PostgreSQL estiver disponível;
- [x] a extensão `pgcrypto` estiver habilitada;
- [x] a função `set_updated_at()` estiver criada;
- [x] a tabela `game` estiver criada;
- [x] o RLS estiver habilitado em `game`;
- [x] o registro `POKEMON` estiver inserido;
- [x] os testes de integridade forem executados;
- [x] o resultado estiver validado.

## Modelo Consolidado

```text
Game (Jogo)

PK  id          UUID
UK  code        VARCHAR(50)
    name        VARCHAR(150)
    created_at  TIMESTAMPTZ
    updated_at  TIMESTAMPTZ
```

## Queries Associadas

Seguindo o Padrão Oficial de Queries SQL (STD-001, Seção 10):

```text
000 - Enable pgcrypto
001 - Create updated_at function
100 - Create Game Table
101 - Create Game Trigger
800 - Seed Game
900 - Validate Game
```

Com a criação e verificação do trigger (`101`), o pacote inicial de Game (Jogo) está tecnicamente completo.

Próxima entidade: **Expansion**, que introduziu o primeiro relacionamento e a primeira chave estrangeira do modelo físico (`Game → Expansion`).

---

# Expansion (Expansão)

Status: **Pacote técnico concluído** (tabela, trigger, seed e validação executados e confirmados). **Sem pendências.** A ausência de `logo_url` no DDL executado, antes registrada como pendência, foi reclassificada como correta — ver "Correção — logo_url pertence ao Set, não à Expansion", abaixo.

## Modelo Lógico

Desenhado por grupo, antes de qualquer SQL (ver "Roteiro por Entidade", acima):

```text
Expansion

Identidade
----------
id
code

Descrição
----------
name

Relacionamento
----------
game_id

Ordenação
----------
release_order

Auditoria
----------
created_at
updated_at
```

Uma proposta inicial havia incluído também `logo_url` neste modelo — corrigida posteriormente: a identidade visual pertence ao Set, não à Expansion (ver "Correção — logo_url pertence ao Set, não à Expansion", abaixo). O diagrama acima já reflete o modelo final, sem `logo_url`.

## Atributos

**id** — Identificador técnico e permanente (UUID).

**code** — Código editorial e internacional, não muda entre idiomas (ex.: `SV`, `SWSH`, `SM`, `XY`, `BW`). Obrigatório, curto, estável. Ver STD-001, Seção 5 — Código Internacional, Nome Localizável.

**name** — Nome de apresentação (ex.: `Scarlet & Violet`, `Sword & Shield`, `Sun & Moon`). Pode ser localizado futuramente.

**game_id** — Chave estrangeira para `game` (ver STD-001, Seção 6). Toda Expansion pertence obrigatoriamente a um Game (cardinalidade `Game 1 --- N Expansion`).

**release_order** — Ordem cronológica da Expansion dentro do Game. Inteiro simples, sem intervalos reservados (ver `04-domain-model.md`, seção Expansion — "Ordem de Lançamento").

**created_at / updated_at** — Auditoria mínima (ver STD-001, Seção 4).

## Campos que Não Incluiremos Agora

Aplicando o Princípio da Simplicidade Inicial (AP-004): `status` (nenhum caso de uso concreto identificado — ver `04-domain-model.md`), `release_date`, `base_set_size`, `total_set_size`, `secret_set_size` (todos pertencem ao Set, não à Expansion — ver `04-domain-model.md`, seção Set), `logo_url` (identidade visual pertence ao Set, não à Expansion — ver "Correção — logo_url pertence ao Set, não à Expansion", abaixo).

## Regras de Negócio

**Regra 1 — Relacionamento obrigatório.** Toda Expansion deve pertencer a exatamente um Game.

**Regra 2 — Código único por Game.** O código deve ser único dentro do respectivo Game (`UNIQUE (game_id, code)`), não globalmente — outro Game pode reutilizar o mesmo código.

**Regra 3 — Ordem única por Game.** A ordem de lançamento deve ser única dentro do respectivo Game (`UNIQUE (game_id, release_order)`) e deve ser um número inteiro positivo.

**Regra 4 — Nome obrigatório.** O nome não pode ser vazio.

**Regra 5 — Exclusão restrita.** Um Game que possua Expansions não pode ser excluído (`ON DELETE RESTRICT`).

## Modelo Físico (PostgreSQL) — Executado

```sql
CREATE TABLE public.expansion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    release_order INTEGER NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_expansion_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_expansion_game_code
        UNIQUE (game_id, code),

    CONSTRAINT uq_expansion_game_release_order
        UNIQUE (game_id, release_order),

    CONSTRAINT ck_expansion_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_expansion_name_not_blank
        CHECK (btrim(name) <> ''),

    CONSTRAINT ck_expansion_release_order_positive
        CHECK (release_order > 0)
);

ALTER TABLE public.expansion
    ENABLE ROW LEVEL SECURITY;
```

Query: `110 - Create Expansion Table`. Resultado confirmado: `Success. No rows returned`.

### Trigger de `updated_at`

```sql
CREATE TRIGGER trg_expansion_set_updated_at
BEFORE UPDATE ON public.expansion
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
```

Query: `111 - Create Expansion Trigger`. Resultado confirmado: `Success. No rows returned`. Reaproveita a função compartilhada `set_updated_at()` (ver seção Game, acima).

### Seed

Primeira Expansion incorporada ao catálogo — resolve o `game_id` por `SELECT` no código do Game, nunca por UUID fixo (ver STD-001, Seção 10):

```sql
INSERT INTO public.expansion (
    game_id,
    code,
    name,
    release_order
)
SELECT
    game.id,
    'ME',
    'Mega Evolution',
    1
FROM public.game
WHERE game.code = 'POKEMON'
ON CONFLICT (game_id, code)
DO NOTHING;
```

Query: `810 - Seed Expansion`. Resultado confirmado: `Success. No rows returned`. Idempotente — executar novamente não cria uma segunda Expansion `ME` para o mesmo Game.

> **Nota sobre `release_order`:** neste momento, `release_order = 1` representa a primeira Expansion incorporada ao catálogo do Project Mimikyu — não a primeira Expansion da história do Pokémon TCG. Quando Expansions históricas anteriores (Base, Neo, e-Card, EX, Diamond & Pearl...) forem importadas, essa ordenação precisará ser revisada para refletir a cronologia editorial completa (ver `04-domain-model.md`, seção Expansion — "Ordem de Lançamento").

### Validação

```sql
-- 1. Dados e relacionamento com Game
SELECT
    expansion.id,
    game.code AS game_code,
    game.name AS game_name,
    expansion.code AS expansion_code,
    expansion.name AS expansion_name,
    expansion.release_order,
    expansion.created_at,
    expansion.updated_at
FROM public.expansion
INNER JOIN public.game
    ON game.id = expansion.game_id
ORDER BY
    game.code,
    expansion.release_order;

-- 2. Validação do trigger de updated_at
SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    event_object_schema,
    event_object_table
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'expansion'
  AND trigger_name = 'trg_expansion_set_updated_at';
```

Query: `910 - Validate Expansion`. A primeira consulta confirmou uma linha (`game_code = POKEMON`, `expansion_code = ME`, `expansion_name = Mega Evolution`, `release_order = 1`); a segunda confirmou o trigger (`trg_expansion_set_updated_at`, `UPDATE`, `BEFORE`, tabela `expansion`).

## Queries Associadas

```text
110 - Create Expansion Table
111 - Create Expansion Trigger
810 - Seed Expansion
910 - Validate Expansion
```

Seguindo a regra de deslocamento fixo (STD-001, Seção 10: Seed = criação + 700, Validate = criação + 800).

## Correção — logo_url pertence ao Set, não à Expansion

**Histórico desta pendência (preservado para rastreabilidade):** a discussão conceitual original ("Modelo revisado de Expansion") havia concluído que a entidade deveria incluir `logo_url`, e Fabrício chegou a confirmar esse modelo antes da execução. O DDL efetivamente executado (Query `110`, acima) não incluiu essa coluna. Isso foi registrado em ciclos anteriores como uma divergência e, depois, como um "descuido" a ser corrigido por `ALTER TABLE`.

**Correção final, ao concluir a modelagem do Set:** ao modelar formalmente o Set (ver seção "Set", abaixo), ficou claro que a identidade visual (logotipo completo e símbolo pequeno usado nas Cards) pertence ao **Set**, não à Expansion — cada Set possui seu próprio logotipo editorial, mesmo dentro da mesma Expansion (ex.: `ME1` e `ME2` têm logotipos diferentes, ainda que ambos pertençam à Expansion `Mega Evolution`). **A ausência de `logo_url` no DDL executado da Expansion estava, portanto, correta — não era um descuido.** Nenhuma migration `ALTER TABLE ... ADD COLUMN logo_url` deve ser criada para `expansion`.

A identidade visual segue pendente, mas agora corretamente escopada ao Set: ver `05-modelo-de-dados.md`, seção Set — "Campos que Não Incluiremos Agora", e `04-domain-model.md`, seção Set — "Identidade Visual".

---

# Set

Status: **Tabela, trigger e seed executados no Supabase — primeiro núcleo do catálogo editorial concluído** (cinco Sets da Expansion `ME`, dados validados contra folhas oficiais). Tabela física: `card_set` (ver nota em `04-domain-model.md` e STD-001, Seção 2 — `SET` é palavra reservada do SQL). **Pendências, identificadas antes de iniciar a entidade Card** (ver "Disciplina do processo", abaixo): (1) Query `920 - Validate Card Set` redigida mas ainda sem execução/confirmação registrada; (2) migration `122 - Adapt Card Set for Promo Series`, para suportar o tipo `PROMO` (ver "Extensão Planejada — Card Set Promocional", abaixo; ADR-015), ainda não executada.

### Disciplina do processo

Ao propor avançar diretamente para a entidade Card, foi identificado um desvio da disciplina já estabelecida pelo próprio projeto: `Criar estrutura → Criar trigger → Popular (Seed) → Validar → Somente então seguir para a próxima entidade`. A Query `920` ainda não havia sido escrita nem executada — avançar para Card antes de fechar completamente o pacote de Card Set teria quebrado essa disciplina. Por isso, `920` foi escrita (abaixo) e a extensão para suportar Sets promocionais foi tratada antes de iniciar a modelagem de Card.

## Modelo Lógico

Desenhado por grupo, antes de qualquer SQL (ver "Roteiro por Entidade", acima):

```text
Card Set

Identidade
----------
id
code

Descrição
----------
name
set_type
release_date
base_set_size
total_set_size

Relacionamento
----------
expansion_id

Ordenação
----------
release_order

Auditoria
----------
created_at
updated_at
```

## Atributos

**id** — Identificador técnico e permanente (UUID).

**expansion_id** — Chave estrangeira obrigatória para `expansion` (ver STD-001, Seção 6). Todo Set pertence a exatamente uma Expansion (cardinalidade `Expansion 1 --- N Card Set`).

**code** — Código editorial, textual — nunca numérico, pois Sets especiais podem ter códigos não inteiros (ex.: `ME2.5`). Não deve ser interpretado como número nem usado para inferir ordem cronológica. Único dentro da Expansion (`UNIQUE (expansion_id, code)`), mesmo padrão de unicidade escopada já aplicado à Expansion (ver `04-domain-model.md`, seção Set — "Unicidade por Expansion").

**name** — Nome de apresentação do catálogo (ex.: `Mega Evolution`, `Phantasmal Flames`, `Ascended Heroes`, `Perfect Order`). Localização futura tratada separadamente, sem duplicar a identidade do Set.

**set_type** — Classificação editorial: `REGULAR`, `SPECIAL` ou `PROMO` (este último em processo de adição via migration `122` — ver "Extensão Planejada", abaixo; ADR-015). Sem tabela de referência própria — poucos valores estáveis, sem atributos associados; também não usa `ENUM` nativo do PostgreSQL, cuja evolução é menos flexível que uma restrição `CHECK` (ver `04-domain-model.md`, seção Set — "Classificação Editorial").

**release_order** — Posição do Set dentro da sequência editorial da Expansion. Não é inferida do `code` — `ME2.5` ocupa uma posição inteira na sequência, mesmo com código fracionário. Único dentro da Expansion (`UNIQUE (expansion_id, release_order)`).

**release_date** — Data de lançamento oficial (`DATE`), opcional (`NULL` permitido). Permite cadastrar um Set oficialmente anunciado cuja data ainda não esteja confirmada. Cobre sozinha o caso de uso que originalmente motivou a ideia de um campo `status` (ver `04-domain-model.md`, seção Set — "Status — Decisão").

**base_set_size** — Número de posições da numeração base do Set (ex.: `ME1` = 132).

**total_set_size** — Número total de posições oficiais, incluindo cartas acima da numeração base (ex.: `ME1` = 188). A quantidade de cartas secretas é sempre derivada (`total_set_size - base_set_size`), nunca armazenada.

**created_at / updated_at** — Auditoria mínima (ver STD-001, Seção 4).

## Campos que Não Incluiremos Agora

Aplicando o Princípio da Simplicidade Inicial (AP-004):

- **`logo_url`, `symbol_url`** — as imagens são relevantes, mas antes é preciso decidir onde os arquivos serão armazenados, se será registrada URL pública ou caminho do Storage, como tratar substituição/versionamento, e se logotipos localizados serão vinculados a traduções. Incluir apenas uma URL agora seria uma decisão técnica prematura, e não impede a criação nem a validação dos primeiros Sets. Mesma decisão já aplicada (e corrigida quanto à entidade correta) para a Expansion — ver seção Expansion, acima, "Correção — logo_url pertence ao Set, não à Expansion". Os campos poderão ser adicionados por migration quando a camada visual do catálogo for iniciada.
- **`status`** — o campo `release_date` (nulo ou preenchido) já cobre o caso de uso inicial; sem necessidade concreta adicional até o momento.
- **`secret_set_size`** — sempre derivado (`total_set_size - base_set_size`), nunca armazenado, para evitar inconsistência.

## Regras de Negócio

**Regra 1 — Relacionamento obrigatório.** Todo Set deve pertencer a exatamente uma Expansion.

**Regra 2 — Código único por Expansion.** O código deve ser único dentro da respectiva Expansion (`UNIQUE (expansion_id, code)`), não globalmente.

**Regra 3 — Ordem única por Expansion.** A ordem de lançamento deve ser única dentro da respectiva Expansion (`UNIQUE (expansion_id, release_order)`) e deve ser um número inteiro positivo.

**Regra 4 — Nome obrigatório.** O nome não pode ser vazio.

**Regra 5 — Classificação editorial restrita.** `set_type` deve ser `REGULAR` ou `SPECIAL` (constraint executada); `PROMO` será incluído pela migration `122`, ainda não executada.

**Regra 6 — Quantidades consistentes.** `base_set_size` deve ser positivo; `total_set_size` deve ser maior ou igual a `base_set_size` (não estritamente maior, pois um Set pode não possuir cartas secretas).

**Regra 7 — Exclusão restrita.** Uma Expansion que já possua Sets não pode ser excluída (`ON DELETE RESTRICT`) — sem exclusão em cascata no catálogo editorial.

**Regra 8 — Quantidades de Set promocional (planejada, migration `122`).** Para `set_type = PROMO`, `base_set_size` deve ser igual a `total_set_size` — não representa uma quantidade editorial fechada, mas a quantidade atualmente conhecida de cartas promocionais (ver ADR-015).

## Modelo Físico (PostgreSQL) — Executado

```sql
CREATE TABLE public.card_set (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expansion_id UUID NOT NULL,

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    set_type VARCHAR(20) NOT NULL,
    release_order INTEGER NOT NULL,
    release_date DATE NULL,
    base_set_size INTEGER NOT NULL,
    total_set_size INTEGER NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_card_set_expansion
        FOREIGN KEY (expansion_id)
        REFERENCES public.expansion (id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_set_expansion_code
        UNIQUE (expansion_id, code),

    CONSTRAINT uq_card_set_expansion_release_order
        UNIQUE (expansion_id, release_order),

    CONSTRAINT ck_card_set_code_format
        CHECK (code ~ '^[A-Z0-9][A-Z0-9._-]*$'),

    CONSTRAINT ck_card_set_name_not_blank
        CHECK (btrim(name) <> ''),

    CONSTRAINT ck_card_set_type
        CHECK (set_type IN ('REGULAR', 'SPECIAL')),

    CONSTRAINT ck_card_set_release_order_positive
        CHECK (release_order > 0),

    CONSTRAINT ck_card_set_base_size_positive
        CHECK (base_set_size > 0),

    CONSTRAINT ck_card_set_total_size_valid
        CHECK (total_set_size >= base_set_size)
);

ALTER TABLE public.card_set
    ENABLE ROW LEVEL SECURITY;
```

Query: `120 - Create Card Set Table`. Resultado confirmado: `Success. No rows returned`, RLS habilitado. Nota: `code` usa `VARCHAR(50)` (mais largo que o inicialmente rascunhado) e a constraint de quantidades foi nomeada `ck_card_set_total_size_valid`.

### Trigger de `updated_at`

```sql
CREATE TRIGGER trg_card_set_set_updated_at
BEFORE UPDATE ON public.card_set
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
```

Query: `121 - Create Card Set Trigger`. Resultado confirmado: `Success. No rows returned`. Verificado via `information_schema.triggers` (mesma consulta usada para Game/Expansion): `trigger_name = trg_card_set_set_updated_at`, `event_manipulation = UPDATE`, `action_timing = BEFORE`, `event_object_schema = public`, `event_object_table = card_set`. Reaproveita a função compartilhada `set_updated_at()` (ver seção Game, acima).

### Seed — Versão Final Executada

**Histórico da correção (preservado para rastreabilidade):** uma primeira versão desta Seed continha apenas três Sets (`ME1`, `ME2`, `ME2.5`), com `ME3` deliberadamente excluído por falta de dados validados e todas as `release_date` nulas — essa versão **nunca chegou a ser executada** ("Não devemos executar o seed anterior"). Fabrício então forneceu as folhas oficiais de verificação (PDF) dos cinco primeiros Sets da Expansion `ME`, eliminando o risco de cadastrar estimativas — ver "Fontes Primárias", abaixo. Com os dados confirmados, a Seed foi reescrita para incluir os cinco Sets de uma vez, com nomes e datas oficiais.

**Correção de nomenclatura:** o campo `name` usa o nome oficial no idioma atualmente adotado pelo catálogo para este dado (português, com base nas folhas disponíveis — ver STD-001, Seção 5, "Código Internacional, Nome Localizável"). Para `ME4`, cuja única folha inicialmente disponível estava em inglês, o nome provisório (`Chaos Rising`) foi **substituído** pelo nome oficial em português (`Caos Ascendente`) assim que a folha correspondente foi obtida — nenhuma tradução não-oficial foi inventada nesse intervalo.

```sql
INSERT INTO public.card_set (
    expansion_id, code, name, set_type, release_order,
    release_date, base_set_size, total_set_size
)
SELECT
    expansion.id, seed.code, seed.name, seed.set_type, seed.release_order,
    seed.release_date, seed.base_set_size, seed.total_set_size
FROM public.expansion
INNER JOIN public.game ON game.id = expansion.game_id
CROSS JOIN (
    VALUES
        ('ME1',   'Megaevolução',         'REGULAR', 1, DATE '2025-09-26', 132, 188),
        ('ME2',   'Fogo Fantasmagórico',  'REGULAR', 2, DATE '2025-11-14',  94, 130),
        ('ME2.5', 'Heróis Excelsos',      'SPECIAL', 3, DATE '2026-01-30', 217, 295),
        ('ME3',   'Equilíbrio Perfeito',  'REGULAR', 4, DATE '2026-03-27',  88, 124),
        ('ME4',   'Caos Ascendente',      'REGULAR', 5, DATE '2026-05-22',  86, 122)
) AS seed (code, name, set_type, release_order, release_date, base_set_size, total_set_size)
WHERE game.code = 'POKEMON'
  AND expansion.code = 'ME'
ON CONFLICT (expansion_id, code) DO NOTHING;
```

Query: `820 - Seed Card Set` (versão final). Resultado confirmado: `Success. No rows returned`. Nenhum campo nulo — todas as `release_date` vêm das folhas oficiais.

**Dados consolidados (fonte: folhas oficiais de verificação):**

| Código | Nome | Tipo | Lançamento | Base | Total | Secretas |
|--------|------|------|------------|------|-------|----------|
| ME1 | Megaevolução | REGULAR | 2025-09-26 | 132 | 188 | 56 |
| ME2 | Fogo Fantasmagórico | REGULAR | 2025-11-14 | 94 | 130 | 36 |
| ME2.5 | Heróis Excelsos | SPECIAL | 2026-01-30 | 217 | 295 | 78 |
| ME3 | Equilíbrio Perfeito | REGULAR | 2026-03-27 | 88 | 124 | 36 |
| ME4 | Caos Ascendente | REGULAR | 2026-05-22 | 86 | 122 | 36 |

> **Nota técnica sobre `ON CONFLICT ... DO NOTHING`:** essa cláusula torna a Seed segura para repetição, mas **não atualiza** dados já existentes — se a Seed for corrigida depois de já ter sido executada com sucesso, rodar a versão corrigida não substitui as linhas antigas. Como a primeira versão (com `ME3` ausente e datas nulas) nunca foi executada, não houve esse problema aqui. Mas o cuidado vale para o futuro: corrigir dados já seedados exige um `UPDATE` explícito ou uma nova migration, não apenas reexecutar a Seed (ver STD-001, Seção 10).

### Fontes Primárias

Cadastro validado contra as folhas oficiais de verificação de cada Set, arquivadas em `assets/reference-sources/`: `P10346_ME01_Card_List_PTBR.pdf`, `P10347_ME02_Card_List_PTBR.pdf`, `ME02pt5_Card_List_PTBR.pdf`, `P11218_ME03_Card_List_PTBR.pdf`, `ME04_Card_List_PTBR.pdf` (mesmo padrão já usado para a PDF oficial da ADR-010). A quantidade base foi identificada pelo término da numeração regular e pelo início das cartas de raridade especial; a quantidade total corresponde ao último número da folha oficial.

### Validação — Redigida, Execução Ainda Não Confirmada

Segue o novo padrão de três seções para Queries `9xx - Validate` (ver STD-001, Seção 10): (1) validação estrutural, (2) validação dos dados persistidos, (3) validação das regras de negócio derivadas — como `secret_set_size`, que não existe como coluna na tabela, mas faz parte do domínio.

```sql
-- 1. Validação dos Card Sets (dados persistidos + regra derivada de secretas)
SELECT
    game.code                    AS game_code,
    expansion.code               AS expansion_code,
    card_set.code                AS card_set_code,
    card_set.name                AS card_set_name,
    card_set.set_type,
    card_set.release_order,
    card_set.release_date,
    card_set.base_set_size,
    card_set.total_set_size,
    (card_set.total_set_size - card_set.base_set_size)
        AS secret_set_size,
    card_set.created_at,
    card_set.updated_at
FROM public.card_set
INNER JOIN public.expansion
    ON expansion.id = card_set.expansion_id
INNER JOIN public.game
    ON game.id = expansion.game_id
ORDER BY
    game.code,
    expansion.release_order,
    card_set.release_order;

-- 2. Validação estrutural do trigger
SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    event_object_schema,
    event_object_table
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'card_set'
  AND trigger_name = 'trg_card_set_set_updated_at';
```

Query: `920 - Validate Card Set`. Resultado esperado da primeira consulta: cinco linhas (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`) com `secret_set_size` igual à coluna "Secretas" da tabela de dados consolidados, acima (56/36/78/36/36). Resultado esperado da segunda: uma linha confirmando `trg_card_set_set_updated_at`/`UPDATE`/`BEFORE`/`public`/`card_set`. **A execução e a confirmação real dos resultados ainda não foram registradas nesta documentação** — não assumir que a Seed está correta até essa validação rodar de fato (ver STD-001, Seção 10).

### Extensão Planejada — Card Set Promocional (`PROMO`)

Antes de iniciar a modelagem de Card, foi identificado que as **cartas promocionais (Black Star Promos)** — ligadas diretamente a uma Expansion, sem código/nome oficial fixo, sem posição própria na sequência de Sets e com quantidade que cresce ao longo do tempo — não se encaixam nas regras atuais de `card_set`, mas também não justificam uma entidade separada. Decisão completa em **ADR-015**; resumo aplicado aqui:

`card_set` ganha um terceiro `set_type`: `PROMO`, preenchido por uma **convenção fixa** (não por campos nulos):

| Campo | Convenção para `PROMO` | Exemplo (`ME`) |
|-------|--------------------------|-----------------|
| `code` | código da Expansion + `0` | `ME0` |
| `name` | código da Expansion + `Black Star Promos` | `ME Black Star Promos` |
| `release_order` | sempre `1` (primeiro Set da Expansion) | `1` |
| `release_date` | mesma data do primeiro Set regular/especial da Expansion | `2025-09-26` (mesma de `ME1`) |
| `base_set_size` / `total_set_size` | iguais entre si — quantidade atualmente conhecida, não fechada | a definir na Seed |

Como todos os valores são determináveis a partir da Expansion, **nenhuma coluna existente precisa se tornar `NULL`** — uma proposta inicial nesse sentido foi avaliada e descartada (ver ADR-015, "Alternatives Considered"). A única mudança estrutural é ampliar a constraint de `set_type` e adicionar a Regra 8 (`PROMO → base_set_size = total_set_size`).

**Deslocamento de `release_order` dos Sets existentes:** como o Set promocional passa a ocupar sempre a posição `1`, os cinco Sets já cadastrados precisam ser deslocados (`+1`). Isso não pode ser feito em uma única `UPDATE` direta, pois violaria a constraint `UNIQUE (expansion_id, release_order)` durante a operação — a técnica é um deslocamento em duas etapas, passando por uma faixa temporária fora do intervalo em uso:

```text
1, 2, 3, 4, 5   →   101, 102, 103, 104, 105   →   2, 3, 4, 5, 6
```

**Unicidade da série promocional:** `UNIQUE (expansion_id, code)` sozinha não impede duas séries promocionais na mesma Expansion (o PostgreSQL permite múltiplos `NULL` em uma `UNIQUE` comum, mas aqui `code` não é nulo — é sempre derivado, então essa unicidade já cobre o caso). Ainda assim, para reforçar a regra de negócio "no máximo uma série promocional por Expansion" de forma independente do valor de `code`, um índice único parcial é a forma recomendada: `CREATE UNIQUE INDEX ... ON public.card_set (expansion_id) WHERE set_type = 'PROMO'`.

**Migration planejada:** `122 - Adapt Card Set for Promo Series`, com quatro mudanças: (1) incluir `PROMO` na constraint de `set_type`; (2) deslocar o `release_order` dos cinco Sets existentes; (3) preservar a unicidade de `release_order` durante o deslocamento (técnica de duas etapas, acima); (4) adicionar a Regra 8 (quantidades iguais para `PROMO`). **Ainda não executada** — é um pré-requisito antes de criar a Query `130 - Create Card Table`.

## Modelo Consolidado

```text
Card Set

PK  id               UUID
FK  expansion_id     UUID

    code             VARCHAR(50)
    name             VARCHAR(150)
    set_type         VARCHAR(20)
    release_order    INTEGER
    release_date     DATE
    base_set_size    INTEGER
    total_set_size   INTEGER

    created_at       TIMESTAMPTZ
    updated_at       TIMESTAMPTZ
```

## Queries Associadas

```text
120 - Create Card Set Table
121 - Create Card Set Trigger
122 - Adapt Card Set for Promo Series   (planejada)
820 - Seed Card Set
920 - Validate Card Set                 (redigida, execução não confirmada)
```

Seguindo a regra de deslocamento fixo (STD-001, Seção 10: Seed = criação + 700, Validate = criação + 800). `122` é uma migration de ajuste dentro do próprio bloco 100–199 de Card Set, não uma nova entidade.

## Definition of Done

- [x] modelo lógico definido, por grupo;
- [x] atributos e campos adiados definidos;
- [x] regras de negócio definidas (incluindo a Regra 8, planejada);
- [x] tabela `card_set` criada no Supabase (`120`);
- [x] RLS habilitado;
- [x] trigger criado (`121`) e verificado via `information_schema.triggers`;
- [x] seed executado (`820` — ME1, ME2, ME2.5, ME3, ME4, todos com dados validados contra folhas oficiais, sem campos nulos);
- [x] Query de validação redigida, seguindo o novo padrão de três seções;
- [ ] validação executada e confirmada (`920`) — **pendência aberta**;
- [ ] migration `122` executada (suporte a `PROMO`, deslocamento de `release_order`) — **pendência aberta, pré-requisito antes de `Card`**.

---

# Card (Carta)

*Documentação pendente.*

---

# Card Translation (Tradução da Carta)

*Documentação pendente.*

---

# Finish (Acabamento) / Card Finish (Acabamento da Carta)

*Documentação pendente.*

---

# Collection Item (Item da Coleção)

*Documentação pendente.*

---

# Collection (Coleção) / Collection Entry (Entrada da Coleção)

*Documentação pendente.*

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 0.1 | Estrutura inicial do documento. Modelagem lógica e física completa da entidade Game (Jogo), incluindo DDL, trigger de `updated_at`, testes mínimos de integridade e Definition of Done. Adicionados stubs para as demais entidades já definidas em `04-domain-model.md`, na ordem prevista de implementação. |
| 0.2 | Adicionado o requisito de Row Level Security (RLS) ao modelo físico e à Definition of Done da entidade Game, refletindo o padrão agora registrado em STD-001, Seção 9. |
| 0.3 | Adicionada nota explicando que o banco físico já possui as 17 tabelas originais com carga inicial de dados, construídas antes desta fase de consolidação documental — a documentação das entidades além de Game será majoritariamente retroativa, não uma criação do zero. |
| 0.4 | Refinado o Roteiro por Entidade: modelo lógico agora organizado por grupo (Identidade/Descrição/Relacionamento/Ordenação/Auditoria); referência ao Padrão Oficial de Queries SQL (STD-001, Seção 10). Adicionadas as Queries associadas à entidade Game (000/001/100/800/900). Adicionado o modelo lógico parcial da entidade Expansion (status "Em elaboração"); regras de negócio, modelo físico e testes previstos para o próximo ciclo. |
| 0.5 | Adicionada a verificação do trigger de Game via `information_schema.triggers`; Queries associadas de Game atualizadas com `101 - Create Game trigger` (pacote tecnicamente completo). Completada a entidade Expansion: atributos, campos adiados, regras de negócio e o DDL efetivamente executado (`110 - Create Expansion table`, com RLS). Sinalizada divergência não resolvida entre o modelo conceitual acordado (inclui `logo_url`) e o DDL executado (não inclui) — não resolvida unilateralmente, aguardando confirmação de Fabrício. |
| 0.6 | Confirmado por Fabrício: a ausência de `logo_url` no DDL executado foi um descuido, não uma simplificação deliberada — a coluna é importante para o projeto. Atualizado o status da entidade Expansion e registrada a ação pendente (migration `ALTER TABLE ... ADD COLUMN logo_url`) para a retomada da implementação. |
| 0.7 | Corrigida a pendência de `logo_url`: o valor deve ser importado automaticamente via API e armazenado no Supabase Storage, seguindo o mesmo padrão de imagens de Card — não uma coluna de preenchimento manual. Ação pendente agora depende de decisão prévia sobre a estrutura do pipeline de ativos visuais (ver `06-pipeline-importacao.md`). |
| 0.8 | Concluído o pacote técnico da entidade Expansion: trigger (`111`), Seed real (`810` — ME/Mega Evolution/release_order=1, com nota sobre revisão futura da ordenação) e Validação (`910`), todos confirmados. Adicionadas as Queries Associadas completas. Adicionada nota sobre o início (não conclusão) da discussão da entidade Set — consistente com a prévia já registrada em `04-domain-model.md`. |
| 0.9 | **Correção:** `logo_url` não é uma pendência da Expansion — pertence ao Set. A seção "Pendência Confirmada — logo_url" foi reescrita como "Correção — logo_url pertence ao Set, não à Expansion", com o histórico preservado. Status da Expansion atualizado para "sem pendências". Completada a entidade Set: modelo lógico por grupo, atributos, campos adiados (`logo_url`/`symbol_url`/`status`/`secret_set_size`), 7 regras de negócio, DDL completo de `card_set` (aprovado, execução ainda pendente — Query `120`), trigger/seed/validação planejados (`121`/`820`/`920`), modelo consolidado e Definition of Done (parcial — aguardando execução no Supabase). |
| 0.10 | Set executado no Supabase: tabela (`120`, com `code VARCHAR(50)` e constraint `ck_card_set_total_size_valid`, ajustados frente ao modelo aprovado), trigger (`121`, verificado via `information_schema.triggers`) e seed (`820` — ME1/ME2/ME2.5 com dados reais, `release_date` nula, `ME3` deliberadamente adiado por falta de validação). Query `920 - Validate Card Set` ainda não executada — sinalizada como pendência aberta da entidade. Definition of Done atualizada (7 de 8 itens concluídos). |
| 0.11 | **Marco: primeiro núcleo do catálogo editorial concluído.** A versão preliminar da Seed `820` (três Sets, datas nulas) nunca foi executada — substituída pela versão final, com os cinco Sets da Expansion `ME` (`ME1`–`ME4`), nomes em português e datas de lançamento, todos validados contra folhas oficiais de verificação (arquivadas em `assets/reference-sources/`). Adicionada tabela de dados consolidados, nota sobre a correção de nomenclatura (nome provisório em inglês de `ME4` substituído pelo nome oficial em português) e alerta sobre `ON CONFLICT ... DO NOTHING` não atualizar dados já gravados. `920 - Validate Card Set` continua pendente. |
| 0.12 | Identificado desvio de disciplina (avançar para Card antes de fechar o pacote de Card Set) — corrigido antes de prosseguir. Adicionada Query `920 - Validate Card Set` completa, seguindo o novo padrão de três seções (estrutural, dados persistidos, regras derivadas); execução ainda não confirmada. Adicionada a seção "Extensão Planejada — Card Set Promocional (`PROMO`)": convenção fixa de preenchimento para a série Black Star Promos, técnica de deslocamento em duas etapas para `release_order`, e a migration planejada `122 - Adapt Card Set for Promo Series` (ver ADR-015). Nova Regra de Negócio 8 (quantidades iguais para `PROMO`). Definition of Done ampliada com os dois itens pendentes antes de iniciar a entidade Card. |
