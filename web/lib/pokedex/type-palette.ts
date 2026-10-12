import type { CSSProperties } from "react";
import {
  Brain,
  Bug,
  CircleDot,
  Crown,
  Droplets,
  Feather,
  Flame,
  FlaskConical,
  Gem,
  Ghost,
  Leaf,
  Moon,
  Mountain,
  Shield,
  Snowflake,
  Sparkles,
  Swords,
  Zap,
  type LucideIcon,
} from "lucide-react";

/**
 * Paleta própria dos 18 tipos Pokémon (Pokédex P3b, 2026-10-12 — aprovada por
 * Fabrício). Uma cor-base por tipo (triplet RGB, usada em luzes, anéis e
 * fundos translúcidos) e uma cor de texto ("ink") por tema, escolhida para
 * contraste AA sobre o fundo do chip em cada tema. A paleta é do MMKYU —
 * inspirada nas convenções conhecidas dos tipos, não copiada de um jogo.
 *
 * O dourado da marca não aparece aqui: tipos nunca competem com o accent.
 *
 * Uso: `pokemonTypeStyle("GRASS", "t1")` devolve as variáveis CSS
 * (`--pk-t1-l`, `--pk-t1-d`, `--pk-t1-ink-l`, `--pk-t1-ink-d`) que os módulos
 * CSS da Pokédex resolvem por tema. Um único layout, 18 atmosferas.
 */

export type PokemonTypeCode =
  | "NORMAL"
  | "FIGHTING"
  | "FLYING"
  | "POISON"
  | "GROUND"
  | "ROCK"
  | "BUG"
  | "GHOST"
  | "STEEL"
  | "FIRE"
  | "WATER"
  | "GRASS"
  | "ELECTRIC"
  | "PSYCHIC"
  | "ICE"
  | "DRAGON"
  | "DARK"
  | "FAIRY";

type TypeTone = {
  /** Cor-base no tema claro (RGB "r g b"). */
  light: string;
  /** Cor-base no tema escuro — mais luminosa nos tipos naturalmente escuros (Sombrio, Fantasma, Dragão). */
  dark: string;
  /** Texto sobre o chip no tema claro. */
  inkLight: string;
  /** Texto sobre o chip no tema escuro. */
  inkDark: string;
  icon: LucideIcon;
};

export const POKEMON_TYPE_PALETTE: Record<PokemonTypeCode, TypeTone> = {
  NORMAL: { light: "150 142 122", dark: "176 168 148", inkLight: "#55503f", inkDark: "#dcd5c4", icon: CircleDot },
  FIGHTING: { light: "200 70 58", dark: "222 96 82", inkLight: "#962c20", inkDark: "#f4a99d", icon: Swords },
  FLYING: { light: "112 142 222", dark: "136 164 238", inkLight: "#36529f", inkDark: "#bfd0f8", icon: Feather },
  POISON: { light: "150 90 200", dark: "176 116 222", inkLight: "#6c2f99", inkDark: "#d8b1f2", icon: FlaskConical },
  GROUND: { light: "196 146 70", dark: "214 168 94", inkLight: "#74500f", inkDark: "#efcf96", icon: Mountain },
  ROCK: { light: "170 146 84", dark: "192 170 108", inkLight: "#665522", inkDark: "#e0d09c", icon: Gem },
  BUG: { light: "136 170 34", dark: "160 194 58", inkLight: "#4b610c", inkDark: "#cde58a", icon: Bug },
  GHOST: { light: "104 84 164", dark: "140 118 214", inkLight: "#47367f", inkDark: "#cbbcf3", icon: Ghost },
  STEEL: { light: "104 144 172", dark: "134 172 198", inkLight: "#365669", inkDark: "#c3d8e6", icon: Shield },
  FIRE: { light: "232 112 40", dark: "246 136 66", inkLight: "#8a3a08", inkDark: "#ffbb8a", icon: Flame },
  WATER: { light: "58 128 228", dark: "86 154 246", inkLight: "#184d96", inkDark: "#a8cdfb", icon: Droplets },
  GRASS: { light: "47 154 93", dark: "63 184 116", inkLight: "#175c36", inkDark: "#97e3b5", icon: Leaf },
  ELECTRIC: { light: "214 168 18", dark: "238 198 46", inkLight: "#6e5300", inkDark: "#f6dc78", icon: Zap },
  PSYCHIC: { light: "226 78 128", dark: "242 104 150", inkLight: "#9e2253", inkDark: "#f9adc8", icon: Brain },
  ICE: { light: "64 176 188", dark: "104 206 216", inkLight: "#16636b", inkDark: "#ade9ef", icon: Snowflake },
  DRAGON: { light: "88 82 214", dark: "120 114 240", inkLight: "#38329f", inkDark: "#bdb9fb", icon: Crown },
  DARK: { light: "96 82 72", dark: "150 128 112", inkLight: "#463a31", inkDark: "#d6c8bc", icon: Moon },
  FAIRY: { light: "222 112 172", dark: "238 142 196", inkLight: "#97295f", inkDark: "#f8bddd", icon: Sparkles },
};

/** Tom neutro (espécie sem perfil importado): mesma estrutura, sem cor de tipo. */
export const NEUTRAL_TYPE_TONE: Omit<TypeTone, "icon"> = {
  light: "150 140 124",
  dark: "150 140 124",
  inkLight: "#55503f",
  inkDark: "#d6cfc2",
};

export function isPokemonTypeCode(value: string | null | undefined): value is PokemonTypeCode {
  return !!value && Object.prototype.hasOwnProperty.call(POKEMON_TYPE_PALETTE, value);
}

/** Variáveis CSS de um tipo para o "slot" informado (t1 = primário, t2 = secundário). */
export function pokemonTypeStyle(code: string | null | undefined, slot: "t1" | "t2"): CSSProperties {
  const tone = isPokemonTypeCode(code) ? POKEMON_TYPE_PALETTE[code] : NEUTRAL_TYPE_TONE;
  return {
    [`--pk-${slot}-l`]: tone.light,
    [`--pk-${slot}-d`]: tone.dark,
    [`--pk-${slot}-ink-l`]: tone.inkLight,
    [`--pk-${slot}-ink-d`]: tone.inkDark,
  } as CSSProperties;
}

export function pokemonTypeIcon(code: string | null | undefined): LucideIcon | null {
  return isPokemonTypeCode(code) ? POKEMON_TYPE_PALETTE[code].icon : null;
}
