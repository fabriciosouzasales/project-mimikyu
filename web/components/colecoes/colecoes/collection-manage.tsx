"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, createContext, useCallback, useContext, useEffect, useId, useRef, useState, useTransition } from "react";
import { CheckCircle2, FolderInput, Layers, Loader2, Settings2, X } from "lucide-react";
import {
  type CardCopiesQuery,
  readCardCopiesInCollection,
  readCollectionStorage,
  setCollectionStorage,
  unlinkCopyFromCollection,
} from "@/app/colecoes/colecoes/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { Select } from "@/components/ui/select";
import { formatCount } from "@/lib/colecoes/acervo";
import { type BinderFinish, finishLabel } from "@/lib/colecoes/binder-finish";
import { type CollectionFailure, type StorageOption, collectionFailureMessage } from "@/lib/colecoes/colecoes";
import {
  type CollectionCopy,
  type CopyGroup,
  addedLabel,
  copyTitle,
  groupLabel,
  removalAffectsProgress,
  storageLabel,
  totalCopies,
  withoutCopy,
} from "@/lib/colecoes/collection-manage";
import { type ProposalOrigin, laterActionLabel } from "@/lib/colecoes/collection-organize";
import { MASTER_SET_OBJECTIVE_ENABLED } from "@/lib/colecoes/master-set";
import { CardArt } from "../acervo/card-art";
import { SharedBinderSettingsSection } from "../fichario/binder-share-settings";
import { IdentityCoverImage, IdentityNameForm } from "./collection-identity-settings";
import { ArchiveCollectionSection } from "./collection-lifecycle";
import { CoverFinishPicker } from "./cover-finish-picker";
import { CollectionObjectiveSection } from "./collection-objective";
import { OrganizeStorageFlow } from "./collection-organize";
import { PokedexGenerationsSection } from "./pokedex-generations";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import styles from "./collection-manage.module.css";

/**
 * Gerenciar a coleção (COLLECTION-MANAGEMENT-RECOVERY-01) — duas superfícies
 * pequenas, no padrão do painel lateral do Meu acervo:
 *
 * 1. **Exemplares da carta** — botão discreto em cada carta da galeria. Mostra
 *    os exemplares DESTA coleção (versão, idioma, número, local físico) e tira
 *    um exemplar específico com uma confirmação no próprio item (`5047`).
 * 2. **Ajustes da coleção** — botão "Ajustes" no topo da página. Identidade em
 *    leitura (cada controle continua onde já funciona), Objetivo — Set padrão ↔
 *    Master Set, só coleção de Set, atrás de `MASTER_SET_OBJECTIVE_ENABLED`
 *    (MASTER-SET-FRONTEND-PHASE-01) — e Onde guardo (`5036`).
 *
 * Nada aqui move carta de lugar, apaga exemplar ou toca outra coleção.
 */

type CollectionKind = "card_set" | "free" | "pokedex";

type CardTarget = {
  /** Consulta sem o id da coleção (vem do provider). */
  query: { kind: "group"; cardVariantId: string; languageCode: string } | { kind: "set_card"; setCode: string; collectorNumber: string };
  cardName: string;
  caption: string;
  imageUrl: string | null;
};

type ManageContextValue = { openCard: (target: CardTarget) => void };

const ManageContext = createContext<ManageContextValue | null>(null);

export function CollectionManageProvider({
  collectionId,
  collectionName,
  kind,
  children,
}: {
  collectionId: string;
  collectionName: string;
  kind: CollectionKind;
  children: ReactNode;
}) {
  const [target, setTarget] = useState<CardTarget | null>(null);
  const value = { openCard: setTarget };
  return (
    <ManageContext.Provider value={value}>
      {children}
      {target ? (
        <CopiesPanel
          collectionId={collectionId}
          collectionName={collectionName}
          kind={kind}
          target={target}
          onClose={() => setTarget(null)}
        />
      ) : null}
    </ManageContext.Provider>
  );
}

/** Botão discreto no canto da carta. Sem provider (coleção arquivada), não aparece. */
export function ManageCopiesButton({ target }: { target: CardTarget }) {
  const manage = useContext(ManageContext);
  if (!manage) return null;
  return (
    <button
      type="button"
      className={styles.tileAction}
      onClick={() => manage.openCard(target)}
      aria-label={`Exemplares de ${target.cardName} nesta coleção`}
      title="Exemplares nesta coleção"
    >
      <Layers className="h-4 w-4" aria-hidden="true" />
    </button>
  );
}

