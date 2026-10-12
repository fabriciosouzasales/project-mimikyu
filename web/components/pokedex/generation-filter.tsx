import Link from "next/link";
import type { PokedexGeneration } from "@/lib/pokedex/queries";
import { formatCount, generationRoman } from "@/lib/pokedex/format";
import { cn } from "@/lib/utils";

/**
 * Filtro por geração da Pokédex Nacional (Pokédex P1) — links simples
 * (servidor, sem JavaScript), preservando a pesquisa atual. Em telas
 * estreitas vira uma faixa com rolagem horizontal em vez de quebrar em
 * várias linhas.
 */
export function GenerationFilter({
  generations,
  activeGeneration,
  query,
  totalSpecies,
}: {
  generations: PokedexGeneration[];
  activeGeneration: number | null;
  query: string | null;
  totalSpecies: number;
}) {
  function hrefFor(generation: number | null) {
    const params = new URLSearchParams();
    if (query) params.set("q", query);
    if (generation) params.set("geracao", String(generation));
    const search = params.toString();
    return search ? `/pokedex?${search}` : "/pokedex";
  }

  return (
    <nav aria-label="Filtrar por geração" className="-mx-1 overflow-x-auto px-1 pb-1">
      <ul className="flex w-max gap-2">
        <li>
          <Chip href={hrefFor(null)} active={activeGeneration === null} title="Todas" detail={formatCount(totalSpecies)} />
        </li>
        {generations.map((generation) => (
          <li key={generation.generation_code}>
            <Chip
              href={hrefFor(generation.generation_ordinal)}
              active={activeGeneration === generation.generation_ordinal}
              eyebrow={generationRoman(generation.generation_code)}
              title={generation.region_name ?? `Geração ${generationRoman(generation.generation_code)}`}
              detail={formatCount(generation.species_count)}
              label={`Geração ${generationRoman(generation.generation_code)}${
                generation.region_name ? `, ${generation.region_name}` : ""
              }, ${formatCount(generation.species_count)} espécies`}
            />
          </li>
        ))}
      </ul>
    </nav>
  );
}

function Chip({
  href,
  active,
  eyebrow,
  title,
  detail,
  label,
}: {
  href: string;
  active: boolean;
  eyebrow?: string;
  title: string;
  detail: string;
  label?: string;
}) {
  return (
    <Link
      href={href}
      scroll={false}
      aria-current={active ? "page" : undefined}
      aria-label={label}
      className={cn(
        "flex h-9 items-center gap-2 whitespace-nowrap rounded-full border px-3.5 text-[13px] transition-colors",
        "focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-primary/20",
        active
          ? "border-primary/60 bg-primary/10 font-semibold text-foreground"
          : "border-border bg-surface text-foreground/80 hover:border-foreground/20 hover:text-foreground",
      )}
    >
      {eyebrow ? (
        <span className={cn("font-heading text-[11px] font-semibold tracking-wide", active ? "text-primary-ink" : "text-muted-foreground")}>
          {eyebrow}
        </span>
      ) : null}
      <span>{title}</span>
      <span className="tabular-nums text-xs text-muted-foreground">{detail}</span>
    </Link>
  );
}
