"use client";

import Link from "next/link";
import { useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { ArrowRight, ChevronDown, History, Info, LayoutGrid, LibraryBig, PawPrint, PenLine, X } from "lucide-react";
import { readBinderCollections, readBinderOccupancy, saveBinderIdentity } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  BINDER_NAME_MAX,
  buildBinderProgress,
  type BinderOccupancy,
  type BinderParticipant,
  type BinderProgressEntry,
  type BinderProgressInput,
  type ControlSection,
  type ResolvedIdentity,
  identityFailureMessage,
  nameLength,
  normalizeBinderName,
  occupancyPercent,
} from "@/lib/colecoes/binder-identity";
import { modelLabel } from "@/lib/colecoes/binder";
import type { SpeciesReferenceState } from "@/lib/colecoes/binder-species";
import { cn } from "@/lib/utils";
import { InsideCoverFace, insideCoverSurface } from "./binder-chrome";
import { BinderHistory } from "./binder-history";
import styles from "./binder-control.module.css";

const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';

export const CONTROL_PANEL_ID = "fichario-centro-de-controle";

type SaveState = { tone: "idle" } | { tone: "saving" } | { tone: "success"; text: string } | { tone: "error"; text: string };
type InfoState = { status: "idle" } | { status: "loading" } | { status: "ready"; occupancy: BinderOccupancy | null } | { status: "error" };

/**
 * Centro de Controle do Fichário (P3-A) — painel lateral direito recolhível.
 *
 * Identidade (compartilhada; só a proprietária edita), Organização (atalhos
 * para o que já existe — sem duplicar o menu esquerdo), Informações
 * (capacidade, ocupação e coleções vinculadas, lidas sob demanda) e Histórico
 * (P3-B S7, só leitura, carregado só com a seção aberta). Aparência
 * fica de fora até existir preferência real (P1).
 *
 * `mode="docked"`: coluna do grid (desktop), `role="complementary"`.
 * `mode="sheet"`: folha sobre o fichário com véu, `role="dialog"` modal, foco
 * preso. Esc fecha nos dois; o foco volta ao botão que abriu (quem chama).
 */
