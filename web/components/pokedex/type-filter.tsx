import Link from "next/link";
import { Check, X } from "lucide-react";
import { PokemonTypeChip } from "@/components/pokedex/pokemon-type-chip";
import { TypeFilterDisclosure, TypeLinkPending } from "@/components/pokedex/type-filter-disclosure";
import { formatCount } from "@/lib/pokedex/format";
import { MAX_TYPE_FILTERS, joinTypeLabels } from "@/lib/pokedex/type-filter";
import styles from "./type-filter.module.css";

export type TypeFilterOption = {
  code: string;
  label: string;
  selected: boolean;
  /** Espécies do resultado se o tipo for acrescentado (`null` para os já selecionados). */
  count: number | null;
  /** Link que liga/desliga o tipo; `null` = indisponível (limite atingido ou combinação vazia). */
  href: string | null;
};

export type ActiveTypeChip = { code: string; label: string; removeHref: string };

/**
 * Filtro por tipo da Pokédex Nacional (Pokédex P5a, 2026-10-14) — Server Component.
 *
 * Botão discreto "Tipo" + chips dos tipos ativos (cada um remove o seu) + "Limpar".
 * O seletor, recolhido por padrão, mostra os 18 tipos com a contagem de espécies que
 * o resultado teria com cada um; combinações sem espécies e, no limite de dois, os
 * demais tipos ficam indisponíveis (sem link) — o seletor nunca leva a uma grade vazia.
 * Todos os links preservam pesquisa e geração e não rolam a página.
 */
export function TypeFilter({
  options,
  active,
  clearHref,
}: {
  options: TypeFilterOption[];
  active: ActiveTypeChip[];
  clearHref: string;
}) {
  const activeLabel = active.length > 0 ? joinTypeLabels(active.map((item) => item.label)) : null;
  const atLimit = active.length >= MAX_TYPE_FILTERS;
  const hintId = "pk-type-filter-hint";

  const chips =
    active.length > 0 ? (
      <ul className={styles.chips} aria-label="Tipos selecionados">
        {active.map((item) => (
          <li key={item.code}>
            <Link href={item.removeHref} scroll={false} className={styles.chipLink} aria-label={`Remover o tipo ${item.label} do filtro`}>
              <PokemonTypeChip code={item.code} label={item.label} className={styles.chip}>
                <X className={styles.chipRemove} aria-hidden="true" />
              </PokemonTypeChip>
              <TypeLinkPending />
            </Link>
          </li>
        ))}
        <li>
          <Link href={clearHref} scroll={false} className={styles.clear}>
            Limpar{active.length > 1 ? " tipos" : ""}
            <TypeLinkPending />
          </Link>
        </li>
      </ul>
    ) : null;

  return (
    <TypeFilterDisclosure activeLabel={activeLabel} activeCount={active.length} chips={chips}>
      <p id={hintId} className={styles.hint}>
        {active.length === 0
          ? "Escolha até dois tipos. Com dois, aparecem só as espécies que têm ambos."
          : atLimit
            ? "Limite de dois tipos. Remova um para escolher outro."
            : `Escolha mais um tipo para ver só as espécies ${active[0]?.label ? `de ${active[0].label} ` : ""}que também o têm.`}
      </p>
      <ul className={styles.options} aria-describedby={hintId}>
        {options.map((option) => (
          <li key={option.code}>
            <TypeOption option={option} atLimit={atLimit} />
          </li>
        ))}
      </ul>
    </TypeFilterDisclosure>
  );
}

function TypeOption({ option, atLimit }: { option: TypeFilterOption; atLimit: boolean }) {
  const trailing = option.selected ? (
    <Check className={styles.optionCheck} aria-hidden="true" />
  ) : option.count !== null && !atLimit ? (
    <span className={styles.optionCount} aria-hidden="true">
      {formatCount(option.count)}
    </span>
  ) : null;

  const chip = (
    <PokemonTypeChip code={option.code} label={option.label} className={styles.optionChip}>
      {trailing}
    </PokemonTypeChip>
  );

  if (option.href) {
    const label = option.selected
      ? `${option.label}, selecionado. Remover do filtro`
      : `${option.label}, ${formatCount(option.count ?? 0)} ${option.count === 1 ? "espécie" : "espécies"}`;
    return (
      <Link
        href={option.href}
        scroll={false}
        className={styles.option}
        data-selected={option.selected ? "" : undefined}
        aria-label={label}
      >
        {chip}
        <TypeLinkPending />
      </Link>
    );
  }

  const reason = atLimit ? "limite de dois tipos atingido" : "nenhuma espécie com essa combinação";
  return (
    <span className={styles.option} data-disabled="" aria-disabled="true" role="link" aria-label={`${option.label}, indisponível: ${reason}`}>
      {chip}
    </span>
  );
}
