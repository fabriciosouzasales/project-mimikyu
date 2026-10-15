import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { pokemonTypeIcon, pokemonTypeStyle } from "@/lib/pokedex/type-palette";
import styles from "./pokemon-type-chip.module.css";

/**
 * Chip de tipo Pokémon (Pokédex P3b, 2026-10-12) — reutilizável na ficha, na
 * galeria e no futuro filtro por tipo. Server Component, sem JavaScript.
 * O rótulo vem do banco (`pokemon_type.labels`, pt-BR com fallback en).
 * `children` (P5a): conteúdo extra depois do rótulo — contagem ou ação de remover no
 * filtro por tipo; sem ele, o chip é o mesmo de sempre.
 */
export function PokemonTypeChip({
  code,
  label,
  slot = "t1",
  className,
  children,
}: {
  code: string;
  label: string;
  slot?: "t1" | "t2";
  className?: string;
  children?: ReactNode;
}) {
  const Icon = pokemonTypeIcon(code);
  return (
    <span className={cn(styles.chip, slot === "t2" && styles.secondary, className)} style={pokemonTypeStyle(code, slot)}>
      {Icon ? <Icon className={styles.icon} strokeWidth={2.25} aria-hidden="true" /> : null}
      {label}
      {children}
    </span>
  );
}