export function BinderControlPanel({
  mode,
  collectionId,
  collectionName,
  role,
  identity,
  columns,
  rows,
  totalPages,
  contentVersion = 0,
  layoutId = null,
  activityVersion = 0,
  onIdentitySaved,
  onClose,
  onOpenOverview,
  backAction,
  collapsed,
  onToggleSection,
  species = null,
}: {
  mode: "docked" | "sheet";
  collectionId: string;
  collectionName: string;
  role: "OWNER" | "GUEST" | null;
  identity: ResolvedIdentity;
  columns: number;
  rows: number;
  totalPages: number;
  /**
   * Muda quando o conteúdo do fichário muda nesta sessão (bolsos ocupados).
   * Junto com `totalPages`, faz Informações reler a ocupação sem recarregar a página.
   */
  contentVersion?: number;
  /** Chave do fichário (5269). `null` = sem histórico a mostrar. */
  layoutId?: string | null;
  /** Muda a cada escrita concluída no fichário nesta sessão: o Histórico relê a primeira página em silêncio. */
  activityVersion?: number;
  onIdentitySaved: (next: { displayName: string | null; name: string; showBrandMark: boolean }) => void;
  onClose: () => void;
  onOpenOverview: () => void;
  /** Caminho para os Ajustes da coleção (compartilhar/desmontar): fechar a sobreposição ou ir à página. */
  backAction: { kind: "close"; onClose: () => void } | { kind: "link"; href: string };
  collapsed: ReadonlySet<ControlSection>;
  onToggleSection: (section: ControlSection) => void;
  /** Fichário de coleção Pokédex: mostrar/ocultar os Pokémon dos bolsos vazios. `null` nos demais. */
  species?: SpeciesControl | null;
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const titleId = useId();

  // Foco vai ao painel quando a pessoa o abre (botão do cabeçalho) ou na folha
  // modal — não quando ele volta aberto por preferência ao carregar a página.
  // Na folha, Tab circula dentro dele.
  useEffect(() => {
    const panel = panelRef.current;
    if (!panel) return;
    const openedByButton = document.activeElement?.getAttribute("aria-controls") === CONTROL_PANEL_ID;
    if (mode === "sheet" || openedByButton) panel.focus({ preventScroll: true });
    if (mode !== "sheet") return;
    function onKey(event: KeyboardEvent) {
      if (event.key !== "Tab" || !panel) return;
      const items = [...panel.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null);
      const first = items[0];
      const last = items[items.length - 1];
      if (!first || !last) return;
      if (event.shiftKey && (document.activeElement === first || document.activeElement === panel)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
    panel.addEventListener("keydown", onKey);
    return () => panel.removeEventListener("keydown", onKey);
  }, [mode]);

  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      onClose();
    }
  };

  const infoOpen = !collapsed.has("info");
  const historyOpen = !collapsed.has("history");

  return (
    <>
      {mode === "sheet" ? <div className={styles.scrim} onClick={onClose} aria-hidden /> : null}
      <div
        ref={panelRef}
        id={CONTROL_PANEL_ID}
        className={cn("dark", styles.panel)}
        data-mode={mode}
        role={mode === "sheet" ? "dialog" : "complementary"}
        aria-modal={mode === "sheet" ? true : undefined}
        aria-labelledby={titleId}
        tabIndex={-1}
        onKeyDown={onKeyDown}
      >
        <div className={styles.head}>
          <div className="min-w-0">
            <h2 id={titleId} className={styles.headTitle}>
              Centro de Controle
            </h2>
            <p className={cn(styles.headSub, "truncate")}>{identity.name}</p>
          </div>
          <button type="button" className={styles.close} onClick={onClose} aria-label="Fechar o Centro de Controle (Esc)" title="Fechar (Esc)">
            <X className="h-4 w-4" aria-hidden />
          </button>
        </div>

        <div className={styles.body}>
          <Section id="identity" title="Identidade do fichário" icon={PenLine} collapsed={collapsed} onToggle={onToggleSection}>
            <IdentitySection
              collectionId={collectionId}
              collectionName={collectionName}
              role={role}
              identity={identity}
              columns={columns}
              rows={rows}
              onSaved={onIdentitySaved}
            />
            {species ? <SpeciesVisibilityRow control={species} /> : null}
          </Section>

          <Section id="organize" title="Organização" icon={LayoutGrid} collapsed={collapsed} onToggle={onToggleSection}>
            <div className={styles.facts}>
              <Fact label="Modelo" value={modelLabel(columns, rows)} />
              <Fact label="Páginas" value={formatCount(totalPages)} />
            </div>
            <p className={styles.hint}>A grade é escolhida na montagem e não muda depois. Adicionar páginas, Bandeja e seleção ficam no menu à esquerda.</p>
            <div className={styles.linkList}>
              <button type="button" className={styles.linkButton} onClick={onOpenOverview}>
                <LayoutGrid aria-hidden />
                Ver todas as páginas
                <ArrowRight aria-hidden />
              </button>
              {backAction.kind === "close" ? (
                <button type="button" className={styles.linkButton} onClick={backAction.onClose}>
                  <LibraryBig aria-hidden />
                  Voltar à coleção
                  <ArrowRight aria-hidden />
                </button>
              ) : (
                <Link href={backAction.href} className={styles.linkButton}>
                  <LibraryBig aria-hidden />
                  Voltar à coleção
                  <ArrowRight aria-hidden />
                </Link>
              )}
            </div>
            <p className={cn(styles.hint, "mt-2")}>Compartilhar o fichário com outras coleções e desmontá-lo ficam em Ajustes da coleção.</p>
          </Section>

          <Section id="info" title="Informações" icon={Info} collapsed={collapsed} onToggle={onToggleSection}>
            {infoOpen ? (
              <InfoSection collectionId={collectionId} columns={columns} rows={rows} refreshKey={`${totalPages}:${contentVersion}`} />
            ) : null}
          </Section>

          {layoutId ? (
            <Section id="history" title="Histórico" icon={History} collapsed={collapsed} onToggle={onToggleSection}>
              {historyOpen ? <BinderHistory layoutId={layoutId} refreshKey={`${totalPages}:${contentVersion}:${activityVersion}`} /> : null}
            </Section>
          ) : null}
        </div>
      </div>
    </>
  );
}

function Section({
  id,
  title,
  icon: Icon,
  collapsed,
  onToggle,
  children,
}: {
  id: ControlSection;
  title: string;
  icon: typeof Info;
  collapsed: ReadonlySet<ControlSection>;
  onToggle: (section: ControlSection) => void;
  children: React.ReactNode;
}) {
  const open = !collapsed.has(id);
  const regionId = `${CONTROL_PANEL_ID}-${id}`;
  return (
    <section className={styles.section}>
      <h3>
        <button type="button" className={styles.sectionToggle} aria-expanded={open} aria-controls={regionId} onClick={() => onToggle(id)}>
          <Icon aria-hidden />
          {title}
          <ChevronDown className={styles.chevron} aria-hidden />
        </button>
      </h3>
      <div id={regionId} className={styles.sectionBody} hidden={!open}>
        {children}
      </div>
    </section>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className={styles.fact}>
      <span className={styles.factLabel}>{label}</span>
      <span className={styles.factValue}>{value}</span>
    </div>
  );
}

/** Proporção da página do fichário (bolsos 8:11 na grade do modelo): a prévia tem a forma da contracapa real. */
function coverAspect(columns: number, rows: number): string {
  return `${columns * 8} / ${rows * 11}`;
}

function IdentitySection({
  collectionId,
  collectionName,
  role,
  identity,
  columns,
  rows,
  onSaved,
}: {
  collectionId: string;
  collectionName: string;
  role: "OWNER" | "GUEST" | null;
  identity: ResolvedIdentity;
  columns: number;
  rows: number;
  onSaved: (next: { displayName: string | null; name: string; showBrandMark: boolean }) => void;
}) {
  const inputId = useId();
  const helpId = useId();
  const [draftName, setDraftName] = useState(identity.displayName ?? "");
  const [draftMark, setDraftMark] = useState(identity.showBrandMark);
  const [save, setSave] = useState<SaveState>({ tone: "idle" });
  const [pending, startTransition] = useTransition();

  const normalized = normalizeBinderName(draftName);
  const nextName = normalized.ok ? normalized.value : null;
  const dirty = (normalized.ok ? nextName !== identity.displayName : true) || draftMark !== identity.showBrandMark;
  // Prévia ao vivo, sem gravar: o nome digitado ou, vazio, o da coleção (quem edita é sempre a proprietária).
  const fallbackName = collectionName;
  const previewName = normalized.ok ? (nextName ?? fallbackName) : draftName.trim() || fallbackName;
  const length = nameLength(draftName.replace(/\s+/g, " ").trim());
  const invalid = !normalized.ok;

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    if (!dirty || invalid || pending) return;
    setSave({ tone: "saving" });
    startTransition(async () => {
      const result = await saveBinderIdentity({ collectionId, displayName: nextName, showBrandMark: draftMark });
      if (!result.ok) {
        setSave({ tone: "error", text: identityFailureMessage(result.reason) });
        return;
      }
      // O banco devolve o estado canônico (nome já normalizado): o rascunho passa a ser ele.
      setDraftName(result.displayName ?? "");
      setDraftMark(result.showBrandMark);
      setSave({ tone: "success", text: result.changed ? "Identidade salva." : "Nada mudou — já estava assim." });
      onSaved({ displayName: result.displayName, name: result.effectiveName, showBrandMark: result.showBrandMark });
    });
  };

  const preview = (
    <>
      <div className={styles.preview} style={{ aspectRatio: coverAspect(columns, rows), ...insideCoverSurface("single") }} aria-hidden>
        <InsideCoverFace name={previewName} showBrandMark={identity.canEdit ? draftMark : identity.showBrandMark} />
      </div>
      <p className={styles.previewCaption}>Prévia da contracapa{identity.canEdit && dirty ? " · não salva" : ""}</p>
    </>
  );

  if (!identity.canEdit) {
    const reason =
      identity.source === "fallback"
        ? "A identidade do fichário ainda não está disponível. Por enquanto ele usa o nome da coleção."
        : role === "GUEST"
          ? "O nome e a contracapa são definidos pela coleção dona do fichário."
          : "Esta coleção está arquivada. Reative-a para editar o fichário.";
    return (
      <>
        {preview}
        <div className={styles.readOnly}>
          <span className={styles.readOnlyName}>{identity.name}</span>
          {reason}
        </div>
      </>
    );
  }

  return (
    <form onSubmit={submit} noValidate>
      {preview}
      <div className={styles.field}>
        <Label htmlFor={inputId}>Nome do fichário</Label>
        <Input
          id={inputId}
          value={draftName}
          onChange={(event) => {
            setDraftName(event.target.value);
            if (save.tone !== "saving") setSave({ tone: "idle" });
          }}
          placeholder={collectionName}
          maxLength={BINDER_NAME_MAX * 2}
          invalid={invalid}
          aria-describedby={helpId}
          autoComplete="off"
          spellCheck={false}
          disabled={pending}
        />
        <div id={helpId} className={styles.fieldMeta}>
          <span>{invalid ? "Use de 1 a 60 caracteres, sem quebras de linha." : "Vazio usa o nome da coleção."}</span>
          <span className={styles.counter} data-near={length > BINDER_NAME_MAX - 10 || undefined} aria-live={length >= BINDER_NAME_MAX ? "polite" : "off"}>
            {length}/{BINDER_NAME_MAX}
          </span>
        </div>
      </div>

      <div className={styles.switchRow}>
        <div className={styles.switchText}>
          <Label htmlFor={`${inputId}-mark`}>Exibir logomarca</Label>
          <span className={styles.switchHint}>Rosto do Mimikyu na contracapa.</span>
        </div>
        <Switch
          id={`${inputId}-mark`}
          checked={draftMark}
          onCheckedChange={(value) => {
            setDraftMark(value);
            if (save.tone !== "saving") setSave({ tone: "idle" });
          }}
          disabled={pending}
        />
      </div>

      <div className={styles.actions}>
        <Button
          type="button"
          variant="ghost"
          disabled={!dirty || pending}
          onClick={() => {
            setDraftName(identity.displayName ?? "");
            setDraftMark(identity.showBrandMark);
            setSave({ tone: "idle" });
          }}
        >
          Descartar
        </Button>
        <Button type="submit" disabled={!dirty || invalid || pending}>
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </div>
      <p
        className={styles.status}
        data-tone={save.tone === "success" || save.tone === "error" ? save.tone : undefined}
        role={save.tone === "error" ? "alert" : "status"}
        aria-live="polite"
      >
        {save.tone === "success" || save.tone === "error" ? save.text : save.tone === "saving" ? "Salvando…" : ""}
      </p>
      <p className={styles.hint}>Nome e logomarca valem para todas as coleções que usam este fichário.</p>
    </form>
  );
}

