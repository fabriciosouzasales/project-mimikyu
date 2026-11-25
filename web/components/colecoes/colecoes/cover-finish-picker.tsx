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
 *
 * Durante a gravação (AUDIT CORRECTION-01, A2/A3): os rádios ficam
 * `aria-disabled` (não `disabled`) — o foco do teclado permanece na amostra;
 * `choose` ignora novas escolhas — e `onBusyChange` avisa o painel de Ajustes
 * para não fechar no meio, no mesmo instante em que a gravação começa e
 * termina (inclusive em falha, via `finally`).
 */
export function CoverFinishPicker({
  collectionId,
  value,
  onBusyChange,
  save = null,
}: {
  collectionId: string;
  value: BinderFinish;
  onBusyChange?: (busy: boolean) => void;
  /**
   * V1-13 · E3-3: gravação do EDITOR (5376). Com ela, a amostra só muda depois
   * da confirmação do servidor (nada otimista) e a mensagem de falha já vem
   * pronta. Ausente = titular, como sempre.
   */
  save?: ((finish: BinderFinish) => Promise<{ ok: true } | { ok: false; message: string; reload: boolean }>) | null;
}) {
  const router = useRouter();
  const name = useId();
  const [current, setCurrent] = useState<BinderFinish>(value);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<CollectionFailure | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const choose = async (finish: BinderFinish) => {
    if (pending || finish === current) return;
    if (save) {
      setPending(true);
      onBusyChange?.(true);
      setMessage(null);
      let outcome: { ok: true } | { ok: false; message: string; reload: boolean };
      try {
        outcome = await save(finish);
      } finally {
        setPending(false);
        onBusyChange?.(false);
      }
      if (!outcome.ok) {
        setMessage(outcome.message);
        if (outcome.reload) router.refresh();
        return;
      }
      setCurrent(finish);
      router.refresh();
      return;
    }
    const previous = current;
    setCurrent(finish);
    setPending(true);
    onBusyChange?.(true);
    setError(null);
    let result: Awaited<ReturnType<typeof setCollectionCoverFinish>> | { ok: false; reason: "unavailable" };
    try {
      result = await setCollectionCoverFinish({ collectionId, finish }).catch(() => ({
        ok: false as const,
        reason: "unavailable" as const,
      }));
    } finally {
      setPending(false);
      onBusyChange?.(false);
    }
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
              aria-disabled={pending || undefined}
              onChange={() => void choose(finish.key)}
              className="sr-only"
            />
            <span className={styles.finishChip} aria-hidden="true" />
            <span className="sr-only">{finish.label}</span>
          </label>
        ))}
      </div>
      <span className={styles.finishName} aria-live="polite">
        {message ?? (error ? collectionFailureMessage(error) : finishLabel(current))}
      </span>
    </fieldset>
  );
}
