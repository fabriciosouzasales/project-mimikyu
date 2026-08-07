# Modelo de Dados — Catálogo Base (Game, Expansion, Card Set)

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados — Catálogo Base |
| **Arquivo** | `docs/05a-catalogo-base.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado (entidades concluídas e executadas) |
| **Objetivo** | Modelo lógico e físico de Game (Jogo), Expansion (Expansão) e Set (Card Set) — a hierarquia base do catálogo. |
| **Escopo** | Parte de `docs/05-modelo-de-dados.md` (índice) — resultado da divisão de 2026-08-06, motivada pelo tamanho do arquivo original (mais de 700 KB, acima do que ferramentas de leitura processam em uma chamada). |
| **Dependências** | `04-domain-model.md`, `standards/STD-001-database-standards.md`, `05-modelo-de-dados.md` |

Ver `docs/05-modelo-de-dados.md` para o mapa completo do domínio, a metodologia (Roteiro por Entidade) e o histórico de revisão consolidado até 2026-08-06 (revisões anteriores a esta divisão não foram redistribuídas retroativamente por entidade — ver nota na Revision History de lá).

---

# Game (Jogo)

Status: **Concluído e implementado.** Modelo físico executado desde o início do projeto (ver DDL abaixo); camada de escrita administrativa (`admin_create_game()`/`admin_update_game()`/`admin_delete_game()`, tela `/catalogo/jogos`) também concluída e validada — ver seção "Ciclo vertical — `Game`" e "Emenda — `Game`: exclusão real via UI", mais adiante neste documento.

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

Status: **Pacote técnico concluído, reaberto pontualmente (terceira vez): `MEE`/`MEP` já existem como `card_set` reais.** Tabela, trigger, suporte a Sets promocionais, seed e validação executados e confirmados. Tabela física: `card_set` (ver nota em `04-domain-model.md` e STD-001, Seção 2 — `SET` é palavra reservada do SQL). Seguindo o novo **Princípio da Fonte Canônica** (STD-001, Seção 10), as Queries `120 - Create Card Set Table` e `820 - Seed Card Set` foram consolidadas para `Versão 2.0`/`2.1` (Status `CANÔNICA`), já nascendo com suporte nativo a `PROMO`/`ENERGY` — as Queries `122`/`263`/`264`/`821` (que originalmente introduziram esses ajustes em um banco já existente) foram reclassificadas como `MIGRATION` (históricas), preservadas mas fora do fluxo de instalação limpa. **`ENERGY` adicionado ao domínio de `set_type` e `release_order` de `ME1`-`ME4` reorganizado (Migrations `263`/`264`, CONFIRMADAS EXECUTADAS)** — ver "Migration `263`–`264`", abaixo. **`MEE`/`MEP` CONFIRMADOS EXECUTADOS (Migrations `265`–`268`)** — ver "Migration `265`–`268`", abaixo. **`MEE` também já tem `card_set_external_reference` confirmada (Migration `270`, TCGdex, `mee`), `metadata` de ambos padronizada para `{}` (Migration `269`), e a data de lançamento de `MEE` corrigida para `2025-09-25` (Migration `271`)** — ver "Migration `269`–`271`", abaixo; camada `Expansion → Card Set → Card Set External Reference` está completa para os dois novos Sets. Cartas/variantes/referências de carta/imagens de `MEE`/`MEP` **ainda não existem** — plano para `840 - Seed Card` v2.2 definido, não executado. **Itens abertos:** (1) confirmar se o índice único parcial `uq_card_set_expansion_promo` (novo na versão canônica de `120`) já existe no banco físico atual — ver "Modelo Físico — Versão Canônica", abaixo; (2) `820` v2.0 desatualizada quanto ao `release_order` real e sem `MEE`/`MEP`; (3) discrepância real sinalizada, não resolvida: nomes de `ME1`-`ME4`/`ME2.5` estão em português, inconsistentes com o princípio (novo, `AP-018` revisão `1.8`) de espelhar o nome exato da fonte oficial consultada.

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

**set_type** — Classificação editorial: `REGULAR`, `SPECIAL`, `PROMO` (adicionado via migration `122` — ver "Card Set Promocional", abaixo; ADR-015) ou `ENERGY` (adicionado via migration `263` — ver "Migration `263`–`264`", abaixo; ADR-015, revisão `1.6`). Sem tabela de referência própria — poucos valores estáveis, sem atributos associados; também não usa `ENUM` nativo do PostgreSQL, cuja evolução é menos flexível que uma restrição `CHECK` (ver `04-domain-model.md`, seção Set — "Classificação Editorial").

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

**Regra 5 — Classificação editorial restrita.** `set_type` deve ser `REGULAR`, `SPECIAL`, `PROMO` (constraint ampliada pela migration `122`, executada) ou `ENERGY` (constraint ampliada pela migration `263`, executada).

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

## Modelo Físico — Versão Canônica (2.1)

Status `CANÔNICA` (STD-001, Seção 10 — Princípio da Fonte Canônica): esta é a versão que uma **instalação nova** deve executar — já nasce com suporte nativo a `PROMO`, incorporando o que antes exigia a migration `122` separada, **e adiciona o índice único parcial que a versão 1.0 e a migration `122` não incluíam** (a divergência sinalizada anteriormente em ADR-015 e nesta seção). **Versão `2.1`**: `ck_card_set_type` ampliada para incluir `ENERGY`, incorporando o que a migration `263` fez contra o banco já existente (ver "Migration `263`–`264`", abaixo) — uma instalação nova a partir desta versão não precisa executar `263` separadamente.

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
        CHECK (set_type IN ('REGULAR', 'SPECIAL', 'PROMO', 'ENERGY')),
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

Query: `120 - Create Card Set Table` (v2.1, `CANÔNICA`). Representa o estado estrutural definitivo para novas instalações — as Queries `122` e `263` (históricas) não precisam ser executadas em uma instalação nova.

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

> **Correção anunciada por Fabrício (2026-07-23), SQL/migration ainda não recebida — a tabela acima está desatualizada quanto ao código do Set promocional e a um novo Card Set.** "A decisão de cobrir o Set ME0 foi equivocada, pois não temos esse código como código oficial na API. Precisamos ajustar o código desse Set para `MEP`, que é o código oficial." Ou seja, `ME0` (linha 1 da tabela acima, `database/schema/120_*.sql`, `database/seeds/820_*.sql`/`821_*.sql`) precisa ser recodificado para `MEP` — nenhuma alteração foi feita em `database/` ainda, aguardando a Query real. Fabrício também informou a criação de um novo Card Set oficial, `MEE` ("Energy Set" da Expansão) — sem detalhes de estrutura (quantidade, `release_order`, datas) fornecidos ainda. **Possível relevância direta para a discrepância `ENERGY`** (9 Cards reais com `category = ENERGY` já cadastradas em `840`, espalhadas em `ME2`/`ME2.5`/`ME3`/`ME4`, contradizendo a decisão de escopo documentada) — não presumido, aguardando esclarecimento de Fabrício sobre a relação entre `MEE` e essas Cards.

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
120 - Create Card Set Table              (v2.1, Status CANÔNICA)
121 - Create Card Set Trigger
122 - Adapt Card Set for Promo           (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
263 - Add ENERGY to Card Set Type        (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
264 - Reorganize ME Release Order        (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
265 - Create Card Set MEE                (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
266 - Create Card Set MEP                (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
267 - Fix Card Set MEP Size              (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
271 - Fix Card Set MEE Release Date      (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
820 - Seed Card Set                      (v2.0, Status CANÔNICA — desatualizada, ver pendência abaixo)
821 - Seed Promo Card Set                (Status MIGRATION — histórica, fora do fluxo de instalação limpa)
920 - Validate Card Set                  (versão 2.0)
```

