/*
Project Mimikyu — tabela fixa da operação SCRYDEX_ASSETS_2026_11_08_ME55_RGB.
Montada em 2026-11-08: as três cartas Mew "RGB" do ME5.5 cadastradas pela 2277 (números R, G, B), que a
TCGdex lista sem arquivo de imagem. Scrydex `me55-R`, `me55-G`, `me55-B` (página
scrydex.com/pokemon/expansions/30th-celebration/me55; imagens `large` 654 × 914 conferidas).

Linha = [número no MMKYU, nome no MMKYU, número na Scrydex, nome na Scrydex (só quando difere)].
Id da imagem = `${sx}-${número Scrydex}`. A função recusa carta cujo nome no banco difere do registrado.
*/

export type PlanRow = readonly [number: string, mmkyuName: string, scrydexNumber: string, scrydexName?: string];
export type PlanSet = { readonly sx: string; readonly rows: readonly PlanRow[] };

export const PLAN: Readonly<Record<string, PlanSet>> = {
  "ME5.5": { sx: "me55", rows: [
    ["R", "Mew", "R"],
    ["G", "Mew", "G"],
    ["B", "Mew", "B"],
  ] },
};

export const PLAN_TOTAL = Object.values(PLAN).reduce((n, s) => n + s.rows.length, 0);
