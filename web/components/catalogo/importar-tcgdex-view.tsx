"use client";

import {
  useActionState,
  useCallback,
  useEffect,
  useRef,
  useState,
  useTransition,
  type ChangeEvent,
} from "react";
import { CheckCircle2, FolderPlus, HelpCircle, ListChecks, Search, type LucideIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RevisaoImportacaoTable } from "@/components/catalogo/revisao-importacao-table";
import type { CatalogImportJobStatus, CatalogImportRowView, CatalogoCardSetRow } from "@/lib/catalogo/queries";
import type { TcgdexAutoMatchResult, TcgdexSetCandidate } from "@/lib/catalogo/tcgdex-lookup";
import {
  buscarSetsTcgdexManualmente,
  getImportacaoJobData,
  iniciarImportacaoTcgdex,
  type IniciarImportacaoTcgdexActionState,
} from "@/app/catalogo/importar-cartas/tcgdex/actions";
import { cn } from "@/lib/utils";

const INITIAL_STATE: IniciarImportacaoTcgdexActionState = { error: null, jobId: null };

/**
 * Resultado da localização automática do Set na TCGdex (Ciclo 2, ADR-024) —
 * `MatchResultPanel` cobre os dois casos "raros" (AMBIGUOUS/NOT_FOUND, mais
 * de um candidato ou nenhum — precisam de uma lista/busca manual). O caso
 * comum, MATCHED, passou a ser tratado direto por `ImportarCartasView`
 * (botão "Analisar" ao lado do toggle de Fonte, no cabeçalho do card — ver
 * comentário lá) desde 2026-08-01, terceira rodada; `CandidateAnalyzeCard`
 * abaixo ainda sabe lidar com MATCHED por robustez de tipos, mas na prática
 * só é alcançado pelos ramos AMBIGUOUS/NOT_FOUND agora.
 *
 * O administrador nunca vê nem digita o external_set_id em nenhum caso —
 * mesmo princípio de sempre.
 */
export function MatchResultPanel({
  cardSet,
  matchResult,
}: {
  cardSet: Pick<CatalogoCardSetRow, "id">;
  matchResult: TcgdexAutoMatchResult;
}) {
  if (matchResult.status === "MATCHED") {
    return <CandidateAnalyzeCard cardSetId={cardSet.id} candidate={matchResult.set} />;
  }

  if (matchResult.status === "AMBIGUOUS") {
    return (
      // `space-y-4` no wrapper dos candidatos (era `space-y-2`, mesmo valor
      // usado *dentro* de cada candidato entre a caixa e seu próprio botão
      // Analisar) — gap maior entre grupos, gap menor dentro de cada grupo,
      // pra separar visualmente onde termina um candidato e começa o
      // próximo.
      <div className="space-y-2">
        <p className="flex items-center gap-1.5 text-sm font-medium text-foreground">
          <HelpCircle className="h-4 w-4 text-amber-600" aria-hidden="true" />
          Mais de um Set encontrado — selecione o correto
        </p>
        <div className="space-y-4">
          {matchResult.candidates.map((candidate) => (
            <CandidateAnalyzeCard key={candidate.id} cardSetId={cardSet.id} candidate={candidate} />
          ))}
        </div>
      </div>
    );
  }

  return <ManualSearchPanel cardSetId={cardSet.id} />;
}

function CandidateSummary({ candidate }: { candidate: TcgdexSetCandidate }) {
  return (
    <div className="rounded-md border border-input p-3">
      <p className="text-sm font-medium text-foreground">{candidate.name}</p>
      <p className="text-xs text-muted-foreground">{candidate.cardCountTotal} cartas</p>
    </div>
  );
}

/**
 * Hook compartilhado por `CandidateAnalyzeCard` e pelo botão "Analisar" do
 * cabeçalho de `ImportarCartasView` (caso comum, Set já localizado) — reúne
 * `useActionState(iniciarImportacaoTcgdex)` com a busca de job/linhas que
 * acontece logo depois, tudo em estado de componente React, **sem navegar**
 * (2026-08-01, terceira rodada).
 *
 * Antes, `iniciarImportacaoTcgdex` terminava com `redirect()` — pra uma
 * rota própria primeiro, depois pra `?jobId=` na mesma rota. Qualquer
 * `redirect()` força uma navegação: a página inteira remonta do zero no
 * servidor, e todo estado de componente cliente (a barra de progresso, os
 * ícones de etapa) é destruído no processo. Era exatamente isso que
 * Fabrício via como "a tabela é carregada em uma nova página" e "o
 * progresso desaparece" — não uma URL diferente por si só, mas a
 * consequência de qualquer navegação: perder o que estava montado. Agora a
 * action só devolve `{ jobId }`; este hook busca job+linhas via
 * `getImportacaoJobData` e guarda tudo em `useState`, então o progresso
 * (`ImportProgress`, com `done=true`) continua visível, empilhado acima da
 * `RevisaoImportacaoTable` quando aplicável, tudo na mesma árvore montada.
 */
