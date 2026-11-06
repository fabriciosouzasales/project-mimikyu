import Link from "next/link";
import type * as React from "react";
import { AlertCircle, ArrowLeft, ClipboardCheck } from "lucide-react";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { ChecklistCaixaVazia, ChecklistLinhaBase, RelatorioChecklistFolhas } from "@/components/catalogo/relatorio-checklist-tabela";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { collectionHref, type PositionFilter } from "@/lib/colecoes/colecoes";
import type { ChecklistReportCollection } from "@/lib/reports/checklist-queries";
import {
  type ChecklistKind,
  type ChecklistLoad,
  type ChecklistRow,
  checklistFilterShortLabel,
  checklistFinishCode,
  checklistFinishLegend,
  checklistSummaryLine,
  checklistHref,
  checklistKindLabel,
} from "@/lib/reports/collection-checklist";
import { PrintFooter } from "./print-footer";
import { ReportPrintButton } from "./report-print-button";
import styles from "./report.module.css";

export const CHECKLIST_TITLE = "Checklist de completude";
const TITLE = CHECKLIST_TITLE;
const FILTERS: { value: PositionFilter; label: string }[] = [
  { value: "todas", label: "Todas" },
  { value: "tenho", label: "Possuídas" },
  { value: "faltam", label: "Faltam" },
];

const count = new Intl.NumberFormat("pt-BR");

/** "ME4 · Caos Ascendente" (Set) ou o nome da coleção. */
export function checklistIdentity(collection: ChecklistReportCollection): string {
  return collection.cardSetCode ? `${collection.cardSetCode} · ${collection.cardSetName ?? collection.name}` : collection.name;
}

/** Motivo de "Imprimir" indisponível (D7.8); `null` = conjunto completo, pronto. */
export function checklistPrintReason(load: ChecklistLoad): string | null {
  if (load.status === "error") return "Não foi possível preparar o checklist agora.";
  if (load.complete) return null;
  return load.incompleteReason === "too_large"
    ? "Este checklist é grande demais para ser preparado de uma vez."
    : "Parte do checklist não carregou — tente novamente.";
}

/**
 * Como o filtro troca: por URL (rota de acesso direto, sem JS) ou por estado (sobreposição sobre
 * a coleção — sem navegar, sem perder a página de origem).
 */
export type ChecklistFilterControl =
  | { kind: "link" }
  | { kind: "state"; onChange: (filter: PositionFilter) => void; onRetry: () => void; pending: PositionFilter | null };

/**
 * Acesso direto (rota auxiliar) — barra com volta à coleção e "Imprimir", título e o corpo comum.
 * O fluxo principal é a sobreposição (`CollectionReportOverlay`), que usa o MESMO corpo.
 */
export function CollectionChecklistReport({
  collection,
  kind,
  filter,
  load,
  logoUrl,
  issuedAt,
}: {
  collection: ChecklistReportCollection;
  kind: ChecklistKind;
  filter: PositionFilter;
  load: ChecklistLoad;
  logoUrl: string | null;
  issuedAt: string;
}) {
  const ready = load.status === "ready" && load.complete;
  return (
    <div className={styles.root} data-print-footer-scope="">
      <PrintFooter />
      <div className="print:hidden">
        <div className={styles.topBar}>
          <Link href={collectionHref(collection.id)} className={styles.backLink}>
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            <span className={styles.backText}>{collection.name}</span>
          </Link>
          <div className={styles.topActions}>
            <ReportPrintButton ready={ready} reason={checklistPrintReason(load)} />
          </div>
        </div>
        <header className={styles.head}>
          <p className={styles.eyebrow}>
            <ClipboardCheck className="h-3.5 w-3.5" aria-hidden="true" />
            Relatório da coleção
          </p>
          <h1 className={styles.title}>{TITLE}</h1>
          <p className={styles.lede}>
            {checklistIdentity(collection)} · {checklistKindLabel(kind)}
          </p>
        </header>
      </div>
      <ChecklistReportBody
        collection={collection}
        kind={kind}
        filter={filter}
        load={load}
        logoUrl={logoUrl}
        issuedAt={issuedAt}
        control={{ kind: "link" }}
      />
    </div>
  );
}

