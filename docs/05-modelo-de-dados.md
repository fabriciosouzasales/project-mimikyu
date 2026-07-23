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

> **Nota:** todo SQL apresentado neste documento como "executado" também existe como arquivo `.sql` versionado em `database/` (fora de `docs/`), organizado por faixa de numeração — ver `database/README.md`. Este documento continua sendo a fonte de verdade narrativa (o porquê e o contexto de cada Query); `database/` é o registro literal e executável.

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

Status: **Pacote técnico concluído.** Tabela, trigger, suporte a Sets promocionais, seed e validação executados e confirmados. Tabela física: `card_set` (ver nota em `04-domain-model.md` e STD-001, Seção 2 — `SET` é palavra reservada do SQL). Seguindo o novo **Princípio da Fonte Canônica** (STD-001, Seção 10), as Queries `120 - Create Card Set Table` e `820 - Seed Card Set` foram consolidadas para `Versão 2.0` (Status `CANÔNICA`), já nascendo com suporte nativo a `PROMO` — as Queries `122` e `821` (que originalmente introduziram esse suporte em um banco já existente) foram reclassificadas como `MIGRATION` (históricas), preservadas mas fora do fluxo de instalação limpa. **Único item aberto:** confirmar se o índice único parcial `uq_card_set_expansion_promo` (novo na versão canônica de `120`) já existe no banco físico atual — ver "Modelo Físico — Versão Canônica", abaixo.

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

**set_type** — Classificação editorial: `REGULAR`, `SPECIAL` ou `PROMO` (este último adicionado via migration `122` — ver "Card Set Promocional", abaixo; ADR-015). Sem tabela de referência própria — poucos valores estáveis, sem atributos associados; também não usa `ENUM` nativo do PostgreSQL, cuja evolução é menos flexível que uma restrição `CHECK` (ver `04-domain-model.md`, seção Set — "Classificação Editorial").

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

**Regra 5 — Classificação editorial restrita.** `set_type` deve ser `REGULAR`, `SPECIAL` ou `PROMO` (constraint ampliada pela migration `122`, executada).

**Regra 6 — Quantidades consistentes.** `base_set_size` deve ser positivo; `total_set_size` deve ser maior ou igual a `base_set_size` (não estritamente maior, pois um Set pode não possuir cartas secretas).

**Regra 7 — Exclusão restrita.** Uma Expansion que já possua Sets não pode ser excluída (`ON DELETE RESTRICT`) — sem exclusão em cascata no catálogo editorial.

**Regra 8 — Quantidades de Set promocional.** Para `set_type = PROMO`, `base_set_size` deve ser igual a `total_set_size` (constraint `ck_card_set_promo_size`, executada pela migration `122`) — não representa uma quantidade editorial fechada, mas a quantidade atualmente conhecida de cartas promocionais (ver ADR-015).

## Modelo Físico (PostgreSQL) — Versão 1.0, Executada Originalmente (histórico)

*Esta é a Query como foi executada pela primeira vez (Status `MIGRATION` retroativo — superada pela Versão Canônica 2.0, abaixo, mas preservada aqui para rastreabilidade, seguindo o Princípio da Fonte Canônica de STD-001, Seção 10).*

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

Query: `120 - Create Card Set Table` (v1.0). Resultado confirmado: `Success. No rows returned`, RLS habilitado. Nota: `code` usa `VARCHAR(50)` (mais largo que o inicialmente rascunhado) e a constraint de quantidades foi nomeada `ck_card_set_total_size_valid`.

## Modelo Físico — Versão Canônica (2.0)

Status `CANÔNICA` (STD-001, Seção 10 — Princípio da Fonte Canônica): esta é a versão que uma **instalação nova** deve executar — já nasce com suporte nativo a `PROMO`, incorporando o que antes exigia a migration `122` separada, **e adiciona o índice único parcial que a versão 1.0 e a migration `122` não incluíam** (a divergência sinalizada anteriormente em ADR-015 e nesta seção):

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
        CHECK (set_type IN ('REGULAR', 'SPECIAL', 'PROMO')),
    CONSTRAINT ck_card_set_release_order_positive
        CHECK (release_order > 0),
    CONSTRAINT ck_card_set_base_size_positive
        CHECK (base_set_size > 0),
    CONSTRAINT ck_card_set_total_size_valid
        CHECK (total_set_size >= base_set_size),
    CONSTRAINT ck_card_set_promo_size
        CHECK (
            set_type <> 'PROMO'
            OR base_set_size = total_set_size
        )
);

-- Garante no máximo um Card Set promocional por Expansion
CREATE UNIQUE INDEX uq_card_set_expansion_promo
    ON public.card_set (expansion_id)
    WHERE set_type = 'PROMO';

ALTER TABLE public.card_set
ENABLE ROW LEVEL SECURITY;
```

Query: `120 - Create Card Set Table` (v2.0, `CANÔNICA`). Representa o estado estrutural definitivo para novas instalações — a Query `122` (histórica) não precisa ser executada em uma instalação nova.

> **Item aberto — não presumir resolvido:** esta versão canônica foi escrita para o **repositório** (arquivo/documentação), não executada como uma nova alteração contra o banco físico atual — o banco atual foi construído pelo caminho antigo (`120` v1.0 + migration `122`), que **não incluía** o índice `uq_card_set_expansion_promo`. Ou seja, é preciso **confirmar separadamente** se esse índice já existe no Supabase real; se não existir, nada no banco atual impede hoje uma segunda linha `PROMO` na mesma Expansion (mesma divergência já registrada em ADR-015, agora resolvida apenas na definição canônica, não necessariamente na instância física).

### Trigger de `updated_at`

```sql
CREATE TRIGGER trg_card_set_set_updated_at
BEFORE UPDATE ON public.card_set
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
```

Query: `121 - Create Card Set Trigger`. Resultado confirmado: `Success. No rows returned`. Verificado via `information_schema.triggers` (mesma consulta usada para Game/Expansion): `trigger_name = trg_card_set_set_updated_at`, `event_manipulation = UPDATE`, `action_timing = BEFORE`, `event_object_schema = public`, `event_object_table = card_set`. Reaproveita a função compartilhada `set_updated_at()` (ver seção Game, acima).

### Seed — Versão 1.0, Executada Originalmente (histórico)

*Esta é a Seed como foi executada originalmente — ainda sem o Set promocional `ME0` (incorporado depois, separadamente, pela Query `821`) e usando `ON CONFLICT ... DO NOTHING` (Status `MIGRATION` retroativo — superada pela Versão Canônica 2.0, abaixo, mas preservada aqui para rastreabilidade, seguindo o Princípio da Fonte Canônica de STD-001, Seção 10).*

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

### Seed — Versão Canônica (2.0)

Status `CANÔNICA` (STD-001, Seção 10 — Princípio da Fonte Canônica): passa a representar o **estado completo e atual da Expansion `ME`**, incorporando o Set promocional `ME0` (antes inserido separadamente pela Query `821`) e trocando `ON CONFLICT ... DO NOTHING` por `ON CONFLICT ... DO UPDATE` — uma Seed que não apenas evita duplicidade, mas também corrige registros existentes caso algum dado oficial seja atualizado (ver "Pendência — Reescrita da Query 820, RESOLVIDA", abaixo).

```sql
/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 820 - Seed Card Set
Versão......: 2.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Status......: CANÔNICA
Descrição...:
Insere e mantém atualizados os Card Sets iniciais da Expansion Mega Evolution,
incluindo o Set promocional Black Star Promos.
Os dados dos Sets regulares e especiais foram definidos com base nas folhas
oficiais de verificação e nas datas de lançamento validadas.
Card Sets contemplados:
- ME0   - ME Black Star Promos
- ME1   - Megaevolução
- ME2   - Fogo Fantasmagórico
- ME2.5 - Heróis Excelsos
- ME3   - Equilíbrio Perfeito
- ME4   - Caos Ascendente
Regras de Negócio:
- Os Card Sets devem ser vinculados ao Game POKEMON e à Expansion ME.
- Os UUIDs das entidades relacionadas não devem ser informados diretamente.
- A execução deve ser idempotente.
- Uma nova execução não pode gerar registros duplicados.
- Registros existentes devem ser atualizados conforme os dados definidos
  nesta Query.
- O Set promocional deve ser o primeiro Card Set da Expansion.
- O código do Set promocional deve ser formado pelo código da Expansion
  seguido de 0.
- O nome do Set promocional deve ser formado pelo código da Expansion
  seguido de " Black Star Promos".
