/**
 * Apresentação da Pokédex (Pokédex P1, 2026-10-12).
 *
 * D5 — pt-BR prioritário, nomes oficiais preservados: o nome da espécie vem
 * do banco exatamente como é (oficial, igual em pt-BR). Rótulos de geração
 * são derivados dos CÓDIGOS estáveis (`GENERATION_IV`), nunca do
 * `canonical_name` em inglês ("Generation IV") — um idioma novo é só mais
 * uma entrada em `GENERATION_LABEL`, sem tocar no banco nem nos componentes.
 * Nomes de região (Kanto, Johto...) são nomes próprios oficiais e passam
 * sem tradução.
 */

const GENERATION_LABEL: Record<string, string> = {
  "pt-BR": "Geração",
};

/** "GENERATION_IV" -> "IV". Códigos fora do padrão voltam inteiros, sem quebrar a tela. */
export function generationRoman(code: string): string {
  return code.startsWith("GENERATION_") ? code.slice("GENERATION_".length) : code;
}

export function generationLabel(code: string, locale: keyof typeof GENERATION_LABEL = "pt-BR"): string {
  return `${GENERATION_LABEL[locale]} ${generationRoman(code)}`;
}

/** Número nacional no formato de Pokédex: 25 -> "0025" (4 dígitos cobrem até 9999). */
export function formatDexNumber(value: number): string {
  return String(value).padStart(4, "0");
}

export function formatCount(value: number): string {
  return new Intl.NumberFormat("pt-BR").format(value);
}

/**
 * Normaliza `?geracao=` da URL: só ordinais inteiros 1..99 são aceitos; o
 * resto vira "todas" — nunca um erro para o usuário por causa de um link
 * editado à mão.
 */
export function parseGenerationParam(value: string | string[] | undefined): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d{1,2}$/.test(raw)) return null;
  const parsed = Number(raw);
  return parsed >= 1 ? parsed : null;
}

export function parseQueryParam(value: string | string[] | undefined, maxLength: number): string | null {
  const raw = Array.isArray(value) ? value[0] : value;
  const trimmed = raw?.trim().slice(0, maxLength) ?? "";
  return trimmed === "" ? null : trimmed;
}

// ---------------------------------------------------------------------------
// Página de detalhes (Pokédex P3b, 2026-10-12)
// ---------------------------------------------------------------------------

/**
 * Contexto da Pokédex Nacional (pesquisa, geração e — P5a — tipos) levado da galeria à
 * ficha e de volta. `types` já vem canônico (lib/pokedex/type-filter.ts); ausente ou
 * vazio = sem filtro por tipo.
 */
export type PokedexContext = {
  query: string | null;
  generation: number | null;
  types?: readonly string[];
  /**
   * Pokédex P6 (2026-10-15): origem da galeria. `"favoritos"` = a página Pokémon
   * Favoritos (`/pokedex/favoritos`); ausente/`null` = Pokédex Nacional. Decide só a
   * rota base dos links da galeria e o "voltar" da ficha — pesquisa, geração e tipos
   * seguem iguais nas duas.
   */
  origin?: PokedexOrigin | null;
};

/** Origens possíveis da galeria além da Pokédex Nacional (P6). */
export type PokedexOrigin = "favoritos";

/** Rota da página Pokémon Favoritos (P6). */
export const POKEDEX_FAVORITES_PATH = "/pokedex/favoritos";

/** `?origem=` da ficha: só `favoritos` é aceito; qualquer outra coisa = Pokédex Nacional. */
export function parseOriginParam(value: string | string[] | undefined): PokedexOrigin | null {
  const raw = Array.isArray(value) ? value[0] : value;
  return raw === "favoritos" ? "favoritos" : null;
}

/** Rota base da galeria de origem. */
export function galleryBasePath(context: Pick<PokedexContext, "origin">): string {
  return context.origin === "favoritos" ? POKEDEX_FAVORITES_PATH : "/pokedex";
}

/**
 * Query string do contexto — fonte única dos links da Pokédex (régua, barra compacta,
 * pesquisa, filtro por tipo, cards, ficha). Ordem estável: `q`, `geracao`, `tipo`.
 */
