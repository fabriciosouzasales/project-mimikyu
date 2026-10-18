"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { usePathname, useRouter } from "next/navigation";
import { type ReactNode, createContext, useCallback, useContext, useEffect, useId, useMemo, useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, ChevronLeft, ListChecks, Loader2, Minus, Plus, Search, Trash2, X } from "lucide-react";
import {
  type PickerPage,
  browseAcervoForCollection,
  collectAvailableCopies,
  linkCopiesToCollection,
  readGroupCopies,
} from "@/app/colecoes/colecoes/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { cardFrontUrl, formatCollectorNumber, formatCount, pluralize } from "@/lib/colecoes/acervo";
import { type CollectionFailure, collectionFailureMessage } from "@/lib/colecoes/colecoes";
import {
  FREE_SELECTION_MAX,
  type GroupCopy,
  type PickerGroup,
  type Selection,
  addNextCopy,
  copyStatus,
  copyStatusLabel,
  countCopies,
  groupKey,
  reconcileSelection,
  removeGroup,
  removeLastCopy,
  selectAllFree,
  selectAllFromGroups,
  selectionCount,
  selectionGroupCount,
  selectionIds,
  toggleCopy,
  versionLabel,
} from "@/lib/colecoes/free-collection";
import { CardArt } from "../acervo/card-art";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import freeStyles from "./free-collection.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SEARCH_DEBOUNCE_MS = 300;

/**
 * "Adicionar cartas do meu acervo" — Coleção livre (FREE-COLLECTION-FRONTEND-COMPLETION-01).
 *
 * Explorar → escolher exemplares → revisar → confirmar. Contratos reutilizados,
 * nenhum novo: 5159 (cartas do acervo, com "só disponíveis"), 5162 (exemplares
 * de uma carta e a coleção de cada um) e 5046 (vínculo).
 *
 * Regras de interface, espelhando o banco:
 * - só exemplares fora de qualquer coleção podem ser escolhidos; os demais
 *   aparecem com o motivo ("Em «Outra coleção»"), nunca são retirados de lá;
 * - nada é gravado antes da revisão e da confirmação;
 * - uma confirmação = uma chamada (até 500 exemplares): entra tudo ou nada;
 * - se o acervo mudou desde a escolha, o banco recusa e a seleção é relida e
 *   ajustada às claras — nunca trocada em silêncio;
 * - nenhuma carta muda de lugar físico; a coleção não ganha Set nem progresso.
 */
type PickerContextValue = { open: () => void };
const PickerContext = createContext<PickerContextValue | null>(null);

/**
 * Dono do painel. Envolve a página inteira da coleção: quando as primeiras
 * cartas entram e a página se atualiza (vazia → com cartas), o botão muda de
 * lugar, mas o painel aberto — e a confirmação "N cartas entraram" — continua.
 */
