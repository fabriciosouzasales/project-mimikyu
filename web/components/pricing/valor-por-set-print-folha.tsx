"use client";

import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
import { useValorPorSetPrint } from "@/components/pricing/valor-por-set-print-context";
import { cn } from "@/lib/utils";
import type { PricingReportSet } from "@/lib/pricing/queries";

const TITULO = "Valor por Set";
const SUBTITULO = "Valor estimado coberto e cobertura de preço das Cartas ativas de um Set.";

// Rótulo só para as duas EXCEÇÕES (item 3, refinamento de impressão
// 2026-08-23) — "Com preço" deixou de ter rótulo próprio na folha impressa
// porque é o caso normal (quase todas as linhas), redundante numa coluna
// dedicada. As exceções continuam claramente identificáveis, só que embu-
// tidas na própria linha (junto ao preço), não numa coluna à parte.
const EXCEPTION_STATUS_LABEL: Record<string, string> = {
  FX_UNAVAILABLE: "Câmbio indisponível",
  NO_PRICE: "Sem cotação",
};

// Mesmo mapa/função de `preco-por-carta-report.tsx` (`SOURCE_CODE_LABEL`/
// `humanizeSourceCode`) — duplicado deliberadamente, mesma decisão já
// registrada lá: "código técnico nunca chega à tela". Pedido explícito de
// Fabrício (2026-08-23): a coluna Variante da folha impressa mostrava o
// `pricing_source_code` cru em minúsculas (`justtcg`) — padronizar para o
// mesmo rótulo humanizado já usado em todo o resto do produto (`JustTCG`).
const SOURCE_CODE_LABEL: Record<string, string> = {
  JUSTTCG: "JustTCG",
};

function humanizeSourceCode(code: string): string {
  return SOURCE_CODE_LABEL[code] ?? code;
}

function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

function formatPercent(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value) + "%";
}

const dateFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

/**
 * Folha imprimível de "Valor por Set" — reescrita completa (2026-08-23,
 * pedido de Fabrício) para deixar de parecer uma captura paginada da UI e
 * virar um documento contínuo. Principais mudanças em relação à v1
 * (2026-08-22):
 *
 * 1. Conjunto COMPLETO do Set, não mais a página de 20 exibida na tela —
 *    consome `allItems` de `useValorPorSetPrint()` (`ValorPorSetPrintProvider`,
 *    acionado pelo `ValorPorSetPrintButton`). Nenhuma paginação/legenda
 *    "Mostrando X–Y de Z · página N/M" — a tabela flui em quantas páginas
 *    físicas o navegador precisar (`<thead>` já repete nativamente em toda
 *    página impressa, mesmo padrão documentado em
 *    `app/catalogo/relatorios/checklist/page.tsx`; `tr { break-inside:
 *    avoid }` global em `app/globals.css` evita linha cortada ao meio).
 * 2. Coluna "Status" dedicada removida — "Com preço" é redundante quando é
 *    quase toda a tabela; exceções (Câmbio indisponível/Sem cotação)
 *    aparecem discretamente junto ao preço da própria linha.
 * 3. "Variante · Fonte" (antes "Variante (FONTE)") — variante como
 *    informação principal, fonte como apoio discreto, sem caixa alta
 *    técnica.
 * 4. "Valor estimado coberto" ganha peso tipográfico maior que
 *    Cobertura/Sem cotação — é o número principal do documento.
 */