export type SpeciesControl = {
  state: SpeciesReferenceState;
  /** Grava a preferência (5258); devolve a mensagem de erro ou `null`. */
  onSetVisible: (visible: boolean) => Promise<string | null>;
  /** Abre o diálogo "Pokémon nos bolsos" (colocar ou remover as referências). */
  onOpen: () => void;
};

/**
 * Pokémon nos bolsos (POKEDEX-BINDER-SPECIES-REFERENCE) no Centro de Controle.
 * Mesma preferência do diálogo do menu à esquerda — os dois mostram sempre o
 * mesmo estado. Diferente de nome e logomarca, grava na hora (sem "Salvar"):
 * é só exibição, nunca apaga as referências. Sem referências ainda, a dona vê
 * o caminho para colocá-las; a convidada, só a explicação.
 */
function SpeciesVisibilityRow({ control }: { control: SpeciesControl }) {
  const switchId = useId();
  const hintId = useId();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { state } = control;
  const applied = state.referenceCount > 0;

  const toggle = async (visible: boolean) => {
    if (busy) return;
    setBusy(true);
    setError(null);
    const message = await control.onSetVisible(visible);
    setBusy(false);
    if (message) setError(message);
  };

  return (
    <div className={styles.speciesBlock}>
      {applied ? (
        <div className={styles.switchRow}>
          <div className={styles.switchText}>
            <Label htmlFor={switchId}>Exibir Pokémon nos bolsos</Label>
            <span id={hintId} className={styles.switchHint}>
              Arte, nome e número nos bolsos vazios. Muda na hora; ocultar não apaga nada.
            </span>
          </div>
          <Switch id={switchId} checked={state.visible} onCheckedChange={(value) => void toggle(value)} disabled={busy} aria-describedby={hintId} />
        </div>
      ) : (
        <div className={styles.switchText}>
          <span className={styles.speciesTitle}>Pokémon nos bolsos</span>
          <span className={styles.switchHint}>
            {state.canManage
              ? "Mostre cada Pokémon da Pokédex no bolso que espera por ele."
              : "A coleção dona do fichário ainda não colocou os Pokémon nos bolsos."}
          </span>
          {state.canManage ? (
            <button type="button" className={cn(styles.linkButton, "mt-2")} onClick={control.onOpen}>
              <PawPrint aria-hidden />
              Colocar Pokémon nos bolsos
              <ArrowRight aria-hidden />
            </button>
          ) : null}
        </div>
      )}
      <p className={styles.status} data-tone={error ? "error" : undefined} role={error ? "alert" : "status"} aria-live="polite">
        {error ?? ""}
      </p>
    </div>
  );
}