Seguindo a regra de deslocamento fixo (STD-001, Seção 10: Seed = criação + 700, Validate = criação + 800). `122`/`263`/`264`/`265`/`266`/`267` são migrations de ajuste dentro do próprio bloco 100–199 de Card Set, não novas entidades. `821` é um Seed adicional dentro da faixa 800–899, criado antes da decisão de consolidar tudo em `820`. Todas preservadas por rastreabilidade, mas reclassificadas como `MIGRATION` pelo Princípio da Fonte Canônica (STD-001, Seção 10) — uma instalação nova executa apenas `120` v2.1 e `820` v2.0. **Pendência**: `820` v2.0 ainda não reflete o `release_order` reorganizado por `264` nem `MEE`/`MEP` — precisa ser reescrita quando o catálogo da Expansion `ME` estiver definitivamente fechado (ver "Migration `265`–`268`", abaixo). `268 - Create Card Set External Reference MEP` pertence à tabela `card_set_external_reference`, listada na "Sequência" de "Card Set External Reference", abaixo.

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
- [ ] confirmar se o índice `uq_card_set_expansion_promo` já existe no banco físico atual — ver "Divergência sinalizada", acima. Não bloqueia o início da modelagem de Card, mas deve ser verificado antes de considerar a regra de unicidade de `PROMO` realmente garantida em produção.
- [x] domínio de `set_type` ampliado para incluir `ENERGY` (`263`, executada, validada);
- [x] `release_order` de `ME1`-`ME4` reorganizado (`264`, executada, validada), liberando `1`/`2` para `MEE`/`MEP`;
- [x] `MEE` cadastrado com dados editoriais oficiais reais (`265`, executada, validada);
- [x] `MEP` cadastrado com dados editoriais oficiais reais (`266`/`267`, executadas, validadas) e `card_set_external_reference` confirmada (`268`, executada, validada);
- [x] cartas de `MEE`/`MEP` cadastradas e validadas (`840` v2.2/`940` v2.1, executadas e confirmadas — 8 Cards em MEE, 60 em MEP, ver seção Card, "Seed — Query 840");
- [x] variantes de `MEE`/`MEP` (`860A`/`860B`/`960` v2.1, executadas e confirmadas — 16 Card Variants em MEE, 82 em MEP);
- [x] referências externas de carta (`card_external_reference`) de `MEE`/`MEP` em `en` — `RUN-20260724-00000041` (MEE, 8/8) e `RUN-20260724-00000061` (MEP, 60/60), ambas confirmadas;
- [x] imagens de `MEE`/`en`+`pt-BR` — **importadas manualmente** via `scripts/import-manual-assets.ts` (`source_code = 'MANUAL'`), já que a TCGdex confirmadamente não publica o asset para este Set (404 direto no CDN, não só ausência no campo `image` da API). `en` 8/8 (0 falhas, validado por consulta ao banco e inspeção visual); `pt-BR` 8/8 (0 falhas). **`MEE` está com o catálogo genuinamente completo nos dois idiomas**;
- [ ] imagens de `MEP`/`en`, `MEP`/`pt-BR` — mesmo processo planejado, imagens ainda não salvas localmente.

## Migration `251` — Remoção de `ME0` (CONFIRMADA EXECUTADA)

**Correção real e definitiva à pendência "ME0 ↔ `mee`" (aberta desde a revisão que descobriu os `external_set_id` reais da TCGdex, cross-referenciada em `06-pipeline-importacao.md`, Sprint B2.5A, e na seção "Card Set External Reference", abaixo).** Descoberta durante um teste real da Edge Function `import-card-assets` (Sprint B3.7, ver `06-pipeline-importacao.md`): uma execução de teste (`asset_import_run` `RUN-20260719-00000001`) apontava para a coleção `ME0`, e a função corretamente retornou `CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND`, pois `ME0` nunca teve uma referência externa ativa (ver Query `910`, abaixo). Ao investigar se `ME0` deveria finalmente ser mapeado ao Set `mee` da TCGdex, Fabrício esclareceu, com conhecimento direto do domínio, encerrando a ambiguidade: *"Na verdade nossa base tem ME0 como cartas promocionais de Megaevolution. na TCGdex mee são as cartas de energia. Coisas diferentes. Sugiro retirarmos da nossa base neste momento ME0."*

**Decisão final, real, confirmada por Fabrício**: `ME0` (interno — cartas promocionais de Mega Evolução) e `mee` (TCGdex — cartas de Energia de Mega Evolução) são **coleções diferentes, sem relação entre si** — o código semelhante (`ME0`/`mee`) era coincidência, não parentesco. Criar o vínculo introduziria um erro conceitual no modelo, não apenas uma referência técnica incorreta. Decisão: remover `ME0` da tabela `card_set` por completo (não apenas deixá-lo sem mapeamento externo), até que exista uma fonte externa homologada para esse conteúdo especificamente.