- A data de lançamento do Set promocional deve ser igual à data de lançamento
  do primeiro Set não promocional da Expansion.
- A quantidade base do Set promocional deve ser igual à quantidade total.
- A quantidade do Set promocional representa a quantidade de cartas conhecidas
  no momento da atualização do catálogo.
- As quantidades dos Sets regulares e especiais devem corresponder às folhas
  oficiais de verificação.
- A quantidade de cartas secretas não é armazenada diretamente.
- A quantidade de cartas secretas é derivada da diferença entre
  total_set_size e base_set_size.
- ME2.5 é um Set especial.
- ME0 é um Set promocional.
- Os demais Sets cadastrados são regulares.
Pré-requisitos:
- A Query 122 - Adapt Card Set for Promo deve ter sido executada.
- O Game POKEMON deve existir.
- A Expansion ME deve existir.
===============================================================================
*/
INSERT INTO public.card_set (
    expansion_id,
    code,
    name,
    set_type,
    release_order,
    release_date,
    base_set_size,
    total_set_size
)
SELECT
    expansion.id,
    seed.code,
    seed.name,
    seed.set_type,
    seed.release_order,
    seed.release_date,
    seed.base_set_size,
    seed.total_set_size
FROM public.expansion
INNER JOIN public.game
    ON game.id = expansion.game_id
CROSS JOIN (
    VALUES
        (
            'ME0',
            'ME Black Star Promos',
            'PROMO',
            1,
            DATE '2025-09-26',
            89,
            89
        ),
        (
            'ME1',
            'Megaevolução',
            'REGULAR',
            2,
            DATE '2025-09-26',
            132,
            188
        ),
        (
            'ME2',
            'Fogo Fantasmagórico',
            'REGULAR',
            3,
            DATE '2025-11-14',
            94,
            130
        ),
        (
            'ME2.5',
            'Heróis Excelsos',
            'SPECIAL',
            4,
            DATE '2026-01-30',
            217,
            295
        ),
        (
            'ME3',
            'Equilíbrio Perfeito',
            'REGULAR',
            5,
            DATE '2026-03-27',
            88,
            124
        ),
        (
            'ME4',
            'Caos Ascendente',
            'REGULAR',
            6,
            DATE '2026-05-22',
            86,
            122
        )
) AS seed (
    code,
    name,
    set_type,
    release_order,
    release_date,
    base_set_size,
    total_set_size
)
WHERE game.code = 'POKEMON'
  AND expansion.code = 'ME'
ON CONFLICT (expansion_id, code)
DO UPDATE SET
    name            = EXCLUDED.name,
    set_type        = EXCLUDED.set_type,
    release_order   = EXCLUDED.release_order,
    release_date    = EXCLUDED.release_date,
    base_set_size   = EXCLUDED.base_set_size,
    total_set_size  = EXCLUDED.total_set_size;
```

Query: `820 - Seed Card Set` (v2.0, `CANÔNICA`). Representa o estado completo e atual da Expansion `ME` em uma única Query — a Query `821` (histórica) não precisa ser executada em uma instalação nova. O `release_order` já nasce na ordem final (`ME0`=1 … `ME4`=6), sem precisar do deslocamento em duas etapas que a migration `122` exigiu contra dados já existentes.

> **Mesmo item aberto da versão canônica de `120`:** esta reescrita também é uma atualização de repositório/documentação — não foi (e não precisa ser) reexecutada contra o banco atual, já que os dados de `ME0`–`ME4` já estão persistidos (via `820` v1.0 + `821`). Serve como definição para instalações novas e como registro do formato `DO UPDATE` a partir de agora.

### Fontes Primárias

Cadastro validado contra as folhas oficiais de verificação de cada Set, arquivadas em `assets/reference-sources/`: `P10346_ME01_Card_List_PTBR.pdf`, `P10347_ME02_Card_List_PTBR.pdf`, `ME02pt5_Card_List_PTBR.pdf`, `P11218_ME03_Card_List_PTBR.pdf`, `ME04_Card_List_PTBR.pdf` (mesmo padrão já usado para a PDF oficial da ADR-010). A quantidade base foi identificada pelo término da numeração regular e pelo início das cartas de raridade especial; a quantidade total corresponde ao último número da folha oficial.

### Validação — Executada e Confirmada (versão 2.0)

A primeira versão de `920` (duas seções) foi substituída, antes de ser considerada definitiva, por uma versão mais completa — a Query passou a incluir também o Set promocional e uma bateria de verificações de inconsistência. Segue um padrão de cinco categorias (ver STD-001, Seção 10, revisado): (1) dados persistidos, (2) regras de negócio derivadas, (3) inconsistências, (4) constraints, (5) trigger.

```sql
-- 1. Validação dos dados persistidos
SELECT
    game.code AS game_code, expansion.code AS expansion_code,
    card_set.code AS card_set_code, card_set.name AS card_set_name,
    card_set.set_type, card_set.release_order, card_set.release_date,
    card_set.base_set_size, card_set.total_set_size,
    card_set.total_set_size - card_set.base_set_size AS secret_set_size,
    card_set.created_at, card_set.updated_at
FROM public.card_set
INNER JOIN public.expansion ON expansion.id = card_set.expansion_id
INNER JOIN public.game ON game.id = expansion.game_id
WHERE game.code = 'POKEMON' AND expansion.code = 'ME'
ORDER BY card_set.release_order;

-- 2. Resumo da Expansion (contagem por tipo)
SELECT
    game.code AS game_code, expansion.code AS expansion_code,
    COUNT(card_set.id) AS card_set_count,
    COUNT(*) FILTER (WHERE card_set.set_type = 'PROMO') AS promo_set_count,
    COUNT(*) FILTER (WHERE card_set.set_type = 'REGULAR') AS regular_set_count,
    COUNT(*) FILTER (WHERE card_set.set_type = 'SPECIAL') AS special_set_count,
    MIN(card_set.release_order) AS first_release_order,
    MAX(card_set.release_order) AS last_release_order
FROM public.card_set
INNER JOIN public.expansion ON expansion.id = card_set.expansion_id
INNER JOIN public.game ON game.id = expansion.game_id
WHERE game.code = 'POKEMON' AND expansion.code = 'ME'
GROUP BY game.code, expansion.code;

-- 3. Sequência editorial sem lacunas (esperado: zero linhas)
WITH ordered_card_sets AS (
    SELECT card_set.id, card_set.code, card_set.release_order,
        ROW_NUMBER() OVER (PARTITION BY card_set.expansion_id ORDER BY card_set.release_order) AS expected_release_order
    FROM public.card_set
    INNER JOIN public.expansion ON expansion.id = card_set.expansion_id
    INNER JOIN public.game ON game.id = expansion.game_id
    WHERE game.code = 'POKEMON' AND expansion.code = 'ME'
)
SELECT code, release_order, expected_release_order
FROM ordered_card_sets
WHERE release_order <> expected_release_order;

-- 4. Regras do Set promocional: code/name/ordem/quantidades (esperado: zero linhas)
SELECT card_set.code, card_set.name, card_set.set_type
FROM public.card_set
INNER JOIN public.expansion ON expansion.id = card_set.expansion_id
WHERE card_set.set_type = 'PROMO'
  AND (card_set.code <> expansion.code || '0'
       OR card_set.name <> expansion.code || ' Black Star Promos'
       OR card_set.release_order <> 1
       OR card_set.base_set_size <> card_set.total_set_size);

-- 5. Data do Set promocional = menor data entre os Sets não promocionais (esperado: zero linhas)
WITH first_non_promo_release AS (
    SELECT expansion_id, MIN(release_date) AS first_release_date
    FROM public.card_set
    WHERE set_type IN ('REGULAR', 'SPECIAL')
    GROUP BY expansion_id
)
SELECT expansion.code, promo.code, promo.release_date, first_release.first_release_date
FROM public.card_set AS promo
INNER JOIN public.expansion ON expansion.id = promo.expansion_id
INNER JOIN first_non_promo_release AS first_release ON first_release.expansion_id = promo.expansion_id
WHERE promo.set_type = 'PROMO'
  AND promo.release_date IS DISTINCT FROM first_release.first_release_date;

-- 6. No máximo um Set promocional por Expansion (esperado: zero linhas — sem constraint de banco, ver divergência acima)
SELECT expansion.code, COUNT(card_set.id) AS promo_set_count
FROM public.card_set
INNER JOIN public.expansion ON expansion.id = card_set.expansion_id
WHERE card_set.set_type = 'PROMO'
GROUP BY expansion.id, expansion.code
HAVING COUNT(card_set.id) > 1;

