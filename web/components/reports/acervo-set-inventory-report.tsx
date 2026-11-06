import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural } from "@/lib/reports/acervo-reports";
import {
  type InventorySetGroup,
  type SetInventoryReport,
  collectorLabel,
  coverageText,
  formatBrl,
  setInventorySummaryLine,
  variantLabelText,
} from "@/lib/reports/acervo-set-inventory";

/**
 * V1-14 R1-B — folha "Inventário detalhado por Card Set" (relatório 02) do Meu acervo. Mesma folha institucional
 * da R1-A (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`; tela = impressão).
 * Todo o acervo físico, independentemente de coleção: um grupo por Card Set (ordem canônica do
 * Acervo), uma linha por variante + idioma, quantidade de exemplares, referência NM unitária e
 * total (quantidade × unitário). Sem cotação = "Sem cotação", fora das somas (nunca R$ 0).
 *
 * Ordem: cabeçalho → indicadores → títulos das colunas (os três no `<thead>`, repetem em toda
 * folha impressa) → grupos. Cada Card Set é um `<tbody>`: o título não fica sozinho no pé da
 * folha (`break-after: avoid`) e grupos curtos não se partem (`break-inside: avoid`); linha
 * nunca dividida (regra global `.relatorio-folha tr`).
 */
const COLUMNS = 5;
/** Grupos até este tamanho ficam inteiros numa folha. */
const KEEP_TOGETHER_LINES = 12;

export function AcervoSetInventorySheet({ report, issuedAt }: { report: SetInventoryReport; issuedAt: string }) {
  const entry = acervoReport("inventory-sets");
  const cabecalho = (
    <RelatorioCabecalho
      titulo={entry.title}
      identificacaoColecao="Meu acervo"
      subtitulo={`${setInventorySummaryLine(report)} · Emitido em ${issuedAt}`}
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

  const hasFallback = report.sets.some((set) => set.lines.some((line) => line.priceBasis === "CARD_FALLBACK"));

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <colgroup>
            <col style={{ width: "4.5rem" }} />
            <col />
            <col style={{ width: "3.5rem" }} />
            <col style={{ width: "5.5rem" }} />
            <col style={{ width: "6rem" }} />
          </colgroup>
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
                    label="Valor dos cotados"
                    value={report.totalBrl === null ? "Sem cotação" : formatBrl(report.totalBrl)}
                    note={coverageText(report)}
                  />
                </section>
              </th>
            </tr>
            {/* Títulos das colunas no padrão dos relatórios da Central (DataTableHeadRow/Cell). */}
            <DataTableHeadRow className="border-neutral-200 text-neutral-500">
              <DataTableHeadCell className="bg-neutral-50 pl-2">Número</DataTableHeadCell>
              <DataTableHeadCell className="bg-neutral-50">Carta</DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Qtd.
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50">
                Unitário NM
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 pr-2 last:pr-2">
                Total
              </DataTableHeadCell>
            </DataTableHeadRow>
          </thead>
          {report.sets.map((set) => (
            <SetGroup key={set.code} set={set} />
          ))}
          <tbody>
            <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
              <td colSpan={2} className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">
                Total do acervo
                {report.unpricedCopies > 0 ? (
                  <span className="ml-1 font-normal text-neutral-500">
                    · {plural(report.unpricedCopies, "exemplar sem cotação", "exemplares sem cotação")} (fora da soma)
                  </span>
                ) : null}
              </td>
              <td className="py-1.5 pr-3 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.totalCopies)}</td>
              <td className="py-1.5 pr-3 text-center text-neutral-400">—</td>
              <td className="py-1.5 pr-2 text-center font-bold tabular-nums text-neutral-900">
                {report.totalBrl === null ? "Sem cotação" : formatBrl(report.totalBrl)}
              </td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={COLUMNS} className="p-0">
                <ul className="mt-3 space-y-1 border-t border-neutral-200 py-3 text-[9px] leading-snug text-neutral-500">
                  <li>Todo o acervo físico, esteja o exemplar em uma coleção ou não; uma linha por variante e idioma.</li>
                  <li>
                    Unitário NM = referência de mercado Near Mint da variante; Total = quantidade × unitário. Não é avaliação da condição
                    física nem garantia de valor de revenda.
                  </li>
                  <li>Exemplares sem cotação aparecem como &ldquo;Sem cotação&rdquo; e ficam fora dos subtotais e do total — nunca contam como zero.</li>
                  {hasFallback ? <li>* Referência geral da carta: a variante não tem cotação própria; pode refletir outra impressão.</li> : null}
                  {report.priceObservedMax ? <li>Preços conforme as observações mais recentes disponíveis; câmbio PTAX da data da observação.</li> : null}
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

function SetGroup({ set }: { set: InventorySetGroup }) {
  return (
    <tbody style={{ breakInside: set.lines.length <= KEEP_TOGETHER_LINES ? "avoid" : "auto" }}>
      <tr style={{ breakInside: "avoid", breakAfter: "avoid" }}>
        <th colSpan={COLUMNS} scope="colgroup" className="pb-1 pl-2 pt-3 text-left text-[11px] font-semibold text-neutral-900">
          {set.name} <span className="font-normal text-neutral-500">· {set.code}</span>
        </th>
      </tr>
      {set.lines.map((line, index) => (
        <tr
          key={`${line.cardVariantId}.${line.languageCode}`}
          className="border-t border-neutral-100"
          style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}
        >
          <td className="py-1 pl-2 pr-2 tabular-nums text-neutral-600">{collectorLabel(line)}</td>
          <td className="py-1 pr-2">
            <span className="font-semibold text-neutral-900">{line.cardName}</span>
            <span className="text-neutral-500">
              {" "}
              · {variantLabelText(line)} · {line.languageCode}
            </span>
          </td>
          <td className="py-1 pr-3 text-center tabular-nums text-neutral-900">{formatCount(line.copies)}</td>
          <td className="py-1 pr-3 text-center tabular-nums text-neutral-700">
            {line.unitBrl === null ? (
              <span className="text-neutral-400">Sem cotação</span>
            ) : (
              <>
                {formatBrl(line.unitBrl)}
                {line.priceBasis === "CARD_FALLBACK" ? <span aria-label="referência geral da carta"> *</span> : null}
              </>
            )}
          </td>
          <td className="py-1 pr-2 text-center font-semibold tabular-nums text-neutral-900">
            {line.totalBrl === null ? <span className="font-normal text-neutral-400">—</span> : formatBrl(line.totalBrl)}
          </td>
        </tr>
      ))}
      <tr className="border-t border-neutral-300" style={{ breakInside: "avoid", breakBefore: "avoid" }}>
        <td colSpan={2} className="py-1 pl-2 pr-2 text-neutral-700">
          Subtotal {set.code}
          {set.unpricedCopies > 0 ? (
            <span className="text-neutral-500"> · {plural(set.unpricedCopies, "sem cotação", "sem cotação")}</span>
          ) : null}
        </td>
        <td className="py-1 pr-3 text-center font-semibold tabular-nums text-neutral-900">{formatCount(set.copies)}</td>
        <td className="py-1 pr-3 text-center text-neutral-400">—</td>
        <td className="py-1 pr-2 text-center font-semibold tabular-nums text-neutral-900">
          {set.subtotalBrl === null ? <span className="font-normal text-neutral-400">Sem cotação</span> : formatBrl(set.subtotalBrl)}
        </td>
      </tr>
    </tbody>
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
