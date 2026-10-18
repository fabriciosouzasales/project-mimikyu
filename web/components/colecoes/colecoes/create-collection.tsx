"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, useEffect, useId, useMemo, useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, ChevronLeft, ChevronRight, Gem, Info, Layers, Loader2, Plus, Search, Sparkles, X } from "lucide-react";
import { activateMasterSetOnCreate, createCollectionFromSet, createFreeCollection } from "@/app/colecoes/colecoes/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  COLLECTION_NAME_MAX,
  type CollectionFailure,
  type CollectionKind,
  type CreationStep,
  type StorageOption,
  availableCreationKinds,
  canSubmitCreate,
  collectionFailureMessage,
  creationSteps,
  initialCreationKind,
  normalizeCollectionName,
  storageStep,
  suggestCollectionName,
  suggestFreeCollectionName,
} from "@/lib/colecoes/colecoes";
import { type CompletionObjective, MASTER_SET_OBJECTIVE_ENABLED } from "@/lib/colecoes/master-set";
import { ADD_PARAM, COVER_CODE_MAX, FREE_COVER_CODE_ENABLED, normalizeCoverCode, sanitizeCoverCodeInput } from "@/lib/colecoes/free-collection";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./colecoes.module.css";

export type OwnedSet = { code: string; name: string; count: number };
type SetOption = { code: string; name: string };

/**
 * Criar coleção — jornada progressiva (North Star Fluxo 1, NS-18;
 * COLLECTIONS-FUNCTIONAL-RECOVERY-01):
 *
 *   1. tipo  →  2. configuração do tipo (Set, só em "Completar um Set")
 *   →  3. nome + local (D-A)  →  criar  →  continuar na coleção.
 *
 * Tipos oferecidos: "Completar um Set" (CT-01, Query 5167) e "Coleção livre"
 * (CT-01 estendido, Query 5175), ambos no LIVE; a livre depende de
 * `FREE_COLLECTION_ENABLED` (ligado em FREE-COLLECTION-FRONTEND-COMPLETION-01)
 * e, ao terminar, leva direto a "Adicionar cartas do meu acervo". "Completar a Pokédex" não aparece antes da P7 (nem desabilitada).
 * Master Set não é tipo de criação: é o objetivo de uma coleção de Set. Com
 * `MASTER_SET_OBJECTIVE_ENABLED`, depois do Set vem o passo "Objetivo" (Set
 * padrão × Master Set, MASTER-SET-CREATE-01); em Master Set a coleção é
 * criada (5167) e o objetivo é ativado em seguida (5191 + 5194) com a
 * sugestão de acabamentos de Ajustes. Se só a ativação falhar, a coleção fica
 * em Set padrão e a conclusão oferece repetir a ativação. Nenhum termo técnico
 * chega ao usuário.
 *
 * Regra D-A, espelhada do banco: sem nenhum local, nada é perguntado e o
 * banco cria o "Local padrão"; com um ou mais locais, a escolha é obrigatória
 * e começa vazia — mesmo com um só. Em nenhum caso alguma carta recebe local.
 *
 * Proteção contra envio repetido: botão desabilitado durante a gravação,
 * painel não fecha no meio e a chave de idempotência é a mesma em toda nova
 * tentativa do mesmo pedido (o banco devolve a mesma coleção).
 */