-- 7. Quantidades gerais válidas (esperado: zero linhas)
SELECT card_set.code, card_set.base_set_size, card_set.total_set_size
FROM public.card_set
WHERE card_set.base_set_size <= 0 OR card_set.total_set_size < card_set.base_set_size;

-- 8. Tipos permitidos (esperado: zero linhas)
SELECT card_set.code, card_set.set_type
FROM public.card_set
WHERE card_set.set_type NOT IN ('REGULAR', 'SPECIAL', 'PROMO');

-- 9. Constraints da tabela
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public' AND table_name = 'card_set'
ORDER BY constraint_type, constraint_name;

-- 10. Definição das CHECK constraints
SELECT constraint_name, check_clause
FROM information_schema.check_constraints
WHERE constraint_schema = 'public'
  AND constraint_name IN (
      SELECT constraint_name FROM information_schema.table_constraints
      WHERE table_schema = 'public' AND table_name = 'card_set' AND constraint_type = 'CHECK'
  );

-- 11. Trigger de updated_at
SELECT trigger_name, event_manipulation, action_timing, event_object_schema, event_object_table
FROM information_schema.triggers
WHERE event_object_schema = 'public' AND event_object_table = 'card_set';
```

Query: `920 - Validate Card Set` (versão 2.0). **Resultado confirmado por Fabrício ("Tudo ok").** A consulta principal (seção 1) retornou os seis Card Sets da Expansion `ME` com `secret_set_size` correto (`ME0`=0, `ME1`=56, `ME2`=36, `ME2.5`=78, `ME3`=36, `ME4`=36); as seções 3 a 8 (inconsistências e tipos) retornaram zero linhas; o trigger `trg_card_set_set_updated_at` confirmado ativo (`BEFORE UPDATE`). **Com esse resultado, o pacote técnico da entidade Card Set está concluído.**

### Pendência — Reescrita da Query `820` (RESOLVIDA)

**Resolvida:** a Query `820` foi reescrita como `Versão 2.0` (Status `CANÔNICA`), incluindo `ME0` e usando `ON CONFLICT ... DO UPDATE` — ver "Seed — Versão Canônica (2.0)", acima. O texto original desta pendência é preservado abaixo para rastreabilidade da decisão.

Imediatamente após confirmar a validação, Fabrício identificou uma inconsistência de processo: a Query `820 - Seed Card Set` (documentada acima, seção "Seed — Versão Final Executada") ainda reflete apenas os cinco Sets regulares/especiais — o Set promocional `ME0` foi inserido por uma Query separada (`821`). **Decisão tomada (ainda não convertida em SQL executado):** `820` deve passar a representar o **estado completo e atual da Expansion `ME`**, incluindo o Set promocional, para que uma reconstrução do banco do zero não dependa de executar `821` separadamente. `821` passa a ser mantida apenas como registro histórico de migrations já executadas, deixando de fazer parte do fluxo principal de instalação.

Também foi recomendado evoluir a cláusula da Seed de `ON CONFLICT ... DO NOTHING` para `ON CONFLICT ... DO UPDATE`, para que reexecutar `820` não apenas evite duplicidade, mas também corrija registros existentes caso alguma informação oficial seja atualizada — uma exceção deliberada à orientação geral de idempotência via `DO NOTHING` (ver STD-001, Seção 10), aplicável a Seeds que representam o **estado atual e reaplicável** de uma entidade (como o catálogo de Card Sets de uma Expansion), e não apenas uma carga inicial única.

**O SQL reescrito de `820` ainda não foi apresentado nem executado** — fica como o único item aberto da entidade Set/Card Set antes de iniciar formalmente a modelagem de Card.

### Card Set Promocional (`PROMO`) — Executado

Antes de iniciar a modelagem de Card, foi identificado que as **cartas promocionais (Black Star Promos)** — ligadas diretamente a uma Expansion, sem código/nome oficial fixo, sem posição própria na sequência de Sets e com quantidade que cresce ao longo do tempo — não se encaixam nas regras originais de `card_set`, mas também não justificam uma entidade separada. Decisão completa em **ADR-015**; resumo aplicado aqui, já executado no Supabase:

`card_set` ganhou um terceiro `set_type`: `PROMO`, preenchido por uma **convenção fixa** (não por campos nulos):

| Campo | Convenção para `PROMO` | Valor real (`ME0`) |
|-------|--------------------------|-----------------|
| `code` | código da Expansion + `0` | `ME0` |
| `name` | código da Expansion + `Black Star Promos` | `ME Black Star Promos` |
| `release_order` | sempre `1` (primeiro Set da Expansion) | `1` |
| `release_date` | mesma data do primeiro Set regular/especial da Expansion | `2025-09-26` (mesma de `ME1`) |
| `base_set_size` / `total_set_size` | iguais entre si — quantidade atualmente conhecida, não fechada | `89` / `89` |

Como todos os valores são determináveis a partir da Expansion, nenhuma coluna existente precisou se tornar `NULL` — a proposta inicial nesse sentido foi avaliada e descartada (ver ADR-015, "Alternatives Considered").

**Migration executada:**

```sql
BEGIN;

-- 1. Remove a constraint atual de tipo
ALTER TABLE public.card_set
DROP CONSTRAINT ck_card_set_type;

-- 2. Cria a nova constraint incluindo PROMO
ALTER TABLE public.card_set
ADD CONSTRAINT ck_card_set_type
CHECK (set_type IN ('REGULAR', 'SPECIAL', 'PROMO'));

-- 3. Desloca temporariamente as ordens atuais para evitar conflito
UPDATE public.card_set
SET release_order = release_order + 100
WHERE expansion_id = (
    SELECT expansion.id
    FROM public.expansion
    INNER JOIN public.game ON game.id = expansion.game_id
    WHERE game.code = 'POKEMON' AND expansion.code = 'ME'
);

-- 4. Define as novas ordens editoriais
UPDATE public.card_set
SET release_order = CASE code
    WHEN 'ME1'   THEN 2
    WHEN 'ME2'   THEN 3
    WHEN 'ME2.5' THEN 4
    WHEN 'ME3'   THEN 5
    WHEN 'ME4'   THEN 6
END
WHERE expansion_id = (
    SELECT expansion.id
    FROM public.expansion
    INNER JOIN public.game ON game.id = expansion.game_id
    WHERE game.code = 'POKEMON' AND expansion.code = 'ME'
)
AND code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4');

-- 5. Garante igualdade entre base e total para Sets promocionais
ALTER TABLE public.card_set
ADD CONSTRAINT ck_card_set_promo_size
CHECK (set_type <> 'PROMO' OR base_set_size = total_set_size);

COMMIT;
```

Query: `122 - Adapt Card Set for Promo`. Resultado confirmado: `Success. No rows returned`. Executada dentro de uma transação explícita (`BEGIN`/`COMMIT`) — recomendação permanente para migrations que alteram constraints e dados existentes juntas (ver STD-001, Seção 10). O deslocamento do `release_order` usa a técnica de duas etapas descrita anteriormente (`1,2,3,4,5 → 101,102,103,104,105 → 2,3,4,5,6`), evitando violar `UNIQUE (expansion_id, release_order)` durante a operação.

> **Status: `MIGRATION` (reclassificação retroativa, STD-001 Seção 10 — Princípio da Fonte Canônica).** Esta Query alterou um banco que já possuía a tabela `card_set` (via `120` v1.0) — não é mais necessária em uma instalação nova, já que a Query canônica `120` v2.0 nasce com suporte nativo a `PROMO`. Preservada aqui apenas como registro histórico de como o suporte a `PROMO` foi de fato introduzido no banco atual.

**Seed do Card Set promocional:**

```sql
INSERT INTO public.card_set (
    expansion_id, code, name, set_type, release_order,
    release_date, base_set_size, total_set_size
)
SELECT
    expansion.id, 'ME0', 'ME Black Star Promos', 'PROMO', 1,
    DATE '2025-09-26', 89, 89
