"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { AlertTriangle, CheckCircle2, Crown, Loader2, RefreshCw, Search, Sparkles, X } from "lucide-react";
import { readEditorPokedexCopies, writeEditorPokedex } from "@/app/colecoes/compartilhada/[id]/pokedex-editor-actions";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { SpeciesArtwork } from "@/components/pokedex/species-artwork";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { cardFrontUrl, formatCount } from "@/lib/colecoes/acervo";
import { SIGN_IN_PATH } from "@/lib/colecoes/binder-activity";
import { COPY_QUERY_MAX, type CopiesPage, type CopyScope, type EditorPokedexCopy, failurePolicy, resultChanged, resultMessage } from "@/lib/colecoes/editor-pokedex";
import {
  type Busy,
  type Outcome,
  type PanelReaction,
  type PendingConfirmation,
  type SyncState,
  type WriteIntent,
  actionsEnabled,
  beginWrite,
  chooseIntent,
  confirmationUsable,
  emptyListMessage,
  isBusy,
  mergeCopiesPages,
  moveIntent,
  moveLabel,
  originLine,
  planAfter,
  prepareConfirmation,
  reactToFailure,
  restoreIntent,
  positionStateLine,
  readFailure,
  syncAfterReload,
  syncMessage,
  unassignIntent,
  writeNoticeTitle,
} from "@/lib/colecoes/editor-pokedex-panel";
import { type PokedexPosition, formatDex } from "@/lib/colecoes/pokedex";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import { CardArt } from "../acervo/card-art";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "../colecoes/pokedex.module.css";
import local from "./shared-pokedex-editor-panel.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SEARCH_DEBOUNCE_MS = 300;

type List =
  | { status: "loading" }
  | { status: "error"; message: string; retry: boolean }
  // F3-5: acesso bloqueado — os dados anteriores (e seus tokens) são descartados, não só escondidos.
  | { status: "blocked"; message: string }
  | { status: "ready"; page: CopiesPage; loadingMore: boolean };

type Feedback = { tone: PanelReaction["tone"]; text: string; title?: string } | null;

/**
 * V1-13 · E3 / F3-2 — painel de uma posição da Pokédex compartilhada para o
 * EDITOR. Mesma linguagem visual do painel do titular, mas só com o contrato
 * colaborativo: leitura 5391 (token opaco por exemplar) e escritas 5392. Nada de
 * identificador físico, local, condição ou "tirar da coleção" (patrimonial).
 *
 * - "Nesta posição" (AT_POSITION): representante efetiva primeiro; escolher outra
 *   representante, voltar à escolha automática, retirar a carta da posição.
 * - "Colocar ou mover para cá" (ASSIGNABLE): cartas da coleção fora desta
 *   posição, com busca e "Mostrar mais"; carta de outra espécie pede confirmação.
 *
 * Toda resposta relê as duas listas (tokens e estado esperado novos); nada é
 * afirmado antes da resposta do servidor. Uma ação por vez no painel inteiro.
 */
