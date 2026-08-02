"use client";

import {
  useActionState,
  useCallback,
  useEffect,
  useRef,
  useState,
  useTransition,
  type ChangeEvent,
  type ReactNode,
} from "react";
import {
  AlertTriangle,
  CheckCircle2,
  FolderPlus,
  HelpCircle,
  ImageOff,
  ImagePlus,
  ListChecks,
  Search,
  type LucideIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RevisaoImportacaoTable } from "@/components/catalogo/revisao-importacao-table";
import type { CatalogImportJobStatus, CatalogImportRowView, CatalogoCardSetRow } from "@/lib/catalogo/queries";
import type { TcgdexAutoMatchResult, TcgdexSetCandidate } from "@/lib/catalogo/tcgdex-lookup";
import {
  abrirImportacaoImagens,
  buscarSetsTcgdexManualmente,
  executarImportacaoImagens,
  getImportacaoJobData,
  iniciarImportacaoTcgdex,
  type IniciarImportacaoImagensResult,
  type IniciarImportacaoTcgdexActionState,
  type ProgressoImportacaoImagens,
} from "@/app/catalogo/importar-cartas/tcgdex/actions";
import {
  fetchProgressoImportacaoImagens,
  MAX_IMAGE_IMPORT_RETRY_ATTEMPTS,
} from "@/lib/catalogo/asset-import-progress-client";
import { cn } from "@/lib/utils";

const INITIAL_STATE: IniciarImportacaoTcgdexActionState = { error: null, jobId: null };