FROM public.expansion
INNER JOIN public.game ON game.id = expansion.game_id
WHERE game.code = 'POKEMON' AND expansion.code = 'ME'
ON CONFLICT (expansion_id, code) DO NOTHING;
```

Query: `821 - Seed Promo Card Set`. Resultado confirmado: `Success. No rows returned`. Quantidade real informada por Fabrício ("Atualmente são 89 cartas promos em ME").

> **Status: `MIGRATION` (reclassificação retroativa, STD-001 Seção 10 — Princípio da Fonte Canônica).** Esta Query inseriu `ME0` separadamente, em um banco onde os demais Sets já existiam — não é mais necessária em uma instalação nova, já que a Query canônica `820` v2.0 inclui `ME0` junto com os demais Sets em um único snapshot. Preservada aqui apenas como registro histórico.

**Estado final da Expansion `ME` após `122` + `821`:**

| Ordem | Código | Nome | Tipo | Lançamento | Base | Total |
|-------|--------|------|------|------------|------|-------|
| 1 | ME0 | ME Black Star Promos | PROMO | 2025-09-26 | 89 | 89 |
| 2 | ME1 | Megaevolução | REGULAR | 2025-09-26 | 132 | 188 |
| 3 | ME2 | Fogo Fantasmagórico | REGULAR | 2025-11-14 | 94 | 130 |
| 4 | ME2.5 | Heróis Excelsos | SPECIAL | 2026-01-30 | 217 | 295 |
| 5 | ME3 | Equilíbrio Perfeito | REGULAR | 2026-03-27 | 88 | 124 |
| 6 | ME4 | Caos Ascendente | REGULAR | 2026-05-22 | 86 | 122 |

> **Divergência sinalizada — agora corrigida na definição canônica, ainda não confirmada no banco físico:** ADR-015 recomendava um índice único parcial (`CREATE UNIQUE INDEX ... ON public.card_set (expansion_id) WHERE set_type = 'PROMO'`) para impedir, ao nível do banco, mais de uma série promocional por Expansion. A migration `122` efetivamente executada **não incluiu esse índice**. A Query canônica `120` v2.0 (ver "Modelo Físico — Versão Canônica (2.0)", acima) já inclui o índice para qualquer instalação nova. **Mas isso não significa que o índice já exista no banco físico atual** — o banco atual foi construído pelo caminho antigo (`120` v1.0 + `122`), e a atualização de `120` para v2.0 foi feita no repositório/documentação, não como uma nova execução contra o Supabase. Enquanto essa confirmação não for feita, a regra continua sendo verificada apenas pela Query de validação (`920`, seção 6, abaixo), não impedida na escrita — nada no banco impede hoje que uma segunda linha `PROMO` seja inserida por engano na mesma Expansion.

**Pendência de nomenclatura do `card`:** esta ADR/migration não define regras específicas sobre a numeração ou identidade das Cards promocionais individuais — fica para a modelagem da entidade Card.

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
120 - Create Card Set Table      (v2.0, Status CANÔNICA)
121 - Create Card Set Trigger
122 - Adapt Card Set for Promo   (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
820 - Seed Card Set              (v2.0, Status CANÔNICA)
821 - Seed Promo Card Set        (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
920 - Validate Card Set          (versão 2.0)
```

Seguindo a regra de deslocamento fixo (STD-001, Seção 10: Seed = criação + 700, Validate = criação + 800). `122` é uma migration de ajuste dentro do próprio bloco 100–199 de Card Set, não uma nova entidade. `821` é um Seed adicional dentro da faixa 800–899, criado antes da decisão de consolidar tudo em `820`. Ambas preservadas por rastreabilidade, mas reclassificadas como `MIGRATION` pelo Princípio da Fonte Canônica (STD-001, Seção 10) — uma instalação nova executa apenas `120` v2.0 e `820` v2.0.

## Definition of Done

- [x] modelo lógico definido, por grupo;
- [x] atributos e campos adiados definidos;
- [x] regras de negócio definidas (incluindo a Regra 8);
- [x] tabela `card_set` criada no Supabase (`120`);
- [x] RLS habilitado;
- [x] trigger criado (`121`) e verificado via `information_schema.triggers`;
- [x] suporte a `PROMO` adicionado (`122`, executada dentro de transação);
- [x] seed executado (`820` — ME1–ME4; `821` — ME0, todos com dados validados);
- [x] validação executada e confirmada (`920` v2.0 — "Tudo ok");
- [x] Query `820` reescrita como snapshot completo da Expansion (v2.0, `ON CONFLICT ... DO UPDATE`, inclui `ME0`) — ver "Pendência — Reescrita da Query 820 (RESOLVIDA)";
- [x] Query `120` consolidada para v2.0 (`CANÔNICA`), com suporte nativo a `PROMO` e o índice `uq_card_set_expansion_promo`; `122`/`821` reclassificadas `MIGRATION`;
- [ ] confirmar se o índice `uq_card_set_expansion_promo` já existe no banco físico atual — **único item aberto**, ver "Divergência sinalizada", acima. Não bloqueia o início da modelagem de Card, mas deve ser verificado antes de considerar a regra de unicidade de `PROMO` realmente garantida em produção.

---

# Rarity (Raridade)

Status: **Pacote técnico concluído, incluindo a evolução do modelo com `symbol_code`.** Tabela, trigger, seed e validação executados e confirmados no Supabase. As Queries `130`, `830` e `930` foram reescritas para `Versão 2.0` (Status `CANÔNICA`, seguindo o Princípio da Fonte Canônica de STD-001, Seção 10) para incorporar `symbol_code`, já aplicado ao banco físico real por uma Query temporária de ajuste — ver "Evolução do Modelo — Campo `symbol_code`", abaixo. `131` permanece inalterada (o trigger continua válido). **Sem pendências técnicas.**

## Modelo Lógico

```text
Rarity

Identidade
----------
id
code

Descrição
----------
name
symbol_code

Relacionamento
----------
game_id

Ordenação
----------
display_order

Auditoria
----------
created_at
updated_at
```

## Atributos

**id** — Identificador técnico e permanente (UUID).

**game_id** — Chave estrangeira obrigatória para `game`. Toda Rarity pertence a exatamente um Game — raridades não são compartilhadas entre jogos, mesmo quando usam nomes parecidos (ver `04-domain-model.md`, seção Rarity).

**code** — Código técnico e estável (ex.: `SPECIAL_ILLUSTRATION_RARE`), ou, quando um código curto oficial for relevante para o mercado, uma forma abreviada (ex.: `SAR`). Único dentro do Game.

**name** — Nome oficial ou principal de exibição (ex.: `Special Art Rare`).

**symbol_code** — Identificador técnico e estável do símbolo visual oficial da raridade, conforme apresentado na legenda oficial do catálogo (ex.: `BLACK_STAR`, `GOLD_DOUBLE_STAR`). **Não é o próprio caractere/emoji** (ex. `★`) nem uma URL de imagem — é um identificador textual que a camada de apresentação (Power Apps, Power BI, interface web) poderá futuramente converter em SVG, PNG, componente visual ou símbolo via CSS. Ver "Evolução do Modelo — Campo `symbol_code`", abaixo, para o raciocínio completo por trás desta decisão.

**display_order** — Posição em uma sequência lógica de apresentação (ex.: Common antes de Uncommon, antes de Rare...). Não deve ser inferida alfabeticamente. **Deliberadamente não é único dentro do Game** (sem `UNIQUE (game_id, display_order)`) — decisão explícita: duas raridades diferentes podem ocupar posições ou níveis equivalentes na sequência, sem serem a mesma classificação. A ordenação continua previsível combinando `display_order` com `code` (`ORDER BY display_order, code`).

**created_at / updated_at** — Auditoria mínima (ver STD-001, Seção 4).

## Campos que Não Incluiremos Agora

Aplicando o Princípio da Simplicidade Inicial (AP-004): uma classificação normalizada para agrupar raridades equivalentes entre catálogos/mercados diferentes (ex.: `official_code`/`rarity_group`, cogitada durante a discussão mas sem necessidade concreta comprovada ainda); `icon_url` (arquivo gráfico oficial do símbolo) — deliberadamente adiado porque os arquivos gráficos oficiais ainda não estão hospedados; incluir a URL agora criaria URLs provisórias ou ativos sem governança. Uma futura tabela de domínio própria `symbol` (`id, code, description, svg_url, png_url, sort_order`), com `rarity.symbol_id` substituindo `rarity.symbol_code`, foi cogitada e deliberadamente **não** adotada agora — hoje existe exatamente um símbolo por raridade, então criar a tabela aumentaria a complexidade sem benefício imediato; fica registrada como possibilidade de evolução natural do modelo, não como pendência.

## Regras de Negócio

**Regra 1 — Relacionamento obrigatório.** Toda Rarity deve pertencer a exatamente um Game.

