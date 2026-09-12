/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6129 - Backfill de Card Primary Species nos Card Sets ME*
               (ME1, ME2, ME2.5, ME3, ME4, MEP) a partir de identidade
               TCGdex persistida em card_external_reference
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO — EVIDENCIA HISTORICA DE STAGING
               (a copia canonica promovida vive em
                database/migrations/6129_backfill_card_primary_species_me_sets.sql;
                o corpo executavel e o mesmo, so os cabecalhos diferem)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Executado...: 2026-09-12, como `postgres` no SQL Editor. Guards G0-G10 e
               asserts A1-A10 passaram; COMMIT efetivado. 751 Cards
               resolvidas AUTOMATIC_DEXID; 16.657 -> 17.408.
Mandato.....: PRIMARY-SPECIES-ME-SOURCING-01 — BACKFILL-GATE-A-REVISION-01
               (autoria) / BACKFILL-SYNTAX-CORRECTION-01 / BACKFILL-01-RETRY
               (execucao) / DOCUMENTATION-CLOSEOUT-01 (promocao)
Diagnóstico.: PRIMARY-SPECIES-ME-SOURCING-01 — AUDIT-01

v2.0 (BACKFILL-GATE-A-REVISION-01) sobre a v1.0:
1. ZERO TEMP TABLE. Nenhum CREATE, nem temporario. A evidencia e uma
   constante JSONB; o conjunto-alvo e uma variavel JSONB montada uma unica
   vez; todos os guards leem via jsonb_to_recordset().
2. EVIDENCIA = 752, nao 781. Foram removidas as 29 Cards que existem na
   TCGdex mas nao tem Card local (MEP). A evidencia desta rodada cobre
   exatamente o universo Primary Species ME*.
3. me01-086 permanece na evidencia EXATAMENTE como observada (351) e
   classificada SOURCE_DATA_ERROR.

-------------------------------------------------------------------------------
POR QUE ESTE BACKFILL EXISTE
-------------------------------------------------------------------------------
As 752 Cards POKEMON dos seis Card Sets ME* nunca passaram pelo pipeline de
importacao de catalogo. Foram criadas por seed manual (database/seeds/
840_seed_card.sql, a partir do checklist oficial PT-BR) e o
card_external_reference veio depois, da Edge Function import-card-assets, que
grava `metadata: tcgCard` a partir da LISTAGEM do Set — payload que, por
construcao, nao traz `dexId` (supabase/functions/import-card-assets/index.ts:973;
tipo TcgdexCardSummary em services/tcgdex.ts:73-78).

Medido no LIVE em AUDIT-01, read-only:
    catalog_import_row para essas 752 Cards ....................... 0 linhas
    card_external_reference.metadata contendo 'dexId' ............. 0 refs
    cobertura de card_primary_species nos seis Sets ............... 0 %

Por isso a 6116 nunca teve o que ler: nao havia job, nao havia raw_data. Nao e
regressao da 6116/6128 — e ausencia de evidencia persistida na origem.

-------------------------------------------------------------------------------
DE ONDE VEM A EVIDENCIA
-------------------------------------------------------------------------------
Do mesmo contrato TCGdex que o projeto ja usa: GET /v2/{lang}/cards/{id},
exposto por TcgdexClient.getCard() em supabase/functions/import-catalog-cards/
services/tcgdex.ts:76-78, cujo tipo TcgdexCardDetail ja declara dexId?: number[]
(linha 40). Nenhuma integracao nova foi criada.

Leitura feita em 2026-09-12, read-only, sem persistencia, via o endpoint
GraphQL do mesmo servico (POST /v2/graphql, filtro por prefixo de `id`), que
devolve os mesmos campos do endpoint de detalhe para o Set inteiro em uma
chamada. O caso SOURCE_DATA_ERROR foi reconfirmado individualmente pelo
endpoint de DETALHE (ver secao propria abaixo).

A CONSTANTE c_evidencia ABAIXO E O ARTEFATO. E o registro versionado e
reproduzivel da leitura externa: 752 itens {"e": external_card_id, "d": dexId},
um por Card POKEMON pendente dos seis Sets. Nao depende de tabela nova, de
alteracao de schema nem de acesso a rede no momento da execucao.

DELIMITACAO DO UNIVERSO (v2.0): a evidencia contem SOMENTE Cards que existem
localmente e estao no escopo Primary Species ME*. A TCGdex publica 88 Cards
Pokemon em `mep` contra as 59 do Mimikyu; as 29 restantes NAO entram aqui.
Divida de catalogo, fora deste escopo, nenhuma Card e criada por esta Query.
A composicao das 59 MEP e determinada pelo proprio seed canonico
(database/seeds/840_seed_card.sql: 60 Cards MEP, das quais `028`
"Fanfarra de Celebracao" e TRAINER) — nao por inferencia.

DECISAO DE DESENHO (registrada, nao silenciosa): a evidencia e congelada pela
CHAVE EXTERNA (external_card_id) + dexId observado. card_id, card_set e
pokemon_species sao DERIVADOS do banco por join, com guard de totalidade.
Razoes:
1. external_card_id e a unica parte da evidencia que vem de fora e nao pode
   ser re-derivada do banco;
2. uma lista de UUIDs transcrita a mao e inauditavel por um revisor humano e
   pode divergir do banco sem que nada acuse. `me01-086 -> 351` e conferivel
   contra a fonte por qualquer pessoa, a qualquer momento;
3. o GATE A proibiu executar SQL; obter os 752 card_id exigiria um SELECT.
O manifesto por Card com as seis colunas exigidas e emitido pela Query 6842.

-------------------------------------------------------------------------------
CASO SOURCE_DATA_ERROR — me01-086 (NAO ENTRA NO PAYLOAD DESTA QUERY)
-------------------------------------------------------------------------------
A TCGdex e internamente inconsistente nesta Card. Confirmado pelas DUAS vias,
que concordam entre si, em 2026-09-12:

    GraphQL  /v2/graphql  cards(filters:{id:"me01-08"})
        name = "Mega Absol ex"   dexId = [351]
    Detalhe  /v2/en/cards/me01-086      <- endpoint ja usado pelo projeto
        name = "Mega Absol ex"   dexId = [351]
        (category Pokemon, localId 086, rarity "Double rare", suffix "ex",
         types ["Darkness"], stage Basic, hp 280, illustrator "aky CG Works")

dexId 351 = Castform. O nome publicado descreve Absol (359). Nao ha divergencia
entre caminhos a arbitrar — ha um DEFEITO DA FONTE.

ESTE CASO NAO E AMBIGUIDADE SEMANTICA. O fato de dominio esta determinado:
    Card = Mega Absol ex · Species = Absol · National Dex = 359
