"use client";

import { type KeyboardEvent, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, CheckCircle2, ChevronDown, FileUp, ImageOff } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import { MatchResultPanel, useAnalyzeJob, ImportProgress } from "@/components/catalogo/importar-tcgdex-view";
import { RevisaoImportacaoTable } from "@/components/catalogo/revisao-importacao-table";
import type { CatalogoCardSetRow } from "@/lib/catalogo/queries";
import type { TcgdexAutoMatchResult } from "@/lib/catalogo/tcgdex-lookup";
import { cn, formatNumber } from "@/lib/utils";

/**
 * Redesenho visual completo em 2026-08-01 (pedido de Fabrício, dois
 * protótipos anexados — visão API e visão PDF): substitui o par "dois
 * cartões de opção" (um deles um beco sem saída, `href` ausente) por uma
 * única tela de trabalho — indicadores de pendência no topo, depois um
 * cartão de controle único com Coleção + Fonte + a ação disponível para a
 * combinação escolhida. Absorve o que antes era `ImportarTcgdexView`
 * (`/catalogo/importar-cartas/tcgdex`, agora um redirect para cá — ver
 * `tcgdex/page.tsx`): a etapa "selecionar fonte TCGdex" deixou de ser uma
 * navegação própria, é a mesma tela.
 *
 * Rodada de ajuste (mesmo dia, feedback direto sobre o resultado da
 * primeira versão):
 * 1. Seletor de Coleção volta a listar só as sem nenhuma carta (uma
 *    tentativa nesta mesma rodada tinha ampliado para todas — revertida,
 *    ver `page.tsx`), e passa a ser um combobox próprio (`CardSetCombobox`)
 *    em vez de `<select>` nativo — o pedido era mostrar Coleção, Expansão e
 *    quantidade de cartas a importar exatamente como no protótipo, e nenhum
 *    `<select>` nativo renderiza conteúdo rico de duas linhas dentro da
 *    caixa fechada.
 * 2. Corrigido o desalinhamento entre a coluna Coleção e a coluna Fonte:
 *    a linha de controle usava `items-end` (alinhamento pelo rodapé), então
 *    a legenda extra abaixo do seletor empurrava o toggle de Fonte para uma
 *    posição inconsistente com o próprio rótulo "Selecione a Fonte" acima
 *    dele. `items-start` (os dois rótulos na mesma linha, como no
 *    protótipo) resolve — reforçado por mover a informação rica para
 *    dentro do próprio combobox, então a coluna da Coleção não varia mais
 *    de altura por causa de uma legenda solta abaixo.
 * 3. Ícone antes do título — mesmo padrão de Expansões/Jogos/Cartas
 *    (`Layers`/ícone do menu antes de `PageTitle`, dentro de `PageHeading`),
 *    que esta tela não tinha ainda.
 *
 * A frente PDF continua sem lógica de importação real nesta rodada (pedido
 * explícito: "só vamos ajustar a experiência visual") — o upload é
 * funcional só para escolher/soltar um arquivo local; o badge "Em
 * construção" ao lado do botão Anexar deixa isso explícito, mesmo padrão já
 * usado no cartão PDF anterior.
 *
 * Terceira rodada (mesmo dia, exemplo concreto usando SV2/SV1/SVE):
 * 1. Segunda linha do combobox trocou de Jogo (`gameCode`/`gameName`) para
 *    Expansão (`expansionCode`/`expansionName`, novo campo em
 *    `CatalogoCardSetRow` — ver `queries.ts`) — pedido explícito era "SV -
 *    Escarlate e Violeta - 279 cartas encontradas para importação" para o
 *    exemplo de SV2. `expansionCode` bate exatamente ("SV"); `expansionName`
 *    no banco é "Scarlet & Violet" (inglês), não "Escarlate e Violeta" —
 *    mantido fiel ao dado real (mesmo nome já mostrado em Expansões/Jogos)
 *    em vez de inventar uma tradução, sinalizado a Fabrício para confirmar.
 *    Texto da contagem também mudou para "cartas encontradas para
 *    importação" (era "cartas para importação").
 * 2. `min-h-[52px]` fixo no botão do combobox (era altura variável por
 *    conteúdo) — o estado placeholder (1 linha) e o estado selecionado (2
 *    linhas) agora ocupam a mesma altura, então escolher uma Coleção não
 *    empurra mais o toggle de Fonte ao lado. Linhas da lista aberta com
 *    `py-1.5` (era `py-2`) e fonte da legenda reduzida para 11px
 *    (`text-[11px]`, era `text-xs`/12px) — menos espaço por opção.
 *
 * Quarta rodada (mesmo dia, "continuamos com muitos problemas"):
 * 1. Bug real no `FonteToggle` (ver componente abaixo): `flex` sozinho é
 *    bloco cheio, não encolhe pro conteúdo — corrigido pra `inline-flex`.
 * 2. Combobox ainda mais compacto: `min-h-[52px]` → `min-h-10`, padding e
 *    fonte reduzidos de novo (ver `CardSetCombobox`).
 * 3-4. Bug real em `autoMatchTcgdexSet` (tcgdex-lookup.ts) — corrigido lá,
 *    não neste arquivo.
 * 5. `JobStatusView`/`RevisaoImportacaoTable` passaram a ser embutidos
 *    aqui via `?jobId=` — revertido na quinta rodada, ver abaixo.
 *
 * Quinta rodada (mesmo dia, protótipo anexado da tela com progresso já
 * concluído + Revisão visível):
 * 1. Linha de seleção virou grid de 2 colunas (`sm:grid-cols-2`, era
 *    `flex`/`flex-1`+`shrink-0`) — Coleção ocupa exatamente metade do
 *    card, não "o que sobra" depois da coluna Fonte. Rótulos viraram
 *    caixa-alta pequena (`text-[11px] uppercase tracking-wide`, era
 *    `text-sm`) e o toggle de Fonte ganhou `h-10` explícito pra bater
 *    exatamente com a altura do combobox ao lado (`min-h-10`) — antes as
 *    alturas eram próximas mas não iguais, dava pra perceber o
 *    desalinhamento.
 * 2-3. O botão Analisar saiu de dentro do painel de resultado e passou a
 *    viver ao lado do toggle de Fonte, neste cabeçalho — só quando
 *    `matchResult.status === "MATCHED"` (o caso comum agora, depois da
 *    correção de matching da rodada anterior). Isso, mais a mudança de
 *    `iniciarImportacaoTcgdex` pra não navegar mais (ver
 *    `importar-tcgdex-view.tsx`/`tcgdex/actions.ts`), é o que permite o
 *    progresso + a tabela de Revisão aparecerem *na mesma tela*, sem
 *    redirect: `useAnalyzeJob()` (hook compartilhado, definido em
 *    `importar-tcgdex-view.tsx`) é chamado aqui mesmo, e tanto o botão
 *    quanto o painel abaixo (progresso → status do job → Revisão) leem o
 *    mesmo estado. Casos raros (AMBIGUOUS/NOT_FOUND) continuam usando
 *    `MatchResultPanel`, autocontido, sem o botão no cabeçalho.
 *
 * Sexta rodada (mesmo dia, "já que não conseguimos alinhar os dois
 * componentes"):
 * 1. Linha de seleção voltou a empilhar (Fonte abaixo de Coleção, era
 *    `grid sm:grid-cols-2` lado a lado) — o alinhamento entre combobox e
 *    toggle continuava incomodando mesmo depois do ajuste de altura da
 *    rodada anterior; empilhar remove o problema por completo em vez de
 *    tentar mais um ajuste fino de altura/padding.
 * 2-3. `ImportProgress` (importar-tcgdex-view.tsx) ganhou uma linha vertical
 *    conectando os ícones das etapas (mais espaço entre elas) e passou a
 *    tratar "Concluído" como a 4ª etapa fixa da lista, com o resultado do
 *    job (Set + contagens + status + erro) embutido ali dentro — ver
 *    comentário completo em `ImportProgress`.
 * 4. O card "Importação" (`JobStatusView`) foi removido de aqui e de
 *    `CandidateAnalyzeCard` — seu conteúdo virou parte do "Concluído" do
 *    item 2-3 acima, então o card separado ficou redundante.
 *
 * Sétima rodada (mesmo dia, bug real reportado por Fabrício: "não consigo
 * retomar a importação de SV1 e SV2"): o seletor de Coleção (`page.tsx`)
 * listava só Coleções com `cardsCatalogados === 0` — qualquer Coleção
 * parcialmente importada (SV1, com 6 linhas que falharam na confirmação
 * antes da emenda de raridade `HYPER_RARE`; SV2, com 9 linhas que nunca
 * passaram de `NEEDS_REVIEW`/`INVALID`) ficava invisível, sem jeito de
 * retomar. Critério ampliado em `page.tsx` para também considerar o job de
 * importação mais recente incompleto (`getLatestImportJobIncompleteFlags`
 * em `queries.ts` — comparar contra `card_set.total_set_size` foi a
 * primeira tentativa e foi descartada, esse campo nem sempre reflete a
 * contagem real da TCGdex). A legenda do combobox agora reflete os dois
 * estados: "N cartas encontradas para importação" (nunca importada) vs.
 * "X/N cartas catalogadas" (parcial, X já cadastradas) — ver
 * `CardSetCombobox` abaixo.
 *
 * Oitava rodada (2026-08-08, pedido de Fabrício após o encerramento
 * definitivo do canal PDF — Ciclos 3/4 de `ADR-024`, ver emenda no ADR):
 * 1. Seletor de Fonte (`FonteToggle`, API/PDF) removido por completo — só
 *    restava uma fonte real (TCGdex/API), então o toggle não representava
 *    mais uma escolha genuína. `PdfUploadPanel` (visual, nunca teve parsing
 *    real por trás) também foi removido junto, mesmo motivo.
 * 2. `CardSetCombobox` ganhou `max-w-[500px]` — Fabrício: "o combobox não
 *    precisa ter essa largura toda", pedido explicitamente como valor a
 *    testar, não necessariamente final.
 * 3. O botão Analisar deixou de ser condicionalmente renderizado (antes só
 *    aparecia com `fonte === "api" && selectedCardSet && matchResult?.status
 *    === "MATCHED"`) e passou a ficar sempre visível — pedido de Fabrício:
 *    "o botão de Importar cartas... deve ser visível permanentemente". A
 *    condição antiga virou só o `disabled` (via `canAnalyzeHere`); os
 *    inputs ocultos do form usam fallback vazio quando ainda não há Coleção/
 *    match, inofensivo porque o botão fica desabilitado nesse caso.
 *
 * Nona rodada (mesmo dia, "esses componentes precisam ter essa altura toda?
 * Visualmente desagradável"): `CardSetCombobox` reduzido de `min-h-10`/
 * `py-1.5` para `min-h-9`/`py-1` (alinha com a altura padrão de controles do
 * resto do app — `h-9` é o tamanho `default` de `Button`/`Input`, ver
 * `button.tsx`/`input.tsx` — `h-10` aqui era uma exceção isolada destas duas
 * telas). Botão Analisar perdeu o `h-10` explícito, volta a usar o `h-9`
 * padrão do próprio `Button`.
 */
