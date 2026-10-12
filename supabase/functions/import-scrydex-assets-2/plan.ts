/*
Project Mimikyu — tabela fixa da operação SCRYDEX_ASSETS_2026_10_11.
Montada em 2026-10-11 a partir das páginas públicas de expansão da Scrydex
(scrydex.com/pokemon/expansions/<slug>/<id>, lidas por web_fetch), cruzadas com as cartas ativas
sem CARD_FRONT em inglês no LIVE, por Set + número, com conferência de nome:
- SM3.5 (78) e SM6 (6): nomes pt do catálogo conferidos contra o inglês da Scrydex
  (ex.: "Genesect Luminescente" = Shining Genesect, "Hibi" = Hau, "Lílian" = Lillie, "Chris" = Sophocles).
- SM2 143: catálogo "Pandam" = Scrydex "Hala" — confirmado pelo texto da carta na TCGdex pt
  (sm2-143: "Embaralhe a sua mão no seu baralho. Se você usou o seu ataque GX, compre 7 cartas.
  Caso contrário, compre 4 cartas."), idêntico ao efeito de Hala; 144 Hibi = Hau, 145 Lulú = Mallow.
- EXU (28): Unown A–Z = ex10-A … ex10-Z. Rodada 2 (2026-10-11, após migration 2263): "!" e "?"
  gravados no catálogo como EXCL e QUES (decisão de Fabrício, opção B) = ex10-exclamation / ex10-question.
- ECARD2 a/b (8): a Scrydex publica uma imagem por número; decisão de Fabrício (2026-10-11):
  a mesma imagem vale para as versões a e b.

Por Set: `sx` = id da expansão na Scrydex; linha = [número no MMKYU, nome no MMKYU,
número na Scrydex, nome na Scrydex (só quando difere)]. Id da imagem = `${sx}-${número Scrydex}`.
A função recusa carta cujo nome no banco difere do nome registrado aqui.
*/

export type PlanRow = readonly [number: string, mmkyuName: string, scrydexNumber: string, scrydexName?: string];
export type PlanSet = { readonly sx: string; readonly rows: readonly PlanRow[] };