export function FreePickerProvider({
  collectionId,
  collectionName,
  autoOpen = false,
  children,
}: {
  collectionId: string;
  collectionName: string;
  /** Abre ao chegar (vindo da criação, `?adicionar=1`). */
  autoOpen?: boolean;
  children: ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(autoOpen);

  // Tira o `?adicionar=1` da URL depois de abrir: recarregar não reabre o painel.
  useEffect(() => {
    if (autoOpen) router.replace(pathname, { scroll: false });
  }, [autoOpen, pathname, router]);

  const value = useMemo(() => ({ open: () => setIsOpen(true) }), []);

  return (
    <PickerContext.Provider value={value}>
      {children}
      {isOpen ? <PickerPanel collectionId={collectionId} collectionName={collectionName} onClose={() => setIsOpen(false)} /> : null}
    </PickerContext.Provider>
  );
}

/** Botão "Adicionar cartas do meu acervo" — em qualquer ponto dentro do provider. */
export function FreePickerButton({ available, showCount = true }: { available: number | null; showCount?: boolean }) {
  const context = useContext(PickerContext);
  if (!context) return null;
  return (
    <Button onClick={context.open} className="min-h-11">
      <Plus className="h-4 w-4" aria-hidden="true" />
      Adicionar cartas do meu acervo
      {showCount && available !== null && available > 0 ? <span className="tabular-nums opacity-80">({formatCount(available)})</span> : null}
    </Button>
  );
}

/**
 * "+ Adicionar cartas (N)" da barra da galeria — mesmo padrão da coleção de Set
 * (botão baixo em pílula, sempre visível). Sem carta disponível no acervo, sem
 * provider (coleção arquivada) ou com a contagem indisponível: desabilitado e
 * sem ação.
 */
export function FreePickerBarButton({ available }: { available: number | null }) {
  const context = useContext(PickerContext);
  const count = available ?? 0;
  const empty = !context || count <= 0;
  return (
    <Button
      onClick={() => !empty && context?.open()}
      disabled={empty}
      size="sm"
      className="h-8 gap-1.5 rounded-full px-3.5 text-[0.8125rem]"
      title={empty ? "Nenhuma carta do seu acervo está disponível para adicionar agora" : undefined}
      aria-label={
        empty
          ? "Adicionar cartas — nenhuma carta disponível no seu acervo agora"
          : `Adicionar cartas do seu acervo a esta coleção (${formatCount(count)} disponíveis)`
      }
    >
      <Plus className="h-3.5 w-3.5" aria-hidden="true" />
      Adicionar cartas
      <span className="tabular-nums opacity-80">({formatCount(count)})</span>
    </Button>
  );
}

type View = { kind: "browse" } | { kind: "copies"; key: string } | { kind: "review" } | { kind: "done"; linked: number };
type Browse =
  | { status: "loading" }
  | { status: "error"; reason: CollectionFailure }
  | { status: "ready"; groups: PickerGroup[]; total: number; page: number; loadingMore: boolean; moreError: boolean };
type CopiesState = { status: "loading" } | { status: "error" } | { status: "ready"; copies: GroupCopy[] };
type Commit = { status: "idle" } | { status: "pending" } | { status: "error"; reason: CollectionFailure };

function PickerPanel({
  collectionId,
  collectionName,
  onClose,
}: {
  collectionId: string;
  collectionName: string;
  onClose: () => void;
}) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const searchId = useId();
  const setFilterId = useId();
  const [view, setView] = useState<View>({ kind: "browse" });
  const [query, setQuery] = useState("");
  const [debounced, setDebounced] = useState("");
  const [setCode, setSetCode] = useState<string>("");
  const [availableOnly, setAvailableOnly] = useState(true);
  const [sets, setSets] = useState<{ value: string; label: string }[]>([]);
  const [browse, setBrowse] = useState<Browse>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [copies, setCopiesState] = useState<Record<string, CopiesState>>({});
  const [selection, setSelectionState] = useState<Selection>({});
  // Espelhos síncronos: cliques rápidos e respostas assíncronas sempre partem do estado mais recente.
  const selectionRef = useRef<Selection>({});
  const copiesRef = useRef<Record<string, CopiesState>>({});
  const setSelection = useCallback((next: Selection) => {
    selectionRef.current = next;
    setSelectionState(next);
  }, []);
  const patchCopies = useCallback((key: string | null, value: CopiesState | null) => {
    copiesRef.current = key === null ? {} : { ...copiesRef.current, [key]: value as CopiesState };
    setCopiesState(copiesRef.current);
  }, []);
  const [commit, setCommit] = useState<Commit>({ status: "idle" });
  const [announce, setAnnounce] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [selectingAll, setSelectingAll] = useState(false);
  const groupsRef = useRef<Map<string, PickerGroup>>(new Map());
  const busy = commit.status === "pending";

  const count = selectionCount(selection);
  const groupsSelected = selectionGroupCount(selection);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(query.trim()), SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query]);

  // Primeira página a cada mudança de busca, Set ou "só disponíveis".
  useEffect(() => {
    let cancelled = false;
    setBrowse({ status: "loading" });
    browseAcervoForCollection({
      collectionId,
      query: debounced,
      setCode: setCode === "" ? null : setCode,
      availableOnly,
      page: 1,
      withSets: sets.length === 0,
    })
      .catch(() => ({ ok: false as const, reason: "unavailable" as const }))
      .then((result) => {
        if (cancelled) return;
        if (!result.ok) {
          setBrowse({ status: "error", reason: result.reason });
          return;
        }
        if (result.sets && result.sets.length > 0) setSets(result.sets);
        remember(result);
        setBrowse({ status: "ready", groups: result.groups, total: result.totalGroups, page: 1, loadingMore: false, moreError: false });
      });
    return () => {
      cancelled = true;
    };
    // `sets` só decide se pede a lista de Sets uma vez — não deve refazer a busca.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collectionId, debounced, setCode, availableOnly, attempt]);

  function remember(page: PickerPage) {
    for (const group of page.groups) groupsRef.current.set(groupKey(group), group);
  }

  const loadMore = async () => {
    if (browse.status !== "ready" || browse.loadingMore) return;
    const nextPage = browse.page + 1;
    setBrowse({ ...browse, loadingMore: true, moreError: false });
    const result = await browseAcervoForCollection({
      collectionId,
      query: debounced,
      setCode: setCode === "" ? null : setCode,
      availableOnly,
      page: nextPage,
      withSets: false,
    }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    setBrowse((current) => {
      if (current.status !== "ready") return current;
      if (!result.ok) return { ...current, loadingMore: false, moreError: true };
      remember(result);
      return {
        status: "ready",
        groups: [...current.groups, ...result.groups.filter((group) => !current.groups.some((g) => groupKey(g) === groupKey(group)))],
        total: result.totalGroups,
        page: nextPage,
        loadingMore: false,
        moreError: false,
      };
    });
  };

  const ensureCopies = useCallback(
    async (group: PickerGroup, force = false): Promise<GroupCopy[] | null> => {
      const key = groupKey(group);
      const cached = copiesRef.current[key];
      if (!force && cached?.status === "ready") return cached.copies;
      patchCopies(key, { status: "loading" });
      const result = await readGroupCopies({ cardVariantId: group.cardVariantId, languageCode: group.languageCode }).catch(() => ({
        ok: false as const,
        reason: "unavailable" as const,
      }));
      if (!result.ok) {
        patchCopies(key, { status: "error" });
        return null;
      }
      patchCopies(key, { status: "ready", copies: result.copies });
      return result.copies;
    },
    [patchCopies],
  );

  const addOne = async (group: PickerGroup) => {
    setNotice(null);
    const list = await ensureCopies(group);
    if (!list) {
      setAnnounce(`Não conseguimos abrir os exemplares de ${group.cardName}. Tente de novo.`);
      return;
    }
    const change = addNextCopy(selectionRef.current, group, list, collectionId);
    if (change.ok) {
      setSelection(change.selection);
      const n = change.selection[groupKey(group)]?.ids.length ?? 0;
      setAnnounce(`${group.cardName} escolhida — ${pluralize(n, "exemplar", "exemplares")}.`);
    } else if (change.reason === "limit") {
      setNotice(`Cabem até ${formatCount(FREE_SELECTION_MAX)} exemplares por vez. Adicione estes e continue em seguida.`);
    } else {
      setAnnounce(`Todos os exemplares disponíveis de ${group.cardName} já estão escolhidos.`);
    }
  };

  const removeOne = (group: PickerGroup) => {
    setSelection(removeLastCopy(selectionRef.current, groupKey(group)));
    setAnnounce(`Um exemplar de ${group.cardName} a menos.`);
  };

  const toggleOne = (group: PickerGroup, list: GroupCopy[], id: string) => {
    const change = toggleCopy(selectionRef.current, group, list, id, collectionId);
    if (change.ok) setSelection(change.selection);
    else if (change.reason === "limit") setNotice(`Cabem até ${formatCount(FREE_SELECTION_MAX)} exemplares por vez.`);
  };

  const chooseAllFree = (group: PickerGroup, list: GroupCopy[]) => {
    const result = selectAllFree(selectionRef.current, group, list, collectionId);
    setSelection(result.selection);
    if (result.limited) setNotice(`Cabem até ${formatCount(FREE_SELECTION_MAX)} exemplares por vez.`);
  };

  /** Todas as cartas disponíveis da busca/Set atuais, todos os exemplares livres de cada uma. */
  const selectEverything = async () => {
    if (selectingAll) return;
    setSelectingAll(true);
    setNotice(null);
    const result = await collectAvailableCopies({ query: debounced, setCode: setCode === "" ? null : setCode }).catch(() => ({
      ok: false as const,
      reason: "unavailable" as const,
    }));
    setSelectingAll(false);
    if (!result.ok) {
      setNotice(`Não conseguimos selecionar todas agora. ${collectionFailureMessage(result.reason)}`);
      return;
    }
    for (const entry of result.entries) {
      groupsRef.current.set(groupKey(entry.group), entry.group);
      patchCopies(groupKey(entry.group), { status: "ready", copies: entry.copies });
    }
    const change = selectAllFromGroups(selectionRef.current, result.entries, collectionId);
    setSelection(change.selection);
    setAnnounce(`${pluralize(change.added, "exemplar escolhido", "exemplares escolhidos")}.`);
    if (change.limited || result.truncated) {
      setNotice(
        `Cabem até ${formatCount(FREE_SELECTION_MAX)} exemplares por vez — escolhemos os primeiros. Adicione estes e selecione o restante em seguida.`,
      );
    }
  };

  const clearSelection = () => {
    setSelection({});
    setNotice(null);
    setAnnounce("Seleção limpa.");
  };

  const openCopies = (group: PickerGroup) => {
    setNotice(null);
    groupsRef.current.set(groupKey(group), group);
    void ensureCopies(group);
    setView({ kind: "copies", key: groupKey(group) });
  };

  const confirm = async () => {
    if (busy || count === 0) return;
    setCommit({ status: "pending" });
    setNotice(null);
    const result = await linkCopiesToCollection({ collectionId, physicalCardIds: selectionIds(selectionRef.current) }).catch(() => ({
      ok: false as const,
      reason: "unavailable" as const,
    }));
    if (result.ok) {
      setCommit({ status: "idle" });
      setView({ kind: "done", linked: result.linked });
      setSelection({});
      patchCopies(null, null);
      router.refresh();
      return;
    }
    setCommit({ status: "error", reason: result.reason });
    if (result.reason === "already_linked") await reconcileAll();
  };

  /** Relê os exemplares de cada carta escolhida e tira o que deixou de estar livre. */
  const reconcileAll = async () => {
    const entries = Object.entries(selectionRef.current);
    let next: Selection = selectionRef.current;
    let here = 0;
    let elsewhere = 0;
    let gone = 0;
    for (const [key, entry] of entries) {
      const list = await ensureCopies(entry.group, true);
      if (!list) continue;
      const result = reconcileSelection(next, key, list, collectionId);
      next = result.selection;
      here += result.here;
      elsewhere += result.elsewhere;
      gone += result.gone;
    }
    setSelection(next);
    const parts: string[] = [];
    if (here > 0) parts.push(`${pluralize(here, "exemplar já estava", "exemplares já estavam")} nesta coleção`);
    if (elsewhere > 0) parts.push(`${pluralize(elsewhere, "exemplar entrou", "exemplares entraram")} em outra coleção`);
    if (gone > 0) parts.push(`${pluralize(gone, "exemplar não está", "exemplares não estão")} mais no acervo`);
    setNotice(
      parts.length > 0
        ? `O acervo mudou desde a escolha: ${parts.join("; ")}. Eles saíram da seleção — nada foi gravado. Revise e confirme de novo.`
        : "Nada foi gravado. Revise a seleção e confirme de novo.",
    );
    if (here > 0) router.refresh();
  };

  const close = () => {
    if (!busy) onClose();
  };

  const title =
    view.kind === "review" ? "Revisar cartas" : view.kind === "done" ? "Cartas adicionadas" : "Adicionar cartas do meu acervo";

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && close()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${addStyles.panel} ${freeStyles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <div className={acervoStyles.drawerHeader}>
            <div className="min-w-0">
              <DialogPrimitive.Title className={addStyles.panelTitle}>{title}</DialogPrimitive.Title>
              <p className="truncate text-xs text-muted-foreground">{collectionName}</p>
            </div>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          <p className="sr-only" aria-live="polite">
            {announce}
          </p>

          {view.kind === "done" ? (
            <DoneView
              linked={view.linked}
              collectionName={collectionName}
              onMore={() => {
                setView({ kind: "browse" });
                setAttempt((n) => n + 1);
              }}
              onClose={onClose}
            />
          ) : view.kind === "review" ? (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.reviewHead}>
                  <span className={addStyles.reviewCount}>{formatCount(count)}</span>
                  <span className={addStyles.reviewLabel}>
                    {count === 1 ? "exemplar entra" : "exemplares entram"} em <strong>{collectionName}</strong>
                    {groupsSelected > 1 ? ` — ${formatCount(groupsSelected)} cartas diferentes` : ""}.
                  </span>
                </div>
                <p className={addStyles.reviewNote}>
                  As cartas continuam no seu acervo, no mesmo lugar — a coleção só passa a reuni-las. Nenhuma sai de outra coleção.
                </p>
                {count === 0 ? (
                  <p className={addStyles.reviewNote}>A seleção ficou vazia. Volte e escolha as cartas.</p>
                ) : (
                  <ul className={freeStyles.reviewLines} aria-label="Cartas escolhidas">
                    {Object.entries(selection).map(([key, entry]) => (
                      <ReviewLine
                        key={key}
                        entry={entry}
                        copies={copies[key]?.status === "ready" ? (copies[key] as { copies: GroupCopy[] }).copies : null}
                        disabled={busy}
                        onRemove={() => setSelection(removeGroup(selectionRef.current, key))}
                      />
                    ))}
                  </ul>
                )}
                <div aria-live="polite">
                  {notice ? <Notice title="A seleção foi ajustada">{notice}</Notice> : null}
                  {commit.status === "error" && commit.reason !== "already_linked" ? (
                    <Notice title="Nenhuma carta foi adicionada">{collectionFailureMessage(commit.reason)}</Notice>
                  ) : null}
                </div>
              </div>
              <Footer lead={pluralize(count, "exemplar", "exemplares")}>
                <Button variant="outline" onClick={() => setView({ kind: "browse" })} disabled={busy}>
                  Voltar
                </Button>
                <Button onClick={() => void confirm()} disabled={busy || count === 0} aria-busy={busy}>
                  {busy ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                  {busy ? "Adicionando…" : `Adicionar ${formatCount(count)} à coleção`}
                </Button>
              </Footer>
            </>
          ) : view.kind === "copies" ? (
            <CopiesView
              group={groupsRef.current.get(view.key) ?? null}
              state={copies[view.key]}
              selection={selection}
              collectionId={collectionId}
              notice={notice}
              onBack={() => {
                setNotice(null);
                setView({ kind: "browse" });
              }}
              onRetry={(group) => void ensureCopies(group, true)}
              onToggle={toggleOne}
              onSelectAll={chooseAllFree}
              footer={
                <Footer lead={count > 0 ? pluralize(count, "exemplar escolhido", "exemplares escolhidos") : null}>
                  <Button variant="outline" onClick={() => setView({ kind: "browse" })}>
                    Escolher mais cartas
                  </Button>
                  <Button onClick={() => setView({ kind: "review" })} disabled={count === 0}>
                    Revisar
                  </Button>
                </Footer>
              }
            />
          ) : (
            <>
              <div className={addStyles.body}>
                <div className={freeStyles.toolbar}>
                  <div className={freeStyles.toolbarField}>
                    <label htmlFor={searchId} className={freeStyles.toolbarLabel}>
                      Buscar no seu acervo
                    </label>
                    <div className={addStyles.searchWrap}>
                      <Search className={addStyles.searchIcon} aria-hidden="true" />
                      <Input
                        id={searchId}
                        type="search"
                        value={query}
                        onChange={(event) => setQuery(event.target.value)}
                        placeholder="Nome ou número (58/102)"
                        autoComplete="off"
                        maxLength={100}
                        className={addStyles.searchInput}
                      />
                    </div>
                  </div>
                  <div className={freeStyles.toolbarField}>
                    <label htmlFor={setFilterId} className={freeStyles.toolbarLabel}>
                      Set
                    </label>
                    <Select id={setFilterId} value={setCode} onChange={(event) => setSetCode(event.target.value)} className="h-11">
                      <option value="">Todos os Sets</option>
                      {sets.map((option) => (
                        <option key={option.value} value={option.value}>
                          {option.label}
                        </option>
                      ))}
                    </Select>
                  </div>
                </div>
                <div className={freeStyles.toolsRow}>
                  <label className={freeStyles.toggle}>
                    <input type="checkbox" checked={availableOnly} onChange={(event) => setAvailableOnly(event.target.checked)} />
                    Só cartas disponíveis
                  </label>
                  <span className={freeStyles.selectTools}>
                    <span className={freeStyles.statusLine} aria-live="polite">
                      {browse.status === "loading"
                        ? "Procurando no seu acervo…"
                        : browse.status === "ready"
                          ? browse.total === 0
                            ? ""
                            : `${pluralize(browse.total, "carta diferente", "cartas diferentes")}`
                          : ""}
                    </span>
                    {count > 0 ? (
                      <Button variant="ghost" size="sm" onClick={clearSelection} disabled={selectingAll}>
                        Limpar seleção
                      </Button>
                    ) : null}
                    {availableOnly && browse.status === "ready" && browse.total > 0 ? (
                      <Button variant="outline" size="sm" onClick={() => void selectEverything()} disabled={selectingAll} aria-busy={selectingAll}>
                        {selectingAll ? (
                          <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" />
                        ) : (
                          <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                        )}
                        {selectingAll ? "Selecionando…" : "Selecionar todas"}
                      </Button>
                    ) : null}
                  </span>
                </div>

                {notice ? <Notice title="Limite da seleção">{notice}</Notice> : null}

                {browse.status === "loading" ? (
                  <ul className={freeStyles.pickerGrid} aria-hidden="true">
                    {Array.from({ length: 8 }, (_, index) => (
                      <li key={index}>
                        <span className={`${acervoStyles.art} ${acervoStyles.skeletonArt} ${freeStyles.pickFrame}`} />
                      </li>
                    ))}
                  </ul>
                ) : browse.status === "error" ? (
                  <Notice title="Não conseguimos abrir o seu acervo">
                    {collectionFailureMessage(browse.reason)}
                    <Button variant="outline" size="sm" className="mt-2" onClick={() => setAttempt((n) => n + 1)}>
                      Tentar novamente
                    </Button>
                  </Notice>
                ) : browse.groups.length === 0 ? (
                  <BrowseEmpty
                    filtered={debounced !== "" || setCode !== ""}
                    availableOnly={availableOnly}
                    onShowAll={() => setAvailableOnly(false)}
                  />
                ) : (
                  <>
                    <ul className={freeStyles.pickerGrid} aria-label="Cartas do seu acervo">
                      {browse.groups.map((group) => {
                        const key = groupKey(group);
                        const state = copies[key];
                        const list = state?.status === "ready" ? state.copies : null;
                        return (
                          <li key={key}>
                            <PickTile
                              group={group}
                              picked={selection[key]?.ids.length ?? 0}
                              counts={list ? countCopies(list, collectionId) : null}
                              availableOnly={availableOnly}
                              loading={state?.status === "loading"}
                              failed={state?.status === "error"}
                              onAdd={() => void addOne(group)}
                              onRemove={() => removeOne(group)}
                              onDetails={() => openCopies(group)}
                            />
                          </li>
                        );
                      })}
                    </ul>
                    {browse.groups.length < browse.total ? (
                      <div className={freeStyles.more}>
                        <Button variant="outline" onClick={() => void loadMore()} disabled={browse.loadingMore}>
                          {browse.loadingMore ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                          {browse.moreError ? "Tentar carregar mais" : "Mostrar mais cartas"}
                        </Button>
                      </div>
                    ) : null}
                  </>
                )}
              </div>
              <Footer
                lead={
                  count > 0
                    ? `${pluralize(count, "exemplar", "exemplares")}${groupsSelected > 1 ? ` · ${pluralize(groupsSelected, "carta", "cartas")}` : ""}`
                    : "Toque numa carta para escolher"
                }
              >
                <Button variant="outline" onClick={close}>
                  Cancelar
                </Button>
                <Button onClick={() => setView({ kind: "review" })} disabled={count === 0}>
                  Revisar{count > 0 ? ` (${formatCount(count)})` : ""}
                </Button>
              </Footer>
            </>
          )}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function caption(group: Pick<PickerGroup, "cardSetCode" | "collectorNumber" | "collectorTotal">): string {
  return `${group.cardSetCode.toUpperCase()} · ${formatCollectorNumber(group.collectorNumber, group.collectorTotal)}`;
}

function PickTile({
  group,
  picked,
  counts,
  availableOnly,
  loading,
  failed,
  onAdd,
  onRemove,
  onDetails,
}: {
  group: PickerGroup;
  picked: number;
  counts: { free: number; here: number; elsewhere: number } | null;
  availableOnly: boolean;
  loading: boolean;
  failed: boolean;
  onAdd: () => void;
  onRemove: () => void;
  onDetails: () => void;
}) {
  // Livres conhecidos: exatos depois de abrir os exemplares; antes disso, a contagem da lista
  // só é "livres" quando a lista é "só disponíveis".
  const free = counts ? counts.free : availableOnly ? group.copies : null;
  const unavailable = free === 0;
  const version = versionLabel(group.isDefaultVariant, group.variantLabel);
  const text = caption(group);
  const availability =
    free === null
      ? pluralize(group.copies, "exemplar no acervo", "exemplares no acervo")
      : free === 0
        ? counts && counts.here > 0 && counts.elsewhere === 0
          ? "Já está nesta coleção"
          : "Em outra coleção"
        : pluralize(free, "disponível", "disponíveis");
  const spoken = [group.cardName, text, version, group.languageName, availability, picked > 0 ? `${picked} escolhida(s)` : null]
    .filter(Boolean)
    .join(", ");

  return (
    <div className={freeStyles.pick} data-unavailable={unavailable || undefined}>
      <button
        type="button"
        className={freeStyles.pickArt}
        data-selected={picked > 0 || undefined}
        onClick={unavailable ? onDetails : onAdd}
        aria-label={unavailable ? `${spoken}. Ver onde estão os exemplares` : `Escolher ${spoken}`}
        aria-busy={loading || undefined}
      >
        <span className={`${acervoStyles.art} ${freeStyles.pickFrame}`}>
          <CardArt
            src={cardFrontUrl(SUPABASE_URL, group.imagePath)}
            alt=""
            name={group.cardName}
            caption={text}
            sizes="(max-width: 767px) 45vw, 9rem"
          />
        </span>
        {picked > 0 ? (
          <span className={freeStyles.pickCount} aria-hidden="true">
            <CheckCircle2 className="h-3.5 w-3.5" />
            {formatCount(picked)}
          </span>
        ) : null}
        {!unavailable ? (
          <span className={freeStyles.pickAdd} aria-hidden="true">
            {loading ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} /> : <Plus className="h-4 w-4" />}
          </span>
        ) : null}
      </button>
      <div className={freeStyles.pickMeta}>
        <div className={freeStyles.pickName} aria-hidden="true">
          {group.cardName}
        </div>
        <div className={freeStyles.pickSub} aria-hidden="true">
          <span>{text}</span>
          {!group.isDefaultVariant ? <span className={acervoStyles.tag}>{version}</span> : null}
          <span className={acervoStyles.tag}>{group.languageCode}</span>
        </div>
        <div className={freeStyles.pickAvail} data-tone={unavailable ? "none" : undefined} aria-hidden="true">
          {failed ? "Não conseguimos abrir os exemplares" : availability}
        </div>
        <div className={freeStyles.pickControls}>
          {picked > 0 ? (
            <div className={freeStyles.stepGroup} role="group" aria-label={`Exemplares de ${group.cardName}`}>
              <button type="button" className={freeStyles.stepBtn} onClick={onRemove} aria-label={`Um exemplar a menos de ${group.cardName}`}>
                <Minus className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
              <span className={freeStyles.stepValue} aria-live="polite">
                {formatCount(picked)}
              </span>
              <button
                type="button"
                className={freeStyles.stepBtn}
                onClick={onAdd}
                disabled={free !== null && picked >= free}
                aria-label={`Mais um exemplar de ${group.cardName}`}
              >
                <Plus className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            </div>
          ) : (
            <span />
          )}
          <button type="button" className={freeStyles.linkBtn} onClick={onDetails} aria-label={`Escolher exemplares de ${group.cardName}`}>
            <ListChecks className="mr-1 inline h-3.5 w-3.5" aria-hidden="true" />
            Exemplares
          </button>
        </div>
      </div>
    </div>
  );
}

function CopiesView({
  group,
  state,
  selection,
  collectionId,
  notice,
  onBack,
  onRetry,
  onToggle,
  onSelectAll,
  footer,
}: {
  group: PickerGroup | null;
  state: CopiesState | undefined;
  selection: Selection;
  collectionId: string;
  notice: string | null;
  onBack: () => void;
  onRetry: (group: PickerGroup) => void;
  onToggle: (group: PickerGroup, copies: GroupCopy[], id: string) => void;
  onSelectAll: (group: PickerGroup, copies: GroupCopy[]) => void;
  footer: ReactNode;
}) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => headingRef.current?.focus(), []);
  const dateFormat = useMemo(() => new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" }), []);

  if (!group) {
    return (
      <>
        <div className={addStyles.body}>
          <Notice title="Carta não encontrada">Volte e escolha a carta de novo.</Notice>
        </div>
        {footer}
      </>
    );
  }

  const key = groupKey(group);
  const chosen = selection[key]?.ids ?? [];
  const list = state?.status === "ready" ? state.copies : null;
  const counts = list ? countCopies(list, collectionId) : null;

  return (
    <>
      <div className={addStyles.body}>
        <button type="button" className={freeStyles.back} onClick={onBack}>
          <ChevronLeft className="h-4 w-4" aria-hidden="true" />
          Voltar às cartas
        </button>
        <div className={freeStyles.copiesHead}>
          <span className={`${acervoStyles.art} ${freeStyles.pickFrame}`}>
            <CardArt src={cardFrontUrl(SUPABASE_URL, group.imagePath)} alt="" name={group.cardName} caption={caption(group)} sizes="7rem" />
          </span>
          <div className="min-w-0">
            <h3 ref={headingRef} tabIndex={-1} className={freeStyles.copiesTitle}>
              {group.cardName}
            </h3>
            <p className={freeStyles.copiesSub}>
              {group.cardSetName} · {formatCollectorNumber(group.collectorNumber, group.collectorTotal)}
            </p>
            <p className={freeStyles.copiesSub}>
              {versionLabel(group.isDefaultVariant, group.variantLabel)} · {group.languageName}
            </p>
            {counts && counts.free > 0 ? (
              <div className={freeStyles.copiesActions}>
                <Button variant="outline" size="sm" onClick={() => list && onSelectAll(group, list)} disabled={chosen.length >= counts.free}>
                  Escolher {counts.free === 1 ? "o disponível" : `os ${formatCount(counts.free)} disponíveis`}
                </Button>
              </div>
            ) : null}
          </div>
        </div>

        {notice ? <Notice title="Limite da seleção">{notice}</Notice> : null}

        {!state || state.status === "loading" ? (
          <div className={addStyles.centerState} role="status">
            <Loader2 className={`h-5 w-5 ${addStyles.spin}`} aria-hidden="true" />
            Abrindo os exemplares…
          </div>
        ) : state.status === "error" ? (
          <Notice title="Não conseguimos abrir os exemplares">
            Nada foi alterado.
            <Button variant="outline" size="sm" className="mt-2" onClick={() => onRetry(group)}>
              Tentar novamente
            </Button>
          </Notice>
        ) : state.copies.length === 0 ? (
          <Notice title="Esta carta não está mais no seu acervo">Volte e escolha outra carta.</Notice>
        ) : (
          <fieldset>
            <legend className={addStyles.sectionTitle}>
              Seus exemplares
              {counts && counts.free < state.copies.length ? (
                <span className="font-normal text-muted-foreground">
                  {" "}
                  — {pluralize(counts.free, "disponível", "disponíveis")} de {formatCount(state.copies.length)}
                </span>
              ) : null}
            </legend>
            <ul className={freeStyles.copyList}>
              {state.copies.map((copy) => {
                const status = copyStatus(copy, collectionId);
                const checked = chosen.includes(copy.physicalCardId);
                const disabled = status !== "free";
                return (
                  <li key={copy.physicalCardId}>
                    <label className={freeStyles.copyRow} data-checked={checked || undefined} data-disabled={disabled || undefined}>
                      <input
                        type="checkbox"
                        checked={checked}
                        disabled={disabled}
                        onChange={() => onToggle(group, state.copies, copy.physicalCardId)}
                        aria-describedby={`${copy.physicalCardId}-status`}
                      />
                      <span className="min-w-0">
                        <span className={`${freeStyles.copyTitle} block`}>Exemplar {formatCount(copy.copyNumber)}</span>
                        <span className={`${freeStyles.copyFacts} block`}>
                          {copy.addedAt ? `No acervo desde ${dateFormat.format(new Date(copy.addedAt))}` : null}
                          {copy.storageName ? ` · ${copy.storageName}` : null}
                        </span>
                      </span>
                      <span id={`${copy.physicalCardId}-status`} className={freeStyles.copyStatus} data-status={status}>
                        {copyStatusLabel(status, copy.collectionName)}
                      </span>
                    </label>
                  </li>
                );
              })}
            </ul>
          </fieldset>
        )}
        {counts && counts.free === 0 && list && list.length > 0 ? (
          <p className={addStyles.reviewNote}>
            Uma carta física fica em uma coleção por vez. Para trazê-la para cá, retire-a da coleção onde está — ou use outro
            exemplar.
          </p>
        ) : null}
      </div>
      {footer}
    </>
  );
}

function ReviewLine({
  entry,
  copies,
  disabled,
  onRemove,
}: {
  entry: { group: PickerGroup; ids: string[] };
  copies: GroupCopy[] | null;
  disabled: boolean;
  onRemove: () => void;
}) {
  const { group, ids } = entry;
  const numbers = copies
    ? ids
        .map((id) => copies.find((copy) => copy.physicalCardId === id)?.copyNumber)
        .filter((n): n is number => typeof n === "number")
        .sort((a, b) => a - b)
    : [];
  return (
    <li className={freeStyles.reviewLine}>
      <span className={`${acervoStyles.art} ${addStyles.thumb} ${freeStyles.pickFrame}`}>
        <CardArt src={cardFrontUrl(SUPABASE_URL, group.imagePath)} alt="" name={group.cardName} caption={caption(group)} sizes="3rem" />
      </span>
      <div className="min-w-0">
        <p className={addStyles.resultName}>{group.cardName}</p>
        <p className={addStyles.resultMeta}>
          {caption(group)} · {versionLabel(group.isDefaultVariant, group.variantLabel)} · {group.languageName}
        </p>
        <p className={freeStyles.reviewCopies}>
          {pluralize(ids.length, "exemplar", "exemplares")}
          {numbers.length > 0 ? ` — nº ${numbers.join(", ")}` : ""}
        </p>
      </div>
      <button type="button" className={addStyles.iconButton} onClick={onRemove} disabled={disabled} aria-label={`Tirar ${group.cardName} da seleção`}>
        <Trash2 className="h-4 w-4" aria-hidden="true" />
      </button>
    </li>
  );
}

function BrowseEmpty({ filtered, availableOnly, onShowAll }: { filtered: boolean; availableOnly: boolean; onShowAll: () => void }) {
  return (
    <div className={addStyles.done} role="status">
      <h3 className={addStyles.doneTitle}>
        {filtered ? "Nenhuma carta encontrada" : availableOnly ? "Nenhuma carta disponível agora" : "Seu acervo ainda está vazio"}
      </h3>
      <p className={addStyles.doneText}>
        {filtered
          ? "Tente outro nome, número ou Set."
          : availableOnly
            ? "Todas as cartas do seu acervo já estão em alguma coleção. Registre cartas novas em Meu acervo, ou veja onde estão as atuais."
            : "Registre suas cartas em Meu acervo para reuni-las aqui."}
      </p>
      {availableOnly && !filtered ? (
        <Button variant="outline" onClick={onShowAll} className="mt-3">
          Ver todas as cartas do acervo
        </Button>
      ) : null}
    </div>
  );
}

function DoneView({
  linked,
  collectionName,
  onMore,
  onClose,
}: {
  linked: number;
  collectionName: string;
  onMore: () => void;
  onClose: () => void;
}) {
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
            {linked === 1 ? `1 carta entrou em ${collectionName}` : `${formatCount(linked)} cartas entraram em ${collectionName}`}
          </h2>
          <p className={addStyles.doneText}>Elas continuam no seu acervo, no mesmo lugar. A coleção já está atualizada.</p>
        </div>
      </div>
      <Footer>
        <Button variant="outline" onClick={onMore}>
          Adicionar mais cartas
        </Button>
        <Button onClick={onClose}>Ver a coleção</Button>
      </Footer>
    </>
  );
}

function Footer({ lead, children }: { lead?: string | null; children: ReactNode }) {
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
