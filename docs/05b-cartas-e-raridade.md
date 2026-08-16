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

## Status (reconciliado em 2026-08-16 contra o schema real do Supabase)

**Fundação concluída (decisão de Fabrício, 2026-08-16) — encerrada como base necessária para Pricing e Collection.** Nome conceitual e físico convergentes desde ADR-016: "Card Variant Type"/"Card Variant" ("Finish"/"Card Finish", usado por ADR-010 entre 2026-07 e a reversão desta decisão, é sinônimo histórico, não um termo ativo). A tabela física `card_variant_type` foi criada em julho de 2026 (Queries `150`/`151`, seed `850` com 13 tipos) e, a partir de 2026-08-14, ganhou uma segunda camada de governança administrativa completa (`ADR-028`) — CRUD via RPC, soft activation/deactivation, e um pipeline de importação que resolve automaticamente combinações de fontes externas para tipos canônicos. Em 2026-08-16 o catálogo real tem **39 tipos ativos**, todos do Game Pokémon TCG (`is_active = true` em 100% das linhas — nenhum foi inativado até esta data). Evoluções futuras da taxonomia (ex.: Vintage/Promo Variant Modeling, ver "Estado Atual", abaixo) permanecem como backlog explicitamente postergado — não bloqueiam Pricing nem Collection.

## Modelo Físico — Estado Atual (confirmado por introspecção direta do Supabase em 2026-08-16)