O perfil da propria Card na fonte corrobora Absol e exclui Castform: types
["Darkness"], hp 280, suffix "ex" — identico ao de me01-161 (tambem "Mega
Absol ex", dexId 359). Castform (351) e Normal, nao tem forma Mega e nao tem
carta ex neste Set.

POR QUE MESMO ASSIM NAO ENTRA AQUI: a 6115 grava resolution_basis =
AUTOMATIC_DEXID com source_evidence contendo tcgdex_dex_ids/resolved_dex_id.
Injetar 359 no payload produziria uma linha AUTOMATIC_DEXID afirmando que a
TCGdex observou 359 para me01-086 — o que e FALSO, e apagaria o registro do
erro da fonte. Regra do projeto: nao falsificar o payload da 6115.

Na evidencia congelada abaixo, me01-086 permanece com d = 351, COMO OBSERVADO.
O guard G3b aborta a execucao se alguem trocar esse 351 por 359.

CAMINHO CORRETO: Query 6130 (artefato separado), resolucao explicitamente
EDITORIAL via admin_resolve_card_primary_species(), gravando
EDITORIAL_RECONCILIATION com source_evidence que preserva o 351 observado ao
lado do 359 decidido. Nao e caso para a futura UI de ambiguidade — aquela fica
reservada as Cards em que a Species realmente nao puder ser determinada.

-------------------------------------------------------------------------------
O QUE ESTA MIGRATION DELIBERADAMENTE NAO FAZ
-------------------------------------------------------------------------------
- NAO cria tabela, nem temporaria; nao cria funcao, indice ou view (v2.0);
- nao altera 6112, 6113, 6114, 6115, 6116 nem 6128;
- nao chama 6114 (a resolucao editorial de me01-086 e a Query 6130, com
  autorizacao propria);
- nao chama 6116 (depende de is_admin()/JWT, indisponivel no SQL Editor);
- nao cria nenhuma Card, inclusive as 29 MEP ausentes localmente;
- nao toca nas 8 Cards SVP nem nas 119 ambiguidades historicas;
- nao toca em nenhuma Card fora dos seis Card Sets ME*;
- nao faz UPDATE de resolucao preexistente — a 6115 nunca substitui
  pokemon_species_id, so INSERE linha nova (6115 v1.2, cabecalho);
- nao usa service_role.

-------------------------------------------------------------------------------
IDENTIDADE DE EXECUCAO
-------------------------------------------------------------------------------
Executar no Supabase SQL Editor como `postgres`. NAO usar service_role.
A 6115 e SECURITY DEFINER, sem is_admin(), com GRANT EXECUTE apenas a
service_role (6115:437-441) — `postgres` executa por ser owner/superuser,
mesmo padrao das rodadas BACKFILL-01/02/03 (SMP/SM10/BW10).
A Secao 0 imprime current_user/session_user. Se nao for `postgres`, ABORTAR.

-------------------------------------------------------------------------------
SEMANTICA TRANSACIONAL
-------------------------------------------------------------------------------
BEGIN/COMMIT fail-closed. Todos os guards sao RAISE EXCEPTION dentro do bloco:
qualquer guard que falhe aborta a transacao inteira e NADA e escrito. Nao ha
caminho de escrita parcial. Executar UMA unica vez.

Pre-requisitos:
- Query 6112/6113 (card_primary_species) CONFIRMADO EXECUTADO / LIVE;
- Query 6115 v1.2 CONFIRMADO EXECUTADO / LIVE;
- baseline card_primary_species = 16.657 (guard G1).
===============================================================================
*/


-- =============================================================================
-- SECAO 0 — IDENTIDADE DE EXECUCAO (read-only, obrigatoria antes da Secao 1)
-- =============================================================================
SELECT
    current_user            AS current_user_deve_ser_postgres,
    session_user            AS session_user_deve_ser_postgres,
    current_database()      AS banco,
    now()                   AS momento;


-- =============================================================================
-- SECAO 1 — BACKFILL (transacional, fail-closed, ZERO CREATE)
-- =============================================================================
BEGIN;

DO $backfill$
DECLARE
    -- -------------------------------------------------------------------
    -- Constantes de contrato. Alterar qualquer uma exige nova autorizacao.
    -- -------------------------------------------------------------------
    -- me01-086: SOURCE_DATA_ERROR. Excluida do payload automatico; resolvida
    -- editorialmente pela Query 6130 (artefato separado).
    c_source_error_external_id CONSTANT TEXT := 'me01-086';
    c_source_error_dex_id      CONSTANT INT  := 351;  -- COMO OBSERVADO

    c_baseline_total     CONSTANT INT := 16657;  -- card_primary_species hoje
    c_evidencia_total    CONSTANT INT := 752;    -- itens congelados (v2.0)
    c_payload_total      CONSTANT INT := 751;    -- 752 - 1 SOURCE_DATA_ERROR
    c_source_error_total CONSTANT INT := 1;
    c_esperado_apos      CONSTANT INT := 17408;  -- 16657 + 751
    c_max_batch_size     CONSTANT INT := 10000;  -- guard da propria 6115

    -- Cardinalidade esperada do payload por Card Set.
    c_me1  CONSTANT INT := 151;   -- 152 - 1 (me01-086 excluida)
    c_me2  CONSTANT INT := 110;
    c_me25 CONSTANT INT := 243;
    c_me3  CONSTANT INT := 91;
    c_me4  CONSTANT INT := 97;
    c_mep  CONSTANT INT := 59;

    -- =================================================================
    -- EVIDENCIA CONGELADA — leitura TCGdex de 2026-09-12.
    -- 752 itens: {"e": external_card_id, "d": dexId observado}.
    -- Um item por Card POKEMON pendente dos seis Card Sets ME*.
    -- Cards da fonte sem Card local NAO entram (ver cabecalho).
    --
    -- ATENCAO (BACKFILL-SYNTAX-CORRECTION-01): o literal abaixo e dollar-quoted
    -- ($json$ ... $json$). TUDO entre os delimitadores e CONTEUDO JSON, nao
    -- codigo SQL — "--" ali dentro NAO e comentario e quebra o cast ::jsonb.
    -- Por isso a composicao por Card Set e as notas de escopo vivem AQUI FORA,
    -- e o literal contem exclusivamente os 752 itens.
    --
    -- COMPOSICAO POR CARD SET (ordem dos itens no literal, de cima para baixo):
    --   ME1   / me01   -> 152 itens : 001-112 · 133-164 · 177-182 · 187-188
    --   ME2   / me02   -> 110 itens : 001-084 · 095-115 · 125-128 · 130
    --   ME2.5 / me02.5 -> 243 itens : 001-179 · 218-253 · 265-290 · 294-295
    --   ME3   / me03   ->  91 itens : 001-067 · 089-107 · 118-121 · 124
    --   ME4   / me04   ->  97 itens : 001-073 · 087-105 · 116-119 · 122
    --   MEP   / mep    ->  59 itens : 001-027 · 029-045 · 064-071 · 074-080
    --                     TOTAL = 752
    --
    -- NOTA MEP: composicao determinada por database/seeds/840_seed_card.sql —
    -- 60 Cards MEP, das quais `028` (Fanfarra de Celebracao) e TRAINER ->
    -- 59 POKEMON. As 29 Cards Pokemon que a TCGdex tem em `mep` e o Mimikyu
    -- nao tem (046-063, 072, 073, 081-088, Museum) NAO entram nesta evidencia.
    -- =================================================================
    c_evidencia CONSTANT JSONB := $json$[
    {"e":"me01-001","d":1},{"e":"me01-002","d":2},{"e":"me01-003","d":3},{"e":"me01-004","d":102},
    {"e":"me01-005","d":103},{"e":"me01-006","d":114},{"e":"me01-007","d":465},{"e":"me01-008","d":152},
    {"e":"me01-009","d":153},{"e":"me01-010","d":154},{"e":"me01-011","d":213},{"e":"me01-012","d":251},
    {"e":"me01-013","d":273},{"e":"me01-014","d":274},{"e":"me01-015","d":275},{"e":"me01-016","d":290},
    {"e":"me01-017","d":291},{"e":"me01-018","d":781},{"e":"me01-019","d":37},{"e":"me01-020","d":38},
    {"e":"me01-021","d":322},{"e":"me01-022","d":323},{"e":"me01-023","d":667},{"e":"me01-024","d":668},
    {"e":"me01-025","d":721},{"e":"me01-026","d":813},{"e":"me01-027","d":814},{"e":"me01-028","d":815},
    {"e":"me01-029","d":850},{"e":"me01-030","d":851},{"e":"me01-031","d":1004},{"e":"me01-032","d":226},
    {"e":"me01-033","d":341},{"e":"me01-034","d":382},{"e":"me01-035","d":459},{"e":"me01-036","d":460},
    {"e":"me01-037","d":692},{"e":"me01-038","d":693},{"e":"me01-039","d":816},{"e":"me01-040","d":817},
    {"e":"me01-041","d":818},{"e":"me01-042","d":872},{"e":"me01-043","d":873},{"e":"me01-044","d":875},
    {"e":"me01-045","d":81},{"e":"me01-046","d":82},{"e":"me01-047","d":462},{"e":"me01-048","d":243},
    {"e":"me01-049","d":309},{"e":"me01-050","d":310},{"e":"me01-051","d":417},{"e":"me01-052","d":694},
    {"e":"me01-053","d":695},{"e":"me01-054","d":63},{"e":"me01-055","d":64},{"e":"me01-056","d":65},
    {"e":"me01-057","d":124},{"e":"me01-058","d":280},{"e":"me01-059","d":281},{"e":"me01-060","d":282},
    {"e":"me01-061","d":292},{"e":"me01-062","d":325},{"e":"me01-063","d":326},{"e":"me01-064","d":716},
    {"e":"me01-065","d":971},{"e":"me01-066","d":972},{"e":"me01-067","d":999},{"e":"me01-068","d":27},
    {"e":"me01-069","d":28},{"e":"me01-070","d":95},{"e":"me01-071","d":236},{"e":"me01-072","d":296},
    {"e":"me01-073","d":297},{"e":"me01-074","d":337},{"e":"me01-075","d":338},{"e":"me01-076","d":447},
    {"e":"me01-077","d":448},{"e":"me01-078","d":453},{"e":"me01-079","d":454},{"e":"me01-080","d":802},
    {"e":"me01-081","d":874},{"e":"me01-082","d":932},{"e":"me01-083","d":933},{"e":"me01-084","d":934},
    {"e":"me01-085","d":342},
    {"e":"me01-086","d":351},
    {"e":"me01-087","d":442},{"e":"me01-088","d":717},{"e":"me01-089","d":827},{"e":"me01-090","d":828},
    {"e":"me01-091","d":944},{"e":"me01-092","d":945},{"e":"me01-093","d":208},{"e":"me01-094","d":303},
    {"e":"me01-095","d":483},{"e":"me01-096","d":957},{"e":"me01-097","d":958},{"e":"me01-098","d":959},
    {"e":"me01-099","d":1000},{"e":"me01-100","d":380},{"e":"me01-101","d":381},{"e":"me01-102","d":21},
    {"e":"me01-103","d":22},{"e":"me01-104","d":115},{"e":"me01-105","d":225},{"e":"me01-106","d":241},
    {"e":"me01-107","d":427},{"e":"me01-108","d":428},{"e":"me01-109","d":734},{"e":"me01-110","d":735},
    {"e":"me01-111","d":759},{"e":"me01-112","d":760},
    {"e":"me01-133","d":1},{"e":"me01-134","d":2},{"e":"me01-135","d":103},{"e":"me01-136","d":213},
    {"e":"me01-137","d":291},{"e":"me01-138","d":37},{"e":"me01-139","d":667},{"e":"me01-140","d":459},
    {"e":"me01-141","d":693},{"e":"me01-142","d":818},{"e":"me01-143","d":694},{"e":"me01-144","d":292},
    {"e":"me01-145","d":972},{"e":"me01-146","d":802},{"e":"me01-147","d":934},{"e":"me01-148","d":442},
    {"e":"me01-149","d":944},{"e":"me01-150","d":208},{"e":"me01-151","d":21},{"e":"me01-152","d":225},
    {"e":"me01-153","d":735},{"e":"me01-154","d":759},{"e":"me01-155","d":3},{"e":"me01-156","d":323},
    {"e":"me01-157","d":460},{"e":"me01-158","d":310},{"e":"me01-159","d":282},{"e":"me01-160","d":448},
    {"e":"me01-161","d":359},{"e":"me01-162","d":303},{"e":"me01-163","d":380},{"e":"me01-164","d":115},
    {"e":"me01-177","d":3},{"e":"me01-178","d":282},{"e":"me01-179","d":448},{"e":"me01-180","d":359},
    {"e":"me01-181","d":380},{"e":"me01-182","d":115},
    {"e":"me01-187","d":282},{"e":"me01-188","d":448},
    {"e":"me02-001","d":43},{"e":"me02-002","d":44},{"e":"me02-003","d":45},{"e":"me02-004","d":214},
    {"e":"me02-005","d":270},{"e":"me02-006","d":271},{"e":"me02-007","d":272},{"e":"me02-008","d":649},
    {"e":"me02-009","d":919},{"e":"me02-010","d":920},{"e":"me02-011","d":4},{"e":"me02-012","d":5},
    {"e":"me02-013","d":6},{"e":"me02-014","d":146},{"e":"me02-015","d":554},{"e":"me02-016","d":555},
    {"e":"me02-017","d":643},{"e":"me02-018","d":741},{"e":"me02-019","d":935},{"e":"me02-020","d":937},
    {"e":"me02-021","d":86},{"e":"me02-022","d":87},{"e":"me02-023","d":220},{"e":"me02-024","d":221},
    {"e":"me02-025","d":473},{"e":"me02-026","d":245},{"e":"me02-027","d":393},{"e":"me02-028","d":394},
    {"e":"me02-029","d":479},{"e":"me02-030","d":835},{"e":"me02-031","d":836},{"e":"me02-032","d":921},
    {"e":"me02-033","d":922},{"e":"me02-034","d":923},{"e":"me02-035","d":200},{"e":"me02-036","d":429},
    {"e":"me02-037","d":209},{"e":"me02-038","d":210},{"e":"me02-039","d":488},{"e":"me02-040","d":648},
    {"e":"me02-041","d":719},{"e":"me02-042","d":778},{"e":"me02-043","d":868},{"e":"me02-044","d":869},
    {"e":"me02-045","d":888},{"e":"me02-046","d":946},{"e":"me02-047","d":947},{"e":"me02-048","d":128},
    {"e":"me02-049","d":207},{"e":"me02-050","d":472},{"e":"me02-051","d":328},{"e":"me02-052","d":329},
    {"e":"me02-053","d":330},{"e":"me02-054","d":92},{"e":"me02-055","d":93},{"e":"me02-056","d":94},
    {"e":"me02-057","d":198},{"e":"me02-058","d":430},{"e":"me02-059","d":302},{"e":"me02-060","d":318},
    {"e":"me02-061","d":319},{"e":"me02-062","d":336},{"e":"me02-063","d":359},{"e":"me02-064","d":551},
    {"e":"me02-065","d":552},{"e":"me02-066","d":553},{"e":"me02-067","d":848},{"e":"me02-068","d":849},
    {"e":"me02-069","d":890},{"e":"me02-070","d":395},{"e":"me02-071","d":436},{"e":"me02-072","d":437},
    {"e":"me02-073","d":777},{"e":"me02-074","d":884},{"e":"me02-075","d":1018},{"e":"me02-076","d":39},
    {"e":"me02-077","d":40},{"e":"me02-078","d":190},{"e":"me02-079","d":424},{"e":"me02-080","d":235},
    {"e":"me02-081","d":263},{"e":"me02-082","d":264},{"e":"me02-083","d":427},{"e":"me02-084","d":428},
    {"e":"me02-095","d":272},{"e":"me02-096","d":919},{"e":"me02-097","d":87},{"e":"me02-098","d":393},
    {"e":"me02-099","d":835},{"e":"me02-100","d":888},{"e":"me02-101","d":330},{"e":"me02-102","d":194},
    {"e":"me02-103","d":849},{"e":"me02-104","d":777},{"e":"me02-105","d":40},{"e":"me02-106","d":52},
    {"e":"me02-107","d":424},{"e":"me02-108","d":214},{"e":"me02-109","d":6},{"e":"me02-110","d":741},
    {"e":"me02-111","d":479},{"e":"me02-112","d":429},{"e":"me02-113","d":319},{"e":"me02-114","d":395},
    {"e":"me02-115","d":428},
    {"e":"me02-125","d":6},{"e":"me02-126","d":479},{"e":"me02-127","d":319},{"e":"me02-128","d":428},
    {"e":"me02-130","d":6},
    {"e":"me02.5-001","d":43},{"e":"me02.5-002","d":44},{"e":"me02.5-003","d":45},{"e":"me02.5-004","d":69},
    {"e":"me02.5-005","d":70},{"e":"me02.5-006","d":71},{"e":"me02.5-007","d":114},{"e":"me02.5-008","d":152},
    {"e":"me02.5-009","d":153},{"e":"me02.5-010","d":154},{"e":"me02.5-011","d":265},{"e":"me02.5-012","d":266},
    {"e":"me02.5-013","d":267},{"e":"me02.5-014","d":268},{"e":"me02.5-015","d":269},{"e":"me02.5-016","d":406},
    {"e":"me02.5-017","d":736},{"e":"me02.5-018","d":917},{"e":"me02.5-019","d":918},{"e":"me02.5-020","d":4},
    {"e":"me02.5-021","d":5},{"e":"me02.5-022","d":6},{"e":"me02.5-023","d":218},{"e":"me02.5-024","d":219},
    {"e":"me02.5-025","d":244},{"e":"me02.5-026","d":250},{"e":"me02.5-027","d":322},{"e":"me02.5-028","d":323},
    {"e":"me02.5-029","d":498},{"e":"me02.5-030","d":499},{"e":"me02.5-031","d":500},{"e":"me02.5-032","d":554},
    {"e":"me02.5-033","d":555},{"e":"me02.5-034","d":757},{"e":"me02.5-035","d":758},{"e":"me02.5-036","d":813},
    {"e":"me02.5-037","d":814},{"e":"me02.5-038","d":815},{"e":"me02.5-039","d":54},{"e":"me02.5-040","d":55},
    {"e":"me02.5-041","d":158},{"e":"me02.5-042","d":159},{"e":"me02.5-043","d":160},{"e":"me02.5-044","d":215},
    {"e":"me02.5-045","d":461},{"e":"me02.5-046","d":361},{"e":"me02.5-047","d":478},{"e":"me02.5-048","d":378},
    {"e":"me02.5-049","d":582},{"e":"me02.5-050","d":583},{"e":"me02.5-051","d":584},{"e":"me02.5-052","d":872},
    {"e":"me02.5-053","d":873},{"e":"me02.5-054","d":896},{"e":"me02.5-055","d":25},{"e":"me02.5-056","d":26},
    {"e":"me02.5-057","d":25},{"e":"me02.5-058","d":100},{"e":"me02.5-059","d":602},{"e":"me02.5-060","d":603},
    {"e":"me02.5-061","d":604},{"e":"me02.5-062","d":618},{"e":"me02.5-063","d":694},{"e":"me02.5-064","d":695},
    {"e":"me02.5-065","d":737},{"e":"me02.5-066","d":738},{"e":"me02.5-067","d":785},{"e":"me02.5-068","d":871},
    {"e":"me02.5-069","d":938},{"e":"me02.5-070","d":939},{"e":"me02.5-071","d":940},{"e":"me02.5-072","d":941},
    {"e":"me02.5-073","d":1008},{"e":"me02.5-074","d":35},{"e":"me02.5-075","d":36},{"e":"me02.5-076","d":35},
    {"e":"me02.5-077","d":102},{"e":"me02.5-078","d":103},{"e":"me02.5-079","d":150},{"e":"me02.5-080","d":175},
    {"e":"me02.5-081","d":176},{"e":"me02.5-082","d":468},{"e":"me02.5-083","d":183},{"e":"me02.5-084","d":184},
    {"e":"me02.5-085","d":200},{"e":"me02.5-086","d":429},{"e":"me02.5-087","d":280},{"e":"me02.5-088","d":281},
    {"e":"me02.5-089","d":282},{"e":"me02.5-090","d":353},{"e":"me02.5-091","d":354},{"e":"me02.5-092","d":479},
    {"e":"me02.5-093","d":684},{"e":"me02.5-094","d":685},{"e":"me02.5-095","d":708},{"e":"me02.5-096","d":709},
    {"e":"me02.5-097","d":778},{"e":"me02.5-098","d":897},{"e":"me02.5-099","d":1015},{"e":"me02.5-100","d":50},
    {"e":"me02.5-101","d":51},{"e":"me02.5-102","d":237},{"e":"me02.5-103","d":307},{"e":"me02.5-104","d":308},
    {"e":"me02.5-105","d":337},{"e":"me02.5-106","d":338},{"e":"me02.5-107","d":377},{"e":"me02.5-108","d":383},
    {"e":"me02.5-109","d":443},{"e":"me02.5-110","d":444},{"e":"me02.5-111","d":445},{"e":"me02.5-112","d":447},
    {"e":"me02.5-113","d":448},{"e":"me02.5-114","d":618},{"e":"me02.5-115","d":674},{"e":"me02.5-116","d":701},
    {"e":"me02.5-117","d":703},{"e":"me02.5-118","d":837},{"e":"me02.5-119","d":838},{"e":"me02.5-120","d":839},
    {"e":"me02.5-121","d":1007},{"e":"me02.5-122","d":1014},{"e":"me02.5-123","d":92},{"e":"me02.5-124","d":93},
    {"e":"me02.5-125","d":94},{"e":"me02.5-126","d":198},{"e":"me02.5-127","d":430},{"e":"me02.5-128","d":261},
    {"e":"me02.5-129","d":262},{"e":"me02.5-130","d":263},{"e":"me02.5-131","d":264},{"e":"me02.5-132","d":862},
    {"e":"me02.5-133","d":442},{"e":"me02.5-134","d":559},{"e":"me02.5-135","d":560},{"e":"me02.5-136","d":570},
    {"e":"me02.5-137","d":571},{"e":"me02.5-138","d":629},{"e":"me02.5-139","d":630},{"e":"me02.5-140","d":675},
    {"e":"me02.5-141","d":720},{"e":"me02.5-142","d":1016},{"e":"me02.5-143","d":1025},{"e":"me02.5-144","d":303},
    {"e":"me02.5-145","d":379},{"e":"me02.5-146","d":624},{"e":"me02.5-147","d":625},{"e":"me02.5-148","d":983},
    {"e":"me02.5-149","d":777},{"e":"me02.5-150","d":147},{"e":"me02.5-151","d":148},{"e":"me02.5-152","d":149},
    {"e":"me02.5-153","d":384},{"e":"me02.5-154","d":643},{"e":"me02.5-155","d":644},{"e":"me02.5-156","d":714},
    {"e":"me02.5-157","d":715},{"e":"me02.5-158","d":885},{"e":"me02.5-159","d":886},{"e":"me02.5-160","d":887},
    {"e":"me02.5-161","d":52},{"e":"me02.5-162","d":115},{"e":"me02.5-163","d":206},{"e":"me02.5-164","d":982},
    {"e":"me02.5-165","d":300},{"e":"me02.5-166","d":301},{"e":"me02.5-167","d":335},{"e":"me02.5-168","d":396},
    {"e":"me02.5-169","d":397},{"e":"me02.5-170","d":398},{"e":"me02.5-171","d":479},{"e":"me02.5-172","d":531},
    {"e":"me02.5-173","d":627},{"e":"me02.5-174","d":628},{"e":"me02.5-175","d":775},{"e":"me02.5-176","d":780},
    {"e":"me02.5-177","d":845},{"e":"me02.5-178","d":1024},{"e":"me02.5-179","d":1024},
    {"e":"me02.5-218","d":114},{"e":"me02.5-219","d":267},{"e":"me02.5-220","d":269},{"e":"me02.5-221","d":406},
    {"e":"me02.5-222","d":219},{"e":"me02.5-223","d":322},{"e":"me02.5-224","d":758},{"e":"me02.5-225","d":813},
    {"e":"me02.5-226","d":54},{"e":"me02.5-227","d":361},{"e":"me02.5-228","d":461},{"e":"me02.5-229","d":695},
    {"e":"me02.5-230","d":738},{"e":"me02.5-231","d":940},{"e":"me02.5-232","d":183},{"e":"me02.5-233","d":200},
    {"e":"me02.5-234","d":354},{"e":"me02.5-235","d":468},{"e":"me02.5-236","d":685},{"e":"me02.5-237","d":709},
    {"e":"me02.5-238","d":778},{"e":"me02.5-239","d":51},{"e":"me02.5-240","d":237},{"e":"me02.5-241","d":308},
    {"e":"me02.5-242","d":703},{"e":"me02.5-243","d":262},{"e":"me02.5-244","d":442},{"e":"me02.5-245","d":862},
    {"e":"me02.5-246","d":303},{"e":"me02.5-247","d":885},{"e":"me02.5-248","d":886},{"e":"me02.5-249","d":398},
    {"e":"me02.5-250","d":479},{"e":"me02.5-251","d":906},{"e":"me02.5-252","d":618},{"e":"me02.5-253","d":531},
    {"e":"me02.5-265","d":478},{"e":"me02.5-266","d":604},{"e":"me02.5-267","d":719},{"e":"me02.5-268","d":701},
    {"e":"me02.5-269","d":94},{"e":"me02.5-270","d":560},{"e":"me02.5-271","d":149},{"e":"me02.5-272","d":154},
    {"e":"me02.5-273","d":500},{"e":"me02.5-274","d":160},{"e":"me02.5-275","d":478},{"e":"me02.5-276","d":25},
    {"e":"me02.5-277","d":25},{"e":"me02.5-278","d":604},{"e":"me02.5-279","d":939},{"e":"me02.5-280","d":35},
    {"e":"me02.5-281","d":150},{"e":"me02.5-282","d":719},{"e":"me02.5-283","d":701},{"e":"me02.5-284","d":94},
    {"e":"me02.5-285","d":560},{"e":"me02.5-286","d":571},{"e":"me02.5-287","d":861},{"e":"me02.5-288","d":1016},
    {"e":"me02.5-289","d":376},{"e":"me02.5-290","d":149},
    {"e":"me02.5-294","d":6},{"e":"me02.5-295","d":149},
    {"e":"me03-001","d":167},{"e":"me03-002","d":168},{"e":"me03-003","d":492},{"e":"me03-004","d":495},
    {"e":"me03-005","d":496},{"e":"me03-006","d":497},{"e":"me03-007","d":664},{"e":"me03-008","d":665},
    {"e":"me03-009","d":666},{"e":"me03-010","d":722},{"e":"me03-011","d":723},{"e":"me03-012","d":724},
    {"e":"me03-013","d":662},{"e":"me03-014","d":663},{"e":"me03-015","d":757},{"e":"me03-016","d":758},
    {"e":"me03-017","d":776},{"e":"me03-018","d":86},{"e":"me03-019","d":87},{"e":"me03-020","d":120},
    {"e":"me03-021","d":121},{"e":"me03-022","d":131},{"e":"me03-023","d":698},{"e":"me03-024","d":699},
    {"e":"me03-025","d":721},{"e":"me03-026","d":403},{"e":"me03-027","d":404},{"e":"me03-028","d":405},
    {"e":"me03-029","d":702},{"e":"me03-030","d":35},{"e":"me03-031","d":36},{"e":"me03-032","d":303},
    {"e":"me03-033","d":677},{"e":"me03-034","d":678},{"e":"me03-035","d":682},{"e":"me03-036","d":683},
    {"e":"me03-037","d":299},{"e":"me03-038","d":476},{"e":"me03-039","d":449},{"e":"me03-040","d":450},
    {"e":"me03-041","d":645},{"e":"me03-042","d":688},{"e":"me03-043","d":689},{"e":"me03-044","d":696},
    {"e":"me03-045","d":697},{"e":"me03-046","d":701},{"e":"me03-047","d":718},{"e":"me03-048","d":92},
    {"e":"me03-049","d":93},{"e":"me03-050","d":94},{"e":"me03-051","d":451},{"e":"me03-052","d":452},
    {"e":"me03-053","d":717},{"e":"me03-054","d":1002},{"e":"me03-055","d":227},{"e":"me03-056","d":679},
    {"e":"me03-057","d":680},{"e":"me03-058","d":681},{"e":"me03-059","d":707},{"e":"me03-060","d":19},
    {"e":"me03-061","d":20},{"e":"me03-062","d":52},{"e":"me03-063","d":143},{"e":"me03-064","d":659},
    {"e":"me03-065","d":660},{"e":"me03-066","d":661},{"e":"me03-067","d":676},
    {"e":"me03-089","d":665},{"e":"me03-090","d":722},{"e":"me03-091","d":663},{"e":"me03-092","d":699},
    {"e":"me03-093","d":702},{"e":"me03-094","d":35},{"e":"me03-095","d":677},{"e":"me03-096","d":476},
    {"e":"me03-097","d":452},{"e":"me03-098","d":680},{"e":"me03-099","d":20},{"e":"me03-100","d":724},
    {"e":"me03-101","d":758},{"e":"me03-102","d":121},{"e":"me03-103","d":36},{"e":"me03-104","d":718},
    {"e":"me03-105","d":717},{"e":"me03-106","d":227},{"e":"me03-107","d":52},
    {"e":"me03-118","d":121},{"e":"me03-119","d":36},{"e":"me03-120","d":718},{"e":"me03-121","d":52},
    {"e":"me03-124","d":718},
    {"e":"me04-001","d":13},{"e":"me04-002","d":14},{"e":"me04-003","d":15},{"e":"me04-004","d":455},
    {"e":"me04-005","d":650},{"e":"me04-006","d":651},{"e":"me04-007","d":652},{"e":"me04-008","d":37},
    {"e":"me04-009","d":38},{"e":"me04-010","d":250},{"e":"me04-011","d":653},{"e":"me04-012","d":654},
    {"e":"me04-013","d":655},{"e":"me04-014","d":667},{"e":"me04-015","d":668},{"e":"me04-016","d":223},
    {"e":"me04-017","d":224},{"e":"me04-018","d":225},{"e":"me04-019","d":647},{"e":"me04-020","d":656},
    {"e":"me04-021","d":657},{"e":"me04-022","d":658},{"e":"me04-023","d":712},{"e":"me04-024","d":713},
    {"e":"me04-025","d":767},{"e":"me04-026","d":768},{"e":"me04-027","d":179},{"e":"me04-028","d":180},
    {"e":"me04-029","d":181},{"e":"me04-030","d":587},{"e":"me04-031","d":386},{"e":"me04-032","d":386},
    {"e":"me04-033","d":386},{"e":"me04-034","d":386},{"e":"me04-035","d":670},{"e":"me04-036","d":677},
    {"e":"me04-037","d":678},{"e":"me04-038","d":708},{"e":"me04-039","d":709},{"e":"me04-040","d":710},
    {"e":"me04-041","d":711},{"e":"me04-042","d":716},{"e":"me04-043","d":185},{"e":"me04-044","d":231},
    {"e":"me04-045","d":232},{"e":"me04-046","d":343},{"e":"me04-047","d":344},{"e":"me04-048","d":475},
    {"e":"me04-049","d":41},{"e":"me04-050","d":42},{"e":"me04-051","d":169},{"e":"me04-052","d":211},
    {"e":"me04-053","d":434},{"e":"me04-054","d":435},{"e":"me04-055","d":553},{"e":"me04-056","d":568},
    {"e":"me04-057","d":569},{"e":"me04-058","d":690},{"e":"me04-059","d":374},{"e":"me04-060","d":375},
    {"e":"me04-061","d":376},{"e":"me04-062","d":597},{"e":"me04-063","d":598},{"e":"me04-064","d":638},
    {"e":"me04-065","d":691},{"e":"me04-066","d":704},{"e":"me04-067","d":705},{"e":"me04-068","d":706},
    {"e":"me04-069","d":128},{"e":"me04-070","d":504},{"e":"me04-071","d":505},{"e":"me04-072","d":572},
    {"e":"me04-073","d":573},
    {"e":"me04-087","d":650},{"e":"me04-088","d":656},{"e":"me04-089","d":657},{"e":"me04-090","d":181},
    {"e":"me04-091","d":716},{"e":"me04-092","d":344},{"e":"me04-093","d":169},{"e":"me04-094","d":375},
    {"e":"me04-095","d":705},{"e":"me04-096","d":128},{"e":"me04-097","d":505},{"e":"me04-098","d":15},
    {"e":"me04-099","d":668},{"e":"me04-100","d":658},{"e":"me04-101","d":670},{"e":"me04-102","d":711},
    {"e":"me04-103","d":638},{"e":"me04-104","d":691},{"e":"me04-105","d":573},
    {"e":"me04-116","d":658},{"e":"me04-117","d":670},{"e":"me04-118","d":691},{"e":"me04-119","d":573},
    {"e":"me04-122","d":658},
    {"e":"mep-001","d":154},{"e":"mep-002","d":818},{"e":"mep-003","d":65},{"e":"mep-004","d":337},
    {"e":"mep-005","d":425},{"e":"mep-006","d":426},{"e":"mep-007","d":54},{"e":"mep-008","d":55},
    {"e":"mep-009","d":65},{"e":"mep-010","d":447},{"e":"mep-011","d":380},{"e":"mep-012","d":448},
    {"e":"mep-013","d":3},{"e":"mep-014","d":937},{"e":"mep-015","d":888},{"e":"mep-016","d":330},
    {"e":"mep-017","d":849},{"e":"mep-018","d":546},{"e":"mep-019","d":547},{"e":"mep-020","d":215},
    {"e":"mep-021","d":461},{"e":"mep-022","d":935},{"e":"mep-023","d":6},{"e":"mep-024","d":741},
    {"e":"mep-025","d":115},{"e":"mep-026","d":648},{"e":"mep-027","d":93},
    {"e":"mep-029","d":6},{"e":"mep-030","d":6},{"e":"mep-031","d":644},{"e":"mep-032","d":282},
    {"e":"mep-033","d":448},{"e":"mep-034","d":154},{"e":"mep-035","d":500},{"e":"mep-036","d":160},
    {"e":"mep-037","d":1},{"e":"mep-038","d":4},{"e":"mep-039","d":7},{"e":"mep-040","d":387},
    {"e":"mep-041","d":390},{"e":"mep-042","d":393},{"e":"mep-043","d":722},{"e":"mep-044","d":725},
    {"e":"mep-045","d":728},
    {"e":"mep-064","d":497},{"e":"mep-065","d":689},{"e":"mep-066","d":697},{"e":"mep-067","d":680},
    {"e":"mep-068","d":296},{"e":"mep-069","d":152},{"e":"mep-070","d":696},{"e":"mep-071","d":718},
    {"e":"mep-074","d":655},{"e":"mep-075","d":181},{"e":"mep-076","d":169},{"e":"mep-077","d":706},
    {"e":"mep-078","d":848},{"e":"mep-079","d":5},{"e":"mep-080","d":653}
    ]$json$::jsonb;

    -- Conjunto-alvo materializado uma unica vez, como JSONB. Nenhuma tabela.
    v_alvo    JSONB;
    v_payload JSONB;
    v_total   INT;
    v_n       INT;
    v_r       RECORD;
    v_set     RECORD;
BEGIN
    -- =================================================================
    -- G0 — evidencia congelada integra (cardinalidade + unicidade).
    -- =================================================================
    IF jsonb_typeof(c_evidencia) <> 'array' THEN
        RAISE EXCEPTION 'G0 FALHOU: c_evidencia nao e array JSON.';
    END IF;

    v_total := jsonb_array_length(c_evidencia);
    IF v_total <> c_evidencia_total THEN
        RAISE EXCEPTION 'G0 FALHOU: evidencia congelada tem % itens, esperado %.',
            v_total, c_evidencia_total;
    END IF;

    SELECT count(DISTINCT ev.e) INTO v_total
    FROM jsonb_to_recordset(c_evidencia) AS ev(e TEXT, d INT);
    IF v_total <> c_evidencia_total THEN
        RAISE EXCEPTION 'G0b FALHOU: % external_card_id distintos na evidencia, esperado %.',
            v_total, c_evidencia_total;
    END IF;

    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(c_evidencia) AS ev(e TEXT, d INT)
    WHERE ev.e IS NULL OR btrim(ev.e) = '' OR ev.d IS NULL OR ev.d <= 0;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G0c FALHOU: % itens da evidencia malformados.', v_total;
    END IF;

    -- =================================================================
    -- G1 — baseline global de card_primary_species.
    -- =================================================================
    SELECT count(*) INTO v_total FROM public.card_primary_species;
    IF v_total <> c_baseline_total THEN
        RAISE EXCEPTION 'G1 FALHOU: baseline card_primary_species = %, esperado %. '
                        'O universo mudou desde o AUDIT-01 — reauditar antes de executar.',
            v_total, c_baseline_total;
    END IF;

    -- =================================================================
    -- CONJUNTO-ALVO — materializado uma unica vez em variavel JSONB.
    -- =================================================================
    SELECT jsonb_agg(x ORDER BY x->>'set_code', x->>'external_card_id')
      INTO v_alvo
      FROM (
        SELECT DISTINCT jsonb_build_object(
                   'card_id',            c.id,
                   'set_code',           cs.code,
                   'external_card_id',   r.external_card_id,
                   'dex_id',             ev.d,
                   'pokemon_species_id', sp.id,
                   'canonical_name',     sp.canonical_name,
                   'card_name',          c.name,
                   'classificacao',      CASE
                                             WHEN r.external_card_id = c_source_error_external_id
                                                 THEN 'SOURCE_DATA_ERROR'
                                             ELSE 'AUTO_APPROVED'
                                         END
               ) AS x
        FROM jsonb_to_recordset(c_evidencia) AS ev(e TEXT, d INT)
        JOIN public.card_external_reference r ON r.external_card_id = ev.e AND r.is_active
        JOIN public.asset_source asrc         ON asrc.id = r.asset_source_id
        JOIN public.card c                    ON c.id = r.card_id
        JOIN public.card_category cc          ON cc.id = c.category_id
        JOIN public.card_set cs               ON cs.id = c.card_set_id
        LEFT JOIN public.pokemon_species sp
               ON sp.national_dex_number = ev.d AND sp.is_active
        LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
        WHERE asrc.code = 'TCGDEX'
          AND cc.code = 'POKEMON'
          AND c.is_active
          AND cps.card_id IS NULL
          AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
      ) s;

    -- =================================================================
    -- G2 — pareamento BIJETIVO evidencia <-> Cards pendentes ME*.
    -- =================================================================
    v_total := COALESCE(jsonb_array_length(v_alvo), 0);
    IF v_total <> c_evidencia_total THEN
        RAISE EXCEPTION 'G2 FALHOU: % Cards pareadas, esperado %.',
            v_total, c_evidencia_total;
    END IF;

    -- G2b — nenhuma Card pendente ME* ficou fora do alvo.
    SELECT count(*) INTO v_total
    FROM public.card c
    JOIN public.card_category cc ON cc.id = c.category_id
    JOIN public.card_set cs      ON cs.id = c.card_set_id
    LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
    WHERE cc.code = 'POKEMON' AND c.is_active AND cps.card_id IS NULL
      AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
      AND NOT EXISTS (
          SELECT 1 FROM jsonb_to_recordset(v_alvo)
                        AS a(card_id UUID) WHERE a.card_id = c.id);
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G2b FALHOU: % Cards pendentes ME* sem evidencia pareada.', v_total;
    END IF;

    -- G2c — nenhum item da evidencia ficou sem Card local. Prova que as 29
    --       Cards MEP fora de escopo foram corretamente removidas na v2.0.
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(c_evidencia) AS ev(e TEXT, d INT)
    WHERE NOT EXISTS (
        SELECT 1 FROM jsonb_to_recordset(v_alvo)
                      AS a(external_card_id TEXT) WHERE a.external_card_id = ev.e);
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G2c FALHOU: % itens da evidencia sem Card local pendente. '
                        'A evidencia desta rodada deve conter SOMENTE as 752 Cards '
                        'do escopo. ABORTADO.', v_total;
    END IF;

    -- =================================================================
    -- G3 — me01-086: presente, classificada SOURCE_DATA_ERROR, evidencia
    --      preservada como observada, e ainda sem resolucao.
    -- =================================================================
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(v_alvo) AS a(external_card_id TEXT, classificacao TEXT)
    WHERE a.external_card_id = c_source_error_external_id
      AND a.classificacao = 'SOURCE_DATA_ERROR';
    IF v_total <> c_source_error_total THEN
        RAISE EXCEPTION 'G3 FALHOU: % linhas SOURCE_DATA_ERROR para %, esperado %.',
            v_total, c_source_error_external_id, c_source_error_total;
    END IF;

    -- G3b — a evidencia congelada de me01-086 continua sendo o 351 OBSERVADO.
    --       Se alguem "corrigir" esse valor para 359 dentro deste arquivo, o
    --       registro do erro da fonte teria sido apagado e a premissa da 6130
    --       estaria invalidada.
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(c_evidencia) AS ev(e TEXT, d INT)
    WHERE ev.e = c_source_error_external_id AND ev.d = c_source_error_dex_id;
    IF v_total <> 1 THEN
        RAISE EXCEPTION 'G3b FALHOU: evidencia congelada de % nao e mais %. '
                        'O registro do erro da fonte foi alterado. ABORTADO.',
            c_source_error_external_id, c_source_error_dex_id;
    END IF;

    -- G3c — me01-086 ainda sem card_primary_species.
    SELECT count(*) INTO v_total
    FROM public.card_primary_species cps
    JOIN public.card_external_reference r ON r.card_id = cps.card_id
    WHERE r.external_card_id = c_source_error_external_id;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G3c FALHOU: % ja possui card_primary_species — estado inesperado.',
            c_source_error_external_id;
    END IF;

    -- =================================================================
    -- G4 — todo dexId resolve para pokemon_species ativa.
    -- =================================================================
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(v_alvo) AS a(pokemon_species_id UUID)
    WHERE a.pokemon_species_id IS NULL;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G4 FALHOU: % Cards com dexId que nao resolve para pokemon_species ativa.',
            v_total;
    END IF;

    -- =================================================================
    -- G5 — sem duplicidade.
    -- =================================================================
    SELECT count(*) INTO v_total FROM (
        SELECT a.card_id FROM jsonb_to_recordset(v_alvo) AS a(card_id UUID)
        GROUP BY a.card_id HAVING count(*) > 1) x;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G5 FALHOU: % card_id duplicados no alvo.', v_total;
    END IF;

    SELECT count(*) INTO v_total FROM (
        SELECT a.external_card_id
        FROM jsonb_to_recordset(v_alvo) AS a(external_card_id TEXT, card_id UUID)
        GROUP BY a.external_card_id HAVING count(DISTINCT a.card_id) > 1) x;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G5b FALHOU: % external_card_id apontando para mais de uma Card.',
            v_total;
    END IF;

    -- =================================================================
    -- G6 — nenhum card_id fora dos seis Card Sets.
    -- =================================================================
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(v_alvo) AS a(set_code TEXT)
    WHERE a.set_code NOT IN ('ME1','ME2','ME2.5','ME3','ME4','MEP');
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G6 FALHOU: % Cards fora dos seis Card Sets autorizados.', v_total;
    END IF;

    -- =================================================================
    -- G7 — CORROBORACAO POR NOME (guard antitranscricao, nao heuristica de
    --      decisao). Provado em AUDIT-01: 751/751 das AUTO_APPROVED tem o
    --      canonical_name da Species dentro do nome da Card. Um dexId
    --      transcrito errado que caisse em outra Species valida quebraria
    --      esta assercao e abortaria a transacao.
    -- =================================================================
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(v_alvo)
         AS a(classificacao TEXT, card_name TEXT, canonical_name TEXT)
    WHERE a.classificacao = 'AUTO_APPROVED'
      AND lower(regexp_replace(a.card_name,'[^a-zA-Z]','','g'))
          NOT LIKE '%' || lower(regexp_replace(a.canonical_name,'[^a-zA-Z]','','g')) || '%';
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G7 FALHOU: % Cards AUTO_APPROVED sem corroboracao por nome. '
                        'Esperado 0 (AUDIT-01 provou 751/751). Possivel erro de transcricao '
                        'da evidencia OU mudanca na fonte. NAO prosseguir sem reauditar.',
            v_total;
    END IF;

    -- =================================================================
    -- G8 — cardinalidade por Card Set do que sera enviado.
    -- =================================================================
    FOR v_set IN
        SELECT a.set_code, count(*) AS n
        FROM jsonb_to_recordset(v_alvo) AS a(set_code TEXT, classificacao TEXT)
        WHERE a.classificacao = 'AUTO_APPROVED'
        GROUP BY a.set_code ORDER BY a.set_code
    LOOP
        v_n := CASE v_set.set_code
                   WHEN 'ME1'   THEN c_me1
                   WHEN 'ME2'   THEN c_me2
                   WHEN 'ME2.5' THEN c_me25
                   WHEN 'ME3'   THEN c_me3
                   WHEN 'ME4'   THEN c_me4
                   WHEN 'MEP'   THEN c_mep
               END;
        IF v_set.n IS DISTINCT FROM v_n THEN
            RAISE EXCEPTION 'G8 FALHOU: Set % tem % Cards no payload, esperado %.',
                v_set.set_code, v_set.n, v_n;
        END IF;
        RAISE NOTICE 'G8 OK: Set % = % Cards.', v_set.set_code, v_set.n;
    END LOOP;

    -- =================================================================
    -- MONTAGEM DO PAYLOAD — contrato da 6115, ordenado por Set e por
    -- external_card_id (deterministico e auditavel). me01-086 e excluida
    -- aqui pela classificacao.
    -- =================================================================
    SELECT jsonb_agg(
               jsonb_build_object(
                   'card_id',        a.card_id,
                   'tcgdex_dex_ids', jsonb_build_array(a.dex_id)
               )
               ORDER BY a.set_code, a.external_card_id
           ),
           count(*)
      INTO v_payload, v_total
      FROM jsonb_to_recordset(v_alvo)
           AS a(card_id UUID, set_code TEXT, external_card_id TEXT,
                dex_id INT, classificacao TEXT)
     WHERE a.classificacao = 'AUTO_APPROVED';

    -- G9 — cardinalidade do payload.
    IF v_total <> c_payload_total THEN
        RAISE EXCEPTION 'G9 FALHOU: payload com % itens, esperado %.',
            v_total, c_payload_total;
    END IF;

    -- G9b — guard de lote da propria 6115 (nao alterar 6115; apenas nao
    --       violar seu contrato).
    IF v_total > c_max_batch_size THEN
        RAISE EXCEPTION 'G9b FALHOU: payload % excede c_max_batch_size % da 6115.',
            v_total, c_max_batch_size;
    END IF;

    -- G10 — PROVA DE EXCLUSAO: me01-086 nao esta no payload, por card_id.
    SELECT count(*) INTO v_total
    FROM jsonb_array_elements(v_payload) item
    JOIN public.card_external_reference r
      ON r.card_id = (item->>'card_id')::uuid
    WHERE r.external_card_id = c_source_error_external_id;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'G10 FALHOU: % aparece % vez(es) no payload. ABORTADO.',
            c_source_error_external_id, v_total;
    END IF;
    RAISE NOTICE 'G10 OK: % ausente do payload (SOURCE_DATA_ERROR preservado).',
        c_source_error_external_id;

    -- =================================================================
    -- EXECUCAO — chamada unica da 6115, transacao unica.
    -- =================================================================
    SELECT * INTO v_r FROM public.resolve_card_primary_species_bulk(v_payload);

    RAISE NOTICE 'RESULTADO 6115: resolved=% unchanged=% unresolved=% ambiguous=% conflict=% failed=%',
        v_r.resolved_count, v_r.unchanged_count, v_r.unresolved_count,
        v_r.ambiguous_count, v_r.conflict_count, v_r.failed_count;

    -- =================================================================
    -- ASSERCOES DE RESULTADO. Qualquer desvio aborta e reverte tudo.
    -- =================================================================
    IF v_r.resolved_count <> c_payload_total THEN
        RAISE EXCEPTION 'A1 FALHOU: resolved=%, esperado %. ROLLBACK.',
            v_r.resolved_count, c_payload_total;
    END IF;
    IF v_r.conflict_count <> 0 THEN
        RAISE EXCEPTION 'A2 FALHOU: conflict=%, esperado 0. ROLLBACK.', v_r.conflict_count;
    END IF;
    IF v_r.failed_count <> 0 THEN
        RAISE EXCEPTION 'A3 FALHOU: failed=%, esperado 0. details=%. ROLLBACK.',
            v_r.failed_count, v_r.details;
    END IF;
    IF v_r.ambiguous_count <> 0 THEN
        RAISE EXCEPTION 'A4 FALHOU: ambiguous=%, esperado 0. ROLLBACK.', v_r.ambiguous_count;
    END IF;
    IF v_r.unresolved_count <> 0 THEN
        RAISE EXCEPTION 'A5 FALHOU: unresolved=%, esperado 0. ROLLBACK.', v_r.unresolved_count;
    END IF;
    IF v_r.unchanged_count <> 0 THEN
        RAISE EXCEPTION 'A6 FALHOU: unchanged=%, esperado 0. ROLLBACK.', v_r.unchanged_count;
    END IF;

    -- A7 — total global pos-escrita.
    SELECT count(*) INTO v_total FROM public.card_primary_species;
    IF v_total <> c_esperado_apos THEN
        RAISE EXCEPTION 'A7 FALHOU: card_primary_species = %, esperado %. ROLLBACK.',
            v_total, c_esperado_apos;
    END IF;

    -- A8 — as 751 novas linhas sao todas AUTOMATIC_DEXID.
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(v_alvo) AS a(card_id UUID, classificacao TEXT)
    JOIN public.card_primary_species cps ON cps.card_id = a.card_id
    WHERE a.classificacao = 'AUTO_APPROVED'
      AND cps.resolution_basis = 'AUTOMATIC_DEXID';
    IF v_total <> c_payload_total THEN
        RAISE EXCEPTION 'A8 FALHOU: % linhas AUTOMATIC_DEXID, esperado %. ROLLBACK.',
            v_total, c_payload_total;
    END IF;

    -- A9 — a Species gravada e exatamente a da evidencia, Card a Card.
    SELECT count(*) INTO v_total
    FROM jsonb_to_recordset(v_alvo)
         AS a(card_id UUID, pokemon_species_id UUID, classificacao TEXT)
    JOIN public.card_primary_species cps ON cps.card_id = a.card_id
    WHERE a.classificacao = 'AUTO_APPROVED'
      AND cps.pokemon_species_id IS DISTINCT FROM a.pokemon_species_id;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'A9 FALHOU: % Cards gravadas com Species diferente da evidencia. ROLLBACK.',
            v_total;
    END IF;

    -- A10 — me01-086 continua SEM resolucao apos a escrita desta Query.
    --       (Sera resolvida pela 6130, editorialmente, em rodada propria.)
    SELECT count(*) INTO v_total
    FROM public.card_primary_species cps
    JOIN public.card_external_reference r ON r.card_id = cps.card_id
    WHERE r.external_card_id = c_source_error_external_id;
    IF v_total <> 0 THEN
        RAISE EXCEPTION 'A10 FALHOU: % foi resolvida indevidamente por esta Query. ROLLBACK.',
            c_source_error_external_id;
    END IF;
    RAISE NOTICE 'A10 OK: % nao foi tocada por esta Query (aguarda 6130).',
        c_source_error_external_id;

    RAISE NOTICE 'BACKFILL 6129 OK: 751 Cards resolvidas automaticamente, '
                 '1 SOURCE_DATA_ERROR reservada para a 6130, 0 conflitos, 0 falhas.';
END;
$backfill$;

COMMIT;