/**
 * Checklist de completude (V1-14 R1-A) — corpo comum, no PADRÃO ÚNICO dos relatórios do sistema
 * (o mesmo da "Lista de Verificação de Cartas" da Central de Relatórios do Catálogo Editorial):
 * a folha A4 branca é a própria visualização — o que se vê na tela é o que sai na impressão.
 *
 * - Acima da folha (só na tela): filtro Todas/Possuídas/Faltam e avisos de estado.
 * - Folha: `RelatorioFolha` + `RelatorioChecklistTabela` (2–4 colunas, 46 linhas por coluna,
 *   ordem coluna-major, `RelatorioCabecalho` repetido em toda folha via `<thead>`) + legenda no
 *   pé + `RelatorioRodape` — exatamente os componentes do Catálogo.
 * - Linha: `ChecklistLinhaBase` (caixa | número | nome | marcador final); a caixa mostra a posse
 *   (✓ na coleção · vazia falta · ponto = falta, mas há exemplar livre no Acervo) e, no Master
 *   Set, o marcador final é a sigla do acabamento.
 * - Conjunto incompleto → a folha mostra só o aviso, nunca uma lista parcial como integral (D7.8).
 */
export function ChecklistReportBody({
  collection,
  kind,
  filter,
  load,
  logoUrl,
  issuedAt,
  control,
}: {
  collection: ChecklistReportCollection;
  kind: ChecklistKind;
  filter: PositionFilter;
  load: ChecklistLoad;
  logoUrl: string | null;
  issuedAt: string;
  control: ChecklistFilterControl;
}) {
  const identity = checklistIdentity(collection);
  const ready = load.status === "ready" && load.complete;
  const printReason = checklistPrintReason(load);
  const subtitle = `${checklistSummaryLine(collection.totalPositions, collection.satisfiedPositions)} · ${checklistFilterShortLabel(filter)} · Emitido em ${issuedAt}`;
  const cabecalho = (
    <RelatorioCabecalho titulo={TITLE} subtitulo={subtitle} identificacaoColecao={identity} colecaoLogoUrl={logoUrl} />
  );

  return (
    <>
      {/* ---------------- controles (só tela) ---------------- */}
      <div className="print:hidden" aria-busy={control.kind === "state" && control.pending !== null ? true : undefined}>
        <nav className={styles.filters} aria-label="Filtrar o checklist">
          {FILTERS.map((option) =>
            control.kind === "link" ? (
              <Link
                key={option.value}
                href={checklistHref(collection.id, option.value)}
                className={styles.filter}
                aria-current={filter === option.value ? "page" : undefined}
                scroll={false}
              >
                {option.label}
              </Link>
            ) : (
              <button
                key={option.value}
                type="button"
                className={styles.filter}
                aria-pressed={filter === option.value}
                data-pending={control.pending === option.value || undefined}
                onClick={() => control.onChange(option.value)}
              >
                {option.label}
              </button>
            ),
          )}
        </nav>
        {load.status === "error" ? (
          <div className={styles.state} role="alert">
            <AlertCircle className="h-6 w-6" aria-hidden="true" />
            <h2>Não foi possível preparar o checklist</h2>
            <p>Nada foi alterado na sua coleção. Tente novamente em instantes.</p>
            {control.kind === "link" ? (
              <Link href={checklistHref(collection.id, filter)} className={styles.stateAction}>
                Tentar novamente
              </Link>
            ) : (
              <button type="button" className={styles.stateAction} onClick={control.onRetry}>
                Tentar novamente
              </button>
            )}
          </div>
        ) : !load.complete ? (
          <p className={styles.notice} role="status">
            <AlertCircle className="h-4 w-4" aria-hidden="true" />
            {load.incompleteReason === "too_large"
              ? `Este checklist tem ${count.format(load.total)} posições — acima do limite desta versão. A impressão fica indisponível para não sair incompleta.`
              : `Carregamos ${count.format(load.rows.length)} de ${count.format(load.total)} posições. A impressão fica indisponível até o conjunto completo carregar.`}
          </p>
        ) : null}
      </div>

      {/* ---------------- folha (tela = impressão) ---------------- */}
      {load.status === "error" ? null : (
        <div className={styles.results} data-stale={control.kind === "state" && control.pending !== null ? true : undefined}>
          {ready && load.status === "ready" ? (
            <ChecklistSheet rows={load.rows} kind={kind} filter={filter} cabecalho={cabecalho} />
          ) : (
            <RelatorioFolha>
              {cabecalho}
              <div className="px-6 py-10 text-center print:px-0">
                <p className="text-sm font-semibold text-neutral-900">Este checklist não foi impresso porque não está completo.</p>
                <p className="mt-2 text-xs text-neutral-600">
                  {printReason ?? "O conjunto solicitado não pôde ser preparado."} Para não apresentar uma lista parcial como se fosse
                  integral, a folha mostra apenas este aviso.
                </p>
              </div>
              <RelatorioRodape />
            </RelatorioFolha>
          )}
        </div>
      )}
    </>
  );
}