export const PLAN: Readonly<Record<string, PlanSet>> = {
  "SM3.5": { sx: "sm35", rows: [
    ["01", "Bulbasaur", "1"],
    ["02", "Ivysaur", "2"],
    ["03", "Venusaur", "3"],
    ["04", "Shroomish", "4"],
    ["05", "Breloom", "5"],
    ["06", "Carnivine", "6"],
    ["07", "Shaymin", "7"],
    ["08", "Virizion", "8"],
    ["09", "Genesect Luminescente", "9", "Shining Genesect"],
    ["10", "Entei GX", "10", "Entei-GX"],
    ["11", "Torkoal", "11"],
    ["12", "Larvesta", "12"],
    ["13", "Volcarona", "13"],
    ["14", "Reshiram", "14"],
    ["15", "Litten", "15"],
    ["16", "Torracat", "16"],
    ["17", "Incineroar", "17"],
    ["18", "Totodile", "18"],
    ["19", "Croconaw", "19"],
    ["20", "Feraligatr", "20"],
    ["21", "Qwilfish", "21"],
    ["22", "Buizel", "22"],
    ["23", "Floatzel", "23"],
    ["24", "Palkia", "24"],
    ["25", "Manaphy", "25"],
    ["26", "Keldeo", "26"],
    ["27", "Volcanion Luminescente", "27", "Shining Volcanion"],
    ["28", "Pikachu", "28"],
    ["29", "Raichu GX", "29", "Raichu-GX"],
    ["30", "Voltorb", "30"],
    ["31", "Electrode", "31"],
    ["32", "Raikou", "32"],
    ["33", "Plusle", "33"],
    ["34", "Minun", "34"],
    ["35", "Zekrom", "35"],
    ["36", "Ekans", "36"],
    ["37", "Arbok", "37"],
    ["38", "Jynx", "38"],
    ["39", "Mewtwo GX", "39", "Mewtwo-GX"],
    ["40", "Mew Luminescente", "40", "Shining Mew"],
    ["41", "Latios", "41"],
    ["42", "Jirachi Luminescente", "42", "Shining Jirachi"],
    ["43", "Golett", "43"],
    ["44", "Golurk", "44"],
    ["45", "Marshadow", "45"],
    ["46", "Stunfisk", "46"],
    ["47", "Spiritomb", "47"],
    ["48", "Purrloin", "48"],
    ["49", "Liepard", "49"],
    ["50", "Scraggy", "50"],
    ["51", "Scrafty", "51"],
    ["52", "Zorua", "52"],
    ["53", "Zoroark GX", "53", "Zoroark-GX"],
    ["54", "Yveltal", "54"],
    ["55", "Hoopa", "55"],
    ["56", "Rayquaza Luminescente", "56", "Shining Rayquaza"],
    ["57", "Arceus Luminescente", "57", "Shining Arceus"],
    ["58", "Movedor de Dano", "58", "Damage Mover"],
    ["59", "Recuperação de Energia", "59", "Energy Retrieval"],
    ["60", "Grande Bola", "60", "Great Ball"],
    ["61", "Hibi", "61", "Hau"],
    ["62", "Lílian", "62", "Lillie"],
    ["63", "Criadora de Pokémon", "63", "Pokémon Breeder"],
    ["64", "Pegador de Pokémon", "64", "Pokémon Catcher"],
    ["65", "Chris", "65", "Sophocles"],
    ["66", "Super-recolhida", "66", "Super Scoop Up"],
    ["67", "Substituição", "67", "Switch"],
    ["68", "Ultra Bola", "68", "Ultra Ball"],
    ["69", "Energia Incolor Dupla", "69", "Double Colorless Energy"],
    ["70", "Energia de Dobra", "70", "Warp Energy"],
    ["71", "Entei GX", "71", "Entei-GX"],
    ["72", "Mewtwo GX", "72", "Mewtwo-GX"],
    ["73", "Criadora de Pokémon", "73", "Pokémon Breeder"],
    ["74", "Entei GX", "74", "Entei-GX"],
    ["75", "Raichu GX", "75", "Raichu-GX"],
    ["76", "Mewtwo GX", "76", "Mewtwo-GX"],
    ["77", "Zoroark GX", "77", "Zoroark-GX"],
    ["78", "Mewtwo GX", "78", "Mewtwo-GX"],
  ] },
  "SM6": { sx: "sm6", rows: [
    ["082", "Dialga GX", "82", "Dialga-GX"],
    ["090", "Xerneas GX", "90", "Xerneas-GX"],
    ["122", "Lucario GX", "122", "Lucario-GX"],
    ["126", "Xerneas GX", "126", "Xerneas-GX"],
    ["134", "Naganadel GX", "134", "Naganadel-GX"],
    ["140", "Ultra Necrozma GX", "140", "Ultra Necrozma-GX"],
  ] },
  "SM2": { sx: "sm2", rows: [
    ["143", "Pandam", "143", "Hala"],
  ] },
  "EXU": { sx: "ex10", rows: [
    ["A", "Unown", "A"],
    ["B", "Unown", "B"],
    ["C", "Unown", "C"],
    ["D", "Unown", "D"],
    ["E", "Unown", "E"],
    ["F", "Unown", "F"],
    ["G", "Unown", "G"],
    ["H", "Unown", "H"],
    ["I", "Unown", "I"],
    ["J", "Unown", "J"],
    ["K", "Unown", "K"],
    ["L", "Unown", "L"],
    ["M", "Unown", "M"],
    ["N", "Unown", "N"],
    ["O", "Unown", "O"],
    ["P", "Unown", "P"],
    ["Q", "Unown", "Q"],
    ["R", "Unown", "R"],
    ["S", "Unown", "S"],
    ["T", "Unown", "T"],
    ["U", "Unown", "U"],
    ["V", "Unown", "V"],
    ["W", "Unown", "W"],
    ["X", "Unown", "X"],
    ["Y", "Unown", "Y"],
    ["Z", "Unown", "Z"],
    ["EXCL", "Unown", "exclamation"],
    ["QUES", "Unown", "question"],
  ] },
  "ECARD2": { sx: "ecard2", rows: [
    ["50a", "Golduck", "50"],
    ["50b", "Golduck", "50"],
    ["74a", "Drowzee", "74"],
    ["74b", "Drowzee", "74"],
    ["95a", "Mr. Mime", "95"],
    ["95b", "Mr. Mime", "95"],
    ["103a", "Porygon", "103"],
    ["103b", "Porygon", "103"],
  ] },
};

export const PLAN_TOTAL = 121;