**Regra 2 — Código único por Game.** O código deve ser único dentro do respectivo Game (`UNIQUE (game_id, code)`), não globalmente — mesmo padrão de unicidade escopada já aplicado a Expansion e Set.

**Regra 3 — Nome e código obrigatórios.** Nem `code` nem `name` podem ser vazios.

**Regra 4 — Não presumir equivalência entre mercados.** Códigos abreviados como `SAR` e `SIR` podem representar classificações distintas em diferentes mercados ou linhas editoriais — o banco preserva a classificação oficial exatamente como usada no catálogo correspondente, sem normalização automática entre eles (ver `04-domain-model.md`, seção Rarity).

**Regra 5 — Símbolo obrigatório e determinístico.** `symbol_code` é obrigatório e segue o mesmo formato técnico de `code` (maiúsculas, números e sublinhado). Representa a identidade visual oficial da raridade, definida por três elementos observados na legenda oficial — formato, quantidade e estilo/cor —, não deve ser inferido do `name` ou do `code`: raridades diferentes podem usar o mesmo elemento gráfico base (ex.: `RARE` e `ILLUSTRATION_RARE` usam estrela) sem serem visualmente equivalentes (cor/estilo diferentes).

**Regra 6 — Exclusão restrita.** Um Game que já possua Rarities não deve ser excluído (`ON DELETE RESTRICT`).

## Modelo Físico (PostgreSQL) — Versão 1.0, Executada Originalmente (histórico)

*Esta é a Query como foi executada pela primeira vez, sem `symbol_code` (Status `MIGRATION` retroativo — superada pela Versão Canônica 2.0, abaixo, mas preservada aqui para rastreabilidade, seguindo o Princípio da Fonte Canônica de STD-001, Seção 10).*

```sql
CREATE TABLE public.rarity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_rarity_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_rarity_game_code
        UNIQUE (game_id, code),
    CONSTRAINT ck_rarity_code_format
        CHECK (code ~ '^[A-Z0-9][A-Z0-9_]*$'),
    CONSTRAINT ck_rarity_name_not_blank
        CHECK (btrim(name) <> ''),
    CONSTRAINT ck_rarity_display_order_positive
        CHECK (display_order > 0)
);

ALTER TABLE public.rarity
ENABLE ROW LEVEL SECURITY;
```

Query: `130 - Create Rarity Table` (v1.0). Resultado confirmado por Fabrício: `Success. No rows returned`. Nota: `name` usa `VARCHAR(150)` (mesmo padrão de Game/Expansion, não o `VARCHAR(100)` inicialmente rascunhado neste documento); `code` recebeu a mesma constraint de formato já usada em Game/Expansion (`ck_rarity_code_format`, letras maiúsculas/números/sublinhado), em vez de apenas "não vazio". Confirma a regra 4 (não presumir equivalência entre mercados) e a decisão de **não** criar `UNIQUE (game_id, display_order)` — ver "Atributos," acima.

## Modelo Físico — Versão Canônica (2.0)

Status `CANÔNICA` (STD-001, Seção 10 — Princípio da Fonte Canônica): esta é a versão que uma **instalação nova** deve executar — já nasce com `symbol_code`, incorporando o que foi aplicado ao banco atual pela Query temporária de ajuste (ver "Evolução do Modelo — Campo `symbol_code`", abaixo). **Diferente do caso do Card Set, aqui a versão canônica já reflete o estado real do banco físico** — a Query temporária confirmou a execução real antes desta consolidação.

```sql
CREATE TABLE public.rarity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    symbol_code VARCHAR(50) NOT NULL,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_rarity_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_rarity_game_code
        UNIQUE (game_id, code),
    CONSTRAINT ck_rarity_code_format
        CHECK (code ~ '^[A-Z0-9][A-Z0-9_]*$'),
    CONSTRAINT ck_rarity_symbol_code_format
        CHECK (symbol_code ~ '^[A-Z0-9][A-Z0-9_]*$'),
    CONSTRAINT ck_rarity_name_not_blank
        CHECK (btrim(name) <> ''),
    CONSTRAINT ck_rarity_display_order_positive
        CHECK (display_order > 0)
);

ALTER TABLE public.rarity
ENABLE ROW LEVEL SECURITY;
```

Query: `130 - Create Rarity Table` (v2.0, `CANÔNICA`). Representa o estado estrutural definitivo para novas instalações e o estado real do banco atual.

### Trigger de `updated_at`

```sql
CREATE TRIGGER trg_rarity_set_updated_at
BEFORE UPDATE
ON public.rarity
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
```

Query: `131 - Create Rarity Trigger`. Resultado confirmado por Fabrício: `Success. No rows returned`. Reaproveita a função compartilhada `set_updated_at()` (ver seção Game). **Não foi alterada pela adição de `symbol_code`** — o trigger opera sobre a linha inteira e continua válido sem qualquer ajuste, confirmado explicitamente na sessão paralela.

### Seed — Versão 1.0, Executada Originalmente (histórico)

*Esta é a Seed como foi executada pela primeira vez, sem `symbol_code` (Status `MIGRATION` retroativo — superada pela Versão Canônica 2.0, abaixo, mas preservada aqui para rastreabilidade).*

Decisão arquitetural tomada antes da carga: cadastrar não apenas as raridades da Expansion `ME`, mas o conjunto consolidado observado nas legendas oficiais de todos os Sets já catalogados (`ME1`–`ME4`), para que `rarity` funcione como uma verdadeira tabela de domínio do Game `POKEMON`, não apenas da Expansion `ME` — evitando que cada nova Expansion exija inserir raridades que já existem no jogo. Fabrício confirmou: "Eu cadastraria todas as raridades que aparecem na lista de verificação de cada Set. Temos todos na legenda do arquivo que já tinha enviado."

**Correção de nomenclatura (SAR):** a lista oficial brasileira usa "Ilustração Rara Especial" — o código canônico adotado é `SPECIAL_ILLUSTRATION_RARE`, **não** um código `SAR` separado. `SAR`/`SIR` não são cadastrados como raridades adicionais apenas por serem abreviações usadas por colecionadores ou em outros mercados; a interface poderá permitir que o usuário pesquise por `SAR`, `SIR` ou `Ilustração Rara Especial` e todos apontem para a mesma raridade canônica, sem duplicar registros (ver Regra 4, acima).

```sql
DO $$
DECLARE
    v_game_id UUID;
BEGIN
    SELECT id
      INTO v_game_id
      FROM public.game
     WHERE code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 830: o Game POKEMON não está cadastrado.';
    END IF;

    INSERT INTO public.rarity (
        game_id,
        code,
        name,
        display_order
    )
    VALUES
        (v_game_id, 'COMMON',                    'Comum',                     1),
        (v_game_id, 'UNCOMMON',                  'Incomum',                   2),
        (v_game_id, 'RARE',                      'Rara',                      3),
        (v_game_id, 'DOUBLE_RARE',               'Rara Dupla',                4),
        (v_game_id, 'ULTRA_RARE',                'Rara Ultra',                5),
        (v_game_id, 'MEGA_ATTACK_RARE',          'Rara Mega Ataque',          6),
        (v_game_id, 'ILLUSTRATION_RARE',         'Ilustração Rara',           7),
        (v_game_id, 'SPECIAL_ILLUSTRATION_RARE', 'Ilustração Rara Especial',  8),
        (v_game_id, 'MEGA_HYPER_RARE',           'Mega Rara Hiper',           9)
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        display_order = EXCLUDED.display_order;
END;
$$;
```

Query: `830 - Seed Rarity` (v1.0). Resultado confirmado por Fabrício: "Executada com sucesso." Nove raridades cadastradas, consolidadas a partir das legendas oficiais de `ME1`, `ME2`, `ME2.5`, `ME3` e `ME4` (fonte: `assets/reference-sources/`) — `Rara Mega Ataque` veio especificamente da legenda de `ME2.5`.

**Nova técnica, diferente do padrão `INSERT ... SELECT ... WHERE` usado em Game/Expansion/Set:** um bloco `DO $$ ... END $$` em PL/pgSQL resolve o `game_id` uma vez em uma variável (`v_game_id`) e usa `RAISE EXCEPTION` para falhar de forma explícita e legível caso o Game `POKEMON` não exista — em vez de silenciosamente inserir zero linhas. Alternativa válida ao padrão de `SELECT`/`CROSS JOIN` já documentado em STD-001, útil quando a ausência do pré-requisito deve ser um erro visível, não um resultado vazio silencioso.

### Seed — Versão Canônica (2.0)

