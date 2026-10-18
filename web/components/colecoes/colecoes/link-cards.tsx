"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangle, Check, CheckCircle2, Loader2, Plus, X } from "lucide-react";
import { type LinkReview, linkOneOfEach, reviewLinkOneOfEach } from "@/app/colecoes/colecoes/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { cardFrontUrl, formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import {
  type CollectionFailure,
  type LinkChoice,
  type LinkItem,
  changedChoices,
  collectionFailureMessage,
  optionKey,
  selectedCardIds,
} from "@/lib/colecoes/colecoes";
import { CardArt } from "../acervo/card-art";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./colecoes.module.css";

/**
 * "Adicionar cartas" — vínculo "1 de cada" (D-C, R3 + 5046). Botão na barra da galeria, antes dos filtros.
 *
 * Lista as cartas do Set que faltam na coleção e estão no acervo (uma de cada)
 * e o colecionador marca quais entram — todas vêm marcadas, com "Selecionar
 * todas" / "Limpar". Quando existe mais de uma opção no acervo para a mesma
 * carta (outra variante ou idioma), a escolha de qual entra aparece na própria
 * carta, com a sugestão marcada, nunca trocada em silêncio. Repetidas ficam de
 * fora e não há "todas as repetidas" (D-C).
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
  layout?: "bar" | "hero" | "empty";
}) {
  const [open, setOpen] = useState(false);
  // Na barra da galeria o botão fica sempre visível; sem carta disponível
  // (ou coleção arquivada / leitura falhou → `linkable` 0), aparece
  // desabilitado e sem ação. No estado vazio, só aparece quando há o que adicionar.
  const empty = linkable <= 0;
  if (empty && layout === "empty") return null;
  return (
    <>
      <Button
        onClick={() => !empty && setOpen(true)}
        disabled={empty}
        title={empty ? "Nenhuma carta deste Set no seu acervo está disponível para adicionar agora" : undefined}
        size={layout === "hero" ? "sm" : "default"}
        className={layout === "empty" ? "mt-5 min-h-11" : layout === "hero" ? "h-8 gap-1.5 rounded-full px-3.5 text-[0.8125rem]" : "min-h-11"}
        aria-label={
          empty
            ? "Adicionar cartas — nenhuma carta disponível no seu acervo agora"
            : `Adicionar cartas do seu acervo a esta coleção (${formatCount(linkable)} disponíveis)`
        }
      >
        <Plus className="h-3.5 w-3.5" aria-hidden="true" />
        Adicionar cartas
        <span className="tabular-nums opacity-80">({formatCount(linkable)})</span>
      </Button>
      {open && !empty ? <LinkPanel collectionId={collectionId} setCode={setCode} onClose={() => setOpen(false)} /> : null}
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
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const [review, setReview] = useState<Review>({ status: "loading" });
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [picked, setPicked] = useState<Set<string>>(new Set());
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
    setPicked(new Set(result.items.map((item) => item.cardId)));
    setReview({ status: "ready", total: result.total, items: result.items, choices: result.choices });
  }, [collectionId, setCode]);

  useEffect(() => {
    void load();
  }, [load]);

  const chosenIds = review.status === "ready" ? selectedCardIds(review.items, picked) : [];
  const chosenCount = chosenIds.length;

  const confirm = async () => {
    if (review.status !== "ready" || busy || chosenCount === 0) return;
    setCommit({ status: "pending" });
    const chosenSet = new Set(chosenIds);
    const result = await linkOneOfEach({
      collectionId,
      cardIds: chosenIds,
      overrides: changedChoices(
        review.choices.filter((choice) => chosenSet.has(choice.cardId)),
        selected,
      ),
    }).catch(() => ({
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
          onCloseAutoFocus={restoreFocus}
        >
          <div className={acervoStyles.drawerHeader}>
            <DialogPrimitive.Title className={addStyles.panelTitle}>Adicionar cartas</DialogPrimitive.Title>
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
                    {review.total === 1 ? "carta deste Set está" : "cartas deste Set estão"} no seu acervo e ainda{" "}
                    {review.total === 1 ? "falta" : "faltam"} nesta coleção. Marque as que entram — <strong>uma de cada</strong>.
                  </span>
                </div>
                <p className={addStyles.reviewNote}>
                  Elas continuam no seu acervo, no mesmo lugar; a coleção só passa a contá-las. Repetidas ficam de fora e
                  continuam disponíveis no acervo.
                </p>

                <section aria-labelledby="colecoes-escolha">
                  <div className={styles.pickHead}>
                    <h3 id="colecoes-escolha" className={addStyles.sectionTitle}>
                      {formatCount(chosenCount)} de {formatCount(review.items.length)} marcadas
                    </h3>
                    <span className={styles.pickTools}>
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={busy || chosenCount === review.items.length}
                        onClick={() => setPicked(new Set(review.items.map((item) => item.cardId)))}
                      >
                        Selecionar todas
                      </Button>
                      <Button variant="ghost" size="sm" disabled={busy || chosenCount === 0} onClick={() => setPicked(new Set())}>
                        Limpar
                      </Button>
                    </span>
                  </div>
                  {review.total > review.items.length ? (
                    <p className={styles.fieldHint}>
                      Mostrando as primeiras {formatCount(review.items.length)}. Depois de adicionar, abra de novo para ver as demais.
                    </p>
                  ) : null}
                  <ul className={styles.pickList} aria-label="Cartas que podem entrar">
                    {review.items.map((item) => {
                      const choice = review.choices.find((candidate) => candidate.cardId === item.cardId) ?? null;
                      const isPicked = picked.has(item.cardId);
                      return (
                        <PickItem
                          key={item.cardId}
                          item={item}
                          picked={isPicked}
                          disabled={busy}
                          onToggle={() =>
                            setPicked((current) => {
                              const next = new Set(current);
                              if (next.has(item.cardId)) next.delete(item.cardId);
                              else next.add(item.cardId);
                              return next;
                            })
                          }
                        >
                          {choice && isPicked ? (
                            <ChoiceGroup
                              choice={choice}
                              value={selected[choice.cardId] ?? choice.suggestedKey}
                              disabled={busy}
                              onChange={(key) => setSelected((current) => ({ ...current, [choice.cardId]: key }))}
                            />
                          ) : null}
                        </PickItem>
                      );
                    })}
                  </ul>
                </section>

                {commit.status === "error" ? (
                  <Notice title={commit.linked > 0 ? "Parte das cartas entrou" : "Nenhuma carta foi adicionada"}>
                    {commit.linked > 0
                      ? `${formatCount(commit.linked)} ${commit.linked === 1 ? "carta entrou" : "cartas entraram"} na coleção. ${collectionFailureMessage(commit.reason)}`
                      : collectionFailureMessage(commit.reason)}
                  </Notice>
                ) : null}
              </div>
              <Footer lead={chosenCount === 0 ? "Nenhuma carta marcada" : `${formatCount(chosenCount)} ${chosenCount === 1 ? "carta" : "cartas"}`}>
                <Button variant="outline" onClick={close} disabled={busy}>
                  Cancelar
                </Button>
                {commit.status === "error" ? (
                  <Button onClick={() => void load()} disabled={busy}>
                    Revisar de novo
                  </Button>
                ) : (
                  <Button onClick={() => void confirm()} disabled={busy || chosenCount === 0} aria-busy={busy}>
                    {busy ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                    {busy ? "Adicionando…" : `Adicionar ${formatCount(chosenCount)} à coleção`}
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

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

function PickItem({
  item,
  picked,
  disabled,
  onToggle,
  children,
}: {
  item: LinkItem;
  picked: boolean;
  disabled: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  const number = formatCollectorNumber(item.collectorNumber, null);
  return (
    <li className={styles.pickItem} data-picked={picked || undefined}>
      <label className={styles.pickRow}>
        <input type="checkbox" checked={picked} disabled={disabled} onChange={onToggle} className="sr-only" />
        <span className={styles.pickArt} aria-hidden="true">
          <CardArt src={cardFrontUrl(SUPABASE_URL, item.imagePath)} alt="" name={item.cardName} caption={number} sizes="3.5rem" />
        </span>
        <span className="min-w-0 flex-1">
          <span className={styles.pickName}>{item.cardName}</span>
          <span className={styles.pickNumber}>{number}</span>
        </span>
        <span className={styles.pickCheck} aria-hidden="true">
          {picked ? <Check className="h-4 w-4" /> : null}
        </span>
      </label>
      {children}
    </li>
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