/** Caixa de posse: ✓ na coleção · vazia = falta · ponto = falta, mas há exemplar livre no Acervo. */
function StateBox({ state }: { state: "owned" | "missing" | "acervo" }) {
  if (state === "missing") return <ChecklistCaixaVazia />;
  return (
    <span
      aria-hidden="true"
      className={`inline-flex h-3 w-3 shrink-0 items-center justify-center border border-neutral-900 text-[8px] leading-none ${state === "owned" ? "bg-neutral-900 text-white" : ""}`}
    >
      {state === "owned" ? "✓" : <span className="h-1 w-1 rounded-full bg-neutral-900" />}
    </span>
  );
}

function ChecklistSheet({
  rows,
  kind,
  filter,
  cabecalho,
}: {
  rows: ChecklistRow[];
  kind: ChecklistKind;
  filter: PositionFilter;
  cabecalho: React.ReactNode;
}) {
  const master = kind === "MASTER_SET";
  const hasAcervo = rows.some((row) => !row.owned && row.inAcervo);
  const finishLegend = master ? checklistFinishLegend(rows.map((row) => row.finish)) : [];
  // Legenda repetida em TODA folha, logo após as linhas.
  const legenda = (
    <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-neutral-200 py-3 text-[9px] text-neutral-500">
      <span className="inline-flex items-center gap-1">
        <StateBox state="owned" /> Na coleção
      </span>
      <span className="inline-flex items-center gap-1">
        <StateBox state="missing" /> Falta
      </span>
      {hasAcervo ? (
        <span className="inline-flex items-center gap-1">
          <StateBox state="acervo" /> Falta · livre no Acervo
        </span>
      ) : null}
      {finishLegend.map((entry) => (
        <span key={entry.code}>
          <span className="font-semibold text-neutral-700">{entry.code}</span> {entry.label}
        </span>
      ))}
    </div>
  );
  if (rows.length === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center text-sm text-neutral-600 print:px-0">
          {filter === "faltam"
            ? "Nada faltando: todas as posições do objetivo estão na coleção."
            : filter === "tenho"
              ? "Nenhuma posição preenchida ainda."
              : "O objetivo da coleção ainda não tem posições."}
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }
  return (
    <RelatorioChecklistFolhas
      itens={rows}
      cabecalho={cabecalho}
      legenda={legenda}
      renderLinha={(row, index) => {
        const finish = master ? checklistFinishCode(row.finish) : null;
        return (
          <ChecklistLinhaBase
            index={index}
            caixa={<StateBox state={row.owned ? "owned" : row.inAcervo ? "acervo" : "missing"} />}
            numero={row.number}
            nome={row.name}
            final={
              master && row.finish ? (
                <span
                  className={`shrink-0 text-right text-neutral-600 ${finish ? "text-[8px] font-semibold tracking-wide" : "max-w-[40%] truncate text-[7.5px]"}`}
                  title={finish?.label ?? row.finish}
                >
                  {finish?.code ?? row.finish}
                </span>
              ) : null
            }
          />
        );
      }}
    />
  );
}