export function pokedexContextSearch(context: PokedexContext): string {
  const params = new URLSearchParams();
  if (context.query) params.set("q", context.query);
  if (context.generation !== null) params.set("geracao", String(context.generation));
  if (context.types && context.types.length > 0) params.set("tipo", context.types.join(","));
  // Vírgula legível na URL compartilhada (`tipo=FIRE,FLYING`); é válida em query string.
  const search = params.toString().replace(/%2C/g, ",");
  return search ? `?${search}` : "";
}

/**
 * Rota da galeria para um contexto (sem âncora): Pokédex Nacional ou, com
 * `origin: "favoritos"` (P6), a página Pokémon Favoritos — régua, barra, pesquisa e
 * filtro por tipo ficam dentro da página de origem.
 */
export function pokedexHref(context: PokedexContext): string {
  return `${galleryBasePath(context)}${pokedexContextSearch(context)}`;
}

/**
 * Rota da ficha preservando o contexto da galeria. A origem Favoritos (P6) viaja como
 * `?origem=favoritos`, depois de `q`/`geracao`/`tipo`, para que o "voltar" e os
 * vizinhos continuem dentro dela.
 */
export function speciesDetailHref(nationalDexNumber: number, context: PokedexContext): string {
  const search = pokedexContextSearch(context);
  const origin = context.origin === "favoritos" ? `${search ? "&" : "?"}origem=favoritos` : "";
  return `/pokedex/${nationalDexNumber}${search}${origin}`;
}

/** Âncora do card na galeria — o "voltar" da ficha rola até a espécie de origem. */
export function speciesAnchorId(nationalDexNumber: number): string {
  return `especie-${formatDexNumber(nationalDexNumber)}`;
}

/** "Voltar" da ficha: a galeria de origem (Nacional ou Favoritos), com a âncora da espécie. */
export function nationalPokedexHref(context: PokedexContext, fromNumber?: number): string {
  const hash = fromNumber ? `#${speciesAnchorId(fromNumber)}` : "";
  return `${galleryBasePath(context)}${pokedexContextSearch(context)}${hash}`;
}

/** Segmento da rota `/pokedex/[numero]`: só inteiros 1..9999 (zeros à esquerda aceitos e normalizados). */
export function parseNationalNumberParam(value: string): number | null {
  if (!/^\d{1,5}$/.test(value)) return null;
  const parsed = Number(value);
  return parsed >= 1 && parsed <= 9999 ? parsed : null;
}

const measureFormat = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

/** 0.7 -> "0,7" (altura em m, peso em kg — sempre uma casa, como a Pokédex oficial). */
export function formatMeasure(value: number): string {
  return measureFormat.format(value);
}

const LANGUAGE_NAME: Record<string, string> = { en: "inglês", "pt-BR": "português" };

export function languageName(code: string | null | undefined): string {
  return (code && LANGUAGE_NAME[code]) || code || "";
}

/**
 * Nome legível da versão de jogo de origem da descrição. As versões presentes
 * na carga P3a estão mapeadas; qualquer outra vira "Pokémon <Título>".
 */
const SOURCE_VERSION_LABEL: Record<string, string> = {
  shield: "Pokémon Shield",
  sword: "Pokémon Sword",
  "legends-arceus": "Pokémon Legends: Arceus",
  violet: "Pokémon Violet",
  scarlet: "Pokémon Scarlet",
  "alpha-sapphire": "Pokémon Alpha Sapphire",
  "omega-ruby": "Pokémon Omega Ruby",
  "ultra-moon": "Pokémon Ultra Moon",
  "ultra-sun": "Pokémon Ultra Sun",
  "lets-go-eevee": "Pokémon Let's Go, Eevee!",
  "lets-go-pikachu": "Pokémon Let's Go, Pikachu!",
};

export function sourceVersionLabel(code: string | null | undefined): string | null {
  if (!code) return null;
  if (SOURCE_VERSION_LABEL[code]) return SOURCE_VERSION_LABEL[code];
  const title = code
    .split("-")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
  return title ? `Pokémon ${title}` : null;
}