// Continuação automática cartas→imagens (2026-08-02, suporte EN + PT-BR):
// idioma fixo `pt-BR`, escolhido deliberadamente diferente do default 'en'
// de `abrirImportacaoImagens`/`admin_start_asset_import_run()` — pedido
// explícito de Fabrício ("O processo de importação das imagens só importou
// as cartas em inglês, ficaram pendentes as 266 imagens em PT"): o pipeline
// de imagens já rodava majoritariamente em inglês por padrão histórico
// (LANGUAGE_CODE fixo na Edge Function até a v2.9.0); a lacuna real e
// recorrente é justamente PT-BR nunca ser importado automaticamente. A
// importação em inglês continua disponível via a tela dedicada
// `/catalogo/importar-imagens?idioma=en` (`LanguageToggle`) — esta
// continuação automática cobre só o idioma que faltava.
const AUTO_CONTINUATION_LANGUAGE_CODE = "pt-BR";

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
 *
 * `cardSetId` (novo parâmetro, 2026-08-01, emenda de ADR-024 "Continuação
 * automática: cartas → imagens") — os dois pontos de chamada
 * (`CandidateAnalyzeCard`/`ImportarCartasView`) já têm esse valor à mão
 * (prop/`selectedCardSet.id`); passá-lo pro hook mantém a orquestração da
 * continuação automática num único lugar, em vez de duplicar o `useEffect`
 * abaixo nos dois componentes.
 */
export function useAnalyzeJob(cardSetId: string) {
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

  // Continuação automática: cartas → imagens (2026-08-01, emenda de
  // ADR-024, pedido de Fabrício: "Após a confirmação das cartas, o fluxo de
  // importação deve continuar automaticamente com a importação das
  // imagens"). Dispara exatamente uma vez por job, assim que ele chega a um
  // status final "produtivo" (COMPLETED/COMPLETED_WITH_ERRORS — cartas de
  // fato persistidas, ainda que com falhas pontuais) — nunca para
  // FAILED/CANCELLED, onde não há Cards novas para anexar imagem.
  // `imageTriggeredJobIdRef` evita disparar de novo a cada `refreshJob()`
  // subsequente (ex.: o próprio `router.refresh()` de `confirmarImportacao`
  // já causa uma re-renderização com o mesmo job final).
  const [imagePhase, setImagePhase] = useState<"idle" | "checking" | "importing" | "done">("idle");
  const [imageResult, setImageResult] = useState<IniciarImportacaoImagensResult | null>(null);
  // Progresso ao vivo (2026-08-02, pedido explícito de Fabrício: "quero
  // colocar um contador ao lado do Step Importando imagens... Quero
  // enxergar o progresso real") — populado por polling em
  // `asset_import_run` (via `fetchProgressoImportacaoImagens`) enquanto a
  // Edge Function processa o lote, em paralelo à chamada bloqueante de
  // `executarImportacaoImagens`. `null` até o primeiro polling responder.
  const [imageProgress, setImageProgress] = useState<ProgressoImportacaoImagens | null>(null);
  // Retry automático (2026-08-02, mesmo dia, rodada seguinte): número da
  // tentativa em curso — ver comentário completo no `useEffect` abaixo.
  const [imageAttempt, setImageAttempt] = useState(0);
  const imageTriggeredJobIdRef = useRef<string | null>(null);

  useEffect(() => {
    const job = jobState.job;
    if (!job || (job.status !== "COMPLETED" && job.status !== "COMPLETED_WITH_ERRORS")) return;
    if (imageTriggeredJobIdRef.current === job.id) return;
    imageTriggeredJobIdRef.current = job.id;
    // `catalogJobId` (2026-08-02, mesmo dia, rodada seguinte) — capturado
    // aqui fora de qualquer closure aninhada: `job` é `const`, mas o
    // TypeScript não propaga o null-check acima para dentro de
    // `runUntilDone` (função aninhada, definida bem mais abaixo) — mesmo
    // motivo já documentado para `run`/`activeRun` em
    // `import-card-assets/index.ts`.
    const catalogJobId = job.id;

    let cancelled = false;
    let pollTimer: ReturnType<typeof setInterval> | undefined;

    setImagePhase("checking");
    setImageProgress(null);
    setImageAttempt(0);

    // Fluxo em duas fases (2026-08-02, mesma emenda do contador ao vivo):
    // `abrirImportacaoImagens` é uma chamada rápida (só abre/reaproveita a
    // run via RPC) que devolve o `runCode` de imediato, permitindo começar
    // o polling em paralelo à chamada longa e bloqueante de
    // `executarImportacaoImagens` (o fetch de fato à Edge Function).
    abrirImportacaoImagens(
      cardSetId,
      `catalog_import_job:${job.id}`,
      AUTO_CONTINUATION_LANGUAGE_CODE,
    ).then((openResult) => {
      if (cancelled) return;

      if (!openResult.supported) {
        setImageResult({
          supported: false,
          success: true,
          error: null,
          imagesImported: 0,
          imagesFailed: 0,
          imagesTotal: 0,
          runCode: null,
          runExpired: false,
        });
        setImagePhase("done");
        return;
      }
      if (openResult.error || !openResult.runCode) {
        setImageResult({
          supported: true,
          success: false,
          error: openResult.error,
          imagesImported: 0,
          imagesFailed: 0,
          imagesTotal: 0,
          runCode: null,
          runExpired: false,
        });
        setImagePhase("done");
        return;
      }
      if (openResult.alreadyActive) {
        setImageResult({
          supported: true,
          success: true,
          error: null,
          imagesImported: 0,
          imagesFailed: 0,
          imagesTotal: 0,
          runCode: openResult.runCode,
          runExpired: false,
        });
        setImagePhase("done");
        return;
      }

      setImagePhase("importing");
      // `runCodeRef` (era `const runCode`, 2026-08-02, mesmo dia, rodada
      // seguinte, mesma correção de `importar-imagens-view.tsx`) — precisa
      // ser mutável agora: o retry automático abaixo pode trocar de
      // run_code no meio do laço, e o polling precisa acompanhar qual run
      // está valendo a cada momento.
      const runCodeRef = { current: openResult.runCode };
      pollTimer = setInterval(() => {
        fetchProgressoImportacaoImagens(runCodeRef.current).then((progress) => {
          if (!cancelled && progress) setImageProgress(progress);
        });
      }, 2000);

      // Retry automático (2026-08-02, pedido explícito de Fabrício depois
      // de ver a importação de SV4 falhar de novo com HTTP 504 apesar do
      // progresso real de 115→169 imagens): o teto de execução da
      // plataforma para a Edge Function não muda — uma Coleção grande
      // sempre precisa de várias chamadas. Em vez de exigir um clique
      // manual a cada falha, repete `executarImportacaoImagens` com o
      // MESMO `runCode` até `imagesFailed` chegar a 0 ou parar de
      // progredir (nenhuma imagem nova desde a tentativa anterior — sinal
      // de falha real e persistente, não mais de timeout de plataforma) ou
      // até o teto de segurança `MAX_IMAGE_IMPORT_RETRY_ATTEMPTS`.
      //
      // `result.runExpired` (2026-08-02, mesmo dia, rodada seguinte) — bug
      // real corrigido (ME5, mesma causa documentada em
      // `importar-imagens-view.tsx`): reusar o MESMO `runCode` só é
      // seguro/correto quando a run ficou presa em `RUNNING` (a plataforma
      // matou a função no meio, sem nunca chegar ao `finishImportRun` que a
      // fecharia). Se a run já chegou a um status TERMINAL por um erro real
      // de aplicação, a máquina de estados nunca permite reabri-la — a
      // Edge Function (v2.9.2) sinaliza esse caso via `runExpired`; quando
      // verdadeiro, em vez de insistir na run morta, abre uma run NOVA
      // (`abrirImportacaoImagens` de novo) e continua o retry com ela.
      let attempt = 0;
      let lastImported = -1;

      async function runUntilDone(): Promise<IniciarImportacaoImagensResult> {
        let result: IniciarImportacaoImagensResult;
        do {
          attempt += 1;
          if (!cancelled) setImageAttempt(attempt);
          result = await executarImportacaoImagens(cardSetId, runCodeRef.current, AUTO_CONTINUATION_LANGUAGE_CODE);
          if (cancelled) return result;

          if (result.runExpired && attempt < MAX_IMAGE_IMPORT_RETRY_ATTEMPTS) {
            const reopened = await abrirImportacaoImagens(
              cardSetId,
              `catalog_import_job:${catalogJobId}`,
              AUTO_CONTINUATION_LANGUAGE_CODE,
            );
            if (cancelled) return result;
            if (reopened.supported && reopened.runCode && !reopened.alreadyActive) {
              runCodeRef.current = reopened.runCode;
              continue;
            }
          }

          if (result.imagesImported === lastImported) break;
          lastImported = result.imagesImported;
        } while (
          result.supported &&
          result.imagesFailed > 0 &&
          attempt < MAX_IMAGE_IMPORT_RETRY_ATTEMPTS
        );
        return { ...result, runCode: runCodeRef.current };
      }

      runUntilDone().then((result) => {
        if (pollTimer) clearInterval(pollTimer);
        if (cancelled) return;
        setImageResult(result);
        setImagePhase("done");
      });
    });

    return () => {
      cancelled = true;
      if (pollTimer) clearInterval(pollTimer);
    };
  }, [jobState.job, cardSetId]);

  return {
    formAction,
    error: state.error,
    isPending,
    fetchingJob,
    jobState,
    refreshJob,
    imagePhase,
    imageResult,
    imageProgress,
    imageAttempt,
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
  const analyzeJob = useAnalyzeJob(cardSetId);

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
          imagePhase={analyzeJob.imagePhase}
          imageResult={analyzeJob.imageResult}
          imageProgress={analyzeJob.imageProgress}
          imageAttempt={analyzeJob.imageAttempt}
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

/** Status finais de um job — depois de STAGED/CONFIRMING (`REVIEWABLE_STATUSES`), é onde ele pousa. Usado por `ImportProgress` para saber quando mostrar a etapa de confirmação (ver comentário lá). */
const IMPORT_FINAL_STATUSES = new Set(["COMPLETED", "COMPLETED_WITH_ERRORS", "FAILED", "CANCELLED"]);

const STEP_INTERVAL_MS = 1400;
const PERCENT_TICK_MS = 200;
/** Teto do avanço simulado enquanto ainda não sabemos a conclusão real — ver comentário abaixo. */
const PERCENT_CEILING = 92;
/**
 * Teto separado para a fase de imagens (2026-08-02, correção de bug real
 * reportado por Fabrício: a barra ficava em 100% com o rótulo ainda dizendo
 * "Importando imagens" — o efeito abaixo considerava `done` só o suficiente
 * para pular pra 100%, sem saber que a continuação automática de imagens
 * ainda tinha etapas pela frente). Mais alto que `PERCENT_CEILING` porque a
 * essa altura o trabalho "pesado" (download/upload de cada carta) já é a
 * maior parte do tempo restante — só o "Finalizando" propriamente dito falta.
 */
const IMAGE_PERCENT_CEILING = 97;

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
 * Oitava rodada (mesmo dia, pedido explícito depois de confirmar uma
 * importação parcial de SV2 com sucesso): "Concluído" (a etapa 4) marca o
 * fim da ANÁLISE — job criado e, se `STAGED`/`CONFIRMING`, ainda esperando
 * revisão/confirmação manual. Isso não é a mesma coisa que a importação
 * estar de fato terminada, e o pedido foi por uma etapa própria pra esse
 * segundo momento: "mais um step no fluxo do progresso (importação
 * concluída com sucesso)". Uma 5ª etapa condicional aparece quando o job
 * chega a um status final (`IMPORT_FINAL_STATUSES` — depois de
 * Confirmar) — as contagens (linhas/válidas/inseridas/atualizadas/falhas)
 * e o resumo de erro saíram da etapa "Concluído" e passaram a viver aqui,
 * já que só fazem sentido de verdade depois da confirmação (antes disso,
 * inseridas/atualizadas são sempre 0). A etapa "Concluído" agora só mostra
 * o Set localizado; o rótulo/ícone/tom da 5ª etapa mudam conforme o
 * resultado real (sucesso, com falhas, falhou, cancelado) — nunca um
 * genérico "Concluído" repetido duas vezes.
 *
 * Emenda de ADR-024, "Continuação automática: cartas → imagens"
 * (2026-08-01, pedido de Fabrício: "Após a confirmação das cartas, o fluxo
 * de importação deve continuar automaticamente com a importação das
 * imagens... A barra de progresso deve ganhar novas etapas"). A 5ª etapa
 * (rótulo antes dinâmico — "Importação concluída com sucesso"/"...com
 * falhas"/"...falhou"/"...cancelada") vira `cardsWrittenStep`, rótulo fixo
 * "Gravando cartas" (mesmo ícone/tom/corpo de antes — só o rótulo deixou de
 * mudar conforme o resultado, pedido explícito de Fabrício usava esse nome
 * fixo na lista de etapas). Três novas etapas só aparecem depois dela,
 * **só quando o job chega a COMPLETED/COMPLETED_WITH_ERRORS** (nunca para
 * FAILED/CANCELLED, onde não há Cards novas pra anexar imagem — ver
 * `useAnalyzeJob`, que só dispara a continuação automática nesses dois
 * casos):
 * 1. "Verificando disponibilidade das imagens" — `imagePhase === "checking"`.
 * 2. "Importando imagens" — `imagePhase === "importing"`; corpo final
 *    depende de `imageResult.supported`: quando `false` (Promo/Energia/Set
 *    fora da TCGdex), mostra uma mensagem informativa, nunca um erro
 *    ("Não tratar como erro", pedido explícito) — o Card Set continua
 *    disponível pro pipeline manual já existente, intocado por esta
 *    emenda.
 * 3. "Finalizando importação" — só etapa realmente terminal agora;
 *    resumo final com as três contagens pedidas explicitamente: "Cartas
 *    cadastradas", "Imagens importadas", "Imagens pendentes" (falhas
 *    parciais de imagem viram "pendentes", nunca impedem a conclusão do
 *    cadastro de cartas — pedido explícito).
 *
 * `mode="images-only"` (2026-08-02, nova tela dedicada
 * `/catalogo/importar-imagens` — ver `importar-imagens-view.tsx`): quando a
 * Coleção já tem todas as Cards cadastradas e só falta retomar a importação
 * de imagens (sem nenhum job de cartas envolvido), as três primeiras etapas
 * ("Abrindo job"/"Buscando cartas"/"Processando"), "Concluído" e "Gravando
 * cartas" não fazem sentido — não há job de cartas para abrir, buscar ou
 * gravar. Neste modo, `job`/`resultSummary` são ignorados e a lista de
 * etapas começa direto em "Verificando disponibilidade das imagens";
 * `totalCards` substitui `job.insertedRows + job.updatedRows` como a base do
 * resumo final (nenhum job para ler essas contagens). Mesmo componente
 * visual (mesma barra, mesmos ícones/tons) — só a lista de etapas muda.
 */
export function ImportProgress({
  mode = "full",
  isPending,
  done,
  resultSummary,
  job,
  totalCards,
  imagePhase,
  imageResult,
  imageProgress,
  imageAttempt,
}: {
  /** "full" (padrão): fluxo completo cartas→imagens. "images-only": só as três etapas de imagem, sem job de cartas. */
  mode?: "full" | "images-only";
  isPending: boolean;
  done: boolean;
  /** Nome do Set localizado + quantidade de cartas na TCGdex — mesmo dado que antes vivia no box "Set localizado". Ignorado em `mode="images-only"`. */
  resultSummary?: { label: string; cardCount: number };
  /** Job carregado após a conclusão — `null`/`undefined` enquanto ainda buscando. Ignorado em `mode="images-only"`. */
  job?: CatalogImportJobStatus | null;
  /** Total de Cards da Coleção — só usado em `mode="images-only"` (substitui `job.insertedRows + job.updatedRows` no resumo final, já que não há job de cartas). */
  totalCards?: number;
  /** Fase da continuação automática de imagens (useAnalyzeJob) — `undefined`/`"idle"` quando ainda não disparou (job não chegou a um status final "produtivo", ou nem existe). */
  imagePhase?: "idle" | "checking" | "importing" | "done";
  /** Resultado final da continuação de imagens — só preenchido quando `imagePhase === "done"`. */
  imageResult?: IniciarImportacaoImagensResult | null;
  /** Progresso ao vivo (2026-08-02) — polling de `asset_import_run` enquanto `imagePhase === "importing"`, ver `fetchProgressoImportacaoImagens`. `null`/`undefined` até o primeiro polling responder. */
  imageProgress?: ProgressoImportacaoImagens | null;
  /**
   * Número da tentativa atual de retry automático (2026-08-02, pedido
   * explícito de Fabrício depois de ver a importação de SV4 falhar de novo
   * com HTTP 504 apesar do progresso real — o teto de execução da Edge
   * Function não muda, então uma Coleção grande sempre precisa de várias
   * chamadas): quando `> 1`, mostrado como "(tentativa N)" ao lado do
   * rótulo, para deixar claro que o sistema está repetindo sozinho, não
   * travado. `1`/`undefined` na primeira tentativa não mostra nada.
   */
  imageAttempt?: number;
}) {
  const [percent, setPercent] = useState(0);
  const [stepIndex, setStepIndex] = useState(0);

  // Determinístico a partir de `job.status` (não de `imagePhase`) — evita um
  // falso "100%" de um único render entre `done` virar `true` e o `useEffect`
  // de `useAnalyzeJob` conseguir disparar `setImagePhase("checking")` logo
  // em seguida. Mesmo critério de `showImageSteps` mais abaixo. Em
  // `mode="images-only"` as etapas de imagem sempre entram — não há job de
  // cartas para checar `status` nenhum.
  const willRunImageSteps =
    mode === "images-only"
      ? true
      : Boolean(job && (job.status === "COMPLETED" || job.status === "COMPLETED_WITH_ERRORS"));
  const imagesInFlight = imagePhase === "checking" || imagePhase === "importing";
  // "De verdade" concluído: ou o job nem vai ganhar etapas de imagem (ex.:
  // FAILED/CANCELLED), ou já ganhou e a continuação de imagens também
  // terminou (`imagePhase === "done"`) — nunca só por `done` (job carregado)
  // sozinho, que era o bug reportado (barra em 100% com "Importando
  // imagens" ainda em andamento). Em `mode="images-only"` não há `done`
  // (job) para compor — só a própria fase de imagens decide.
  const fullyDone = mode === "images-only" ? imagePhase === "done" : done && (!willRunImageSteps || imagePhase === "done");

  useEffect(() => {
    if (fullyDone) {
      setPercent(100);
      setStepIndex(IMPORT_PROGRESS_STEPS.length);
      return;
    }
    if (mode === "images-only" ? !imagesInFlight : !isPending && !imagesInFlight) return;

    // Progresso real (2026-08-02) — assim que o polling de
    // `asset_import_run` responde, a barra passa a refletir a proporção
    // real processada/solicitada em vez da curva simulada abaixo. Só entra
    // em vigor durante a fase de imagens, onde o dado existe.
    if (imagesInFlight && imageProgress && imageProgress.requestedCount > 0) {
      const ratio = imageProgress.processedCount / imageProgress.requestedCount;
      setPercent(Math.min(IMAGE_PERCENT_CEILING, Math.round(ratio * IMAGE_PERCENT_CEILING)));
      return;
    }

    // Teto mais alto durante a fase de imagens (ver `IMAGE_PERCENT_CEILING`)
    // — a barra continua avançando visivelmente enquanto a Edge Function
    // processa a coleção, em vez de ficar parada num valor qualquer
    // esperando `imagePhase` virar "done".
    const ceiling = imagesInFlight ? IMAGE_PERCENT_CEILING : PERCENT_CEILING;

    const stepTimer =
      mode !== "images-only" && isPending
        ? setInterval(() => {
            setStepIndex((index) => Math.min(index + 1, IMPORT_PROGRESS_STEPS.length - 1));
          }, STEP_INTERVAL_MS)
        : undefined;
    const percentTimer = setInterval(() => {
      setPercent((value) => (value >= ceiling ? value : value + Math.max(1, Math.round((ceiling - value) * 0.08))));
    }, PERCENT_TICK_MS);
    return () => {
      if (stepTimer) clearInterval(stepTimer);
      clearInterval(percentTimer);
    };
  }, [isPending, fullyDone, imagesInFlight, mode, imageProgress]);

  type StepStatus = "pending" | "active" | "done";
  type StepTone = "neutral" | "success" | "warning";
  type Step = { key: string; label: string; icon: LucideIcon; status: StepStatus; tone: StepTone; body?: ReactNode };

  const analysisSteps: Step[] =
    mode === "images-only"
      ? []
      : IMPORT_PROGRESS_STEPS.map((step, index) => ({
          key: step.label,
          label: step.label,
          icon: step.icon,
          status: done || index < stepIndex ? "done" : index === stepIndex ? "active" : "pending",
          tone: "neutral",
        }));

  const conclusionStep: Step | null =
    mode === "images-only"
      ? null
      : {
          key: "conclusao",
          label: "Concluído",
          icon: CheckCircle2,
          status: done ? "done" : "pending",
          tone: "success",
          body: done && resultSummary && (
            <p>
              {resultSummary.label} — {resultSummary.cardCount} cartas na TCGdex
            </p>
          ),
        };

  // Só aparece depois que o job chega a um status final — ver comentário
  // da função acima ("Oitava rodada"). Sempre `false` em `mode="images-only"`
  // (não há job de cartas).
  const isFinal = mode !== "images-only" && Boolean(job && IMPORT_FINAL_STATUSES.has(job.status));
  const hasFailures = Boolean(job && (job.failedRows > 0 || job.status === "COMPLETED_WITH_ERRORS"));
  // Rótulo fixo "Gravando cartas" (era dinâmico — ver "Emenda de ADR-024"
  // no comentário da função) — tom/ícone/corpo continuam refletindo o
  // resultado real da confirmação, só o texto do rótulo parou de mudar.
  const cardsWrittenStep: Step | null =
    isFinal && job
      ? {
          key: "gravando-cartas",
          label: "Gravando cartas",
          icon: hasFailures || job.status === "FAILED" ? AlertTriangle : CheckCircle2,
          status: "done",
          tone: hasFailures || job.status === "FAILED" ? "warning" : "success",
          body: (
            <>
              <p>
                {job.totalRows} linhas · {job.validRows} válidas · {job.insertedRows} inseridas ·{" "}
                {job.updatedRows} atualizadas · {job.failedRows} falhas
              </p>
              {job.errorSummary && <p className="text-destructive">{job.errorSummary}</p>}
            </>
          ),
        }
      : null;

  // Continuação automática de imagens — só quando o job persistiu cartas de
  // fato (COMPLETED/COMPLETED_WITH_ERRORS, nunca FAILED/CANCELLED; ver
  // useAnalyzeJob, que só dispara a chamada nesses dois casos). `imagePhase`
  // chega `undefined`/`"idle"` em qualquer outro cenário — as três etapas
  // abaixo simplesmente não entram na lista. Mesmo critério de
  // `willRunImageSteps` (calculado mais acima, para a barra de progresso) —
  // reaproveitado aqui para não ter duas fontes de verdade.
  const showImageSteps = willRunImageSteps;

  const verifyingImagesStep: Step | null = showImageSteps
    ? {
        key: "verificando-imagens",
        label: "Verificando disponibilidade das imagens",
        icon: Search,
        status: !imagePhase || imagePhase === "idle" ? "pending" : imagePhase === "checking" ? "active" : "done",
        tone: "neutral",
      }
    : null;

  // Erro real ao abrir a run/chamar a Edge Function (rede, 500 etc.) — nunca
  // confundido com "sem suporte na TCGdex" (`supported = false`, caminho
  // normal) nem com "algumas imagens falharam" (`imagesFailed > 0`, ainda
  // `success = true`).
  const imageHardError = Boolean(imageResult && !imageResult.success && imageResult.error);
  const importingImagesStep: Step | null = showImageSteps
    ? {
        key: "importando-imagens",
        label: "Importando imagens",
        icon: imageResult && !imageResult.supported ? ImageOff : ImagePlus,
        status:
          !imagePhase || imagePhase === "idle" || imagePhase === "checking"
            ? "pending"
            : imagePhase === "importing"
              ? "active"
              : "done",
        tone: imageHardError || (imageResult && imageResult.imagesFailed > 0) ? "warning" : "success",
        // Contador ao vivo (2026-08-02, pedido explícito de Fabrício: "quero
        // colocar um contador... que indique a quantidade de imagens
        // importadas e o total a ser importada. Quero enxergar o progresso
        // real") — enquanto `imagePhase === "importing"`, mostra
        // `imageProgress` (polling de `asset_import_run` via
        // `getProgressoImportacaoImagens`, gravado a cada lote pela Edge
        // Function v2.7.0). `requestedCount > 0` evita mostrar "0 de 0"
        // antes do primeiro polling retornar dados reais.
        body:
          imagePhase === "importing" && imageProgress && imageProgress.requestedCount > 0 ? (
            <p className="tabular-nums">
              {imageProgress.processedCount} de {imageProgress.requestedCount} processadas
              {imageProgress.successCount > 0 && ` · ${imageProgress.successCount} importadas`}
              {imageProgress.failedCount > 0 && ` · ${imageProgress.failedCount} falharam`}
            </p>
          ) : (
            imagePhase === "done" &&
            imageResult && (
              <>
                {imageHardError ? (
                  <p className="text-destructive">{imageResult.error}</p>
                ) : !imageResult.supported ? (
                  <p>
                    Este Card Set não está disponível na TCGdex — as imagens deverão ser importadas posteriormente
                    pelo pipeline manual já existente.
                  </p>
                ) : (
                  <p>
                    {imageResult.imagesImported} importada{imageResult.imagesImported === 1 ? "" : "s"}
                    {imageResult.imagesFailed > 0 &&
                      `, ${imageResult.imagesFailed} pendente${imageResult.imagesFailed === 1 ? "" : "s"} (falharam — seguem disponíveis pelo pipeline manual)`}
                    .
                  </p>
                )}
              </>
            )
          ),
      }
    : null;

  // `totalCards` (prop, só em `mode="images-only"`) substitui
  // `job.insertedRows + job.updatedRows` — não há job de cartas nesse modo,
  // a Coleção já tinha todas as Cards cadastradas de antes.
  const cardsCatalogadas = mode === "images-only" ? (totalCards ?? 0) : job ? job.insertedRows + job.updatedRows : 0;
  // "Pendentes": `imageResult.imagesFailed` é a fonte de verdade sempre que
  // `supported = true` — inclusive em erro real (`imageHardError`), desde a
  // correção de 2026-08-02 (revisão `1.33`): `contarImagensImportadas`
  // (`tcgdex/actions.ts`) já consulta a contagem real de `card_asset` no
  // banco nos dois caminhos de erro, então `imagesFailed` não é mais "0
  // forçado" nesse caso. Bug real corrigido aqui (2026-08-02, mesmo dia,
  // rodada seguinte): a checagem extra `!imageHardError` ainda fazia esta
  // conta cair para `cardsCatalogadas` (o TOTAL de Cards da Coleção) em vez
  // do que de fato falta — reportado por Fabrício ao ver "Imagens
  // pendentes: 266" (o total) numa Coleção que já tinha 115 imagens de
  // antes, quando o correto era 151 (266 - 115). Só cai para
  // `cardsCatalogadas` quando `supported = false` (Card Set genuinamente
  // fora da TCGdex — nenhuma imagem automática é possível, tudo mesmo
  // pendente pro pipeline manual).
  const imagesPendentes = imageResult ? (imageResult.supported ? imageResult.imagesFailed : cardsCatalogadas) : 0;
  const finalizingStep: Step | null = showImageSteps
    ? {
        key: "finalizando",
        label: "Finalizando importação",
        icon: CheckCircle2,
        status: imagePhase === "done" ? "done" : "pending",
        tone: imageHardError || (imageResult && imageResult.supported && imageResult.imagesFailed > 0) ? "warning" : "success",
        // "Cartas cadastradas" só faz sentido em `mode="full"` (é o resultado
        // do job de cartas que acabou de rodar) — em `mode="images-only"` a
        // Coleção já tinha todas as Cards de antes, então o resumo final
        // mostra só as duas contagens de imagem.
        body: imagePhase === "done" && imageResult && (
          <p>
            {mode === "full" && `Cartas cadastradas: ${cardsCatalogadas} · `}
            Imagens importadas: {imageResult.imagesImported} · Imagens pendentes: {imagesPendentes}
          </p>
        ),
      }
    : null;

  const steps: Step[] = [
    ...analysisSteps,
    ...(conclusionStep ? [conclusionStep] : []),
    ...(cardsWrittenStep ? [cardsWrittenStep] : []),
    ...(verifyingImagesStep && importingImagesStep && finalizingStep
      ? [verifyingImagesStep, importingImagesStep, finalizingStep]
      : []),
  ];
  // Badge de status do job só na última etapa de fato alcançada — evita
  // repetir a mesma informação de status em duas linhas quando a etapa de
  // confirmação já existe.
  const lastStep = steps[steps.length - 1];

  return (
    <div className="space-y-3 rounded-md border border-border bg-surface-muted p-3">
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span>
            {fullyDone
              ? "Importação processada"
              : imagesInFlight
                ? imageAttempt && imageAttempt > 1
                  ? `Importando imagens... (tentativa ${imageAttempt})`
                  : "Importando imagens..."
                : mode === "images-only"
                  ? "Iniciando importação de imagens..."
                  : "Processando importação..."}
          </span>
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
          const Icon = step.icon;
          const isLast = index === steps.length - 1;
          const toneClass =
            step.status !== "done"
              ? step.status === "active"
                ? "animate-pulse text-primary"
                : "text-muted-foreground"
              : step.tone === "success"
                ? "text-emerald-600"
                : step.tone === "warning"
                  ? "text-amber-600"
                  : "text-muted-foreground";

          return (
            <li key={step.key} className="relative flex gap-2.5 pb-4 last:pb-0">
              {!isLast && (
                <span aria-hidden="true" className="absolute left-[9px] top-[18px] bottom-0 w-px bg-border" />
              )}
              <span
                className={cn(
                  "relative z-10 flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-surface-muted",
                  step.status === "pending" && "opacity-40",
                )}
              >
                <Icon className={cn("h-3.5 w-3.5", toneClass)} aria-hidden="true" />
              </span>
              <div className="min-w-0 flex-1 space-y-0.5 pt-0.5">
                <span
                  className={cn(
                    "text-xs",
                    step.status === "active" || (step.status === "done" && step.tone !== "neutral")
                      ? "font-medium text-foreground"
                      : "text-muted-foreground",
                    step.status === "pending" && "opacity-40",
                  )}
                >
                  {step.label}
                  {step === lastStep && step.status === "done" && job && (
                    <Badge variant="outline" className="ml-1.5 align-middle">
                      {JOB_STATUS_LABEL[job.status] ?? job.status}
                    </Badge>
                  )}
                </span>
                {step.body && <div className="space-y-0.5 text-xs text-muted-foreground">{step.body}</div>}
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
