// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/normalize.ts
// Normalização pura (Seção 4 do contrato) — nenhuma função aqui faz I/O.

import type { PokeApiNameEntry } from "./types.ts";

// external_*_id = ID numérico da PokéAPI, extraído da URL do recurso (ex.:
// "https://pokeapi.co/api/v2/region/1/" -> "1"). Nunca o slug/name.
export function extractIdFromUrl(url: string): string | null {
  const match = url.match(/\/(\d+)\/?$/);
  return match ? match[1] : null;
}

// canonical_name — Seção 4.0: vem EXCLUSIVAMENTE de names[] onde
// language.name = 'en'. Vazio/ausente -> null (VALIDATION FAILURE a cargo do
// chamador — nunca fallback silencioso para o slug estruturado).
export function extractCanonicalNameEn(
  names: PokeApiNameEntry[] | undefined | null,
): string | null {
  if (!Array.isArray(names)) return null;
  const entry = names.find((n) => n?.language?.name === "en");
  const value = entry?.name?.trim();
  return value ? value : null;
}

// code de structured slug (Seção 4.1/4.4/4.2): uppercase, hífen -> underscore,
// qualquer caractere fora de [A-Z0-9_] removido. Nunca produz string vazia
// para um slug não-vazio bem formado da PokéAPI (slugs reais são
// [a-z0-9-]+). Ex.: "kanto" -> "KANTO"; "generation-i" -> "GENERATION_I".
export function codeFromSlug(slug: string): string {
  return slug
    .toUpperCase()
    .replace(/-/g, "_")
    .replace(/[^A-Z0-9_]/g, "");
}

const ROMAN_NUMERAL_VALUES: Record<string, number> = {
  I: 1,
  V: 5,
  X: 10,
  L: 50,
  C: 100,
  D: 500,
  M: 1000,
};

// Conversor genérico de algarismo romano -> inteiro (notação subtrativa
// padrão). Usado exclusivamente para derivar ordinal_number do slug da
// Generation (Seção 4.2) — NUNCA do id da PokéAPI. Retorna null para entrada
// vazia/inválida (dígito desconhecido) — nunca uma inferência silenciosa.
// Sem limite de dígitos: cobre qualquer geração futura além de IX.
export function romanNumeralToInt(roman: string): number | null {
  const upper = roman.toUpperCase();
  if (upper.length === 0 || !/^[IVXLCDM]+$/.test(upper)) return null;
  let total = 0;
  for (let i = 0; i < upper.length; i++) {
    const current = ROMAN_NUMERAL_VALUES[upper[i]];
    const next = ROMAN_NUMERAL_VALUES[upper[i + 1]];
    if (next !== undefined && current < next) {
      total -= current;
    } else {
      total += current;
    }
  }
  return total > 0 ? total : null;
}

// Extrai o algarismo romano de um slug "generation-<roman>" (ex.:
// "generation-viii" -> "VIII" -> 8). Retorna null se o slug não seguir
// exatamente esse formato — nunca uma inferência parcial.
export function extractGenerationOrdinal(slug: string): number | null {
  const match = slug.match(/^generation-([a-z]+)$/i);
  if (!match) return null;
  return romanNumeralToInt(match[1]);
}
