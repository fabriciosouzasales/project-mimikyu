"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { Loader2, Minus, Plus } from "lucide-react";
import { addMyCopies, removeMyCopies } from "@/app/colecoes/acervo/actions";
import { Button } from "@/components/ui/button";
import { failureMessage } from "@/lib/colecoes/acervo-add";
import {
  type QuantityCopy,
  clampQuantity,
  copiesToRemove,
  quantityBounds,
  quantityChangeLabel,
} from "@/lib/colecoes/acervo-quantity";
import styles from "./acervo.module.css";

/**
 * Quantidade de exemplares no detalhe da carta (INVENTORY-COPY-QUANTITY-01).
 *
 * O colecionador diz quantos tem — "tenho 6" — e o painel mostra a diferença
 * antes de gravar: mais exemplares são registrados pelo contrato B1 (mesma
 * variante e idioma); menos remove os mais recentes que estão fora de
 * coleção (mesma regra da lixeira). Nada é gravado só por mexer no número.
 *
 * Integridade: um envio por vez; a chave de idempotência é fixa por
 * quantidade escolhida, então repetir a mesma confirmação (clique duplo,
 * rede) não registra em dobro. Remoção repetida também é segura.
 */
export function CopyQuantityControl({
  cardVariantId,
  languageId,
  copies,
  total,
}: {
  cardVariantId: string;
  /** `null` = idioma indisponível para cadastro: só é possível diminuir. */
  languageId: string | null;
  copies: QuantityCopy[];
  total: number;
}) {
  const router = useRouter();
  const inputId = useId();
  const changeId = useId();
  const bounds = quantityBounds(copies, total);
  const maxAllowed = languageId ? bounds.max : total;
  const [target, setTarget] = useState(total);
  const [draft, setDraft] = useState(String(total));
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const inFlight = useRef(false);
  const keyFor = useRef<{ target: number; key: string } | null>(null);
  const [, startNavigation] = useTransition();

  // Depois de gravar, o servidor devolve o novo total: o número volta a refleti-lo.
  useEffect(() => {
    if (inFlight.current) return;
    setTarget(total);
    setDraft(String(total));
  }, [total]);

  const delta = target - total;

  function choose(next: number) {
    const value = clampQuantity(next, { min: bounds.min, max: maxAllowed });
    setTarget(value);
    setDraft(String(value));
    setMessage(null);
  }

  function reset() {
    setTarget(total);
    setDraft(String(total));
  }

  async function save() {
    if (inFlight.current || delta === 0) return;
    inFlight.current = true;
    setPending(true);
    setMessage(null);
    try {
      if (delta > 0 && languageId) {
        if (!keyFor.current || keyFor.current.target !== target) {
          keyFor.current = { target, key: crypto.randomUUID() };
        }
        const response = await addMyCopies({
          idempotencyKey: keyFor.current.key,
          cardVariantId,
          languageId,
          quantity: delta,
        });
        if (!response.ok) {
          setMessage({ tone: "error", text: failureMessage(response.reason) });
          return;
        }
        keyFor.current = null;
        setMessage({ tone: "ok", text: `Pronto — agora você tem ${target} exemplares desta carta.` });
      } else if (delta < 0) {
        const ids = copiesToRemove(copies, -delta);
        const response = await removeMyCopies(ids);
        if (!response.ok) {
          const partial = response.removed > 0 ? ` ${response.removed} já ${response.removed === 1 ? "saiu" : "saíram"}.` : "";
          setMessage({ tone: "error", text: `${failureMessage(response.reason)}${partial}` });
          if (response.removed > 0) startNavigation(() => router.refresh());
          return;
        }
        setMessage({
          tone: "ok",
          text: `Pronto — agora você tem ${total - response.removed} ${total - response.removed === 1 ? "exemplar" : "exemplares"} desta carta.`,
        });
      }
      startNavigation(() => router.refresh());
    } catch {
      setMessage({ tone: "error", text: failureMessage("unavailable") });
    } finally {
      inFlight.current = false;
      setPending(false);
    }
  }

  return (
    <div className={styles.quantity}>
      <div className={styles.quantityRow}>
        <label htmlFor={inputId} className={styles.quantityLabel}>
          Quantos você tem?
        </label>
        <div className={styles.stepper}>
          <button
            type="button"
            className={styles.stepperButton}
            onClick={() => choose(target - 1)}
            disabled={pending || target <= bounds.min}
            aria-label="Um exemplar a menos"
          >
            <Minus className="h-4 w-4" aria-hidden="true" />
          </button>
          <input
            id={inputId}
            data-autofocus
            className={styles.stepperInput}
            inputMode="numeric"
            pattern="[0-9]*"
            value={draft}
            // readOnly (não disabled) durante o envio: o foco fica no campo e o
            // colecionador segue digitando a próxima quantidade sem pegar o mouse.
            readOnly={pending}
            aria-busy={pending}
            aria-describedby={delta !== 0 ? changeId : undefined}
            onChange={(event) => setDraft(event.target.value.replace(/\D/g, "").slice(0, 4))}
            onBlur={() => choose(Number(draft))}
            onKeyDown={(event) => {
              if (event.key === "Escape" && delta !== 0) {
                event.preventDefault();
                event.stopPropagation(); // não fecha o painel: só desfaz a mudança
                reset();
                return;
              }
              if (event.key !== "Enter") return;
              event.preventDefault();
              if (pending) return;
              const typed = clampQuantity(Number(draft), { min: bounds.min, max: maxAllowed });
              // 1º Enter mostra a diferença; 2º Enter (mesmo número) confirma.
              // Só para adicionar: remover apaga registros e pede o clique no botão.
              if (typed === target && delta > 0) void save();
              else choose(typed);
            }}
          />
          <button
            type="button"
            className={styles.stepperButton}
            onClick={() => choose(target + 1)}
            disabled={pending || target >= maxAllowed}
            aria-label="Um exemplar a mais"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
          </button>
        </div>
      </div>

      {delta !== 0 ? (
        <div className={styles.quantityChange} data-tone={delta > 0 ? "add" : "remove"}>
          <p id={changeId} className={styles.quantityChangeText}>
            {quantityChangeLabel(delta)}
            {delta < 0 ? " — use só para corrigir um cadastro." : ". Enter de novo confirma."}
          </p>
          <div className={styles.copyConfirmActions}>
            <Button variant="outline" size="sm" onClick={reset} disabled={pending}>
              Cancelar
            </Button>
            <Button
              variant={delta > 0 ? "default" : "destructive"}
              size="sm"
              className={delta < 0 ? styles.copyConfirmRemove : undefined}
              onClick={() => void save()}
              disabled={pending}
            >
              {pending ? <Loader2 className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
              {pending ? "Salvando…" : delta > 0 ? `Adicionar ${delta}` : `Remover ${-delta}`}
            </Button>
          </div>
        </div>
      ) : null}

      <p
        className={message?.tone === "error" ? styles.quantityError : styles.quantityHint}
        aria-live="polite"
      >
        {message?.text ??
          (bounds.min > 1
            ? `${bounds.min} estão em coleções — retire-os da coleção para ficar com menos.`
            : !languageId
              ? "Este idioma não aceita novos cadastros agora; dá para diminuir."
              : "Ajuste e confirme. Cada exemplar continua com seu próprio registro.")}
      </p>
    </div>
  );
}
