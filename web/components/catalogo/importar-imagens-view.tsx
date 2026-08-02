"use client";

import { useEffect, useRef, useState, useTransition, type KeyboardEvent } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, ChevronDown, ImageOff, ImagePlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import { ImportProgress } from "@/components/catalogo/importar-tcgdex-view";
import {
  abrirImportacaoImagens,
  executarImportacaoImagens,
  type IniciarImportacaoImagensResult,
  type ProgressoImportacaoImagens,
} from "@/app/catalogo/importar-cartas/tcgdex/actions";
import {
  fetchProgressoImportacaoImagens,
  MAX_IMAGE_IMPORT_RETRY_ATTEMPTS,
} from "@/lib/catalogo/asset-import-progress-client";
import type { CatalogoCardSetImagensRow } from "@/lib/catalogo/queries";
import { cn } from "@/lib/utils";

/**
 * Tela dedicada `/catalogo/importar-imagens` (2026-08-02) — substitui o stub
 * `ComingSoonPage` (ver `page.tsx`). Pedido explícito de Fabrício depois de
 * testar a continuação automática cartas→imagens numa Coleção grande
 * (SV4/Fenda Paradoxal, 266 cartas) e a Edge Function ter estourado o tempo
 * de execução no meio (Query 2092 v1.2, `05-modelo-de-dados.md` revisão
 * `1.33`): "Não consigo mais realizar uma nova tentativa de importação das
 * cartas, pois o set não é mais exibido no combobox... Para resolver,
 * precisamos criar a página dedicada a importação de imagens".
 *
 * Cópia deliberada do layout de `ImportarCartasView` (mesmo `PageHeader` com
 * ícone antes do título, mesmo `StatsRow` de dois indicadores, mesmo cartão
 * único com combobox + ação) — pedido explícito: "cópia da Importação de
 * Cartas em termos de layout, e com funcionalidades parecidas". Duas
 * diferenças de propósito, não de layout:
 * 1. O combobox lista `CatalogoCardSetImagensRow[]` (Card Sets com pelo
 *    menos uma Card cadastrada E pelo menos uma Card ainda sem imagem —
 *    `getCardSetsForImportacaoImagens`, `queries.ts`) em vez de Card Sets
 *    sem carta nenhuma — o universo é o oposto do de `Importar Cartas`.
 * 2. Sem Fonte (API/PDF) nem etapa de análise/Revisão — clicar "Importar
 *    Imagens" chama `iniciarImportacaoImagens` diretamente (mesma Server
 *    Action já usada pela continuação automática, só com um `initiatedBy`
 *    diferente — "manual_retry:importar-imagens" em vez de
 *    "catalog_import_job:<id>") e `ImportProgress` entra direto em
 *    `mode="images-only"` (ver comentário lá): sem "Abrindo job"/"Buscando
 *    cartas"/"Processando"/"Concluído"/"Gravando cartas", só as três etapas
 *    de imagem.
 */
