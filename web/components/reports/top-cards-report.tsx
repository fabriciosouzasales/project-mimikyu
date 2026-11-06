import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural, shareText } from "@/lib/reports/acervo-reports";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import { valueShareText } from "@/lib/reports/acervo-value";
import {
  TOP_CARDS_LIMIT,
  type TopCardLine,
  type TopCardsReport,
  topCardsSummaryLine,
  topIdentityText,
  topObservedText,
  topPriceFlags,
  topTiedText,
} from "@/lib/reports/top-cards";

/**
 * V1-14 R1-F — folha "Top 10 cartas mais valiosas" (relatório 06 do Meu acervo). Mesma folha
 * institucional dos demais relatórios (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`;
 * rodapé de impressão institucional pela casca). Indicadores → dez linhas (posição, miniatura
 * 40 × 56, carta e identificação, referência NM unitária com data e sinais, exemplares, valor das
 * cópias) → total das cópias do Top 10 e nota metodológica. Cabe numa folha A4.
 */
const COLUMNS = 5;

export function TopCardsSheet({ report, issuedAt }: { report: TopCardsReport; issuedAt: string }) {
  const entry = acervoReport("top");
  const cabecalho = (
    <RelatorioCabecalho titulo={entry.title} identificacaoColecao="Meu acervo" subtitulo={`${topCardsSummaryLine(report)} · Emitido em ${issuedAt}`} />
  );

  if (report.lines.length === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0">
          <p className="text-sm font-semibold text-neutral-900">
            {report.totalGroups === 0 ? "Seu acervo ainda não tem cartas." : "Nenhuma carta do acervo tem cotação ainda."}
          </p>
          <p className="mt-2 text-xs text-neutral-600">
            {report.unavailableGroups > 0
              ? "Os preços de referência não puderam ser carregados agora. Tente novamente em instantes."
              : "Quando houver referência de mercado para seus exemplares, as mais valiosas aparecem aqui."}
          </p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  const first = report.lines[0] as TopCardLine;
  const tied = topTiedText(report);
  const topTotal = report.topCopiesBrl === null ? "—" : formatBrl(report.topCopiesBrl);
  const share = valueShareText(report.topShare);

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <colgroup>
            <col style={{ width: "2.75rem" }} />
            <col />
            <col style={{ width: "7rem" }} />
            <col style={{ width: "4.75rem" }} />
            <col style={{ width: "6.5rem" }} />
          </colgroup>
          <thead>
            <tr>
              <th colSpan={COLUMNS} className="p-0 font-normal">
                <div className="-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <th colSpan={COLUMNS} className="p-0 pb-3 pt-1 text-left font-normal">
                <section aria-label="Indicadores do Top 10" className="grid grid-cols-2 gap-2 sm:grid-cols-4 print:grid-cols-4">
                  <Indicator label="Cartas no Top 10" value={`${formatCount(report.lines.length)} de ${TOP_CARDS_LIMIT}`} />
                  <Indicator label="Maior valor unitário" value={formatBrl(first.unitBrl)} note={first.cardName} emphasis />
                  <Indicator label="Valor do Top 10" value={topTotal} note={`${share} do acervo cotado`} />
                  <Indicator
                    label="Cobertura de preços"
                    value={`${formatCount(report.pricedGroups)} / ${formatCount(report.totalGroups)}`}
                    note={`${shareText(report.pricedGroups, report.totalGroups)} dos itens`}
                  />
                </section>
              </th>
            </tr>
            <DataTableHeadRow className="border-neutral-200 text-neutral-500">
              <DataTableHeadCell align="center" className="bg-neutral-50 px-1">
                Pos.
              </DataTableHeadCell>
              <DataTableHeadCell className="bg-neutral-50">Carta</DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                Referência NM
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                Exemplares
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2 last:pr-2">
                Valor das cópias
              </DataTableHeadCell>
            </DataTableHeadRow>
          </thead>
          <tbody>
            {report.lines.map((line, index) => (
              <TopRow key={`${line.cardVariantId}.${line.languageCode}`} line={line} index={index} />
            ))}
            <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
              <td colSpan={3} className="py-1 pl-2 pr-2 font-semibold text-neutral-900">
                Valor das cópias do Top 10
                <span className="ml-1 font-normal text-neutral-500">· {share} do valor estimado dos exemplares cotados</span>
              </td>
              <td className="px-2 py-1 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.topCopies)}</td>
              <td className="px-2 py-1 text-center font-bold tabular-nums text-neutral-900">{topTotal}</td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={COLUMNS} className="p-0">
                {/* Notas compactas (A4 PRINT COMPACTION-01): mesmas informações em três itens, para o Top 10 caber numa folha. */}
                <ul className="mt-2 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500">
                  <li>
                    Ranking pela referência de mercado Near Mint (NM) unitária, do maior para o menor; a quantidade de exemplares não muda a posição. Uma
                    posição por variante + idioma (a mesma variante em dois idiomas pode ocupar duas posições). Desempate: Card Set, número, variante e
                    idioma.
                    {tied ? ` ${tied.charAt(0).toUpperCase()}${tied.slice(1)}.` : null}
                    {report.lines.length < TOP_CARDS_LIMIT ? ` O acervo tem ${plural(report.pricedGroups, "item cotado", "itens cotados")}: o ranking mostra todos.` : null}
                  </li>
                  <li>
                    Valor das cópias = referência unitária × exemplares; participação sobre a mesma base do Valor estimado total (exemplares cotados). Não
                    considera a condição física do exemplar; não é avaliação nem preço de venda.
                  </li>
                  <li>
                    Cobertura: {formatCount(report.pricedGroups)} de {plural(report.totalGroups, "item", "itens")} (variante + idioma) e{" "}
                    {formatCount(report.pricedCopies)} de {plural(report.totalCopies, "exemplar", "exemplares")} com cotação; sem cotação fica fora do
                    ranking (nunca conta como zero). &ldquo;Preço geral da carta&rdquo;: a variante não tem cotação própria (pode
                    refletir outra impressão) · &ldquo;Desatualizada&rdquo;: observação com mais de 14 dias · &ldquo;Referência internacional&rdquo;:
                    idioma diferente do inglês. Dólar convertido pela PTAX da data da observação.
                  </li>
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

function TopRow({ line, index }: { line: TopCardLine; index: number }) {
  const flags = topPriceFlags(line);
  return (
    <tr className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
      <td className="px-1 py-1 text-center align-middle">
        <span className={`font-heading text-sm font-bold tabular-nums ${line.rank === 1 ? "text-primary" : "text-neutral-800"}`}>{line.rank}º</span>
      </td>
      <td className="py-1 pr-2 align-middle">
        <span className="flex items-center gap-2.5">
          {/* Miniatura maior que nas listas (40 × 56, proporção da carta), na tela e na impressão. */}
          <span aria-hidden="true" className="h-[56px] w-[40px] shrink-0 overflow-hidden rounded-[3px] border border-neutral-200 bg-neutral-100">
            {line.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador de imagens configurado (mesma regra da Pesquisa)
              <img src={line.imageUrl} alt="" width={40} height={56} loading="eager" decoding="async" className="h-full w-full object-cover" />
            ) : null}
          </span>
          <span className="min-w-0 leading-snug">
            <span className="block text-[11px] font-semibold text-neutral-900">{line.cardName}</span>
            <span className="block text-[9px] text-neutral-500">{topIdentityText(line)}</span>
          </span>
        </span>
      </td>
      <td className="px-2 py-1 text-center align-middle">
        <span className="block font-semibold tabular-nums text-neutral-900">{formatBrl(line.unitBrl)}</span>
        <span className="block text-[8.5px] text-neutral-500">{topObservedText(line)}</span>
        {flags.length > 0 ? <span className="block text-[8.5px] font-medium text-neutral-700">{flags.join(" · ")}</span> : null}
      </td>
      <td className="px-2 py-1 text-center align-middle tabular-nums text-neutral-900">{formatCount(line.copies)}</td>
      <td className="px-2 py-1 text-center align-middle tabular-nums text-neutral-700">{formatBrl(line.copiesBrl)}</td>
    </tr>
  );
}

function Indicator({ label, value, note, emphasis = false }: { label: string; value: string; note?: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
      {note ? <p className="text-[9px] leading-snug text-neutral-500">{note}</p> : null}
    </div>
  );
}
