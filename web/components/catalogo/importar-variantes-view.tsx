"use client";

import { type KeyboardEvent, useActionState, useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  Copy,
  FolderPlus,
  ListChecks,
  Loader2,
  Search,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import { RevisaoImportacaoVariantesTable } from "@/components/catalogo/revisao-importacao-variantes-table";
import {
  getImportacaoVariantesJobData,
  iniciarImportacaoVariantes,
  type IniciarImportacaoVariantesActionState,
} from "@/app/catalogo/importar-variantes/actions";
import type {
  CardVariantTypeOption,
  CatalogVariantImportJobStatus,
  CatalogVariantImportRowView,
  CatalogoVariantCardSetRow,
} from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const INITIAL_STATE: IniciarImportacaoVariantesActionState = { error: null, jobId: null };

/**
 * Fluxo Importar Variantes (Incremento 4, ADR-028) — mesma forma de estado
 * de useAnalyzeJob (importar-tcgdex-view.tsx: form action sem navegar, job
 * buscado à parte e guardado em useState), sem a continuação automática
 * cartas→imagens (não existe pipeline seguinte encadeado aqui — o fim do
 * fluxo é a confirmação em card_variant). Uma instância própria e mais
 * enxuta em vez de generalizar o hook das Cartas, que está estruturalmente
 * acoplado a essa continuação (dois idiomas, retry, polling de
 * asset_import_run) — nada disso se aplica a variantes.
 */
function useAnalyzeVariantsJob() {
  const [state, formAction, isPending] = useActionState(iniciarImportacaoVariantes, INITIAL_STATE);
  const [jobState, setJobState] = useState<{
    job: CatalogVariantImportJobStatus | null;
    rows: CatalogVariantImportRowView[];
    cardVariantTypes: CardVariantTypeOption[];
  }>({ job: null, rows: [], cardVariantTypes: [] });
  const [fetchingJob, setFetchingJob] = useState(false);
  const fetchedJobIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (state.jobId && fetchedJobIdRef.current !== state.jobId) {
      fetchedJobIdRef.current = state.jobId;
      setFetchingJob(true);
      getImportacaoVariantesJobData(state.jobId).then((data) => {
        setJobState(data);
        setFetchingJob(false);
      });
    }
  }, [state.jobId]);

  const refreshJob = useCallback(async () => {
    if (!jobState.job) return;
    const data = await getImportacaoVariantesJobData(jobState.job.id);
    setJobState(data);
  }, [jobState.job]);

  return {
    formAction,
    error: state.error,
    isPending,
    fetchingJob,
    jobState,
    refreshJob,
    started: isPending || fetchingJob || Boolean(jobState.job),
  };
}

const ANALYSIS_STEPS: { label: string; icon: LucideIcon }[] = [
  { label: "Localizando Set na TCGdex", icon: FolderPlus },
  { label: "Buscando variantes no dataset-fonte", icon: Search },
  { label: "Resolvendo mapeamentos e validando", icon: ListChecks },
];

const STEP_INTERVAL_MS = 1400;
const PERCENT_TICK_MS = 200;
const PERCENT_CEILING = 92;

/**
 * Fase visual derivada do `job.status` real — correção do incidente SV10
 * (2026-08-15). Antes, a etapa "Concluído" (✓ verde) aparecia assim que
 * `Boolean(job)` fosse verdadeiro, isto é, assim que QUALQUER linha de job
 * fosse buscada com sucesso — mesmo com `status = PROCESSING` (job ainda
 * rodando, ou preso). Um job de SV10 ficou preso em `PROCESSING` (Edge
 * Function travada em `resolveSetSerieName()`, sem timeout, morta pela
 * plataforma por estouro do teto de execução) e a UI mostrou "Concluído,
 * 0 variantes propostas" mesmo assim — falso sucesso. Agora cada status
 * vira uma fase própria, e só `STAGED`/`COMPLETED`/`COMPLETED_WITH_ERRORS`
 * são tratados como "terminado com sucesso" (✓ verde); `RECEIVED`/
 * `PROCESSING`/`CONFIRMING` continuam "em andamento" (nunca ✓ verde,
 * mesmo já havendo um `job` carregado); `FAILED`/`CANCELLED` mostram erro
 * de verdade (ícone e cor de destructive, não a mesma cor de sucesso).
 *
 * `COMPLETED`/`COMPLETED_WITH_ERRORS` só existem depois da confirmação
 * (RPC `admin_confirm_catalog_variant_import`, fora deste formulário de
 * Análise) — tratados aqui porque `refreshJob()` (chamado por
 * `RevisaoImportacaoVariantesTable` após confirmar) pode atualizar o mesmo
 * `job` observado por este componente para um desses status.
 */
