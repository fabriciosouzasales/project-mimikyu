"use client";

import { type KeyboardEvent, useActionState, useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  Copy,
  CreditCard,
  FolderPlus,
  ListChecks,
  Loader2,
  RotateCcw,
  Search,
  Sparkles,
  XCircle,
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
  type ImportacaoVariantesJobData,
  type IniciarImportacaoVariantesActionState,
} from "@/app/catalogo/importar-variantes/actions";
import type { VariantImportScopeCounters } from "@/lib/catalogo/variant-size-scope";
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
function useAnalyzeVariantsJob(resumeJobId: string | null = null) {
  const [state, formAction, isPending] = useActionState(iniciarImportacaoVariantes, INITIAL_STATE);
  const [jobState, setJobState] = useState<ImportacaoVariantesJobData>({
    job: null,
    rows: [],
    cardVariantTypes: [],
    counters: null,
    dataError: null,
  });
  // Semeado com `true` quando já sabemos que existe job ativo: a retomada
  // começa "carregando" no primeiro render, sem uma janela em que a tela diz
  // "Selecione uma Coleção" nem em que o botão fica clicável por engano.
  // `resumeJobId` é estável por montagem porque `page.tsx` usa
  // `key={selectedCardSet?.id}` — trocar de Coleção remonta o componente.
  const [fetchingJob, setFetchingJob] = useState(Boolean(resumeJobId));
  const fetchedJobIdRef = useRef<string | null>(null);

  // >>> RETOMADA FIRST-CLASS (2026-09-14) <<<
  // O read-model agora entrega `activeVariantJobId`. Quando ele existe, o job
  // é carregado DIRETAMENTE por `getImportacaoVariantesJobData` — a mesma
  // função que o caminho de análise já usava. Não se chama a Edge para
  // descobrir algo que já sabemos, e portanto não se usa mais
  // deliberadamente o par 409 `JOB_ALREADY_ACTIVE_FOR_CARD_SET` + recuperação
  // como fluxo NORMAL de retomada.
  //
  // Esse par continua intacto em `actions.ts` e segue sendo o caminho correto
  // para a corrida real: se o job terminar entre a renderização da página e o
  // clique, `activeVariantJobId` estará obsoleto e a submissão do formulário
  // resolve — criando job novo (se o anterior virou terminal) ou recuperando o
  // ativo (se outro apareceu). `state.jobId` tem precedência sobre
  // `resumeJobId` justamente para que o resultado da ação real prevaleça
  // sobre o snapshot da renderização.
  const jobIdToLoad = state.jobId ?? resumeJobId;

  useEffect(() => {
    if (jobIdToLoad && fetchedJobIdRef.current !== jobIdToLoad) {
      fetchedJobIdRef.current = jobIdToLoad;
      setFetchingJob(true);
      getImportacaoVariantesJobData(jobIdToLoad).then((data) => {
        setJobState(data);
        setFetchingJob(false);
      });
    }
  }, [jobIdToLoad]);

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
  counters,
  dataError,
}: {
  isPending: boolean;
  job: CatalogVariantImportJobStatus | null | undefined;
  /** `null` = não foi possível apurar (ver dataError). NUNCA zeros por omissão. */
  counters: VariantImportScopeCounters | null;
  dataError: string | null;
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

  // Três naturezas, três números — nunca `totalRows - validRows` (2026-09-15)
  // e nunca zeros por omissão (2026-09-16, BLOCKER-2). Os contadores vêm
  // derivados da coleção COMPLETA de linhas, e `null` significa literalmente
  // "não foi possível apurar" — não "nenhuma pendência".
  const pendenciasEditoriais = counters ? counters.mappingPendingRows + counters.unsupportedSizeRows : null;
  // "com pendência" só é relevante para o resultado de fato concluído
  // (STAGED/COMPLETED/COMPLETED_WITH_ERRORS) — um job ainda em andamento
  // não tem pendências/`failedRows` significativos ainda.
  //
  // outOfScopeRows NÃO entra: uma variante JUMBO não é problema a resolver, e
  // marcá-la como "issue" acenderia o alerta de um job perfeitamente sadio.
  //
  // dataError entra: se não conseguimos ler as linhas, a tela NÃO pode exibir
  // o ícone de sucesso. Sem saber, o estado honesto é "atenção".
  const hasIssues = Boolean(
    dataError || (job && (job.failedRows > 0 || (pendenciasEditoriais !== null && pendenciasEditoriais > 0))),
  );

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
            {formatNumber(job.totalRows)} variantes propostas · {formatNumber(job.validRows)} válidas
            {counters ? (
              <>
                {counters.mappingPendingRows > 0 &&
                  ` · ${formatNumber(counters.mappingPendingRows)} a revisar (sem mapeamento)`}
                {counters.unsupportedSizeRows > 0 &&
                  ` · ${formatNumber(counters.unsupportedSizeRows)} com tamanho desconhecido`}
                {counters.outOfScopeRows > 0 && ` · ${formatNumber(counters.outOfScopeRows)} fora de escopo (JUMBO)`}
              </>
            ) : null}
          </p>
          {dataError && <p className="text-destructive">{dataError}</p>}
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
                step.status === "done" && "border-success/30 bg-success/10 text-success",
                step.status === "active" && "animate-pulse border-primary/40 bg-primary/10 text-primary-ink",
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
const TERMINAL_STATUSES = new Set(["COMPLETED", "COMPLETED_WITH_ERRORS"]);

type ConclusionState = "success" | "pending" | "errors";

const CONCLUSION_META: Record<
  ConclusionState,
  { title: string; icon: LucideIcon; toneClass: string; iconWrapClass: string }
> = {
  success: {
    title: "Importação concluída",
    icon: CheckCircle2,
    toneClass: "text-success",
    iconWrapClass: "border-success/30 bg-success/10",
  },
  pending: {
    title: "Concluído com pendências",
    icon: AlertTriangle,
    toneClass: "text-warning",
    iconWrapClass: "border-warning/30 bg-warning/10",
  },
  errors: {
    title: "Concluído com erros",
    icon: XCircle,
    toneClass: "text-destructive",
    iconWrapClass: "border-destructive/30 bg-destructive/10",
  },
};

/**
 * Painel de conclusão persistente — fechamento de UX pedido por Fabrício
 * (2026-08-15). Antes, ao terminar a confirmação, `REVIEWABLE_STATUSES`
 * desmontava `RevisaoImportacaoVariantesTable` (levando junto seu
 * `confirmSummary` local, só existente enquanto o componente vive) e, se a
 * Coleção acabasse de zerar `cardsSemVariante`, ela também desaparecia de
 * `getCardSetsForVariantes()` — o `key` de `ImportarVariantesView` em
 * page.tsx mudava e a view inteira remontava, apagando o job. A segunda
 * causa foi corrigida em page.tsx (fallback `getCardSetForVariantesById`
 * mantém a Coleção selecionada estável); este painel resolve a primeira,
 * substituindo "nada renderizado" por um resumo real quando o job já é
 * terminal — sem depender do estado da tabela de revisão, que continua
 * desmontando normalmente (comportamento correto: não há mais nada para
 * decidir numa linha depois que o job conclui).
 *
 * Todos os números vêm só de `job` (CatalogVariantImportJobStatus, já
 * carregado por useAnalyzeVariantsJob) — nenhum round-trip novo.
 *
 * "Aprovadas" não existe como coluna própria do job. Deriva-se por
 * subtração exata, não aproximação: `admin_confirm_catalog_variant_import`
 * (Query 2145) só permite o job chegar a COMPLETED/COMPLETED_WITH_ERRORS
 * depois que toda linha já foi decidida (nenhuma decision_status PENDING
 * resta) — logo total_rows = rejected_rows + skipped_rows + aprovadas.
 *
 * Classificação em três estados, pela ordem pedida (sucesso completo /
 * concluído com pendências / concluído com erros): `errors` quando o
 * status é COMPLETED_WITH_ERRORS (houve failed_rows); senão `pending`
 * quando restou pendência editorial real — falta de mapeamento OU tamanho
 * desconhecido, contadas nas próprias linhas (job.mappingPendingRows /
 * job.unsupportedSizeRows), inclusive as já decididas como
 * REJECTED/SKIPPED, porque nenhuma delas ficou mapeada; senão `success`.
 *
 * 2026-09-15: linhas fora de escopo por tamanho (JUMBO) NÃO entram nessa
 * conta. Antes, o contador era `total_rows - valid_rows`, e a primeira
 * importação com uma variante JUMBO teria deixado o job eternamente
 * "concluído com pendências" — com um botão convidando o administrador a
 * resolver um mapeamento que não existe.
 */
function ImportConclusionPanel({
  job,
  counters,
  dataError,
  onImportarOutra,
}: {
  job: CatalogVariantImportJobStatus;
  /** `null` = não apurado. O painel NÃO declara sucesso nesse caso. */
  counters: VariantImportScopeCounters | null;
  dataError: string | null;
  onImportarOutra: () => void;
}) {
  const semMapeamento = counters?.mappingPendingRows ?? 0;
  const tamanhoDesconhecido = counters?.unsupportedSizeRows ?? 0;
  const foraDeEscopo = counters?.outOfScopeRows ?? 0;
  const pendenciasEditoriais = semMapeamento + tamanhoDesconhecido;
  const aprovadas = Math.max(job.totalRows - job.rejectedRows - job.skippedRows, 0);
  // FAIL-CLOSED: sem contadores, o estado NUNCA é `success`. Declarar sucesso
  // a partir de uma leitura que falhou é exatamente o BLOCKER-2.
  const state: ConclusionState =
    job.status === "COMPLETED_WITH_ERRORS" || !counters
      ? "errors"
      : pendenciasEditoriais > 0
        ? "pending"
        : "success";
  const meta = CONCLUSION_META[state];
  const Icon = meta.icon;

  const stats: { label: string; value: number }[] = [
    { label: "Analisadas", value: job.totalRows },
    { label: "Aprovadas", value: aprovadas },
    { label: "Inseridas", value: job.insertedRows },
    { label: "Inalteradas", value: job.unchangedRows },
    { label: "Rejeitadas", value: job.rejectedRows },
    { label: "Falhas", value: job.failedRows },
  ];
  // Cada natureza ganha seu próprio card, e só quando existe — a tela
  // continua enxuta nos jobs em que nada disso aconteceu.
  if (semMapeamento > 0) stats.push({ label: "Sem mapeamento", value: semMapeamento });
  if (tamanhoDesconhecido > 0) stats.push({ label: "Tamanho desconhecido", value: tamanhoDesconhecido });
  if (foraDeEscopo > 0) stats.push({ label: "Fora de escopo", value: foraDeEscopo });

  return (
    <Card>
      <CardContent className="space-y-4 pt-6">
        <div className="flex items-start gap-3">
          <span
            className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-full border", meta.iconWrapClass, meta.toneClass)}
            aria-hidden="true"
          >
            <Icon className="h-4 w-4" />
          </span>
          <div className="min-w-0 flex-1 space-y-0.5">
            <p className={cn("text-sm font-medium", meta.toneClass)}>{meta.title}</p>
            <p className="text-sm text-muted-foreground">
              {job.cardSetCode} — {job.cardSetName}
            </p>
            {job.errorSummary && <p className="text-xs text-destructive">{job.errorSummary}</p>}
            {dataError && <p className="text-xs text-destructive">{dataError}</p>}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {stats.map((stat) => (
            <div key={stat.label} className="rounded-lg border border-border bg-surface px-3 py-2">
              <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">{stat.label}</p>
              <p className="text-lg font-semibold text-foreground">{formatNumber(stat.value)}</p>
            </div>
          ))}
        </div>

        <div className="flex flex-wrap items-center gap-2 border-t border-border pt-4">
          {/* O botão leva a Card Variant Type, que só resolve FALTA DE
              MAPEAMENTO. Tamanho desconhecido é pendência, mas não desta
              tela — oferecê-la seria mandar o administrador ao lugar errado. */}
          {semMapeamento > 0 && (
            <Button asChild size="sm">
              <Link href="/catalogo/tipos-variacao">
                <Sparkles className="h-3.5 w-3.5" aria-hidden="true" />
                Resolver mapeamentos pendentes
              </Link>
            </Button>
          )}
          <Button asChild size="sm" variant={semMapeamento > 0 ? "outline" : "default"}>
            <Link href={`/catalogo/cartas?set=${encodeURIComponent(job.cardSetCode)}`}>
              <CreditCard className="h-3.5 w-3.5" aria-hidden="true" />
              Ver cartas da coleção
            </Link>
          </Button>
          <Button type="button" size="sm" variant="outline" onClick={onImportarOutra}>
            <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
            Importar outra coleção
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

export function ImportarVariantesView({
  cardSets,
  selectedCardSet,
}: {
  /** Coleções com pelo menos uma carta cadastrada E (cardsSemVariante > 0 OU job TCGDEX ativo/revisável) — filtro aplicado em page.tsx, ver getCardSetsForVariantes. */
  cardSets: CatalogoVariantCardSetRow[];
  selectedCardSet: CatalogoVariantCardSetRow | null;
}) {
  const router = useRouter();
  const analyzeJob = useAnalyzeVariantsJob(selectedCardSet?.activeVariantJobId ?? null);

  function navigate(next: { cardSetId?: string | null }) {
    const params = new URLSearchParams();
    const cardSetId = next.cardSetId !== undefined ? next.cardSetId : selectedCardSet?.id;
    if (cardSetId) params.set("cardSetId", cardSetId);
    const query = params.toString();
    router.push(query ? `/catalogo/importar-variantes?${query}` : "/catalogo/importar-variantes");
  }

  // Fail-closed: com mais de um job TCGDEX ativo para o mesmo Card Set, nem
  // retomada (o read-model já entrega `activeVariantJobId = null`) nem nova
  // análise. Bloquear o submit aqui é o que impede o único caminho restante
  // de arbitrar sozinho: a Edge responderia 409 e a recuperação em
  // `actions.ts` escolheria o job mais recente — exatamente a decisão que
  // ninguém autorizou.
  const jobConflict = selectedCardSet?.activeVariantJobConflict ?? false;
  const canAnalyzeHere = !!selectedCardSet && !analyzeJob.started && !jobConflict;

  // Três grandezas independentes, em três unidades que NUNCA se somam:
  //   Sets · Cards · linhas de staging a revisar.
  // `cardsSemVariante` segue com o significado de sempre (Cards sem nenhuma
  // card_variant) — o que mudou foi deixar de tratá-la como proxy de backlog
  // editorial, que agora tem métrica própria.
  const totalCardsSemVariante = cardSets.reduce((sum, cardSet) => sum + cardSet.cardsSemVariante, 0);
  const totalVariacoesARevisar = cardSets.reduce((sum, cardSet) => sum + cardSet.variacoesARevisar, 0);

  /** Microcópia do CTA — nunca "Analisar" quando já existe job ativo conhecido, e nunca "revisão" enquanto o job ainda processa. */
  const ctaLabel = (() => {
    if (jobConflict) return "Conflito de importações ativas";
    switch (selectedCardSet?.activeVariantJobStatus) {
      case "STAGED":
      case "CONFIRMING":
        return "Retomar revisão";
      case "RECEIVED":
      case "PROCESSING":
        return "Acompanhar processamento";
      default:
        return "Analisar";
    }
  })();

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
          label="Coleções com pendência"
          value={formatNumber(cardSets.length)}
          caption="sem variante ou com revisão aberta"
          icon={AlertTriangle}
          tone="danger"
        />
        <StatCard
          label="Cards sem variante"
          value={formatNumber(totalCardsSemVariante)}
          caption="nas coleções listadas"
          icon={Copy}
          tone="danger"
        />
        <StatCard
          label="Variações a revisar"
          value={formatNumber(totalVariacoesARevisar)}
          caption="em importações abertas"
          icon={ListChecks}
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
                {ctaLabel}
              </Button>
            </form>
          </div>

          <div className="space-y-4 border-t border-border pt-4">
            {!selectedCardSet ? (
              <p className="text-sm text-muted-foreground">Selecione uma Coleção acima para continuar.</p>
            ) : jobConflict ? (
              // Estado excepcional, tratado com o mínimo necessário: uma
              // mensagem explícita, nenhuma ação automática, nenhuma escolha
              // feita pelo sistema. Não há infraestrutura nova para isto.
              <div className="space-y-1">
                <p className="flex items-center gap-2 text-sm font-medium text-destructive">
                  <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                  Conflito de importações ativas — revisão necessária
                </p>
                <p className="text-sm text-muted-foreground">
                  Esta Coleção tem mais de uma importação de variantes em aberto ao mesmo tempo. O sistema não
                  escolhe qual delas continuar: retomar a errada levaria a revisar e confirmar dados do job errado.
                  Resolva as importações duplicadas antes de prosseguir — nenhuma análise nova será iniciada aqui.
                </p>
              </div>
            ) : (
              <>
                {analyzeJob.error && <p className="text-sm text-destructive">{analyzeJob.error}</p>}
                {analyzeJob.started && (
                  <ImportProgressVariantes
                    isPending={analyzeJob.isPending || analyzeJob.fetchingJob}
                    job={analyzeJob.jobState.job}
                    counters={analyzeJob.jobState.counters}
                    dataError={analyzeJob.jobState.dataError}
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

      {analyzeJob.jobState.job && TERMINAL_STATUSES.has(analyzeJob.jobState.job.status) && (
        <ImportConclusionPanel
          job={analyzeJob.jobState.job}
          counters={analyzeJob.jobState.counters}
          dataError={analyzeJob.jobState.dataError}
          onImportarOutra={() => {
            // Reset explícito, só disparado por ação do usuário — nunca
            // automático. Limpa `cardSetId` da URL: `selectedCardSet` volta
            // a `null` em page.tsx, o `key` de `ImportarVariantesView` muda
            // para "none" e a view remonta limpa, pronta para uma nova
            // Coleção. Mesmo mecanismo de reset que já existia para troca
            // manual de Coleção pelo combobox — só que agora só acontece
            // quando pedido.
            router.push("/catalogo/importar-variantes");
          }}
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

  /**
   * Legenda do item — três grandezas independentes, em segmentos separados por
   * `·`, nunca somadas entre si:
   *   cobertura de Card  ·  Cards sem variante  ·  pendência editorial/estado do job
   *
   * Os cinco casos possíveis:
   *   1. só Cards sem Variant ....... `279 cards sem variante`
   *   2. só pendência editorial ..... `24/24 cards com variante · 48 variações a revisar`
   *   3. ambos ...................... `47/53 cards com variante · 6 sem variante · 27 variações a revisar`
   *   4. RECEIVED/PROCESSING ........ `24/24 cards com variante · análise em andamento`
   *   5. CONFIRMING ................. `24/24 cards com variante · confirmação em andamento`
   *
   * Em 4 e 5 o job ainda não é revisável, então NÃO se fala em "revisar" — o
   * segmento comunica estado operacional, não backlog.
   */
  function legend(cardSet: CatalogoVariantCardSetRow): string {
    const partes: string[] = [];

    if (cardSet.cardsComVariante > 0) {
      partes.push(
        `${formatNumber(cardSet.cardsComVariante)}/${formatNumber(cardSet.cardsCatalogados)} cards com variante`,
      );
      if (cardSet.cardsSemVariante > 0) {
        partes.push(`${formatNumber(cardSet.cardsSemVariante)} sem variante`);
      }
    } else {
      partes.push(`${formatNumber(cardSet.cardsSemVariante)} cards sem variante`);
    }

    // Fail-closed antes de tudo: sob conflito não há status eleito para
    // descrever, e `variacoesARevisar` está neutralizado em 0 — mostrar
    // qualquer número aqui seria exibir dados de um job escolhido a esmo.
    if (cardSet.activeVariantJobConflict) {
      partes.push("conflito de importações ativas");
      return partes.join(" · ");
    }

    switch (cardSet.activeVariantJobStatus) {
      case "RECEIVED":
      case "PROCESSING":
        partes.push("análise em andamento");
        break;
      case "CONFIRMING":
        partes.push("confirmação em andamento");
        break;
      case "STAGED":
        if (cardSet.variacoesARevisar > 0) {
          partes.push(`${formatNumber(cardSet.variacoesARevisar)} variações a revisar`);
        } else {
          partes.push("revisão aberta");
        }
        break;
      default:
        break;
    }

    return partes.join(" · ");
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