export function CreateCollectionLauncher({
  locations,
  ownedSets,
  layout,
}: {
  /** `null` = falha ao ler os locais: criar fica indisponível (não daria para aplicar D-A). */
  locations: StorageOption[] | null;
  ownedSets: OwnedSet[];
  layout: "hero" | "empty";
}) {
  const [open, setOpen] = useState(false);
  if (locations === null) return null;
  return (
    <>
      <div className={layout === "hero" ? addStyles.launcherHero : addStyles.launcherEmpty}>
        <Button onClick={() => setOpen(true)} className={addStyles.launchPrimary}>
          <Plus className="h-4 w-4" aria-hidden="true" />
          {layout === "empty" ? "Criar minha primeira coleção" : "Nova coleção"}
        </Button>
      </div>
      {open ? <CreatePanel locations={locations} ownedSets={ownedSets} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

type Submit =
  | { status: "idle" }
  | { status: "pending" }
  | { status: "error"; reason: CollectionFailure }
  | { status: "activating" }
  | {
      status: "done";
      href: string;
      storageCreated: boolean;
      name: string;
      kind: CollectionKind;
      codeSaved: boolean;
      /** Só em "Completar um Set" com objetivo Master Set. */
      master: MasterOutcome | null;
      collectionId: string | null;
    };

type MasterOutcome =
  | { status: "on"; total: number; finishes: number }
  | { status: "retrying" }
  | { status: "failed" };

const OBJECTIVE_COPY: Record<CompletionObjective, { title: string; text: string; icon: typeof Layers }> = {
  STANDARD_SET: {
    title: "Set padrão",
    text: "Uma de cada carta. O jeito mais simples de começar.",
    icon: Layers,
  },
  MASTER_SET: {
    title: "Master Set",
    text: "Cada carta em cada acabamento que você escolher. Começamos com Padrão, Holográfica e Holográfica Reversa (os que existirem no Set) — você ajusta depois em Ajustes.",
    icon: Gem,
  },
};

const KIND_COPY: Record<CollectionKind, { title: string; text: string; icon: typeof Layers }> = {
  card_set: {
    title: "Completar um Set",
    text: "Escolha uma expansão oficial e acompanhe quantas cartas você já tem e quais faltam.",
    icon: Layers,
  },
  free: {
    title: "Coleção livre",
    text: "Reúna as cartas que quiser, do seu jeito — sem Set definido e sem contagem de progresso.",
    icon: Sparkles,
  },
};

function CreatePanel({ locations, ownedSets, onClose }: { locations: StorageOption[]; ownedSets: OwnedSet[]; onClose: () => void }) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const filterId = useId();
  const nameId = useId();
  const codeId = useId();
  const storageId = useId();
  const headingRef = useRef<HTMLHeadingElement>(null);

  const kinds = availableCreationKinds();
  // Um só tipo disponível: sem passo de escolha — abre direto nele.
  const [kind, setKind] = useState<CollectionKind | null>(() => initialCreationKind(kinds));
  const [step, setStep] = useState<CreationStep>(
    () => creationSteps(initialCreationKind(kinds), kinds.length, MASTER_SET_OBJECTIVE_ENABLED)[0] ?? "type",
  );
  const [catalog, setCatalog] = useState<{ status: "loading" | "error" } | { status: "ready"; options: SetOption[] }>({ status: "loading" });
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [filter, setFilter] = useState("");
  const [setCode, setSetCode] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [nameTouched, setNameTouched] = useState(false);
  // Código opcional da Coleção livre (5179/5180): vazio = sem código.
  const [coverCode, setCoverCode] = useState("");
  const [storage, setStorage] = useState<string | null>(null);
  const [objective, setObjective] = useState<CompletionObjective>("STANDARD_SET");
  const [submit, setSubmit] = useState<Submit>({ status: "idle" });
  // Uma chave por pedido: reaproveitada em toda nova tentativa do mesmo pedido.
  const keyRef = useRef<{ payload: string; key: string } | null>(null);

  const busy = submit.status === "pending" || submit.status === "activating";
  const locationStep = storageStep(locations);
  const steps = creationSteps(kind, kinds.length, MASTER_SET_OBJECTIVE_ENABLED);
  const stepIndex = steps.indexOf(step);

  // Lista de Sets só é buscada quando o passo do Set existe de fato.
  const needsCatalog = kind === "card_set";
  useEffect(() => {
    if (!needsCatalog) return;
    const controller = new AbortController();
    setCatalog({ status: "loading" });
    fetch("/api/cards/filter-options", { signal: controller.signal })
      .then((response) => (response.ok ? response.json() : Promise.reject(new Error(String(response.status)))))
      .then((body: { cardSets?: SetOption[] }) => setCatalog({ status: "ready", options: body.cardSets ?? [] }))
      .catch((error: Error) => {
        if (error.name !== "AbortError") setCatalog({ status: "error" });
      });
    return () => controller.abort();
  }, [loadAttempt, needsCatalog]);

  // Cada passo novo anuncia o próprio título (leitor de tela e teclado).
  useEffect(() => {
    if (step !== "set") headingRef.current?.focus();
  }, [step]);

  const ownedCodes = useMemo(() => new Set(ownedSets.map((set) => set.code)), [ownedSets]);
  const term = filter.trim().toLocaleLowerCase("pt-BR");
  const matches = (option: { code: string; name: string }) =>
    !term || option.name.toLocaleLowerCase("pt-BR").includes(term) || option.code.toLocaleLowerCase("pt-BR").includes(term);
  const owned = ownedSets.filter(matches);
  const others = catalog.status === "ready" ? catalog.options.filter((option) => !ownedCodes.has(option.code) && matches(option)) : [];
  const allNames = new Map<string, string>([
    ...(catalog.status === "ready" ? catalog.options.map((option) => [option.code, option.name] as const) : []),
    ...ownedSets.map((set) => [set.code, set.name] as const),
  ]);
  const setLabel = setCode ? allNames.get(setCode) ?? setCode.toUpperCase() : "";

  const resetError = () => {
    if (submit.status === "error") setSubmit({ status: "idle" });
  };

  const chooseKind = (next: CollectionKind) => {
    if (next !== kind) {
      setKind(next);
      setSetCode(null);
      if (!nameTouched) setName(next === "free" ? suggestFreeCollectionName() : "");
    }
    resetError();
    setStep(creationSteps(next, kinds.length, MASTER_SET_OBJECTIVE_ENABLED)[1] ?? "details");
  };

  const chooseSet = (code: string) => {
    setSetCode(code);
    if (!nameTouched) setName(suggestCollectionName(allNames.get(code) ?? code.toUpperCase()));
    resetError();
  };

  const goBack = () => {
    if (busy || stepIndex <= 0) return;
    resetError();
    setStep(steps[stepIndex - 1] ?? "type");
  };

  const codeEnabled = FREE_COVER_CODE_ENABLED && kind === "free";
  const normalizedCode = codeEnabled ? normalizeCoverCode(coverCode) : null;
  const codeInvalid = normalizedCode === "invalid";
  const ready =
    kind !== null &&
    !codeInvalid &&
    canSubmitCreate({ kind, setCode, name, locations, storageId: locationStep === "choose" ? storage : null });

  const send = async () => {
    const normalized = normalizeCollectionName(name);
    if (!ready || busy || !kind || !normalized) return;
    const storageContainerId = locationStep === "choose" ? storage : null;
    const code = normalizedCode === "invalid" ? null : normalizedCode;
    // O código não entra na chave: mudar só o código e reenviar reaproveita a
    // mesma coleção (5175 idempotente) e regrava o código (5180 idempotente).
    const payload = JSON.stringify([kind, kind === "card_set" ? setCode : null, normalized, storageContainerId]);
    if (keyRef.current?.payload !== payload) keyRef.current = { payload, key: crypto.randomUUID() };
    setSubmit({ status: "pending" });
    const request =
      kind === "free"
        ? createFreeCollection({ idempotencyKey: keyRef.current.key, name: normalized, storageContainerId, coverCode: code })
        : createCollectionFromSet({ idempotencyKey: keyRef.current.key, setCode: setCode ?? "", name: normalized, storageContainerId });
    const result = await request.catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    if (result.ok) {
      const wantsMaster = MASTER_SET_OBJECTIVE_ENABLED && kind === "card_set" && objective === "MASTER_SET";
      const collectionId = result.collectionId ?? null;
      let master: MasterOutcome | null = null;
      if (wantsMaster && collectionId) {
        setSubmit({ status: "activating" });
        master = await activateMaster(collectionId);
      }
      setSubmit({
        status: "done",
        href: result.href,
        storageCreated: result.storageCreated,
        name: normalized,
        kind,
        codeSaved: "codeSaved" in result ? result.codeSaved === true : true,
        master,
        collectionId,
      });
      router.refresh();
    } else {
      setSubmit({ status: "error", reason: result.reason });
      // Locais mudaram (outra aba criou um): recarrega para aplicar D-A com o estado real.
      if (result.reason === "storage_required" || result.reason === "storage_invalid") router.refresh();
    }
  };

  /** 5191 + 5194 (idempotente). Falha não desfaz a coleção: ela fica em Set padrão. */
  async function activateMaster(collectionId: string): Promise<MasterOutcome> {
    const outcome = await activateMasterSetOnCreate({ collectionId }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    return outcome.ok
      ? { status: "on", total: outcome.total, finishes: outcome.finishes }
      : { status: "failed" };
  }

  const retryMaster = async () => {
    if (submit.status !== "done" || !submit.collectionId || submit.master?.status !== "failed") return;
    const base = submit;
    setSubmit({ ...base, master: { status: "retrying" } });
    const master = await activateMaster(base.collectionId as string);
    setSubmit({ ...base, master });
    router.refresh();
  };

  const stepCounter = submit.status === "done" ? null : `Passo ${stepIndex + 1} de ${steps.length}`;

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && !busy && onClose()}>
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
            <div>
              <DialogPrimitive.Title className={addStyles.panelTitle}>Nova coleção</DialogPrimitive.Title>
              {stepCounter ? <p className={styles.stepLabel}>{stepCounter}</p> : null}
            </div>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          {submit.status === "done" ? (
            <DoneView
              name={submit.name}
              kind={submit.kind}
              storageCreated={submit.storageCreated}
              codeSaved={submit.codeSaved}
              master={submit.master}
              onRetryMaster={() => void retryMaster()}
              onOpen={() => router.push(submit.kind === "free" ? `${submit.href}?${ADD_PARAM}=1` : submit.href)}
              onClose={onClose}
            />
          ) : step === "type" ? (
            <>
              <div className={addStyles.body}>
                <div className={styles.stepHead}>
                  <h2 ref={headingRef} tabIndex={-1} className={styles.stepHeading}>
                    Que coleção você quer começar?
                  </h2>
                </div>
                <ul className={styles.typeList}>
                  {kinds.map((option) => {
                    const copy = KIND_COPY[option];
                    const Icon = copy.icon;
                    return (
                      <li key={option}>
                        <button
                          type="button"
                          className={styles.typeOption}
                          aria-pressed={kind === option}
                          onClick={() => chooseKind(option)}
                        >
                          <span className={styles.kindIcon} aria-hidden="true">
                            <Icon className="h-4 w-4" />
                          </span>
                          <span>
                            <span className={`${styles.kindTitle} block`}>{copy.title}</span>
                            <span className={`${styles.kindText} block`}>{copy.text}</span>
                          </span>
                          <ChevronRight className={`h-4 w-4 ${styles.typeArrow}`} aria-hidden="true" />
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </div>
              <div className={addStyles.footer}>
                <span className={addStyles.footerLead} />
                <div className={addStyles.footerActions}>
                  <Button variant="outline" onClick={onClose}>
                    Cancelar
                  </Button>
                </div>
              </div>
            </>
          ) : step === "set" ? (
            <>
              <div className={addStyles.body}>
                <section aria-labelledby={`${filterId}-label`}>
                  <label id={`${filterId}-label`} htmlFor={filterId} className={addStyles.sectionTitle}>
                    Qual Set você quer completar?
                  </label>
                  <div className={addStyles.searchWrap}>
                    <Search className={addStyles.searchIcon} aria-hidden="true" />
                    <Input
                      id={filterId}
                      type="search"
                      value={filter}
                      onChange={(event) => setFilter(event.target.value)}
                      placeholder="Filtrar por nome ou código"
                      autoComplete="off"
                      autoFocus
                      className={addStyles.searchInput}
                    />
                  </div>
                  <div aria-live="polite" className={addStyles.searchStatus}>
                    {catalog.status === "loading" ? "Carregando Sets…" : null}
                    {catalog.status === "ready" && owned.length === 0 && others.length === 0 ? "Nenhum Set encontrado." : null}
                  </div>
                  {catalog.status === "error" ? (
                    <Notice title="Não conseguimos carregar a lista completa de Sets">
                      {ownedSets.length > 0 ? "Os Sets do seu acervo continuam disponíveis abaixo. " : null}
                      <Button variant="outline" size="sm" onClick={() => setLoadAttempt((n) => n + 1)} className="mt-2">
                        Tentar novamente
                      </Button>
                    </Notice>
                  ) : null}
                  {owned.length > 0 || others.length > 0 ? (
                    <div className={addStyles.setList} role="radiogroup" aria-label="Sets">
                      {owned.length > 0 ? <p className={styles.setGroupLabel}>No seu acervo</p> : null}
                      {owned.map((option) => (
                        <SetRadio
                          key={option.code}
                          option={option}
                          checked={option.code === setCode}
                          disabled={false}
                          onChoose={chooseSet}
                          extra={<span className={styles.setOwned}>{formatCount(option.count)} no acervo</span>}
                        />
                      ))}
                      {others.length > 0 && owned.length > 0 ? <p className={styles.setGroupLabel}>Outros Sets</p> : null}
                      {others.map((option) => (
                        <SetRadio key={option.code} option={option} checked={option.code === setCode} disabled={false} onChoose={chooseSet} />
                      ))}
                    </div>
                  ) : null}
                </section>
              </div>
              <div className={addStyles.footer}>
                <span className={addStyles.footerLead} aria-live="polite">
                  {setLabel}
                </span>
                <div className={addStyles.footerActions}>
                  {stepIndex > 0 ? (
                    <Button variant="outline" onClick={goBack}>
                      <ChevronLeft className="h-4 w-4" aria-hidden="true" />
                      Voltar
                    </Button>
                  ) : (
                    <Button variant="outline" onClick={onClose}>
                      Cancelar
                    </Button>
                  )}
                  <Button onClick={() => setStep(steps[stepIndex + 1] ?? "details")} disabled={!setCode}>
                    Continuar
                  </Button>
                </div>
              </div>
            </>
          ) : step === "objective" ? (
            <>
              <div className={addStyles.body}>
                <div className={styles.stepHead}>
                  <h2 ref={headingRef} tabIndex={-1} className={styles.stepHeading}>
                    Como você quer completar {setLabel || "este Set"}?
                  </h2>
                </div>
                <ul className={styles.typeList} role="radiogroup" aria-label="Objetivo da coleção">
                  {(["STANDARD_SET", "MASTER_SET"] as const).map((option) => {
                    const copy = OBJECTIVE_COPY[option];
                    const Icon = copy.icon;
                    return (
                      <li key={option}>
                        <button
                          type="button"
                          role="radio"
                          aria-checked={objective === option}
                          className={styles.typeOption}
                          onClick={() => {
                            setObjective(option);
                            resetError();
                          }}
                        >
                          <span className={styles.kindIcon} aria-hidden="true">
                            <Icon className="h-4 w-4" />
                          </span>
                          <span>
                            <span className={`${styles.kindTitle} block`}>{copy.title}</span>
                            <span className={`${styles.kindText} block`}>{copy.text}</span>
                          </span>
                        </button>
                      </li>
                    );
                  })}
                </ul>
                <p className={styles.fieldHint}>Você pode trocar o objetivo a qualquer momento em Ajustes — nenhuma carta sai da coleção.</p>
              </div>
              <div className={addStyles.footer}>
                <span className={addStyles.footerLead} />
                <div className={addStyles.footerActions}>
                  <Button variant="outline" onClick={goBack}>
                    <ChevronLeft className="h-4 w-4" aria-hidden="true" />
                    Voltar
                  </Button>
                  <Button onClick={() => setStep(steps[stepIndex + 1] ?? "details")}>Continuar</Button>
                </div>
              </div>
            </>
          ) : (
            <>
              <div className={addStyles.body}>
                <div className={styles.stepHead}>
                  <h2 ref={headingRef} tabIndex={-1} className={styles.stepHeading}>
                    {kind === "free" ? "Dê um nome à sua coleção" : "Quase lá"}
                  </h2>
                </div>

                {kind ? (
                  <div className={styles.kindCard}>
                    <span className={styles.kindIcon} aria-hidden="true">
                      {kind === "free" ? <Sparkles className="h-4 w-4" /> : <Layers className="h-4 w-4" />}
                    </span>
                    <div>
                      <p className={styles.kindTitle}>{kind === "card_set" && setLabel ? setLabel : KIND_COPY[kind].title}</p>
                      <p className={styles.kindText}>
                        {kind === "card_set"
                          ? MASTER_SET_OBJECTIVE_ENABLED && objective === "MASTER_SET"
                            ? "Master Set — cada carta nos acabamentos sugeridos. Você ajusta os acabamentos depois em Ajustes."
                            : "Set padrão — uma de cada carta. O progresso mostra quantas você já tem e quais faltam."
                          : "Curadoria sua, sem contagem de progresso. Você decide o que entra."}
                      </p>
                    </div>
                  </div>
                ) : null}

                <div className={addStyles.field}>
                  <label htmlFor={nameId} className={addStyles.sectionTitle}>
                    Nome da coleção
                  </label>
                  <Input
                    id={nameId}
                    value={name}
                    maxLength={COLLECTION_NAME_MAX}
                    onChange={(event) => {
                      setName(event.target.value);
                      setNameTouched(true);
                    }}
                    placeholder="Dê um nome à coleção"
                    disabled={busy}
                    autoComplete="off"
                  />
                </div>

                {codeEnabled ? (
                  <div className={addStyles.field}>
                    <label htmlFor={codeId} className={addStyles.sectionTitle}>
                      Código da capa <span className={styles.coverCodeOptional}>(opcional)</span>
                    </label>
                    <Input
                      id={codeId}
                      value={coverCode}
                      maxLength={COVER_CODE_MAX}
                      onChange={(event) => {
                        setCoverCode(sanitizeCoverCodeInput(event.target.value));
                        resetError();
                      }}
                      placeholder="Ex.: MMK"
                      disabled={busy}
                      autoComplete="off"
                      spellCheck={false}
                      invalid={codeInvalid}
                      aria-describedby={`${codeId}-hint`}
                      className={styles.coverCodeInput}
                    />
                    <p id={`${codeId}-hint`} className={styles.fieldHint}>
                      {codeInvalid
                        ? "Use de 2 a 6 letras ou números — ou deixe em branco."
                        : "De 2 a 6 letras ou números. Aparece na capa do fichário. Pode ficar em branco."}
                    </p>
                  </div>
                ) : null}

                {locationStep === "auto" ? (
                  <div className={styles.autoLocation}>
                    <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
                    <p>
                      Vamos criar o seu <strong>Local padrão</strong> — o lugar sugerido para guardar esta coleção. Nenhuma
                      carta é atribuída a ele.
                    </p>
                  </div>
                ) : (
                  <div className={addStyles.field}>
                    <label htmlFor={storageId} className={addStyles.sectionTitle}>
                      Onde guardo esta coleção
                    </label>
                    <Select
                      id={storageId}
                      value={storage ?? ""}
                      onChange={(event) => setStorage(event.target.value || null)}
                      disabled={busy}
                      aria-describedby={`${storageId}-hint`}
                      required
                    >
                      <option value="" disabled>
                        Escolha um local
                      </option>
                      {locations.map((location) => (
                        <option key={location.id} value={location.id}>
                          {location.name}
                        </option>
                      ))}
                    </Select>
                    <p id={`${storageId}-hint`} className={styles.fieldHint}>
                      É só o lugar sugerido para esta coleção. Nenhuma carta muda de lugar.
                    </p>
                  </div>
                )}

                {submit.status === "error" ? (
                  <Notice title="A coleção não foi criada">{collectionFailureMessage(submit.reason)}</Notice>
                ) : null}
              </div>

              <div className={addStyles.footer}>
                <span className={addStyles.footerLead} />
                <div className={addStyles.footerActions}>
                  <Button variant="outline" onClick={goBack} disabled={busy}>
                    <ChevronLeft className="h-4 w-4" aria-hidden="true" />
                    Voltar
                  </Button>
                  <Button onClick={() => void send()} disabled={!ready || busy} aria-busy={busy}>
                    {busy ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                    {submit.status === "activating" ? "Ativando o Master Set…" : busy ? "Criando…" : submit.status === "error" ? "Tentar novamente" : "Criar coleção"}
                  </Button>
                </div>
              </div>
            </>
          )}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function SetRadio({
  option,
  checked,
  disabled,
  onChoose,
  extra,
}: {
  option: { code: string; name: string };
  checked: boolean;
  disabled: boolean;
  onChoose: (code: string) => void;
  extra?: ReactNode;
}) {
  return (
    <label className={addStyles.setOption} data-checked={checked || undefined}>
      <input
        type="radio"
        name="colecoes-create-set"
        value={option.code}
        checked={checked}
        disabled={disabled}
        onChange={() => onChoose(option.code)}
        className={addStyles.setRadio}
      />
      <span className={addStyles.setName}>{option.name}</span>
      {extra}
      <span className={addStyles.setCode}>{option.code.toUpperCase()}</span>
    </label>
  );
}

function DoneView({
  name,
  kind,
  storageCreated,
  codeSaved,
  master,
  onRetryMaster,
  onOpen,
  onClose,
}: {
  name: string;
  kind: CollectionKind;
  storageCreated: boolean;
  codeSaved: boolean;
  master: MasterOutcome | null;
  onRetryMaster: () => void;
  onOpen: () => void;
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
            {name} está pronta
          </h2>
          <p className={addStyles.doneText}>
            {kind === "free"
              ? "A coleção começa vazia. Escolha agora as primeiras cartas do seu acervo — de qualquer Set."
              : master?.status === "on"
                ? `Master Set com ${formatCount(master.total)} posições (${master.finishes === 1 ? "1 acabamento" : `${master.finishes} acabamentos`}). A coleção começa vazia — abra para adicionar as cartas que você já tem.`
                : "A coleção começa vazia. Abra para ver o Set inteiro e adicionar as cartas que você já tem — uma de cada."}
          </p>
          {master?.status === "failed" || master?.status === "retrying" ? (
            <div className="w-full text-left">
              <Notice title="A coleção foi criada em Set padrão">
                Não conseguimos ativar o Master Set agora. Nada se perdeu — tente de novo ou ative depois em Ajustes.
                <div>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={onRetryMaster}
                    disabled={master.status === "retrying"}
                    aria-busy={master.status === "retrying"}
                    className="mt-2"
                  >
                    {master.status === "retrying" ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                    {master.status === "retrying" ? "Ativando…" : "Tentar ativar de novo"}
                  </Button>
                </div>
              </Notice>
            </div>
          ) : null}
          {storageCreated ? (
            <p className={addStyles.doneText}>
              Também criamos o seu <strong>Local padrão</strong>. Nenhuma carta foi atribuída a ele.
            </p>
          ) : null}
          {!codeSaved ? (
            <p className={addStyles.doneText}>
              Não conseguimos salvar o código da capa agora. A coleção está criada — defina o código depois, na página dela.
            </p>
          ) : null}
        </div>
      </div>
      <div className={addStyles.footer}>
        <span className={addStyles.footerLead} />
        <div className={addStyles.footerActions}>
          <Button variant="outline" onClick={onClose}>
            Ver minhas coleções
          </Button>
          <Button onClick={onOpen}>{kind === "free" ? "Escolher as primeiras cartas" : "Abrir e adicionar cartas"}</Button>
        </div>
      </div>
    </>
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
