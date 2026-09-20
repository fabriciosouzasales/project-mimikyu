-- ============================================================================
-- Query 2231 — SEED dos 144 Edition Context Profiles
-- Status: PROPOSTA — PROPOSAL ONLY · Versao 3.1
-- Mandato: EDITION-CONTEXT-AXIS-EDITORIAL-VOCABULARY-FINAL-CORRECTION-01
--          + EDITION-CONTEXT-AXIS-SECURITY-SEED-HARDENING-01 (v3.1, B1)
--
-- v3.1 — B1: name passa a ser o LABEL CANONICO PT-BR
--   A v3.0 gravava a composicao INGLESA em `name` e a composicao PT-BR em
--   `description`. O frontend precisaria ler `description` como label —
--   contrato inventado, e divergente de card_printing_profile.name, que e
--   PT-BR no LIVE ('Sem Sombra · 1ª Edicao', Query 2169).
--
--   NAO foi um swap cego. Antes de escrever, as 144 composicoes foram
--   confrontadas contra a N:N declarada neste mesmo arquivo:
--     144/144  aridade declarada == numero de links
--     144/144  code == codes dos traits em ordem alfabetica unidos por '__'
--     144/144  name(EN) antigo == join ' · ' dos names EN dos traits
--     144/144  description(PT) antiga == join ' · ' dos names PT dos traits
--     144/144  labels PT-BR distintos entre si
--   Ou seja: a coluna `description` continha EXATAMENTE a composicao PT-BR
--   correta. A correcao move o que ja estava provado, nao reescreve semantica.
--
--   A composicao inglesa NAO foi descartada: vive em `description` como
--   "Termo editorial de origem (en)". Zero perda de informacao.
--
--   Maior name PT-BR: 100 chars (as 4 composicoes de aridade 3 do My First
--   Battle) contra VARCHAR(200) — 50% de folga. Medido, nao estimado.
--
--   Gate P5 novo torna a regra EXECUTAVEL: recomputa o label a partir da N:N
--   no banco e falha alto se divergir. Nenhuma futura edicao manual de `name`
--   passa silenciosamente.
--
--   code, display_order, traits_signature, composicao, arity, origem,
--   contagens (144 / 196 / 137 A / 7 B PROVEN / 12 B DEFERRED): INTOCADOS.
--
-- CORRECAO DA v2.0 — DEFEITO REAL CORRIGIDO
--   A v2.0 criou 19 profiles de aridade 1, um por trait exclusivo do legado B,
--   "para materializar o trait". Isso e INVALIDO: um profile representa a
--   COMPOSICAO EXATA de traits de uma variante, nao a existencia de um trait.
--   Afirmar aridade 1 sem prova e inventar composicao — exatamente o que o
--   cabecalho deste arquivo proibe.
--
--   Auditados os 19 contra MIGRATION-MAP-365.md:
--     7  PROVEN      — linha NOMEADA do mapa, destino de aridade 1 explicito
--     12 NOT_PROVEN  — caem em linha AGREGADA do mapa, que nao enumera
--                      composicao ("21x STANDARDS_WORLDS_* -> EVENT_WORLDS_<ano>
--                      (+ PLACEMENT_* / ROLE_STAFF)" e "Demais (24 tipos)
--                      conforme familia")
--
--   Os 12 NOT_PROVEN foram REMOVIDOS deste seed. Os traits permanecem em
--   2230 e os mappings em 2232 — o que nao esta provado e a COMPOSICAO, nao a
--   existencia do trait nem o vinculo token->trait.
--
--   FAIL-CLOSED preservado: sem profile, 2211 devolve
--   NEEDS_REVIEW_NO_EC_PROFILE (estado nao-terminal). Nenhuma row e resolvida
--   por engano. A composicao fica diferida para 2213.
--
-- COMPOSICAO
--   aridade 1 ... 89 composicoes de A  (1.005 rows)
--   aridade 2 ... 44 composicoes de A  (   72 rows)
--   aridade 3 ...  4 composicoes de A  (    8 rows)   <- aridade MAXIMA medida
--   -------------------------------------------------
--   subtotal A .. 137 composicoes  (1.085 rows)  <- cobertura integral do corpus
--   + B PROVEN .. 7
--   = 144
--
-- REGRA DE NOMENCLATURA (aridade 1, 2 e 3, deterministica):
--   code = codes dos traits em ordem ALFABETICA, unidos por '__'
--   name = names dos traits na MESMA ordem, unidos por ' · '
--   Mesma composicao -> mesmo code. Zero duplicata por construcao.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE seed_ec_profile (
    code TEXT, name TEXT, description TEXT, display_order INT, arity INT, origem TEXT
) ON COMMIT DROP;
CREATE TEMP TABLE seed_ec_profile_trait (profile_code TEXT, trait_code TEXT) ON COMMIT DROP;

INSERT INTO seed_ec_profile (code, name, description, display_order, arity, origem) VALUES
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_BULBASAUR', 'My First Battle — Borda Azul · My First Battle — Marca Poké Ball · My First Battle — Deck Bulbasaur', 'Composição de 3 traços de Contexto de Edição. Termo editorial de origem (en): "My First Battle — Blue Border · My First Battle — Poké Ball Mark · My First Battle — Bulbasaur Deck".', 10, 3, 'A'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_CHARMANDER', 'My First Battle — Borda Azul · My First Battle — Marca Poké Ball · My First Battle — Deck Charmander', 'Composição de 3 traços de Contexto de Edição. Termo editorial de origem (en): "My First Battle — Blue Border · My First Battle — Poké Ball Mark · My First Battle — Charmander Deck".', 20, 3, 'A'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_PIKACHU', 'My First Battle — Borda Azul · My First Battle — Marca Poké Ball · My First Battle — Deck Pikachu', 'Composição de 3 traços de Contexto de Edição. Termo editorial de origem (en): "My First Battle — Blue Border · My First Battle — Poké Ball Mark · My First Battle — Pikachu Deck".', 30, 3, 'A'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_SQUIRTLE', 'My First Battle — Borda Azul · My First Battle — Marca Poké Ball · My First Battle — Deck Squirtle', 'Composição de 3 traços de Contexto de Edição. Termo editorial de origem (en): "My First Battle — Blue Border · My First Battle — Poké Ball Mark · My First Battle — Squirtle Deck".', 40, 3, 'A'),
    ('ARTWORK_SET_LOGO', 'Selo com Logo da Coleção', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Set Logo Stamp".', 50, 1, 'A'),
    ('CAMPAIGN_10TH_ANNIVERSARY', '10º Aniversário', 'Contexto de Edição de traço único. Termo editorial de origem (en): "10th Anniversary".', 60, 1, 'A'),
    ('CAMPAIGN_25TH_ANNIVERSARY', 'Celebração de 25 Anos', 'Contexto de Edição de traço único. Termo editorial de origem (en): "25th Anniversary Celebration".', 70, 1, 'A'),
    ('CAMPAIGN_COUNTDOWN_CALENDAR', 'Calendário de Contagem Regressiva', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Countdown Calendar".', 80, 1, 'A'),
    ('CAMPAIGN_DESTINY_DEOXYS', 'Destino Deoxys', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Destiny Deoxys".', 90, 1, 'A'),
    ('CAMPAIGN_FIRST_MOVIE', 'Primeiro Filme', 'Contexto de Edição de traço único. Termo editorial de origem (en): "First Movie".', 100, 1, 'B'),
    ('CAMPAIGN_FIRST_MOVIE_INVERTED', 'Primeiro Filme — Invertido', 'Contexto de Edição de traço único. Termo editorial de origem (en): "First Movie — Inverted".', 110, 1, 'B'),
    ('CAMPAIGN_HORIZONS', 'Horizontes', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Horizons".', 120, 1, 'B'),
    ('CAMPAIGN_PLATINUM', 'Promoção da Série Platinum', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Platinum Series Promotion".', 130, 1, 'A'),
    ('CAMPAIGN_THANK_YOU', 'Agradecimento', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Thank You".', 140, 1, 'A'),
    ('CAMPAIGN_THANK_YOU__PROGRAM_PLAYER_REWARDS', 'Agradecimento · Programa Player Rewards', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "Thank You · Player Rewards Program".', 150, 2, 'A'),
    ('CAMPAIGN_TRICK_OR_TRADE', 'Trick or Trade', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Trick or Trade".', 160, 1, 'A'),
    ('CHANNEL_ASIA_PROMO', 'Promo Ásia', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Asia Promo".', 170, 1, 'A'),
    ('CHANNEL_EB_GAMES', 'EB Games', 'Contexto de Edição de traço único. Termo editorial de origem (en): "EB Games".', 180, 1, 'A'),
    ('CHANNEL_FRUIT_ROLLS', 'Promo Fruit Rolls', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Fruit Rolls Promo".', 190, 1, 'A'),
    ('CHANNEL_GAMESTOP', 'GameStop', 'Contexto de Edição de traço único. Termo editorial de origem (en): "GameStop".', 200, 1, 'A'),
    ('CHANNEL_INQUEST_GAMER', 'InQuest Gamer', 'Contexto de Edição de traço único. Termo editorial de origem (en): "InQuest Gamer".', 210, 1, 'A'),
    ('CHANNEL_KRAZE_CLUB', 'Kraze Club', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Kraze Club".', 220, 1, 'A'),
    ('CHANNEL_MCDONALDS', 'McDonald''s', 'Contexto de Edição de traço único. Termo editorial de origem (en): "McDonald''s".', 230, 1, 'A'),
    ('CHANNEL_MFB_DECK_BULBASAUR', 'My First Battle — Deck Bulbasaur', 'Contexto de Edição de traço único. Termo editorial de origem (en): "My First Battle — Bulbasaur Deck".', 240, 1, 'A'),
    ('CHANNEL_MFB_DECK_CHARMANDER', 'My First Battle — Deck Charmander', 'Contexto de Edição de traço único. Termo editorial de origem (en): "My First Battle — Charmander Deck".', 250, 1, 'A'),
    ('CHANNEL_MFB_DECK_PIKACHU', 'My First Battle — Deck Pikachu', 'Contexto de Edição de traço único. Termo editorial de origem (en): "My First Battle — Pikachu Deck".', 260, 1, 'A'),
    ('CHANNEL_MFB_DECK_SQUIRTLE', 'My First Battle — Deck Squirtle', 'Contexto de Edição de traço único. Termo editorial de origem (en): "My First Battle — Squirtle Deck".', 270, 1, 'A'),
    ('CHANNEL_POKEMON_CENTER', 'Pokémon Center', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Pokémon Center".', 280, 1, 'B'),
    ('CHANNEL_SCRYE', 'Revista Scrye', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Scrye Magazine".', 290, 1, 'A'),
    ('CHANNEL_WOTC_PROMO', 'Promo Wizards of the Coast', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Wizards of the Coast Promo".', 300, 1, 'A'),
    ('DECK_PLAYER_AKIRA_MIYAZAKI', 'Akira Miyazaki', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Akira Miyazaki".', 310, 1, 'A'),
    ('DECK_PLAYER_CHASE_MOLONEY', 'Chase Moloney', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Chase Moloney".', 320, 1, 'A'),
    ('DECK_PLAYER_CHRISTOPHER_KAN', 'Christopher Kan', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Christopher Kan".', 330, 1, 'A'),
    ('DECK_PLAYER_CHRIS_FULOP', 'Chris Fulop', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Chris Fulop".', 340, 1, 'A'),
    ('DECK_PLAYER_CURRAN_HILL', 'Curran Hill', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Curran Hill".', 350, 1, 'A'),
    ('DECK_PLAYER_DAVID_COHEN', 'David Cohen', 'Contexto de Edição de traço único. Termo editorial de origem (en): "David Cohen".', 360, 1, 'A'),
    ('DECK_PLAYER_DYLAN_LEFAVOUR', 'Dylan Lefavour', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Dylan Lefavour".', 370, 1, 'A'),
    ('DECK_PLAYER_GABRIEL_FERNANDEZ', 'Gabriel Fernandez', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Gabriel Fernandez".', 380, 1, 'A'),
    ('DECK_PLAYER_GUSTAVO_WADA', 'Gustavo Wada', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Gustavo Wada".', 390, 1, 'A'),
    ('DECK_PLAYER_HIROKI_YANO', 'Hiroki Yano', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Hiroki Yano".', 400, 1, 'A'),
    ('DECK_PLAYER_IGOR_COSTA', 'Igor Costa', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Igor Costa".', 410, 1, 'A'),
    ('DECK_PLAYER_JASON_KLACZYNSKI', 'Jason Klaczynski', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Jason Klaczynski".', 420, 1, 'A'),
    ('DECK_PLAYER_JASON_MARTINEZ', 'Jason Martinez', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Jason Martinez".', 430, 1, 'A'),
    ('DECK_PLAYER_JEREMY_MARON', 'Jeremy Maron', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Jeremy Maron".', 440, 1, 'A'),
    ('DECK_PLAYER_JEREMY_SCHARFF_KIM', 'Jeremy Scharff-Kim', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Jeremy Scharff-Kim".', 450, 1, 'A'),
    ('DECK_PLAYER_JESSE_PARKER', 'Jesse Parker', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Jesse Parker".', 460, 1, 'A'),
    ('DECK_PLAYER_JIMMY_BALLARD', 'Jimmy Ballard', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Jimmy Ballard".', 470, 1, 'A'),
    ('DECK_PLAYER_JUN_HASEBE', 'Jun Hasebe', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Jun Hasebe".', 480, 1, 'A'),
    ('DECK_PLAYER_KEVIN_NGUYEN', 'Kevin Nguyen', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Kevin Nguyen".', 490, 1, 'A'),
    ('DECK_PLAYER_MICHAEL_GONZALEZ', 'Michael Gonzalez', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Michael Gonzalez".', 500, 1, 'A'),
    ('DECK_PLAYER_MICHAEL_PRAMAWAT', 'Michael Pramawat', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Michael Pramawat".', 510, 1, 'A'),
    ('DECK_PLAYER_MISKA_SAARI', 'Miska Saari', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Miska Saari".', 520, 1, 'A'),
    ('DECK_PLAYER_MYCHAEL_BRYAN', 'Mychael Bryan', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Mychael Bryan".', 530, 1, 'A'),
    ('DECK_PLAYER_PAUL_ATANASSOV', 'Paul Atanassov', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Paul Atanassov".', 540, 1, 'A'),
    ('DECK_PLAYER_REED_WEICHLER', 'Reed Weichler', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Reed Weichler".', 550, 1, 'A'),
    ('DECK_PLAYER_ROSS_CAWTHORN', 'Ross Cawthorn', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Ross Cawthorn".', 560, 1, 'A'),
    ('DECK_PLAYER_SAKUYA_OTA', 'Sakuya Ota', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Sakuya Ota".', 570, 1, 'A'),
    ('DECK_PLAYER_SHAO_TONG_YEN', 'Shao Tong Yen', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Shao Tong Yen".', 580, 1, 'A'),
    ('DECK_PLAYER_SHUTO_ITAGAKI', 'Shuto Itagaki', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Shuto Itagaki".', 590, 1, 'A'),
    ('DECK_PLAYER_STEPHEN_SILVESTRO', 'Stephen Silvestro', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Stephen Silvestro".', 600, 1, 'A'),
    ('DECK_PLAYER_TAKASHI_YONEDA', 'Takashi Yoneda', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Takashi Yoneda".', 610, 1, 'A'),
    ('DECK_PLAYER_TOM_ROOS', 'Tom Roos', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Tom Roos".', 620, 1, 'A'),
    ('DECK_PLAYER_TRISTAN_ROBINSON', 'Tristan Robinson', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Tristan Robinson".', 630, 1, 'A'),
    ('DECK_PLAYER_TSUBASA_NAKAMURA', 'Tsubasa Nakamura', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Tsubasa Nakamura".', 640, 1, 'A'),
    ('DECK_PLAYER_TSUGUYOSHI_YAMATO', 'Tsuguyoshi Yamato', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Tsuguyoshi Yamato".', 650, 1, 'A'),
    ('DECK_PLAYER_YUKA_FURUSAWA', 'Yuka Furusawa', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Yuka Furusawa".', 660, 1, 'A'),
    ('DECK_PLAYER_YUTA_KOMATSUDA', 'Yuta Komatsuda', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Yuta Komatsuda".', 670, 1, 'A'),
    ('DECK_PLAYER_ZACHARY_BOKHARI', 'Zachary Bokhari', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Zachary Bokhari".', 680, 1, 'A'),
    ('EVENT_CHICAGO_2009', 'Chicago 2009', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Chicago 2009".', 690, 1, 'A'),
    ('EVENT_CITIES', 'Campeonato Municipal', 'Contexto de Edição de traço único. Termo editorial de origem (en): "City Championships".', 700, 1, 'A'),
    ('EVENT_CITIES__ROLE_STAFF', 'Campeonato Municipal · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "City Championships · Staff".', 710, 2, 'A'),
    ('EVENT_COMIC_CON', 'Comic-Con', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Comic-Con".', 720, 1, 'A'),
    ('EVENT_COMIC_CON__ROLE_STAFF', 'Comic-Con · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "Comic-Con · Staff".', 730, 2, 'A'),
    ('EVENT_DISTRIBUTOR_MEETING', 'Encontro de Distribuidores', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Distributor Meeting".', 740, 1, 'A'),
    ('EVENT_GAMES_EXPO', 'Games Expo', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Games Expo".', 750, 1, 'A'),
    ('EVENT_GEN_CON', 'Gen Con', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Gen Con".', 760, 1, 'A'),
    ('EVENT_GYM_CHALLENGE', 'Desafio de Ginásio', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Gym Challenge".', 770, 1, 'B'),
    ('EVENT_NATIONALS', 'Campeonato Nacional', 'Contexto de Edição de traço único. Termo editorial de origem (en): "National Championships".', 780, 1, 'A'),
    ('EVENT_NATIONALS__ROLE_STAFF', 'Campeonato Nacional · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "National Championships · Staff".', 790, 2, 'A'),
    ('EVENT_NINTENDO_WORLD', 'Nintendo World', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Nintendo World".', 800, 1, 'A'),
    ('EVENT_ORIGINS', 'Origins Game Fair', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Origins Game Fair".', 810, 1, 'A'),
    ('EVENT_ORIGINS_2008', 'Origins Game Fair 2008', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Origins Game Fair 2008".', 820, 1, 'A'),
    ('EVENT_ORIGINS_2008__ROLE_STAFF', 'Origins Game Fair 2008 · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "Origins Game Fair 2008 · Staff".', 830, 2, 'A'),
    ('EVENT_POKEMON_DAY', 'Dia Pokémon', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Pokémon Day".', 840, 1, 'A'),
    ('EVENT_POKEMON_ROCKS_AMERICA', 'Pokémon Rocks America', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Pokémon Rocks America".', 850, 1, 'A'),
    ('EVENT_POP_TOURNAMENT', 'Torneio POP', 'Contexto de Edição de traço único. Termo editorial de origem (en): "POP Tournament".', 860, 1, 'A'),
    ('EVENT_PRERELEASE', 'Pré-lançamento', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Prerelease".', 870, 1, 'A'),
    ('EVENT_PRERELEASE__ROLE_STAFF', 'Pré-lançamento · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "Prerelease · Staff".', 880, 2, 'A'),
    ('EVENT_REGIONALS', 'Campeonato Regional', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Regional Championships".', 890, 1, 'A'),
    ('EVENT_REGIONALS__ROLE_STAFF', 'Campeonato Regional · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "Regional Championships · Staff".', 900, 2, 'A'),
    ('EVENT_STADIUM_CHALLENGE', 'Stadium Challenge', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Stadium Challenge".', 910, 1, 'A'),
    ('EVENT_STATES', 'Campeonato Estadual', 'Contexto de Edição de traço único. Termo editorial de origem (en): "State Championships".', 920, 1, 'A'),
    ('EVENT_STATES__ROLE_STAFF', 'Campeonato Estadual · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "State Championships · Staff".', 930, 2, 'A'),
    ('EVENT_WIZARD_WORLD_CHICAGO', 'Wizard World Chicago', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Wizard World Chicago".', 940, 1, 'A'),
    ('EVENT_WIZARD_WORLD_PHILADELPHIA', 'Wizard World Philadelphia', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Wizard World Philadelphia".', 950, 1, 'A'),
    ('EVENT_WORLDS_2004', 'Campeonato Mundial 2004', 'Contexto de Edição de traço único. Termo editorial de origem (en): "World Championships 2004".', 960, 1, 'A'),
    ('EVENT_WORLDS_2004__PLACEMENT_FINALIST', 'Campeonato Mundial 2004 · Finalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2004 · Finalist".', 970, 2, 'A'),
    ('EVENT_WORLDS_2004__PLACEMENT_QUARTER_FINALIST', 'Campeonato Mundial 2004 · Quartas de Final', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2004 · Quarter-Finalist".', 980, 2, 'A'),
    ('EVENT_WORLDS_2004__PLACEMENT_SEMI_FINALIST', 'Campeonato Mundial 2004 · Semifinalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2004 · Semi-Finalist".', 990, 2, 'A'),
    ('EVENT_WORLDS_2004__PLACEMENT_TOP_16', 'Campeonato Mundial 2004 · Top 16', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2004 · Top 16".', 1000, 2, 'A'),
    ('EVENT_WORLDS_2004__PLACEMENT_TOP_32', 'Campeonato Mundial 2004 · Top 32', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2004 · Top 32".', 1010, 2, 'A'),
    ('EVENT_WORLDS_2004__ROLE_STAFF', 'Campeonato Mundial 2004 · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2004 · Staff".', 1020, 2, 'A'),
    ('EVENT_WORLDS_2005', 'Campeonato Mundial 2005', 'Contexto de Edição de traço único. Termo editorial de origem (en): "World Championships 2005".', 1030, 1, 'A'),
    ('EVENT_WORLDS_2005__PLACEMENT_FINALIST', 'Campeonato Mundial 2005 · Finalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2005 · Finalist".', 1040, 2, 'A'),
    ('EVENT_WORLDS_2005__PLACEMENT_QUARTER_FINALIST', 'Campeonato Mundial 2005 · Quartas de Final', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2005 · Quarter-Finalist".', 1050, 2, 'A'),
    ('EVENT_WORLDS_2005__PLACEMENT_SEMI_FINALIST', 'Campeonato Mundial 2005 · Semifinalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2005 · Semi-Finalist".', 1060, 2, 'A'),
    ('EVENT_WORLDS_2005__PLACEMENT_TOP_16', 'Campeonato Mundial 2005 · Top 16', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2005 · Top 16".', 1070, 2, 'A'),
    ('EVENT_WORLDS_2005__PLACEMENT_TOP_32', 'Campeonato Mundial 2005 · Top 32', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2005 · Top 32".', 1080, 2, 'A'),
    ('EVENT_WORLDS_2005__ROLE_STAFF', 'Campeonato Mundial 2005 · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2005 · Staff".', 1090, 2, 'A'),
    ('EVENT_WORLDS_2007', 'Campeonato Mundial 2007', 'Contexto de Edição de traço único. Termo editorial de origem (en): "World Championships 2007".', 1100, 1, 'A'),
    ('EVENT_WORLDS_2007__PLACEMENT_FINALIST', 'Campeonato Mundial 2007 · Finalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2007 · Finalist".', 1110, 2, 'A'),
    ('EVENT_WORLDS_2007__PLACEMENT_QUARTER_FINALIST', 'Campeonato Mundial 2007 · Quartas de Final', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2007 · Quarter-Finalist".', 1120, 2, 'A'),
    ('EVENT_WORLDS_2007__PLACEMENT_SEMI_FINALIST', 'Campeonato Mundial 2007 · Semifinalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2007 · Semi-Finalist".', 1130, 2, 'A'),
    ('EVENT_WORLDS_2007__PLACEMENT_TOP_16', 'Campeonato Mundial 2007 · Top 16', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2007 · Top 16".', 1140, 2, 'A'),
    ('EVENT_WORLDS_2007__PLACEMENT_TOP_32', 'Campeonato Mundial 2007 · Top 32', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2007 · Top 32".', 1150, 2, 'A'),
    ('EVENT_WORLDS_2007__ROLE_STAFF', 'Campeonato Mundial 2007 · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2007 · Staff".', 1160, 2, 'A'),
    ('EVENT_WORLDS_2008', 'Campeonato Mundial 2008', 'Contexto de Edição de traço único. Termo editorial de origem (en): "World Championships 2008".', 1170, 1, 'A'),
    ('EVENT_WORLDS_2008__PLACEMENT_FINALIST', 'Campeonato Mundial 2008 · Finalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2008 · Finalist".', 1180, 2, 'A'),
    ('EVENT_WORLDS_2008__PLACEMENT_QUARTER_FINALIST', 'Campeonato Mundial 2008 · Quartas de Final', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2008 · Quarter-Finalist".', 1190, 2, 'A'),
    ('EVENT_WORLDS_2008__PLACEMENT_SEMI_FINALIST', 'Campeonato Mundial 2008 · Semifinalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2008 · Semi-Finalist".', 1200, 2, 'A'),
    ('EVENT_WORLDS_2008__PLACEMENT_TOP_16', 'Campeonato Mundial 2008 · Top 16', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2008 · Top 16".', 1210, 2, 'A'),
    ('EVENT_WORLDS_2008__PLACEMENT_TOP_32', 'Campeonato Mundial 2008 · Top 32', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2008 · Top 32".', 1220, 2, 'A'),
    ('EVENT_WORLDS_2008__ROLE_STAFF', 'Campeonato Mundial 2008 · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2008 · Staff".', 1230, 2, 'A'),
    ('EVENT_WORLDS_2009', 'Campeonato Mundial 2009', 'Contexto de Edição de traço único. Termo editorial de origem (en): "World Championships 2009".', 1240, 1, 'A'),
    ('EVENT_WORLDS_2009__PLACEMENT_FINALIST', 'Campeonato Mundial 2009 · Finalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2009 · Finalist".', 1250, 2, 'A'),
    ('EVENT_WORLDS_2009__PLACEMENT_QUARTER_FINALIST', 'Campeonato Mundial 2009 · Quartas de Final', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2009 · Quarter-Finalist".', 1260, 2, 'A'),
    ('EVENT_WORLDS_2009__PLACEMENT_SEMI_FINALIST', 'Campeonato Mundial 2009 · Semifinalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2009 · Semi-Finalist".', 1270, 2, 'A'),
    ('EVENT_WORLDS_2009__PLACEMENT_TOP_16', 'Campeonato Mundial 2009 · Top 16', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2009 · Top 16".', 1280, 2, 'A'),
    ('EVENT_WORLDS_2009__PLACEMENT_TOP_32', 'Campeonato Mundial 2009 · Top 32', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2009 · Top 32".', 1290, 2, 'A'),
    ('EVENT_WORLDS_2009__ROLE_STAFF', 'Campeonato Mundial 2009 · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2009 · Staff".', 1300, 2, 'A'),
    ('EVENT_WORLDS_2010', 'Campeonato Mundial 2010', 'Contexto de Edição de traço único. Termo editorial de origem (en): "World Championships 2010".', 1310, 1, 'A'),
    ('EVENT_WORLDS_2010__PLACEMENT_FINALIST', 'Campeonato Mundial 2010 · Finalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2010 · Finalist".', 1320, 2, 'A'),
    ('EVENT_WORLDS_2010__PLACEMENT_QUARTER_FINALIST', 'Campeonato Mundial 2010 · Quartas de Final', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2010 · Quarter-Finalist".', 1330, 2, 'A'),
    ('EVENT_WORLDS_2010__PLACEMENT_SEMI_FINALIST', 'Campeonato Mundial 2010 · Semifinalista', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2010 · Semi-Finalist".', 1340, 2, 'A'),
    ('EVENT_WORLDS_2010__PLACEMENT_TOP_16', 'Campeonato Mundial 2010 · Top 16', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2010 · Top 16".', 1350, 2, 'A'),
    ('EVENT_WORLDS_2010__PLACEMENT_TOP_32', 'Campeonato Mundial 2010 · Top 32', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2010 · Top 32".', 1360, 2, 'A'),
    ('EVENT_WORLDS_2010__ROLE_STAFF', 'Campeonato Mundial 2010 · Equipe', 'Composição de 2 traços de Contexto de Edição. Termo editorial de origem (en): "World Championships 2010 · Staff".', 1370, 2, 'A'),
    ('EVENT_WORLDS_2024', 'Campeonato Mundial 2024', 'Contexto de Edição de traço único. Termo editorial de origem (en): "World Championships 2024".', 1380, 1, 'B'),
    ('PLACEMENT_WINNER', 'Campeão', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Winner".', 1390, 1, 'A'),
    ('PROGRAM_LEAGUE', 'Programa de Liga', 'Contexto de Edição de traço único. Termo editorial de origem (en): "League Program".', 1400, 1, 'B'),
    ('PROGRAM_LEAGUE_POKE_BALL', 'Liga — Nível Poké Ball', 'Contexto de Edição de traço único. Termo editorial de origem (en): "League — Poké Ball Tier".', 1410, 1, 'A'),
    ('PROGRAM_PLAYER_REWARDS', 'Programa Player Rewards', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Player Rewards Program".', 1420, 1, 'A'),
    ('PROGRAM_PROFESSOR', 'Programa Professor', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Professor Program".', 1430, 1, 'A'),
    ('ROLE_STAFF', 'Equipe', 'Contexto de Edição de traço único. Termo editorial de origem (en): "Staff".', 1440, 1, 'A');

INSERT INTO seed_ec_profile_trait (profile_code, trait_code) VALUES
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_BULBASAUR', 'ARTWORK_MFB_BLUE_BORDER'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_BULBASAUR', 'ARTWORK_MFB_POKE_BALL'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_BULBASAUR', 'CHANNEL_MFB_DECK_BULBASAUR'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_CHARMANDER', 'ARTWORK_MFB_BLUE_BORDER'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_CHARMANDER', 'ARTWORK_MFB_POKE_BALL'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_CHARMANDER', 'CHANNEL_MFB_DECK_CHARMANDER'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_PIKACHU', 'ARTWORK_MFB_BLUE_BORDER'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_PIKACHU', 'ARTWORK_MFB_POKE_BALL'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_PIKACHU', 'CHANNEL_MFB_DECK_PIKACHU'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_SQUIRTLE', 'ARTWORK_MFB_BLUE_BORDER'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_SQUIRTLE', 'ARTWORK_MFB_POKE_BALL'),
    ('ARTWORK_MFB_BLUE_BORDER__ARTWORK_MFB_POKE_BALL__CHANNEL_MFB_DECK_SQUIRTLE', 'CHANNEL_MFB_DECK_SQUIRTLE'),
    ('ARTWORK_SET_LOGO', 'ARTWORK_SET_LOGO'),
    ('CAMPAIGN_10TH_ANNIVERSARY', 'CAMPAIGN_10TH_ANNIVERSARY'),
    ('CAMPAIGN_25TH_ANNIVERSARY', 'CAMPAIGN_25TH_ANNIVERSARY'),
    ('CAMPAIGN_COUNTDOWN_CALENDAR', 'CAMPAIGN_COUNTDOWN_CALENDAR'),
    ('CAMPAIGN_DESTINY_DEOXYS', 'CAMPAIGN_DESTINY_DEOXYS'),
    ('CAMPAIGN_FIRST_MOVIE', 'CAMPAIGN_FIRST_MOVIE'),
    ('CAMPAIGN_FIRST_MOVIE_INVERTED', 'CAMPAIGN_FIRST_MOVIE_INVERTED'),
    ('CAMPAIGN_HORIZONS', 'CAMPAIGN_HORIZONS'),
    ('CAMPAIGN_PLATINUM', 'CAMPAIGN_PLATINUM'),
    ('CAMPAIGN_THANK_YOU', 'CAMPAIGN_THANK_YOU'),
    ('CAMPAIGN_THANK_YOU__PROGRAM_PLAYER_REWARDS', 'CAMPAIGN_THANK_YOU'),
    ('CAMPAIGN_THANK_YOU__PROGRAM_PLAYER_REWARDS', 'PROGRAM_PLAYER_REWARDS'),
    ('CAMPAIGN_TRICK_OR_TRADE', 'CAMPAIGN_TRICK_OR_TRADE'),
    ('CHANNEL_ASIA_PROMO', 'CHANNEL_ASIA_PROMO'),
    ('CHANNEL_EB_GAMES', 'CHANNEL_EB_GAMES'),
    ('CHANNEL_FRUIT_ROLLS', 'CHANNEL_FRUIT_ROLLS'),
    ('CHANNEL_GAMESTOP', 'CHANNEL_GAMESTOP'),
    ('CHANNEL_INQUEST_GAMER', 'CHANNEL_INQUEST_GAMER'),
    ('CHANNEL_KRAZE_CLUB', 'CHANNEL_KRAZE_CLUB'),
    ('CHANNEL_MCDONALDS', 'CHANNEL_MCDONALDS'),
    ('CHANNEL_MFB_DECK_BULBASAUR', 'CHANNEL_MFB_DECK_BULBASAUR'),
    ('CHANNEL_MFB_DECK_CHARMANDER', 'CHANNEL_MFB_DECK_CHARMANDER'),
    ('CHANNEL_MFB_DECK_PIKACHU', 'CHANNEL_MFB_DECK_PIKACHU'),
    ('CHANNEL_MFB_DECK_SQUIRTLE', 'CHANNEL_MFB_DECK_SQUIRTLE'),
    ('CHANNEL_POKEMON_CENTER', 'CHANNEL_POKEMON_CENTER'),
    ('CHANNEL_SCRYE', 'CHANNEL_SCRYE'),
    ('CHANNEL_WOTC_PROMO', 'CHANNEL_WOTC_PROMO'),
    ('DECK_PLAYER_AKIRA_MIYAZAKI', 'DECK_PLAYER_AKIRA_MIYAZAKI'),
    ('DECK_PLAYER_CHASE_MOLONEY', 'DECK_PLAYER_CHASE_MOLONEY'),
    ('DECK_PLAYER_CHRISTOPHER_KAN', 'DECK_PLAYER_CHRISTOPHER_KAN'),
    ('DECK_PLAYER_CHRIS_FULOP', 'DECK_PLAYER_CHRIS_FULOP'),
    ('DECK_PLAYER_CURRAN_HILL', 'DECK_PLAYER_CURRAN_HILL'),
    ('DECK_PLAYER_DAVID_COHEN', 'DECK_PLAYER_DAVID_COHEN'),
    ('DECK_PLAYER_DYLAN_LEFAVOUR', 'DECK_PLAYER_DYLAN_LEFAVOUR'),
    ('DECK_PLAYER_GABRIEL_FERNANDEZ', 'DECK_PLAYER_GABRIEL_FERNANDEZ'),
    ('DECK_PLAYER_GUSTAVO_WADA', 'DECK_PLAYER_GUSTAVO_WADA'),
    ('DECK_PLAYER_HIROKI_YANO', 'DECK_PLAYER_HIROKI_YANO'),
    ('DECK_PLAYER_IGOR_COSTA', 'DECK_PLAYER_IGOR_COSTA'),
    ('DECK_PLAYER_JASON_KLACZYNSKI', 'DECK_PLAYER_JASON_KLACZYNSKI'),
    ('DECK_PLAYER_JASON_MARTINEZ', 'DECK_PLAYER_JASON_MARTINEZ'),
    ('DECK_PLAYER_JEREMY_MARON', 'DECK_PLAYER_JEREMY_MARON'),
    ('DECK_PLAYER_JEREMY_SCHARFF_KIM', 'DECK_PLAYER_JEREMY_SCHARFF_KIM'),
    ('DECK_PLAYER_JESSE_PARKER', 'DECK_PLAYER_JESSE_PARKER'),
    ('DECK_PLAYER_JIMMY_BALLARD', 'DECK_PLAYER_JIMMY_BALLARD'),
    ('DECK_PLAYER_JUN_HASEBE', 'DECK_PLAYER_JUN_HASEBE'),
    ('DECK_PLAYER_KEVIN_NGUYEN', 'DECK_PLAYER_KEVIN_NGUYEN'),
    ('DECK_PLAYER_MICHAEL_GONZALEZ', 'DECK_PLAYER_MICHAEL_GONZALEZ'),
    ('DECK_PLAYER_MICHAEL_PRAMAWAT', 'DECK_PLAYER_MICHAEL_PRAMAWAT'),
    ('DECK_PLAYER_MISKA_SAARI', 'DECK_PLAYER_MISKA_SAARI'),
    ('DECK_PLAYER_MYCHAEL_BRYAN', 'DECK_PLAYER_MYCHAEL_BRYAN'),
    ('DECK_PLAYER_PAUL_ATANASSOV', 'DECK_PLAYER_PAUL_ATANASSOV'),
    ('DECK_PLAYER_REED_WEICHLER', 'DECK_PLAYER_REED_WEICHLER'),
    ('DECK_PLAYER_ROSS_CAWTHORN', 'DECK_PLAYER_ROSS_CAWTHORN'),
    ('DECK_PLAYER_SAKUYA_OTA', 'DECK_PLAYER_SAKUYA_OTA'),
    ('DECK_PLAYER_SHAO_TONG_YEN', 'DECK_PLAYER_SHAO_TONG_YEN'),
    ('DECK_PLAYER_SHUTO_ITAGAKI', 'DECK_PLAYER_SHUTO_ITAGAKI'),
    ('DECK_PLAYER_STEPHEN_SILVESTRO', 'DECK_PLAYER_STEPHEN_SILVESTRO'),
    ('DECK_PLAYER_TAKASHI_YONEDA', 'DECK_PLAYER_TAKASHI_YONEDA'),
    ('DECK_PLAYER_TOM_ROOS', 'DECK_PLAYER_TOM_ROOS'),
    ('DECK_PLAYER_TRISTAN_ROBINSON', 'DECK_PLAYER_TRISTAN_ROBINSON'),
    ('DECK_PLAYER_TSUBASA_NAKAMURA', 'DECK_PLAYER_TSUBASA_NAKAMURA'),
    ('DECK_PLAYER_TSUGUYOSHI_YAMATO', 'DECK_PLAYER_TSUGUYOSHI_YAMATO'),
    ('DECK_PLAYER_YUKA_FURUSAWA', 'DECK_PLAYER_YUKA_FURUSAWA'),
    ('DECK_PLAYER_YUTA_KOMATSUDA', 'DECK_PLAYER_YUTA_KOMATSUDA'),
    ('DECK_PLAYER_ZACHARY_BOKHARI', 'DECK_PLAYER_ZACHARY_BOKHARI'),
    ('EVENT_CHICAGO_2009', 'EVENT_CHICAGO_2009'),
    ('EVENT_CITIES', 'EVENT_CITIES'),
    ('EVENT_CITIES__ROLE_STAFF', 'EVENT_CITIES'),
    ('EVENT_CITIES__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_COMIC_CON', 'EVENT_COMIC_CON'),
    ('EVENT_COMIC_CON__ROLE_STAFF', 'EVENT_COMIC_CON'),
    ('EVENT_COMIC_CON__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_DISTRIBUTOR_MEETING', 'EVENT_DISTRIBUTOR_MEETING'),
    ('EVENT_GAMES_EXPO', 'EVENT_GAMES_EXPO'),
    ('EVENT_GEN_CON', 'EVENT_GEN_CON'),
    ('EVENT_GYM_CHALLENGE', 'EVENT_GYM_CHALLENGE'),
    ('EVENT_NATIONALS', 'EVENT_NATIONALS'),
    ('EVENT_NATIONALS__ROLE_STAFF', 'EVENT_NATIONALS'),
    ('EVENT_NATIONALS__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_NINTENDO_WORLD', 'EVENT_NINTENDO_WORLD'),
    ('EVENT_ORIGINS', 'EVENT_ORIGINS'),
    ('EVENT_ORIGINS_2008', 'EVENT_ORIGINS_2008'),
    ('EVENT_ORIGINS_2008__ROLE_STAFF', 'EVENT_ORIGINS_2008'),
    ('EVENT_ORIGINS_2008__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_POKEMON_DAY', 'EVENT_POKEMON_DAY'),
    ('EVENT_POKEMON_ROCKS_AMERICA', 'EVENT_POKEMON_ROCKS_AMERICA'),
    ('EVENT_POP_TOURNAMENT', 'EVENT_POP_TOURNAMENT'),
    ('EVENT_PRERELEASE', 'EVENT_PRERELEASE'),
    ('EVENT_PRERELEASE__ROLE_STAFF', 'EVENT_PRERELEASE'),
    ('EVENT_PRERELEASE__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_REGIONALS', 'EVENT_REGIONALS'),
    ('EVENT_REGIONALS__ROLE_STAFF', 'EVENT_REGIONALS'),
    ('EVENT_REGIONALS__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_STADIUM_CHALLENGE', 'EVENT_STADIUM_CHALLENGE'),
    ('EVENT_STATES', 'EVENT_STATES'),
    ('EVENT_STATES__ROLE_STAFF', 'EVENT_STATES'),
    ('EVENT_STATES__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WIZARD_WORLD_CHICAGO', 'EVENT_WIZARD_WORLD_CHICAGO'),
    ('EVENT_WIZARD_WORLD_PHILADELPHIA', 'EVENT_WIZARD_WORLD_PHILADELPHIA'),
    ('EVENT_WORLDS_2004', 'EVENT_WORLDS_2004'),
    ('EVENT_WORLDS_2004__PLACEMENT_FINALIST', 'EVENT_WORLDS_2004'),
    ('EVENT_WORLDS_2004__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2004__PLACEMENT_QUARTER_FINALIST', 'EVENT_WORLDS_2004'),
    ('EVENT_WORLDS_2004__PLACEMENT_QUARTER_FINALIST', 'PLACEMENT_QUARTER_FINALIST'),
    ('EVENT_WORLDS_2004__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2004'),
    ('EVENT_WORLDS_2004__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2004__PLACEMENT_TOP_16', 'EVENT_WORLDS_2004'),
    ('EVENT_WORLDS_2004__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2004__PLACEMENT_TOP_32', 'EVENT_WORLDS_2004'),
    ('EVENT_WORLDS_2004__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2004__ROLE_STAFF', 'EVENT_WORLDS_2004'),
    ('EVENT_WORLDS_2004__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2005', 'EVENT_WORLDS_2005'),
    ('EVENT_WORLDS_2005__PLACEMENT_FINALIST', 'EVENT_WORLDS_2005'),
    ('EVENT_WORLDS_2005__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2005__PLACEMENT_QUARTER_FINALIST', 'EVENT_WORLDS_2005'),
    ('EVENT_WORLDS_2005__PLACEMENT_QUARTER_FINALIST', 'PLACEMENT_QUARTER_FINALIST'),
    ('EVENT_WORLDS_2005__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2005'),
    ('EVENT_WORLDS_2005__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2005__PLACEMENT_TOP_16', 'EVENT_WORLDS_2005'),
    ('EVENT_WORLDS_2005__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2005__PLACEMENT_TOP_32', 'EVENT_WORLDS_2005'),
    ('EVENT_WORLDS_2005__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2005__ROLE_STAFF', 'EVENT_WORLDS_2005'),
    ('EVENT_WORLDS_2005__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2007', 'EVENT_WORLDS_2007'),
    ('EVENT_WORLDS_2007__PLACEMENT_FINALIST', 'EVENT_WORLDS_2007'),
    ('EVENT_WORLDS_2007__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2007__PLACEMENT_QUARTER_FINALIST', 'EVENT_WORLDS_2007'),
    ('EVENT_WORLDS_2007__PLACEMENT_QUARTER_FINALIST', 'PLACEMENT_QUARTER_FINALIST'),
    ('EVENT_WORLDS_2007__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2007'),
    ('EVENT_WORLDS_2007__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2007__PLACEMENT_TOP_16', 'EVENT_WORLDS_2007'),
    ('EVENT_WORLDS_2007__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2007__PLACEMENT_TOP_32', 'EVENT_WORLDS_2007'),
    ('EVENT_WORLDS_2007__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2007__ROLE_STAFF', 'EVENT_WORLDS_2007'),
    ('EVENT_WORLDS_2007__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2008', 'EVENT_WORLDS_2008'),
    ('EVENT_WORLDS_2008__PLACEMENT_FINALIST', 'EVENT_WORLDS_2008'),
    ('EVENT_WORLDS_2008__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2008__PLACEMENT_QUARTER_FINALIST', 'EVENT_WORLDS_2008'),
    ('EVENT_WORLDS_2008__PLACEMENT_QUARTER_FINALIST', 'PLACEMENT_QUARTER_FINALIST'),
    ('EVENT_WORLDS_2008__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2008'),
    ('EVENT_WORLDS_2008__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2008__PLACEMENT_TOP_16', 'EVENT_WORLDS_2008'),
    ('EVENT_WORLDS_2008__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2008__PLACEMENT_TOP_32', 'EVENT_WORLDS_2008'),
    ('EVENT_WORLDS_2008__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2008__ROLE_STAFF', 'EVENT_WORLDS_2008'),
    ('EVENT_WORLDS_2008__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2009', 'EVENT_WORLDS_2009'),
    ('EVENT_WORLDS_2009__PLACEMENT_FINALIST', 'EVENT_WORLDS_2009'),
    ('EVENT_WORLDS_2009__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2009__PLACEMENT_QUARTER_FINALIST', 'EVENT_WORLDS_2009'),
    ('EVENT_WORLDS_2009__PLACEMENT_QUARTER_FINALIST', 'PLACEMENT_QUARTER_FINALIST'),
    ('EVENT_WORLDS_2009__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2009'),
    ('EVENT_WORLDS_2009__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2009__PLACEMENT_TOP_16', 'EVENT_WORLDS_2009'),
    ('EVENT_WORLDS_2009__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2009__PLACEMENT_TOP_32', 'EVENT_WORLDS_2009'),
    ('EVENT_WORLDS_2009__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2009__ROLE_STAFF', 'EVENT_WORLDS_2009'),
    ('EVENT_WORLDS_2009__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2010', 'EVENT_WORLDS_2010'),
    ('EVENT_WORLDS_2010__PLACEMENT_FINALIST', 'EVENT_WORLDS_2010'),
    ('EVENT_WORLDS_2010__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2010__PLACEMENT_QUARTER_FINALIST', 'EVENT_WORLDS_2010'),
    ('EVENT_WORLDS_2010__PLACEMENT_QUARTER_FINALIST', 'PLACEMENT_QUARTER_FINALIST'),
    ('EVENT_WORLDS_2010__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2010'),
    ('EVENT_WORLDS_2010__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2010__PLACEMENT_TOP_16', 'EVENT_WORLDS_2010'),
    ('EVENT_WORLDS_2010__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2010__PLACEMENT_TOP_32', 'EVENT_WORLDS_2010'),
    ('EVENT_WORLDS_2010__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2010__ROLE_STAFF', 'EVENT_WORLDS_2010'),
    ('EVENT_WORLDS_2010__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2024', 'EVENT_WORLDS_2024'),
    ('PLACEMENT_WINNER', 'PLACEMENT_WINNER'),
    ('PROGRAM_LEAGUE', 'PROGRAM_LEAGUE'),
    ('PROGRAM_LEAGUE_POKE_BALL', 'PROGRAM_LEAGUE_POKE_BALL'),
    ('PROGRAM_PLAYER_REWARDS', 'PROGRAM_PLAYER_REWARDS'),
    ('PROGRAM_PROFESSOR', 'PROGRAM_PROFESSOR'),
    ('ROLE_STAFF', 'ROLE_STAFF');

-- ---------------------------------------------------------------- PASSO 1 ---
DO $$
DECLARE v_n INT; v_ar INT; v_dup INT; v_orf TEXT; v_bad INT; v_a INT; v_b INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM seed_ec_profile;
    IF v_n <> 144 THEN RAISE EXCEPTION 'SEED_PROFILE_COUNT: esperado 144, obtido %.', v_n; END IF;

    SELECT COUNT(*) FILTER (WHERE origem='A'), COUNT(*) FILTER (WHERE origem='B')
      INTO v_a, v_b FROM seed_ec_profile;
    IF v_a <> 137 OR v_b <> 7 THEN
        RAISE EXCEPTION 'SEED_PROFILE_ORIGIN_SPLIT: esperado 137 A / 7 B, obtido % / %.', v_a, v_b; END IF;

    -- P4 — aridade maxima 3 (medida no corpus).
    SELECT MAX(c) INTO v_ar FROM (SELECT COUNT(*) c FROM seed_ec_profile_trait GROUP BY profile_code) d;
    IF v_ar <> 3 THEN RAISE EXCEPTION 'SEED_PROFILE_ARITY: esperada 3, obtida %.', v_ar; END IF;

    SELECT COUNT(*) INTO v_bad FROM seed_ec_profile p
      JOIN (SELECT profile_code, COUNT(*) c FROM seed_ec_profile_trait GROUP BY profile_code) d
        ON d.profile_code = p.code
     WHERE d.c <> p.arity;
    IF v_bad <> 0 THEN RAISE EXCEPTION 'SEED_PROFILE_ARITY_MISMATCH: % profiles.', v_bad; END IF;

    -- B3 — nenhum profile de B fora da lista PROVEN.
    IF EXISTS (SELECT 1 FROM seed_ec_profile WHERE origem='B' AND code NOT IN (
        'EVENT_WORLDS_2024', 'PROGRAM_LEAGUE', 'CHANNEL_POKEMON_CENTER', 'CAMPAIGN_FIRST_MOVIE', 'CAMPAIGN_FIRST_MOVIE_INVERTED', 'EVENT_GYM_CHALLENGE', 'CAMPAIGN_HORIZONS')) THEN
        RAISE EXCEPTION 'SEED_PROFILE_B_UNPROVEN: profile de B sem composicao provada no MIGRATION-MAP-365.'; END IF;

    SELECT COUNT(*) INTO v_dup FROM (SELECT code FROM seed_ec_profile GROUP BY code HAVING COUNT(*)>1) d;
    IF v_dup <> 0 THEN RAISE EXCEPTION 'SEED_PROFILE_CODE_DUPLICATE: %.', v_dup; END IF;

    SELECT COUNT(*) INTO v_dup FROM (
        SELECT array_agg(trait_code ORDER BY trait_code) sig
          FROM seed_ec_profile_trait GROUP BY profile_code) x
     GROUP BY sig HAVING COUNT(*)>1;
    IF COALESCE(v_dup,0) <> 0 THEN RAISE EXCEPTION 'SEED_PROFILE_SIGNATURE_DUPLICATE.'; END IF;

    SELECT string_agg(DISTINCT pt.trait_code, ', ') INTO v_orf
      FROM seed_ec_profile_trait pt
     WHERE NOT EXISTS (SELECT 1 FROM public.card_edition_context_trait t WHERE t.code = pt.trait_code);
    IF v_orf IS NOT NULL THEN RAISE EXCEPTION 'SEED_PROFILE_TRAIT_ORPHAN: %.', v_orf; END IF;

    SELECT COUNT(*) INTO v_dup FROM (
        SELECT display_order FROM seed_ec_profile GROUP BY display_order HAVING COUNT(*)>1) d;
    IF v_dup <> 0 THEN RAISE EXCEPTION 'SEED_PROFILE_ORDER_COLLISION: %.', v_dup; END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
INSERT INTO public.card_edition_context_profile (game_id, code, name, description, display_order)
SELECT g.id, p.code, p.name, p.description, p.display_order
  FROM seed_ec_profile p CROSS JOIN LATERAL (SELECT id FROM public.game WHERE code='PTCG') g;

INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
SELECT p.id, t.id, p.game_id
  FROM seed_ec_profile_trait s
  JOIN public.card_edition_context_profile p ON p.code = s.profile_code
  JOIN public.card_edition_context_trait   t ON t.code = s.trait_code AND t.game_id = p.game_id;

-- ---------------------------------------------------------------- PASSO 3 ---
-- FORÇA O SELO DEFERIDO A DISPARAR AGORA (BATCH1-RUNTIME-CORRECTION-02).
--
-- OBRIGATÓRIO, não cosmético. trg_cecp_seal (2206 v2.0) é CONSTRAINT TRIGGER
-- DEFERRABLE INITIALLY DEFERRED: por padrão ele só roda no COMMIT, DEPOIS de
-- todo este bloco. Sem esta linha, o gate SEED_SIGNATURE_UNSEALED abaixo leria
-- traits_signature ainda NULL em 144/144 e abortaria o seed SEMPRE — um falso
-- negativo garantido, não uma proteção.
--
-- SET CONSTRAINTS ALL IMMEDIATE força a execução dos triggers deferidos
-- pendentes neste ponto. Se qualquer Profile estiver vazio, o EXCEPTION
-- EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION aborta aqui — fail-loud, ainda
-- dentro da transação. Se tudo passar, os 144 já estão selados e os gates
-- abaixo medem estado REAL, não estado intermediário.
SET CONSTRAINTS ALL IMMEDIATE;

DO $$
DECLARE v_n INT; v_null INT; v_dup INT; v_sem INT; v_lbl INT; v_len INT; v_mis INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM public.card_edition_context_profile;
    IF v_n <> 144 THEN RAISE EXCEPTION 'SEED_PROFILE_POSTCHECK: esperado 144, obtido %.', v_n; END IF;

    SELECT COUNT(*) INTO v_null FROM public.card_edition_context_profile WHERE traits_signature IS NULL;
    IF v_null <> 0 THEN RAISE EXCEPTION 'SEED_SIGNATURE_UNSEALED: %.', v_null; END IF;

    -- P8 (NOVO) — o selo corresponde EXATAMENTE à N:N, para os 144.
    -- Não basta "não é NULL": prova que o array selado é idêntico ao conjunto
    -- canônico recalculado da fonte da verdade (DISTINCT pela PK, ORDER BY).
    SELECT COUNT(*) INTO v_mis
      FROM public.card_edition_context_profile p
     WHERE p.traits_signature IS DISTINCT FROM ARRAY(
             SELECT t.trait_id FROM public.card_edition_context_profile_trait t
              WHERE t.profile_id = p.id ORDER BY t.trait_id);
    IF v_mis <> 0 THEN
        RAISE EXCEPTION 'SEED_SIGNATURE_MISMATCH_NN (P8): % profiles com selo divergente da N:N.', v_mis;
    END IF;

    SELECT COUNT(*) INTO v_dup FROM (
        SELECT game_id, traits_signature FROM public.card_edition_context_profile
         GROUP BY game_id, traits_signature HAVING COUNT(*)>1) d;
    IF v_dup <> 0 THEN RAISE EXCEPTION 'SEED_SIGNATURE_DUPLICATE: %.', v_dup; END IF;

    -- PROVA NEGATIVA: os 12 traits diferidos existem e NAO tem profile proprio.
    SELECT COUNT(*) INTO v_sem FROM public.card_edition_context_trait t
     WHERE t.code IN ('CAMPAIGN_POKEMON_4EVER', 'CAMPAIGN_POKEMON_DAY_30TH', 'CAMPAIGN_POKEMON_TOGETHER', 'CHANNEL_ASIA_2023_24', 'CHANNEL_POKEMON_CENTER_NY', 'EVENT_INTERNATIONALS_EUROPE', 'EVENT_INTERNATIONALS_NORTH_AMERICA', 'EVENT_POKETOUR_99', 'EVENT_WORLDS_2023', 'EVENT_WORLDS_2025', 'PLACEMENT_TOP_8', 'PROGRAM_LEAGUE_ULTRA_BALL')
       AND EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.code = t.code);
    IF v_sem <> 0 THEN
        RAISE EXCEPTION 'SEED_DEFERRED_HAS_PROFILE: % traits diferidos ganharam profile de aridade 1.', v_sem; END IF;

    -- ------------------------------------------------------------------ P5 ---
    -- B1 — name E COMPOSICAO, NAO TEXTO LIVRE.
    -- Recomputa o label a partir da N:N ja gravada (fonte da verdade, 2205) e
    -- compara com o name persistido. Isto prova, de uma vez:
    --   (a) o label esta em PT-BR — porque herda de card_edition_context_trait.name,
    --       que a Query 2230 v2.1 fixou como label canonico PT-BR;
    --   (b) a ordem e a editorial ja definida (codes alfabeticos, o mesmo
    --       criterio que monta o code por '__');
    --   (c) nenhum profile ganhou nome digitado a mao divergente da composicao.
    -- Nao e heuristica de idioma: e igualdade exata contra a composicao real.
    SELECT COUNT(*) INTO v_lbl
      FROM public.card_edition_context_profile p
      JOIN LATERAL (
          SELECT string_agg(t.name, ' ' || chr(183) || ' ' ORDER BY t.code) AS expected
            FROM public.card_edition_context_profile_trait pt
            JOIN public.card_edition_context_trait t ON t.id = pt.trait_id
           WHERE pt.profile_id = p.id
      ) c ON TRUE
     WHERE c.expected IS DISTINCT FROM p.name;
    IF v_lbl <> 0 THEN
        RAISE EXCEPTION 'SEED_PROFILE_NAME_NOT_COMPOSED (B1/P5): % profiles com name divergente da composicao de traits.', v_lbl; END IF;

    -- P6 — limite fisico de card_edition_context_profile.name (VARCHAR(200)).
    SELECT COALESCE(MAX(length(name)), 0) INTO v_len FROM public.card_edition_context_profile;
    IF v_len > 200 THEN
        RAISE EXCEPTION 'SEED_PROFILE_NAME_TOO_LONG (B1/P6): maior name tem % chars, acima do VARCHAR(200).', v_len; END IF;

    -- P7 — description e FRASE, jamais label alternativo.
    IF EXISTS (SELECT 1 FROM public.card_edition_context_profile
                WHERE description IS NULL
                   OR description = name
                   OR description NOT LIKE '%Termo editorial de origem (en):%') THEN
        RAISE EXCEPTION 'SEED_PROFILE_DESC_SHAPE (B1/P7): description ausente, igual ao label, ou sem o termo editorial de origem.'; END IF;

    RAISE NOTICE 'SEED 2231 OK — 144 profiles (137 A + 7 B PROVEN), 12 composicoes de B diferidas para 2213. Maior name PT-BR: % chars (limite 200).', v_len;
END $$;

-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
COMMIT;