type CollectionsState =
  | { status: "loading" }
  | { status: "ready"; participants: BinderParticipant[]; progress: Readonly<Record<string, BinderProgressInput>> | null }
  | { status: "unavailable" }
  | { status: "error" };

/**
 * Informações: duas leituras independentes, em paralelo — ocupação (5245) e
 * coleções do fichário com o progresso oficial de cada uma (5246 + R1, numa
 * ida só). Uma falha não esconde a outra; cada bloco tem o próprio "tentar de novo".
 */
function InfoSection({
  collectionId,
  columns,
  rows,
  refreshKey,
}: {
  collectionId: string;
  columns: number;
  rows: number;
  /** Páginas/conteúdo do fichário: ao mudar, a ocupação é relida (capacidade e bolsos atualizados sem recarregar). */
  refreshKey: string;
}) {
  const [occupancy, setOccupancy] = useState<InfoState>({ status: "loading" });
  const [collections, setCollections] = useState<CollectionsState>({ status: "loading" });
  // Só a leitura mais recente vale: adicionar páginas em sequência dispara várias.
  const requestRef = useRef(0);

  const loadOccupancy = useCallback(
    async (silent = false) => {
      const request = ++requestRef.current;
      // Releitura por mudança no fichário mantém os números atuais à vista (sem esqueleto piscando).
      if (!silent) setOccupancy({ status: "loading" });
      const result = await readBinderOccupancy({ collectionId });
      if (request !== requestRef.current) return;
      setOccupancy((current) =>
        result.ok
          ? { status: "ready", occupancy: result.occupancy }
          : silent && current.status === "ready"
            ? current
            : { status: "error" },
      );
    },
    [collectionId],
  );

  const loadCollections = useCallback(async () => {
    setCollections({ status: "loading" });
    const result = await readBinderCollections({ collectionId });
    if (!result.ok) {
      setCollections(result.reason === "unavailable" ? { status: "unavailable" } : { status: "error" });
      return;
    }
    setCollections({ status: "ready", participants: result.participants, progress: result.progress });
  }, [collectionId]);

  useEffect(() => {
    void loadOccupancy();
    void loadCollections();
  }, [loadOccupancy, loadCollections]);

  // Páginas adicionadas/removidas ou bolsos preenchidos nesta sessão: relê a ocupação.
  const firstKey = useRef(refreshKey);
  useEffect(() => {
    if (refreshKey === firstKey.current) return;
    firstKey.current = refreshKey;
    void loadOccupancy(true);
  }, [refreshKey, loadOccupancy]);

  return (
    <>
      <CollectionsProgress state={collections} onRetry={() => void loadCollections()} />
      <OccupancyInfo state={occupancy} columns={columns} rows={rows} onRetry={() => void loadOccupancy()} />
      <h4 className={cn(styles.subTitle, "mt-4")}>Coleções neste fichário</h4>
      {collections.status === "loading" ? (
        <div aria-busy="true" aria-label="Carregando as coleções">
          <div className={styles.skeleton} style={{ width: "70%" }} />
        </div>
      ) : collections.status === "ready" ? (
        <ul className={styles.participants}>
          {collections.participants.map((p) => (
            <li key={p.collectionId} className={styles.participant} data-current={p.current || undefined}>
              {/* Só informativo (P3A-CONTROL-PARTICIPANTS-UX-CORRECTION-01): sem navegação — sair do fichário é o "Voltar à coleção" de Organização. */}
              <span className={styles.participantName} title={p.name}>
                {p.name}
              </span>
              {p.role === "OWNER" ? <span className={styles.tag}>Dona</span> : null}
              {!p.active ? <span className={styles.tag}>Arquivada</span> : null}
              <span className={styles.participantCount}>
                {formatCount(p.cards)} {p.cards === 1 ? "carta" : "cartas"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className={styles.hint}>A lista de coleções ainda não está disponível.</p>
      )}
    </>
  );
}

/**
 * Progresso das coleções do fichário (P3A-BINDER-CONTROL-MULTI-COLLECTION-PROGRESS-01).
 * Um bloco só: a dona primeiro, em destaque; convidadas abaixo, compactas,
 * separadas por fio discreto. Só leitura, sem navegação. Números oficiais de
 * cada coleção (nunca somados entre si nem tirados dos bolsos).
 */
function CollectionsProgress({ state, onRetry }: { state: CollectionsState; onRetry: () => void }) {
  const titleId = useId();
  const entries = state.status === "ready" && state.progress !== null ? buildBinderProgress(state.participants, state.progress) : [];
  const title = entries.length > 1 ? "Progresso das coleções" : "Progresso da coleção";

  let body: React.ReactNode;
  if (state.status === "loading") {
    body = (
      <div aria-busy="true" aria-label="Carregando o progresso das coleções">
        <div className={styles.skeleton} style={{ width: "55%" }} />
        <div className={styles.skeleton} style={{ width: "100%" }} />
      </div>
    );
  } else if (state.status === "error" || (state.status === "ready" && state.progress === null)) {
    body = (
      <div role="alert" className={styles.hint}>
        Não foi possível ler o progresso.{" "}
        <button type="button" className="font-semibold text-foreground underline underline-offset-2" onClick={onRetry}>
          Tentar de novo
        </button>
      </div>
    );
  } else if (state.status === "unavailable" || entries.length === 0) {
    body = <p className={styles.hint}>O progresso das coleções não está disponível.</p>;
  } else {
    body = (
      <ul className={styles.progressList}>
        {entries.map((entry) => (
          <ProgressEntry key={entry.collectionId} entry={entry} />
        ))}
      </ul>
    );
  }

  return (
    <section className={styles.progressCard} aria-labelledby={titleId}>
      <h4 id={titleId} className={styles.subTitle}>
        {title}
      </h4>
      {body}
    </section>
  );
}

function ProgressEntry({ entry }: { entry: BinderProgressEntry }) {
  const nameId = useId();
  const owner = entry.role === "OWNER";
  const v = entry.view;
  return (
    <li className={styles.progressItem} data-role={owner ? "owner" : "guest"}>
      <div className={styles.progressHead}>
        <span id={nameId} className={styles.progressName} title={entry.name}>
          {entry.name}
        </span>
        <span className={styles.tag}>{owner ? "Dona" : "Convidada"}</span>
        {v?.kind === "goal" && v.complete ? (
          <span className={styles.tag} data-tone="gold">
            Completa
          </span>
        ) : null}
        {v?.archived ? <span className={styles.tag}>Arquivada</span> : null}
      </div>
      {v === null ? (
        <p className={styles.hint}>Progresso indisponível.</p>
      ) : v.kind === "free" ? (
        <p className={styles.hint}>Coleção livre: sem total previsto.</p>
      ) : (
        <>
          <div className={styles.progressMeta}>
            <span className={styles.factLabel}>{v.label}</span>
            <span className={styles.progressPercent}>{v.percentText}</span>
          </div>
          <div
            className={cn(styles.track, styles.progressTrack)}
            role="progressbar"
            aria-valuemin={0}
            aria-valuemax={v.total}
            aria-valuenow={v.satisfied}
            aria-valuetext={`${v.label} (${v.percentText})`}
            aria-labelledby={nameId}
          >
            <div className={cn(styles.fill, styles.progressFill)} style={{ transform: `scaleX(${v.barPercent / 100})` }} />
          </div>
        </>
      )}
    </li>
  );
}

function OccupancyInfo({ state, columns, rows, onRetry }: { state: InfoState; columns: number; rows: number; onRetry: () => void }) {
  if (state.status === "idle" || state.status === "loading") {
    return (
      <div aria-busy="true" aria-label="Carregando informações">
        <div className={styles.skeleton} style={{ width: "60%" }} />
        <div className={styles.skeleton} style={{ width: "100%" }} />
        <div className={styles.skeleton} style={{ width: "80%" }} />
      </div>
    );
  }
  if (state.status === "error") {
    return (
      <div role="alert" className={styles.hint}>
        Não foi possível ler as informações do fichário.{" "}
        <button type="button" className="font-semibold text-foreground underline underline-offset-2" onClick={onRetry}>
          Tentar de novo
        </button>
      </div>
    );
  }
  const o = state.occupancy;
  if (!o) return <p className={styles.hint}>As informações deste fichário não estão disponíveis.</p>;
  const perPage = columns * rows;
  const percent = occupancyPercent(o);
  const rowsInfo: { label: string; value: number; color: string; hint?: string }[] = [
    { label: "Com carta", value: o.cards, color: "hsl(var(--primary))" },
    { label: "Com imagem", value: o.images, color: "hsl(var(--primary) / 0.55)" },
    {
      label: "Em imagens de 2 bolsos",
      value: o.merged,
      color: "hsl(var(--primary) / 0.3)",
      hint: o.mergedRegions > 0 ? `${formatCount(o.mergedRegions)} ${o.mergedRegions === 1 ? "imagem" : "imagens"}` : undefined,
    },
    { label: "Reservados vazios", value: o.reservedEmpty, color: "hsl(var(--foreground) / 0.35)" },
    { label: "Livres", value: o.free, color: "hsl(var(--foreground) / 0.12)" },
  ];
  return (
    <>
      <div className={styles.facts}>
        <Fact label="Capacidade" value={`${formatCount(o.pages)} × ${formatCount(perPage)} = ${formatCount(o.pockets)} bolsos`} />
      </div>
      <div className={styles.meter}>
        <div className={styles.meterHead}>
          <span className={styles.factLabel}>Bolsos ocupados</span>
          <span className={styles.meterValue}>{percent}%</span>
        </div>
        <div
          className={styles.track}
          role="meter"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-label={`Bolsos ocupados: ${percent}%`}
        >
          <div className={styles.fill} style={{ transform: `scaleX(${percent / 100})` }} />
        </div>
      </div>
      <div className={styles.breakdown}>
        {rowsInfo.map((row) => (
          <div key={row.label} className={styles.fact}>
            <span className={styles.factLabel}>
              <span className={styles.swatch} style={{ background: row.color }} aria-hidden />
              {row.label}
              {row.hint ? <span className="ml-1 text-[0.6875rem]">({row.hint})</span> : null}
            </span>
            <span className={styles.factValue}>{formatCount(row.value)}</span>
          </div>
        ))}
      </div>
      <p className={styles.hint}>Cada bolso conta uma vez. Reservado com carta conta como &ldquo;Com carta&rdquo;.</p>
    </>
  );
}