Status `CANÔNICA`: inclui `symbol_code` para cada uma das nove raridades, mapeado a partir das legendas oficiais de verificação (fonte: `assets/reference-sources/`, especificamente `P10346_ME01_Card_List_PTBR.pdf` e `ME02pt5_Card_List_PTBR.pdf` para o símbolo específico de `MEGA_ATTACK_RARE`):

```sql
DO $$
DECLARE
    v_game_id UUID;
BEGIN
    SELECT id
      INTO v_game_id
      FROM public.game
     WHERE code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 830: o Game POKEMON não está cadastrado.';
    END IF;

    INSERT INTO public.rarity (
        game_id,
        code,
        name,
        symbol_code,
        display_order
    )
    VALUES
        (v_game_id, 'COMMON',                    'Comum',                     'BLACK_CIRCLE',       1),
        (v_game_id, 'UNCOMMON',                  'Incomum',                   'BLACK_DIAMOND',      2),
        (v_game_id, 'RARE',                      'Rara',                      'BLACK_STAR',         3),
        (v_game_id, 'DOUBLE_RARE',               'Rara Dupla',                'BLACK_DOUBLE_STAR',  4),
        (v_game_id, 'ULTRA_RARE',                'Rara Ultra',                'SILVER_DOUBLE_STAR', 5),
        (v_game_id, 'MEGA_ATTACK_RARE',          'Rara Mega Ataque',          'MEGA_ATTACK',        6),
        (v_game_id, 'ILLUSTRATION_RARE',         'Ilustração Rara',           'GOLD_STAR',          7),
        (v_game_id, 'SPECIAL_ILLUSTRATION_RARE', 'Ilustração Rara Especial',  'GOLD_DOUBLE_STAR',   8),
        (v_game_id, 'MEGA_HYPER_RARE',           'Mega Rara Hiper',           'GOLD_DIAMOND',       9)
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        symbol_code = EXCLUDED.symbol_code,
        display_order = EXCLUDED.display_order;
END;
$$;
```

Query: `830 - Seed Rarity` (v2.0, `CANÔNICA`). Reflete o estado real e atual do banco, já aplicado via Query temporária de ajuste (ver "Evolução do Modelo — Campo `symbol_code`", abaixo).

**Nota importante sobre a identidade visual:** um mesmo elemento gráfico base (ex.: estrela) pode representar raridades diferentes — `RARE` e `ILLUSTRATION_RARE` usam estrela, mas não são visualmente equivalentes (cor/estilo diferentes: estrela preta vs. estrela dourada). O `symbol_code` captura os três elementos observados na legenda oficial — formato (círculo, losango, estrela), quantidade (simples, dupla) e estilo/cor (preto, prateado, dourado, multicolorido) — evitando que dois `symbol_code` diferentes sejam confundidos apenas por compartilharem o mesmo formato-base.

### Validação — Versão 1.0 (histórico)

*Versão executada e confirmada antes da adição de `symbol_code` — superada pela Versão Canônica 2.0, abaixo.*

Query: `930 - Validate Rarity` (v1.0). **Resultado confirmado por Fabrício ("Executada com sucesso").** As mesmas 7 subconsultas da versão 1.0 do modelo físico (sem `symbol_code`) — ver o histórico de revisão 0.18 deste documento para o SQL completo, se necessário.

### Validação — Versão Canônica (2.0)

```sql
-- 1. Relação completa das raridades
SELECT
    g.code AS game,
    r.display_order,
    r.code,
    r.name,
    r.symbol_code
FROM public.rarity r
INNER JOIN public.game g
    ON g.id = r.game_id
ORDER BY
    g.code,
    r.display_order,
    r.code;

-- 2. Quantidade de raridades por Game
SELECT
    g.code,
    COUNT(*) AS total_rarities
FROM public.rarity r
INNER JOIN public.game g
    ON g.id = r.game_id
GROUP BY
    g.code;

-- 3. Verificar códigos duplicados (esperado: zero linhas)
SELECT
    game_id,
    code,
    COUNT(*)
FROM public.rarity
GROUP BY
    game_id,
    code
HAVING COUNT(*) > 1;

-- 4. Verificar display_order inválido (esperado: zero linhas)
SELECT *
FROM public.rarity
WHERE display_order <= 0;

-- 5. Verificar nomes vazios (esperado: zero linhas)
SELECT *
FROM public.rarity
WHERE btrim(name) = '';

-- 6. Verificar códigos inválidos (esperado: zero linhas)
SELECT *
FROM public.rarity
WHERE code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- 7. Verificar symbol_code inválido ou ausente (esperado: zero linhas)
SELECT *
FROM public.rarity
WHERE symbol_code IS NULL
   OR symbol_code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- 8. Verificar funcionamento do trigger updated_at
SELECT
    code,
    created_at,
    updated_at
FROM public.rarity
ORDER BY
    display_order;
```

Query: `930 - Validate Rarity` (v2.0, `CANÔNICA`). Resultado esperado, consistente com a Query temporária já executada (ver tabela abaixo, "Evolução do Modelo — Campo `symbol_code`"): consulta 1 retorna 9 registros com `symbol_code` preenchido; consultas 3, 4, 5, 6 e 7 retornam zero linhas; consulta 8 confirma auditoria presente em todos os registros. **Com esse resultado, o pacote técnico da entidade Rarity permanece concluído**, agora já refletindo `symbol_code`.

### Evolução do Modelo — Campo `symbol_code`

Ao revisar o resultado de Rarity já implementado, Fabrício levantou, na sessão paralela, se a raridade deveria carregar seu símbolo oficial — não como um único caractere (`★`), mas como um identificador estável que capture os três elementos observados nas legendas oficiais dos Sets já catalogados: **formato** (círculo, losango, estrela), **quantidade** (simples, dupla) e **estilo/cor** (preto, prateado, dourado, multicolorido). Ponto de partida explícito de Fabrício: *"não usaremos apenas um caractere como ★ [...] As listas oficiais mostram que a identidade da raridade depende de três elementos: formato; quantidade; estilo/cor."*

**Decisão tomada e já aplicada ao banco físico:** adicionar `symbol_code VARCHAR(50) NOT NULL` a `rarity`, com os seguintes valores reais:

| Raridade | `code` | `symbol_code` |
|----------|--------|----------------|
| Comum | `COMMON` | `BLACK_CIRCLE` |
| Incomum | `UNCOMMON` | `BLACK_DIAMOND` |
| Rara | `RARE` | `BLACK_STAR` |
| Rara Dupla | `DOUBLE_RARE` | `BLACK_DOUBLE_STAR` |
| Rara Ultra | `ULTRA_RARE` | `SILVER_DOUBLE_STAR` |
| Rara Mega Ataque | `MEGA_ATTACK_RARE` | `MEGA_ATTACK` |
| Ilustração Rara | `ILLUSTRATION_RARE` | `GOLD_STAR` |
| Ilustração Rara Especial | `SPECIAL_ILLUSTRATION_RARE` | `GOLD_DOUBLE_STAR` |
| Mega Rara Hiper | `MEGA_HYPER_RARE` | `GOLD_DIAMOND` |

Deliberadamente **não** foi incluído `icon_url` neste momento — os arquivos gráficos oficiais ainda não estão hospedados, e incluir a URL agora criaria ativos sem governança (mesmo cuidado já aplicado a `logo_url`/`symbol_url` do Set — ver seção Set, acima).

**Como a mudança foi aplicada:** por uma Query de ajuste operacional, explicitamente marcada como `Status: TEMPORÁRIA` (não numerada, não canônica) — adicionou a coluna, preencheu os valores reais por `CASE`, tornou a coluna `NOT NULL` e criou a constraint de formato, tudo dentro de uma transação (`BEGIN`/`COMMIT`). Confirmada por Fabrício como executada com sucesso, com o resultado final conferido (9 linhas, `symbol_code` preenchido conforme a tabela acima). **Esta Query temporária não foi copiada para `database/`** — por decisão explícita de Fabrício ("A Query temporária usada para modificar o banco atual pode ser descartada após confirmarmos as versões canônicas"), ela existe apenas como registro narrativo aqui; as Queries `130`, `830` e `930` foram reescritas em lugar (Versão 2.0, `CANÔNICA`) para que uma instalação nova já nasça com `symbol_code`, sem depender de um ajuste posterior — mesmo princípio já aplicado ao Card Set (`120`/`820`), mas aqui com uma diferença importante: a consolidação canônica já reflete o estado real do banco físico, não apenas uma correção de repositório pendente de confirmação.

