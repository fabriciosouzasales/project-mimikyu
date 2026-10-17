/*
Project Mimikyu — tabela fixa da operação SCRYDEX_ASSETS_2026_10_17_MEP.
Montada em 2026-10-17 a partir da página pública da expansão na Scrydex
(scrydex.com/pokemon/expansions/mega-evolution-black-star-promos/mep), cruzada com as cartas ativas do
MEP sem CARD_FRONT em inglês no LIVE (51), por número, com conferência de nome:
- 046–063, 072–073, 081–088: cartas importadas da TCGdex na Etapa 1 (TCGdex sem imagem).
- 089–110, 120: cartas da Etapa 2 (migration 2275).
- 092 e 093: a variante padrão do catálogo é a de selo (Mundial 2025 · Equipe / Campeão); a Scrydex
  publica essas imagens como mep-92wcs (World Championships Staff Stamp) e mep-93ws (Winner Stamp).
- Nomes pt do catálogo que diferem do inglês: Exeggutor de Alola = Alolan Exeggutor,
  Resort Paraíso = Paradise Resort, Fanfarra de Celebração = Celebratory Fanfare.

Linha = [número no MMKYU, nome no MMKYU, número na Scrydex, nome na Scrydex (só quando difere)].
Id da imagem = `${sx}-${número Scrydex}`. A função recusa carta cujo nome no banco difere do registrado.
*/

export type PlanRow = readonly [number: string, mmkyuName: string, scrydexNumber: string, scrydexName?: string];
export type PlanSet = { readonly sx: string; readonly rows: readonly PlanRow[] };

export const PLAN: Readonly<Record<string, PlanSet>> = {
  "MEP": { sx: "mep", rows: [
    ["046", "Chikorita", "46"],
    ["047", "Cyndaquil", "47"],
    ["048", "Totodile", "48"],
    ["049", "Snivy", "49"],
    ["050", "Tepig", "50"],
    ["051", "Oshawott", "51"],
    ["052", "Grookey", "52"],
    ["053", "Scorbunny", "53"],
    ["054", "Sobble", "54"],
    ["055", "Treecko", "55"],
    ["056", "Torchic", "56"],
    ["057", "Mudkip", "57"],
    ["058", "Chespin", "58"],
    ["059", "Fennekin", "59"],
    ["060", "Froakie", "60"],
    ["061", "Sprigatito", "61"],
    ["062", "Fuecoco", "62"],
    ["063", "Quaxly", "63"],
    ["072", "Mega Clefable ex", "72"],
    ["073", "Mega Gengar ex", "73"],
    ["081", "Mega Greninja ex", "81"],
    ["082", "Miraidon", "82"],
    ["083", "Slowbro", "83"],
    ["084", "Dhelmise", "84"],
    ["085", "Bastiodon", "85"],
    ["086", "Slowpoke", "86"],
    ["087", "Binacle", "87"],
    ["088", "Zarude", "88"],
    ["089", "Mega Zeraora ex", "89"],
    ["090", "Mega Darkrai ex", "90"],
    ["091", "Mega Dragonite ex", "91"],
    ["092", "Resort Paraíso", "92wcs", "Paradise Resort"],
    ["093", "Pikachu", "93ws"],
    ["094", "Exeggutor de Alola", "94", "Alolan Exeggutor"],
    ["095", "Lucario", "95"],
    ["096", "Moltres", "96"],
    ["097", "Articuno", "97"],
    ["098", "Zapdos", "98"],
    ["099", "Greninja ex", "99"],
    ["100", "Sylveon ex", "100"],
    ["101", "Nidorina", "101"],
    ["102", "Victini", "102"],
    ["103", "Zeraora", "103"],
    ["104", "Mewtwo", "104"],
    ["105", "Mew", "105"],
    ["106", "Ditto", "106"],
    ["107", "Pikachu ex", "107"],
    ["108", "Espeon ex", "108"],
    ["109", "Pikachu ex", "109"],
    ["110", "Umbreon ex", "110"],
    ["120", "Fanfarra de Celebração", "120", "Celebratory Fanfare"],
  ] },
};

export const PLAN_TOTAL = Object.values(PLAN).reduce((n, s) => n + s.rows.length, 0);