```sql
CREATE TABLE public.card_variant_type (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id        UUID NOT NULL REFERENCES public.game (id),
    code           VARCHAR(50) NOT NULL,
    name           VARCHAR(100) NOT NULL,
    description    TEXT,
    display_order  INTEGER NOT NULL,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,   -- Query 2152 (2026-08-15), aditiva
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_card_variant_type_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_card_variant_type_name_not_blank
        CHECK (btrim(name) <> ''),
    CONSTRAINT ck_card_variant_type_description_not_blank
        CHECK (description IS NULL OR btrim(description) <> ''),
    CONSTRAINT ck_card_variant_type_display_order_positive
        CHECK (display_order > 0),
    CONSTRAINT uq_card_variant_type_game_code UNIQUE (game_id, code),
    CONSTRAINT uq_card_variant_type_game_display_order UNIQUE (game_id, display_order)
);

CREATE INDEX ix_card_variant_type_game_id ON public.card_variant_type (game_id);

CREATE TRIGGER trg_card_variant_type_set_updated_at
    BEFORE UPDATE ON public.card_variant_type
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

**RLS**: habilitado, uma única policy — `catalog_admin_select` (`SELECT`, `(select is_admin())`, padrão `STD-001` pós-hardening de 2026-08-14). Não existe policy de `INSERT`/`UPDATE`/`DELETE` para nenhuma role — toda escrita passa exclusivamente pelas funções `SECURITY DEFINER` abaixo. **Grants de tabela**: `authenticated` tem só `SELECT`; `anon` não tem nenhum privilégio; `service_role` tem `SELECT`/`REFERENCES`/`TRIGGER`/`TRUNCATE` (privilégios padrão de superusuário de aplicação, não usados na prática por este módulo).

**Nenhuma exclusão física** (`DELETE`) é suportada — nem por RPC, nem por privilégio de tabela. A única forma de remover um tipo do fluxo ativo é `admin_deactivate_card_variant_type()` (soft governance, ver abaixo).

## Governança administrativa (ADR-028) — funções `SECURITY DEFINER`, todas com `search_path=''`, `EXECUTE` restrito a `authenticated`

| Função | Query | O que faz | Regras validadas no corpo da função |
|---|---|---|---|
| `admin_create_card_variant_type(game_id, code, name, description, display_order)` | `2154` | Cadastra um novo tipo canônico. | Admin-only; `game_id` deve existir; `code` normalizado para maiúsculas e validado contra `^[A-Z0-9][A-Z0-9_]*$` **antes** do INSERT (nota: esta regex da função aceita código iniciando por dígito, um passo mais permissiva que a `CHECK` física da tabela — `^[A-Z][A-Z0-9_]*$` — ver "Achados desta auditoria", abaixo); `name` não pode ser vazio; `display_order` positivo; `code` e `display_order` únicos por Game (checados explicitamente, com mensagem de erro de negócio, antes de deixar a `UNIQUE` física estourar); grava `CARD_VARIANT_TYPE_CREATED` em `catalog_admin_action_log`. |
| `admin_update_card_variant_type(id, name, description, display_order)` | `2155` | Atualiza nome/descrição/ordem. | `code` e `game_id` **não são parâmetros** — imutáveis após a criação, por design; `display_order` revalidado como único dentro do Game (excluindo o próprio registro); grava `CARD_VARIANT_TYPE_UPDATED`. |
| `admin_deactivate_card_variant_type(id)` | `2156` | Soft-deactivation (`is_active = false`). | Rejeita se já estiver inativo; **não** afeta `card_variant`/`card_variant_type_external_mapping` já existentes — histórico nunca é alterado; `is_active` só governa disponibilidade para **novos** cadastros/mappings; grava `CARD_VARIANT_TYPE_DEACTIVATED`. |
| `admin_reactivate_card_variant_type(id)` | `2157` | Reverte a inativação. | Rejeita se já estiver ativo; grava `CARD_VARIANT_TYPE_REACTIVATED`. |
| `admin_create_card_variant_type_with_import_mapping(row_id, code, name, description, display_order)` | `2158` | Wrapper transacional: cria um tipo novo **e** resolve o mapeamento externo da linha de staging que originou o pedido, na mesma transação implícita da RPC. | Chama internamente `admin_create_card_variant_type()` (2154) e `admin_resolve_catalog_variant_import_mapping()` (2150, ver seção de importação); `game_id` nunca é parâmetro — resolvido a partir de `card → card_set → expansion` da própria linha, nunca informável pelo chamador; atomicidade comprovada (falha em qualquer etapa desfaz as duas). |

Todas as cinco funções são chamadas exclusivamente pelo frontend administrativo (`/catalogo/tipos-variacao`, e o Dialog "Resolver mapeamento" de `/catalogo/importar-variantes` para a última) — nenhuma escrita direta de tabela pelo cliente.

## Taxonomia e distinção conceitual (herdada da modelagem original, ainda válida)

`card_variant_type` representa apenas o **acabamento físico** da carta (Standard, Holo, Cosmos Holo, Reverse, etc.) — nunca a origem/distribuição de uma impressão promocional específica (booster vs. produto promocional vs. coleção especial), que permanece uma necessidade de modelagem reconhecida e **ainda não construída** (decisão original preservada da modelagem de julho de 2026). O cadastro de um tipo não implica que toda Card, ou todo Card Set, possua essa variante — a associação real é feita por `card_variant` (seção seguinte).

## Estado Atual (dado real, Supabase, 2026-08-16)

39 tipos cadastrados, todos ativos, todos do Game Pokémon TCG (nenhum outro Game tem `card_variant_type` hoje). Crescimento real do catálogo: 13 tipos originais (`850` v1.3, julho de 2026) → 39 tipos após a governança e o pipeline de importação de variantes (agosto de 2026) resolverem taxonomicamente combinações reais encontradas em `SV7`–`SV10.5W` e casos vintage/promocionais (`GameStop`, `EB Games`, campeonatos regionais, Gym Challenge, etc.). A lista completa e atualizada vive no banco (`card_variant_type`, ordenável por `display_order`) — não duplicada aqui para não criar uma segunda fonte que fica desatualizada a cada novo tipo cadastrado.

**Backlog explicitamente postergado, não bloqueante (decisão de Fabrício, 2026-08-16)**: Vintage/Promo Variant Modeling — ver seção "Importação de Card Variant", abaixo, para o achado técnico (30+ combinações de `BASEP` e a totalidade de `BASE1` sem mapeamento, motivando uma futura dimensão de "origem/distribuição" separada do acabamento físico).

## Definition of Done

- [x] modelo físico definido e executado (`150`/`151`, v1.0, julho de 2026);
- [x] seed original executada — 13 tipos canônicos (`850` v1.3);
- [x] governança administrativa completa — CRUD via RPC admin-only, soft activation/deactivation, sem exclusão física (`ADR-028` revisões `1.2`–`1.4`, Queries `2152`–`2158`, agosto de 2026);
- [x] UI administrativa (`/catalogo/tipos-variacao`) consumindo só as RPCs, nenhuma escrita direta de tabela;
- [x] pipeline de resolução de mapeamento externo → tipo canônico, incluindo o modo "criar tipo novo + resolver" na mesma operação (ver seção de importação, abaixo);
- [x] RLS + least privilege de `GRANT` (Query `2147`) aplicados;
- [x] taxonomia real em 39 tipos ativos, cobrindo até `SV10.5W` (2026-08-16);
- [ ] distinção entre acabamento físico e origem/distribuição de uma impressão promocional — necessidade identificada desde julho de 2026, entidade futura ainda não modelada;
- [ ] Vintage/Promo Variant Modeling — backlog postergado, não bloqueante (ver "Estado Atual", acima).

## Queries Associadas

```text
150  - Create Card Variant Type Table                         (v1.0, CANÔNICA — jul/2026)
151  - Create Card Variant Type Triggers                       (v1.0, CANÔNICA — jul/2026)
850  - Seed Card Variant Type                                  (v1.3, CANÔNICA — jul/2026, 13 tipos)
950  - Validate Card Variant Type                               (v1.3, CANÔNICA — jul/2026)
2152 - Add is_active to Card Variant Type                       (CONFIRMADO EXECUTADO — 2026-08-15)
2153 - Widen catalog_admin_action_log for Card Variant Type     (CONFIRMADO EXECUTADO — 2026-08-15)
2154 - admin_create_card_variant_type()                         (CONFIRMADO EXECUTADO — 2026-08-15)
2155 - admin_update_card_variant_type()                         (CONFIRMADO EXECUTADO — 2026-08-15)
2156 - admin_deactivate_card_variant_type()                     (CONFIRMADO EXECUTADO — 2026-08-15)
2157 - admin_reactivate_card_variant_type()                     (CONFIRMADO EXECUTADO — 2026-08-15)
2158 - admin_create_card_variant_type_with_import_mapping()     (CONFIRMADO EXECUTADO — 2026-08-15)
```

---

# Card Variant (Variante da Carta)

## Status (reconciliado em 2026-08-16 contra o schema real do Supabase)

**Fundação concluída (decisão de Fabrício, 2026-08-16).** Associa uma Card específica a um Card Variant Type específico — representa uma versão colecionável que oficialmente existe para aquela Card. Não representa uma cópia física: duas cópias físicas da mesma variante serão, quando Collection existir, dois registros distintos de Collection Item, não dois registros de `card_variant` (`ADR-013`). A tabela nasceu em julho de 2026 (859 Cards / 1.555 Card Variants nas 5 coleções originais, depois 927/1.653 com `MEE`/`MEP` — ver "Histórico da carga original", abaixo) e cresceu substancialmente em agosto de 2026 via o pipeline de importação administrativa (ver seção "Importação de Card Variant", a seguir). **Estado real hoje: 4.718 Card Variants, cobrindo 2.433 das 7.104 Cards cadastradas no catálogo** (≈34% — cobertura ainda parcial porque o catálogo de Cards cresceu, via ingestão TCGdex, muito além das 7 Card Sets originais, e o pipeline de variantes ainda não foi rodado para todo Card Set existente).

## Modelo Físico — Estado Atual (confirmado por introspecção direta do Supabase em 2026-08-16)

```sql
CREATE TABLE public.card_variant (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id          UUID NOT NULL REFERENCES public.card (id),
    variant_type_id  UUID NOT NULL REFERENCES public.card_variant_type (id),
    variant_order    INTEGER NOT NULL,
    is_default       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_card_variant_order_positive CHECK (variant_order > 0),
    CONSTRAINT uq_card_variant_card_type  UNIQUE (card_id, variant_type_id),
    CONSTRAINT uq_card_variant_card_order UNIQUE (card_id, variant_order)
);

