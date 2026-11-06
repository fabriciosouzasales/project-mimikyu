import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural, shareText } from "@/lib/reports/acervo-reports";
import { type SetSummaryReport, setSummaryLine } from "@/lib/reports/acervo-set-summary";

/**
 * V1-14 R1-B — folha "Inventário resumido por Card Set" (relatório 01 do Meu acervo). Mesma
 * identidade da folha homologada de distribuição por coleção: folha institucional da R1-A
 * (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`; tela = impressão), indicadores
 * consolidados e títulos no padrão da Central. Uma linha por Card Set do catálogo presente no
 * acervo, na ordem canônica (lançamento mais recente primeiro); nenhum valor monetário.
 *
 * Ordem: cabeçalho institucional → indicadores → títulos das colunas (os três no `<thead>`,
 * repetem em toda folha impressa) → linhas → total; linha nunca dividida (regra global
 * `.relatorio-folha tr`).
 */
const COLUMNS = 5;

export function AcervoSetSummarySheet({ report, issuedAt }: { report: SetSummaryReport; issuedAt: string }) {
  const entry = acervoReport("inventory-summary");
  const cabecalho = (
    <RelatorioCabecalho titulo={entry.title} identificacaoColecao="Meu acervo" subtitulo={`${setSummaryLine(report)} · Emitido em ${issuedAt}`} />
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
                  <Indicator label="Cartas diferentes" value={formatCount(report.distinctItems)} note="Combinações de variante + idioma" />
                  <Indicator label="Repetidas" value={formatCount(report.duplicateCopies)} note="Exemplares além do primeiro" />
                  <Indicator label="Card Sets" value={formatCount(report.distinctSets)} note="Sets do catálogo com cartas no acervo" />
                </section>
              </th>
            </tr>
            {/* Títulos das colunas no padrão dos relatórios da Central (DataTableHeadRow/Cell). */}
            <DataTableHeadRow className="border-neutral-200 text-neutral-500">
              <DataTableHeadCell className="bg-neutral-50 pl-2">Card Set</DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Exemplares
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Diferentes
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Repetidas
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="w-16 bg-neutral-50 pr-2 last:pr-2">
                %
              </DataTableHeadCell>
            </DataTableHeadRow>
          </thead>
          <tbody>
            {report.sets.map((set, index) => (
              <tr
                key={set.code}
                className="border-t border-neutral-100"
                style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}
              >
                <td className="py-1.5 pl-2 pr-2">
                  <span className="font-semibold text-neutral-900">{set.name}</span>
                  <span className="text-neutral-500"> · {set.code}</span>
                </td>
                <td className="py-1.5 pr-3 text-center font-semibold tabular-nums text-neutral-900">{formatCount(set.copies)}</td>
                <td className="py-1.5 pr-3 text-center tabular-nums text-neutral-700">{formatCount(set.distinct)}</td>
                <td className="py-1.5 pr-3 text-center tabular-nums text-neutral-700">{formatCount(set.duplicates)}</td>
                <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">{shareText(set.copies, report.totalCopies)}</td>
              </tr>
            ))}
            <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
              <td className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">
                Total do acervo
                <span className="ml-1 font-normal text-neutral-500">· {plural(report.distinctSets, "Card Set", "Card Sets")}</span>
              </td>
              <td className="py-1.5 pr-3 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.totalCopies)}</td>
              <td className="py-1.5 pr-3 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.distinctItems)}</td>
              <td className="py-1.5 pr-3 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.duplicateCopies)}</td>
              <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">100%</td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={COLUMNS} className="p-0">
                <ul className="mt-3 space-y-1 border-t border-neutral-200 py-3 text-[9px] leading-snug text-neutral-500">
                  <li>Todo o acervo físico, esteja o exemplar em uma coleção ou não; cada exemplar conta uma única vez, no Card Set da sua carta.</li>
                  <li>Cartas diferentes = combinações de variante e idioma (a mesma contagem do cabeçalho do Acervo); repetidas = exemplares além do primeiro de cada uma.</li>
                  <li>% = participação do Card Set no total de exemplares do acervo.</li>
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
