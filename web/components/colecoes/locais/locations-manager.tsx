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
import {
  Archive,
  BookOpen,
  Box,
  Briefcase,
  Folder,
  Loader2,
  Lock,
  MapPin,
  Package,
  PackageOpen,
  Pencil,
  Plus,
  Star,
  Trash2,
  Vault,
  X,
  type LucideIcon,
} from "lucide-react";
import { createStorageLocation, deleteStorageLocation, updateStorageLocation } from "@/app/colecoes/locais/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { Dialog, DialogBody, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  STORAGE_NAME_MAX,
  type StorageFailure,
  type StorageKind,
  type StorageLocation,
  kindOptionsFor,
  normalizeStorageName,
  storageCardCountLabel,
  storageDefaultLabel,
  storageDeleteBlock,
  storageDeleteBlockMessage,
  storageEditChanged,
  storageFailureMessage,
  storageStackTier,
  storageSuccessMessage,
} from "@/lib/colecoes/storage-locations";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import manageStyles from "../colecoes/collection-manage.module.css";
import styles from "./locais.module.css";

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

type Panel = { kind: "create" } | { kind: "edit"; location: StorageLocation } | { kind: "delete"; location: StorageLocation };

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

/** Ícone por tipo — só apresentação; o rótulo e a lista vêm do banco. Tipo novo cai no genérico. */
const KIND_ICONS: Record<string, LucideIcon> = {
  BINDER: BookOpen,
  BOX: Box,
  FOLDER: Folder,
  DECK_BOX: Package,
  ETB: PackageOpen,
  CASE: Briefcase,
  SAFE: Vault,
  OTHER: Archive,
};

function kindIcon(code: string | null): LucideIcon {
  return (code && KIND_ICONS[code]) || MapPin;
}

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
export function NewLocationButton({ label = "Novo local" }: { label?: string }) {
  const { open } = useManager();
  return (
    <Button className="min-h-11 gap-1.5 px-5" onClick={() => open({ kind: "create" })} aria-haspopup="dialog">
      <Plus className="h-4 w-4" aria-hidden="true" />
      {label}
    </Button>
  );
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

/** Grade de locais (ordem do banco: nome, sem distinção de maiúsculas). */
export function LocationGrid({ locations }: { locations: StorageLocation[] }) {
  const { patches, removed, refreshing } = useManager();
  const visible = locations.filter((location) => !removed.has(location.id)).map((location) => ({ ...location, ...patches[location.id] }));
  return (
    <ul className={styles.grid} aria-labelledby="locais-lista" aria-busy={refreshing || undefined}>
      {visible.map((location) => (
        <LocationTile key={location.id} location={location} />
      ))}
    </ul>
  );
}

function LocationTile({ location }: { location: StorageLocation }) {
  const { open, highlightId } = useManager();
  const reasonId = useId();
  const Icon = kindIcon(location.kindCode);
  const block = storageDeleteBlock(location);
  const defaultLabel = storageDefaultLabel(location.defaultCollectionCount);
  const count = location.cardCount;
  const isNew = highlightId === location.id;
  const editRef = useRef<HTMLButtonElement>(null);

  // Local recém-criado: se o foco se perdeu (o botão do estado vazio sumiu), ele vem para o novo local.
  useEffect(() => {
    if (isNew && (document.activeElement === null || document.activeElement === document.body)) editRef.current?.focus();
  }, [isNew]);

  return (
    <li className={styles.tile} data-new={isNew || undefined}>
      <div className={styles.tileHead}>
        <span className={styles.kindMark} aria-hidden="true">
          <Icon className="h-5 w-5" strokeWidth={1.75} />
        </span>
        <div className={styles.tileTitles}>
          <h3 className={styles.tileName}>{location.name}</h3>
          <p className={location.kindLabel ? styles.tileKind : `${styles.tileKind} ${styles.tileKindNone}`}>
            {location.kindLabel ?? "Sem tipo definido"}
          </p>
        </div>
        <CardStack tier={storageStackTier(count)} />
      </div>

      <p className={styles.tileCount}>
        <span className={count === 0 ? `${styles.tileNumber} ${styles.tileNumberEmpty}` : styles.tileNumber}>{formatCount(count)}</span>
        <span>{count === 0 ? "exemplares · vazio" : count === 1 ? "exemplar guardado aqui" : "exemplares guardados aqui"}</span>
      </p>

      {defaultLabel ? (
        <p className={styles.badge}>
          <Star className="h-3.5 w-3.5" aria-hidden="true" />
          {defaultLabel}
        </p>
      ) : null}

      <div className={styles.tileFoot}>
        <div className={styles.tileActions}>
          <Button
            ref={editRef}
            variant="outline"
            className="min-h-11 gap-1.5"
            onClick={() => open({ kind: "edit", location })}
            aria-haspopup="dialog"
            aria-label={`Editar ${location.name}`}
          >
            <Pencil className="h-4 w-4" aria-hidden="true" />
            Editar
          </Button>
          <Button
            variant="ghost"
            className="min-h-11 gap-1.5 text-muted-foreground hover:text-foreground"
            onClick={() => open({ kind: "delete", location })}
            aria-haspopup="dialog"
            aria-label={`Excluir ${location.name}`}
            aria-describedby={block ? reasonId : undefined}
          >
            {block ? <Lock className="h-4 w-4" aria-hidden="true" /> : <Trash2 className="h-4 w-4" aria-hidden="true" />}
            Excluir
          </Button>
        </div>
        {block ? (
          <p id={reasonId} className={styles.tileReason}>
            <Lock className="h-3.5 w-3.5" aria-hidden="true" />
            {block === "has_cards"
              ? "Para excluir, o local precisa estar vazio."
              : "Para excluir, troque antes o local padrão da coleção."}
          </p>
        ) : null}
      </div>
    </li>
  );
}

/** 0 = contorno tracejado (vazio); 1–3 silhuetas em leque. Puramente decorativo. */
function CardStack({ tier }: { tier: 0 | 1 | 2 | 3 }) {
  return (
    <svg className={styles.stack} viewBox="0 0 44 44" aria-hidden="true" focusable="false">
      {tier === 0 ? (
        <rect className={styles.stackEmpty} x="13" y="6" width="22" height="30" rx="2.5" />
      ) : (
        <>
          {tier >= 3 ? <rect className={styles.stackCard} x="13" y="6" width="22" height="30" rx="2.5" transform="rotate(-14 24 21)" /> : null}
          {tier >= 2 ? <rect className={styles.stackCard} x="13" y="6" width="22" height="30" rx="2.5" transform="rotate(-6 24 21)" /> : null}
          <rect className={styles.stackCard} x="13" y="7" width="22" height="30" rx="2.5" transform="rotate(4 24 22)" />
        </>
      )}
    </svg>
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