export function ValorPorSetPrintFolha({
  report,
  cardSet,
}: {
  report: PricingReportSet;
  cardSet: { code: string; name: string; expansionName: string | null; logoUrl: string | null } | null;
}) {
  const { status, allItems } = useValorPorSetPrint();
  const items = allItems ?? [];

  const cabecalho = (
    <RelatorioCabecalho
      titulo={TITULO}
      subtitulo={SUBTITULO}
      identificacaoColecao={cardSet ? `${cardSet.code} · ${cardSet.name}` : undefined}
      colecaoLogoUrl={cardSet?.logoUrl ?? null}
    />
  );

  // Bloco de resumo (identificação da Expansão/Condição/Moeda + Valor
  // estimado coberto + Cobertura/Sem cotação + alerta de valor parcial) —
  // conteúdo específico deste relatório, não o "cabeçalho padrão" dos
  // relatórios impressos. Aparece só UMA vez (primeira linha do `<tbody>`
  // quando há tabela, ver comentário abaixo), nunca repete por página.
  const resumo = (
    <div className="space-y-3 px-6 pb-3 pt-2 print:px-0">
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-b border-neutral-200 pb-2 text-[10px] text-neutral-500">
        <span>{cardSet?.expansionName ?? ""}</span>
        <span>
          Condição {report.condition.name} · Moeda {report.currency}
        </span>
      </div>

      <div className="grid grid-cols-3 gap-x-4 gap-y-2">
        <div>
          <p className="text-[10px] text-neutral-500">Valor estimado coberto</p>
          <p className="text-lg font-bold text-neutral-900">
            {formatMoney(report.estimatedValueCovered, report.currency)}
          </p>
        </div>
        <div>
          <p className="text-[10px] text-neutral-500">Cobertura</p>
          <p className="text-xs font-medium text-neutral-700">
            {formatPercent(report.coveragePct)} · {report.pricedConvertibleCount}/{report.totalActiveCards}
          </p>
        </div>
        <div>
          <p className="text-[10px] text-neutral-500">Sem cotação</p>
          <p className="text-xs font-medium text-neutral-700">{report.noPriceCount}</p>
        </div>
      </div>

      {report.isPartial && (
        <p className="border-l-2 border-neutral-400 bg-neutral-50 py-1 pl-2 text-[10px] text-neutral-600">
          Valor parcial — {report.noPriceCount} carta(s) ativa(s) deste Set não têm cotação confirmada nesta
          condição/moeda. O valor acima soma só as cartas com preço, nunca trata a ausência de cotação como zero.
        </p>
      )}
    </div>
  );

  return (
    <div className="hidden print:block">
      <RelatorioFolha>
        {status !== "ready" || items.length === 0 ? (
          <>
            {cabecalho}
            {resumo}
            <p className="px-6 pb-6 text-xs text-neutral-500 print:px-0">
              {status !== "ready"
                ? 'Carregando o Set completo para impressão — use o botão "Imprimir" no topo da página.'
                : "Nenhuma carta ativa neste Set."}
            </p>
          </>
        ) : (
          // Cabeçalho padrão (`RelatorioCabecalho`) repetindo em toda página
          // impressa (correção 2026-08-23 — decisão já documentada nos 5
          // relatórios do Catálogo Editorial, ver `app/catalogo/relatorios/
          // checklist/page.tsx` e `docs/05e-catalogo-editorial.md`, que este
          // relatório de Pricing ainda não seguia): vive dentro do `<thead>`,
          // num `<th colSpan>` acima da linha de colunas — mesmo mecanismo de
          // "Cobertura Geral". `<thead>` repete nativamente em toda página
          // impressa quando a tabela fragmenta em mais de uma folha, ao
          // contrário de um bloco solto acima da `<table>` (só aparecia na
          // primeira página, causa raiz do defeito reportado). O bloco de
          // resumo (`resumo`, acima) é conteúdo específico deste relatório,
          // não "cabeçalho padrão" — vive como a primeira linha do `<tbody>`,
          // então aparece só uma vez, na mesma posição visual de antes.
          <DataTable className="text-[10px]">
            <DataTableHead>
              <tr>
                <th colSpan={5} className="p-0 text-left font-normal">
                  {cabecalho}
                </th>
              </tr>
              <DataTableHeadRow className="border-neutral-200 text-[9px] text-neutral-500">
                <DataTableHeadCell className="bg-neutral-50 py-1 pl-6 print:pl-0">Carta</DataTableHeadCell>
                <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                  Variante
                </DataTableHeadCell>
                <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                  Preço
                </DataTableHeadCell>
                <DataTableHeadCell align="center" className="bg-neutral-50 py-1">
                  Últ. Atualização
                </DataTableHeadCell>
                <DataTableHeadCell
                  align="center"
                  className="bg-neutral-50 py-1 pr-6 last:pr-6 print:pr-0 print:last:pr-0"
                >
                  Participação
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              <tr>
                <td colSpan={5} className="p-0">
                  {resumo}
                </td>
              </tr>
              {items.map((item, index) => {
                const exceptionLabel = EXCEPTION_STATUS_LABEL[item.status];
                return (
                  <DataTableRow
                    key={item.cardId}
                    className={cn("border-neutral-100", index % 2 === 1 && "bg-[#F7F5ED]")}
                  >
                    <DataTableCell className="py-1 pl-6 text-neutral-900 print:pl-0">
                      {item.cardName}{" "}
                      <span className="tabular-nums text-neutral-500">
                        ({item.collectorNumber}
                        {item.collectorTotal ? `/${item.collectorTotal}` : ""})
                      </span>
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-neutral-700">
                      {item.printingLabel ?? "—"}
                      {item.pricingSourceCode ? ` · ${humanizeSourceCode(item.pricingSourceCode)}` : ""}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1">
                      <span className="font-medium text-neutral-900">
                        {item.priceDisplay !== null ? formatMoney(item.priceDisplay, item.currency) : "—"}
                      </span>
                      {exceptionLabel && (
                        <span className="ml-1 uppercase tracking-wide text-neutral-500">{exceptionLabel}</span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 tabular-nums text-neutral-500">
                      {item.observedAt ? dateFormatter.format(new Date(item.observedAt)) : "—"}
                    </DataTableCell>
                    <DataTableCell
                      align="center"
                      className="py-1 pr-6 tabular-nums text-neutral-500 last:pr-6 print:pr-0 print:last:pr-0"
                    >
                      {item.participationPct !== null ? formatPercent(item.participationPct) : "—"}
                    </DataTableCell>
                  </DataTableRow>
                );
              })}
            </tbody>
          </DataTable>
        )}

        <RelatorioRodape />
      </RelatorioFolha>
    </div>
  );
}