**Execução real, com verificação de dependências antes de qualquer exclusão (mesma disciplina já usada em todo o projeto)**: consultas de pré-checagem confirmaram exatamente o esperado — `card` referenciando `ME0`: `0`; `asset_import_run` referenciando `ME0`: `1` (a própria execução de teste que revelou o problema); `card_set_external_reference` referenciando `ME0`: `0` (nunca existiu, ver Query `910`). Com o cenário confirmado seguro, a migration `251 - Remove ME0` foi criada (`npx supabase migration new 251_remove_me0`) e executada via `npx supabase db push`:

```sql
DO $$
DECLARE
    v_card_set_id uuid;
BEGIN
    SELECT id
    INTO v_card_set_id
    FROM public.card_set
    WHERE code = 'ME0';

    IF v_card_set_id IS NULL THEN
        RAISE NOTICE 'ME0 não encontrada. Nenhuma alteração necessária.';
        RETURN;
    END IF;

    DELETE FROM public.asset_import_run
    WHERE card_set_id = v_card_set_id;

    DELETE FROM public.card_set
    WHERE id = v_card_set_id;
END;
$$;
```

**Validação real pós-execução, confirmada por Fabrício**: `SELECT id, code, name FROM public.card_set ORDER BY release_order;` retornou apenas `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` — `ME0` ausente, como esperado. `SELECT * FROM public.asset_import_run WHERE run_code = 'RUN-20260719-00000001';` retornou zero linhas ("Success. No rows returned. Tudo correto"). Migration confirmada executada com sucesso.

**Consequência para o restante deste documento**: todas as menções anteriores a `ME0` como parte da Expansion `ME` (Queries `120`/`121`/`122`/`820`/`821`/`920`, ADR-015) permanecem como registro histórico exato do que foi de fato modelado e executado até este ponto — não foram reescritas retroativamente, seguindo a disciplina de preservação de histórico do projeto. A partir desta revisão, porém, o estado físico e canônico da Expansion `ME` passa a ser de **cinco** Card Sets (`ME1`–`ME4`/`ME2.5`), não seis. Uma futura reescrita da Query `820` (Seed canônica) para remover `ME0` do snapshot **não foi feita nesta revisão** — a Query `820` v2.0 ainda insere `ME0` se executada em uma instalação nova, o que reintroduziria a linha removida aqui; sinalizado como pendência abaixo.

**Pendência nova, registrada nesta revisão**: a Query `820` v2.0 (Seed canônica de Card Set) precisa ser atualizada para não incluir mais `ME0`, sob risco de uma instalação nova a partir do zero recriar um registro que o projeto acabou de decidir remover. Até lá, `820` v2.0 deve ser tratada como desatualizada nesse ponto específico.

> **Diário Técnico — Migration 251 — Remoção de ME0**
> **Objetivo**: resolver definitivamente a pendência de longa data "`ME0` ↔ `mee`" e remover `ME0` do modelo físico, caso confirmado que não há relação real com nenhuma fonte externa homologada.
> **Critério de aceite**: decisão de negócio explícita de Fabrício; `ME0` removida de `card_set` sem quebrar integridade referencial.
> **Resultado**: 🟩 Concluído. Decisão de negócio ✅ obtida (coleções diferentes, sem relação). Remoção ✅ confirmada por consulta real pós-execução.
> **Pendências descobertas**: (1) Query `820` v2.0 (Seed canônica) ainda inclui `ME0` — precisa ser reescrita para uma instalação nova não reintroduzir a linha removida; (2) discrepância notada, mas não investigada, durante o diagnóstico: o `asset_source_id` usado pela execução de teste que apontava para `ME0` era diferente do `asset_source_id` usado por todos os registros existentes em `card_set_external_reference` — como `ME0` foi removida, essa instância específica ficou sem importância prática, mas a causa da discrepância em si (possível troca de identificador de `asset_source` em algum ponto do histórico) nunca foi explicada; baixa prioridade, registrada por transparência.

### Investigação de acompanhamento — identificador oficial real encontrado: `MEP`

**A pergunta deixada em aberto pela Migration `251` ("qual é, então, a fonte externa homologada para as cartas promocionais?") foi respondida por uma investigação real, cruzando TCGdex, TCGCodex e fontes de referência da comunidade.** As cartas promocionais de Mega Evolution não pertencem a `mee` (Energias) nem a nenhum dos Sets numerados — pertencem a um Set oficial próprio, publicado pela própria série: **`MEP` — "Mega Evolution Black Star Promos"** (TCGdex: `mep`; cartas como `mep-001`, `mep-023`, `mep-025`). Confirmação adicional real: cartas com esse código já referenciam Pokémon que só aparecem em coleções lançadas depois da `ME1` (ex.: `mep-034` "Mega Meganium ex", `mep-035` "Mega Emboar ex", `mep-036` "Mega Feraligatr ex") — prova de que `MEP` é o Set promocional de **toda a era Mega Evolution**, não uma sub-série vinculada apenas à `ME1`. Mesmo padrão já usado pela Pokémon Company em outras eras (ex.: `SVP` — "Scarlet & Violet Black Star Promos" — como Set irmão de `SV1`-`SV4`, não filho de nenhum deles).

**Confirmação real de que a arquitetura já estava correta**: Fabrício confirmou que o Set promocional sempre foi modelado corretamente como um `card_set` irmão de `ME1`-`ME4` dentro da Expansion `ME` (nunca como filho de `ME1`) — o mecanismo geral de `ADR-015` (Set do tipo `PROMO`, sem entidade separada) permanece válido e não muda. **O erro real estava apenas no código usado**: `ME0` era um identificador sintético, inventado internamente (convenção "código da Expansion + `0`"), sem correspondência em nenhuma fonte externa — por isso a Query `910` nunca conseguiu mapear `ME0` a nada real. O identificador correto é `MEP`. Ver `ADR-015`, revisão `1.4`, para a correção formal da convenção, e o novo `AP-018` (`02-architecture-principles.md`) para o princípio geral adotado a partir deste episódio: nunca inventar um código editorial quando um identificador oficial real existe ou pode ser pesquisado.

