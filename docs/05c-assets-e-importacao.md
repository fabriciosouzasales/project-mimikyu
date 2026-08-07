# Modelo de Dados — Assets e Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados — Assets e Importação |
| **Arquivo** | `docs/05c-assets-e-importacao.md` |
| **Versão** | 1.0 |
| **Status** | Em elaboração |
| **Objetivo** | Modelo lógico e físico de Card Asset Type/Card Asset, Language, Storage Bucket, Asset Source, Card External Reference e Card Set External Reference — a camada física de importação de cartas e imagens. |
| **Escopo** | Parte de `docs/05-modelo-de-dados.md` (índice) — resultado da divisão de 2026-08-06, motivada pelo tamanho do arquivo original (mais de 700 KB, acima do que ferramentas de leitura processam em uma chamada). |
| **Dependências** | `04-domain-model.md`, `standards/STD-001-database-standards.md`, `05-modelo-de-dados.md`, `06-pipeline-importacao.md` |

Ver `docs/05-modelo-de-dados.md` para o mapa completo do domínio, a metodologia (Roteiro por Entidade) e o histórico de revisão consolidado até 2026-08-06 (revisões anteriores a esta divisão não foram redistribuídas retroativamente por entidade — ver nota na Revision History de lá).

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

