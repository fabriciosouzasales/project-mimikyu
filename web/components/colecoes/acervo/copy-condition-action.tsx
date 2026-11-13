"use client";

import { useId, useRef, useState } from "react";
import { Loader2 } from "lucide-react";
import { setMyCopiesCondition } from "@/app/colecoes/acervo/actions";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { formatCount, pluralize } from "@/lib/colecoes/acervo";
import { type CardConditionCode, cardConditionLabel, cardConditionOptions, isCardConditionCode } from "@/lib/colecoes/card-condition";
import { CONDITION_BATCH_MAX, type CopyConditionFailure, type CopyConditionResult, idsToChange } from "@/lib/colecoes/copy-condition";
import { useDetailSheetLock } from "./acervo-detail-sheet";
import local from "./copy-storage.module.css";

const ARIA_DISABLED_BUTTON = "aria-disabled:pointer-events-none aria-disabled:opacity-50";

/**
 * V1-16 FRONTEND-02 — ação "Condição" do rodapé de "Seus exemplares".
 *
 * Usa a MESMA seleção da lista (um ou vários exemplares). Escolher a condição
 * e aplicar é um passo só (sem confirmação, ao contrário do local — NS-13): a
 * troca é reversível pelo mesmo fluxo. Envia só os marcados que ainda não
 * estão na condição escolhida; se todos já estão, não chama o banco. O
 * resultado vem de `changed_count` (nunca presumido igual ao pedido).
 *
 * O estado provisório (o selo já mostra a condição nova durante o envio) mora
 * na lista: `onStart` o aplica, `onFailure` o desfaz, `onSuccess` o mantém até
 * a leitura nova do servidor chegar. A mensagem de erro é exibida pela lista
 * (sobrevive à seleção esvaziada em "exemplar indisponível"). Não depende do
 * contexto de local.
 */
export function CopyConditionAction({
  selected,
  conditionOf,
  onStart,
  onSuccess,
  onFailure,
  onBusyChange,
}: {
  selected: readonly string[];
  /** Condição exibida de um exemplar (já com o provisório aplicado). */
  conditionOf: (physicalCardId: string) => CardConditionCode | null;
  onStart: (ids: string[], code: CardConditionCode) => void;
  /** `selected` = quantos estavam marcados quando o envio começou (para a mensagem). */
  onSuccess: (result: CopyConditionResult & { selected: number }, code: CardConditionCode) => void;
  onFailure: (reason: CopyConditionFailure) => void;
  /** Envio em andamento: a lista bloqueia a seleção (caixas, "Marcar todos", troca de ação, lixeira). */
  onBusyChange: (busy: boolean) => void;
}) {
  const setSheetLocked = useDetailSheetLock();
  const selectId = useId();
  const [choice, setChoice] = useState<CardConditionCode | "">("");
  const [pending, setPending] = useState(false);
  const inFlight = useRef(false);

  const target = choice === "" ? null : choice;
  const toChange = target === null ? [] : idsToChange(selected, conditionOf, target);
  const tooMany = selected.length > CONDITION_BATCH_MAX;
  const canApply = !pending && target !== null && selected.length > 0 && !tooMany && toChange.length > 0;
  const targetShort = target ? (cardConditionLabel(target)?.short ?? target) : "";

  const apply = async () => {
    if (inFlight.current || !canApply || target === null) return;
    inFlight.current = true;
    setPending(true);
    setSheetLocked(true);
    onBusyChange(true);
    const ids = toChange;
    const selectedAtStart = selected.length;
    onStart(ids, target);
    try {
      const result = await setMyCopiesCondition({ physicalCardIds: ids, conditionCode: target }).catch(
        () => ({ ok: false, reason: "unavailable" }) as const,
      );
      if (!result.ok) {
        onFailure(result.reason);
        return;
      }
      setChoice("");
      onSuccess({ selected: selectedAtStart, requested: result.requested, changed: result.changed }, target);
    } finally {
      inFlight.current = false;
      setPending(false);
      setSheetLocked(false);
      onBusyChange(false);
    }
  };

  return (
    <>
      <div className={local.barRow}>
        <div>
          <label htmlFor={selectId} className="sr-only">
            Condição declarada
          </label>
          <Select
            id={selectId}
            value={choice}
            className="h-11"
            aria-disabled={pending || selected.length === 0 || undefined}
            onChange={(event) => {
              if (pending) return;
              const value = event.target.value;
              setChoice(isCardConditionCode(value) ? value : "");
            }}
          >
            <option value="" disabled>
              Condição…
            </option>
            {cardConditionOptions().map((option) => (
              <option key={option.code} value={option.code}>
                {option.label}
              </option>
            ))}
          </Select>
        </div>
        <Button className={`min-h-11 px-5 ${ARIA_DISABLED_BUTTON}`} aria-disabled={!canApply || undefined} onClick={() => void apply()}>
          {pending ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
          {pending ? "Aplicando…" : target ? `Aplicar ${targetShort}` : "Aplicar"}
        </Button>
      </div>
      {tooMany ? (
        <p className={local.barNote}>Escolha até {formatCount(CONDITION_BATCH_MAX)} exemplares por vez.</p>
      ) : target !== null && selected.length > 0 && toChange.length === 0 ? (
        <p className={local.barNote}>
          {selected.length === 1 ? "Este exemplar já está" : "Todos os marcados já estão"} em {targetShort}.
        </p>
      ) : target !== null && toChange.length < selected.length ? (
        <p className={local.barNote}>
          {pluralize(selected.length - toChange.length, "exemplar já está", "exemplares já estão")} em {targetShort} e{" "}
          {selected.length - toChange.length === 1 ? "fica" : "ficam"} como {selected.length - toChange.length === 1 ? "está" : "estão"}.
        </p>
      ) : null}
      <p className={local.barNote}>É a condição que você declara para o exemplar. O preço exibido continua sendo a referência NM.</p>
    </>
  );
}