export function useAnalyzeJob() {
  const [state, formAction, isPending] = useActionState(iniciarImportacaoTcgdex, INITIAL_STATE);
  const [jobState, setJobState] = useState<{ job: CatalogImportJobStatus | null; rows: CatalogImportRowView[] }>({
    job: null,
    rows: [],
  });
  const [fetchingJob, setFetchingJob] = useState(false);
  const fetchedJobIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (state.jobId && fetchedJobIdRef.current !== state.jobId) {
      fetchedJobIdRef.current = state.jobId;
      setFetchingJob(true);
      getImportacaoJobData(state.jobId).then((data) => {
        setJobState(data);
        setFetchingJob(false);
      });
    }
  }, [state.jobId]);

  const refreshJob = useCallback(async () => {
    if (!jobState.job) return;
    const data = await getImportacaoJobData(jobState.job.id);
    setJobState(data);
  }, [jobState.job]);

  return {
    formAction,
    error: state.error,
    isPending,
    fetchingJob,
    jobState,
    refreshJob,
    /** Já foi clicado em Analisar (mesmo que ainda processando) — some o botão, aparece o progresso. */
    started: isPending || fetchingJob || Boolean(jobState.job),
  };
}

const REVIEWABLE_STATUSES = new Set(["STAGED", "CONFIRMING"]);

/**
 * Um candidato (localizado automaticamente ou achado na busca manual) +
 * seu próprio botão Analisar + o que acontece depois de clicado — progresso
 * e, quando pronto, status do job + tabela de Revisão, tudo embutido aqui
 * mesmo, sem navegar (ver useAnalyzeJob acima).
 */
function CandidateAnalyzeCard({ cardSetId, candidate }: { cardSetId: string; candidate: TcgdexSetCandidate }) {
  const analyzeJob = useAnalyzeJob();

  return (
    <div className="space-y-3">
      {!analyzeJob.started ? (
        <form action={analyzeJob.formAction} className="space-y-2">
          <input type="hidden" name="card_set_id" value={cardSetId} />
          <input type="hidden" name="external_set_id" value={candidate.id} />
          <CandidateSummary candidate={candidate} />
          <Button type="submit">Analisar</Button>
          {analyzeJob.error && <p className="text-sm text-destructive">{analyzeJob.error}</p>}
        </form>
      ) : (
        // Sexta rodada (2026-08-01) — o card "Importação" (JobStatusView) foi
        // eliminado (pedido de Fabrício); o resultado que ele mostrava
        // (status/contagens/erro) migrou para dentro da própria etapa
        // "Concluído" do ImportProgress, via as props resultSummary/job.
        // `CandidateSummary` também some nesta fase — ficaria redundante com
        // esse mesmo resumo agora exibido ali dentro.
        <ImportProgress
          isPending={analyzeJob.isPending || analyzeJob.fetchingJob}
          done={Boolean(analyzeJob.jobState.job)}
          resultSummary={{ label: candidate.name, cardCount: candidate.cardCountTotal }}
          job={analyzeJob.jobState.job}
        />
      )}

      {analyzeJob.jobState.job && REVIEWABLE_STATUSES.has(analyzeJob.jobState.job.status) && (
        <RevisaoImportacaoTable
          jobId={analyzeJob.jobState.job.id}
          rows={analyzeJob.jobState.rows}
          onRefresh={analyzeJob.refreshJob}
        />
      )}
    </div>
  );
}

/** Etapas fixas exibidas durante o processamento — texto/ícones ilustrativos do que a chamada síncrona a iniciarImportacaoTcgdex de fato faz, não instrumentação real linha a linha. */
const IMPORT_PROGRESS_STEPS: { label: string; icon: LucideIcon }[] = [
  { label: "Abrindo job de importação", icon: FolderPlus },
  { label: "Buscando cartas na TCGdex", icon: Search },
  { label: "Processando e validando dados", icon: ListChecks },
];

const JOB_STATUS_LABEL: Record<string, string> = {
  RECEIVED: "Recebido",
  PROCESSING: "Processando",
  STAGED: "Aguardando revisão",
  CONFIRMING: "Confirmando",
  COMPLETED: "Concluído",
  COMPLETED_WITH_ERRORS: "Concluído com erros",
  FAILED: "Falhou",
  CANCELLED: "Cancelado",
};

