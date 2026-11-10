import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural, shareText } from "@/lib/reports/acervo-reports";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import {
  type DistributionBand,
  type DistributionDimension,
  type DistributionReport,
  distributionBarPercent,
  distributionCoverageText,
  distributionSetSummaryText,
  distributionShowsSetComposition,
  distributionShareText,
  distributionSummaryLine,
  distributionValueText,
} from "@/lib/reports/distribution";

/**
 * V1-14 R1-H — folha "Distribuição por Set, raridade e idioma" (relatório 08 do Meu acervo;
 * contrato D7 §4h). Mesma folha institucional dos demais relatórios (rodapé de impressão pela
 * casca em toda página). Cabeçalho institucional e indicadores só no início (1ª página) → resumo
 * da composição por Card Set (Top 10 + Demais, uma barra; só com mais de 10 Sets) → três tabelas analíticas (Card Set,
 * Raridade, Idioma) com a barra de participação FÍSICA integrada à linha (HTML/CSS, sem gráfico
 * separado) → nota metodológica. Na impressão, o cabeçalho institucional completo se repete em
 * TODAS as páginas (thead da tabela externa) e os KPIs ficam só na 1ª; o `<thead>` de cada tabela
 * interna repete o título da seção e as colunas quando ela continua na página seguinte. Colunas:
 * Faixa · Exemplares · % · Itens · Valor estimado · % · Cobertura (1º % = exemplares físicos; 2º % =
 * valor total cotado — definidos na nota). Sem miniaturas.
 */
const COLUMNS = 7;
const KEEP_TOGETHER_ROWS = 24;

