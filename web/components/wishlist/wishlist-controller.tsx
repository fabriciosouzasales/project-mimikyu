"use client";

import { type MouseEvent, type ReactNode, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Bookmark } from "lucide-react";
import { readCardWishOptions, readPositionWishOptions, setVariantWished } from "@/app/colecoes/lista-de-desejos/actions";
import { Dialog, DialogBody, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import {
  type WishEntry,
  type WishFailureReason,
  type WishOutcome,
  type WishSend,
  type WishVariantOption,
  ANY_FINISH,
  cardWishMode,
  initialWishEntry,
  normalizeId,
  parseFinishKey,
  settleChooserWished,
  settleWish,
  toggleWish,
  wishAnnouncement,
  wishErrorMessage,
} from "@/lib/wishlist/wishlist";
import styles from "./wishlist.module.css";

/**
 * Alvo de um marcador de carta. `finish` (W3, Master Set) restringe a decisão às
 * variantes do acabamento da posição (`"*"` = carta secreta); `null` = carta inteira
 * (Pesquisa, Set padrão — comportamento da W1/W2, inalterado).
 */
type CardTarget = { cardId: string; finish: string | null };

function targetKey(target: CardTarget): string {
  return target.finish === null ? target.cardId : `${target.cardId}|${target.finish}`;
}

type Chooser = {
  cardId: string;
  finish: string | null;
  cardName: string;
  options: WishVariantOption[];
  /** Estado PERSISTIDO (confirmado pelo servidor) — o marcador da escolha nunca mente. */
  wished: ReadonlySet<string>;
  /** Variantes com gravação em andamento (botão desabilitado + "Salvando…"). */
  saving: ReadonlySet<string>;
  /** Falha da última gravação, exibida DENTRO do diálogo (fora dele fica inerte/oculta). */
  error: { message: string; linksToList: boolean } | null;
};

/**
 * Ilha controladora dos marcadores da Lista de desejos (V1-11 W1) — mesmo desenho do
 * `CardFavoritesController` (delegação de cliques, nenhum componente cliente por carta).
 *
 * - Marcador de VARIANTE (`data-wish-variant`): máquina de intenção da P6 por variante —
 *   tela muda na hora (otimista), uma gravação por vez, última intenção vence; falha =
 *   estado revertido + mensagem inline (STD-004). Todos os marcadores da mesma variante
 *   na grade são pintados juntos.
 * - Marcador de CARTA (`data-wish-card`, Pesquisa): lê as variantes ativas da carta
 *   (5163) e o que já está na lista. Uma variante → age direto; mais de uma → abre a
 *   escolha explícita (C-212); nenhuma → avisa, sem presumir nada.
 * - Marcador de POSIÇÃO (`data-wish-card` + `data-wish-finish`, W3 Master Set): a mesma
 *   decisão, mas só entre as variantes ativas do acabamento da posição (5348) — nunca
 *   uma variante incompatível; pintura e estado por carta + acabamento.
 * - Escolha de variante (HOMOLOGATION-04): cada opção mostra "Salvando…" e fica
 *   desabilitada enquanto grava; o marcador da opção só muda com a confirmação do
 *   servidor; falhas aparecem DENTRO do diálogo (com saída para a Lista de desejos
 *   quando aplicável); o diálogo fecha a qualquer momento e a carta passa a refletir o
 *   estado persistido — inclusive quando a gravação termina depois do fechamento.
 *
 * Nunca toca coleção, fichário ou exemplar; o desejo nasce sempre de um clique.
 */
export function WishlistController({
  children,
  onCardConfirmed,
}: {
  children: ReactNode;
  /** Avisa a grade (Pesquisa) do conjunto final de variantes desejadas da carta. */
  onCardConfirmed?: (cardId: string, variantIds: string[]) => void;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const entries = useRef(new Map<string, WishEntry>());
  const [announcement, setAnnouncement] = useState("");
  const [error, setError] = useState<string | null>(null);
  // CORRECTION-02: com desejos em mais de um idioma, a remoção é escolhida na página.
  const [errorLinksToList, setErrorLinksToList] = useState(false);
  const fail = (message: string | null, reason?: WishFailureReason) => {
    setError(message);
    setErrorLinksToList(reason === "multiple_entries");
  };
  const [chooser, setChooser] = useState<Chooser | null>(null);
  // HOMOLOGATION-04 (Defeito B): a escolha lê sempre o estado mais recente (ref), não um
  // fechamento antigo; o conjunto persistido por carta sobrevive ao fechamento do diálogo,
  // para que uma gravação que termine depois ainda atualize o marcador da carta.
  const chooserRef = useRef<Chooser | null>(null);
  const persistedByCard = useRef(new Map<string, ReadonlySet<string>>());
  const savingByCard = useRef(new Map<string, number>());
  useEffect(() => {
    chooserRef.current = chooser;
  }, [chooser]);

  function paintVariant(variantId: string, entry: WishEntry) {
    rootRef.current?.querySelectorAll<HTMLButtonElement>(`button[data-wish-variant="${variantId}"]`).forEach((button) => {
      button.setAttribute("aria-pressed", String(entry.desired));
      if (entry.inFlight) button.setAttribute("data-pending", "");
      else button.removeAttribute("data-pending");
    });
  }

  function paintCard(target: CardTarget, wished: boolean, pending: boolean) {
    const selector =
      target.finish === null
        ? `button[data-wish-card="${target.cardId}"]:not([data-wish-finish])`
        : `button[data-wish-card="${target.cardId}"][data-wish-finish="${target.finish}"]`;
    rootRef.current?.querySelectorAll<HTMLButtonElement>(selector).forEach((button) => {
      button.setAttribute("aria-pressed", String(wished));
      if (pending) button.setAttribute("data-pending", "");
      else button.removeAttribute("data-pending");
    });
  }

  async function callSet(send: WishSend): Promise<{ outcome: WishOutcome; reason: WishFailureReason }> {
    try {
      const result = await setVariantWished(send.variantId, send.value);
      if (result.ok) return { outcome: { ok: true, value: result.wished }, reason: "failed" };
      return { outcome: { ok: false }, reason: result.reason };
    } catch {
      return { outcome: { ok: false }, reason: "failed" };
    }
  }

  async function writeVariant(send: WishSend, name: string, card: CardTarget | null) {
    const { outcome, reason } = await callSet(send);
    const current = entries.current.get(send.variantId) ?? initialWishEntry(send.value);
    const step = settleWish(send.variantId, current, outcome);
    entries.current.set(send.variantId, step.entry);
    paintVariant(send.variantId, step.entry);
    if (card) paintCard(card, step.entry.desired, step.entry.inFlight);

    if (step.reverted) {
      fail(wishErrorMessage(name, reason), reason);
    } else if (step.send) {
      void writeVariant(step.send, name, card);
    } else {
      setAnnouncement(wishAnnouncement(name, step.entry.confirmed));
      if (card && card.finish === null) onCardConfirmed?.(card.cardId, step.entry.confirmed ? [send.variantId] : []);
    }
  }

  function toggleVariant(variantId: string, initiallyWished: boolean, name: string, card: CardTarget | null) {
    const current = entries.current.get(variantId) ?? initialWishEntry(initiallyWished);
    const step = toggleWish(variantId, current);
    entries.current.set(variantId, step.entry);
    paintVariant(variantId, step.entry);
    if (card) paintCard(card, step.entry.desired, step.entry.inFlight);
    fail(null);
    if (step.send) void writeVariant(step.send, name, card);
  }

  async function openCard(button: HTMLButtonElement, target: CardTarget, name: string) {
    const { cardId, finish } = target;
    const wasWished = button.getAttribute("aria-pressed") === "true";
    paintCard(target, wasWished, true);
    fail(null);
    let data: Awaited<ReturnType<typeof readCardWishOptions>> = null;
    try {
      data = finish === null ? await readCardWishOptions(cardId) : await readPositionWishOptions(cardId, finish);
    } catch {
      data = null;
    }
    paintCard(target, wasWished, false);
    if (!data) {
      fail(wishErrorMessage(name, "unavailable"));
      return;
    }
    const mode = cardWishMode(data.options);
    if (mode === "none") {
      fail(
        finish === null || finish === ANY_FINISH
          ? `${name} não tem variante disponível no catálogo para a lista de desejos.`
          : `${name} não tem variante ativa neste acabamento para a lista de desejos.`,
      );
      return;
    }
    const single = data.options[0];
    if (mode === "direct" && single) {
      toggleVariant(single.variantId, data.wished.includes(single.variantId), name, target);
      return;
    }
    const persisted = new Set(data.wished);
    persistedByCard.current.set(targetKey(target), persisted);
    const opened: Chooser = { cardId, finish, cardName: name, options: data.options, wished: persisted, saving: new Set(), error: null };
    chooserRef.current = opened;
    setChooser(opened);
  }

  function updateChooser(key: string, change: (prev: Chooser) => Chooser) {
    setChooser((prev) => {
      const next = prev && targetKey(prev) === key ? change(prev) : prev;
      chooserRef.current = next;
      return next;
    });
  }

  /** Marcador da carta + aviso à grade a partir do estado PERSISTIDO (nunca do otimista). */
  function confirmCard(target: CardTarget) {
    const key = targetKey(target);
    const persisted = persistedByCard.current.get(key) ?? new Set<string>();
    const busy = (savingByCard.current.get(key) ?? 0) > 0;
    paintCard(target, persisted.size > 0, busy);
    if (!busy && target.finish === null) onCardConfirmed?.(target.cardId, [...persisted]);
  }

  async function toggleOption(option: WishVariantOption) {
    const state = chooserRef.current;
    if (!state) return;
    const { cardName } = state;
    const target: CardTarget = { cardId: state.cardId, finish: state.finish };
    const key = targetKey(target);
    // O botão já fica desabilitado enquanto salva; este guarda só evita gravação dupla.
    if (state.saving.has(option.variantId)) return;
    const next = !state.wished.has(option.variantId);
    const label = `${cardName} · ${option.label}`;
    const withSaving = (set: ReadonlySet<string>, on: boolean) => {
      const copy = new Set(set);
      if (on) copy.add(option.variantId);
      else copy.delete(option.variantId);
      return copy;
    };

    savingByCard.current.set(key, (savingByCard.current.get(key) ?? 0) + 1);
    updateChooser(key, (prev) => ({ ...prev, saving: withSaving(prev.saving, true), error: null }));
    fail(null);

    const { outcome, reason } = await callSet({ variantId: option.variantId, value: next });

    const persisted = settleChooserWished(persistedByCard.current.get(key) ?? new Set(), option.variantId, outcome);
    persistedByCard.current.set(key, persisted);
    savingByCard.current.set(key, Math.max(0, (savingByCard.current.get(key) ?? 1) - 1));

    const message = outcome.ok ? null : wishErrorMessage(label, reason);
    const stillOpen = chooserRef.current !== null && targetKey(chooserRef.current) === key;
    if (stillOpen) {
      updateChooser(key, (prev) => ({
        ...prev,
        wished: persisted,
        saving: withSaving(prev.saving, false),
        error: message ? { message, linksToList: reason === "multiple_entries" } : null,
      }));
    } else {
      // Diálogo já fechado: a carta reflete o que o servidor confirmou; a falha vai ao aviso da grade.
      confirmCard(target);
      if (message) fail(message, reason);
    }
    if (outcome.ok) setAnnouncement(wishAnnouncement(label, outcome.value));
  }

  function closeChooser() {
    const state = chooserRef.current;
    if (!state) return;
    chooserRef.current = null;
    setChooser(null);
    confirmCard({ cardId: state.cardId, finish: state.finish });
  }

  function onClick(event: MouseEvent<HTMLDivElement>) {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>("button[data-wish-variant], button[data-wish-card]");
    if (!button || button.disabled || !rootRef.current?.contains(button)) return;
    // O marcador nunca abre a carta nem dispara a seleção do tile.
    event.preventDefault();
    event.stopPropagation();
    const name = button.dataset.wishName?.trim() || "Carta";

    const variantId = normalizeId(button.dataset.wishVariant);
    if (variantId) {
      toggleVariant(variantId, button.getAttribute("aria-pressed") === "true", name, null);
      return;
    }
    const cardId = normalizeId(button.dataset.wishCard);
    if (!cardId || button.hasAttribute("data-pending")) return;
    // W3: com `data-wish-finish`, a decisão fica restrita ao acabamento da posição;
    // valor inválido = nenhuma ação (nunca cai para "qualquer variante").
    if (button.dataset.wishFinish === undefined) {
      void openCard(button, { cardId, finish: null }, name);
      return;
    }
    const finish = parseFinishKey(button.dataset.wishFinish);
    if (finish) void openCard(button, { cardId, finish }, name);
  }

  return (
    <div ref={rootRef} onClickCapture={onClick}>
      {children}
      <p className="sr-only" aria-live="polite">
        {announcement}
      </p>
      {error ? (
        <div className="pointer-events-none sticky bottom-4 z-20 mt-6 flex justify-center" role="alert">
          <div className="pointer-events-auto max-w-md bg-surface shadow-lg">
            <InlineFeedback tone="error">
              {error}
              {errorLinksToList ? (
                <>
                  {" "}
                  <Link href="/colecoes/lista-de-desejos" className="font-medium underline underline-offset-2">
                    Abrir Lista de desejos
                  </Link>
                </>
              ) : null}
            </InlineFeedback>
          </div>
        </div>
      ) : null}

      <Dialog open={chooser !== null} onOpenChange={(open) => (open ? null : closeChooser())}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Qual variante você deseja?</DialogTitle>
            <DialogDescription>
              {chooser?.cardName} tem mais de uma variante
              {chooser && chooser.finish !== null && chooser.finish !== ANY_FINISH ? " neste acabamento" : ""}. Marque as que você quer
              na lista de desejos — vale qualquer idioma.
            </DialogDescription>
          </DialogHeader>
          <DialogBody>
            <ul className={styles.chooserList}>
              {chooser?.options.map((option) => {
                const pressed = chooser.wished.has(option.variantId);
                const saving = chooser.saving.has(option.variantId);
                return (
                  <li key={option.variantId}>
                    <button
                      type="button"
                      className={styles.chooserOption}
                      aria-pressed={pressed}
                      aria-busy={saving || undefined}
                      data-pending={saving || undefined}
                      disabled={saving}
                      onClick={() => void toggleOption(option)}
                    >
                      <span>
                        {option.label}
                        {option.isDefault ? <span className={styles.chooserDefault}>padrão</span> : null}
                        {saving ? <span className={styles.chooserDefault}>Salvando…</span> : null}
                      </span>
                      <Bookmark className={styles.chooserMark} strokeWidth={2} aria-hidden="true" />
                    </button>
                  </li>
                );
              })}
            </ul>
            {chooser?.error ? (
              <div className="mt-4" role="alert">
                <InlineFeedback tone="error">
                  {chooser.error.message}
                  {chooser.error.linksToList ? (
                    <>
                      {" "}
                      <Link href="/colecoes/lista-de-desejos" className="font-medium underline underline-offset-2">
                        Abrir Lista de desejos
                      </Link>
                    </>
                  ) : null}
                </InlineFeedback>
              </div>
            ) : null}
          </DialogBody>
        </DialogContent>
      </Dialog>
    </div>
  );
}