export function ImportarCartasView({
  cardSets,
  colecoesSemCartas,
  cardsSemImagem,
  selectedCardSet,
  matchResult,
}: {
  /** Coleções ainda pendentes — sem nenhuma carta, ou com o job de importação mais recente incompleto — filtro aplicado em `page.tsx` (ver `getLatestImportJobIncompleteFlags` em `queries.ts`). */
  cardSets: CatalogoCardSetRow[];
  colecoesSemCartas: number;
  cardsSemImagem: number;
  selectedCardSet: CatalogoCardSetRow | null;
  matchResult: TcgdexAutoMatchResult | null;
}) {
  const router = useRouter();
  // `selectedCardSet?.id ?? ""` — cardSetId "" antes de qualquer Coleção
  // escolhida; inofensivo porque o useEffect de continuação automática (ver
  // useAnalyzeJob) só dispara depois que um job chega a status final, e sem
  // Coleção selecionada não há como ter iniciado análise/job nenhum.
  const analyzeJob = useAnalyzeJob(selectedCardSet?.id ?? "");

  function navigate(next: { cardSetId?: string | null }) {
    const params = new URLSearchParams();
    const cardSetId = next.cardSetId !== undefined ? next.cardSetId : selectedCardSet?.id;
    if (cardSetId) params.set("cardSetId", cardSetId);
    const query = params.toString();
    router.push(query ? `/catalogo/importar-cartas?${query}` : "/catalogo/importar-cartas");
  }

  const canAnalyzeHere = !!selectedCardSet && matchResult?.status === "MATCHED" && !analyzeJob.started;

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <FileUp className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Importar Cartas</PageTitle>
          </div>
          <PageDescription>Cadastro e atualização de Cards em lote no catálogo editorial.</PageDescription>
        </PageHeading>
      </PageHeader>

      <StatsRow>
        <StatCard
          label="Sem Cartas"
          value={formatNumber(colecoesSemCartas)}
          caption="coleções sem cartas"
          icon={AlertTriangle}
          tone="danger"
        />
        <StatCard
          label="Sem Imagens"
          value={formatNumber(cardsSemImagem)}
          caption="cartas sem imagens"
          icon={ImageOff}
          tone="danger"
        />
      </StatsRow>

      <Card>
        <CardContent className="space-y-4 pt-6">
          <div className="space-y-4">
            <div className="min-w-0 max-w-[500px] space-y-1">
              <label className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                Selecione a Coleção para cadastro de Cartas
              </label>
              <CardSetCombobox
                cardSets={cardSets}
                selected={selectedCardSet}
                onSelect={(id) => navigate({ cardSetId: id })}
              />
            </div>

            <form action={analyzeJob.formAction}>
              <input type="hidden" name="card_set_id" value={selectedCardSet?.id ?? ""} />
              <input
                type="hidden"
                name="external_set_id"
                value={matchResult?.status === "MATCHED" ? matchResult.set.id : ""}
              />
              <Button type="submit" disabled={!canAnalyzeHere}>
                Analisar
              </Button>
            </form>
          </div>

          <div className="space-y-4 border-t border-border pt-4">
            {!selectedCardSet ? (
              <p className="text-sm text-muted-foreground">Selecione uma Coleção acima para continuar.</p>
            ) : !matchResult ? null : matchResult.status === "MATCHED" ? (
              <>
                <div className="flex items-center gap-3 rounded-md border border-input bg-[#F7F5ED] p-3">
                  <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" aria-hidden="true" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-foreground">Set localizado: {matchResult.set.name}</p>
                    <p className="text-xs text-muted-foreground">
                      {formatNumber(matchResult.set.cardCountTotal)} cartas na TCGdex
                    </p>
                  </div>
                </div>
                {analyzeJob.error && <p className="text-sm text-destructive">{analyzeJob.error}</p>}
                {analyzeJob.started && (
                  <ImportProgress
                    isPending={analyzeJob.isPending || analyzeJob.fetchingJob}
                    done={Boolean(analyzeJob.jobState.job)}
                    resultSummary={{ label: matchResult.set.name, cardCount: matchResult.set.cardCountTotal }}
                    job={analyzeJob.jobState.job}
                    imagePhase={analyzeJob.imagePhase}
                    imageLanguage={analyzeJob.imageLanguage}
                    imageResults={analyzeJob.imageResults}
                    imageProgress={analyzeJob.imageProgress}
                    imageAttempt={analyzeJob.imageAttempt}
                  />
                )}
              </>
            ) : (
              <MatchResultPanel cardSet={selectedCardSet} matchResult={matchResult} />
            )}
          </div>
        </CardContent>
      </Card>

      {analyzeJob.jobState.job &&
        (analyzeJob.jobState.job.status === "STAGED" || analyzeJob.jobState.job.status === "CONFIRMING") && (
          <RevisaoImportacaoTable
            jobId={analyzeJob.jobState.job.id}
            rows={analyzeJob.jobState.rows}
            onRefresh={analyzeJob.refreshJob}
          />
        )}
    </div>
  );
}