**Decisão adicional real: o catálogo será completado com `MEE` também, não apenas `MEP`.** Fabrício havia decidido anteriormente não cadastrar o Set de Energias (`mee` da TCGdex) por não ser relevante ao colecionador — reavaliou e decidiu fazer o trabalho completo: *"Vamos cadastrar também o set de energias da expansão Megaevolution [...] Vamos fazer o trabalho completo."* Critério adotado para o Catálogo Editorial a partir de agora: a única pergunta relevante para uma carta pertencer ao catálogo é **"foi oficialmente publicada?"** — não importa se é energia, promocional, treinador, comum ou rara, sem exceções por categoria. Com isso, a Expansion `ME` terá 7 Card Sets no total quando concluída: `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`/`MEP`/`MEE`.

**Nova convenção real de `release_order` quando existem Sets especiais**: dentro de uma mesma Expansion, o Set de Energia vem primeiro (`release_order = 1`), o Set de promocionais em seguida (`release_order = 2`), e os Sets regulares depois, na ordem oficial de lançamento (`3+`). Decisão explícita de Fabrício: *"Os card_set MEE e MEP devem ter o campo release_order 1 e 2 respectivamente. Vamos convencionar que todo Card_Set de Energia e Cartas Promocionais devem ser os primeiros de cada expansão."* Isso refina (não substitui) a convenção de `release_order = 1` já registrada em `ADR-015` para `PROMO` sozinho — ver `ADR-015`, revisão `1.5`.

**Plano real, ainda NÃO executado nesta revisão** (confirmar em ciclo futuro antes de tratar como concluído): auditoria estrutural do banco real (nomes de tabela, estrutura de `card_set`/`card_set_external_reference`) antes de qualquer escrita — nomes reais confirmados no singular (`expansion`, `card_set`, `card_set_external_reference`, não no plural como inicialmente presumido pela sessão pareada); ajustar `release_order` dos Sets existentes se necessário; inserir `MEE` e `MEP`; cadastrar `card_set_external_reference` para ambos; importar `card`/`card_variant`; gerar `card_external_reference`; importar imagens (inglês, depois português) pelo pipeline já existente (ver `06-pipeline-importacao.md`, "Guia Operacional"); validar a integridade completa do catálogo (checklist de estrutura/conteúdo/integridade, sem cartas sem variante, sem variante órfã, sem referência externa inválida, sem asset órfão) antes de considerar o módulo Catálogo Editorial oficialmente encerrado. Se **algum** desses passos ainda não tiver sido confirmado por execução real, tratar como planejado, não como concluído.

**Questão sobre "Expansion" vs. "Series"/"Era" — RESOLVIDA por decisão direta de Fabrício, dispensando a investigação**: a hipótese levantada na revisão anterior (se `Expansion` deveria ser reconcebida como um conceito de "Series"/"Era") foi descartada por Fabrício sem necessidade de pesquisa adicional: *"Na modelagem não alteramos a tabela expansion. Desconsidere qualquer informação sobre as possíveis entidades 'Series e Era'."* `Expansion` permanece exatamente como já modelada — nenhuma mudança de schema, nenhuma nova entidade.

### Migration `263`–`264` — Domínio `ENERGY` e reorganização de `release_order` (CONFIRMADAS EXECUTADAS)

**Primeira execução real do plano registrado na revisão anterior ("auditoria estrutural → ajustar `release_order` → inserir `MEE`/`MEP`") — apenas os dois primeiros passos, ainda sem inserir `MEE`/`MEP` em si.** Antes de qualquer `ALTER`/`UPDATE`, uma disciplina de auditoria foi seguida à risca, na ordem: (1) `information_schema.table_constraints`/`key_column_usage`, confirmando duas restrições reais sobre `card_set` — `uq_card_set_expansion_release_order` (`UNIQUE (expansion_id, release_order)`, já documentada) e `uq_card_set_expansion_code` (`UNIQUE (expansion_id, code)`, já documentada) — nenhuma novidade estrutural, apenas confirmação; (2) `pg_constraint`/`pg_get_constraintdef`, confirmando a definição exata de `ck_card_set_type` (`REGULAR`, `SPECIAL`, `PROMO` — `ENERGY` ainda **não** fazia parte do domínio) e de `ck_card_set_promo_size`. Só depois dessa dupla confirmação as alterações reais foram escritas — mesma disciplina de "auditar antes de alterar" já usada nas Migrations `251`/`122`.

**Observação real sobre a numeração de `release_order` herdada**: a sequência atual (`ME1`=2 … `ME4`=6) começa em `2`, não em `1`, porque a posição `1` já foi ocupada por `ME0` antes de sua remoção (Migration `251`) — os demais Sets nunca foram renumerados retroativamente. Essa observação de Fabrício explica a lacuna e confirma que a reorganização abaixo não está corrigindo um erro, apenas formalizando o espaço já implicitamente livre para os dois novos Sets especiais.

**Migration `263 - Add Energy to Card Set Type`**: amplia `ck_card_set_type` para incluir `ENERGY`, dentro de transação (`BEGIN`/`COMMIT`), preservando `REGULAR`/`SPECIAL`/`PROMO`. Não altera nenhum dado existente — apenas o domínio permitido.

```sql
BEGIN;

ALTER TABLE public.card_set
    DROP CONSTRAINT ck_card_set_type;

ALTER TABLE public.card_set
    ADD CONSTRAINT ck_card_set_type
    CHECK (
        set_type IN (
            'REGULAR',
            'SPECIAL',
            'PROMO',
            'ENERGY'
        )
    );

COMMIT;
```

Validação real, confirmada: `SELECT con.conname, pg_get_constraintdef(con.oid) FROM pg_constraint ... WHERE con.conname = 'ck_card_set_type';` retornou o domínio já incluindo `ENERGY`, junto com `REGULAR`/`SPECIAL`/`PROMO`. **Decisão consciente de não refatorar agora**: durante a auditoria, foi observado que os quatro valores não pertencem à mesma dimensão conceitual — `REGULAR`/`SPECIAL` descrevem a *natureza editorial* de um Set, enquanto `PROMO`/`ENERGY` descrevem a *natureza do conteúdo*. Uma separação em duas colunas foi cogitada e deliberadamente adiada por Fabrício (*"Não vamos refatorar agora [...] Introduzir uma nova dimensão agora aumentaria o escopo sem trazer benefício imediato"*), com a evolução mínima necessária (adicionar `ENERGY` ao mesmo domínio) escolhida para esta fase. Registrado como possível ADR futura em "Em Aberto" — ver abaixo.