export function SharedPokedexEditorPanel({
  collectionId,
  position,
  onClose,
}: {
  collectionId: string;
  position: PokedexPosition;
  onClose: (changed: boolean) => void;
}) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const uid = useId();
  const positionId = position.positionId.toLowerCase();
  const [here, setHere] = useState<List>({ status: "loading" });
  const [assignable, setAssignable] = useState<List>({ status: "loading" });
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState<Busy>({ kind: "idle" });
  const [feedback, setFeedback] = useState<Feedback>(null);
  const [confirm, setConfirm] = useState<PendingConfirmation | null>(null);
  const [disabled, setDisabled] = useState(false);
  const [blocked, setBlocked] = useState<string | null>(null);
  // E3-7a: sessão expirada — caminho fixo para entrar de novo (sem parâmetros na URL).
  const [blockedSignIn, setBlockedSignIn] = useState(false);
  const feedbackRef = useRef<HTMLDivElement>(null);
  // F3-6: "Retirar desta posição" pede confirmação (toque acidental no celular); presa à geração da lista.
  const [removeAsk, setRemoveAsk] = useState<{ token: string; generation: number } | null>(null);
  const confirmRef = useRef<HTMLDivElement>(null);
  const [sync, setSync] = useState<SyncState>("synced");
  // F3-3: a grade é atualizada pela página do servidor (router.refresh) logo depois da escrita
  // confirmada — inclui as posições de origem e de destino; o painel mostra "Atualizando…" enquanto isso.
  const [refreshingGrid, startGridRefresh] = useTransition();
  const changedRef = useRef(false);
  // Geração das listas: toda releitura invalida tokens, respostas atrasadas e confirmações anteriores.
  const generation = useRef(0);
  const alive = useRef(true);
  useEffect(() => () => void (alive.current = false), []);

  const read = useCallback(
    (scope: CopyScope, q: string, offset: number) =>
      readEditorPokedexCopies({ collectionId, positionId, scope, query: scope === "ASSIGNABLE" ? q : null, offset }).catch(() => ({ ok: false, reason: "unknown" }) as const),
    [collectionId, positionId],
  );

  /** Bloqueio de acesso: desliga as ações, descarta listas, tokens e confirmação (nova geração). */
  const block = useCallback((message: string, signIn = false) => {
    generation.current += 1;
    setDisabled(true);
    setBlocked(message);
    if (signIn) setBlockedSignIn(true);
    setConfirm(null);
    setRemoveAsk(null);
    setHere({ status: "blocked", message });
    setAssignable({ status: "blocked", message });
  }, []);

  const toList = useCallback(
    (r: Awaited<ReturnType<typeof read>>): List => {
      if (r.ok) return { status: "ready", page: r.page, loadingMore: false };
      const f = readFailure(r.reason);
      if (f.blocks) {
        // Depois do retorno (fora do setState em andamento): tudo some, não só esta lista.
        queueMicrotask(() => alive.current && block(f.message, r.reason === "not_authenticated"));
        return { status: "blocked", message: f.message };
      }
      return { status: "error", message: f.message, retry: f.retry };
    },
    [block],
  );

  /** Descarta tudo o que veio antes (tokens, confirmação) e relê as duas listas. true = ambas lidas. */
  const reloadAll = useCallback(
    async (q: string): Promise<boolean> => {
      const gen = ++generation.current;
      setConfirm(null);
      setRemoveAsk(null);
      setHere({ status: "loading" });
      setAssignable({ status: "loading" });
      const [h, a] = await Promise.all([read("AT_POSITION", "", 0), read("ASSIGNABLE", q, 0)]);
      if (!alive.current || gen !== generation.current) return false;
      setHere(toList(h));
      setAssignable(toList(a));
      return h.ok && a.ok;
    },
    [read, toList],
  );

  const refreshGrid = useCallback(() => startGridRefresh(() => router.refresh()), [router]);

  // Abertura e busca (com espera curta): a lista "Colocar ou mover" sempre recomeça do servidor.
  const firstLoad = useRef(true);
  useEffect(() => {
    if (firstLoad.current) {
      firstLoad.current = false;
      void reloadAll("");
      return;
    }
    const timer = window.setTimeout(() => {
      const gen = ++generation.current;
      setConfirm(null);
      setAssignable({ status: "loading" });
      void read("ASSIGNABLE", query.trim(), 0).then((r) => {
        if (alive.current && gen === generation.current) setAssignable(toList(r));
      });
    }, SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [query, read, reloadAll, toList]);

  const loadMore = async () => {
    if (assignable.status !== "ready" || assignable.loadingMore || !assignable.page.hasMore || isBusy(busy)) return;
    const gen = generation.current;
    const prev = assignable.page;
    setAssignable({ status: "ready", page: prev, loadingMore: true });
    const r = await read("ASSIGNABLE", query.trim(), prev.offset + prev.items.length);
    if (!alive.current || gen !== generation.current) return;
    if (!r.ok) {
      const f = readFailure(r.reason);
      if (f.blocks) return block(f.message, r.reason === "not_authenticated");
      setAssignable({ status: "ready", page: prev, loadingMore: false });
      setFeedback({ tone: "error", title: "Não conseguimos carregar mais cartas", text: f.message });
      return;
    }
    const merged = r.page.items.length > 0 ? mergeCopiesPages(prev, r.page) : null;
    if (!merged) {
      // Zero linhas depois da 1ª página ou ordem diferente: o estado mudou — recomeça do servidor.
      setFeedback({ tone: "warning", text: failurePolicy("state_changed").message });
      setSync(syncAfterReload(false, await reloadAll(query.trim())));
      return;
    }
    setAssignable({ status: "ready", page: merged, loadingMore: false });
  };

  /** Fluxo único depois de qualquer resposta de escrita (F3-3). */
  const run = async (intent: WriteIntent | null) => {
    if (!intent || !actionsEnabled({ busy, disabled, sync, loading: here.status === "loading" || assignable.status === "loading" })) return;
    const next = beginWrite(busy, intent);
    if (!next) return; // já há uma ação em andamento
    setBusy(next);
    setFeedback(null);
    const genAtStart = generation.current; // se a lista for relida durante a escrita, a confirmação não vale
    const res = await writeEditorPokedex(intent).catch(() => ({ ok: false, reason: "unknown" }) as const);
    if (!alive.current) return;
    const outcome: Outcome = res.ok ? { ok: true, changed: resultChanged(res.result) } : { ok: false, reason: res.reason === "disabled" ? "unavailable" : res.reason };
    const plan = planAfter(outcome);
    if (plan.confirmed) changedRef.current = true;
    if (res.ok) setFeedback({ tone: plan.confirmed ? "success" : "neutral", text: resultMessage(res.result) });
    else {
      const reason = outcome.ok ? "unknown" : outcome.reason;
      const reaction = reactToFailure(reason);
      setFeedback({ tone: reaction.tone, text: reaction.message, title: writeNoticeTitle(reason) });
    }
    setBusy({ kind: "idle" });
    // Foco no resultado: o botão clicado pode sumir com a releitura (F3-5, teclado e leitor de tela).
    // Pedido de confirmação: o foco vai para a pergunta (efeito abaixo), não para o aviso.
    if (!plan.askConfirmation) window.requestAnimationFrame(() => feedbackRef.current?.focus());
    if (plan.disable) {
      block(outcome.ok ? failurePolicy("unknown").message : failurePolicy(outcome.reason).message, !outcome.ok && outcome.reason === "not_authenticated");
      if (plan.refreshGrid) refreshGrid();
      return;
    }
    if (plan.askConfirmation) {
      // Nada foi gravado: a confirmação fica presa à intenção recusada (mesmo estado esperado) e a ESTA geração.
      setRemoveAsk(null);
      setConfirm(prepareConfirmation(collectionId, positionId, assignable.status === "ready" ? assignable.page : null, intent, genAtStart));
      return;
    }
    if (plan.dropTokens) setConfirm(null);
    if (plan.refreshGrid) refreshGrid();
    if (plan.reloadPanel) setSync(syncAfterReload(plan.confirmed, await reloadAll(query.trim())));
  };

  // F3-6: a pergunta de confirmação recebe o foco (lida pelo leitor de tela); NUNCA o botão de confirmar,
  // para que Enter ou um toque acidental não confirme sozinho.
  const askingKey = confirm ? `c:${confirm.intent.copyToken}:${confirm.generation}` : removeAsk ? `r:${removeAsk.token}:${removeAsk.generation}` : null;
  useEffect(() => {
    if (askingKey) window.requestAnimationFrame(() => confirmRef.current?.focus());
  }, [askingKey]);

  /** Atualização manual (visual pendente ou falha transitória): relê o painel e a grade; nunca repete a escrita. */
  const resync = async () => {
    if (isBusy(busy) || blocked) return;
    refreshGrid();
    const ok = await reloadAll(query.trim());
    if (alive.current) setSync(syncAfterReload(sync === "confirmed_stale", ok));
  };

  const close = () => {
    if (busy.kind === "writing") return;
    onClose(changedRef.current);
  };

  const herePage = here.status === "ready" ? here.page : null;
  const assignPage = assignable.status === "ready" ? assignable.page : null;
  const restore = restoreIntent(collectionId, positionId, herePage);
  const writing = busy.kind === "writing";
  const enabled = actionsEnabled({ busy, disabled, sync, loading: here.status === "loading" || assignable.status === "loading" });
  const actionsOff = !enabled;
  const liveConfirm = confirmationUsable(confirm, generation.current) ? confirm : null;
  const liveRemove = removeAsk && removeAsk.generation === generation.current ? removeAsk : null;
  const dex = `#${formatDex(position.number)}`;
  const artUrl = speciesArtworkUrl(position.artworkPath);
  const stateLine = positionStateLine(here.status === "ready" ? { status: "ready", total: here.page.total } : here.status === "loading" ? { status: "loading" } : { status: "error" });
  const syncText = blocked ? null : syncMessage(sync);

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && close()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${addStyles.panel} ${local.root}`}
          data-pkx-dialog=""
          aria-describedby={`${uid}-state`}
          onEscapeKeyDown={(event) => writing && event.preventDefault()}
          onPointerDownOutside={(event) => writing && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <div className={acervoStyles.drawerHeader}>
            <span className={styles.panelEyebrow}>Organizar a Pokédex</span>
            <DialogPrimitive.Close
              disabled={writing}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          <div className={`${addStyles.body} ${local.body}`}>
            <div className={styles.panelHero}>
              <div className={styles.panelArt} aria-hidden="true">
                {artUrl ? <SpeciesArtwork src={artUrl} priority={false} /> : <Pokeball className="text-foreground/10" strokeWidth={1.25} />}
              </div>
              <div>
                <DialogPrimitive.Title className={styles.panelTitle}>
                  <span className={styles.panelDex}>{dex}</span> <span className={styles.panelName}>{position.speciesName}</span>
                </DialogPrimitive.Title>
                <p id={`${uid}-state`} className={styles.panelState}>
                  {stateLine}
                </p>
              </div>
            </div>

            <p className="sr-only" role="status" aria-live="polite">
              {feedback && feedback.tone !== "error" ? feedback.text : ""}
            </p>
            <div ref={feedbackRef} tabIndex={-1} className="outline-none">
              {feedback ? (
                feedback.tone === "success" || feedback.tone === "neutral" ? (
                  <div className={styles.statusLine} aria-hidden="true">
                    <CheckCircle2 className="h-4 w-4 shrink-0" />
                    {feedback.text}
                  </div>
                ) : (
                  <Notice title={feedback.title ?? (feedback.tone === "warning" ? "Confira antes de continuar" : "Nada foi alterado")}>{feedback.text}</Notice>
                )
              ) : null}
              {blocked && feedback?.text !== blocked ? <Notice title="Ação indisponível">{blocked} As ações desta posição ficam desligadas.</Notice> : null}
              {blockedSignIn ? (
                <Button asChild variant="outline" size="sm" className="mt-2 min-h-11">
                  <Link href={SIGN_IN_PATH}>Entrar de novo</Link>
                </Button>
              ) : null}
            </div>
            {syncText ? (
              <div className={addStyles.notice} role="alert">
                <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                <div>
                  <p className={addStyles.noticeTitle}>{sync === "confirmed_stale" ? "Alteração confirmada" : "Visualização desatualizada"}</p>
                  <div className={addStyles.noticeText}>{syncText}</div>
                  <Button variant="outline" size="sm" className="mt-2 min-h-11" onClick={() => void resync()} disabled={isBusy(busy) || here.status === "loading"}>
                    <RefreshCw className="mr-1.5 h-4 w-4" aria-hidden="true" />
                    Atualizar
                  </Button>
                </div>
              </div>
            ) : null}
            {refreshingGrid ? (
              <p className={styles.panelSectionMeta} role="status">
                <Loader2 className={`mr-1.5 inline h-3.5 w-3.5 ${addStyles.spin}`} aria-hidden="true" />
                Atualizando a Pokédex da coleção…
              </p>
            ) : null}

            {/* ---- Nesta posição ---- */}
            <section className={styles.panelSection} aria-labelledby={`${uid}-here`} aria-busy={here.status === "loading"}>
              <div className={styles.panelSectionHead}>
                <h3 id={`${uid}-here`} className={styles.panelSectionTitle}>
                  Nesta posição
                </h3>
                {herePage && herePage.items.length > 0 ? (
                  <span className={styles.panelSectionMeta}>{herePage.items[0]?.representativeMode === "CHOSEN" ? "representante escolhida" : "representante automática"}</span>
                ) : null}
              </div>
              <ListBody list={here} empty={emptyListMessage("AT_POSITION", false)} onRetry={() => void resync()} retryDisabled={isBusy(busy)}>
                {(items) => (
                  <ul className={styles.copyList}>
                    {items.map((copy) => {
                      const choose = chooseIntent(collectionId, positionId, herePage, copy);
                      const unassign = unassignIntent(collectionId, positionId, herePage, copy);
                      const busyHere = busy.kind === "writing" && busy.token === copy.token;
                      const askingRemove = liveRemove?.token === copy.token;
                      return (
                        <CopyRow key={copy.token} copy={copy} representative={copy.isEffectiveRepresentative === true} meta={null}>
                          {choose && !askingRemove ? (
                            <button type="button" className={`${styles.copyAction} ${local.action}`} onClick={() => void run(choose)} disabled={actionsOff} aria-busy={busyHere && busy.intent === "choose"}>
                              {busyHere && busy.intent === "choose" ? "Salvando…" : "Mostrar na grade"}
                            </button>
                          ) : null}
                          {unassign && !askingRemove ? (
                            <button
                              type="button"
                              className={`${styles.copyAction} ${local.action}`}
                              data-tone="quiet"
                              onClick={() => {
                                setConfirm(null);
                                setRemoveAsk({ token: copy.token, generation: generation.current });
                              }}
                              disabled={actionsOff}
                              aria-haspopup="true"
                            >
                              Retirar desta posição
                            </button>
                          ) : null}
                          {unassign && askingRemove ? (
                            <div ref={confirmRef} tabIndex={-1} className={`${styles.confirm} ${local.confirmBlock}`} role="alertdialog" aria-labelledby={`${uid}-remove`} aria-describedby={`${uid}-remove-d`}>
                              <p id={`${uid}-remove`} className={styles.confirmTitle}>
                                Retirar {copy.cardName} de {dex} {position.speciesName}?
                              </p>
                              <p id={`${uid}-remove-d`} className={local.confirmLine}>
                                A carta continua na coleção, sem posição na Pokédex.{copy.isEffectiveRepresentative ? " A posição passa a usar outra carta na grade." : ""}
                              </p>
                              <div className={`${styles.confirmActions} ${local.confirmActions}`}>
                                <Button variant="outline" size="sm" onClick={() => setRemoveAsk(null)} disabled={writing}>
                                  Cancelar
                                </Button>
                                <Button size="sm" onClick={() => void run(liveRemove ? unassign : null)} disabled={actionsOff} aria-busy={busyHere && busy.intent === "unassign"}>
                                  {busyHere && busy.intent === "unassign" ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                                  Retirar da posição
                                </Button>
                              </div>
                            </div>
                          ) : null}
                        </CopyRow>
                      );
                    })}
                  </ul>
                )}
              </ListBody>
              {restore ? (
                <Button variant="outline" size="sm" className="mt-3 min-h-11" onClick={() => void run(restore)} disabled={actionsOff} aria-busy={busy.kind === "writing" && busy.intent === "restore"}>
                  {busy.kind === "writing" && busy.intent === "restore" ? <Loader2 className={`mr-1.5 h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                  Voltar à escolha automática
                </Button>
              ) : null}
            </section>

            {/* ---- Colocar ou mover para cá ---- */}
            <section className={styles.panelSection} aria-labelledby={`${uid}-add`} aria-busy={assignable.status === "loading"}>
              <div className={styles.panelSectionHead}>
                <h3 id={`${uid}-add`} className={styles.panelSectionTitle}>
                  Colocar ou mover para cá
                </h3>
                {assignPage ? <span className={styles.panelSectionMeta}>{formatCount(assignPage.total)} na coleção</span> : null}
              </div>
              <p className={addStyles.hint}>Cartas desta coleção que estão sem posição ou em outra posição da Pokédex.</p>
              <div className={`${addStyles.searchWrap} ${local.search}`}>
                <Search className={addStyles.searchIcon} aria-hidden="true" />
                <label htmlFor={`${uid}-q`} className="sr-only">
                  Buscar nas cartas da coleção por nome ou número do Pokémon
                </label>
                <Input
                  id={`${uid}-q`}
                  className={addStyles.searchInput}
                  placeholder="Nome ou número do Pokémon"
                  value={query}
                  maxLength={COPY_QUERY_MAX}
                  onChange={(event) => setQuery(event.target.value)}
                  autoComplete="off"
                  disabled={writing || blocked !== null}
                />
              </div>
              <ListBody list={assignable} empty={emptyListMessage("ASSIGNABLE", query.trim() !== "")} onRetry={() => void resync()} retryDisabled={isBusy(busy)}>
                {(items) => (
                  <>
                    <ul className={styles.copyList}>
                      {items.map((copy) => {
                        const move = moveIntent(collectionId, positionId, assignPage, copy);
                        const busyHere = busy.kind === "writing" && busy.token === copy.token;
                        const asking = liveConfirm !== null && liveConfirm.intent.copyToken === copy.token;
                        return (
                          <CopyRow key={copy.token} copy={copy} representative={false} meta={originLine(copy)}>
                            {move && !asking ? (
                              <button type="button" className={`${styles.copyAction} ${local.action}`} onClick={() => void run(move)} disabled={actionsOff} aria-busy={busyHere}>
                                {busyHere ? "Salvando…" : moveLabel(copy)}
                              </button>
                            ) : null}
                            {move && asking ? (
                              <div ref={confirmRef} tabIndex={-1} className={`${styles.confirm} ${local.confirmBlock}`} data-tone="warning" role="alertdialog" aria-labelledby={`${uid}-confirm`} aria-describedby={`${uid}-confirm-d`}>
                                <p id={`${uid}-confirm`} className={styles.confirmTitle}>
                                  {liveConfirm.intent.expectedPositionId === null ? "Colocar" : "Mover"} {liveConfirm.cardName} para {dex} {position.speciesName}?
                                </p>
                                <div id={`${uid}-confirm-d`}>
                                  <dl className={local.confirmWhere}>
                                    <dt>De</dt>
                                    <dd>{liveConfirm.fromLine}</dd>
                                    <dt>Para</dt>
                                    <dd>
                                      {dex} {position.speciesName}
                                    </dd>
                                  </dl>
                                  <p className={local.confirmLine}>
                                    O catálogo não registra esta carta como {position.speciesName}; ela fica marcada como exceção. Se a carta mudar de lugar antes da
                                    confirmação, nada é alterado.
                                  </p>
                                </div>
                                <div className={`${styles.confirmActions} ${local.confirmActions}`}>
                                  <Button variant="outline" size="sm" onClick={() => setConfirm(null)} disabled={writing}>
                                    Cancelar
                                  </Button>
                                  <Button size="sm" onClick={() => void run(confirmationUsable(confirm, generation.current) ? confirm.intent : null)} disabled={actionsOff} aria-busy={busyHere}>
                                    {busyHere ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                                    {liveConfirm.intent.expectedPositionId === null ? "Confirmar e colocar" : "Confirmar e mover"}
                                  </Button>
                                </div>
                              </div>
                            ) : null}
                          </CopyRow>
                        );
                      })}
                    </ul>
                    {assignPage?.hasMore ? (
                      <div className={styles.more}>
                        <span>
                          Mostrando {formatCount(items.length)} de {formatCount(assignPage.total)}
                        </span>
                        <Button variant="outline" className="min-h-11" onClick={() => void loadMore()} disabled={(assignable.status === "ready" && assignable.loadingMore) || writing} aria-busy={assignable.status === "ready" && assignable.loadingMore}>
                          {assignable.status === "ready" && assignable.loadingMore ? "Carregando…" : "Mostrar mais cartas"}
                        </Button>
                      </div>
                    ) : null}
                  </>
                )}
              </ListBody>
            </section>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function ListBody({
  list,
  empty,
  onRetry,
  retryDisabled,
  children,
}: {
  list: List;
  empty: string;
  onRetry: () => void;
  retryDisabled: boolean;
  children: (items: EditorPokedexCopy[]) => ReactNode;
}) {
  if (list.status === "loading") {
    return (
      <div className={addStyles.centerState} role="status">
        <Loader2 className={`h-5 w-5 ${addStyles.spin}`} aria-hidden="true" />
        Conferindo as cartas…
      </div>
    );
  }
  if (list.status === "blocked") return <p className={styles.emptyNote}>As cartas não estão disponíveis para você agora.</p>;
  if (list.status === "error") {
    return (
      <Notice title="Não conseguimos ler as cartas agora">
        {list.message}
        {list.retry ? (
          <Button variant="outline" size="sm" className="mt-2 min-h-11" onClick={onRetry} disabled={retryDisabled}>
            <RefreshCw className="mr-1.5 h-4 w-4" aria-hidden="true" />
            Tentar de novo
          </Button>
        ) : null}
      </Notice>
    );
  }
  if (list.page.items.length === 0) return <p className={styles.emptyNote}>{empty}</p>;
  return <>{children(list.page.items)}</>;
}

function CopyRow({ copy, representative, meta, children }: { copy: EditorPokedexCopy; representative: boolean; meta: string | null; children: ReactNode }) {
  const identity = [copy.setCode?.toUpperCase(), copy.collectorNumber].filter(Boolean).join(" · ");
  const attrs = [copy.variantLabel, copy.languageCode].filter(Boolean).join(" · ");
  const exception = copy.assignmentBasis === "USER_OVERRIDE";
  return (
    <li className={styles.copyItem} data-representative={representative ? "" : undefined} data-exception={exception ? "" : undefined}>
      <span className={styles.copyArt} aria-hidden="true">
        <CardArt src={cardFrontUrl(SUPABASE_URL, copy.imagePath)} alt="" name={copy.cardName} caption={identity} sizes="3.75rem" />
      </span>
      <div className={styles.copyBody}>
        <span className={`${styles.copyName} ${local.cardName}`}>{copy.cardName}</span>
        <span className={styles.copyMeta}>{[identity, attrs, meta].filter(Boolean).join(" · ")}</span>
        {representative || exception || !copy.speciesMatch ? (
          <span className={styles.copyBadges}>
            {representative ? (
              <span className={`${styles.badge} ${styles.badgeRep}`}>
                <Crown className="h-3 w-3" aria-hidden="true" />
                Na grade
              </span>
            ) : null}
            {exception || !copy.speciesMatch ? (
              <span className={`${styles.badge} ${styles.badgeException}`}>
                <Sparkles className="h-3 w-3" aria-hidden="true" />
                Outro Pokémon no catálogo
              </span>
            ) : null}
          </span>
        ) : null}
        <span className={`${styles.copyActions} ${local.actions}`}>{children}</span>
      </div>
    </li>
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
