# Modelo de Dados — Cartas e Raridade

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados — Cartas e Raridade |
| **Arquivo** | `docs/05b-cartas-e-raridade.md` |
| **Versão** | 1.0 |
| **Status** | Em elaboração |
| **Objetivo** | Modelo lógico e físico de Rarity (Raridade), Card Category, Card (Carta), Card Translation, Card Variant Type e Card Variant. |
| **Escopo** | Parte de `docs/05-modelo-de-dados.md` (índice) — resultado da divisão de 2026-08-06, motivada pelo tamanho do arquivo original (mais de 700 KB, acima do que ferramentas de leitura processam em uma chamada). |
| **Dependências** | `04-domain-model.md`, `standards/STD-001-database-standards.md`, `05-modelo-de-dados.md` |

Ver `docs/05-modelo-de-dados.md` para o mapa completo do domínio, a metodologia (Roteiro por Entidade) e o histórico de revisão consolidado até 2026-08-06 (revisões anteriores a esta divisão não foram redistribuídas retroativamente por entidade — ver nota na Revision History de lá).

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

