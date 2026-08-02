# Modelo de Dados

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados |
| **Arquivo** | `docs/05-modelo-de-dados.md` |
| **Versão** | 1.28 |
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

> **Nota sobre o Status "Em elaboração" (2026-07-30).** A maior parte do Catálogo Editorial (Game até Card Variant) está executada e confirmada no Supabase. O que mantém este documento em elaboração: `Card Variant` para `MEE`/`MEP` ainda não executado (ver seção "Card", "Ressalva importante"); as seções `Card Translation`, `Collection Item` e `Collection`/`Collection Entry` seguem como "Documentação pendente" — ainda não iniciadas, aguardando a Sub-Fase 2 (Coleções) do roadmap. Não é uma promoção de status.

> **Nota importante (retrato histórico, não a contagem atual):** no início desta fase de consolidação documental, o banco físico do Project Mimikyu (Supabase, projeto `mimikyu-core`) já possuía 17 tabelas com carga inicial de dados — as tabelas originais do Catálogo Editorial (`game` até `asset_import_failure`; ver "Status Atual do Projeto" em `README.md`). Para a maioria das entidades a seguir, o roteiro abaixo não representa uma sequência de criação do zero — representa a documentação retroativa da estrutura já existente, confirmada contra o banco real à medida que os lotes históricos forem processados. Game foi a exceção: sua tabela foi recriada/validada junto com o restante desta documentação, e por isso já segue o roteiro completo do início ao fim. **Este número (17) descreve aquele momento específico, não o total atual do schema `public`** — módulos adicionados depois (Identidade e Acesso, Administração, auditoria do Catálogo Editorial) elevaram o total para `22` tabelas (confirmado em 2026-07-30). As demais menções a "17 tabelas" ao longo deste documento (Revision History e notas de descoberta) preservam o mesmo sentido histórico e não foram alteradas.

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

# Rarity (Raridade)

Status: **Encerrada.** Tabela (`130` v1.1, já com `symbol_code`), trigger (`131`, inalterado), seed (`830` v1.2, incluindo a raridade `PROMO`) e validação (`930` v1.2) executados e confirmados no Supabase. `PROMO` foi confirmada como uma décima raridade oficial do Pokémon TCG (não uma criação do projeto) — ver "Descoberta — PROMO é uma Raridade Oficial", abaixo. Fabrício: "Agora sim podemos dizer que a entidade Rarity está encerrada." **Sem pendências.**

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

**symbol_code** — Identificador técnico e estável do símbolo visual oficial da raridade, conforme apresentado na legenda oficial do catálogo (ex.: `BLACK_STAR`, `GOLD_DOUBLE_STAR`). **Não é o próprio caractere/emoji** (ex. `★`) nem uma URL de imagem — é um identificador textual que a camada de apresentação (aplicação web, ver `ADR-019-web-application-as-primary-interface.md`) poderá futuramente converter em SVG, PNG, componente visual ou símbolo via CSS. Ver "Evolução do Modelo — Campo `symbol_code`", abaixo, para o raciocínio completo por trás desta decisão.

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

*Esta é a Query como foi executada pela primeira vez, sem `symbol_code` (Status `MIGRATION` retroativo — superada pela Versão Canônica 1.1, abaixo, mas preservada aqui para rastreabilidade, seguindo o Princípio da Fonte Canônica de STD-001, Seção 10).*

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

## Modelo Físico — Versão Canônica (1.1)

Status `CANÔNICA` (STD-001, Seção 10 — Princípio da Fonte Canônica): esta é a versão que uma **instalação nova** deve executar — já nasce com `symbol_code`, incorporando o que foi aplicado ao banco atual pela Query temporária de ajuste (ver "Evolução do Modelo — Campo `symbol_code`", abaixo). **Diferente do caso do Card Set, aqui a versão canônica já reflete o estado real do banco físico** — a Query temporária confirmou a execução real antes desta consolidação. Texto verbatim fornecido por Fabrício.

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
    CONSTRAINT ck_rarity_name_not_blank
        CHECK (btrim(name) <> ''),
    CONSTRAINT ck_rarity_symbol_code_format
        CHECK (symbol_code ~ '^[A-Z0-9][A-Z0-9_]*$'),
    CONSTRAINT ck_rarity_display_order_positive
        CHECK (display_order > 0)
);

ALTER TABLE public.rarity
ENABLE ROW LEVEL SECURITY;
```

Query: `130 - Create Rarity Table` (v1.1, `CANÔNICA`). Representa o estado estrutural definitivo para novas instalações e o estado real do banco atual. **Não precisa ser executada novamente no banco atual** — a tabela já existe com esta estrutura, aplicada pela Query temporária de ajuste; esta atualização serve para manter a definição canônica correta para futuras instalações do zero.

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

*Esta é a Seed como foi executada pela primeira vez, sem `symbol_code` (Status `MIGRATION` retroativo — superada pela Versão Canônica 1.1, abaixo, mas preservada aqui para rastreabilidade).*

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

### Seed — Versão Canônica (1.1)

Status `CANÔNICA`: inclui `symbol_code` para cada uma das nove raridades, mapeado a partir das legendas oficiais de verificação (fonte: `assets/reference-sources/`, especificamente `P10346_ME01_Card_List_PTBR.pdf` e `ME02pt5_Card_List_PTBR.pdf` para o símbolo específico de `MEGA_ATTACK_RARE`). Texto verbatim fornecido por Fabrício:

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
        (
            v_game_id,
            'COMMON',
            'Comum',
            'BLACK_CIRCLE',
            1
        ),
        (
            v_game_id,
            'UNCOMMON',
            'Incomum',
            'BLACK_DIAMOND',
            2
        ),
        (
            v_game_id,
            'RARE',
            'Rara',
            'BLACK_STAR',
            3
        ),
        (
            v_game_id,
            'DOUBLE_RARE',
            'Rara Dupla',
            'BLACK_DOUBLE_STAR',
            4
        ),
        (
            v_game_id,
            'ULTRA_RARE',
            'Rara Ultra',
            'SILVER_DOUBLE_STAR',
            5
        ),
        (
            v_game_id,
            'MEGA_ATTACK_RARE',
            'Rara Mega Ataque',
            'MEGA_ATTACK',
            6
        ),
        (
            v_game_id,
            'ILLUSTRATION_RARE',
            'Ilustração Rara',
            'GOLD_STAR',
            7
        ),
        (
            v_game_id,
            'SPECIAL_ILLUSTRATION_RARE',
            'Ilustração Rara Especial',
            'GOLD_DOUBLE_STAR',
            8
        ),
        (
            v_game_id,
            'MEGA_HYPER_RARE',
            'Mega Rara Hiper',
            'GOLD_DIAMOND',
            9
        )
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        symbol_code = EXCLUDED.symbol_code,
        display_order = EXCLUDED.display_order;
END;
$$;
```

Query: `830 - Seed Rarity` (v1.1, histórico). Superada pela Versão Canônica 1.2, abaixo, que incorpora `PROMO`.

**Nota importante sobre a identidade visual:** um mesmo elemento gráfico base (ex.: estrela) pode representar raridades diferentes — `RARE` e `ILLUSTRATION_RARE` usam estrela, mas não são visualmente equivalentes (cor/estilo diferentes: estrela preta vs. estrela dourada). O `symbol_code` captura os três elementos observados na legenda oficial — formato (círculo, losango, estrela), quantidade (simples, dupla) e estilo/cor (preto, prateado, dourado, multicolorido) — evitando que dois `symbol_code` diferentes sejam confundidos apenas por compartilharem o mesmo formato-base.

### Seed — Versão Canônica (1.2)

Status `CANÔNICA`: inclui a raridade `PROMO` (código `PROMO`, símbolo `BLACK_STAR`, compartilhado com `RARE`), deslocando as demais raridades uma posição na ordem de exibição. **Executada e confirmada por Fabrício** ("Tudo feito com sucesso. Vamos avançar!"). Texto verbatim:

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
        (
            v_game_id,
            'COMMON',
            'Comum',
            'BLACK_CIRCLE',
            1
        ),
        (
            v_game_id,
            'UNCOMMON',
            'Incomum',
            'BLACK_DIAMOND',
            2
        ),
        (
            v_game_id,
            'RARE',
            'Rara',
            'BLACK_STAR',
            3
        ),
        (
            v_game_id,
            'PROMO',
            'Promo',
            'BLACK_STAR',
            4
        ),
        (
            v_game_id,
            'DOUBLE_RARE',
            'Rara Dupla',
            'BLACK_DOUBLE_STAR',
            5
        ),
        (
            v_game_id,
            'ULTRA_RARE',
            'Rara Ultra',
            'SILVER_DOUBLE_STAR',
            6
        ),
        (
            v_game_id,
            'MEGA_ATTACK_RARE',
            'Rara Mega Ataque',
            'MEGA_ATTACK',
            7
        ),
        (
            v_game_id,
            'ILLUSTRATION_RARE',
            'Ilustração Rara',
            'GOLD_STAR',
            8
        ),
        (
            v_game_id,
            'SPECIAL_ILLUSTRATION_RARE',
            'Ilustração Rara Especial',
            'GOLD_DOUBLE_STAR',
            9
        ),
        (
            v_game_id,
            'MEGA_HYPER_RARE',
            'Mega Rara Hiper',
            'GOLD_DIAMOND',
            10
        )
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        symbol_code = EXCLUDED.symbol_code,
        display_order = EXCLUDED.display_order;
END;
$$;
```

Query: `830 - Seed Rarity` (v1.2, `CANÔNICA`). **Executada com sucesso** — 10 raridades persistidas, incluindo `PROMO`.

### Validação — Versão 1.0 (histórico)

*Versão executada e confirmada antes da adição de `symbol_code` — superada pela Versão Canônica 1.1, abaixo.*

Query: `930 - Validate Rarity` (v1.0). **Resultado confirmado por Fabrício ("Executada com sucesso").** As mesmas 7 subconsultas da versão 1.0 do modelo físico (sem `symbol_code`) — ver o histórico de revisão 0.18 deste documento para o SQL completo, se necessário.

### Validação — Versão Canônica (1.1)

Versão significativamente ampliada em relação ao rascunho anterior (7 subconsultas) — agora com 12 subconsultas, incluindo uma verificação linha-a-linha contra os valores canônicos esperados (útil para detectar drift entre o que está documentado e o que está persistido) e uma verificação de raridades não previstas. Texto verbatim fornecido por Fabrício:

```sql
-- ============================================================================
-- 1. Relação completa das raridades
-- Resultado esperado: 9 registros do Game POKEMON
-- ============================================================================
SELECT
    g.code AS game_code,
    r.display_order,
    r.code AS rarity_code,
    r.name AS rarity_name,
    r.symbol_code,
    r.created_at,
    r.updated_at
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
ORDER BY
    g.code,
    r.display_order,
    r.code;

-- ============================================================================
-- 2. Quantidade de raridades por Game
-- Resultado esperado para POKEMON: 9
-- ============================================================================
SELECT
    g.code AS game_code,
    COUNT(*) AS total_rarities
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
GROUP BY
    g.code
ORDER BY
    g.code;

-- ============================================================================
-- 3. Verificar códigos duplicados dentro do mesmo Game
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    g.code AS game_code,
    r.code AS rarity_code,
    COUNT(*) AS duplicate_count
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
GROUP BY
    g.code,
    r.code
HAVING COUNT(*) > 1;

-- ============================================================================
-- 4. Verificar ordens de exibição inválidas
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    display_order
FROM public.rarity
WHERE display_order <= 0;

-- ============================================================================
-- 5. Verificar nomes vazios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    name
FROM public.rarity
WHERE btrim(name) = '';

-- ============================================================================
-- 6. Verificar códigos de raridade inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code
FROM public.rarity
WHERE code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- ============================================================================
-- 7. Verificar símbolos nulos ou vazios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    symbol_code
FROM public.rarity
WHERE symbol_code IS NULL
   OR btrim(symbol_code) = '';

-- ============================================================================
-- 8. Verificar códigos de símbolo inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    symbol_code
FROM public.rarity
WHERE symbol_code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- ============================================================================
-- 9. Conferir os dados canônicos do Pokémon TCG
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_rarity (
    code,
    name,
    symbol_code,
    display_order
) AS (
    VALUES
        ('COMMON',                    'Comum',                     'BLACK_CIRCLE',       1),
        ('UNCOMMON',                  'Incomum',                   'BLACK_DIAMOND',      2),
        ('RARE',                      'Rara',                      'BLACK_STAR',         3),
        ('DOUBLE_RARE',               'Rara Dupla',                'BLACK_DOUBLE_STAR',  4),
        ('ULTRA_RARE',                'Rara Ultra',                'SILVER_DOUBLE_STAR', 5),
        ('MEGA_ATTACK_RARE',          'Rara Mega Ataque',          'MEGA_ATTACK',        6),
        ('ILLUSTRATION_RARE',         'Ilustração Rara',           'GOLD_STAR',          7),
        ('SPECIAL_ILLUSTRATION_RARE', 'Ilustração Rara Especial',  'GOLD_DOUBLE_STAR',   8),
        ('MEGA_HYPER_RARE',           'Mega Rara Hiper',           'GOLD_DIAMOND',       9)
)
SELECT
    e.code AS expected_code,
    e.name AS expected_name,
    e.symbol_code AS expected_symbol_code,
    e.display_order AS expected_display_order,
    r.name AS persisted_name,
    r.symbol_code AS persisted_symbol_code,
    r.display_order AS persisted_display_order
FROM expected_rarity AS e
LEFT JOIN public.game AS g
    ON g.code = 'POKEMON'
LEFT JOIN public.rarity AS r
    ON r.game_id = g.id
   AND r.code = e.code
WHERE r.id IS NULL
   OR r.name <> e.name
   OR r.symbol_code <> e.symbol_code
   OR r.display_order <> e.display_order;

-- ============================================================================
-- 10. Verificar raridades adicionais não previstas para o Game POKEMON
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_rarity (code) AS (
    VALUES
        ('COMMON'),
        ('UNCOMMON'),
        ('RARE'),
        ('DOUBLE_RARE'),
        ('ULTRA_RARE'),
        ('MEGA_ATTACK_RARE'),
        ('ILLUSTRATION_RARE'),
        ('SPECIAL_ILLUSTRATION_RARE'),
        ('MEGA_HYPER_RARE')
)
SELECT
    r.code,
    r.name,
    r.symbol_code,
    r.display_order
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
LEFT JOIN expected_rarity AS e
    ON e.code = r.code
WHERE g.code = 'POKEMON'
  AND e.code IS NULL;

-- ============================================================================
-- 11. Verificar a existência do trigger updated_at
-- Resultado esperado: 1 registro
-- ============================================================================
SELECT
    event_object_schema,
    event_object_table,
    trigger_name,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'rarity'
  AND trigger_name = 'trg_rarity_set_updated_at';

-- ============================================================================
-- 12. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    code,
    created_at,
    updated_at
FROM public.rarity
WHERE created_at IS NULL
   OR updated_at IS NULL;
```

Query: `930 - Validate Rarity` (v1.1, histórico). Superada pela Versão Canônica 1.2, abaixo, que valida 10 raridades (incluindo `PROMO`) em vez de 9.

### Validação — Versão Canônica (1.2)

Ampliada para validar 10 raridades e adiciona uma nova subconsulta (11) que confirma explicitamente quais raridades compartilham o símbolo `BLACK_STAR` (`RARE` e `PROMO`) — útil como evidência de que a decisão de manter `symbol_code` fora da chave de unicidade continua correta. **Executada e confirmada por Fabrício.** Texto verbatim:

```sql
-- ============================================================================
-- 1. Relação completa das raridades
-- Resultado esperado: 10 registros do Game POKEMON
-- ============================================================================
SELECT
    g.code AS game_code,
    r.display_order,
    r.code AS rarity_code,
    r.name AS rarity_name,
    r.symbol_code,
    r.created_at,
    r.updated_at
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
ORDER BY
    g.code,
    r.display_order,
    r.code;

-- ============================================================================
-- 2. Quantidade de raridades por Game
-- Resultado esperado para POKEMON: 10
-- ============================================================================
SELECT
    g.code AS game_code,
    COUNT(*) AS total_rarities
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
GROUP BY
    g.code
ORDER BY
    g.code;

-- ============================================================================
-- 3. Verificar códigos duplicados dentro do mesmo Game
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    g.code AS game_code,
    r.code AS rarity_code,
    COUNT(*) AS duplicate_count
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
GROUP BY
    g.code,
    r.code
HAVING COUNT(*) > 1;

-- ============================================================================
-- 4. Verificar ordens de exibição inválidas
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    display_order
FROM public.rarity
WHERE display_order <= 0;

-- ============================================================================
-- 5. Verificar nomes vazios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    name
FROM public.rarity
WHERE btrim(name) = '';

-- ============================================================================
-- 6. Verificar códigos de raridade inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code
FROM public.rarity
WHERE code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- ============================================================================
-- 7. Verificar símbolos nulos ou vazios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    symbol_code
FROM public.rarity
WHERE symbol_code IS NULL
   OR btrim(symbol_code) = '';

-- ============================================================================
-- 8. Verificar códigos de símbolo inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    symbol_code
FROM public.rarity
WHERE symbol_code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- ============================================================================
-- 9. Conferir os dados canônicos do Pokémon TCG
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_rarity (
    code,
    name,
    symbol_code,
    display_order
) AS (
    VALUES
        ('COMMON',                    'Comum',                    'BLACK_CIRCLE',       1),
        ('UNCOMMON',                  'Incomum',                  'BLACK_DIAMOND',      2),
        ('RARE',                      'Rara',                     'BLACK_STAR',         3),
        ('PROMO',                     'Promo',                    'BLACK_STAR',         4),
        ('DOUBLE_RARE',               'Rara Dupla',               'BLACK_DOUBLE_STAR',  5),
        ('ULTRA_RARE',                'Rara Ultra',               'SILVER_DOUBLE_STAR', 6),
        ('MEGA_ATTACK_RARE',          'Rara Mega Ataque',         'MEGA_ATTACK',        7),
        ('ILLUSTRATION_RARE',         'Ilustração Rara',          'GOLD_STAR',          8),
        ('SPECIAL_ILLUSTRATION_RARE', 'Ilustração Rara Especial', 'GOLD_DOUBLE_STAR',   9),
        ('MEGA_HYPER_RARE',           'Mega Rara Hiper',          'GOLD_DIAMOND',      10)
)
SELECT
    e.code AS expected_code,
    e.name AS expected_name,
    e.symbol_code AS expected_symbol_code,
    e.display_order AS expected_display_order,
    r.name AS persisted_name,
    r.symbol_code AS persisted_symbol_code,
    r.display_order AS persisted_display_order
FROM expected_rarity AS e
LEFT JOIN public.game AS g
    ON g.code = 'POKEMON'
LEFT JOIN public.rarity AS r
    ON r.game_id = g.id
   AND r.code = e.code
WHERE r.id IS NULL
   OR r.name <> e.name
   OR r.symbol_code <> e.symbol_code
   OR r.display_order <> e.display_order;

-- ============================================================================
-- 10. Verificar raridades adicionais não previstas para o Game POKEMON
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_rarity (code) AS (
    VALUES
        ('COMMON'),
        ('UNCOMMON'),
        ('RARE'),
        ('PROMO'),
        ('DOUBLE_RARE'),
        ('ULTRA_RARE'),
        ('MEGA_ATTACK_RARE'),
        ('ILLUSTRATION_RARE'),
        ('SPECIAL_ILLUSTRATION_RARE'),
        ('MEGA_HYPER_RARE')
)
SELECT
    r.code,
    r.name,
    r.symbol_code,
    r.display_order
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
LEFT JOIN expected_rarity AS e
    ON e.code = r.code
WHERE g.code = 'POKEMON'
  AND e.code IS NULL;

-- ============================================================================
-- 11. Verificar raridades que compartilham o símbolo BLACK_STAR
-- Resultado esperado:
-- RARE
-- PROMO
-- ============================================================================
SELECT
    r.code,
    r.name,
    r.symbol_code,
    r.display_order
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
WHERE g.code = 'POKEMON'
  AND r.symbol_code = 'BLACK_STAR'
ORDER BY
    r.display_order,
    r.code;

-- ============================================================================
-- 12. Verificar a existência do trigger updated_at
-- Resultado esperado: 1 registro
-- ============================================================================
SELECT
    event_object_schema,
    event_object_table,
    trigger_name,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'rarity'
  AND trigger_name = 'trg_rarity_set_updated_at';

-- ============================================================================
-- 13. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    code,
    created_at,
    updated_at
FROM public.rarity
WHERE created_at IS NULL
   OR updated_at IS NULL;
```

Query: `930 - Validate Rarity` (v1.2, `CANÔNICA`). **Resultado confirmado por Fabrício** ("Tudo feito com sucesso. Vamos avançar!"): consulta 1 → 10 raridades; consulta 2 → `POKEMON = 10`; consultas 3 a 10 → nenhum registro; consulta 11 → `RARE` e `PROMO` (únicas com `BLACK_STAR`); consulta 12 → um trigger; consulta 13 → nenhum registro. **Com esse resultado, o pacote técnico da entidade Rarity está definitivamente concluído.**

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

**Como a mudança foi aplicada:** por uma Query de ajuste operacional, explicitamente marcada como `Status: TEMPORÁRIA` (não numerada, não canônica) — adicionou a coluna, preencheu os valores reais por `CASE`, tornou a coluna `NOT NULL` e criou a constraint de formato, tudo dentro de uma transação (`BEGIN`/`COMMIT`). Confirmada por Fabrício como executada com sucesso, com o resultado final conferido (9 linhas, `symbol_code` preenchido conforme a tabela acima). **Esta Query temporária não foi copiada para `database/`** — por decisão explícita de Fabrício ("A Query temporária usada para modificar o banco atual pode ser descartada após confirmarmos as versões canônicas"), ela existe apenas como registro narrativo aqui; as Queries `130`, `830` e `930` foram reescritas em lugar (Versão 1.1, `CANÔNICA` — texto verbatim fornecido por Fabrício, corrigindo o rótulo "2.0" usado erroneamente na revisão anterior deste documento, que era uma reconstrução própria, não o texto real) para que uma instalação nova já nasça com `symbol_code`, sem depender de um ajuste posterior — mesmo princípio já aplicado ao Card Set (`120`/`820`), mas aqui com uma diferença importante: a consolidação canônica já reflete o estado real do banco físico, não apenas uma correção de repositório pendente de confirmação.

`131 - Create Rarity Trigger` foi explicitamente confirmada como **não precisando de alteração** — o trigger de `updated_at` opera sobre a linha inteira, independente de quais colunas existem.

**Ideia para o futuro, registrada mas não adotada agora:** uma tabela de domínio própria `symbol` (`id, code, description, svg_url, png_url, sort_order`), com `rarity.symbol_id` substituindo `rarity.symbol_code`. Motivo para não adotar: hoje existe exatamente um símbolo por raridade — criar a tabela agora aumentaria a complexidade sem trazer benefício imediato. Motivo para registrar: mostra que o modelo é evolutivo sem exigir refatorações radicais, caso essa relação deixe de ser 1-para-1 no futuro (ex.: dois estilos de arte para o mesmo símbolo).

### Descoberta — PROMO é uma Raridade Oficial (confirmada e executada)

Ao revisar o modelo já com `symbol_code`, Fabrício lembrou de um detalhe que altera a compreensão da entidade Rarity: *"Toda carta do set promocional terá a raridade PROMO, com símbolo Black Star."* Isso revela que `PROMO` **não é uma raridade "inventada" para o Set promocional** — é uma raridade oficial do próprio Pokémon TCG, confirmada com exemplos concretos de diferentes eras/mercados de promocionais:

| Set | Carta | Raridade | Símbolo |
|-----|-------|----------|---------|
| Promo SVP | Pikachu SVP001 | `PROMO` | ★ preta |
| Promo SM | SM01 | `PROMO` | ★ preta |
| Promo SWSH | SWSH001 | `PROMO` | ★ preta |

**Consequência importante, já observada e usada para validar uma decisão anterior:** `PROMO` e `RARE` compartilham exatamente o mesmo `symbol_code` (`BLACK_STAR`). Isso confirma que `symbol_code` está corretamente **fora** da chave de unicidade de Rarity (`UNIQUE (game_id, code)`, nunca `(game_id, symbol_code)`) — é um atributo puramente descritivo, não identificador. Nenhuma alteração estrutural é necessária por causa disso; a tabela já suporta múltiplas raridades com o mesmo símbolo.

**Ordem de exibição decidida para a raridade `PROMO`:** inserida logo após `RARE` (display_order `4`), com as demais raridades deslocadas uma posição — `PROMO` é entendida como uma categoria paralela a `RARE`, não uma raridade "mais alta" na escala:

| `display_order` | `code` | `symbol_code` |
|------------------|--------|----------------|
| 1 | `COMMON` | `BLACK_CIRCLE` |
| 2 | `UNCOMMON` | `BLACK_DIAMOND` |
| 3 | `RARE` | `BLACK_STAR` |
| 4 | `PROMO` | `BLACK_STAR` |
| 5 | `DOUBLE_RARE` | `BLACK_DOUBLE_STAR` |
| 6 | `ULTRA_RARE` | `SILVER_DOUBLE_STAR` |
| 7 | `MEGA_ATTACK_RARE` | `MEGA_ATTACK` |
| 8 | `ILLUSTRATION_RARE` | `GOLD_STAR` |
| 9 | `SPECIAL_ILLUSTRATION_RARE` | `GOLD_DOUBLE_STAR` |
| 10 | `MEGA_HYPER_RARE` | `GOLD_DIAMOND` |

**Consequência arquitetural para a futura entidade Card, explicitamente sinalizada:** uma carta promocional não deve ser identificada apenas pela sua raridade — ela também precisa pertencer a um Card Set do tipo `PROMO` (ex.: `SVP`, `SWSH`, `SM`). `card_set.set_type = 'PROMO'` identifica que a carta pertence a um conjunto promocional; `rarity.code = 'PROMO'` identifica a raridade oficial daquela carta específica. **São dois conceitos independentes e complementares**, não um substituto do outro — ver também a seção Set, acima ("Card Set Promocional — Executado"), e a seção Card, abaixo, que precisará contemplar essa dupla marcação quando `140` for modelada.

**Sequência de atualização executada, conforme decidido por Fabrício:** *"Vamos seguir com esta sequência agora: Atualizar a Query 830 para incluir PROMO. Atualizar a Query 930 para validar as 10 raridades canônicas em vez de 9. Manter a Query 130 como está, pois ela já suporta essa inclusão sem alterações estruturais."* `130 - Create Rarity Table` (v1.1) permaneceu como está — nenhuma constraint de `code` restringe os valores possíveis, então adicionar `PROMO` foi puramente uma questão de dados, não de estrutura. `830` e `930` foram reescritas para v1.2 (ver "Seed — Versão Canônica (1.2)" e "Validação — Versão Canônica (1.2)", acima) e executadas com sucesso, confirmadas por Fabrício: "Tudo feito com sucesso. Vamos avançar!" **Rarity está oficialmente encerrada.**

### Emenda — Hiper Rara (`HYPER_RARE`, v1.3, 2026-08-01)

Gap real descoberto durante a importação TCGdex de SV1 (Escarlate e Violeta, Ciclo 2 — ver seção Catalog Import Job/Row, abaixo): a confirmação do job (`admin_confirm_catalog_import`) rejeitou 6 das 258 linhas com o erro "Não foi possível identificar o Game da Rarity informada" — Miraidon ex, Koraidon ex, Bola de Ninho, Doce Raro e as duas Energias Básicas (`collector_number` 253–258), todas com `raw_data.rarity = "Hiper Rara"` vinda da TCGdex.

`rarity` já tinha `MEGA_HYPER_RARE`/"Mega Rara Hiper" (exclusiva da Megaevolução), mas nada para "Hiper Rara" pura — raridade distinta, real, usada pela TCGdex para os `ex`/Energias secretos de SV1. Sem `rarity_id` correspondente, `normalizeRarityLookupKey`/`raritiesByName` (Edge Function, `services/normalize.ts`) deixava `rarity_id = NULL` nessas 6 linhas, e a confirmação bloqueava a persistência.

**Confirmado por Fabrício ("Cadastre essa raridade no catálogo") e executado:**

| `display_order` | `code` | `name` | `symbol_code` |
|---|---|---|---|
| 11 | `HYPER_RARE` | Hiper Rara | `GOLD_STAR` |

Acrescentada ao final (display_order 11, sem reordenar as demais 10). `symbol_code = GOLD_STAR` reaproveita o símbolo de `ILLUSTRATION_RARE` — **escolha provisória, sinalizada e não confirmada por fonte oficial** (mesmo espírito da divergência já registrada para Ilustração Rara em `RaritySymbol`, frontend); ajustar se surgir referência melhor.

Queries `830`/`930` reescritas para v1.3 (mesmos arquivos, `ON CONFLICT` idempotente) e reexecutadas — `rarity` agora tem 11 registros para POKEMON, `HYPER_RARE` confirmado com os valores acima.

**Consequência não resolvida nesta emenda:** as 6 linhas já processadas do job SV1 (`e5e43441-3193-41de-a5d3-8df5b0ac679f`, status `COMPLETED_WITH_ERRORS`) têm `rarity_id = NULL` congelado em `normalized_data` — cadastrar a raridade agora não corrige retroativamente essas 6 linhas já normalizadas; corrigir exige reprocessar (novo job de importação para SV1, ou lógica de retry específica, nenhuma das duas implementada ainda).

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
- [x] tabela `rarity` criada no Supabase, já com `symbol_code` (`130` v1.1);
- [x] RLS habilitado;
- [x] trigger criado (`131`, inalterado);
- [x] seed executada com sucesso, incluindo `symbol_code` e `PROMO` (`830` v1.2);
- [x] validação executada e confirmada, incluindo `symbol_code` e `PROMO` (`930` v1.2 — "Tudo feito com sucesso").

**Entidade Rarity oficialmente encerrada.** Modelagem, estrutura física, seed canônica, validação e documentação 100% consistentes entre si (palavras de Fabrício: "Agora sim podemos dizer que a entidade Rarity está encerrada").

## Queries Associadas

```text
130 - Create Rarity Table    (v1.1, Status CANÔNICA — executada)
131 - Create Rarity Trigger  (executada, inalterada)
830 - Seed Rarity            (v1.2, Status CANÔNICA — executada, inclui PROMO)
930 - Validate Rarity        (v1.2, Status CANÔNICA — executada e confirmada, inclui PROMO)
```

Rarity precisava ser criada antes de Card, por dependência de chave estrangeira (`card.rarity_id`) — ver STD-001, Seção 10. **Com o pacote técnico de Rarity definitivamente concluído, a próxima etapa foi a modelagem conceitual de Card**, cujo histórico completo (duas revisões arquiteturais sucessivas) está registrado em `04-domain-model.md`, seção Card. O resultado final está documentado logo abaixo, na seção Card Category (nova entidade, executada primeiro por dependência) e na seção Card (modelo final, aprovado, ainda não executado).

---

# Card Category (Categoria de Carta)

Status: **Executada e confirmada.** Nova entidade, introduzida durante a modelagem de Card (ver `04-domain-model.md`, seção "Revisão Arquitetural — Card Volta a Pertencer a um Card Set"), para substituir a coluna solta `category_code` que estava cogitada diretamente em `card`. Segue o mesmo padrão de domínio já usado por Rarity: tabela de referência por Game, com `code`/`name`/`display_order`.

## Modelo Lógico

```text
Card Category

Identidade
----------
id
code

Descrição
----------
name
display_order

Relacionamento
----------
game_id

Auditoria
----------
created_at
updated_at
```

## Atributos

**id** — Identificador técnico e permanente (UUID).

**game_id** — Chave estrangeira obrigatória para `game`. Cada Game define seu próprio conjunto de categorias, evitando alterações estruturais em `card` caso outros TCGs sejam adicionados no futuro.

**code** — Identificação técnica e estável da categoria (`POKEMON`, `TRAINER`, `ENERGY`). Único dentro do Game (`UNIQUE (game_id, code)`), não globalmente — outro Game pode reutilizar o mesmo código.

**name** — Nome principal da categoria para apresentação ao usuário, em português (`Pokémon`, `Treinador`, `Energia`).

**display_order** — Ordem lógica de exibição da categoria na interface e em relatórios.

**created_at / updated_at** — Auditoria mínima (ver STD-001, Seção 4).

## Campos que Não Incluiremos Agora

- **Ícone/símbolo visual** — não cogitado para Card Category nesta fase (diferente de Rarity, que tem `symbol_code`); as categorias atuais não têm identidade visual própria a preservar.
- **Descrição estendida/texto explicativo** — não solicitado; `name` já é autoexplicativo para as três categorias atuais.

## Regras de Negócio

**Regra 1 — Relacionamento obrigatório.** Toda categoria deve pertencer a um Game.

**Regra 2 — Código único por Game.** `UNIQUE (game_id, code)`; Games diferentes podem reutilizar o mesmo código.

**Regra 3 — Formato do código.** Letras maiúsculas, números e underscore (`^[A-Z0-9][A-Z0-9_]*$`).

**Regra 4 — Nome obrigatório.** `name` não pode ser vazio.

**Regra 5 — Ordem de exibição positiva.** `display_order > 0`.

**Regra 6 — Exclusão restrita.** Um Game com categorias cadastradas não pode ser excluído (`ON DELETE RESTRICT`, `ON UPDATE RESTRICT`).

## Modelo Físico (PostgreSQL) — Executado

```sql
CREATE TABLE public.card_category (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_card_category_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_category_game_code
        UNIQUE (game_id, code),

    CONSTRAINT ck_card_category_code_format
        CHECK (
            code ~ '^[A-Z0-9][A-Z0-9_]*$'
        ),

    CONSTRAINT ck_card_category_name_not_blank
        CHECK (
            btrim(name) <> ''
        ),

    CONSTRAINT ck_card_category_display_order_positive
        CHECK (
            display_order > 0
        )
);

ALTER TABLE public.card_category ENABLE ROW LEVEL SECURITY;
```

> Query `132`, Versão 1.0, Status CANÔNICA. Inclui `COMMENT ON TABLE`/`COMMENT ON COLUMN` para toda a tabela (não usado em Rarity até aqui) e `ON UPDATE RESTRICT` além de `ON DELETE RESTRICT` na FK — convenções novas observadas pela primeira vez neste pacote. Texto completo em `database/schema/132_create_card_category_table.sql`.

### Trigger de `updated_at`

```sql
DROP TRIGGER IF EXISTS trg_card_category_set_updated_at
ON public.card_category;

CREATE TRIGGER trg_card_category_set_updated_at
BEFORE UPDATE ON public.card_category
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
```

> Query `133`, Versão 1.0, Status CANÔNICA. Uso de `DROP TRIGGER IF EXISTS` antes do `CREATE TRIGGER` para idempotência — também uma convenção nova neste pacote. Texto completo em `database/schema/133_create_card_category_trigger.sql`.

### Seed — Executado

Cadastra três categorias para o Game POKEMON: `POKEMON`/Pokémon/1, `TRAINER`/Treinador/2, `ENERGY`/Energia/3. Texto completo em `database/seeds/831_seed_card_category.sql`.

> **Discrepância resolvida (2026-07-30).** A Query `831`, executada e confirmada no Supabase, inclui `ENERGY` como uma categoria real e válida de Card Category — o que antes contradizia a "Decisão de Escopo — Cartas de Energia" registrada em `04-domain-model.md`. Fabrício confirmou explicitamente que essa realidade física é a decisão vigente: cartas de Energia ocupam posição oficial no Set e fazem parte do catálogo numerado, como Pokémon e Trainer. Formalizado em `adr/ADR-025-energy-as-catalog-card-category.md`; a antiga decisão de escopo, em `04-domain-model.md`, foi marcada como substituída (texto histórico preservado). Nenhuma alteração física adicional foi necessária — a categoria `ENERGY` já estava corretamente cadastrada.

### Validação — Executada e Confirmada

Texto completo em `database/validations/931_validate_card_category.sql`. 13 subconsultas seguindo o mesmo padrão de Rarity (relação completa, quantidade por Game, integridade referencial, duplicados, formato de código, nomes vazios, ordem inválida, ordens duplicadas, dados canônicos via CTE, categorias extras não previstas, timestamps, trigger, RLS). Resultados confirmados por Fabrício: 3 categorias (ordem 1 POKEMON/Pokémon, 2 TRAINER/Treinador, 3 ENERGY/Energia), quantidade POKEMON = 3, todas as consultas de erro "Nenhum registro," trigger "1 registro," RLS `true`. Fabrício: "Execução com sucesso."

## Definition of Done

- [x] modelo lógico definido;
- [x] atributos e campos adiados definidos;
- [x] regras de negócio definidas;
- [x] tabela `card_category` criada no Supabase (`132`);
- [x] RLS habilitado;
- [x] trigger criado e verificado (`133`);
- [x] seed executada com sucesso (`831`) — inclui `ENERGY`, formalizada como categoria vigente do catálogo por `ADR-025` (ver nota acima);
- [x] validação executada e confirmada (`931` — "Execução com sucesso").

## Queries Associadas

```text
132 - Create Card Category Table    (v1.0, Status CANÔNICA — executada)
133 - Create Card Category Trigger  (v1.0, Status CANÔNICA — executada)
831 - Seed Card Category            (v1.0, Status CANÔNICA — executada, inclui ENERGY)
931 - Validate Card Category        (v1.0, Status CANÔNICA — executada e confirmada)
```

Card Category precisava ser criada antes de Card, por dependência de chave estrangeira (`card.category_id`) — mesma lógica de precedência já aplicada a Rarity (ver STD-001, Seção 10).

---

# Card (Carta)

Status: **Executado e confirmado no Supabase (927 Cards, 7 Card Sets).** Esta seção passou por duas revisões arquiteturais sucessivas, documentadas em detalhe em `04-domain-model.md`, seção Card: (1) uma proposta de identidade editorial independente de Set (Card Printing como nova camada), discutida e explicitamente **não concluída**; (2) a reversão dessa proposta — decisão final de Fabrício ("Estou achando melhor considerar uma 'Card' como uma representação da carta dentro de um Set específico [...] Fiquei com receio do modelo anterior trazer dificuldades no cadastro") — voltando Card a pertencer diretamente a um Card Set, com Card Printing descartada por ora. O conteúdo original abaixo (modelo lógico com `card_number`/`card_order`/`category_code` diretamente em `card`) é preservado por rastreabilidade histórica; **o modelo final executado está na subseção "Modelo Final — Versão 1.1 (executado e confirmado no Supabase)", ao final desta seção.** Camada de escrita administrativa (`internal.write_card()`, `admin_create_card()`/`admin_update_card()`) é tratada à parte, na seção "Catálogo Editorial — Escrita e Ingestão".

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
- **Acabamento (Holofoil, Reverse Holofoil), selo** — pertencem à camada Card Variant (nomenclatura conceitual resolvida por ADR-016; ver seção "Card Variant Type"/"Card Variant", abaixo).
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
- [x] nomenclatura Card Variant Type/Card Variant confirmada por Fabrício (ADR-016), revertendo Finish/Card Finish;
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

> **Nota:** o conteúdo acima (Modelo Lógico, Atributos, Regras de Negócio 1-7 e DDL proposto nesta seção "Card (Carta)") reflete o estado **anterior às duas revisões arquiteturais** descritas no callout de status, no início desta seção. Preservado por rastreabilidade. **O modelo final está na subseção abaixo.**

## Modelo Final — Versão 1.1 (executado e confirmado no Supabase)

Resultado da reversão documentada em `04-domain-model.md`, seção "Revisão Arquitetural — Card Volta a Pertencer a um Card Set". Card representa "uma entrada específica no checklist oficial de um Card Set" (ex.: Charizard ex nº 021 da coleção ME4) — não uma identidade editorial independente de Set. Card Printing, cogitada na revisão intermediária, **não é necessária neste momento**.

**Refinamento desta revisão (1.1):** a validação campo-a-campo do modelo aprovado no ciclo anterior (Versão 1.0) levou a duas adições — `collector_total` e `collector_order` — e a uma decisão sobre o idioma de `name`. Ver "Evolução do Modelo" abaixo.

### Modelo Lógico

```text
Card

Identidade
----------
id
collector_number

Descrição
----------
name

Relacionamento
----------
card_set_id
rarity_id
category_id

Ordenação
----------
collector_order

Auditoria
----------
created_at
updated_at
```

### Atributos

**id** — Identificador técnico e permanente (UUID).

**card_set_id** — Chave estrangeira obrigatória para `card_set`. Toda Card pertence a exatamente um Card Set.

**rarity_id** — Chave estrangeira obrigatória para `rarity` (ver seção Rarity, acima).

**category_id** — Chave estrangeira obrigatória para `card_category` (ver seção Card Category, acima) — substitui a coluna solta `category_code` cogitada na versão anterior.

**collector_number** — Renomeado de `card_number`. Número oficial impresso ou atribuído à Card, `VARCHAR(20)`, nunca inteiro — preserva zeros à esquerda, prefixos e sufixos (`001`, `SVP001`, `TG07`, `GG32`, `RC15`, `12a`).

**collector_total** — **Novo nesta revisão.** `INTEGER`, opcional (`NULL` permitido). Registra o denominador exibido na numeração oficial da carta (o `182` em `021/182`), quando aplicável. Explicitamente distinto de `card_set.total_set_size`: uma mesma carta pode exibir um denominador diferente do total absoluto do Set — seções especiais (`TG`, `GG`) têm seu próprio denominador (`TG07/TG30`, `GG15/GG70`), e cartas promocionais frequentemente não exibem denominador algum (`SVP001`). Quando informado, deve ser maior que zero (`ck_card_collector_total_positive`).

**collector_order** — **Reintroduzido nesta revisão** (havia sido removido na Versão 1.0, sem confirmação explícita de necessidade). Posição editorial da carta no checklist oficial do Card Set, usada para ordenação — necessário porque `collector_number` sozinho não ordena naturalmente quando há prefixos/sufixos não numéricos (`001, 002, TG01, TG02, GG15, SVP001, 12a` não têm uma ordenação textual simples). `INTEGER`, obrigatório, maior que zero, único dentro do Card Set (`uq_card_card_set_collector_order`).

**name** — Nome da carta armazenado exatamente como impresso oficialmente (ex.: `Charizard ex`), deliberadamente **sem** separar sufixos mecânicos (`ex`, `V`, `GX`, `VMAX`) do nome base — essa distinção é de mecânica de jogo (fora de escopo por AP-017), não de colecionismo, e mecânicas mudam ao longo do tempo.

> **Decisão sobre idioma de `name` (Opção B, confirmada por Fabrício).** Cogitadas duas opções: (A) `name` acompanha o idioma do Set de cada Card individualmente; (B) a Card sempre guarda o nome oficial da edição (Card Set) em que foi cadastrada — se o Set é em português, o nome é em português; se em inglês, em inglês. Fabrício escolheu a **Opção B**: "a Card representa exatamente o catálogo daquele Set. Não precisamos criar uma camada de tradução." Ou seja, `name` não é multi-idioma dentro da própria Card — cada publicação (cada Card, específica de um Set) tem um único nome, no idioma daquele Set. Uma eventual camada de tradução/localização permanece uma responsabilidade separada (ver seção Card Translation, abaixo — ainda "Documentação pendente"), não um campo de `card`.

**created_at / updated_at** — Auditoria mínima (ver STD-001, Seção 4).

### Não Persistido — `card_code` (composto)

O identificador legível composto (ex.: `ME4-021`, `SVP-001`) **não é armazenado como coluna**. Decisão: derivar via lógica de aplicação ou `VIEW` (`card_set.code || '-' || card.collector_number`), evitando redundância e risco de inconsistência — mesmo princípio já aplicado a `card_set.secret_set_size` (sempre derivado, nunca persistido). A Query `940` (abaixo) demonstra essa derivação em uma consulta real (`derived_card_code`).

### Extensão Futura, Não Construída — `card_relation`

Ponto de extensão registrado para rastrear reimpressões/artes alternativas no futuro (`source_card_id`, `target_card_id`, `relation_type`, com exemplos `REPRINT_OF`, `SAME_ARTWORK_AS`, `ALTERNATE_ART_OF`) — deliberadamente não construído agora, para que o cadastro inicial não dependa dessa classificação.

### Forma Final Aprovada

```text
card (
    id, card_set_id, rarity_id, category_id,
    collector_number, collector_total, collector_order, name,
    created_at, updated_at
)
```

Fabrício: "Vamos em frente. Concordo!"

> **Tensão sinalizada, não resolvida:** conforme já registrado em `04-domain-model.md`, este modelo (Card atrelada a um Card Set específico, de modo que uma reimpressão em outro Set é uma Card diferente) está em tensão não resolvida com o princípio AP-011 (Editorial Identity), que declara que a identidade editorial deve ser independente de "impressão"/"distribuição". Não discutido pela sessão pareada; AP-011 não foi alterado.

### Regra Adicional — Consistência de Game entre Card Set, Rarity e Card Category

`card` **não armazena `game_id`** — essa informação é obtida via `Card → Card Set → Expansion → Game`. Porém `rarity_id` e `category_id` também pertencem a um Game (cada um com seu próprio `game_id`), e nada impede, apenas pela FK, que uma Card referencie uma Rarity ou Card Category de um Game diferente do seu Card Set. Regra de negócio nova: **Card Set, Rarity e Card Category referenciados por uma mesma Card devem pertencer ao mesmo Game** — validada não por CHECK constraint (não é possível comparar colunas de tabelas diferentes em um CHECK simples), mas por um **trigger de validação** (`141`, abaixo), primeira vez neste projeto que esse padrão é usado.

### Modelo Físico (PostgreSQL) — Executado e confirmado

```sql
CREATE TABLE public.card (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_set_id UUID NOT NULL,
    rarity_id UUID NOT NULL,
    category_id UUID NOT NULL,

    collector_number VARCHAR(20) NOT NULL,
    collector_total INTEGER,
    collector_order INTEGER NOT NULL,
    name VARCHAR(200) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_card_card_set
        FOREIGN KEY (card_set_id)
        REFERENCES public.card_set (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_rarity
        FOREIGN KEY (rarity_id)
        REFERENCES public.rarity (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_category
        FOREIGN KEY (category_id)
        REFERENCES public.card_category (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_card_set_collector_number
        UNIQUE (card_set_id, collector_number),

    CONSTRAINT uq_card_card_set_collector_order
        UNIQUE (card_set_id, collector_order),

    CONSTRAINT ck_card_collector_number_not_blank
        CHECK (btrim(collector_number) <> ''),

    CONSTRAINT ck_card_collector_number_format
        CHECK (collector_number ~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'),

    CONSTRAINT ck_card_collector_total_positive
        CHECK (collector_total IS NULL OR collector_total > 0),

    CONSTRAINT ck_card_collector_order_positive
        CHECK (collector_order > 0),

    CONSTRAINT ck_card_name_not_blank
        CHECK (btrim(name) <> '')
);

ALTER TABLE public.card ENABLE ROW LEVEL SECURITY;
```

> Query `140`, Versão 1.0, Status CANÔNICA — **execução confirmada por inferência técnica direta**: Fabrício confirmou explicitamente a execução da Query `840` v2.1 ("Executei com sucesso"), que insere 859 linhas em `card` e depende estruturalmente de `140` já existir — logo `140` necessariamente já estava executada antes disso. Nenhuma mensagem separada "140 executado com sucesso" foi mostrada isoladamente; esta conclusão foi documentada explicitamente como inferência (não presunção), para que Fabrício possa corrigir caso a leitura esteja errada. Texto completo, incluindo `COMMENT ON TABLE`/`COMMENT ON COLUMN`, copiado para `database/schema/140_create_card_table.sql`. `ck_card_collector_number_format` permite letras, números, ponto, underscore e hífen — mais permissivo que a antiga Regra 5 do modelo superado (que evitava qualquer regex), para acomodar `TG01`, `SVP001`, `12a`, `001-A`.

### Trigger — Consistência de Game + `updated_at`

```sql
CREATE OR REPLACE FUNCTION public.validate_card_game_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_card_set_game_id UUID;
    v_rarity_game_id UUID;
    v_category_game_id UUID;
BEGIN
    SELECT e.game_id INTO v_card_set_game_id
      FROM public.card_set AS cs
      INNER JOIN public.expansion AS e ON e.id = cs.expansion_id
     WHERE cs.id = NEW.card_set_id;

    SELECT r.game_id INTO v_rarity_game_id
      FROM public.rarity AS r
     WHERE r.id = NEW.rarity_id;

    SELECT cc.game_id INTO v_category_game_id
      FROM public.card_category AS cc
     WHERE cc.id = NEW.category_id;

    IF v_card_set_game_id <> v_rarity_game_id THEN
        RAISE EXCEPTION 'Inconsistência de Game: o Card Set e a Rarity pertencem a Games diferentes.';
    END IF;

    IF v_card_set_game_id <> v_category_game_id THEN
        RAISE EXCEPTION 'Inconsistência de Game: o Card Set e a Card Category pertencem a Games diferentes.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_card_validate_game_consistency
BEFORE INSERT OR UPDATE OF card_set_id, rarity_id, category_id
ON public.card
FOR EACH ROW
EXECUTE FUNCTION public.validate_card_game_consistency();

CREATE TRIGGER trg_card_set_updated_at
BEFORE UPDATE ON public.card
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
```

> Query `141`, Versão 1.0, Status CANÔNICA — execução confirmada pela mesma inferência técnica acima (o trigger `trg_card_validate_game_consistency` é acionado em todo `INSERT`, então a Seed de 859 linhas só poderia ter sido concluída com sucesso se este trigger já estivesse ativo e correto). Primeira vez no projeto em que um trigger de validação (não apenas `updated_at`) é usado para impor uma regra de integridade referencial cruzada (Card Set/Rarity/Card Category do mesmo Game) que uma FK/CHECK simples não consegue expressar. Texto completo (incluindo tratamento de `NULL`, `COMMENT ON FUNCTION` e `DROP TRIGGER IF EXISTS` antes de cada `CREATE TRIGGER`) copiado para `database/schema/141_create_card_triggers.sql`.

### Seed — Query `840`, Versão 2.2, executada e confirmada ("Já executei as duas queries. Sem erros!")

**Mudança de arquitetura em relação ao padrão usado até aqui**: em vez de uma Seed por Card Set (como cogitado inicialmente, "840 - Seed Card (ME1)"), a Query `840` foi desenhada como **uma única Seed canônica cobrindo todo o catálogo oficial atualmente suportado** pelo projeto. Raciocínio de Fabrício, adotado pela sessão pareada: "a tabela `card` é um catálogo mestre, não um cadastro operacional" — quando um novo Card Set for lançado, a própria Query `840` é atualizada (não uma nova migration), consistente com o já estabelecido Princípio da Fonte Canônica (STD-001, Seção 10).

**Evolução v2.1 → v2.2 (executada nesta revisão)**: a Query, que já cobria os cinco Card Sets da expansão Megaevolução (`ME1`, `ME2`, `ME2.5`, `ME3`, `ME4`, 859 Cards), foi estendida para incluir `MEE` (8 Cards) e `MEP` (60 Cards), elevando o total canônico para **927 Cards em sete Card Sets**. Mudanças concretas: cabeçalho/descrição atualizados; a validação inicial (bloco 1) passou a exigir os sete Card Sets e a raridade `PROMO` entre as dez raridades obrigatórias (antes nove); o CTE `source_card` recebeu os 8 registros de MEE (categoria `ENERGY`, raridade `PROMO`, nomes das oito Energias Básicas em português) e os 60 registros de MEP (`collector_number` preservando a numeração promocional oficial com lacunas — `001`-`045`, depois `064`-`080` — enquanto `collector_order` permanece contínuo de 1 a 60); a validação final (bloco 3) passou a exigir exatamente 927 Cards no total consolidado, com a lista `expected_set` estendida aos sete Card Sets. A estrutura da Query (validar → inserir/atualizar via `ON CONFLICT ... DO UPDATE` → validar quantidade final) e a base ME1-ME4/ME2.5 foram preservadas integralmente, sem nenhuma alteração aos dados já existentes.

**Fonte primária**: os cinco checklists oficiais em PT-BR já arquivados em `assets/reference-sources/` (`P10346_ME01_Card_List_PTBR`, `P10347_ME02_Card_List_PTBR`, `ME02pt5_Card_List_PTBR`, `P11218_ME03_Card_List_PTBR`, `ME04_Card_List_PTBR`), mais os catálogos MEE/MEP consultados diretamente na TCGdex.

**Decisão sobre `collector_total` — ponto que exigiu uma leitura editorial explícita.** Os PDFs mostram a numeração completa das cartas (`001`...`188`) mas não exibem o denominador em todos os registros (o formato impresso `021/182` só aparece em parte do material). Decisão adotada e documentada explicitamente na Query: `collector_total` é derivado do `card_set.base_set_size` já cadastrado para cada Set (MEE=8, MEP=60, ME1=132, ME2=94, ME2.5=217, ME3=88, ME4=86), aplicado a **todas** as cartas do Set, incluindo as secretas/especiais que excedem o `base_set_size` (ex. ME1 cartas 133–188 recebem `collector_total = 132`, mesmo valor das cartas 001–132) — essa é a leitura editorial padrão do Pokémon TCG, mas o documento por si só não a comprova, por isso precisou ser assumida explicitamente como regra derivada, não lida diretamente do checklist.

**Estrutura da Query**: (1) valida a existência do Game `POKEMON` e dos sete Card Sets, com seus `base_set_size`/`total_set_size` batendo com os valores canônicos; (2) valida que as três Card Categories (`POKEMON`/`TRAINER`/`ENERGY`) e todas as dez Rarities utilizadas (incluindo `MEGA_ATTACK_RARE` e `PROMO`) já estão cadastradas; (3) insere/atualiza as 927 linhas de forma idempotente (`ON CONFLICT (card_set_id, collector_number) DO UPDATE`); (4) valida ao final que cada Card Set tem exatamente sua quantidade canônica e que o total consolidado é exatamente 927 — reverte toda a transação (`BEGIN`/`COMMIT`) se qualquer verificação falhar.

**Distribuição real confirmada (screenshot da sessão pareada)**: por Card Category — Pokémon 152, Treinador 36, Energia 0 (para ME1 especificamente); por Rarity (ME1) — `COMMON` 63, `UNCOMMON` 48, `RARE` 11, `DOUBLE_RARE` 10, `ILLUSTRATION_RARE` 22, `ULTRA_RARE` 22, `SPECIAL_ILLUSTRATION_RARE` 10, `MEGA_HYPER_RARE` 2 (soma 188). Totais por Set: MEE=8, MEP=60, ME1=188, ME2=130, ME2.5=295, ME3=124, ME4=122 → 927.

> **`ENERGY` no catálogo numerado — confirmado como decisão vigente (2026-07-30).** Ao contrário de ME1 (que não tem nenhuma carta de categoria `ENERGY`), os outros Sets **têm** Cards de Energia com posição numerada real no checklist: ME2 tem 1 (`124 - Energia de Ignição`), ME2.5 tem 2 (`216`/`217`), ME3 tem 3 (`086`-`088`), ME4 tem 3 (`084`-`086`), e MEE tem 8 (as oito Energias Básicas, `001`-`008`) — 17 Cards de Energia ao todo, já inseridos em produção via esta Query. Esse dado físico é o que motivou a resolução definitiva de Fabrício, formalizada em `adr/ADR-025-energy-as-catalog-card-category.md`: cartas de Energia ocupam posição oficial no Set e fazem parte do catálogo numerado, como Pokémon e Trainer. A antiga "Decisão de Escopo — Cartas de Energia" em `04-domain-model.md` foi marcada como substituída (texto histórico preservado, não apagado).

Texto completo verbatim copiado para `database/seeds/840_seed_card.sql`, sobrescrevendo a v2.1 no mesmo arquivo (Princípio da Fonte Canônica — seed representa o estado correto atual, não uma migration histórica).

### Validação — Query `940`, Versão 2.1, executada e confirmada ("Já executei as duas queries. Sem erros!")

**Evolução v2.0 → v2.1 (executada nesta revisão), sincronizada com a Query 840 v2.2**: de 27 para **31 blocos de validação**. Todos os blocos existentes foram estendidos para cobrir os sete Card Sets (`MEE`, `MEP`, `ME1`, `ME2`, `ME2.5`, `ME3`, `ME4`) e o total consolidado de 927 Cards, e dois blocos foram acrescentados especificamente para o novo escopo: bloco 24 (raridade inválida em MEE/MEP — exige `PROMO` em ambos) e bloco 25 (categoria inválida em MEE — exige `ENERGY`). Os blocos de checklist explícito por Card Set (antes cobrindo apenas ME1-ME4 implicitamente via `generate_series`) ganharam duas novas seções dedicadas: bloco 26 (checklist completo de `collector_number`/`collector_order` esperado para as 8 Cards de MEE) e bloco 27 (checklist completo para as 60 Cards de MEP, preservando explicitamente a lacuna de numeração `046`-`063` que não existe na numeração promocional oficial). Mantém os 27 blocos anteriores (agora renumerados 1-23 e 28-31): quantidades esperadas por Card Set via CTE (`expected_set`), total consolidado, status `COMPLETE`/`PENDING`/`EXCEEDED`, continuidade de `collector_order` de 1 até `total_set_size`, divergência entre `collector_total` e `card_set.base_set_size`, duplicidade de número/ordem, formato/vazio de número e nome, integridade referencial com Card Set/Rarity/Card Category, inconsistência de Game, timestamps, os dois triggers, RLS. **Fabrício confirmou a execução diretamente: "Já executei as duas queries. Sem erros!"** Texto completo verbatim copiado para `database/validations/940_validate_card.sql`, sobrescrevendo a v2.0 no mesmo arquivo.

Com isso, **o catálogo de Card do Project Mimikyu passa a cobrir as sete Card Sets da expansão Megaevolução, incluindo MEE e MEP** (`140`/`141`/`840`/`940`, todos executados e sincronizados). Marco confirmado pela sessão pareada: 7 Card Sets cadastrados, 927 Cards catalogadas, estrutura totalmente normalizada, validações canônicas sincronizadas com os Seeds.

> **Ressalva importante, não é o fim da entidade Card**: um item segue em aberto — **`Card Variant` para MEE/MEP ainda não existe** — a camada de variantes editoriais (860A-860E/860 consolidada) cobre apenas as cinco coleções originais (ME1-ME4/ME2.5); o plano de estender essa camada a MEE/MEP está definido mas não executado (ver seção "Card Variant", abaixo, "Próximo passo planejado"). A discrepância `ENERGY` (17 Cards reais ocupando posições numeradas), antes listada aqui como item em aberto, está **resolvida** — ver nota acima e `adr/ADR-025-energy-as-catalog-card-category.md`.

## Definition of Done (Versão 1.1)

- [x] modelo lógico definido, por grupo (incluindo `collector_total`/`collector_order`);
- [x] atributos definidos, incluindo a decisão de idioma de `name` (Opção B);
- [x] regra de consistência de Game entre Card Set/Rarity/Card Category definida;
- [x] tabela `card` criada no Supabase (`140`, execução confirmada por inferência técnica);
- [x] RLS habilitado;
- [x] triggers criados e confirmados (`141`, execução confirmada por inferência técnica);
- [x] seed executada com sucesso — 927 Cards, 7 Card Sets, incluindo MEE/MEP (`840` v2.2, confirmado por Fabrício: "Já executei as duas queries. Sem erros!");
- [x] validação reescrita (31 blocos, sincronizada com 840 v2.2) e executada com sucesso (`940` v2.1, confirmado por Fabrício: "Já executei as duas queries. Sem erros!");
- [x] arquivos `140`/`141`/`840`/`940` copiados/atualizados em `database/`;
- [x] confirmação explícita de Fabrício sobre a discrepância `ENERGY` (17 Cards reais classificadas como Energia, ocupando posições numeradas, incluindo as 8 de MEE) — resolvida em 2026-07-30, ver `adr/ADR-025-energy-as-catalog-card-category.md`;
- [x] entidade Card Variant (associação Card ↔ Card Variant Type) — estrutura executada e canonicamente encerrada **para as cinco coleções originais** (`160`/`161`/`860` consolidada/`960` v2.0): 859 Cards, 1.555 Card Variants, status `COMPLETE` — ver seções Card Variant Type e Card Variant, abaixo;
- [ ] Card Variant para MEE/MEP — plano definido (série `860A`-`860G` por Card Set, ordem cronológica MEE/MEP/ME1/ME2/ME2.5/ME3/ME4, seguida de `960 - Validate Card Variant`), **não executado** — ver seção "Card Variant", abaixo.

## Queries Associadas (Versão 1.1)

```text
140 - Create Card Table     (v1.0, Status CANÔNICA — executada e confirmada)
141 - Create Card Triggers  (v1.0, Status CANÔNICA — executada e confirmada)
840 - Seed Card             (v2.2, Status CANÔNICA — executada e confirmada, 927 Cards / 7 Card Sets)
940 - Validate Card         (v2.1, Status CANÔNICA — executada e confirmada, 31 blocos de validação)
```

Próxima etapa: estender a camada `Card Variant` (`860A`-`860G`/`960`) para cobrir `MEE` e `MEP`, começando por `MEE` (8 Cards) para validar o pipeline em escala pequena antes de `MEP` (60 Cards) — ver seção "Card Variant", abaixo, "Próximo passo planejado". Nomenclatura resolvida por ADR-016.

---

# Card Translation (Tradução da Carta)

*Documentação pendente.*

---

# Card Variant Type (Tipo de Variante da Carta)

## Status

**Pacote técnico concluído e executado.** Nome conceitual e físico convergentes: "Card Variant Type" (ADR-016) — o nome alternativo "Finish", usado por ADR-010 entre 2026-07 e a reversão desta decisão, é preservado apenas como sinônimo histórico. A tabela física foi criada e povoada sob o nome `card_variant_type`. A associação entre uma Card e um Card Variant Type específico é a entidade Card Variant (ver seção própria, abaixo).

## Modelo Físico — Versão 1.0

```sql
CREATE TABLE public.card_variant_type (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.game (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (game_id, code),
    UNIQUE (game_id, display_order)
);
```

Regras de negócio: `code` segue o formato `^[A-Z][A-Z0-9_]*$`; `name` não pode ser vazio; `display_order` deve ser positivo e único dentro do Game; exclusão de Game referenciado é impedida (`RESTRICT`); RLS habilitado.

Queries `150 - Create Card Variant Type Table` e `151 - Create Card Variant Type Triggers` (trigger de `updated_at`, mesmo padrão já usado nas demais entidades) executadas e confirmadas por Fabrício.

## Seed — Versão 1.3

Catálogo canônico atual do Game `POKEMON` (13 tipos, `850` v1.3):

| code | name | display_order |
|------|------|----------------|
| `STANDARD` | Padrão | 1 |
| `HOLO` | Holográfica | 2 |
| `COSMOS_HOLO` | Holográfica Cosmos | 3 |
| `REVERSE_HOLO` | Holográfica Reversa | 4 |
| `ENERGY_REVERSE` | Energia Reversa | 5 |
| `POKE_BALL_REVERSE` | Poké Bola Reversa | 6 |
| `LOVE_BALL_REVERSE` | Love Ball Reversa | 7 |
| `FRIEND_BALL_REVERSE` | Friend Ball Reversa | 8 |
| `QUICK_BALL_REVERSE` | Quick Ball Reversa | 9 |
| `DUSK_BALL_REVERSE` | Dusk Ball Reversa | 10 |
| `ROCKET_REVERSE` | Equipe Rocket Reversa | 11 |
| `MASTER_BALL_REVERSE` | Master Ball Reversa | 12 |
| `PROMO_STAMPED` | Promocional Estampada | 13 |

Histórico: a v1.0 continha cinco tipos (sem `HOLO`); a v1.1 (6 tipos) adicionou `HOLO`; a v1.2 (12 tipos) adicionou os seis tipos de reversa específica descobertos na análise editorial da coleção ME2.5 (ver "Query 860", abaixo). A **v1.3 (13 tipos)** adicionou `COSMOS_HOLO`, motivada por checklists editoriais oficiais (pkmn.gg) que confirmaram esse acabamento como um padrão físico recorrente — observado em mais de uma Card e mais de um produto de coleções distintas (ex.: Card `008` e Card `020` de uma mesma coleção, cada uma com uma impressão "Cosmos Holo" vinda de um produto promocional específico) — e não um caso isolado nem um simples selo (`PROMO_STAMPED`). Todas as versões usam o mesmo mecanismo de convergência segura (deslocamento temporário de `display_order` em `+1000` antes do UPSERT definitivo). Executada com sucesso, confirmada por Fabrício.

O catálogo foi mantido deliberadamente restrito a tipos com utilidade colecionável clara e documentada. Outros acabamentos ainda sem evidência editorial confirmada nas coleções do projeto (ex.: Galaxy Holo, Confetti Holo, Cracked Ice) foram deliberadamente **não** incluídos — serão avaliados individualmente se e quando aparecerem em uma coleção suportada pelo Project Mimikyu. O cadastro de um Card Variant Type não implica que toda Card, ou mesmo todo Card Set, possua essa variante — essa associação é feita pela tabela `card_variant`.

## Distinção Reconhecida — Acabamento vs. Origem de Distribuição (não modelada ainda)

A investigação que levou à inclusão de `COSMOS_HOLO` revelou que `card_variant_type` está tentando representar, hoje, duas dimensões conceitualmente independentes sob um único catálogo: (1) o **acabamento físico** da Card (Standard, Holo, Cosmos Holo, Reverse, etc. — "o que a carta fisicamente é") e (2) a **origem/distribuição** daquela impressão (booster, produto promocional específico, coleção especial — "de onde ela veio"). Uma mesma Card pode ter o mesmo acabamento reaparecendo em produtos diferentes, sem que isso deva gerar um novo Card Variant Type a cada novo produto lançado.

Decisão confirmada por Fabrício: `card_variant_type` continua representando **apenas** o acabamento físico (Opção A, entre as duas avaliadas). A origem/distribuição de uma impressão promocional específica é uma necessidade de modelagem reconhecida, mas **ainda não construída** — provavelmente uma futura entidade de "Printing"/"Release" vinculada a `card_variant` (ou reaproveitando `card_asset`), registrando produto de distribuição, idioma, data de lançamento, tiragem (quando conhecida) e exclusividade. Isso mantém o catálogo de tipos enxuto e evita que ele cresça indefinidamente a cada nova caixa, blister ou coleção promocional lançada.

## Validação — Versão 1.3

Query `950 - Validate Card Variant Type` (v1.3) valida: existência do Game, quantidade canônica (13 para `POKEMON`), presença e aderência dos 13 códigos esperados (incluindo `COSMOS_HOLO`), tipos fora do catálogo canônico, duplicidades de `code`/`display_order`, formato de `code`, campos obrigatórios, sequência de `display_order` (1 a 13), relacionamento com Game, timestamps, trigger de `updated_at` e RLS. **Mudança de padrão nesta versão**: reescrita como bloco executável (`DO $$`) com `RAISE EXCEPTION` e rollback automático em qualquer inconsistência, substituindo o padrão anterior (v1.0–v1.2) de `SELECT`s apenas informativos. Executada com sucesso logo após `850` v1.3 — confirmado por Fabrício.

## Nomenclatura — RESOLVIDA (ADR-016)

ADR-010 havia renomeado o conceito antes chamado "Card Variant" para **Finish**/**Card Finish**, deixando em aberto se as tabelas físicas pré-existentes `card_variant`/`card_variant_type` (parte do conjunto original de 17 tabelas, anteriores a esta fase de documentação) seriam renomeadas para acompanhar. Essa renomeação física nunca aconteceu, nem foi necessária: toda a modelagem física subsequente (Queries `150`/`151`/`160`/`161`/`850`/`950`/`860`, e a própria ADR-008) foi construída e executada sob os nomes `card_variant_type`/`card_variant`, sem qualquer referência a "Finish".

**Fabrício resolveu a tensão (2026-07-23, ADR-016): o vocabulário conceitual do domínio converge para "Card Variant Type"/"Card Variant"**, revertendo especificamente a parte de nomenclatura de ADR-010 — a separação de Rarity como atributo de primeira classe da Card, também decidida em ADR-010, permanece válida e não foi afetada. Nenhuma alteração física é necessária: `card_variant_type`/`card_variant` já usam o nome agora também canônico no vocabulário conceitual.

## Definition of Done

- [x] modelo físico definido e executado (`150`, v1.0);
- [x] trigger de `updated_at` criado e confirmado (`151`, v1.0);
- [x] RLS habilitado;
- [x] seed executada com sucesso — 13 tipos canônicos (`850` v1.3, incluindo `COSMOS_HOLO` e os 6 tipos de reversa específica descobertos na análise da ME2.5);
- [x] validação executada com sucesso (`950` v1.3, reescrita como bloco `DO $$` com `RAISE EXCEPTION`);
- [x] arquivos `150`/`151`/`850`/`950` copiados para `database/` (`850`/`950` sobrescritos em vigor, v1.3 — Princípio da Fonte Canônica);
- [x] entidade Card Variant (associação Card ↔ Card Variant Type) — estrutura executada, ver seção própria abaixo;
- [x] nomenclatura conceitual resolvida — Card Variant Type/Card Variant (ADR-016), revertendo Finish/Card Finish (ADR-010);
- [ ] distinção reconhecida entre acabamento (`card_variant_type`) e origem/distribuição de uma impressão promocional — necessidade identificada, entidade futura ainda não modelada (ver "Distinção Reconhecida", acima).

## Queries Associadas

```text
150 - Create Card Variant Type Table     (v1.0, Status CANÔNICA — executada e confirmada)
151 - Create Card Variant Type Triggers  (v1.0, Status CANÔNICA — executada e confirmada)
850 - Seed Card Variant Type             (v1.3, Status CANÔNICA — executada e confirmada, 13 tipos)
950 - Validate Card Variant Type         (v1.3, Status CANÔNICA — executada e confirmada, bloco DO $$ com RAISE EXCEPTION)
```

---

# Card Variant (Variante da Carta)

## Status

**CANONICAMENTE ENCERRADA — estrutura e dados 100% concluídos e executados.** As 5 coleções (ME1/ME2/ME2.5/ME3/ME4) estão totalmente povoadas: 859 Cards, 1.555 Card Variants, com a Query `860` consolidada (substituindo definitivamente `860A`–`860E`) e validadas integralmente pela Query `960` v2.0 — resultado confirmado: 859/859 Cards cobertas, 1.555/1.555 Card Variants, 859/859 variantes padrão, status `COMPLETE` (ver "Query 860", abaixo). Associa uma Card específica a um Card Variant Type específico — representa uma versão colecionável que oficialmente existe para aquela Card (ex.: `ME1-001 — Bulbasaur` possui `STANDARD` e `REVERSE_HOLO`). Não representa uma cópia física: duas cópias físicas da mesma variante serão, no futuro, dois registros distintos de inventário/coleção, não dois registros de `card_variant`.

## Modelo Físico — Versão 1.0

```sql
CREATE TABLE public.card_variant (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id UUID NOT NULL REFERENCES public.card (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    variant_type_id UUID NOT NULL REFERENCES public.card_variant_type (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    variant_order INTEGER NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (card_id, variant_type_id),
    UNIQUE (card_id, variant_order)
);

CREATE UNIQUE INDEX uq_card_variant_one_default_per_card
    ON public.card_variant (card_id)
    WHERE is_default = TRUE;
```

Regras de negócio: `variant_order` deve ser positivo e único dentro da Card (é local à Card, não ao catálogo geral de Card Variant Type — a ordem de apresentação das variantes de uma Card específica pode divergir da ordem canônica dos tipos); no máximo uma variante `is_default = TRUE` por Card, garantido por índice único parcial; a obrigatoriedade de existir pelo menos uma variante padrão por Card será garantida pelo processo de carga e validada pela Query `960` após o Seed `860`; exclusões de Card ou Card Variant Type referenciados são impedidas; RLS habilitado.

**Decisão — sem campo `variant_code` persistido**: seguindo o mesmo precedente já usado para `card_code` (Card) e `secret_set_size` (Card Set), o código legível da variante é derivado, não armazenado: `card_set.code || '-' || card.collector_number || '-' || card_variant_type.code` (ex.: `ME1-001-STANDARD`, `ME1-001-REVERSE_HOLO`). Evita duplicação e risco de divergência entre o código persistido e os dados de origem.

Queries `160 - Create Card Variant Table` e `161 - Create Card Variant Triggers` executadas e confirmadas por Fabrício ("Executado com sucesso").

## Trigger — Consistência de Game

Mesmo padrão já usado em Card (`141`, `validate_card_game_consistency()`): `validate_card_variant_game_consistency()` verifica, antes de INSERT/UPDATE de `card_id`/`variant_type_id`, que a Card (via `Card → Card Set → Expansion → Game`) e o Card Variant Type (via `Card Variant Type → Game`) pertencem ao mesmo Game — evita duplicar `game_id` diretamente em `card_variant`.

## Validação — Query 960 (Versão 2.0, CANÔNICA)

**Evoluída de validação estrutural para validação completa pós-carga**, exatamente como a própria v1.0 já previa que faria. Mantém os 15 blocos estruturais originais (existência da tabela, colunas, constraints — PK/2 FK/2 UNIQUE/1 CHECK, índices — incluindo o índice único parcial da variante padrão, triggers, funções, RLS, integridade referencial, inconsistência de Game, unicidade lógica) e acrescenta a validação completa da carga editorial: cobertura exata das 859 Cards, total exato de 1.555 Card Variants, quantidade de Cards/variantes por Card Set (5 coleções), exatamente uma variante padrão por Card (sempre na posição `variant_order = 1`, sempre `STANDARD` ou `HOLO`), sequência contínua de `variant_order` dentro de cada Card, e distribuição canônica completa por Card Set + Card Variant Type (24 combinações esperadas, cobrindo os 12 tipos de variante). Qualquer divergência provoca `RAISE EXCEPTION` e rollback integral.

**Resultado real, executado e confirmado:** `covered_cards` 859/859, `registered_variants` 1.555/1.555, `default_variants` 859/859, `status` `COMPLETE`. Fecha o ciclo `160 → 860 → 960` como referência definitiva da camada de Card Variant. Arquivo copiado para `database/validations/960_validate_card_variant.sql`, substituindo em vigor a versão 1.0 (`960_validate_card_variant_structure.sql`, removida do repositório com permissão de Fabrício — Princípio da Fonte Canônica).

## Seed 860 — CONCLUÍDO E EXECUTADO (histórico do planejamento original, preservado)

Ver `04-domain-model.md`, seção Card Variant Type/Card Variant, para o raciocínio completo. Resumo (histórico do planejamento original): não existe fonte oficial única e estruturada com todas as variantes de cada Card — o Seed foi produzido por um pipeline (`Checklist oficial + TCGdex campo variants + Pokémon TCG API como evidência complementar + validação manual de exceções → dataset intermediário rastreável → Query 860`), consistente com o padrão Import/Synchronization já estabelecido em `ADR-008`/`06-pipeline-importacao.md`. Dado o volume estimado (859 Cards, 1.555 registros de Card Variant no total real), o trabalho foi dividido e validado por Card Set (`860A`–`860E`) e depois consolidado na Query canônica `860`, conforme planejado.

**Refinamento da estratégia (executado integralmente).** Fabrício recusou a recomendação de adiar `860` e abrir o domínio `200 — Collections` em paralelo ("Não temos como fugir dele!") — reafirmando a disciplina já registrada de não abrir Coleções enquanto o Catálogo Editorial estiver incompleto (ver roadmap de prioridades em memória). Processo confirmado por Card Set (cinco etapas): identificar variantes nas fontes → cruzar com Cards já cadastradas → classificar automaticamente casos seguros → separar divergências/exceções → gerar UPSERT canônico. Regra de `variant_order`: local à Card, sequencial e sem lacunas (não usa a ordem global de Card Variant Type quando a Card não possui todos os tipos). Regra de `is_default`: `STANDARD`/`HOLO` padrão conforme a impressão principal seja normal ou holográfica; demais variantes não são padrão salvo evidência excepcional. Forma da carga: `INSERT ... ON CONFLICT (card_id, variant_type_id) DO UPDATE` idempotente, com validações internas (Card/Variant Type inexistentes, duplicidade, mais de uma ou nenhuma variante padrão por Card, ordem duplicada/descontínua, inconsistência de Game, contagem divergente da esperada) — todas confirmadas sem erro nas cinco execuções e na execução consolidada. As cinco execuções por coleção (`860A`–`860E`) foram concluídas e, em seguida, consolidadas em uma única Query canônica (`860`), com os cinco arquivos intermediários removidos de `database/seeds/` (Princípio da Fonte Canônica).

**Discrepância sinalizada, parcialmente esclarecida**: o plano de staging cita `860F` para um Card Set "`ME5`", que não existe no catálogo atual — provável reaproveitamento por engano do rótulo "`ME5`", já usado neste documento como exemplo hipotético de expansão futura. **Atualização (2026-07-23):** a resposta não é `ME0` nem `ME5` — Fabrício esclareceu que o próprio código `ME0` estava errado (correto: `MEP`, ver seção Set/Card Set Promocional, acima) e que um novo Card Set oficial `MEE` ("Energy Set") foi criado, possivelmente relevante para a discrepância `ENERGY`. O plano de staging do Seed `860` será revisado quando a SQL/migration dessa correção for recebida; nada alterado em `database/` ainda.

**Extensão a `MEE`/`MEP` — CONCLUÍDA E EXECUTADA (2026-07-24).** O plano original de renomear a antiga `860A` (ME1) para `860C` e reorganizar `860C`-`860G` por ordem cronológica (ver revisão anterior deste parágrafo, preservada no histórico do repositório) foi **explicitamente abandonado por Fabrício antes de qualquer execução**: "A renumeração que eu havia proposto para transformar a antiga `860A` (ME1) em `860C` também não deve ser feita agora. Isso criaria trabalho documental sem benefício e poderia gerar confusão com o histórico já executado. Mantemos os nomes atuais das Queries existentes e atribuímos um código novo apenas para o MEE e o MEP." Como os cinco arquivos intermediários originais (antigo `860A`-`860E`, para `ME1`-`ME4`) já haviam sido consolidados e removidos em favor de `860_seed_card_variant.sql` (ver "Nota histórica", abaixo), não havia de fato colisão de nomes de arquivo a resolver — apenas dois códigos novos foram necessários. **⚠️ Atenção, letra reaproveitada**: as letras `A`/`B` abaixo referem-se a `MEE`/`MEP` (2026-07-24), não a `ME1`/`ME2` como nas menções históricas de `860A`/`860B` no restante desta seção (essas descrevem os arquivos intermediários já removidos, preservados aqui apenas como registro histórico). `860_seed_card_variant.sql` (a Query consolidada para `ME1`-`ME4`/`ME2.5`) permanece inalterado, sem renomeação. Executados e confirmados: `database/seeds/860a_seed_card_variant_mee.sql` (v1.0, CANÔNICA — 8 Cards, 16 Card Variants: 8 `STANDARD` + 8 `REVERSE_HOLO`) e `database/seeds/860b_seed_card_variant_mep.sql` (v1.0, CANÔNICA — 60 Cards, 82 Card Variants: 59 `HOLO` + 23 `PROMO_STAMPED`). Detalhamento de cada execução na seção "Query 860", abaixo.

## Definition of Done

- [x] arquitetura validada formalmente antes da escrita das Queries (Card → Card Variant → Collection Item);
- [x] modelo físico definido e executado (`160`, v1.0);
- [x] decisão sobre `variant_code` não persistido, documentada;
- [x] trigger de `updated_at` criado e confirmado (`161`, v1.0);
- [x] trigger de consistência de Game criado e confirmado (`161`, v1.0);
- [x] RLS habilitado;
- [x] validação estrutural executada com sucesso (`960` v1.0, 17 blocos — tabela ainda vazia, sem erro); posteriormente evoluída para `960` v2.0 (validação completa pós-carga, ver seção própria abaixo);
- [x] arquivos `160`/`161`/`860`/`960` copiados para `database/`;
- [x] arquitetura da Query `860` homologada (matriz JSONB autocontida, sem tabelas temporárias, validação pós-carga em passos) — comprovada por cinco execuções reais por coleção (`860A`–`860E`) e consolidada em uma única Query canônica;
- [x] `860A` (ME1) executada e confirmada — 310 Card Variants (111 `STANDARD`/77 `HOLO`/122 `REVERSE_HOLO`);
- [x] `860B` (ME2) executada e confirmada — 214 Card Variants (74 `STANDARD`/56 `HOLO`/84 `REVERSE_HOLO`);
- [x] `860C` (ME2.5) executada e confirmada — 630 Card Variants (153 `STANDARD`/142 `HOLO`/7 `COSMOS_HOLO`/38 `REVERSE_HOLO`/140 `ENERGY_REVERSE`/140 reversas de bola-ou-Rocket/10 `PROMO_STAMPED`), ver seção Card Asset Type/Card Asset, "Query 860";
- [x] `860D` (ME3) executada e confirmada — 203 Card Variants (68 `STANDARD`/56 `HOLO`/79 `REVERSE_HOLO`);
- [x] `860E` (ME4) executada e confirmada — 198 Card Variants (64 `STANDARD`/58 `HOLO`/76 `REVERSE_HOLO`; 10 Cards Rara Dupla `ex` excluídas de `REVERSE_HOLO`, uma a mais que `860D`, confirmando que a exceção é por classificação editorial, não por contagem fixa);
- [x] Query `860` consolidada (v1.0, CANÔNICA CONSOLIDADA) — todas as 5 coleções em uma única transação, `v_set_catalog` + `v_matrix` JSONB, UPSERT set-based via `jsonb_to_recordset`, 11 passos de validação; substitui definitivamente `860A`–`860E`, que foram removidas de `database/` com permissão de Fabrício (Princípio da Fonte Canônica). Resultado real: **859 Cards, 1.555 Card Variants** — distribuição global: `STANDARD` 470, `HOLO` 389, `REVERSE_HOLO` 399, `ENERGY_REVERSE` 140, `POKE_BALL_REVERSE` 34, `LOVE_BALL_REVERSE` 25, `FRIEND_BALL_REVERSE` 23, `QUICK_BALL_REVERSE` 22, `DUSK_BALL_REVERSE` 26, `ROCKET_REVERSE` 10, `COSMOS_HOLO` 7, `PROMO_STAMPED` 10;
- [x] Query `960` v2.0 (CANÔNICA) executada e confirmada — validação completa pós-carga (estrutura + cobertura + distribuição), resultado `COMPLETE` (859/859 Cards, 1.555/1.555 Card Variants, 859/859 variantes padrão);
- [x] nomenclatura conceitual resolvida — Card Variant Type/Card Variant (ADR-016), revertendo Finish/Card Finish (ADR-010); consistente com `ADR-008`, que já listava "Card Variant" entre as entidades do Catálogo Editorial;
- [x] **`860A - Seed Card Variant MEE` (v1.0, CANÔNICA) executada e confirmada (2026-07-24)** — 16 Card Variants (8 `STANDARD`/8 `REVERSE_HOLO`) para as 8 Cards de `MEE`;
- [x] **`860B - Seed Card Variant MEP` (v1.0, CANÔNICA) executada e confirmada (2026-07-24)** — 82 Card Variants (59 `HOLO`/23 `PROMO_STAMPED`) para as 60 Cards de `MEP`;
- [x] **`960` evoluída para v2.1 (CANÔNICA), executada e confirmada (2026-07-24)** — escopo estendido às 7 Card Sets, resultado `COMPLETE` (927/927 Cards, 1.653/1.653 Card Variants, 927/927 variantes padrão).

## Queries Associadas

```text
160 - Create Card Variant Table              (v1.0, Status CANÔNICA — executada e confirmada)
161 - Create Card Variant Triggers            (v1.0, Status CANÔNICA — executada e confirmada)
860 - Seed Card Variant                       (v1.0, Status CANÔNICA CONSOLIDADA — executada e confirmada, 859 Cards / 1.555 Card Variants, ME1-ME4/ME2.5; substitui os antigos arquivos intermediários 860A-860E dessas 5 coleções)
860A - Seed Card Variant MEE                  (v1.0, Status CANÔNICA — executada e confirmada, 8 Cards / 16 Card Variants; letra reaproveitada para MEE, não colide com o 860A histórico de ME1, já removido)
860B - Seed Card Variant MEP                  (v1.0, Status CANÔNICA — executada e confirmada, 60 Cards / 82 Card Variants)
960 - Validate Card Variant                   (v2.1, Status CANÔNICA — executada e confirmada, 7 Card Sets, 927 Cards / 1.653 Card Variants, status COMPLETE)
```

**Nota histórica (Princípio da Fonte Canônica)**: as migrations intermediárias `860A` (ME1), `860B` (ME2), `860C` (ME2.5), `860D` (ME3) e `860E` (ME4) foram cada uma escrita, executada e confirmada individualmente antes da consolidação — seus resultados reais permanecem documentados nos parágrafos da seção "Query 860", abaixo, e no Definition of Done, acima. Os cinco arquivos foram removidos de `database/seeds/` com permissão explícita de Fabrício, mantendo apenas `860_seed_card_variant.sql` como fonte única de verdade, consistente com o padrão já aplicado a `850`/`950`.

**Marco confirmado por Fabrício — camada de Card Variant canonicamente encerrada para as 5 coleções originais**: com `150`/`151`/`160`/`161`/`850`/`950`/`860`/`960` todos executados e confirmados, o bloco "Editorial Catalog" (`100`) estava estrutural e editorialmente completo para as 5 coleções (ME1, ME2, ME2.5, ME3, ME4) — 859 Cards, 1.555 Card Variants, validados integralmente. **Atualização (2026-07-24) — extensão a `MEE`/`MEP` CONCLUÍDA E EXECUTADA**: com `860A - Seed Card Variant MEE` (v1.0), `860B - Seed Card Variant MEP` (v1.0) e `960 - Validate Card Variant` (v2.1) todos executados e confirmados, a camada de Card Variant passa a cobrir as **7 Card Sets** da Expansion `ME` — **927 Cards, 1.653 Card Variants**, validados integralmente, `status COMPLETE`. Ver "Query 860", abaixo, para o detalhamento de `860A`/`860B`. A modelagem editorial das variantes segue como base estável para as próximas funcionalidades. Próximo grande bloco: completar Card Asset para `MEE`/`MEP` (imagens, via `import-card-assets` — ver `06-pipeline-importacao.md`/`ADR-018`), depois retomar a Sub-Fase 2 (Coleções). Fabrício foi explícito sobre a granularidade correta desse próximo marco: "Não teremos encerrado toda a fundação do catálogo editorial do Project Mimikyu. Só concluímos após importação de todas as imagens para nossa base."

**Reconfirmação real, Sprint B3.11 do Bloco B (ver `06-pipeline-importacao.md` para o episódio completo)**: durante o planejamento do pipeline de importação de imagens (`import-card-assets`), a sessão pareada, momentaneamente, tratou `card`/`card_variant` como ainda vazias e a preencher a partir da TCGdex — contrariando este marco, já fechado há dezenas de batches. Fabrício corrigiu diretamente, lembrando que os 859 Cards/1.555 Card Variants já estavam carregados. Duas queries de auditoria real (`SELECT * FROM public.card`/`public.card_variant`) foram executadas contra o banco físico e confirmaram, sem divergência, tanto os totais (`859`/`1.555`) quanto a estrutura de colunas exatamente como documentada nesta seção (sem colunas denormalizadas de código/nome, apenas FKs/UUIDs). Decisão real resultante: o pipeline de `import-card-assets` passa a **consultar** `card` (nunca inserir), usando-a como base para popular `card_external_reference` e, depois, `card_asset` — `card`/`card_variant` permanecem congeladas, fora do escopo do Bloco B.

---

# Card Asset Type (Tipo de Ativo da Carta) / Card Asset (Ativo da Carta)

## Status

**Marco: camada Card Asset estruturalmente concluída e HOMOLOGADA.** Card Asset Type: pacote técnico CONCLUÍDO E EXECUTADO (`170`/`171`/`870`/`970`, ver "SQL confirmada" abaixo). Card Asset: `180`/`181` confirmados; governança de idioma e provedor (`193`/`194`) CONFIRMADAS EXECUTADAS por Fabrício ("Houve execução real de 193 e 194."); `storage_provider` **removido definitivamente** de `card_asset` pela migration `197 - Integrate Storage Bucket into Card Asset` (CONFIRMADA EXECUTADA nesta revisão) em favor de `storage_bucket_id` (FK obrigatória para a nova entidade `storage_bucket`, ver seção própria abaixo); validação `980 - Validate Card Asset` (v2.0, 28 blocos) **CONFIRMADA EXECUTADA e HOMOLOGADA**. A partir desta revisão, a estrutura de `card_asset` está congelada — qualquer nova mudança estrutural exigirá uma nova migration explícita, não uma correção implícita. Nomenclatura final "Card Asset"/"Card Asset Type" (não "Card Image", nome inicialmente cogitado e depois generalizado — ver `04-domain-model.md` para o raciocínio completo, incluindo o exemplo Bulbasaur/Standard/Reverse Holo que motivou a generalização).

> **Colisão confirmada com tabelas físicas já existentes — divergências reais encontradas.** `card_asset` e `card_asset_type` já constam entre as 17 tabelas físicas pré-existentes a esta fase de documentação. Fabrício confirmou via captura de tela do Table Editor: `card_asset_type` bate exatamente com a proposta. `card_asset` diverge em três pontos — ver "Estrutura Física Real", abaixo. `170`/`180` não devem ser escritas como `CREATE TABLE` novo — as tabelas já existem; falta apenas documentação retroativa (mesmo padrão já usado para Game/Card/etc.), não criação.

## Estrutura Proposta (discussão inicial, anterior à confirmação física)

`card_asset_type`: `id, game_id, code, name, description, asset_order, is_active, created_at, updated_at`. Catálogo inicial sugerido: `CARD_FRONT`, `CARD_BACK`, `ARTWORK`, `THUMBNAIL`, `SET_SYMBOL` (finalidade semântica, não resolução — `SMALL`/`LARGE`/`HIRES` foram deliberadamente descartados como tipos).

`card_asset` (proposta original, **divergente da estrutura física real** — ver abaixo): `id, card_id, card_variant_id, asset_type_id, source_code, source_reference, storage_provider, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active, created_at, updated_at`.

## Estrutura Física Real (histórico — confirmada via Table Editor antes da Query `197`)

`card_asset_type`: idêntica à proposta.

`card_asset`, ANTES de `197` (20 colunas): `id, card_id, asset_type_id, source_code, source_reference, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active, created_at, updated_at, language_id, storage_bucket_id` — mais `storage_provider` (adicionada por `194`, coexistindo temporariamente com `storage_bucket_id`).

Três divergências em relação à proposta original — a primeira explicada, a segunda superada por `197`, a terceira explicada:

1. **Sem `card_variant_id` — RESOLVIDO/EXPLICADO.** Fabrício corrigiu explicitamente o design: "Não pretendi representar com imagens as variações das cartas! A ilustração será representada de uma única forma." Confirmado: `card_asset` não se relaciona com `card_variant` — a imagem pertence exclusivamente à Card. Arquitetura final: Card possui identidade visual única; Card Variant representa acabamento/impressão/distribuição; Card Asset representa digitalmente a Card, nunca a Variant. A ausência de `card_variant_id` na tabela física era intencional, não uma lacuna.
2. **`storage_bucket_id`/`storage_provider` — SUPERADO pela Query `197` (CONFIRMADA EXECUTADA).** `storage_bucket_id` já era, como suspeitado no "Risco 1" da revisão `0.43`, uma FK para a tabela `storage_bucket` (própria entidade, criada/homologada nesta revisão via `195`/`196`/`895`/`975`). Como o bucket já carrega seu próprio `storage_provider`, manter `storage_provider` também em `card_asset` era redundante. A Query `197 - Integrate Storage Bucket into Card Asset` **removeu definitivamente `storage_provider` de `card_asset`** e tornou `storage_bucket_id` obrigatório (`NOT NULL`) — ver "Estrutura Física Real — Atual", abaixo, para o estado corrente.
3. **`language_id`** (FK para `language`) — coluna presente e com propósito explicado (idioma da imagem digital, não tradução editorial nem idioma do exemplar físico — ver seção "Language (Idioma)", abaixo, e "Três Dimensões de Idioma" em `04-domain-model.md`). A coluna já existia fisicamente antes de `193` ser escrita (consistente com a listagem original da revisão `0.30`); o passo `ADD COLUMN IF NOT EXISTS language_id` de `193` foi, portanto, um no-op para a coluna em si. As alterações de constraint/índice de `193` (unicidade e ativo principal por idioma) confirmadas por Fabrício ("Houve execução real de 193 e 194.").

## Estrutura Física Real — Atual (após `197`, CONFIRMADA EXECUTADA)

`card_asset` (19 colunas, `storage_provider` removida): `id, card_id, asset_type_id, source_code, source_reference, storage_bucket_id, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active, created_at, updated_at, language_id`. `storage_bucket_id` agora `NOT NULL`, com FK `fk_card_asset_storage_bucket` para `storage_bucket.id`. Localização do arquivo resolvida via `JOIN` com `storage_bucket` (não mais uma coluna própria em `card_asset`) — ver "Query 197", abaixo.

## Regras adicionais de `card_asset` (vigentes, CONFIRMADAS EXECUTADAS)

**Localização do arquivo — regra reescrita por `197`.** Não depende mais de `card_asset.storage_provider` (removida); depende do `storage_provider` do bucket referenciado por `storage_bucket_id`, aplicada via trigger `trg_card_asset_validate_storage`/função `validate_card_asset_storage()` (ver "Query 197", abaixo): bucket com `storage_provider = EXTERNAL` exige `external_url` preenchido e `storage_path` nulo; qualquer outro provider exige `storage_path` preenchido e `external_url` nulo. Integridade técnica adicional, já vigente: `asset_order` positivo (`CHECK`), Asset Type do mesmo Game da Card, sem duplicidade lógica, exclusão protegida (FKs `ON DELETE RESTRICT`), RLS habilitado. Escopo inicial da futura `880` continua reduzido a `CARD_FRONT` (uma imagem por Card por idioma); `ARTWORK`/`CARD_BACK` catalogados para uso futuro.

**Ativo principal e unicidade — CONFIRMADAS EXECUTADAS (Query `193`), reafirmadas pela validação `980` v2.0.** Regra anterior (sem dimensão de idioma): no máximo um `is_primary = TRUE` por `card_id` + `asset_type_id`, via índice único parcial `uq_card_asset_one_primary`; unicidade lógica por `card_id` + `asset_type_id` + `asset_order`. **Regra vigente, aplicada por `193`**: cada combinação `card_id` + `asset_type_id` + `language_id` tem seu próprio ativo principal — no máximo um `is_primary = TRUE` por `card_id` + `asset_type_id` + `language_id` (índice `ux_card_asset_primary_per_card_type_language`); unicidade lógica é `card_id` + `asset_type_id` + `language_id` + `asset_order` (constraint `uq_card_asset_card_type_language_order`). Isso permite que a mesma Card tenha, por exemplo, um `CARD_FRONT` principal em português (`asset_order = 1`, `is_primary = TRUE`) e outro `CARD_FRONT` principal em inglês (`asset_order = 1`, `is_primary = TRUE`), sem conflito.

## SQL confirmada — `170`/`171`/`870`/`970` — CONCLUÍDA E EXECUTADA

**Bloco encerrado.** Escrito em `database/` com cabeçalho reformatado para STD-001 e comentários traduzidos (lógica idêntica ao executado): `schema/170_create_card_asset_type_table.sql`, `schema/171_create_card_asset_type_triggers.sql`, `seeds/870_seed_card_asset_type.sql`, `validations/970_validate_card_asset_type.sql`.

`170`/`171` confirmados por **inferência técnica direta** (mesmo padrão de `140`/`141`): a validação estrutural completa de `970` (tabela/PK/FK/constraints/índices/trigger/RLS) só passa se `170`/`171` já tiverem sido aplicadas.

**Ciclo real de erro e correção no Seed `870`**, confirmando o problema já sinalizado antes da execução:
1. **v1.0**: código de Game `POKEMON_TCG` (inexistente) + textos em inglês. Execução real falhou com `ERROR: P0001: Game with code POKEMON_TCG was not found` — exatamente o erro previsto nesta documentação.
2. **v1.1**: corrigiu apenas o idioma, mantendo o bug do código de Game.
3. **v1.2** (executada com sucesso): corrigiu código de Game para `POKEMON` (o real, usado por todos os demais seeds) e idioma. Fabrício rejeitou a sugestão da sessão pareada de inserir um novo Game/adivinhar um código ("Não quero correr o risco de outras inconsistências"), forçando a correção baseada no histórico real do projeto.

**Autocorreção da sessão pareada**: reconheceu o erro ("deveria ter preservado o padrão já estabelecido ou solicitado confirmação") e se comprometeu a validar nomes/códigos consolidados do projeto antes de cada nova Query.

`970` v1.2 confirmou sucesso com marcador próprio: *"Query 970 concluída com sucesso: card_asset_type está estruturalmente válida e com a carga canônica correta."* Catálogo final (Game `POKEMON`): `CARD_FRONT`/`ARTWORK`/`CARD_BACK`, ordem 1/2/3, todos `is_active = TRUE`.

## SQL confirmada — `180`/`181`/`980` — CONCLUÍDA E EXECUTADA (v1.1), com ressalva técnica NÃO resolvida

Regeneradas a pedido de Fabrício, confirmadas diretamente: **"Excelente. Executadas com sucesso."** Cabeçalho já em padrão STD-001, sem reformatação necessária — escritas em `database/schema/180_create_card_asset_table.sql`, `database/schema/181_create_card_asset_triggers.sql`, `database/validations/980_validate_card_asset_structure.sql`. Função/trigger de `181` estruturalmente idêntica ao padrão de `161`.

> **Ressalva técnica importante, não resolvida**: `card_asset` já existia fisicamente (20 colunas reais, incluindo `storage_bucket_id`/`language_id`, sem `storage_provider` — ver seção "Estrutura Física Real", acima). `180` usa `CREATE TABLE IF NOT EXISTS`, um no-op completo em PostgreSQL quando a tabela já existe — as 19 colunas propostas (com `storage_provider`, sem `storage_bucket_id`/`language_id`) provavelmente não foram de fato aplicadas. "Executadas com sucesso" é compatível com esse no-op silencioso. `181` (triggers) é diferente — só referencia `card_id`/`asset_type_id`, ambas reais, então a criação do trigger é genuína. `980` é só `SELECT`s informativos (sem `RAISE EXCEPTION`) — não teria acusado erro mesmo com contagens divergentes (bloco 2 espera 19 colunas; real são 20). **Pergunta em aberto para Fabrício**: os blocos 2/3 de `980` retornaram os números documentados, ou a estrutura real de 20 colunas permanece? Se a segunda, será necessária migration/`ALTER TABLE` — não presumido.

## Queries

```text
170 - Create Card Asset Type Table       (EXECUTADA — inferência técnica via 970)
171 - Create Card Asset Type Triggers    (EXECUTADA — inferência técnica via 970)
870 - Seed Card Asset Type               (EXECUTADA v1.2 — código de Game e idioma corrigidos)
970 - Validate Card Asset Type           (EXECUTADA v1.2 — sucesso confirmado com marcador próprio)

180 - Create Card Asset Table            (EXECUTADA v1.1 — possível no-op contra tabela já existente, ver ressalva acima)
181 - Create Card Asset Triggers         (EXECUTADA v1.1 — trigger genuinamente criado)
980 - Validate Card Asset Structure      (EXECUTADA v1.1 — SUPERADA por 980 v2.0, abaixo; arquivo antigo removido do database/ com permissão de Fabrício)

190 - Create Language Table              (EXECUTADA — ver seção "Language", abaixo)
191 - Create Language Triggers           (EXECUTADA)
192 - Refine Language Code Constraint    (EXECUTADA — ajuste de constraint, NÃO é a migration de card_asset)
193 - Add Language to Card Asset         (CONFIRMADA EXECUTADA por Fabrício — ver "Language")
194 - Govern Card Asset Storage Provider (CONFIRMADA EXECUTADA por Fabrício — ver "Language"; será revertida por 197, ver "Arquitetura de Armazenamento")
890 - Seed Language                      (EXECUTADA — pt-BR/en, não depende de card_asset)
970 - Validate Language                  (EXECUTADA — ⚠️ colide em número com 970 - Validate Card Asset Type, ver nota de numeração abaixo)

195 - Create Storage Bucket              (EXECUTADA — ver seção "Storage Bucket", abaixo)
196 - Create Storage Bucket Triggers     (EXECUTADA)
895 - Seed Storage Bucket                (EXECUTADA — card-front/artwork/card-back)
975 - Validate Storage Bucket            (EXECUTADA v1.1 — ⚠️ deveria ser 995 pelo padrão de deslocamento fixo, ver nota de numeração abaixo)

197 - Integrate Storage Bucket into Card Asset (CONFIRMADA EXECUTADA — adiciona storage_bucket_id NOT NULL, cria FK, remove storage_provider definitivamente; ver "Query 197", abaixo)
980 - Validate Card Asset (v2.0)         (CONFIRMADA EXECUTADA e HOMOLOGADA — 28 blocos; ver "Query 980", abaixo)

200 - Create Asset Source                (CONFIRMADA EXECUTADA — ver seção "Asset Source", abaixo)
201 - Asset Source Triggers              (CONFIRMADA EXECUTADA)
900 - Seed Asset Source                  (CONFIRMADA EXECUTADA — ⚠️ colide em número com 900 - Validate Game, ver nota de numeração abaixo)
985 - Validate Asset Source              (CONFIRMADA EXECUTADA e HOMOLOGADA)

210 - Create Card External Reference     (CONFIRMADA EXECUTADA — ver seção "Card External Reference", abaixo)
211 - Card External Reference Triggers   (CONFIRMADA EXECUTADA)
910 - Seed Card External Reference       (DESCARTADA DELIBERADAMENTE — registros serão produzidos pela própria rotina de importação, não por seed estático)
990 - Validate Card External Reference   (CONFIRMADA EXECUTADA e HOMOLOGADA)

220 - Create Asset Import Run            (CONFIRMADA EXECUTADA — ver "Query 220", acima)
221 - Asset Import Run Triggers          (CONFIRMADA EXECUTADA)
230 - Create Asset Import Failure        (CONFIRMADA EXECUTADA — ver "Query 230", acima)
231 - Asset Import Failure Triggers      (CONFIRMADA EXECUTADA)
995 - Validate Asset Import Infrastructure (CONFIRMADA EXECUTADA E HOMOLOGADA)

880 - Seed Card Asset                    (planejada — escopo confirmado: apenas CARD_FRONT, card_id direto; infraestrutura de importação 100% pronta; bloqueada até que o pipeline de importação [Fase 1, Bloco B — Edge Function] seja implementado, ver "Roteiro Consolidado", abaixo)
```

> **⚠️ Discrepância de numeração, sinalizada nesta revisão, NÃO resolvida unilateralmente.** O projeto já usa um padrão implícito de deslocamento fixo (Seed = Create + 700, Validate = Create + 800 — ver seção Expansion, "regra de deslocamento fixo", e o próprio par `170`→`970`/`180`→`980` já executado). Por esse padrão, `190 - Create Language` deveria validar como `990`, e `195 - Create Storage Bucket` como `995`. Em vez disso, a sessão pareada numerou as duas novas validações desta revisão como `970` e `975`. O número `970` **já pertencia** a `970 - Validate Card Asset Type` (executada em ciclo muito anterior, arquivo `database/validations/970_validate_card_asset_type.sql`) — ou seja, existem agora duas Queries distintas, ambas executadas contra o banco real, ambas se autodenominando "Query 970" em seus próprios cabeçalhos. Isso não quebra a execução em si (cada uma é um bloco `DO $$` autocontido, sem depender do número), mas quebra a rastreabilidade do catálogo de Queries. Os arquivos foram gravados como `database/validations/970_validate_language.sql` e `database/validations/975_validate_storage_bucket.sql`, preservando os números exatamente como executados no Supabase — nenhuma Query foi renumerada retroativamente. Recomendação (não decisão): a partir de agora, novas validações de entidades de catálogo devem seguir `Create + 800` (ex.: a próxima seria `990` ou, se preferir manter `970`/`975`, os números futuros de Card Asset Type precisam ser resguardados de reuso).

> **⚠️ Nova discrepância de numeração, sinalizada nesta revisão (batch 54), NÃO resolvida unilateralmente — colisão em `900`.** A `900 - Seed Asset Source` (Create = `200`, logo `200 + 700 = 900`, matematicamente correto pelo padrão de deslocamento fixo) colide diretamente com a já existente e já executada `900 - Validate Game` (Create = `100`, `100 + 800 = 900` — documentada desde a primeira entidade deste projeto, arquivo `database/validations/900_validate_game.sql`). Diferente da colisão de `970` (mesmo padrão de deslocamento, faixas diferentes se sobrepondo), esta colisão é estrutural: dentro da faixa de Infraestrutura de Importação (`200`-`299`), `900` é simultaneamente "Seed" (deslocamento `+700` a partir de `200`) e, na faixa de Game (`000`-`099`), `900` já é "Validate" (deslocamento `+800` a partir de `100`) — os dois esquemas de deslocamento fixo, aplicados a faixas de Create diferentes, convergem para o mesmo número final. O arquivo foi gravado como `database/seeds/900_seed_asset_source.sql`, preservando o número exatamente como executado — nenhuma renumeração retroativa foi feita. Recomendação forte (não decisão): antes de numerar `910`/`920`/`995` (próximas camadas do pipeline), Fabrício e a sessão pareada devem definir uma regra explícita de reserva de faixas de Seed/Validate por range de Create (ex.: Seed/Validate de `200`-`299` poderiam usar uma faixa dedicada, como `280`-`299`, em vez de reaproveitar `900`-`999`), para evitar que futuras entidades do pipeline colidam novamente com Game/Expansion/Set/Card/Rarity/etc., que já ocupam boa parte de `900`-`999`.

## Query 860 — `860A`–`860E` CONCLUÍDAS, EXECUTADAS E CONSOLIDADAS; camada de Card Variant canonicamente encerrada

Ordem confirmada por Fabrício: `860` antes de `880`.

**Metodologia homologada** (dois resultados reais batendo exatamente com o esperado): Matriz Editorial de Variantes explícita construída e validada por coleção, antes de qualquer SQL — `860X.1` construção → `860X.2` validação → `860X.3` geração (bloco `DO $$` autocontido, matriz JSONB embutida, sem tabelas temporárias) → validação pós-carga. **Opção A** (derivação dinâmica via Rarity) rejeitada — usada só para validar totais da ME1. **Opção B** (matriz explícita, sem inferência) adotada e confirmada em produção duas vezes.

**Ambiguidade de `variant_order` — RESOLVIDA pela execução real.** As matrizes de `860A`/`860B` confirmam: `variant_order` é local à Card (1, ou 1 e 2), nunca a posição global 1–12 de `card_variant_type.display_order` — são dois conceitos distintos, confirmado na prática. `is_default`: `STANDARD` padrão quando existir; `HOLO` padrão só na ausência de `STANDARD`; `REVERSE_HOLO` nunca padrão.

**`860A` (ME1) — EXECUTADA.** Matriz: `001`–`132` `COMMON`/`UNCOMMON` → `STANDARD`+`REVERSE_HOLO`; 11 `RARE` → `HOLO`+`REVERSE_HOLO`; 10 `DOUBLE_RARE` (Mega `ex`) → apenas `HOLO`; `133`–`188` (Laminadas Padrão) → apenas `HOLO`. Resultado real: **111 `STANDARD` + 77 `HOLO` + 122 `REVERSE_HOLO` = 310**, conferido linha a linha (todos ✅). `POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE` não existem na ME1.

**`860B` (ME2) — EXECUTADA, mesma arquitetura.** 94 Cards no conjunto base, 130 no total. Resultado real: **74 `STANDARD` + 56 `HOLO` + 84 `REVERSE_HOLO` = 214**, confirmado ("Show! Resultado esperado após execução. Vamos em frente."). Com os dois resultados batendo, Fabrício declarou o padrão arquitetural homologado.

**`860C` (ME2.5, Heróis Excelsios) — EXECUTADA.** 217 Cards no conjunto base, 78 secretas, 295 no total. A análise revelou que essa coleção não segue o padrão simples de ME1/ME2: reversa com padrão de Poké Bola específica por linha evolutiva (Poké Ball/Love Ball/Friend Ball/Quick Ball/Dusk Ball), símbolo "R" para Equipe Rocket, reversa de Energia para Pokémon não `ex` — sem evidência de `MASTER_BALL_REVERSE`. Isso exigiu expandir `card_variant_type` de 6 para 12 tipos (`850`/`950` v1.2) antes de `860C` poder ser gerada com segurança — usar `POKE_BALL_REVERSE` para todos esses padrões violaria a regra de negócio da Query `160`.

Regra editorial confirmada: cada Pokémon comum/incomum/raro elegível (não `ex`) recebe variante principal + `ENERGY_REVERSE` + uma reversa específica de bola/Rocket; Pokémon `ex` recebem apenas `HOLO`, sem reversas; Treinadores e Energias elegíveis recebem apenas a `REVERSE_HOLO` genérica; as 78 Cards secretas (`218`–`295`) recebem apenas sua variante principal (`HOLO`). Distribuição de raridade do conjunto base: `COMMON` 84, `UNCOMMON` 69, `RARE` 25, `DOUBLE_RARE` 39 (total 217).

**Matriz construída a partir de uma fonte editorial mais completa que a inicialmente disponível.** A estimativa anterior (613 Card Variants) foi baseada apenas no checklist oficial em PT-BR, que não expõe todas as variantes físicas por Card (faltavam `ENERGY_REVERSE`/reversas de bola específicas e, principalmente, `COSMOS_HOLO`/`PROMO_STAMPED`). O pkmn.gg (fonte editorial complementar, com ficha individual por Card) forneceu essa informação, mas bloqueava acesso automatizado via scraping (`403 Forbidden`) — contornado com a exportação manual, por Fabrício, da página completa em PDF ("Ascended Heroes - Track and Price Pokemon Cards"), cobrindo as 295 Cards. A checklist oficial (PT-BR) continuou sendo a fonte de catalogação/classificação; o PDF do pkmn.gg foi a fonte das variantes físicas de cada Card, incluindo as promocionais.

**Resultado real, executado e confirmado (`860C` v1.0):** `STANDARD` 153 + `HOLO` 142 + `COSMOS_HOLO` 7 + `REVERSE_HOLO` 38 + `ENERGY_REVERSE` 140 + `POKE_BALL_REVERSE` 34 + `LOVE_BALL_REVERSE` 25 + `FRIEND_BALL_REVERSE` 23 + `QUICK_BALL_REVERSE` 22 + `DUSK_BALL_REVERSE` 26 + `ROCKET_REVERSE` 10 + `PROMO_STAMPED` 10 = **630 Card Variants** (613 da estimativa original + 7 `COSMOS_HOLO` + 10 `PROMO_STAMPED`, identificados apenas com a fonte pkmn.gg completa). Matriz explícita em JSONB, mesma arquitetura homologada de `860A`/`860B` (sem tabelas temporárias, validação de referências antes da carga, convergência segura via deslocamento `+1000`, validação pós-carga por tipo com `RAISE EXCEPTION`/rollback). Confirmado por Fabrício ("Sucesso. Vamos avançar com 860D").

**`860D` (ME3, Equilíbrio Perfeito) — EXECUTADA, mesma arquitetura, mesma regra de ME2.** 88 Cards no conjunto base, 124 no total (36 secretas). Regra confirmada com Fabrício antes da geração: as Cards Rara Dupla (`ex`) do conjunto base — nesta coleção, `Decidueye ex`, `Salazzle ex`, `Mega Starmie ex`, `Mega Clefable ex`, `Mega Zygarde ex`, `Yveltal ex`, `Mega Skarmory ex`, `Meowth ex` e outra (9 no total) — não recebem `REVERSE_HOLO`, replicando a exceção já estabelecida em `860B` (ME2). Cards `001`–`088` (exceto as 9 Raras Duplas) recebem `STANDARD`+`REVERSE_HOLO`; Cards `089`–`124` (especiais) recebem apenas `HOLO`. Nenhuma variante promocional externa incluída. **Resultado real: `STANDARD` 68 + `HOLO` 56 + `REVERSE_HOLO` 79 = 203 Card Variants**, conferido por tipo. Confirmado por Fabrício.

**`860E` (ME4) — EXECUTADA, mesma arquitetura, mesma regra de exceção de ME2/ME3.** Regra confirmada: as Cards Rara Dupla (`ex`) do conjunto base — 10 nesta coleção, uma a mais que as 9 de `860D` (ME3) — não recebem `REVERSE_HOLO`, reforçando que a exceção é aplicada por classificação editorial (Rarity `DOUBLE_RARE`), não por uma contagem fixa reaproveitada entre coleções. **Resultado real: `STANDARD` 64 + `HOLO` 58 + `REVERSE_HOLO` 76 = 198 Card Variants**, conferido por tipo. Confirmado por Fabrício. Com as cinco coleções executadas e batendo exatamente com o esperado, a arquitetura da Query `860` foi considerada definitivamente homologada.

**Consolidação — Query `860` (v1.0, CANÔNICA CONSOLIDADA).** Seguindo o Princípio da Fonte Canônica (mesmo padrão já aplicado a `820`/`850`/`930` em ciclos anteriores), as cinco execuções por coleção foram reunidas em uma única Query: `v_set_catalog` (metadados por Set) + `v_matrix` (as 1.555 linhas de todas as coleções, com `set_code`/`collector_number`/`variant_type_code`/`variant_order`/`is_default`) + carga set-based via `INSERT ... SELECT ... FROM jsonb_to_recordset(...) ON CONFLICT (card_id, variant_type_id) DO UPDATE` (substituindo o `FOR ... LOOP` linha-a-linha usado em `860A`–`860E`) + validação pós-carga em 11 passos (Game, catálogo de Sets, matriz, referências, convergência segura via `+1000`, UPSERT, contagem total, distribuição por Set e por tipo via `FULL OUTER JOIN`, variantes adicionais não esperadas, divergências, exatamente uma variante padrão por Card). **Resultado real, executado e confirmado:** 859 Cards, 1.555 Card Variants — `STANDARD` 470 + `HOLO` 389 + `REVERSE_HOLO` 399 + `ENERGY_REVERSE` 140 + `POKE_BALL_REVERSE` 34 + `LOVE_BALL_REVERSE` 25 + `FRIEND_BALL_REVERSE` 23 + `QUICK_BALL_REVERSE` 22 + `DUSK_BALL_REVERSE` 26 + `ROCKET_REVERSE` 10 + `COSMOS_HOLO` 7 + `PROMO_STAMPED` 10. Os cinco arquivos intermediários (`860a`–`860e_seed_card_variant_*.sql`) foram removidos de `database/seeds/` com permissão explícita de Fabrício, restando apenas `860_seed_card_variant.sql` como fonte única de verdade.

**Validação final — Query `960` (v2.0, CANÔNICA, histórico — ver v2.1 abaixo).** Evoluída de validação puramente estrutural (v1.0, 17 blocos, executada quando a tabela ainda estava vazia) para validação completa pós-carga: mantém todos os blocos estruturais e acrescenta cobertura exata das 859 Cards, total exato de 1.555 Card Variants, quantidade por Card Set, exatamente uma variante padrão por Card na posição `variant_order = 1` (sempre `STANDARD` ou `HOLO`), sequência contínua de `variant_order` por Card, e distribuição canônica completa por Card Set + Card Variant Type (24 combinações esperadas). **Resultado real, executado e confirmado:** `covered_cards` 859/859, `registered_variants` 1.555/1.555, `default_variants` 859/859, `status` `COMPLETE`. Com isso, o ciclo `160 → 860 → 960` se fechou (para as 5 coleções originais) e a camada de Card Variant foi declarada **canonicamente encerrada** — migrations canônicas: `150`/`151`/`160`/`161`/`850` v1.3/`950`/`860` consolidada/`960` v2.0. Arquivo antigo `960_validate_card_variant_structure.sql` (v1.0) removido de `database/validations/` com permissão de Fabrício, substituído por `960_validate_card_variant.sql` (v2.0).

---

## `860A - Seed Card Variant MEE` e `860B - Seed Card Variant MEP` — CONCLUÍDAS, EXECUTADAS E CONFIRMADAS (2026-07-24)

**⚠️ Letra reaproveitada, atenção ao ler o histórico acima.** `860A`/`860B` neste bloco referem-se a `MEE`/`MEP` (2026-07-24) — **não** aos antigos `860A` (ME1)/`860B` (ME2) descritos nos parágrafos anteriores, cujos arquivos já haviam sido removidos em favor de `860_seed_card_variant.sql` muito antes de `MEE`/`MEP` existirem no catálogo. Não há colisão real de arquivo — apenas de rótulo textual dentro desta documentação. `860_seed_card_variant.sql` permanece intocado.

**Nova disciplina de processo, adotada a partir de um erro real capturado antes da execução**: a primeira versão gerada de `860A` (MEE) assumiu, sem pesquisa prévia, que cada uma das 8 Energias Básicas do Set possuía apenas uma versão editorial — matriz com 8 registros. Antes de executar, Fabrício pediu confirmação do total pesquisado (16 variações) e a discrepância foi capturada: cada uma das 8 Cards possui, na verdade, duas variantes (`STANDARD` e `REVERSE_HOLO`), totalizando 16, não 8. A versão incorreta foi descartada integralmente, sem execução. **Nova regra permanente, adotada por Fabrício para toda futura Query `860`**: (1) pesquisar oficialmente todas as variantes editoriais do Card Set; (2) consolidar a matriz editorial; (3) só então gerar a Query — nunca assumir a partir de um padrão de Set anterior.

**`860A - Seed Card Variant MEE` — EXECUTADA E CONFIRMADA.** Matriz corrigida: as 8 Cards (`001`-`008`) recebem `STANDARD` (`variant_order = 1`, `is_default = TRUE`) + `REVERSE_HOLO` (`variant_order = 2`, `is_default = FALSE`) cada. **Resultado real: 8 `STANDARD` + 8 `REVERSE_HOLO` = 16 Card Variants**, confirmado por execução real ("Perfeito! Agora sim. 🍊" — resultado bateu exatamente com o esperado).

**`860B - Seed Card Variant MEP` — EXECUTADA E CONFIRMADA, com metodologia de correspondência reforçada por Fabrício.** Fabrício forneceu um arquivo externo listando variantes promocionais do MEP, mas alertou explicitamente que o arquivo lista promoções (`001`-`088`) além das 60 Cards já cadastradas na base, e que a correspondência **não pode presumir** que "60 Cards cadastradas" significa "posições `001`-`060`" — a numeração promocional real tem lacunas. Regra travada: a correspondência é feita exclusivamente pela coluna `collector_number`, cruzando o arquivo de variações com as Cards já existentes na Query `840` (não com a posição na lista do arquivo, nem com a contagem de registros). O MEP realmente cadastrado corresponde a `001`-`045`, `064`-`071`, `074`-`080` (60 Cards com lacunas reais na numeração) — as demais posições do arquivo (incluindo tudo após `080` e as lacunas internas) foram descartadas por ainda não existirem no catálogo.

**Duas regras de negócio adicionais, definidas por Fabrício para esta primeira carga de promos**: (1) variantes `JUMBO` são desconsideradas — não geram registro em `card_variant`; (2) qualquer variante com carimbo/selo (Staff, Pokémon Center, Liga, Campeonato Asiático, Pré-lançamento etc.) é gravada como o tipo já existente `PROMO_STAMPED`, sem criar um `card_variant_type` específico por carimbo — múltiplas edições estampadas da mesma Card consolidam em um único registro `PROMO_STAMPED`. Fabrício classificou isso como "a regra definitiva do Project Mimikyu para Promos", com um caminho de extensão futura já identificado (um atributo `variant_subtype`/`printing_type`, se algum dia for necessário diferenciar as edições) que não exige alterar a estrutura atual nem recarregar o que já foi carregado. **Resultado real: 60 Cards, 59 `HOLO` + 23 `PROMO_STAMPED` = 82 Card Variants**, confirmado por execução real. A Card `028` é a única exceção com `PROMO_STAMPED` como variante principal (`variant_order = 1`, `is_default = TRUE`) — na fonte usada, ela só existe em versão estampada, sem `HOLO` convencional.

**Reversão explícita de um plano anterior, confirmada por Fabrício antes de qualquer execução redundante**: com `860A`/`860B` prontos, Fabrício perguntou diretamente se seria necessário recarregar as variantes de `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` — a resposta correta é não, pelas seguintes razões, todas verdadeiras e registradas aqui para não serem esquecidas em ciclos futuros: `840` v2.2 foi idempotente (não recriou UUIDs de `card` já existentes); nenhuma regra de `card_variant` foi alterada; os tipos de variante usados nos Sets anteriores continuam os mesmos; `940` v2.1 apenas validou `card`, sem tocar `card_variant`. **`860_seed_card_variant.sql` permanece válido e não foi reexecutado.**

**`960 - Validate Card Variant` evoluída para v2.1 (CANÔNICA) — EXECUTADA E CONFIRMADA.** Escopo estendido de 5 para 7 Card Sets, incorporando as distribuições canônicas de `MEE` (8 `STANDARD`/8 `REVERSE_HOLO`) e `MEP` (59 `HOLO`/23 `PROMO_STAMPED`) e passando a aceitar `PROMO_STAMPED` como tipo de variante padrão permitido (necessário para a Card `028` do MEP). **Resultado real, executado e confirmado:** `covered_cards` 927/927, `registered_variants` 1.653/1.653, `default_variants` 927/927, `status` `COMPLETE`. Arquivo `database/validations/960_validate_card_variant.sql` sobrescrito no local (v2.0 → v2.1), seguindo o Princípio da Fonte Canônica.

**Marco alcançado, com a granularidade correta reafirmada por Fabrício**: a camada de Card Variant agora cobre integralmente as 7 Card Sets da Expansion `ME` — 927 Cards, 1.653 Card Variants. Isso **não** encerra a fundação do Catálogo Editorial como um todo — falta ainda a carga e validação das imagens (Card Asset) para `MEE`/`MEP` via `import-card-assets` (ver `06-pipeline-importacao.md`/`ADR-018`). Fabrício foi explícito sobre essa distinção quando a sessão pareada tentou declarar o marco maior prematuramente: "Não teremos encerrado toda a fundação do catálogo editorial do Project Mimikyu. Só concluímos após importação de todas as imagens para nossa base."

## Query 880 — Escopo Confirmado, Regras e Estratégia (planejamento, ainda não executada)

`CARD_FRONT` apenas, `is_primary = TRUE`, `asset_order = 1`, vinculado a `card_id` direto, nunca a `card_variant`.

**Regras que a Query `880` precisará respeitar, por registro**: Card obrigatória; Card Asset Type obrigatório; `storage_path` ou `external_url` obrigatório (ao menos um); `asset_order > 0`; Card e Asset Type pertencentes ao mesmo Game. Sem duplicidade em `card_id` + `asset_type_id` + `language_id` + `asset_order` (unicidade lógica, já revisada acima para incluir `language_id`); no máximo um registro principal por `card_id` + `asset_type_id` + `language_id`; a mesma localização (`storage_path` ou `external_url`) não pode se repetir para a mesma Card + Asset Type + idioma.

**Quantidade esperada, calculada a partir do catálogo já homologado**: 859 Cards já cadastradas (Card Variant canonicamente encerrada, ver seção acima) → 1 ativo `CARD_FRONT` por Card, por idioma disponível. Sem a dimensão de idioma, seriam exatamente 859 registros; com ela, o total real depende de quantos idiomas cada Card tiver imagem confirmada (mínimo 859, um por Card, quando só um idioma estiver disponível por Card).

**Arquitetura planejada — mesmo padrão homologado da `860`**: Matriz Editorial em JSONB (`collector_number`/`set_code` → URLs por idioma) + um único bloco `DO $$` que localiza a Card, resolve o `asset_type_id` de `CARD_FRONT` (via `870`, já executada) e executa o UPSERT — sem centenas de `INSERT`s individuais, com idempotência, rollback em qualquer inconsistência e validação de consistência de Game. Fabrício confirmou explicitamente essa direção ("Siga em frente") antes do bloqueio de idioma surgir.

**Estratégia provável de preenchimento de campos — SUPERADA por uma decisão mais firme (ver "Arquitetura de Armazenamento", abaixo).** A estratégia original cogitava `storage_path = NULL` + `external_url` = URL pública de uma fonte externa (Pokémon TCG API/TCGdex). Fabrício e a sessão pareada decidiram, em vez disso, hospedar as imagens no Supabase Storage — portanto `storage_path` (preenchido) é o campo relevante, `external_url` permanece `NULL`. Campos que não puderem ser conhecidos com segurança continuam devendo permanecer `NULL` — especialmente `file_size_bytes` e `checksum_sha256` — não devem ser inventados/inferidos.

**Bloqueio 1 — fonte oficial das imagens, ainda em aberto.** Três opções avaliadas: (A) Pokémon TCG API (`images.pokemontcg.io`) — estável, CDN, alta resolução, referência oficial do ecossistema, mas concentra majoritariamente imagens em inglês; (B) TCGdex (`assets.tcgdex.net`) — também sólida, com suporte multilíngue real; (C) armazenamento próprio — descartada por não fazer sentido nesta fase. Uma recomendação técnica foi esboçada (`TCGDEX`, com ME1/ME2/ME2.5 em pt-BR quando disponível e ME3/ME4 em inglês) mas **não confirmada por Fabrício** — nenhuma fonte foi definitivamente escolhida.

**Bloqueio 2 — identificador externo de cada coleção/carta, ainda em aberto.** `card` possui `card_set_code + collector_number` como identidade interna, mas a URL pública de qualquer fonte externa depende da convenção de nomenclatura própria dessa fonte (ex.: `ME1` → identificador externo → URL real) — não deve ser presumido que `ME1 = me1`, `ME2.5 = me2.5`, `001 = 1`, etc. Interpolar 859 URLs sem confirmar sua existência arriscaria uma execução "bem-sucedida" registrando URLs inválidas. A Query `880` só poderá ser gerada com segurança a partir de uma matriz externa validada contendo, no mínimo: `set_code`, `collector_number`, `source_code`, `source_reference`, `external_url`, `mime_type`, `file_extension` — ainda não recebida.

**Bloqueio 3 — dimensão de idioma — RESOLVIDO.** Ao comparar duas imagens reais da mesma Card (`Rufflet`, `173/217`, ME2.5) — uma em português ("Rufflet do Lauro") e outra em inglês ("Larry's Rufflet") — Fabrício identificou que ambas representam a mesma Card, o mesmo Card Asset Type (`CARD_FRONT`), mas são duas **representações linguísticas distintas do mesmo ativo digital** — não dois Card Assets Types, não duas Cards, não duas Card Variants. Isso disparou a decisão de adicionar `language_id` como dimensão de `card_asset` (ver "Estrutura Física Real", acima, e a seção "Language", abaixo), com SQL escrita via `190`/`191`/`192`/`193`/`890`. A dúvida de execução real levantada na revisão `0.42` foi **resolvida nesta revisão**: Fabrício confirmou diretamente ("Houve execução real de 193 e 194.") que ambas as Queries foram de fato aplicadas ao banco real.

**Bloqueio 4 — coluna `storage_bucket` — RESOLVIDO E EXECUTADO.** A entidade `storage_bucket` foi criada, semeada e homologada (`195`/`196`/`895`/`975`, todas executadas — ver seção "Storage Bucket", abaixo), confirmando o "Risco 1" sinalizado na revisão `0.43`: `card_asset.storage_bucket_id` já era FK para essa tabela pré-existente, e a modelagem correta era mesmo uma entidade de referência (mesmo padrão de `language`/`card_asset_type`), não uma coluna de texto livre. A migration `197 - Integrate Storage Bucket into Card Asset` — que integra `storage_bucket_id` a `card_asset` e remove definitivamente `storage_provider` — foi **escrita, executada e confirmada nesta revisão** ("Success. No rows returned" / "Excelente. Isso significa que a migração passou integralmente."). **Marco: com `197` e a validação `980` v2.0 (também confirmada e HOMOLOGADA), a camada estrutural de Card Asset está 100% concluída** — ver "Query 197"/"Query 980", na seção "Arquitetura de Armazenamento", abaixo.

**Bloqueio 5 — RESOLVIDO: as três camadas estruturais de dados estão concluídas.** Fabrício corrigiu explicitamente a sequência antes proposta ("Não seguiremos agora para: 880 – Seed Card Asset"): o passo estrutural foi construído em camadas, uma de cada vez, com pacote técnico completo antes de avançar — (1) **Asset Source** (`200`/`201`/`900`/`985` — CONFIRMADOS EXECUTADOS, ver seção "Asset Source", abaixo); (2) **Card External Reference** (`210`/`211`/`990` — CONFIRMADOS EXECUTADOS, ver seção "Card External Reference", abaixo; a Seed `910` foi deliberadamente **não criada**); (3) **camada de execução de importação, arquitetura híbrida `asset_import_run`/`asset_import_failure`** (em vez de `asset_import_job`/`asset_import_item`, planejado na revisão `0.46` mas nunca escrito em SQL) — `220`/`221`/`230`/`231`/`995` **CONFIRMADOS EXECUTADOS E HOMOLOGADOS**, ver "Query 220"/"Query 221"/"Query 230"/"Query 231"/"Query 995", abaixo. **Este bloqueio, como originalmente formulado, está encerrado** — as tabelas que sustentam a importação existem e estão governadas. O que falta agora não é mais modelagem de dados, e sim **implementação**: o worker (Edge Function) que efetivamente executa o fluxo de importação, e só depois disso a carga em escala de `880`. Ver "Roteiro Consolidado — Fases e Blocos", abaixo, para como esse trabalho remanescente está organizado. Este bloqueio absorve e substitui os antigos Bloqueios 1 (fonte oficial de imagens) e 2 (identificador externo).

Fabrício havia adiado anteriormente o detalhamento fino desta entidade e de `language`/`card_external_reference`/`card_set_external_reference` (tabelas físicas pré-existentes, ver `06-pipeline-importacao.md`): "Vamos chegar a detalhar essas três mais para frente. Vamos seguir o fluxo." — o detalhamento de `language` foi antecipado por conta do Bloqueio 3 e concluído; `card_external_reference` (e, por extensão, `asset_source`) voltam à tona agora, no desenho do pipeline de importação — ver abaixo.

## Arquitetura de Armazenamento — Decisões (planejamento avançado, NENHUMA SQL executada ainda)

Discussão extensa, sem execução de SQL, sobre como as imagens serão fisicamente armazenadas e localizadas. Decisões e recomendações, na ordem em que convergiram:

**Provedor**: Supabase Storage (não uma fonte externa como Pokémon TCG API/TCGdex, nem outro provedor de objeto) — justificado por já ser o mesmo projeto usado para o banco, evitando introduzir um segundo fornecedor nesta fase. `storage_provider = SUPABASE` em todos os registros da primeira carga.

**Bucket público**: `card-assets`/buckets por tipo de ativo (ver abaixo) configurados como públicos, não privados — acesso direto por URL, sem necessidade de gerar URLs assinadas nem de política de RLS adicional no Storage. Justificativa: melhor cache/CDN, carregamento mais simples; buckets privados foram descartados por adicionar complexidade sem benefício imediato para imagens de Cards (diferente de documentos pessoais/arquivos confidenciais).

**Formato do arquivo**: PNG, não WebP como cogitado inicialmente — decisão de Fabrício, priorizando preservar a imagem na melhor qualidade possível (arquivo mestre); otimizações futuras para web (WebP, JPEG etc.) poderão ser geradas como derivadas, sem substituir o original. `mime_type = image/png`, `file_extension = png`.

**Estratégia de backup — nova regra operacional, não uma constraint de banco**: a documentação do Supabase confirma que backups do banco de dados NÃO incluem os objetos armazenados no Storage (apenas metadados). Regra adotada: todo arquivo enviado ao Supabase Storage deve ter uma cópia de segurança externa (ex.: Google Drive, HD externo, OneDrive, Amazon S3) — mínimo de 1 cópia operacional no Supabase + 1 cópia de segurança fora do Supabase. Esta é uma prática operacional do projeto, não algo a ser modelado em `card_asset`.

**Convenção de caminho — evoluiu várias vezes na mesma conversa, forma final ainda sujeita ao Bloqueio 4 abaixo.** Sequência de propostas, da mais verbosa à mais enxuta: `pokemon/card-front/{language_code}/{expansion_code}/{card_number}.webp` → remoção do prefixo `pokemon/` (bucket já é exclusivo do projeto) → troca de `.webp` para `.png` → remoção de `{language_code}`/`{asset_type}` do caminho, por já estarem representados nas colunas relacionais (`card_asset.language_id`, `card_asset.asset_type_id`) → **proposta de um bucket por tipo de ativo** (`card-front`, `artwork`, `card-back`, em vez de um único bucket `card-assets` com subpastas) — nessa forma final, um caminho de exemplo seria `ME1/001.png` dentro do bucket `card-front`.

**Decisão evoluída nesta revisão: `storage_bucket` como entidade de catálogo própria, não como coluna de texto em `card_asset`.** O "Risco 1" sinalizado na revisão `0.43` — de que `storage_bucket` já existia como uma das 17 tabelas físicas pré-existentes e que `card_asset.storage_bucket_id` provavelmente já era uma FK para ela — foi **confirmado e adotado como a modelagem correta**. Em vez de uma coluna `storage_bucket TEXT` em `card_asset`, a sessão pareada propôs (e Fabrício aprovou, "Vamos fazer essa mudança") uma entidade `Storage Bucket` completa, no mesmo padrão arquitetural já usado para `language` e `card_asset_type`: `id, code, name, description, storage_provider, bucket_order, is_public, is_active, created_at, updated_at`. Catálogo inicial: `card-front`, `artwork`, `card-back`, todos `storage_provider = SUPABASE`, `is_public = TRUE`. Ver seção "Storage Bucket", abaixo, para o modelo físico completo e a execução real (`195`/`196`/`895`/`975`).

**Segunda evolução da mesma conversa: eliminar `storage_provider` de `card_asset`.** Ao desenhar a nova entidade, percebeu-se uma redundância: `storage_bucket` já carrega seu próprio `storage_provider` (ex.: o bucket `card-front` já "sabe" que pertence a `SUPABASE`), então manter `card_asset.storage_provider = SUPABASE` repetido em cada uma das centenas/milhares de linhas é dado duplicado, sujeito a divergir do bucket real. Modelo mais normalizado: `storage_provider` depende funcionalmente do bucket, não do ativo (`Storage Bucket → Storage Provider`, não `Card Asset → Storage Provider`). Resultado proposto para `card_asset`: manter apenas `storage_bucket_id` (FK) + `storage_path`; quando a aplicação precisar saber o provedor, resolve via `JOIN card_asset ... JOIN storage_bucket`. Benefício adicional: migrar de provedor no futuro (ex.: Supabase → S3) vira um único `UPDATE storage_bucket SET storage_provider = 'S3'`, sem tocar nenhuma linha de `card_asset`.

## Query 197 — Integrate Storage Bucket into Card Asset (CONFIRMADA EXECUTADA)

Migration mais impactante desta revisão sobre a estrutura de `card_asset`. Passos, todos confirmados via `RAISE EXCEPTION` de pré-requisito/proteção + blocos `DO $$` idempotentes: (1) valida pré-requisitos (`card_asset`/`storage_bucket` existem, colunas `storage_provider`/`storage_path`/`external_url` presentes); (2) **proteção contra migração ambígua** — aborta se `card_asset` já tiver qualquer registro, já que não haveria uma forma segura de atribuir um bucket a dados pré-existentes sem uma regra de conversão explícita (confirmado seguro, pois `880` ainda não havia rodado — tabela vazia); (3) valida que os três buckets obrigatórios (`card-front`/`artwork`/`card-back`) existem e estão ativos; (4) adiciona `storage_bucket_id UUID` (inicialmente nulo); (5) cria a FK `fk_card_asset_storage_bucket` para `storage_bucket.id`; (6)-(8) remove, por introspecção de `pg_trigger`/`pg_constraint`/`pg_indexes`, todo trigger/constraint/índice que mencione `storage_provider` na sua definição (sem depender de conhecer os nomes previamente — mesmo padrão de introspecção já usado em `193`); (9) remove definitivamente a coluna `storage_provider`; (10) torna `storage_bucket_id NOT NULL`; (11) cria três novos índices (`ix_card_asset_storage_bucket_id`, `ix_card_asset_bucket_language`, `ix_card_asset_card_bucket`); (12)-(13) cria a função `validate_card_asset_storage()` e o trigger `trg_card_asset_validate_storage`, que substitui a antiga constraint `ck_card_asset_storage_provider_location` — a cada `INSERT`/`UPDATE` relevante, consulta o `storage_provider` do bucket referenciado e exige `external_url` (sem `storage_path`) quando o provider é `EXTERNAL`, ou `storage_path` (sem `external_url`) para qualquer outro provider; (14) comentários; (15) validação estrutural pós-migration (confirma que `storage_provider` não existe mais, que `storage_bucket_id` é `UUID NOT NULL`, que a FK e o trigger existem). Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/migrations/197_integrate_storage_bucket_into_card_asset.sql`.

## Query 980 (v2.0) — Validate Card Asset (CONFIRMADA EXECUTADA, HOMOLOGADA)

Substitui a validação puramente estrutural v1.1 (`980_validate_card_asset_structure.sql`, que antecedia `language`/`storage_bucket`/`197` e por isso estava tecnicamente defasada) por uma homologação completa da arquitetura vigente, em 28 blocos: existência de tabelas dependentes (`card`/`card_asset_type`/`language`/`storage_bucket`/`card_asset`), estrutura de colunas essenciais (confirma a ausência de `storage_provider`), defaults, primary key, quatro foreign keys (`card_id`, `asset_type_id`, `language_id`, `storage_bucket_id`), unicidade lógica `card_id`+`asset_type_id`+`language_id`+`asset_order`, índice único parcial de ativo principal por Card+Tipo+Idioma, `CHECK` de `asset_order` positivo, três índices da integração com Storage Bucket, cobertura de índice para `card_id`/`asset_type_id`/`language_id`, trigger de `updated_at`, trigger e função `validate_card_asset_storage()` (confirma que a função contém as validações de bucket/provider/path/url esperadas), RLS, integridade básica dos registros, integridade referencial nas quatro FKs, coerência entre provider do bucket e `storage_path`/`external_url`, ausência de duplicidade lógica, ausência de múltiplos ativos principais por grupo, ausência de valores em branco, comentários obrigatórios nas colunas de armazenamento, e um bloco de resultado consolidado (contagem de ativos, principais, internos/externos, idiomas e buckets utilizados). Confirmado executado por Fabrício ("Success. No rows returned") e declarado **HOMOLOGADA**. Arquivo escrito em `database/validations/980_validate_card_asset.sql`. **Arquivo anterior `database/validations/980_validate_card_asset_structure.sql` (v1.1) removido** com permissão explícita de Fabrício, seguindo o Princípio da Fonte Canônica (mesmo padrão já aplicado a `960`) — `980_validate_card_asset.sql` é agora a única fonte de verdade para a validação desta entidade.

**Padrão formalizado nesta revisão: toda entidade de catálogo deve possuir quatro migrations obrigatórias — Create, Trigger, Seed, Validate.** Proposto pela sessão pareada ao notar que `language` e `storage_bucket` ainda não tinham uma Query de validação própria (diferente de `card_asset_type`, que já tinha `970` desde um ciclo anterior). Vantagens apontadas: homologação independente de cada catálogo antes de ser referenciado por outras tabelas; manutenção simplificada (bastar rodar a validação de uma entidade para confirmar que sua estrutura continua íntegra). Aplicado nesta revisão: `970 - Validate Language` e `975 - Validate Storage Bucket`, ambas executadas com sucesso — mas ver a ressalva de numeração no bloco "Queries", acima, sobre a colisão do número `970`.

> **Risco 2 (revisão `0.43`) — RESOLVIDO nesta revisão.** A convenção de caminho final, definida no planejamento do pipeline de importação (ver "Arquitetura de Importação de Ativos", abaixo), reintroduz explicitamente o idioma no caminho, agrupado antes do número da Card: `{collection-code}/{language-code}/{card-number}/front.png`. Dois registros do mesmo Card Asset Type para a mesma Card em idiomas diferentes agora apontam para caminhos distintos (ex.: `me2.5/pt-BR/217/front.png` vs. `me2.5/en/217/front.png`) — sem colisão. Fabrício confirmou e priorizou esse agrupamento por idioma explicitamente, com justificativa própria (exportação/backup por idioma, importação em lote por idioma, melhor localidade de cache/CDN) — ver "Arquitetura de Importação de Ativos" para o raciocínio completo.

**Marco: camada estrutural de Card Asset 100% concluída e validada, incluindo Card Asset Type, Language, Storage Bucket e Card Asset — arquitetura consolidada em `Card → Card Variant → Card Asset → { Asset Type, Language, Storage Bucket → Storage Path, External URL }`.** A partir daqui, o próximo passo lógico é a carga inicial (`880`) — ver "Arquitetura de Importação de Ativos", abaixo, para o planejamento conceitual (ainda não executado) que substitui o antigo "Fluxo de carga recomendado" desta seção.

**Próximo passo real, reafirmado em 2026-07-24**: com `card_variant` completo para as 7 Card Sets (ver seção "Card Variant", acima), o passo seguinte é rodar o pipeline real e já confirmado — a Edge Function única `import-card-assets` (ver `06-pipeline-importacao.md`/`ADR-018-single-function-import-pipeline.md`/`operations/import-card-assets.md`) — para `MEE`/`MEP`, exatamente como já foi feito para `ME1`-`ME4`/`ME2.5` (859 Cards, 1.718 assets, `en`+`pt-BR`, 0 falhas). Uma sessão pareada propôs, na mesma data, duas arquiteturas alternativas (colunas de URL de imagem direto em `card`; depois uma Seed estática para `card_external_reference`/`card_asset`) — nenhuma das duas foi adotada: a primeira foi corrigida na hora por colidir com a estrutura já homologada acima; a segunda contradiz a decisão já registrada de que `card_external_reference` é preenchida pela rotina real de importação, não por Seed estático (ver "Queries", acima, `910` "DESCARTADA DELIBERADAMENTE"), e descreve `card_asset` de forma mais simples do que sua estrutura real já executada. Nenhuma das duas propostas foi incorporada a este documento.

**Execução real para `MEE` (2026-07-24, `RUN-20260724-00000041`, `en`)**: `card_external_reference` 8/8 importadas; `card_asset`/imagens 0/8, todas com `TCGDEX_IMAGE_NOT_AVAILABLE`. Causa confirmada por consulta direta à TCGdex (endpoint de Set e de carta individual): o campo `image` está genuinamente ausente para as 8 cartas deste Set — gap de dados na fonte, não falha do pipeline.

**Execução real para `MEP` (2026-07-24, `RUN-20260724-00000061`, `en`)**: mesmo resultado — `card_external_reference` 60/60 importadas; `card_asset`/imagens 0/60, todas com `TCGDEX_IMAGE_NOT_AVAILABLE`, confirmado pelo mesmo tipo de consulta direta ao endpoint de Set (`/en/sets/mep`). Com isso, as duas coleções restantes da Expansion `ME` (`MEE`/`MEP`) têm referências externas 100% importadas e imagens bloqueadas na fonte — não há mais nenhuma coleção com execução pendente; falta apenas a TCGdex publicar os assets de imagem para estes dois Sets especiais (Energia/Promocional).

**Solução real adotada para o bloqueio de imagens (2026-07-24)**: em vez de esperar indefinidamente a TCGdex publicar os assets, Fabrício propôs importação manual — como `MEE`/`MEP` são coleções pequenas (`8`+`60` = `68` Cards), as imagens podem ser obtidas de outras fontes e importadas diretamente. Antes de adotar essa solução, confirmado por consulta real que o CDN da TCGdex (`https://assets.tcgdex.net/en/me/mee/001/{quality}.{extension}`, todas as combinações) retorna `404` para `MEE` — não é um gap apenas da API JSON, o asset realmente não existe na fonte, nem mesmo pelo padrão de URL documentado em `tcgdex.dev/assets`. Criado `scripts/import-manual-assets.ts` — script administrativo standalone (mesmo padrão de `scripts/discover-tcgdex-sets.ts`), **deliberadamente fora de `supabase/functions/import-card-assets/`** porque lê arquivos locais do disco (inexistente no runtime de uma Edge Function) e não deve ser implantado. Lê imagens de `assets/manual-imports/{card_set_code}/{language_code}/{collector_number}.{ext}`, calcula checksum SHA-256, sobe ao Storage (bucket `card-front`) e faz `UPSERT` em `card_asset` — mesma chave natural de idempotência já usada pelo pipeline automático (`card_id`+`asset_type_id`+`language_id`+`storage_bucket_id`). Todo registro criado por este script é marcado com `source_code = "MANUAL"` (em vez de `"TCGDEX"`), preservando rastreabilidade da origem real de cada imagem — decisão explícita de Fabrício, para permitir auditar/substituir depois, caso a TCGdex publique os assets oficiais.

**CONFIRMADO EXECUTADO: `MEE`/`en` (2026-07-24), 8/8 Cards — 0 falhas.** Dry-run limpo seguido de execução real; validado por consulta direta ao banco (`card_asset` com `source_code = 'MANUAL'`, `storage_path` correto por carta) e por inspeção visual da imagem pública no navegador (`.../storage/v1/object/public/card-front/mee/en/001.png`, `Basic Grass Energy`, MEE 001, confirmada real e correta).

**CONFIRMADO EXECUTADO: `MEE`/`pt-BR` (2026-07-24), 8/8 Cards — 0 falhas.** Mesmo processo, mesmo dia. **Com isso, `MEE` está com o catálogo genuinamente completo nos dois idiomas** — referências externas e imagens, `en`+`pt-BR`. Pendente: `MEP`/`en`, `MEP`/`pt-BR` (mesmo processo, imagens ainda não salvas localmente).

## Arquitetura de Importação de Ativos — Planejamento e Execução em Camadas (Asset Source EXECUTADA; demais camadas planejadas)

Discussão extensa sobre como popular `880` na prática, iniciada pela preocupação explícita de Fabrício: *"Confesso que estou preocupado com os próximos passos [...] Minha maior preocupação é em relação às imagens de cada carta. Ainda não sei como conseguir essas imagens de forma prática. Não quero ter o trabalho de baixar uma a uma."*

**Duas estratégias apresentadas e comparadas**: (1) referenciar imagens diretamente por `external_url` de uma fonte pública (ex. `https://images.pokemontcg.io/xy1/1_hires.png`), sem baixar nada — mais rápida, mas cria dependência permanente de disponibilidade de terceiros; (2) importar automaticamente para o Supabase Storage próprio — um script busca, baixa, valida, envia ao bucket correto e grava o registro em `card_asset`, com `storage_bucket_id`/`storage_path` preenchidos e `external_url` nulo. **Fabrício decidiu pela opção 2, explicitamente**: *"Gostaria de partir com a solução de executar uma rotina automática para internalizar as imagens no Supabase Storage. Gosto de ir na solução definitiva para nossos problemas, mesmo que isso tenha um esforço maior nesse momento. Garantimos que vamos trabalhar nesse item apenas uma vez."* — `card_asset` **não usará URLs externas como solução operacional principal**.

**Decisão de rastreabilidade em aberto, sinalizada pela própria sessão pareada**: como `external_url` fica reservado para o caso `EXTERNAL` (por força da constraint de `197`, ver "Query 197", acima), a URL de origem de uma imagem já internalizada (de onde ela foi baixada, para fins de auditoria/reimportação) **não pode reaproveitar essa mesma coluna** — precisaria de "uma camada própria de rastreabilidade". **Nota desta revisão, não levantada na conversa original**: `card_asset` já possui `source_code`/`source_reference` (colunas confirmadas fisicamente desde a revisão `0.30`, nunca usadas em nenhuma migration até agora) — plausivelmente exatamente o par de colunas que resolveria essa necessidade (`source_code` = qual fonte, ex. `POKEMON_TCG_API`; `source_reference` = URL/identificador na fonte), sem exigir nenhuma coluna nova. Recomenda-se que, antes de desenhar uma "nova camada de rastreabilidade", Fabrício e a sessão pareada confirmem se `source_code`/`source_reference` já resolvem essa necessidade — evitaria adicionar estrutura redundante.

**Componentes do pipeline, por camada — ordem de construção corrigida na revisão `0.46`, com progresso adicional nesta revisão**:
1. **Asset Source** — catálogo de fontes externas. **CRIADO, SEMEADO E VALIDADO** (`200`/`201`/`900`/`985`, todos confirmados executados) — ver seção "Asset Source", abaixo, para o modelo físico completo e a execução real.
2. **Card External Reference** — mapeamento entre uma Card do Project Mimikyu e sua identidade em uma fonte externa. **CRIADA, COM TRIGGERS E VALIDADA nesta revisão** (`210`/`211`/`990`, todos confirmados executados) — ver seção "Card External Reference", abaixo, para o modelo físico completo e a execução real. **A Seed `910` foi deliberadamente descartada**: Fabrício e a sessão pareada concluíram que não faz sentido popular esta tabela com um `INSERT` estático, já que os registros reais serão produzidos automaticamente pela própria rotina de importação, à medida que ela descobre a correspondência entre cada Card e seu identificador externo — um seed manual seria dado inventado, não dado real.
3. **Camada de execução de importação — arquitetura revisada por meio de um "Architecture Review" solicitado por Fabrício antes de escrever qualquer SQL; `asset_import_run` (`220`/`221`) CONFIRMADOS EXECUTADOS nesta revisão.** O modelo originalmente planejado na revisão `0.46` (`asset_import_job`/`asset_import_item` — um registro de job por execução e **um registro de item por Card processada**, com sucesso ou falha) foi avaliado e revisado antes de qualquer escrita, pela preocupação explícita de Fabrício com o crescimento do histórico ao longo do tempo (*"Imagine daqui a alguns anos. Você terá: 8 idiomas, 150 coleções, 30.000 cartas, várias reimportações [...] A tabela de Jobs pode facilmente crescer para centenas de milhares ou milhões de registros. [...] Precisamos mesmo persistir todo esse histórico no banco principal? Talvez não."*). Nova arquitetura híbrida adotada, com um fluxo operacional em 9 etapas (ver abaixo): **`asset_import_run`** (um registro por *execução* da rotina — não por Card, **CRIADA E COM TRIGGERS, `220`/`221` executados**, ver "Query 220"/"Query 221", abaixo) + **`asset_import_failure`** (um registro apenas para itens que falharam, **ainda não escrita**) — descartando deliberadamente um registro por Card processada com sucesso, que seria auditoria redundante frente ao próprio `card_asset`/`card_external_reference` já persistidos.
4. Somente depois das três camadas acima: desenvolvimento do worker (Edge Function em TypeScript) responsável por buscar → baixar → validar (é realmente uma imagem?) → calcular checksum → gerar caminho padronizado → verificar se o objeto já existe → enviar ao Supabase Storage → criar/atualizar `card_asset` → registrar resultado — e um **piloto controlado com uma coleção pequena** antes de qualquer escala real.
5. Só então, a carga em escala de `880 - Seed Card Asset`.

**Arquitetura híbrida de execução de importação, detalhada nesta revisão (ainda conceitual, nenhuma SQL escrita)**: fluxo revisado de `Fonte externa → Execução de importação → Descoberta e correspondência → Download temporário → Validação → Supabase Storage → Card Asset → Resumo da execução`, em 9 etapas — (1) seleção, parâmetros como `source`/`collection`/`language`/`mode` (modos possíveis: `MISSING_ONLY`, `REFRESH_EXISTING`, `RETRY_FAILURES`, `SINGLE_CARD`, `FULL_COLLECTION`); (2) criação do registro em `asset_import_run`, status inicial `PENDING`, passando a `RUNNING` ao iniciar o processamento; (3) correspondência via `card_external_reference` (criada automaticamente via consulta à API quando ainda não existir); (4) download temporário — nenhuma URL externa deve ser usada diretamente pela aplicação final; (5) validação do arquivo (resposta HTTP, tipo MIME, tamanho mínimo/máximo, formato permitido, dimensões, conteúdo vazio/corrompido, hash, associação correta com Card/coleção/idioma) — formatos aceitos na origem (`image/png`, `image/jpeg`, `image/webp`), padronizados para `front.png` no destino, mantendo PNG como formato canônico; (6) upload para `card-front/pokemon/{collection-code}/{language-code}/{card-number}/front.png`, com `upsert = false` para imagens novas e `upsert = true` apenas nos modos de reprocessamento; (7) registro do ativo em `card_asset`, apontando para o objeto interno — a URL externa deixa de ser dependência operacional; (8) tratamento de falha — registro em `asset_import_failure` por `failure_stage` (`REFERENCE_LOOKUP`, `SOURCE_REQUEST`, `DOWNLOAD`, `VALIDATION`, `TRANSFORMATION`, `STORAGE_UPLOAD`, `CARD_ASSET_WRITE`), permitindo reprocessar somente falhas reais; (9) encerramento — `asset_import_run` recebe os totais (`requested_count`/`processed_count`/`success_count`/`failed_count`/`skipped_count`) e o status final (`COMPLETED`, `COMPLETED_WITH_ERRORS`, `FAILED`, `CANCELLED`). Controle de duplicidade via hash `SHA-256` do arquivo (campo recomendado em `card_asset`, reaproveitando `checksum_sha256`, já existente e nunca usado). Retenção recomendada: `card_external_reference`/`card_asset`/falhas não resolvidas mantidos indefinidamente; execuções automáticas bem-sucedidas podem ser removidas de `asset_import_run` após um período (ex.: 180 dias), já que seus resultados consolidados permanecem refletidos em `card_asset`; falhas resolvidas, após 90-180 dias.

## Query 220 — Create Asset Import Run (CONFIRMADA EXECUTADA)

Estrutura final, após um episódio de correção e uma tentativa de generalização revertida (ver abaixo): `id, run_code, asset_source_id, card_set_id, language_id, run_type, status, execution_context, initiated_by, requested_count, processed_count, success_count, failed_count, skipped_count, parameters, error_summary, started_at, finished_at, created_at, updated_at`. `run_code` é gerado automaticamente por uma sequência dedicada (`asset_import_run_code_seq`) no formato `RUN-{YYYYMMDD}-{sequencial de 8 dígitos}` — identificador amigável para logs/suporte/auditoria/telas administrativas, sem substituir o `id` (`UUID`) como chave primária. `asset_source_id` é FK obrigatória; `card_set_id`/`language_id` são FKs **opcionais** (`RESTRICT`), permitindo tanto uma execução com escopo estrito de coleção/idioma quanto uma execução mais ampla (ex. `FULL_CARD_SET`, `SINGLE_CARD`) filtrada via `parameters JSONB`. `run_type` restrito a `MISSING_ONLY`/`REFRESH_EXISTING`/`RETRY_FAILURES`/`SINGLE_CARD`/`FULL_CARD_SET`; `status` a `PENDING`/`RUNNING`/`COMPLETED`/`COMPLETED_WITH_ERRORS`/`FAILED`/`CANCELLED`; `execution_context` a `MANUAL`/`SCHEDULED`/`API`/`SYSTEM` (permite diferenciar execuções manuais de agendadas/via API/via sistema, útil para suporte e auditoria). `CHECK`s garantem consistência entre os contadores (`processed_count <= requested_count`; `success_count + failed_count + skipped_count <= processed_count`) e período (`finished_at >= started_at`). Cinco índices, incluindo dois parciais (execuções ativas — `status IN ('PENDING','RUNNING')` — e execuções finalizadas). RLS habilitado.

**Episódio de correção, registrado por transparência.** A primeira versão da migration (não executada) referenciava uma tabela `collection`, que não existe no projeto real — a sessão pareada assumiu esse nome por uma limitação de memória de conversas longas, que ela própria reconheceu ao ser confrontada com uma captura real do Table Editor: *"eu assumi incorretamente que a tabela se chamava collection, quando na verdade ela é: card_set."* A execução da versão incorreta falhou dentro do bloco de validação inicial (transação revertida, nada chegou a ser criado) — nenhum dado ou estrutura ficou inconsistente. Em seguida, antes de corrigir e reexecutar, a sessão pareada abriu uma discussão arquitetural mais ampla, propondo tornar `asset_import_run` totalmente agnóstica de domínio (remover `card_set_id`/`language_id` como FKs e mover todo o escopo da execução para dentro de `parameters JSONB`, argumentando reuso futuro para outros importadores/jogos). **Fabrício interrompeu essa expansão de escopo diretamente**: *"Vamos manter o foco na query 220. Estou sentindo que estamos evoluindo pouco neste ponto. Ainda temos muito trabalho pela frente [...] Precisamos concluir o bloco do catálogo editorial e começar a pensar no desenvolvimento das coleções. Lembre que são conceitos distintos."* A sessão pareada reconheceu o desvio e voltou ao escopo mínimo necessário: apenas corrigir `collection_id`→`card_set_id` e `FULL_COLLECTION`→`FULL_CARD_SET`, mantendo `card_set_id`/`language_id` como FKs reais (não generalizadas para `parameters`). Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/220_create_asset_import_run.sql`.

## Query 221 — Asset Import Run Triggers (CONFIRMADA EXECUTADA)

Três elementos: `normalize_asset_import_run()` (normaliza `run_code`/`run_type`/`status`/`execution_context` para maiúsculo, `initiated_by`/`error_summary` vazios viram `NULL`, `parameters` nunca fica `NULL`); **`govern_asset_import_run()`** — trigger de governança mais sofisticado já escrito neste projeto, combinando proteção de identidade (`id`/`run_code` imutáveis), **bloqueio de alteração do escopo da execução após sair de `PENDING`** (nenhum de `asset_source_id`/`card_set_id`/`language_id`/`run_type`/`execution_context`/`initiated_by`/`parameters` pode mudar depois que a execução começa), **máquina de estados de transição de status** (`PENDING → RUNNING/FAILED/CANCELLED`; `RUNNING → COMPLETED/COMPLETED_WITH_ERRORS/FAILED/CANCELLED`; qualquer estado terminal é definitivo — nenhuma transição posterior é aceita), **preenchimento automático de `started_at`/`finished_at`** conforme o status (limpos em `PENDING`, `started_at` fixado ao entrar em `RUNNING`, ambos fixados ao atingir um estado terminal caso ainda não estejam preenchidos), e uma **regra de coerência entre status final e `failed_count`** (`COMPLETED` exige `failed_count = 0`; `COMPLETED_WITH_ERRORS` exige `failed_count > 0`); e o trigger padrão de `updated_at`. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/221_asset_import_run_triggers.sql`.

## Correção real: máquina de estados nunca escrita (v2.6.0, CONFIRMADA DEPLOYADA E TESTADA)

Bug real encontrado por Fabrício em 2026-07-25, inspecionando a tabela `asset_import_run` diretamente no Table Editor: a coluna `status` estava em `PENDING` em 100% das 11 linhas já existentes, incluindo execuções que sabidamente tinham concluído com sucesso ("*Imagino que essa coluna deve registrar o status de cada importação. Para as importações que foram concluídas com sucesso esse status não deveria ser outro?*"). Investigação confirmou a suspeita: `import-card-assets` (`index.ts`, todas as versões até `v2.5.0`) fazia apenas um `SELECT` sobre esta tabela (`findImportRun`) e nunca um `UPDATE` — a máquina de estados completa descrita em "Query 221" (`PENDING`→`RUNNING`→`COMPLETED`/`COMPLETED_WITH_ERRORS`/`FAILED`/`CANCELLED`, governada por `govern_asset_import_run()`) simplesmente nunca era usada pela função.

Corrigido na v2.6.0 com duas novas funções em `services/database.ts`: `transitionImportRunToRunning` (chamada assim que a run é localizada, antes de qualquer processamento) e `finishImportRun` (chamada em todo caminho de saída — sucesso com/sem falhas de imagem, e todo erro conhecido após a run ser localizada), deliberadamente tolerante a falha (loga mas não relança erro, para nunca mascarar o resultado real já processado). `index.ts` foi ajustado para declarar `run` como `let` (acessível pelo `catch`, que encerra a run como `FAILED` se um erro ocorrer após ela ser localizada) e introduzir `const activeRun = run` logo após o null-check, necessário porque o narrowing de tipo do TypeScript não atravessa closures sobre variáveis `let` (usado dentro de `processInBatches`).

**Backfill das 11 runs históricas, dado real extraído por consulta, não adivinhado**: uma query diagnóstica cruzou `asset_import_run`→`card_set`→contagem real de `card_asset` por idioma antes de qualquer `UPDATE`. Resultado: 10 runs (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`×2/`MEE`) corrigidas para `COMPLETED` com contagens = total de cartas do Set, `0` falhas; a run da `MEP` (`RUN-20260724-00000061`) corrigida para `COMPLETED_WITH_ERRORS` (`60`/`60`/`0`/`60`, `error_summary` registrando o gap de imagens já conhecido). Executado em duas fases (todas para `RUNNING` primeiro, depois para o status terminal correto), respeitando a máquina de estados do trigger.

**Teste real pós-deploy** (nova run `RUN-20260725-00000081`, criada especificamente para este teste, `MEP`, `execution_context = 'API'`): primeira invocação falhou com `IMPORT_RUN_TRANSITION_TO_RUNNING_FAILED: permission denied for table asset_import_run` — mais um caso do mesmo gap de GRANT recorrente neste projeto (RLS habilitado não substitui GRANT de tabela; `service_role` tinha apenas `SELECT`/`TRUNCATE`/`REFERENCES`/`TRIGGER` nesta tabela, confirmado por consulta direta a `information_schema.role_table_grants` antes de corrigir). Corrigido por `database/migrations/272_grant_asset_import_run_write_permissions.sql` (concede `INSERT`/`UPDATE`, o `INSERT` já pensado para o próximo item abaixo). Reinvocação confirmou o fluxo completo: `PENDING`→`RUNNING`→`COMPLETED_WITH_ERRORS`, contagens (`60`/`60`/`0`/`60`) e timestamps (`started_at`/`finished_at`) corretos.

**Auditoria complementar solicitada por Fabrício, 100% das 11 linhas revisada antes de fechar este ciclo**: `execution_context = MANUAL` confirmado correto em todas — a coluna reflete quem/o que disparou a execução (documentado em "Query 220": `MANUAL`/`SCHEDULED`/`API`/`SYSTEM`), e todas as 11 runs foram de fato disparadas manualmente por Fabrício via `Invoke-RestMethod` no PowerShell; não há confusão com a fonte dos dados (`asset_source_code = TCGDEX`, coluna separada). Duas pendências reais, registradas e conscientemente NÃO tratadas nesta revisão: `language_id` e `initiated_by` são `NULL` em 100% das linhas (a FK/coluna existe, nunca foi populada). Achado adicional: `scripts/import-manual-assets.ts` (as duas importações manuais de `MEE`, en/pt-BR) nunca criava nenhuma linha em `asset_import_run` — as importações manuais ficavam invisíveis para quem consultasse esta tabela. Corrigido no próprio script (v1.1): passa a criar uma linha por `(card_set, language)` processado de verdade (nunca em `--dry-run`), usando o `asset_source` `MANUAL` já seedado (Query 900), com a mesma máquina de estados (`PENDING`→`RUNNING`→`COMPLETED`/`COMPLETED_WITH_ERRORS`). Confirmado via `deno check` + `--dry-run` limpo (29/29, 0 falhas); **execução real ainda NÃO feita** — Fabrício optou por aguardar `MEP`/`en`+`pt-BR` completas (hoje só há 13/60 de `MEP`/`en` salvas localmente) antes de rodar de verdade, para não deixar uma `asset_import_run` parcial para a `MEP`.

## Query 230 — Create Asset Import Failure (CONFIRMADA EXECUTADA)

Estrutura final: `id, asset_import_run_id, card_id, failure_stage, error_code, error_message, external_card_id, attempt_count, is_resolved, resolved_at, created_at, updated_at`. **Refinamento de última hora, proposto pela sessão pareada enquanto `221` ainda executava**: a proposta inicial media a falha por `external_card_id` (identificador da fonte externa); a versão final passou a exigir `card_id` como FK direta e obrigatória para `card`, com o raciocínio de que `asset_import_failure` representa **falhas de Cards do catálogo, não falhas de identificadores externos soltos** — isso dá vínculo direto com a Card real (acesso imediato a idioma/coleção/expansão via os relacionamentos já existentes), permite reprocessar exatamente aquela Card sem depender da fonte externa para relocalizá-la, e mantém `external_card_id` apenas como dado de apoio ao diagnóstico. **Segunda decisão de normalização, também de última hora**: a proposta inicial incluía `asset_source_id` como coluna própria de `asset_import_failure`; a versão final **a omite deliberadamente**, resolvendo a fonte por `JOIN` via `asset_import_run.asset_source_id` — evita duplicar um dado que já está disponível através do relacionamento com a execução, mesmo padrão de normalização já usado em `storage_bucket`/`card_asset` (revisão `0.44`). `failure_stage` restrito a `REFERENCE_LOOKUP`/`SOURCE_REQUEST`/`DOWNLOAD`/`VALIDATION`/`TRANSFORMATION`/`STORAGE_UPLOAD`/`CARD_ASSET_WRITE` (mesmas etapas do fluxo operacional de 9 passos documentado acima); `error_code` um código curto e estável (ex. `HTTP_404`, `INVALID_IMAGE`, `TIMEOUT`, `UNSUPPORTED_FORMAT`, `DUPLICATE_ASSET`, `CARD_NOT_FOUND`, `STORAGE_ERROR`), pensado desde já para alimentar dashboards/indicadores externos (Power BI, mencionado explicitamente); unicidade composta (`asset_import_run_id`+`card_id`+`failure_stage`+`error_code`) evita duplicar o mesmo erro registrado várias vezes na mesma execução; `CHECK` garante coerência entre `is_resolved`/`resolved_at` (um não pode existir sem o outro). Quatro índices, incluindo um parcial para falhas ainda não resolvidas. RLS habilitado. Confirmado executado por Fabrício ("Success. No rows returned" / "Vamos em frente!"). Arquivo escrito em `database/schema/230_create_asset_import_failure.sql`.

## Query 231 — Asset Import Failure Triggers (CONFIRMADA EXECUTADA)

Mesmo padrão de sofisticação já visto em `221`: `normalize_asset_import_failure()` (normaliza `failure_stage`/`error_code` para maiúsculo, `error_message` aparado, `external_card_id` vazio vira `NULL`); `govern_asset_import_failure()` — protege `id`/`asset_import_run_id`/`card_id`/`failure_stage`/`error_code` contra alteração, impede que `attempt_count` seja reduzido (só pode crescer, refletindo tentativas reais), e administra `resolved_at` automaticamente: preenchido quando `is_resolved` passa a `TRUE` (na criação ou na transição `FALSE→TRUE`), preservado enquanto `is_resolved` permanece `TRUE`, e limpo (`NULL`) sempre que `is_resolved` volta a `FALSE`; e o trigger padrão de `updated_at`. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/231_asset_import_failure_triggers.sql`.

## Query 995 — Validate Asset Import Infrastructure (CONFIRMADA EXECUTADA, HOMOLOGADA)

Validação consolidada de toda a camada de execução de importação (`asset_import_run` + `asset_import_failure` juntas, não uma validação por tabela): existência das duas tabelas, presença de todas as colunas esperadas em cada uma, quatro funções (`normalize`/`govern` de cada tabela), seis triggers, RLS habilitado em ambas, e dois blocos de integridade referencial (nenhuma falha órfã de execução, nenhuma falha apontando para uma Card inexistente). Confirmado executado por Fabrício ("Success. No rows returned") e declarado **HOMOLOGADA**. Arquivo escrito em `database/validations/995_validate_asset_import_infrastructure.sql`.

> **Marco: infraestrutura de importação do catálogo editorial encerrada.** Com `220`/`221`/`230`/`231`/`995` confirmados executados, a camada de execução de importação está tecnicamente completa: `asset_import_run` controla cada execução, `asset_import_failure` registra apenas as exceções, e ambas se relacionam diretamente com `card`/`card_set`/`language`/`asset_source`/`card_external_reference`, já homologados em revisões anteriores. **Isto não significa que o pipeline de importação em si já funciona** — as tabelas existem e estão governadas, mas o worker que efetivamente busca, baixa, valida e envia imagens ao Supabase Storage (a Edge Function) ainda não foi escrito. Ver "Roteiro Consolidado — Fases e Blocos", abaixo, para a reformulação de como o restante do trabalho está organizado.

> **⚠️ Ressalva de numeração e nomenclatura (revisão `0.47`) — RESOLVIDA nesta revisão.** **Numeração**: a recomendação da revisão `0.47` (`220`/`221` para Create/Trigger de `asset_import_run`, `230`/`231` para `asset_import_failure`, `995` para a validação consolidada) foi adotada e executada integralmente, sem colisões — evitando a colisão com `920 - Validate Card Set` que teria ocorrido com o plano original da revisão `0.46`. **Nomenclatura**: permanece a mesma leitura da revisão `0.48` — a evidência do Table Editor (tabelas físicas existentes antes de `220`, sem `asset_import_run`/`asset_import_failure`/`card_set_external_reference`) segue como corroboração forte, não prova absoluta, de que `06-pipeline-importacao.md` está desatualizado quanto a essas três tabelas. Ver também a correção feita nesta revisão em `docs/README.md`, que citava as quatro tabelas (`asset_source`, `asset_import_run`, `asset_import_failure`, e implicitamente `card_set_external_reference`) como parte das "17 tabelas pré-existentes" — reformulado para refletir que ao menos três delas foram criadas por este próprio projeto, não herdadas.

**Convenção de caminho — FINALIZADA e formalizada nesta revisão, resolve o Risco 2 (ver acima).** Evoluiu em duas etapas dentro desta mesma discussão: primeiro `pokemon/{collection-code}/{card-number}/{language-code}/front.png` (organizado por carta), depois invertida por proposta direta de Fabrício — *"Não faz mais sentido usar: Path: pokemon/me1/pt-BR/001.png ao invés de Path: pokemon/me1/001/pt-BR.png?"* — para organizar **primeiro por idioma**: `pokemon/{collection-code}/{language-code}/{card-number}.png`. Justificativa (Fabrício + sessão pareada): exportação por idioma mais simples; importação em lote por idioma escreve tudo sob um único prefixo; melhor localidade de cache/CDN; backup seletivo por idioma (copiar só a pasta do idioma). Refinamento final, para acomodar múltiplos tipos de ativo por Card/idioma sem restruturar o caminho no futuro (frente/verso/artwork/thumbnail/cropped/preview holográfico): pasta por Card, um arquivo por tipo — `pokemon/{collection-code}/{language-code}/{card-number}/front.png`. Como o bucket físico (ex. `card-front`) já identifica o tipo de ativo, o nome do arquivo mantém o sufixo de tipo (`front.png`) apenas por clareza/robustez futura, não por necessidade estrita. **Forma final**: `Bucket: card-front` / `Path: pokemon/{collection-code}/{language-code}/{card-number}/front.png` — exemplos: `pokemon/me2.5/pt-BR/217/front.png`, `pokemon/me3/en/088/front.png`. Fabrício: *"Vamos seguir em frente."* Princípio de projeto registrado: *"As imagens das cartas serão internalizadas automaticamente no Supabase Storage; URLs externas serão tratadas apenas como fontes de aquisição e rastreabilidade."*

**Idempotência**: a rotina deve poder ser executada novamente sem duplicar dados — verifica se o `card_asset` já existe, se o objeto já existe no mesmo caminho, se o checksum é igual, se a origem mudou, se a imagem precisa ser substituída, se houve importação parcial anterior. Comportamento por caso: arquivo inexistente → cria; arquivo igual → ignora; arquivo diferente → sinaliza ou atualiza; registro incompleto → corrige; falha anterior → tenta novamente. Processamento em lotes pequenos e retomáveis (não uma única Edge Function monolítica, por causa dos limites de duração/memória/CPU do Supabase) — se uma coleção de 295 Cards falhar na 173, a retomada continua de onde parou, não do zero.

**Segurança**: a chave administrativa do Supabase ficaria confinada ao ambiente da Edge Function (nunca no navegador nem em texto aberto no banco); o Storage usa políticas de RLS sobre `storage.objects`; o usuário comum da aplicação poderia visualizar as imagens, mas não substituir/apagar arquivos.

**Ressalva de direitos de imagem, registrada pela sessão pareada, não resolvida**: internalizar as imagens resolve a dependência técnica de disponibilidade da fonte externa, mas não resolve por si só questões de termos de uso, possibilidade de download automatizado, finalidade permitida, exigência de atribuição e limitações de redistribuição pública das imagens — que precisam ser verificadas antes de uma importação em massa, não apenas do ponto de vista técnico.

> **Correção desta revisão ao "RISCO CRÍTICO" sinalizado na revisão `0.45`: para `asset_source`, especificamente, o risco de duplicação NÃO se confirmou.** A Query `200 - Create Asset Source` incluiu sua própria guarda defensiva de pré-execução (`IF to_regclass('public.asset_source') IS NOT NULL THEN RAISE EXCEPTION 'Query 200 interrompida: public.asset_source já existe.'`) — e a Query foi executada com sucesso ("Success. No rows returned"), o que só é possível se a guarda **não** disparou, ou seja, **`public.asset_source` não existia no banco real conectado no momento da execução**. Isso contradiz diretamente a afirmação de `docs/06-pipeline-importacao.md` de que `asset_source` já constava entre as 17 tabelas físicas pré-existentes do projeto. Duas leituras possíveis, nenhuma resolvida unilateralmente: (a) a lista de `06-pipeline-importacao.md` está desatualizada ou incorreta quanto a `asset_source`; ou (b) `asset_source` existia em outro projeto/schema Supabase, não o mesmo contra o qual `200` foi executada (mesmo tipo de dúvida já levantado na revisão `0.42` para `193`/`194`). Recomenda-se que Fabrício confirme contra qual projeto Supabase as Queries desta camada estão sendo executadas, e que `docs/06-pipeline-importacao.md` seja corrigido para remover `asset_source` da lista de pré-existentes assim que confirmado.
>
> **Este teste empírico cobre apenas `asset_source`. As demais quatro tabelas da mesma lista — `asset_import_run`, `asset_import_failure`, `card_external_reference` e `card_set_external_reference` — permanecem não inspecionadas e devem ser tratadas com a mesma cautela de antes.** Antes de escrever `210`/`220`/`221`, recomenda-se repetir o mesmo padrão de guarda defensiva usado em `200` (ela mesma serve como teste de existência seguro) e, se possível, inspecionar essas tabelas via Table Editor. Mesmo padrão de risco já visto neste projeto: `card_asset`/`card_asset_type` (batches 29-30), `storage_provider` em `card_asset` (revisão `0.42`), primeira proposta de `storage_bucket` como coluna de texto (revisão `0.43`) — em todos os casos anteriores, a estrutura física real divergia do que havia sido documentado ou presumido. **Nota da revisão `0.49`: o teste foi de fato repetido em `220`/`230`, e a evidência do Table Editor da revisão `0.48` corroborou o mesmo padrão para `asset_import_run`/`asset_import_failure` — ver "Query 231", acima, e o "Roteiro Consolidado", abaixo.**

## Roteiro Consolidado — Fases e Blocos (revisão `0.49`, substitui o framing por "Bloqueios" numerados)

**Origem desta seção: um incidente de confiança no roteiro, registrado por transparência.** Ao encerrar a camada de execução de importação (`995`), Fabrício comparou o estado atual do projeto com um roadmap combinado em uma conversa anterior (`200`/`201`/`900`/`985` → `210`/`211`/`910`/`990` → `220`/`221`/`222`/`920`/`995`, com o passo 3 ainda nomeado "Asset Import Job/Item" naquele momento) e expressou preocupação real e direta: *"Estou achando que você se perdeu na sequência do trabalho e isso me deixa verdadeiramente preocupado [...] Preciso que você garanta uma linha de trabalho clara, sem que tenhamos problemas na sequência de execução!"* A sessão pareada respondeu com uma comparação lado a lado, mostrando que o roadmap não foi abandonado, mas deliberadamente evoluído em um ponto específico e já documentado nesta revisão (a substituição de Asset Import Job/Item por Run/Failure, revisão `0.47`):

```text
Roadmap original          →  Roadmap implementado
220 Asset Import Job      →  220 Asset Import Run
221 Asset Import Item     →  221 Asset Import Run Triggers
222 Asset Import Triggers →  230 Asset Import Failure
920 Seed/Test Import Job  →  231 Asset Import Failure Triggers
995 Validate ... Architecture → 995 Validate Asset Import Infrastructure
```

A sessão pareada reconheceu a causa raiz sem se eximir: *"O problema não foi a arquitetura; foi eu não ter mantido um registro mestre da evolução do roadmap. Isso fez parecer que eu estava 'inventando' a sequência ao longo do caminho."* — e foi explícita sobre a limitação estrutural por trás disso: conversas muito longas são resumidas, não preservadas literalmente; a arquitetura geral, as decisões importantes e o estado do projeto sobrevivem ao resumo, mas detalhes pontuais (o nome exato de uma tabela, uma convenção definida em uma única mensagem, um roadmap intermediário nunca consolidado por escrito) podem se perder. Conclusão registrada, consistente com o papel desta documentação: **"Para um projeto do tamanho do Project Mimikyu, não devemos depender apenas da memória da conversa. Isso seria um risco desnecessário."** — exatamente a razão de ser deste documento e de `06-pipeline-importacao.md` como fonte de verdade, em vez de qualquer histórico de conversa.

**Reformulação do roteiro, para eliminar o framing frágil de "Bloqueios" numerados dispersos pela seção e substituí-lo por uma estrutura hierárquica de Fases e Blocos:**

**FASE 1 — Catálogo Editorial (em andamento)**

- **Bloco A — Modelo de Dados.** Status: **Concluído**, com uma adição pontual nesta revisão (`0.51`). Cobre `game`, `expansion`, `card_set`, `card`, `language`, `rarity`, `card_variant_type`/`card_variant`, `card_asset_type`/`card_asset`, `storage_bucket`, `asset_source`, `card_external_reference`, `asset_import_run`, `asset_import_failure`, `card_set_external_reference` — todas as entidades e camadas documentadas até este ponto do documento. **Nota sobre `card_set_external_reference`**: mesmo com o Bloco A já "concluído", esta entidade foi identificada como uma lacuna real de modelagem durante o próprio Sprint B2.5 do Bloco B — antes de consultar a TCGdex por um `card_set`, o pipeline precisa saber qual identificador externo corresponde a cada `card_set` interno, exatamente como `card_external_reference` já resolve para `card`. Tratado como uma extensão do Bloco A, não como parte do Bloco B (que permanece focado em código/orquestração, não em modelo de dados) — ver seção "Card Set External Reference", abaixo, e `06-pipeline-importacao.md`, "Sprint B2.5", para o contexto completo da descoberta.
- **Bloco B — Pipeline de Importação.** Status: **iniciado nesta revisão (`0.50`).** As tabelas do Bloco A já sustentam esta camada; a arquitetura completa da Edge Function `import-card-assets` foi especificada (14 responsabilidades: validação da execução, seleção de cartas, resolução de referência externa, fontes TCGdex/Pokémon TCG API, download/validação, formato canônico, caminho no Storage, política de upload, registro em `card_asset`, hash/idempotência, tratamento de falhas, contadores/status final, segurança, estrutura de arquivos) e um roteiro de 12 sprints incrementais (`B2.1`–`B2.12`) foi definido. O código do Sprint B2.1 (Edge Function básica, sem lógica de importação) foi proposto, mas **deploy ainda não confirmado**. Ver `06-pipeline-importacao.md`, seções "Arquitetura de Execução — Edge Function `import-card-assets`" e "Roteiro de Implementação Incremental", para o detalhamento completo — este documento (`05`) permanece focado no modelo de dados/SQL, sem duplicar o conteúdo de arquitetura de código (ver `03-documentation-architecture.md`, "Não duplicar conteúdo entre artefatos"). Este bloco substitui, na prática, o antigo item "4" do Bloqueio 5 ("Edge Function + piloto controlado").
- **Bloco C — Carga Editorial.** Status: **ainda não iniciado, depende do Bloco B.** É a Query `880 - Seed Card Asset`, mas com uma função diferente da originalmente cogitada: não será mais um `INSERT` manual de URLs, e sim uma **orquestração** — `Executar importador (Bloco B) → popular card_asset`. `880` passa a ser o ponto de entrada que aciona o pipeline, não uma carga de dados em si.

**FASE 2 — Coleções.** Só se inicia depois que Fase 1 estiver com catálogo, imagens e `card_asset` populados — representará a coleção física do usuário (cópias, itens individuais, aquisições, condição, localização, custos, movimentações, status de posse), mantida deliberadamente separada do Catálogo Editorial desde a concepção original do projeto (ver `AP-016 - Princípio da Unicidade do Catálogo`).

**Separação conceitual reafirmada nesta revisão** (Catálogo Editorial vs. Coleções do Usuário — mesma distinção que motivou Fabrício a interromper a tentativa de generalização de `asset_import_run` na revisão `0.48`, ver "Query 220", acima):

```text
CATÁLOGO EDITORIAL          COLEÇÕES DO USUÁRIO
game                        cópias físicas
expansion                   itens individuais
card_set                    aquisições
card                        condição
card_asset                  localização
asset_source                custos
card_external_reference     movimentações
asset_import_run            status de posse
asset_import_failure
```

---

# Language (Idioma)

## Status

**Camada Language integralmente executada, integrada a `card_asset` e homologada por Query de validação própria.** `190`/`191`/`192`/`890`/`970` CONFIRMADOS EXECUTADOS; a integração com `card_asset` (`193`/`194`) também **CONFIRMADA EXECUTADA por Fabrício nesta revisão** — ver "Query 193"/"Query 194"/"Query 970", abaixo. Surgiu como pré-requisito direto da Query `880`: ao decidir que `card_asset` precisa distinguir o idioma da imagem exibida (ver Bloqueio 3 da seção Card Asset, acima), tornou-se necessário formalizar `language` como um catálogo de referência, em vez de um campo de texto livre em `card_asset` — mesmo padrão já usado para `card_variant_type`/`card_asset_type` (evitar risco de duplicidade como `PT`/`pt`/`pt_BR`/`Português` representando o mesmo idioma).

> **Divergência da revisão `0.42`/`0.43` — RESOLVIDA nesta revisão.** As revisões anteriores sinalizaram que uma captura real de Table Editor parecia mostrar `card_asset` sem a coluna `storage_provider`, o que seria incompatível com a execução relatada de `194 - Govern Card Asset Storage Provider` (cujo próprio bloco de pré-requisito exige essa coluna). Fabrício esclareceu diretamente, nesta revisão: **"Houve execução real de 193 e 194."** — confirmação explícita e direta, tratada como a fonte de verdade mais recente sobre o estado real do banco. A suspeita registrada anteriormente permanece descrita aqui por rastreabilidade histórica, mas não deve mais orientar o tratamento de `193`/`194` como não confiáveis.
>
> **Discrepância de numeração — RESOLVIDA (histórico).** A sessão pareada reconheceu explicitamente a colisão sinalizada na revisão anterior ("eu sugiro utilizar 193, e não 192, porque a 192 acabou de ser utilizada para o refinamento da constraint da tabela `language`. Assim mantemos a numeração das migrations única e sem reutilização.") — a migration que adiciona `language_id` a `card_asset` foi de fato numerada e executada como `193`, confirmando a suposição já registrada na revisão `0.40`.
>
> **⚠️ Nova discrepância de numeração, sinalizada nesta revisão — a Query `970 - Validate Language` colide com a já existente `970 - Validate Card Asset Type`.** Ver a nota de numeração completa no bloco "Queries" da seção Card Asset Type/Card Asset, acima.

## Decisão de Modelagem

`language` é um catálogo **global**, sem `game_id` — o idioma não pertence exclusivamente ao Pokémon TCG nem a nenhum Game específico. Catálogo inicial planejado: `pt-BR` (Português Brasil) e `en` (Inglês) — os dois idiomas com imagens reais já confirmadas nas Cards do projeto.

**Formato de `code` revisado antes de qualquer carga de dados (Query `192`, abaixo).** A revisão do padrão BCP 47 completo usado por `190` mostrou-se mais permissiva do que o domínio do projeto precisa (aceitaria, por exemplo, variantes de script como `zh-Hant-TW`). Como a tabela `language` ainda não continha nenhum registro, a simplificação foi feita sem qualquer impacto: `code` passa a aceitar apenas os formatos `xx` ou `xx-YY` (ex.: `en`, `ja`, `fr`, `es`, `de`, `it`, `pt-BR`, `pt-PT`) — suficiente para todos os idiomas do Pokémon TCG previstos, reduz ambiguidade e simplifica validação futura.

## Modelo Físico — Versão 1.0 (CONFIRMADO EXECUTADO)

```sql
CREATE TABLE IF NOT EXISTS public.language (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    native_name TEXT NOT NULL,
    language_order INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_language_code
        UNIQUE (code),
    CONSTRAINT uq_language_order
        UNIQUE (language_order),
    CONSTRAINT ck_language_code_not_blank
        CHECK (BTRIM(code) <> ''),
    CONSTRAINT ck_language_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_language_native_name_not_blank
        CHECK (BTRIM(native_name) <> ''),
    CONSTRAINT ck_language_code_format
        CHECK (
            code ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$'
        ),
    CONSTRAINT ck_language_order_positive
        CHECK (language_order > 0)
);

CREATE INDEX IF NOT EXISTS ix_language_is_active
    ON public.language (is_active);

ALTER TABLE public.language ENABLE ROW LEVEL SECURITY;
```

Regras de negócio: `code` único, formato revisado pela `192` (`xx` ou `xx-YY`, ver acima); `name`/`native_name` não podem ser vazios; `language_order` positivo e único; `is_active` permite desativar um idioma sem apagar registros já vinculados; RLS habilitado. Cabeçalho original (Query `190 - Create Language Table`, v1.0, Status declarado `CANÔNICA` pelo autor) executado em `BEGIN`/`COMMIT`, com comentários (`COMMENT ON TABLE`/`COMMENT ON COLUMN`) completos em português. Arquivo escrito em `database/schema/190_create_language_table.sql`.

## Query 191 — Create Language Triggers (CONFIRMADO EXECUTADO)

Mesmo padrão já usado em todas as demais entidades do catálogo (`101`/`111`/`121`/`131`/`141`/`151`/`161`/`171`/`181`): valida a existência de `public.set_updated_at()` antes de criar o trigger, recria `trg_language_set_updated_at` via `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`, sem nenhuma regra de negócio adicional. Confirmado executado por Fabrício ("Executada com sucesso"). Arquivo escrito em `database/schema/191_create_language_triggers.sql`.

## Query 192 — Refine Language Code Constraint (CONFIRMADO EXECUTADO — não é a migration de `card_asset`)

Migration de ajuste pontual, não a adição de `language_id` a `card_asset` originalmente prevista para este número (ver "Discrepância de numeração", acima). `ALTER TABLE public.language DROP CONSTRAINT IF EXISTS ck_language_code_format` seguido de `ADD CONSTRAINT` com o novo regex `^[a-z]{2}(-[A-Z]{2})?$`, executada com segurança porque a tabela ainda não tinha registros. Confirmado executado por Fabrício ("Executada com sucesso"). Arquivo escrito em `database/migrations/192_refine_language_code_constraint.sql` (mesma pasta de `122_adapt_card_set_for_promo.sql`, precedente de migration pontual pós-criação).

## Query 890 — Seed Language (CONFIRMADO EXECUTADO)

Carga idempotente via `INSERT ... ON CONFLICT (code) DO UPDATE`, mesmo padrão já usado em `840`/`850`/`860`. Cadastra os dois idiomas com imagens reais já confirmadas nas Cards do projeto: `pt-BR` (Português Brasil, `language_order = 1`) e `en` (English, `language_order = 2`), ambos `is_active = TRUE`. Confirmado executado por Fabrício ("Executada com sucesso"). Arquivo escrito em `database/seeds/890_seed_language.sql`.

## Query 193 — Add Language to Card Asset (CONFIRMADO EXECUTADO)

**Migration estrutural mais importante deste bloco** — integra `language` a `card_asset`, resolvendo a discrepância de numeração já documentada (era esperada como `192`, foi de fato executada como `193`). Passos, todos confirmados via `RAISE EXCEPTION` de pré-requisito + blocos `DO $$` idempotentes: (1) valida pré-requisitos (`card_asset`/`language` existem, `pt-BR` cadastrado); (2) adiciona `language_id UUID` (inicialmente nulo); (3) migra registros existentes para `pt-BR` (classificação retroativa — qualquer Card Asset anterior à introdução do idioma é tratado como português do Brasil); (4) torna `language_id NOT NULL`; (5) cria a FK `fk_card_asset_language`; (6) remove, por introspecção de `pg_constraint`, a antiga `UNIQUE` exata em `card_id`+`asset_type_id`+`asset_order` (sem depender de conhecer o nome real da constraint); (7) remove, por introspecção de `pg_index`, o antigo índice único parcial de ativo principal por `card_id`+`asset_type_id`; (8) cria `uq_card_asset_card_type_language_order` — `UNIQUE (card_id, asset_type_id, language_id, asset_order)`; (9) cria `ux_card_asset_primary_per_card_type_language` — índice único parcial `(card_id, asset_type_id, language_id) WHERE is_primary = TRUE`; (10)-(11) índices de suporte para consulta por idioma; (12) comentários. Confirmado executado por Fabrício ("Executada com sucesso"; reafirmado nesta revisão — "Houve execução real de 193 e 194."). Arquivo escrito em `database/migrations/193_add_language_to_card_asset.sql`.

**Resultado**: `language_id` já existia fisicamente antes desta Query ser escrita (consistente com a listagem original da revisão `0.30`) — o passo `ADD COLUMN IF NOT EXISTS language_id` foi um no-op para a coluna em si. As mudanças de constraint (`uq_card_asset_card_type_language_order`, `ux_card_asset_primary_per_card_type_language`, `fk_card_asset_language`) são tratadas, junto com o restante desta Query, como confirmadas — ver "Status", acima.

## Query 194 — Govern Card Asset Storage Provider (CONFIRMADO EXECUTADO — revertida por `197`)

Proposta pela sessão pareada como uma última melhoria antes da `880`: em vez de criar uma nova entidade `asset_source` (ideia já cogitada e descartada anteriormente por escopo), formaliza `storage_provider` como um enumerador governado por `CHECK`, em vez de texto livre. Passos: (1) valida pré-requisitos, incluindo a existência da própria coluna `storage_provider`; (2) normaliza valores existentes (aliases como `SUPABASE STORAGE`→`SUPABASE`, `AWS S3`/`AMAZON S3`→`S3`, `CLOUDFLARE R2`→`R2`, `LOCAL STORAGE`→`LOCAL`, `URL`/`EXTERNAL URL`→`EXTERNAL`; valores nulos/vazios classificados como `EXTERNAL` quando há `external_url`, senão `LOCAL`); (3) valida que não sobrou nenhum valor fora do enumerador e que a localização é compatível antes de criar as constraints (evita quebrar em runtime); (4) torna `storage_provider NOT NULL`; (5) cria `ck_card_asset_storage_provider` — `CHECK (storage_provider IN ('SUPABASE','S3','R2','LOCAL','EXTERNAL'))`; (6) cria `ck_card_asset_storage_provider_location` — `EXTERNAL` exige `external_url`, os demais exigem `storage_path`; (7) comentários. Confirmado executado por Fabrício ("Executada sem intercorrências"; reafirmado nesta revisão). Arquivo escrito em `database/migrations/194_govern_card_asset_storage_provider.sql`.

**Vida útil curta, confirmada nesta revisão**: a evolução arquitetural desta mesma revisão (ver "Arquitetura de Armazenamento", seção Card Asset Type/Card Asset, acima) decidiu que `storage_provider` era redundante em `card_asset` uma vez que `storage_bucket` (nova entidade, ver seção "Storage Bucket", abaixo) já carrega essa informação por bucket. A migration `197 - Integrate Storage Bucket into Card Asset` **removeu `storage_provider` de `card_asset`** (CONFIRMADA EXECUTADA) — ou seja, esta coluna, embora confirmada executada e correta no momento em que rodou, teve vida útil curta por decisão arquitetural posterior, não por erro de execução. `storage_provider` não existe mais em `card_asset`; o dado equivalente é obtido hoje via `JOIN` com `storage_bucket`.

## Query 970 — Validate Language (EXECUTADA — ⚠️ ver nota de numeração)

Validação estrutural e de conteúdo completa de `language`, no mesmo padrão de rigor já aplicado a `930`/`950`/`960`/`970` (Card Asset Type): existência da tabela, estrutura de colunas (tipo/nulidade), ausência de colunas inesperadas, defaults, primary key, sete constraints obrigatórias (`uq_language_code`, `uq_language_order`, três `CHECK` de não-vazio, `ck_language_code_format`, `ck_language_order_positive`), conteúdo textual da constraint de formato (confirma que usa o padrão `xx`/`xx-YY` da `192`, não o BCP 47 original da `190`), índice `ix_language_is_active`, trigger `trg_language_set_updated_at`, RLS habilitado, integridade geral dos dados, unicidade lógica de `code`/`language_order`, presença e valores exatos dos dois idiomas obrigatórios (`pt-BR`/`en`), quantidade mínima de dois registros. Confirmado executado por Fabrício ("Success. No rows returned" — sem `RAISE EXCEPTION`, portanto sem falhas). Arquivo escrito em `database/validations/970_validate_language.sql`. **Ver a ressalva de numeração**: este número colide com `970 - Validate Card Asset Type`, já executada em ciclo anterior — ver "Queries", seção Card Asset Type/Card Asset, acima.

## Impacto em `card_asset` — Confirmado por `193`/`194`, com vida útil planejada para parte de `194`

`card_asset` ganhou, confirmado por Fabrício nesta revisão: `language_id UUID NOT NULL` (FK `fk_card_asset_language`, coluna que na prática já existia antes de `193`); unicidade revisada de `card_id`+`asset_type_id`+`asset_order` para `card_id`+`asset_type_id`+`language_id`+`asset_order` (`uq_card_asset_card_type_language_order`); ativo principal por `card_id`+`asset_type_id`+`language_id` (`ux_card_asset_primary_per_card_type_language`); `storage_provider` obrigatório e restrito a `SUPABASE`/`S3`/`R2`/`LOCAL`/`EXTERNAL` (`ck_card_asset_storage_provider`); compatibilidade de localização por provedor (`ck_card_asset_storage_provider_location`). Isso permite, por exemplo, que a mesma Card tenha `CARD_FRONT` + `ARTWORK`, cada um em `pt-BR` e em `en`, cada combinação com seu próprio ativo principal — exatamente o cenário ilustrado pela sessão pareada com a Card `Rufflet` (ME2.5-173). **Ressalva**: a parte de `storage_provider`/`ck_card_asset_storage_provider`/`ck_card_asset_storage_provider_location` está confirmada como executada, mas será removida pela migration planejada `197` — ver "Query 194", acima, e "Arquitetura de Armazenamento", seção Card Asset Type/Card Asset.

## Sequência (atualizada com o estado real de execução)

```text
170 - Create Card Asset Type Table       (EXECUTADA)
171 - Create Card Asset Type Triggers    (EXECUTADA)
870 - Seed Card Asset Type               (EXECUTADA v1.2)
970 - Validate Card Asset Type           (EXECUTADA v1.2)

180 - Create Card Asset Table            (EXECUTADA v1.1 — ver ressalva de no-op acima)
181 - Create Card Asset Triggers         (EXECUTADA v1.1)

190 - Create Language Table              (CONFIRMADO EXECUTADO — database/schema/190_create_language_table.sql)
191 - Create Language Triggers           (CONFIRMADO EXECUTADO — database/schema/191_create_language_triggers.sql)
192 - Refine Language Code Constraint    (CONFIRMADO EXECUTADO — database/migrations/192_refine_language_code_constraint.sql; NÃO é a migration de card_asset)
193 - Add Language to Card Asset         (CONFIRMADO EXECUTADO — database/migrations/193_add_language_to_card_asset.sql)
194 - Govern Card Asset Storage Provider (CONFIRMADO EXECUTADO — database/migrations/194_govern_card_asset_storage_provider.sql; revertida por 197)
890 - Seed Language                      (CONFIRMADO EXECUTADO — database/seeds/890_seed_language.sql; pt-BR/en, tabela independente de card_asset)
970 - Validate Language                  (EXECUTADA — database/validations/970_validate_language.sql; ⚠️ colide em número com 970 Card Asset Type)

195 - Create Storage Bucket              (EXECUTADA — ver seção "Storage Bucket", abaixo)
196 - Create Storage Bucket Triggers     (EXECUTADA)
895 - Seed Storage Bucket                (EXECUTADA)
975 - Validate Storage Bucket            (EXECUTADA v1.1 — ⚠️ deveria ser 995 pelo padrão de deslocamento fixo)

197 - Integrate Storage Bucket into Card Asset (CONFIRMADA EXECUTADA — database/migrations/197_integrate_storage_bucket_into_card_asset.sql; remove storage_provider, integra storage_bucket_id)

980 - Validate Card Asset (v2.0)         (CONFIRMADA EXECUTADA E HOMOLOGADA — database/validations/980_validate_card_asset.sql; ver "Query 980", acima)

200 - Create Asset Source                (CONFIRMADA EXECUTADA — database/schema/200_create_asset_source.sql; ver seção "Asset Source", abaixo)
201 - Asset Source Triggers              (CONFIRMADA EXECUTADA — database/schema/201_asset_source_triggers.sql)
900 - Seed Asset Source                  (CONFIRMADA EXECUTADA — database/seeds/900_seed_asset_source.sql; ⚠️ colide em número com 900 Validate Game)
985 - Validate Asset Source              (CONFIRMADA EXECUTADA E HOMOLOGADA — database/validations/985_validate_asset_source.sql)

210 - Create Card External Reference     (CONFIRMADA EXECUTADA — database/schema/210_create_card_external_reference.sql; ver seção "Card External Reference", abaixo)
211 - Card External Reference Triggers   (CONFIRMADA EXECUTADA — database/schema/211_card_external_reference_triggers.sql)
990 - Validate Card External Reference   (CONFIRMADA EXECUTADA E HOMOLOGADA — database/validations/990_validate_card_external_reference.sql)

220 - Create Asset Import Run            (CONFIRMADA EXECUTADA — database/schema/220_create_asset_import_run.sql; ver "Query 220", acima)
221 - Asset Import Run Triggers          (CONFIRMADA EXECUTADA — database/schema/221_asset_import_run_triggers.sql)
230 - Create Asset Import Failure        (CONFIRMADA EXECUTADA — database/schema/230_create_asset_import_failure.sql; ver "Query 230", acima)
231 - Asset Import Failure Triggers      (CONFIRMADA EXECUTADA — database/schema/231_asset_import_failure_triggers.sql)
995 - Validate Asset Import Infrastructure (CONFIRMADA EXECUTADA E HOMOLOGADA — database/validations/995_validate_asset_import_infrastructure.sql)

240 - Create Card Set External Reference (CONFIRMADA EXECUTADA — database/schema/240_create_card_set_external_reference.sql; ver seção "Card Set External Reference", abaixo)
241 - Card Set External Reference Triggers (CONFIRMADA EXECUTADA — database/schema/241_card_set_external_reference_triggers.sql)
910 - Seed Card Set External Reference   (CONFIRMADA EXECUTADA — PARCIAL — database/seeds/910_seed_card_set_external_reference.sql; ME1/ME2/ME2.5/ME3/ME4 mapeados; ME0 removida de card_set — Migration 251, decisão de negócio resolvida: sem relação com mee; ME5 aguarda card_set; número colide com 910 Validate Expansion, mesmo padrão de colisão de numeração entre pastas já registrado para 900/970/975)
991 - Validate Card Set External Reference (planejada, ainda NÃO executada)

880 - Seed Card Asset                    (bloqueada até o pipeline de importação [Fase 1, Bloco B — Edge Function, ainda não implementada] existir e um piloto controlado ser executado, ver "Roteiro Consolidado", acima)
```

---

# Storage Bucket

## Status

**Camada Storage Bucket criada, semeada e homologada nesta revisão — `195`/`196`/`895`/`975` CONFIRMADOS EXECUTADOS.** Surgiu de uma evolução arquitetural durante a discussão de armazenamento da Query `880` (ver "Arquitetura de Armazenamento", seção Card Asset Type/Card Asset, acima): ao propor uma nova coluna `storage_bucket` em `card_asset`, foi identificado que essa informação melhor pertence a uma entidade de catálogo própria — mesmo padrão já usado para `language`/`card_asset_type`/`card_variant_type` — e que `card_asset.storage_bucket_id` (presente desde a estrutura física original) provavelmente já era uma FK para uma tabela `storage_bucket` pré-existente entre as 17 tabelas originais do projeto, ainda não detalhada nesta documentação.

## Decisão de Modelagem

`storage_bucket` representa a camada de infraestrutura de um Object Storage moderno: `Storage Provider → Storage Bucket → Object (Path)`. Cada bucket possui seu próprio `storage_provider` — a informação de "onde" um ativo está hospedado passa a depender do bucket a que ele pertence, não de uma coluna redundante em cada ativo (ver "Arquitetura de Armazenamento", acima, para o racional completo da normalização). Catálogo inicial: `card-front`, `artwork`, `card-back` — um bucket por Card Asset Type, todos `storage_provider = SUPABASE`, `is_public = TRUE`. Buckets futuros previstos, sem exigir nova migration estrutural: `thumbnail`, `zoom`, `binder-cover`, `deck-image`.

## Modelo Físico — Versão 1.0 (CONFIRMADO EXECUTADO)

```sql
CREATE TABLE IF NOT EXISTS public.storage_bucket (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    storage_provider TEXT NOT NULL,
    bucket_order INTEGER NOT NULL,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_storage_bucket_code
        UNIQUE (code),
    CONSTRAINT uq_storage_bucket_order
        UNIQUE (bucket_order),
    CONSTRAINT ck_storage_bucket_code_not_blank
        CHECK (BTRIM(code) <> ''),
    CONSTRAINT ck_storage_bucket_code_format
        CHECK (code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    CONSTRAINT ck_storage_bucket_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_storage_bucket_description_not_blank
        CHECK (description IS NULL OR BTRIM(description) <> ''),
    CONSTRAINT ck_storage_bucket_provider
        CHECK (storage_provider IN ('SUPABASE', 'S3', 'R2', 'LOCAL', 'EXTERNAL')),
    CONSTRAINT ck_storage_bucket_order_positive
        CHECK (bucket_order > 0)
);

CREATE INDEX IF NOT EXISTS ix_storage_bucket_storage_provider
    ON public.storage_bucket (storage_provider);
CREATE INDEX IF NOT EXISTS ix_storage_bucket_is_active
    ON public.storage_bucket (is_active);
CREATE INDEX IF NOT EXISTS ix_storage_bucket_provider_active
    ON public.storage_bucket (storage_provider, is_active);

ALTER TABLE public.storage_bucket ENABLE ROW LEVEL SECURITY;
```

Regras de negócio: `code` único, minúsculo, letras/números/hífens sem hífen nas pontas (mesmo padrão de nomes de bucket do Supabase Storage); `name` não vazio; `description` opcional, não vazio quando presente; `storage_provider` restrito ao mesmo enumerador homologado para `card_asset` (`SUPABASE`/`S3`/`R2`/`LOCAL`/`EXTERNAL`); `bucket_order` positivo e único; `is_public` indica se os objetos são acessíveis por URL pública direta (sem URL assinada); `is_active` permite desativar um bucket sem apagar referências já existentes; RLS habilitado. Cabeçalho original (Query `195 - Create Storage Bucket`, v1.0, Status declarado `CANÔNICA` pelo autor) executado em `BEGIN`/`COMMIT`, com comentários completos em português. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/195_create_storage_bucket.sql`.

## Query 196 — Create Storage Bucket Triggers (CONFIRMADO EXECUTADO)

Mesmo padrão já usado em todas as demais entidades do catálogo: valida a existência de `public.set_updated_at()` antes de criar o trigger, recria `trg_storage_bucket_set_updated_at` via `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`, sem regra de negócio adicional. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/196_create_storage_bucket_triggers.sql`.

## Query 895 — Seed Storage Bucket (CONFIRMADO EXECUTADO)

Carga idempotente via `INSERT ... ON CONFLICT (code) DO UPDATE`, mesmo padrão já usado em `840`/`850`/`860`/`890`. Cadastra os três buckets iniciais, um por Card Asset Type já homologado: `card-front` (`bucket_order = 1`), `artwork` (`bucket_order = 2`), `card-back` (`bucket_order = 3`), todos `storage_provider = SUPABASE`, `is_public = TRUE`, `is_active = TRUE`. **Nota operacional importante, destacada pela sessão pareada**: esta migration registra os buckets apenas no catálogo PostgreSQL — os buckets físicos correspondentes ainda precisam ser criados manualmente no painel do Supabase Storage, com exatamente esses nomes (`card-front`, `artwork`, `card-back`), antes de qualquer upload real de imagem. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/seeds/895_seed_storage_bucket.sql`.

## Query 975 — Validate Storage Bucket (v1.1, EXECUTADA — ⚠️ ver nota de numeração)

Validação mais extensa já aplicada a uma entidade de catálogo simples neste projeto: além dos blocos estruturais padrão (colunas, ausência de colunas inesperadas, defaults, primary key, unicidade de `code`/`bucket_order`, mínimo de 5 `CHECK` constraints, índices, trigger, RLS), inclui **quatro testes controlados de rejeição** — tentativas de `INSERT` com `storage_provider` inválido, `code` fora do formato, `name` vazio e `bucket_order` não positivo, cada uma esperando que o banco rejeite via `check_violation` (e a própria validação falha se a rejeição não ocorrer). Nenhum desses registros de teste permanece na tabela. Fecha com verificação de conteúdo exato dos três buckets obrigatórios e contagem mínima de 3 registros. A versão 1.1 corrigiu uma premissa de tipo: "esta versão espera o seguinte tipo real: `storage_provider → text`; ela não pressupõe a existência de um `ENUM` chamado `storage_provider`" (evitando o erro de assumir um tipo `ENUM` nativo, que o projeto já havia descartado desde a modelagem original de `set_type`/`storage_provider`, preferindo `CHECK`). Confirmado executado por Fabrício ("Success. No rows returned", validação concluída sem exceções). Arquivo escrito em `database/validations/975_validate_storage_bucket.sql`. **Ver a ressalva de numeração** no bloco "Queries", seção Card Asset Type/Card Asset, acima.

## Sequência

```text
195 - Create Storage Bucket              (CONFIRMADO EXECUTADO — database/schema/195_create_storage_bucket.sql)
196 - Create Storage Bucket Triggers     (CONFIRMADO EXECUTADO — database/schema/196_create_storage_bucket_triggers.sql)
895 - Seed Storage Bucket                (CONFIRMADO EXECUTADO — database/seeds/895_seed_storage_bucket.sql; buckets físicos no Supabase Storage AINDA precisam ser criados manualmente)
975 - Validate Storage Bucket            (EXECUTADA v1.1 — database/validations/975_validate_storage_bucket.sql; ⚠️ ver nota de numeração)

197 - Integrate Storage Bucket into Card Asset (CONFIRMADA EXECUTADA — database/migrations/197_integrate_storage_bucket_into_card_asset.sql; ver seção Card Asset Type/Card Asset, "Query 197")
```

---

# Asset Source

## Status

**Camada Asset Source criada, semeada e homologada nesta revisão — `200`/`201`/`900`/`985` CONFIRMADOS EXECUTADOS.** Primeira camada da nova infraestrutura de importação de ativos (ver "Arquitetura de Importação de Ativos", seção Card Asset Type/Card Asset, acima), construída após correção explícita de rota por Fabrício ("Não seguiremos agora para: 880 – Seed Card Asset. O próximo passo será estrutural: 200 – Create Asset Source [...]"). A Query `200` incluiu sua própria guarda defensiva contra recriação (`IF to_regclass('public.asset_source') IS NOT NULL THEN RAISE EXCEPTION`), que **não disparou** — evidência direta de que a tabela não existia previamente no banco conectado, o que contradiz o registro histórico de `docs/06-pipeline-importacao.md` (ver a correção ao "Risco Crítico" na seção "Arquitetura de Importação de Ativos", acima).

## Decisão de Modelagem

`asset_source` é o catálogo das fontes externas usadas para aquisição de metadados e arquivos digitais das cartas (Pokémon TCG API, TCGdex, importação manual controlada), mantendo separadas a origem do arquivo (rastreabilidade) e a localização definitiva do arquivo internalizado no Supabase Storage (`card_asset.storage_bucket_id`/`storage_path`). Mesmo padrão arquitetural das demais entidades de catálogo do projeto (`language`, `storage_bucket`, `card_asset_type`): `id, code, name, source_type, base_url, api_base_url, documentation_url, terms_url, attribution_text, supports_api, supports_bulk_download, is_active, source_order, created_at, updated_at`. Catálogo inicial: `POKEMON_TCG_API` (`API`, com suporte a API e download em lote), `TCGDEX` (`API`, com suporte a API, sem download em lote), `MANUAL` (`MANUAL`, sem API nem download em lote — importação manual controlada).

## Modelo Físico — Versão 1.0 (CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.asset_source (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    source_type TEXT NOT NULL,
    base_url TEXT,
    api_base_url TEXT,
    documentation_url TEXT,
    terms_url TEXT,
    attribution_text TEXT,
    supports_api BOOLEAN NOT NULL DEFAULT FALSE,
    supports_bulk_download BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    source_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_asset_source_code UNIQUE (code),
    CONSTRAINT uq_asset_source_order UNIQUE (source_order),
    CONSTRAINT ck_asset_source_code
        CHECK (code = UPPER(code) AND code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_asset_source_name CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_asset_source_type
        CHECK (source_type IN ('API', 'DATASET', 'MANUAL')),
    CONSTRAINT ck_asset_source_base_url
        CHECK (base_url IS NULL OR (BTRIM(base_url) <> '' AND base_url ~* '^https://')),
    CONSTRAINT ck_asset_source_api_base_url
        CHECK (api_base_url IS NULL OR (BTRIM(api_base_url) <> '' AND api_base_url ~* '^https://')),
    CONSTRAINT ck_asset_source_documentation_url
        CHECK (documentation_url IS NULL OR (BTRIM(documentation_url) <> '' AND documentation_url ~* '^https://')),
    CONSTRAINT ck_asset_source_terms_url
        CHECK (terms_url IS NULL OR (BTRIM(terms_url) <> '' AND terms_url ~* '^https://')),
    CONSTRAINT ck_asset_source_attribution_text
        CHECK (attribution_text IS NULL OR BTRIM(attribution_text) <> ''),
    CONSTRAINT ck_asset_source_order CHECK (source_order > 0),
    CONSTRAINT ck_asset_source_api_configuration
        CHECK (supports_api = FALSE OR api_base_url IS NOT NULL),
    CONSTRAINT ck_asset_source_manual_configuration
        CHECK (source_type <> 'MANUAL' OR (supports_api = FALSE AND supports_bulk_download = FALSE))
);

CREATE INDEX ix_asset_source_active_order ON public.asset_source (is_active, source_order);
CREATE INDEX ix_asset_source_type ON public.asset_source (source_type);

ALTER TABLE public.asset_source ENABLE ROW LEVEL SECURITY;
```

Regras de negócio: `code` único, maiúsculo, iniciando por letra (`^[A-Z][A-Z0-9_]*$`); `name` não vazio; `source_type` restrito a `API`/`DATASET`/`MANUAL`; URLs (`base_url`/`api_base_url`/`documentation_url`/`terms_url`), quando presentes, devem começar com `https://`; `attribution_text` opcional, não vazio quando presente; `source_order` positivo e único; se `supports_api = TRUE`, `api_base_url` é obrigatório; fontes `MANUAL` não podem declarar suporte a API nem a download em lote; RLS habilitado. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/200_create_asset_source.sql`.

## Query 201 — Asset Source Triggers (CONFIRMADO EXECUTADO)

Três triggers: `trg_asset_source_normalize` (`normalize_asset_source()` — normaliza `code` para maiúsculo/sem espaços, `name`/`source_type` aparados, URLs e `attribution_text` convertidos para `NULL` quando vazios), `trg_asset_source_set_updated_at` (padrão já usado em todas as entidades), e **`trg_asset_source_protect_identity`** (`protect_asset_source_identity()`) — **primeiro uso neste projeto de um trigger de proteção de identidade que bloqueia explicitamente a alteração de `id` ou `code` via `RAISE EXCEPTION` em `UPDATE`**, mais rígido que o padrão de imutabilidade observado em outras entidades. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/201_asset_source_triggers.sql`.

## Query 900 — Seed Asset Source (CONFIRMADO EXECUTADO — ⚠️ ver nota de numeração)

Carga idempotente via `INSERT ... ON CONFLICT (code) DO UPDATE`, mesmo padrão já usado em `840`/`850`/`860`/`890`/`895`. Cadastra as três fontes iniciais: `POKEMON_TCG_API` (`source_order = 1`, API REST com documentação pública, suporte a API e a download em lote), `TCGDEX` (`source_order = 2`, catálogo multilíngue, suporte a API, sem download em lote), `MANUAL` (`source_order = 99`, importação manual controlada, sem API nem download em lote). Comentários reduzidos em relação às migrations estruturais — convenção adotada explicitamente por Fabrício nesta revisão (ver nota de processo, abaixo). Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/seeds/900_seed_asset_source.sql`. **Ver a ressalva de numeração** no bloco "Queries", seção Card Asset Type/Card Asset, acima — colide com `900 - Validate Game`.

## Query 985 — Validate Asset Source (CONFIRMADO EXECUTADO, HOMOLOGADA)

Validação estrutural e de dados completa: existência da tabela, presença das 15 colunas esperadas, primary key, unicidade de `code`/`source_order`, dois índices, três funções (`normalize_asset_source()`, `protect_asset_source_identity()`, `set_updated_at()`), três triggers, RLS habilitado, presença das três fontes obrigatórias (`POKEMON_TCG_API`/`TCGDEX`/`MANUAL`), integridade de dados (formato de `code`, `name` não vazio, `source_type` válido, `source_order` positivo), coerência de configuração (fonte com `supports_api = TRUE` exige `api_base_url`; fonte `MANUAL` não pode declarar suporte a API/lote), ausência de códigos e ordens duplicados. Confirmado executado por Fabrício ("Success. No rows returned") e declarado **HOMOLOGADA**. Arquivo escrito em `database/validations/985_validate_asset_source.sql`.

**Nota de processo, registrada nesta revisão por Fabrício**: a partir de agora, migrations estruturais (`200`/`201`/`202`...) mantêm o rigor de comentários completo já praticado; Seeds (`900`/`901`/`902`...) passam a ter comentários reduzidos, sem repetir o que já está óbvio no próprio SQL. Padrões já consolidados no projeto (`created_at`/`updated_at`, RLS, comentários, índices, validações, trigger de `updated_at`) passam a ser aplicados automaticamente, sem reexplicação a cada nova migration — mudança de ritmo declarada por Fabrício: *"Acredito que já passamos da fase de 'desenhar a arquitetura'. Agora estamos entrando na fase de 'construir o sistema'."*

## Sequência

```text
200 - Create Asset Source        (CONFIRMADA EXECUTADA — database/schema/200_create_asset_source.sql)
201 - Asset Source Triggers      (CONFIRMADA EXECUTADA — database/schema/201_asset_source_triggers.sql)
900 - Seed Asset Source          (CONFIRMADA EXECUTADA — database/seeds/900_seed_asset_source.sql; ⚠️ ver nota de numeração)
985 - Validate Asset Source      (CONFIRMADA EXECUTADA E HOMOLOGADA — database/validations/985_validate_asset_source.sql)
```

Ver seção "Card External Reference", abaixo, para a próxima camada do pipeline (já executada nesta revisão) e "Arquitetura de Importação de Ativos" (seção Card Asset Type/Card Asset, acima) para o estado revisado da camada de execução de importação — o plano `220`/`221`/`222`/`920`/`995` (Asset Import Job/Item) desta seção, na revisão `0.46`, foi **substituído** por uma arquitetura `asset_import_run`/`asset_import_failure`, ainda sem SQL nem números definidos.

---

# Card External Reference

## Status

**Camada Card External Reference criada, com triggers e homologada — `210`/`211`/`990` CONFIRMADOS EXECUTADOS. Primeira população real via pipeline (2026-07-24): `MEE`/`en`, 8/8 registros, `RUN-20260724-00000041`.** Segunda camada da infraestrutura de importação (depois de Asset Source), construída seguindo o mesmo roteiro em etapas — mapeia cada Card do Project Mimikyu ao seu identificador em uma fonte externa (`asset_source`), evitando correspondências frágeis baseadas apenas em nome/número presumidos. **A Seed `910` foi deliberadamente descartada**: Fabrício e a sessão pareada concluíram que, como ainda não existem correspondências reais confirmadas entre cartas internas e fontes externas, não faz sentido popular esta tabela com um `INSERT` estático — os registros reais serão produzidos automaticamente pela própria rotina de importação, à medida que ela descobre e confirma cada correspondência.

## Decisão de Modelagem

`card_external_reference` relaciona `card` (interno) a `asset_source` (externo) via `card_id`+`asset_source_id`, com o identificador da carta na fonte externa (`external_card_id`, obrigatório), o identificador da coleção na fonte externa (`external_set_id`, opcional), o número da carta conforme informado pela fonte (`source_number`, opcional), a URL do registro/página na fonte (`source_url`) e a URL usada para aquisição da imagem original (`image_source_url`) — ambas distintas, mantendo a URL de navegação separada da URL de download da imagem. `metadata JSONB` guarda atributos adicionais específicos da fonte sem exigir novas colunas. Estrutura final é mais rica que a proposta conceitual original da revisão `0.45` (que previa apenas `card_id`/`source_id`/`external_card_id`/`external_set_id`/`source_number`/`metadata`) — inclui também `source_url`/`image_source_url`/`is_active`, refletindo a necessidade de rastrear tanto a página de origem quanto a URL de aquisição da imagem separadamente.

## Modelo Físico — Versão 1.0 (CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.card_external_reference (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id UUID NOT NULL,
    asset_source_id UUID NOT NULL,
    external_card_id TEXT NOT NULL,
    external_set_id TEXT,
    source_number TEXT,
    source_url TEXT,
    image_source_url TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_card_external_reference_card
        FOREIGN KEY (card_id) REFERENCES public.card (id) ON DELETE CASCADE,
    CONSTRAINT fk_card_external_reference_asset_source
        FOREIGN KEY (asset_source_id) REFERENCES public.asset_source (id) ON DELETE RESTRICT,
    CONSTRAINT uq_card_external_reference_card_source
        UNIQUE (card_id, asset_source_id),
    CONSTRAINT uq_card_external_reference_source_external
        UNIQUE (asset_source_id, external_card_id),
    CONSTRAINT ck_card_external_reference_external_card_id
        CHECK (BTRIM(external_card_id) <> ''),
    CONSTRAINT ck_card_external_reference_external_set_id
        CHECK (external_set_id IS NULL OR BTRIM(external_set_id) <> ''),
    CONSTRAINT ck_card_external_reference_source_number
        CHECK (source_number IS NULL OR BTRIM(source_number) <> ''),
    CONSTRAINT ck_card_external_reference_source_url
        CHECK (source_url IS NULL OR (BTRIM(source_url) <> '' AND source_url ~* '^https://')),
    CONSTRAINT ck_card_external_reference_image_source_url
        CHECK (image_source_url IS NULL OR (BTRIM(image_source_url) <> '' AND image_source_url ~* '^https://')),
    CONSTRAINT ck_card_external_reference_metadata
        CHECK (JSONB_TYPEOF(metadata) = 'object')
);

CREATE INDEX ix_card_external_reference_card ON public.card_external_reference (card_id);
CREATE INDEX ix_card_external_reference_asset_source ON public.card_external_reference (asset_source_id);
CREATE INDEX ix_card_external_reference_external_set
    ON public.card_external_reference (asset_source_id, external_set_id) WHERE external_set_id IS NOT NULL;
CREATE INDEX ix_card_external_reference_source_number
    ON public.card_external_reference (asset_source_id, external_set_id, source_number) WHERE source_number IS NOT NULL;
CREATE INDEX ix_card_external_reference_active ON public.card_external_reference (asset_source_id, is_active);

ALTER TABLE public.card_external_reference ENABLE ROW LEVEL SECURITY;
```

Regras de negócio: FK para `card` (`ON DELETE CASCADE` — se a Card for removida, suas referências externas somem junto) e para `asset_source` (`ON DELETE RESTRICT` — não permite remover uma fonte enquanto houver referências dependentes); unicidade dupla — uma Card só pode ter uma referência por fonte (`card_id`+`asset_source_id`), e um identificador externo só pode apontar para uma Card dentro da mesma fonte (`asset_source_id`+`external_card_id`); `external_card_id` obrigatório e não vazio; demais campos textuais opcionais, não vazios quando presentes; URLs, quando presentes, devem começar com `https://`; `metadata` deve ser sempre um objeto JSON válido; RLS habilitado. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/210_create_card_external_reference.sql`.

## Query 211 — Card External Reference Triggers (CONFIRMADO EXECUTADO)

Mesmo padrão já estabelecido em `201` (Asset Source): `trg_card_external_reference_normalize` (`normalize_card_external_reference()` — apara textos, converte vazios para `NULL`, garante `metadata` nunca nulo), `trg_card_external_reference_set_updated_at` (padrão), e `trg_card_external_reference_protect_identity` (`protect_card_external_reference_identity()` — impede alteração de `id`, `card_id` e `asset_source_id` via `RAISE EXCEPTION`, mesmo padrão rígido introduzido em `201`). Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/211_card_external_reference_triggers.sql`.

## Query 990 — Validate Card External Reference (CONFIRMADO EXECUTADO, HOMOLOGADA)

Validação estrutural e de dados completa: existência da tabela, presença das 12 colunas esperadas, primary key, duas FKs (`card`, `asset_source`), duas unicidades compostas, cinco índices, duas funções e três triggers, RLS habilitado, integridade de dados (formato de URLs, `metadata` sempre objeto, `external_card_id` não vazio), ausência de duplicidade por Card+fonte e por fonte+identificador externo, integridade referencial contra `card` e `asset_source` inexistentes. Confirmado executado por Fabrício ("Success. No rows returned") e declarado **HOMOLOGADA**. Arquivo escrito em `database/validations/990_validate_card_external_reference.sql`.

## Sequência

```text
210 - Create Card External Reference     (CONFIRMADA EXECUTADA — database/schema/210_create_card_external_reference.sql)
211 - Card External Reference Triggers   (CONFIRMADA EXECUTADA — database/schema/211_card_external_reference_triggers.sql)
910 - Seed Card External Reference       (DESCARTADA DELIBERADAMENTE — sem seed estático; registros virão da rotina de importação)
990 - Validate Card External Reference   (CONFIRMADA EXECUTADA E HOMOLOGADA — database/validations/990_validate_card_external_reference.sql)
```

---

# Card Set External Reference

## Status

**Camada Card Set External Reference criada e com triggers nesta revisão — `240`/`241` CONFIRMADAS EXECUTADAS.** Terceira camada de mapeamento externo do projeto (depois de Asset Source e Card External Reference), descoberta como uma lacuna real durante o Sprint B2.5 de `06-pipeline-importacao.md`: antes de consultar a TCGdex por um `card_set`, o pipeline precisa saber qual identificador a TCGdex usa para aquele conjunto — informação que ainda não existia em nenhuma tabela do catálogo. Decisão explícita de Fabrício, justificada por manter a consistência do modelo: *"Isso quebra um princípio que seguimos desde o início: tudo que vem de sistemas externos deve ser persistido e rastreável. Na minha opinião, vale muito a pena gastar mais uma sprint agora e manter a consistência do modelo."*

**Episódio real, registrado por transparência: um mapeamento de teste incorreto foi inserido e corrigido antes de qualquer Seed formal.** Ao validar a Query `241`, um registro manual foi inserido em `card_set_external_reference` (`card_set: ME0`, `asset_source: TCGDEX`, `external_set: sv10pt5`). Ao revisar esse registro, ficou claro que **`sv10pt5` é o identificador de um Set oficial real da Pokémon na TCGdex — não o `ME0` do Project Mimikyu**. Isso reafirma uma decisão já registrada anteriormente: `ME0` **não existe oficialmente** como Set na TCGdex nem na Pokémon TCG API — é uma convenção interna, criada pelo Project Mimikyu, para organizar as cartas promocionais da expansão Megaevolution. Deixar o mapeamento incorreto em pé faria a Edge Function acreditar, erradamente, que as promos de `ME0` pertencem ao Set oficial `sv10pt5`. Corrigido via `DELETE FROM public.card_set_external_reference WHERE external_set_id = 'sv10pt5';`, confirmado executado ("Success. No rows returned") — a tabela está novamente vazia (0 registros).

**Decisão revisada sobre como popular esta tabela, corrigida dentro do próprio raciocínio desta revisão (auto-correção, não um erro de execução)**: a primeira proposta foi popular a Seed `910` manualmente, com os Sets que sabidamente têm equivalência oficial (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`) e deixar `ME0` deliberadamente sem mapeamento, permanente. Antes de escrever essa Seed, a proposta foi revisada: *"Como `ME0` representa as cartas promocionais da expansão Megaevolution, é bem provável que ela tenha sim um mapeamento oficial na TCGdex (um Set promocional específico). O que não devemos fazer é assumir que seja `sv10pt5` sem validar."* Decisão final: **a Query `910` fica adiada** (não descartada como em `card_external_reference` — aqui a expectativa é que a maioria dos Sets, incluindo possivelmente `ME0`, tenha sim uma correspondência real) até que a Edge Function consiga descobrir os `external_set_id` reais consultando a própria TCGdex — a Seed só será escrita depois, com dados confirmados pela API, nunca com suposições. Apenas a Query `240` e a `241` foram executadas nesta revisão — `910` (adiada) e `991` (validação) ainda **não foram executadas**.

**Atualização: Query `910` CONFIRMADA EXECUTADA (parcial) nesta revisão**, depois que os `external_set_id` reais foram descobertos via chamada real à TCGdex (`scripts/discover-tcgdex-sets.ts`, ver `06-pipeline-importacao.md`) — ver seção "Query 910", abaixo, para o detalhamento completo.

## Decisão de Modelagem

`card_set_external_reference` relaciona `card_set` (interno) a `asset_source` (externo) via `card_set_id`+`asset_source_id`, com o identificador do conjunto na fonte externa (`external_set_id`, obrigatório) e a URL do registro na fonte (`source_url`, opcional). **Deliberadamente não é uma cópia 1:1 de `card_external_reference`** — duas colunas da tabela de cartas foram descartadas por não fazerem sentido no nível de Set: `external_card_id` (óbvio — não existe carta aqui) e, mais relevante, `image_source_url`: o Pipeline Automático de Imagens baixa imagens de **cartas**, não de Sets: o logotipo/símbolo de um Set (já coberto por `card_set.logo_url`/`symbol_url` — não confundir) não faz parte deste pipeline. Incluir `image_source_url` aqui seria copiar estrutura sem copiar significado. Chaves únicas seguem a mesma filosofia de `card_external_reference`: um Set só pode ter uma referência por fonte (`card_set_id`+`asset_source_id`), e um identificador externo só pode apontar para um Set dentro da mesma fonte (`asset_source_id`+`external_set_id`) — mesmo padrão, entidade diferente, não uma generalização única para as duas.

## Modelo Físico — Versão 1.0 (CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.card_set_external_reference (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    card_set_id UUID NOT NULL,
    asset_source_id UUID NOT NULL,
    external_set_id TEXT NOT NULL,
    source_url TEXT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT card_set_external_reference_pkey
        PRIMARY KEY (id),
    CONSTRAINT fk_card_set_external_reference_card_set
        FOREIGN KEY (card_set_id)
        REFERENCES public.card_set (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_card_set_external_reference_asset_source
        FOREIGN KEY (asset_source_id)
        REFERENCES public.asset_source (id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_card_set_external_reference_card_set_source
        UNIQUE (card_set_id, asset_source_id),
    CONSTRAINT uq_card_set_external_reference_source_external
        UNIQUE (asset_source_id, external_set_id),
    CONSTRAINT ck_card_set_external_reference_external_set_id
        CHECK (BTRIM(external_set_id) <> ''),
    CONSTRAINT ck_card_set_external_reference_source_url
        CHECK (
            source_url IS NULL
            OR (
                BTRIM(source_url) <> ''
                AND source_url ~ '^https://'
            )
        ),
    CONSTRAINT ck_card_set_external_reference_metadata
        CHECK (JSONB_TYPEOF(metadata) = 'object')
);

CREATE INDEX ix_card_set_external_reference_card_set
    ON public.card_set_external_reference (card_set_id);
CREATE INDEX ix_card_set_external_reference_asset_source
    ON public.card_set_external_reference (asset_source_id);
CREATE INDEX ix_card_set_external_reference_active
    ON public.card_set_external_reference (asset_source_id, is_active);

ALTER TABLE public.card_set_external_reference ENABLE ROW LEVEL SECURITY;
```

Regras de negócio: FK para `card_set` (`ON DELETE CASCADE`) e para `asset_source` (`ON DELETE RESTRICT`); unicidade dupla (`card_set_id`+`asset_source_id` e `asset_source_id`+`external_set_id`); `external_set_id` obrigatório e não vazio; `source_url`, quando presente, deve começar com `https://`; `metadata` deve ser sempre um objeto JSON válido; RLS habilitado. Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/240_create_card_set_external_reference.sql`.

## Query 241 — Card Set External Reference Triggers (CONFIRMADA EXECUTADA)

Mesmo padrão já estabelecido para as demais camadas de referência externa: `normalize_card_set_external_reference()` (apara `external_set_id`, converte `source_url` vazio em `NULL`, garante `metadata` nunca nulo), `touch_card_set_external_reference_updated_at()` (padrão), e `govern_card_set_external_reference()` — proteção de identidade via `RAISE EXCEPTION`, cobrindo não só `id`/`card_set_id`/`asset_source_id` (mesmo padrão de `card_external_reference`) mas também `external_set_id` e `created_at` como imutáveis após criados:

```sql
CREATE OR REPLACE FUNCTION public.normalize_card_set_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.external_set_id := BTRIM(NEW.external_set_id);
    IF NEW.source_url IS NOT NULL THEN
        NEW.source_url := NULLIF(BTRIM(NEW.source_url), '');
    END IF;
    NEW.metadata := COALESCE(NEW.metadata, '{}'::JSONB);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_card_set_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'CARD_SET_EXTERNAL_REFERENCE_ID_IMMUTABLE';
    END IF;
    IF NEW.card_set_id IS DISTINCT FROM OLD.card_set_id THEN
        RAISE EXCEPTION 'CARD_SET_EXTERNAL_REFERENCE_CARD_SET_IMMUTABLE';
    END IF;
    IF NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id THEN
        RAISE EXCEPTION 'CARD_SET_EXTERNAL_REFERENCE_ASSET_SOURCE_IMMUTABLE';
    END IF;
    IF NEW.external_set_id IS DISTINCT FROM OLD.external_set_id THEN
        RAISE EXCEPTION 'CARD_SET_EXTERNAL_REFERENCE_EXTERNAL_SET_ID_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'CARD_SET_EXTERNAL_REFERENCE_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_card_set_external_reference_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_normalize_card_set_external_reference
    BEFORE INSERT OR UPDATE ON public.card_set_external_reference
    FOR EACH ROW EXECUTE FUNCTION public.normalize_card_set_external_reference();

CREATE TRIGGER trg_020_govern_card_set_external_reference
    BEFORE UPDATE ON public.card_set_external_reference
    FOR EACH ROW EXECUTE FUNCTION public.govern_card_set_external_reference();

CREATE TRIGGER trg_030_touch_card_set_external_reference_updated_at
    BEFORE UPDATE ON public.card_set_external_reference
    FOR EACH ROW EXECUTE FUNCTION public.touch_card_set_external_reference_updated_at();
```

Confirmado executado por Fabrício ("Success. No rows returned"). Arquivo escrito em `database/schema/241_card_set_external_reference_triggers.sql`.

> **Diário Técnico — Query 241 — Card Set External Reference Triggers**
> **Objetivo**: adicionar normalização, `updated_at` automático e proteção de identidade a `card_set_external_reference`, mesmo padrão das demais camadas de referência externa.
> **Critério de aceite**: três funções e três triggers criados, sem alterar dados existentes.
> **Resultado**: ✅ Concluído.
> **Pendências descobertas**: um mapeamento de teste incorreto (`ME0`→`sv10pt5`) foi inserido durante a validação e precisou ser removido — ver "Status", acima, para o episódio completo. Query `910` (Seed) adiada até a Edge Function conseguir descobrir `external_set_id` reais via a própria TCGdex; Query `991` (Validação) ainda não escrita, mas com critérios já decididos: sem mapeamentos duplicados; todo `card_set_external_reference` aponta para `card_set` e `asset_source` válidos; nenhum `card_set` do tipo `REGULAR` ou `SPECIAL` sem mapeamento ativo; `PROMO` pode ficar sem mapeamento.

## Query 910 — Seed Card Set External Reference (CONFIRMADA EXECUTADA — PARCIAL)

Executada depois que os `external_set_id` reais foram descobertos por uma chamada real à TCGdex (`scripts/discover-tcgdex-sets.ts`, execução confirmada — ver `06-pipeline-importacao.md`, Sprint B2.5A/B3). Insere apenas os Sets com correspondência oficial já confirmada (`ME1`–`ME5`); usa `JOIN` (não `LEFT JOIN`) contra `card_set`, portanto um código sem `card_set` correspondente é simplesmente ignorado, sem erro — comportamento que se revelou útil na prática (ver abaixo). Idempotente via `ON CONFLICT (card_set_id, asset_source_id) DO UPDATE`.

```sql
INSERT INTO public.card_set_external_reference (
    card_set_id,
    asset_source_id,
    external_set_id,
    source_url
)
SELECT
    cs.id,
    src.id,
    m.external_set_id,
    'https://api.tcgdex.net/v2/en/sets/' || m.external_set_id
FROM (
    VALUES
        ('ME1', 'me01'),
        ('ME2', 'me02'),
        ('ME2.5', 'me02.5'),
        ('ME3', 'me03'),
        ('ME4', 'me04'),
        ('ME5', 'me05')
) AS m(card_set_code, external_set_id)
JOIN public.card_set cs
    ON cs.code = m.card_set_code
JOIN public.asset_source src
    ON src.code = 'TCGDEX'
ON CONFLICT (card_set_id, asset_source_id)
DO UPDATE SET
    external_set_id = EXCLUDED.external_set_id,
    source_url = EXCLUDED.source_url,
    updated_at = NOW();
```

**`ME0` deliberadamente excluído desta Seed** — reafirmado explicitamente nesta revisão: *"Continuo recomendando não inseri-lo agora. Nós sabemos que existe o Set `mee`, mas ainda não sabemos se ele representa exatamente a coleção interna `ME0`. É uma decisão de domínio, não de tecnologia."* Mesma pendência já registrada em `06-pipeline-importacao.md` (Sprint B2.5A, revisão `0.17`), cross-referenciada com o "escopo `ENERGY`".

**Execução real, confirmada por consulta de validação** (`SELECT cs.code, cser.external_set_id FROM public.card_set_external_reference cser JOIN public.card_set cs ON cs.id = cser.card_set_id ORDER BY cs.release_order`) — resultado real:

| `code` | `external_set_id` |
|--------|--------------------|
| `ME1` | `me01` |
| `ME2` | `me02` |
| `ME2.5` | `me02.5` |
| `ME3` | `me03` |
| `ME4` | `me04` |

**`ME5` não foi inserido — investigado e explicado, não é um bug.** Diagnóstico direto, sem adivinhar: consulta real a `card_set` (`SELECT code, name, release_order FROM public.card_set ORDER BY release_order`) confirmou que a tabela física hoje contém apenas `ME0` ("ME Black Star Promos"), `ME1` ("Megaevolução"), `ME2` ("Fogo Fantasmagórico"), `ME2.5` ("Heróis Excelsos"), `ME3` ("Equilíbrio Perfeito") e `ME4` ("Caos Ascendente") — **`ME5` ainda não existe como `card_set` real no banco**, apenas como dado de planejamento (nomes em inglês aprendidos na revisão `0.16` de `06-pipeline-importacao.md`, nunca confirmado como cadastrado). O `JOIN` da Query `910` simplesmente não encontrou correspondência para `ME5` e seguiu adiante sem erro — comportamento correto, não uma falha da Seed. Reexecutar esta Query (idempotente) depois que `ME5` for cadastrado como `card_set` populará o mapeamento automaticamente, sem alterações no SQL.

Arquivo escrito em `database/seeds/910_seed_card_set_external_reference.sql`.

> **Diário Técnico — Query 910 — Seed Card Set External Reference**
> **Objetivo**: popular `card_set_external_reference` com os `external_set_id` reais da TCGdex, descobertos por chamada real à API — nunca por suposição.
> **Critério de aceite**: `ME1`–`ME4` (e `ME5`, se já cadastrado) com `external_set_id` gravado e confirmado por consulta; `ME0` deliberadamente ausente até a decisão de negócio.
> **Resultado**: ✅ Concluído (parcial, por design). `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` confirmados via consulta real. `ME5` ausente porque `card_set.code = 'ME5'` ainda não existe no banco — não é uma falha, confirmado por investigação direta.
> **Pendências descobertas**: (1) decisão de negócio sobre `ME0`↔`mee` continua aberta, não resolvida aqui; (2) `card_set.code = 'ME5'` ainda não cadastrado — quando for, reexecutar esta Query (idempotente) resolve automaticamente; (3) Query `991` (Validação) continua não escrita.

**Atualização posterior (Migration `251`, ver seção "Card Set", acima): a pendência (1) foi resolvida.** `ME0` (interno) e `mee` (TCGdex) foram confirmados por Fabrício como coleções diferentes e sem relação — `ME0` (cartas promocionais de Mega Evolução) não é `mee` (cartas de Energia de Mega Evolução). `ME0` foi removida de `card_set` por completo, não apenas deixada sem mapeamento. Ver "Migration `251` — Remoção de `ME0`" para o histórico completo.

**Atualização posterior (2026-07-24, ver seção "Card Set", acima, "Investigação de acompanhamento"): identificador oficial real encontrado — `MEP` ("Mega Evolution Black Star Promos", TCGdex `mep`), não `mee`.** Recadastro planejado, ainda NÃO executado nesta revisão.

## Sequência

```text
240 - Create Card Set External Reference (CONFIRMADA EXECUTADA — database/schema/240_create_card_set_external_reference.sql)
241 - Card Set External Reference Triggers (CONFIRMADA EXECUTADA — database/schema/241_card_set_external_reference_triggers.sql)
910 - Seed Card Set External Reference   (CONFIRMADA EXECUTADA — PARCIAL — database/seeds/910_seed_card_set_external_reference.sql; ME1/ME2/ME2.5/ME3/ME4 mapeados; ME0 removida de card_set — Migration 251, decisão de negócio resolvida: sem relação com mee; ME5 aguarda ser cadastrado como card_set)
268 - Create Card Set External Reference MEP (CONFIRMADA EXECUTADA — database/migrations/268_create_card_set_external_reference_mep.sql; MEP mapeado à TCGdex, external_set_id = 'mep'; ver seção "Set", "Migration 265-268")
269 - Fix Card Set External Reference MEP Metadata (CONFIRMADA EXECUTADA — database/migrations/269_fix_card_set_external_reference_mep_metadata.sql; metadata de MEP zerada, ver seção "Set", "Migration 269-271")
270 - Create Card Set External Reference MEE (CONFIRMADA EXECUTADA — database/migrations/270_create_card_set_external_reference_mee.sql; MEE mapeado à TCGdex, external_set_id = 'mee', metadata = {})
991 - Validate Card Set External Reference (planejada, NÃO executada — critérios já decididos, ver Diário Técnico da Query 241, acima)
```

---

# Collection Item (Item da Coleção)

*Documentação pendente.*

---

# Collection (Coleção) / Collection Entry (Entrada da Coleção)

*Documentação pendente.*

---

# User Profile (Perfil de Usuário) / Reserved Username

## Status

**Camada Identidade e Acesso criada, semeada e homologada nesta revisão — Incremento 1 ("Meu Perfil") do módulo, `1000`–`1040`/`1710`/`1800`–`1840` CONFIRMADOS EXECUTADOS.** Primeira entidade fora do Catálogo Editorial, motivada pela decisão de arquitetura frontend (ADR-019) e formalizada em ADR-020 (User Profile and Username Identity Model). Introduz o Modelo Modular de Numeração (STD-001, Seção 10): esta é a primeira entidade do milhar `1000–1999`.

## Decisão de Modelagem

`user_profile` separa identidade de negócio (nome, avatar, username) da autenticação (`auth.users`, gerida pelo Supabase Auth) — ver ADR-020. Relação 1:1 via `id` compartilhado. `username` é a identidade pública, única e estável do usuário (imutável pelo próprio usuário); `display_name` é livremente editável. `reserved_username` é uma tabela de apoio (não uma entidade de domínio), consultada apenas por functions `SECURITY DEFINER`, sem acesso direto via API.

## Modelo Físico — `user_profile` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.user_profile (
    id            UUID PRIMARY KEY
                  REFERENCES auth.users(id)
                  ON DELETE CASCADE,
    username      TEXT NOT NULL,
    display_name  TEXT NOT NULL,
    avatar_path   TEXT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT user_profile_username_unique
        UNIQUE (username),
    CONSTRAINT user_profile_username_format
        CHECK (username ~ '^[a-z0-9_]{3,20}$'),
    CONSTRAINT user_profile_display_name_length
        CHECK (char_length(trim(display_name)) BETWEEN 1 AND 60)
);

ALTER TABLE public.user_profile
    ENABLE ROW LEVEL SECURITY;
```

Regras de negócio: `username` minúsculo, 3–20 caracteres (letras, números, underscore), único, imutável após criado (garantido por trigger, não pela tabela em si); `display_name` sempre gravado já com `trim`; `avatar_path` guarda o caminho relativo dentro do bucket `avatars` (Query `1040`), não a URL pública completa (derivada em runtime); RLS habilitado. Confirmado executado por Fabrício (estrutura e colunas conferidas via `information_schema`). Arquivo em `database/schema/1000_create_user_profile_table.sql`.

## Query `1001` — Create User Profile Trigger (CONFIRMADO EXECUTADO)

Mantém `updated_at` atualizado, reaproveitando `public.set_updated_at()` — mesmo padrão de toda a base. Confirmado via `information_schema.triggers`. Arquivo em `database/schema/1001_create_user_profile_trigger.sql`.

## Query `1002` — Create User Profile Invariants Trigger (CONFIRMADO EXECUTADO)

Function `enforce_user_profile_invariants()` + trigger `BEFORE INSERT OR UPDATE`: normaliza `display_name` (`trim`) incondicionalmente e bloqueia qualquer alteração de `username` (`RAISE EXCEPTION`), sem válvula de exceção — imutabilidade total nesta fase, por decisão explícita de Fabrício. Uma futura correção administrativa será modelada apenas quando existir papel administrativo aprovado (ver ADR-020), sem reabrir este trigger. Confirmado via `information_schema.triggers` (três linhas: `enforce_invariants` em INSERT e UPDATE, `set_updated_at` em UPDATE). Arquivo em `database/schema/1002_create_user_profile_invariants_trigger.sql`.

## Query `1003` — Create User Profile RLS Policies (CONFIRMADO EXECUTADO)

`user_profile_select_own`/`user_profile_update_own`, ambas restritas a `auth.uid() = id`. Sem política de `INSERT`/`DELETE` — a única via de criação é o trigger da Query `1020` (roda como dono da function, ignora RLS). Confirmado via `pg_policies`. Arquivo em `database/schema/1003_create_user_profile_rls_policies.sql`.

## Modelo Físico — `reserved_username` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.reserved_username (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username   TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.reserved_username ENABLE ROW LEVEL SECURITY;
```

Tabela de apoio, não uma entidade de domínio — sem política de RLS para `anon`/`authenticated` (só as functions `SECURITY DEFINER` a leem). Confirmado executado. Arquivo em `database/schema/1010_create_reserved_username_table.sql`; trigger de `updated_at` em `1011` (mesmo padrão, confirmado via `information_schema.triggers`, arquivo `database/schema/1011_create_reserved_username_trigger.sql`).

## Query `1710` — Seed Reserved Username (v1.1, CONFIRMADA EXECUTADA)

Carga idempotente (`ON CONFLICT (username) DO NOTHING`) com 50 termos reservados (`admin`, `suporte`, `sistema`, `perfil`, `me`, `about`, entre outros) — nenhum usuário pode reivindicá-los como `username`. v1.0 tinha 48 termos; v1.1 acrescenta `me` (rotas futuras como `/me`, `/api/me`) e `about` (rota institucional comum), sugeridos por Fabrício após a execução original e já aplicados incrementalmente ao banco antes desta consolidação. Confirmado: `count(*) = 48` na execução original, lista conferida termo a termo contra a intenção. Arquivo em `database/seeds/1710_seed_reserved_username.sql`.

## Query `1020` — Create `handle_new_user()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, trigger `AFTER INSERT ON auth.users`: popula `user_profile` a partir de `raw_user_meta_data` (`username`/`display_name` enviados pelo formulário via `options.data` do `signUp()`), tratado como dado não confiável — normalizado e revalidado no próprio trigger (formato, reservados, presença). Qualquer falha cancela a transação inteira do `INSERT` em `auth.users`: a partir desta Query, nunca existe usuário sem perfil. `EXECUTE` revogado de `PUBLIC` — só o próprio trigger invoca. Confirmado: `prosecdef = true`, trigger correto em `auth.users`, `anon`/`authenticated` sem `EXECUTE`. Arquivo em `database/schema/1020_create_handle_new_user_function.sql`.

**Limitação de MVP documentada em ADR-020**: esta function assume que `username` sempre vem em `raw_user_meta_data`, o que só é verdade no cadastro por e-mail/senha controlado pelo próprio formulário. Login social (OAuth) não popula esse campo — precisará de um fluxo de onboarding pós-login, não implementado nesta fase.

**Achado real desta revisão**: a conta de teste de Fabrício (criada antes desta Query existir) ficou sem `user_profile` — detectado pela checagem de inconsistência da Query `1800`. Decisão tomada: excluir a conta de teste via painel do Supabase (Authentication → Users) e recriá-la pelo fluxo real assim que o frontend estiver pronto, em vez de criar um perfil manualmente ou deixar a conta órfã.

## Query `1030` — Create `username_available()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, retorno estritamente `BOOLEAN`, chamável por `anon`/`authenticated` (checagem de disponibilidade durante o cadastro, antes de existir sessão). Documentada explicitamente como antecipação de UX sujeita a condição de corrida — a autoridade final continua sendo o `UNIQUE` de `user_profile`, verificado no `INSERT` real da Query `1020`. Testado com três casos reais: `'admin'` → `false` (reservado), `'ab'` → `false` (formato inválido), `'fabricio_teste'` → `true` (disponível). Arquivo em `database/schema/1030_create_username_available_function.sql`.

## Query `1040` — Create bucket `avatars` (CONFIRMADO EXECUTADO)

Bucket Supabase Storage dedicado a avatares: leitura pública (única exceção aprovada), escrita restrita à própria pasta do usuário (`<uid>/<arquivo>`), MIME `image/png`/`image/jpeg`/`image/webp`, limite de 2 MB. Toda política em `storage.objects` filtra `bucket_id = 'avatars'` explicitamente (tabela compartilhada entre todos os buckets do projeto). Confirmado: bucket e as quatro políticas (`avatars_public_read`/`avatars_insert_own_folder`/`avatars_update_own_folder`/`avatars_delete_own_folder`) conferidos via `storage.buckets`/`pg_policies`. Arquivo em `database/schema/1040_create_avatars_bucket.sql`.

## Query `1004` — Grant User Profile Privileges (CONFIRMADO EXECUTADO)

**Bug real encontrado durante a integração do frontend (2026-07-26)**: `/perfil` retornava `permission denied for table user_profile` (`code 42501`) mesmo com as políticas de RLS da Query `1003` corretas. Causa: RLS restringe linhas, mas pressupõe que o privilégio de tabela já exista — o `GRANT` de base para o role `authenticated` nunca tinha sido emitido (mesma classe de lacuna já vista antes neste projeto com `service_role`/Edge Functions, ver revisão `0.69`, migration `272`). Corrigido com `GRANT SELECT, UPDATE ON public.user_profile TO authenticated;`, espelhando exatamente as duas políticas de RLS existentes — nenhum privilégio concedido a `anon` (perfil não é público neste incremento) nem `INSERT` (a criação da linha continua exclusiva de `handle_new_user()`, que roda como `SECURITY DEFINER`). Confirmado via `information_schema.role_table_grants`: `authenticated` com `SELECT`/`UPDATE`, `anon` sem nenhum dos dois. Arquivo em `database/schema/1004_grant_user_profile_privileges.sql`.

## Sequência

```text
1000 - Create User Profile table                       (CONFIRMADO EXECUTADO — database/schema/1000_create_user_profile_table.sql)
1001 - Create User Profile trigger                      (CONFIRMADO EXECUTADO — database/schema/1001_create_user_profile_trigger.sql)
1002 - Create User Profile invariants trigger           (CONFIRMADO EXECUTADO — database/schema/1002_create_user_profile_invariants_trigger.sql)
1003 - Create User Profile RLS policies                 (CONFIRMADO EXECUTADO — database/schema/1003_create_user_profile_rls_policies.sql)
1004 - Grant User Profile privileges                    (CONFIRMADO EXECUTADO — database/schema/1004_grant_user_profile_privileges.sql)
1010 - Create Reserved Username table                   (CONFIRMADO EXECUTADO — database/schema/1010_create_reserved_username_table.sql)
1011 - Create Reserved Username trigger                 (CONFIRMADO EXECUTADO — database/schema/1011_create_reserved_username_trigger.sql)
1020 - Create handle_new_user function and trigger      (CONFIRMADO EXECUTADO — database/schema/1020_create_handle_new_user_function.sql)
1030 - Create username_available function                (CONFIRMADO EXECUTADO — database/schema/1030_create_username_available_function.sql)
1040 - Create avatars bucket and storage policies         (CONFIRMADO EXECUTADO — database/schema/1040_create_avatars_bucket.sql)
1710 - Seed Reserved Username (v1.1, 50 termos)           (CONFIRMADA EXECUTADA — database/seeds/1710_seed_reserved_username.sql)
1800 - Validate User Profile                              (EXECUTADA — database/validations/1800_validate_user_profile.sql)
1810 - Validate Reserved Username                         (EXECUTADA — database/validations/1810_validate_reserved_username.sql)
1820 - Validate handle_new_user                           (EXECUTADA — database/validations/1820_validate_handle_new_user.sql)
1830 - Validate username_available                        (EXECUTADA — database/validations/1830_validate_username_available.sql)
1840 - Validate avatars bucket                            (EXECUTADA — database/validations/1840_validate_avatars_bucket.sql)
```

## Pendências / Próximos Passos

Frontend do Incremento 1 concluído e validado por Fabrício (2026-07-26): cadastro com `username`/`display_name`, tela `/perfil` real (avatar, nome de exibição editável, username bloqueado) — cadastro completo, carregamento de `/perfil`, edição de `display_name` e troca de avatar todos confirmados em produção. Incremento 2 (Administração de Usuários) iniciado — ver seção própria abaixo.

---

# Administração de Usuários

## Status

**Incremento 2, Fases 1–3 (fundação, leitura segura, interface) CONFIRMADAS EXECUTADAS e validadas em produção (2026-07-26).** Segunda entidade do módulo Identidade e Acesso (milhar `1000`–`1999`), formalizada em ADR-021 (Administrative Role Model). Fase 4 (correção administrativa de `username`) deliberadamente fora deste incremento — tratada como incremento futuro separado.

## Decisão de Modelagem

Papel administrativo modelado como presença de linha em `admin_user`, entidade separada de `user_profile` — nunca um atributo booleano nela, para não expor uma coluna autopromovível pelas políticas de RLS de `UPDATE` já existentes. Um único papel (`admin`), sem sistema genérico de papéis/permissões. Todo acesso administrativo passa por functions `SECURITY DEFINER`; `admin_user` e `admin_action_log` têm RLS habilitado e zero políticas — nenhum acesso direto via API, nem para o próprio admin. Ver ADR-021 para o raciocínio completo e as alternativas rejeitadas.

## Modelo Físico — `admin_user` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.admin_user (
    id           UUID PRIMARY KEY
                 REFERENCES auth.users(id)
                 ON DELETE CASCADE,
    granted_by   UUID NULL
                 REFERENCES auth.users(id)
                 ON DELETE SET NULL,
    granted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_user ENABLE ROW LEVEL SECURITY;
```

Sem `updated_at`/trigger: tabela de presença (INSERT/DELETE), não um registro editável. `granted_by` anulável com `ON DELETE SET NULL` — a exclusão futura de quem concedeu o papel nunca invalida a concessão em si. Confirmado via `information_schema`/`pg_tables`. Arquivo em `database/schema/1050_create_admin_user_table.sql`.

## Modelo Físico — `admin_action_log` (Versão 1.0, CONFIRMADO EXECUTADO)

```sql
CREATE TABLE public.admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    target_user_id   UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    action           TEXT NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT admin_action_log_action_valid CHECK (action IN ('GRANT_ADMIN', 'REVOKE_ADMIN'))
);

ALTER TABLE public.admin_action_log ENABLE ROW LEVEL SECURITY;
```

FKs anuláveis com `ON DELETE SET NULL` (não `CASCADE`): o histórico administrativo sobrevive à exclusão futura de qualquer usuário envolvido — `metadata` grava um retrato (username/e-mail de ator e alvo) capturado no momento da ação, preservando contexto legível mesmo depois que a referência direta vira `NULL`. Ajuste pedido por Fabrício antes da implementação. Confirmado via `pg_constraint`/`pg_tables`. Arquivo em `database/schema/1070_create_admin_action_log_table.sql`.

## Query `1060` — Create `is_admin()` (CONFIRMADO EXECUTADO)

Function `SECURITY DEFINER`, `SET search_path = ''`, **sem parâmetro** — verifica somente `auth.uid()`, o usuário da própria sessão. Ajuste pedido por Fabrício antes da implementação: a proposta original aceitava um `p_user_id` arbitrário, permitindo que qualquer usuário consultasse o status administrativo de outro UUID; rejeitado. `EXECUTE` concedido apenas a `authenticated`. Confirmado: `prosecdef = true`, `pronargs = 0`, grants corretos. Testado via SQL Editor retornando `false` (esperado — sem sessão real, `auth.uid()` é `NULL` nesse contexto). Arquivo em `database/schema/1060_create_is_admin_function.sql`.

## Query `1061` — Create `admin_list_users()` (CONFIRMADO EXECUTADO, v1.1)

Function `SECURITY DEFINER` que lista usuários para fins administrativos — única via de leitura de e-mail (`auth.users`) para esse propósito; o frontend nunca consulta `auth.users` diretamente. Paginada desde a origem (`limit`/`offset`, teto de 100 controlado no servidor), mesmo sem busca/filtros nesta fase — ajuste pedido por Fabrício antes da implementação ("uma listagem ilimitada não é adequada à evolução comercial do sistema"). Retorna `total_count` via `count(*) OVER()` em cada linha, evitando uma segunda chamada para montar a paginação. Campos: `id`, `username`, `display_name`, `avatar_path`, `email`, `created_at`, `is_admin`.

**Bug real encontrado na integração da Fase 3**: `structure of query does not match function result type` (erro `42804`) — `auth.users.email` é `character varying(255)`, não `TEXT`; o `RETURN QUERY` exige tipo exato contra o `RETURNS TABLE` declarado. Corrigido com `au.email::text` (v1.1). Confirmado funcionando a partir do app real, retornando a lista corretamente. Arquivo em `database/schema/1061_create_admin_list_users_function.sql`.

## Query `1062` — Create `admin_grant_admin()` / `admin_revoke_admin()` (CONFIRMADO EXECUTADO)

Functions `SECURITY DEFINER` para conceder/revogar o papel administrativo, ambas exigindo `is_admin()` do chamador. Ambas adquirem a mesma trava consultiva de transação (`pg_advisory_xact_lock`), serializando concessões/revogações concorrentes — ajuste pedido por Fabrício antes da implementação, para que duas revogações simultâneas não possam remover o último administrador ao mesmo tempo. `admin_revoke_admin()` bloqueia explicitamente essa remoção (`RAISE EXCEPTION` se restaria zero administradores). Ambas gravam em `admin_action_log` com o retrato de `metadata`. Confirmado: `prosecdef = true`, `pronargs = 1`, grants corretos. Arquivo em `database/schema/1062_create_admin_grant_revoke_functions.sql`.

## Bootstrap administrativo — operação única (NÃO é uma migration replicável)

Como `admin_grant_admin()` exige que o chamador já seja administrador, a primeira concessão não pode passar pela function — é um `INSERT` direto, rodado uma única vez via SQL Editor, concedendo o papel a Fabrício (identificado por e-mail, evitando copiar/colar UUID manualmente) e registrando a ação em `admin_action_log` com uma nota explícita de que é bootstrap. Por decisão de Fabrício, esta operação **não** foi numerada na sequência estrutural nem gravada em `database/schema/` — é específica deste ambiente (hardcoda um e-mail real) e não deve ser reexecutada em outro projeto/ambiente sem ajuste.

```sql
INSERT INTO public.admin_user (id, granted_by)
SELECT id, NULL FROM auth.users WHERE email = 'fabricio.souza.sales@hotmail.com';

INSERT INTO public.admin_action_log (actor_id, target_user_id, action, metadata)
SELECT id, id, 'GRANT_ADMIN',
    jsonb_build_object('note', 'bootstrap inicial — primeiro administrador, concedido manualmente via SQL Editor')
FROM auth.users WHERE email = 'fabricio.souza.sales@hotmail.com';
```

Confirmado executado — Fabrício listado como administrador em `admin_user`, com o registro correspondente em `admin_action_log`.

## Sequência

```text
1050 - Create Admin User table                          (CONFIRMADO EXECUTADO — database/schema/1050_create_admin_user_table.sql)
1060 - Create is_admin() function                        (CONFIRMADO EXECUTADO — database/schema/1060_create_is_admin_function.sql)
1061 - Create admin_list_users() function (v1.1)          (CONFIRMADO EXECUTADO — database/schema/1061_create_admin_list_users_function.sql)
1062 - Create admin_grant_admin()/admin_revoke_admin()     (CONFIRMADO EXECUTADO — database/schema/1062_create_admin_grant_revoke_functions.sql)
1070 - Create Admin Action Log table                      (CONFIRMADO EXECUTADO — database/schema/1070_create_admin_action_log_table.sql)
      - Bootstrap administrativo                          (CONFIRMADO EXECUTADO — operação única, não numerada, não versionada em database/schema/)
1850 - Validate Admin User                                (EXECUTADA — database/validations/1850_validate_admin_user.sql)
1860 - Validate Admin Functions                           (EXECUTADA — database/validations/1860_validate_admin_functions.sql)
1870 - Validate Admin Action Log                          (EXECUTADA — database/validations/1870_validate_admin_action_log.sql)
```

## Frontend (Fase 3, CONFIRMADO EXECUTADO)

Rota `/usuarios` (já existia como placeholder desde a fundação do frontend, agora real): Server Component que redireciona para `/login` sem sessão, mostra "Acesso restrito a administradores" para não-admin, erro dedicado se `admin_list_users()` falhar, "Nenhum usuário encontrado" no caso vazio, e a tabela paginada nos demais casos. Item "Usuários" do menu (`nav-config.ts`) marcado `adminOnly` — some do menu para quem não é admin (checagem de UX; a autorização real está nas functions do banco, não no frontend). `AppShell` busca `is_admin()` uma única vez e repassa a `Sidebar`/`Header`/`MobileNav`. Tabela (`components/usuarios/users-table.tsx`) mostra username/nome/e-mail/data/papel e um botão conceder/revogar por linha, via Server Actions (`app/usuarios/actions.ts`) com tradução de erros dedicada (`lib/supabase/admin-errors.ts`).

## Pendências / Próximos Passos

Fase 4 (correção administrativa de `username`) deliberadamente fora deste incremento — mecanismo desenhado em nível conceitual no ADR-021 (flag local à transação sinalizando ao trigger `enforce_user_profile_invariants()`), implementação adiada para um incremento futuro. Testabilidade de `admin_grant_admin()`/`admin_revoke_admin()` com um segundo usuário real ainda pendente (Fabrício é hoje o único usuário/administrador cadastrado). Visualização do `admin_action_log` pela interface não faz parte deste incremento — o dado já é gravado, sem tela própria ainda.

---

# Autorização do Catálogo Editorial

## Status

**CONFIRMADO EXECUTADO (2026-07-26).** Formaliza `ADR-022` (Catalog Editorial Admin-Only Access): todo o módulo Catálogo Editorial — menu, rota e dado — passa a ser exclusivo de administradores. Motivado pela retomada do frontend do módulo (tela Visão Geral) e pela descoberta, durante a verificação que antecedeu o desenho da tela, de que as 17 tabelas do Catálogo Editorial já tinham Row Level Security habilitado sem nenhuma política — ou seja, ninguém (nem administrador) conseguia ler esses dados pela API. Este incremento torna esse fechamento uma decisão explícita, seguindo exatamente o mesmo rigor já aplicado em Administração de Usuários (acima): leitura mínima necessária, escrita sensível sempre por função vetada.

## Leitura — políticas `catalog_admin_select` (Query `274`, CONFIRMADO EXECUTADO)

Política `SELECT` idêntica em dez tabelas — as únicas efetivamente consultadas pela Visão Geral aprovada: `game`, `expansion`, `card_set`, `card`, `card_variant`, `card_asset`, `language`, `rarity`, `card_category`, `asset_import_run`.

```sql
CREATE POLICY catalog_admin_select ON public.<tabela>
    FOR SELECT USING (is_admin());
GRANT SELECT ON public.<tabela> TO authenticated;
```

Reaproveita `is_admin()` (`ADR-021`). Sem o `GRANT` de nível de tabela do PostgreSQL, a política nunca chega a ser avaliada — mesmo gap já visto nas Queries `250`/`253`/`254`/`272`. As sete tabelas do Catálogo Editorial ainda não consultadas por nenhuma tela real (`card_variant_type`, `card_asset_type`, `storage_bucket`, `asset_source`, `card_external_reference`, `card_set_external_reference`, `asset_import_failure`) permanecem sem nenhuma política — fechadas até que uma tela real precise delas, por decisão explícita (`AP-004`, Simplicidade Inicial), não por esquecimento. Confirmado via `pg_policies`/`information_schema.role_table_grants`. Arquivo em `database/migrations/274_add_admin_only_select_policies_to_catalog_tables.sql`.

## Escrita da logo — `admin_set_card_set_logo()` (Query `275`, CONFIRMADO EXECUTADO)

Nenhuma tabela do Catálogo Editorial recebeu política de `INSERT`/`UPDATE`/`DELETE` neste incremento. A escrita de `card_set.logo_storage_path` passa exclusivamente por uma função `SECURITY DEFINER`, mesmo padrão já usado em `admin_grant_admin()`/`admin_revoke_admin()` (`ADR-021`): restrita a administradores, restrita a este único campo, e que nunca falha silenciosamente — confirma via `GET DIAGNOSTICS ... ROW_COUNT` que exatamente uma linha foi alterada, levantando exceção se o Card Set informado não existir.

```sql
CREATE OR REPLACE FUNCTION public.admin_set_card_set_logo(
    p_card_set_id UUID,
    p_logo_storage_path TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rows_updated INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_SET_CARD_SET_LOGO_FORBIDDEN: apenas administradores podem alterar a logo de um Card Set.';
    END IF;

    IF p_logo_storage_path IS NOT NULL
       AND p_logo_storage_path ~* '^[a-z][a-z0-9+.-]*://' THEN
        RAISE EXCEPTION 'ADMIN_SET_CARD_SET_LOGO_INVALID_PATH: logo_storage_path deve ser um caminho relativo, nunca uma URL absoluta.';
    END IF;

    UPDATE public.card_set
        SET logo_storage_path = p_logo_storage_path,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_card_set_id;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    IF v_rows_updated <> 1 THEN
        RAISE EXCEPTION 'ADMIN_SET_CARD_SET_LOGO_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_card_set_id;
    END IF;
END;
$$;
```

Confirmado estruturalmente: `SECURITY DEFINER`, `search_path` vazio, `EXECUTE` concedido a `authenticated` e negado a `anon`/`public`. Chamada em tempo real não foi testada nesta rodada (bloqueada pelo classificador automático do ambiente de execução por se parecer com uma ação de escrita) — comportamento validado por revisão do corpo da função. Arquivo em `database/migrations/275_create_admin_set_card_set_logo_function.sql`.

## Storage — bucket `card-set-logo` (Query `276`, CONFIRMADO EXECUTADO)

Bucket privado, dedicado exclusivamente às logos de Card Set — diverge deliberadamente do padrão público já usado por `card-front`/`artwork`/`card-back`/`avatars`, porque o Catálogo Editorial é admin-only por completo. Leitura no frontend ocorre por URL assinada (`createSignedUrl()`), nunca `getPublicUrl()`. Quatro políticas separadas em `storage.objects` — nunca uma única `FOR ALL` — cada uma restrita a `bucket_id = 'card-set-logo' AND is_admin()`:

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('card-set-logo', 'card-set-logo', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY card_set_logo_admin_select ON storage.objects
    FOR SELECT USING (bucket_id = 'card-set-logo' AND is_admin());

CREATE POLICY card_set_logo_admin_insert ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'card-set-logo' AND is_admin());

CREATE POLICY card_set_logo_admin_update ON storage.objects
    FOR UPDATE USING (bucket_id = 'card-set-logo' AND is_admin())
    WITH CHECK (bucket_id = 'card-set-logo' AND is_admin());

CREATE POLICY card_set_logo_admin_delete ON storage.objects
    FOR DELETE USING (bucket_id = 'card-set-logo' AND is_admin());
```

`card-set-logo` não é registrado na tabela `storage_bucket` — mesmo padrão já usado por `avatars` (bucket module-owned, fora do catálogo multi-bucket de `card_asset`). Confirmado via `storage.buckets`/`pg_policies`. Arquivo em `database/migrations/276_create_card_set_logo_storage_bucket_and_policies.sql`.

## Menu e rota (CONFIRMADO IMPLEMENTADO — validação em produção pendente)

Guarda de menu (`nav-config.ts`, `catalogo.adminOnly = true`) e guarda de servidor compartilhada pelas seis rotas do módulo (`components/catalogo/catalogo-guard.tsx`, função `requireCatalogoAdmin()`), mesmo padrão já validado em produção em `/usuarios/page.tsx`: sem sessão → `/login`; sem papel administrativo → `Alert` de acesso restrito, nenhum conteúdo real renderizado. Aplicada às seis rotas (`/catalogo`, `/jogos`, `/expansoes`, `/card-sets`, `/cartas`, `/importacoes`) e à nova rota de detalhe `/catalogo/card-sets/[code]`, inclusive as que ainda são `ComingSoonPage` — a guarda não depende da tela ter conteúdo real. `tsc --noEmit` confirmado limpo para todo o código novo; validação visual em `npm run dev` ainda pendente (ambiente sem acesso a npm/CDN nesta sessão).

## Sequência

```text
274 - Add Admin-Only SELECT Policies to Catalog Tables   (CONFIRMADO EXECUTADO — database/migrations/274_add_admin_only_select_policies_to_catalog_tables.sql)
275 - Create admin_set_card_set_logo() Function            (CONFIRMADO EXECUTADO — database/migrations/275_create_admin_set_card_set_logo_function.sql)
276 - Create Card Set Logo Storage Bucket and Policies      (CONFIRMADO EXECUTADO — database/migrations/276_create_card_set_logo_storage_bucket_and_policies.sql)
277 - Validate Catalog Editorial Authorization and Logo     (EXECUTADA — database/validations/277_validate_catalog_editorial_authorization_and_logo.sql)
```

(`273 - Add Card Set Logo Column` documentada na seção "Set" acima, não repetida aqui.)

## Frontend — Visão Geral (`/catalogo`, CONFIRMADO IMPLEMENTADO, validação em produção pendente)

Implementada após a fundação de banco acima ser concluída e validada, conforme condicionado por Fabrício. Quatro blocos, todos exclusivos de administradores (guarda de servidor + RLS `catalog_admin_select`):

- **Estado do Catálogo** — KPIs de estado (Card Sets catalogados, cobertura de imagens, cartas catalogadas, importações com pendência), deliberadamente sem Games/Expansions (só 1 registro cada, sem valor visual).
- **Card Sets** — tabela navegável; cada linha leva a `/catalogo/card-sets/{code}`, uma página de detalhe mínima (mesmos dados já resumidos na tabela — galeria de cartas, edição de logo e histórico de importações do Set ficam para um incremento futuro).
- **Cartas por raridade** — distribuição em barras simples (CSS, sem nova dependência de gráfico); deliberadamente por Raridade, não por Card Category, para não expor a discrepância interna da categoria `ENERGY`.
- **Atividade Recente** — últimas execuções de `asset_import_run` traduzidas para linguagem natural; continua sendo informação exclusivamente administrativa (decisão de Fabrício), nunca pública.

Camada de dados em `web/lib/catalogo/queries.ts` — leitura direta das 10 tabelas liberadas pela Query `274`, sem função de banco dedicada (volume atual, ~927 Cards, pequeno o suficiente para agregar no servidor Next.js). Guarda compartilhada em `web/components/catalogo/catalogo-guard.tsx`.

**Ressalva de transparência**: os blocos e o wireframe originais foram aprovados por Fabrício em uma troca anterior à compactação de contexto desta sessão; o texto exato (indicadores linha a linha, wireframe ASCII) não pôde ser recuperado integralmente. Esta implementação reconstrói os quatro blocos e os seis refinamentos já confirmados (rota `/catalogo` separada de `/`, KPIs de estado sem Games/Expansions, Atividade Recente amigável, sem expor `ENERGY`, tabela navegável) a partir do resumo disponível e de nova verificação direta do banco — os indicadores exatos (títulos, agrupamentos) podem não ser idênticos ao que foi aprovado originalmente e valem uma conferência de Fabrício.

## Pendências / Próximos Passos

Validação visual em `npm run dev` (ambiente desta sessão sem acesso a npm/CDN — `tsc --noEmit` confirmado limpo, mas nenhuma renderização real foi conferida). Design completo do detalhe de Card Set (galeria de cartas, upload de logo via `admin_set_card_set_logo()`, histórico de importações do Set). Telas `/catalogo/jogos`, `/expansoes`, `/card-sets` (listagem), `/cartas` e `/importacoes` seguem como `ComingSoonPage`, agora com a guarda de admin já aplicada.

---

# Catálogo Editorial — Escrita e Ingestão

## Status

**EM IMPLEMENTAÇÃO (iniciado em 2026-07-26).** Formaliza `ADR-023` (Catalog Editorial Write Authorization) e, em incremento futuro, `ADR-024` (Catalog Card Ingestion Strategy). Numeração no milhar `2000`–`2999` (`STD-001` v1.17, Seção 10). Implementação em ciclos verticais por entidade (Backend → Tela → Validação), por decisão de Fabrício: primeiro a infraestrutura comum, depois `Game` → `Expansion` → `Card Set` → `Card` (subdividido em criação/edição e desativação/reativação).

## Schema `internal` (Query `2000`, CONFIRMADO EXECUTADO)

Schema dedicado a rotinas de persistência internas, não expostas pela API (`STD-001` v1.17, Seção 9). Primeira rotina prevista: `internal.write_card()` (Query `2030`).

```sql
CREATE SCHEMA internal;

COMMENT ON SCHEMA internal IS
    'Rotinas de persistência internas do Catálogo Editorial (ADR-023/ADR-024). '
    'Nunca exposto pela API do Supabase. Contém apenas funções SECURITY DEFINER, '
    'nunca tabelas ou views (STD-001 v1.17, Seção 9).';

REVOKE ALL ON SCHEMA internal FROM PUBLIC;
REVOKE ALL ON SCHEMA internal FROM anon;
REVOKE ALL ON SCHEMA internal FROM authenticated;
```

Confirmado: schema existe, comentário gravado, `nspacl = {postgres=UC/postgres}` (nenhuma entrada para `PUBLIC`/`anon`/`authenticated`), `has_schema_privilege('anon'/'authenticated', 'internal', 'USAGE')` = `false` para ambos. Confirmado manualmente por Fabrício: `internal` não consta em Studio → Settings → API → Exposed schemas (só `graphql_public`/`public` expostos). Arquivo em `database/schema/2000_create_internal_schema.sql`; validação em `database/validations/2800_validate_internal_schema.sql`.

## Auditoria — `catalog_admin_action_log` (Query `2010`, CONFIRMADO EXECUTADO)

Auditoria própria do módulo, deliberadamente separada de `admin_action_log` (`ADR-021`, domínio de Identidade & Acesso). Nome definitivo confirmado nesta implementação — `ADR-023` havia registrado apenas um exemplo, deixando a confirmação para este documento.

```sql
CREATE TABLE public.catalog_admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    action           TEXT NOT NULL,
    entity_type      TEXT NOT NULL,
    entity_id        UUID NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT ck_catalog_admin_action_log_action_valid
        CHECK (action IN (
            'GAME_CREATED', 'GAME_UPDATED',
            'EXPANSION_CREATED', 'EXPANSION_UPDATED',
            'CARD_SET_CREATED', 'CARD_SET_UPDATED',
            'CARD_CREATED', 'CARD_UPDATED',
            'CARD_DEACTIVATED', 'CARD_REACTIVATED'
        )),
    CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
        CHECK (entity_type IN ('GAME', 'EXPANSION', 'CARD_SET', 'CARD')),
    CONSTRAINT ck_catalog_admin_action_log_action_entity_match
        CHECK (
            (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED'))
            OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED'))
            OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED'))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
        )
);

ALTER TABLE public.catalog_admin_action_log ENABLE ROW LEVEL SECURITY;
```

`entity_id` é polimórfico (aponta para `game`/`expansion`/`card_set`/`card` conforme `entity_type`) e por isso não tem FK — `NOT NULL` porque toda ação registrada aqui sempre tem exatamente uma entidade concreta como alvo. `actor_id` anulável com `ON DELETE SET NULL`, mesmo padrão de `admin_action_log`. Terceiro `CHECK` (`action_entity_match`) é reforço de integridade de implementação, adicional ao que `ADR-023` descreveu — garante que uma combinação logicamente inválida (ex. `GAME_CREATED` com `entity_type = 'CARD'`) nunca é gravada. Confirmado via `information_schema`/`pg_constraint`/`pg_tables`/`pg_policies`: 7 colunas, 5 constraints (PK, FK, 3 CHECKs), RLS habilitado, zero políticas. Arquivo em `database/schema/2010_create_catalog_admin_action_log.sql`; validação em `database/validations/2801_validate_catalog_admin_action_log.sql`.

## `card.is_active` (Query `2020`, CONFIRMADO EXECUTADO)

Soft delete real e irrestrito, não condicionado à ausência de dependentes (`ADR-023`).

```sql
ALTER TABLE public.card
    ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;
```

`DEFAULT true` evita qualquer backfill separado — as 927 Cards existentes tornaram-se ativas automaticamente, confirmado (`927`/`927`). `uq_card_card_set_collector_number` (Query `140`) permanece inalterada e continua válida independentemente de `is_active` — uma Card inativa continua ocupando sua chave natural. Nenhum índice criado nesta Query (volume atual não justifica; reavaliar quando o número de Cards inativas crescer). Nenhuma cascata para `card_variant`/`card_asset`/`card_external_reference`. O ajuste da camada de leitura (`web/lib/catalogo/queries.ts` filtrar `is_active = true` por padrão) fica para o ciclo vertical de `Card`, junto com `admin_deactivate_card()`/`admin_reactivate_card()` (`2039`/`2040`) e o controle de inativas na tela. Arquivo de execução em `database/migrations/2020_add_is_active_to_card.sql`; canônica `database/schema/140_create_card_table.sql` atualizada para v1.1 (Princípio da Fonte Canônica); validação em `database/validations/2802_validate_card_is_active.sql`.

## `internal.write_card()` (Query `2030`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Camada canônica única de persistência de Card — reutilizada por `admin_create_card()`/`admin_update_card()` (Queries `2037`/`2038`, ainda não escritas) e, em `ADR-024`, por `admin_confirm_catalog_import()` (`ADR-023`, "Camada interna canônica").

```sql
CREATE OR REPLACE FUNCTION internal.write_card(
    p_mode TEXT, p_card_id UUID, p_card_set_id UUID, p_rarity_id UUID,
    p_category_id UUID, p_collector_number TEXT, p_collector_total INTEGER,
    p_collector_order INTEGER, p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$ ... $$;

REVOKE ALL ON FUNCTION internal.write_card(...) FROM PUBLIC, anon, authenticated;
```

`p_mode` distingue `CREATE`/`UPDATE` numa função única — evita duplicar a proteção de campos sensíveis em dois lugares. Modo `UPDATE`: se o chamador informar `p_card_set_id`/`p_collector_number` não-nulos, a função levanta `INTERNAL_WRITE_CARD_PROTECTED_FIELD` — nunca ignora silenciosamente um valor divergente. Semântica de substituição integral (não parcial) nos campos editáveis, evitando a ambiguidade de `NULL` como sentinela de "não alterar" em `collector_total` (que também aceita `NULL` como valor real). `is_active` nunca é tocado aqui — pertence exclusivamente a `admin_deactivate_card()`/`admin_reactivate_card()` (`2039`/`2040`).

**Descoberta de implementação**: a consistência de Game (Card Set/Rarity/Card Category no mesmo Game) e `updated_at` já são garantidos pelo trigger existente `trg_card_validate_game_consistency`/`trg_card_set_updated_at` (Query `141`), independentemente de quem faz o `INSERT`/`UPDATE` — a "validação de FK" que `ADR-023` atribui a esta camada já é satisfeita por construção, sem duplicar lógica. Por simetria com `admin_set_card_set_logo()` (que faz sua própria checagem de `is_admin()` por não ter camada interna), esta função **não** verifica `is_admin()` — essa responsabilidade é exclusiva das funções públicas que a chamam (`2037`/`2038`), já que `EXECUTE` é revogado de todos exceto o owner.

Validado estruturalmente (`prosecdef = true`, `search_path = ""`, `anon`/`authenticated` sem `EXECUTE`) **e funcionalmente, com execução real contra o banco** — primeira função deste módulo testada em tempo real, não apenas por revisão de código: cinco cenários (`CREATE` bem-sucedido; `UPDATE` de campos editáveis; tentativa de alterar `card_set_id` bloqueada; `UPDATE` de id inexistente bloqueado; `p_mode` inválido bloqueado), todos dentro de uma transação com `RAISE EXCEPTION` forçado ao final — `ROLLBACK` total confirmado, `0` linhas residuais. Arquivo em `database/schema/2030_create_internal_write_card_function.sql`; validação em `database/validations/2803_validate_internal_write_card.sql`.

## Sequência

```text
2000 - Create Internal Schema                              (CONFIRMADO EXECUTADO — database/schema/2000_create_internal_schema.sql)
2010 - Create Catalog Admin Action Log Table                (CONFIRMADO EXECUTADO — database/schema/2010_create_catalog_admin_action_log.sql)
2020 - Add is_active to Card                                (CONFIRMADO EXECUTADO — database/migrations/2020_add_is_active_to_card.sql)
2030 - Create internal.write_card() Function                (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2030_create_internal_write_card_function.sql)
2800 - Validate Internal Schema                             (EXECUTADA — database/validations/2800_validate_internal_schema.sql)
2801 - Validate Catalog Admin Action Log                    (EXECUTADA — database/validations/2801_validate_catalog_admin_action_log.sql)
2802 - Validate Card is_active                              (EXECUTADA — database/validations/2802_validate_card_is_active.sql)
2803 - Validate internal.write_card()                       (EXECUTADA — database/validations/2803_validate_internal_write_card.sql)
2031 - Create admin_create_game() Function                  (CONFIRMADO EXECUTADO — database/schema/2031_create_admin_create_game_function.sql)
2032 - Create admin_update_game() Function                  (CONFIRMADO EXECUTADO — database/schema/2032_create_admin_update_game_function.sql)
2041 - Add GAME_DELETED to Catalog Admin Action Log          (CONFIRMADO EXECUTADO — database/migrations/2041_add_game_deleted_to_catalog_admin_action_log.sql)
2042 - Create admin_delete_game() Function                  (CONFIRMADO EXECUTADO — database/schema/2042_create_admin_delete_game_function.sql)
2804 - Validate Game Admin Functions                        (EXECUTADA — database/validations/2804_validate_game_admin_functions.sql)
2808 - Validate Game Delete                                 (EXECUTADA — database/validations/2808_validate_game_delete.sql)
2033 - Create admin_create_expansion() Function              (CONFIRMADO EXECUTADO — database/schema/2033_create_admin_create_expansion_function.sql)
2034 - Create admin_update_expansion() Function              (CONFIRMADO EXECUTADO — database/schema/2034_create_admin_update_expansion_function.sql)
2805 - Validate Expansion Admin Functions                    (EXECUTADA — database/validations/2805_validate_expansion_admin_functions.sql)
2043 - Add EXPANSION_DELETED to Catalog Admin Action Log     (CONFIRMADO EXECUTADO — database/migrations/2043_add_expansion_deleted_to_catalog_admin_action_log.sql)
2044 - Create admin_delete_expansion() Function              (CONFIRMADO EXECUTADO — database/schema/2044_create_admin_delete_expansion_function.sql)
2809 - Validate Expansion Delete                             (CONFIRMADO EXECUTADO — database/validations/2809_validate_expansion_delete.sql; validação estrutural via SQL + validação funcional via UI por Fabrício)
2045 - Add Expansion Logo Column                             (CONFIRMADO EXECUTADO — database/schema/2045_add_expansion_logo_column.sql)
2046 - Create admin_set_expansion_logo() Function            (CONFIRMADO EXECUTADO — database/schema/2046_create_admin_set_expansion_logo_function.sql)
2047 - Create Expansion Logo Storage Bucket and Policies     (CONFIRMADO EXECUTADO — database/schema/2047_create_expansion_logo_storage_bucket_and_policies.sql)
2810 - Validate Expansion Logo                               (CONFIRMADO EXECUTADO — database/validations/2810_validate_expansion_logo.sql)
2048 - Create admin_update_card_set() Function               (CONFIRMADO EXECUTADO — database/schema/2048_create_admin_update_card_set_function.sql)
2049 - Add CARD_SET_DELETED to Catalog Admin Action Log      (CONFIRMADO EXECUTADO — database/migrations/2049_add_card_set_deleted_to_catalog_admin_action_log.sql)
2050 - Create admin_delete_card_set() Function               (CONFIRMADO EXECUTADO — database/schema/2050_create_admin_delete_card_set_function.sql)
2811 - Validate Card Set Update and Delete                   (validação estrutural CONFIRMADA EXECUTADA; validação funcional pendente — database/validations/2811_validate_card_set_update_and_delete.sql)
2051 - Create admin_create_card_set() Function                (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE, v1.1 com ENERGY — database/schema/2051_create_admin_create_card_set_function.sql)
2052 - Widen admin_update_card_set() for Type and Release Date (CONFIRMADO EXECUTADO — database/migrations/2052_widen_admin_update_card_set_for_type_and_release_date.sql)
2053 - Add card_asset_type Admin Select Policy                (CONFIRMADO EXECUTADO — database/schema/2053_add_card_asset_type_admin_select_policy.sql)
2812 - Validate admin_create_card_set()                       (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE, três cenários — database/validations/2812_validate_admin_create_card_set.sql)
2091 - Widen admin_update_card_set() for Code                (CONFIRMADO EXECUTADO — database/migrations/2091_widen_admin_update_card_set_function_for_code.sql)
2815 - Validate Card Set Code Editable                        (CONFIRMADO EXECUTADO — database/validations/2815_validate_card_set_code_editable.sql)
2092 - Create admin_start_asset_import_run() Function          (v1.1 CONFIRMADO EXECUTADO; v1.2 SQL PREPARADO — AGUARDANDO EXECUÇÃO — database/schema/2092_create_admin_start_asset_import_run_function.sql)
2816 - Validate admin_start_asset_import_run()                 (v1.1 CONFIRMADO EXECUTADO; v1.2 SQL PREPARADO — AGUARDANDO EXECUÇÃO — database/validations/2816_validate_admin_start_asset_import_run.sql)
```

**Reconciliação de gap (2026-08-01):** as quatro linhas acima (`2051`/`2052`/`2053`/`2812`) já estavam confirmadas executadas por Fabrício desde 2026-07-31 (ver revisões anteriores desta tabela de histórico), mas nunca haviam sido incluídas nesta lista de Sequência — mesmo tipo de gap documental já visto antes neste projeto (ex.: `EXPANSION_DELETED` faltando no arquivo canônico de `catalog_admin_action_log`, corrigido na Query `2049` v1.2). Corrigido aqui, sem re-executar nada — só a lista estava desatualizada.

### Ciclo 1 — Infraestrutura comum de staging e confirmação (ADR-024, Catalog Card Ingestion Strategy)

Primeiro ciclo vertical do fluxo de ingestão de Cards (PDF e TCGdex), aprovado por Fabrício em 2026-08-01 após duas rodadas de revisão do plano técnico (ver `HANDOFF`/ata da conversa — nenhuma migration/função/frontend foi escrita antes da aprovação final). Ordem de ciclos definida por Fabrício: (1) infraestrutura comum — esta seção; (2) fluxo TCGdex completo; (3) prova técnica do processador de PDF; (4) fluxo PDF com o processador aprovado. Nenhum processador (Edge Function TCGdex ou PDF) existe ainda — esta seção só cobre staging, decisão e confirmação, exercitadas nesta fase com dados sintéticos (Query `2814`) até o Ciclo 2 existir.

Decisões definitivas do ajuste final de Fabrício (2026-08-01), incorporadas em todas as Queries abaixo:
1. `progress_step` (`catalog_import_job`) é um enum/índice estável (`TEXT` com `CHECK` fechado de 7 valores) — os textos e ícones de exibição pertencem inteiramente ao frontend.
2. `category_confidence` (`HIGH`/`MEDIUM`/`LOW`) e `category_source` (`API`/`ENERGY_PREFIX`/`POKEMON_MATCH`/`TRAINER_FALLBACK`) vivem dentro de `normalized_data` (JSONB) de `catalog_import_row`, junto com `category` — **não** como colunas físicas próprias. Decisão revista por Fabrício em 2026-08-01 (segunda rodada de aprovação): o desenho de dados do ADR-024 não é alterado nesta etapa; category_source/category_confidence são metadados do mesmo processo de resolução que já produz name/collector_number/rarity_id/category_id dentro do JSONB, não um novo eixo de estado da linha — os quatro estados independentes continuam sendo só validation_status/match_status/decision_status/persistence_status. (Uma primeira versão desta Query havia acrescentado os dois como colunas físicas; revertido antes de qualquer execução.)
3. A regra de classificação de categoria é única para os dois canais: a API TCGdex, quando fornece categoria, só aumenta a confiança do mesmo algoritmo (prefixo "Energia" → `ENERGY`; senão correspondência de nome de espécie Pokémon via TCGdex → `POKEMON`; senão `TRAINER` por eliminação) — nunca o substitui. Implementada nos campos `category_source`/`category_confidence` dentro de `normalized_data`; o algoritmo em si só é escrito em código no processador de cada canal (Ciclos 2/3/4), fora do escopo SQL desta Query.
4. O resumo de análise da tela de Revisão (cartas analisadas/classificadas automaticamente/com alerta/com erro) é derivável diretamente dos contadores já recalculados por agregação em `catalog_import_job` — nenhuma coluna nova foi necessária para viabilizá-lo.

Descoberta durante a implementação: `card_set`/`card` não possuem nenhuma coluna de idioma (confirmado em `database/schema/120`/`140`) — `catalog_import_job` não guarda `language_id` (diferente do que uma leitura apressada de `card_asset`, que É localizado por idioma, sugeriria). O idioma de publicação já está implícito em qual Card Set foi escolhido no dropdown.

`admin_start_catalog_import()`/`admin_decide_catalog_import_row()`/`admin_confirm_catalog_import()` são três funções distintas (não uma só) porque cobrem três momentos do fluxo com autorizações e granularidades diferentes: abrir (uma vez, gera auditoria), decidir (muitas vezes por job, reversível, sem auditoria própria — a decisão já fica registrada na própria linha) e confirmar (persiste de fato, sempre em lote, sempre auditada). `admin_confirm_catalog_import()` chama `internal.write_card()` diretamente — mesma camada canônica usada por `admin_create_card()`/`admin_update_card()` (ainda não escritas), nunca duplicando a lógica de proteção de campos.

```sql
CREATE OR REPLACE FUNCTION public.admin_start_catalog_import(
    p_card_set_id UUID, p_source TEXT, p_file_checksum TEXT DEFAULT NULL, p_external_set_id TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_decide_catalog_import_row(
    p_row_ids UUID[], p_decision_status TEXT, p_corrected_normalized_data JSONB DEFAULT NULL
)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_confirm_catalog_import(
    p_job_id UUID, p_row_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (inserted_count INTEGER, updated_count INTEGER, unchanged_count INTEGER, failed_count INTEGER, pending_count INTEGER, job_status TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

## Sequência — Ciclo 1 (ADR-024)

```text
2054 - Widen Catalog Admin Action Log for Catalog Import      (CONFIRMADO EXECUTADO, com gap — ver 2055 — database/migrations/2054_widen_catalog_admin_action_log_for_catalog_import.sql)
2055 - Add CATALOG_IMPORT_JOB Entity Type to Action Log       (CONFIRMADO EXECUTADO — corrige gap da 2054 — database/migrations/2055_add_catalog_import_job_entity_type_to_action_log.sql)
2060 - Create Catalog Import Job Table                        (CONFIRMADO EXECUTADO — database/schema/2060_create_catalog_import_job.sql)
2061 - Catalog Import Job Triggers                            (CONFIRMADO EXECUTADO — database/schema/2061_catalog_import_job_triggers.sql)
2070 - Create Catalog Import Row Table                        (CONFIRMADO EXECUTADO — database/schema/2070_create_catalog_import_row.sql)
2071 - Catalog Import Row Triggers                            (CONFIRMADO EXECUTADO — database/schema/2071_catalog_import_row_triggers.sql)
2080 - Create admin_start_catalog_import() Function            (CONFIRMADO EXECUTADO — database/schema/2080_create_admin_start_catalog_import_function.sql)
2081 - Create admin_decide_catalog_import_row() Function       (CONFIRMADO EXECUTADO — database/schema/2081_create_admin_decide_catalog_import_row_function.sql)
2082 - Create admin_confirm_catalog_import() Function          (CONFIRMADO EXECUTADO — database/schema/2082_create_admin_confirm_catalog_import_function.sql)
2813 - Validate Catalog Import Staging Tables                 (CONFIRMADO EXECUTADO — validação estrutural conferida nos 9 resultados, database/validations/2813_validate_catalog_import_staging_tables.sql)
2814 - Validate Catalog Import Functions                      (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/validations/2814_validate_catalog_import_functions.sql)
```

**Ciclo 1 concluído e validado (2026-08-01)** — as 11 Queries acima (as 10 originais mais a `2055`, gap descoberto durante a validação funcional) foram executadas uma a uma por Fabrício no Supabase, seguindo o ritual já estabelecido do projeto, cada uma confirmada antes da próxima. Validação estrutural (`2813`) conferida nos 9 resultados retornados. Validação funcional (`2814`, bloco 4) rodou o caminho completo com dados sintéticos (prefixo `ZZTEST`, `ROLLBACK` ao final, nenhum resíduo): abertura de job, bloqueio de fingerprint duplicado, decisão de linhas (aprovar/pular), confirmação com os três desfechos de persistência (`INSERTED`/`UPDATED`/`UNCHANGED`) — incluindo o cenário de conflito já revisado sendo sobrescrito corretamente —, bloqueio de reconfirmação de job já `COMPLETED`, e a auditoria agregada (`CATALOG_IMPORT_JOB`/`CATALOG_IMPORT_CONFIRMED`) gravada nos dois pontos certos. Dois problemas reais encontrados e corrigidos durante a própria execução (não hipotéticos, descobertos ao rodar contra o banco real):
- **Gap na Query 2054** (Query `2055`): `catalog_admin_action_log` tem três constraints de validação, não duas — `ck_catalog_admin_action_log_entity_type_valid` foi esquecida na ampliação original, bloqueando a primeira chamada real de `admin_start_catalog_import()`. Corrigido com uma migration isolada e reconciliado no arquivo canônico da Query `2010` (v1.3).
- **`is_admin()` inalcançável no SQL Editor**: mesma limitação já registrada na Query `1860` (`auth.uid()` não resolve fora de uma sessão JWT real) — mas, diferente de todos os ciclos anteriores, este Ciclo 1 não tem nenhuma tela para validar por lá ainda. Contornado simulando a sessão do primeiro administrador real via `set_config('request.jwt.claim(s)...', true)`, escopo local à transação de teste.

Ciclo 2 (fluxo TCGdex completo) só começa com autorização explícita de Fabrício, por instrução direta dele ("Não avance para o Ciclo 2 até concluirmos integralmente o Ciclo 1 e validarmos sua implementação").

## Ciclo vertical — `Game` (Queries `2031`/`2032`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Primeiro ciclo vertical implementado (Backend → Tela → Validação), por decisão de Fabrício. Sem camada `internal` própria — diferente de Card, `Game` não converge múltiplos canais de entrada nem tem campos protegidos por regra complexa; o `INSERT`/`UPDATE` acontece diretamente na função pública, mesmo padrão de `admin_set_card_set_logo()` (`ADR-022`).

```sql
CREATE OR REPLACE FUNCTION public.admin_create_game(p_code TEXT, p_name TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_update_game(p_id UUID, p_name TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

`code` imutável na edição **por construção**: `admin_update_game()` nem tem parâmetro para isso — não é uma checagem em tempo de execução (como o `RAISE EXCEPTION` de campo protegido em `internal.write_card()`), é a ausência do próprio parâmetro na assinatura. `admin_create_game()` normaliza `code` para maiúsculas (`upper(btrim(...))`) antes de validar formato (`^[A-Z][A-Z0-9_]*$`) e duplicidade — duplicidade verificada explicitamente antes do `INSERT`, com mensagem clara (`ADMIN_CREATE_GAME_DUPLICATE_CODE`), antecipando o erro bruto de `uq_game_code`. Ambas gravam em `catalog_admin_action_log` (`GAME_CREATED`/`GAME_UPDATED`) em caso de sucesso.

Validado estruturalmente e **funcionalmente, com execução real contra o banco**: 8 cenários (criação bem-sucedida com normalização de `code`; duplicidade; formato inválido; nome vazio na criação; atualização bem-sucedida; id inexistente; nome vazio na atualização; chamada sem sessão administrativa), todos simulando a sessão do administrador real via `set_config('request.jwt.claim.sub', ...)`, dentro de uma transação com `RAISE EXCEPTION` forçado ao final — `ROLLBACK` total confirmado, incluindo as duas linhas de auditoria geradas pelos cenários de sucesso. Arquivos em `database/schema/2031_create_admin_create_game_function.sql` e `database/schema/2032_create_admin_update_game_function.sql`; validação em `database/validations/2804_validate_game_admin_functions.sql`.

**Frontend (`/catalogo/jogos`, IMPLEMENTADO — validação pela interface pendente)**: `JogosTable` (`web/components/catalogo/jogos-table.tsx`) substitui a tabela estática por um componente client com cadastro (formulário inline acima da tabela) e edição (linha da tabela substituída por um formulário inline, `code` sempre desabilitado). Duas Server Actions em `web/app/catalogo/jogos/actions.ts` (`createGame`/`updateGame`) chamam os RPCs via `supabase.rpc(...)`, traduzem erros com o novo `traduzirErroCatalogo()` (`web/lib/supabase/catalogo-errors.ts` — extrai o texto após o prefixo `CODIGO_MAIUSCULO: `, reutilizável pelas funções futuras de Expansion/Card Set/Card, diferente de `traduzirErroAdmin()` de ADR-021, que faz match exato de frase) e chamam `revalidatePath("/catalogo/jogos")`; o componente força `router.refresh()` após sucesso para repassar dados atualizados do Server Component. `tsc --noEmit` confirmado limpo para todo o código novo (dois erros pré-existentes em `lib/supabase/middleware.ts`/`server.ts`, não tocados nesta revisão, não fazem parte deste incremento).

**Confirmado por Fabrício via interface real** (2026-07-26): listagem e cadastro testados na própria tela (`/catalogo/jogos` exibindo os Jogos reais cadastrados). Dois ajustes visuais pedidos e aplicados: botão "Cadastrar novo jogo" reposicionado para fora do card da tabela (linha do título, alinhado à direita), com borda na cor primária (`outline-primary`, nova variante de `Button`, reutilizável pelos próximos ciclos), ícone `Plus` e altura compacta (`sm`); ação "Editar" na tabela trocada de botão de texto para ícone (`Pencil`, nova variante `icon-sm`).

## Emenda — `Game`: exclusão real via UI (Queries `2041`/`2042`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Durante a validação do ciclo de `Game`, Fabrício pediu exclusão de itens pela própria tela. `ADR-023` originalmente previa para `Game`/`Expansion`/`Card Set` apenas "create/update nesta fase, sem desativação por UI", com correção rara resolvida "por SQL direta" — como isto contradizia uma decisão já formalizada e encerrada, a exclusão foi tratada como uma emenda explícita ao ADR (não uma implementação silenciosa), aprovada por Fabrício antes de qualquer Query. Ver `ADR-023`, seção "Emenda (2026-07-26) — `Game`: exclusão real via UI".

```sql
-- 2041: adiciona GAME_DELETED às constraints de catalog_admin_action_log
ALTER TABLE public.catalog_admin_action_log DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;
ALTER TABLE public.catalog_admin_action_log ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
    CHECK (action IN (..., 'GAME_DELETED', ...));
-- (mesma alteração em ck_catalog_admin_action_log_action_entity_match)

-- 2042: admin_delete_game()
CREATE OR REPLACE FUNCTION public.admin_delete_game(p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

Exclusão real (`DELETE`), não desativação — `Game` continua sem `is_active`. `code`/`name` são capturados por `SELECT` antes do `DELETE` (para a auditoria, já que depois não há mais registro a consultar). A `FK fk_expansion_game` (`ON DELETE RESTRICT`, Query `110`) já impedia a exclusão de um Game com Expansions — a função antecipa esse erro bruto com `ADMIN_DELETE_GAME_HAS_DEPENDENTS`. Toda exclusão bem-sucedida grava `GAME_DELETED` em `catalog_admin_action_log`. Restrita a `Game` — `Expansion`/`Card Set` não recebem `admin_delete_*` por esta emenda.

Validado com **4 cenários reais** (exclusão de um Game de teste sem Expansions — sucesso, auditoria confirmada; tentativa de excluir `POKEMON` — bloqueada por ter Expansion associada, `POKEMON` preservado; id inexistente; sem sessão administrativa), dentro de uma transação com `ROLLBACK` forçado — 0 Jogos/linhas de auditoria residuais, total real de Jogos inalterado. `database/schema/2010_create_catalog_admin_action_log.sql` atualizado para v1.1 (Princípio da Fonte Canônica). Arquivos em `database/migrations/2041_add_game_deleted_to_catalog_admin_action_log.sql` e `database/schema/2042_create_admin_delete_game_function.sql`; validação em `database/validations/2808_validate_game_delete.sql`.

**Frontend**: `JogosTable` ganhou checkbox por linha (+ "selecionar todos" no cabeçalho), uma barra de seleção ("N selecionados" + "Excluir selecionados") e uma confirmação inline antes de excluir (lista os Jogos afetados, aviso de ação irreversível). Nova Server Action `deleteGames` (`web/app/catalogo/jogos/actions.ts`) chama `admin_delete_game()` uma vez por id selecionado — sem função de exclusão em lote no banco, dado o volume — e reporta falhas por item individualmente (ex.: um Jogo bloqueado por ter Expansions não impede a exclusão dos demais selecionados); em caso de falha parcial, a tabela é atualizada para refletir os itens já excluídos, mas a barra de confirmação permanece aberta mostrando o motivo da falha nos itens restantes. `tsc --noEmit` confirmado limpo.

**Pendência explícita**: teste da exclusão pela própria interface ainda não confirmado por Fabrício (o teste de interface já feito nesta revisão cobriu listagem/cadastro, antes desta emenda existir).

## Colunas de auditoria na tela (`created_at`/`updated_at`)

Pedido de Fabrício para fechar o módulo: exibir data de criação e de última atualização na tabela de Jogos — explicitamente **não** no formato numérico `DD/MM/AAAA`. Novo helper `formatarData()` (`web/lib/format-date.ts`, reutilizável pelos ciclos seguintes) formata como `"26 jul 2026"`. `getJogos()` (`web/lib/catalogo/queries.ts`) passou a selecionar `created_at`/`updated_at`; `JogoRow` ganhou `createdAt`/`updatedAt`. `tsc --noEmit` confirmado limpo.

## Fechamento do ciclo de Game — refino e extração para reuso (2026-07-26)

Fabrício aprovou formalmente o ciclo de Game ("implementação consistente com a arquitetura definida, pode ser considerada concluída") e pediu quatro ajustes antes de iniciar `Expansion`, para que a base já sirva aos próximos ciclos sem duplicação:

1. **Exclusão mútua entre edição e seleção em massa.** Entrar em edição limpa a seleção e oculta a barra de ações em massa; checkboxes ficam desabilitados (visualmente esmaecidos) enquanto um formulário de criação/edição está aberto. Centralizado no novo hook `useAdminListState` (`web/hooks/use-admin-list-state.ts`) — `isFormOpen = creating || editingId !== null` é a única fonte de verdade, evitando reimplementar essa regra em cada ciclo.
2. **Componentes extraídos para reuso**: `AdminToolbar` (título + botão de criação), `BulkSelectionBar` (barra "N selecionados"), `ConfirmDeleteBar` (confirmação inline, genérica sobre `DeleteEntitiesActionState`), `SuccessBanner` (aviso de sucesso) — todos em `web/components/catalogo/`. Tipos de retorno das Server Actions centralizados em `web/lib/catalogo/admin-action-types.ts` (`EntityActionState`/`DeleteEntitiesActionState`); `GameActionState`/`DeleteGamesActionState` (em `web/app/catalogo/jogos/actions.ts`) agora são apenas aliases desses tipos compartilhados. O que permanece específico de Game em `jogos-table.tsx`: colunas da tabela, `CreateGameForm`, `EditGameRow` — tudo o que depende dos campos reais da entidade.
3. **Feedback de sucesso**: `useAdminListState.onSuccess(mensagem, id)` mostra um `SuccessBanner` e destaca a linha afetada (`bg-primary/5`, com `transition-colors`) por 3 segundos após criar/editar/excluir.
4. **Contador de Expansões clicável**: o número na coluna "Expansões" agora é um link para `/catalogo/expansoes?game=CODE`. `getExpansoes()` (`web/lib/catalogo/queries.ts`) ganhou um segundo parâmetro opcional `filters.gameCode` (filtra via `game!inner(code)` + `.eq("game.code", ...)`); `ExpansaoRow` ganhou `gameCode`. A tela `/catalogo/expansoes` (ainda somente leitura — cadastro/edição chegam no próprio ciclo de Expansion, a seguir) passou a ler `searchParams.game` e mostra um indicador "Filtrando por Jogo: X — Limpar filtro" quando o filtro está ativo.

`tsc --noEmit` confirmado limpo para todo o código novo/alterado. Escopo deliberadamente contido aos quatro pontos pedidos — nenhuma ordenação, filtro adicional ou exclusão lógica de Game foi introduzida.

## Ciclo vertical — `Expansion` (Queries `2033`/`2034`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Segundo ciclo vertical, construído sobre os componentes já extraídos no fechamento de `Game` (`useAdminListState`, `AdminToolbar`, `SuccessBanner`). Nasceu apenas com `create`/`update` — `Expansion` ganhou exclusão real (`admin_delete_expansion()`) numa emenda posterior, ver "Emenda — `Expansion`: exclusão real via UI" mais adiante nesta seção.

```sql
CREATE OR REPLACE FUNCTION public.admin_create_expansion(
    p_game_id UUID, p_code TEXT, p_name TEXT, p_release_order INTEGER
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_update_expansion(
    p_id UUID, p_name TEXT, p_release_order INTEGER
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

`game_id` e `code` imutáveis na edição por construção — `admin_update_expansion()` nem tem parâmetro para nenhum dos dois, mesmo princípio já aplicado a `code` em `Game` (Query `2032`). `admin_create_expansion()` verifica explicitamente a existência do `game_id` informado antes do `INSERT`, antecipando o erro bruto de `fk_expansion_game` (`ADMIN_CREATE_EXPANSION_GAME_NOT_FOUND`); `code` é normalizado para maiúsculas e validado por formato e duplicidade dentro do mesmo Game (`uq_expansion_game_code` é por `game_id`+`code`, não global — duas Expansions de Games diferentes podem compartilhar `code`). `release_order` deve ser um inteiro positivo e único dentro do mesmo Game (`uq_expansion_game_release_order`) — duplicidade verificada explicitamente tanto no `CREATE` quanto no `UPDATE` (excluindo a própria linha), antecipando o erro bruto da constraint. Ambas gravam em `catalog_admin_action_log` (`EXPANSION_CREATED`/`EXPANSION_UPDATED`) em caso de sucesso.

Validado estruturalmente e **funcionalmente, com execução real contra o banco**: 11 cenários (criação bem-sucedida com normalização de `code`; duplicidade de `code` no mesmo Game; duplicidade de `release_order` no mesmo Game; `game_id` inexistente; formato de `code` inválido; nome vazio na criação; atualização bem-sucedida; `release_order` colidindo com outra Expansion do mesmo Game na atualização; id inexistente na atualização; nome vazio na atualização; chamada sem sessão administrativa), todos simulando a sessão do administrador real via `set_config('request.jwt.claim.sub', ...)`, dentro de uma transação com `RAISE EXCEPTION` forçado ao final — `ROLLBACK` total confirmado, incluindo as linhas de auditoria geradas pelos cenários de sucesso (2 `EXPANSION_CREATED`, 1 `EXPANSION_UPDATED`), 0 Expansões/linhas de auditoria residuais, total real de Expansões inalterado. Arquivos em `database/schema/2033_create_admin_create_expansion_function.sql` e `database/schema/2034_create_admin_update_expansion_function.sql`; validação em `database/validations/2805_validate_expansion_admin_functions.sql`.

**Frontend (`/catalogo/expansoes`, IMPLEMENTADO — validação pela interface pendente)**: a tela foi redesenhada em 2026-07-31 (`web/components/catalogo/expansoes-gallery.tsx`, galeria de cards no mesmo padrão visual da tela Coleções, substitui a tabela original `ExpansoesTable` — que fica sem uso, mas segue exportando `CreateExpansionDialog`/`EditExpansionDialog`, reaproveitados pela galeria). Cadastro/edição continuam sobre `useAdminListState`/os mesmos Dialogs; seletor de Jogo (`<select>`, populado por `getGameOptions()`) pré-selecionado quando a tela chega filtrada por `?game=CODE`; edição mantém `game_id`/`code` desabilitados (imutáveis). `getExpansoes()`/`ExpansaoRow` ganharam `createdAt`/`updatedAt`/`gameId`; Server Actions em `web/app/catalogo/expansoes/actions.ts` (`createExpansion`/`updateExpansion`, mais `deleteExpansions` — ver emenda de exclusão abaixo). `tsc --noEmit` confirmado limpo para todo o código novo (os dez erros pré-existentes em `lib/supabase/middleware.ts`/`server.ts` não fazem parte deste incremento).

**Pendência explícita**: teste da tela pela própria interface (listar/cadastrar/editar/excluir, inclusive o filtro `?game=`) depende do ambiente de Fabrício — sandbox desta sessão sem acesso a `npm`/CDN.

## Emenda — `Expansion`: exclusão real via UI (Queries `2043`/`2044`/`2809` — CONCLUÍDA, CONFIRMADA EXECUTADA E VALIDADA FUNCIONALMENTE)

Mesmo padrão da emenda de `Game` (Queries `2041`/`2042`), estendido a `Expansion` a pedido de Fabrício — ver ADR-023, emenda 2026-07-31. Ação rápida "excluir" (ícone de lixeira) ao lado de "editar" em cada card da galeria de Expansões, mesmo mecanismo de `useAdminListState.startQuickDelete()`/`ConfirmDeleteBar` já usado em `Game`.

```sql
-- 2043: adiciona EXPANSION_DELETED às constraints de catalog_admin_action_log
ALTER TABLE public.catalog_admin_action_log DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;
ALTER TABLE public.catalog_admin_action_log ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
    CHECK (action IN (..., 'EXPANSION_DELETED', ...));
-- (mesma alteração em ck_catalog_admin_action_log_action_entity_match)

-- 2044: admin_delete_expansion()
CREATE OR REPLACE FUNCTION public.admin_delete_expansion(p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

`admin_delete_expansion()` segue byte-a-byte o mesmo roteiro de `admin_delete_game()`: exige `is_admin()`, captura `code`/`name` antes do `DELETE`, deixa a `FK fk_card_set_expansion` (`ON DELETE RESTRICT`, Query `120`) bloquear a exclusão quando há Card Sets associados (antecipada como `ADMIN_DELETE_EXPANSION_HAS_DEPENDENTS`), confirma o `DELETE` via `GET DIAGNOSTICS ... ROW_COUNT` e grava `EXPANSION_DELETED` em `catalog_admin_action_log`. Exclusão definitiva, sem "lixeira" nem forma de desfazer pela UI — mesmas garantias de `Game`.

Frontend: `deleteExpansions` (nova Server Action em `web/app/catalogo/expansoes/actions.ts`, mesmo contrato `DeleteEntitiesActionState` de `deleteGames`) chamada uma vez por id via `admin_delete_expansion()`; `ExpansoesGallery` ganhou a mesma `ConfirmDeleteBar` já usada em `JogosTable`.

**Status final**: Query `2043` confirmada executada (validado via `pg_get_constraintdef` — as duas constraints de `catalog_admin_action_log` já incluem `EXPANSION_DELETED`). Query `2044` (`admin_delete_expansion()`) confirmada executada (validado via `has_function_privilege`: `anon` sem `EXECUTE`, `authenticated` com `EXECUTE`). Validação funcional (`2809`) confirmada por Fabrício diretamente pela interface — exclusão bem-sucedida e bloqueio por dependentes testados na tela, "todos funcionando corretamente" (2026-07-31). Emenda encerrada; botão "excluir" da galeria de Expansões está em produção.

## Ajuste — Galeria de Expansões agrupada por Jogo (2026-07-31)

Pedido de Fabrício: "as expansões devem ser exibidas separadamente por cada tipo de Jogo e organizadas pela data de lançamento de forma decrescente." Puramente de apresentação — nenhuma mudança de schema, RPC, RLS ou regra de negócio.

`Expansion` não tem coluna de data de lançamento — só `release_order`, inteiro sequencial único por Jogo (`database/schema/110_create_expansion_table.sql`, `uq_expansion_game_release_order`). "Data de lançamento" foi interpretada como `release_order`, já que é o único campo que expressa ordem cronológica de lançamento ali — maior `release_order` é a Expansão mais recente daquele Jogo, por definição do próprio campo.

Nova função `getExpansoesGroupedByGame()` (`web/lib/catalogo/queries.ts`) substitui `getExpansoesForCatalogo()` no modo galeria (sem busca): agrupa por Jogo, ordena cada grupo por `release_order`, e ordena os próprios grupos alfabeticamente pelo nome do Jogo (mesmo critério de `getGameOptions()`). `ExpansoesGallery` passou a renderizar uma seção por Jogo — nome do Jogo com o mesmo indicador de cor (`getGameAccentColor`) já usado nos cards, seguido do grid daquele grupo.

**Correção de direção (2026-07-31, mesmo dia)**: a primeira versão ordenava `release_order` descendente (literal de "forma decrescente"). Fabrício testou na tela e reportou "a ordem... ficou na ordem inversa" — ajustado para `release_order` **ascendente** (`a.releaseOrder - b.releaseOrder`) a partir desse feedback direto ao vivo, não por reinterpretação teórica do pedido original.

**Ordem dos grupos corrigida (2026-07-31, mesmo dia, terceiro ajuste)**: a primeira versão ordenava os grupos (Jogos) alfabeticamente pelo nome. Fabrício pediu explicitamente o contrário: "primeiro listar todas as expansões do jogo Pokémon e depois Lorcana... Pokémon foi o primeiro game cadastrado" — ordem de cadastro, não alfabética. `game.created_at` passou a ser selecionado junto com a Expansão (só em `fetchExpansoesRawForCatalogo`, não nas demais queries que reaproveitam `ExpansionRawRow`) e os grupos são ordenados por ele, ascendente (Jogo mais antigo primeiro). Deliberadamente diferente do critério de `getGameOptions()` (alfabético, usado só no seletor de Jogo dos formulários de cadastro/edição) — os dois atendem propósitos diferentes e não precisam concordar.

Consequência necessária: o "Carregar mais" flat (paginação de 24 em 24) deixou de existir no modo galeria — carregar tudo de uma vez é a única forma de agrupar corretamente sem paginar grupos individualmente, e o volume atual (1 Jogo, poucas Expansões) não justifica essa complexidade adicional agora. `loadMoreExpansoes` (Server Action) e `getExpansoesForCatalogo()`/`sortExpansoesForCatalogo()` (query) foram removidas por ficarem sem uso. A busca (`mode === "search"`) não foi tocada — continua flat, sem agrupamento, com o "Carregar mais" que já tinha.

`tsc --noEmit` confirmado limpo (mesmos 10 erros pré-existentes de sempre, em `lib/supabase/middleware.ts`/`server.ts`).

## Logo da Expansão (`logo_storage_path`, Queries `2045`/`2046`/`2047`, CONFIRMADO EXECUTADO)

Pedido de Fabrício ("vamos incluir uma imagem para cada expansão"), mesmo dia do ajuste de agrupamento acima. Mesma arquitetura de `card_set.logo_storage_path` (ver seção "Logo do Card Set" mais adiante neste documento; decisão formalizada em `ADR-022`, emenda 2026-07-31) — coluna opcional, escrita só via função `SECURITY DEFINER`, bucket privado, leitura via URL assinada:

```sql
-- 2045: coluna
ALTER TABLE public.expansion ADD COLUMN logo_storage_path TEXT NULL;
ALTER TABLE public.expansion ADD CONSTRAINT ck_expansion_logo_storage_path_not_url
    CHECK (logo_storage_path IS NULL OR logo_storage_path !~* '^[a-z][a-z0-9+.-]*://');

-- 2046: admin_set_expansion_logo(p_expansion_id UUID, p_logo_storage_path TEXT)
-- SECURITY DEFINER, exige is_admin(), única via de escrita.

-- 2047: bucket privado expansion-logo + 4 políticas admin-only em storage.objects
```

Números fora da faixa legada `200`–`299` (onde `card_set.logo_storage_path` foi numerada, `273`/`275`/`276`) porque essa faixa está congelada desde então (`STD-001`, "Esquema Legado — Congelado") — numeradas no milhar `2000`–`2999` em vez disso, mesmo critério já usado na emenda de exclusão de `Expansion`/`Game`. Ver `ADR-022`, nova seção "Emenda", para o registro completo dessa decisão de numeração.

**Diferente de `card_set.logo_storage_path` num ponto importante**: esta é a primeira vez que o fluxo de upload realmente chega à tela — a logo de Card Set tem toda a infraestrutura de banco pronta desde 2026-07-26 (`273`/`275`/`276`), mas o upload nunca foi conectado ao frontend (`card-sets/[code]/page.tsx` marca isso como "incremento futuro"). Para Expansão, o upload foi construído de ponta a ponta nesta mesma rodada:

- `ExpansaoLogoUploader` (`web/components/catalogo/expansao-logo-uploader.tsx`, novo) — adaptado de `AvatarUploader` (`components/perfil/avatar-uploader.tsx`), com duas diferenças impostas pelo bucket ser privado/admin-only: leitura via `createSignedUrl` (não `getPublicUrl`), e a gravação do ponteiro passa pela Server Action `setExpansionLogo()` (que chama `admin_set_expansion_logo()`) em vez de um `.update()` direto do cliente — não existe política de RLS de `UPDATE` em `expansion` para isso.
- Upload disponível só no Dialog de **edição** (`EditExpansionDialog`/`EditExpansionForm`, `expansoes-table.tsx`), não no de criação — a Expansão precisa já existir (ter um `id`) para compor o caminho no bucket e para a função `admin_set_expansion_logo()` ter o que atualizar. Uma Expansão nova é criada sem logo; a logo é adicionada depois, editando.
- `getExpansionLogoUrls()` (`web/lib/catalogo/queries.ts`) gera URLs assinadas em lote (1h de validade), mesmo padrão de `getCardSetLogoUrls()`. Resolvida no Server Component (`expansoes/page.tsx`, para grupos e para a busca inicial) e em `searchExpansoesAction` (`catalogo-actions.ts`, para o "Carregar mais" da busca).
- `ExpansaoGalleryCard` exibe a imagem quando `logoUrl` existe, iniciais como reserva quando não — mesmo comportamento de `CardSetGalleryCard`.
- Novo tipo `ExpansaoWithLogo` (`ExpansaoRow & { logoUrl: string | null }`) — só usado pelas telas de leitura, nunca pela camada de escrita.
- Também é possível remover a logo (`admin_set_expansion_logo(id, NULL)`, já suportado pela função desde a Query `2046`) — botão "Remover" no uploader quando há logo cadastrada.

Todas as três Queries de banco (`2045`/`2046`/`2047`) e a validação (`2810`) confirmadas executadas por Fabrício via o ritual de pareamento (uma de cada vez, resultado conferido antes de avançar). `tsc --noEmit` confirmado limpo.

**Ajuste visual (2026-07-31, mesmo dia, depois de ver as primeiras logos reais na tela)**: a caixa da imagem em `ExpansaoGalleryCard` deixou de ser `aspect-square` — logos de Expansão são wordmarks horizontais (ex.: "Scarlet & Violet"), diferentes do símbolo compacto de Card Set que motivou o quadrado original. Trocada para `aspect-[2/1]`, `object-contain` preservado (nunca corta a imagem), padding reduzido de `p-4` para `p-3`.

## Coleções (`/catalogo/card-sets`) no padrão de Expansões + emenda `Card Set`: atualização e exclusão real via UI (Queries `2048`/`2049`/`2050`/`2811` — CONFIRMADO EXECUTADO)

Pedido de Fabrício (2026-07-31, mesmo dia da logo de Expansão): "faça todos os ajustes necessários para manter o mesmo padrão da página Expansões" na tela Coleções. Sete pontos, todos de apresentação exceto o último:

1. **`CardSetsStats`** (novo, `web/components/catalogo/card-sets-stats.tsx`) — mesmo padrão de `ExpansoesStats`: Jogos/Expansões/Coleções/Sem Cartas (Coleções sem nenhuma Carta catalogada, `tone="danger"`). Sem query nova — reaproveita `getGameOptions()`/`getExpansoes()` (já buscados para o filtro) e `getCardSetsOverview()` (mesma função da tabela de Card Sets da Visão Geral).
2. **Botão "Novo"** sai do `PageHeader` e passa a ficar numa linha própria acima do `Card` que envolve busca/filtro/conteúdo — mesmo lugar de "Nova expansão"/"Novo Jogo". Continua abrindo `NovoCatalogoDialog` (cadastro de Card Set segue fora de escopo — `admin_create_card_set()` não existe).
3. **Busca e filtro** migram para dentro do `Card` (cabeçalho, só `border-b`), tamanho/cor padrão (`h-9`, `bg-surface-muted`, `text-xs`) — deixam de flutuar soltos/`sticky`.
4. **Tamanho da logo**: padding da caixa de imagem reduzido de `p-4` para `p-3` (mesmo valor de `ExpansaoGalleryCard`), uniformizando a "respiração" da arte entre as duas galerias. A altura da caixa passou por duas rodadas de ajuste depois da implementação inicial — ver seção própria "Altura fixa da logo (Expansão e Card Set)" mais adiante, que registra o estado final (`h-28`).
5. **Paginação**: já seguia o mesmo padrão de Expansões ("Carregar mais", sem rolagem infinita) — reconfirmado ao mover o botão para dentro do `Card`, junto do grid.
6. **Botões de edição e exclusão em cada Card Set** — ação rápida (ícones sem borda, lápis/lixeira) no card, mesmo mecanismo de `useAdminListState` + `ConfirmDeleteBar` já usado em Jogos/Expansões. Estrutura do card também migrou para `<Link>` absoluto + botões `relative z-10` sobre ele (mesma técnica de `ExpansaoGalleryCard`, necessária para os ícones não ficarem aninhados dentro do link de navegação para o detalhe).
7. **Outros ajustes de padronização**: `catalogo-gallery.tsx` e `catalogo-content.tsx` (que antes dividiam cabeçalho/busca fixos vs. conteúdo trocável) foram unificados num único componente, espelhando `expansoes-gallery.tsx` (que nunca teve essa divisão) — `catalogo-content.tsx` fica sem uso, marcado no próprio arquivo, não removido. `loading.tsx` da tela também foi atualizado para o mesmo formato de skeleton usado em `expansoes/loading.tsx` (skeletons dos 4 indicadores, botão fora do cabeçalho, busca/filtro/grid dentro do mesmo `Card`).

**O item 6 exigiu escrita nova no banco** — diferente de Expansão (que já tinha `admin_update_expansion()` antes da emenda de exclusão), Card Set não tinha **nenhuma** via administrativa de escrita estrutural além da logo (`admin_set_card_set_logo()`, `ADR-022`). Ver `ADR-023`, nova seção "Emenda (2026-07-31) — `Card Set`: atualização e exclusão real via UI", para o registro completo da decisão.

```sql
-- 2048: admin_update_card_set(p_id UUID, p_name TEXT, p_release_order INTEGER)
-- Mesmo escopo mínimo de admin_update_expansion(): só nome e ordem de
-- lançamento editáveis. expansion_id/code imutáveis por construção;
-- set_type/base_set_size/total_set_size ficam de fora (campos estruturais
-- amarrados a ck_card_set_promo_size). release_order único por Expansion.

-- 2049: adiciona CARD_SET_DELETED às constraints de catalog_admin_action_log
-- (mesma técnica de 2041/2043 — DROP + ADD). Aproveitado para reconciliar
-- um gap: o arquivo canônico 2010 nunca tinha recebido EXPANSION_DELETED,
-- apesar de a migration 2043 já estar confirmada executada contra o banco
-- real desde a emenda de Expansion — corrigido no mesmo commit (2010 bump
-- para v1.2), sem migration própria (valor já existe fisicamente).

-- 2050: admin_delete_card_set(p_id UUID)
-- Mesmo padrão de admin_delete_expansion(): DELETE real, bloqueado pela
-- FK fk_card_card_set (ON DELETE RESTRICT, Query 140) quando há Cards
-- associadas (ADMIN_DELETE_CARD_SET_HAS_DEPENDENTS); grava CARD_SET_DELETED
-- em catalog_admin_action_log com code/name capturados antes do DELETE.
```

Números no milhar `2000`–`2999` (faixa legada `200`–`299` congelada desde `STD-001`), mesmo critério já usado nas emendas de Game/Expansion. Validação em `2811` (`database/validations/2811_validate_card_set_update_and_delete.sql`), mesmo roteiro de `2809`, com um bloco a mais para `admin_update_card_set()`.

**Frontend já com a fiação completa**: `EditCardSetDialog`/`EditCardSetForm` (novo, `web/components/catalogo/card-set-dialogs.tsx`) — cópia fiel do `EditExpansionDialog` já corrigido pelo ciclo de layout daquela tela (campos imutáveis viram `DialogDescription` do cabeçalho — `"{Jogo} · {Expansão} · {Código}"`, um nível a mais que Expansão; `size="lg"`). Duas novas Server Actions em `web/app/catalogo/card-sets/actions.ts` (`updateCardSet`/`deleteCardSets`), mesmo padrão de `expansoes/actions.ts`. `tsc --noEmit` confirmado limpo.

**Queries `2048`/`2049`/`2050` confirmadas executadas por Fabrício (2026-07-31)** via o ritual de pareamento (uma de cada vez, resultado conferido antes de avançar): `2048` e `2050` validadas via `has_function_privilege` (`anon` sem `EXECUTE`, `authenticated` com `EXECUTE`); `2049` validada via `pg_get_constraintdef` (ambas as constraints de `catalog_admin_action_log` incluem `CARD_SET_DELETED`, e também `EXPANSION_DELETED` — confirmando de quebra que o gap do canônico `2010` já estava reconciliado com o banco real). Os botões "editar"/"excluir" da galeria de Coleções estão funcionalmente operantes em produção. Pendência remanescente: validação funcional dos cenários de `2811` pela própria interface.

## Ajuste de contraste — `ConfirmDeleteBar` no tema escuro (2026-07-31)

Pedido de Fabrício, a partir de captura de tela real da galeria de Coleções: "ajustar a cor da tarja vermelha ao selecionar um card set para exclusão no modo escuro". Mesmo problema já diagnosticado e corrigido para o ícone de `tone="danger"` em `StatCard` — `--destructive` no tema escuro é um vermelho muito escuro (20% de luminosidade, `globals.css`), quase invisível sobre o fundo também escuro do app. `ConfirmDeleteBar` (`web/components/catalogo/confirm-delete-bar.tsx`, compartilhado por Jogos/Expansões/Coleções) ganhou `dark:` overrides: borda do container troca para `destructive-foreground` (quase branco no tema escuro) em opacidade baixa, fundo ganha mais opacidade (`/5` → `/20`); mesma troca aplicada aos textos de erro/falha internos. Tema claro inalterado. `tsc --noEmit` confirmado limpo.

## Logo do Card Set conectada ao frontend + "Novo" renomeado para "Nova Coleção" (2026-07-31)

Dois ajustes pedidos por Fabrício depois de testar a tela de Coleções redesenhada:

1. **Botão "Novo" → "Nova Coleção"** — mesma convenção de nome já usada por "Nova expansão"/"Novo Jogo" (identifica a entidade, não um genérico "Novo"). Atualizado em `catalogo-gallery.tsx` (botão + texto do estado vazio), `card-sets/loading.tsx` (skeleton) e `novo-catalogo-dialog.tsx` (título/descrição do Dialog, para não ficar inconsistente com o botão que o abre).
2. **Upload de logo no Dialog de edição** ("tela de edição não permite inclusão, alteração e remoção da logo do card Set. Use o mesmo padrão da tela de edição de Expansão") — diferente da logo de Expansão, aqui **não houve nenhum trabalho de banco**: bucket `card-set-logo` e `admin_set_card_set_logo()` já existiam desde 2026-07-26 (Queries `275`/`276`, ADR-022), CONFIRMADOS EXECUTADOS na época — só nunca tinham sido conectados a um uploader real no frontend (a seção "Logo da Expansão" acima registra esse mesmo fato como o motivo de a Expansão ter sido a "primeira vez que o fluxo de upload realmente chega à tela" — não é mais o caso). Construído nesta rodada:
   - `CardSetLogoUploader` (`web/components/catalogo/card-set-logo-uploader.tsx`, novo) — cópia fiel de `ExpansaoLogoUploader`, adaptada só na entidade/bucket (`card-set-logo`)/Server Action.
   - `setCardSetLogo()` (nova Server Action, `card-sets/actions.ts`) chama `admin_set_card_set_logo()` — mesmo padrão de `setExpansionLogo()`.
   - `EditCardSetDialog`/`EditCardSetForm` (`card-set-dialogs.tsx`) ganharam a seção Logo no corpo do formulário, mesma posição de `EditExpansionForm`; `onLogoUpdated` só chama `router.refresh()`, sem fechar o Dialog nem disparar o banner de sucesso do formulário nome/ordem — ações independentes.
   - `getCardSetLogoUrls()` (já existente, usada pela galeria) segue sendo a única fonte de URL assinada — nenhuma query nova.

`tsc --noEmit` confirmado limpo.

## Altura fixa da logo (Expansão e Card Set) (2026-07-31)

Puramente de apresentação — nenhuma mudança de schema, RPC, RLS ou regra de negócio. Duas rodadas de ajuste, ambas motivadas por feedback direto de Fabrício vendo a tela renderizada, não por reinterpretação teórica:

1. **Primeira rodada** — Fabrício pediu que a caixa da logo de Card Set (`CardSetGalleryCard`) usasse "a mesma altura que foi utilizada para as logos das expansões". A implementação inicial da seção anterior tinha mantido `aspect-square` para Card Set (raciocínio: logo de Card Set é um símbolo compacto, diferente do wordmark horizontal de Expansão) — esse raciocínio não se sustentou contra o pedido explícito, revertido para `aspect-[2/1]` (mesma proporção já usada em `ExpansaoGalleryCard`).
2. **Segunda rodada, mesmo dia** — Fabrício pediu algo mais específico: "gostaria que a altura do local destinado para imagem da logo fosse fixo e padrão para todos os card set, independente das dimensões das imagens... ajuste o tamanho da imagem ao local destinado e não o inverso". `aspect-[2/1]` ainda amarrava a altura da caixa à largura da coluna do grid (variável entre breakpoints, `grid-cols-2` a `grid-cols-6`) — trocado para `h-28` (altura fixa em pixels, igual em qualquer breakpoint). `object-contain` continua responsável por encaixar a imagem no espaço sem cortar nem distorcer — a imagem se adapta à caixa, nunca o inverso.

**Estado final**: `h-28` aplicado em ambas as galerias (`ExpansaoGalleryCard` e `CardSetGalleryCard`, `flex h-28 items-center justify-center bg-surface-muted`), mantendo as duas visualmente idênticas. Os skeletons de carregamento (`expansoes/loading.tsx` e `card-sets/loading.tsx`) foram atualizados junto, trocando `aspect-square`/`aspect-[2/1]` por `h-28 w-full` no bloco de imagem, para não divergir do card real. `tsc --noEmit` confirmado limpo.

## Confirmações de interface real (2026-07-31)

Fabrício confirmou, pela própria tela, as três pendências que vinham em aberto desde revisões anteriores:

- **Validação funcional de `2811`** (Card Set: edição, exclusão, bloqueio por dependentes, upload/remoção de logo) — confirmada.
- **Exclusão de `Game`** — confirmada, com um ajuste de escopo: a exclusão em lote (checkbox + `BulkSelectionBar`) foi desabilitada; só a exclusão individual (ação rápida por linha, mesmo padrão de `Expansion`/`Card Set`) está em produção. Consistente com o redesenho da tela `/catalogo/jogos` para o mesmo padrão de ícones de ação rápida (ver `jogos-table.tsx`) — `BulkSelectionBar` segue sem uso por nenhuma tela do módulo.
- **Tela completa de `Expansion`** (listagem, cadastro, edição, filtro `?game=`) — confirmada.

Com isso, `Game`/`Expansion`/`Card Set` (create/update/delete conforme aplicável) estão validados funcionalmente pela própria interface. Ver seção seguinte para a decisão explícita que resolve a última pendência do módulo — cadastro de `Card Set`.

## Cadastro de Card Set (`admin_create_card_set()`, Query `2051`) — decisão explícita de Fabrício

A decisão futura explícita que a seção anterior deste documento aguardava foi tomada: Fabrício pediu para concluir as funcionalidades de Card Set, especificamente o cadastro pela própria tela (`NovoCatalogoDialog` até então mostrava "Cadastro de Card Set ainda não disponível"). `admin_create_card_set()` deixa de estar fora de escopo.

Diferente de `admin_update_card_set()` (só nome/ordem de lançamento), a criação precisa cobrir todos os campos estruturais obrigatórios de `card_set` que a atualização deliberadamente não toca: `set_type`, `base_set_size`, `total_set_size` (além de `release_date`, opcional). Mesmo padrão de validação de `admin_create_expansion()` (Query `2033`), com as regras de negócio próprias de `card_set` (`database/schema/120_create_card_set_table.sql`) antecipadas como erro administrativo claro:

- `expansion_id` deve existir.
- `code` normalizado para maiúsculas, formato `^[A-Z0-9][A-Z0-9._-]*$` (permite começar com dígito, diferente de `Game`/`Expansion`), único dentro da Expansion.
- `release_order` positivo, único dentro da Expansion.
- `set_type` deve ser `REGULAR`, `SPECIAL` ou `PROMO`.
- `base_set_size` positivo; `total_set_size` maior ou igual a `base_set_size`.
- Se `set_type = PROMO`: `base_set_size` deve ser igual a `total_set_size` (`ck_card_set_promo_size`) e não pode já existir outro Card Set `PROMO` na mesma Expansion (`uq_card_set_expansion_promo`) — os dois antecipados com mensagem clara antes do erro bruto de constraint.
- Toda criação bem-sucedida grava `CARD_SET_CREATED` em `catalog_admin_action_log` — ação já prevista no `CHECK` desde a Query `2049` (v1.2), nenhuma migration de constraint necessária.

Número de Query: `2051`, milhar `2000`–`2999` já reservado (`STD-001` v1.17 §10). **Confirmada executada por Fabrício em 2026-07-31** (validada via `has_function_privilege`: `anon` sem `EXECUTE`, `authenticated` com `EXECUTE`). Validação `2812` — estrutural confirmada; funcional (cadastro real pela tela, incluindo um Card Set `PROMO`) ainda pendente.

Frontend: `NovoCatalogoDialog` ganhou o formulário completo (seletor de Expansão agrupado por Jogo, código, nome, tipo, ordem de lançamento, data de lançamento opcional, quantidade base e total) e nova Server Action `createCardSet` (`web/app/catalogo/card-sets/actions.ts`) — fiação completa e, com a Query `2051` confirmada, funcionalmente operante.

## Validação funcional de `2812` confirmada + dois ajustes visuais (2026-07-31)

Fabrício testou o cadastro de Card Set pela própria tela ("Funcionando perfeitamente bem"), incluindo o cenário `PROMO`: uma segunda tentativa de Card Set `PROMO` na mesma Expansion foi corretamente bloqueada por `uq_card_set_expansion_promo`, com a mensagem administrativa exibida na tela. Validação `2812` encerrada — **o ciclo vertical de `Game`/`Expansion`/`Card Set` do `ADR-023` está funcionalmente completo e confirmado.**

Dois ajustes de apresentação, puramente visuais:

1. **Largura do Dialog "Nova Coleção"**: `max-w-md` (padrão) cortava o texto das opções do seletor "Tipo" (ex.: "Promocional (Black Star..."). `NovoCatalogoDialog` passou a usar `size="lg"` (`DialogContent`, mesmo mecanismo já usado por `EditExpansionDialog`/`EditCardSetDialog`).
2. **Contraste da tarja de erro no tema escuro**: mesmo diagnóstico já repetido nesta sessão (`StatCard tone="danger"`, `ConfirmDeleteBar`) — `--destructive` no tema escuro é quase invisível sobre fundo escuro. Corrigido na fonte, em `InlineFeedback` (`web/components/ui/feedback.tsx`), tom `error`: `dark:border-destructive-foreground/25 dark:bg-destructive/20 dark:text-destructive-foreground`. Por ser um componente compartilhado, o fix vale para toda mensagem de erro inline do catálogo, não só este Dialog. Tema claro e os demais tons (`success`/`warning`) não alterados.

`tsc --noEmit` confirmado limpo.

## Correção — `admin_create_card_set()` rejeitava `ENERGY` + gap canônico em `card_set.set_type` (2026-07-31)

Fabrício testou o cadastro real de Card Set e reportou: "o campo tipo não consta o tipo Energy". Investigação encontrou dois problemas relacionados, não um só:

1. **Bug em `admin_create_card_set()` v1.0**: a validação de `set_type` só aceitava `REGULAR`/`SPECIAL`/`PROMO` — mas `ENERGY` já é um valor válido da coluna desde a **Migration `263`** (`database/migrations/263_add_energy_to_card_set_type.sql`), **confirmada executada em produção desde 2026-07-26**, quando `MEE` (Energia Básica Megaevolução) foi cadastrado com `set_type = 'ENERGY'` (Migration `265`). A função nova não foi checada contra o domínio real da coluna, só contra a leitura do arquivo canônico local — que tinha o mesmo problema (item 2). Corrigido: `admin_create_card_set()` v1.1 passa a aceitar `ENERGY`.
2. **Gap canônico em `database/schema/120_create_card_set_table.sql`**: o arquivo canônico (v2.1) nunca tinha incorporado a Migration `263` — `ck_card_set_type` ali ainda listava só `REGULAR`/`SPECIAL`/`PROMO`, apesar do próprio docstring da migration `263` alegar "incorporada à versão canônica de 120 a partir da v2.1". Uma instalação nova a partir da v2.1 ficaria divergente da produção (rejeitaria `ENERGY`). Mesma classe de problema já encontrada e corrigida nesta sessão para `EXPANSION_DELETED` em `catalog_admin_action_log` (Query `2010`). Corrigido: `120` bump para v2.2, `ck_card_set_type` agora inclui `ENERGY`.

Nenhuma constraint nova foi inventada: `ENERGY` **não** exige `base_set_size = total_set_size` por construção do banco — só `PROMO` tem essa regra (`ck_card_set_promo_size`). Em `MEE`, os dois valores hoje coincidem (`8 = 8`) porque são os únicos conhecidos no momento do cadastro, não por constraint — mesma semântica já esclarecida em `ADR-015`, revisão `1.7`, para Sets evolutivos do tipo `PROMO`/`ENERGY`.

Frontend: `NovoCatalogoDialog` ganhou a opção "Energia" no seletor de tipo; rótulo de `PROMO` simplificado de "Promocional (Black Star Promos)" para "Promocional" (pedido explícito de Fabrício, mesma rodada).

Validação `2812` reaberta (v1.1) para cobrir o novo cenário — depende do `CREATE OR REPLACE` de `admin_create_card_set()` v1.1 ser executado por Fabrício.

**`admin_create_card_set()` v1.1 confirmada por Fabrício em 2026-07-31** ("Teste em tela validado! e resposta da query como esperado") — cadastro de Card Set do tipo Energia funcionando pela própria tela. Validação `2812` (v1.1) encerrada, com os três cenários funcionais cobertos (cadastro geral, bloqueio de `PROMO` duplicado, cadastro `ENERGY`).

## Ordenação de Coleções — desempate por `release_order` (2026-07-31)

Pedido de Fabrício, a partir do teste da tela sem filtro ativo: "os card sets devem ser organizados por data de lançamento e se as datas forem iguais deve ser levado em consideração o número de ordem do lançamento. Sempre em ordem decrescente para os dois parâmetros." Puramente de apresentação — nenhuma mudança de schema/RPC/RLS.

`sortCatalogoCardSets()` (`web/lib/catalogo/queries.ts`), caminho sem filtro (galeria padrão de `/catalogo/card-sets`, cruza Jogos/Expansões por `release_date`): o desempate quando as duas datas coincidem — ou quando as duas estão ausentes — deixou de ser `created_at` (metadado técnico, sem significado editorial) e passou a ser `release_order` descendente. Quando só um dos dois Card Sets tem `release_date`, o comportamento existente (o que tem data vem primeiro) não foi questionado e permanece. Caminho **com** filtro de Jogo/Expansão (clique a partir de um card de Expansão) não foi alterado — continua usando `release_order` como critério primário (decisão já registrada e aprovada anteriormente nesta mesma revisão de sessão), fora do escopo deste pedido específico. `tsc --noEmit` confirmado limpo.

## Ampliação de `admin_update_card_set()` — tipo e data de lançamento editáveis (Query 2048 v2.0, Migration 2052)

Pedido explícito de Fabrício, testando a tela de edição: "deve ser permitido editar o tipo e a data de lançamento. Da forma como está, só consigo editar o nome e a ordem de lançamento." A v1.0 (Query `2048`, confirmada executada em 2026-07-31) só aceitava `name`/`release_order`.

`admin_update_card_set()` passa de 3 para 5 parâmetros (`p_id`, `p_name`, `p_set_type`, `p_release_order`, `p_release_date`). `expansion_id`/`code` continuam imutáveis (não aceitos); `base_set_size`/`total_set_size` continuam de fora — não foram pedidos, e mudar `set_type` sozinho já precisa lidar com as regras de `PROMO` usando o tamanho **já cadastrado** (não editável por esta função):

- Ao mudar `set_type` para `PROMO`, a função antecipa as duas regras que `ck_card_set_promo_size`/`uq_card_set_expansion_promo` reforçariam de qualquer forma, com mensagem administrativa clara: `base_set_size`/`total_set_size` já cadastrados precisam ser iguais (`ADMIN_UPDATE_CARD_SET_PROMO_SIZE_MISMATCH`); nenhum outro Card Set da mesma Expansion pode já ser `PROMO` (`ADMIN_UPDATE_CARD_SET_DUPLICATE_PROMO`).
- `set_type` aceita o mesmo domínio de `admin_create_card_set()`: `REGULAR`/`SPECIAL`/`PROMO`/`ENERGY`.
- `release_date` é opcional (`NULL` = data ainda não confirmada).

Como a assinatura muda (não é só a lógica interna, como na correção de `admin_create_card_set()` v1.1), `CREATE OR REPLACE` sozinho criaria uma segunda função sobrecarregada em vez de substituir a v1.0 — por isso o arquivo canônico (`database/schema/2048_...sql`, bump para v2.0) representa o estado de instalação nova, e uma migration própria (`database/migrations/2052_widen_admin_update_card_set_function.sql`) foi criada para reconciliar o banco já instalado: `DROP FUNCTION` da assinatura de 3 parâmetros, depois `CREATE FUNCTION` da nova.

Frontend: `EditCardSetForm` (`card-set-dialogs.tsx`) ganhou o campo Tipo (mesmo `SET_TYPE_OPTIONS` exportado de `novo-catalogo-dialog.tsx`, evitando duplicação) e Data de lançamento; `updateCardSet` (`card-sets/actions.ts`) envia os dois novos campos. `CatalogoCardSetRow`/`CatalogoCardSetRawRow` (`queries.ts`) ganharam `setType`/`set_type` — não existia antes, nenhuma tela de leitura precisava do tipo até agora. `tsc --noEmit` confirmado limpo.

**Migration `2052` confirmada executada por Fabrício em 2026-07-31** — validada via `pg_get_function_arguments`: uma única `admin_update_card_set` com os 5 parâmetros esperados (`p_id uuid, p_name text, p_set_type text, p_release_order integer, p_release_date date`), confirmando que a assinatura antiga de 3 parâmetros foi de fato removida (não ficou sobrecarregada). **Validação funcional confirmada por Fabrício em 2026-07-31** ("Teste na tela validado!") — edição de tipo e data de lançamento de Card Set pela própria tela funcionando.

## Ampliação de `admin_update_card_set()` — código editável sem Cards cadastradas (Query 2048 v3.0, Migration 2091)

Fabrício percebeu um erro real de cadastro (Coleção "151" registrada com código `SV4` em vez de `MEW`, dentro da Expansão `SV` — Scarlet & Violet) e pediu: "Preciso substituir de SV4 para MEW... Na tela de Edição deveremos permitir alterar o código. Só não será permitido se já houver cartas cadastradas." Isso revisa parcialmente a decisão original do `ADR-023` (`code` "imutável por construção... nunca uma ação de botão") — ver emenda "Card Set: código editável sem Cards cadastradas" no próprio `ADR-023`.

`admin_update_card_set()` passa de 5 para 6 parâmetros (`p_id`, `p_code`, `p_name`, `p_set_type`, `p_release_order`, `p_release_date`). `expansion_id` continua completamente fora da assinatura — só `code` ganhou uma via de correção, condicional:

- `code` normalizado para maiúsculas e validado no mesmo formato de `admin_create_card_set()` (`^[A-Z0-9][A-Z0-9._-]*$`).
- Só é efetivamente alterável enquanto o Card Set não tiver nenhuma `Card` cadastrada (ativa ou inativa — `EXISTS (SELECT 1 FROM card WHERE card_set_id = p_id)`); com pelo menos uma Card existente, tentar mudar o código falha com `ADMIN_UPDATE_CARD_SET_CODE_LOCKED`.
- Duplicidade dentro da mesma Expansion (`uq_card_set_expansion_code`) verificada explicitamente, excluindo a própria linha, só quando o código está de fato mudando (`ADMIN_UPDATE_CARD_SET_DUPLICATE_CODE`).

Como a assinatura muda, arquivo canônico (`database/schema/2048_...sql`, bump para v3.0) mais uma migration própria (`database/migrations/2091_widen_admin_update_card_set_function_for_code.sql`) para reconciliar o banco já instalado — mesmo padrão da Migration `2052`: `DROP FUNCTION` da assinatura de 5 parâmetros, depois `CREATE FUNCTION` da nova.

Frontend: `EditCardSetForm`/`EditCardSetDialog` (`card-set-dialogs.tsx`) ganharam o campo Código — editável quando `cardSet.cardsCatalogados === 0` (campo já existente em `CatalogoCardSetRow`, sem consulta nova), desabilitado com uma explicação inline quando há cartas cadastradas; a `DialogDescription` (antes só "{Jogo} · {Expansão} · {Código}", código sempre estático) passou a refletir o valor sendo digitado. `updateCardSet` (`card-sets/actions.ts`) envia o novo campo.

**Correção pontual da Coleção "151"**: como o Card Set em questão não tinha nenhuma Card cadastrada (`cards_count = 0`, verificado antes de qualquer alteração) e `MEW` não colidia com nenhum outro código já usado na Expansão `SV`, a correção foi aplicada diretamente no banco (`UPDATE card_set SET code = 'MEW' WHERE id = ...`, mesma condição que a função nova passou a impor) com uma linha correspondente gravada em `catalog_admin_action_log` (`actor_id NULL` — ação executada fora de uma sessão de aplicação, antes da Migration `2091` estar confirmada executada; `actor_id` é anulável por construção nesta tabela justamente para sobreviver a este tipo de caso). **Migration `2091` confirmada executada por Fabrício em 2026-08-01** — a partir de agora, qualquer futura correção de código passa a ir pela própria tela.

## Subciclo Card — Galeria de Cartas (leitura, 2026-07-31)

Pedido explícito de Fabrício: "vamos ao subciclo Card... precisamos caprichar no visual. A exibição das cartas é a funcionalidade que deve impressionar qualquer usuário visualmente" (referência: `tcg.pokemon.com/pt-br/galleries/scarlet-violet/`). Escopo desta rodada é **somente leitura/navegação** — a tela `/catalogo/cartas` (antes uma tabela simples por chips de código) foi reescrita como galeria visual completa: 3 Card Sets mais recentes em destaque (logo, em vez de indicadores numéricos), seletor "Coleção" para qualquer Set, busca por nome/número, filtros por raridade e categoria (checkboxes derivados das cartas do Set selecionado), grid de imagens ordenado por `collector_order`, efeito de hover "holográfico" (`HoloCard` — tilt 3D + brilho seguindo o cursor, CSS/JS puro, sem dependência nova) reaproveitado no grid e no modal de ampliação, numeração/nome/símbolo de raridade discretos abaixo de cada carta, paginação inicial (30 cartas) com botão "Ver todas".

**Nenhuma Query SQL nova foi necessária.** `card`, `card_asset`, `rarity`, `card_category` já tinham `SELECT` liberado para `authenticated` + `is_admin()` desde a Query `274` (ADR-022) — a mesma leitura que a tela anterior (`getCartasPorCardSet`) já fazia. O bucket de Storage `card-front` já é público (`Seed 895`, `is_public = TRUE`, diferente dos buckets de logo que são privados/assinados) — `getPublicUrl()` é usado em vez de `createSignedUrl()`, sem round-trip extra por imagem.

Decisões de implementação registradas aqui por não terem um critério objetivo único no pedido original:
- **Idioma da imagem**: prioridade `pt-BR` > `en` > qualquer idioma disponível (`IMAGE_LANGUAGE_PRIORITY`, `queries.ts`) — plataforma é pt-BR-first (`PRODUCT.md`), mas nem todo Card Set tem os dois idiomas importados (ver `06-pipeline-importacao.md`, "idioma é configuração fixa no código").
- **Tamanho de página inicial**: 30 cartas antes do botão "Ver todas" (`PAGE_SIZE`, `cartas-gallery.tsx`) — cobre ~5 linhas em telas largas sem sobrecarregar o primeiro carregamento de um Set grande (ME1 tem 198 cartas).
- **Símbolo de raridade**: `rarity.symbol_code` (Query 130) delega a conversão visual à aplicação — implementado com ícones já existentes de `lucide-react` (`Circle`/`Diamond`/`Star`), monocromático (`text-muted-foreground`, sem dourado real para `GOLD_DOUBLE_STAR`) — "bem discreta" foi lido como discrição de cor, não só de tamanho.

Arquivos novos: `components/catalogo/rarity-symbol.tsx`, `components/catalogo/holo-card.tsx` (+ estilos em `globals.css`), `components/catalogo/cartas-gallery.tsx`. `queries.ts`: `getCardSetOptions`/`CartaRow`/`getCartasPorCardSet` (só usados pela tela antiga) substituídos por `getCardSetsForCartas()` e `getCartasCompletas()`. `tsc --noEmit` confirmado limpo (mesma baseline de 10 erros pré-existentes em `lib/supabase/`, não relacionados). **Validação funcional pela tela ainda pendente de confirmação explícita de Fabrício.**

### Bug encontrado no primeiro teste real + ajustes de UX (2026-07-31, mesmo dia)

Fabrício testou a tela e reportou: "as cartas não [são] listadas, como esperado" (Card Set com cartas reais mostrando "Nenhuma carta catalogada"), além de três pedidos de ajuste visual.

**Causa raiz do bug — correção da afirmação acima ("Nenhuma Query SQL nova foi necessária").** Estava errada: `getCartasCompletas()` embute `card_asset(..., card_asset_type(code), ...)` para resolver qual ativo é a imagem `CARD_FRONT` principal — e `card_asset_type` é uma das 7 tabelas do Catálogo Editorial que a Query `274` (2026-07-26) deliberadamente deixou sem política de SELECT, por não ter, na época, nenhuma tela real que a consultasse. RLS bloqueia o embed aninhado silenciosamente: a query falha, `getCartasCompletas()` cai no `catch`-equivalente (`error || !data`) e retorna lista vazia — sem erro visível na tela, só o "Nenhuma carta catalogada" enganoso. Nova migration `2053_add_admin_select_policy_to_card_asset_type.sql`, mesmo padrão da `274` (uma política `USING (is_admin())` + `GRANT SELECT` para `authenticated`), SQL preparado, **aguardando execução por Fabrício via o ritual de pareamento** — a tela só listará cartas de fato depois disso.

**Três ajustes de UX, a partir do mesmo teste:**
1. Os 3 chips de Card Set mais recentes (antes blocos grandes `h-28`/`h-32`, `grid-cols-3` ocupando a largura da página) viraram uma barra fina de chips compactos (miniatura de 32px + nome) — "visual menos agressivo... não precisa ocupar a página inteira".
2. Um seletor "Outra coleção" (lista completa, agrupada por Jogo) foi adicionado na mesma barra dos chips, para saltar para qualquer Card Set sem depender do top 3.
3. Um seletor "Expansão" foi adicionado ao lado do seletor "Coleção", junto à busca — os dois sempre visíveis. "Expansão" não guarda estado próprio (é sempre derivado do Card Set selecionado, já que todo Card Set pertence a exatamente uma Expansão); trocá-lo navega para o Card Set mais recente daquela Expansão, e "Coleção" passa a listar só os Sets da Expansão atual — o "sincronismo" pedido.

`tsc --noEmit` confirmado limpo. Nenhuma mudança de schema além da Query `2053`.

### Query `2053` confirmada executada + modal de ampliação reduzido a só a imagem (2026-07-31, mesmo dia)

Fabrício executou a Query `2053` no Supabase Studio ("Success. No rows returned") — a galeria de Cartas passou a listar cartas de fato, encerrando o bug. Em seguida, primeiro elogio + um pedido pontual: "ficou espetacular... ao ampliar a carta, só quero enxergar a imagem da carta. Não preciso de nenhuma outra informação. É um modo onde o foco está única e exclusivamente na carta", com print comparando nosso modal (título, número, categoria, raridade visíveis) contra a referência oficial (só a carta, sem nenhum texto).

`CartaZoomDialog` reduzido ao essencial: removidos `DialogHeader`/título/número/categoria visíveis, a linha de raridade abaixo da carta e o botão de fechar (`hideClose`); o `DialogContent` teve fundo/borda/sombra do painel sobrepostos para transparente (só o `HoloCard` com a imagem flutua sobre o overlay escurecido, com sombra própria). Fecha por clique fora ou Esc — comportamento padrão do `Dialog`, preservado. `DialogTitle` continua presente para leitores de tela (`sr-only`, nunca visível) — Radix exige um nome acessível no `Dialog.Content`; removê-lo trocaria "sem informação visível" (o pedido) por "sem informação nenhuma" (acessibilidade quebrada), que não foi pedido. `tsc --noEmit` confirmado limpo.

### Animação idle flutuante no modal + carta maior (2026-07-31, mesmo dia)

Pedido de Fabrício, com dois prints do DevTools da referência oficial capturados em momentos diferentes (mesmos valores de `matrix3d(...)` levemente distintos entre um print e outro): "gostaria que essa carta ficasse com o efeito flutuando na tela... a carta fica se movendo lentamente mesmo sem que o mouse passe por ela. Além disso a imagem ampliada deve ser um pouco maior."

`HoloCard` ganhou uma prop `floating` (só usada por `CartaZoomDialog` — o grid continua estático em repouso, "flutuar" é destaque de uma carta por vez, não do grid inteiro): um loop `requestAnimationFrame` escreve continuamente em `rotateX`/`rotateY`/`translateY` usando três senoides com frequências e fases diferentes (evita um ciclo óbvio de "vai e volta", reproduzindo a deriva orgânica dos dois `matrix3d` capturados), pausado enquanto o mouse está sobre a carta — a interação do usuário sempre vence o automático, e ao tirar o mouse a animação retoma sozinha (sem saltar, a `transition` do CSS já existente suaviza) — e desligado por completo sob `prefers-reduced-motion: reduce`. Tamanho máximo da carta ampliada aumentado de `300px`/`340px` para `380px`/`460px` (mobile/desktop). `tsc --noEmit` confirmado limpo.

### Reformatação da identificação no grid + ampliação do mapa de símbolos de raridade (2026-07-31, mesmo dia)

Novo elogio de Fabrício ("Espetacular!") seguido de dois pedidos pontuais, com print de uma carta (Clefairy) como estava renderizada: (1) a identificação abaixo de cada carta do grid deve virar uma linha única no formato `#003/088 - Shaymim` (número, com o total quando existir, seguido do nome), com o símbolo de raridade numa linha própria logo abaixo — ambos alinhados à esquerda, substituindo o layout anterior (nome em uma linha, número/símbolo em `justify-between` na linha seguinte); (2) "os símbolos não estão exatamente como convencionado em nossa base. Exemplo: cartas do tipo Ilustração rara com símbolo círculo cinza".

O item (1) foi aplicado diretamente em `CartaGridCard` (`cartas-gallery.tsx`) — sem ambiguidade de critério.

O item (2) expôs uma lacuna, não um dado errado. `RaritySymbol` (`rarity-symbol.tsx`) nasceu na primeira rodada deste subciclo cobrindo só os 5 `symbol_code` citados como "Exemplos" no comentário da própria coluna (Query `130`) — `BLACK_CIRCLE`/`BLACK_DIAMOND`/`BLACK_STAR`/`BLACK_DOUBLE_STAR`/`GOLD_DOUBLE_STAR` —, e essa lista não é exaustiva: o seed real (`830_seed_rarity.sql`, Status `CANÔNICA`) usa nove códigos distintos em três famílias (`BLACK_*`, `SILVER_*`, `GOLD_*`, mais o caso isolado `MEGA_ATTACK` para `MEGA_ATTACK_RARE`). Todo `symbol_code` fora daqueles 5 caía no fallback genérico — um círculo cinza monocromático —, então raridades como `ILLUSTRATION_RARE` (`GOLD_STAR`), `SPECIAL_ILLUSTRATION_RARE` (`GOLD_DOUBLE_STAR`, já mapeado mas sem cor), `MEGA_HYPER_RARE` (`GOLD_DIAMOND`) e `ULTRA_RARE` (`SILVER_DOUBLE_STAR`) ficavam visualmente indistinguíveis entre si — plausivelmente exatamente o "círculo cinza" que Fabrício viu em uma carta Ilustração Rara.

`RaritySymbol` reescrito cobrindo os 9 `symbol_code` reais do seed `830`, com um esquema de cor em três tons reaproveitando tokens já existentes do Design System (não cores novas): `BLACK_*` → `text-foreground`, `SILVER_*` → `text-muted-foreground`, `GOLD_*` → `text-primary` (o dourado da marca). `MEGA_ATTACK` recebeu um ícone próprio (`Zap`, `lucide-react`) em tom dourado — não há símbolo oficial documentado para essa raridade em nenhuma fonte do projeto; escolha própria até surgir referência.

**Divergência sinalizada, não resolvida unilateralmente:** o seed `830` (CANÔNICA) mapeia `ILLUSTRATION_RARE` → `GOLD_STAR`, não a um código cinza/prateado. É plausível que o "círculo cinza" relatado por Fabrício fosse só o efeito do fallback genérico acima (agora corrigido — `GOLD_STAR` passa a renderizar em `text-primary`), mas também é possível que a convenção real da carta física seja outra (o TCG oficial usa uma estrela dourada única para Illustration Rare, o que bateria com `GOLD_STAR`) — este documento não assume qual das duas leituras está correta. Pendente confirmação explícita de Fabrício após ver o resultado na tela; se a convenção real divergir do seed, a correção é uma mudança de dado (`UPDATE rarity SET symbol_code = ...`), não de código.

`tsc --noEmit` confirmado limpo (mesma baseline de 10 erros pré-existentes em `lib/supabase/`).

### Transição de zoom com View Transitions API + dois ajustes pontuais (2026-07-31, mesmo dia)

Fabrício testou a tela novamente (print de uma carta Weedle real, Card Set com 86 cartas) e pediu três ajustes: (1) "quero mais fluidez no movimento de zoom ao clicar na imagem da carta... quero que o movimento pareça realmente uma ampliação da carta", rejeitando o zoom+fade genérico que salta direto para o tamanho final; (2) reduzir o espaço entre a identificação da carta e o símbolo de raridade, "achei muito distante"; (3) `collector_total` precisa de 3 dígitos em Card Sets pequenos — "001/086", não "001/86".

**Item 1 — morph de verdade via View Transitions API.** `document.startViewTransition()` (API nativa do navegador, sem dependência nova) substitui o zoom+fade padrão do `Dialog` só nesta tela: `CartaGridCard` e `CartaZoomDialog` passam a compartilhar o mesmo `viewTransitionName` (`carta-img-<id>`, via a nova prop `style` de `HoloCard`) — o navegador anima a miniatura do grid crescendo até virar a imagem ampliada, e o inverso ao fechar. Mecanismo: `runWithViewTransition()` (`cartas-gallery.tsx`) embrulha a troca de `zoomCarta` com `flushSync` dentro do callback do `startViewTransition`, exigido pela API para conseguir capturar o DOM "antigo" e o "novo" em dois instantes bem definidos. Como a mesma carta não pode ter o nome em dois elementos simultâneos (o grid continua montado atrás do modal), o card em processo de ampliação cede seu nome (`isZoomTarget` → `"none"`) exatamente quando o modal assume esse mesmo nome — sem essa cessão a API rejeitaria a transição por nome duplicado. `DialogContent` ganhou uma nova prop `animated` (default `true`, preserva todo Dialog existente) que desliga seu zoom+fade embutido (`animate-dialog-in`/`-out`) só quando a View Transitions API está disponível — sem suporte, ou sob `prefers-reduced-motion: reduce`, cai de volta para esse comportamento padrão, ainda curto o bastante. Nova regra `::view-transition-group(*)` em `globals.css` alinha a duração/curva do morph (420ms, `cubic-bezier(0.22, 1, 0.36, 1)`) com a mesma curva já usada em `.holo-card`.

**Item 2 — aplicado diretamente**: `space-y-1` → `space-y-0.5` entre a linha de identificação e `RaritySymbol`, em `CartaGridCard`.

**Item 3 — `collector_total` é `INTEGER`** (não `VARCHAR` como `collector_number`), perde zeros à esquerda no banco. Em vez de consultar `base_set_size` do Card Set (uma junção a mais), a exibição aplica `padStart(3, "0")` diretamente no valor — cobre exatamente o mesmo caso descrito por Fabrício ("set base inferior a 100 cartas"), já que sets com 100+ cartas já têm 3+ dígitos naturalmente.

`tsc --noEmit` confirmado limpo (mesma baseline de 10 erros pré-existentes em `lib/supabase/`).

### Correção: carta em transição aparecia atrás das vizinhas (2026-07-31, mesmo dia)

Fabrício reportou, com print capturando o meio da animação: "durante a transição a carta fica por trás das demais cartas. Só no estágio final ela aparece na frente."

**Causa raiz.** A implementação original dava `viewTransitionName` único a cada uma das ~122 cartas do grid, o tempo todo (só a carta-alvo cedia o próprio nome para o modal). A View Transitions API não distingue "elemento que de fato vai mudar de posição/tamanho" de "elemento que só por acaso tem um nome" — qualquer elemento com `view-transition-name` diferente de `none` no instante em que `document.startViewTransition()` é chamado é retirado do fluxo normal e repintado através da árvore de pseudo-elementos da transição (`::view-transition-group`), mesmo que sua geometria não mude. Como as ~122 cartas tinham nome simultaneamente, todas eram "hoistadas" junto — e a ordem de pintura entre esses grupos (baseada na ordem de descoberta na árvore, não em z-index) colocava vizinhas posteriores no DOM na frente da carta que estava de fato crescendo.

**Correção.** Nova regra: no máximo uma carta por vez pode ter um `viewTransitionName` não-`"none"` — todas as outras ficam permanentemente `"none"` (não fazem parte de nenhuma transição, nunca são hoistadas). Novo estado `transitionTargetId` (`cartas-gallery.tsx`) marca qual carta é a "fonte" no instante certo: um `flushSync` fora da transição atribui o nome à carta clicada ANTES de chamar `document.startViewTransition` (para existir no snapshot "antigo"); a própria transição então move esse nome da miniatura do grid para a imagem do modal (abrir) ou de volta (fechar), exatamente como antes — só que agora isolado a uma única carta por vez. `tsc --noEmit` confirmado limpo.

### Correção: espaço "solto" entre identificação e símbolo (2026-07-31, mesmo dia)

Fabrício ainda achou o símbolo distante da identificação: "prefiro mais compacto... da forma que está o símbolo parece solto na tela." A causa não era a margem entre os dois elementos (`space-y-0.5`, já pequena) — era o próprio `<span>` do `RaritySymbol`, que não define `line-height` próprio e por isso herda o line-height ambiente de onde é usado (bem maior que os 7px do ícone), deixando uma faixa de espaço em branco embutida em torno do símbolo mesmo sem nenhuma margem visível causando isso. Corrigido com `leading-none` no `RaritySymbol` (e no `<p>` de identificação, para simetria). `tsc --noEmit` confirmado limpo.

## Pendências / Próximos Passos

A leitura/galeria de Cartas está implementada, funcional (Query `2053` confirmada executada) e ajustada visualmente conforme três rounds de teste real de Fabrício — nenhuma pendência conhecida na experiência de leitura. Seguem pendentes, no escopo original do `ADR-023`: criação/edição administrativa de Card (reaproveitando `internal.write_card()`, Query `2030`) e desativação/reativação (reaproveitando `card.is_active`, Query `2020`) — únicos itens restantes antes do fechamento formal do ADR-023.

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
| 0.20 | **Correção de versão + descoberta de `PROMO` como raridade oficial.** O rótulo "Versão 2.0" usado na revisão 0.19 para `130`/`830`/`930` foi uma reconstrução própria, não o texto real — corrigido para `Versão 1.1`, com o texto verbatim fornecido por Fabrício (ordem de constraints em `130` ajustada; `830` reformatada; `930` ampliada de 7 para 12 subconsultas, incluindo verificação linha-a-linha contra valores canônicos esperados). Reexecução formal de `830`/`930` v1.1 como tal ainda não confirmada nesta revisão (os dados já batem via a Query temporária da revisão anterior). Nova descoberta: `PROMO` é uma raridade oficial do Pokémon TCG (não uma invenção do projeto), compartilha `symbol_code = BLACK_STAR` com `RARE` — confirma que `symbol_code` está corretamente fora da chave de unicidade. Nova ordem de exibição decidida (`PROMO` logo após `RARE`, display_order 4, demais deslocadas). Novo item arquitetural sinalizado para a futura Card: `card_set.set_type = PROMO` e `rarity.code = PROMO` são independentes e complementares. Sequência de atualização (`830`/`930` → v1.2, incluir `PROMO`; `130` inalterada) decidida por Fabrício, mas **ainda não escrita nem executada** — status da entidade revertido de "concluído" para "quase concluído, pendência final identificada". Definition of Done reaberta nos itens de seed/validação; Queries Associadas atualizadas. |
| 0.21 | **Entidade Rarity oficialmente encerrada.** `830`/`930` reescritas para v1.2 (incluindo a raridade `PROMO`, código `PROMO`, símbolo `BLACK_STAR` compartilhado com `RARE`, display_order 4) e executadas com sucesso — confirmado por Fabrício ("Tudo feito com sucesso. Vamos avançar!" / "Agora sim podemos dizer que a entidade Rarity está encerrada"). `130` permaneceu inalterada (v1.1), conforme decidido. Definition of Done totalmente concluída; status da entidade atualizado de "quase concluído" para "encerrada". Próxima etapa: modelagem conceitual de Card (ver revisão seguinte). |
| 0.22 | **Revisão arquitetural de Card iniciada (não concluída).** Fabrício confirmou que a identidade de Card é independente de Set ("representa a carta editorial de forma única, que pode aparecer em vários Sets") — inverte a premissa "Set + Número" usada no modelo mínimo anteriormente aprovado. `card_set_id`, `card_number`, `card_order` e `rarity_id` deslocam-se para uma futura `card_printing`, que passa a depender de dois pais (`card` e `card_set`). Seção Card marcada como "SUPERADO por revisão em andamento" no topo; conteúdo original preservado por rastreabilidade. Rascunho de nova forma para `card` (`id, game_id, name, category_code, editorial_key, created_at, updated_at`) documentado apenas em `04-domain-model.md` (não replicado aqui como proposta formal, já que a própria discussão termina sem resposta sobre quais atributos distinguem um design editorial de outro). Nenhuma DDL nova escrita. |
| 0.23 | **Card reverte para identidade Set-específica (decisão final) + nova entidade Card Category executada.** Fabrício reconsiderou a revisão 0.22: "Estou achando melhor considerar uma 'Card' como uma representação da carta dentro de um Set específico [...] Fiquei com receio do modelo anterior trazer dificuldades no cadastro". Nova seção **Card Category** criada do zero (mesmo padrão de Rarity), executada e confirmada no Supabase (`132`/`133`/`831`/`931`) com três valores reais: `POKEMON`, `TRAINER`, `ENERGY` — **`ENERGY` contradiz diretamente a "Decisão de Escopo — Cartas de Energia"** já registrada em `04-domain-model.md`; sinalizado com urgência na Seed, não resolvido unilateralmente. Seção Card atualizada: status muda de "SUPERADO" para "modelo final aprovado, ainda não executado"; conteúdo original (`card_number`/`card_order`/`category_code`) preservado por rastreabilidade; nova subseção "Modelo Final — Versão 1.0" com a forma aprovada (`id, card_set_id, rarity_id, category_id, collector_number, name, created_at, updated_at`), incluindo `collector_number` (renomeado de `card_number`), `name` armazenado como impresso, `category_id` como FK, `card_order` removido, `card_code` deliberadamente não persistido (derivado via VIEW, mesmo precedente de `secret_set_size`), e ponto de extensão futuro `card_relation` (reprints) registrado, não construído. Tensão não resolvida com AP-011 (Editorial Identity) sinalizada, não alterada. Arquivos `database/schema/132_*.sql`, `database/schema/133_*.sql`, `database/seeds/831_*.sql`, `database/validations/931_*.sql` criados com o texto verbatim executado. |
| 0.24 | **Card — Modelo Final refinado para Versão 1.1; SQL real de `140`/`141`/`940` recebida (execução não confirmada).** Validação campo-a-campo do modelo aprovado na revisão 0.23 levou a duas adições: `collector_total` (denominador da numeração impressa, ex. `182` em `021/182`, distinto de `card_set.total_set_size` pois seções especiais como `TG`/`GG` têm denominador próprio) e `collector_order` (reintroduzido — necessário para ordenar corretamente números não-numéricos como `TG01`/`SVP001`/`12a`). Decisão sobre idioma de `name`: Opção B confirmada — Card sempre guarda o nome no idioma da edição/Set em que foi cadastrada, sem camada de tradução própria (Fabrício: "a Card representa exatamente o catálogo daquele Set"). Nova regra de consistência de Game entre Card Set/Rarity/Card Category, implementada via trigger de validação (`141`) — primeiro uso desse padrão no projeto. SQL verbatim de `140`/`141`/`940` recebida e documentada, mas **não copiada para `database/`** (regra do `database/README.md`: arquivos só são copiados após execução confirmada — nenhuma confirmação explícita de sucesso foi recebida nesta revisão). Query `840 - Seed Card` permanece deliberadamente não escrita; PDF de referência de ME1 já estava arquivado de um ciclo anterior. Definition of Done e Queries Associadas reescritas para a Versão 1.1. |
| 0.25 | **`140`/`141` confirmados executados por inferência técnica; `840` v2.1 executada e confirmada por Fabrício — 859 Cards, 5 Card Sets (ME1–ME4).** Fabrício confirmou diretamente ("Executei com sucesso") a execução da Seed `840`, que insere 859 linhas em `card` e depende estruturalmente de `140`/`141` já existirem — logo ambas são tratadas como confirmadas por necessidade técnica direta, explicitamente documentada como inferência (não presunção), passível de correção. Mudança de arquitetura na Seed: uma única Query `840` canônica cobre todo o catálogo atualmente suportado (não uma Seed por Card Set) — generaliza o Princípio da Fonte Canônica de DDL/domínios para Seeds de dados de catálogo em massa; futuras expansões (ex. `ME5`) atualizarão a mesma Query `840`, não uma nova migration. `collector_total` derivado de `card_set.base_set_size`, aplicado a todas as cartas do Set incluindo as secretas (decisão editorial documentada explicitamente, já que os checklists não exibem o denominador para toda carta). Query envolvida em `BEGIN`/`COMMIT` com validação prévia (Game/Sets/categorias/raridades) e posterior (quantidade exata por Set e total 859), revertendo tudo em caso de divergência. **Discrepância `ENERGY` elevada de "valor de referência cadastrado" para "9 Cards reais, numeradas, em produção"** (1 em ME2, 2 em ME2.5, 3 em ME3, 3 em ME4) — sinalizada com força renovada, não resolvida unilateralmente. Query `940` reexecutada uma vez sobre os dados reais (resultados relatados: todos os 5 Sets `COMPLETE`, sem duplicidades/inconsistências) mas identificada como precisando de uma seção canônica explícita (5 Sets + total 859, no padrão já usado por `930` de Rarity) antes de ser copiada para `database/` — Fabrício confirmou a intenção de reescrevê-la, ainda não feito. Arquivos `database/schema/140_*.sql`, `database/schema/141_*.sql`, `database/seeds/840_seed_card.sql` (v2.1, texto verbatim completo) criados. Definition of Done e Queries Associadas atualizadas. |
| 0.26 | **Query `940` reescrita para Versão 2.0 (27 blocos), executada e confirmada — pacote técnico de Card tecnicamente completo.** Fabrício confirmou diretamente ("Pronto! Executado com sucesso.") a execução de `940` v2.0, que adiciona a seção canônica explícita antes ausente (CTE de quantidades esperadas por Card Set, total 859, continuidade de `collector_order`, aderência de `collector_total` ao `base_set_size`) às 18 checagens já existentes, mais duas novas (categorias/raridades não previstas). Arquivo `database/validations/940_validate_card.sql` criado. Com isso, `140`/`141`/`840`/`940` estão todos executados e confirmados — marco descrito pela sessão pareada como "o banco deixou de ser apenas uma estrutura de tabelas e passou a conter um catálogo editorial canônico completamente validado." **Ressalva registrada, não é o fechamento da entidade**: a discrepância `ENERGY` segue sem confirmação de Fabrício, e a própria sessão pareada corrigiu a si mesma — o bloco "Editorial Catalog" (100) ainda não está completo, falta modelar Card Variant (ou Finish/Card Finish) antes de avançar para Coleções (bloco 200). Nova seção "Finish (Acabamento) / Card Finish" atualizada com nota apontando a discussão iniciada (não concluída) em `04-domain-model.md`, incluindo a tensão de nomenclatura com ADR-010 (a proposta física usa "Card Variant"/`card_variant_type`, não "Finish"/"Card Finish"). Definition of Done e Queries Associadas atualizadas; próxima etapa apontada (`150`/`151`/`850`/`950` depois `160`/`161`/`860`/`960`). |
| 0.27 | **Nova entidade Card Variant Type — pacote técnico concluído e executado.** Seção "Finish (Acabamento) / Card Finish" substituída por "Card Variant Type (Tipo de Variante da Carta) / Finish (Acabamento)", com modelo físico completo (`150` v1.0: `id, game_id, code, name, description, display_order, created_at, updated_at`; `UNIQUE (game_id, code)`; `UNIQUE (game_id, display_order)`), trigger de `updated_at` (`151` v1.0) e seed canônico (`850` v1.1, seis tipos: `STANDARD`, `HOLO`, `REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `PROMO_STAMPED`) — todos confirmados por Fabrício. O tipo `HOLO` foi adicionado na revisão v1.1 do seed após Fabrício identificar sua ausência no catálogo inicial de cinco tipos; a Query `850` foi reescrita em vez de corrigida manualmente (Princípio da Fonte Canônica), usando um deslocamento temporário de `display_order` (`+1000`) para contornar a `UNIQUE` já ocupada pelos registros da v1.0. Query `950 - Validate Card Variant Type` (v1.1, 16 blocos) confirmada. Nova nota "Nomenclatura — tensão com ADR-010, ainda não resolvida": a execução real usa "Card Variant"/"Card Variant Type" de ponta a ponta, sem qualquer referência a "Finish" — reforça, sem resolver sozinha, a tensão já sinalizada em `04-domain-model.md`; decisão de Fabrício continua pendente. Nova seção-stub "Card Variant (Variante da Carta) / Card Finish" criada para o próximo bloco (`160`/`161`/`860`/`960`, associação Card ↔ Card Variant Type), bloqueada pela decisão de nomenclatura. Definition of Done de Card atualizada: item de "entidade Card Variant" refinado para deixar claro que Card Variant Type já está concluído — falta apenas a associação Card Variant. Arquivos `database/schema/150_*.sql`, `database/schema/151_*.sql`, `database/seeds/850_seed_card_variant_type.sql` (v1.1), `database/validations/950_validate_card_variant_type.sql` (v1.1) criados. |
| 0.28 | **Nova entidade Card Variant (estrutura) — executada; todo o Catálogo Editorial (`100`–`160`) estruturalmente modelado, falta apenas o Seed `860`.** Seção-stub "Card Variant (Variante da Carta) / Card Finish" substituída por conteúdo completo: modelo físico (`160` v1.0: `id, card_id, variant_type_id, variant_order, is_default, created_at, updated_at`; `UNIQUE (card_id, variant_type_id)`; `UNIQUE (card_id, variant_order)`; índice único parcial para no máximo uma variante padrão por Card), trigger de `updated_at` e trigger de consistência de Game entre Card e Card Variant Type (`161` v1.0, mesmo padrão de `141`), decisão de não persistir `variant_code` (derivável, mesmo precedente de `card_code`), e validação estrutural (`960` v1.0, 17 blocos — tabela vazia é esperado, Seed `860` ainda não existe). Nova seção "Seed 860 — planejado, ainda não construído": estratégia de fontes (checklist oficial + campo `variants` da TCGdex + Pokémon TCG API como evidência complementar + validação manual para variantes de Card Set específico e `PROMO_STAMPED`), carga faseada por Card Set (`860A`–`860E`) antes da consolidação canônica. Definition of Done e Queries Associadas de Card Variant Type atualizadas (item de nomenclatura reforçado com nova evidência: Card Variant Type e Card Variant, ambos executados, usam "Card Variant"). `docs/06-pipeline-importacao.md` atualizado com a seção "Primeira Aplicação Concreta — Seed de Card Variant" (revisão `0.4`), respondendo parcialmente o ponto em aberto sobre fontes externas, escopado apenas a esta entidade. Arquivos `database/schema/160_*.sql`, `database/schema/161_*.sql`, `database/validations/960_validate_card_variant_structure.sql` criados. |
| 0.29 | **Estratégia do Seed `860` refinada (nada executado; discrepância `ME5`/`ME0` sinalizada) + nova entidade Card Asset Type / Card Asset descoberta e discutida (`170`/`180`, aprovada, não executada).** Seção "Seed 860" ampliada com o processo por Card Set em cinco etapas, tratamento de casos seguros vs. especiais, regras de `variant_order`/`is_default`, e forma idempotente da carga (`ON CONFLICT ... DO UPDATE`); sinalizado que o plano de staging citou um `860F`/"`ME5`" inexistente no catálogo (Card Sets reais: `ME1`–`ME4` + promocional `ME0`, este último ainda sem Cards em `840`) — não resolvido, aguardando confirmação de Fabrício. Nova seção "Card Asset Type (Tipo de Ativo da Carta) / Card Asset (Ativo da Carta)": lacuna identificada por Fabrício (onde ficam as imagens das cartas, já que a ilustração é específica da Card) resolvida com a decisão de não colocar campos de imagem em `card`; entidade nomeada inicialmente "Card Image", generalizada para "Card Asset" (cobre qualquer ativo digital futuro, não só imagens); `card_asset_type` (catálogo semântico por Game) e `card_asset` (`card_id` obrigatório, `card_variant_id` opcional, `source_code` para procedência) com estrutura completa proposta. **Achado crítico, mesmo padrão do episódio Card Variant/Finish**: `card_asset`/`card_asset_type` já existem fisicamente entre as 17 tabelas pré-existentes (`06-pipeline-importacao.md`), e a proposta foi feita sem checar a estrutura real — sinalizado, precisa de verificação antes de `170`/`180` virarem DDL. Fabrício adiou o detalhamento fino desta entidade e de `language`/`card_external_reference`/`card_set_external_reference`. |
| 0.30 | **Estrutura física real de Card Asset confirmada (diverge da proposta em 3 pontos) + correção anunciada de Card Set (`ME0` → `MEP`, novo `MEE`).** Card Asset Type/Card Asset: `card_asset_type` bate exatamente com a proposta; `card_asset` real tem `id, card_id, asset_type_id, source_code, source_reference, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active, created_at, updated_at, language_id, storage_bucket_id` — sem `card_variant_id` (contradiz a proposta de asset específico por variante), `storage_bucket_id` (FK) no lugar de `storage_provider` (texto), e novo `language_id` (FK, possivelmente ligado a Card Translation), nenhuma divergência resolvida. Seção Card Set (Set/Card Set Promocional) recebeu nota de correção anunciada por Fabrício, SQL/migration ainda não recebida: código `ME0` estava errado, correto é `MEP`; novo Card Set oficial `MEE` ("Energy Set") criado, possivelmente relevante para a discrepância `ENERGY` já registrada. Nota `ME5`/`ME0` da seção Card Variant/Seed 860 corrigida. Nenhuma alteração em `database/`. |
| 0.31 | **Card Asset: relação com Card Variant descartada explicitamente + SQL recebida para `170`/`171`/`870`/`970`, execução não confirmada, 2 problemas identificados.** Fabrício: "Não pretendi representar com imagens as variações das cartas! A ilustração será representada de uma única forma" — confirmado que `card_asset` não se relaciona com `card_variant`, resolvendo/explicando a divergência de `card_variant_id` já confirmada como ausente na tabela física (era intencional). Novas regras: localização de arquivo (`storage_provider`/`storage_path`/`external_url`, reintroduzindo `storage_provider`, que segue divergindo de `storage_bucket_id` real), índice único parcial `uq_card_asset_one_primary`, integridade técnica, escopo inicial reduzido a `CARD_FRONT`. SQL verbatim recebida para `170`/`171`/`870`/`970` — sem confirmação de execução, não copiada para `database/`. Dois problemas: cabeçalhos fora do padrão STD-001 (Fabrício alertou sobre sinais de perda de contexto na sessão pareada a partir deste ponto) e bug no Seed `870` (código de Game `POKEMON_TCG`, inexistente — o real é `POKEMON`). Nota técnica: `card_asset_type` já existe fisicamente, então `170` como `CREATE TABLE IF NOT EXISTS` não adicionaria retroativamente as novas constraints. |
| 0.32 | **Card Asset Type — pacote técnico concluído e executado (`170`/`171`/`870`/`970`); bug de Game code previsto na revisão 0.31 confirmado na prática e corrigido; `180`/`181`/`980` (Card Asset) recebidas, execução não confirmada.** Fabrício tentou executar o `870` v1.0 original e obteve exatamente o erro previsto (`ERROR: P0001: Game with code POKEMON_TCG was not found`). Ciclo de correção: v1.1 corrigiu apenas idioma; v1.2 corrigiu código de Game (`POKEMON`) e idioma simultaneamente — executada com sucesso, assim como `970` v1.2 (marcador próprio de conclusão confirma a validação estrutural completa). `170`/`171` confirmadas por inferência técnica direta (mesmo padrão de `140`/`141`). Fabrício rejeitou a sugestão de adivinhar/inserir um novo código de Game; sessão pareada reconheceu o lapso de contexto e se comprometeu a validar nomes/códigos consolidados antes de cada nova Query. Arquivos `database/schema/170_*.sql`, `database/schema/171_*.sql`, `database/seeds/870_seed_card_asset_type.sql` (v1.2), `database/validations/970_validate_card_asset_type.sql` (v1.2) criados, cabeçalho reformatado para STD-001, comentários traduzidos. SQL de `180`/`181`/`980` regenerada, mas ainda sem confirmação de execução — mesmo problema de cabeçalho/`COMMENT ON` em inglês; não copiada para `database/`. |
| 0.33 | **Card Asset (`180`/`181`/`980` v1.1) confirmada executada — ressalva técnica importante sinalizada, não resolvida: `180` provavelmente não alterou a estrutura física real** (`CREATE TABLE IF NOT EXISTS` é no-op contra a tabela já existente com 20 colunas reais confirmadas; a `180` v1.1 propõe 19 colunas divergentes, com `storage_provider` em vez de `storage_bucket_id`/`language_id`). `181` genuinamente aplicada (trigger só depende de colunas reais). `980` é só `SELECT`s informativos, sem `RAISE EXCEPTION` — pergunta explícita deixada para Fabrício sobre os resultados reais dos blocos 2/3. Arquivos `database/schema/180_*.sql`, `database/schema/181_*.sql`, `database/validations/980_*.sql` criados (v1.1, cabeçalho já em STD-001). **Nova fase: `860`/`880` confirmadas como pendências finais do Catálogo Editorial, ordem `860` antes de `880`.** Metodologia da `860` mudada para Matriz Editorial explícita por coleção (construção → validação → geração do SQL → validação); Opção A (derivação por Rarity) rejeitada, Opção B (matriz explícita) adotada. Ordem canônica de `variant_order` (1–6) proposta, sinalizada como potencialmente conflitante com a regra de numeração local sem lacunas já registrada — não resolvido. Matriz ME1 consolidada analiticamente: 310 Card Variants esperados (111 `STANDARD`+77 `HOLO`+122 `REVERSE_HOLO`), nada executado. Escopo da `880` confirmado (`CARD_FRONT`, `card_id` direto), seis pontos em aberto. |
| 0.34 | **`860A` (ME1) e `860B` (ME2) executadas e confirmadas com resultado real batendo exatamente com o esperado — arquitetura da Query `860` homologada; ambiguidade de `variant_order` da revisão anterior RESOLVIDA; descoberta na ME2.5 força expansão de `card_variant_type` de 6 para 12 tipos.** `860A` v1.2: 310 Card Variants (111 `STANDARD`/77 `HOLO`/122 `REVERSE_HOLO`), conferido linha a linha. `860B` v1.0: 214 Card Variants (74 `STANDARD`/56 `HOLO`/84 `REVERSE_HOLO`), confirmado por Fabrício. Ambas no padrão homologado: bloco `DO $$` autocontido, matriz JSONB local, sem tabelas temporárias, validação pré-carga, convergência segura, carga idempotente, nove passos de validação pós-carga com rollback automático. Execuções reais confirmam `variant_order` local à Card (1, ou 1 e 2), nunca a posição global de `card_variant_type.display_order` — resolve a ambiguidade da revisão `0.33`. **Descoberta ME2.5**: reversa do conjunto base não segue padrão genérico — Poké Bola específica por linha evolutiva (Poké Ball/Love Ball/Friend Ball/Quick Ball/Dusk Ball), símbolo "R" para Equipe Rocket, reversa de Energia para não `ex`; sem `MASTER_BALL_REVERSE`. Catálogo de Card Variant Type expandido para 12 tipos (`850`/`950` v1.2), confirmado executado via captura de tela real. `860C` (ME2.5) ainda NÃO executada — matriz ainda não construída. Arquivos `database/seeds/860a_seed_card_variant_me1.sql`, `database/seeds/860b_seed_card_variant_me2.sql` criados; `850`/`950` sobrescritos para v1.2. |
| 0.35 | **Catálogo de Card Variant Type expandido de 12 para 13 tipos com a inclusão de `COSMOS_HOLO` (`850`/`950` v1.3, executadas e confirmadas); reconhecida — não modelada — a distinção entre acabamento físico e origem/distribuição de uma impressão; planejamento de `860C` (ME2.5) avançado.** Checklists editoriais oficiais (pkmn.gg) confirmaram que o acabamento "Cosmos Holo" é um padrão recorrente entre produtos promocionais distintos, não um caso isolado nem um `PROMO_STAMPED`. Avaliadas duas opções (tratar como origem de uma Card já existente vs. cadastrar como tipo físico próprio); adotada a segunda, restrita a este único tipo — outros acabamentos ainda sem evidência editorial confirmada (Galaxy Holo, Confetti Holo, Cracked Ice) permanecem fora do catálogo. Nova seção "Distinção Reconhecida — Acabamento vs. Origem de Distribuição": reconhece que `card_variant_type` deveria representar apenas o acabamento físico, com uma futura entidade de "Printing"/"Release" (ainda não modelada) cobrindo produto de distribuição, idioma, data e tiragem. `950` reescrita como bloco `DO $$` com `RAISE EXCEPTION`, substituindo o padrão anterior de `SELECT`s informativos. `860C`: distribuição final refinada e confirmada analiticamente — 613 Card Variants esperados (153 `STANDARD` + 142 `HOLO` + 38 `REVERSE_HOLO` + 140 `ENERGY_REVERSE` + 140 reversas de bola/Rocket), regra editorial por elegibilidade (`ex` vs. não-`ex`, Treinador/Energia, cartas secretas) confirmada, fonte TCGdex validada carta a carta — matriz ainda não construída, `860C` continua não executada. Arquivos `database/seeds/850_seed_card_variant_type.sql` e `database/validations/950_validate_card_variant_type.sql` sobrescritos para v1.3. |
| 0.36 | **Nomenclatura conceitual resolvida: Card Variant Type/Card Variant, revertendo Finish/Card Finish (ADR-016, reverte parcialmente ADR-010).** Fabrício avaliou que Card Variant Type/Card Variant deve prevalecer, por já ser o nome usado no banco, no pipeline de importação e na prática do projeto — sem que "Card Variant" esteja sendo usado para Full Art/Gold/Secret Rare (escopo já restrito por ADR-009). A separação de Rarity como atributo de primeira classe da Card, também decidida em ADR-010, permanece válida. Seção "Nota sobre nomenclatura — tensão com ADR-010" reescrita como "Nomenclatura — RESOLVIDA (ADR-016)". Cabeçalhos das seções ajustados para "Card Variant Type (Tipo de Variante da Carta)" e "Card Variant (Variante da Carta)", sem o sufixo "/Finish"/"/Card Finish". Definition of Done de ambas as entidades atualizada (item de nomenclatura marcado como concluído). Nenhuma alteração física necessária — `card_variant_type`/`card_variant` já usavam o nome agora canônico. |
| 0.37 | **`860C` (ME2.5) e `860D` (ME3) executadas e confirmadas — 630 e 203 Card Variants, respectivamente. Apenas `860E` (ME4) permanece pendente para o bloco "Editorial Catalog".** `860C`: a estimativa anterior (613, baseada apenas no checklist oficial PT-BR) foi superada pela matriz real (630) após Fabrício exportar manualmente em PDF a página completa do pkmn.gg (bloqueada para scraping automatizado, `403 Forbidden`), revelando 7 `COSMOS_HOLO` e 10 `PROMO_STAMPED` adicionais não capturados pela fonte original. `860D`: mesma arquitetura e mesma regra de exceção de `860B` (as 9 Cards Rara Dupla/`ex` do conjunto base não recebem `REVERSE_HOLO`), confirmada com Fabrício antes da geração. Ambas seguem a arquitetura homologada (matriz JSONB autocontida, validação de referências pré-carga, convergência segura via `+1000`, validação pós-carga por tipo com `RAISE EXCEPTION`/rollback). Arquivos `database/seeds/860c_seed_card_variant_me2_5.sql` e `database/seeds/860d_seed_card_variant_me3.sql` criados, verbatim. |
| 0.38 | **Marco: camada de Card Variant canonicamente encerrada.** `860E` (ME4) executada e confirmada — 198 Card Variants (64 `STANDARD`/58 `HOLO`/76 `REVERSE_HOLO`; 10 Cards Rara Dupla `ex` excluídas de `REVERSE_HOLO`, confirmando a exceção como editorial, não de contagem fixa). As cinco execuções por coleção (`860A`–`860E`) foram consolidadas em uma única Query canônica `860` (v1.0, CANÔNICA CONSOLIDADA): `v_set_catalog`+`v_matrix` JSONB, carga set-based via `jsonb_to_recordset`/`ON CONFLICT DO UPDATE` (substituindo o `FOR...LOOP` por coleção), 11 passos de validação — resultado real 859 Cards, 1.555 Card Variants. Os cinco arquivos intermediários removidos de `database/seeds/` com permissão de Fabrício (Princípio da Fonte Canônica). Query `960` reescrita para v2.0 (CANÔNICA): evoluída de validação puramente estrutural para validação completa pós-carga (estrutura + cobertura + distribuição editorial completa) — resultado real `covered_cards` 859/859, `registered_variants` 1.555/1.555, `default_variants` 859/859, `status` `COMPLETE`. Arquivo antigo `960_validate_card_variant_structure.sql` (v1.0) removido com permissão de Fabrício, substituído por `960_validate_card_variant.sql` (v2.0). Migrations canônicas da camada: `150`/`151`/`160`/`161`/`850` v1.3/`950`/`860` consolidada/`960` v2.0. Bloco "Editorial Catalog" (100) declarado integralmente concluído; próximo bloco confirmado: Card Asset (`170`/`171`/`870`/`180`/`181`/`880`/`980`), com o levantamento consolidado dos campos que a futura `880` deverá popular (`card_id, asset_type_id, source_code, source_reference, storage_provider, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active`) já registrado para o próximo ciclo. Definition of Done e Queries Associadas de Card Variant atualizadas. |
| 0.39 | **Planejamento da Query `880` avançado (regras, estratégia provável, 3 bloqueios identificados) e nova entidade `language` iniciada (retroativa) como pré-requisito.** Regras de integridade da `880` documentadas (Card/Asset Type obrigatórios, localização obrigatória, `asset_order > 0`, mesmo Game, sem duplicidade). Estratégia provável de preenchimento de campos externos documentada (URLs públicas, campos técnicos NULL quando não confirmados). Bloqueio 1 (fonte oficial de imagens — Pokémon TCG API vs. TCGdex, não decidido), Bloqueio 2 (identificador externo de Set/Card na fonte, não confirmado) e Bloqueio 3 (idioma da imagem) documentados. **Bloqueio 3 resolvido arquiteturalmente**: Fabrício, ao comparar duas imagens reais da mesma Card (`Rufflet`, ME2.5) em português e inglês, identificou que `card_asset` precisa de uma dimensão de idioma — mesma Card, mesmo Card Asset Type, duas representações linguísticas distintas (não duas Cards, não duas Card Variants, não dois Asset Types). Resolve também um item em aberto desde a revisão `0.30`: o `language_id` já presente na estrutura física real de `card_asset` (uma das 17 tabelas pré-existentes) finalmente tem propósito explicado — idioma do ativo digital, não tradução editorial nem idioma do exemplar físico. Nova entidade "Language" documentada: catálogo global (sem `game_id`), formato BCP 47, SQL de `190` recebida verbatim mas **execução NÃO confirmada** — sinalizado risco de no-op via `CREATE TABLE IF NOT EXISTS` contra estrutura física já existente, mesmo padrão que já ocorreu com `170`/`180`. Regra de unicidade de `card_asset` revisada para incluir `language_id`. Sequência planejada: `190`/`191`/`890`/`192` antes de `880`/`980` (nova versão). Nenhum arquivo copiado para `database/` (regra do `database/README.md`: só após execução confirmada). |
| 0.40 | **`190`/`191`/`192` (Language) confirmados executados; discrepância de numeração sinalizada (não resolvida).** `190 - Create Language Table` e `191 - Create Language Triggers` confirmados por Fabrício ("Executada com sucesso") — arquivos escritos em `database/schema/`. Antes de `890`, a sessão pareada revisou a constraint `ck_language_code_format` de `190` (BCP 47 completo, permissiva demais) e propôs simplificá-la para `xx`/`xx-YY`, viável sem impacto pois `language` ainda não tinha registros — executada como `192 - Refine Language Code Constraint`, confirmada, escrita em `database/migrations/` (mesma pasta de `122_adapt_card_set_for_promo.sql`). **Discrepância**: `192` havia sido descrita, em dois pontos desta mesma conversa, como a futura migration que adicionaria `language_id` a `card_asset` — na prática o número foi consumido pelo ajuste de constraint; a migration de `card_asset` ainda não tem número confirmado (provavelmente `193`, não confirmado) nem SQL recebida. Risco de no-op de `190` (sinalizado na revisão `0.39`) parcialmente mitigado por evidência indireta (a `192` alterou com sucesso uma constraint sobre a coluna `code`, sugerindo que a coluna existe conforme proposto) mas não definitivamente resolvido — nenhuma inspeção direta via Table Editor foi feita. `890 - Seed Language` iniciada (cabeçalho v1.0 recebido: pt-BR/en, idempotente via `ON CONFLICT (code)`), corpo completo ainda não fornecido. Seção "Language" e Queries Associadas de Card Asset atualizadas com o estado real. |
| 0.41 | **Camada Language integralmente executada e integrada a `card_asset`; discrepância de numeração RESOLVIDA (era `193`, como suposto); nova divergência sinalizada sobre `storage_provider`.** `890 - Seed Language` executada (pt-BR/en). `193 - Add Language to Card Asset` executada — adiciona `language_id` (FK, `NOT NULL`, registros antigos migrados para `pt-BR`), revisa unicidade para `card_id`+`asset_type_id`+`language_id`+`asset_order` (`uq_card_asset_card_type_language_order`) e ativo principal para `card_id`+`asset_type_id`+`language_id` (`ux_card_asset_primary_per_card_type_language`), removendo as constraints/índices antigos por introspecção de catálogo (sem depender de nomes conhecidos previamente) — confirma exatamente a estrutura já antecipada na revisão `0.39`. `194 - Govern Card Asset Storage Provider` executada — formaliza `storage_provider` como enumerador (`SUPABASE`/`S3`/`R2`/`LOCAL`/`EXTERNAL`) com `CHECK` de valores e de compatibilidade de localização; normaliza dados legados antes de aplicar as constraints. **Nova divergência não resolvida**: a validação de pré-requisito da `194` confirma programaticamente que `storage_provider` existe em `card_asset` e a execução teve sucesso — isso contradiz a "Estrutura Física Real" documentada na revisão `0.30`, que registrava `storage_bucket_id` no lugar de `storage_provider`. Sinalizado para nova inspeção via Table Editor, não resolvido unilateralmente. Seção "Card Asset" (regras de ativo principal/unicidade) e seção "Language" (Queries `890`/`193`/`194`, sequência, Status) atualizadas para refletir execução real. Arquivos `database/seeds/890_seed_language.sql`, `database/migrations/193_add_language_to_card_asset.sql`, `database/migrations/194_govern_card_asset_storage_provider.sql` criados. |
| 0.42 | **Fabrício enviou captura real do Table Editor de `card_asset` — contradiz a execução relatada da Query `194` e lança dúvida sobre `193`.** A tabela real mostra exatamente as mesmas 20 colunas já registradas na revisão `0.30` (`id, card_id, asset_type_id, source_code, source_reference, storage_path, external_url, mime_type, file_extension, file_size_bytes, width_pixels, height_pixels, checksum_sha256, is_primary, asset_order, is_active, created_at, updated_at, language_id, storage_bucket_id`) — **sem `storage_provider`**. Como o próprio pré-requisito da Query `194` exige essa coluna (via `information_schema.columns`) antes de prosseguir, e a Query foi relatada "Executada com sucesso"/"sem intercorrências", há uma contradição direta: ou a Query não foi de fato executada contra este banco, ou não foi executada como relatado. Rebaixada de "CONFIRMADO EXECUTADO" para "RELATADO EXECUTADO, CONTRADITO por evidência real" em toda a seção Card Asset/Language. Adicionalmente, a captura confirma que `language_id` já existia **antes** de `193` ser escrita (consistente com a listagem original da revisão `0.30`) — o passo de adicionar a coluna seria um no-op; as constraints que `193` alega ter criado não são verificáveis a partir de uma lista de colunas, então foram igualmente rebaixadas para "não confirmadas", por cautela, dado o padrão de discrepância já observado. Nenhum arquivo removido de `database/` — a decisão de manter, corrigir ou re-executar as migrations é de Fabrício, não resolvida unilateralmente. Recomendação registrada: confirmar contra qual projeto/schema Supabase `193`/`194` foram executadas antes de prosseguir com `880`. |
| 0.43 | **Arquitetura de armazenamento de imagens (Query `880`) planejada em detalhe — nenhuma SQL executada; dois riscos sinalizados por cross-check.** Decisões de design: Supabase Storage como provedor único; bucket público (não privado); PNG como formato mestre (não WebP); regra operacional de backup externo obrigatório para todo arquivo enviado ao Storage (não modelada em banco); convenção de caminho evoluída várias vezes até a forma `{expansion_code}/{card_number}.png` dentro de um bucket por tipo de ativo (`card-front`/`artwork`/`card-back`); nova coluna `storage_bucket` proposta e aprovada por Fabrício ("Vamos fazer essa mudança"), ainda sem SQL escrita. **Risco 1**: `storage_bucket` já é uma das 17 tabelas físicas pré-existentes do projeto (não detalhada até agora) e `card_asset.storage_bucket_id` (confirmado na captura de Table Editor da revisão `0.42`) é provavelmente sua FK — a proposta de uma coluna `storage_bucket` de texto livre arrisca duplicar essa entidade já existente, sem qualquer inspeção prévia (mesmo padrão de erro já visto com `card_asset_type`/`card_asset` nos batches 29-30, e possivelmente com `storage_provider` na revisão `0.42`). **Risco 2**: a convenção de caminho final, ao remover o idioma do caminho em favor de buckets por tipo de ativo, não contempla a dimensão de idioma já adotada em `card_asset` (`language_id`) — dois registros do mesmo Card + Asset Type em idiomas diferentes colidiriam no mesmo `storage_bucket`+`storage_path`. Nenhum dos dois riscos foi levantado por Fabrício ou pela sessão pareada; ambos sinalizados nesta revisão, não resolvidos unilateralmente. Fluxo de carga recomendado (bucket → upload de teste → validação → inserção manual → automação) documentado, ainda não iniciado. |
| 0.44 | **Marco: dúvida da revisão `0.42` sobre `193`/`194` RESOLVIDA por confirmação direta de Fabrício ("Houve execução real de 193 e 194."); Risco 1 da revisão `0.43` confirmado e resolvido — nova entidade `Storage Bucket` criada e homologada (`195`/`196`/`895`/`975`); Query `197` planejada (remove `storage_provider` de `card_asset`); nova discrepância de numeração sinalizada.** Toda a seção Card Asset/Language teve a linguagem de dúvida ("RELATADO EXECUTADO, CONTRADITO") revertida para "CONFIRMADO EXECUTADO" em `193`/`194`, com nota histórica preservando o registro da suspeita anterior. Nova entidade **Storage Bucket** (seção própria criada, mesmo padrão de `language`/`card_asset_type`): `id, code, name, description, storage_provider, bucket_order, is_public, is_active, created_at, updated_at` — catálogo inicial `card-front`/`artwork`/`card-back`, todos `SUPABASE`/público/ativo (`195`/`196`/`895` executadas). Nova decisão arquitetural: eliminar `storage_provider` de `card_asset` (redundante frente ao `storage_provider` já em `storage_bucket`) via migration planejada `197 - Add Storage Bucket to Card Asset` (aprovada por Fabrício "Vamos em frente", **ainda não escrita nem executada**) — modelo final de `card_asset` passaria a ter apenas `storage_bucket_id`+`storage_path`, provedor resolvido via `JOIN`. Formalizado novo padrão de processo: toda entidade de catálogo deve ter quatro migrations (Create/Trigger/Seed/Validate); aplicado retroativamente a Language (`970 - Validate Language`, nova, executada) e a Storage Bucket (`975 - Validate Storage Bucket` v1.1, com quatro testes controlados de rejeição). **⚠️ Nova discrepância de numeração, sinalizada e NÃO resolvida unilateralmente**: pelo padrão de deslocamento fixo já em uso no projeto (Validate = Create + 800), `970 - Validate Language` deveria ser `990` e `975 - Validate Storage Bucket` deveria ser `995` — em vez disso, `970` colide diretamente com a já existente e já executada `970 - Validate Card Asset Type` (duas Queries reais, distintas, ambas se autodenominando "Query 970"). Arquivos preservados com os números exatamente como executados no Supabase, sem renumeração retroativa; nota de numeração incluída nos próprios arquivos `.sql`. Risco 2 da revisão `0.43` (colisão de caminho por idioma) permanece **não resolvido**. Arquivos `database/schema/195_create_storage_bucket.sql`, `database/schema/196_create_storage_bucket_triggers.sql`, `database/seeds/895_seed_storage_bucket.sql`, `database/validations/970_validate_language.sql`, `database/validations/975_validate_storage_bucket.sql` criados. |
| 0.45 | **Marco: camada estrutural de Card Asset 100% concluída e validada.** A migration planejada `197 - Integrate Storage Bucket into Card Asset` foi escrita, executada e confirmada ("Success. No rows returned" / "a migração passou integralmente") — remove definitivamente `storage_provider` de `card_asset`, adiciona `storage_bucket_id NOT NULL` com FK para `storage_bucket`, remove triggers/constraints/índices antigos por introspecção, cria três novos índices e um novo trigger de validação (`trg_card_asset_validate_storage`/`validate_card_asset_storage()`) que verifica a coerência entre o provider do bucket e `storage_path`/`external_url`. `card_asset` passa de 20 para 19 colunas reais. Validação `980 - Validate Card Asset` reescrita para v2.0 (28 blocos, cobrindo toda a arquitetura pós-`language`/`storage_bucket`/`197`) — executada e declarada **HOMOLOGADA**; arquivo antigo `980_validate_card_asset_structure.sql` (v1.1) permanece no repositório por ora, superado, aguardando confirmação de Fabrício antes de ser removido. Bloqueios 1/2 (fonte de imagens, identificador externo) absorvidos por um novo Bloqueio 5: `880` não será mais um `INSERT` estático de URLs externas, mas um pipeline de importação automatizado — decisão explícita de Fabrício ("Gostaria de partir com a solução de executar uma rotina automática para internalizar as imagens no Supabase Storage [...] Garantimos que vamos trabalhar nesse item apenas uma vez"). Nova seção "Arquitetura de Importação de Ativos" documenta o desenho conceitual completo (nenhuma SQL executada): componentes propostos `asset_source`/`card_external_reference`/`asset_import_job`/`asset_import_item`, worker via Edge Function, nova convenção de caminho com idioma reintroduzido, regras de idempotência, notas de segurança e a ressalva de direitos de imagem. **Risco crítico de cross-check, sinalizado nesta revisão**: `asset_source` (nome idêntico) e `card_external_reference` já constam, desde um ciclo muito anterior (`06-pipeline-importacao.md`), como tabelas físicas pré-existentes nunca inspecionadas — junto com `asset_import_run`/`asset_import_failure`, que se sobrepõem em propósito aos novos `asset_import_job`/`asset_import_item` propostos. Mesmo padrão de erro já cometido três vezes neste projeto (propor estrutura nova sem checar a física real primeiro); recomendado inspecionar essas tabelas antes de qualquer SQL do pipeline. Observação adicional: `card_asset.source_code`/`source_reference` (já existentes, nunca usados) podem já resolver a necessidade de rastreabilidade de origem que a conversa cogitou modelar do zero. |
| 0.46 | **Correção de rota: `880` não é o próximo passo — camada estrutural do pipeline construída em etapas, começando por Asset Source (`200`/`201`/`900`/`985`, CONFIRMADOS EXECUTADOS).** Fabrício corrigiu a sequência antes prevista: Asset Source (concluída nesta revisão) → Card External Reference (`210`/`211`/`910`/`990`, planejada) → Asset Import Job/Item (`220`/`221`/`222`/`920`/`995`, planejada) → Edge Function + piloto controlado → só então `880` em escala. Nova entidade **Asset Source** (seção própria criada): `id, code, name, source_type, base_url, api_base_url, documentation_url, terms_url, attribution_text, supports_api, supports_bulk_download, is_active, source_order, created_at, updated_at` — catálogo inicial `POKEMON_TCG_API`/`TCGDEX`/`MANUAL`; trigger `protect_asset_source_identity()` introduz um novo padrão (mais rígido) de proteção de identidade via `RAISE EXCEPTION`. **Correção ao "Risco Crítico" da revisão `0.45`**: a guarda defensiva da própria Query `200` não disparou, provando que `asset_source` não existia no banco real conectado — contradizendo `06-pipeline-importacao.md`; risco permanece em aberto apenas para `asset_import_run`/`asset_import_failure`/`card_external_reference`/`card_set_external_reference`, ainda não inspecionadas. **Risco 2 (colisão de caminho por idioma, aberto desde a revisão `0.43`) formalmente RESOLVIDO**: convenção final definida como `Bucket: {type}` / `Path: pokemon/{collection-code}/{language-code}/{card-number}/front.png`, com idioma agrupado antes do número da Card (decisão explícita de Fabrício, com racional de exportação/backup/importação em lote/cache por idioma). **Nova discrepância de numeração sinalizada, NÃO resolvida unilateralmente**: `900 - Seed Asset Source` colide com a já existente `900 - Validate Game` — os dois esquemas de deslocamento fixo (`Create+700`/`Create+800`), aplicados a faixas de Create diferentes (`200` vs. `100`), convergem para o mesmo número. Registrado o princípio de projeto de Fabrício sobre internalização de imagens, e a nova convenção de processo (Seeds com comentários reduzidos; padrões consolidados reutilizados sem reexplicação). Arquivos `database/schema/200_create_asset_source.sql`, `database/schema/201_asset_source_triggers.sql`, `database/seeds/900_seed_asset_source.sql`, `database/validations/985_validate_asset_source.sql` criados. |
| 0.47 | **Camada Card External Reference criada, com triggers e homologada (`210`/`211`/`990`, CONFIRMADOS EXECUTADOS); Seed `910` deliberadamente descartada; Architecture Review substitui o modelo Asset Import Job/Item (planejado na revisão `0.46`) por um modelo híbrido `asset_import_run`/`asset_import_failure`, ainda sem SQL escrita.** Nova entidade **Card External Reference** (seção própria criada): `id, card_id, asset_source_id, external_card_id, external_set_id, source_number, source_url, image_source_url, metadata, is_active, created_at, updated_at` — FK para `card` (`ON DELETE CASCADE`) e `asset_source` (`ON DELETE RESTRICT`), unicidade dupla (`card_id`+`asset_source_id` e `asset_source_id`+`external_card_id`), mesmo padrão de triggers de `asset_source` (normalização, `updated_at`, proteção de identidade). A Seed `910` foi conscientemente descartada — sem correspondências reais confirmadas ainda, um `INSERT` estático seria dado inventado; os registros virão da própria rotina de importação. Antes de escrever `220`/`221`/`222` (Asset Import Job/Item), Fabrício solicitou um "Architecture Review" pela preocupação com o crescimento ilimitado de uma tabela de auditoria por Card processada (*"Imagine daqui a alguns anos [...] A tabela de Jobs pode facilmente crescer para centenas de milhares ou milhões de registros [...] Precisamos mesmo persistir todo esse histórico no banco principal? Talvez não."*) — revisão concluiu por um modelo híbrido `asset_import_run` (um registro por execução) + `asset_import_failure` (um registro só para falhas), descartando o registro por-Card-com-sucesso. Documentado o fluxo operacional completo em 9 etapas (seleção → execução → correspondência → download temporário → validação → upload → registro do ativo → tratamento de falha → encerramento). **Duas ressalvas sinalizadas, não resolvidas unilateralmente**: (a) `asset_import_run`/`asset_import_failure` são exatamente os nomes que `06-pipeline-importacao.md` registra como pré-existentes — mesmo padrão de risco já visto com `asset_source` (que a revisão `0.46` provou não pré-existir); recomendada a mesma guarda defensiva da Query `200` quando essas tabelas forem finalmente escritas; (b) o número `920`, reservado na revisão `0.46` para "Seed/Test Import Job", teria colidido com a já existente `920 - Validate Card Set` — colisão pega **antes** de qualquer SQL ser escrita com esse número, primeira vez que isso acontece neste projeto (as colisões de `970`/`900` só foram descobertas depois da execução). Arquivos `database/schema/210_create_card_external_reference.sql`, `database/schema/211_card_external_reference_triggers.sql`, `database/validations/990_validate_card_external_reference.sql` criados. |
| 0.48 | **`asset_import_run` criada, com triggers (`220`/`221`, CONFIRMADOS EXECUTADOS), seguindo exatamente a numeração recomendada na revisão `0.47`; episódio de correção `collection`→`card_set`; tentativa de generalização revertida por pedido direto de Fabrício; nova evidência (Table Editor) corrobora que `asset_import_run`/`asset_import_failure`/`card_set_external_reference` não são tabelas pré-existentes.** Estrutura final: `id, run_code, asset_source_id, card_set_id, language_id, run_type, status, execution_context, initiated_by, requested_count, processed_count, success_count, failed_count, skipped_count, parameters, error_summary, started_at, finished_at, created_at, updated_at` — `run_code` gerado por sequência dedicada (`RUN-{data}-{sequencial}`), `card_set_id`/`language_id` como FKs opcionais. Trigger `govern_asset_import_run()` introduz o padrão de governança mais sofisticado do projeto: bloqueio de alteração de escopo após `PENDING`, máquina de estados de status, preenchimento automático de `started_at`/`finished_at`, coerência entre status final e `failed_count`. **Episódio de correção**: a primeira versão da migration referenciava uma tabela `collection` inexistente — engano da sessão pareada por limitação de memória de conversa longa, autoidentificado e corrigido após Fabrício compartilhar uma captura real do Table Editor (`collection_id`→`card_set_id`, `FULL_COLLECTION`→`FULL_CARD_SET`); a execução incorreta falhou dentro do próprio bloco de validação, sem deixar nada inconsistente. **Tentativa de generalização revertida**: antes da correção, a sessão pareada propôs tornar `asset_import_run` totalmente agnóstica de domínio (mover `card_set_id`/`language_id` para dentro de `parameters`); Fabrício interrompeu diretamente ("Lembre que são conceitos distintos" — catálogo editorial vs. coleções do usuário), e a versão final manteve as FKs reais. **Nova evidência para o Risco Crítico das revisões `0.45`-`0.47`**: a captura do Table Editor mostrou as tabelas físicas então existentes (`asset_source`, `card`, `card_asset`, `card_asset_type`, `card_category`, `card_external_reference`, `card_set`, `card_variant`, `card_variant_type`, `expansion`, `game`, `language`, `rarity`, `storage_bucket`) — **sem `asset_import_run` (esperado, pré-`220`), sem `asset_import_failure` nem `card_set_external_reference`**, reforçando (mas não provando definitivamente, dado que a captura pode estar truncada) que a lista de "17 tabelas pré-existentes" de `06-pipeline-importacao.md` está desatualizada para estes casos, no mesmo padrão já confirmado para `asset_source`. `230`/`231` (Asset Import Failure) e `995` (Validate) permanecem não escritos. Arquivos `database/schema/220_create_asset_import_run.sql`, `database/schema/221_asset_import_run_triggers.sql` criados. |
| 0.49 | **Marco: infraestrutura de importação do catálogo editorial encerrada — `asset_import_failure` criada com triggers e a validação consolidada `995` executadas (`230`/`231`/`995`, CONFIRMADOS EXECUTADOS E HOMOLOGADOS); Bloqueio 5 formalmente RESOLVIDO; framing por "Bloqueios" numerados substituído por uma estrutura de Fases e Blocos após um incidente de confiança no roteiro.** `asset_import_failure` refinada de última hora, antes da execução: FK direta e obrigatória para `card_id` (não apenas um identificador externo solto), e `asset_source_id` deliberadamente omitido como coluna própria (resolvido via `JOIN` com `asset_import_run`, mesmo padrão de normalização já usado em `storage_bucket`/`card_asset`). `995` valida as duas tabelas da camada em conjunto (não uma validação por tabela). **Incidente de confiança no roteiro**: Fabrício expressou preocupação direta e legítima de que a sessão pareada tivesse perdido o fio do roadmap combinado anteriormente (*"Estou achando que você se perdeu na sequência do trabalho e isso me deixa verdadeiramente preocupado [...]"*); a resposta comparou lado a lado o roadmap original (`220`/`221`/`222`/`920`/`995`, nomeado "Asset Import Job/Item") com o implementado (`220`/`221`/`230`/`231`/`995`, "Asset Import Run/Failure"), demonstrando que a sequência foi deliberadamente evoluída, não perdida — mas reconheceu a causa raiz: ausência de um registro mestre do roadmap, dependência excessiva da memória de conversa (que é resumida, não literal, em conversas longas). **Nova estrutura registrada**: FASE 1 — Catálogo Editorial (Bloco A — Modelo de Dados, **concluído**; Bloco B — Pipeline de Importação, **ainda não iniciado**, é o próximo trabalho — a Edge Function que efetivamente executa o fluxo; Bloco C — Carga Editorial, **ainda não iniciado**, `880` torna-se uma orquestração do importador, não um `INSERT`) → FASE 2 — Coleções (não iniciada, aguarda Fase 1 completa). Corrigido `docs/README.md`: a tabela "Status Atual do Projeto" citava `asset_source`/`asset_import_run`/`asset_import_failure` como parte das "17 tabelas físicas pré-existentes" — mas as três foram demonstravelmente criadas por este próprio projeto (guardas defensivas de `200`/`220`/`230`, mais a evidência do Table Editor da revisão `0.48`); tabela reformulada para refletir isso. Arquivos `database/schema/230_create_asset_import_failure.sql`, `database/schema/231_asset_import_failure_triggers.sql`, `database/validations/995_validate_asset_import_infrastructure.sql` criados. |
| 0.50 | **Bloco B (Pipeline de Importação) iniciado: arquitetura completa da Edge Function `import-card-assets` especificada e roteiro de 12 sprints (`B2.1`–`B2.12`) definido — detalhamento movido para `06-pipeline-importacao.md` para evitar duplicação com este documento (que permanece focado em modelo de dados/SQL).** Atualizada a entrada de "Bloco B" no "Roteiro Consolidado — Fases e Blocos": status muda de "ainda não iniciado" para "iniciado", com cross-referência à nova seção "Arquitetura de Execução — Edge Function `import-card-assets` (Bloco B1)" de `06-pipeline-importacao.md`. Sprint B2.1 (Edge Function básica, apenas resposta `status: ready`) teve código proposto por Fabrício, mas **nenhuma confirmação de deploy foi recebida nesta revisão** — não é tratado como executado, seguindo o mesmo princípio de `database/README.md` (nada é registrado como concluído sem confirmação real). Sprint B2.2 (ler `asset_import_run` por `run_id`) apenas com objetivo definido. Nenhuma alteração de modelo de dados/SQL nesta revisão. |
| 0.51 | **Bloco A reaberto pontualmente: nova entidade `card_set_external_reference` criada (`240` CONFIRMADA EXECUTADA; `241`/`910`/`991` planejadas, ainda não executadas).** Lacuna real identificada durante o Sprint B2.5 de `06-pipeline-importacao.md`: o pipeline precisa saber qual identificador a TCGdex usa para um `card_set` antes de poder consultá-lo, exatamente como `card_external_reference` já resolve para `card` — decisão explícita de Fabrício de manter a consistência do modelo em vez de improvisar o mapeamento dentro da Edge Function. Nova entidade **Card Set External Reference** (seção própria criada, entre "Card External Reference" e "Collection Item"): `id, card_set_id, asset_source_id, external_set_id, source_url, metadata, is_active, created_at, updated_at` — **deliberadamente não é uma cópia 1:1 de `card_external_reference`**: sem `external_card_id` (não se aplica a Set) e sem `image_source_url` (o Pipeline Automático de Imagens baixa imagens de cartas, não de Sets — o logo/símbolo do Set já é coberto por colunas próprias de `card_set`, fora deste pipeline). FK para `card_set` (`ON DELETE CASCADE`) e `asset_source` (`ON DELETE RESTRICT`), unicidade dupla (`card_set_id`+`asset_source_id` e `asset_source_id`+`external_set_id`), RLS habilitado. Apenas três índices nesta primeira versão (`card_set`, `asset_source`, `active`) — triggers de normalização/`updated_at`/proteção de identidade ficam para a Query `241`, ainda não escrita. Seed `910` já decidida como descartada (mesmo racional de `910 - Seed Card External Reference`: sem correspondências reais ainda, registros virão da própria importação) — número citado colide com `910 - Validate Expansion`, mesmo padrão de colisão de numeração entre pastas já registrado para `900`/`970`/`975`, não resolvido unilateralmente. "Bloco A" no "Roteiro Consolidado" atualizado para refletir esta adição pontual pós-conclusão. Arquivo `database/schema/240_create_card_set_external_reference.sql` criado. |
| 0.52 | **`card_set_external_reference`: Query `241` (triggers) CONFIRMADA EXECUTADA; episódio real de correção — mapeamento de teste `ME0`→`sv10pt5` inserido e removido; Seed `910` adiada (não descartada), aguardando descoberta real via TCGdex em vez de suposição manual.** Ao validar `241`, um registro de teste foi inserido associando `ME0` (convenção interna do Project Mimikyu para promos da expansão Megaevolution) ao Set oficial real `sv10pt5` da TCGdex — identificado como incorreto (`ME0` não existe oficialmente na TCGdex/Pokémon TCG API) e removido via `DELETE`, confirmado. Plano inicial de popular `910` manualmente com `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` (excluindo `ME0` permanentemente) foi revisado antes de qualquer Seed ser escrita: `ME0` provavelmente tem sim um mapeamento oficial na TCGdex (um Set promocional específico), só não deve ser presumido sem validar — decisão final: `910` fica adiada até a Edge Function conseguir descobrir os `external_set_id` reais via chamada real à API; a Seed só será escrita depois, com dados confirmados. Critérios da futura Query `991` (Validação) já decididos: sem mapeamentos duplicados, FKs válidas, todo `card_set` `REGULAR`/`SPECIAL` com mapeamento ativo, `PROMO` pode ficar sem. Arquivo `database/schema/241_card_set_external_reference_triggers.sql` criado. |
| 0.53 | Cross-referência pontual: o plano para descobrir os `external_set_id` reais da TCGdex (necessário para finalmente escrever a Seed `910`, adiada) passou a ser um script administrativo standalone (`scripts/discover-tcgdex-sets.ts`), não uma nova migration nem uma Edge Function — detalhado em `06-pipeline-importacao.md`, "Sprint B2.5A", não duplicado aqui. Nenhuma alteração de modelo de dados/SQL nesta revisão. |
| 0.54 | **Query `910` — Seed Card Set External Reference — CONFIRMADA EXECUTADA (parcial), depois que os `external_set_id` reais foram descobertos por chamada real à TCGdex.** `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` mapeados e confirmados via consulta real de validação. `ME0` deliberadamente excluído — decisão de negócio sobre `mee`/"Mega Evolution Energy" continua aberta. `ME5` investigado e explicado (não é falha): `card_set.code = 'ME5'` ainda não existe fisicamente no banco, confirmado por consulta direta; a Query (idempotente, `ON CONFLICT DO UPDATE`) simplesmente não encontrou correspondência e seguirá funcionando quando `ME5` for cadastrado, sem precisar ser reescrita. Arquivo `database/seeds/910_seed_card_set_external_reference.sql` criado. Sequência (local e consolidada) atualizada de "ADIADA" para "CONFIRMADA EXECUTADA — PARCIAL". |
| 0.55 | **Marco real: Migration `251` — remoção definitiva de `ME0` de `card_set`, resolvendo a pendência "`ME0`↔`mee`" aberta desde a revisão `0.17` de `06-pipeline-importacao.md`.** Descoberto durante teste real da Edge Function `import-card-assets` (Sprint B3.7): uma execução de teste apontava para `ME0`, retornando corretamente `CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND`. Fabrício esclareceu, com conhecimento direto do domínio, que `ME0` (interno, cartas promocionais de Mega Evolução) e `mee` (TCGdex, cartas de Energia de Mega Evolução) são coleções diferentes, sem relação — decisão: remover `ME0` de `card_set` por completo, não apenas deixá-la sem mapeamento. Pré-checagem real confirmou dependências seguras (`card`: 0, `asset_import_run`: 1, `card_set_external_reference`: 0); migration `251_remove_me0` criada e aplicada via `npx supabase db push`; validação real pós-execução confirmou apenas `ME1`–`ME4`/`ME2.5` remanescentes e a execução de teste removida. Nova seção "Migration `251`" adicionada à seção Card Set/Set; pendência nova registrada (Query `820` v2.0 ainda inclui `ME0`, precisa ser reescrita para não reintroduzi-la em instalação nova); Query `910` e "Sequência" atualizadas para refletir a resolução. |
| 0.56 | **Reconfirmação real, Sprint B3.11 de `06-pipeline-importacao.md`: a sessão pareada momentaneamente tratou `card`/`card_variant` como vazias, a preencher pela TCGdex — Fabrício corrigiu, lembrando que os 859 Cards/1.555 Card Variants já estavam carregados (marco fechado há dezenas de batches, seção "Card Variant" acima).** Duas queries de auditoria real (`SELECT * FROM public.card`/`public.card_variant`) confirmaram, sem divergência, os totais e a estrutura de colunas exatamente como já documentado (sem colunas denormalizadas). Decisão real resultante: `import-card-assets` passa a **consultar** `card` (nunca inserir); `card`/`card_variant` permanecem congeladas, fora do escopo do Bloco B. Nota adicionada ao final da seção Card Variant. Nenhuma alteração de schema/SQL nesta revisão. |
| 0.57 | **Encontrado o identificador oficial real do Set promocional removido pela Migration `251`: `MEP` ("Mega Evolution Black Star Promos", TCGdex `mep`), não relacionado a `mee` (Energia).** Investigação real (TCGdex, TCGCodex, fontes de referência da comunidade) confirmou que `MEP` é um Set irmão de `ME1`-`ME4` dentro da Expansion `ME`, cobrindo cartas promocionais de toda a era (evidenciado por cartas `MEP` referenciando Pokémon exclusivos de coleções posteriores). O mecanismo geral de `ADR-015` (Set `PROMO`, sem entidade separada) permanece correto — o erro real estava apenas na convenção de código sintético ("Expansion + `0`"). Nova seção "Investigação de acompanhamento" adicionada à "Migration `251`"; `ADR-015` revisado (`1.4`); novo `AP-018` criado em `02-architecture-principles.md`. Recadastro de `MEP` planejado para um ciclo futuro, **NÃO executado nesta revisão**. Questão real, explicitamente em aberto: se `Expansion` modela corretamente o conceito de "Series"/"Era" dos catálogos oficiais — Fabrício optou por investigar antes de qualquer mudança no banco. |
| 0.58 | **Duas decisões reais novas, nenhuma ainda executada**: (1) `MEE` (Set de Energias da TCGdex) também será cadastrado — Fabrício reavaliou e decidiu completar o catálogo integralmente ("a única pergunta é: foi oficialmente publicada?"), Expansion `ME` terá 7 Card Sets no total (`ME1`-`ME4`/`ME2.5`/`MEP`/`MEE`); (2) nova convenção de `release_order` quando existem Sets especiais: Energia primeiro (`1`), Promocional em seguida (`2`), regulares depois — refina a convenção de `ADR-015` (revisão `1.5`). **Questão sobre `Expansion`/"Series"/"Era" (revisão `0.57`) RESOLVIDA por decisão direta de Fabrício, sem necessidade de investigação**: "Na modelagem não alteramos a tabela expansion. Desconsidere qualquer informação sobre as possíveis entidades 'Series e Era'." Nenhuma mudança de schema. Plano completo de execução (auditoria estrutural → ajustar `release_order` → inserir `MEE`/`MEP` → referências externas → cartas/variantes → imagens → checklist de integridade) registrado, nada executado nesta revisão. |
| 0.59 | **Primeiros dois passos do plano da revisão `0.58` executados: Migrations `263`/`264` (CONFIRMADAS EXECUTADAS) — domínio de `set_type` ampliado para incluir `ENERGY`, `release_order` de `ME1`-`ME4` reorganizado (`3`-`7`), liberando `1`/`2` para `MEE`/`MEP`.** Antes de qualquer alteração, auditoria estrutural real confirmou duas constraints já documentadas (`uq_card_set_expansion_release_order`, `uq_card_set_expansion_code`) e a definição exata de `ck_card_set_type` — mesma disciplina de "auditar antes de alterar" já usada na Migration `251`. Nova seção "Migration `263`–`264`" adicionada à seção Set/Card Set. `120` (canônica) bumped para `v2.1`, já incluindo `ENERGY` nativamente. **Decisão consciente de não refatorar `set_type`/`ck_card_set_type` em duas dimensões (natureza editorial vs. natureza do conteúdo) nesta fase** — cogitada durante a auditoria, deliberadamente adiada por Fabrício, registrada como possível ADR futura. `MEE`/`MEP` **ainda não cadastrados** — Fabrício optou por confirmar dados editoriais oficiais reais antes do `INSERT`, mesmo princípio já aplicado à correção `ME0`→`MEP` (`AP-018`). Arquivos `database/migrations/263_add_energy_to_card_set_type.sql` e `database/migrations/264_reorganize_me_release_order.sql` criados. |
| 0.60 | **`MEE`/`MEP` CONFIRMADOS EXECUTADOS (Migrations `265`–`268`), completando os passos 1-5 do plano da revisão `0.58`.** Antes de qualquer `INSERT`, Diagnósticos `07`/`08` confirmaram que `asset_source`/`card_set_external_reference` já suportam múltiplas fontes editoriais sem qualquer mudança de schema. Um erro real (`column cser.external_code does not exist` — a coluna real é `external_set_id`) motivou uma nova disciplina permanente: consultar a estrutura real de uma tabela antes de escrever qualquer SQL contra ela. `MEP` confirmado via pesquisa real na TCGdex (`mep`, "MEP Black Star Promos", `2025-09-26`, `60` cartas registradas — contagem real via `cardCount.total`, corrigindo uma estimativa inicial de `52`, diferente também do maior `localId` impresso, `080`, que tem lacunas de numeração). `MEE` cadastrado com dados de fontes oficiais da Pokémon (sem equivalente na TCGdex) — `card_set_external_reference` de `MEE` deliberadamente **não criada** (comportamento intencional da arquitetura: existência editorial independe de referência externa confirmada). Nova seção "Migration `265`–`268`" adicionada à seção Set/Card Set; "Sequência" de "Card Set External Reference" atualizada com `268`. **`AP-018` estendido (revisão `1.8`) para cobrir também `name`, não apenas `code`** — nasceu da correção real do nome de `MEP` (de uma tradução criada durante o cadastro para o nome oficial exato da TCGdex). **Discrepância real sinalizada, não resolvida**: os nomes já cadastrados de `ME1`-`ME4`/`ME2.5` estão em português, o que esse princípio classificaria como não-conforme se aplicado retroativamente — decisão de renomear ou não cabe a Fabrício. Esclarecida a semântica de `ck_card_set_promo_size` para Sets evolutivos (`base_set_size`/`total_set_size` = fotografia da contagem conhecida no momento, não um conjunto fechado) — nova regra operacional (atualizar a cada nova carta catalogada) ainda não formalizada em `operations/`. Arquivos `database/migrations/265_create_card_set_mee.sql`, `266_create_card_set_mep.sql`, `267_fix_card_set_mep_size.sql`, `268_create_card_set_external_reference_mep.sql` criados. |
| 0.61 | **Migrations `269`–`271` (CONFIRMADAS EXECUTADAS): `metadata` de `card_set_external_reference` padronizada para `{}` (incluindo `MEP`, corrigindo uma inconsistência real notada por Fabrício), referência externa de `MEE` confirmada (TCGdex, `mee`), e data de lançamento de `MEE` corrigida para `2025-09-25` (conforme TCGdex).** Nova regra permanente adotada e formalizada em `STD-001-database-standards.md` (revisão `1.14`): `metadata` nunca deve duplicar um atributo já coberto por coluna relacional. Camada `Expansion → Card Set → Card Set External Reference` concluída para `MEE`/`MEP`. Antes de qualquer `INSERT` em `card`, a estrutura real da tabela foi auditada (Diagnósticos `09`/`10`) — mesma disciplina "estrutura antes de SQL" do batch anterior. **Plano definido, ainda NÃO executado**: evoluir a Query canônica `840 - Seed Card` de `v2.1` para `v2.2`, adicionando as `8` cartas de `MEE` e as `60` cartas de `MEP` preservando integralmente `ME1`-`ME4`/`ME2.5` — decisão consciente de reaproveitar/evoluir a Seed existente (preservando seu histórico de versões) em vez de recriá-la, e de não criar uma Seed complementar (`841`). Arquivos `database/migrations/269_fix_card_set_external_reference_mep_metadata.sql` e `270_create_card_set_external_reference_mee.sql` e `271_fix_card_set_mee_release_date.sql` criados. |
| 0.62 | **Marco: Query `840` evoluída de `v2.1` para `v2.2` e Query `940` de `v2.0` para `v2.1`, AMBAS CONFIRMADAS EXECUTADAS ("Já executei as duas queries. Sem erros!") — catálogo `card` passa de 859 para 927 Cards, cobrindo agora as sete Card Sets da Expansion `ME` (`MEE`/`MEP`/`ME1`-`ME4`/`ME2.5`).** `840` v2.2 preservou integralmente a base ME1-ME4/ME2.5 e acrescentou as 8 Cards de `MEE` (categoria `ENERGY`, raridade `PROMO`) e as 60 Cards de `MEP` (raridade `PROMO`, `collector_number` preservando lacunas promocionais reais enquanto `collector_order` permanece contínuo 1-60); validações interna e final passaram a exigir os sete Sets e 927 Cards. `940` v2.1 foi sincronizada, passando de 27 para 31 blocos — dois blocos novos de raridade/categoria (`PROMO` obrigatório em MEE/MEP; `ENERGY` obrigatório em MEE) e dois blocos novos de checklist explícito (`collector_number`/`collector_order` esperados de MEE e de MEP, incluindo a lacuna `046`-`063` do MEP). Discrepância `ENERGY` (seção Card Category) agora soma 17 Cards reais (9 anteriores + 8 de MEE), reforçando o sinalizador já registrado, ainda não resolvido. Arquivos `database/seeds/840_seed_card.sql` e `database/validations/940_validate_card.sql` sobrescritos em vigor (Princípio da Fonte Canônica). **Plano definido, ainda NÃO executado, para o próximo ciclo**: estender `Card Variant` a `MEE`/`MEP` via nova série `860A`(`MEE`)-`860B`(`MEP`)-`860C`(`ME1`, renomeada da atual `860A`)-`860G`(`ME4`) + `960`, ordem cronológica dos Card Sets — ver seção "Card Variant", "Próximo passo planejado". |
| 0.63 | **Marco: `860A - Seed Card Variant MEE` e `860B - Seed Card Variant MEP` (ambas v1.0, CANÔNICA) e `960 - Validate Card Variant` v2.1, TODAS CONFIRMADAS EXECUTADAS — Card Variant agora cobre as 7 Card Sets: 927 Cards, 1.653 Card Variants, status COMPLETE.** O plano da revisão `0.62` de renomear a antiga `860A` (ME1) para `860C` foi **explicitamente abandonado por Fabrício antes de qualquer execução** ("criaria trabalho documental sem benefício... Mantemos os nomes atuais das Queries existentes e atribuímos um código novo apenas para o MEE e o MEP") — `860_seed_card_variant.sql` permanece intocado; apenas `860A`/`860B` (letras reaproveitadas para MEE/MEP, sem colisão real de arquivo, já que o `860A`/`860B` históricos de ME1/ME2 haviam sido removidos há dezenas de batches) foram criados. Nova disciplina adotada a partir de um erro real capturado antes da execução: a primeira versão de `860A` assumiu 8 variantes (1 por Card) quando o real, confirmado por pesquisa, era 16 (2 por Card — `STANDARD`+`REVERSE_HOLO`); versão incorreta descartada sem executar. Regra permanente adotada: pesquisar → consolidar matriz → só então gerar a Query. `860B` (MEP) usou correspondência estrita por `collector_number` contra `840` (não por posição/contagem), descartando promoções do arquivo de referência ainda não cadastradas; duas regras de negócio novas para promos: `JUMBO` desconsiderado, qualquer `STAMPED` consolidado em `PROMO_STAMPED` existente (sem criar tipos novos). Resultados reais: `860A` 16 Card Variants (8 `STANDARD`/8 `REVERSE_HOLO`); `860B` 82 Card Variants (59 `HOLO`/23 `PROMO_STAMPED`); `960` v2.1 `covered_cards` 927/927, `registered_variants` 1.653/1.653, `default_variants` 927/927, `status COMPLETE`. Confirmado explicitamente que `ME1`-`ME4`/`ME2.5` **não precisaram ser recarregadas** (840 v2.2 idempotente, nenhuma regra de `card_variant` alterada). Arquivos `database/seeds/860a_seed_card_variant_mee.sql`, `database/seeds/860b_seed_card_variant_mep.sql` criados; `database/validations/960_validate_card_variant.sql` sobrescrito em vigor (v2.0 → v2.1). Ressalva mantida por Fabrício: isso **não** encerra a fundação do Catálogo Editorial — falta a carga/validação de imagens para MEE/MEP. |
| 0.64 | Adicionada nota "Próximo passo real" à seção Card Asset, reafirmando que o caminho para as imagens de `MEE`/`MEP` é o pipeline real já confirmado (`import-card-assets`/`ADR-018`), não as duas propostas alternativas surgidas em uma sessão pareada que, segundo Fabrício, passou a propor soluções incompatíveis com a arquitetura vigente após perda de contexto operacional. Nenhuma das duas propostas (colunas de imagem em `card`; Seed estática de `card_external_reference`/`card_asset`) foi incorporada — a primeira colide com a estrutura já homologada; a segunda contradiz a descontinuação deliberada de `910` e descreve `card_asset` de forma mais simples que sua estrutura real. Decisão confirmada por Fabrício via pergunta direta. Detalhamento completo do episódio registrado em memória, não neste documento. |
| 0.65 | **Retomada da implementação (2026-07-24): dois bugs reais de tipagem corrigidos em `import-card-assets` (deploy v2.5.0) e primeira execução real do pipeline para `MEE` — 8/8 referências externas importadas, imagens bloqueadas por gap real de dados na fonte.** `TcgdexClient.getSet()` retornava `Promise<Record<string, unknown>>`, colapsando toda propriedade lida (`set.cards`, cada `tcgCard`) para `unknown` — corrigido com os tipos `TcgdexCardSummary`/`TcgdexSetDetail`. `upsertCardExternalReference`'s `image_source_url` estava tipado como `string` obrigatório, divergindo da coluna real (`TEXT` nula, com `CHECK` exigindo `NULL` ou URL `https://`) — corrigido para `string | null`, com `tcgCard.image ?? null` em `index.ts`. Ambos os bugs eram latentes desde a criação dos arquivos, só expostos agora pela primeira execução real de `deno check` (Convenção #7) contra este código. `LANGUAGE_CODE`/`TCGDEX_LANGUAGE` revertidos para `en`/`en`, deploy confirmado, `asset_import_run` `RUN-20260724-00000041` executado: `card_external_reference` 8/8 importadas (`en`); `card_asset`/imagens 0/8 — TCGdex não publica o campo `image` para `MEE`, confirmado tanto no endpoint de Set quanto no de carta individual, consulta real feita nesta mesma revisão. Não é falha do pipeline. Decisão de Fabrício: seguir para `MEP` agora, revisitar as imagens de `MEE` quando a TCGdex publicar os assets. Seção Set/Card Set (DoD) e Card External Reference atualizadas com o estado real; `services/tcgdex.ts` e `services/database.ts` copiados ao repositório após confirmação de deploy, seguindo o Princípio da Fonte Canônica. Cabeçalho deste documento corrigido de `0.58` para `0.65` (campo **Versão** estava desatualizado em relação ao corpo há várias revisões). |
| 0.66 | **`MEP` executada (`RUN-20260724-00000061`, `en`), mesmo dia: 60/60 referências externas importadas, mesmas 0/60 imagens bloqueadas — mesmo gap real de dados na TCGdex, confirmado pelo mesmo tipo de consulta direta ao endpoint de Set.** Nenhuma mudança de código foi necessária (mesma configuração `en`/`en` já deployada para `MEE`). Com isso, as sete Card Sets da Expansion `ME` têm `card_external_reference` 100% importada; imagens completas para `ME1`-`ME4`/`ME2.5` (859/859) e bloqueadas na fonte para `MEE`/`MEP` (0/68) — não há mais nenhuma coleção com execução pendente do lado do Project Mimikyu, só falta a TCGdex publicar os assets destes dois Sets especiais. Seção Set/Card Set (DoD) e Card Asset atualizadas com o estado real. |
| 0.67 | **Bloqueio de imagens de `MEE`/`MEP` resolvido por importação manual, decisão real de Fabrício: `scripts/import-manual-assets.ts` criado e CONFIRMADO EXECUTADO para `MEE`/`en` (8/8, 0 falhas).** Confirmado antes, por consulta direta ao CDN da TCGdex (`assets.tcgdex.net`, todas as combinações de qualidade/extensão, seguindo o padrão documentado em `tcgdex.dev/assets`), que o asset realmente não existe na fonte — não é só ausência no campo `image` da API. Script administrativo standalone (mesmo padrão de `scripts/discover-tcgdex-sets.ts`), deliberadamente fora de `supabase/functions/import-card-assets/` (lê arquivos locais, incompatível com o runtime de uma Edge Function); lê `assets/manual-imports/{card_set_code}/{language_code}/{collector_number}.{ext}`, sobe ao Storage e faz `UPSERT` em `card_asset` com `source_code = 'MANUAL'` (rastreabilidade da origem, para permitir substituir depois se a TCGdex publicar os assets). Resultado validado por consulta ao banco e por inspeção visual da imagem pública. `MEE`/`en` agora com catálogo genuinamente completo; `MEE`/`pt-BR` e `MEP`/`en`+`pt-BR` seguem o mesmo processo, imagens ainda não salvas localmente. Seção Set/Card Set (DoD) e Card Asset atualizadas. |
| 0.68 | **`MEE`/`pt-BR` executada (2026-07-24), mesmo dia: 8/8 Cards, 0 falhas — mesmo processo de `MEE`/`en`.** Com isso, `MEE` está com o catálogo genuinamente completo nos dois idiomas (referências externas e imagens, `en`+`pt-BR`). Pendente: `MEP`/`en`, `MEP`/`pt-BR`, mesmo processo, imagens ainda não salvas localmente. Seção Set/Card Set (DoD) e Card Asset atualizadas. |
| 0.69 | **Bug real encontrado por Fabrício (2026-07-25), inspecionando `asset_import_run` diretamente: 100% das 11 runs já executadas estavam presas em `status = PENDING`, mesmo as concluídas com sucesso — `import-card-assets` nunca escrevia nessa tabela após o `SELECT` inicial.** Corrigido em `index.ts`/`services/database.ts` (v2.6.0, CONFIRMADO DEPLOYADO E TESTADO EM PRODUÇÃO — ver nova seção "Correção real: máquina de estados nunca escrita (v2.6.0)", logo após "Query 221"). As 11 runs históricas corrigidas via backfill manual (dados reais extraídos por consulta, não adivinhados): 10 para `COMPLETED` (contagens = total de cartas do Set), `MEP` (`RUN-20260724-00000061`) para `COMPLETED_WITH_ERRORS` (`60`/`60`/`0`/`60`, gap de imagens já conhecido). Teste real pós-deploy expôs mais um caso do mesmo gap de GRANT recorrente neste projeto (`service_role` sem `INSERT`/`UPDATE` em `asset_import_run`) — corrigido por `database/migrations/272_grant_asset_import_run_write_permissions.sql`; reinvocação confirmou o fluxo completo. **Auditoria adicional solicitada por Fabrício, 100% das 11 linhas revisada**: `execution_context = MANUAL` está correto em todas (todas as execuções foram disparadas manualmente via terminal, não é bug); `language_id` e `initiated_by` seguem `NULL` em 100% das linhas — pendência conhecida, registrada, não tratada nesta revisão. `scripts/import-manual-assets.ts` (v1.1, `deno check` + dry-run confirmados, execução real ainda NÃO feita — aguardando `MEP` completa) passou a criar sua própria linha em `asset_import_run` por `(card_set, language)` processado, fechando a lacuna de as importações manuais não terem nenhum rastro nessa tabela. |
| 0.70 | **Nova entidade User Profile (Perfil de Usuário) / Reserved Username — Incremento 1 ("Meu Perfil") do módulo Identidade e Acesso, `1000`–`1040`/`1710`/`1800`–`1840` CONFIRMADOS EXECUTADOS.** Primeira entidade fora do Catálogo Editorial, inaugurando o Modelo Modular de Numeração (milhar `1000`–`1999`, ver STD-001 revisão 1.15) e formalizada em ADR-020 (User Profile and Username Identity Model). `user_profile`: separada de `auth.users`, `username` público/único/imutável (trigger sem válvula de exceção), `display_name` editável (trim garantido por trigger), `avatar_path` relativo ao bucket `avatars`. `reserved_username`: tabela de apoio (50 termos, v1.1 acrescentou `me`/`about` por sugestão de Fabrício), sem política de RLS direta — só lida por functions `SECURITY DEFINER` (`handle_new_user()`, que popula o perfil automaticamente no cadastro a partir de metadados tratados como não confiáveis; `username_available()`, checagem de disponibilidade sujeita a condição de corrida, não autoritativa). Bucket `avatars` criado com leitura pública e escrita restrita à própria pasta do usuário. Achado real: conta de teste de Fabrício, criada antes de `handle_new_user()` existir, ficou sem perfil — decisão tomada de excluí-la e recriar pelo fluxo real quando o frontend estiver pronto, não de corrigir manualmente. Frontend (formulário de cadastro + tela `/perfil`) ainda pendente. |
| 0.71 | **Frontend do Incremento 1 implementado e Query `1004` (bug real de GRANT) corrigida (2026-07-26).** Formulário de cadastro (`/cadastro`) estendido com `username`/`display_name`, normalização espelhando as constraints do banco (`web/lib/username.ts`), checagem de disponibilidade em tempo real via `username_available()` e envio pelos metadados esperados por `handle_new_user()`. `traduzirErroAuth` estendido para os erros do trigger, com ressalva registrada no código de que o formato exato devolvido pelo GoTrue para falha de trigger ainda não foi confirmado em produção. Tela `/perfil` real: Server Component protegido por sessão (redireciona para `/login` se ausente), trata perfil ainda não carregado, delega a edição de `display_name` a uma Server Action e o upload de avatar a uma função client-side que envia o novo arquivo ao bucket antes de remover o anterior. Durante a validação em produção, `/perfil` falhou com `permission denied for table user_profile` (`42501`): as políticas de RLS da Query `1003` estavam corretas, mas faltava o `GRANT` de base do role `authenticated` — corrigido pela Query `1004` (ver seção acima). Teste de cadastro completo (`user_profile` criado com `username`/`display_name` corretos) e carregamento de `/perfil` confirmados por Fabrício; edição de `display_name` e avatar seguem em validação. |
| 0.72 | **Incremento 2 (Administração de Usuários), Fases 1–3 CONFIRMADAS EXECUTADAS e validadas em produção (2026-07-26) — nova entidade Administração de Usuários.** `admin_user` (papel administrativo por presença de linha, separado de `user_profile`) e `admin_action_log` (auditoria, FKs anuláveis `ON DELETE SET NULL`, `metadata` com retrato de dados), formalizados em ADR-021. Functions `is_admin()` (sem parâmetro, verifica só o chamador), `admin_list_users()` (paginada, `SECURITY DEFINER`, única via de leitura de e-mail de `auth.users` para fins administrativos) e `admin_grant_admin()`/`admin_revoke_admin()` (trava consultiva de transação contra remoção concorrente do último administrador). Bug real encontrado na Fase 3: `admin_list_users()` falhava com erro `42804` (`auth.users.email` é `varchar(255)`, não `TEXT` — corrigido com cast explícito, v1.1). Bootstrap do primeiro administrador documentado como operação única, não numerada, não replicável entre ambientes (por decisão de Fabrício). Frontend: rota `/usuarios` real (estados de acesso negado/erro/vazio/carregado), item de menu condicional a `is_admin()`. Fase 4 (correção administrativa de `username`, prevista em ADR-020) deliberadamente fora deste incremento. |
| 0.74 | **Frontend da Visão Geral (`/catalogo`) implementado sobre a fundação da revisão `0.73` (2026-07-26).** Guarda de servidor compartilhada (`requireCatalogoAdmin()`) aplicada às seis rotas do módulo, inclusive as ainda `ComingSoonPage`; nova rota de detalhe `/catalogo/card-sets/[code]`. Quatro blocos implementados: Estado do Catálogo (KPIs de estado), Card Sets (tabela navegável), Cartas por Raridade (distribuição, sem expor `ENERGY`) e Atividade Recente (linguagem natural, admin-only). Camada de dados em `web/lib/catalogo/queries.ts`, lendo diretamente as 10 tabelas liberadas pela Query `274`. `tsc --noEmit` confirmado limpo; validação visual em `npm run dev` pendente (sem acesso a npm/CDN nesta sessão). Ressalva registrada: o wireframe/indicadores exatos aprovados antes da compactação de contexto desta sessão não puderam ser recuperados verbatim — os blocos foram reconstruídos a partir do resumo disponível e de nova verificação do banco, e valem conferência de Fabrício. |
| 0.73 | **Fundação de autorização e logo do Catálogo Editorial, Queries `273`–`277` CONFIRMADAS EXECUTADAS (2026-07-26) — nova seção Autorização do Catálogo Editorial, formalizando ADR-022.** `card_set.logo_storage_path` (`TEXT NULL`, caminho relativo, nunca URL, `CHECK ck_card_set_logo_storage_path_not_url`) adicionada via Query `273`; `database/schema/120_create_card_set_table.sql` atualizado para v2.1 (Princípio da Fonte Canônica). Leitura do Catálogo Editorial restrita a administradores via política `catalog_admin_select` (`USING is_admin()`) + `GRANT SELECT` a `authenticated`, em exatamente dez tabelas efetivamente consultadas pela Visão Geral (Query `274`) — as sete tabelas do catálogo ainda sem tela real seguem sem política. Escrita da logo restrita à função `SECURITY DEFINER` `admin_set_card_set_logo()` (Query `275`, valida administrador, formato do caminho e existência do Card Set via `ROW_COUNT`) — nenhuma política de `UPDATE` criada em `card_set`. Bucket privado `card-set-logo` com quatro políticas separadas de Storage (`SELECT`/`INSERT`/`UPDATE`/`DELETE`, Query `276`), divergindo deliberadamente do padrão público de `card-front`/`artwork`/`card-back`/`avatars`; fora do catálogo `storage_bucket`, mesmo padrão de `avatars`. Validação consolidada `277` confirma os cinco blocos (coluna+CHECK, ausência de políticas de escrita em `card_set`, as dez políticas de leitura, a segurança da função, o bucket e suas políticas). Motivado pela retomada do frontend do Catálogo Editorial e pela descoberta de que as 17 tabelas do módulo já estavam de fato fechadas (RLS sem política) antes desta decisão. Implementação da tela `/catalogo` (guardas de menu/rota, componentes) explicitamente **não** iniciada nesta rodada, por instrução de Fabrício. |
| 0.75 | **Início da implementação de ADR-023/ADR-024 (Catálogo Editorial — Escrita e Ingestão), Queries `2000`/`2010` CONFIRMADAS EXECUTADAS (2026-07-26) — nova seção própria, milhar `2000`–`2999`.** Schema `internal` criado (Query `2000`), isolado da API (confirmado manualmente por Fabrício: não consta em Exposed Schemas), `USAGE` revogado de `PUBLIC`/`anon`/`authenticated`. `catalog_admin_action_log` criada (Query `2010`) — nome definitivo, confirmando o exemplo dado em ADR-023 — auditoria própria do módulo, separada de `admin_action_log`; `entity_id` polimórfico sem FK, `NOT NULL`; três `CHECK`s, incluindo um reforço de integridade adicional a ADR-023 (`action` compatível com `entity_type`). Implementação segue em ciclos verticais por entidade (Backend → Tela → Validação), por decisão de Fabrício — próximos passos: `card.is_active` (`2020`), `internal.write_card()` (`2030`), depois `Game` → `Expansion` → `Card Set` → `Card` (subdividido). |
| 0.76 | **Marco: infraestrutura comum de ADR-023 concluída — `card.is_active` (Query `2020`) e `internal.write_card()` (Query `2030`), AMBAS CONFIRMADAS EXECUTADAS (2026-07-26).** `is_active BOOLEAN NOT NULL DEFAULT true` adicionada a `card` (927/927 ativas, sem backfill); `database/schema/140_create_card_table.sql` atualizado para v1.1 (Princípio da Fonte Canônica). `internal.write_card()` criada — `p_mode` (`CREATE`/`UPDATE`) numa função única, protege `card_set_id`/`collector_number` contra atualização (`RAISE EXCEPTION`, nunca ignora silenciosamente), substituição integral (não parcial) dos campos editáveis. Descoberta de implementação: consistência de Game e `updated_at` já garantidos pelo trigger existente (`141`), então a função não duplica essa validação. Primeira função do módulo **testada funcionalmente em tempo real** (não apenas revisão de código): cinco cenários executados dentro de uma transação com `ROLLBACK` forçado, todos com o comportamento esperado, `0` linhas residuais confirmadas. Próximo passo: ciclo vertical de `Game` (`2031`/`2032` + tela + validação `2804`). |
| 0.77 | **Primeiro ciclo vertical (Backend → Tela → Validação) concluído: `Game` — `admin_create_game()`/`admin_update_game()` (Queries `2031`/`2032`, CONFIRMADAS EXECUTADAS e testadas funcionalmente com 8 cenários reais) e tela `/catalogo/jogos` (cadastro/edição inline) IMPLEMENTADA (2026-07-26).** Sem camada `internal` própria (mesmo padrão de `admin_set_card_set_logo()`) — `Game` não converge múltiplos canais nem tem complexidade que justifique isolar a persistência. `code` imutável na edição por construção (parâmetro simplesmente não existe em `admin_update_game()`); `admin_create_game()` normaliza `code` para maiúsculas e verifica duplicidade explicitamente antes do `INSERT`. Auditoria via `catalog_admin_action_log` confirmada para os dois casos de sucesso. Novo helper `traduzirErroCatalogo()` (`web/lib/supabase/catalogo-errors.ts`), reutilizável pelos ciclos seguintes. `tsc --noEmit` confirmado limpo para o código novo. **Pendência explícita**: teste da tela pela própria interface (listar/cadastrar/editar) depende do ambiente de Fabrício — sandbox desta sessão sem acesso a `npm`/CDN. Próximo passo: confirmação de Fabrício, depois ciclo vertical de `Expansion` (`2033`/`2034` + tela + validação `2805`). |
| 0.78 | **Confirmação de Fabrício via interface real + dois ajustes visuais; emenda ADR-023 dá a `Game` exclusão real via UI (Queries `2041`/`2042`, CONFIRMADAS EXECUTADAS e testadas com 4 cenários reais), com checkbox/exclusão em lote na tela (2026-07-26).** Ajustes visuais: botão "Cadastrar novo jogo" movido para fora do card, borda na cor primária (`outline-primary`), ícone `Plus`, altura compacta; "Editar" virou ícone (`Pencil`, `icon-sm`) — ambas as variantes novas em `Button`, reutilizáveis pelos ciclos seguintes. **Emenda registrada explicitamente antes de implementar**, por contradizer a decisão original do ADR ("sem desativação por UI" para Game/Expansion/Card Set) — Fabrício optou por emendar em vez de manter a via manual por SQL. `admin_delete_game()`: exclusão real (não desativação, `Game` continua sem `is_active`), bloqueada pela `FK fk_expansion_game` já existente quando há Expansions, com mensagem antecipada (`ADMIN_DELETE_GAME_HAS_DEPENDENTS`); auditoria via novo `GAME_DELETED` (`catalog_admin_action_log` atualizado para v1.1). Restrita a `Game` — `Expansion`/`Card Set` não afetados. Frontend: checkbox por linha, barra de seleção, confirmação inline antes de excluir, falhas parciais reportadas por item. `tsc --noEmit` confirmado limpo. Pendente: confirmação de Fabrício da exclusão pela própria interface (o teste de interface já feito cobriu listagem/cadastro, anterior a esta emenda). |
| 0.79 | **Colunas "Criado em"/"Atualizado em" na tela de Jogos, fechando o ciclo de Game (2026-07-26).** Novo helper `formatarData()` (`web/lib/format-date.ts`) formata como `"26 jul 2026"` — deliberadamente não `DD/MM/AAAA`, pedido explícito de Fabrício, reutilizável pelos ciclos seguintes. `getJogos()` passou a selecionar `created_at`/`updated_at`; `JogoRow` ganhou `createdAt`/`updatedAt`. `tsc --noEmit` confirmado limpo. |
| 0.80 | **Aprovação formal do ciclo de Game + quatro ajustes de fechamento, extraindo componentes reutilizáveis para Expansion/Card Set (2026-07-26).** Exclusão mútua edição/seleção centralizada no hook `useAdminListState`; `AdminToolbar`/`BulkSelectionBar`/`ConfirmDeleteBar`/`SuccessBanner` extraídos para `web/components/catalogo/`; tipos de Server Action centralizados em `web/lib/catalogo/admin-action-types.ts`. Feedback de sucesso com destaque temporário de linha. Contador de Expansões agora linka para `/catalogo/expansoes?game=CODE`; `getExpansoes()` ganhou filtro opcional por `gameCode`. `tsc --noEmit` confirmado limpo. Autorizado o início do ciclo vertical de `Expansion`. |
| 0.81 | **Segundo ciclo vertical concluído: `Expansion` — `admin_create_expansion()`/`admin_update_expansion()` (Queries `2033`/`2034`, CONFIRMADAS EXECUTADAS e testadas funcionalmente com 11 cenários reais) e tela `/catalogo/expansoes` (cadastro/edição inline, reconstruída sobre os componentes compartilhados) IMPLEMENTADA (2026-07-26).** `game_id`/`code` imutáveis na edição por construção, mesmo princípio de Game; `code` único por Game (não global); `release_order` único por Game, verificado explicitamente em ambas as funções. Sem seleção em massa/exclusão — emenda de exclusão real via UI continua restrita a Game. Frontend sem `BulkSelectionBar`/`ConfirmDeleteBar`; seletor de Jogo no cadastro via novo `getGameOptions()`; filtro `?game=` preservado. `tsc --noEmit` confirmado limpo. **Pendência explícita**: teste da tela pela própria interface depende do ambiente de Fabrício. Próximo passo: ciclo vertical de `Card Set` (`2035`/`2036` + tela + validação `2806`). |
| 0.82 | **Correção direcionada (2026-07-30), a pedido de Fabrício.** Status de `Game` (seção Game) corrigido de "pronto para implementação" para "concluído e implementado" (camada de escrita administrativa já validada). Status de `Card` (seção "Card (Carta)") corrigido de "modelo aprovado, ainda não executado" para "executado e confirmado no Supabase (927 Cards, 7 Card Sets)", com referência de subseção atualizada para "Modelo Final — Versão 1.1". Nota introdutória sobre "17 tabelas" esclarecida como snapshot histórico das tabelas originais do Catálogo Editorial especificamente (não o total atual do schema `public`, hoje 22 tabelas, confirmado 2026-07-30) — demais menções a "17 tabelas" no documento preservam seu sentido histórico original e não foram alteradas. **Resolução de `OD-001` (Energy), formalizada em `adr/ADR-025-energy-as-catalog-card-category.md`**: nota de discrepância da seção Card Category (Query `831`/`ENERGY`) atualizada de "não resolvida" para resolvida, com referência ao ADR-025; item correspondente da Definition of Done marcado `[x]`; nota de discrepância da seção Card/Modelo Final (Query `840`, 17 Cards de Energia) atualizada da mesma forma; "Ressalva importante" da seção Card simplificada para o único item que permanece de fato em aberto (`Card Variant` para MEE/MEP); item de Definition of Done correspondente marcado `[x]`. O bloco histórico preservado da seção "Card (Carta)" (modelo anterior à reversão arquitetural, com `category_code`/Regra 6, explicitamente já marcado como superado desde a revisão que introduziu "Modelo Final — Versão 1.1") não foi alterado — permanece como registro do estado da pendência antes da resolução de Fabrício. Nenhuma alteração física no banco. |
| 0.83 | Nota objetiva adicionada (2026-07-30), a pedido de Fabrício, explicando o que mantém o Status deste documento como "Em elaboração" — sem promover para "Aprovado": `Card Variant` de `MEE`/`MEP` (não executado) e as seções `Card Translation`/`Collection Item`/`Collection`/`Collection Entry` (documentação pendente, aguardando Sub-Fase 2). Nenhum conteúdo técnico alterado. |
| 0.84 | **Emenda: `Expansion` ganha exclusão real via UI (`admin_delete_expansion()`, Queries `2043`/`2044`, SQL PREPARADO — AGUARDANDO EXECUÇÃO), 2026-07-31.** Nova seção "Emenda — `Expansion`: exclusão real via UI", mesmo padrão já validado em `Game` (`2041`/`2042`): bloqueada pela `FK fk_card_set_expansion` (`ON DELETE RESTRICT`, Query `120`) quando há Card Sets associados; auditoria via novo `EXPANSION_DELETED` em `catalog_admin_action_log`. Frontend: nova Server Action `deleteExpansions` e `ConfirmDeleteBar` na galeria de Expansões, ação rápida de excluir ao lado de editar em cada card. Também corrigida a descrição desatualizada do frontend da tela de Expansões (referenciava a antiga `ExpansoesTable`, hoje sem uso — a tela real é `ExpansoesGallery`, redesenho de galeria de cards de 2026-07-31). Queries `2043`/`2044` ainda não executadas no Supabase — SQL versionado em `database/`, aguardando o ritual de pareamento com Fabrício; botão "excluir" só funciona após essa execução. |
| 0.85 | **Queries `2043` e `2044` confirmadas executadas por Fabrício (2026-07-31), fechando a emenda de exclusão de `Expansion`.** `2043` validada via `pg_get_constraintdef` (ambas as constraints de `catalog_admin_action_log` incluem `EXPANSION_DELETED`); `2044` validada via `has_function_privilege` (`anon` sem `EXECUTE`, `authenticated` com `EXECUTE`). O botão "excluir" da galeria de Expansões está funcionalmente operante em produção. Pendência remanescente: validação funcional dos 4 cenários de `2809` (sem dependentes, com dependentes, id inexistente, sessão não-admin) — ainda não executada. |
| 0.86 | **Validação funcional (`2809`) confirmada por Fabrício pela própria interface (2026-07-31) — emenda de exclusão de `Expansion` encerrada.** Testado diretamente na tela: exclusão bem-sucedida e bloqueio ao excluir Expansão com Card Sets associados, ambos "funcionando corretamente". Cenários de id inexistente e sessão não-administrativa não são alcançáveis pela UI normal — permanecem como cobertura teórica da função, mesma lógica já validada em `admin_delete_game()`. Ciclo de `Expansion` (cadastro/edição/exclusão) agora no mesmo patamar de maturidade de `Game`. |
| 0.87 | **Galeria de Expansões agrupada por Jogo (2026-07-31), a pedido de Fabrício.** Nova `getExpansoesGroupedByGame()` substitui `getExpansoesForCatalogo()` no modo galeria — agrupa por Jogo, cada grupo ordenado por `release_order` descendente (Expansion não tem coluna de data real; `release_order` é o campo que expressa "data de lançamento" ali), grupos em si ordenados alfabeticamente por nome do Jogo. `ExpansoesGallery` ganhou uma seção por Jogo (nome + indicador de cor + grid próprio). Consequência necessária: "Carregar mais" deixou de existir no modo galeria (carrega tudo de uma vez); `loadMoreExpansoes` e `getExpansoesForCatalogo()`/`sortExpansoesForCatalogo()` removidas por ficarem sem uso. Busca não alterada. `tsc --noEmit` confirmado limpo. Puramente de apresentação — nenhuma mudança de schema/RPC/RLS. Duas correções no mesmo dia, a partir de feedback ao vivo de Fabrício: direção do sort dentro do grupo (`release_order` ascendente, não descendente) e ordem dos próprios grupos (por `game.created_at` ascendente — Jogo mais antigo primeiro — não alfabética). |
| 0.88 | **Logo por Expansão (2026-07-31, mesmo dia), a pedido de Fabrício ("vamos incluir uma imagem para cada expansão").** Nova coluna `expansion.logo_storage_path` (Query `2045`), função `admin_set_expansion_logo()` (Query `2046`), bucket privado `expansion-logo` com 4 políticas admin-only (Query `2047`) — mesma arquitetura de `card_set.logo_storage_path`, numerada no milhar `2000`–`2999` em vez de `200`–`299` (faixa legada congelada desde `STD-001`; ver `ADR-022`, emenda 2026-07-31). Diferente do precedente de Card Set (infraestrutura pronta desde 2026-07-26, nunca conectada ao frontend): aqui o upload foi construído de ponta a ponta — novo `ExpansaoLogoUploader` (adaptado de `AvatarUploader`, leitura via URL assinada, escrita via Server Action `setExpansionLogo()`), disponível no Dialog de edição (não no de criação — a Expansão precisa já existir). `getExpansionLogoUrls()` resolve URLs assinadas em lote; `ExpansaoGalleryCard` exibe a imagem com iniciais como reserva. Todas as Queries (`2045`/`2046`/`2047`/`2810`) confirmadas executadas via o ritual de pareamento. `tsc --noEmit` confirmado limpo. |
| 0.89 | **Coleções no mesmo padrão de Expansões + emenda `Card Set`: atualização e exclusão real via UI (2026-07-31), a pedido de Fabrício ("faça todos os ajustes necessários para manter o mesmo padrão da página Expansões").** Sete ajustes de apresentação: `CardSetsStats` (novo indicador Jogos/Expansões/Coleções/Sem Cartas), botão "Novo" reposicionado, busca/filtro dentro do `Card`, padding da logo reduzido para `p-3` (`aspect-square` mantido — logo de Card Set é símbolo quadrado, diferente do wordmark de Expansão), paginação confirmada consistente, `catalogo-gallery.tsx`/`catalogo-content.tsx` unificados num só componente (`catalogo-content.tsx` sem uso, marcado não removido) e `loading.tsx` atualizado. Mais uma mudança de escrita: botões de editar/excluir em cada card exigiram `admin_update_card_set()`/`admin_delete_card_set()` (Queries `2048`/`2050`, SQL PREPARADO — AGUARDANDO EXECUÇÃO) e `CARD_SET_DELETED` em `catalog_admin_action_log` (Query `2049`) — primeira via de escrita estrutural de Card Set além da logo. Aproveitado para reconciliar um gap: o arquivo canônico `2010` nunca tinha recebido `EXPANSION_DELETED` (só a migration histórica `2043`, já confirmada contra o banco real) — corrigido no mesmo commit (`2010` bump para v1.2). Frontend com fiação completa (`EditCardSetDialog`, `card-sets/actions.ts`) — botões só funcionam de fato após Fabrício executar `2048`–`2050` via o ritual de pareamento. Validação em `2811`. `tsc --noEmit` confirmado limpo. |
| 0.90 | **Queries `2048`/`2049`/`2050` confirmadas executadas por Fabrício (2026-07-31), fechando a parte de banco da emenda de `Card Set`.** `2048`/`2050` validadas via `has_function_privilege` (`anon` sem `EXECUTE`, `authenticated` com `EXECUTE`); `2049` validada via `pg_get_constraintdef` (ambas as constraints com `CARD_SET_DELETED`, e `EXPANSION_DELETED` confirmado presente de quebra — o gap do canônico `2010` já estava reconciliado com o banco real). Botões "editar"/"excluir" da galeria de Coleções funcionalmente operantes em produção. Pendência remanescente: validação funcional de `2811` pela própria interface. |
| 0.91 | **Três ajustes pontuais em Coleções (2026-07-31), a partir de teste real de Fabrício.** (1) Contraste da `ConfirmDeleteBar` no tema escuro corrigido (`dark:` overrides na borda/fundo/textos vermelhos — mesmo diagnóstico já aplicado ao ícone `tone="danger"` de `StatCard`), compartilhado por Jogos/Expansões/Coleções. (2) Botão "Novo" renomeado para "Nova Coleção" (mesma convenção de "Nova expansão"/"Novo Jogo"), incluindo o Dialog que ele abre. (3) Upload de logo conectado ao Dialog de edição de Card Set (`CardSetLogoUploader`, cópia fiel de `ExpansaoLogoUploader`) — sem nenhum trabalho de banco, já que `admin_set_card_set_logo()`/bucket `card-set-logo` (Queries `275`/`276`) já existiam desde 2026-07-26, só nunca tinham sido conectados a um uploader real. `tsc --noEmit` confirmado limpo. |
| 0.92 | **Correção de sincronização documental + altura fixa da logo (2026-07-31), motivada pela retomada de sessão e pelo pedido explícito de Fabrício de recuperar o ponto exato de continuidade a partir do Handoff.** Duas pendências textuais desatualizadas corrigidas na seção "Coleções... emenda `Card Set`": (a) o título ainda dizia "SQL PREPARADO, AGUARDANDO EXECUÇÃO" apesar de as Queries `2048`/`2049`/`2050` já constarem CONFIRMADAS EXECUTADAS desde a revisão `0.90` — corrigido para "CONFIRMADO EXECUTADO"; (b) o item 4 (tamanho da logo) ainda descrevia `aspect-square` como decisão final, superada por dois pedidos posteriores de Fabrício não refletidos nesta seção. Nova seção "Altura fixa da logo (Expansão e Card Set)" documenta a evolução completa: `aspect-square` → `aspect-[2/1]` (pedido "use a mesma altura das expansões") → `h-28`, altura fixa em pixels (pedido "ajuste o tamanho da imagem ao local destinado e não o inverso") — estado final aplicado a `ExpansaoGalleryCard`/`CardSetGalleryCard` e aos dois `loading.tsx`. Nenhuma mudança de schema/RPC/RLS. |
| 0.93 | **Três confirmações de interface real + decisão explícita de cadastro de Card Set (2026-07-31).** Fabrício confirmou pela própria tela: validação funcional de `2811` (Card Set), exclusão de `Game` (individual — exclusão em lote foi desabilitada por decisão de escopo, consistente com o redesenho de `/catalogo/jogos` para ação rápida por linha) e a tela completa de `Expansion`. Decisão explícita que resolve a última pendência do módulo: cadastro de `Card Set` pela própria tela passa a estar em escopo — nova Query `2051` (`admin_create_card_set()`), cobrindo os campos estruturais que a atualização deliberadamente não toca (`set_type`, `base_set_size`, `total_set_size`, `release_date`), com as regras de `ck_card_set_promo_size`/`uq_card_set_expansion_promo` antecipadas como erro claro. SQL preparado, aguardando execução via o ritual de pareamento. Frontend (`NovoCatalogoDialog` com formulário completo + `createCardSet`) já com a fiação pronta. |
| 0.94 | **Query `2051` confirmada executada por Fabrício (2026-07-31), fechando a parte de banco do cadastro de Card Set.** Validada via `has_function_privilege` (`anon` sem `EXECUTE`, `authenticated` com `EXECUTE`). Botão "Nova Coleção" da galeria de Coleções funcionalmente operante em produção. Pendência remanescente: validação funcional de `2812` pela própria interface (incluindo um cenário `PROMO`) — único item restante antes de considerar o ciclo vertical `Game`/`Expansion`/`Card Set` do `ADR-023` totalmente encerrado. |
| 0.95 | **Validação funcional de `2812` confirmada + dois ajustes visuais (2026-07-31).** Fabrício testou o cadastro de Card Set pela tela, incluindo o cenário `PROMO` (bloqueio de duplicidade exercitado com sucesso) — "Funcionando perfeitamente bem". Ciclo vertical de `Game`/`Expansion`/`Card Set` do `ADR-023` encerrado. Dois ajustes de apresentação a partir do teste real: `NovoCatalogoDialog` ganhou `size="lg"` (texto do seletor "Tipo" estava sendo cortado no tamanho padrão); contraste da tarja de erro no tema escuro corrigido na fonte, em `InlineFeedback` (tom `error`) — mesmo diagnóstico já repetido nesta sessão para `--destructive` no tema escuro (`StatCard`, `ConfirmDeleteBar`), agora resolvido no componente compartilhado. `tsc --noEmit` confirmado limpo. |
| 0.96 | **Correção: `admin_create_card_set()` rejeitava `ENERGY` + gap canônico em `card_set.set_type` (2026-07-31).** Fabrício testou a tela e reportou a ausência do tipo Energia no seletor. Dois problemas relacionados: (1) `admin_create_card_set()` v1.0 só validava `REGULAR`/`SPECIAL`/`PROMO`, apesar de `ENERGY` já ser um valor real da coluna desde a Migration `263` (confirmada executada em 2026-07-26, usada para cadastrar `MEE`) — corrigido, função bump para v1.1; (2) o arquivo canônico `database/schema/120_create_card_set_table.sql` (v2.1) nunca tinha incorporado essa mesma migration — mesma classe de gap já corrigida nesta sessão para `EXPANSION_DELETED` — corrigido, bump para v2.2. Nenhuma constraint nova inventada: `ENERGY` não exige `base_set_size = total_set_size` (só `PROMO` tem essa regra, `ck_card_set_promo_size`). Frontend: opção "Energia" adicionada ao seletor; rótulo de `PROMO` simplificado para "Promocional". Validação `2812` reaberta (v1.1), aguardando `CREATE OR REPLACE` de `admin_create_card_set()` v1.1 ser executado por Fabrício. |
| 0.97 | **`admin_create_card_set()` v1.1 confirmada + ajuste de ordenação em Coleções (2026-07-31).** Fabrício confirmou o cadastro de Card Set tipo Energia funcionando pela tela — validação `2812` encerrada com os três cenários funcionais (geral, `PROMO`, `ENERGY`). Pedido seguinte: "os card sets devem ser organizados por data de lançamento e se as datas forem iguais deve ser levado em consideração o número de ordem do lançamento. Sempre em ordem decrescente para os dois parâmetros" — `sortCatalogoCardSets()`, caminho sem filtro (galeria padrão de Coleções), trocou o desempate de `created_at` para `release_order` descendente quando as datas coincidem ou estão ambas ausentes. Caminho com filtro de Jogo/Expansão não alterado (já usa `release_order` como critério primário, decisão anterior). Puramente de apresentação. `tsc --noEmit` confirmado limpo. |
| 0.98 | **`admin_update_card_set()` ampliada para aceitar tipo e data de lançamento (Query 2048 v2.0, Migration 2052), 2026-07-31.** Pedido explícito de Fabrício testando a edição: "deve ser permitido editar o tipo e a data de lançamento". Assinatura passa de 3 para 5 parâmetros (`p_set_type`, `p_release_date` novos); `expansion_id`/`code`/`base_set_size`/`total_set_size` continuam fora. Ao mudar para `PROMO`, antecipa `ck_card_set_promo_size` (tamanhos já cadastrados precisam ser iguais) e `uq_card_set_expansion_promo` (só um `PROMO` por Expansion) como erro administrativo claro. Como a assinatura muda (não só a lógica interna), arquivo canônico `2048` bump para v2.0 e nova Migration `2052` (`DROP FUNCTION` + `CREATE FUNCTION`) criada para reconciliar o banco já instalado. Frontend: `EditCardSetForm` ganhou os campos Tipo/Data de lançamento; `CatalogoCardSetRow`/raw row ganharam `setType`. Migration `2052` preparada, aguardando execução de Fabrício. |
| 0.99 | **Migration `2052` confirmada executada por Fabrício em 2026-07-31** — validada via `pg_get_function_arguments`: uma única `admin_update_card_set`, com os 5 parâmetros esperados, confirmando que a assinatura antiga de 3 parâmetros foi removida (sem sobrecarga ambígua). Botões de edição de Card Set na tela de Coleções agora expõem tipo e data de lançamento como campos editáveis. Validação funcional (edição real pela tela) ainda pendente de confirmação explícita. |
| 1.0 | **Validação funcional confirmada por Fabrício em 2026-07-31** ("Teste na tela validado!") — edição de tipo e data de lançamento de Card Set pela própria tela funcionando, fechando a Migration `2052`. Com isso, o ciclo vertical de `Game`/`Expansion`/`Card Set` do `ADR-023` está integralmente implementado e validado pela própria interface (create/update/delete conforme aplicável); próximo passo é o subciclo `Card`. Bump de versão sem relação com o campo `Status` deste documento (que permanece "Em elaboração", ver revisão `0.83`) — apenas o contador sequencial cruzando de `0.99` para `1.0`. |
| 1.1 | **Subciclo `Card` iniciado — galeria visual de Cartas (leitura, 2026-07-31), a pedido de Fabrício ("precisamos caprichar no visual... deve impressionar qualquer usuário visualmente").** Tela `/catalogo/cartas` reescrita: 3 Card Sets mais recentes em destaque (logo, substituindo indicadores numéricos), seletor "Coleção", busca por nome/número, filtros de raridade/categoria, grid ordenado por `collector_order` com efeito de hover "holográfico" (`HoloCard`, CSS/JS puro) reaproveitado no modal de ampliação, numeração/nome/símbolo de raridade discretos por carta, paginação inicial de 30 + "Ver todas". Nenhuma Query SQL nova: `card`/`card_asset`/`rarity`/`card_category` já liberados desde a Query `274` (ADR-022); bucket `card-front` já público desde a Seed `895` (`getPublicUrl()`, sem URL assinada). Três decisões de implementação sem critério único no pedido, registradas na seção "Subciclo Card — Galeria de Cartas": prioridade de idioma da imagem (`pt-BR` > `en`), tamanho de página inicial (30) e símbolo de raridade monocromático via ícones `lucide-react`. `queries.ts`: `getCardSetOptions`/`CartaRow`/`getCartasPorCardSet` (só usados pela tela antiga) substituídos por `getCardSetsForCartas()`/`getCartasCompletas()`. `tsc --noEmit` confirmado limpo. Escopo desta revisão é somente leitura — criação/edição/desativação administrativa de Card permanecem pendentes. Validação funcional pela tela ainda não confirmada por Fabrício. |
| 1.2 | **Bug real encontrado no primeiro teste + três ajustes de UX (2026-07-31, mesmo dia).** A afirmação da revisão `1.1` ("nenhuma Query SQL nova foi necessária") estava errada: `card_asset_type`, lida pelo embed aninhado de `getCartasCompletas()`, é uma das 7 tabelas do Catálogo Editorial que a Query `274` deliberadamente deixou sem política de SELECT (nenhuma tela a consultava, na época) — RLS bloqueava a query silenciosamente, e toda a galeria mostrava "Nenhuma carta catalogada" mesmo em Card Sets com cartas reais. Nova migration `2053` (mesmo padrão da `274`), SQL preparado, aguardando execução por Fabrício. Ajustes de UX a partir do mesmo teste: chips compactos substituem os blocos grandes dos 3 Card Sets recentes ("visual menos agressivo"); seletor "Outra coleção" adicionado ao lado dos chips; seletor "Expansão" adicionado ao lado do seletor "Coleção" na busca, sincronizado (Expansão sempre derivada do Card Set selecionado, Coleção sempre restrita à Expansão atual). `tsc --noEmit` confirmado limpo. |
| 1.3 | **Query `2053` confirmada executada + modal de ampliação reduzido a só a imagem (2026-07-31, mesmo dia).** Fabrício confirmou a execução da `2053` ("Success. No rows returned") — a galeria de Cartas lista cartas normalmente, bug encerrado. Elogio recebido ("ficou espetacular") seguido de um pedido pontual, com print comparando nosso modal de ampliação (título/número/categoria/raridade visíveis) contra a referência oficial (só a carta): "só quero enxergar a imagem da carta... o foco está única e exclusivamente na carta". `CartaZoomDialog` reduzido ao essencial — removidos título/número/categoria/raridade visíveis e o botão de fechar; fundo/borda/sombra do painel do `Dialog` sobrepostos para transparente, só o `HoloCard` com a imagem flutua sobre o overlay escurecido. `DialogTitle` mantido `sr-only` (nome acessível exigido pelo Radix, nunca visível). Nenhuma pendência conhecida resta na experiência de leitura de Cartas. `tsc --noEmit` confirmado limpo. |
| 1.4 | **Animação idle flutuante na carta ampliada + carta maior (2026-07-31, mesmo dia).** Pedido de Fabrício com dois prints do DevTools da referência oficial (`matrix3d(...)` capturado em dois instantes, valores levemente diferentes): "gostaria que essa carta ficasse com o efeito flutuando na tela... se movendo lentamente mesmo sem que o mouse passe por ela". `HoloCard` ganhou a prop `floating` (só usada por `CartaZoomDialog`): loop `requestAnimationFrame` com três senoides independentes (`rotateX`/`rotateY`/`translateY`, frequências/fases diferentes, sem ciclo óbvio), pausado durante hover (interação do usuário sempre vence) e desligado sob `prefers-reduced-motion: reduce`. Tamanho máximo da carta ampliada aumentado de `300px`/`340px` para `380px`/`460px`. `tsc --noEmit` confirmado limpo. |
| 1.5 | **Reformatação da identificação no grid + mapa de símbolos de raridade ampliado (2026-07-31, mesmo dia).** Novo elogio de Fabrício seguido de dois pedidos, com print de uma carta real: (1) identificação abaixo de cada carta do grid virou linha única `#003/088 - Nome` + símbolo de raridade em linha própria, ambos alinhados à esquerda (aplicado sem ambiguidade em `CartaGridCard`); (2) "os símbolos não estão exatamente como convencionado em nossa base... Ilustração rara com símbolo círculo cinza". Investigação mostrou lacuna de cobertura, não dado errado: `RaritySymbol` só mapeava 5 dos 9 `symbol_code` reais do seed canônico `830_seed_rarity.sql`, e todo código fora desses 5 (incluindo `GOLD_STAR`, de `ILLUSTRATION_RARE`) caía num fallback cinza genérico — plausivelmente o que Fabrício viu. Componente reescrito cobrindo os 9 códigos reais em três tons (`BLACK_*`→`text-foreground`, `SILVER_*`→`text-muted-foreground`, `GOLD_*`→`text-primary`, tokens já existentes do Design System) mais um ícone próprio para `MEGA_ATTACK`. **Divergência sinalizada, não resolvida unilateralmente:** o seed `830` mapeia `ILLUSTRATION_RARE`→`GOLD_STAR`, não a um código cinza — pendente confirmação de Fabrício se o problema era só cobertura (agora corrigida) ou se a convenção real da carta física diverge do seed (nesse caso a correção seria de dado, não de código). `tsc --noEmit` confirmado limpo. |
| 1.6 | **View Transitions API no zoom + gap reduzido + padding de 3 dígitos no collector_total (2026-07-31, mesmo dia).** Fabrício testou novamente (print de uma carta Weedle real, Card Set com 86 cartas) e pediu três ajustes. (1) O zoom+fade genérico do Dialog (`animate-dialog-in`, salta direto pro tamanho final) foi substituído por `document.startViewTransition()` — API nativa do navegador, sem dependência nova — fazendo a miniatura do grid morfar de verdade até virar a imagem ampliada (e o inverso ao fechar), via `viewTransitionName` compartilhado entre `CartaGridCard` e `CartaZoomDialog` (`carta-img-<id>`); `flushSync` sincroniza a troca de estado dentro do callback exigido pela API; `DialogContent` ganhou a prop `animated` (default `true`) para ceder seu zoom+fade embutido só quando a API está disponível, com fallback automático sob navegadores sem suporte ou `prefers-reduced-motion: reduce`. (2) Gap entre identificação e símbolo de raridade reduzido (`space-y-1` → `space-y-0.5`). (3) `collector_total` (`INTEGER`, perde zeros à esquerda) passou a ser exibido com `padStart(3, "0")` — cobre o caso relatado ("001/086", não "001/86") sem precisar consultar `base_set_size` do Card Set. `tsc --noEmit` confirmado limpo. |
| 1.7 | **Correção: carta em transição aparecia atrás das vizinhas (2026-07-31, mesmo dia).** Fabrício reportou, com print do meio da animação: "durante a transição a carta fica por trás das demais cartas". Causa raiz: a implementação da revisão `1.6` dava `viewTransitionName` único e permanente a cada uma das ~122 cartas do grid — a View Transitions API "hoista" para sua árvore de pseudo-elementos qualquer elemento nomeado no instante da captura, não só o que de fato muda de posição/tamanho, e a ordem de pintura entre elementos hoistados (por ordem de descoberta, não z-index) colocava vizinhas na frente da carta em movimento. Corrigido: no máximo uma carta por vez pode ter um nome não-`"none"` (novo estado `transitionTargetId`, `cartas-gallery.tsx`), atribuído à carta clicada por um `flushSync` fora da transição (para já existir no snapshot "antigo") e movido para o modal pela própria transição, como antes — só que isolado a uma única carta. `tsc --noEmit` confirmado limpo. |
| 1.8 | **Correção: espaço "solto" entre identificação e símbolo (2026-07-31, mesmo dia).** Fabrício ainda achou o símbolo distante: "prefiro mais compacto... o símbolo parece solto na tela". Causa: não era a margem entre os dois elementos, mas o `<span>` do `RaritySymbol` herdando o line-height ambiente (bem maior que os 7px do ícone), deixando uma faixa de espaço em branco embutida no próprio símbolo. Corrigido com `leading-none` em `RaritySymbol` e no `<p>` de identificação. `tsc --noEmit` confirmado limpo. |
| 1.9 | **Espaço entre identificação e símbolo reduzido mais uma vez (2026-07-31, mesmo dia).** Pedido direto de Fabrício após a revisão `1.8`: "reduza um pouco mais o espaço". `space-y-0.5` → `space-y-0` no contêiner de `CartaGridCard` — com `leading-none` já eliminando o espaço embutido nos dois elementos (revisão `1.8`), a margem explícita era o que restava para reduzir. `tsc --noEmit` confirmado limpo. |
| 1.10 | **Distância entre a carta e a identificação aumentada (2026-07-31, mesmo dia).** Fabrício confirmou que `space-y-0` (revisão `1.9`) é o mínimo prático entre identificação e símbolo, e pediu o ajuste complementar: com print de uma carta com o mouse sobre a imagem, "aumente um pouco a distância da carta e a identificação" — o `scale3d(1.045, ...)` do hover holográfico (`HoloCard`) é só `transform`, não reflui os elementos vizinhos, então a carta cresce visualmente por cima do respiro entre ela e o texto abaixo, quase encostando com o `gap-1.5` anterior. `gap-1.5` → `gap-2.5` no contêiner de `CartaGridCard` (o espaço identificação↔símbolo não foi tocado, já no mínimo). `tsc --noEmit` confirmado limpo. |
| 1.11 | **Correção: busca por número não encontrava a carta (2026-07-31, mesmo dia).** Fabrício reportou, com print buscando "001/086" na tela Cartas: "informa que a carta não foi encontrada". Causa: a busca comparava só `collectorNumber` cru ("001"), nunca `collectorTotal` — nunca tinha sido atualizada para considerar o texto completo exibido ("001/086") depois do padding de 3 dígitos introduzido na revisão `1.6`. Novo helper `cartaFullNumber()` monta exatamente o mesmo texto mostrado em `CartaGridCard` e passa a ser usado tanto na exibição quanto na busca — buscar por "001", "086" ou "001/086" agora encontra a carta igualmente. `tsc --noEmit` confirmado limpo. |
| 1.12 | **Filtro de Jogo adicionado, hierarquia Jogo→Expansão→Coleção, opção "Selecionar Todos" (2026-07-31, mesmo dia).** Pedido de Fabrício: (1) rótulo da Expansão não precisa mais repetir o nome do Jogo; (2) novo seletor de Jogo, primeiro na ordem, respeitando a hierarquia; (3) "Selecionar Todos" nos três. Pergunta explícita sobre o terceiro nível (Card Set é quem decide quais cartas a tela busca — o que "Todos" significaria ali?), respondida por Fabrício: Jogo/Expansão resetam livremente, mas Card Set não ganha um "Todos" funcional — ao escolher "Todos" em Jogo ou Expansão, a tela navega automaticamente para o Card Set mais recente do escopo resultante (mesmo mecanismo que já existia para Expansão→Coleção, agora também cobrindo Jogo). `selectedGameId`/`selectedExpansionId` continuam sendo derivados do Card Set selecionado (nunca estado próprio) — como a página remonta a cada troca de `?set=` (`key={selectedCode}`), os seletores sempre refletem o Jogo/Expansão reais do Card Set exibido, nunca ficando "presos" num valor que não bate com a tela. `tsc --noEmit` confirmado limpo. |
| 1.13 | **Correção: seletor de Jogo não listava todos os Jogos cadastrados (2026-07-31, mesmo dia).** Fabrício reportou, com print mostrando só "Pokémon Trading Card Game" na lista: "o primeiro componente não exibi todos os jogos cadastrados". Causa: a revisão `1.12` montava `gameOptions`/`expansionOptions` a partir de `cardSets` — um Jogo ou Expansão recém-cadastrado em `/catalogo/jogos`/`/catalogo/expansoes`, ainda sem nenhum Card Set, ficava invisível nos dois seletores, e `selectedGameId`/`selectedExpansionId` (derivados só do Card Set selecionado) nunca conseguiriam representar esse estado mesmo se aparecessem. Corrigido com duas mudanças: (1) `page.tsx` passa a buscar `games`/`expansions` via `getGameOptions()`/`getExpansoes()` (já existentes, usadas em outras telas) — todo o cadastro, não só o que já tem Card Set; (2) `selectedGameId`/`selectedExpansionId` passam a ser resolvidos em `page.tsx` a partir de `set`/`expansion`/`game` na URL (nessa ordem de prioridade), não mais só derivados do Card Set — um Jogo/Expansão escolhido sem nenhum Card Set ainda é um estado legítimo, com uma tela vazia dedicada (`!selectedCardSet` em `CartasGallery`, distinta de "Card Set existe mas está vazio"). `tsc --noEmit` confirmado limpo. |
| 1.14 | **Cabeçalho da Coleção selecionada reescrito, nome como protagonista (2026-07-31, mesmo dia).** Pedido de Fabrício: "precisamos tornar o nome da coleção protagonista" — a antiga linha `X de Y cartas · Nome` (pequena, discreta) virou um bloco de cabeçalho: (1) `"{code} - {name}"` em destaque (`text-base`/`sm:text-lg font-semibold`, fonte maior que qualquer outro texto da tela); (2) logo abaixo, todas as informações da Coleção pedidas — `SetTypeTag` (badge já existente, reaproveitado), data de lançamento (`formatarData()`, já existente) e o total de cartas com a quebra base/secretas (`"94 cartas (86 base + 8 secretas)"`, novo helper `formatCardSetTotals()` — secretas = `totalSetSize - baseSetSize`, mesma fórmula do comentário de `120_create_card_set_table.sql`; Card Sets sem secretas, como `PROMO`/`ENERGY`, mostram só `"N cartas"`); (3) a contagem de busca/filtro (`X de Y cartas exibidas`) preservada, agora como linha auxiliar abaixo do cabeçalho, não mais a única informação. `baseSetSize`/`totalSetSize` (`card_set.base_set_size`/`total_set_size`) adicionados a `CatalogoCardSetRow` — não estavam na query antes, só usados internamente para cadastro/edição. `tsc --noEmit` confirmado limpo. |
| 1.15 | **Logo da Coleção e rótulo "Data de lançamento:" no cabeçalho (2026-07-31, mesmo dia).** Pedido de Fabrício, com print do cabeçalho da revisão `1.14`: (1) "incluir a logo da coleção antes (a esquerda) de todo esse bloco de informações"; (2) "antes da data de lançamento inclua o label 'Data de lançamento: '". A busca de logos assinadas (`getCardSetLogoUrls()`, já usada para os 3 cards de destaque) foi estendida em `page.tsx` para incluir também o caminho do Card Set selecionado (pode não estar entre os 3 mais recentes, ex.: escolhido via busca/filtro) — um único `Set<string | null>` deduplicado, um único round-trip ao Storage. `selectedLogoUrl` passa a ser prop de `CartasGallery`. O cabeçalho virou um `flex items-start gap-3`: caixa de 36px (`h-9 w-9 rounded-md`) à esquerda com a logo (`object-contain`) ou, na ausência, as iniciais do nome da Coleção (mesmo padrão visual já usado em `CardSetChip`); o bloco de código/nome + metadados (revisão `1.14`) segue à direita, agora dentro de um `min-w-0` para preservar o truncamento de texto no layout flex. O rótulo "Data de lançamento: " foi adicionado como prefixo literal antes de `formatarData(selectedCardSet.releaseDate)`. `tsc --noEmit` confirmado limpo. |
| 1.16 | **Logo ampliada e contagem de cartas unificada em uma linha (2026-07-31, mesmo dia).** Dois ajustes de Fabrício sobre o cabeçalho da revisão `1.15`: (1) "a logo ficou muito pequena. Vamos ampliar" — caixa de `h-9 w-9` (36px) para `h-14 w-14` (56px), com padding interno e fonte das iniciais (fallback sem logo) proporcionalmente maiores; (2) formato da contagem de cartas: "124 cartas (88 base + 36 secretas) - Exibidas 124 de 124 cartas" — antes eram duas linhas separadas (total do Card Set acima, contagem de busca/filtro abaixo), agora uma linha só combinando `formatCardSetTotals()` (já existente, revisão `1.14`) com "Exibidas X de Y cartas" (ordem invertida em relação à revisão `1.14`, que dizia "X de Y cartas exibidas"). `tsc --noEmit` confirmado limpo. |
| 1.17 | **Logo em 70px e alternador de imagem PT/EN (2026-07-31, mesmo dia).** Dois ajustes de Fabrício sobre o cabeçalho da revisão `1.16`: (1) "vamos testar a logo com 70 px" — caixa de `h-14 w-14` (56px) para `h-[70px] w-[70px]`, padding interno e fonte das iniciais (fallback) ajustados na mesma proporção; (2) "do lado oposto das informações da coleção, incluir um componente para alternar entre imagens das cartas em PT e IN" — novo `ImageLanguageToggle` (segmented control "PT"/"EN"), posicionado à direita do bloco logo+informações via `justify-between` no contêiner do cabeçalho, só aparece quando o Card Set tem os dois idiomas de fato importados (`hasBothImageLanguages`, calculado sobre `cartas`). Suporte de dados: `pickCardFrontPath()` em `queries.ts` deixou de escolher um único idioma por prioridade (`IMAGE_LANGUAGE_PRIORITY`, pt-BR > en) e passa a resolver os dois separadamente — `CartaCompletaRow.imageUrl` virou `imageUrlPt`/`imageUrlEn`. Novo helper `cartaImageUrl(carta, idioma)` em `cartas-gallery.tsx` escolhe a imagem do idioma selecionado com fallback para o outro idioma quando aquela carta específica não tem os dois importados (evita "Sem imagem" quando existe imagem, só que no idioma que não foi escolhido). Estado `imageLanguage` é local ao componente (não vai para a URL), resetado a cada troca de Coleção pelo mesmo `key={selectedCode}` que já reseta busca/filtros. `tsc --noEmit` confirmado limpo. |
| 1.18 | **Barra "Recentes" substituída por indicadores; seleção padrão passa a exigir cartas cadastradas (2026-07-31, mesmo dia).** Dois pedidos de Fabrício, com print da barra "Recentes" (3 chips de Card Set + seletor "outra coleção"): (1) "vamos remover esse card do topo da página. Perdeu o sentido de tê-lo... com os filtros que incluímos. No lugar... indicadores relacionado com o tema cartas" — bloco removido (`CardSetChip`, `recentCardSets`, seletor "outra coleção" e o fetch dos 3 logos em destaque em `page.tsx`), substituído por `CartasStats` (novo componente, mesmo padrão `StatCard`/`StatsRow` de `CardSetsStats`/`JogosStats`): "Cartas" (total catalogado), "Coleções", "Média" (cartas por coleção, truncada) e "Sem Cartas" (`tone="danger"`, coleções com 0 cartas). (2) "ao clicar no menu cartas, a página deve trazer carregada as cartas do último card set com cartas cadastradas. Caso as cartas ainda não tenham imagens carregadas, use placehold" — a seleção padrão (sem `set`/`expansion`/`game` na URL) deixou de ser cegamente `cardSets[0]` (Card Set mais recente, podendo estar vazio) e passa a ser o primeiro Card Set, em ordem de mais recente, com `cardsCatalogados > 0` (fallback para `cardSets[0]` se nenhum tiver cartas ainda); a parte de imagens já era coberta pelo estado "Sem imagem" existente em `CartaGridCard`/`CartaZoomDialog`, sem mudança necessária. Suporte de dados: `getCardSetsForCartas()` (`queries.ts`) passou a popular `cardsCatalogados` de fato (buscava com `Map()` vazio antes, contagem sempre 0) via `getCardCountsForSets()`, já usada por `getCardSetsForCatalogo`/`getEstadoDoCatalogo` — sem query nova, mesmo padrão reaproveitado. `tsc --noEmit` confirmado limpo. |
| 1.19 | **`CartasStats` reescrito com a lista fechada de 5 indicadores pedida por Fabrício (2026-07-31, mesmo dia).** Pedido explícito: "1. Quantidade de cartas 2. Quantidade de variações cadastradas 3. Quantidade de imagens em nossa base 4. Quantidade de coleções sem cartas 5. Quantidade de cartas sem imagens" — substitui o rascunho da revisão `1.18` (Cartas/Coleções/Média/Sem Cartas). "Cartas" e "Sem Cartas" continuam deriváveis de `cardSets`/`cardsCatalogados`, sem consulta nova. Os outros três vêm da nova `getCartasCatalogoStats(supabase, totalCartas)` (`queries.ts`), buscada em `page.tsx` e passada por `CartasGallery` como prop `cartasStats`: (a) "Variações" — `count(card_variant)` (Query 160, cada linha é uma variante colecionável cadastrada, ex.: STANDARD/REVERSE_HOLO); (b) "Imagens" — `count(card_asset)` (Query 180, todo ativo digital registrado, não só CARD_FRONT); (c) "Sem Imagens" — `totalCartas` menos a contagem de Cards distintos com pelo menos um `card_asset` primário do tipo CARD_FRONT (`card_asset_type!inner(code)` + `.eq("card_asset_type.code", "CARD_FRONT")`, mesmo padrão de filtro por tabela relacionada já usado em `fetchCardSetsForCatalogo`), mesmo critério que decide o placeholder "Sem imagem" no grid/modal. "Sem Cartas" e "Sem Imagens" levam `tone="danger"` (os dois são indicadores de dado faltante). `tsc --noEmit` confirmado limpo. |
| 1.20 | **Filtros de Raridade/Categoria: checkboxes substituídos por chips multi-seleção (2026-07-31, mesmo dia).** Pedido de Fabrício: "os filtros de Raridade e Categoria ainda estão com aparência de formulário HTML (checkboxes) e destoam da linguagem visual do restante do Catálogo... substitua os checkboxes por chips de filtro multi-seleção, seguindo a mesma linguagem visual já utilizada nos filtros de Jogos", com a ressalva explícita de manter "exatamente o mesmo comportamento atual" (lógica/estado/consultas intocados) — só a marcação visual de `FilterGroup` mudou. Reaproveita as classes de `Chip` em `catalogo-filter-chips.tsx` (filtro de Jogo/Expansão): `rounded-full border px-3 py-1 text-xs font-medium`, ativo `border-primary/40 bg-primary/5 text-primary`, inativo `border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground` — mas como `<button aria-pressed>` em vez de `Link` (aqui é multi-seleção via `Set` local, não navegação de rota de seleção única). Contagem embutida no rótulo do chip ("Comum (43)"), pedido explícito. Rótulo do grupo ("Raridade"/"Categoria") passou de linha própria acima dos itens para inline ao lado dos chips, e o contêiner dos dois grupos passou de lado-a-lado (`flex-wrap gap-x-8`) para empilhado (`space-y-1.5`) — reduz a altura ocupada pelo bloco de filtros (também pedido explícito). Nenhum outro elemento da tela foi alterado. `tsc --noEmit` confirmado limpo. |
| 1.21 | **Chips de Raridade/Categoria: rótulo volta para linha própria, 12px entre os grupos (2026-07-31, mesmo dia).** Ajuste de Fabrício sobre a revisão `1.20`: "use esse esquema: RARIDADE / chips / (12px) / CATEGORIA / chips" — reverte o rótulo inline (ao lado dos chips) da revisão anterior de volta para linha própria acima dos chips dentro de cada `FilterGroup` (`space-y-1.5` interno, mesma estrutura de antes dos checkboxes), e fixa a separação entre os blocos "Raridade" e "Categoria" em exatamente 12px (`space-y-3` no contêiner pai, era `space-y-1.5`). Só espaçamento/estrutura de rótulo mudou — chips, contagem embutida, multi-seleção e `tone` continuam iguais à revisão `1.20`. `tsc --noEmit` confirmado limpo. |
| 1.22 | **Espaçamento entre os blocos "Raridade" e "Categoria" ajustado de 12px para 16px (2026-07-31, mesmo dia).** Pedido de Fabrício, ajuste fino sobre a revisão `1.21`: "aumente o espaçamento entre os blocos... para 16px" — `space-y-3` (0.75rem/12px) → `space-y-4` (1rem/16px) no contêiner que empilha os dois `FilterGroup`. Nenhuma outra mudança. `tsc --noEmit` confirmado limpo. |
| 1.23 | **Fundo da logo no cabeçalho da Coleção removido; só a altura (70px) é controlada (2026-07-31, mesmo dia).** Pedido de Fabrício: "o fundo da logo deve ser transparente e vamos manter a altura em 70px e deixar a imagem ajustar a largura. Vamos controlar apenas a altura". A caixa quadrada fixa (`h-[70px] w-[70px]`, `bg-surface-muted`, `rounded-md`, `overflow-hidden`, `object-contain p-2`) da revisão `1.17` fazia sentido para o fallback de iniciais (precisa de uma área para centralizar o texto), mas emolduava a logo real sem necessidade e distorcia proporção quando a imagem não era quadrada. Com logo cadastrada: `<img>` direta, sem contêiner/fundo/borda, só `h-[70px] w-auto object-contain` — altura fixa em 70px, largura livre conforme a proporção original do arquivo. Sem logo cadastrada: mantém a caixa 70×70 com `bg-surface-muted` e iniciais (mesmo fallback de `CardSetChip`/`getInitials`) — o pedido foi especificamente sobre "a logo", não sobre o placeholder de iniciais, que continua precisando de uma área visual. `tsc --noEmit` confirmado limpo. |
| 1.24 | **Logo do cabeçalho ganha teto de largura (250px), além do teto de altura (70px) — proporção original sempre preservada (2026-07-31, mesmo dia).** Pedido de Fabrício: "a largura máxima permitida para a logo é 250px. Vamos limitar a altura a 70px ou largura de 250px. A imagem deve manter a proporção original, sem exceder esses limites. A imagem não deve ser redimensionada em hipótese alguma" — a revisão `1.23` fixava `h-[70px] w-auto`, sem teto de largura: uma logo muito larga e baixa (ex.: wordmark horizontal) podia esticar sem limite no eixo horizontal. Trocado para `h-auto max-h-[70px] w-auto max-w-[250px]`: nenhuma dimensão é forçada — a imagem renderiza no tamanho original até esbarrar num dos dois tetos (altura OU largura, o que vier primeiro), e a proporção é sempre preservada porque é o comportamento nativo do navegador para `max-height`/`max-width` combinados com `height`/`width: auto` (não depende de `object-fit`, já que não há caixa de dimensões fixas para a imagem "encaixar"/distorcer — `object-contain` mantido só como reforço defensivo, sem efeito prático nesse caso). `tsc --noEmit` confirmado limpo. |
| 1.25 | **Segunda reorganização do menu secundário do Catálogo (2026-08-01), início do subciclo Card criação/variações/importação de imagens.** Pedido de Fabrício: "1. Reorganize o bloco de Operações, deixando os itens: 'Importar Cartas' e 'Importar Imagens' 2. No bloco Gerencial, inclua o item Log de Atualizações". (1) Bloco "Operações" (`nav-config.ts`) trocou a categorização por método de importação ("Importação Manual"/"Via PDF"/"Via API" — só stubs, nunca implementada) por categorização pelo que é importado: "Importar Cartas" (`/catalogo/importar-cartas`, ícone `FileUp`) e "Importar Imagens" (`/catalogo/importar-imagens`, ícone `ImagePlus`). As rotas antigas (`importacao-manual`/`-pdf`/`-api`) perderam o item de menu, mas os arquivos de página permanecem no repositório — não podem ser removidos sem autorização explícita de Fabrício. (2) Bloco "Gerencial" ganhou "Log de Atualizações" (`/catalogo/log-atualizacoes`, ícone `ScrollText`) — trilha de auditoria de escrita administrativa (`catalog_admin_action_log`, `ADR-023`), distinta do "Histórico de Importações" já existente no mesmo bloco (execuções do pipeline de imagens, `asset_import_run`). Três novas rotas ganharam página stub (`ComingSoonPage` + `requireCatalogoAdmin()`, mesmo padrão já usado em todo o módulo) — item de menu não pode levar a 404 (bug já reportado por Fabrício, 2026-07-25). Nenhuma Query SQL nova; mudança só de navegação/apresentação. `tsc --noEmit` confirmado limpo (10 erros pré-existentes em `lib/supabase/middleware.ts`/`server.ts`, inalterados). |
| 1.26 | **Botão "Importar Cartas" na tela Cartas + estrutura visual da página Importar Cartas (2026-08-01, mesmo dia).** Pedido de Fabrício: "na página cartas, vamos incluir o botão de 'Importar cartas'... deve seguir o mesmo padrão das demais páginas de cadastro" e "na página de importação de cartas, vamos ter as opções de importar cartas via pdf (lista de verificação oficial - modelo em anexo) ou importar via API (TCGDEX) para as coleções que ainda estão sem cartas cadastradas". (1) `CartasGallery` ganhou o botão "Importar Cartas" (`Link` para `/catalogo/importar-cartas`), mesma posição/padrão visual de "Nova Coleção"/"Nova expansão"/"Novo Jogo" (linha própria com `flex justify-end`, logo acima do `Card` de busca/conteúdo) — mas navega em vez de abrir Dialog, já que a importação em lote é um fluxo próprio, não um cadastro individual. (2) `/catalogo/importar-cartas` deixou de ser `ComingSoonPage` — novo componente `ImportarCartasView` mostra dois cartões lado a lado, "Importar via PDF" e "Importar via API (TCGDex)", cada um ainda com selo "Em construção" (`Badge variant="outline"`), sem lógica de importação real nesta rodada. O cartão da API reaproveita `getCardSetsForCartas()` (mesma consulta de `CartasStats`) para mostrar quantas Coleções estão sem nenhuma carta cadastrada — só contextualiza o escopo, nenhuma Coleção é listada nominalmente. **Anexo pendente:** o modelo da lista de verificação oficial em PDF, mencionado pelo pedido, não chegou anexado a esta rodada (confirmado por Fabrício, que disse que reenviaria) — o detalhamento do fluxo PDF (upload, parsing, mapeamento de campos) fica para quando o anexo chegar; o fluxo da API TCGDex também segue sem detalhamento (autenticação, endpoints, regra de mapeamento) por decisão explícita de escopo desta rodada ("só a estrutura visual"). `tsc --noEmit` confirmado limpo (10 erros pré-existentes, inalterados). |
| 1.27 | **Indicador "Variações" removido de `CartasStats` (2026-08-01, mesmo dia).** Pedido de Fabrício: "após a inserção do botão 'Importar Cartas' a harmonia visual da página foi impactada. Para corrigir isso, remova o indicador VARIAÇÕES desta página" — a linha de 5 indicadores (revisão `1.19`) mais o novo botão acima do `Card` de busca (revisão `1.26`) deixaram o bloco superior da tela carregado; retirar um cartão reequilibra o espaço sem mexer no botão em si. `CartasStats` passa a mostrar 4 indicadores: Cartas, Imagens, Sem Cartas, Sem Imagens. Só o cartão saiu — `stats.totalVariacoes` continua calculado em `getCartasCatalogoStats()` (`queries.ts`, `count(card_variant)`), sem consumidor nesta tela por ora, mas preservado no shape de retorno caso volte a ser útil (ex.: outra tela, ou reintrodução futura). `tsc --noEmit` confirmado limpo (10 erros pré-existentes, inalterados). |
| 1.28 | **Correção real: espaço entre o botão "Importar Cartas" e o `Card` de busca/conteúdo destoava das demais telas de cadastro (2026-08-01, mesmo dia).** Pedido de Fabrício, com prints comparando Cartas e Coleções lado a lado: "padronize o espaço do botão e da tabela abaixo. Veja a diferença nas imagens". Causa raiz: em `CartaGallery`, o botão "Importar Cartas" (revisão `1.26`) tinha sido inserido como irmão solto do `Card` dentro do `space-y-4` externo (16px, o mesmo espaço usado entre `PageHeader`/`CartasStats`/conteúdo) — nas outras três telas de cadastro (Jogos/Expansões/Coleções), botão e `Card` sempre estiveram juntos dentro de um `space-y-2` próprio (8px), mais apertado que o espaçamento entre seções da página. Corrigido envolvendo o botão e o bloco `Card` (as duas ramificações do ternário `cardSets.length === 0`) num único `<div className="space-y-2">`, igualando a estrutura das demais telas — nenhuma outra mudança visual ou de comportamento. `tsc --noEmit` confirmado limpo (10 erros pré-existentes, inalterados). |
| 1.29 | **`admin_update_card_set()` ampliada para aceitar `code`, condicionalmente editável (Query 2048 v3.0, Migration 2091), 2026-08-01.** Fabrício percebeu um erro real de cadastro (Coleção "151", Expansão `SV`, registrada com código `SV4` em vez de `MEW`) e pediu a correção mais a capacidade de editar pela própria tela, restrita a "só não será permitido se já houver cartas cadastradas" — revisão parcial da decisão original do `ADR-023` (`code` "imutável por construção"), formalizada como nova emenda "Card Set: código editável sem Cards cadastradas". Assinatura passa de 5 para 6 parâmetros (`p_code` novo); `expansion_id` continua totalmente fora. Trava condicional: código só é alterável enquanto `EXISTS (SELECT 1 FROM card WHERE card_set_id = p_id)` for falso — com qualquer Card já cadastrada (ativa ou inativa), tentar mudar falha com `ADMIN_UPDATE_CARD_SET_CODE_LOCKED`; duplicidade dentro da Expansion continua verificada (`ADMIN_UPDATE_CARD_SET_DUPLICATE_CODE`). Assinatura muda → arquivo canônico `2048` bump para v3.0 + nova Migration `2091` (`DROP FUNCTION` + `CREATE FUNCTION`) para reconciliar o banco já instalado, mesmo padrão da Migration `2052`. Frontend: `EditCardSetForm` ganhou o campo Código, editável só quando `cardSet.cardsCatalogados === 0`. **Correção pontual aplicada de imediato**: como a Coleção "151" não tinha nenhuma Card cadastrada e `MEW` não colidia com nenhum outro código da Expansão `SV` (ambos verificados antes de agir), o dado foi corrigido diretamente no banco (`UPDATE card_set SET code = 'MEW'`) com o registro correspondente em `catalog_admin_action_log` (`actor_id NULL`, ação fora de sessão de aplicação, antes da Migration `2091` estar confirmada executada) — não dependeu da execução da migration para ser resolvida. **Migration `2091` e Validação `2815` confirmadas executadas por Fabrício em 2026-08-01.** |
| 1.30 | **Continuação automática cartas → imagens, emenda de `ADR-024` (Query 2092, `admin_start_asset_import_run()`), 2026-08-01.** Pedido explícito de Fabrício: "Após a confirmação das cartas, o fluxo de importação deve continuar automaticamente com a importação das imagens do Card Set", preservando o pipeline manual existente (`import-card-assets`) intocado — Card Sets sem cobertura na TCGdex (Promo, Energia) continuam dependendo dele. Nova função `admin_start_asset_import_run(p_card_set_id, p_run_type, p_initiated_by)` (`SECURITY DEFINER`, só admin) formaliza a abertura de uma linha em `asset_import_run` (Query 220) — até aqui feita só por SQL manual avulso por Coleção — sem duplicar nenhuma lógica do pipeline em si: "suporte" é a existência de `card_set_external_reference` ativo para (Card Set, TCGDEX), o mesmo dado que `import-card-assets` já exige e que `import-catalog-cards` já grava durante a própria importação de Cards; ausência devolve `supported = false` sem lançar exceção (caminho normal, não erro); uma run `PENDING`/`RUNNING` já existente para o mesmo Card Set é reaproveitada (`already_active = true`) em vez de duplicada. `iniciarImportacaoImagens()` (Server Action, `tcgdex/actions.ts`) chama essa RPC e, se `supported`, invoca `import-card-assets` (mesmo padrão de `fetch` sem header de autorização já usado por `iniciarImportacaoTcgdex`) — disparada por um novo `useEffect` em `useAnalyzeJob()` (agora recebendo `cardSetId`), exatamente uma vez, assim que o job de cartas chega a `COMPLETED`/`COMPLETED_WITH_ERRORS` (nunca `FAILED`/`CANCELLED`). `ImportProgress` ganhou três novas etapas condicionais — "Verificando disponibilidade das imagens", "Importando imagens", "Finalizando importação" — que só aparecem junto dessas duas conclusões de job; a etapa antes chamada "Concluído com falhas"/"...com sucesso" (rótulo dinâmico) foi renomeada para o rótulo fixo "Gravando cartas", pedido explícito de Fabrício para a nova sequência de nomes. Falta de suporte na TCGdex e falhas parciais de imagem são tratadas como caminho informativo, não erro — a etapa final resume "Cartas cadastradas / Imagens importadas / Imagens pendentes", com as pendentes seguindo resolvíveis pelo pipeline manual. Nenhuma alteração em `import-card-assets` (inclusive sua limitação conhecida de idioma fixo `en`, herdada sem mudança). **Query `2092` e Validação `2816` confirmadas executadas por Fabrício em 2026-08-01.** |
| 1.31 | **Bug real de produção corrigido: `admin_start_asset_import_run()` nunca conseguia abrir uma run (2026-08-02).** Primeiro uso real da continuação automática (Coleção "151"/`MEW`, revisão `1.30`) falhou na etapa "Importando imagens" com mensagem genérica; confirmado nos logs do Postgres: `ERROR: column reference "run_code" is ambiguous`. Causa: `RETURNS TABLE (..., run_code TEXT, ...)` declara uma variável implícita `run_code` visível em toda a função (característica de PL/pgSQL) — as duas leituras de `asset_import_run.run_code` por nome solto ficavam ambíguas entre a coluna e essa variável, e a função nunca chegava a inserir a run. Corrigido na Query `2092` v1.1 qualificando a coluna (`asset_import_run.run_code`) nas duas consultas; assinatura não muda, `CREATE OR REPLACE` é suficiente (mesmo padrão da correção `ENERGY` em `admin_create_card_set()`, Query `2051` v1.1). Validação `2816` v1.1 ganhou uma consulta nova que comprova a correção diretamente (lista runs `SYSTEM` reais). **Consequência colateral encontrada e corrigida junto**: a mesma falha (não a de `run_code`, uma anterior e independente) explica por que `card_set_external_reference` da Coleção "151" apontava para o Set errado da TCGdex (`sv04`/Fenda Paradoxal, de uma primeira tentativa de correspondência equivocada) em vez do correto (`sv03.5`, o que de fato originou as 207 cartas importadas) — `import-catalog-cards` tenta corrigir essa referência a cada nova análise via upsert, mas `external_set_id` é imutável por trigger (`govern_card_set_external_reference`, decisão estrutural preexistente, fora do escopo deste ciclo) e o erro da tentativa de correção era só logado (`console.error`), nunca propagado — a importação de Cards terminava "com sucesso" mesmo com a referência de imagem errada por baixo. Corrigido pontualmente (mesmo padrão da correção `SV4`→`MEW`): `DELETE` da linha errada + `INSERT` da linha correta para este Card Set específico — não uma mudança de arquitetura; a imutabilidade de `external_set_id` em si permanece intacta, sinalizada para uma futura decisão de Fabrício caso o caso se repita. Frontend: `imagesPendentes` em `ImportProgress` (`importar-tcgdex-view.tsx`) também tratava incorretamente uma falha real (`imageHardError`) como "0 pendentes" — corrigido para tratar qualquer falha real, além de "sem suporte", como todas as cartas gravadas ficando pendentes. **Correções confirmadas executadas por Fabrício em 2026-08-02** (Query `2092` v1.1, Validação `2816` v1.1, correção pontual da referência TCGdex — `card_set_external_reference` de "151" confirmado apontando para `sv03.5`). |
| 1.32 | **Correção pontual de dado: código da Coleção "151" de `MEW` para `SV3.5` (2026-08-02).** Fabrício identificou que o código correto desta Coleção especial é `SV3.5` (mesmo padrão de `ME2.5`, já cadastrada) — `MEW` estava errado desde o início; a correção anterior (revisão `1.29`) tinha só trocado `SV4` por esse valor igualmente incorreto. Como a Coleção já tem 207 Cards cadastradas, a própria trava introduzida pela Query `2048` v3.0 (`ADMIN_UPDATE_CARD_SET_CODE_LOCKED`) impede a correção pela tela — pedido explícito de Fabrício para corrigir direto no banco antes de tentar a importação de imagens. Sem colisão (nenhum outro Card Set da Expansão `SV` usa `SV3.5`) e sem impacto em `card_set_external_reference`/`asset_import_run` (ambos referenciam o Card Set por `id`, nunca por `code`) — corrigido diretamente (`UPDATE card_set SET code = 'SV3.5'`) com o registro correspondente em `catalog_admin_action_log` (`actor_id NULL`, mesmo padrão da correção `SV4`→`MEW`). Confirmado via `SELECT`: código agora é `SV3.5`. |
| 1.33 | **Dois bugs de UX corrigidos + causa raiz de falha em Coleção grande identificada e Query `2092` v1.2 escrita (2026-08-02, mesmo dia).** Primeiro teste real com uma Coleção grande (SV4/Fenda Paradoxal, 266 cartas) expôs dois problemas de frontend reportados por Fabrício: (1) a barra de progresso de `ImportProgress` saltava para 100% assim que o job de cartas chegava a `COMPLETED`, mesmo com a etapa "Importando imagens" ainda em andamento — corrigido com um novo estado derivado (`willRunImageSteps`/`imagesInFlight`/`fullyDone`) e um teto de porcentagem próprio para a fase de imagens (`IMAGE_PERCENT_CEILING = 97`, abaixo do teto de 100% real), só liberado quando a fase de imagens de fato termina; o rótulo acima da barra passou a distinguir "Importando imagens..." de "Processando importação...". (2) em falha (rede ou HTTP não-2xx), `iniciarImportacaoImagens()` sempre devolvia `imagesImported = 0` mesmo quando parte das imagens já tinha sido gravada de verdade — corrigido com um novo helper `contarImagensImportadas()` (`tcgdex/actions.ts`) que consulta a contagem real de `card_asset`/`card` para o Card Set antes de responder, usado nos dois caminhos de erro (`catch` e `!response.ok`) em vez de zerar os contadores. **Causa raiz da falha em si (não corrigida — arquitetural, fora do escopo autorizado por Fabrício de não alterar o pipeline manual):** a Edge Function `import-card-assets` processa a Coleção inteira numa única invocação e só grava o resultado final de `asset_import_run` (contadores, status) uma única vez, no fim (`finishImportRun()`); numa Coleção grande o bastante (266 cartas), a função estourou o tempo de execução da plataforma e foi encerrada no meio (`HTTP 546`), sem nunca chegar a `finishImportRun()` — as imagens já processadas até ali (115, confirmadas por Fabrício direto no Storage) ficaram gravadas normalmente (`card_asset` é escrito de forma incremental, dentro do laço de processamento), mas a run em si ficou presa em `RUNNING` para sempre. Consequência prática grave: a regra "evita runs duplicadas" da Query `2092` (v1.0/v1.1) trata qualquer run `PENDING`/`RUNNING` como `already_active`, então nenhuma nova tentativa de importação de imagens para aquele Card Set conseguia mais chamar a Edge Function — bloqueio permanente. Corrigido na Query `2092` v1.2 (SQL preparado, aguardando execução): a busca por run ativa passa a ignorar linhas `PENDING`/`RUNNING` com mais de 15 minutos (janela generosa acima de qualquer execução plausível da Edge Function); ao encontrar uma dessas linhas "presas", a função a fecha como `FAILED` (`error_summary` explicando o motivo, `finished_at = NOW()`) antes de abrir a nova run normalmente, em vez de só ignorá-la. Validação `2816` ganhou uma quarta consulta (query 4) para comprovar isso diretamente contra a run travada real do Card Set SV4. |
| 1.34 | **Nova tela `/catalogo/importar-imagens`, substitui o stub (2026-08-02, mesmo dia).** Consequência prática do bug descrito na revisão `1.33`: depois que a Coleção SV4 ganha Cards cadastradas, o seletor de `Importar Cartas` (`getCardSetsForCartas` filtrado por `cardsCatalogados === 0` ou job incompleto) para de listá-la — sem jeito de retomar a importação de imagens pela tela, mesmo depois da Query `2092` v1.2 destravar a run. Pedido explícito de Fabrício: "precisamos criar a página dedicada a importação de imagens... cópia da Importação de Cartas em termos de layout, e com funcionalidades parecidas", com dois requisitos: (1) o combobox lista Coleções com Cards cadastradas e pelo menos uma imagem pendente (nunca importada, falha parcial ou falha total — mesma condição cobre os três casos); (2) os passos de progresso começam direto na importação de imagens, sem etapas de análise/gravação de cartas. Implementado: `getCardSetsForImportacaoImagens()` (nova, `queries.ts`) — reaproveita `getCardSetsForCartas()`, filtra por `cardsCatalogados > 0`, e cruza com uma nova contagem por Card Set de Cards com pelo menos uma imagem primária CARD_FRONT (`getImagesImportadasPorCardSet()`, mesmo critério/consulta de `getCartasCatalogoStats`, agrupado por `card_set_id` via embed `card!inner(card_set_id)` — mesmo padrão já usado por `contarImagensImportadas`, revisão `1.33`); só entram Coleções com `imagesPendentes > 0`. `iniciarImportacaoImagens()` (`tcgdex/actions.ts`) generalizada: o parâmetro `jobId` virou `initiatedBy` (texto livre gravado em `asset_import_run.initiated_by`, só rastreabilidade) — a continuação automática continua passando `catalog_import_job:<id>`, a tela nova passa `manual_retry:importar-imagens`; nenhuma lógica de negócio mudou, a mesma função/RPC/Edge Function são reaproveitadas (sem segundo pipeline, sem duplicação). `ImportProgress` (`importar-tcgdex-view.tsx`) ganhou `mode="images-only"` — quando ativo, as etapas "Abrindo job"/"Buscando cartas"/"Processando"/"Concluído"/"Gravando cartas" somem da lista (não haveria job de cartas para elas descreverem), a barra de progresso e o resumo final passam a depender só da fase de imagens (`totalCards`, nova prop, substitui `job.insertedRows + job.updatedRows` no resumo), e o rótulo "Cartas cadastradas" some do resumo final (a Coleção já tinha todas as Cards de antes). Novo componente `ImportarImagensView` (`importar-imagens-view.tsx`) espelha o layout de `ImportarCartasView` (mesmo `PageHeader`/ícone, mesmo `StatsRow` de dois indicadores — "Coleções Pendentes" e "Sem Imagens", esta última somando o mesmo `imagesPendentes` que alimenta o filtro do combobox, então bate com o indicador global já existente na tela `Importar Cartas`) — sem Fonte (API/PDF) nem Revisão, só o combobox e o botão "Importar Imagens", que chama `iniciarImportacaoImagens` direto (sem `<form>`/`useActionState`, via `useTransition`) e renderiza `ImportProgress mode="images-only"`. `page.tsx` (`ComingSoonPage` removido) segue o mesmo padrão de `?cardSetId=` + `key` no componente cliente de `ImportarCartasPage`. Verificado com `tsc --noEmit` (raiz `web/`, 0 erros) diretamente no ambiente de trabalho (`node_modules` já instalado; `next lint`/`next build` continuam indisponíveis por falta de acesso a registro/CDN). |
| 1.35 | **Edge Function `import-card-assets` reescrita para pular cartas já importadas + progresso incremental (v2.7.0, proposta — aguardando `deno check` e deploy por Fabrício); contador "X de Y" ao vivo na tela (2026-08-02, mesmo dia).** Teste real de SV4/Fenda Paradoxal (266 cartas) confirmou o pior cenário previsto na revisão `1.33`: repetir a tentativa de importação de imagens produzia exatamente o mesmo resultado (115/266) — zero progresso real —, porque a Edge Function reprocessa `set.cards` (a coleção inteira da TCGdex) do zero a cada invocação, sempre esbarrando no mesmo teto de tempo de execução da plataforma. Fabrício reportou o travamento com prints e autorizou explicitamente alterar a função, revertendo pontualmente a restrição anterior de não tocar no pipeline manual: "Se for preciso alterar a function para corrigir o problema, vamos fazer" — a restrição permanece válida apenas contra *duplicar* o pipeline (criar um segundo caminho), não contra corrigir o existente. Pedido adicional, também atendido nesta revisão: "quero colocar um contador ao lado do Step Importando imagens (Exemplo: 110 de 546)... Quero enxergar o progresso real". **Causa raiz corrigida (Edge Function, `supabase/functions/import-card-assets/`, v2.7.0):** antes de processar, a função agora consulta `card_asset` (`listCardIdsWithPrimaryAsset()`, novo helper em `services/database.ts`) para descobrir quais Cards da Coleção já têm imagem primária ativa, e filtra `set.cards` para `cardsToImport` — só as que ainda faltam. Cada retry passa a fazer progresso líquido de verdade (a próxima invocação processa o restante, não repete o já feito), em vez de morrer sempre no mesmo ponto. Além disso, `asset_import_run.requested_count/processed_count/success_count/failed_count` — antes gravados uma única vez, só no fim, via `finishImportRun()` — agora também são atualizados a cada lote de `IMAGE_BATCH_SIZE` (5) cartas processadas (`updateImportRunProgress()`, novo helper, tolerante a falha — nunca interrompe o processamento se a escrita de progresso falhar), preservando o progresso parcial real mesmo que a função seja encerrada no meio de novo. **Frontend — progresso ao vivo:** como uma única chamada de Server Action bloqueante não consegue transmitir estado intermediário ao cliente, o fluxo de imagens foi dividido em duas fases (`tcgdex/actions.ts`): `abrirImportacaoImagens()` (chamada rápida, só abre/reaproveita a run via `admin_start_asset_import_run` e devolve o `run_code` de imediato) e `executarImportacaoImagens()` (a chamada longa e bloqueante à Edge Function, recebendo o `run_code` já aberto) — substituem a antiga `iniciarImportacaoImagens()` (removida). Nova função `getProgressoImportacaoImagens(runCode)` lê `asset_import_run` diretamente (sem RPC nova — a política `catalog_admin_select` já existente, `USING is_admin()`, mais o `GRANT SELECT` da migration `274`, já cobrem esse caminho de leitura). O cliente (`useAnalyzeJob()` em `importar-tcgdex-view.tsx`, e o equivalente em `importar-imagens-view.tsx`) chama `abrirImportacaoImagens`, inicia um polling a cada 2s em `getProgressoImportacaoImagens` assim que tem o `run_code`, dispara `executarImportacaoImagens` em paralelo, e para o polling quando ela resolve. `ImportProgress` ganhou a prop `imageProgress` — enquanto `imagePhase === "importing"`, o corpo da etapa mostra "`{processadas} de {solicitadas} processadas · N importadas · N falharam`" em vez do resumo final simulado, e a barra de progresso passa a refletir a proporção real `processedCount/requestedCount` (até o teto `IMAGE_PERCENT_CEILING`) em vez da curva de avanço simulada, sempre que o polling já tiver respondido pelo menos uma vez. **Status de deploy:** o arquivo `index.ts`/`services/database.ts` da Edge Function foi escrito e revisado manualmente (sandbox sem Deno disponível para `deno check`) mas **ainda não publicado** — depende de Fabrício rodar `deno cache`/`deno check` e `supabase functions deploy import-card-assets` pelo próprio checklist, seguindo a convenção do repositório de só copiar a versão "confirmada como publicada" (aqui marcada explicitamente como proposta). O frontend (Server Actions + componentes) já compila limpo (`tsc --noEmit`, 0 erros) mas depende do deploy da função para funcionar de ponta a ponta em produção. |
| 1.36 | **Deploy da Edge Function `import-card-assets` v2.7.0 confirmado; Query `2092` v1.2 e Validação `2816` v1.2 confirmadas executadas (2026-08-02, mesmo dia).** Fabrício rodou o checklist padrão (`deno cache`/`deno check` na pasta da função, depois `npx supabase functions deploy import-card-assets` na raiz do projeto) e confirmou com o log real do terminal: `Deployed Functions on project qjfutqujxrbzgrtkpgkg: import-card-assets`, os cinco arquivos da função enviados (`deno.json`, `index.ts`, `services/storage.ts`, `services/tcgdex.ts`, `services/database.ts`). `index.ts` atualizado de "PROPOSTA — AGUARDANDO deploy" para "CONFIRMADO DEPLOYADO" (mesmo padrão de status já usado nas versões anteriores da função). Também confirmadas por Fabrício nesta mesma mensagem: a Query `2092` v1.2 (staleness — runs `PENDING`/`RUNNING` com mais de 15 minutos passam a ser fechadas como `FAILED` antes de abrir uma nova run, resolvendo o bloqueio permanente descrito na revisão `1.33`) e a Validação `2816` v1.2 — ambas com `Status` atualizado de "SQL PREPARADO — AGUARDANDO EXECUÇÃO" para "EXECUTADA E CONFIRMADA". Com isso, a emenda completa da continuação automática cartas→imagens (revisões `1.30`–`1.36`) está de ponta a ponta em produção: Edge Function resiliente a retries, progresso incremental gravado, contador ao vivo no frontend, e a run travada de SV4 destravável. Próximo teste real recomendado: repetir a importação de imagens de SV4/Fenda Paradoxal (151 pendentes) para confirmar visualmente o contador "X de Y" e a conclusão completa das 266 cartas. |
| 1.37 | **Bug real de produção corrigido: o contador ao vivo nunca aparecia; causa raiz isolada na leitura via Server Action, não na gravação (2026-08-02, mesmo dia).** Primeiro teste real depois do deploy da v2.7.0 (retomada de SV4, 151 pendentes): a Edge Function fez progresso líquido de verdade (115 → 169 imagens, +54, confirmando que o "pular cartas já importadas" da revisão `1.35` funciona), mas voltou a falhar por tempo de execução (`HTTP 504`) — esperado, o teto de execução da plataforma não mudou, só a forma como o trabalho é dividido entre tentativas — e o contador "X de Y" nunca apareceu em nenhum momento da barra de progresso, mesmo o run tendo durado tempo suficiente (a barra chegou a 97%, teto da curva simulada) para várias rodadas de polling a cada 2s terem sucesso, se a leitura estivesse funcionando. **Diagnóstico:** a escrita (`updateImportRunProgress`, Edge Function) está confirmada correta pela evidência indireta (o resultado final bateu com o progresso real); o problema está do lado da leitura — `getProgressoImportacaoImagens()`, implementada como Server Action chamada repetidamente via `setInterval` a partir do cliente (revisão `1.35`). Sem acesso a logs do navegador/rede de Fabrício não foi possível confirmar a causa exata (chamadas que nunca completavam, respostas vazias, ou estado React que não re-renderizava) — em vez de insistir num mecanismo que já falhou uma vez em produção, a leitura foi trocada para o padrão já testado e usado em outros pontos do projeto (`card-set-logo-uploader.tsx`/`expansao-logo-uploader.tsx`/`avatar-uploader.tsx`/`users-table.tsx`): consulta direta via `createBrowserClient` (`@/lib/supabase/client`, anon key + RLS), não mais uma chamada de servidor. Novo arquivo `lib/catalogo/asset-import-progress-client.ts` (`fetchProgressoImportacaoImagens`) substitui o uso de `getProgressoImportacaoImagens` nos dois pontos de polling (`useAnalyzeJob` em `importar-tcgdex-view.tsx`, e `handleImportar` em `importar-imagens-view.tsx`) — a Server Action original foi mantida no arquivo (marcada `@deprecated`), sem consumidor no código atual, por rastreabilidade. `tsc --noEmit` confirmado limpo. **Não resolvido nesta revisão, sinalizado para Fabrício:** o `HTTP 504` em si é esperado, dado o teto de execução da plataforma — cada clique em "Importar Imagens" processa um lote parcial e precisa ser repetido manualmente até `imagesPendentes` chegar a zero; um loop de nova tentativa automática no cliente (repetir `abrirImportacaoImagens`+`executarImportacaoImagens` sozinho até terminar ou parar de progredir) foi cogitado, mas não implementado sem confirmação explícita de Fabrício, por mudar o comportamento de forma mais ampla que o pedido original. |
| 1.38 | **Retry automático no cliente para a importação de imagens — decisão confirmada por Fabrício (2026-08-02, mesmo dia, rodada seguinte).** Perguntado explicitamente se queria retry automático (um clique repete sozinho até terminar) ou manter o clique manual só com o contador corrigido, Fabrício escolheu a opção recomendada. Implementado em `useAnalyzeJob` (`importar-tcgdex-view.tsx`) e `handleImportar` (`importar-imagens-view.tsx`): depois de abrir a run uma única vez (`abrirImportacaoImagens`), o cliente chama `executarImportacaoImagens` em loop **com o mesmo `run_code`** — nunca reabre a run — até `imagesFailed` chegar a 0 (concluído) ou o número de imagens importadas parar de aumentar entre uma tentativa e a seguinte (sinal de falha real e persistente, não mais de timeout de plataforma), com um teto de segurança de `MAX_IMAGE_IMPORT_RETRY_ATTEMPTS = 25` tentativas (`lib/catalogo/asset-import-progress-client.ts`). Reabrir a run a cada tentativa (via `admin_start_asset_import_run()`) não funcionaria: quando a plataforma mata a Edge Function no meio (`HTTP 504`/`546`), a run fica presa em `RUNNING` para sempre (nunca chega a `finishImportRun()`) — uma nova chamada de abertura cairia no caminho `already_active` e não invocaria a função de novo. Reutilizar o `run_code` direto contorna isso: `findImportRun`/`transitionImportRunToRunning`, do lado da Edge Function, não checam o `status` atual, só localizam a run pelo código e seguem processando o que falta. `ImportProgress` ganhou a prop `imageAttempt` — quando `> 1`, o rótulo acima da barra passa a mostrar "Importando imagens... (tentativa N)", para deixar claro que o sistema está repetindo sozinho em vez de parecer travado. `tsc --noEmit` confirmado limpo. |
| 1.39 | **Dois bugs reais corrigidos depois do teste do retry automático: tela resetava ao concluir; lentidão real por overhead redundante a cada tentativa (2026-08-02, mesmo dia, rodada seguinte).** Fabrício testou o retry automático da revisão `1.38` em SV4 — funcionou (concluiu, contador subindo em tempo real, "tentativa N" visível), mas reportou dois problemas novos: (1) "apesar de ter concluído", a tela voltava para "Selecione uma Coleção..." e o resultado final desaparecia; (2) "estou bem desapontado com a lentidão... quando rodávamos essa importação direta pelo PowerShell a importação era quase instantânea". **Bug 1 (frontend, causa raiz isolada):** `page.tsx` de `/catalogo/importar-imagens` resolvia `selectedCardSet` só a partir de `getCardSetsForImportacaoImagens()` — a lista filtrada por `imagesPendentes > 0`. Assim que uma Coleção termina (pendentes chega a 0), ela sai dessa lista; `selectedCardSet` virava `null`; a `key={selectedCardSet?.id ?? "none"}` de `ImportarImagensView` (existe desde a revisão `1.34`, propositalmente, para resetar o progresso ao trocar de Coleção pelo combobox) forçava um remount que também apagava, sem querer, o resultado que tinha acabado de ficar pronto. Corrigido com uma nova função `getCardSetImagensById()` (`queries.ts`) — mesmas contagens de `getCardSetsForImportacaoImagens`, mas para um único Card Set, sem o filtro de pendentes — usada como *fallback* em `page.tsx` quando o `cardSetId` da URL não está mais na lista filtrada; a lista em si (as opções do combobox) continua filtrada normalmente, então a Coleção concluída não volta a ser oferecida de novo, só permanece visível enquanto for a seleção atual. **Bug 2 (Edge Function, v2.8.0, PROPOSTA — AGUARDANDO deploy):** cada tentativa do retry automático refazia a sincronização de `card_external_reference` para as 266 cartas da Coleção INTEIRA (`processInBatches(set.cards, 20, ...)`, existente desde o Sprint B3.15, nunca ajustada pela otimização "pular cartas já importadas" da v2.7.0/revisão `1.35` — essa só cobria o laço de download de imagem, não a sincronização de referências que roda antes dele) — mesmo quando só uma fração ainda precisava de imagem. Como uma carta com imagem já salva necessariamente já teve sua referência sincronizada num passo anterior bem-sucedido (a sincronização sempre roda por completo antes do laço de imagens, na mesma invocação), pular essas cartas é seguro. Corrigido reordenando o cálculo de `cardsToImport` para ANTES da sincronização de referências (era depois) e restringindo o laço de sincronização a `cardsToImport` (era `set.cards`) — reduz o trabalho redundante de cada nova tentativa automática de 266 upserts para só o que falta. Não elimina toda a diferença de velocidade frente ao script PowerShell (que roda local, sem overhead de invocação de Edge Function nem de rebuscar o Set inteiro da TCGdex a cada chamada — isso continua sem mudança nesta rodada), mas remove a parte mais redundante e mais facilmente evitável do padrão de retry introduzido pela revisão `1.38`. `tsc --noEmit` confirmado limpo. **Status de deploy:** `index.ts`/`services/database.ts` da Edge Function (v2.8.0) escritos e revisados manualmente, ainda não publicados — depende de Fabrício rodar `deno cache`/`deno check` e `supabase functions deploy import-card-assets` de novo. |
