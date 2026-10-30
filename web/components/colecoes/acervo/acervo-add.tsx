"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useId, useMemo, useRef, useState, useTransition } from "react";
import { AlertTriangle, CheckCircle2, Layers, Loader2, Minus, Plus, Search, Trash2, X } from "lucide-react";
import {
  listCardVariantsForAdd,
  confirmAddCards,
  confirmAddSet,
  previewAddCards,
  previewAddSet,
  resolveCardSetForAdd,
} from "@/app/colecoes/acervo/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { formatCollectorNumber, formatCount, pluralize } from "@/lib/colecoes/acervo";
import {
  ADD_MAX_QUANTITY,
  type AddFailure,
  type AddLanguage,
  type AddVariant,
  type DraftLine,
  type PreviewResult,
  type RegisterResult,
  addLine,
  defaultLanguageId,
  defaultVariant,
  draftProblem,
  failureMessage,
  isRetryable,
  issueMessage,
  removeLine,
  selectionLabel,
  toRegisterItems,
  totalQuantity,
  updateLine,
} from "@/lib/colecoes/acervo-add";
import { CardArt } from "./card-art";
import styles from "./acervo-add.module.css";
import acervoStyles from "./acervo.module.css";

type Mode = "cards" | "set";

/**
 * Destino coleção (V1-06 — Fluxos 2 e 5 a partir da coleção). Os mesmos fluxos
 * de Meu acervo, com a coleção no envelope: o banco cria os exemplares e já os
 * aloca na coleção, na mesma transação (5150/5157 — tudo ou nada). Em coleção
 * de Set (inclui Master Set) a busca e o "Set inteiro" ficam presos ao Set de
 * referência; na livre e na Pokédex a busca é o catálogo todo e "Set inteiro"
 * não é oferecido (NS Fluxo 5.1).
 */
export type AddTarget = {
  collectionId: string;
  collectionName: string;
  kind: "set" | "free" | "pokedex";
  cardSet: { code: string; name: string } | null;
  /**
   * Onde guardar (V1-06 COMPLETE-01, NS-13): `choose` = o colecionador escolhe
   * explicitamente (nada pré-selecionado; o local da coleção é só sugestão);
   * `fixed` = local físico do fichário (5247), mostrado e confirmado na revisão.
   * O local vai no mesmo envelope do cadastro (5150/5157) — tudo ou nada.
   */
  storage?: AddStorage;
  /** Cadastro pelo bolso vazio: uma carta por vez (todas as cópias da mesma versão). */
  singleCard?: boolean;
  /** Passo seguinte depois do cadastro confirmado (ex.: colocar no bolso). Nunca desfaz o cadastro. */
  afterRegister?: (result: RegisterResult) => Promise<AfterRegister | null>;
  /** Onde montar o painel (o fichário em tela cheia só mostra o que está dentro dele). */
  container?: HTMLElement | null;
  /** Rótulo do botão de fechar depois do sucesso. */
  closeLabel?: string;
};

export type StorageChoice = { id: string; name: string };
export type AddStorage =
  | { kind: "choose"; locations: StorageChoice[]; suggestedId: string | null }
  | { kind: "fixed"; id: string; name: string };
export type AfterRegister = { tone: "success" | "warning"; text: string };

/**
 * Ações de cadastro de Meu acervo (MY-INVENTORY-ACTIONS-01) — a única ilha
 * cliente nova da página. Dois caminhos:
 *
 * - **Adicionar cartas**: busca → seleção (variante, idioma, quantidade) →
 *   revisão (Preview do banco) → confirmação.
 * - **Adicionar um Set inteiro**: Set + idioma → revisão → confirmação
 *   (contrato BULK-04: uma carta de cada, na versão padrão).
 *
 * Nada aqui decide regra de domínio: a revisão é o Preview do próprio banco e
 * a confirmação reconfere tudo sob lock (PREVIEW_STALE). O painel usa a mesma
 * superfície do detalhe (lateral no desktop, tela cheia no mobile) e não fecha
 * enquanto uma gravação está em andamento.
 *
 * Só é renderizado quando há idiomas disponíveis para cadastro — sem eles as
 * RPCs não teriam como receber o idioma e a ação não funcionaria.
 */
export function AcervoAddActions({ languages, layout }: { languages: AddLanguage[]; layout: "hero" | "empty" }) {
  const [mode, setMode] = useState<Mode | null>(null);

  return (
    <>
      <div className={layout === "hero" ? styles.launcherHero : styles.launcherEmpty}>
        <Button onClick={() => setMode("cards")} className={styles.launchPrimary}>
          <Plus className="h-4 w-4" aria-hidden="true" />
          {layout === "empty" ? "Adicionar a primeira carta" : "Adicionar cartas"}
        </Button>
        <Button variant="outline" onClick={() => setMode("set")} className={styles.launchSecondary}>
          <Layers className="h-4 w-4" aria-hidden="true" />
          Adicionar um Set inteiro
        </Button>
      </div>
      {mode ? <AcervoAddPanel mode={mode} languages={languages} onClose={() => setMode(null)} /> : null}
    </>
  );
}