export function ImportarImagensView({
  cardSets,
  colecoesPendentes,
  cartasSemImagem,
  selectedCardSet,
  languageCode,
}: {
  /** Card Sets com Cards cadastradas e pelo menos uma imagem pendente — filtro aplicado em `page.tsx` via `getCardSetsForImportacaoImagens`. */
  cardSets: CatalogoCardSetImagensRow[];
  colecoesPendentes: number;
  cartasSemImagem: number;
  selectedCardSet: CatalogoCardSetImagensRow | null;
  /** Idioma da tela inteira (2026-08-02, suporte EN + PT-BR) — resolvido em `page.tsx` a partir de `?idioma=`. */
  languageCode: string;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [imagePhase, setImagePhase] = useState<"idle" | "checking" | "importing" | "done">("idle");
  const [imageResult, setImageResult] = useState<IniciarImportacaoImagensResult | null>(null);
  // Progresso ao vivo (2026-08-02, mesmo pedido/mesma implementação de
  // `useAnalyzeJob` em `importar-tcgdex-view.tsx`): polling em
  // `asset_import_run` enquanto a Edge Function processa o lote.
  const [imageProgress, setImageProgress] = useState<ProgressoImportacaoImagens | null>(null);
  // Retry automático (2026-08-02, mesmo dia, rodada seguinte) — ver
  // comentário completo em `handleImportar` abaixo.
  const [imageAttempt, setImageAttempt] = useState(0);
  const started = isPending || imagePhase !== "idle";

  function navigate(cardSetId: string | null) {
    const params = new URLSearchParams();
    params.set("idioma", languageCode);
    if (cardSetId) params.set("cardSetId", cardSetId);
    router.push(`/catalogo/importar-imagens?${params.toString()}`);
  }

  // Troca de idioma (2026-08-02) — não preserva `?cardSetId=` de propósito:
  // a Coleção selecionada pertence à lista de pendências do idioma
  // anterior e pode nem existir na do novo.
  function navigateLanguage(nextLanguageCode: string) {
    router.push(`/catalogo/importar-imagens?idioma=${nextLanguageCode}`);
  }

  function handleImportar() {
    if (!selectedCardSet) return;
    const cardSetId = selectedCardSet.id;
    setImagePhase("checking");
    setImageResult(null);
    setImageProgress(null);
    setImageAttempt(0);

    startTransition(async () => {
      // Fluxo em duas fases (mesmo padrão de `useAnalyzeJob`):
      // `abrirImportacaoImagens` é rápida (só abre/reaproveita a run via
      // RPC) e devolve o `runCode` de imediato, permitindo iniciar o
      // polling em paralelo à chamada longa e bloqueante de
      // `executarImportacaoImagens`.
      const openResult = await abrirImportacaoImagens(cardSetId, "manual_retry:importar-imagens", languageCode);

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
        router.refresh();
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
        router.refresh();
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
        router.refresh();
        return;
      }

      setImagePhase("importing");
      // `runCodeRef` (era `const runCode`, 2026-08-02, mesmo dia, rodada
      // seguinte) — precisa ser mutável agora: o retry automático abaixo
      // pode trocar de run_code no meio do laço (ver comentário completo
      // logo abaixo), e o polling precisa acompanhar qual run está valendo
      // a cada momento.
      const runCodeRef = { current: openResult.runCode };
      const pollTimer = setInterval(() => {
        fetchProgressoImportacaoImagens(runCodeRef.current).then((progress) => {
          if (progress) setImageProgress(progress);
        });
      }, 2000);

      // Retry automático (2026-08-02, pedido explícito de Fabrício depois
      // de ver a importação de SV4 falhar de novo com HTTP 504 apesar do
      // progresso real de 115→169 imagens — mesmo raciocínio/implementação
      // de `useAnalyzeJob` em `importar-tcgdex-view.tsx`): o teto de
      // execução da plataforma para a Edge Function não muda, então repete
      // `executarImportacaoImagens` com o MESMO `runCode` até `imagesFailed`
      // chegar a 0 ou parar de progredir, com teto de segurança
      // `MAX_IMAGE_IMPORT_RETRY_ATTEMPTS`.
      //
      // `result.runExpired` (2026-08-02, mesmo dia, rodada seguinte) — bug
      // real corrigido (ME5): reusar o MESMO `runCode` só é seguro/correto
      // quando a run ficou presa em RUNNING (a plataforma matou a função no
      // meio, sem nunca terminar) — nesse caso a Edge Function localiza a
      // mesma run e retoma de onde parou. Mas se a run já chegou a um
      // status TERMINAL por um erro real de aplicação (não por timeout de
      // plataforma), a máquina de estados nunca permite reabri-la — insistir
      // no mesmo `runCode` sempre falha com "Execução encerrada não pode
      // mudar de status.", e pior, essa falha de transição SOBRESCREVIA o
      // motivo real da primeira falha no banco. A Edge Function (v2.9.2)
      // agora sinaliza esse caso via `runExpired`; quando verdadeiro, em vez
      // de repetir a mesma run morta, abre uma run NOVA
      // (`abrirImportacaoImagens` de novo — o Card Set continua com imagens
      // pendentes, então uma nova run é sempre criada) e continua o retry
      // com ela.
      let attempt = 0;
      let lastImported = -1;
      let result: IniciarImportacaoImagensResult;

      do {
        attempt += 1;
        setImageAttempt(attempt);
        result = await executarImportacaoImagens(cardSetId, runCodeRef.current, languageCode);

        if (result.runExpired && attempt < MAX_IMAGE_IMPORT_RETRY_ATTEMPTS) {
          const reopened = await abrirImportacaoImagens(cardSetId, "manual_retry:importar-imagens", languageCode);
          if (reopened.supported && reopened.runCode && !reopened.alreadyActive) {
            runCodeRef.current = reopened.runCode;
            continue;
          }
        }

        if (result.imagesImported === lastImported) break;
        lastImported = result.imagesImported;
      } while (result.supported && result.imagesFailed > 0 && attempt < MAX_IMAGE_IMPORT_RETRY_ATTEMPTS);

      clearInterval(pollTimer);
      setImageResult({ ...result, runCode: runCodeRef.current });
      setImagePhase("done");
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <ImagePlus className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Importar Imagens</PageTitle>
          </div>
          <PageDescription>Retomada da ingestão de imagens de cartas (card_asset) já cadastradas.</PageDescription>
        </PageHeading>
      </PageHeader>

      <StatsRow>
        <StatCard
          label="Coleções Pendentes"
          value={colecoesPendentes}
          caption="coleções com imagens faltando"
          icon={AlertTriangle}
          tone="danger"
        />
        <StatCard
          label="Sem Imagens"
          value={cartasSemImagem}
          caption="cartas sem imagens"
          icon={ImageOff}
          tone="danger"
        />
      </StatsRow>

      <Card>
        <CardContent className="space-y-4 pt-6">
          <div className="space-y-4">
            <div className="min-w-0 space-y-1">
              <label className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                Selecione a Coleção para importação de Imagens
              </label>
              <div className="flex items-center gap-2">
                <div className="min-w-0 flex-1">
                  <CardSetImagensCombobox
                    cardSets={cardSets}
                    selected={selectedCardSet}
                    onSelect={(id) => navigate(id)}
                  />
                </div>
                <LanguageToggle value={languageCode} onChange={navigateLanguage} />
                {selectedCardSet && (
                  <Button type="button" className="h-10 shrink-0" onClick={handleImportar} disabled={started}>
                    Importar Imagens
                  </Button>
                )}
              </div>
            </div>
          </div>

          <div className="space-y-4 border-t border-border pt-4">
            {!selectedCardSet ? (
              <p className="text-sm text-muted-foreground">Selecione uma Coleção acima para continuar.</p>
            ) : started ? (
              <ImportProgress
                mode="images-only"
                isPending={false}
                done={imagePhase === "done"}
                totalCards={selectedCardSet.cardsCatalogados}
                imagePhase={imagePhase}
                imageResult={imageResult}
                imageProgress={imageProgress}
                imageAttempt={imageAttempt}
              />
            ) : (
              <p className="text-sm text-muted-foreground">
                {selectedCardSet.imagesImportadas} de {selectedCardSet.cardsCatalogados} cartas já têm imagem —{" "}
                {selectedCardSet.imagesPendentes} pendente{selectedCardSet.imagesPendentes === 1 ? "" : "s"}. Clique em
                "Importar Imagens" para tentar novamente.
              </p>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

/**
 * Alternador de idioma da tela inteira (2026-08-02, suporte EN + PT-BR) —
 * mesmo padrão visual de `FonteToggle` (`importar-cartas-view.tsx`): grupo
 * segmentado, `inline-flex` (não `flex`, mesmo motivo já documentado lá —
 * encolhe para caber só o conteúdo, sem sobrar espaço vazio ao lado).
 * Posicionado entre o combobox e o botão "Importar Imagens" (pedido
 * explícito de Fabrício, mesma rodada) — antes vivia no `PageHeader`.
 *
 * Rótulo do botão é "PT" (era "PT-BR"), pedido explícito de Fabrício
 * ("Use PT pois é a forma como a API TCGDEX está configurada") — mas o
 * `code` continua `"pt-BR"`: é o valor real de `language.code` no banco
 * (confirmado: `en`/`pt-BR`, não existe `pt` cadastrado) e o que
 * `admin_start_asset_import_run()` espera em `p_language_code`. O "pt" da
 * TCGdex já é tratado à parte, só dentro da Edge Function
 * (`TCGDEX_LANGUAGE_BY_CODE`, `pt-BR` → `pt`) — só o RÓTULO exibido aqui
 * muda, nada no valor que trafega internamente.
 */
function LanguageToggle({ value, onChange }: { value: string; onChange: (languageCode: string) => void }) {
  const options: { code: string; label: string }[] = [
    { code: "en", label: "EN" },
    { code: "pt-BR", label: "PT" },
  ];

  return (
    <div
      className="inline-flex h-10 shrink-0 items-center gap-0.5 rounded-md border border-border bg-surface-muted p-0.5"
      role="group"
      aria-label="Idioma da importação de imagens"
    >
      {options.map((option) => (
        <button
          key={option.code}
          type="button"
          onClick={() => onChange(option.code)}
          aria-pressed={value === option.code}
          className={cn(
            "rounded-[5px] px-3 py-1.5 text-xs font-medium transition-colors",
            value === option.code
              ? "bg-surface text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground",
          )}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

/**
 * Combobox da Coleção — mesmo padrão visual de `CardSetCombobox`
 * (`importar-cartas-view.tsx`: painel próprio posicionado por `absolute`,
 * fechado ao clicar fora ou Esc, mesmo conteúdo rico no botão fechado e em
 * cada linha da lista aberta), não compartilhado diretamente porque a
 * segunda linha mostra progresso de imagens (`X/Y importadas`) em vez de
 * contagem de cartas a importar.
 */
function CardSetImagensCombobox({
  cardSets,
  selected,
  onSelect,
}: {
  cardSets: CatalogoCardSetImagensRow[];
  selected: CatalogoCardSetImagensRow | null;
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
          "flex w-full min-h-10 items-center justify-between gap-2 rounded-md border border-input bg-surface px-3 py-1.5 text-left shadow-subtle transition-colors",
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
              {selected.expansionCode} — {selected.expansionName} — {selected.imagesImportadas}/
              {selected.cardsCatalogados} imagens importadas
            </span>
          </span>
        ) : (
          <span className="flex-1 truncate text-sm text-muted-foreground">
            {disabled ? "Nenhuma Coleção com imagens pendentes no momento." : "Selecione uma Coleção..."}
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
                {cardSet.expansionCode} — {cardSet.expansionName} — {cardSet.imagesImportadas}/{cardSet.cardsCatalogados}{" "}
                imagens importadas
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
