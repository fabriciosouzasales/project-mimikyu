import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural } from "@/lib/reports/acervo-reports";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import {
  type AcervoValueReport,
  type AcervoValueSetRow,
  acervoValueSummaryLine,
  priceObservationPeriod,
  valueCoveragePercent,
  valueCoverageText,
  valueShareBarPercent,
  valueShareText,
} from "@/lib/reports/acervo-value";

/**
 * V1-14 R1-C — folha "Valor estimado total" (relatório 03) do Meu acervo. Mesma folha institucional
 * da R1-B (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`; tela = impressão).
 * Visão patrimonial executiva: indicadores (valor, cobertura, sem cotação, Sets cotados), uma linha
 * por Card Set (valor decrescente) com participação e barra discreta, total e nota metodológica.
 * Sem linhas por carta (isso é o Inventário detalhado) e sem lista de cartas sem cotação (relatório
 * "Cobertura de preços"). Set sem cotado: "Sem cotação" e participação "—" (nunca R$ 0).
 *
 * Cabeçalho, indicadores e títulos das colunas no `<thead>` (repetem em toda folha impressa);
 * linha nunca dividida (regra global `.relatorio-folha tr`).
 */
const COLUMNS = 6;

export function AcervoValueSheet({ report, issuedAt }: { report: AcervoValueReport; issuedAt: string }) {
  const entry = acervoReport("value");
  const cabecalho = (
    <RelatorioCabecalho
      titulo={entry.title}
      identificacaoColecao="Meu acervo"
      subtitulo={`${acervoValueSummaryLine(report)} · Emitido em ${issuedAt}`}
    />
  );

  if (report.totalCopies === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0">
          <p className="text-sm font-semibold text-neutral-900">Seu acervo ainda não tem cartas.</p>
          <p className="mt-2 text-xs text-neutral-600">Quando você cadastrar exemplares, o valor estimado aparece aqui.</p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  const period = priceObservationPeriod(report);
  const totalText = report.totalBrl === null ? "Sem cotação" : formatBrl(report.totalBrl);

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <colgroup>
            <col />
            <col style={{ width: "5.5rem" }} />
            <col style={{ width: "4.75rem" }} />
            <col style={{ width: "5.25rem" }} />
            <col style={{ width: "6.5rem" }} />
            <col style={{ width: "8.25rem" }} />
          </colgroup>
          <thead>
            <tr>
              <th colSpan={COLUMNS} className="p-0 font-normal">
                <div className="-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <th colSpan={COLUMNS} className="p-0 pb-3 pt-1 text-left font-normal">
                <section aria-label="Indicadores do valor estimado" className="grid grid-cols-2 gap-2 sm:grid-cols-4 print:grid-cols-4">
                  <Indicator label="Valor estimado total" value={totalText} note="Exemplares cotados · referência NM" emphasis />
                  <Indicator label="Cobertura de preços" value={valueCoveragePercent(report)} note={valueCoverageText(report)} />
                  <Indicator label="Sem cotação" value={formatCount(report.unpricedCopies)} note="Exemplares fora do valor estimado" />
                  <Indicator
                    label="Card Sets com cotação"
                    value={`${formatCount(report.pricedSetCount)} de ${formatCount(report.setCount)}`}
                    note="Sets com exemplar cotado"
                  />
                </section>
              </th>
            </tr>
            <DataTableHeadRow className="border-neutral-200 text-neutral-500">
              <DataTableHeadCell className="bg-neutral-50 pl-2">Card Set</DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                Exemplares
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                Cotados
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                Sem cotação
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                Valor estimado
              </DataTableHeadCell>
              <DataTableHeadCell className="bg-neutral-50 pr-2 last:pr-2">Participação</DataTableHeadCell>
            </DataTableHeadRow>
          </thead>
          <tbody>
            {report.sets.map((set, index) => (
              <SetRow key={set.code} set={set} index={index} />
            ))}
            <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
              <td className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">Total do acervo</td>
              <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.totalCopies)}</td>
              <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.pricedCopies)}</td>
              <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.unpricedCopies)}</td>
              <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{totalText}</td>
              <td className="py-1.5 pr-2">
                <span className="inline-block w-11 text-right tabular-nums text-neutral-500">{valueShareText(report.totalBrl === null ? null : 1)}</span>
              </td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={COLUMNS} className="p-0">
                <ul className="mt-3 space-y-1 border-t border-neutral-200 py-3 text-[9px] leading-snug text-neutral-500">
                  <li>
                    Valor estimado = soma, por variante e idioma, de quantidade × referência de mercado Near Mint (NM). Não considera a condição física
                    real de cada exemplar e não é avaliação nem garantia de valor de venda.
                  </li>
                  <li>
                    Cobertura = proporção de exemplares com referência de preço; não mede a precisão nem a completude do valor patrimonial. Exemplares sem
                    cotação ficam fora do valor — nunca contam como zero.
                  </li>
                  <li>Todo o acervo físico, esteja o exemplar em uma coleção ou não. Participação = valor do Card Set ÷ valor estimado total, com uma casa decimal truncada; a soma pode não fechar 100%.</li>
                  {report.fallbackCopies > 0 ? (
                    <li>
                      {plural(report.fallbackCopies, "exemplar usa", "exemplares usam")} a referência geral da carta (a variante não tem cotação própria;
                      pode refletir outra impressão).
                    </li>
                  ) : null}
                  {period ? <li>Referências observadas em {period}; valores em dólar convertidos pela PTAX da data da observação.</li> : null}
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

function SetRow({ set, index }: { set: AcervoValueSetRow; index: number }) {
  const share = valueShareText(set.share);
  const bar = valueShareBarPercent(set.share);
  return (
    <tr className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
      <td className="py-1 pl-2 pr-2 align-middle leading-snug">
        <span className="font-semibold text-neutral-900">{set.name}</span>{" "}
        <span className="whitespace-nowrap text-neutral-500">· {set.code}</span>
      </td>
      <td className="px-2 py-1 text-center tabular-nums text-neutral-900">{formatCount(set.copies)}</td>
      <td className="px-2 py-1 text-center tabular-nums text-neutral-700">{formatCount(set.pricedCopies)}</td>
      <td className={`px-2 py-1 text-center tabular-nums ${set.unpricedCopies > 0 ? "text-neutral-700" : "text-neutral-400"}`}>
        {formatCount(set.unpricedCopies)}
      </td>
      <td className="px-2 py-1 text-center font-semibold tabular-nums text-neutral-900">
        {set.valueBrl === null ? <span className="font-normal text-neutral-400">Sem cotação</span> : formatBrl(set.valueBrl)}
      </td>
      <td className="py-1 pr-2">
        <div className="flex items-center gap-2">
          <span className={`w-11 shrink-0 text-right tabular-nums ${set.share === null ? "text-neutral-400" : "text-neutral-800"}`}>{share}</span>
          <span aria-hidden="true" className="h-1.5 flex-1 overflow-hidden rounded-full bg-neutral-100">
            {bar > 0 ? <span className="block h-full rounded-full bg-primary" style={{ width: `${bar}%` }} /> : null}
          </span>
        </div>
      </td>
    </tr>
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
