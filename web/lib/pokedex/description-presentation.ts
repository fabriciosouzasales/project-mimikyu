import { languageName, sourceVersionLabel } from "./format.ts";

/**
 * Apresentação da descrição da espécie na ficha (Pokédex P3d, 2026-10-12).
 *
 * Regra pura (sem React, sem rede), testável com `node --test`:
 *
 * - Descrição editorial MMKYU em pt-BR + descrição oficial em inglês disponível
 *   → modo bilíngue: português inicial com o rótulo editorial; inglês com a
 *   proveniência (versão do jogo de origem, quando houver).
 * - Descrição editorial sem o original (leitura `en` falhou ou não existe)
 *   → só o português editorial, com o rótulo. A ficha continua utilizável.
 * - Sem conteúdo editorial → exatamente a nota da P3b (texto oficial/estrangeiro).
 *
 * O texto oficial vem da mesma função da ficha (`get_pokedex_species_detail`)
 * chamada com `p_language = 'en'` — nenhum SQL novo.
 */

export const PAGE_LANGUAGE = "pt-BR";
export const EDITORIAL_LABEL = "Texto editorial MMKYU · Português brasileiro";

/** Campos de texto que a apresentação precisa — subconjunto de `PokedexSpeciesDetail`. */
export type SpeciesTextFields = {
  genus: string | null;
  genus_language: string | null;
  genus_is_official: boolean | null;
  description: string | null;
  description_language: string | null;
  description_is_official: boolean | null;
  description_source_version: string | null;
};

export type DescriptionVariant = {
  text: string;
  /** Idioma BCP 47 do texto — vai para o atributo `lang` do parágrafo. */
  lang: string;
  note: string | null;
};

export type DescriptionPresentation =
  | { mode: "none" }
  | { mode: "single"; variant: DescriptionVariant; editorial: boolean }
  | { mode: "bilingual"; portuguese: DescriptionVariant; english: DescriptionVariant };

export function isEditorialPortuguese(fields: Pick<SpeciesTextFields, "description" | "description_language" | "description_is_official">): boolean {
  return !!fields.description && fields.description_language === PAGE_LANGUAGE && fields.description_is_official === false;
}

/** A leitura `en` só é útil quando a ficha veio com descrição editorial em pt-BR. */
export function needsOriginalText(fields: SpeciesTextFields): boolean {
  return isEditorialPortuguese(fields);
}

export function buildDescriptionPresentation(
  species: SpeciesTextFields,
  original: SpeciesTextFields | null,
): DescriptionPresentation {
  if (!species.description) return { mode: "none" };

  if (!isEditorialPortuguese(species)) {
    return {
      mode: "single",
      editorial: false,
      variant: {
        text: species.description,
        lang: species.description_language ?? PAGE_LANGUAGE,
        note: buildLegacySourceNote(species),
      },
    };
  }

  const portuguese: DescriptionVariant = {
    text: species.description,
    lang: PAGE_LANGUAGE,
    note: EDITORIAL_LABEL,
  };

  const english = buildOfficialEnglish(original);
  if (!english) return { mode: "single", editorial: true, variant: portuguese };
  return { mode: "bilingual", portuguese, english };
}

function buildOfficialEnglish(original: SpeciesTextFields | null): DescriptionVariant | null {
  if (!original?.description || original.description_language !== "en" || original.description_is_official === false) {
    return null;
  }
  const version = sourceVersionLabel(original.description_source_version);
  return {
    text: original.description,
    lang: "en",
    note: version ? `Descrição oficial em inglês · ${version}` : "Descrição oficial em inglês",
  };
}

/**
 * Nota de origem da P3b (sem editorial), preservada: só aparece para texto em
 * outro idioma ou para indicar a versão do jogo da descrição oficial.
 */
export function buildLegacySourceNote(species: SpeciesTextFields): string | null {
  const version = sourceVersionLabel(species.description_source_version);
  const official = species.description_is_official !== false;
  const genusForeign = !!species.genus_language && species.genus_language !== PAGE_LANGUAGE;
  const descriptionForeign = !!species.description_language && species.description_language !== PAGE_LANGUAGE;
  const from = version ? `, de ${version}` : "";

  if (!genusForeign && !descriptionForeign) {
    return version && official ? `Descrição oficial de ${version}.` : null;
  }
  const language = languageName(descriptionForeign ? species.description_language : species.genus_language);
  if (genusForeign && descriptionForeign) {
    return `Classificação e descrição ${official ? "oficiais " : ""}em ${language}${from}.`;
  }
  if (descriptionForeign) {
    return `Descrição ${official ? "oficial " : ""}em ${language}${from}.`;
  }
  return `Classificação ${species.genus_is_official !== false ? "oficial " : ""}em ${language}.`;
}