type JobPhase = "in_progress" | "staged" | "failed" | "completed" | "completed_with_errors";

function resolveJobPhase(status: string | undefined): JobPhase | null {
  switch (status) {
    case "RECEIVED":
    case "PROCESSING":
    case "CONFIRMING":
      return "in_progress";
    case "STAGED":
      return "staged";
    case "FAILED":
    case "CANCELLED":
      return "failed";
    case "COMPLETED":
      return "completed";
    case "COMPLETED_WITH_ERRORS":
      return "completed_with_errors";
    default:
      return null;
  }
}

const CONCLUSION_LABEL: Record<JobPhase, string> = {
  in_progress: "Processando…",
  staged: "Concluído",
  failed: "Falhou",
  completed: "Concluído",
  completed_with_errors: "Concluído com pendências",
};

/**
 * Indicador de progresso — mesmo desenho visual de ImportProgress
 * (importar-tcgdex-view.tsx: etapas fixas + linha vertical + barra
 * simulada até terminar), sem as etapas condicionais de imagem (não
 * existem aqui). A fase real do job (`resolveJobPhase`) decide o rótulo,
 * ícone, cor e corpo da etapa final — nunca `Boolean(job)` sozinho.
 */
function ImportProgressVariantes({
  isPending,
  job,
}: {
  isPending: boolean;
  job: CatalogVariantImportJobStatus | null | undefined;
}) {
  const [percent, setPercent] = useState(0);
  const [stepIndex, setStepIndex] = useState(0);

  const phase = resolveJobPhase(job?.status);
  // "terminado" (successo ou erro) — só quando o job tem um status real
  // fora de RECEIVED/PROCESSING/CONFIRMING. Um `job` já carregado mas
  // ainda em andamento continua animando os passos, exatamente como
  // antes de qualquer resposta chegar.
  const finished = phase !== null && phase !== "in_progress";
  const stillRunning = isPending || phase === "in_progress";

  useEffect(() => {
    if (finished) {
      setPercent(100);
      setStepIndex(ANALYSIS_STEPS.length);
      return;
    }
    if (!stillRunning) return;

    const stepTimer = setInterval(() => {
      setStepIndex((index) => Math.min(index + 1, ANALYSIS_STEPS.length - 1));
    }, STEP_INTERVAL_MS);
    const percentTimer = setInterval(() => {
      setPercent((value) => (value >= PERCENT_CEILING ? value : value + Math.max(1, Math.round((PERCENT_CEILING - value) * 0.08))));
    }, PERCENT_TICK_MS);
    return () => {
      clearInterval(stepTimer);
      clearInterval(percentTimer);
    };
  }, [stillRunning, finished]);

  type StepStatus = "pending" | "active" | "done" | "error";
  type Step = { key: string; label: string; icon: LucideIcon; status: StepStatus; body?: ReactNode };

  const analysisSteps: Step[] = ANALYSIS_STEPS.map((step, index) => ({
    key: step.label,
    label: step.label,
    icon: step.icon,
    status: finished || index < stepIndex ? "done" : index === stepIndex ? "active" : "pending",
  }));

  const needsReview = job ? Math.max(job.totalRows - job.validRows, 0) : 0;
  // "com pendência" só é relevante para o resultado de fato concluído
  // (STAGED/COMPLETED/COMPLETED_WITH_ERRORS) — um job ainda em andamento
  // não tem `needsReview`/`failedRows` significativos ainda.
  const hasIssues = Boolean(job && (job.failedRows > 0 || needsReview > 0));

  const conclusionIcon: LucideIcon =
    phase === "failed" ? AlertTriangle : phase === "in_progress" ? Loader2 : hasIssues ? AlertTriangle : CheckCircle2;

  const conclusionStatus: StepStatus =
    phase === "failed" ? "error" : phase === "in_progress" ? "active" : finished ? "done" : "pending";

  const conclusionBody: ReactNode = job && phase && (
    <>
      <p>
        {job.cardSetCode} — {job.cardSetName}
      </p>
      {phase === "failed" ? (
        <p className="text-destructive">{job.errorSummary ?? "A importação falhou antes de concluir a análise."}</p>
      ) : phase === "in_progress" ? (
        <p>Análise em andamento — isso pode levar alguns minutos para Coleções grandes.</p>
      ) : (
        <>
          <p>
            {formatNumber(job.totalRows)} variantes propostas · {formatNumber(job.validRows)} válidas ·{" "}
            {formatNumber(needsReview)} a revisar (sem mapeamento)
          </p>
          {(phase === "completed" || phase === "completed_with_errors") && (
            <p>
              {formatNumber(job.insertedRows)} inseridas · {formatNumber(job.unchangedRows)} inalteradas ·{" "}
              {formatNumber(job.failedRows)} falhas
            </p>
          )}
          {job.errorSummary && <p className="text-destructive">{job.errorSummary}</p>}
        </>
      )}
    </>
  );

  const conclusionStep: Step = {
    key: "conclusao",
    label: phase ? CONCLUSION_LABEL[phase] : "Concluído",
    icon: conclusionIcon,
    status: conclusionStatus,
    body: conclusionBody,
  };

  const steps = [...analysisSteps, conclusionStep];

  return (
    <div className="space-y-0 pb-1">
      {steps.map((step, index) => {
        const Icon = step.icon;
        const isLast = index === steps.length - 1;
        return (
          <div key={step.key} className="relative flex gap-3 pb-4 last:pb-0">
            {!isLast && <span className="absolute left-[15px] top-8 h-[calc(100%-1.5rem)] w-px bg-border" aria-hidden="true" />}
            <span
              className={cn(
                "z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border",
                step.status === "done" && "border-emerald-600/30 bg-emerald-600/10 text-emerald-600",
                step.status === "active" && "animate-pulse border-primary/40 bg-primary/10 text-primary",
                step.status === "error" && "border-destructive/40 bg-destructive/10 text-destructive",
                step.status === "pending" && "border-border bg-surface text-muted-foreground opacity-40",
              )}
            >
              <Icon className={cn("h-4 w-4", step.status === "active" && step.icon === Loader2 && "animate-spin")} aria-hidden="true" />
            </span>
            <div className="min-w-0 flex-1 pt-1.5">
              <p className="text-sm font-medium text-foreground">{step.label}</p>
              {step.body && <div className="mt-1 space-y-0.5 text-xs text-muted-foreground">{step.body}</div>}
            </div>
          </div>
        );
      })}
      {!finished && (
        <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
          <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${percent}%` }} />
        </div>
      )}
    </div>
  );
}

const REVIEWABLE_STATUSES = new Set(["STAGED", "CONFIRMING"]);

export function ImportarVariantesView({
  cardSets,
  selectedCardSet,
}: {
  /** Coleções com pelo menos uma carta cadastrada e cardsSemVariante > 0 (filtro aplicado em page.tsx, ver getCardSetsForVariantes). */
  cardSets: CatalogoVariantCardSetRow[];
  selectedCardSet: CatalogoVariantCardSetRow | null;
}) {
  const router = useRouter();
  const analyzeJob = useAnalyzeVariantsJob();

  function navigate(next: { cardSetId?: string | null }) {
    const params = new URLSearchParams();
    const cardSetId = next.cardSetId !== undefined ? next.cardSetId : selectedCardSet?.id;
    if (cardSetId) params.set("cardSetId", cardSetId);
    const query = params.toString();
    router.push(query ? `/catalogo/importar-variantes?${query}` : "/catalogo/importar-variantes");
  }

  const canAnalyzeHere = !!selectedCardSet && !analyzeJob.started;
  const totalCardsSemVariante = cardSets.reduce((sum, cardSet) => sum + cardSet.cardsSemVariante, 0);

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <Copy className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Importar Variantes</PageTitle>
          </div>
          <PageDescription>Cadastro em lote de Card Variant a partir do dataset-fonte da TCGdex.</PageDescription>
        </PageHeading>
      </PageHeader>

      <StatsRow>
        <StatCard
          label="Coleções Pendentes"
          value={formatNumber(cardSets.length)}
          caption="com cartas sem variante"
          icon={AlertTriangle}
          tone="danger"
        />
        <StatCard
          label="Cards Sem Variante"
          value={formatNumber(totalCardsSemVariante)}
          caption="nas coleções pendentes"
          icon={Copy}
          tone="danger"
        />
      </StatsRow>

      <Card>
        <CardContent className="space-y-4 pt-6">
          <div className="space-y-4">
            <div className="min-w-0 max-w-[500px] space-y-1">
              <label className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                Selecione a Coleção para importar variantes
              </label>
              <CardSetCombobox cardSets={cardSets} selected={selectedCardSet} onSelect={(id) => navigate({ cardSetId: id })} />
            </div>

            <form action={analyzeJob.formAction}>
              <input type="hidden" name="card_set_id" value={selectedCardSet?.id ?? ""} />
              <Button type="submit" disabled={!canAnalyzeHere}>
                Analisar
              </Button>
            </form>
          </div>

          <div className="space-y-4 border-t border-border pt-4">
            {!selectedCardSet ? (
              <p className="text-sm text-muted-foreground">Selecione uma Coleção acima para continuar.</p>
            ) : (
              <>
                {analyzeJob.error && <p className="text-sm text-destructive">{analyzeJob.error}</p>}
                {analyzeJob.started && (
                  <ImportProgressVariantes
                    isPending={analyzeJob.isPending || analyzeJob.fetchingJob}
                    job={analyzeJob.jobState.job}
                  />
                )}
              </>
            )}
          </div>
        </CardContent>
      </Card>

      {analyzeJob.jobState.job && REVIEWABLE_STATUSES.has(analyzeJob.jobState.job.status) && (
        <RevisaoImportacaoVariantesTable
          jobId={analyzeJob.jobState.job.id}
          rows={analyzeJob.jobState.rows}
          cardVariantTypes={analyzeJob.jobState.cardVariantTypes}
          onRefresh={analyzeJob.refreshJob}
        />
      )}
    </div>
  );
}

/** Combobox de Coleção — mesmo componente/UX de CardSetCombobox (importar-cartas-view.tsx), legenda adaptada para "cards sem variante" em vez de "cartas para importação". */
function CardSetCombobox({
  cardSets,
  selected,
  onSelect,
}: {
  cardSets: CatalogoVariantCardSetRow[];
  selected: CatalogoVariantCardSetRow | null;
  onSelect: (id: string | null) => void;
}) {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;

    function handlePointerDown(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    function handleKeyDown(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }

    document.addEventListener("mousedown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [open]);

  function handleTriggerKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "Enter" || event.key === " " || event.key === "ArrowDown") {
      event.preventDefault();
      setOpen(true);
    }
  }

  const disabled = cardSets.length === 0;

  function legend(cardSet: CatalogoVariantCardSetRow): string {
    return cardSet.cardsComVariante > 0
      ? `${formatNumber(cardSet.cardsComVariante)}/${formatNumber(cardSet.cardsCatalogados)} cards com variante — ${formatNumber(cardSet.cardsSemVariante)} pendentes`
      : `${formatNumber(cardSet.cardsSemVariante)} cards sem variante`;
  }

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((value) => !value)}
        onKeyDown={handleTriggerKeyDown}
        aria-haspopup="listbox"
        aria-expanded={open}
        className={cn(
          "flex w-full min-h-9 items-center justify-between gap-2 rounded-md border border-input bg-surface px-3 py-1 text-left shadow-subtle transition-colors",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
          disabled && "cursor-not-allowed opacity-60",
        )}
      >
        {selected ? (
          <span className="min-w-0 flex-1 space-y-0">
            <span className="block truncate text-[13px] font-medium leading-tight text-foreground">
              {selected.code} — {selected.name}
            </span>
            <span className="block truncate text-[11px] leading-tight text-muted-foreground">
              {selected.expansionCode} — {selected.expansionName} — {legend(selected)}
            </span>
          </span>
        ) : (
          <span className="flex-1 truncate text-sm text-muted-foreground">
            {disabled ? "Nenhuma Coleção pendente no momento." : "Selecione uma Coleção..."}
          </span>
        )}
        <ChevronDown
          className={cn("h-4 w-4 shrink-0 text-muted-foreground transition-transform", open && "rotate-180")}
          aria-hidden="true"
        />
      </button>

      {open && !disabled && (
        <div
          role="listbox"
          className="absolute z-20 mt-1 max-h-72 w-full overflow-auto rounded-md border border-border bg-surface p-1 shadow-panel"
        >
          {cardSets.map((cardSet) => (
            <button
              key={cardSet.id}
              type="button"
              role="option"
              aria-selected={selected?.id === cardSet.id}
              onClick={() => {
                onSelect(cardSet.id);
                setOpen(false);
              }}
              className={cn(
                "block w-full rounded-md px-2.5 py-1 text-left transition-colors hover:bg-surface-muted",
                selected?.id === cardSet.id && "bg-surface-muted",
              )}
            >
              <span className="block truncate text-[13px] font-medium leading-tight text-foreground">
                {cardSet.code} — {cardSet.name}
              </span>
              <span className="block truncate text-[11px] leading-tight text-muted-foreground">
                {cardSet.expansionCode} — {cardSet.expansionName} — {legend(cardSet)}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