**Migration `264 - Reorganize ME Release Order`**: reorganiza `release_order` dos cinco Card Sets existentes da Expansion `ME` (`ME1`=2→3, `ME2`=3→4, `ME2.5`=4→5, `ME3`=5→6, `ME4`=6→7), liberando as posições `1` e `2` para `MEE` e `MEP`, respectivamente — sem essa migration, `UPDATE card_set SET release_order = release_order + 1` violaria `uq_card_set_expansion_release_order` no meio da operação (cada linha tentaria ocupar a posição da seguinte antes desta ser liberada). Executada em duas fases dentro da mesma transação, técnica clássica de migração de valores únicos: (1) desloca temporariamente todos os cinco para valores altos (`+100`), fora de qualquer colisão; (2) define a sequência definitiva final por `CASE code`.

```sql
BEGIN;

-- Fase 1: move temporariamente para valores altos
UPDATE card_set
SET release_order = release_order + 100
WHERE expansion_id = (
    SELECT id FROM expansion WHERE code = 'ME'
);

-- Fase 2: define a nova sequência definitiva
UPDATE card_set
SET release_order =
CASE code
    WHEN 'ME1' THEN 3
    WHEN 'ME2' THEN 4
    WHEN 'ME2.5' THEN 5
    WHEN 'ME3' THEN 6
    WHEN 'ME4' THEN 7
END
WHERE expansion_id = (
    SELECT id FROM expansion WHERE code = 'ME'
);

COMMIT;
```

Validação real, confirmada: `SELECT code, release_order FROM card_set WHERE expansion_id = (...) ORDER BY release_order;` retornou exatamente `ME1`=3, `ME2`=4, `ME2.5`=5, `ME3`=6, `ME4`=7 — nenhum dado de carta/variante/asset foi tocado, apenas a coluna `release_order` de `card_set`.

**Estado real após as duas migrations**: `card_set.set_type` aceita `ENERGY`; posições `1`/`2` de `release_order` na Expansion `ME` estão livres; `MEE`/`MEP` **ainda não foram inseridos** — Fabrício optou por confirmar os dados editoriais oficiais reais de `MEE` (nome, código, data de lançamento, `base_set_size`, `total_set_size`) antes de escrever o `INSERT`, seguindo o mesmo `AP-018` (nunca inventar/presumir dado editorial) já aplicado à correção `ME0`→`MEP`. Pesquisa das fontes oficiais (TCGdex/Pokémon) planejada para um ciclo futuro, ainda **não realizada nesta revisão**.

> **Diário Técnico — Migrations 263–264 — Domínio ENERGY e reorganização de release_order**
> **Objetivo**: preparar `card_set` para receber `MEE` e `MEP` sem violar nenhuma constraint existente, seguindo a disciplina "auditar → entender restrições → evoluir o modelo → só então alterar dados".
> **Critério de aceite**: `ck_card_set_type` aceita `ENERGY`; `release_order` de `ME1`-`ME4` desloca para `3`-`7` sem violar `uq_card_set_expansion_release_order`; nenhum dado de outras tabelas alterado.
> **Resultado**: 🟩 Concluído. Ambas migrations confirmadas por validação real pós-execução.
> **Pendências descobertas**: (1) `MEE`/`MEP` ainda não cadastrados — aguardando confirmação de dados oficiais; (2) `ck_card_set_type` mistura duas dimensões conceituais distintas (natureza editorial vs. natureza do conteúdo) — refatoração para duas colunas deliberadamente adiada, registrada como possível ADR futura; (3) Query `820` v2.0 (Seed canônica) segue desatualizada quanto ao `release_order` real e não inclui `MEE`/`MEP` — precisa ser reescrita quando os dois Sets forem inseridos.

### Migration `265`–`268` — Cadastro real de `MEE`/`MEP` e referência externa do `MEP` (CONFIRMADAS EXECUTADAS)

**Antes de qualquer `INSERT`, uma auditoria real de estrutura confirmou que a arquitetura já existente (`asset_source`, `card_set_external_reference`) não precisava de nenhuma mudança para suportar múltiplas fontes editoriais.** Diagnóstico `07` (`information_schema.columns` de `card_set_external_reference` e `asset_source`) e Diagnóstico `08` (`SELECT * FROM asset_source`) confirmaram: `asset_source` já cadastra três fontes reais (`POKEMON_TCG_API`, `TCGDEX`, `MANUAL`), e `card_set_external_reference` já é desacoplada por `asset_source_id` — um mesmo `card_set` pode ter referências em múltiplas fontes sem qualquer alteração de schema. Nenhuma tabela ou coluna nova foi necessária.

**Novo padrão de processo, adotado a partir de um erro real encontrado nesta revisão**: uma primeira tentativa de consulta a `card_set_external_reference` referenciou uma coluna `external_code`, que não existe (`ERROR 42703: column cser.external_code does not exist`) — a coluna real é `external_set_id` (já documentada corretamente na seção "Card Set External Reference", abaixo, mas presumida incorretamente aqui de memória). A partir deste erro, Fabrício declarou uma nova disciplina permanente: **"Antes de escrever qualquer SQL para uma tabela, primeiro consultaremos sua estrutura."** — nunca mais assumir nomes de coluna de memória, sempre confirmar via `information_schema.columns` antes de qualquer `INSERT`/`UPDATE`/`SELECT` contra uma tabela.

**Convenção real de `external_set_id` reconfirmada por consulta** (já documentada na seção "Card Set External Reference", "Query 910"): `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` usam o identificador exato da TCGdex, com zero-padding (`me01`, `me02`, `me02.5`, `me03`, `me04`) — não os códigos internos do Project Mimikyu. Essa confirmação motivou a decisão de **não presumir** `mee`/`mep` como identificadores da TCGdex sem verificar — mesma lição do episódio `ME0`→`sv10pt5` (ver seção "Card Set External Reference", acima).

