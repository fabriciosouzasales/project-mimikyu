-- ============================================================================
-- Query 2230 — SEED dos 115 Edition Context Traits
-- Status: PROPOSTA — PROPOSAL ONLY · Versao 2.1
-- Mandato: EDITION-CONTEXT-AXIS-EDITORIAL-VOCABULARY-02
--          + EDITION-CONTEXT-AXIS-SECURITY-SEED-HARDENING-01 (v2.1, B1)
--
-- v2.1 — B1: name passa a ser o LABEL CANONICO PT-BR
--   A v2.0 gravava o rotulo INGLES em `name` e o rotulo PT-BR em
--   `description`. Isso divergia dos dois eixos irmaos, ambos PT-BR no LIVE
--   (card_variant_type.name = 'Holografica'; card_printing_profile.name =
--   'Sem Sombra · 1ª Edicao', Query 2169), e obrigaria o frontend a ler
--   `description` como label — inventando contrato.
--
--   Esta correcao NAO e um swap cego. Foi validada antes de escrever:
--     - 115/115 traits tem rotulo PT-BR distinto;
--     - nenhum rotulo PT-BR contem ' · ' (traco e ATOMICO, nunca composicao);
--     - o rotulo ingles NAO foi descartado: vive agora em `description`, como
--       "Termo editorial de origem (en)". Zero perda de informacao.
--
--   62 dos 115 tem PT == EN por serem NOMES PROPRIOS (jogadores, McDonalds,
--   GameStop, Pokémon Center, Pokémon 4Ever). Nome proprio nao se traduz —
--   por isso nenhum gate tenta detectar "ingles" heuristicamente. O gate real
--   de idioma e composicional e vive na Query 2231 (P5).
--
--   code, display_order, family, contagens e o mapa de tokens de B: INTOCADOS.
--
-- VOCABULARIO PREENCHIDO. Corpus: as 1.085 rows EDITION_CONTEXT da particao
-- canonica (FINISH 423 / PRINTING 72 / EC 1.085 / INDETERMINATE 61 / HOLD 1).
--
--   96 traits do corpus A (96 tokens observados)
--   19 traits exclusivos do legado B (SEED-COVERAGE.md, lista congelada)
--   115 total
--
-- NAO-1:1 PROVADO: 'PLAYER-REWARD' (B) e 'PLAYER-REWARDS-PROGRAM' (A) apontam
-- para PROGRAM_PLAYER_REWARDS; 'WOTC' (B) e 'W-PROMO' (A) para
-- CHANNEL_WOTC_PROMO. 117 tokens de origem -> 115 traits.
--
-- Nenhum code foi transliterado de token: TOP-SIXTEEN -> PLACEMENT_TOP_16,
-- TOP-THIRTY-TWO -> PLACEMENT_TOP_32, GOLD-BORDER -> CHANNEL_FRUIT_ROLLS.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE seed_ec_trait (
    family TEXT, code TEXT, name TEXT, description TEXT, display_order INT
) ON COMMIT DROP;