`131 - Create Rarity Trigger` foi explicitamente confirmada como **não precisando de alteração** — o trigger de `updated_at` opera sobre a linha inteira, independente de quais colunas existem.

**Ideia para o futuro, registrada mas não adotada agora:** uma tabela de domínio própria `symbol` (`id, code, description, svg_url, png_url, sort_order`), com `rarity.symbol_id` substituindo `rarity.symbol_code`. Motivo para não adotar: hoje existe exatamente um símbolo por raridade — criar a tabela agora aumentaria a complexidade sem trazer benefício imediato. Motivo para registrar: mostra que o modelo é evolutivo sem exigir refatorações radicais, caso essa relação deixe de ser 1-para-1 no futuro (ex.: dois estilos de arte para o mesmo símbolo).

### Observação Arquitetural — Card Depende de Dois Domínios

A criação de `rarity` revelou uma estrutura de dependência antes não explícita: `card` não depende apenas da cadeia `Game → Expansion → Card Set`, mas também diretamente de `Game → Rarity`:

```text
Game
 ├── Expansion
 │     └── Card Set
 │           └── Card
 │
 └── Rarity
       └── Card
```

Consequência prática, não apenas estética: `rarity` deixa de ser um atributo textual solto e passa a ser um catálogo oficial do próprio Game, o que facilita filtros, estatísticas, internacionalização e evita inconsistências de cadastro (ver `04-domain-model.md`, seção Rarity).

### Proposta do Campo `symbol` — Resolvida

Uma proposta anterior (revisão 0.18 deste documento) havia sinalizado, como item em aberto e não confirmado, um possível campo `symbol` para o símbolo/ícone da raridade. **Esta proposta foi retomada, refinada e confirmada por Fabrício nesta revisão** — não como um único caractere `symbol`, mas como o identificador estruturado `symbol_code` descrito em "Evolução do Modelo — Campo `symbol_code`", acima, que captura formato+quantidade+estilo/cor em vez de um símbolo solto. Texto original da proposta preservado no histórico de revisão (0.18) para rastreabilidade.

## Definition of Done

- [x] modelo lógico definido, por grupo (incluindo `symbol_code`);
- [x] atributos e campos adiados definidos;
- [x] regras de negócio definidas (incluindo a Regra 5, `symbol_code`);
- [x] tabela `rarity` criada no Supabase, já com `symbol_code` (`130` v2.0);
- [x] RLS habilitado;
- [x] trigger criado (`131`, inalterado);
- [x] seed executado, já com `symbol_code` (`830` v2.0 — nove raridades reais, consolidadas de `ME1`–`ME4`);
- [x] validação executada e confirmada, já com `symbol_code` (`930` v2.0).

Sem pendências técnicas.

## Queries Associadas

```text
130 - Create Rarity Table    (v2.0, Status CANÔNICA — executada, inclui symbol_code)
131 - Create Rarity Trigger  (executada, inalterada)
830 - Seed Rarity            (v2.0, Status CANÔNICA — executada, inclui symbol_code)
930 - Validate Rarity        (v2.0, Status CANÔNICA — executada e confirmada, inclui symbol_code)
```

Rarity precisava ser criada antes de Card, por dependência de chave estrangeira (`card.rarity_id`) — ver STD-001, Seção 10. Com o pacote técnico de Rarity concluído, o próximo passo real é `140 - Create Card Table`.

---

# Card (Carta)

Status: **Modelo lógico aprovado por Fabrício** ("Excelente. Temos a definição agora. Vamos seguir com a execução!"). **Execução no Supabase ainda pendente** — depende da criação prévia de `rarity` (Query `130`). Query `140 - Create Card Table` é o próximo passo real após Rarity. **Itens em aberto que precisam de confirmação de Fabrício antes da execução:** nomenclatura Card Printing vs. Card Translation; nomenclatura Card Variant vs. Finish/Card Finish; se `category_code` deve aceitar `ENERGY` (ver "Regras de Negócio," abaixo — contradiz uma decisão de escopo já registrada) — ver `04-domain-model.md`, seção Card, "Modelagem Física — Discussão Iniciada".

## Modelo Lógico

```text
Card

Identidade
----------
id
card_number
card_order

Descrição
----------
category_code

Relacionamento
----------
card_set_id
rarity_id

Auditoria
----------
created_at
updated_at
```

## Atributos

**id** — Identificador técnico e permanente (UUID).

**card_set_id** — Chave estrangeira obrigatória para `card_set`. Toda Card pertence a exatamente um Card Set (ver ADR-004 — identidade Set + Número da Card).

**rarity_id** — Chave estrangeira obrigatória para `rarity` (ver seção Rarity, acima). Não armazenado como texto solto — decisão resolvida após avaliar riscos de duplicação/inconsistência entre jogos e mercados.

**card_number** — Número oficial impresso ou atribuído à Card, armazenado como texto (`VARCHAR`), nunca inteiro — preserva zeros à esquerda (`003`), prefixos (`TG01`), sufixos e numerações alfanuméricas de outros TCGs ou formatos editoriais futuros, sem conversão.

**card_order** — Posição sequencial da Card no checklist do Card Set, tecnicamente distinta de `card_number`: usada para ordenação correta (comparar `card_number` como texto ordenaria `001, 010, 011, 002` incorretamente) e sustenta numerações futuras não numéricas (`TG01`, `SV01`) sem regras especiais de conversão.

**category_code** — Classifica a Card (Pokémon ou Trainer no escopo atual — ver "Regras de Negócio," abaixo para a pendência sobre `ENERGY`). Mantido como coluna simples nesta primeira versão, não como entidade de referência — poucos valores estáveis. Necessário para filtros concretos do produto (ex.: listar apenas Cards de Treinador de um Set), não apenas para identificar a Card.

**created_at / updated_at** — Auditoria mínima (ver STD-001, Seção 4).

## Campos que Não Incluiremos Agora

Aplicando o Princípio da Simplicidade Inicial (AP-004) e o Princípio do Escopo Colecionável (AP-017):

- **Nome, idioma, texto localizado, arte, ilustrador, revisão/errata** — pertencem à camada Card Printing (ainda não modelada fisicamente; nomenclatura frente a Card Translation ainda não decidida por Fabrício).
- **Acabamento (Holofoil, Reverse Holofoil), selo** — pertencem à camada Card Variant / Finish-Card Finish (nomenclatura ainda não decidida por Fabrício).
- **HP, estágio, tipo elemental, fraqueza, resistência, custo de recuo, ataques, habilidades, texto de regras, referência estrutural a Pokémon** — permanentemente fora do banco de dados (mecânica de jogo, não colecionismo — ver AP-017). Continuam visíveis apenas na imagem oficial da Card.
- **Condição física, preço pago, quantidade possuída, localização, grading, notas** — pertencem ao Collection Item.
- **Preço de mercado** — domínio de mercado/preços, não modelado ainda.

## Regras de Negócio

**Regra 1 — Relacionamento obrigatório.** Toda Card deve pertencer a exatamente um Card Set.

**Regra 2 — Raridade obrigatória.** Toda Card deve referenciar uma Rarity (`rarity_id NOT NULL`).

**Regra 3 — Número único por Card Set.** O número deve ser único dentro do respectivo Card Set (`UNIQUE (card_set_id, card_number)`), não globalmente.

**Regra 4 — Ordem única por Card Set.** A posição no checklist deve ser única dentro do respectivo Card Set (`UNIQUE (card_set_id, card_order)`) e um número inteiro positivo.

**Regra 5 — Número não vazio, sem formato rígido.** `card_number` não pode ser vazio, mas deliberadamente **sem** uma expressão regular de formato — formatos variam entre jogos/publicações; uma restrição rígida poderia bloquear um código oficial válido.

**Regra 6 — Categoria restrita.** `category_code` deve ser `POKEMON` ou `TRAINER`.

> **Pendência sinalizada, não resolvida unilateralmente:** um lote de modelagem física cogitou `ENERGY` como terceiro valor inicial de `category_code`, o que contradiz a "Decisão de Escopo — Cartas de Energia" já registrada em `04-domain-model.md` (Card Category) — cartas de Energia foram deliberadamente excluídas do catálogo numerado. Esta Regra 6 reflete a decisão já confirmada (apenas `POKEMON`/`TRAINER`); **não incluir `ENERGY` na constraint até confirmação explícita de Fabrício.**

**Regra 7 — Exclusão restrita.** Um Card Set que já possua Cards não pode ser excluído (`ON DELETE RESTRICT`); uma Rarity que já esteja referenciada por Cards não pode ser excluída (`ON DELETE RESTRICT`).

