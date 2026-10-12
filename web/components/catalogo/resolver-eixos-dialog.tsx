"use client";

import { AlertTriangle, ArrowRight, CircleDashed, FlaskConical, Globe2, Layers, RefreshCw } from "lucide-react";
import { useEffect, useMemo, useState, type FormEvent, type MutableRefObject, type ReactNode } from "react";
import {
  carregarCatalogoEixo,
  criarTipoVariacaoEResolverMapeamento,
  diagnosticarLinhaVariante,
  resolverMapeamentoEixo,
  resolverMapeamentoVariante,
  simularMapeamentoEixo,
  type AxisTraitOption,
  type CatalogoEixoResult,
} from "@/app/catalogo/importar-variantes/actions";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import {
  AXIS_LABEL,
  FIELD_LABEL,
  axisStateLabel,
  conflictLabel,
  currentItemAxis,
  draftFingerprint,
  effectiveScope,
  findProfileBySignature,
  isAxisStateResolved,
  isClassifiableItem,
  isMissingProfileReason,
  isValidProfileCode,
  itemStatusLabel,
  nextDisplayOrder,
  normalizeProfileCode,
  sortedIds,
  type AxisPreview,
  type AxisProfileOption,
  type ExplainItem,
  type MappingAxis,
  type MappingDraft,
  type MappingScope,
  type ResolutionAxis,
  type RowDiagnosis,
} from "@/lib/catalogo/axis-resolution";
import type { CardVariantTypeOption, CatalogVariantImportRowView } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

/**
 * Cache dos catálogos de eixo (características e perfis ativos), vivo enquanto
 * a tela de revisão estiver montada. Todas as linhas de um job são do mesmo
 * jogo, então cada eixo é lido no máximo uma vez por tela.
 */
export type AxisCatalogCache = Partial<Record<MappingAxis, CatalogoEixoResult>>;

const textareaClassName =
  "flex min-h-16 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

const ITEM_TONE: Record<ExplainItem["status"], StateTone> = {
  PRINTING: "success",
  EDITION_CONTEXT: "success",
  FINISH: "success",
  UNRECOGNIZED: "warning",
  NOT_EVALUATED: "muted",
};

type Target = { kind: "item"; index: number } | { kind: "combination" };
type DestinationMode = "existing" | "new";

/**
 * "Resolver mapeamento" — diagnóstico e resolução dos três eixos de uma linha
 * de importação em revisão (P3b).
 *
 * 1. Diagnóstico (Query 2271): estado de Impressão, Contexto de Edição e
 *    Acabamento, e cada item recebido da fonte com o eixo em que foi
 *    reconhecido. Item desconhecido aparece como "Não reconhecido" — a tela
 *    nunca sugere um eixo para ele.
 * 2. Classificação: o administrador escolhe o eixo entre os que o campo admite.
 * 3. Destino: perfil ativo existente ou perfil novo (características
 *    existentes; cadastro de característica fica fora desta tela).
 * 4. Escopo: Impressão é global; Contexto nasce restrito ao Set e só vira
 *    global com confirmação explícita.
 * 5. Prévia (Query 2272): só por ação explícita — ela executa a escrita real e
 *    a desfaz. Qualquer mudança no rascunho a invalida.
 * 6. Confirmação: RPC de escrita; o resultado volta para a tabela.
 *
 * Acabamento mantém o fluxo anterior (tipo existente ou novo tipo canônico).
 */
