import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { formatCount, plural, shareText } from "@/lib/reports/acervo-reports";
import { type CollectionDistributionReport, collectionDistributionSummaryLine } from "@/lib/reports/collection-distribution";
import { libraryReport } from "@/lib/reports/library-reports";

/**
 * V1-14 R1-B — folha "Distribuição do Acervo por coleção" (Minhas coleções; antes "Inventário geral
 * e por coleção" no Meu acervo — realocada sem mudar regras, layout nem impressão). Mesma folha institucional
 * da R1-A (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`; tela = impressão).
 * Só o que é inventário: exemplares, cartas diferentes, repetidas e onde os exemplares estão —
 * nenhum valor monetário (D7.6; valor é relatório próprio). Cada exemplar aparece uma vez: está
 * em no máximo uma coleção ou em "Sem coleção", e a soma das linhas é o total.
 *
 * Ordem: cabeçalho institucional → indicadores consolidados → títulos das colunas → linhas.
 * Os três primeiros ficam no `<thead>` (repetem em toda folha impressa); linha nunca dividida
 * (regra global `.relatorio-folha tr`).
 */
const COLUMNS = 5;

export function CollectionDistributionSheet({ report, issuedAt }: { report: CollectionDistributionReport; issuedAt: string }) {
  const entry = libraryReport("distribution");
  const cabecalho = (
    <RelatorioCabecalho
      titulo={entry.title}
      identificacaoColecao="Minhas coleções"
      subtitulo={`${collectionDistributionSummaryLine(report)} · Emitido em ${issuedAt}`}
    />
  );

  if (report.totalCopies === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0">
          <p className="text-sm font-semibold text-neutral-900">Seu acervo ainda não tem cartas.</p>
          <p className="mt-2 text-xs text-neutral-600">Quando você cadastrar exemplares, o inventário aparece aqui.</p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  const rows = [
    ...report.collections.map((c) => ({ key: c.id, name: c.name, kind: c.kindLabel, status: c.archived ? "Arquivada" : "Ativa", copies: c.copies })),
    ...(report.unallocatedCopies > 0
      ? [{ key: "none", name: "Sem coleção", kind: "—", status: "Disponível no acervo", copies: report.unallocatedCopies }]
      : []),
  ];

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full text-left text-[10px]" style={{ borderCollapse: "collapse" }}>
          <thead>
            <tr>
              <th colSpan={COLUMNS} className="p-0 font-normal">
                <div className="-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <th colSpan={COLUMNS} className="p-0 pb-3 pt-1 text-left font-normal">
                <section aria-label="Indicadores do inventário" className="grid grid-cols-2 gap-2 sm:grid-cols-4 print:grid-cols-4">
                  <Indicator label="Exemplares" value={formatCount(report.totalCopies)} note="Cartas físicas no acervo" emphasis />
                  <Indicator
                    label="Cartas diferentes"
                    value={formatCount(report.distinctItems)}
                    note={`Variante + idioma · ${plural(report.distinctSets, "Set", "Sets")}`}
                  />
                  <Indicator label="Repetidas" value={formatCount(report.duplicateCopies)} note="Exemplares além do primeiro" />
                  <Indicator
                    label="Em coleções"
                    value={formatCount(report.allocatedCopies)}
                    note={`${plural(report.unallocatedCopies, "exemplar sem coleção", "exemplares sem coleção")}`}
                  />
                </section>
              </th>
            </tr>
            {/* Títulos das colunas no padrão dos relatórios da Central (DataTableHeadRow/Cell):
                caixa-alta 11px, cinza, fundo neutro em cada `th` (imprime inteiro). */}
            <DataTableHeadRow className="border-neutral-200 text-neutral-500">
              <DataTableHeadCell className="bg-neutral-50 pl-2">Onde estão os exemplares</DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Tipo
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Situação
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Exemplares
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="w-16 bg-neutral-50 pr-2 last:pr-2">
                %
              </DataTableHeadCell>
            </DataTableHeadRow>
          </thead>
          <tbody>
            {rows.map((row, index) => (
              <tr
                key={row.key}
                className="border-t border-neutral-100"
                style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}
              >
                <td className={`py-1.5 pl-2 pr-2 ${row.key === "none" ? "italic text-neutral-700" : "font-semibold text-neutral-900"}`}>{row.name}</td>
                <td className="py-1.5 pr-3 text-center text-neutral-700">{row.kind}</td>
                <td className="py-1.5 pr-3 text-center text-neutral-700">{row.status}</td>
                <td className="py-1.5 pr-3 text-center font-semibold tabular-nums text-neutral-900">{formatCount(row.copies)}</td>
                <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">{shareText(row.copies, report.totalCopies)}</td>
              </tr>
            ))}
            <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
              <td colSpan={3} className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">
                Total do acervo
              </td>
              <td className="py-1.5 pr-3 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.totalCopies)}</td>
              <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">100%</td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={COLUMNS} className="p-0">
                <ul className="mt-3 space-y-1 border-t border-neutral-200 py-3 text-[9px] leading-snug text-neutral-500">
                  <li>Cada exemplar físico é contado uma única vez: está em no máximo uma coleção ou em &ldquo;Sem coleção&rdquo;.</li>
                  <li>Cartas diferentes = combinações de variante e idioma (a mesma contagem do cabeçalho do Acervo); repetidas = exemplares além do primeiro de cada uma.</li>
                  {report.emptyCollectionCount > 0 ? (
                    <li>{plural(report.emptyCollectionCount, "coleção sem exemplares não aparece", "coleções sem exemplares não aparecem")} na lista.</li>
                  ) : null}
                </ul>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <RelatorioRodape />
    </RelatorioFolha>
  );
}

function Indicator({ label, value, note, emphasis = false }: { label: string; value: string; note: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
      <p className="text-[9px] leading-snug text-neutral-500">{note}</p>
    </div>
  );
}