**`MEP` confirmado via pesquisa real na TCGdex**: identificador `mep`, nome oficial `MEP Black Star Promos`, data de lançamento `2025-09-26`. Contagem real de cartas registradas verificada diretamente no endpoint público (`https://api.tcgdex.net/v2/en/sets/mep`, acessado por Fabrício no navegador) — **descoberta real, não presumida**: o maior `localId` impresso é `080`, mas a numeração tem lacunas (salta de `045` para `064`, e de `071` para `074`), e o JSON da própria API relata `cardCount.total = 60` — a quantidade real de cartas efetivamente catalogadas é `60`, não `80` (o maior número impresso) nem `52` (uma primeira estimativa usada no cadastro inicial, corrigida ainda no mesmo ciclo).

**`MEE` — nenhuma fonte externa com metadados equivalentes foi encontrada nas fontes consultadas.** Decisão explícita, consistente com a arquitetura já existente: *"Não vamos assumir que o MEE possui referência externa. Se ele existir oficialmente: cadastraremos normalmente. Se ele não existir: o `card_set` continuará existindo; `card_set_external_reference` ficará vazio até surgir uma fonte oficial."* Os dados editoriais de `MEE` (nome oficial em português, código, tipo, data, tamanho) foram confirmados a partir de fontes oficiais da Pokémon (não a TCGdex) — suficientes para cadastrar o `card_set`, mas sem um identificador de fonte externa equivalente ao que `card_set_external_reference` espera.

**Migration `265 - Create Card Set MEE`**: insere o `card_set` `MEE`, idempotente via `NOT EXISTS`.

```sql
BEGIN;

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
    e.id,
    'MEE',
    'Cartas de Energia Básica Megaevolução',
    'ENERGY',
    1,
    DATE '2025-09-26',
    8,
    8
FROM public.expansion e
WHERE e.code = 'ME'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set cs
      WHERE cs.expansion_id = e.id
        AND cs.code = 'MEE'
  );

COMMIT;
```

Validação real confirmou a linha inserida (`release_order = 1`, `base_set_size = total_set_size = 8`). **Ajuste real posterior ao `INSERT`, confirmado por diálogo direto com Fabrício, mas sem a instrução `UPDATE` exata capturada nas informações recebidas**: o nome foi encurtado de `Cartas de Energia Básica Megaevolução` para **`Energia Básica Megaevolução`** — mesmo padrão de nomenclatura usado pela própria Pokémon para esse produto. `card_set.name` atual e confirmado de `MEE` é `Energia Básica Megaevolução`.

**Migration `266 - Create Card Set MEP`**: insere o `card_set` `MEP`, idempotente via `NOT EXISTS`. Nome e tamanho usados nesta primeira execução eram estimativas iniciais, corrigidas logo em seguida (`267`, abaixo).

```sql
BEGIN;

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
    e.id,
    'MEP',
    'Promos Estrela Negra Megaevolução',
    'PROMO',
    2,
    DATE '2025-09-26',
    52,
    52
FROM public.expansion e
WHERE e.code = 'ME'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set cs
      WHERE cs.expansion_id = e.id
        AND cs.code = 'MEP'
  );

COMMIT;
```

**Migration `267 - Fix Card Set MEP Size`**: corrige `base_set_size`/`total_set_size` de `52` (estimativa inicial) para `60` (contagem real confirmada via consulta direta ao endpoint da TCGdex, ver acima).

```sql
UPDATE public.card_set cs
SET
    base_set_size = 60,
    total_set_size = 60,
    updated_at = CURRENT_TIMESTAMP
FROM public.expansion e
WHERE e.id = cs.expansion_id
  AND e.code = 'ME'
  AND cs.code = 'MEP';
```

**Ajuste real de nome, análogo ao de `MEE`, também sem a instrução `UPDATE` exata capturada**: o nome inicial (`Promos Estrela Negra Megaevolução`, uma tradução criada durante o próprio cadastro) foi corrigido para o nome oficial exato da TCGdex, **`MEP Black Star Promos`** — confirmado explicitamente por Fabrício ("Veja que só ajustei o nome mais uma vez") e pela validação final. `card_set.name` atual e confirmado de `MEP` é `MEP Black Star Promos`. Este episódio motivou a extensão de `AP-018` para cobrir também `name`, não apenas `code` — ver `02-architecture-principles.md`, revisão `1.8`.

Validação final real, confirmada (`SELECT code, name, set_type, release_order, base_set_size, total_set_size FROM card_set WHERE code = 'MEP'`): `MEP` / `MEP Black Star Promos` / `PROMO` / `release_order = 2` / `base_set_size = total_set_size = 60`.

**Migration `268 - Create Card Set External Reference MEP`**: insere a referência externa de `MEP` na TCGdex, seguindo exatamente o padrão já usado para `ME1`-`ME4` (Query `910`).

```sql
BEGIN;

INSERT INTO public.card_set_external_reference (
    card_set_id,
    asset_source_id,
    external_set_id,
    source_url,
    metadata,
    is_active
)
SELECT
    cs.id,
    src.id,
    'mep',
    'https://api.tcgdex.net/v2/en/sets/mep',
    jsonb_build_object(
        'official_code', 'MEP',
        'external_name', 'MEP Black Star Promos',
        'release_date', '2025-09-26',
        'card_count_at_registration', 60
    ),
    TRUE
FROM public.card_set cs
INNER JOIN public.expansion e
    ON e.id = cs.expansion_id
CROSS JOIN public.asset_source src
WHERE e.code = 'ME'
  AND cs.code = 'MEP'
  AND src.code = 'TCGDEX'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set_external_reference cser
      WHERE cser.card_set_id = cs.id
        AND cser.asset_source_id = src.id
  );

COMMIT;
```

Validação real confirmou exatamente uma linha nova: `MEP` / `TCGDEX` / `mep` / `https://api.tcgdex.net/v2/en/sets/mep`, `metadata` com os quatro campos acima. **`MEE` deliberadamente sem `card_set_external_reference` nesta revisão** — comportamento intencional da arquitetura (a existência editorial de um Set é independente de ele já ter uma referência externa confirmada), não uma pendência esquecida; será criada quando/se uma fonte oficial equivalente for encontrada.