export function ResolverEixosDialog({
  row,
  cardVariantTypes,
  catalogCache,
  onResolved,
  onCancel,
}: {
  row: CatalogVariantImportRowView | null;
  cardVariantTypes: CardVariantTypeOption[];
  catalogCache: MutableRefObject<AxisCatalogCache>;
  onResolved: (summary: string) => void;
  onCancel: () => void;
}) {
  const [busy, setBusy] = useState(false);

  return (
    <Dialog open={row !== null} onOpenChange={(next) => !next && !busy && onCancel()}>
      <DialogContent
        size="xl"
        className="flex max-h-[min(860px,calc(100dvh-2rem))] w-[calc(100vw-1.5rem)] flex-col sm:w-full"
        onEscapeKeyDown={(event) => busy && event.preventDefault()}
        onInteractOutside={(event) => busy && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Resolver mapeamento</DialogTitle>
          <DialogDescription>
            {row ? (
              <>
                {row.cardName} · {row.collectorNumber}
                {row.collectorTotal ? `/${row.collectorTotal}` : ""}
              </>
            ) : null}
          </DialogDescription>
        </DialogHeader>
        {row && (
          <ResolverEixosBody
            key={row.id}
            row={row}
            cardVariantTypes={cardVariantTypes}
            catalogCache={catalogCache}
            busy={busy}
            setBusy={setBusy}
            onResolved={onResolved}
            onCancel={onCancel}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ResolverEixosBody({
  row,
  cardVariantTypes,
  catalogCache,
  busy,
  setBusy,
  onResolved,
  onCancel,
}: {
  row: CatalogVariantImportRowView;
  cardVariantTypes: CardVariantTypeOption[];
  catalogCache: MutableRefObject<AxisCatalogCache>;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  onResolved: (summary: string) => void;
  onCancel: () => void;
}) {
  const [diagnosis, setDiagnosis] = useState<RowDiagnosis | null>(null);
  const [diagnosisError, setDiagnosisError] = useState<string | null>(null);
  const [diagnosisAttempt, setDiagnosisAttempt] = useState(0);

  const [target, setTarget] = useState<Target | null>(null);
  const [axis, setAxis] = useState<ResolutionAxis | null>(null);

  useEffect(() => {
    let cancelled = false;
    setDiagnosis(null);
    setDiagnosisError(null);
    diagnosticarLinhaVariante(row.id).then((result) => {
      if (cancelled) return;
      if (result.error || !result.diagnosis) {
        setDiagnosisError(result.error ?? "Não foi possível diagnosticar esta linha.");
        return;
      }
      const d = result.diagnosis;
      setDiagnosis(d);
      // Abre já no único caminho possível, sem escolher eixo por ninguém:
      // com um só item classificável, ele é o alvo; sem nenhum, o alvo é a
      // combinação inteira (acabamento).
      const classifiable = d.items.map((item, index) => ({ item, index })).filter(({ item }) => isClassifiableItem(item));
      if (classifiable.length === 1) {
        const only = classifiable[0]!;
        setTarget({ kind: "item", index: only.index });
        setAxis(currentItemAxis(only.item));
      } else if (classifiable.length === 0) {
        setTarget({ kind: "combination" });
        setAxis("FINISH");
      }
    });
    return () => {
      cancelled = true;
    };
  }, [row.id, diagnosisAttempt]);

  const item = diagnosis && target?.kind === "item" ? (diagnosis.items[target.index] ?? null) : null;

  function selectItem(index: number) {
    if (!diagnosis) return;
    const next = diagnosis.items[index];
    if (!next) return;
    setTarget({ kind: "item", index });
    setAxis(currentItemAxis(next));
  }

  if (diagnosisError) {
    return (
      <>
        <DialogBody className="space-y-3">
          <InlineFeedback tone="error">{diagnosisError}</InlineFeedback>
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="outline" size="sm" onClick={onCancel}>
            Fechar
          </Button>
          <Button type="button" size="sm" onClick={() => setDiagnosisAttempt((n) => n + 1)}>
            <RefreshCw className="h-3.5 w-3.5" aria-hidden="true" />
            Tentar novamente
          </Button>
        </DialogFooter>
      </>
    );
  }

  if (!diagnosis) {
    return (
      <DialogBody className="space-y-4" aria-busy="true">
        <span className="sr-only" role="status">
          Diagnosticando a linha…
        </span>
        <div className="grid gap-2 sm:grid-cols-3">
          <Skeleton className="h-16" />
          <Skeleton className="h-16" />
          <Skeleton className="h-16" />
        </div>
        <Skeleton className="h-24" />
      </DialogBody>
    );
  }

  const finishBlocked = diagnosis.outcome === "C";

  return (
    <>
      <DialogBody className="min-h-0 flex-1 space-y-6 overflow-y-auto">
        <DiagnosisPanel diagnosis={diagnosis} />

        <Section title="Itens recebidos da fonte" hint="Escolha o item que você vai classificar.">
          <ItemList
            items={diagnosis.items}
            selectedIndex={target?.kind === "item" ? target.index : null}
            onSelect={selectItem}
            disabled={busy}
          />
          {diagnosis.finish.evaluated && !diagnosis.finish.variantType ? (
            <button
              type="button"
              disabled={busy}
              aria-pressed={target?.kind === "combination"}
              onClick={() => {
                setTarget({ kind: "combination" });
                setAxis("FINISH");
              }}
              className={cn(
                "mt-2 inline-flex items-center gap-1.5 rounded-md text-xs font-medium text-primary-ink underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                target?.kind === "combination" && "underline",
              )}
            >
              <Layers className="h-3.5 w-3.5" aria-hidden="true" />
              Mapear o acabamento da combinação restante
            </button>
          ) : null}
        </Section>

        {target?.kind === "item" && item ? (
          <AxisChoice
            item={item}
            value={axis}
            onChange={setAxis}
            finishBlocked={finishBlocked}
            disabled={busy}
          />
        ) : null}

        {axis === "FINISH" && target ? (
          finishBlocked ? (
            <InlineFeedback tone="warning">
              Impressão ou Contexto de Edição ainda não resolvidos nesta linha. Resolva-os primeiro: só então se sabe qual
              combinação sobra para o acabamento.
            </InlineFeedback>
          ) : (
            <FinishResolution
              row={row}
              diagnosis={diagnosis}
              cardVariantTypes={cardVariantTypes}
              busy={busy}
              setBusy={setBusy}
              onResolved={onResolved}
              onCancel={onCancel}
            />
          )
        ) : null}

        {(axis === "PRINTING" || axis === "EDITION_CONTEXT") && item ? (
          <AxisMappingResolution
            key={`${target?.kind === "item" ? target.index : "c"}-${axis}`}
            row={row}
            diagnosis={diagnosis}
            item={item}
            axis={axis}
            catalogCache={catalogCache}
            busy={busy}
            setBusy={setBusy}
            onResolved={onResolved}
            onCancel={onCancel}
          />
        ) : null}
      </DialogBody>

      {/* Sem eixo escolhido, o rodapé só oferece sair — cada fluxo traz o seu. */}
      {axis === null || (axis === "FINISH" && finishBlocked) ? (
        <DialogFooter>
          <Button type="button" variant="outline" size="sm" onClick={onCancel}>
            Cancelar
          </Button>
        </DialogFooter>
      ) : null}
    </>
  );
}

// ---------------------------------------------------------------------------
// Diagnóstico
// ---------------------------------------------------------------------------

function Section({ title, hint, children }: { title: string; hint?: string; children: ReactNode }) {
  return (
    <section className="space-y-2.5">
      <div>
        <h3 className="text-sm font-semibold text-foreground">{title}</h3>
        {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
      </div>
      {children}
    </section>
  );
}

function DiagnosisPanel({ diagnosis }: { diagnosis: RowDiagnosis }) {
  const finish = diagnosis.finish;
  const finishResolved = Boolean(finish.variantType);
  const residual = [finish.residual.type, finish.residual.foil, finish.residual.subtype, ...finish.residual.stamp].filter(
    (v): v is string => Boolean(v),
  );

  return (
    <Section title="Diagnóstico">
      <dl className="grid gap-2 sm:grid-cols-3">
        <AxisCell
          label={AXIS_LABEL.PRINTING}
          resolved={isAxisStateResolved(diagnosis.printing.state)}
          stateLabel={axisStateLabel(diagnosis.printing.state)}
          detail={diagnosis.printing.profile?.name ?? null}
        />
        <AxisCell
          label={AXIS_LABEL.EDITION_CONTEXT}
          resolved={isAxisStateResolved(diagnosis.editionContext.state)}
          stateLabel={axisStateLabel(diagnosis.editionContext.state)}
          detail={diagnosis.editionContext.profile?.name ?? null}
        />
        <AxisCell
          label={AXIS_LABEL.FINISH}
          resolved={finishResolved}
          stateLabel={!finish.evaluated ? "Aguarda os outros eixos" : finishResolved ? "Mapeado" : "Sem mapeamento"}
          detail={finish.variantType?.name ?? (finish.evaluated && residual.length > 0 ? residual.join(" · ") : null)}
          detailHint={finishResolved ? undefined : finish.evaluated ? "Combinação restante" : undefined}
        />
      </dl>
    </Section>
  );
}

function AxisCell({
  label,
  resolved,
  stateLabel,
  detail,
  detailHint,
}: {
  label: string;
  resolved: boolean;
  stateLabel: string;
  detail: string | null;
  detailHint?: string;
}) {
  return (
    <div className="rounded-md border border-border bg-surface-muted/40 px-3 py-2.5">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="mt-1 space-y-1">
        <p className={cn("flex items-center gap-1.5 text-sm font-medium", resolved ? "text-foreground" : "text-warning")}>
          {resolved ? null : <AlertTriangle className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />}
          {stateLabel}
        </p>
        {detail ? (
          <p className="truncate text-xs text-muted-foreground" title={detail}>
            {detailHint ? <span className="sr-only">{detailHint}: </span> : null}
            {detail}
          </p>
        ) : null}
      </dd>
    </div>
  );
}

function ItemList({
  items,
  selectedIndex,
  onSelect,
  disabled,
}: {
  items: ExplainItem[];
  selectedIndex: number | null;
  onSelect: (index: number) => void;
  disabled: boolean;
}) {
  if (items.length === 0) {
    return <p className="text-sm text-muted-foreground">A fonte não enviou nenhum item para esta variante.</p>;
  }
  return (
    <ul className="divide-y divide-border overflow-hidden rounded-md border border-border">
      {items.map((item, index) => {
        const classifiable = isClassifiableItem(item);
        const selected = selectedIndex === index;
        const mapping =
          item.status === "PRINTING"
            ? item.printingMapping
            : item.status === "EDITION_CONTEXT"
              ? item.editionContextMapping
              : null;
        return (
          <li
            key={`${item.field}-${item.normalized}-${index}`}
            className={cn("flex flex-wrap items-center gap-x-3 gap-y-1.5 px-3 py-2.5", selected && "bg-primary/5")}
          >
            <span className="w-16 shrink-0 text-xs text-muted-foreground">{FIELD_LABEL[item.field]}</span>
            <span className="min-w-0 flex-1 break-words text-sm font-medium text-foreground">{item.raw}</span>
            <span className="flex flex-wrap items-center gap-1.5">
              <StateBadge tone={ITEM_TONE[item.status]}>{itemStatusLabel(item.status)}</StateBadge>
              {item.editionContextMapping && item.status === "EDITION_CONTEXT" ? (
                <span className="text-[11px] text-muted-foreground">
                  {item.editionContextMapping.scope === "GLOBAL" ? "global" : "deste Set"}
                </span>
              ) : null}
            </span>
            {classifiable ? (
              <Button
                type="button"
                variant={selected ? "outline-primary" : "outline"}
                size="sm"
                disabled={disabled}
                aria-pressed={selected}
                onClick={() => onSelect(index)}
              >
                {currentItemAxis(item) ? "Alterar" : "Classificar"}
                <span className="sr-only">
                  {" "}
                  {FIELD_LABEL[item.field]} {item.raw}
                </span>
              </Button>
            ) : (
              <span className="w-[74px] text-right text-[11px] text-muted-foreground">Só acabamento</span>
            )}
            {mapping && mapping.traits.length > 0 ? (
              <p className="basis-full pl-[76px] text-xs text-muted-foreground">
                {mapping.traits.map((t) => t.name).join(" · ")}
              </p>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

// ---------------------------------------------------------------------------
// Classificação
// ---------------------------------------------------------------------------

const AXIS_ORDER: ResolutionAxis[] = ["FINISH", "PRINTING", "EDITION_CONTEXT"];

const AXIS_HELP: Record<ResolutionAxis, string> = {
  FINISH: "Como a carta foi impressa fisicamente (normal, holo, reverse…). Mapeia a combinação restante inteira.",
  PRINTING: "Marca da tiragem impressa na carta (1ª edição, sem símbolo de edição…). Sempre global.",
  EDITION_CONTEXT: "Contexto de lançamento (promoção, evento, selo de coleção…). Pode valer só para este Set.",
};

function AxisChoice({
  item,
  value,
  onChange,
  finishBlocked,
  disabled,
}: {
  item: ExplainItem;
  value: ResolutionAxis | null;
  onChange: (axis: ResolutionAxis) => void;
  finishBlocked: boolean;
  disabled: boolean;
}) {
  return (
    <fieldset className="space-y-2.5">
      <legend className="text-sm font-semibold text-foreground">
        Classificar &ldquo;{item.raw}&rdquo;
      </legend>
      <p className="-mt-1 text-xs text-muted-foreground">
        A escolha é sua: o sistema não presume o eixo de um item desconhecido.
      </p>
      <div className="grid gap-2 sm:grid-cols-3">
        {AXIS_ORDER.map((option) => {
          const allowed = item.allowedAxes.includes(option);
          const checked = value === option;
          return (
            <label
              key={option}
              className={cn(
                "flex gap-2.5 rounded-md border border-border px-3 py-2.5 transition-colors has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring",
                allowed ? "cursor-pointer hover:bg-surface-muted" : "cursor-not-allowed opacity-60",
                checked && "border-primary/40 bg-primary/5 hover:bg-primary/5",
              )}
            >
              <input
                type="radio"
                name="resolver-axis"
                className="mt-0.5 h-4 w-4 shrink-0 accent-primary focus-visible:outline-none"
                checked={checked}
                disabled={!allowed || disabled}
                onChange={() => onChange(option)}
                aria-describedby={`axis-help-${option}`}
              />
              <span className="min-w-0">
                <span className="block text-sm font-medium text-foreground">{AXIS_LABEL[option]}</span>
                <span id={`axis-help-${option}`} className="mt-0.5 block text-xs leading-snug text-muted-foreground">
                  {!allowed
                    ? `${FIELD_LABEL[item.field]} não pode ser ${AXIS_LABEL[option]}.`
                    : option === "FINISH" && finishBlocked
                      ? "Disponível depois de resolver Impressão e Contexto."
                      : AXIS_HELP[option]}
                </span>
              </span>
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}

// ---------------------------------------------------------------------------
// Acabamento (fluxo anterior, preservado)
// ---------------------------------------------------------------------------

function FinishResolution({
  row,
  diagnosis,
  cardVariantTypes,
  busy,
  setBusy,
  onResolved,
  onCancel,
}: {
  row: CatalogVariantImportRowView;
  diagnosis: RowDiagnosis;
  cardVariantTypes: CardVariantTypeOption[];
  busy: boolean;
  setBusy: (busy: boolean) => void;
  onResolved: (summary: string) => void;
  onCancel: () => void;
}) {
  const [mode, setMode] = useState<DestinationMode>("existing");
  const [variantTypeId, setVariantTypeId] = useState("");
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [order, setOrder] = useState("");
  const [error, setError] = useState<string | null>(null);

  const residual = diagnosis.finish.residual;
  const residualChips = [residual.type, residual.foil, residual.subtype, ...residual.stamp].filter((v): v is string =>
    Boolean(v),
  );

  const canSubmit = mode === "existing" ? Boolean(variantTypeId) : Boolean(code.trim() && name.trim() && order);

  function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit || busy) return;
    setError(null);
    setBusy(true);
    const done = (result: { error: string | null; rowsUpdated?: number; jobsAffected?: number }, created?: string) => {
      setBusy(false);
      if (result.error) {
        setError(result.error);
        return;
      }
      const rows = result.rowsUpdated ?? 0;
      const jobs = result.jobsAffected ?? 0;
      onResolved(
        `${created ? `Tipo "${created}" criado e acabamento mapeado` : "Acabamento mapeado"}: ${formatNumber(rows)} linha(s) em ${formatNumber(jobs)} importação(ões) revalidada(s).`,
      );
    };
    if (mode === "existing") {
      resolverMapeamentoVariante(row.id, variantTypeId).then((r) => done(r));
      return;
    }
    const displayOrder = Number.parseInt(order, 10);
    if (!Number.isFinite(displayOrder) || displayOrder <= 0) {
      setBusy(false);
      setError("A ordem precisa ser um número inteiro positivo.");
      return;
    }
    criarTipoVariacaoEResolverMapeamento(row.id, {
      code: code.trim(),
      name: name.trim(),
      description: description.trim() || null,
      displayOrder,
    }).then((r) => done(r, name.trim()));
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <Section
        title="Destino do acabamento"
        hint="Vale para este Jogo e Fonte: outras linhas com a mesma combinação, em qualquer importação em revisão, também serão resolvidas."
      >
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-xs text-muted-foreground">Combinação restante:</span>
          {residualChips.length > 0 ? (
            residualChips.map((chip, index) => (
              <StateBadge key={`${chip}-${index}`} tone="muted">
                {chip}
              </StateBadge>
            ))
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
        </div>
        <ModeSwitch
          value={mode}
          onChange={setMode}
          labels={{ existing: "Tipo existente", new: "Novo tipo canônico" }}
          disabled={busy}
        />
        {mode === "existing" ? (
          <div className="space-y-1">
            <Label htmlFor="finish-type">Card Variant Type</Label>
            <Select id="finish-type" value={variantTypeId} onChange={(e) => setVariantTypeId(e.target.value)} disabled={busy}>
              <option value="" disabled>
                Selecione…
              </option>
              {cardVariantTypes.map((type) => (
                <option key={type.id} value={type.id}>
                  {type.name} ({type.code})
                </option>
              ))}
            </Select>
          </div>
        ) : (
          <div className="space-y-3">
            <div className="grid gap-3 sm:grid-cols-[minmax(7rem,1fr)_2fr_6rem]">
              <div className="space-y-1">
                <Label htmlFor="finish-new-code">Código</Label>
                <Input id="finish-new-code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="Ex.: SET_LOGO_STAFF" maxLength={50} disabled={busy} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="finish-new-name">Nome</Label>
                <Input id="finish-new-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex.: Logo da Coleção Staff" maxLength={100} disabled={busy} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="finish-new-order">Ordem</Label>
                <Input id="finish-new-order" type="number" min={1} value={order} onChange={(e) => setOrder(e.target.value)} disabled={busy} />
              </div>
            </div>
            <div className="space-y-1">
              <Label htmlFor="finish-new-description">Descrição (opcional)</Label>
              <textarea
                id="finish-new-description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Explicação permanente do significado deste tipo de variação."
                maxLength={500}
                disabled={busy}
                className={textareaClassName}
              />
            </div>
          </div>
        )}
      </Section>
      {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
      <StickyFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={busy}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={busy || !canSubmit}>
          {busy ? "Resolvendo…" : mode === "new" ? "Criar tipo e mapear" : "Mapear acabamento"}
        </Button>
      </StickyFooter>
    </form>
  );
}

// ---------------------------------------------------------------------------
// Impressão / Contexto de Edição
// ---------------------------------------------------------------------------

function AxisMappingResolution({
  row,
  diagnosis,
  item,
  axis,
  catalogCache,
  busy,
  setBusy,
  onResolved,
  onCancel,
}: {
  row: CatalogVariantImportRowView;
  diagnosis: RowDiagnosis;
  item: ExplainItem;
  axis: MappingAxis;
  catalogCache: MutableRefObject<AxisCatalogCache>;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  onResolved: (summary: string) => void;
  onCancel: () => void;
}) {
  const [catalog, setCatalog] = useState<CatalogoEixoResult | null>(catalogCache.current[axis] ?? null);
  const [catalogAttempt, setCatalogAttempt] = useState(0);

  // Destino
  const currentMapping = axis === "PRINTING" ? item.printingMapping : item.editionContextMapping;
  const [mode, setMode] = useState<DestinationMode>("existing");
  const [profileId, setProfileId] = useState("");
  const [newTraitIds, setNewTraitIds] = useState<string[]>([]);
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [order, setOrder] = useState("");

  // Escopo
  // Sem referência externa ativa o Set não tem escopo próprio: só resta o global (com confirmação).
  const [scope, setScope] = useState<MappingScope>(diagnosis.externalSetId ? "SOURCE_SET" : "GLOBAL");
  const [globalAck, setGlobalAck] = useState(false);

  // Prévia e confirmação
  const [preview, setPreview] = useState<{ fingerprint: string; data: AxisPreview } | null>(null);
  const [previewing, setPreviewing] = useState(false);
  const [regressionAck, setRegressionAck] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (catalog && !catalog.error) return;
    let cancelled = false;
    carregarCatalogoEixo(row.id, axis).then((result) => {
      if (cancelled) return;
      if (!result.error) catalogCache.current[axis] = result;
      setCatalog(result);
    });
    return () => {
      cancelled = true;
    };
    // catalogAttempt reexecuta só a pedido ("Tentar novamente").
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [row.id, axis, catalogAttempt]);

  const profiles = catalog?.profiles ?? [];
  const traits = catalog?.traits ?? [];
  const selectedProfile = profiles.find((p) => p.id === profileId) ?? null;

  // Pré-seleciona o perfil do mapeamento atual, quando o item já é deste eixo.
  useEffect(() => {
    if (!currentMapping || profileId || profiles.length === 0) return;
    const match = findProfileBySignature(
      profiles,
      currentMapping.traits.map((t) => t.id),
    );
    if (match) setProfileId(match.id);
  }, [currentMapping, profiles, profileId]);

  useEffect(() => {
    if (mode === "new" && !order && profiles.length > 0) setOrder(String(nextDisplayOrder(profiles)));
  }, [mode, order, profiles]);

  const traitIds = mode === "existing" ? (selectedProfile?.traitIds ?? []) : newTraitIds;
  const duplicateOfNew = mode === "new" ? findProfileBySignature(profiles, newTraitIds) : null;
  const scopeEffective = effectiveScope(axis, scope);
  const needsGlobalAck = axis === "EDITION_CONTEXT" && scope === "GLOBAL";

  const draft: MappingDraft | null =
    traitIds.length > 0 ? { axis, field: item.field, token: item.raw, traitIds: sortedIds(traitIds), scope: scopeEffective } : null;
  const fingerprint = draft ? draftFingerprint(draft) : null;
  const previewFresh = preview !== null && preview.fingerprint === fingerprint;

  const newProfileValid =
    mode === "existing" ||
    (newTraitIds.length > 0 &&
      !duplicateOfNew &&
      isValidProfileCode(code) &&
      name.trim().length > 0 &&
      Number.parseInt(order, 10) > 0);

  const canPreview = Boolean(draft) && newProfileValid && (!needsGlobalAck || globalAck) && !busy && !previewing;
  const regressed = preview?.data.impact.regressed ?? 0;
  const canConfirm =
    previewFresh && preview!.data.ok && (regressed === 0 || regressionAck) && canPreview && !busy;

  function runPreview() {
    if (!draft || !canPreview) return;
    setError(null);
    setPreviewing(true);
    setRegressionAck(false);
    const fp = draftFingerprint(draft);
    simularMapeamentoEixo(row.id, draft).then((result) => {
      setPreviewing(false);
      if (result.error || !result.preview) {
        setError(result.error ?? "Não foi possível simular este mapeamento.");
        setPreview(null);
        return;
      }
      setPreview({ fingerprint: fp, data: result.preview });
    });
  }

  function confirm() {
    if (!draft || !canConfirm) return;
    setError(null);
    setBusy(true);
    const novoPerfil =
      mode === "new"
        ? {
            code: normalizeProfileCode(code),
            name: name.trim(),
            description: description.trim() || null,
            displayOrder: Number.parseInt(order, 10),
          }
        : null;
    resolverMapeamentoEixo(row.id, draft, novoPerfil).then((result) => {
      setBusy(false);
      if (result.error) {
        setError(result.error);
        // Perfil criado e mapeamento recusado: o perfil passa a existir —
        // descarta o cache para a próxima tentativa enxergá-lo.
        if (result.createdProfileName) delete catalogCache.current[axis];
        return;
      }
      if (result.createdProfileName) delete catalogCache.current[axis];
      const scopeText =
        axis === "PRINTING" ? "global" : scopeEffective === "GLOBAL" ? "global" : `só ${diagnosis.externalSetId ?? "este Set"}`;
      const prefix = result.createdProfileName
        ? `Perfil "${result.createdProfileName}" criado e ${AXIS_LABEL[axis]} mapeado (${scopeText})`
        : `${AXIS_LABEL[axis]} mapeado (${scopeText})`;
      onResolved(
        `${prefix}: ${formatNumber(result.rowsTouched ?? 0)} linha(s) reavaliada(s), ${formatNumber(result.rowsRevalidated ?? 0)} válida(s), ${formatNumber(result.rowsStillPending ?? 0)} ainda pendente(s), em ${formatNumber(result.jobsAffected ?? 0)} importação(ões).`,
      );
    });
  }

  if (!catalog) {
    return (
      <div className="space-y-2" aria-busy="true">
        <span className="sr-only" role="status">
          Carregando perfis de {AXIS_LABEL[axis]}…
        </span>
        <Skeleton className="h-9" />
        <Skeleton className="h-20" />
      </div>
    );
  }

  if (catalog.error) {
    return (
      <div className="space-y-2">
        <InlineFeedback tone="error">{catalog.error}</InlineFeedback>
        <Button type="button" variant="outline" size="sm" onClick={() => setCatalogAttempt((n) => n + 1)}>
          <RefreshCw className="h-3.5 w-3.5" aria-hidden="true" />
          Tentar novamente
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <Section
        title={`Perfil de ${AXIS_LABEL[axis]}`}
        hint="O perfil é a identidade da variante neste eixo. A composição de características define o perfil."
      >
        <ModeSwitch
          value={mode}
          onChange={(next) => {
            setMode(next);
          }}
          labels={{ existing: "Perfil existente", new: "Novo perfil" }}
          disabled={busy}
        />
        {mode === "existing" ? (
          <div className="space-y-2">
            <div className="space-y-1">
              <Label htmlFor="axis-profile">Perfil ativo</Label>
              <Select id="axis-profile" value={profileId} onChange={(e) => setProfileId(e.target.value)} disabled={busy}>
                <option value="" disabled>
                  {profiles.length === 0 ? "Nenhum perfil ativo neste eixo" : "Selecione…"}
                </option>
                {profiles.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} ({p.code})
                  </option>
                ))}
              </Select>
            </div>
            {selectedProfile ? <TraitSummary traitIds={selectedProfile.traitIds} traits={traits} /> : null}
          </div>
        ) : (
          <NewProfileForm
            axis={axis}
            traits={traits}
            selected={newTraitIds}
            onToggle={(id) =>
              setNewTraitIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]))
            }
            duplicateOf={duplicateOfNew}
            onUseDuplicate={(p) => {
              setMode("existing");
              setProfileId(p.id);
            }}
            code={code}
            setCode={setCode}
            name={name}
            setName={setName}
            description={description}
            setDescription={setDescription}
            order={order}
            setOrder={setOrder}
            disabled={busy}
          />
        )}
      </Section>

      <ScopeSection
        axis={axis}
        scope={scope}
        onScope={(next) => {
          setScope(next);
          if (next === "SOURCE_SET") setGlobalAck(false);
        }}
        globalAck={globalAck}
        onGlobalAck={setGlobalAck}
        externalSetId={diagnosis.externalSetId}
        disabled={busy}
      />

      <Section
        title="Prévia do impacto"
        hint="A prévia executa a gravação de verdade e a desfaz em seguida. Rode quando o formulário estiver pronto."
      >
        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" variant="outline" size="sm" onClick={runPreview} disabled={!canPreview}>
            <FlaskConical className="h-3.5 w-3.5" aria-hidden="true" />
            {previewing ? "Simulando…" : preview ? "Simular novamente" : "Simular impacto"}
          </Button>
          {preview && !previewFresh && !previewing ? (
            <span className="inline-flex items-center gap-1 text-xs text-warning">
              <CircleDashed className="h-3.5 w-3.5" aria-hidden="true" />
              Desatualizada: o formulário mudou depois da última simulação.
            </span>
          ) : null}
          {!draft ? <span className="text-xs text-muted-foreground">Escolha o perfil para simular.</span> : null}
        </div>
        <div aria-live="polite">
          {preview ? (
            <PreviewPanel
              preview={preview.data}
              stale={!previewFresh}
              creatingProfile={mode === "new"}
              regressionAck={regressionAck}
              onRegressionAck={setRegressionAck}
              disabled={busy}
            />
          ) : null}
        </div>
      </Section>

      {error && <InlineFeedback tone="error">{error}</InlineFeedback>}

      <StickyFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={busy}>
          Cancelar
        </Button>
        <Button type="button" size="sm" onClick={confirm} disabled={!canConfirm}>
          {busy ? "Gravando…" : mode === "new" ? "Criar perfil e mapear" : `Mapear como ${AXIS_LABEL[axis]}`}
        </Button>
      </StickyFooter>
    </div>
  );
}

function TraitSummary({ traitIds, traits }: { traitIds: string[]; traits: AxisTraitOption[] }) {
  const byId = new Map(traits.map((t) => [t.id, t]));
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="text-xs text-muted-foreground">Características:</span>
      {traitIds.map((id) => (
        <StateBadge key={id} tone="muted">
          {byId.get(id)?.name ?? "característica inativa"}
        </StateBadge>
      ))}
    </div>
  );
}

function NewProfileForm({
  axis,
  traits,
  selected,
  onToggle,
  duplicateOf,
  onUseDuplicate,
  code,
  setCode,
  name,
  setName,
  description,
  setDescription,
  order,
  setOrder,
  disabled,
}: {
  axis: MappingAxis;
  traits: AxisTraitOption[];
  selected: string[];
  onToggle: (id: string) => void;
  duplicateOf: AxisProfileOption | null;
  onUseDuplicate: (profile: AxisProfileOption) => void;
  code: string;
  setCode: (v: string) => void;
  name: string;
  setName: (v: string) => void;
  description: string;
  setDescription: (v: string) => void;
  order: string;
  setOrder: (v: string) => void;
  disabled: boolean;
}) {
  const [filter, setFilter] = useState("");
  const groups = useMemo(() => {
    const q = filter.trim().toLowerCase();
    const visible = traits.filter(
      (t) => selected.includes(t.id) || !q || t.name.toLowerCase().includes(q) || t.code.toLowerCase().includes(q),
    );
    const map = new Map<string, AxisTraitOption[]>();
    for (const t of visible) {
      const key = t.family ?? "";
      map.set(key, [...(map.get(key) ?? []), t]);
    }
    return Array.from(map.entries());
  }, [traits, filter, selected]);
  const codeInvalid = code.trim().length > 0 && !isValidProfileCode(code);

  return (
    <div className="space-y-3">
      <fieldset className="space-y-2">
        <legend className="text-xs font-medium text-foreground">
          Características <span className="font-normal text-muted-foreground">({formatNumber(selected.length)} escolhida(s))</span>
        </legend>
        {traits.length > 12 ? (
          <Input
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filtrar características"
            aria-label="Filtrar características"
            disabled={disabled}
          />
        ) : null}
        <div className="max-h-56 space-y-3 overflow-y-auto rounded-md border border-border p-2.5">
          {groups.length === 0 ? (
            <p className="text-xs text-muted-foreground">Nenhuma característica ativa corresponde ao filtro.</p>
          ) : (
            groups.map(([family, list]) => (
              <div key={family || "_"} className="space-y-1">
                {axis === "EDITION_CONTEXT" && family ? (
                  <p className="text-[11px] font-medium text-muted-foreground">{family}</p>
                ) : null}
                <div className="grid gap-x-3 gap-y-0.5 sm:grid-cols-2">
                  {list.map((t) => (
                    <label
                      key={t.id}
                      className="flex min-h-9 cursor-pointer items-center gap-2 rounded px-1.5 text-sm hover:bg-surface-muted has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring"
                    >
                      <input
                        type="checkbox"
                        className="h-4 w-4 shrink-0 accent-primary focus-visible:outline-none"
                        checked={selected.includes(t.id)}
                        onChange={() => onToggle(t.id)}
                        disabled={disabled}
                      />
                      <span className="min-w-0 truncate" title={`${t.name} (${t.code})`}>
                        {t.name}
                      </span>
                    </label>
                  ))}
                </div>
              </div>
            ))
          )}
        </div>
        <p className="text-xs text-muted-foreground">
          Falta uma característica? O cadastro de características fica fora desta tela.
        </p>
      </fieldset>

      {duplicateOf ? (
        <div className="flex flex-wrap items-center gap-2 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-sm text-warning">
          <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
          <span className="min-w-0 flex-1">Já existe o perfil &ldquo;{duplicateOf.name}&rdquo; com estas características.</span>
          <Button type="button" variant="outline" size="sm" onClick={() => onUseDuplicate(duplicateOf)} disabled={disabled}>
            Usar este perfil
          </Button>
        </div>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-[minmax(7rem,1fr)_2fr_6rem]">
        <div className="space-y-1">
          <Label htmlFor="axis-new-code">Código</Label>
          <Input
            id="axis-new-code"
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="Ex.: STAFF_PROMO"
            maxLength={60}
            aria-invalid={codeInvalid || undefined}
            aria-describedby="axis-new-code-help"
            disabled={disabled}
          />
          <p id="axis-new-code-help" className={cn("text-[11px]", codeInvalid ? "text-destructive" : "text-muted-foreground")}>
            Letras maiúsculas, números e _, começando por letra.
          </p>
        </div>
        <div className="space-y-1">
          <Label htmlFor="axis-new-name">Nome</Label>
          <Input id="axis-new-name" value={name} onChange={(e) => setName(e.target.value)} maxLength={120} disabled={disabled} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="axis-new-order">Ordem</Label>
          <Input id="axis-new-order" type="number" min={1} value={order} onChange={(e) => setOrder(e.target.value)} disabled={disabled} />
        </div>
      </div>
      <div className="space-y-1">
        <Label htmlFor="axis-new-description">Descrição (opcional)</Label>
        <textarea
          id="axis-new-description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          maxLength={500}
          disabled={disabled}
          className={textareaClassName}
        />
      </div>
    </div>
  );
}

function ScopeSection({
  axis,
  scope,
  onScope,
  globalAck,
  onGlobalAck,
  externalSetId,
  disabled,
}: {
  axis: MappingAxis;
  scope: MappingScope;
  onScope: (scope: MappingScope) => void;
  globalAck: boolean;
  onGlobalAck: (ack: boolean) => void;
  externalSetId: string | null;
  disabled: boolean;
}) {
  if (axis === "PRINTING") {
    return (
      <Section title="Escopo">
        <p className="flex items-start gap-2 rounded-md border border-border bg-surface-muted/40 px-3 py-2.5 text-sm text-foreground">
          <Globe2 className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden="true" />
          <span>
            Global — Impressão vale para todos os Sets desta fonte.
            <span className="block text-xs text-muted-foreground">Mapeamentos de Impressão não têm escopo de Set.</span>
          </span>
        </p>
      </Section>
    );
  }

  const setLabel = externalSetId ? `Somente este Set (${externalSetId})` : "Somente este Set";
  return (
    <fieldset className="space-y-2.5">
      <legend className="text-sm font-semibold text-foreground">Escopo</legend>
      <div className="grid gap-2 sm:grid-cols-2">
        <ScopeOption
          checked={scope === "SOURCE_SET"}
          onChange={() => onScope("SOURCE_SET")}
          title={setLabel}
          help="Recomendado. Não afeta outros Sets."
          disabled={disabled || !externalSetId}
        />
        <ScopeOption
          checked={scope === "GLOBAL"}
          onChange={() => onScope("GLOBAL")}
          title="Todos os Sets (global)"
          help="Vale para todo Set sem mapeamento próprio deste item."
          disabled={disabled}
        />
      </div>
      {!externalSetId ? (
        <p className="text-xs text-warning">Este Set não tem referência externa ativa nesta fonte; só o escopo global é possível.</p>
      ) : null}
      {scope === "GLOBAL" ? (
        <label className="flex cursor-pointer items-start gap-2.5 rounded-md border border-warning/40 bg-warning/10 px-3 py-2.5 text-sm text-foreground has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring">
          <input
            type="checkbox"
            className="mt-0.5 h-4 w-4 shrink-0 accent-primary focus-visible:outline-none"
            checked={globalAck}
            onChange={(e) => onGlobalAck(e.target.checked)}
            disabled={disabled}
          />
          <span>
            Entendo que este item passará a ser Contexto de Edição em todos os Sets desta fonte que não tenham mapeamento
            próprio.
          </span>
        </label>
      ) : null}
    </fieldset>
  );
}

function ScopeOption({
  checked,
  onChange,
  title,
  help,
  disabled,
}: {
  checked: boolean;
  onChange: () => void;
  title: string;
  help: string;
  disabled: boolean;
}) {
  return (
    <label
      className={cn(
        "flex gap-2.5 rounded-md border border-border px-3 py-2.5 transition-colors has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring",
        disabled ? "cursor-not-allowed opacity-60" : "cursor-pointer hover:bg-surface-muted",
        checked && "border-primary/40 bg-primary/5 hover:bg-primary/5",
      )}
    >
      <input
        type="radio"
        name="resolver-scope"
        className="mt-0.5 h-4 w-4 shrink-0 accent-primary focus-visible:outline-none"
        checked={checked}
        onChange={onChange}
        disabled={disabled}
      />
      <span>
        <span className="block text-sm font-medium text-foreground">{title}</span>
        <span className="mt-0.5 block text-xs text-muted-foreground">{help}</span>
      </span>
    </label>
  );
}

// ---------------------------------------------------------------------------
// Prévia
// ---------------------------------------------------------------------------

function PreviewPanel({
  preview,
  stale,
  creatingProfile,
  regressionAck,
  onRegressionAck,
  disabled,
}: {
  preview: AxisPreview;
  stale: boolean;
  creatingProfile: boolean;
  regressionAck: boolean;
  onRegressionAck: (ack: boolean) => void;
  disabled: boolean;
}) {
  const impact = preview.impact;
  const reasons = Object.entries(impact.pendingByReason).sort((a, b) => b[1] - a[1]);
  const awaitingNewProfile = creatingProfile
    ? reasons.filter(([reason]) => isMissingProfileReason(reason)).reduce((sum, [, n]) => sum + n, 0)
    : 0;

  return (
    <div className={cn("mt-3 space-y-3 rounded-md border border-border p-3.5", stale && "opacity-60")}>
      {preview.ok ? (
        <p className="text-sm font-medium text-foreground">
          {impact.rowsTouched === 0
            ? "Nenhuma linha em revisão contém este item no escopo escolhido."
            : `${formatNumber(impact.rowsTouched)} linha(s) em ${formatNumber(impact.jobs)} importação(ões), ${formatNumber(impact.cardSets)} Set(s).`}
        </p>
      ) : (
        <InlineFeedback tone="error">{preview.error ?? "A gravação seria recusada pelo banco."}</InlineFeedback>
      )}

      {preview.conflicts.length > 0 ? (
        <ul className="space-y-1.5">
          {preview.conflicts.map((c) => (
            <li key={c.code} className="flex gap-2 text-sm text-destructive dark:text-destructive-foreground">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
              <span>
                {conflictLabel(c.code)}
                {c.scopes.length > 0 ? (
                  <span className="block text-xs opacity-80">Escopo(s) ativo(s): {c.scopes.join(", ")}</span>
                ) : null}
              </span>
            </li>
          ))}
        </ul>
      ) : null}

      {preview.ok && impact.resolved !== null ? (
        <dl className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Metric label="Passam a válidas" value={impact.newlyResolved ?? 0} tone="success" />
          <Metric label="Válidas ao final" value={impact.resolved} />
          <Metric label="Continuam pendentes" value={impact.pending ?? 0} tone={(impact.pending ?? 0) > 0 ? "warning" : undefined} />
          <Metric label="Deixam de ser válidas" value={impact.regressed ?? 0} tone={(impact.regressed ?? 0) > 0 ? "danger" : undefined} />
        </dl>
      ) : null}

      {preview.ok && reasons.length > 0 ? (
        <div className="space-y-1">
          <p className="text-xs font-medium text-foreground">Por que continuam pendentes</p>
          <ul className="space-y-0.5 text-xs text-muted-foreground">
            {reasons.map(([reason, n]) => (
              <li key={reason} className="flex justify-between gap-3">
                <span>{axisStateLabel(reason)}</span>
                <span className="tabular-nums">{formatNumber(n)}</span>
              </li>
            ))}
          </ul>
          {awaitingNewProfile > 0 ? (
            <p className="text-xs text-muted-foreground">
              {formatNumber(awaitingNewProfile)} delas aguardam o perfil novo, que será criado antes do mapeamento.
            </p>
          ) : null}
        </div>
      ) : null}

      <ul className="space-y-1 text-xs text-muted-foreground">
        {preview.targetProfile ? (
          <li className="flex items-center gap-1.5">
            <ArrowRight className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            Perfil de destino: <span className="text-foreground">{preview.targetProfile.name}</span>
          </li>
        ) : creatingProfile ? (
          <li className="flex items-center gap-1.5">
            <ArrowRight className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            Perfil de destino: o perfil novo deste formulário.
          </li>
        ) : null}
        {preview.superseded ? (
          <li>
            Substitui o mapeamento ativo {preview.superseded.scope === "GLOBAL" ? "global" : `do Set ${preview.superseded.externalSetId ?? ""}`}
            ; o anterior fica no histórico, inativo.
          </li>
        ) : null}
        {preview.scopedOverrides.length > 0 ? (
          <li>
            Não altera {formatNumber(preview.scopedOverrides.length)} Set(s) com mapeamento próprio:{" "}
            {preview.scopedOverrides.join(", ")}.
          </li>
        ) : null}
        {preview.finishMappingsReferencingToken > 0 ? (
          <li>
            {formatNumber(preview.finishMappingsReferencingToken)} mapeamento(s) de acabamento também citam este item. Eles
            continuam existindo; confira se ainda fazem sentido.
          </li>
        ) : null}
        {preview.rowsTruncated ? <li>A lista detalhada foi limitada às primeiras 200 linhas; os totais acima são completos.</li> : null}
      </ul>

      {preview.ok && (impact.regressed ?? 0) > 0 ? (
        <label className="flex cursor-pointer items-start gap-2.5 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2.5 text-sm text-foreground has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring">
          <input
            type="checkbox"
            className="mt-0.5 h-4 w-4 shrink-0 accent-primary focus-visible:outline-none"
            checked={regressionAck}
            onChange={(e) => onRegressionAck(e.target.checked)}
            disabled={disabled || stale}
          />
          <span>
            Entendo que {formatNumber(impact.regressed ?? 0)} linha(s) hoje válida(s) voltarão para revisão.
          </span>
        </label>
      ) : null}
    </div>
  );
}

function Metric({ label, value, tone }: { label: string; value: number; tone?: "success" | "warning" | "danger" }) {
  return (
    <div className="rounded-md bg-surface-muted/50 px-2.5 py-2">
      <dt className="text-[11px] text-muted-foreground">{label}</dt>
      <dd
        className={cn(
          "mt-0.5 text-lg font-semibold leading-none tabular-nums",
          tone === "success" && "text-success",
          tone === "warning" && "text-warning",
          tone === "danger" && "text-destructive dark:text-destructive-foreground",
          !tone && "text-foreground",
        )}
      >
        {formatNumber(value)}
      </dd>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Peças compartilhadas
// ---------------------------------------------------------------------------

function ModeSwitch({
  value,
  onChange,
  labels,
  disabled,
}: {
  value: DestinationMode;
  onChange: (mode: DestinationMode) => void;
  labels: Record<DestinationMode, string>;
  disabled: boolean;
}) {
  return (
    <div className="flex gap-1.5 rounded-md border border-border bg-surface-muted/40 p-1" role="group">
      {(["existing", "new"] as const).map((mode) => (
        <button
          key={mode}
          type="button"
          aria-pressed={value === mode}
          disabled={disabled}
          onClick={() => onChange(mode)}
          className={cn(
            "min-h-8 flex-1 rounded px-2.5 py-1.5 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
            value === mode ? "bg-surface text-foreground shadow-subtle" : "text-muted-foreground hover:text-foreground",
          )}
        >
          {labels[mode]}
        </button>
      ))}
    </div>
  );
}

/** Ações do fluxo, presas ao fim do corpo rolável para ficarem sempre ao alcance. */
function StickyFooter({ children }: { children: ReactNode }) {
  return (
    <div className="sticky bottom-0 -mx-5 -mb-4 flex justify-end gap-2 border-t border-border bg-surface px-5 py-3.5">
      {children}
    </div>
  );
}