// ---------------------------------------------------------------------------
// Painel: exemplares da carta nesta coleção
// ---------------------------------------------------------------------------

type LoadState =
  | { status: "loading" }
  | { status: "error"; reason: CollectionFailure }
  | { status: "ready"; groups: CopyGroup[] };

function CopiesPanel({
  collectionId,
  collectionName,
  kind,
  target,
  onClose,
}: {
  collectionId: string;
  collectionName: string;
  kind: CollectionKind;
  target: CardTarget;
  onClose: () => void;
}) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const [state, setState] = useState<LoadState>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [confirming, setConfirming] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [rowError, setRowError] = useState<{ id: string; reason: CollectionFailure } | null>(null);
  const [removed, setRemoved] = useState<{ title: string; count: number } | null>(null);
  const [announce, setAnnounce] = useState("");
  const [, startRefresh] = useTransition();

  useEffect(() => {
    let alive = true;
    setState({ status: "loading" });
    const query: CardCopiesQuery = { ...target.query, collectionId };
    readCardCopiesInCollection(query)
      .then((result) => {
        if (!alive) return;
        setState(result.ok ? { status: "ready", groups: result.groups } : { status: "error", reason: result.reason });
      })
      .catch(() => alive && setState({ status: "error", reason: "unavailable" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId, target]);

  const groups = state.status === "ready" ? state.groups : [];
  const count = totalCopies(groups);

  const remove = async (copy: CollectionCopy) => {
    setBusy(copy.physicalCardId);
    setRowError(null);
    const result = await unlinkCopyFromCollection({ collectionId, physicalCardId: copy.physicalCardId }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    setBusy(null);
    if (!result.ok) {
      if (result.reason === "not_linked") {
        // O exemplar já tinha saído (outra aba, outro dispositivo): relê a lista e a página.
        setAnnounce(collectionFailureMessage("not_linked"));
        setRemoved(null);
        setConfirming(null);
        setAttempt((n) => n + 1);
        startRefresh(() => router.refresh());
        return;
      }
      setRowError({ id: copy.physicalCardId, reason: result.reason });
      return;
    }
    const next = withoutCopy(groups, copy.physicalCardId);
    setState({ status: "ready", groups: next });
    setConfirming(null);
    const title = copyTitle(copy);
    setRemoved({ title, count: totalCopies(next) });
    setAnnounce(`${title} de ${target.cardName} saiu de ${collectionName}. Continua no seu acervo, no mesmo lugar.`);
    // Indicadores, galeria e progresso vêm do servidor — sem recarregar a página.
    startRefresh(() => router.refresh());
  };

  const locked = busy !== null;

  return (
    <DialogPrimitive.Root open onOpenChange={(open) => !open && !locked && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${styles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => locked && event.preventDefault()}
          onPointerDownOutside={(event) => locked && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <PanelHeader title="Exemplares nesta coleção" subtitle={collectionName} disabled={locked} />
          <p className="sr-only" role="status" aria-live="polite">
            {announce}
          </p>

          <div className={styles.body}>
            <div className={styles.cardHead}>
              <div className={styles.cardArt}>
                <CardArt src={target.imageUrl} alt="" name={target.cardName} caption={target.caption} sizes="6rem" />
              </div>
              <div className="min-w-0">
                <p className={styles.cardName}>{target.cardName}</p>
                <p className={styles.cardCaption}>{target.caption}</p>
                {state.status === "ready" ? (
                  <p className={styles.cardCount}>
                    <strong>{formatCount(count)}</strong> {count === 1 ? "exemplar nesta coleção" : "exemplares nesta coleção"}
                  </p>
                ) : null}
              </div>
            </div>

            {removed ? (
              <InlineFeedback tone="success">
                {removed.title} saiu da coleção e continua no seu acervo, no mesmo lugar.
              </InlineFeedback>
            ) : null}

            <p className={styles.note}>
              Tirar da coleção só desfaz a ligação com <strong>{collectionName}</strong>. O exemplar continua no seu acervo,
              guardado onde está — nada é apagado e nenhuma outra coleção muda.
            </p>

            {state.status === "loading" ? (
              <div className={styles.copyList} aria-busy="true" aria-label="Carregando exemplares">
                <div className={styles.skeleton} />
                <div className={styles.skeleton} />
              </div>
            ) : state.status === "error" ? (
              <div className="flex flex-col gap-3" role="alert">
                <InlineFeedback tone="error">{readFailureText(state.reason)}</InlineFeedback>
                <Button variant="outline" className="min-h-11 self-start" onClick={() => setAttempt((n) => n + 1)}>
                  Tentar novamente
                </Button>
              </div>
            ) : groups.length === 0 ? (
              <div className="flex flex-col gap-3">
                <p className={styles.note}>
                  {removed
                    ? "Não restou nenhum exemplar desta carta nesta coleção."
                    : "Nenhum exemplar desta carta está nesta coleção agora."}
                </p>
                <Button variant="outline" className="min-h-11 self-start" onClick={onClose}>
                  Fechar
                </Button>
              </div>
            ) : (
              groups.map((group) => (
                <section key={`${group.cardVariantId}.${group.languageCode}`} aria-label={groupLabel(group)}>
                  <h3 className={styles.groupTitle}>{groupLabel(group)}</h3>
                  <ul className={styles.copyList}>
                    {group.copies.map((copy) => (
                      <CopyItem
                        key={copy.physicalCardId}
                        copy={copy}
                        collectionName={collectionName}
                        confirming={confirming === copy.physicalCardId}
                        busy={busy === copy.physicalCardId}
                        disabled={locked && busy !== copy.physicalCardId}
                        affectsProgress={removalAffectsProgress(kind === "card_set" ? "card_set" : "free", count)}
                        error={rowError?.id === copy.physicalCardId ? rowError.reason : null}
                        onAsk={() => {
                          setRowError(null);
                          setConfirming(copy.physicalCardId);
                        }}
                        onCancel={() => setConfirming(null)}
                        onConfirm={() => remove(copy)}
                      />
                    ))}
                  </ul>
                </section>
              ))
            )}
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function CopyItem({
  copy,
  collectionName,
  confirming,
  busy,
  disabled,
  affectsProgress,
  error,
  onAsk,
  onCancel,
  onConfirm,
}: {
  copy: CollectionCopy;
  collectionName: string;
  confirming: boolean;
  busy: boolean;
  disabled: boolean;
  affectsProgress: boolean;
  error: CollectionFailure | null;
  onAsk: () => void;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const title = copyTitle(copy);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const askRef = useRef<HTMLButtonElement>(null);
  const wasConfirming = useRef(false);

  // Foco acompanha a confirmação: vai para "Tirar" ao abrir e volta ao botão ao cancelar.
  useEffect(() => {
    if (confirming) confirmRef.current?.focus();
    else if (wasConfirming.current) askRef.current?.focus();
    wasConfirming.current = confirming;
  }, [confirming]);

  const added = addedLabel(copy.addedAt);
  return (
    <li className={styles.copy} data-confirming={confirming || undefined}>
      <div className={styles.copyRow}>
        <div className="min-w-0">
          <p className={styles.copyTitle}>{title}</p>
          <p className={styles.copyMeta}>
            <span>{storageLabel(copy.storageName)}</span>
            {added ? <span>{added}</span> : null}
          </p>
        </div>
        {!confirming ? (
          <Button ref={askRef} variant="outline" className="min-h-11 shrink-0" onClick={onAsk} disabled={disabled}>
            Tirar da coleção
          </Button>
        ) : null}
      </div>
      {confirming ? (
        <div className={styles.confirm}>
          <p className={styles.confirmText}>
            Tirar o <strong>{title}</strong> de {collectionName}? Ele continua no seu acervo, no mesmo lugar.
          </p>
          {affectsProgress ? (
            <p className={styles.confirmWarn}>É o único exemplar desta carta na coleção: ela volta a aparecer em “Faltam”.</p>
          ) : null}
          <div className={styles.confirmActions}>
            <Button ref={confirmRef} className="min-h-11" onClick={onConfirm} disabled={busy}>
              {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
              {busy ? "Tirando…" : "Tirar da coleção"}
            </Button>
            <Button variant="outline" className="min-h-11" onClick={onCancel} disabled={busy}>
              Cancelar
            </Button>
          </div>
        </div>
      ) : null}
      {error ? (
        <div className="mt-3" role="alert">
          <InlineFeedback tone="error">{unlinkFailureText(error)}</InlineFeedback>
        </div>
      ) : null}
    </li>
  );
}

// ---------------------------------------------------------------------------
// Ajustes da coleção
// ---------------------------------------------------------------------------

type Identity = {
  name: string;
  finish: BinderFinish;
  finishEditable: boolean;
  /** Só Coleção livre; `undefined` = não se aplica. */
  coverCode?: string | null;
  /** Só Coleção livre; `undefined` = não se aplica. */
  hasCoverImage?: boolean;
  /** Coleção de Set: nome do Set (identidade oficial, não editável). */
  setName?: string | null;
  /** Dono da sessão — pasta do envio da imagem da capa; ausente = envio indisponível. */
  userId?: string | null;
};

export function CollectionSettingsButton({
  collectionId,
  collectionName,
  kind,
  identity,
}: {
  collectionId: string;
  collectionName: string;
  kind: CollectionKind;
  identity: Identity;
}) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={styles.settingsButton} onClick={() => setOpen(true)} aria-haspopup="dialog">
        <Settings2 className="h-4 w-4" aria-hidden="true" />
        Ajustes
      </button>
      {open ? (
        <SettingsPanel
          collectionId={collectionId}
          collectionName={collectionName}
          kind={kind}
          identity={identity}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}

type StorageState =
  | { status: "loading" }
  | { status: "error"; reason: CollectionFailure }
  | { status: "ready"; current: string | null; locations: StorageOption[] };

function SettingsPanel({
  collectionId,
  collectionName,
  kind,
  identity,
  onClose,
}: {
  collectionId: string;
  collectionName: string;
  kind: CollectionKind;
  identity: Identity;
  onClose: () => void;
}) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const selectId = useId();
  const helpId = useId();
  const [storage, setStorage] = useState<StorageState>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [choice, setChoice] = useState<string>("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<CollectionFailure | null>(null);
  const [objectiveBusy, setObjectiveBusy] = useState(false);
  // A3: um sinal por controle de identidade (nome/código, imagem, cor), combinados
  // abaixo — um não apaga o outro.
  const [nameBusy, setNameBusy] = useState(false);
  const [imageBusy, setImageBusy] = useState(false);
  const [finishBusy, setFinishBusy] = useState(false);
  // WHERE-05A: organização física em lote, sempre por escolha explícita (nunca ao salvar o padrão).
  const [organize, setOrganize] = useState<{ origin: ProposalOrigin; key: number } | null>(null);
  const [organizeBusy, setOrganizeBusy] = useState(false);
  const [destinationNotice, setDestinationNotice] = useState<string | null>(null);
  // P2-SHARED-BINDER-FRONTEND-01: sair do fichário compartilhado (só convidadas).
  const [shareBusy, setShareBusy] = useState(false);
  // V1-04: arquivar a coleção (última seção; o painel some quando a página volta arquivada).
  const [lifecycleBusy, setLifecycleBusy] = useState(false);
  const [, startRefresh] = useTransition();

  const load = useCallback(() => setAttempt((n) => n + 1), []);

  useEffect(() => {
    let alive = true;
    setStorage({ status: "loading" });
    readCollectionStorage({ collectionId })
      .then((result) => {
        if (!alive) return;
        if (!result.ok) {
          setStorage({ status: "error", reason: result.reason });
          return;
        }
        setStorage({ status: "ready", current: result.storageId, locations: result.locations });
        setChoice(result.storageId ?? "");
      })
      .catch(() => alive && setStorage({ status: "error", reason: "unavailable" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId]);

  const current = storage.status === "ready" ? storage.current : null;
  const locations = storage.status === "ready" ? storage.locations : [];
  const currentLocation = locations.find((location) => location.id === current) ?? null;
  const currentName = currentLocation?.name ?? null;
  const dirty = storage.status === "ready" && choice !== "" && choice !== current;

  const save = async () => {
    if (!dirty) return;
    setSaving(true);
    setSaveError(null);
    setSaved(null);
    const result = await setCollectionStorage({ collectionId, storageContainerId: choice }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    setSaving(false);
    if (!result.ok) {
      setSaveError(result.reason);
      if (result.reason === "storage_invalid") load();
      return;
    }
    setStorage({ status: "ready", current: result.storageId, locations });
    setSaved(locations.find((location) => location.id === result.storageId)?.name ?? "o local escolhido");
    setDestinationNotice(null);
    // A preferência já está salva; só agora o fluxo pergunta se o colecionador quer organizar.
    setOrganize({ origin: "after_save", key: Date.now() });
    startRefresh(() => router.refresh());
  };

  const isFree = kind === "free";
  const isPokedex = kind === "pokedex";
  // Fechar o painel no meio de uma gravação deixaria o resultado sem feedback.
  const locked = saving || objectiveBusy || nameBusy || imageBusy || finishBusy || organizeBusy || shareBusy || lifecycleBusy;

  return (
    <DialogPrimitive.Root open onOpenChange={(open) => !open && !locked && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${styles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => locked && event.preventDefault()}
          onPointerDownOutside={(event) => locked && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <PanelHeader title="Ajustes da coleção" subtitle={collectionName} disabled={locked} />

          <div className={styles.body}>
            <section className={styles.section} aria-labelledby="ajustes-identidade">
              <h3 id="ajustes-identidade" className={styles.sectionTitle}>
                Identidade
              </h3>
              {/* UX-06: nome, código, imagem e cor do fichário são editados aqui, não mais na página. */}
              <IdentityNameForm
                collectionId={collectionId}
                name={identity.name}
                coverCode={isFree || isPokedex ? identity.coverCode : undefined}
                onBusyChange={setNameBusy}
              />
              {(isFree || isPokedex) && identity.hasCoverImage !== undefined && identity.userId ? (
                <IdentityCoverImage
                  collectionId={collectionId}
                  userId={identity.userId}
                  hasLogo={identity.hasCoverImage}
                  onBusyChange={setImageBusy}
                />
              ) : null}
              {identity.finishEditable ? (
                <div className={styles.finishRow}>
                  <CoverFinishPicker collectionId={collectionId} value={identity.finish} onBusyChange={setFinishBusy} />
                </div>
              ) : null}
              {(!isFree && identity.setName) || isPokedex || !identity.finishEditable ? (
                <dl className={styles.facts}>
                  {!isFree && identity.setName ? <Fact label="Set" value={identity.setName} hint="Identidade oficial do Set." /> : null}
                  {isPokedex ? <Fact label="Universo" value="Pokédex Nacional" hint="Uma carta de cada Pokémon conquista a posição." /> : null}
                  {!identity.finishEditable ? <Fact label="Cor do fichário" value={finishLabel(identity.finish)} /> : null}
                </dl>
              ) : null}
            </section>

            {kind === "card_set" && MASTER_SET_OBJECTIVE_ENABLED ? (
              <CollectionObjectiveSection collectionId={collectionId} onBusyChange={setObjectiveBusy} />
            ) : null}

            {isPokedex ? <PokedexGenerationsSection collectionId={collectionId} onBusyChange={setObjectiveBusy} /> : null}

            <section className={styles.section} aria-labelledby="ajustes-onde-guardo">
              <h3 id="ajustes-onde-guardo" className={styles.sectionTitle}>
                Onde guardo
              </h3>
              <p id={helpId} className={styles.note}>
                É o lugar sugerido para guardar as cartas desta coleção. Trocar aqui não move nenhuma carta: cada exemplar
                continua registrado onde está hoje.
              </p>
              {storage.status === "loading" ? (
                <div className={styles.skeleton} aria-busy="true" aria-label="Carregando locais" />
              ) : storage.status === "error" ? (
                <div className="flex flex-col gap-3" role="alert">
                  <InlineFeedback tone="error">{readFailureText(storage.reason)}</InlineFeedback>
                  <Button variant="outline" className="min-h-11 self-start" onClick={load}>
                    Tentar novamente
                  </Button>
                </div>
              ) : locations.length === 0 ? (
                <p className={styles.note}>Você ainda não tem nenhum local cadastrado.</p>
              ) : (
                <form
                  className={styles.storageForm}
                  onSubmit={(event) => {
                    event.preventDefault();
                    void save();
                  }}
                >
                  <label htmlFor={selectId} className={addStyles.sectionTitle}>
                    Local padrão {currentName ? <span className="font-normal text-muted-foreground">· hoje: {currentName}</span> : null}
                  </label>
                  <div className={styles.storageRow}>
                    <Select
                      id={selectId}
                      value={choice}
                      aria-describedby={helpId}
                      disabled={saving || organizeBusy}
                      onChange={(event) => {
                        setChoice(event.target.value);
                        setSaved(null);
                        setSaveError(null);
                        setDestinationNotice(null);
                        setOrganize(null);
                      }}
                    >
                      {current === null ? <option value="">Escolha um local</option> : null}
                      {locations.map((location) => (
                        <option key={location.id} value={location.id}>
                          {location.name}
                        </option>
                      ))}
                    </Select>
                    <Button type="submit" className="min-h-11" disabled={!dirty || saving || organizeBusy}>
                      {saving ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
                      {saving ? "Salvando…" : "Salvar"}
                    </Button>
                  </div>
                  <div aria-live="polite">
                    {saved ? (
                      <InlineFeedback tone="success">
                        <span>
                          Local padrão agora é <strong>{saved}</strong>. Nenhuma carta mudou de lugar.
                        </span>
                      </InlineFeedback>
                    ) : null}
                    {saveError ? <InlineFeedback tone="error">{storageFailureText(saveError)}</InlineFeedback> : null}
                    {destinationNotice ? <InlineFeedback tone="warning">{destinationNotice}</InlineFeedback> : null}
                  </div>
                </form>
              )}
              {storage.status === "ready" && currentLocation && !dirty ? (
                organize ? (
                  <OrganizeStorageFlow
                    key={organize.key}
                    collectionId={collectionId}
                    collectionName={collectionName}
                    target={{ id: currentLocation.id, name: currentLocation.name, kindCode: currentLocation.kindCode ?? null }}
                    origin={organize.origin}
                    onBusyChange={setOrganizeBusy}
                    onDismiss={() => {
                      setOrganizeBusy(false);
                      setOrganize(null);
                    }}
                    onDefaultChanged={(message) => {
                      setOrganizeBusy(false);
                      setOrganize(null);
                      setSaved(null);
                      setDestinationNotice(message);
                      load();
                    }}
                  />
                ) : (
                  <Button
                    variant="outline"
                    className="min-h-11 self-start"
                    onClick={() => {
                      setDestinationNotice(null);
                      setOrganize({ origin: "later", key: Date.now() });
                    }}
                  >
                    <FolderInput className="mr-1.5 h-4 w-4" aria-hidden="true" />
                    {laterActionLabel(currentLocation.kindCode)}
                  </Button>
                )
              ) : null}
            </section>

            <SharedBinderSettingsSection collectionId={collectionId} onBusyChange={setShareBusy} />

            {isPokedex ? null : (
              <p className={`${styles.note} flex items-start gap-2`}>
                <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
                {isFree
                  ? "Para tirar uma carta, use o botão de exemplares no canto de cada carta da coleção."
                  : "Para tirar uma carta, use o botão de exemplares no canto de cada carta que você tem."}
              </p>
            )}

            <ArchiveCollectionSection collectionId={collectionId} collectionName={collectionName} onBusyChange={setLifecycleBusy} />
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function Fact({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className={styles.fact}>
      <dt className={styles.factLabel}>{label}</dt>
      <dd className={styles.factValue}>{value}</dd>
      {hint ? <dd className={styles.factHint}>{hint}</dd> : null}
    </div>
  );
}

function PanelHeader({ title, subtitle, disabled }: { title: string; subtitle: string; disabled: boolean }) {
  return (
    <div className={acervoStyles.drawerHeader}>
      <div className="min-w-0">
        <DialogPrimitive.Title className={addStyles.panelTitle}>{title}</DialogPrimitive.Title>
        <p className="truncate text-xs text-muted-foreground">{subtitle}</p>
      </div>
      <DialogPrimitive.Close
        disabled={disabled}
        className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
        aria-label="Fechar"
      >
        <X className="h-4 w-4" aria-hidden="true" />
      </DialogPrimitive.Close>
    </div>
  );
}

function readFailureText(reason: CollectionFailure): string {
  if (reason === "not_authenticated") return collectionFailureMessage(reason);
  if (reason === "not_found") return "Esta coleção não está disponível.";
  return "Não conseguimos carregar agora. Nada foi alterado — tente novamente.";
}

function unlinkFailureText(reason: CollectionFailure): string {
  if (reason === "not_authenticated") return collectionFailureMessage(reason);
  if (reason === "not_found") return "Esta coleção não aceita mudanças agora (pode ter sido arquivada). Nada foi alterado.";
  return "Não foi possível tirar o exemplar. Nada foi alterado — tente novamente.";
}

function storageFailureText(reason: CollectionFailure): string {
  if (reason === "storage_invalid") return "Esse local não está mais disponível. A lista foi atualizada — escolha outro.";
  if (reason === "not_found") return "Esta coleção não aceita mudanças agora (pode ter sido arquivada). Nada foi alterado.";
  if (reason === "not_authenticated") return collectionFailureMessage(reason);
  return "Não foi possível salvar. O local padrão continua o mesmo — tente novamente.";
}