**Esclarecimento real sobre `ck_card_set_promo_size` (`base_set_size = total_set_size` para `PROMO`), motivado pela pergunta "o `MEP` deveria ter uma contagem base fixa?"**: a igualdade não representa um conjunto fechado — representa **uma fotografia da quantidade oficialmente conhecida no momento do cadastro/atualização**, para Sets (promocionais ou de energia) cujo conteúdo cresce ao longo do tempo. Consequência operacional real, ainda **não formalizada em `operations/`**: sempre que novas cartas de um Set `PROMO`/`ENERGY` forem catalogadas, `base_set_size`/`total_set_size` precisam ser atualizados manualmente como parte da mesma operação — candidato a uma futura seção de `operations/import-card-assets.md` ou de um novo artefato operacional dedicado a manutenção do catálogo, ainda não escrito.

**Estado real após esta revisão**: `MEE` e `MEP` existem como `card_set`, com dados editoriais confirmados; `MEP` tem referência externa TCGdex confirmada; `MEE` aguarda uma fonte externa equivalente. Nenhuma carta, variante, referência externa de carta ou imagem foi criada para `MEE`/`MEP` ainda — próximo passo planejado (não executado): validar o pipeline completo primeiro com `MEE` (menor Set, 8 cartas), depois repetir para `MEP`.

> **Diário Técnico — Migrations 265–268 — Cadastro de MEE/MEP**
> **Objetivo**: cadastrar `MEE`/`MEP` como `card_set` com dados editoriais reais (não presumidos), e a referência externa confirmada de `MEP`.
> **Critério de aceite**: `MEE`/`MEP` inseridos com dados confirmados por fonte oficial; `card_set_external_reference` de `MEP` confirmada; `MEE` sem referência externa inventada.
> **Resultado**: 🟩 Concluído. Ambos Sets confirmados por validação real; referência externa de `MEP` confirmada.
> **Pendências descobertas**: (1) as instruções `UPDATE` exatas que renomearam `MEE`/`MEP` para seus nomes finais não foram capturadas nas informações recebidas — o estado final foi confirmado por diálogo e por validação, mas o SQL literal do ajuste de nome não está registrado em `database/`; (2) discrepância real sinalizada em `AP-018` (revisão `1.8`): os nomes já cadastrados de `ME1`-`ME4`/`ME2.5` estão em português, inconsistente com o princípio de espelhar o nome exato da fonte oficial consultada (TCGdex, em inglês) — não resolvida unilateralmente; (3) `ck_card_set_promo_size`/`ENERGY` equivalente exige atualização manual de `base_set_size`/`total_set_size` a cada nova carta catalogada — regra operacional ainda não escrita em `operations/`; (4) Query `820` v2.0 (Seed canônica) segue sem refletir `MEE`/`MEP`/`release_order` real.

### Migration `269`–`271` — Padronização de `metadata`, referência externa do `MEE` e correção de data (CONFIRMADAS EXECUTADAS)

**Fabrício notou, por observação direta dos dados, uma inconsistência real entre o registro de `MEP` (com `metadata` descritiva) e todos os demais registros de `card_set_external_reference` (`metadata = {}`).** Avaliação: três dos quatro campos guardados em `metadata` de `MEP` (`official_code`, `external_name`, `release_date`) já existem como colunas relacionais em `card_set` (`code`, `name`, `release_date`, acessíveis por `JOIN`), e o quarto (`card_count_at_registration`) ficaria desatualizado rapidamente por natureza — `card_set.total_set_size` já é a fonte de verdade para a contagem atual (ver Migration `267`, acima). Recomendação: padronizar `MEP` para `metadata = {}`, mesmo padrão de todos os demais registros. **Nova regra permanente adotada**: `metadata` nunca deve duplicar um atributo já coberto por coluna relacional — existe apenas para propriedades específicas da fonte externa, sem equivalente relacional (formalizada em `STD-001-database-standards.md`, Seção 3, revisão `1.14`).

**Migration `269 - Fix Card Set External Reference MEP Metadata`**: zera `metadata` de `MEP`.

```sql
UPDATE public.card_set_external_reference cser
SET
    metadata = '{}'::jsonb,
    updated_at = CURRENT_TIMESTAMP
FROM public.card_set cs,
     public.asset_source src
WHERE cser.card_set_id = cs.id
  AND cser.asset_source_id = src.id
  AND cs.code = 'MEP'
  AND src.code = 'TCGDEX';
```

Validação real confirmou `metadata = {}` para `MEP`.

**`MEE` confirmado via pesquisa real na TCGdex** (`https://api.tcgdex.net/v2/en/sets/mee`, acessado diretamente por Fabrício): identificador `mee`, `cardCount.total = 8` (todas as 8 cartas oficiais, sem lacunas de numeração — `001` a `008`), abreviação oficial `MEE`, Set irmão de `ME1`-`ME4`/`ME2.5`/`MEP` dentro da Série `me`. **Divergência real de data encontrada**: a TCGdex registra `releaseDate: 2025-09-25`, um dia antes do valor já cadastrado em `card_set.release_date` (`2025-09-26`, herdado da Migration `265`). Sinalizada primeiro sem correção automática (*"Vamos preservar o cadastro atual até definirmos qual fonte será canônica para a data de lançamento"*); Fabrício confirmou diretamente em seguida que a data correta é `2025-09-25`, e a correção foi aplicada (Migration `271`, abaixo).

**Migration `270 - Create Card Set External Reference MEE`**: insere a referência externa de `MEE`, já com `metadata = {}` desde o início (aplicando a regra recém-adotada).

```sql
BEGIN;

INSERT INTO public.card_set_external_reference (
    card_set_id,
    asset_source_id,
    external_set_id,
    source_url,
    metadata,
    is_active
)
SELECT
    cs.id,
    src.id,
    'mee',
    'https://api.tcgdex.net/v2/en/sets/mee',
    '{}'::jsonb,
    TRUE
FROM public.card_set cs
INNER JOIN public.expansion e
    ON e.id = cs.expansion_id
CROSS JOIN public.asset_source src
WHERE e.code = 'ME'
  AND cs.code = 'MEE'
  AND src.code = 'TCGDEX'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set_external_reference cser
      WHERE cser.card_set_id = cs.id
        AND cser.asset_source_id = src.id
  );

COMMIT;
```

Validação real confirmou `MEE`/`TCGDEX`/`mee` e `MEP`/`TCGDEX`/`mep`, ambos com `metadata = {}` — camada `Expansion → Card Set → Card Set External Reference` concluída para os dois novos Sets.

**Migration `271 - Fix Card Set MEE Release Date`**: corrige `card_set.release_date` de `MEE` de `2025-09-26` para `2025-09-25`, conforme confirmado pela TCGdex e por Fabrício.