export function AcervoAddPanel({
  mode: initialMode,
  languages,
  onClose,
  target,
}: {
  mode: Mode;
  languages: AddLanguage[];
  onClose: () => void;
  target?: AddTarget;
}) {
  const [busy, setBusy] = useState(false);
  const [mode, setMode] = useState<Mode>(target?.cardSet || !target ? initialMode : "cards");
  const canSwitch = target?.kind === "set" && target.cardSet !== null && !target.singleCard;
  // Local comum à operação: fixo (fichário) ou escolhido; nunca pré-selecionado (NS-13).
  const [storageId, setStorageId] = useState<string | null>(target?.storage?.kind === "fixed" ? target.storage.id : null);
  const storage: StorageState = { value: storageId, onChange: setStorageId, config: target?.storage ?? null };
  const title = target ? "Adicionar cartas novas" : mode === "cards" ? "Adicionar cartas" : "Adicionar um Set inteiro";

  return (
    <DialogPrimitive.Root
      open
      onOpenChange={(next) => {
        // Nunca fechar com uma gravação em andamento: o resultado precisa ser mostrado.
        if (!next && !busy) onClose();
      }}
    >
      <DialogPrimitive.Portal container={target?.container ?? undefined}>
        <DialogPrimitive.Overlay className={`${acervoStyles.overlay} ${target?.container ? styles.layerOverlay : ""}`} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${styles.panel} ${target?.container ? styles.layerDrawer : ""}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
          // Teclas do painel não chegam a quem está por trás (ex.: navegação de páginas do fichário).
          onKeyDown={(event) => event.stopPropagation()}
        >
          <div className={acervoStyles.drawerHeader}>
            <div className="min-w-0">
              <DialogPrimitive.Title className={styles.panelTitle}>{title}</DialogPrimitive.Title>
              {target ? <p className={styles.panelContext}>em {target.collectionName}</p> : null}
            </div>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>
          {canSwitch ? (
            <div className={styles.modeTabs} role="tablist" aria-label="Como adicionar">
              {(["cards", "set"] as const).map((option) => (
                <button
                  key={option}
                  type="button"
                  role="tab"
                  aria-selected={mode === option}
                  className={styles.modeTab}
                  disabled={busy}
                  onClick={() => setMode(option)}
                >
                  {option === "cards" ? <Plus className="h-3.5 w-3.5" aria-hidden="true" /> : <Layers className="h-3.5 w-3.5" aria-hidden="true" />}
                  {option === "cards" ? "Escolher cartas" : "Set inteiro"}
                </button>
              ))}
            </div>
          ) : null}
          {mode === "cards" ? (
            <CardsFlow key="cards" languages={languages} onBusy={setBusy} onClose={onClose} target={target} storage={storage} />
          ) : (
            <SetFlow key="set" languages={languages} onBusy={setBusy} onClose={onClose} target={target} storage={storage} />
          )}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

// ---------------------------------------------------------------------------
// Confirmação compartilhada: revisão → gravação → resultado
// ---------------------------------------------------------------------------

type Review =
  | { status: "loading" }
  | { status: "error"; reason: AddFailure }
  | { status: "ready"; preview: PreviewResult; key: string };

type Commit =
  | { status: "idle" }
  | { status: "pending" }
  | { status: "error"; reason: AddFailure }
  | { status: "done"; result: RegisterResult; follow: AfterRegister | null };

/**
 * Máquina da confirmação, igual nos dois fluxos.
 *
 * - A chave de idempotência nasce com a revisão aprovada e é reaproveitada em
 *   toda nova tentativa da mesma confirmação (falha transitória → REPLAY no
 *   banco, nunca cartas em dobro).
 * - `inFlight` impede um segundo envio enquanto o primeiro não volta, mesmo
 *   antes de o botão desabilitar (duplo clique, Enter repetido).
 */
function useConfirmFlow({
  runPreview,
  runCommit,
  onBusy,
  afterCommit,
}: {
  runPreview: () => Promise<{ ok: true; preview: PreviewResult } | { ok: false; reason: AddFailure }>;
  runCommit: (key: string, fingerprint: string) => Promise<{ ok: true; result: RegisterResult } | { ok: false; reason: AddFailure }>;
  onBusy: (busy: boolean) => void;
  afterCommit?: (result: RegisterResult) => Promise<AfterRegister | null>;
}) {
  const router = useRouter();
  const [review, setReview] = useState<Review | null>(null);
  const [commit, setCommit] = useState<Commit>({ status: "idle" });
  const inFlight = useRef(false);
  const generation = useRef(0);
  const [, startRefresh] = useTransition();

  const startReview = useCallback(async () => {
    const run = ++generation.current;
    setCommit({ status: "idle" });
    setReview({ status: "loading" });
    const response = await runPreview();
    if (run !== generation.current) return; // seleção mudou enquanto conferia
    if (!response.ok) {
      setReview({ status: "error", reason: response.reason });
      return;
    }
    setReview({ status: "ready", preview: response.preview, key: crypto.randomUUID() });
  }, [runPreview]);

  const cancelReview = useCallback(() => {
    generation.current++;
    setReview(null);
    setCommit({ status: "idle" });
  }, []);

  const confirm = useCallback(async () => {
    if (inFlight.current || review?.status !== "ready" || !review.preview.fingerprint) return;
    inFlight.current = true;
    onBusy(true);
    setCommit({ status: "pending" });
    try {
      const response = await runCommit(review.key, review.preview.fingerprint);
      if (response.ok) {
        // O cadastro já está gravado; o passo seguinte (ex.: bolso) nunca o desfaz e
        // comunica o próprio resultado — sucesso parcial não vira "tudo certo".
        const follow = afterCommit ? await afterCommit(response.result).catch(() => ({ tone: "warning" as const, text: FOLLOW_UNKNOWN })) : null;
        setCommit({ status: "done", result: response.result, follow });
        // Galeria, números e detalhe relidos no servidor (a ação também revalida a rota).
        startRefresh(() => router.refresh());
      } else {
        setCommit({ status: "error", reason: response.reason });
      }
    } catch {
      // Rede caiu no meio: o resultado é desconhecido, a mesma chave torna a nova tentativa segura.
      setCommit({ status: "error", reason: "unavailable" });
    } finally {
      inFlight.current = false;
      onBusy(false);
    }
  }, [review, runCommit, onBusy, router, afterCommit]);

  return { review, commit, startReview, cancelReview, confirm };
}

function ReviewView({
  review,
  commit,
  summary,
  details,
  note,
  where,
  onBack,
  onConfirm,
  onRetryReview,
}: {
  review: Review;
  commit: Commit;
  summary: (preview: PreviewResult) => ReactNode;
  details?: ReactNode;
  note: string;
  /** Local da operação (V1-06): mostrado e confirmado aqui (NS-13). */
  where?: ReactNode;
  onBack: () => void;
  onConfirm: () => void;
  onRetryReview: () => void;
}) {
  const pending = commit.status === "pending";

  if (review.status === "loading") {
    return (
      <div className={styles.body}>
        <div className={styles.centerState} role="status">
          <Loader2 className={`h-5 w-5 ${styles.spin}`} aria-hidden="true" />
          Conferindo com o catálogo…
        </div>
      </div>
    );
  }

  if (review.status === "error") {
    return (
      <>
        <div className={styles.body}>
          <Notice tone="error" title="Não conseguimos revisar agora">
            {failureMessage(review.reason)}
          </Notice>
        </div>
        <Footer>
          <Button variant="outline" onClick={onBack}>
            Voltar
          </Button>
          <Button onClick={onRetryReview}>Tentar de novo</Button>
        </Footer>
      </>
    );
  }

  const { preview } = review;

  if (!preview.ok) {
    return (
      <>
        <div className={styles.body}>
          <Notice tone="error" title="Ainda não dá para adicionar">
            <ul className={styles.issueList}>
              {preview.issues.map((issue, index) => (
                <li key={`${issue.code}.${index}`}>{issueMessage(issue)}</li>
              ))}
            </ul>
          </Notice>
        </div>
        <Footer>
          <Button onClick={onBack}>Voltar e ajustar</Button>
        </Footer>
      </>
    );
  }

  const staleLike = commit.status === "error" && !isRetryable(commit.reason);

  return (
    <>
      <div className={styles.body}>
        <div className={styles.reviewHead}>{summary(preview)}</div>
        <p className={styles.reviewNote}>{note}</p>
        {where}
        {details}
        <div aria-live="polite">
          {commit.status === "error" ? (
            <Notice tone="error" title="A adição não foi concluída">
              {failureMessage(commit.reason)}
            </Notice>
          ) : null}
        </div>
      </div>
      <Footer>
        <Button variant="outline" onClick={onBack} disabled={pending}>
          Voltar
        </Button>
        {staleLike ? (
          <Button onClick={onRetryReview}>Revisar de novo</Button>
        ) : (
          <Button onClick={onConfirm} disabled={pending} aria-disabled={pending}>
            {pending ? <Loader2 className={`h-4 w-4 ${styles.spin}`} aria-hidden="true" /> : null}
            {pending
              ? "Adicionando…"
              : commit.status === "error"
                ? "Tentar novamente"
                : `Adicionar ${pluralize(preview.totalQuantity, "carta", "cartas")}`}
          </Button>
        )}
      </Footer>
    </>
  );
}

function DoneView({
  result,
  onMore,
  onClose,
  moreLabel,
  target,
  follow = null,
}: {
  result: RegisterResult;
  onMore: () => void;
  onClose: () => void;
  moreLabel: string;
  target?: AddTarget;
  follow?: AfterRegister | null;
}) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => headingRef.current?.focus(), []);
  if (target) {
    const n = result.createdCount;
    return (
      <>
        <div className={styles.body}>
          <div className={styles.done} role="status">
            <span className={styles.doneIcon} aria-hidden="true">
              <CheckCircle2 className="h-6 w-6" />
            </span>
            <h2 ref={headingRef} tabIndex={-1} className={styles.doneTitle}>
              {n === 1 ? "1 carta adicionada à coleção" : `${formatCount(n)} cartas adicionadas à coleção`}
            </h2>
            <p className={styles.doneText}>{targetDoneText(target, n)}</p>
            {follow ? (
              <p className={styles.followNote} data-tone={follow.tone} role={follow.tone === "warning" ? "alert" : undefined}>
                {follow.tone === "warning" ? <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" /> : <CheckCircle2 className="h-4 w-4 shrink-0" aria-hidden="true" />}
                {follow.text}
              </p>
            ) : null}
          </div>
        </div>
        <Footer>
          {target.singleCard ? null : (
            <Button variant="outline" onClick={onMore}>
              {moreLabel}
            </Button>
          )}
          <Button onClick={onClose}>{target.closeLabel ?? "Ver a coleção"}</Button>
        </Footer>
      </>
    );
  }
  return (
    <>
      <div className={styles.body}>
        <div className={styles.done} role="status">
          <span className={styles.doneIcon} aria-hidden="true">
            <CheckCircle2 className="h-6 w-6" />
          </span>
          <h2 ref={headingRef} tabIndex={-1} className={styles.doneTitle}>
            {result.createdCount === 1
              ? "1 carta adicionada ao seu acervo"
              : `${formatCount(result.createdCount)} cartas adicionadas ao seu acervo`}
          </h2>
          <p className={styles.doneText}>
            {result.distinctItems > 1
              ? `${formatCount(result.distinctItems)} cartas diferentes. Elas já aparecem na sua galeria e nos números do acervo.`
              : "Ela já aparece na sua galeria e nos números do acervo."}
          </p>
        </div>
      </div>
      <Footer>
        <Button variant="outline" onClick={onMore}>
          {moreLabel}
        </Button>
        <Button onClick={onClose}>Ver meu acervo</Button>
      </Footer>
    </>
  );
}

// ---------------------------------------------------------------------------
// Adicionar cartas
// ---------------------------------------------------------------------------

type SearchCard = {
  id: string;
  name: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSet: { id: string; code: string; name: string };
  imageUrlPt: string | null;
  imageUrlEn: string | null;
};

type VariantState = AddVariant[] | "loading" | "error";

const SEARCH_DEBOUNCE_MS = 300;
const SEARCH_LIMIT = 20;

function CardsFlow({
  languages,
  onBusy,
  onClose,
  target,
  storage,
}: {
  languages: AddLanguage[];
  onBusy: (busy: boolean) => void;
  onClose: () => void;
  target?: AddTarget;
  storage: StorageState;
}) {
  const [lines, setLines] = useState<DraftLine[]>([]);
  const [variants, setVariants] = useState<Record<string, VariantState>>({});
  const [reviewing, setReviewing] = useState(false);
  const languageId = defaultLanguageId(languages);

  const items = useMemo(() => toRegisterItems(lines), [lines]);
  const collectionId = target?.collectionId ?? null;
  const storageId = storage.value;
  const runPreview = useCallback(() => previewAddCards(items, collectionId, storageId), [items, collectionId, storageId]);
  const runCommit = useCallback(
    (key: string, fingerprint: string) => confirmAddCards({ idempotencyKey: key, fingerprint, items, collectionId, storageId }),
    [items, collectionId, storageId],
  );
  const flow = useConfirmFlow({ runPreview, runCommit, onBusy, afterCommit: target?.afterRegister });

  async function pick(card: SearchCard) {
    if (!languageId) return;
    const known = variants[card.id];
    let list: AddVariant[] | null = Array.isArray(known) ? known : null;
    if (!list) {
      if (known === "loading") return;
      setVariants((prev) => ({ ...prev, [card.id]: "loading" }));
      const response = await listCardVariantsForAdd(card.id).catch(() => null);
      if (!response || !response.ok) {
        setVariants((prev) => ({ ...prev, [card.id]: "error" }));
        return;
      }
      list = response.variants;
      setVariants((prev) => ({ ...prev, [card.id]: response.variants }));
    }
    const variant = defaultVariant(list);
    if (!variant) return;
    // Bolso vazio: uma carta só — escolher outra substitui a seleção.
    setLines((prev) =>
      addLine(target?.singleCard ? [] : prev, {
        cardId: card.id,
        cardName: card.name,
        setCode: card.cardSet.code,
        setName: card.cardSet.name,
        collectorNumber: card.collectorNumber,
        collectorTotal: card.collectorTotal,
        imageUrl: card.imageUrlPt ?? card.imageUrlEn,
        variantId: variant.id,
        variantLabel: variant.label,
        isDefaultVariant: variant.isDefault,
        languageId,
        quantity: 1,
      }),
    );
  }

  const copies = totalQuantity(lines);
  const problem = draftProblem(lines);

  if (flow.commit.status === "done") {
    return (
      <DoneView
        result={flow.commit.result}
        follow={flow.commit.follow}
        moreLabel="Adicionar mais cartas"
        target={target}
        onClose={onClose}
        onMore={() => {
          setLines([]);
          setReviewing(false);
          flow.cancelReview();
        }}
      />
    );
  }

  if (reviewing && flow.review) {
    return (
      <ReviewView
        review={flow.review}
        commit={flow.commit}
        onBack={() => {
          flow.cancelReview();
          setReviewing(false);
        }}
        onConfirm={() => void flow.confirm()}
        onRetryReview={() => void flow.startReview()}
        note={reviewNote(target)}
        where={<StorageReview storage={storage} />}
        summary={(preview) => (
          <>
            <span className={styles.reviewCount}>{formatCount(preview.totalQuantity)}</span>
            <span className={styles.reviewLabel}>
              {preview.totalQuantity === 1 ? "carta será adicionada" : "cartas serão adicionadas"}
              {preview.distinctItems > 1 ? ` · ${formatCount(preview.distinctItems)} diferentes` : ""}
            </span>
          </>
        )}
        details={
          <ul className={styles.reviewList} aria-label="Cartas que serão adicionadas">
            {lines.map((line) => (
              <li key={`${line.variantId}:${line.languageId}`} className={styles.reviewItem}>
                <span className={styles.reviewQty}>×{line.quantity}</span>
                <span className={styles.reviewName}>{line.cardName}</span>
                <span className={styles.reviewMeta}>
                  {line.setCode.toUpperCase()} · {formatCollectorNumber(line.collectorNumber, line.collectorTotal)}
                  {line.variantLabel?.trim() ? ` · ${line.variantLabel.trim()}` : ""}
                  {" · "}
                  {languages.find((language) => language.id === line.languageId)?.code ?? ""}
                </span>
              </li>
            ))}
          </ul>
        }
      />
    );
  }

  return (
    <>
      <div className={styles.body}>
        <CardSearch onPick={pick} variants={variants} cardSet={target?.cardSet ?? null} />
        <StorageField storage={storage} />

        <section className={styles.selection} aria-labelledby="acervo-add-selecao">
          <h3 id="acervo-add-selecao" className={styles.sectionTitle}>
            Sua seleção
          </h3>
          {lines.length === 0 ? (
            <p className={styles.hint}>
              Busque uma carta e toque nela para incluí-la. Repita para montar a lista toda de uma vez.
              {target ? " Elas entram no seu acervo e já nesta coleção." : ""}
            </p>
          ) : (
            <ul className={styles.lines}>
              {lines.map((line, index) => (
                <SelectionLine
                  key={`${line.variantId}:${line.languageId}`}
                  line={line}
                  variants={variants[line.cardId]}
                  languages={languages}
                  onChange={(patch) => setLines((prev) => updateLine(prev, index, patch))}
                  onRemove={() => setLines((prev) => removeLine(prev, index))}
                />
              ))}
            </ul>
          )}
        </section>
      </div>
      <Footer lead={lines.length > 0 ? selectionLabel({ copies, distinct: lines.length }) : null}>
        {problem && lines.length > 0 ? <span className={styles.footerProblem}>{problem}</span> : null}
        <Button
          disabled={problem !== null}
          onClick={() => {
            setReviewing(true);
            void flow.startReview();
          }}
        >
          Revisar
        </Button>
      </Footer>
    </>
  );
}

function CardSearch({
  onPick,
  variants,
  cardSet = null,
}: {
  onPick: (card: SearchCard) => void;
  variants: Record<string, VariantState>;
  /** Coleção de Set: busca presa ao Set de referência (o banco recusaria as demais). */
  cardSet?: { code: string; name: string } | null;
}) {
  const inputId = useId();
  const [query, setQuery] = useState("");
  const [state, setState] = useState<{ status: "idle" | "loading" | "error" } | { status: "ready"; cards: SearchCard[]; total: number }>({
    status: "idle",
  });

  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) {
      setState({ status: "idle" });
      return;
    }
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      setState({ status: "loading" });
      try {
        const scope = cardSet ? `&set=${encodeURIComponent(cardSet.code)}` : "";
        const response = await fetch(`/api/cards/search?q=${encodeURIComponent(term)}&limit=${SEARCH_LIMIT}${scope}`, {
          signal: controller.signal,
        });
        if (!response.ok) throw new Error(String(response.status));
        const body = (await response.json()) as { cards: SearchCard[]; totalCount: number };
        setState({ status: "ready", cards: body.cards, total: body.totalCount });
      } catch (error) {
        if ((error as Error).name !== "AbortError") setState({ status: "error" });
      }
    }, SEARCH_DEBOUNCE_MS);
    return () => {
      controller.abort();
      clearTimeout(timer);
    };
  }, [query, cardSet]);

  return (
    <section aria-labelledby={`${inputId}-label`}>
      <label id={`${inputId}-label`} htmlFor={inputId} className={styles.sectionTitle}>
        {cardSet ? `Buscar em ${cardSet.name}` : "Buscar no catálogo"}
      </label>
      <div className={styles.searchWrap}>
        <Search className={styles.searchIcon} aria-hidden="true" />
        <Input
          id={inputId}
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={cardSet ? "Nome ou número (58/102)" : "Nome, número (58/102) ou Set"}
          autoComplete="off"
          autoFocus
          className={styles.searchInput}
        />
      </div>
      <div aria-live="polite" className={styles.searchStatus}>
        {state.status === "loading" ? "Buscando…" : null}
        {state.status === "error" ? "Não conseguimos buscar agora. Tente de novo em instantes." : null}
        {state.status === "ready" && state.cards.length === 0 ? "Nenhuma carta encontrada." : null}
        {state.status === "ready" && state.total > state.cards.length
          ? `Mostrando ${state.cards.length} de ${formatCount(state.total)} — refine a busca para encontrar mais rápido.`
          : null}
      </div>
      {state.status === "ready" && state.cards.length > 0 ? (
        <ul className={styles.results} aria-label="Resultados da busca">
          {state.cards.map((card) => {
            const cardVariants = variants[card.id];
            const number = formatCollectorNumber(card.collectorNumber, card.collectorTotal);
            return (
              <li key={card.id}>
                <button
                  type="button"
                  className={styles.result}
                  onClick={() => onPick(card)}
                  disabled={cardVariants === "loading"}
                  aria-label={`Incluir ${card.name}, ${card.cardSet.name} ${number}`}
                >
                  <span className={`${acervoStyles.art} ${styles.thumb}`}>
                    <CardArt
                      src={card.imageUrlPt ?? card.imageUrlEn}
                      alt=""
                      name={card.name}
                      caption={number}
                      sizes="3rem"
                    />
                  </span>
                  <span className={styles.resultText}>
                    <span className={styles.resultName}>{card.name}</span>
                    <span className={styles.resultMeta}>
                      {card.cardSet.name} · {number}
                    </span>
                    {cardVariants === "error" ? (
                      <span className={styles.resultError}>Não conseguimos carregar as versões. Toque para tentar de novo.</span>
                    ) : null}
                  </span>
                  <span className={styles.resultAdd} aria-hidden="true">
                    {cardVariants === "loading" ? <Loader2 className={`h-4 w-4 ${styles.spin}`} /> : <Plus className="h-4 w-4" />}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      ) : null}
    </section>
  );
}

function SelectionLine({
  line,
  variants,
  languages,
  onChange,
  onRemove,
}: {
  line: DraftLine;
  variants: VariantState | undefined;
  languages: AddLanguage[];
  onChange: (patch: Partial<Pick<DraftLine, "variantId" | "variantLabel" | "isDefaultVariant" | "languageId" | "quantity">>) => void;
  onRemove: () => void;
}) {
  const id = useId();
  const number = formatCollectorNumber(line.collectorNumber, line.collectorTotal);
  const list = Array.isArray(variants) ? variants : [];

  return (
    <li className={styles.line}>
      <span className={`${acervoStyles.art} ${styles.thumb}`}>
        <CardArt src={line.imageUrl} alt="" name={line.cardName} caption={number} sizes="3rem" />
      </span>
      <div className={styles.lineMain}>
        <div className={styles.lineHead}>
          <div>
            <p className={styles.resultName}>{line.cardName}</p>
            <p className={styles.resultMeta}>
              {line.setName} · {number}
            </p>
          </div>
          <button type="button" className={styles.iconButton} onClick={onRemove} aria-label={`Remover ${line.cardName} da seleção`}>
            <Trash2 className="h-4 w-4" aria-hidden="true" />
          </button>
        </div>
        <div className={styles.lineControls}>
          {list.length > 1 ? (
            <div className={styles.field}>
              <label htmlFor={`${id}-variant`} className={styles.fieldLabel}>
                Versão
              </label>
              <Select
                id={`${id}-variant`}
                value={line.variantId}
                onChange={(event) => {
                  const next = list.find((variant) => variant.id === event.target.value);
                  if (next) onChange({ variantId: next.id, variantLabel: next.label, isDefaultVariant: next.isDefault });
                }}
              >
                {list.map((variant) => (
                  <option key={variant.id} value={variant.id}>
                    {variant.isDefault ? `Padrão${variant.label ? ` (${variant.label})` : ""}` : (variant.label ?? "Outra versão")}
                  </option>
                ))}
              </Select>
            </div>
          ) : null}
          {languages.length > 1 ? (
            <div className={styles.field}>
              <label htmlFor={`${id}-language`} className={styles.fieldLabel}>
                Idioma
              </label>
              <Select id={`${id}-language`} value={line.languageId} onChange={(event) => onChange({ languageId: event.target.value })}>
                {languages.map((language) => (
                  <option key={language.id} value={language.id}>
                    {language.name}
                  </option>
                ))}
              </Select>
            </div>
          ) : null}
          <div className={styles.field}>
            <span id={`${id}-qty`} className={styles.fieldLabel}>
              Cópias
            </span>
            <div className={styles.stepper} role="group" aria-labelledby={`${id}-qty`}>
              <button
                type="button"
                className={styles.stepButton}
                onClick={() => onChange({ quantity: line.quantity - 1 })}
                disabled={line.quantity <= 1}
                aria-label="Menos uma cópia"
              >
                <Minus className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
              <input
                className={styles.stepValue}
                inputMode="numeric"
                aria-label={`Cópias de ${line.cardName}`}
                value={line.quantity}
                onChange={(event) => {
                  const value = Number.parseInt(event.target.value.replace(/\D/g, ""), 10);
                  if (Number.isFinite(value)) onChange({ quantity: value });
                }}
              />
              <button
                type="button"
                className={styles.stepButton}
                onClick={() => onChange({ quantity: line.quantity + 1 })}
                disabled={line.quantity >= ADD_MAX_QUANTITY}
                aria-label="Mais uma cópia"
              >
                <Plus className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </li>
  );
}

// ---------------------------------------------------------------------------
// Adicionar um Set inteiro
// ---------------------------------------------------------------------------

type SetOption = { code: string; name: string };

function SetFlow({
  languages,
  onBusy,
  onClose,
  target,
  storage,
}: {
  languages: AddLanguage[];
  onBusy: (busy: boolean) => void;
  onClose: () => void;
  target?: AddTarget;
  storage: StorageState;
}) {
  const filterId = useId();
  const storageId = storage.value;
  const languageFieldId = useId();
  // Coleção de Set: o Set já é o da coleção — sem lista para escolher.
  const fixedSet = target?.cardSet ?? null;
  const collectionId = target?.collectionId ?? null;
  const [sets, setSets] = useState<{ status: "loading" | "error" } | { status: "ready"; options: SetOption[] }>(
    fixedSet ? { status: "ready", options: [fixedSet] } : { status: "loading" },
  );
  const [filter, setFilter] = useState("");
  const [setCode, setSetCode] = useState<string | null>(fixedSet?.code ?? null);
  const [languageId, setLanguageId] = useState<string | null>(defaultLanguageId(languages));
  const [reviewing, setReviewing] = useState(false);
  const resolved = useRef<{ code: string; id: string } | null>(null);
  const [loadAttempt, setLoadAttempt] = useState(0);

  useEffect(() => {
    if (fixedSet) return;
    const controller = new AbortController();
    setSets({ status: "loading" });
    fetch("/api/cards/filter-options", { signal: controller.signal })
      .then((response) => (response.ok ? response.json() : Promise.reject(new Error(String(response.status)))))
      .then((body: { cardSets?: SetOption[] }) => setSets({ status: "ready", options: body.cardSets ?? [] }))
      .catch((error: Error) => {
        if (error.name !== "AbortError") setSets({ status: "error" });
      });
    return () => controller.abort();
  }, [loadAttempt, fixedSet]);

  const chosen = sets.status === "ready" ? sets.options.find((option) => option.code === setCode) ?? null : null;
  const language = languages.find((option) => option.id === languageId) ?? null;

  const runPreview = useCallback(async () => {
    if (!setCode || !languageId) return { ok: false as const, reason: "invalid" as const };
    let cardSetId = resolved.current?.code === setCode ? resolved.current.id : null;
    if (!cardSetId) {
      const response = await resolveCardSetForAdd(setCode);
      if (!response.ok) return response;
      cardSetId = response.cardSetId;
      resolved.current = { code: setCode, id: cardSetId };
    }
    return previewAddSet({ cardSetId, languageId, collectionId, storageId });
  }, [setCode, languageId, collectionId, storageId]);

  const runCommit = useCallback(
    async (key: string, fingerprint: string) => {
      const cardSetId = resolved.current?.code === setCode ? resolved.current.id : null;
      if (!cardSetId || !languageId) return { ok: false as const, reason: "invalid" as const };
      return confirmAddSet({ idempotencyKey: key, fingerprint, cardSetId, languageId, collectionId, storageId });
    },
    [setCode, languageId, collectionId, storageId],
  );

  const flow = useConfirmFlow({ runPreview, runCommit, onBusy, afterCommit: target?.afterRegister });

  const visible = useMemo(() => {
    if (sets.status !== "ready") return [];
    const term = filter.trim().toLocaleLowerCase("pt-BR");
    if (!term) return sets.options;
    return sets.options.filter(
      (option) => option.name.toLocaleLowerCase("pt-BR").includes(term) || option.code.toLocaleLowerCase("pt-BR").includes(term),
    );
  }, [sets, filter]);

  if (flow.commit.status === "done") {
    return (
      <DoneView
        result={flow.commit.result}
        follow={flow.commit.follow}
        moreLabel={fixedSet ? "Adicionar mais cartas" : "Adicionar outro Set"}
        target={target}
        onClose={onClose}
        onMore={() => {
          setSetCode(fixedSet?.code ?? null);
          setReviewing(false);
          flow.cancelReview();
        }}
      />
    );
  }

  if (reviewing && flow.review) {
    return (
      <ReviewView
        review={flow.review}
        commit={flow.commit}
        onBack={() => {
          flow.cancelReview();
          setReviewing(false);
        }}
        onConfirm={() => void flow.confirm()}
        onRetryReview={() => void flow.startReview()}
        note={reviewNote(target)}
        where={<StorageReview storage={storage} />}
        summary={(preview) => (
          <>
            <span className={styles.reviewCount}>{formatCount(preview.totalQuantity)}</span>
            <span className={styles.reviewLabel}>
              {preview.totalQuantity === 1 ? "carta será adicionada" : "cartas serão adicionadas"} — uma de cada carta de{" "}
              <strong>{chosen?.name ?? setCode}</strong>, na versão padrão, em {language?.name ?? "idioma escolhido"}.
            </span>
          </>
        )}
      />
    );
  }

  return (
    <>
      <div className={styles.body}>
        <p className={styles.hint}>
          {fixedSet
            ? `Tem ${fixedSet.name} completo? Registre uma carta de cada, na versão padrão, de uma vez — já nesta coleção. Repetidas e outras versões você adiciona depois, em “Escolher cartas”.`
            : "Uma carta de cada do Set, na versão padrão de cada uma. Repetidas e outras versões você adiciona depois, carta a carta."}
        </p>

        <div className={styles.field}>
          <label htmlFor={languageFieldId} className={styles.sectionTitle}>
            Idioma das cartas
          </label>
          <Select id={languageFieldId} value={languageId ?? ""} onChange={(event) => setLanguageId(event.target.value)}>
            {languages.map((option) => (
              <option key={option.id} value={option.id}>
                {option.name}
              </option>
            ))}
          </Select>
        </div>

        <StorageField storage={storage} />

        {fixedSet ? (
          <div className={styles.fixedSet}>
            <span className={styles.sectionTitle}>Set</span>
            <p className={styles.fixedSetName}>
              {fixedSet.name}
              <span className={styles.setCode}>{fixedSet.code.toUpperCase()}</span>
            </p>
          </div>
        ) : (
          <section className={styles.selection} aria-labelledby={`${filterId}-label`}>
            <label id={`${filterId}-label`} htmlFor={filterId} className={styles.sectionTitle}>
              Set
            </label>
            <div className={styles.searchWrap}>
              <Search className={styles.searchIcon} aria-hidden="true" />
              <Input
                id={filterId}
                type="search"
                value={filter}
                onChange={(event) => setFilter(event.target.value)}
                placeholder="Filtrar por nome ou código"
                autoComplete="off"
                autoFocus
                className={styles.searchInput}
              />
            </div>
            <div aria-live="polite" className={styles.searchStatus}>
              {sets.status === "loading" ? "Carregando Sets…" : null}
              {sets.status === "ready" && visible.length === 0 ? "Nenhum Set encontrado." : null}
            </div>
            {sets.status === "error" ? (
              <Notice tone="error" title="Não conseguimos carregar os Sets">
                <Button variant="outline" size="sm" onClick={() => setLoadAttempt((n) => n + 1)} className="mt-2">
                  Tentar de novo
                </Button>
              </Notice>
            ) : null}
            {visible.length > 0 ? (
              <div className={styles.setList} role="radiogroup" aria-label="Sets do catálogo">
                {visible.map((option) => (
                  <label key={option.code} className={styles.setOption} data-checked={option.code === setCode || undefined}>
                    <input
                      type="radio"
                      name="acervo-add-set"
                      value={option.code}
                      checked={option.code === setCode}
                      onChange={() => setSetCode(option.code)}
                      className={styles.setRadio}
                    />
                    <span className={styles.setName}>{option.name}</span>
                    <span className={styles.setCode}>{option.code.toUpperCase()}</span>
                  </label>
                ))}
              </div>
            ) : null}
          </section>
        )}
      </div>
      <Footer lead={chosen ? chosen.name : null}>
        <Button
          disabled={!setCode || !languageId}
          onClick={() => {
            setReviewing(true);
            void flow.startReview();
          }}
        >
          Revisar
        </Button>
      </Footer>
    </>
  );
}

// ---------------------------------------------------------------------------
// Peças compartilhadas
// ---------------------------------------------------------------------------

function Footer({ lead, children }: { lead?: string | null; children: ReactNode }) {
  return (
    <div className={styles.footer}>
      <span className={styles.footerLead} aria-live="polite">
        {lead ?? ""}
      </span>
      <div className={styles.footerActions}>{children}</div>
    </div>
  );
}

function Notice({ tone, title, children }: { tone: "error"; title: string; children: ReactNode }) {
  return (
    <div className={styles.notice} data-tone={tone} role="alert">
      <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
      <div>
        <p className={styles.noticeTitle}>{title}</p>
        <div className={styles.noticeText}>{children}</div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Textos com destino coleção (V1-06)
// ---------------------------------------------------------------------------

function reviewNote(target: AddTarget | undefined): string {
  if (!target) return "Cada carta entra como um exemplar próprio, sem coleção e sem localização definida.";
  return "Cada carta entra como um exemplar próprio no seu acervo e já nesta coleção — e no local abaixo, se houver. Se algo impedir, nada é gravado.";
}

function targetDoneText(target: AddTarget, created: number): string {
  const they = created === 1 ? "Ela também está" : "Elas também estão";
  if (target.storage?.kind === "fixed") {
    return `${they} no seu acervo, guardada${created === 1 ? "" : "s"} em “${target.storage.name}”, prontas para os bolsos em Cartas disponíveis.`;
  }
  if (target.kind === "free") return `${they} no seu acervo.`;
  if (target.kind === "pokedex") {
    return `${they} no seu acervo. Quando o Pokémon da carta é reconhecido, ela já ocupa o lugar dele na Pokédex; as demais ficam na coleção para você posicionar.`;
  }
  return `${they} no seu acervo, e o progresso da coleção já foi atualizado.`;
}

// ---------------------------------------------------------------------------
// Onde guardar (V1-06 COMPLETE-01 — NS-13)
// ---------------------------------------------------------------------------

type StorageState = { value: string | null; onChange: (id: string | null) => void; config: AddStorage | null };

const FOLLOW_UNKNOWN = "As cartas foram cadastradas, mas não conseguimos confirmar o passo seguinte. Confira no fichário.";

function storageName(storage: StorageState): string | null {
  const config = storage.config;
  if (!config || storage.value === null) return null;
  if (config.kind === "fixed") return config.name;
  return config.locations.find((location) => location.id === storage.value)?.name ?? null;
}

/**
 * Escolha comum à operação. `fixed`: o fichário físico, sem controle (é o
 * local que o próprio fichário representa). `choose`: nada pré-selecionado —
 * "Sem localização definida" até o colecionador escolher; o local da coleção
 * aparece como atalho explícito, nunca aplicado sozinho.
 */
function StorageField({ storage }: { storage: StorageState }) {
  const id = useId();
  const config = storage.config;
  if (!config) return null;
  if (config.kind === "fixed") {
    return (
      <div className={styles.field}>
        <span className={styles.sectionTitle}>Onde guardar</span>
        <p className={styles.storageFixed}>
          <span className={styles.storageName}>{config.name}</span>
          <span className={styles.hint}>O fichário físico deste fichário digital. As cartas ficam prontas para ir aos bolsos.</span>
        </p>
      </div>
    );
  }
  const suggested = config.suggestedId ? config.locations.find((location) => location.id === config.suggestedId) ?? null : null;
  return (
    <div className={styles.field}>
      <label htmlFor={id} className={styles.sectionTitle}>
        Onde guardar
      </label>
      <Select id={id} value={storage.value ?? ""} onChange={(event) => storage.onChange(event.target.value || null)}>
        <option value="">Sem localização definida</option>
        {config.locations.map((location) => (
          <option key={location.id} value={location.id}>
            {location.name}
            {location.id === config.suggestedId ? " — local da coleção" : ""}
          </option>
        ))}
      </Select>
      {suggested && storage.value !== suggested.id ? (
        <button type="button" className={styles.storageSuggest} onClick={() => storage.onChange(suggested.id)}>
          Usar o local da coleção: {suggested.name}
        </button>
      ) : null}
      <p className={styles.hint}>
        {storage.value
          ? "Escolha só se as cartas estão fisicamente lá. Você confirma na revisão."
          : "Você pode definir depois, em Meu acervo."}
      </p>
    </div>
  );
}

function StorageReview({ storage }: { storage: StorageState }) {
  if (!storage.config) return null;
  const name = storageName(storage);
  return (
    <p className={styles.storageReview}>
      <span className={styles.storageReviewLabel}>Onde guardar</span>
      {name ? (
        <>
          <strong>{name}</strong>
          <span>Ao confirmar, você declara que estas cartas estão fisicamente em “{name}”.</span>
        </>
      ) : (
        <strong>Sem localização definida</strong>
      )}
    </p>
  );
}