export function DistributionSheet({ report, issuedAt }: { report: DistributionReport; issuedAt: string }) {
  const entry = acervoReport("distribution");
  const cabecalho = (
    <RelatorioCabecalho titulo={entry.title} identificacaoColecao="Meu acervo" subtitulo={`${distributionSummaryLine(report)} · Emitido em ${issuedAt}`} />
  );

  if (report.totalCopies === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0">
          <p className="text-sm font-semibold text-neutral-900">Seu acervo ainda não tem exemplares.</p>
          <p className="mt-2 text-xs text-neutral-600">Quando você adicionar cartas, a distribuição por Set, raridade e idioma aparece aqui.</p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  const topSet = report.sets.bands[0];
  const anyPriced = report.pricedCopies > 0;
  const valueText = report.totalBrl === null ? (report.unavailableCopies > 0 ? "Indisponível" : "Sem cotação") : report.unavailableCopies > 0 ? `${formatBrl(report.totalBrl)} (parcial)` : formatBrl(report.totalBrl);

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        {/*
          Cabeçalho institucional em TODAS as páginas impressas: mesmo mecanismo homologado do Top 10 e do
          Valor estimado total — o cabeçalho no <thead> de uma tabela (o navegador repete o grupo de
          cabeçalho no topo de cada folha, no fluxo, sem posicionamento fixo nem sobreposição). Como esta
          folha tem três tabelas, elas ficam dentro de uma única linha da tabela externa; essa linha precisa
          poder continuar na página seguinte (a regra global `.relatorio-folha tr { break-inside: avoid }`
          é desfeita só nela) — as linhas das tabelas internas continuam indivisíveis.
        */}
        <table className="w-full" style={{ borderCollapse: "collapse" }}>
          <thead>
            <tr>
              <th className="p-0 text-left font-normal">
                <div className="-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr style={{ breakInside: "auto", pageBreakInside: "auto" }}>
              <td className="p-0 align-top">
        <section aria-label="Indicadores da distribuição" className="grid grid-cols-2 gap-2 pb-3 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
          <Indicator label="Exemplares" value={formatCount(report.totalCopies)} note={`em ${plural(report.distinctItems, "item", "itens")}`} emphasis />
          <Indicator
            label="Diversidade"
            value={plural(report.sets.bands.length, "Set", "Sets")}
            note={`${plural(report.rarityCount, "raridade", "raridades")} · ${plural(report.languages.bands.length, "idioma", "idiomas")}`}
          />
          <Indicator label="Valor estimado" value={valueText} note={`${shareText(report.pricedCopies, report.totalCopies)} dos exemplares cotados`} />
          <Indicator label="Maior concentração" value={topSet ? distributionShareText(topSet.copiesShare) : "—"} note={topSet ? `${topSet.label} · dos exemplares` : ""} />
        </section>

        <SetComposition report={report} />

        <DimensionTable title="Por Card Set" dimension={report.sets} anyPriced={anyPriced} showUnavailable={report.unavailableCopies > 0} />
        {report.rarities ? (
          <DimensionTable title="Por raridade" dimension={report.rarities} anyPriced={anyPriced} showUnavailable={report.unavailableCopies > 0} />
        ) : (
          <section className="mt-4 rounded-md border border-neutral-200 px-3 py-3 text-[10px] text-neutral-600" style={{ breakInside: "avoid" }}>
            <h3 className="text-[11px] font-semibold text-neutral-900">Por raridade</h3>
            <p className="mt-1">O catálogo de raridades não pôde ser carregado agora; esta seção volta quando o relatório for aberto de novo.</p>
          </section>
        )}
        <DimensionTable title="Por idioma" dimension={report.languages} anyPriced={anyPriced} showUnavailable={report.unavailableCopies > 0} />

        <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
          <li>
            Todo o acervo físico, esteja o exemplar em uma coleção ou não. Exemplares = cartas físicas (medida das barras, dos percentuais e da
            ordem); itens = variante + idioma distintos (uma carta com várias cópias é um item). Cada dimensão soma o total do acervo.
          </li>
          <li>
            Raridade da carta, conforme o catálogo (uma variante herda a raridade da sua carta), na ordem oficial; &ldquo;Sem raridade
            definida&rdquo;: carta sem raridade no catálogo. Raridades diferentes com o mesmo nome aparecem com o código ao lado.
          </li>
          <li>
            Valor estimado = referência de mercado Near Mint (NM) unitária × exemplares, só dos exemplares cotados — mesma base do Valor estimado
            total. Colunas &ldquo;%&rdquo;: a primeira (ao lado de Exemplares) é a participação nos exemplares físicos; a segunda (ao lado de Valor
            estimado) é a participação no valor total cotado. Sem cotação: fora do valor, nunca zero. Cobertura = exemplares cotados da
            faixa; &ldquo;Baixa cobertura de preços&rdquo; abaixo de 50% — ali o percentual de valor subestima a participação real. Não considera a
            condição física; não é avaliação nem preço de venda. Dólar convertido pela PTAX da data da observação.
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

/** Resumo visual da composição por Card Set: Top 10 + Demais numa única barra (sem repetir a tabela); só com mais de 10 Sets. */
export function SetComposition({ report }: { report: Pick<DistributionReport, "sets" | "setSummary" | "totalCopies"> }) {
  if (!distributionShowsSetComposition(report)) return null;
  const { top, othersCopies } = report.setSummary;
  const segments: { key: string; label: string; share: number; tone: string }[] = top.map((band, index) => ({
    key: band.key,
    label: `${band.label} · ${distributionShareText(band.copiesShare)}`,
    share: band.copiesShare,
    tone: index === 0 ? "bg-primary" : index % 2 === 0 ? "bg-neutral-500" : "bg-neutral-400",
  }));
  if (othersCopies > 0) segments.push({ key: "others", label: `Demais Sets · ${distributionShareText(othersCopies / report.totalCopies)}`, share: othersCopies / report.totalCopies, tone: "bg-neutral-200" });
  return (
    <section aria-label="Composição por Card Set" className="pb-2" style={{ breakInside: "avoid" }}>
      <div className="flex h-2.5 w-full overflow-hidden rounded-full bg-neutral-100" aria-hidden="true">
        {segments.map((segment) => (
          <span key={segment.key} title={segment.label} className={`h-full border-r border-white last:border-r-0 ${segment.tone}`} style={{ width: `${segment.share * 100}%` }} />
        ))}
      </div>
      <p className="mt-1 text-[9px] text-neutral-500">{distributionSetSummaryText(report)}</p>
    </section>
  );
}

function DimensionTable({
  title,
  dimension,
  anyPriced,
  showUnavailable,
}: {
  title: string;
  dimension: DistributionDimension;
  anyPriced: boolean;
  showUnavailable: boolean;
}) {
  const partial = showUnavailable && dimension.bands.some((b) => b.unavailableCopies > 0);
  const totalValue = dimension.valueBrl === null ? (partial ? "Indisponível" : "Sem cotação") : partial ? `${formatBrl(dimension.valueBrl)} (parcial)` : formatBrl(dimension.valueBrl);
  const priced = dimension.bands.reduce((n, b) => n + b.pricedCopies, 0);
  return (
    <table className="mt-3 w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
      <colgroup>
        <col />
        <col style={{ width: "5rem" }} />
        <col style={{ width: "3.75rem" }} />
        <col style={{ width: "3.75rem" }} />
        <col style={{ width: "6.75rem" }} />
        <col style={{ width: "3.75rem" }} />
        <col style={{ width: "5.25rem" }} />
      </colgroup>
      <thead>
        <tr style={{ breakAfter: "avoid" }}>
          <th colSpan={COLUMNS} scope="colgroup" className="pb-1 pl-2 pt-1 text-left text-[11px] font-semibold text-neutral-900">
            {title} <span className="font-normal text-neutral-500">· {plural(dimension.bands.length, "faixa", "faixas")}</span>
          </th>
        </tr>
        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
          <DataTableHeadCell className="bg-neutral-50 pl-2">Faixa</DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-1">
            Exemplares
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-1" title="Participação nos exemplares físicos" aria-label="% dos exemplares">
            %
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-1">
            Itens
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
            Valor estimado
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-1" title="Participação no valor total cotado" aria-label="% do valor cotado">
            %
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-1 last:pr-2">
            Cobertura
          </DataTableHeadCell>
        </DataTableHeadRow>
      </thead>
      <tbody style={{ breakInside: dimension.bands.length <= KEEP_TOGETHER_ROWS ? "avoid" : "auto" }}>
        {dimension.bands.map((band, index) => (
          <BandRow key={band.key} band={band} index={index} anyPriced={anyPriced} />
        ))}
        <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
          <td className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">Total</td>
          <td className="px-1 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(dimension.copies)}</td>
          <td className="px-1 py-1.5 text-center font-bold tabular-nums text-neutral-900">100,0%</td>
          <td className="px-1 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(dimension.items)}</td>
          <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{totalValue}</td>
          <td className="px-1 py-1.5 text-center font-bold tabular-nums text-neutral-900">{dimension.valueBrl === null ? "—" : "100,0%"}</td>
          <td className="px-1 py-1.5 text-center tabular-nums text-neutral-700">{shareText(priced, dimension.copies)}</td>
        </tr>
      </tbody>
    </table>
  );
}

function BandRow({ band, index, anyPriced }: { band: DistributionBand; index: number; anyPriced: boolean }) {
  const bar = distributionBarPercent(band.copiesShare);
  const muted = band.kind === "rarity-none" || band.kind === "rarity-unknown";
  return (
    <tr className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
      <td className="py-1 pl-2 pr-2 align-middle leading-snug">
        <span className={`block truncate ${band.top ? "font-semibold text-neutral-900" : muted ? "italic text-neutral-600" : "text-neutral-900"}`}>
          {band.label}
          {band.detail ? <span className="font-normal not-italic text-neutral-500"> · {band.detail}</span> : null}
        </span>
        <span aria-hidden="true" className="mt-0.5 block h-1.5 w-full overflow-hidden rounded-full bg-neutral-100">
          {bar > 0 ? <span className={`block h-full rounded-full ${band.top ? "bg-primary" : "bg-neutral-400"}`} style={{ width: `${bar}%` }} /> : null}
        </span>
      </td>
      <td className="px-1 py-1 text-center tabular-nums text-neutral-900">{formatCount(band.copies)}</td>
      <td className="px-1 py-1 text-center tabular-nums text-neutral-900">{distributionShareText(band.copiesShare)}</td>
      <td className="px-1 py-1 text-center tabular-nums text-neutral-700">{formatCount(band.items)}</td>
      <td className="px-2 py-1 text-center tabular-nums text-neutral-900">
        {band.valueBrl === null ? <span className={band.unavailableCopies > 0 ? "italic text-neutral-500" : "text-neutral-400"}>{distributionValueText(band, formatBrl)}</span> : distributionValueText(band, formatBrl)}
      </td>
      <td className="px-1 py-1 text-center tabular-nums text-neutral-700">{anyPriced ? distributionShareText(band.valueShare) : "—"}</td>
      <td className="px-1 py-1 text-center align-middle tabular-nums text-neutral-700">
        <span className="block">{distributionCoverageText(band)}</span>
        {band.lowCoverage ? <span className="block text-[8.5px] font-medium leading-tight text-neutral-600">Baixa cobertura de preços</span> : null}
      </td>
    </tr>
  );
}

function Indicator({ label, value, note, emphasis = false }: { label: string; value: string; note?: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="truncate font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
      {note ? <p className="truncate text-[9px] leading-snug text-neutral-500">{note}</p> : null}
    </div>
  );
}
