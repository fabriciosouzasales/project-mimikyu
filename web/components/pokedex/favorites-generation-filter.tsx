import Link from "next/link";
import { Check, X } from "lucide-react";
import { TypeFilterDisclosure, TypeLinkPending } from "@/components/pokedex/type-filter-disclosure";
import { formatCount } from "@/lib/pokedex/format";
import styles from "./favorites-generation-filter.module.css";
import typeStyles from "./type-filter.module.css";

export type FavoritesGenerationOption = {
  ordinal: number;
  /** "Geração I" */
  label: string;
  regionName: string | null;
  /** Favoritos nessa geração com a pesquisa e os tipos atuais. */
  count: number;
  selected: boolean;
  /** `null` = indisponível (nenhum favorito nessa geração com os filtros atuais). */
  href: string | null;
};

/**
 * Filtro compacto de geração da página Pokémons Favoritos (Pokédex P6, Correção de
 * UX-01, 2026-10-15) — Server Component.
 *
 * Substitui, só nesta página, a régua de nove gerações: botão "Geração" recolhido por
 * padrão (mesmo disclosure e mesma linguagem do filtro por tipo da P5a), a geração
 * ativa como chip removível e, no painel, "Todas as gerações" + cada geração com a
 * contagem de favoritos que o resultado teria. Gerações sem favoritos (com a pesquisa e
 * os tipos atuais) ficam indisponíveis — o filtro nunca leva a uma grade vazia. Todos os
 * links preservam pesquisa e tipos, são URLs compartilháveis e não rolam a página.
 */
export function FavoritesGenerationFilter({
  options,
  allHref,
  allCount,
}: {
  options: FavoritesGenerationOption[];
  /** Link para "Todas as gerações" (remove `?geracao=`). */
  allHref: string;
  allCount: number;
}) {
  const active = options.find((option) => option.selected) ?? null;
  const activeLabel = active ? `${active.label}${active.regionName ? `, ${active.regionName}` : ""}` : null;

  const chips = active ? (
    <ul className={typeStyles.chips} aria-label="Geração selecionada">
      <li>
        <Link href={allHref} scroll={false} className={styles.activeChip} aria-label={`Remover o filtro ${activeLabel}`}>
          <span className={styles.activeRoman}>{active.label}</span>
          {active.regionName ? <span className={styles.activeRegion}>{active.regionName}</span> : null}
          <X className={styles.activeRemove} aria-hidden="true" />
          <TypeLinkPending />
        </Link>
      </li>
    </ul>
  ) : null;

  return (
    <TypeFilterDisclosure variant="generation" inline activeLabel={activeLabel} activeCount={active ? 1 : 0} chips={chips}>
      <ul className={styles.options} aria-label="Gerações">
        <li>
          <GenerationOption
            label="Todas as gerações"
            regionName={null}
            count={allCount}
            selected={active === null}
            href={allHref}
          />
        </li>
        {options.map((option) => (
          <li key={option.ordinal}>
            <GenerationOption
              label={option.label}
              regionName={option.regionName}
              count={option.count}
              selected={option.selected}
              href={option.href}
            />
          </li>
        ))}
      </ul>
    </TypeFilterDisclosure>
  );
}

function GenerationOption({
  label,
  regionName,
  count,
  selected,
  href,
}: {
  label: string;
  regionName: string | null;
  count: number;
  selected: boolean;
  href: string | null;
}) {
  const content = (
    <>
      <span className={styles.optionText}>
        <span className={styles.optionLabel}>{label}</span>
        {regionName ? <span className={styles.optionRegion}>{regionName}</span> : null}
      </span>
      {selected ? (
        <Check className={styles.optionCheck} aria-hidden="true" />
      ) : (
        <span className={styles.optionCount} aria-hidden="true">
          {formatCount(count)}
        </span>
      )}
    </>
  );
  const name = `${label}${regionName ? `, ${regionName}` : ""}`;
  const favorites = `${formatCount(count)} ${count === 1 ? "favorito" : "favoritos"}`;

  if (href) {
    return (
      <Link
        href={href}
        scroll={false}
        className={styles.option}
        data-selected={selected ? "" : undefined}
        aria-current={selected ? "true" : undefined}
        aria-label={selected ? `${name}, selecionada` : `${name}, ${favorites}`}
      >
        {content}
        <TypeLinkPending />
      </Link>
    );
  }

  return (
    <span className={styles.option} data-disabled="" aria-disabled="true" role="link" aria-label={`${name}, indisponível: nenhum favorito`}>
      {content}
    </span>
  );
}