CREATE INDEX ix_card_variant_card_id ON public.card_variant (card_id);
CREATE INDEX ix_card_variant_variant_type_id ON public.card_variant (variant_type_id);

CREATE UNIQUE INDEX uq_card_variant_one_default_per_card
    ON public.card_variant (card_id) WHERE is_default = TRUE;

CREATE TRIGGER trg_card_variant_set_updated_at
    BEFORE UPDATE ON public.card_variant
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_card_variant_validate_game_consistency
    BEFORE INSERT OR UPDATE ON public.card_variant
    FOR EACH ROW EXECUTE FUNCTION validate_card_variant_game_consistency();
```

Regras de negócio confirmadas: `variant_order` positivo e único por Card (local à Card, não ao catálogo geral de tipos); no máximo uma variante `is_default = TRUE` por Card, via índice único parcial; `validate_card_variant_game_consistency()` impede que uma Card de um Game seja associada a um `card_variant_type` de outro Game (mesmo padrão do trigger equivalente em `Card`). **Sem campo `variant_code` persistido** (mesmo precedente de `card_code`/`secret_set_size`): o código legível é derivado — `card_set.code || '-' || card.collector_number || '-' || card_variant_type.code` (ex.: `ME1-001-STANDARD`).

**RLS**: habilitado, uma única policy — `catalog_admin_select` (`SELECT`, `(select is_admin())`). **Grants de tabela**: `authenticated` só `SELECT`; `anon` sem privilégio nenhum; `service_role` com `SELECT`/`REFERENCES`/`TRIGGER`/`TRUNCATE`.

## Imutabilidade — regra confirmada no código, não apenas na intenção

`internal.write_card_variant(mode, variant_id, card_id, variant_type_id, variant_order)` (Query `2143`, `SECURITY DEFINER`, chamada só internamente — nunca exposta a `authenticated`/`anon`) é a única rotina que grava em `card_variant`. **O modo `UPDATE` existe na assinatura mas está desabilitado deliberadamente**: chamá-lo levanta `INTERNAL_WRITE_CARD_VARIANT_UPDATE_NOT_SUPPORTED` — "nenhum fluxo atual atualiza uma Card Variant existente — ela é tratada como UNCHANGED. Parâmetro reservado para uma necessidade futura ainda não desenhada." Na prática, hoje, **uma `card_variant` nunca é alterada depois de criada** — só criada (via importação confirmada) ou deixada como está (`UNCHANGED`, quando a combinação já existe). Não existe nenhuma rotina de exclusão física de `card_variant`.

## Governança e origem dos dados

Diferente de `card_variant_type` (taxonomia com CRUD administrativo direto), `card_variant` só é populada por dois caminhos: (1) a carga original de julho de 2026 (`860`/`860A`/`860B`, ver "Histórico da carga original", abaixo); (2) o pipeline de importação administrativa de agosto de 2026 (`admin_confirm_catalog_variant_import()`, ver seção seguinte). Não existe uma tela de "criar Card Variant" avulsa — toda criação nova passa pelo fluxo de importação e revisão, nunca por um formulário direto, reforçando `ADR-028`: Card Variant é dado editorial, mantido exclusivamente por administradores, por um processo auditável.

---

# Importação de Card Variant — Pipeline Administrativo (ADR-028, agosto de 2026)

Bloco novo desde o checkpoint técnico de 2026-08-14, cobrindo taxonomia (governança já descrita acima) e a ingestão de novas `card_variant` a partir da TCGdex. Objetivo: dado um Card Set já com Cards cadastradas (via `ADR-024`), identificar automaticamente quais combinações de acabamento a fonte externa descreve para cada Card, resolvê-las para um `card_variant_type` canônico, e só então gravar em `card_variant` — nunca a partir de inferência automática de um tipo novo (ADR-028: criar tipo é sempre decisão explícita de administrador).

## `card_variant_type_external_mapping` — de-para combinação externa → tipo canônico

```sql
CREATE TABLE public.card_variant_type_external_mapping (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id            UUID NOT NULL REFERENCES public.game (id),
    asset_source_id    UUID NOT NULL REFERENCES public.asset_source (id),
    external_type      TEXT NOT NULL,
    external_foil      TEXT,
    external_subtype   TEXT,
    external_stamp     TEXT[],
    normalized_type     TEXT NOT NULL,
    normalized_foil     TEXT,
    normalized_subtype  TEXT,
    normalized_stamp    TEXT[],
    variant_type_id    UUID NOT NULL REFERENCES public.card_variant_type (id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- normalized_type não pode ser vazio; external_stamp/normalized_stamp, quando presentes,
    -- não podem ser array vazio nem conter elemento NULL (4 CHECKs dedicados)
    CONSTRAINT uq_card_variant_type_external_mapping_combo
        UNIQUE (game_id, asset_source_id, normalized_type,
                COALESCE(normalized_foil, ''), COALESCE(normalized_subtype, ''),
                COALESCE(normalized_stamp, '{}'))
);
```

Cada linha é um mapeamento **canônico por Game+Fonte+combinação normalizada** (não por job nem por Card Set) — resolver uma combinação uma vez a resolve para todos os jobs presentes e futuros daquele Game/Fonte. Normalização via `normalize_external_catalog_value()` (`STABLE`, `upper(regexp_replace(trim(unaccent(valor)), '\s+', ' ', 'g'))`) — mesma função para os 4 campos (type/foil/subtype/cada elemento de stamp). Hoje: **33 mapeamentos, cobrindo 1 única Fonte** (TCGdex).

## `catalog_variant_import_job` / `catalog_variant_import_row` — staging

Mesmo padrão arquitetural de `catalog_import_job`/`catalog_import_row` (`ADR-024`), adaptado para variantes:

```sql
CREATE TABLE public.catalog_variant_import_job (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_set_id      UUID NOT NULL REFERENCES public.card_set (id),
    source           TEXT NOT NULL CHECK (source = 'TCGDEX'),
    external_set_id  TEXT NOT NULL,
    status           TEXT NOT NULL DEFAULT 'RECEIVED'
        CHECK (status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING',
                           'COMPLETED','COMPLETED_WITH_ERRORS','FAILED','CANCELLED')),
    progress_step    TEXT CHECK (progress_step IS NULL OR status = 'PROCESSING'),
    total_rows INT NOT NULL DEFAULT 0, valid_rows INT NOT NULL DEFAULT 0,
    rejected_rows INT NOT NULL DEFAULT 0, inserted_rows INT NOT NULL DEFAULT 0,
    unchanged_rows INT NOT NULL DEFAULT 0, skipped_rows INT NOT NULL DEFAULT 0,
    failed_rows INT NOT NULL DEFAULT 0,       -- todas as 7 contagens CHECK >= 0
    error_summary    TEXT,
    initiated_by     UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- só um job ATIVO (RECEIVED/PROCESSING/STAGED/CONFIRMING) por Card Set + external_set_id:
    CONSTRAINT uq_catalog_variant_import_job_fingerprint_active
        UNIQUE (card_set_id, external_set_id)  -- índice único PARCIAL, só quando status é não-terminal
);