```sql
UPDATE public.card_set cs
SET
    release_date = DATE '2025-09-25',
    updated_at = CURRENT_TIMESTAMP
FROM public.expansion e
WHERE e.id = cs.expansion_id
  AND e.code = 'ME'
  AND cs.code = 'MEE';
```

Validação real confirmou: `MEE` / `Energia Básica Megaevolução` / `2025-09-25`.

**Antes de qualquer `INSERT` em `card` para `MEE`/`MEP`, a estrutura real da tabela foi auditada (Diagnósticos `09`/`10` — `information_schema.columns` e `pg_constraint`), reaplicando a disciplina "consultar a estrutura antes de escrever SQL" adotada no batch anterior.** A auditoria confirmou os atributos obrigatórios já documentados (`card_set_id`, `rarity_id`, `category_id`, `collector_number`, `collector_total`, `collector_order`, `name`) — nenhuma divergência estrutural encontrada.

**Decisão real de estratégia para popular as cartas de `MEE`/`MEP`, ainda NÃO executada**: em vez de novos `INSERT`s avulsos (padrão `ALTERAÇÃO NN` usado até aqui para `card_set`/`card_set_external_reference`), Fabrício determinou reaproveitar e evoluir a própria Query canônica de cartas: *"Vamos revisar a query 840 [...] com o cuidado de manter o padrão que usamos na primeira carga [...] mantenha os dados como na primeira carga acrescentando as cartas dos dois novos sets."* Um arquivo real (`840 - Seed Card.txt`) com o conteúdo atual e completo da Query `840` foi fornecido diretamente por Fabrício, revelando que ela já está oficialmente na `Versão 2.1`, Status `CANÔNICA` — decisão consciente de **não** recriá-la do zero como uma nova "v2.0", preservando o histórico de versões já existente (mesmo Princípio da Fonte Canônica, aplicado à evolução, não à substituição).

**Plano real para `840 - Seed Card`, Versão `2.2` (ainda NÃO executado)**, quatro alterações sobre a `2.1` existente, preservando integralmente `ME1`-`ME4`/`ME2.5`:

1. A validação de Card Sets esperados passa a incluir `MEE`/`MEP`, além dos cinco já existentes.
2. As quantidades canônicas por Set são atualizadas: `MEE` `8`/`8`, `MEP` `60`/`60`, mantendo as demais inalteradas (`ME1` `132`/`188`, etc.).
3. O CTE de origem (`source_card`, com `VALUES`) recebe os registros das `8` cartas de `MEE` e das `60` cartas atualmente catalogadas de `MEP`, no mesmo formato de escrita já usado para as 5 coleções existentes.
4. A validação final passa a esperar `927` cartas no total (`859 + 8 + 60`), em vez de `859`.

**Decidido explicitamente: não criar uma Seed complementar (`841`)** — `840` continua sendo a única fonte oficial e completa de todas as cartas da Expansion `ME`, mesmo padrão de "fonte canônica única" já usado para `card_set`/`820`.

> **Diário Técnico — Migrations 269–271 — Padronização de metadata, referência externa do MEE, correção de data**
> **Objetivo**: eliminar a inconsistência de `metadata` entre `MEP` e os demais registros; cadastrar a referência externa confirmada de `MEE`; corrigir a data de lançamento de `MEE` conforme a TCGdex.
> **Critério de aceite**: `metadata` de `MEP` zerada; `card_set_external_reference` de `MEE` confirmada com `metadata = {}`; `release_date` de `MEE` = `2025-09-25`.
> **Resultado**: 🟩 Concluído. Todas as três migrations confirmadas por validação real.
> **Pendências descobertas**: (1) `840 - Seed Card` v2.2 (MEE + MEP) planejada em detalhe, mas **ainda não escrita nem executada** — nenhuma carta de `MEE`/`MEP` existe em `card` até esta revisão; (2) mesma pendência se propaga a `card_variant`, `card_external_reference` e `card_asset` — nada disso pode começar antes de `840` v2.2.

## Logo do Card Set (`logo_storage_path`)

**CONFIRMADO EXECUTADO (2026-07-26).** `card_set` ganhou a coluna `logo_storage_path TEXT NULL`, guardando o caminho relativo (nunca uma URL completa) da logo oficial do Set dentro do bucket privado dedicado `card-set-logo`. Motivada pela retomada do frontend do Catálogo Editorial: a tela Visão Geral precisa exibir a logo de cada Set, e não havia nenhuma referência para ela no modelo. Decisão de Fabrício: nenhuma tabela genérica de assets — a necessidade aprovada é uma única logo principal por Card Set, resolvida com uma coluna simples, mesmo padrão de simplicidade inicial (AP-004) já aplicado outras vezes no projeto.

```sql
ALTER TABLE public.card_set
    ADD COLUMN logo_storage_path TEXT NULL;

ALTER TABLE public.card_set
    ADD CONSTRAINT ck_card_set_logo_storage_path_not_url
    CHECK (
        logo_storage_path IS NULL
        OR logo_storage_path !~* '^[a-z][a-z0-9+.-]*://'
    );
```

`NULL` representa um Card Set ainda sem logo cadastrada — o frontend deve prever um fallback visual (ex.: iniciais/placeholder), não um erro. Nenhuma política de `UPDATE` foi criada em `card_set` para este campo: toda escrita passa pela função administrativa `admin_set_card_set_logo()` (ver seção "Autorização do Catálogo Editorial", abaixo), restrita a administradores e ao próprio campo. Convenção de caminho, espelhando o padrão já adotado para Card Asset (`pokemon/{collection-code}/{language-code}/{card-number}/front.png`, ver seção "Arquitetura de Armazenamento" acima): `{game_code}/{card_set_code}.png` — ex.: `pokemon/me1.png`, `pokemon/me2.5.png`. Leitura ocorre por URL assinada (`createSignedUrl()`), nunca `getPublicUrl()`, já que o bucket é privado (ver "Autorização do Catálogo Editorial"). Decisão formalizada em `ADR-022`. Confirmado via `information_schema.columns`/`pg_constraint`. Arquivo em `database/migrations/273_add_card_set_logo_column.sql`; `database/schema/120_create_card_set_table.sql` atualizado para v2.1 (Princípio da Fonte Canônica).

---