const STEP_INTERVAL_MS = 1400;
const PERCENT_TICK_MS = 200;
/** Teto do avanço simulado enquanto ainda não sabemos a conclusão real — ver comentário abaixo. */
const PERCENT_CEILING = 92;

/**
 * Indicador visual de progresso — 2026-08-01, terceira rodada, redesenhado
 * a partir do feedback direto de Fabrício ("ficou bem pobre visualmente,
 * sem ícones como o modelo de referência que pedi"): cada etapa ganhou seu
 * próprio ícone semântico (`FolderPlus`/`Search`/`ListChecks`, não mais um
 * círculo genérico ou um spinner só na etapa ativa) — etapa pendente mostra
 * o próprio ícone esmaecido (`opacity-40`) em vez de um placeholder vazio,
 * etapa ativa em destaque (`animate-pulse` + cor primária), etapa concluída
 * em tom neutro (mesmo padrão do traço de atividade que Fabrício referenciou
 * como exemplo).
 *
 * `done` (antes só existia `isPending`): quando `true`, todas as etapas são
 * marcadas concluídas, a barra vai a 100% de verdade (não mais o teto
 * simulado de 92%) — o componente **continua montado e visível** mesmo
 * depois de `done`, porque quem chama (CandidateAnalyzeCard/
 * ImportarCartasView) não desmonta mais nada ao terminar (não há
 * navegação). Pedido explícito: "quero manter esse histórico de progresso
 * visível após sua conclusão".
 *
 * Sexta rodada (mesmo dia, "vamos valorizar esse progresso"):
 * 1. "Concluído" deixou de ser uma linha que só aparece quando `done` —
 *    agora é a 4ª etapa fixa da lista (ícone `CheckCircle2` esmaecido
 *    enquanto pendente, igual às outras três), ligada às anteriores por uma
 *    linha vertical contínua (`<span className="absolute ... w-px">` entre
 *    cada ícone) — pedido explícito: "inclua uma linha vertical entre os
 *    ícones... para aumentar o espaço entre as etapas e a sensação de
 *    progresso". `pb-4` (era `space-y-1.5`) dá o espaço extra que a linha
 *    precisa pra não ficar colada.
 * 2. `resultSummary`/`job` (novas props): o card "Importação" separado
 *    (`JobStatusView`) foi eliminado (pedido de Fabrício) — o que ele
 *    mostrava (nome do Set + contagem TCGdex, status do job, linhas/
 *    válidas/inseridas/atualizadas/falhas, resumo de erro) migrou pra
 *    dentro da própria etapa "Concluído", exibido só quando `done` é
 *    `true`. `job` é `null` enquanto o job ainda não foi buscado
 *    (`fetchingJob`) — nesse caso a etapa aparece concluída (ícone) mas
 *    sem o detalhe de contagens ainda.
 *
 * Enquanto ainda processando (`!done`), a porcentagem é uma simulação por
 * tempo com teto de 92% — não existe progresso granular real vindo do
 * backend nesta rodada (a Server Action é uma única chamada síncrona); só
 * quando `done` vira `true` (job de fato carregado) é que 100% reflete a
 * conclusão real.
 */