/**
 * Combobox próprio da Coleção — substitui o `<select>` nativo (2026-08-01,
 * mesmo dia, pedido direto de Fabrício: "a seleção deve trazer as
 * informações exatamente como no protótipo. Informações da Coleção,
 * Expansão e quantidade de cartas a serem importadas"). Sem primitive de
 * Popover no projeto ainda (só `@radix-ui/react-dialog`/`-tooltip`/
 * `-collapsible`) — painel próprio, posicionado por `absolute`, fechado ao
 * clicar fora ou apertar Esc. Mesmo conteúdo rico (nome em negrito + legenda
 * Jogo/quantidade) no botão fechado E em cada linha da lista aberta.
 */
function CardSetCombobox({
  cardSets,
  selected,
  onSelect,
}: {
  cardSets: CatalogoCardSetRow[];
  selected: CatalogoCardSetRow | null;
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
          // `min-h-10` (2026-08-01, segunda rodada — era `min-h-[52px]`:
          // Fabrício reportou o box ainda "grosseiro"; 40px é o suficiente
          // pra caber as duas linhas com o padding/fonte reduzidos abaixo
          // sem deixar o box maior do que precisa) — altura fixa continua
          // existindo (placeholder de 1 linha não pode ficar mais baixo que
          // o estado selecionado de 2 linhas), só o valor mudou.
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
              {selected.expansionCode} — {selected.expansionName} —{" "}
              {selected.cardsCatalogados > 0
                ? `${formatNumber(selected.cardsCatalogados)}/${formatNumber(selected.totalSetSize)} cartas catalogadas`
                : `${formatNumber(selected.totalSetSize)} cartas encontradas para importação`}
            </span>
          </span>
        ) : (
          <span className="flex-1 truncate text-sm text-muted-foreground">
            {disabled ? "Nenhuma Coleção sem cartas no momento." : "Selecione uma Coleção..."}
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
          // `p-1` + linhas com `py-1` (reduzido de `py-1.5`, 2026-08-01,
          // segunda rodada — Fabrício: "a lista suspensa eh muito
          // grosseira") — sem `space-y`/`gap` entre botões, cada linha já é
          // um bloco cheio, então o único espaçamento perceptível é o
          // padding vertical de cada uma.
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
                {cardSet.expansionCode} — {cardSet.expansionName} —{" "}
                {cardSet.cardsCatalogados > 0
                  ? `${formatNumber(cardSet.cardsCatalogados)}/${formatNumber(cardSet.totalSetSize)} cartas catalogadas`
                  : `${formatNumber(cardSet.totalSetSize)} cartas encontradas para importação`}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// `FonteToggle` e `PdfUploadPanel` (canal API/PDF) foram removidos em
// 2026-08-08 — o canal PDF (Ciclos 3/4 de `ADR-024`) foi encerrado
// definitivamente por decisão de Fabrício (ver emenda 2026-08-08 no ADR), e
// o toggle não representava mais uma escolha real com uma única fonte
// (TCGdex/API) restante.