CREATE TABLE public.catalog_variant_import_row (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id                UUID NOT NULL REFERENCES public.catalog_variant_import_job (id),
    card_id               UUID NOT NULL REFERENCES public.card (id),
    raw_data              JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(raw_data) = 'object'),
    normalized_data       JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(normalized_data) = 'object'),
    validation_status     TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (validation_status IN ('PENDING','VALID','NEEDS_REVIEW','INVALID')),
    match_status          TEXT NOT NULL DEFAULT 'NEW'
        CHECK (match_status IN ('NEW','MATCHED','CONFLICT')),
    decision_status       TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (decision_status IN ('PENDING','APPROVED','REJECTED','SKIPPED')),
    persistence_status    TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (persistence_status IN ('PENDING','INSERTED','UNCHANGED','FAILED')),
    matched_variant_id    UUID REFERENCES public.card_variant (id),
    resulting_variant_id  UUID REFERENCES public.card_variant (id),
    error_detail          TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- dedupe real (fix do incidente SV8.5): no máximo uma linha por job+card+variant_type_id resolvido
    CONSTRAINT uq_catalog_variant_import_row_job_card_variant_type
        UNIQUE (job_id, card_id, (normalized_data->>'variant_type_id'))
        -- índice único PARCIAL, só quando normalized_data->>'variant_type_id' IS NOT NULL
);
```

Ambas as tabelas têm gatilhos de normalização (`UPPER(BTRIM(...))` em todos os campos de status/enum, antes de qualquer `CHECK`) e de `updated_at`. RLS habilitado em ambas, mesma policy `catalog_admin_select`. **Grants**: `authenticated` só `SELECT`; `service_role` tem `SELECT`/`INSERT`/`UPDATE` (a Edge Function grava como `service_role`); `anon` sem privilégio nenhum.

**Máquina de estados do job**: `RECEIVED` (criado) → `PROCESSING` (Edge Function ativa) → `STAGED` (linhas geradas, aguardando decisão administrativa) → `CONFIRMING` (confirmação em andamento) → `COMPLETED`/`COMPLETED_WITH_ERRORS` (terminal, com sucesso) ou `FAILED`/`CANCELLED` (terminal, sem sucesso). `admin_confirm_catalog_variant_import()` decide o status final automaticamente: `STAGED` enquanto houver linha com `decision_status = PENDING`; `CONFIRMING` enquanto houver linha aprovada/pulada ainda não persistida; `COMPLETED_WITH_ERRORS` se alguma persistência falhou; `COMPLETED` caso contrário.

**Máquina de estados da linha**: `validation_status` (`NEEDS_REVIEW` quando a combinação normalizada não tem mapeamento em `card_variant_type_external_mapping`; `VALID` quando tem) → `decision_status` (`PENDING`/`APPROVED`/`REJECTED`/`SKIPPED`, decidido pelo administrador — só linhas `VALID` podem ser `APPROVED`) → `persistence_status` (`PENDING`/`INSERTED`/`UNCHANGED`/`FAILED`, resultado real da confirmação). `match_status` (`NEW`/`MATCHED`/`CONFLICT`) registra se a combinação já corresponde a uma `card_variant` existente da Card.

## Edge Function `import-card-variants` (versão 3, ativa)

Recebe `{ card_set_id }` (não `{ job_id }` — diferente de `import-catalog-cards`, porque ainda não existe tela dedicada de pré-criação do job para variantes), cria o próprio `catalog_variant_import_job` internamente, resolve o `external_set_id` do dataset TCGdex via `card_set_external_reference` já gravada por Importar Cartas, busca os arquivos de carta do Set inteiro (não carta a carta), correlaciona cada Card externa com a Card MMKYU via `card_external_reference`, extrai as combinações `variants[]`, resolve o mapeamento externo e grava **somente em `catalog_variant_import_row`** (staging) — nunca em `card_variant` diretamente, mesmo Princípio da Fonte Canônica de `ADR-024`. Não cria RPC de confirmação própria, não infere `is_default`/`variant_order` (resolvidos só na confirmação, por `admin_confirm_catalog_variant_import()`), não modela vintage/promo.

**Resiliência (fix real, incidente SV10, 2026-08-15)**: as três chamadas de rede externas (`resolveSetSerieName()`/`listSetCardFiles()`/`fetchCardFileSource()`) usam `AbortController` com timeout de 15s cada — antes, um `fetch()` sem timeout podia deixar a invocação presa até a plataforma matá-la por estouro do teto de execução (~150s), sem que o `catch()`/marcação de falha do job rodasse, deixando o job preso em `PROCESSING` indefinidamente. **Dedupe (fix real, incidente SV8.5, 2026-08-15)**: a função deduplica combinações repetidas da mesma fonte antes de gravar em `catalog_variant_import_row` (reforçado pela `UNIQUE` parcial da tabela, acima) — antes, uma combinação duplicada na fonte externa derrubava a resolução de mapeamento com erro genérico.

## Funções administrativas do fluxo de revisão/confirmação

| Função | Query | O que faz |
|---|---|---|
| `admin_decide_catalog_variant_import_row(row_ids[], decision_status)` | `2144` | Marca um lote de linhas como `APPROVED`/`REJECTED`/`SKIPPED`/`PENDING`. Exige que o job esteja `STAGED`; rejeita aprovar linha `NEEDS_REVIEW` (sem tipo resolvido). |
| `admin_resolve_catalog_variant_import_mapping(row_id, variant_type_id)` | `2150` | Cria um `card_variant_type_external_mapping` novo para a combinação da linha (só linhas `NEEDS_REVIEW`) e **revalida em lote, cross-job e cross-Card-Set**, toda linha `STAGED`/`PENDING` da mesma Fonte/Game com a mesma combinação normalizada — não apenas a linha que originou a ação. |
| `admin_create_card_variant_type_with_import_mapping(row_id, code, name, description, display_order)` | `2158` | Wrapper: cria um `card_variant_type` novo **e** resolve o mapeamento na mesma operação (ver seção de taxonomia, acima). |
| `admin_confirm_catalog_variant_import(job_id, row_ids[]?)` | `2145` | Confirma linhas `APPROVED`/`SKIPPED` com `persistence_status = PENDING`. Para cada `APPROVED`: se já existe `card_variant` para `(card_id, variant_type_id)`, marca `UNCHANGED` (`match_status = MATCHED`); senão calcula o próximo `variant_order` livre da Card e chama `internal.write_card_variant('CREATE', ...)`. Falha de linha isolada não aborta o lote — cada linha roda em bloco `EXCEPTION WHEN OTHERS` próprio, gravando `FAILED` + `error_detail` sem interromper as demais (mesmo princípio de isolamento de erro por linha de `ADR-024`). Recalcula os 7 contadores do job e o status final ao fim. Grava `CARD_VARIANT_IMPORT_CONFIRMED` em `catalog_admin_action_log` só quando o job chega a um estado terminal de sucesso. |

Todas admin-only (`is_admin()`), `SECURITY DEFINER`, `search_path=''`, `EXECUTE` restrito a `authenticated`. **`service_role`** tem `GRANT` adicional de `INSERT`/`UPDATE` em `catalog_variant_import_job`/`catalog_variant_import_row` (a Edge Function grava como `service_role`, Query `2148`) e `SELECT` nas tabelas de referência que precisa ler durante o processamento.

## Least privilege (Query `2147`, 2026-08-15)

`TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` revogados de `anon`/`authenticated` nas 24 tabelas do Catálogo Editorial, incluindo as 5 deste bloco — mesmo padrão formalizado em `STD-001` (Seção "Row Level Security (RLS)", versão `1.19`).

## Estado Atual (dado real, Supabase, 2026-08-16) — 11 jobs, 2 ainda abertos

| Card Set | `external_set_id` | Status | Linhas | Observação |
|---|---|---|---|---|
| `ME5` | `me05` | `COMPLETED` | 194/194 inseridas | |
| `BASEP` (Wizards Black Star Promos) | `basep` | **`STAGED`** | 74 total, 44 válidas, 0 inseridas | Backlog Vintage/Promo já documentado — 30 combinações sem mapeamento, pelo menos 3 eixos conceituais hoje colapsados no mesmo `card_variant_type` (acabamento genuíno, estampa promocional/proveniência, erro/errata de impressão). Job intocado desde 2026-08-15. |
| `SV10.5W` (Fogo Branco) | `sv10.5w` | `COMPLETED` | 404/404 inseridas | |
| `SV10` (Rivais Predestinados) | `sv10` | `FAILED` | 0 linhas | Job original do incidente SV10 (timeout) — corrigido e substituído pela execução seguinte. |
| `SV10` (reexecução) | `sv10` | `COMPLETED` | 435/435 inseridas | |
| `SV10.5B` (Raio Preto) | `sv10.5b` | `COMPLETED` | 406/406 inseridas | |
| `SV9` (Amigos de Jornada) | `sv09` | `COMPLETED` | 385/385 inseridas | |
| `SV8.5` (Evoluções Prismáticas) | `sv08.5` | `COMPLETED` | 472/472 inseridas | Set do incidente SV8.5 (dedupe) — corrigido no mesmo job. |
| `SV8` (Fagulhas Impetuosas) | `sv08` | `COMPLETED` | 450/450 inseridas | |
| `SV7` (Coroa Estelar) | `sv07` | `COMPLETED` | 319/319 inseridas | |
| `BASE1` (Coleção Básica) | `base1` | **`STAGED`** | 410 total, **0 válidas** (100% `NEEDS_REVIEW`/`NEW`/`PENDING`) | **Achado desta auditoria, não documentado anteriormente em nenhum artefato canônico ou em `docs/log.md`.** Job criado em 2026-08-16 04:32 UTC — todas as 410 linhas ficaram `NEEDS_REVIEW`, ou seja, nenhuma combinação do Set Base original (1999, Wizards of the Coast) tem mapeamento cadastrado para nenhum `card_variant_type`. Consistente com o mesmo gap Vintage/Promo já identificado em `BASEP` (a taxonomia atual foi construída sobre o vocabulário moderno da TCGdex, `2142`), mas em escala maior (um Set inteiro, não 30 combinações). Job permanece `STAGED`, sem nenhuma linha decidida. |

**39 tipos canônicos** (ver seção anterior), **33 mapeamentos externos** (1 fonte — TCGdex), **4.718 Card Variants reais**, **437 linhas em `NEEDS_REVIEW`** no total (concentradas nos dois jobs `STAGED` acima).

## Achados desta auditoria (2026-08-16) — precisão, não decisão

Registrados aqui por exigirem apenas leitura/observação — nenhum é uma decisão de arquitetura nem exige mudança de código para ser documentado corretamente:

1. **Job `BASE1` (`STAGED`, 410 linhas, 100% `NEEDS_REVIEW`) não estava registrado em nenhum documento canônico nem em `docs/log.md` antes desta auditoria** — ver tabela acima. Even o `ROADMAP.md` (débito "Vintage/Promo Variant Modeling") só mencionava `BASEP`. Corrigido nesta rodada — ver `ROADMAP.md`.
2. **Pequena divergência entre a validação de `code` na função `admin_create_card_variant_type()` e a `CHECK` física da tabela**: a função rejeita códigos que não casem `^[A-Z0-9][A-Z0-9_]*$` (permite iniciar por dígito), mas a `CHECK` da tabela exige `^[A-Z][A-Z0-9_]*$` (deve iniciar por letra) — um código hipotético iniciado por dígito passaria na validação da função e ainda assim seria rejeitado pela constraint física, com uma mensagem de erro genérica do Postgres em vez da mensagem de negócio da função. Nunca observado na prática (nenhum dos 39 `code`s reais começa por dígito) — registrado como observação de precisão, não como bug ativo.
3. **`catalog_card_set_variant_coverage` (view) tem um `GRANT` ligeiramente inconsistente**: `anon` tem `REFERENCES`/`TRIGGER`/`TRUNCATE` mas não `SELECT` (não consegue lê-la de qualquer forma, dado que RLS das tabelas de base já bloqueia `anon`); `authenticated` tem os quatro. As tabelas físicas de Card Variant (diferente da view) já tiveram esses privilégios revogados de `anon`/`authenticated` pela Query `2147` — a view não foi incluída nessa passada de limpeza. Sem risco de segurança real (não é possível `TRUNCATE`/criar `TRIGGER` numa view comum; `REFERENCES` não se aplica), mas é uma inconsistência de higiene de `GRANT` factualmente real.

---

## Histórico da carga original (julho de 2026, preservado para rastreabilidade — não é o estado atual)

A base de `card_variant` começou com uma carga manual estruturada, anterior a qualquer governança administrativa: Queries `160`/`161` (tabela e triggers, v1.0), seed `860` (consolidação de `860A`–`860E` por Card Set: `ME1` 310, `ME2` 214, `ME2.5` 630, `ME3` 203, `ME4` 198 — 1.555 Card Variants, 859 Cards) e validação `960` v2.0 (`COMPLETE`). Fonte dos dados: checklists oficiais + campo `variants` da TCGdex + Pokémon TCG API como evidência complementar + validação manual de exceções — sem fonte oficial única estruturada, mesmo padrão de `ADR-008`. Estendida a `MEE`/`MEP` em 2026-07-24 (`860A`/`860B` reaproveitando as letras já liberadas pela consolidação — 16 e 82 Card Variants respectivamente), com `960` evoluída para v2.1 (927 Cards / 1.653 Card Variants, `COMPLETE` para as 7 Card Sets originais da Expansion `ME`). Marco histórico: Fabrício declarou esta carga "canonicamente encerrada" para as 7 Card Sets originais antes de qualquer trabalho de Card Asset (imagens) prosseguir — ver `06-pipeline-importacao.md` para o episódio da Sprint B3.11, em que uma sessão pareada tratou por engano `card`/`card_variant` como vazias, corrigido por Fabrício com auditoria real contra o banco.

Arquivos históricos (`860A`–`860E` de `ME1`–`ME4`) foram consolidados e removidos de `database/seeds/`, mantendo `860_seed_card_variant.sql`, `860a_seed_card_variant_mee.sql` e `860b_seed_card_variant_mep.sql` como fonte única de verdade — Princípio da Fonte Canônica, `STD-001`.

```text
160 - Create Card Variant Table       (v1.0, CANÔNICA — jul/2026)
161 - Create Card Variant Triggers    (v1.0, CANÔNICA — jul/2026)
860  - Seed Card Variant              (v1.0, CANÔNICA CONSOLIDADA — jul/2026, ME1-ME4/ME2.5)
860A - Seed Card Variant MEE          (v1.0, CANÔNICA — jul/2026)
860B - Seed Card Variant MEP          (v1.0, CANÔNICA — jul/2026)
960  - Validate Card Variant          (v2.1, CANÔNICA — jul/2026, 7 Card Sets, 927/1.653, COMPLETE)
```

## Queries Associadas (estado atual, agosto de 2026)

```text
2143 - internal.write_card_variant()                              (CONFIRMADO EXECUTADO — 2026-08-15)
2144 - admin_decide_catalog_variant_import_row()                  (CONFIRMADO EXECUTADO — 2026-08-15)
2145 - admin_confirm_catalog_variant_import()                     (CONFIRMADO EXECUTADO — 2026-08-15)
2136-2141 - catalog_variant_import_job/row, external_mapping (tabelas + triggers)  (CONFIRMADO EXECUTADO — 2026-08-15)
2142 - Seed card_variant_type_external_mapping (combinações modernas)              (CONFIRMADO EXECUTADO — 2026-08-15)
2146 - Widen catalog_admin_action_log (variant import)            (CONFIRMADO EXECUTADO — 2026-08-15)
2147 - Least privilege — REVOKE DDL grants (24 tabelas)           (CONFIRMADO EXECUTADO — 2026-08-15)
2148 - GRANT service_role read access (processador)               (CONFIRMADO EXECUTADO — 2026-08-15)
2149 - Fail stuck variant import job (fix SV10)                   (CONFIRMADO EXECUTADO — 2026-08-15)
2150 - admin_resolve_catalog_variant_import_mapping()             (CONFIRMADO EXECUTADO — 2026-08-15)
2151 - Widen catalog_admin_action_log (variant mapping)           (CONFIRMADO EXECUTADO — 2026-08-15)
```

---