export function ImportProgress({
  isPending,
  done,
  resultSummary,
  job,
}: {
  isPending: boolean;
  done: boolean;
  /** Nome do Set localizado + quantidade de cartas na TCGdex — mesmo dado que antes vivia no box "Set localizado". */
  resultSummary?: { label: string; cardCount: number };
  /** Job carregado após a conclusão — `null`/`undefined` enquanto ainda buscando. */
  job?: CatalogImportJobStatus | null;
}) {
  const [percent, setPercent] = useState(0);
  const [stepIndex, setStepIndex] = useState(0);

  useEffect(() => {
    if (done) {
      setPercent(100);
      setStepIndex(IMPORT_PROGRESS_STEPS.length);
      return;
    }
    if (!isPending) return;

    const stepTimer = setInterval(() => {
      setStepIndex((index) => Math.min(index + 1, IMPORT_PROGRESS_STEPS.length - 1));
    }, STEP_INTERVAL_MS);
    const percentTimer = setInterval(() => {
      setPercent((value) =>
        value >= PERCENT_CEILING ? value : value + Math.max(1, Math.round((PERCENT_CEILING - value) * 0.08)),
      );
    }, PERCENT_TICK_MS);
    return () => {
      clearInterval(stepTimer);
      clearInterval(percentTimer);
    };
  }, [isPending, done]);

  // 4 linhas fixas: as 3 etapas simuladas + "Concluído" (só essa última
  // depende de `done`, não do relógio de stepIndex).
  const steps = [...IMPORT_PROGRESS_STEPS, { label: "Concluído", icon: CheckCircle2 }];

  return (
    <div className="space-y-3 rounded-md border border-border bg-surface-muted p-3">
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span>{done ? "Importação processada" : "Processando importação..."}</span>
          <span className="tabular-nums">{percent}%</span>
        </div>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-border">
          <div
            className="h-full rounded-full bg-primary transition-all duration-300 ease-out"
            style={{ width: `${percent}%` }}
          />
        </div>
      </div>
      <ol className="relative">
        {steps.map((step, index) => {
          const isConclusion = index === steps.length - 1;
          const status = isConclusion
            ? done
              ? "done"
              : "pending"
            : done || index < stepIndex
              ? "done"
              : index === stepIndex
                ? "active"
                : "pending";
          const Icon = step.icon;
          const isLast = index === steps.length - 1;

          return (
            <li key={step.label} className="relative flex gap-2.5 pb-4 last:pb-0">
              {!isLast && (
                <span aria-hidden="true" className="absolute left-[9px] top-[18px] bottom-0 w-px bg-border" />
              )}
              <span
                className={cn(
                  "relative z-10 flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-surface-muted",
                  status === "pending" && "opacity-40",
                )}
              >
                <Icon
                  className={cn(
                    "h-3.5 w-3.5",
                    isConclusion && status === "done"
                      ? "text-emerald-600"
                      : status === "active"
                        ? "animate-pulse text-primary"
                        : "text-muted-foreground",
                  )}
                  aria-hidden="true"
                />
              </span>
              <div className="min-w-0 flex-1 space-y-0.5 pt-0.5">
                <span
                  className={cn(
                    "text-xs",
                    status === "active" || (isConclusion && status === "done")
                      ? "font-medium text-foreground"
                      : "text-muted-foreground",
                    status === "pending" && "opacity-40",
                  )}
                >
                  {step.label}
                  {isConclusion && status === "done" && job && (
                    <Badge variant="outline" className="ml-1.5 align-middle">
                      {JOB_STATUS_LABEL[job.status] ?? job.status}
                    </Badge>
                  )}
                </span>
                {isConclusion && status === "done" && (
                  <div className="space-y-0.5 text-xs text-muted-foreground">
                    {resultSummary && (
                      <p>
                        {resultSummary.label} — {resultSummary.cardCount} cartas na TCGdex
                      </p>
                    )}
                    {job && (
                      <p>
                        {job.totalRows} linhas · {job.validRows} válidas · {job.insertedRows} inseridas ·{" "}
                        {job.updatedRows} atualizadas · {job.failedRows} falhas
                      </p>
                    )}
                    {job?.errorSummary && <p className="text-destructive">{job.errorSummary}</p>}
                  </div>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

/**
 * Busca manual — só aparece quando a localização automática não resolve
 * sozinha. Busca por nome (nunca por id técnico); os resultados usam o
 * mesmo CandidateAnalyzeCard da localização automática.
 */
function ManualSearchPanel({ cardSetId }: { cardSetId: string }) {
  const [query, setQuery] = useState("");
  const [candidates, setCandidates] = useState<TcgdexSetCandidate[]>([]);
  const [searched, setSearched] = useState(false);
  const [isPending, startTransition] = useTransition();

  function handleSearch() {
    if (!query.trim()) return;
    startTransition(async () => {
      const results = await buscarSetsTcgdexManualmente(query);
      setCandidates(results);
      setSearched(true);
    });
  }

  return (
    <div className="space-y-3">
      <p className="flex items-center gap-1.5 text-sm font-medium text-foreground">
        <Search className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
        Nenhuma correspondência automática — busque o Set pelo nome
      </p>
      <div className="flex gap-2">
        <input
          type="text"
          value={query}
          onChange={(event: ChangeEvent<HTMLInputElement>) => setQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              handleSearch();
            }
          }}
          placeholder="Nome do Set na TCGdex..."
          className="h-10 flex-1 rounded-md border border-input bg-surface px-3 text-sm shadow-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        />
        <Button type="button" variant="outline" onClick={handleSearch} disabled={isPending}>
          {isPending ? "Buscando..." : "Buscar"}
        </Button>
      </div>
      {searched && candidates.length === 0 && !isPending && (
        <p className="text-sm text-muted-foreground">Nenhum Set encontrado com esse nome.</p>
      )}
      <div className="space-y-4">
        {candidates.map((candidate) => (
          <CandidateAnalyzeCard key={candidate.id} cardSetId={cardSetId} candidate={candidate} />
        ))}
      </div>
    </div>
  );
}
