"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, Layers, Loader2, X } from "lucide-react";
import { type LinkReview, linkOneOfEach, reviewLinkOneOfEach } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import {
  type CollectionFailure,
  type LinkChoice,
  changedChoices,
  collectionFailureMessage,
  optionKey,
} from "@/lib/colecoes/colecoes";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./colecoes.module.css";

/**
 * "Adicionar as que já tenho" — vínculo "1 de cada" (D-C, R3 + 5046).
 *
 * Revisão antes de gravar: quantas cartas entram e, só quando existe mais de
 * uma opção no acervo para a mesma carta (outra variante ou idioma), a
 * escolha de qual entra — com a sugestão marcada e visível, nunca trocada em
 * silêncio. Repetidas ficam de fora e não há "todas as repetidas".
 *
 * Adicionar a uma coleção não move carta nenhuma: elas continuam no acervo,
 * no mesmo lugar; a coleção só passa a contá-las.
 */
export function LinkCardsLauncher({
  collectionId,
  setCode,
  linkable,
  layout = "bar",
}: {
  collectionId: string;
  setCode: string;
  linkable: number;
  layout?: "bar" | "empty";
}) {
  const [open, setOpen] = useState(false);
  if (linkable <= 0) return null;
  return (
    <>
      <Button onClick={() => setOpen(true)} className={layout === "empty" ? "mt-5 min-h-11" : "min-h-11"}>
        <Layers className="h-4 w-4" aria-hidden="true" />
        Adicionar as que já tenho
        <span className="tabular-nums opacity-80">({formatCount(linkable)})</span>
      </Button>
      {open ? <LinkPanel collectionId={collectionId} setCode={setCode} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

type Review = { status: "loading" } | { status: "error"; reason: CollectionFailure } | ({ status: "ready" } & LinkReview);
type Commit =
  | { status: "idle" }
  | { status: "pending" }
  | { status: "error"; reason: CollectionFailure; linked: number }
  | { status: "done"; linked: number };

function LinkPanel({ collectionId, setCode, onClose }: { collectionId: string; setCode: string; onClose: () => void }) {
  const router = useRouter();
  const [review, setReview] = useState<Review>({ status: "loading" });
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [commit, setCommit] = useState<Commit>({ status: "idle" });
  const busy = commit.status === "pending";

  const load = useCallback(async () => {
    setReview({ status: "loading" });
    setCommit({ status: "idle" });
    const result = await reviewLinkOneOfEach({ collectionId, setCode }).catch(() => ({
      ok: false as const,
      reason: "unavailable" as const,
    }));
    if (!result.ok) {
      setReview({ status: "error", reason: result.reason });
      return;
    }
    setSelected(Object.fromEntries(result.choices.map((choice) => [choice.cardId, choice.suggestedKey])));
    setReview({ status: "ready", total: result.total, choices: result.choices });
  }, [collectionId, setCode]);

  useEffect(() => {
    void load();
  }, [load]);

  const confirm = async () => {
    if (review.status !== "ready" || busy) return;
    setCommit({ status: "pending" });
    const result = await linkOneOfEach({ collectionId, overrides: changedChoices(review.choices, selected) }).catch(() => ({
      ok: false as const,
      reason: "unavailable" as const,
      linked: 0,
    }));
    setCommit(result.ok ? { status: "done", linked: result.linked } : { status: "error", reason: result.reason, linked: result.linked });
    if (result.linked > 0) router.refresh();
  };

  const close = () => {
    if (!busy) onClose();
  };

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && close()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${addStyles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
        >
          <div className={acervoStyles.drawerHeader}>
            <DialogPrimitive.Title className={addStyles.panelTitle}>Adicionar as que já tenho</DialogPrimitive.Title>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          {commit.status === "done" ? (
            <Done linked={commit.linked} onClose={onClose} />
          ) : review.status === "loading" ? (
            <div className={addStyles.body}>
              <div className={addStyles.centerState} role="status">
                <Loader2 className={`h-5 w-5 ${addStyles.spin}`} aria-hidden="true" />
                Conferindo as cartas do seu acervo…
              </div>
            </div>
          ) : review.status === "error" ? (
            <>
              <div className={addStyles.body}>
                <Notice title="Não conseguimos preparar a revisão">{collectionFailureMessage(review.reason)}</Notice>
              </div>
              <Footer>
                <Button variant="outline" onClick={onClose}>
                  Fechar
                </Button>
                <Button onClick={() => void load()}>Tentar novamente</Button>
              </Footer>
            </>
          ) : review.total === 0 ? (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.done} role="status">
                  <h2 className={addStyles.doneTitle}>Nada para adicionar agora</h2>
                  <p className={addStyles.doneText}>
                    Todas as cartas deste Set que estão no seu acervo já estão nesta ou em outra coleção.
                  </p>
                </div>
              </div>
              <Footer>
                <Button onClick={onClose}>Fechar</Button>
              </Footer>
            </>
          ) : (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.reviewHead}>
                  <span className={addStyles.reviewCount}>{formatCount(review.total)}</span>
                  <span className={addStyles.reviewLabel}>
                    {review.total === 1 ? "carta entra" : "cartas diferentes entram"} nesta coleção — <strong>uma de cada</strong>, das
                    que estão no seu acervo e ainda não fazem parte de nenhuma coleção.
                  </span>
                </div>
                <p className={addStyles.reviewNote}>
                  Elas continuam no seu acervo, no mesmo lugar; a coleção só passa a contá-las. Repetidas ficam de fora e
                  continuam disponíveis no acervo.
                </p>

                {review.choices.length > 0 ? (
                  <section aria-labelledby="colecoes-escolhas">
                    <h3 id="colecoes-escolhas" className={addStyles.sectionTitle}>
                      {review.choices.length === 1
                        ? "1 carta tem mais de uma versão no seu acervo"
                        : `${formatCount(review.choices.length)} cartas têm mais de uma versão no seu acervo`}
                    </h3>
                    <p className={styles.fieldHint}>Confira qual versão entra. A sugestão já vem marcada.</p>
                    <div className={`${styles.choiceList} mt-3`}>
                      {review.choices.map((choice) => (
                        <ChoiceGroup
                          key={choice.cardId}
                          choice={choice}
                          value={selected[choice.cardId] ?? choice.suggestedKey}
                          disabled={busy}
                          onChange={(key) => setSelected((current) => ({ ...current, [choice.cardId]: key }))}
                        />
                      ))}
                    </div>
                  </section>
                ) : null}

                {commit.status === "error" ? (
                  <Notice title={commit.linked > 0 ? "Parte das cartas entrou" : "Nenhuma carta foi adicionada"}>
                    {commit.linked > 0
                      ? `${formatCount(commit.linked)} ${commit.linked === 1 ? "carta entrou" : "cartas entraram"} na coleção. ${collectionFailureMessage(commit.reason)}`
                      : collectionFailureMessage(commit.reason)}
                  </Notice>
                ) : null}
              </div>
              <Footer lead={`${formatCount(review.total)} ${review.total === 1 ? "carta" : "cartas"}`}>
                <Button variant="outline" onClick={close} disabled={busy}>
                  Cancelar
                </Button>
                {commit.status === "error" ? (
                  <Button onClick={() => void load()} disabled={busy}>
                    Revisar de novo
                  </Button>
                ) : (
                  <Button onClick={() => void confirm()} disabled={busy} aria-busy={busy}>
                    {busy ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                    {busy ? "Adicionando…" : `Adicionar ${formatCount(review.total)} à coleção`}
                  </Button>
                )}
              </Footer>
            </>
          )}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function ChoiceGroup({
  choice,
  value,
  disabled,
  onChange,
}: {
  choice: LinkChoice;
  value: string;
  disabled: boolean;
  onChange: (key: string) => void;
}) {
  return (
    <fieldset className={styles.choice}>
      <legend className="sr-only">
        {choice.cardName}, número {choice.collectorNumber}
      </legend>
      <div className={styles.choiceHead} aria-hidden="true">
        <span className={styles.choiceName}>{choice.cardName}</span>
        <span className={styles.choiceNumber}>{formatCollectorNumber(choice.collectorNumber, null)}</span>
      </div>
      <div className={styles.choiceOptions}>
        {choice.options.map((option) => {
          const key = optionKey(option);
          return (
            <label key={key} className={addStyles.setOption} data-checked={key === value || undefined}>
              <input
                type="radio"
                name={`colecoes-choice-${choice.cardId}`}
                value={key}
                checked={key === value}
                disabled={disabled}
                onChange={() => onChange(key)}
                className={addStyles.setRadio}
              />
              <span className={addStyles.setName}>
                {option.isDefaultVariant ? "Versão padrão" : option.variantLabel ?? "Outra versão"} · {option.languageName}
              </span>
              <span className={addStyles.setCode}>
                {option.copies === 1 ? "1 no acervo" : `${formatCount(option.copies)} no acervo`}
              </span>
              {key === choice.suggestedKey ? <span className={styles.suggested}>Sugerida</span> : null}
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}

function Done({ linked, onClose }: { linked: number; onClose: () => void }) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => headingRef.current?.focus(), []);
  return (
    <>
      <div className={addStyles.body}>
        <div className={addStyles.done} role="status">
          <span className={addStyles.doneIcon} aria-hidden="true">
            <CheckCircle2 className="h-6 w-6" />
          </span>
          <h2 ref={headingRef} tabIndex={-1} className={addStyles.doneTitle}>
            {linked === 1 ? "1 carta adicionada à coleção" : `${formatCount(linked)} cartas adicionadas à coleção`}
          </h2>
          <p className={addStyles.doneText}>
            {linked === 0
              ? "Elas já tinham entrado antes — nada mudou."
              : "O progresso já está atualizado. As cartas continuam no seu acervo, no mesmo lugar."}
          </p>
        </div>
      </div>
      <Footer>
        <Button onClick={onClose}>Ver a coleção</Button>
      </Footer>
    </>
  );
}

function Footer({ lead, children }: { lead?: string; children: ReactNode }) {
  return (
    <div className={addStyles.footer}>
      <span className={addStyles.footerLead} aria-live="polite">
        {lead ?? ""}
      </span>
      <div className={addStyles.footerActions}>{children}</div>
    </div>
  );
}

function Notice({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className={addStyles.notice} role="alert">
      <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
      <div>
        <p className={addStyles.noticeTitle}>{title}</p>
        <div className={addStyles.noticeText}>{children}</div>
      </div>
    </div>
  );
}
