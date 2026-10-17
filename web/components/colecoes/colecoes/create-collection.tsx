"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, useEffect, useId, useMemo, useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, Info, Layers, Loader2, Plus, Search, X } from "lucide-react";
import { createCollectionFromSet } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  COLLECTION_NAME_MAX,
  type CollectionFailure,
  type StorageOption,
  canSubmitCreate,
  collectionFailureMessage,
  normalizeCollectionName,
  storageStep,
  suggestCollectionName,
} from "@/lib/colecoes/colecoes";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./colecoes.module.css";

export type OwnedSet = { code: string; name: string; count: number };
type SetOption = { code: string; name: string };

/**
 * Criar coleção — "Completar um Set" (N6), contrato CT-01 (Query 5167).
 *
 * Um único tipo nesta rodada: coleção de Set padrão ("uma de cada carta",
 * NS-14). Passos no mesmo painel: Set → nome (sugerido pelo Set) → local.
 *
 * Regra D-A, espelhada do banco: sem nenhum local, nada é perguntado e CT-01
 * cria o "Local padrão"; com um ou mais locais, a escolha é obrigatória e
 * começa vazia — mesmo com um só. Em nenhum caso alguma carta recebe local.
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
          {layout === "empty" ? "Completar um Set" : "Nova coleção"}
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
  | { status: "done"; href: string; storageCreated: boolean; name: string };

function CreatePanel({ locations, ownedSets, onClose }: { locations: StorageOption[]; ownedSets: OwnedSet[]; onClose: () => void }) {
  const router = useRouter();
  const filterId = useId();
  const nameId = useId();
  const storageId = useId();

  const [catalog, setCatalog] = useState<{ status: "loading" | "error" } | { status: "ready"; options: SetOption[] }>({ status: "loading" });
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [filter, setFilter] = useState("");
  const [setCode, setSetCode] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [nameTouched, setNameTouched] = useState(false);
  const [storage, setStorage] = useState<string | null>(null);
  const [submit, setSubmit] = useState<Submit>({ status: "idle" });
  // Uma chave por pedido: reaproveitada em toda nova tentativa do mesmo pedido.
  const keyRef = useRef<{ payload: string; key: string } | null>(null);

  const busy = submit.status === "pending";
  const step = storageStep(locations);

  useEffect(() => {
    const controller = new AbortController();
    setCatalog({ status: "loading" });
    fetch("/api/cards/filter-options", { signal: controller.signal })
      .then((response) => (response.ok ? response.json() : Promise.reject(new Error(String(response.status)))))
      .then((body: { cardSets?: SetOption[] }) => setCatalog({ status: "ready", options: body.cardSets ?? [] }))
      .catch((error: Error) => {
        if (error.name !== "AbortError") setCatalog({ status: "error" });
      });
    return () => controller.abort();
  }, [loadAttempt]);

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

  const chooseSet = (code: string) => {
    setSetCode(code);
    if (!nameTouched) setName(suggestCollectionName(allNames.get(code) ?? code.toUpperCase()));
    if (submit.status === "error") setSubmit({ status: "idle" });
  };

  const ready = canSubmitCreate({ setCode, name, locations, storageId: step === "choose" ? storage : null });

  const send = async () => {
    const normalized = normalizeCollectionName(name);
    if (!ready || busy || !setCode || !normalized) return;
    const storageContainerId = step === "choose" ? storage : null;
    const payload = JSON.stringify([setCode, normalized, storageContainerId]);
    if (keyRef.current?.payload !== payload) keyRef.current = { payload, key: crypto.randomUUID() };
    setSubmit({ status: "pending" });
    const result = await createCollectionFromSet({
      idempotencyKey: keyRef.current.key,
      setCode,
      name: normalized,
      storageContainerId,
    }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    if (result.ok) {
      setSubmit({ status: "done", href: result.href, storageCreated: result.storageCreated, name: normalized });
      router.refresh();
    } else {
      setSubmit({ status: "error", reason: result.reason });
      // Locais mudaram (outra aba criou um): recarrega para aplicar D-A com o estado real.
      if (result.reason === "storage_required" || result.reason === "storage_invalid") router.refresh();
    }
  };

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && !busy && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${addStyles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
        >
          <div className={acervoStyles.drawerHeader}>
            <DialogPrimitive.Title className={addStyles.panelTitle}>Nova coleção</DialogPrimitive.Title>
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
              storageCreated={submit.storageCreated}
              onOpen={() => router.push(submit.href)}
              onClose={onClose}
            />
          ) : (
            <>
              <div className={addStyles.body}>
                <div className={styles.kindCard}>
                  <span className={styles.kindIcon} aria-hidden="true">
                    <Layers className="h-4 w-4" />
                  </span>
                  <div>
                    <p className={styles.kindTitle}>Completar um Set</p>
                    <p className={styles.kindText}>
                      Set padrão — uma de cada carta. O progresso mostra quantas você já tem e quais faltam.
                    </p>
                  </div>
                </div>

                <section aria-labelledby={`${filterId}-label`}>
                  <label id={`${filterId}-label`} htmlFor={filterId} className={addStyles.sectionTitle}>
                    Set
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
                      disabled={busy}
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
                          disabled={busy}
                          onChoose={chooseSet}
                          extra={<span className={styles.setOwned}>{formatCount(option.count)} no acervo</span>}
                        />
                      ))}
                      {others.length > 0 && owned.length > 0 ? <p className={styles.setGroupLabel}>Outros Sets</p> : null}
                      {others.map((option) => (
                        <SetRadio key={option.code} option={option} checked={option.code === setCode} disabled={busy} onChoose={chooseSet} />
                      ))}
                    </div>
                  ) : null}
                </section>

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
                    placeholder={setCode ? "Dê um nome à coleção" : "Escolha um Set para sugerirmos um nome"}
                    disabled={busy}
                    autoComplete="off"
                  />
                </div>

                {step === "auto" ? (
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
                <span className={addStyles.footerLead} aria-live="polite">
                  {setCode ? allNames.get(setCode) ?? setCode.toUpperCase() : ""}
                </span>
                <div className={addStyles.footerActions}>
                  <Button variant="outline" onClick={onClose} disabled={busy}>
                    Cancelar
                  </Button>
                  <Button onClick={() => void send()} disabled={!ready || busy} aria-busy={busy}>
                    {busy ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                    {busy ? "Criando…" : submit.status === "error" ? "Tentar novamente" : "Criar coleção"}
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
  storageCreated,
  onOpen,
  onClose,
}: {
  name: string;
  storageCreated: boolean;
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
            A coleção começa vazia. Abra para ver o Set inteiro e adicionar as cartas que você já tem — uma de cada.
          </p>
          {storageCreated ? (
            <p className={addStyles.doneText}>
              Também criamos o seu <strong>Local padrão</strong>. Nenhuma carta foi atribuída a ele.
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
          <Button onClick={onOpen}>Abrir coleção</Button>
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