## Modelo Físico (PostgreSQL) — Proposto, Ainda Não Executado

```sql
CREATE TABLE public.card (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_set_id UUID NOT NULL,
    rarity_id UUID NOT NULL,

    card_number VARCHAR(30) NOT NULL,
    card_order INTEGER NOT NULL,
    category_code VARCHAR(20) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_card_card_set
        FOREIGN KEY (card_set_id)
        REFERENCES public.card_set (id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_rarity
        FOREIGN KEY (rarity_id)
        REFERENCES public.rarity (id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_card_set_number
        UNIQUE (card_set_id, card_number),

    CONSTRAINT uq_card_card_set_order
        UNIQUE (card_set_id, card_order),

    CONSTRAINT ck_card_number_not_blank
        CHECK (btrim(card_number) <> ''),

    CONSTRAINT ck_card_order_positive
        CHECK (card_order > 0),

    CONSTRAINT ck_card_category
        CHECK (category_code IN ('POKEMON', 'TRAINER'))
);

ALTER TABLE public.card
ENABLE ROW LEVEL SECURITY;
```

> **Nota:** este DDL é uma proposta seguindo os padrões já estabelecidos em STD-001, refletindo o modelo mínimo aprovado por Fabrício. A constraint `ck_card_category` inclui deliberadamente apenas `POKEMON`/`TRAINER` — ver Regra 6 acima sobre a pendência de `ENERGY`. Tipos e nomes de constraint específicos podem ser ajustados na execução real. Não presumir que este SQL foi executado até confirmação.

## Definition of Done

- [x] modelo lógico definido, por grupo;
- [x] atributos e campos adiados definidos, incluindo o escopo confirmado por AP-017;
- [x] regras de negócio definidas (com a pendência de `ENERGY` sinalizada, não resolvida);
- [x] modelo físico proposto (DDL);
- [ ] confirmação de Fabrício sobre `ENERGY` como valor de `category_code`;
- [ ] confirmação de Fabrício sobre a nomenclatura Card Printing vs. Card Translation;
- [ ] confirmação de Fabrício sobre a nomenclatura Card Variant vs. Finish/Card Finish;
- [ ] tabela `rarity` criada no Supabase (pré-requisito, ver seção Rarity);
- [ ] tabela `card` criada no Supabase (Query `140`);
- [ ] RLS habilitado e confirmado;
- [ ] trigger criado (`141`) e verificado;
- [ ] seed executado (`840`);
- [ ] validação executada e confirmada (`940`).

## Queries Associadas

```text
140 - Create Card Table
141 - Create Card Trigger
840 - Seed Card
940 - Validate Card
```

Depende da existência prévia de `rarity` (`130`) e `card_set` (`120`). Card Printing e Card Variant (ou os nomes que Fabrício confirmar) ainda não têm números de Query atribuídos — dependem das decisões de nomenclatura em aberto.

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
| 0.13 | **Pacote técnico da entidade Set concluído.** Migration `122 - Adapt Card Set for Promo` executada (transação com drop/add de constraint, deslocamento de `release_order`, nova constraint `ck_card_set_promo_size`). Set promocional real cadastrado via `821 - Seed Promo Card Set` (`ME0`, 89 cartas). Query `920` evoluída para versão 2.0 (cinco categorias, onze subconsultas), executada e confirmada por Fabrício ("Tudo ok"). Sinalizada divergência entre o índice único parcial recomendado por ADR-015 e o que foi de fato executado (não implementado). Nova seção "Pendência — Reescrita da Query 820": decisão de consolidar `820`+`821` em um único snapshot completo com `ON CONFLICT ... DO UPDATE`, SQL ainda não apresentado. Definition of Done quase completa — falta apenas essa reescrita. |
| 0.14 | Adicionada nota apontando que todo SQL "executado" documentado aqui também existe como arquivo `.sql` versionado em `database/` (auditoria de saúde do repositório) — ver `database/README.md`. |
| 0.15 | Adotado o Princípio da Fonte Canônica (STD-001, Seção 10) para Card Set. Queries `120` e `820` reescritas em `Versão 2.0` (Status `CANÔNICA`): `120` v2.0 já nasce com suporte nativo a `PROMO` e inclui o índice único parcial `uq_card_set_expansion_promo` (ausente na v1.0/migration `122`); `820` v2.0 consolida todos os seis Card Sets da Expansion `ME` (incluindo `ME0`) em um único snapshot com `ON CONFLICT ... DO UPDATE`. DDL e Seed originais preservados como histórico (v1.0). Queries `122` e `821` reclassificadas como `MIGRATION` — preservadas, mas fora do fluxo de instalação limpa. Pendência de reescrita da `820` marcada como RESOLVIDA (texto original preservado). Sinalizado item aberto: status do índice `uq_card_set_expansion_promo` no banco físico atual não confirmado, já que esta consolidação foi feita no repositório, não reexecutada no Supabase. Definition of Done e Queries Associadas atualizadas com Status por Query. |
| 0.16 | Adicionadas as entidades **Rarity** e **Card**, ambas com modelo lógico completo e aprovado por Fabrício ("Vamos seguir com a execução!"), incluindo proposta de DDL (ainda não executada no Supabase). Rarity: entidade de referência vinculada ao Game (`id, game_id, code, name, display_order`), criada antes de Card por dependência de FK — Query `130`. Card: modelo mínimo (`id, card_set_id, rarity_id, card_number, card_order, category_code, created_at, updated_at`) — Query `140` (deslocada de `130`, cedido a Rarity). Substituído o stub "Documentação pendente" da seção Card. Sinalizadas três pendências antes da execução real: confirmação de Fabrício sobre `ENERGY` como valor de `category_code` (contradiz decisão de escopo já registrada), e as nomenclaturas Card Printing vs. Card Translation e Card Variant vs. Finish/Card Finish. |
| 0.17 | **Rarity executada e confirmada no Supabase.** Queries `130` (tabela — `name VARCHAR(150)`, `code` com constraint de formato, `display_order` deliberadamente sem `UNIQUE`), `131` (trigger) e `830` (seed — nove raridades reais, consolidadas de `ME1`–`ME4`, usando um novo padrão `DO $$ ... END $$` com `RAISE EXCEPTION` caso o Game não exista) confirmadas por Fabrício. Corrigida a nomenclatura: código canônico é `SPECIAL_ILLUSTRATION_RARE`, não um `SAR` separado. Query `930 - Validate Rarity` escrita com resultados esperados, mas execução ainda não confirmada — único item aberto. Adicionada "Observação Arquitetural — Card Depende de Dois Domínios" (`Game → Rarity` além de `Game → Expansion → Card Set`). Definition of Done e Queries Associadas atualizadas. |
| 0.18 | **Pacote técnico da entidade Rarity concluído.** Query `930 - Validate Rarity` confirmada por Fabrício ("Executada com sucesso") — todas as 7 subconsultas com resultado esperado (9 registros, sem duplicidade/inconsistência). Definition of Done e Queries Associadas atualizadas (sem pendências técnicas). Adicionada seção "Proposta em Aberto — Campo `symbol`": levantada na sessão paralela (adicionar símbolo/ícone textual da raridade), com ressalva própria da recomendação de levantar legendas oficiais antes de decidir — não confirmada por Fabrício, nenhuma alteração de DDL feita. |
| 0.19 | **Campo `symbol_code` adicionado a `rarity` — decisão confirmada e já aplicada ao banco físico.** Refinamento de Fabrício sobre a proposta da revisão anterior: não um único caractere, mas um identificador que capture formato+quantidade+estilo/cor observados nas legendas oficiais. Queries `130`, `830` e `930` reescritas para `Versão 2.0` (`CANÔNICA`, Princípio da Fonte Canônica); versões 1.0 preservadas como histórico. `131` confirmada como inalterada. Mudança aplicada ao banco atual por uma Query temporária (`Status: TEMPORÁRIA`, não numerada) — deliberadamente **não** copiada para `database/`, por instrução explícita de Fabrício. Nova seção "Evolução do Modelo — Campo `symbol_code`" com a tabela real de valores (`BLACK_CIRCLE`...`GOLD_DIAMOND`) e o raciocínio completo, incluindo a ideia registrada (não adotada) de uma futura tabela de domínio `symbol`. `icon_url` formalmente adiado (mesmo cuidado já aplicado a `logo_url`/`symbol_url` do Set). Definition of Done e Queries Associadas atualizadas. |
