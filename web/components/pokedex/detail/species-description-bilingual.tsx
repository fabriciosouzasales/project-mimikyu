"use client";

import { useState } from "react";
import { PenLine } from "lucide-react";
import type { DescriptionVariant } from "@/lib/pokedex/description-presentation";
import styles from "./species-detail.module.css";

type DescriptionLanguage = "pt-BR" | "en";

const OPTIONS: { code: DescriptionLanguage; label: string }[] = [
  { code: "pt-BR", label: "Português" },
  { code: "en", label: "English" },
];

/**
 * Descrição bilíngue da ficha (Pokédex P3d, 2026-10-12): texto editorial MMKYU
 * em português (inicial) e descrição oficial em inglês com a proveniência.
 * Os dois textos chegam do servidor — a troca é só estado local, sem rede.
 * Só é usado quando existem os dois textos; caso contrário a ficha mantém a
 * descrição da P3b.
 */
export function SpeciesDescriptionBilingual({
  portuguese,
  english,
}: {
  portuguese: DescriptionVariant;
  english: DescriptionVariant;
}) {
  const [active, setActive] = useState<DescriptionLanguage>("pt-BR");
  return <SpeciesDescriptionBilingualView active={active} onSelect={setActive} portuguese={portuguese} english={english} />;
}

/** Apresentação pura (sem estado) — separada para verificação de markup. */
export function SpeciesDescriptionBilingualView({
  active,
  onSelect,
  portuguese,
  english,
}: {
  active: DescriptionLanguage;
  onSelect: (language: DescriptionLanguage) => void;
  portuguese: DescriptionVariant;
  english: DescriptionVariant;
}) {
  const variant = active === "en" ? english : portuguese;
  const editorial = active === "pt-BR";

  return (
    <div className={styles.descriptionBlock}>
      <div className={styles.langSwitch} role="group" aria-label="Idioma da descrição">
        {OPTIONS.map((option) => (
          <button
            key={option.code}
            type="button"
            lang={option.code}
            className={styles.langOption}
            aria-pressed={active === option.code}
            onClick={() => onSelect(option.code)}
          >
            {option.label}
          </button>
        ))}
      </div>

      <div aria-live="polite">
        <p className={styles.description} lang={variant.lang}>
          {variant.text}
        </p>
        <p className={styles.note}>
          {editorial ? <PenLine className={styles.noteIcon} aria-hidden="true" /> : null}
          {variant.note}
        </p>
      </div>
    </div>
  );
}
