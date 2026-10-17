"use client";

import { useRouter } from "next/navigation";
import { useId, useState } from "react";
import { setCollectionCoverFinish } from "@/app/colecoes/colecoes/actions";
import { BINDER_FINISHES, type BinderFinish, finishLabel } from "@/lib/colecoes/binder-finish";
import { collectionFailureMessage, type CollectionFailure } from "@/lib/colecoes/colecoes";
import styles from "./colecoes.module.css";

/**
 * Seletor da cor do fichário (amostras de couro). Só é renderizado quando a
 * persistência existe no banco (R1 devolve `cover_finish`); antes disso a
 * página nem o monta — nenhuma ação aparece sem funcionar.
 *
 * Grupo de rádio nativo (teclado: setas), uma gravação por vez; a amostra
 * escolhida muda na hora e volta atrás se a gravação falhar.
 */
export function CoverFinishPicker({ collectionId, value }: { collectionId: string; value: BinderFinish }) {
  const router = useRouter();
  const name = useId();
  const [current, setCurrent] = useState<BinderFinish>(value);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<CollectionFailure | null>(null);

  const choose = async (finish: BinderFinish) => {
    if (pending || finish === current) return;
    const previous = current;
    setCurrent(finish);
    setPending(true);
    setError(null);
    const result = await setCollectionCoverFinish({ collectionId, finish }).catch(() => ({
      ok: false as const,
      reason: "unavailable" as const,
    }));
    setPending(false);
    if (!result.ok) {
      setCurrent(previous);
      setError(result.reason);
      return;
    }
    router.refresh();
  };

  return (
    <fieldset className={styles.finishPicker} aria-busy={pending}>
      <legend className={styles.finishLegend}>Cor do fichário</legend>
      <div className={styles.finishSwatches}>
        {BINDER_FINISHES.map((finish) => (
          <label key={finish.key} className={styles.finishSwatch} data-finish={finish.key} title={finish.label}>
            <input
              type="radio"
              name={name}
              value={finish.key}
              checked={current === finish.key}
              disabled={pending}
              onChange={() => void choose(finish.key)}
              className="sr-only"
            />
            <span className={styles.finishChip} aria-hidden="true" />
            <span className="sr-only">{finish.label}</span>
          </label>
        ))}
      </div>
      <span className={styles.finishName} aria-live="polite">
        {error ? collectionFailureMessage(error) : finishLabel(current)}
      </span>
    </fieldset>
  );
}