INSERT INTO seed_ec_trait (family, code, name, description, display_order) VALUES
    ('ARTWORK_MARK', 'ARTWORK_MFB_BLUE_BORDER', 'My First Battle — Borda Azul', 'Traço de Contexto de Edição da família Marca de Arte. Termo editorial de origem (en): "My First Battle — Blue Border".', 10),
    ('ARTWORK_MARK', 'ARTWORK_MFB_POKE_BALL', 'My First Battle — Marca Poké Ball', 'Traço de Contexto de Edição da família Marca de Arte. Termo editorial de origem (en): "My First Battle — Poké Ball Mark".', 20),
    ('ARTWORK_MARK', 'ARTWORK_SET_LOGO', 'Selo com Logo da Coleção', 'Traço de Contexto de Edição da família Marca de Arte. Termo editorial de origem (en): "Set Logo Stamp".', 30),
    ('CAMPAIGN', 'CAMPAIGN_10TH_ANNIVERSARY', '10º Aniversário', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "10th Anniversary".', 10),
    ('CAMPAIGN', 'CAMPAIGN_25TH_ANNIVERSARY', 'Celebração de 25 Anos', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "25th Anniversary Celebration".', 20),
    ('CAMPAIGN', 'CAMPAIGN_COUNTDOWN_CALENDAR', 'Calendário de Contagem Regressiva', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Countdown Calendar".', 30),
    ('CAMPAIGN', 'CAMPAIGN_DESTINY_DEOXYS', 'Destino Deoxys', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Destiny Deoxys".', 40),
    ('CAMPAIGN', 'CAMPAIGN_FIRST_MOVIE', 'Primeiro Filme', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "First Movie".', 50),
    ('CAMPAIGN', 'CAMPAIGN_FIRST_MOVIE_INVERTED', 'Primeiro Filme — Invertido', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "First Movie — Inverted".', 60),
    ('CAMPAIGN', 'CAMPAIGN_HORIZONS', 'Horizontes', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Horizons".', 70),
    ('CAMPAIGN', 'CAMPAIGN_PLATINUM', 'Promoção da Série Platinum', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Platinum Series Promotion".', 80),
    ('CAMPAIGN', 'CAMPAIGN_POKEMON_4EVER', 'Pokémon 4Ever', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Pokémon 4Ever".', 90),
    ('CAMPAIGN', 'CAMPAIGN_POKEMON_DAY_30TH', '30º Dia Pokémon', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Pokémon Day 30th".', 100),
    ('CAMPAIGN', 'CAMPAIGN_POKEMON_TOGETHER', 'Pokémon Together', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Pokémon Together".', 110),
    ('CAMPAIGN', 'CAMPAIGN_THANK_YOU', 'Agradecimento', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Thank You".', 120),
    ('CAMPAIGN', 'CAMPAIGN_TRICK_OR_TRADE', 'Trick or Trade', 'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Trick or Trade".', 130),
    ('CHANNEL', 'CHANNEL_ASIA_2023_24', 'Ásia 2023–24', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Asia 2023–24".', 10),
    ('CHANNEL', 'CHANNEL_ASIA_PROMO', 'Promo Ásia', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Asia Promo".', 20),
    ('CHANNEL', 'CHANNEL_EB_GAMES', 'EB Games', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "EB Games".', 30),
    ('CHANNEL', 'CHANNEL_FRUIT_ROLLS', 'Promo Fruit Rolls', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Fruit Rolls Promo".', 40),
    ('CHANNEL', 'CHANNEL_GAMESTOP', 'GameStop', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "GameStop".', 50),
    ('CHANNEL', 'CHANNEL_INQUEST_GAMER', 'InQuest Gamer', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "InQuest Gamer".', 60),
    ('CHANNEL', 'CHANNEL_KRAZE_CLUB', 'Kraze Club', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Kraze Club".', 70),
    ('CHANNEL', 'CHANNEL_MCDONALDS', 'McDonald''s', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "McDonald''s".', 80),
    ('CHANNEL', 'CHANNEL_MFB_DECK_BULBASAUR', 'My First Battle — Deck Bulbasaur', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "My First Battle — Bulbasaur Deck".', 90),
    ('CHANNEL', 'CHANNEL_MFB_DECK_CHARMANDER', 'My First Battle — Deck Charmander', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "My First Battle — Charmander Deck".', 100),
    ('CHANNEL', 'CHANNEL_MFB_DECK_PIKACHU', 'My First Battle — Deck Pikachu', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "My First Battle — Pikachu Deck".', 110),
    ('CHANNEL', 'CHANNEL_MFB_DECK_SQUIRTLE', 'My First Battle — Deck Squirtle', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "My First Battle — Squirtle Deck".', 120),
    ('CHANNEL', 'CHANNEL_POKEMON_CENTER', 'Pokémon Center', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Pokémon Center".', 130),
    ('CHANNEL', 'CHANNEL_POKEMON_CENTER_NY', 'Pokémon Center Nova York', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Pokémon Center New York".', 140),
    ('CHANNEL', 'CHANNEL_SCRYE', 'Revista Scrye', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Scrye Magazine".', 150),
    ('CHANNEL', 'CHANNEL_WOTC_PROMO', 'Promo Wizards of the Coast', 'Traço de Contexto de Edição da família Canal. Termo editorial de origem (en): "Wizards of the Coast Promo".', 160),
    ('DECK_PLAYER', 'DECK_PLAYER_AKIRA_MIYAZAKI', 'Akira Miyazaki', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Akira Miyazaki".', 10),
    ('DECK_PLAYER', 'DECK_PLAYER_CHASE_MOLONEY', 'Chase Moloney', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Chase Moloney".', 20),
    ('DECK_PLAYER', 'DECK_PLAYER_CHRISTOPHER_KAN', 'Christopher Kan', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Christopher Kan".', 30),
    ('DECK_PLAYER', 'DECK_PLAYER_CHRIS_FULOP', 'Chris Fulop', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Chris Fulop".', 40),
    ('DECK_PLAYER', 'DECK_PLAYER_CURRAN_HILL', 'Curran Hill', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Curran Hill".', 50),
    ('DECK_PLAYER', 'DECK_PLAYER_DAVID_COHEN', 'David Cohen', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "David Cohen".', 60),
    ('DECK_PLAYER', 'DECK_PLAYER_DYLAN_LEFAVOUR', 'Dylan Lefavour', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Dylan Lefavour".', 70),
    ('DECK_PLAYER', 'DECK_PLAYER_GABRIEL_FERNANDEZ', 'Gabriel Fernandez', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Gabriel Fernandez".', 80),
    ('DECK_PLAYER', 'DECK_PLAYER_GUSTAVO_WADA', 'Gustavo Wada', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Gustavo Wada".', 90),
    ('DECK_PLAYER', 'DECK_PLAYER_HIROKI_YANO', 'Hiroki Yano', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Hiroki Yano".', 100),
    ('DECK_PLAYER', 'DECK_PLAYER_IGOR_COSTA', 'Igor Costa', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Igor Costa".', 110),
    ('DECK_PLAYER', 'DECK_PLAYER_JASON_KLACZYNSKI', 'Jason Klaczynski', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Jason Klaczynski".', 120),
    ('DECK_PLAYER', 'DECK_PLAYER_JASON_MARTINEZ', 'Jason Martinez', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Jason Martinez".', 130),
    ('DECK_PLAYER', 'DECK_PLAYER_JEREMY_MARON', 'Jeremy Maron', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Jeremy Maron".', 140),
    ('DECK_PLAYER', 'DECK_PLAYER_JEREMY_SCHARFF_KIM', 'Jeremy Scharff-Kim', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Jeremy Scharff-Kim".', 150),
    ('DECK_PLAYER', 'DECK_PLAYER_JESSE_PARKER', 'Jesse Parker', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Jesse Parker".', 160),
    ('DECK_PLAYER', 'DECK_PLAYER_JIMMY_BALLARD', 'Jimmy Ballard', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Jimmy Ballard".', 170),
    ('DECK_PLAYER', 'DECK_PLAYER_JUN_HASEBE', 'Jun Hasebe', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Jun Hasebe".', 180),
    ('DECK_PLAYER', 'DECK_PLAYER_KEVIN_NGUYEN', 'Kevin Nguyen', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Kevin Nguyen".', 190),
    ('DECK_PLAYER', 'DECK_PLAYER_MICHAEL_GONZALEZ', 'Michael Gonzalez', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Michael Gonzalez".', 200),
    ('DECK_PLAYER', 'DECK_PLAYER_MICHAEL_PRAMAWAT', 'Michael Pramawat', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Michael Pramawat".', 210),
    ('DECK_PLAYER', 'DECK_PLAYER_MISKA_SAARI', 'Miska Saari', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Miska Saari".', 220),
    ('DECK_PLAYER', 'DECK_PLAYER_MYCHAEL_BRYAN', 'Mychael Bryan', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Mychael Bryan".', 230),
    ('DECK_PLAYER', 'DECK_PLAYER_PAUL_ATANASSOV', 'Paul Atanassov', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Paul Atanassov".', 240),
    ('DECK_PLAYER', 'DECK_PLAYER_REED_WEICHLER', 'Reed Weichler', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Reed Weichler".', 250),
    ('DECK_PLAYER', 'DECK_PLAYER_ROSS_CAWTHORN', 'Ross Cawthorn', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Ross Cawthorn".', 260),
    ('DECK_PLAYER', 'DECK_PLAYER_SAKUYA_OTA', 'Sakuya Ota', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Sakuya Ota".', 270),
    ('DECK_PLAYER', 'DECK_PLAYER_SHAO_TONG_YEN', 'Shao Tong Yen', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Shao Tong Yen".', 280),
    ('DECK_PLAYER', 'DECK_PLAYER_SHUTO_ITAGAKI', 'Shuto Itagaki', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Shuto Itagaki".', 290),
    ('DECK_PLAYER', 'DECK_PLAYER_STEPHEN_SILVESTRO', 'Stephen Silvestro', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Stephen Silvestro".', 300),
    ('DECK_PLAYER', 'DECK_PLAYER_TAKASHI_YONEDA', 'Takashi Yoneda', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Takashi Yoneda".', 310),
    ('DECK_PLAYER', 'DECK_PLAYER_TOM_ROOS', 'Tom Roos', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Tom Roos".', 320),
    ('DECK_PLAYER', 'DECK_PLAYER_TRISTAN_ROBINSON', 'Tristan Robinson', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Tristan Robinson".', 330),
    ('DECK_PLAYER', 'DECK_PLAYER_TSUBASA_NAKAMURA', 'Tsubasa Nakamura', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Tsubasa Nakamura".', 340),
    ('DECK_PLAYER', 'DECK_PLAYER_TSUGUYOSHI_YAMATO', 'Tsuguyoshi Yamato', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Tsuguyoshi Yamato".', 350),
    ('DECK_PLAYER', 'DECK_PLAYER_YUKA_FURUSAWA', 'Yuka Furusawa', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Yuka Furusawa".', 360),
    ('DECK_PLAYER', 'DECK_PLAYER_YUTA_KOMATSUDA', 'Yuta Komatsuda', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Yuta Komatsuda".', 370),
    ('DECK_PLAYER', 'DECK_PLAYER_ZACHARY_BOKHARI', 'Zachary Bokhari', 'Traço de Contexto de Edição da família Deck de Jogador. Termo editorial de origem (en): "Zachary Bokhari".', 380),
    ('EVENT', 'EVENT_CHICAGO_2009', 'Chicago 2009', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Chicago 2009".', 10),
    ('EVENT', 'EVENT_CITIES', 'Campeonato Municipal', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "City Championships".', 20),
    ('EVENT', 'EVENT_COMIC_CON', 'Comic-Con', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Comic-Con".', 30),
    ('EVENT', 'EVENT_DISTRIBUTOR_MEETING', 'Encontro de Distribuidores', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Distributor Meeting".', 40),
    ('EVENT', 'EVENT_GAMES_EXPO', 'Games Expo', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Games Expo".', 50),
    ('EVENT', 'EVENT_GEN_CON', 'Gen Con', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Gen Con".', 60),
    ('EVENT', 'EVENT_GYM_CHALLENGE', 'Desafio de Ginásio', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Gym Challenge".', 70),
    ('EVENT', 'EVENT_INTERNATIONALS_EUROPE', 'Campeonato Internacional — Europa', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "International Championships — Europe".', 80),
    ('EVENT', 'EVENT_INTERNATIONALS_NORTH_AMERICA', 'Campeonato Internacional — América do Norte', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "International Championships — North America".', 90),
    ('EVENT', 'EVENT_NATIONALS', 'Campeonato Nacional', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "National Championships".', 100),
    ('EVENT', 'EVENT_NINTENDO_WORLD', 'Nintendo World', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Nintendo World".', 110),
    ('EVENT', 'EVENT_ORIGINS', 'Origins Game Fair', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Origins Game Fair".', 120),
    ('EVENT', 'EVENT_ORIGINS_2008', 'Origins Game Fair 2008', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Origins Game Fair 2008".', 130),
    ('EVENT', 'EVENT_POKEMON_DAY', 'Dia Pokémon', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Pokémon Day".', 140),
    ('EVENT', 'EVENT_POKEMON_ROCKS_AMERICA', 'Pokémon Rocks America', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Pokémon Rocks America".', 150),
    ('EVENT', 'EVENT_POKETOUR_99', 'PokéTour ''99', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "PokéTour ''99".', 160),
    ('EVENT', 'EVENT_POP_TOURNAMENT', 'Torneio POP', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "POP Tournament".', 170),
    ('EVENT', 'EVENT_PRERELEASE', 'Pré-lançamento', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Prerelease".', 180),
    ('EVENT', 'EVENT_REGIONALS', 'Campeonato Regional', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Regional Championships".', 190),
    ('EVENT', 'EVENT_STADIUM_CHALLENGE', 'Stadium Challenge', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Stadium Challenge".', 200),
    ('EVENT', 'EVENT_STATES', 'Campeonato Estadual', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "State Championships".', 210),
    ('EVENT', 'EVENT_WIZARD_WORLD_CHICAGO', 'Wizard World Chicago', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Wizard World Chicago".', 220),
    ('EVENT', 'EVENT_WIZARD_WORLD_PHILADELPHIA', 'Wizard World Philadelphia', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "Wizard World Philadelphia".', 230),
    ('EVENT', 'EVENT_WORLDS_2004', 'Campeonato Mundial 2004', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2004".', 240),
    ('EVENT', 'EVENT_WORLDS_2005', 'Campeonato Mundial 2005', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2005".', 250),
    ('EVENT', 'EVENT_WORLDS_2007', 'Campeonato Mundial 2007', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2007".', 260),
    ('EVENT', 'EVENT_WORLDS_2008', 'Campeonato Mundial 2008', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2008".', 270),
    ('EVENT', 'EVENT_WORLDS_2009', 'Campeonato Mundial 2009', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2009".', 280),
    ('EVENT', 'EVENT_WORLDS_2010', 'Campeonato Mundial 2010', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2010".', 290),
    ('EVENT', 'EVENT_WORLDS_2023', 'Campeonato Mundial 2023', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2023".', 300),
    ('EVENT', 'EVENT_WORLDS_2024', 'Campeonato Mundial 2024', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2024".', 310),
    ('EVENT', 'EVENT_WORLDS_2025', 'Campeonato Mundial 2025', 'Traço de Contexto de Edição da família Evento. Termo editorial de origem (en): "World Championships 2025".', 320),
    ('PLACEMENT', 'PLACEMENT_FINALIST', 'Finalista', 'Traço de Contexto de Edição da família Colocação. Termo editorial de origem (en): "Finalist".', 10),
    ('PLACEMENT', 'PLACEMENT_QUARTER_FINALIST', 'Quartas de Final', 'Traço de Contexto de Edição da família Colocação. Termo editorial de origem (en): "Quarter-Finalist".', 20),
    ('PLACEMENT', 'PLACEMENT_SEMI_FINALIST', 'Semifinalista', 'Traço de Contexto de Edição da família Colocação. Termo editorial de origem (en): "Semi-Finalist".', 30),
    ('PLACEMENT', 'PLACEMENT_TOP_16', 'Top 16', 'Traço de Contexto de Edição da família Colocação. Termo editorial de origem (en): "Top 16".', 40),
    ('PLACEMENT', 'PLACEMENT_TOP_32', 'Top 32', 'Traço de Contexto de Edição da família Colocação. Termo editorial de origem (en): "Top 32".', 50),
    ('PLACEMENT', 'PLACEMENT_TOP_8', 'Top 8', 'Traço de Contexto de Edição da família Colocação. Termo editorial de origem (en): "Top 8".', 60),
    ('PLACEMENT', 'PLACEMENT_WINNER', 'Campeão', 'Traço de Contexto de Edição da família Colocação. Termo editorial de origem (en): "Winner".', 70),
    ('PROGRAM', 'PROGRAM_LEAGUE', 'Programa de Liga', 'Traço de Contexto de Edição da família Programa. Termo editorial de origem (en): "League Program".', 10),
    ('PROGRAM', 'PROGRAM_LEAGUE_POKE_BALL', 'Liga — Nível Poké Ball', 'Traço de Contexto de Edição da família Programa. Termo editorial de origem (en): "League — Poké Ball Tier".', 20),
    ('PROGRAM', 'PROGRAM_LEAGUE_ULTRA_BALL', 'Liga — Nível Ultra Ball', 'Traço de Contexto de Edição da família Programa. Termo editorial de origem (en): "League — Ultra Ball Tier".', 30),
    ('PROGRAM', 'PROGRAM_PLAYER_REWARDS', 'Programa Player Rewards', 'Traço de Contexto de Edição da família Programa. Termo editorial de origem (en): "Player Rewards Program".', 40),
    ('PROGRAM', 'PROGRAM_PROFESSOR', 'Programa Professor', 'Traço de Contexto de Edição da família Programa. Termo editorial de origem (en): "Professor Program".', 50),
    ('ROLE', 'ROLE_STAFF', 'Equipe', 'Traço de Contexto de Edição da família Função. Termo editorial de origem (en): "Staff".', 10);

-- ---------------------------------------------------------------- PASSO 1 ---
DO $$
DECLARE v_n INT; v_dp INT; v_dup INT; v_fmt INT; v_ord INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM seed_ec_trait;
    IF v_n <> 115 THEN RAISE EXCEPTION 'SEED_TRAIT_COUNT: esperado 115, obtido %.', v_n; END IF;

    SELECT COUNT(*) INTO v_dp FROM seed_ec_trait WHERE family = 'DECK_PLAYER';
    IF v_dp <> 38 THEN RAISE EXCEPTION 'SEED_DECK_PLAYER_COUNT (E2): esperado 38, obtido %.', v_dp; END IF;
    IF EXISTS (SELECT 1 FROM seed_ec_trait WHERE family='DECK_PLAYER' AND code NOT LIKE 'DECK_PLAYER\_%') THEN
        RAISE EXCEPTION 'SEED_DECK_PLAYER_PREFIX: code de jogador sem prefixo.'; END IF;

    SELECT COUNT(*) INTO v_fmt FROM seed_ec_trait WHERE code !~ '^[A-Z][A-Z0-9_]*$';
    IF v_fmt <> 0 THEN RAISE EXCEPTION 'SEED_CODE_FORMAT: % codes fora do padrao.', v_fmt; END IF;

    SELECT COUNT(*) INTO v_dup FROM (SELECT code FROM seed_ec_trait GROUP BY code HAVING COUNT(*)>1) d;
    IF v_dup <> 0 THEN RAISE EXCEPTION 'SEED_CODE_DUPLICATE: % codes repetidos.', v_dup; END IF;

    SELECT COUNT(*) INTO v_ord FROM (SELECT family,display_order FROM seed_ec_trait
        GROUP BY family,display_order HAVING COUNT(*)>1) d;
    IF v_ord <> 0 THEN RAISE EXCEPTION 'SEED_ORDER_COLLISION: % pares repetidos.', v_ord; END IF;

    IF EXISTS (SELECT 1 FROM seed_ec_trait WHERE family NOT IN
        ('EVENT','PLACEMENT','ROLE','DECK_PLAYER','CHANNEL','PROGRAM','CAMPAIGN','ARTWORK_MARK')) THEN
        RAISE EXCEPTION 'SEED_FAMILY_UNKNOWN: nona familia criada.'; END IF;

    -- T4 (B1) — name e LABEL ATOMICO PT-BR, nunca composicao nem descricao.
    IF EXISTS (SELECT 1 FROM seed_ec_trait WHERE btrim(COALESCE(name,'')) = '') THEN
        RAISE EXCEPTION 'SEED_TRAIT_NAME_BLANK (B1): trait sem label.'; END IF;
    IF EXISTS (SELECT 1 FROM seed_ec_trait WHERE name LIKE '%' || ' ' || chr(183) || ' ' || '%') THEN
        RAISE EXCEPTION 'SEED_TRAIT_NAME_COMPOSED (B1): label de traco contem o separador de composicao. Traco e atomico.'; END IF;
    IF EXISTS (SELECT 1 FROM seed_ec_trait WHERE length(name) > 120) THEN
        RAISE EXCEPTION 'SEED_TRAIT_NAME_TOO_LONG (B1): excede VARCHAR(120) de card_edition_context_trait.name.'; END IF;
    -- description e FRASE, nunca label alternativo: precisa registrar a origem.
    IF EXISTS (SELECT 1 FROM seed_ec_trait WHERE description NOT LIKE '%Termo editorial de origem (en):%') THEN
        RAISE EXCEPTION 'SEED_TRAIT_DESC_SHAPE (B1): description sem o termo editorial de origem.'; END IF;
    IF EXISTS (SELECT 1 FROM seed_ec_trait WHERE description = name) THEN
        RAISE EXCEPTION 'SEED_TRAIT_DESC_IS_LABEL (B1): description repetindo o label.'; END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
INSERT INTO public.card_edition_context_trait
    (game_id, family, code, name, description, display_order)
SELECT g.id, s.family, s.code, s.name, s.description, s.display_order
  FROM seed_ec_trait s
  CROSS JOIN LATERAL (SELECT id FROM public.game WHERE code='PTCG') g;

-- ---------------------------------------------------------------- PASSO 3 ---
-- T2 — os 21 tokens exclusivos de B tem destino. Mapa explicito (nao-1:1).
DO $$
DECLARE v_n INT; v_orfao TEXT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM public.card_edition_context_trait;
    IF v_n <> 115 THEN RAISE EXCEPTION 'SEED_POSTCHECK_COUNT: esperado 115, obtido %.', v_n; END IF;

    CREATE TEMP TABLE seed_b_token_map (source_token TEXT, code TEXT) ON COMMIT DROP;
    INSERT INTO seed_b_token_map VALUES
        ('WORLDS-2023', 'EVENT_WORLDS_2023'),
        ('WORLDS-2024', 'EVENT_WORLDS_2024'),
        ('WORLDS-2025', 'EVENT_WORLDS_2025'),
        ('TOP-EIGHT', 'PLACEMENT_TOP_8'),
        ('LEAGUE', 'PROGRAM_LEAGUE'),
        ('ULTRA-BALL-LEAGUE', 'PROGRAM_LEAGUE_ULTRA_BALL'),
        ('POKEMON-CENTER', 'CHANNEL_POKEMON_CENTER'),
        ('POKEMON-CENTER-NY', 'CHANNEL_POKEMON_CENTER_NY'),
        ('1ST-MOVIE', 'CAMPAIGN_FIRST_MOVIE'),
        ('1ST-MOVIE-INVERTED', 'CAMPAIGN_FIRST_MOVIE_INVERTED'),
        ('30TH-POKEDAY', 'CAMPAIGN_POKEMON_DAY_30TH'),
        ('ASIA-2023-24', 'CHANNEL_ASIA_2023_24'),
        ('GYM-CHALLENGE', 'EVENT_GYM_CHALLENGE'),
        ('HORIZONS', 'CAMPAIGN_HORIZONS'),
        ('INTERNATIONAL-CHAMPIONSHIP-EUROPE', 'EVENT_INTERNATIONALS_EUROPE'),
        ('INTERNATIONAL-CHAMPIONSHIP-NORTH-AMERICA', 'EVENT_INTERNATIONALS_NORTH_AMERICA'),
        ('POKEMON-4-EVER', 'CAMPAIGN_POKEMON_4EVER'),
        ('POKEMON-TOGETHER', 'CAMPAIGN_POKEMON_TOGETHER'),
        ('POKETOUR-99', 'EVENT_POKETOUR_99'),
        ('PLAYER-REWARD', 'PROGRAM_PLAYER_REWARDS'),
        ('WOTC', 'CHANNEL_WOTC_PROMO');

    SELECT string_agg(m.source_token, ', ') INTO v_orfao FROM seed_b_token_map m
     WHERE NOT EXISTS (SELECT 1 FROM public.card_edition_context_trait x WHERE x.code = m.code);
    IF v_orfao IS NOT NULL THEN
        RAISE EXCEPTION 'SEED_B_EXCLUSIVE_ORPHAN (T2): %.', v_orfao; END IF;

    RAISE NOTICE 'SEED 2230 OK — 115 traits, 38 DECK_PLAYER_*, 21 exclusivos de B cobertos.';
END $$;

-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
COMMIT;
