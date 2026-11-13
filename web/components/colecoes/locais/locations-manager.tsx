"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import {
  type FormEvent,
  type ReactNode,
  createContext,
  useContext,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  useTransition,
} from "react";
import { ArrowLeft, ArrowRight, BookOpen, ChevronRight, ClipboardList, Loader2, Lock, MapPin, MoreHorizontal, Pencil, Plus, ScanSearch, Search, Star, Trash2, X } from "lucide-react";
import Link from "next/link";
import { createStorageLocation, deleteStorageLocation, readCardLocations, readCardSearch, readLocationContents, updateStorageLocation } from "@/app/colecoes/locais/actions";
import { LocationInventoryOverlay } from "@/components/reports/location-inventory-overlay";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { Dialog, DialogBody, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import {
  cardFrontUrl,
  formatCollectorNumber,
  formatCount,
  languageLabel,
  pluralize,
  storageMatchAccessible,
  storageMatchLabel,
  variantName,
  variantTag,
} from "@/lib/colecoes/acervo";
import { binderHref } from "@/lib/colecoes/binder";
import { collectionHref } from "@/lib/colecoes/colecoes";
import type { AcervoItem } from "@/lib/colecoes/acervo-queries";
import type { CardLocations, LocationContents } from "@/lib/colecoes/storage-locations-queries";
import { type ConditionTally, conditionDistributionAccessible, conditionDistributionText, conditionParts } from "@/lib/colecoes/condition-distribution";
import {
  LOCATION_SORT_OPTIONS,
  type LocationKindFilter,
  type LocationSort,
  STORAGE_NAME_MAX,
  type StorageFailure,
  type StorageKind,
  type StorageLocation,
  kindOptionsFor,
  acervoShareText,
  acervoShareWidth,
  type CardIdentity,
  cardsCopiesLabel,
  exploreLocations,
  findLocatedItem,
  groupBySet,
  kindFilterOptions,
  normalizeStorageName,
  previewRarityLabel,
  storageCardCountLabel,
  storageDefaultLabel,
  storageDeleteBlock,
  splitLocationCode,
  storageDeleteBlockMessage,
  storageEditChanged,
  storageFailureMessage,
  storageSuccessMessage,
} from "@/lib/colecoes/storage-locations";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import manageStyles from "../colecoes/collection-manage.module.css";
import styles from "./locais.module.css";
import { StorageGlyph } from "./storage-glyph";

/**
 * Meus locais (WHERE-02 FRONTEND IMPLEMENTATION-01) — gestão dos lugares
 * físicos onde o colecionador guarda cartas.
 *
 * Princípio: o local pertence a cada exemplar (C-58). O local padrão de uma
 * coleção é só uma preferência (NS-15) — nada aqui coloca, move ou tira carta
 * de lugar, nem muda o local padrão de coleção.
 *
 * Estrutura: o servidor lê tudo (5219 + tipos) e renderiza o cabeçalho; este
 * módulo cuida só do que é interativo — a grade, o painel de criar/editar
 * (mesmo painel lateral de Ajustes da coleção) e a confirmação de exclusão
 * (Dialog do Design System). Depois de cada gravação a página é relida do
 * servidor (`router.refresh`); enquanto isso, a grade já mostra o resultado
 * (nome novo, local excluído) para não "piscar" o estado antigo.
 *
 * Gravações: painel aberto e travado (Esc/fora/fechar ignorados) enquanto a
 * ação está em andamento; campos ficam `readOnly`/`aria-disabled` (continuam
 * focáveis — padrão A2); um segundo clique não dispara outra gravação. Criar
 * é idempotente: a chave nasce com o conteúdo do formulário e é reaproveitada
 * em toda nova tentativa do MESMO envio.
 */

type Panel =
  | { kind: "create" }
  /** `focus` = aberto por "Encontrar carta": painel filtrado pela identidade exata (variante + idioma). */
  | { kind: "view"; location: StorageLocation; focus?: CardIdentity }
  | { kind: "report"; location: StorageLocation }
  | { kind: "edit"; location: StorageLocation }
  | { kind: "delete"; location: StorageLocation };

type Notice = { tone: "success" | "error"; text: string };

type Patch = Pick<StorageLocation, "name" | "kindCode" | "kindLabel">;

type ManagerValue = {
  kinds: StorageKind[];
  open: (panel: Panel) => void;
  notice: Notice | null;
  highlightId: string | null;
  patches: Record<string, Patch>;
  removed: ReadonlySet<string>;
  refreshing: boolean;
};

const ManagerContext = createContext<ManagerValue | null>(null);

function useManager(): ManagerValue {
  const value = useContext(ManagerContext);
  if (!value) throw new Error("LocationsProvider ausente");
  return value;
}

const ARIA_DISABLED_FIELD = "aria-disabled:cursor-not-allowed aria-disabled:opacity-50";
/** Visual de desabilitado para botões `aria-disabled` (igual a `disabled:` do DS). */
const ARIA_DISABLED_BUTTON = "aria-disabled:pointer-events-none aria-disabled:opacity-50";

export function LocationsProvider({
  kinds,
  locations,
  children,
}: {
  kinds: StorageKind[];
  /** Mesma lista que a grade recebe — só para descartar os ajustes locais quando o servidor responde. */
  locations: StorageLocation[];
  children: ReactNode;
}) {
  const router = useRouter();
  const [panel, setPanel] = useState<Panel | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [highlightId, setHighlightId] = useState<string | null>(null);
  const [patches, setPatches] = useState<Record<string, Patch>>({});
  const [removed, setRemoved] = useState<ReadonlySet<string>>(new Set());
  const [refreshing, startRefresh] = useTransition();

  // A lista do servidor chegou: ela é a verdade — os ajustes otimistas saem.
  useEffect(() => {
    setPatches({});
    setRemoved(new Set());
  }, [locations]);

  // O brilho do local recém-criado dura só a animação.
  useEffect(() => {
    if (!highlightId) return;
    const timer = window.setTimeout(() => setHighlightId(null), 2400);
    return () => window.clearTimeout(timer);
  }, [highlightId]);

  const refresh = () => startRefresh(() => router.refresh());

  const value: ManagerValue = {
    kinds,
    open: (next) => {
      setNotice(null);
      setPanel(next);
    },
    notice,
    highlightId,
    patches,
    removed,
    refreshing,
  };

  return (
    <ManagerContext.Provider value={value}>
      {children}
      {panel?.kind === "view" ? (
        <LocationContentPanel
          location={{ ...panel.location, ...patches[panel.location.id] }}
          focus={panel.focus ?? null}
          onClose={() => setPanel(null)}
          onReport={(location) => {
            setNotice(null);
            setPanel({ kind: "report", location });
          }}
        />
      ) : null}
      {panel?.kind === "report" ? (
        <LocationInventoryOverlay
          locationId={panel.location.id}
          onClose={() => {
            const id = panel.location.id;
            setPanel(null);
            window.requestAnimationFrame(() => document.querySelector<HTMLElement>(`[data-location-row="${id}"]`)?.focus());
          }}
        />
      ) : null}
      {panel?.kind === "create" ? (
        <LocationFormPanel
          mode="create"
          kinds={kinds}
          location={null}
          onClose={() => setPanel(null)}
          onCreated={(saved) => {
            setPanel(null);
            setHighlightId(saved.id);
            setNotice({
              tone: "success",
              text: saved.replayed
                ? `“${saved.name}” já estava criado. Nenhuma carta foi colocada nele automaticamente.`
                : storageSuccessMessage("created", saved.name),
            });
            refresh();
          }}
          onUpdated={() => {}}
          onStale={refresh}
        />
      ) : null}
      {panel?.kind === "edit" ? (
        <LocationFormPanel
          mode="edit"
          kinds={kinds}
          location={panel.location}
          onClose={() => setPanel(null)}
          onCreated={() => {}}
          onUpdated={(saved, changed) => {
            setPanel(null);
            if (!changed) return;
            const label = kindOptionsFor(kinds, panel.location).find((kind) => kind.code === saved.kindCode)?.label ?? null;
            setPatches((current) => ({ ...current, [saved.id]: { name: saved.name, kindCode: saved.kindCode, kindLabel: label } }));
            setNotice({ tone: "success", text: storageSuccessMessage("updated", saved.name) });
            refresh();
          }}
          onStale={refresh}
        />
      ) : null}
      {panel?.kind === "delete" ? (
        <DeleteDialog
          location={panel.location}
          onClose={() => setPanel(null)}
          onDeleted={(name, alreadyGone) => {
            setPanel(null);
            // O botão que abriu a confirmação sai junto com o local: o foco vai para o título da lista.
            window.requestAnimationFrame(() => document.getElementById("locais-lista")?.focus());
            setRemoved((current) => new Set([...current, panel.location.id]));
            setNotice({
              tone: "success",
              text: alreadyGone ? `“${name}” já tinha sido excluído. A lista foi atualizada.` : storageSuccessMessage("deleted", name),
            });
            refresh();
          }}
          onStale={refresh}
        />
      ) : null}
    </ManagerContext.Provider>
  );
}

/** Botão principal "Novo local" (cabeçalho e estado vazio). */
/**
 * "Novo local" — mesmo lançador das ações principais do módulo ("Nova coleção",
 * "Adicionar cartas"): `launcherHero`/`launchPrimary` de acervo-add.module.css.
 * No cabeçalho, a altura compacta do módulo (36 px; 44 px no celular); no estado
 * vazio, o tamanho cheio (a ação é o protagonista).
 */
export function NewLocationButton({ label = "Novo local", layout = "hero" }: { label?: string; layout?: "hero" | "empty" }) {
  const { open } = useManager();
  const button = (
    <Button className={addStyles.launchPrimary} onClick={() => open({ kind: "create" })} aria-haspopup="dialog">
      <Plus className="h-4 w-4" aria-hidden="true" />
      {label}
    </Button>
  );
  return layout === "hero" ? <div className={addStyles.launcherHero}>{button}</div> : button;
}

/** Mensagem de resultado da última ação — anunciada pelo leitor de tela. */
export function LocationsNotice() {
  const { notice } = useManager();
  return (
    <div className={styles.notice} role="status" aria-live="polite">
      {notice ? <InlineFeedback tone={notice.tone}>{notice.text}</InlineFeedback> : null}
    </div>
  );
}

/**
 * Inventário (Conceito B): coluna lateral com a organização (servidor) e as
 * facetas de tipo; área principal com busca, ordem e o índice de locais em
 * linhas. Tudo sobre a lista já lida (5219), sem nova consulta; ajustes
 * otimistas (renomear/excluir) aplicados antes de filtrar.
 */
export function LocationsExplorer({
  locations,
  kinds,
  totalCards,
  binders,
  organization,
}: {
  locations: StorageLocation[];
  kinds: StorageKind[];
  /** Fichários digitais por local (nomes das coleções), quando a leitura existe. */
  binders: Record<string, string[]>;
  /** Exemplares no acervo (5219) — base da participação de cada local. */
  totalCards: number;
  /** Bloco "Organização do acervo", renderizado no servidor. */
  organization: ReactNode;
}) {
  const { patches, removed, refreshing } = useManager();
  const searchId = useId();
  const sortId = useId();
  const [query, setQuery] = useState("");
  const [kind, setKind] = useState<LocationKindFilter>("all");
  const [sort, setSort] = useState<LocationSort>("name");
  const current = useMemo(
    () => locations.filter((location) => !removed.has(location.id)).map((location) => ({ ...location, ...patches[location.id] })),
    [locations, patches, removed],
  );
  const facets = useMemo(() => kindFilterOptions(current, kinds), [current, kinds]);
  // Tipo escolhido que deixou de existir (local renomeado/excluído): volta para "Todos".
  const activeKind = facets.some((option) => option.value === kind) ? kind : "all";
  const visible = useMemo(() => exploreLocations(current, { query, kind: activeKind, sort }), [current, query, activeKind, sort]);
  const [mode, setMode] = useState<"explore" | "find">("explore");
  const filtering = query.trim() !== "" || activeKind !== "all";
  const total = current.length === 1 ? "1 local" : `${formatCount(current.length)} locais`;
  const activeLabel = facets.find((option) => option.value === activeKind)?.label ?? "";

  return (
    <div className={styles.layout}>
      <aside className={styles.side} aria-label="Organização e tipos de local">
        {organization}
        <nav className={styles.facets} aria-labelledby="locais-tipos">
          <h2 id="locais-tipos" className={styles.facetsTitle}>
            Por tipo
          </h2>
          <ul className={styles.facetList}>
            {facets.map((option) => {
              const pressed = option.value === activeKind;
              return (
                <li key={option.value}>
                  <button
                    type="button"
                    className={styles.facet}
                    data-all={option.value === "all" || undefined}
                    aria-pressed={pressed}
                    onClick={() => {
                      setKind(option.value);
                      setMode("explore");
                    }}
                  >
                    {option.value === "all" ? null : (
                      <span className={styles.facetGlyph} aria-hidden="true">
                        <StorageGlyph kindCode={option.value === "none" ? null : option.value} />
                      </span>
                    )}
                    <span className={styles.facetLabel}>{option.label}</span>
                    <span className={styles.facetMeta}>
                      {option.count === 1 ? "1 local" : `${formatCount(option.count)} locais`}
                      <span>{pluralize(option.copies, "exemplar", "exemplares")}</span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>
      </aside>

      <section className={styles.mainCol} aria-labelledby="locais-lista">
        <h2 id="locais-lista" className="sr-only" tabIndex={-1}>
          Seus locais
        </h2>
        <div className={styles.modes} role="tablist" aria-label="Modo de consulta">
          {(
            [
              ["explore", "Explorar locais", MapPin],
              ["find", "Encontrar carta", ScanSearch],
            ] as const
          ).map(([value, label, Icon]) => (
            <button
              key={value}
              type="button"
              role="tab"
              id={`locais-modo-${value}`}
              aria-selected={mode === value}
              aria-controls={`locais-painel-${value}`}
              tabIndex={mode === value ? 0 : -1}
              className={styles.mode}
              onClick={() => setMode(value)}
              onKeyDown={(event) => {
                if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
                  event.preventDefault();
                  const next = value === "explore" ? "find" : "explore";
                  setMode(next);
                  document.getElementById(`locais-modo-${next}`)?.focus();
                }
              }}
            >
              <Icon className="h-4 w-4" aria-hidden="true" />
              {label}
            </button>
          ))}
        </div>

        {mode === "find" ? (
          <div id="locais-painel-find" role="tabpanel" aria-labelledby="locais-modo-find">
            <CardFinder locations={current} totalCards={totalCards} />
          </div>
        ) : (
        <div id="locais-painel-explore" role="tabpanel" aria-labelledby="locais-modo-explore">
        <div className={styles.toolbar} role="search" aria-label="Encontrar um local">
          <div className={styles.searchField}>
            <Label htmlFor={searchId} className="sr-only">
              Buscar local pelo nome
            </Label>
            <Search className={styles.searchIcon} aria-hidden="true" />
            <Input
              id={searchId}
              type="search"
              value={query}
              autoComplete="off"
              placeholder="Buscar pelo nome (ex.: F001, Card Box)"
              className="h-11 pl-9"
              onChange={(event) => setQuery(event.target.value)}
            />
          </div>
          <div className={styles.toolbarField}>
            <Label htmlFor={sortId} className="sr-only">
              Ordenar locais
            </Label>
            <Select id={sortId} value={sort} className="h-11" onChange={(event) => setSort(event.target.value as LocationSort)}>
              {LOCATION_SORT_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Select>
          </div>
        </div>

        <p className={styles.listMeta} aria-live="polite">
          <span>
            {filtering ? `${formatCount(visible.length)} de ${total}` : total}
            {activeKind !== "all" ? ` · ${activeLabel}` : ""}
          </span>
          <span className={styles.listLegend}>Barra e % = participação no acervo físico (0–100%)</span>
        </p>

        {visible.length === 0 ? (
          <div className={styles.noMatch} role="status">
            <p className={styles.noMatchTitle}>Nenhum local encontrado.</p>
            <p className={styles.noMatchText}>
              {query.trim() !== "" ? `Nenhum local com “${query.trim()}” no nome${activeKind !== "all" ? " neste tipo" : ""}.` : "Nenhum local deste tipo."}
            </p>
            <Button
              variant="outline"
              className="mt-3 min-h-11"
              onClick={() => {
                setQuery("");
                setKind("all");
              }}
            >
              Limpar busca e filtro
            </Button>
          </div>
        ) : (
          <ul className={styles.index} aria-labelledby="locais-lista" aria-busy={refreshing || undefined}>
            {visible.map((location) => (
              <LocationRow key={location.id} location={location} totalCards={totalCards} binders={binders[location.id] ?? []} />
            ))}
          </ul>
        )}
        </div>
        )}
      </section>
    </div>
  );
}

/**
 * Uma entrada do índice: recipiente desenhado, código do colecionador (quando
 * inequívoco no nome), nome, tipo e vínculos, exemplares e participação no
 * acervo. A linha inteira abre o conteúdo (painel do local); Editar e Excluir
 * ficam no menu "Mais ações" ao fim da linha. A barra compara a participação
 * entre locais — não é capacidade nem ocupação.
 */
function LocationRow({ location, totalCards, binders }: { location: StorageLocation; totalCards: number; binders: string[] }) {
  const { open, highlightId } = useManager();
  const { code, title } = splitLocationCode(location.name);
  const count = location.cardCount;
  const share = acervoShareText(count, totalCards);
  const defaultLabel = storageDefaultLabel(location.defaultCollectionCount);
  const isNew = highlightId === location.id;
  const rowRef = useRef<HTMLButtonElement>(null);
  // Mesmo denominador do percentual: o acervo físico inteiro (L2-01).
  const bar = acervoShareWidth(count, totalCards);

  // Local recém-criado: se o foco se perdeu (o botão do estado vazio sumiu), ele vem para o novo local.
  useEffect(() => {
    if (isNew && (document.activeElement === null || document.activeElement === document.body)) rowRef.current?.focus();
  }, [isNew]);

  return (
    <li className={styles.entry} data-new={isNew || undefined} data-empty={count === 0 || undefined}>
      <button
        ref={rowRef}
        type="button"
        data-location-row={location.id}
        className={styles.entryRow}
        onClick={() => open({ kind: "view", location })}
        aria-haspopup="dialog"
        aria-label={`Ver conteúdo de ${location.name}: ${storageCardCountLabel(count).toLowerCase()}${share ? `, ${share} do acervo` : ""}`}
      >
        <span className={styles.entryGlyph} aria-hidden="true">
          <StorageGlyph kindCode={location.kindCode} />
        </span>
        <span className={styles.entryCode} data-none={code ? undefined : ""}>
          {code ?? "—"}
        </span>
        <span className={styles.entryName}>
          <span className={styles.entryTitle}>
            {code ? <span className={styles.entryCodeInline}>{code} </span> : null}
            {code ? title : location.name}
          </span>
          <span className={styles.entrySub}>
            <span>{location.kindLabel ?? "Sem tipo definido"}</span>
            {binders.length > 0 ? (
              <span className={styles.entryLink}>
                <BookOpen className="h-3.5 w-3.5" aria-hidden="true" />
                {binders.length === 1 ? "Fichário digital" : `${binders.length} fichários digitais`}
              </span>
            ) : null}
            {defaultLabel ? (
              <span className={styles.entryLink}>
                <Star className="h-3.5 w-3.5" aria-hidden="true" />
                {defaultLabel}
              </span>
            ) : null}
          </span>
        </span>
        <span className={styles.entryVolume}>
          <span className={styles.entryCount}>
            <b>{formatCount(count)}</b> {count === 1 ? "exemplar" : "exemplares"}
            <span className={styles.entryShare}>{share ?? "vazio"}</span>
          </span>
          <span className={styles.entryBar} aria-hidden="true">
            {bar > 0 ? <span style={{ width: `max(${bar}%, 3px)` }} /> : null}
          </span>
        </span>
        <span className={styles.entryGo} aria-hidden="true">
          <ChevronRight className="h-4 w-4" />
        </span>
      </button>
      <ActionsMenu location={location} />
    </li>
  );
}

/**
 * Menu "Mais ações" (Editar, Imprimir inventário, Excluir): botão + lista de
 * itens, teclado (setas, Esc, Tab) e clique fora. "Imprimir inventário"
 * (LOCATION INVENTORY ACCESS UX REFINEMENT-01) abre a MESMA prévia do botão
 * "Gerar inventário deste local" do painel (`{ kind: "report", location }` →
 * `LocationInventoryOverlay`): o local é o da linha, o inventário é sempre do
 * local inteiro (nenhum filtro da página ou do painel), nada é impresso sem a
 * escolha do usuário na prévia. Leitura apenas — a ação não depende de poder
 * editar ou excluir.
 */
function ActionsMenu({ location }: { location: StorageLocation }) {
  const { open } = useManager();
  const [expanded, setExpanded] = useState(false);
  const menuId = useId();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const block = storageDeleteBlock(location);

  useEffect(() => {
    if (!expanded) return;
    menuRef.current?.querySelector<HTMLButtonElement>("[role=menuitem]")?.focus();
    const onDown = (event: PointerEvent) => {
      if (!menuRef.current?.contains(event.target as Node) && !buttonRef.current?.contains(event.target as Node)) setExpanded(false);
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [expanded]);

  const choose = (panel: Panel) => {
    setExpanded(false);
    open(panel);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const items = [...(menuRef.current?.querySelectorAll<HTMLButtonElement>("[role=menuitem]") ?? [])];
    const index = items.indexOf(document.activeElement as HTMLButtonElement);
    if (event.key === "Escape") {
      event.preventDefault();
      setExpanded(false);
      buttonRef.current?.focus();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const next = (index + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
      items[next]?.focus();
    } else if (event.key === "Tab") {
      setExpanded(false);
    }
  };

  return (
    <div className={styles.more}>
      <button
        ref={buttonRef}
        type="button"
        className={styles.moreButton}
        aria-haspopup="menu"
        aria-expanded={expanded}
        aria-controls={expanded ? menuId : undefined}
        aria-label={`Mais ações para ${location.name}`}
        onClick={() => setExpanded((value) => !value)}
      >
        <MoreHorizontal className="h-4 w-4" aria-hidden="true" />
      </button>
      {expanded ? (
        <div ref={menuRef} id={menuId} role="menu" aria-label={`Ações de ${location.name}`} className={styles.menu} onKeyDown={onKeyDown}>
          <button type="button" role="menuitem" className={styles.menuItem} onClick={() => choose({ kind: "edit", location })}>
            <Pencil className="h-4 w-4" aria-hidden="true" />
            Editar local
          </button>
          <button type="button" role="menuitem" className={styles.menuItem} onClick={() => choose({ kind: "report", location })} aria-haspopup="dialog">
            <ClipboardList className="h-4 w-4" aria-hidden="true" />
            Imprimir inventário
          </button>
          <div role="separator" className={styles.menuSeparator} />
          <button type="button" role="menuitem" className={styles.menuItem} onClick={() => choose({ kind: "delete", location })}>
            {block ? <Lock className="h-4 w-4" aria-hidden="true" /> : <Trash2 className="h-4 w-4" aria-hidden="true" />}
            Excluir local
          </button>
        </div>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// (D) Consulta contextual do local — painel lateral, somente leitura
// ---------------------------------------------------------------------------

/** 1ª página da 5220 (a mesma do Meu acervo, até 48 itens); o restante no Meu acervo. */
type ContentRead = { status: "loading" } | { status: "error" } | { status: "ready"; contents: LocationContents };

/** Cartas mostradas por vez no painel (os totais por Set vêm sempre da leitura COMPLETA do local). */
const PANEL_PAGE = 48;

/** Fatia os grupos para mostrar só as primeiras `limit` cartas, na ordem; o cabeçalho de cada grupo continua com o total. */
function visibleGroups<G extends { items: readonly unknown[] }>(groups: readonly G[], limit: number): Array<{ group: G; shown: G["items"] }> {
  const out: Array<{ group: G; shown: G["items"] }> = [];
  let left = limit;
  for (const group of groups) {
    if (left <= 0) break;
    const shown = group.items.slice(0, left);
    left -= shown.length;
    out.push({ group, shown });
  }
  return out;
}

function LocationContentPanel({
  location,
  focus,
  onClose,
  onReport,
}: {
  location: StorageLocation;
  /** Origem "Encontrar carta": identidade a mostrar primeiro; `null` = origem "Explorar locais" (conteúdo completo). */
  focus: CardIdentity | null;
  onClose: () => void;
  onReport: (location: StorageLocation) => void;
}) {
  const restoreFocus = useRestoreFocus();
  const [read, setRead] = useState<ContentRead>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const titleRef = useRef<HTMLHeadingElement>(null);
  const { code, title } = splitLocationCode(location.name);

  useEffect(() => {
    let alive = true;
    setRead({ status: "loading" });
    readLocationContents({ id: location.id })
      .catch(() => ({ ok: false as const }))
      .then((result) => {
        if (alive) setRead(result.ok ? { status: "ready", contents: result.contents } : { status: "error" });
      });
    return () => {
      alive = false;
    };
  }, [location.id, attempt]);

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const ready = read.status === "ready" ? read.contents : null;
  const groups = useMemo(() => (ready ? groupBySet(ready.items) : []), [ready]);
  const [visible, setVisible] = useState(PANEL_PAGE);
  const [preview, setPreview] = useState<AcervoItem | null>(null);
  // Filtro contextual: só apresentação — os totais, a leitura e o relatório continuam do local inteiro.
  // Removido aqui, volta na próxima abertura pela pesquisa (o estado nasce de `focus` a cada abertura).
  const [filter, setFilter] = useState<CardIdentity | null>(focus);
  const located = ready && filter ? findLocatedItem(ready.items, filter) : null;
  const contentHeadRef = useRef<HTMLHeadingElement>(null);
  const showAll = () => {
    setFilter(null);
    window.requestAnimationFrame(() => contentHeadRef.current?.focus());
  };
  const rarityOf = (item: AcervoItem) => previewRarityLabel(item.rarityCode, ready?.rarityNames ?? null);

  return (
    <DialogPrimitive.Root open onOpenChange={(value) => !value && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${styles.viewPanel}`}
          aria-describedby={undefined}
          onCloseAutoFocus={restoreFocus}
          onOpenAutoFocus={(event) => {
            event.preventDefault();
            titleRef.current?.focus();
          }}
        >
          <div className={`${acervoStyles.drawerHeader} ${styles.viewHeader}`}>
            <div className={styles.viewHead}>
              <span className={styles.viewObject} aria-hidden="true">
                <StorageGlyph kindCode={location.kindCode} code={code} open={read.status === "ready" && location.cardCount > 0} />
              </span>
              <div className="min-w-0">
                {code ? <span className={styles.codeChip}>{code}</span> : null}
                <DialogPrimitive.Title ref={titleRef} tabIndex={-1} className={styles.viewTitle}>
                  {code ? title : location.name}
                </DialogPrimitive.Title>
                <p className={styles.viewKind}>{location.kindLabel ?? "Sem tipo definido"}</p>
              </div>
            </div>
            <DialogPrimitive.Close
              className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              aria-label="Fechar e voltar aos locais"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          <div className={styles.viewBody}>
            {filter ? <p className={styles.factsCaption}>Totais do local inteiro</p> : null}
            <dl className={styles.facts}>
              <div className={styles.fact}>
                <dt className={styles.factLabel}>{location.cardCount === 1 ? "exemplar guardado aqui" : "exemplares guardados aqui"}</dt>
                <dd className={styles.factValue}>{formatCount(location.cardCount)}</dd>
              </div>
              <div className={styles.fact}>
                <dt className={styles.factLabel}>{ready?.totalGroups === 1 ? "carta diferente" : "cartas diferentes"}</dt>
                <dd className={styles.factValue}>{ready ? formatCount(ready.totalGroups) : "…"}</dd>
              </div>
            </dl>

            {ready && (ready.binders.length > 0 || ready.defaultCollections.length > 0) ? (
              <div className={styles.links}>
                {ready.binders.map((b) => (
                  <Link key={`b-${b.id}`} href={binderHref(b.id)} className={styles.linkRow}>
                    <BookOpen className="h-4 w-4 shrink-0" aria-hidden="true" />
                    <span className="min-w-0">
                      <span className={styles.linkTitle}>Fichário digital</span>
                      <span className={styles.linkName}>{b.name}</span>
                    </span>
                    <ArrowRight className="ml-auto h-4 w-4 shrink-0" aria-hidden="true" />
                  </Link>
                ))}
                {ready.defaultCollections.map((c) => (
                  <Link key={`c-${c.id}`} href={collectionHref(c.id)} className={styles.linkRow}>
                    <Star className="h-4 w-4 shrink-0" aria-hidden="true" />
                    <span className="min-w-0">
                      <span className={styles.linkTitle}>Local padrão da coleção</span>
                      <span className={styles.linkName}>{c.name}</span>
                    </span>
                    <ArrowRight className="ml-auto h-4 w-4 shrink-0" aria-hidden="true" />
                  </Link>
                ))}
              </div>
            ) : null}

            <section aria-labelledby="local-conteudo" aria-busy={read.status === "loading" || undefined}>
              <h3 id="local-conteudo" ref={contentHeadRef} tabIndex={-1} className={styles.viewSection}>
                {filter ? "Carta localizada" : "Guardado aqui"}
              </h3>
              {read.status === "loading" ? (
                <ul className={styles.cardGrid} aria-hidden="true">
                  {Array.from({ length: Math.min(Math.max(location.cardCount, 1), 8) }, (_, i) => (
                    <li key={i} className={styles.cardSkeleton} />
                  ))}
                </ul>
              ) : read.status === "error" ? (
                <div className={styles.contentState} role="alert">
                  <InlineFeedback tone="error">Não conseguimos ler o conteúdo deste local agora. Nada foi alterado.</InlineFeedback>
                  <Button variant="outline" className="mt-3 min-h-11" onClick={() => setAttempt((n) => n + 1)}>
                    Tentar novamente
                  </Button>
                </div>
              ) : read.contents.items.length === 0 && !filter ? (
                <div className={styles.contentState}>
                  <p className={styles.noMatchTitle}>Nenhum exemplar guardado aqui.</p>
                  <p className={styles.noMatchText}>No Meu acervo, selecione cartas e escolha este local para guardá-las aqui.</p>
                </div>
              ) : filter ? (
                <LocatedCard item={located} base={base} complete={read.contents.complete} onOpen={setPreview} onShowAll={showAll} />
              ) : (
                <>
                  {visibleGroups(groups, visible).map(({ group, shown }) => (
                    <div key={group.code} className={styles.setGroup}>
                      <p className={styles.setHead}>
                        <b>{group.code.toUpperCase()}</b> {group.name}
                        <span>{cardsCopiesLabel(group.cards, group.copies)}</span>
                      </p>
                      <ul className={styles.cardGrid}>
                        {shown.map((item) => (
                          <li key={`${item.cardVariantId}|${item.languageCode}`}>
                            <CardTile item={item} base={base} onOpen={() => setPreview(item)} />
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}
                  <div className={styles.contentFoot}>
                    {visible < read.contents.items.length ? (
                      <>
                        <p>
                          Mostrando {formatCount(visible)} de {formatCount(read.contents.items.length)} cartas diferentes, em ordem de Set.
                        </p>
                        <Button variant="outline" className="mt-2 min-h-11" onClick={() => setVisible((n) => n + PANEL_PAGE)}>
                          Mostrar mais {formatCount(Math.min(PANEL_PAGE, read.contents.items.length - visible))}
                        </Button>
                      </>
                    ) : (
                      <p>Em ordem de Set e número.</p>
                    )}
                    {!read.contents.complete ? (
                      <InlineFeedback tone="error">A leitura deste local não fechou por inteiro agora; os totais podem estar incompletos. Nada foi alterado.</InlineFeedback>
                    ) : null}
                  </div>
                </>
              )}
            </section>
          </div>

          <div className={styles.viewFoot}>
            <Button className="min-h-11 gap-1.5" onClick={() => onReport(location)} aria-haspopup="dialog">
              <ClipboardList className="h-4 w-4" aria-hidden="true" />
              Gerar inventário deste local
            </Button>
          </div>
          {preview ? <CardPreview item={preview} base={base} locationName={location.name} rarity={rarityOf(preview)} onClose={() => setPreview(null)} /> : null}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

/** Miniatura de uma carta do local (grade por Set e carta localizada) — abre a prévia ampliada. */
function CardTile({ item, base, onOpen }: { item: AcervoItem; base: string | undefined; onOpen: () => void }) {
  const src = cardFrontUrl(base, item.imagePath);
  const variant = variantTag(item.isDefaultVariant, item.variantLabel);
  return (
    <button
      type="button"
      className={styles.cardTile}
      onClick={onOpen}
      aria-haspopup="dialog"
      aria-label={`Ampliar ${item.cardName}, ${item.cardSetCode.toUpperCase()} ${formatCollectorNumber(item.collectorNumber, item.collectorTotal)}, ${languageLabel(item.languageCode, item.languageName)}${variant ? `, ${variant}` : ""}: ${storageMatchAccessible("location", item.copiesCount, item.copiesOwned)}`}
    >
      <span className={styles.cardImage} aria-hidden="true">
        {/* eslint-disable-next-line @next/next/no-img-element -- frente da carta do bucket público, mesmo padrão do Meu acervo */}
        {src ? <img src={src} alt="" loading="lazy" decoding="async" /> : null}
        <span className={styles.cardBadge}>{formatCount(item.copiesCount)}</span>
      </span>
      <span className={styles.cardName} aria-hidden="true">
        {item.cardName}
      </span>
      <span className={styles.cardMeta} aria-hidden="true">
        {formatCollectorNumber(item.collectorNumber, item.collectorTotal)} · {languageLabel(item.languageCode, item.languageName)}
        {variant ? ` · ${variant}` : ""}
      </span>
      <span className={styles.cardMeta} aria-hidden="true">
        {storageMatchLabel("location", item.copiesCount, item.copiesOwned)}
      </span>
    </button>
  );
}

/**
 * Carta localizada (CONTEXTUAL UX-02) — o painel aberto por "Encontrar carta"
 * mostra primeiro só a versão pesquisada (variante + idioma exatos) com a
 * quantidade DESTE local; "Ver todas as cartas deste local" tira só o filtro,
 * no mesmo painel. A miniatura é a mesma da grade e abre a mesma prévia.
 */
function LocatedCard({
  item,
  base,
  complete,
  onOpen,
  onShowAll,
}: {
  item: AcervoItem | null;
  base: string | undefined;
  complete: boolean;
  onOpen: (item: AcervoItem) => void;
  onShowAll: () => void;
}) {
  return (
    <div className={styles.located}>
      {item ? (
        <div className={styles.locatedBody}>
          <div className={styles.locatedTile}>
            <CardTile item={item} base={base} onOpen={() => onOpen(item)} />
          </div>
          <div className="min-w-0">
            <p className={styles.locatedName}>{item.cardName}</p>
            <p className={styles.locatedMeta}>
              {item.cardSetCode.toUpperCase()} · {item.cardSetName} · Nº {formatCollectorNumber(item.collectorNumber, item.collectorTotal)}
            </p>
            <p className={styles.locatedMeta}>
              {variantName(item.variantLabel)} · {languageLabel(item.languageCode, item.languageName)}
            </p>
            <p className={styles.locatedCount}>
              <b>{formatCount(item.copiesCount)}</b> {item.copiesCount === 1 ? "exemplar desta versão neste local" : "exemplares desta versão neste local"}
            </p>
          </div>
        </div>
      ) : (
        <div className={styles.contentState} role="status">
          <p className={styles.noMatchTitle}>A carta pesquisada não está mais neste local.</p>
          <p className={styles.noMatchText}>
            {complete ? "Ela pode ter sido movida. Nada foi alterado." : "A leitura deste local não fechou por inteiro agora. Nada foi alterado."}
          </p>
        </div>
      )}
      <p className={styles.locatedNote}>Mostrando só a carta pesquisada.</p>
      <Button variant="outline" className="min-h-11 w-full gap-1.5 sm:w-auto" onClick={onShowAll}>
        Ver todas as cartas deste local
        <ArrowRight className="h-4 w-4" aria-hidden="true" />
      </Button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Prévia da carta (L2-01, CONTEXTUAL UX-02) — dentro do painel do local, sem sair de Meus locais
// ---------------------------------------------------------------------------

/**
 * Imagem ampliada e identificação da carta, num diálogo sobre o painel (Radix:
 * Esc fecha só a prévia e o foco volta à miniatura). Somente leitura — nenhuma
 * ação de edição; para gerir a carta, o Meu acervo continua sendo o lugar.
 *
 * Informações (UX-02): identificação (nome, Set) → características (Número,
 * Idioma, Raridade, Variante — cada uma na sua linha) → armazenamento (o local
 * do painel aberto, exemplares neste local e no acervo) → voltar. Tudo já está
 * na leitura do painel: nenhuma consulta nova.
 */
function CardPreview({
  item,
  base,
  locationName,
  rarity,
  onClose,
}: {
  item: AcervoItem;
  base: string | undefined;
  /** Nome real do local do painel que originou a prévia (localização física, não coleção). */
  locationName: string;
  /** Nome canônico da raridade (`previewRarityLabel`). */
  rarity: string;
  onClose: () => void;
}) {
  const src = cardFrontUrl(base, item.imagePath);
  const traits = [
    { label: "Número", value: formatCollectorNumber(item.collectorNumber, item.collectorTotal) },
    { label: "Idioma", value: languageLabel(item.languageCode, item.languageName) },
    { label: "Raridade", value: rarity },
    { label: "Variante", value: variantName(item.variantLabel) },
  ];
  return (
    <DialogPrimitive.Root open onOpenChange={(value) => !value && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={styles.previewOverlay} />
        <DialogPrimitive.Content className={styles.preview} aria-describedby={undefined}>
          <div className={styles.previewImage}>
            {/* eslint-disable-next-line @next/next/no-img-element -- frente da carta do bucket público, mesmo padrão do Meu acervo */}
            {src ? <img src={src} alt={`${item.cardName} — frente da carta`} decoding="async" /> : <span className={styles.previewNoImage}>Sem imagem</span>}
          </div>
          <div className={styles.previewInfo}>
            <div className={styles.previewIdentity}>
              <DialogPrimitive.Title className={styles.previewTitle}>{item.cardName}</DialogPrimitive.Title>
              <p className={styles.previewMeta}>
                {item.cardSetCode.toUpperCase()} · {item.cardSetName}
              </p>
            </div>
            {/* Características: número e idioma em linhas próprias (decisão do proprietário). */}
            <dl className={styles.previewTraits}>
              {traits.map((t) => (
                <div key={t.label} className={styles.previewTrait}>
                  <dt>{t.label}</dt>
                  <dd>{t.value}</dd>
                </div>
              ))}
            </dl>
            {/* Armazenamento: o local do painel + as duas quantidades nomeadas. */}
            <div className={styles.previewStorage}>
              <p className={styles.previewPlaceLabel}>Local de armazenamento</p>
              <p className={styles.previewPlace}>
                <MapPin className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                <span>{locationName}</span>
              </p>
              <dl className={styles.previewCounts}>
                <div className={styles.previewCountRow}>
                  <dt>Neste local</dt>
                  <dd>{pluralize(item.copiesCount, "exemplar", "exemplares")}</dd>
                </div>
                <div className={styles.previewCountRow}>
                  <dt>No acervo</dt>
                  <dd>{pluralize(item.copiesOwned, "exemplar", "exemplares")}</dd>
                </div>
              </dl>
            </div>
            <DialogPrimitive.Close asChild>
              <Button variant="outline" className={`${styles.previewBack} min-h-11 w-full gap-1.5`}>
                <ArrowLeft className="h-4 w-4" aria-hidden="true" />
                Voltar às cartas
              </Button>
            </DialogPrimitive.Close>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

// ---------------------------------------------------------------------------
// Encontrar carta (L2-01) — onde estão os exemplares de uma carta
// ---------------------------------------------------------------------------

type Search = { status: "idle" } | { status: "loading" } | { status: "error" } | { status: "ready"; query: string; items: AcervoItem[]; total: number };
type Located = { status: "loading" } | { status: "error" } | { status: "ready"; result: CardLocations };

/**
 * Busca no acervo do titular (a mesma busca do Meu acervo: nome ou número), lista
 * as identidades físicas encontradas (carta + Set + número + variante + idioma —
 * nunca agrupadas pelo nome) e, escolhida uma, mostra onde estão os exemplares:
 * cada local com a quantidade (abre o painel do local) e os sem localização.
 * Σ locais + sem localização = exemplares da identidade. Somente leitura.
 */
function CardFinder({ locations, totalCards }: { locations: StorageLocation[]; totalCards: number }) {
  const { open } = useManager();
  const inputId = useId();
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState<Search>({ status: "idle" });
  const [selected, setSelected] = useState<AcervoItem | null>(null);
  const [located, setLocated] = useState<Located | null>(null);
  const seq = useRef(0);
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const byId = useMemo(() => new Map(locations.map((l) => [l.id, l])), [locations]);

  // Busca com espera curta; só a resposta mais recente vale.
  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) {
      setSearch({ status: "idle" });
      return;
    }
    const id = ++seq.current;
    setSearch({ status: "loading" });
    const timer = window.setTimeout(() => {
      readCardSearch({ query: q })
        .catch(() => ({ ok: false as const }))
        .then((res) => {
          if (id !== seq.current) return;
          setSearch(res.ok ? { status: "ready", query: q, items: res.items, total: res.totalGroups } : { status: "error" });
        });
    }, 280);
    return () => window.clearTimeout(timer);
  }, [query]);

  const choose = (item: AcervoItem) => {
    setSelected(item);
    setLocated({ status: "loading" });
    readCardLocations({ cardVariantId: item.cardVariantId, languageCode: item.languageCode })
      .catch(() => ({ ok: false as const, reason: "error" as const }))
      .then((res) => setLocated(res.ok ? { status: "ready", result: res.result } : { status: "error" }));
  };

  const rows =
    located?.status === "ready"
      ? Object.entries(located.result.byStorage)
          .map(([id, n]) => ({ id, n, location: byId.get(id) ?? null }))
          .sort((a, b) => b.n - a.n || (a.location?.name ?? "").localeCompare(b.location?.name ?? "", "pt-BR"))
      : [];

  return (
    <div className={styles.finder}>
      <div className={styles.searchField} role="search" aria-label="Encontrar uma carta no acervo">
        <Label htmlFor={inputId} className="sr-only">
          Buscar carta do seu acervo pelo nome ou número
        </Label>
        <Search className={styles.searchIcon} aria-hidden="true" />
        <Input
          id={inputId}
          type="search"
          value={query}
          autoComplete="off"
          placeholder="Nome ou número da carta (ex.: Pikachu, 25/88)"
          className="h-11 pl-9"
          onChange={(event) => {
            setQuery(event.target.value);
            setSelected(null);
            setLocated(null);
          }}
        />
      </div>

      {selected ? (
        <section className={styles.found} aria-labelledby="carta-encontrada">
          <div className={styles.foundHead}>
            <span className={styles.foundImage} aria-hidden="true">
              {/* eslint-disable-next-line @next/next/no-img-element -- frente da carta do bucket público */}
              {cardFrontUrl(base, selected.imagePath) ? <img src={cardFrontUrl(base, selected.imagePath) ?? ""} alt="" decoding="async" /> : null}
            </span>
            <div className="min-w-0">
              <h3 id="carta-encontrada" className={styles.foundTitle} tabIndex={-1}>
                {selected.cardName}
              </h3>
              <p className={styles.foundMeta}>
                {selected.cardSetCode.toUpperCase()} · {selected.cardSetName} · Nº {formatCollectorNumber(selected.collectorNumber, selected.collectorTotal)}
              </p>
              <p className={styles.foundMeta}>
                {variantName(selected.variantLabel)} · {languageLabel(selected.languageCode, selected.languageName)}
              </p>
              <p className={styles.foundTotal}>
                {located?.status === "ready" ? pluralize(located.result.total, "exemplar no acervo", "exemplares no acervo") : "…"}
              </p>
              {located?.status === "ready" ? <ConditionMix tally={located.result.conditions} /> : null}
            </div>
            <Button variant="ghost" className="min-h-11 shrink-0" onClick={() => { setSelected(null); setLocated(null); }}>
              Trocar carta
            </Button>
          </div>

          {located?.status === "loading" ? (
            <ul className={styles.index} aria-hidden="true">
              {[0, 1].map((i) => (
                <li key={i} className={styles.foundSkeleton} />
              ))}
            </ul>
          ) : located?.status === "error" ? (
            <div className={styles.contentState} role="alert">
              <InlineFeedback tone="error">Não conseguimos localizar os exemplares agora. Nada foi alterado.</InlineFeedback>
              <Button variant="outline" className="mt-3 min-h-11" onClick={() => choose(selected)}>
                Tentar novamente
              </Button>
            </div>
          ) : located?.status === "ready" ? (
            <>
              <p className={styles.listMeta} aria-live="polite">
                <span>
                  {rows.length === 0
                    ? "Nenhum exemplar desta carta está em um local."
                    : `Em ${rows.length === 1 ? "1 local" : `${formatCount(rows.length)} locais`}${located.result.unlocated > 0 ? " e sem localização" : ""}`}
                </span>
              </p>
              <ul className={styles.index}>
                {rows.map(({ id, n, location }) => {
                  const split = location ? splitLocationCode(location.name) : null;
                  const mix = located.result.conditionsByStorage?.[id] ?? null;
                  const mixSpoken = mix ? conditionDistributionAccessible(mix) : "";
                  return (
                    <li key={id} className={styles.entry}>
                      {location ? (
                        <button
                          type="button"
                          className={`${styles.entryRow} ${styles.foundRow}`}
                          onClick={() => open({ kind: "view", location, focus: { cardVariantId: selected.cardVariantId, languageCode: selected.languageCode } })}
                          aria-haspopup="dialog"
                          aria-label={`Abrir ${location.name} mostrando esta carta: ${pluralize(n, "exemplar desta carta", "exemplares desta carta")}${mixSpoken ? `. ${mixSpoken}` : ""}`}
                        >
                          <span className={styles.entryGlyph} aria-hidden="true">
                            <StorageGlyph kindCode={location.kindCode} />
                          </span>
                          <span className={styles.entryCode} data-none={split?.code ? undefined : ""}>
                            {split?.code ?? "—"}
                          </span>
                          <span className={styles.entryName}>
                            <span className={styles.entryTitle}>{split?.code ? split.title : location.name}</span>
                            <span className={styles.entrySub}>
                              <span>{location.kindLabel ?? "Sem tipo definido"}</span>
                            </span>
                            {mix ? <ConditionMix tally={mix} compact /> : null}
                          </span>
                          <span className={styles.foundCount}>
                            <b>{formatCount(n)}</b> {n === 1 ? "exemplar" : "exemplares"}
                          </span>
                          <span className={styles.entryGo} aria-hidden="true">
                            <ChevronRight className="h-4 w-4" />
                          </span>
                        </button>
                      ) : (
                        <div className={`${styles.entryRow} ${styles.foundRow}`}>
                          <span />
                          <span />
                          <span className={styles.entryName}>
                            <span className={styles.entryTitle}>Local indisponível</span>
                            {mix ? <ConditionMix tally={mix} compact /> : null}
                          </span>
                          <span className={styles.foundCount}>
                            <b>{formatCount(n)}</b>
                          </span>
                          <span />
                        </div>
                      )}
                    </li>
                  );
                })}
                {located.result.unlocated > 0 ? (
                  <li className={styles.entry}>
                    <div className={`${styles.entryRow} ${styles.foundRow}`} data-unlocated="">
                      <span className={styles.entryGlyph} aria-hidden="true">
                        <StorageGlyph kindCode={null} />
                      </span>
                      <span className={styles.entryCode} data-none="">
                        —
                      </span>
                      <span className={styles.entryName}>
                        <span className={styles.entryTitle}>Sem localização</span>
                        <span className={styles.entrySub}>
                          <span>Exemplares ainda sem local definido</span>
                        </span>
                        {located.result.unlocatedConditions ? <ConditionMix tally={located.result.unlocatedConditions} compact /> : null}
                      </span>
                      <span className={styles.foundCount}>
                        <b>{formatCount(located.result.unlocated)}</b> {located.result.unlocated === 1 ? "exemplar" : "exemplares"}
                      </span>
                      <span />
                    </div>
                  </li>
                ) : null}
              </ul>
            </>
          ) : null}
        </section>
      ) : search.status === "idle" ? (
        <p className={styles.finderHint}>
          Digite ao menos 2 letras do nome ou o número da carta. Só as cartas do seu acervo aparecem — a busca não muda nada de lugar.
        </p>
      ) : search.status === "loading" ? (
        <ul className={styles.candidates} aria-hidden="true">
          {[0, 1, 2].map((i) => (
            <li key={i} className={styles.foundSkeleton} />
          ))}
        </ul>
      ) : search.status === "error" ? (
        <div className={styles.contentState} role="alert">
          <InlineFeedback tone="error">Não conseguimos buscar agora. Nada foi alterado — tente de novo.</InlineFeedback>
        </div>
      ) : search.items.length === 0 ? (
        <div className={styles.noMatch} role="status">
          <p className={styles.noMatchTitle}>Nenhuma carta encontrada no seu acervo.</p>
          <p className={styles.noMatchText}>Confira o nome ou tente pelo número (ex.: 25 ou 25/88).</p>
        </div>
      ) : (
        <>
          <p className={styles.listMeta} aria-live="polite">
            <span>
              {search.total > search.items.length
                ? `Mostrando ${formatCount(search.items.length)} de ${formatCount(search.total)} cartas — refine a busca`
                : pluralize(search.items.length, "carta encontrada", "cartas encontradas")}{" "}
              · escolha a versão exata
            </span>
          </p>
          <ul className={styles.candidates}>
            {search.items.map((item) => {
              const src = cardFrontUrl(base, item.imagePath);
              return (
                <li key={`${item.cardVariantId}|${item.languageCode}`}>
                  <button type="button" className={styles.candidate} onClick={() => choose(item)}>
                    <span className={styles.candidateImage} aria-hidden="true">
                      {/* eslint-disable-next-line @next/next/no-img-element -- frente da carta do bucket público */}
                      {src ? <img src={src} alt="" loading="lazy" decoding="async" /> : null}
                    </span>
                    <span className={styles.candidateText}>
                      <span className={styles.entryTitle}>{item.cardName}</span>
                      <span className={styles.entrySub}>
                        <span>
                          {item.cardSetCode.toUpperCase()} · Nº {formatCollectorNumber(item.collectorNumber, item.collectorTotal)}
                        </span>
                        <span>{variantName(item.variantLabel)}</span>
                        <span>{languageLabel(item.languageCode, item.languageName)}</span>
                      </span>
                    </span>
                    <span className={styles.foundCount}>
                      <b>{formatCount(item.copiesOwned)}</b> {item.copiesOwned === 1 ? "exemplar" : "exemplares"}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </>
      )}
      {totalCards === 0 ? <p className={styles.finderHint}>Seu acervo ainda não tem exemplares.</p> : null}
    </div>
  );
}

/**
 * V1-16 UX-B — distribuição das condições declaradas ("NM ×2 · SP ×1"), na
 * ordem e com os rótulos do mapa canônico. Exemplar com código ausente ou
 * fora da escala aparece como "não reconhecida" — nunca como uma condição.
 * Visual curto (sigla em selo + quantidade) com leitura por extenso para
 * leitor de tela; frase (não lista) para caber também dentro de um botão.
 */
function ConditionMix({ tally, compact = false }: { tally: ConditionTally; compact?: boolean }) {
  if (!tally || tally.total <= 0) return null;
  const parts = conditionParts(tally);
  return (
    <span className={styles.conditionMix} data-compact={compact ? "" : undefined} title={conditionDistributionText(tally)}>
      <span className={styles.conditionMixItems} aria-hidden="true">
        {parts.map((part) => (
          <span key={part.code} className={styles.conditionMixItem}>
            <span className={styles.conditionMixCode}>{part.short}</span>×{formatCount(part.count)}
          </span>
        ))}
        {tally.unrecognized > 0 ? (
          <span className={styles.conditionMixItem} data-unrecognized="">
            Condição não reconhecida ×{formatCount(tally.unrecognized)}
          </span>
        ) : null}
      </span>
      <span className="sr-only">{conditionDistributionAccessible(tally)}</span>
    </span>
  );
}

// ---------------------------------------------------------------------------
// Painel lateral: criar / editar
// ---------------------------------------------------------------------------

type Saved = { id: string; name: string; kindCode: string | null };

function LocationFormPanel({
  mode,
  kinds,
  location,
  onClose,
  onCreated,
  onUpdated,
  onStale,
}: {
  mode: "create" | "edit";
  kinds: StorageKind[];
  location: StorageLocation | null;
  onClose: () => void;
  onCreated: (saved: Saved & { replayed: boolean }) => void;
  onUpdated: (saved: Saved, changed: boolean) => void;
  /** A lista na tela pode estar desatualizada (local sumiu, tipo saiu): relê do servidor. */
  onStale: () => void;
}) {
  const restoreFocus = useRestoreFocus();
  const nameId = useId();
  const nameHelpId = useId();
  const kindId = useId();
  const kindHelpId = useId();
  const nameRef = useRef<HTMLInputElement>(null);
  const [name, setName] = useState(location?.name ?? "");
  const [kind, setKind] = useState<string>(location?.kindCode ?? "");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<StorageFailure | null>(null);
  const [touched, setTouched] = useState(false);
  // Chave de idempotência do envio atual: muda só quando o conteúdo muda.
  const keyRef = useRef<{ payload: string; key: string } | null>(null);
  const pendingRef = useRef(false);

  const options = useMemo(() => kindOptionsFor(kinds, location), [kinds, location]);
  const normalized = normalizeStorageName(name);
  const trimmedLength = name.trim().length;
  const nameInvalid = touched && normalized === null;
  const changed = mode === "create" ? normalized !== null : location !== null && storageEditChanged(location, name, kind || null);
  const gone = error === "not_found";

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (pendingRef.current || gone) return;
    setTouched(true);
    if (normalized === null) {
      // A regra aparece no próprio campo (borda + texto de ajuda); o foco volta para ele.
      nameRef.current?.focus();
      return;
    }
    if (!changed) return;
    pendingRef.current = true;
    setPending(true);
    setError(null);
    const fallback = { ok: false as const, reason: "unavailable" as const };
    try {
      if (mode === "create") {
        const payload = JSON.stringify([normalized, kind || null]);
        if (keyRef.current?.payload !== payload) keyRef.current = { payload, key: crypto.randomUUID() };
        const result = await createStorageLocation({ idempotencyKey: keyRef.current.key, name: normalized, kindCode: kind || null }).catch(
          () => fallback,
        );
        if (!result.ok) {
          setError(result.reason);
          if (result.reason === "invalid_kind") onStale();
          return;
        }
        onCreated({ id: result.id, name: result.name, kindCode: result.kindCode, replayed: result.replayed });
      } else if (location) {
        const result = await updateStorageLocation({ id: location.id, name: normalized, kindCode: kind || null }).catch(() => fallback);
        if (!result.ok) {
          setError(result.reason);
          if (result.reason === "not_found" || result.reason === "invalid_kind") onStale();
          return;
        }
        onUpdated({ id: result.id, name: result.name, kindCode: result.kindCode }, result.changed);
      }
    } finally {
      pendingRef.current = false;
      setPending(false);
    }
  };

  const title = mode === "create" ? "Novo local" : "Editar local";
  const subtitle = mode === "create" ? "Meus locais" : (location?.name ?? "");
  const defaultLabel = location ? storageDefaultLabel(location.defaultCollectionCount) : null;

  return (
    <DialogPrimitive.Root open onOpenChange={(open) => !open && !pending && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${manageStyles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => pending && event.preventDefault()}
          onPointerDownOutside={(event) => pending && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
          onOpenAutoFocus={(event) => {
            event.preventDefault();
            nameRef.current?.focus();
          }}
        >
          <div className={acervoStyles.drawerHeader}>
            <div className="min-w-0">
              <DialogPrimitive.Title className={addStyles.panelTitle}>{title}</DialogPrimitive.Title>
              <p className="truncate text-xs text-muted-foreground">{subtitle}</p>
            </div>
            <DialogPrimitive.Close
              aria-disabled={pending || undefined}
              onClick={(event) => pending && event.preventDefault()}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring aria-disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          <div className={manageStyles.body}>
            <p className={manageStyles.note}>
              {mode === "create"
                ? "Um lugar real onde você guarda cartas — um fichário, uma caixa, uma pasta. Criar o local não coloca nenhuma carta nele."
                : "Mudar o nome ou o tipo não move nenhuma carta e não muda o local padrão de nenhuma coleção."}
            </p>

            {location ? (
              <dl className={styles.facts}>
                <div className={styles.fact}>
                  <dt className={styles.factLabel}>{location.cardCount === 1 ? "exemplar guardado aqui" : "exemplares guardados aqui"}</dt>
                  <dd className={styles.factValue}>{formatCount(location.cardCount)}</dd>
                </div>
                <div className={styles.fact}>
                  <dt className={styles.factLabel}>
                    {location.defaultCollectionCount === 1 ? "coleção usa como local padrão" : "coleções usam como local padrão"}
                  </dt>
                  <dd className={styles.factValue}>{formatCount(location.defaultCollectionCount)}</dd>
                </div>
              </dl>
            ) : null}

            <form className={styles.form} onSubmit={submit} noValidate>
              <div className={styles.field}>
                <div className={styles.fieldRow}>
                  <Label htmlFor={nameId}>Nome do local</Label>
                  <span className={styles.counter} data-over={trimmedLength > STORAGE_NAME_MAX || undefined} aria-hidden="true">
                    {trimmedLength}/{STORAGE_NAME_MAX}
                  </span>
                </div>
                <Input
                  ref={nameRef}
                  id={nameId}
                  value={name}
                  maxLength={STORAGE_NAME_MAX + 20}
                  autoComplete="off"
                  placeholder="Ex.: Fichário azul, Caixa do armário"
                  invalid={nameInvalid}
                  aria-describedby={nameHelpId}
                  aria-required="true"
                  readOnly={pending || gone}
                  aria-disabled={pending || gone || undefined}
                  className={`h-11 ${ARIA_DISABLED_FIELD}`}
                  onChange={(event) => {
                    setName(event.target.value);
                    if (error === "invalid_name") setError(null);
                  }}
                  onBlur={() => name !== "" && setTouched(true)}
                />
                <p id={nameHelpId} className={nameInvalid ? `${styles.help} text-destructive dark:text-destructive-foreground` : styles.help}>
                  {nameInvalid
                    ? `Dê um nome ao local, com até ${STORAGE_NAME_MAX} caracteres.`
                    : `Obrigatório, até ${STORAGE_NAME_MAX} caracteres. Pode repetir o nome de outro local.`}
                </p>
              </div>

              <div className={styles.field}>
                <Label htmlFor={kindId}>
                  Tipo <span className="font-normal text-muted-foreground">(opcional)</span>
                </Label>
                <Select
                  id={kindId}
                  value={kind}
                  aria-describedby={kindHelpId}
                  aria-disabled={pending || gone || undefined}
                  className={`h-11 ${ARIA_DISABLED_FIELD}`}
                  onChange={(event) => {
                    if (pending || gone) return;
                    setKind(event.target.value);
                    if (error === "invalid_kind") setError(null);
                  }}
                >
                  <option value="">Sem tipo definido</option>
                  {options.map((option) => (
                    <option key={option.code} value={option.code}>
                      {option.label}
                    </option>
                  ))}
                </Select>
                <p id={kindHelpId} className={styles.help}>
                  {kinds.length === 0
                    ? "Os tipos não carregaram agora — você pode criar o local sem tipo e definir depois."
                    : "Ajuda a reconhecer o local de relance. Pode mudar quando quiser."}
                </p>
              </div>

              {defaultLabel ? (
                <p className={styles.help}>
                  <Star className="mr-1 inline h-3.5 w-3.5 align-[-2px]" aria-hidden="true" />
                  {defaultLabel}. Esse vínculo continua o mesmo depois de salvar.
                </p>
              ) : null}

              <div aria-live="assertive">
                {error ? (
                  <InlineFeedback tone="error">{storageFailureMessage(error)}</InlineFeedback>
                ) : null}
              </div>

              <div className={styles.formActions}>
                {gone ? (
                  <Button type="button" className="min-h-11" onClick={onClose}>
                    Fechar
                  </Button>
                ) : (
                  <>
                    <Button
                      type="submit"
                      className={`min-h-11 px-5 ${ARIA_DISABLED_BUTTON}`}
                      aria-disabled={pending || (mode === "edit" && !changed) || undefined}
                    >
                      {pending ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
                      {mode === "create" ? (pending ? "Criando…" : "Criar local") : pending ? "Salvando…" : "Salvar"}
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      className={`min-h-11 ${ARIA_DISABLED_BUTTON}`}
                      aria-disabled={pending || undefined}
                      onClick={() => !pending && onClose()}
                    >
                      Cancelar
                    </Button>
                  </>
                )}
              </div>
            </form>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

// ---------------------------------------------------------------------------
// Excluir: confirmação explícita ou, se bloqueado, a explicação do porquê
// ---------------------------------------------------------------------------

function DeleteDialog({
  location,
  onClose,
  onDeleted,
  onStale,
}: {
  location: StorageLocation;
  onClose: () => void;
  onDeleted: (name: string, alreadyGone: boolean) => void;
  onStale: () => void;
}) {
  const restoreFocus = useRestoreFocus();
  const [pending, setPending] = useState(false);
  const [failure, setFailure] = useState<StorageFailure | null>(null);
  const pendingRef = useRef(false);
  const block = storageDeleteBlock(location);
  // Bloqueio conhecido de antemão ou devolvido pelo banco (corrida): nenhuma ação destrutiva é oferecida.
  const serverBlocked = failure === "has_cards" || failure === "collection_default" || failure === "in_use";
  const blocked = block !== null || serverBlocked;

  const confirm = async () => {
    if (pendingRef.current || blocked) return;
    pendingRef.current = true;
    setPending(true);
    setFailure(null);
    try {
      const result = await deleteStorageLocation({ id: location.id }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
      if (result.ok) {
        onDeleted(location.name, false);
        return;
      }
      if (result.reason === "not_found") {
        // Já tinha sido excluído (outra aba, outro dispositivo): é o resultado pedido.
        onDeleted(location.name, true);
        return;
      }
      setFailure(result.reason);
      if (result.reason === "has_cards" || result.reason === "collection_default" || result.reason === "in_use") onStale();
    } finally {
      pendingRef.current = false;
      setPending(false);
    }
  };

  return (
    <Dialog open onOpenChange={(open) => !open && !pending && onClose()}>
      <DialogContent
        hideClose
        role={blocked ? "dialog" : "alertdialog"}
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onPointerDownOutside={(event) => pending && event.preventDefault()}
        onCloseAutoFocus={restoreFocus}
      >
        <DialogHeader>
          <DialogTitle className="font-heading text-base font-bold">
            {block ? "Este local não pode ser excluído agora" : serverBlocked ? "Não foi possível excluir" : `Excluir “${location.name}”?`}
          </DialogTitle>
          <DialogDescription className="text-sm">
            {blocked ? location.name : "O local está vazio e não é local padrão de nenhuma coleção."}
          </DialogDescription>
        </DialogHeader>
        <DialogBody>
          <div className={styles.confirmBody}>
            {block ? (
              <>
                <p>{storageDeleteBlockMessage(block, location)}</p>
                {block === "collection_default" ? (
                  <p className={styles.confirmMuted}>Abra a coleção, entre em Ajustes → Onde guardo e escolha outro local.</p>
                ) : (
                  <p className={styles.confirmMuted}>
                    Hoje: {storageCardCountLabel(location.cardCount).toLowerCase()} neste local. Nada foi alterado.
                  </p>
                )}
              </>
            ) : serverBlocked ? null : (
              <p>
                Nenhuma carta ou coleção é afetada, e o histórico de criação das suas coleções continua preservado. Esta ação não
                pode ser desfeita.
              </p>
            )}
            <div aria-live="assertive">
              {failure ? <InlineFeedback tone="error">{storageFailureMessage(failure)}</InlineFeedback> : null}
            </div>
          </div>
        </DialogBody>
        <DialogFooter>
          {blocked ? (
            <Button className="min-h-11 px-5" onClick={onClose}>
              Entendi
            </Button>
          ) : (
            <>
              <Button
                variant="outline"
                className={`min-h-11 ${ARIA_DISABLED_BUTTON}`}
                aria-disabled={pending || undefined}
                onClick={() => !pending && onClose()}
              >
                Cancelar
              </Button>
              <Button
                variant="destructive"
                className={`min-h-11 gap-1.5 px-5 ${ARIA_DISABLED_BUTTON}`}
                aria-disabled={pending || undefined}
                onClick={confirm}
              >
                {pending ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Trash2 className="h-4 w-4" aria-hidden="true" />}
                {pending ? "Excluindo…" : "Excluir local"}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
