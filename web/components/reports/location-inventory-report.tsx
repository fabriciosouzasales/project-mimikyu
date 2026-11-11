import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { LOCATION_INVENTORY_TITLE, type LocationInventoryReport, type InventorySet, formatInt, plural } from "@/lib/reports/location-inventory";

/**
 * V1-14 — bloco Locais — "Inventário do Local" (Relação de cartas armazenadas em
 * um local). Folha institucional dos relatórios (papel branco também no tema
 * escuro; rodapé de impressão pela casca). Inventário de CONFERÊNCIA: cabeçalho
 * com o local, três indicadores (exemplares físicos, cartas diferentes, Card
 * Sets), uma tabela por Card Set (Nº · Carta · Variante · Idioma · Qtd. · caixa
 * de conferência) e o total. Sem imagens — economia de impressão. Na impressão,
 * o cabeçalho institucional repete em todas as folhas (`<thead>` da tabela
 * externa) e cada tabela repete o título do Set e as colunas ao continuar.
 */
export function LocationInventorySheet({
  locationName,
  kindLabel,
  report,
  issuedAt,
}: {
  locationName: string;
  kindLabel: string | null;
  report: LocationInventoryReport;
  issuedAt: string;
}) {
  const cabecalho = (
    <RelatorioCabecalho
      titulo={LOCATION_INVENTORY_TITLE}
      identificacaoColecao={locationName}
      subtitulo={`${kindLabel ?? "Sem tipo definido"} · ${plural(report.copies, "exemplar", "exemplares")} · ${plural(report.cards, "carta diferente", "cartas diferentes")} · Emitido em ${issuedAt}`}
    />
  );

  if (report.copies === 0 && report.complete) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0" data-inventory-empty>
          <p className="text-sm font-semibold text-neutral-900">Nenhum exemplar guardado neste local.</p>
          <p className="mt-2 text-xs text-neutral-600">Quando você guardar cartas aqui, o inventário lista cada uma com a quantidade.</p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  return (
    <RelatorioFolha>
      <div className="px-4 sm:px-6 print:px-0">
        <table className="w-full" style={{ borderCollapse: "collapse" }}>
          <thead>
            <tr>
              <th className="p-0 text-left font-normal">
                <div className="-mx-4 sm:-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr style={{ breakInside: "auto", pageBreakInside: "auto" }}>
              <td className="p-0 align-top">
                <section aria-label="Indicadores do inventário" className="grid grid-cols-3 gap-2 pb-3 pt-1" style={{ breakInside: "avoid" }}>
                  <Indicator label="Exemplares físicos" value={formatInt(report.copies)} emphasis />
                  <Indicator label="Cartas diferentes" value={formatInt(report.cards)} />
                  <Indicator label="Card Sets" value={formatInt(report.sets.length)} />
                </section>

                {report.sets.map((set) => (
                  <SetTable key={set.code} set={set} />
                ))}

                <p className="mt-4 flex justify-between border-t-2 border-neutral-300 pt-2 text-[11px] font-bold text-neutral-900" style={{ breakInside: "avoid" }}>
                  <span>Total do local</span>
                  <span className="tabular-nums">
                    {plural(report.cards, "carta diferente", "cartas diferentes")} · {plural(report.copies, "exemplar", "exemplares")}
                  </span>
                </p>
                <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                  <li>Exemplares guardados neste local no momento da emissão — cartas de outros locais ou sem localização não entram.</li>
                  <li>Carta diferente = carta + variante + idioma (a mesma identidade do Meu acervo); Qtd. = exemplares físicos dessa carta aqui.</li>
                  <li>A coluna ☐ é para a conferência no próprio local.</li>
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

function SetTable({ set }: { set: InventorySet }) {
  return (
    <table className="mt-4 w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
      <colgroup>
        <col style={{ width: "4.25rem" }} />
        <col />
        <col style={{ width: "8.5rem" }} />
        <col style={{ width: "7.5rem" }} />
        <col style={{ width: "3rem" }} />
        <col style={{ width: "2rem" }} />
      </colgroup>
      <thead>
        <tr style={{ breakAfter: "avoid" }}>
          <th colSpan={6} scope="colgroup" className="pb-1 pl-2 pt-1 text-left font-normal">
            <span className="text-[11px] font-semibold text-neutral-900">
              {set.code.toUpperCase()} · {set.name}
            </span>
            <span className="text-neutral-500">
              {" "}
              · {plural(set.cards, "carta", "cartas")} · {plural(set.copies, "exemplar", "exemplares")}
            </span>
          </th>
        </tr>
        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
          <DataTableHeadCell className="bg-neutral-50 pl-2">Nº</DataTableHeadCell>
          <DataTableHeadCell className="bg-neutral-50">Carta</DataTableHeadCell>
          <DataTableHeadCell className="bg-neutral-50">Variante</DataTableHeadCell>
          <DataTableHeadCell className="bg-neutral-50">Idioma</DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50" title="Exemplares neste local">
            Qtd.
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 pr-2" aria-label="Conferido">
            ☐
          </DataTableHeadCell>
        </DataTableHeadRow>
      </thead>
      <tbody>
        {set.lines.map((line, index) => (
          <tr key={line.key} className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
            <td className="py-1 pl-2 tabular-nums text-neutral-600">{line.number}</td>
            <td className="truncate py-1 pr-2 font-medium text-neutral-900">{line.name}</td>
            <td className="truncate py-1 pr-2 text-neutral-700">{line.variant}</td>
            <td className="truncate py-1 pr-2 text-neutral-700">{line.language}</td>
            <td className="py-1 text-center font-bold tabular-nums text-neutral-900">{formatInt(line.copies)}</td>
            <td className="py-1 pr-2 text-center">
              <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-[2px] border border-neutral-400 align-middle" />
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Indicator({ label, value, emphasis = false }: { label: string; value: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
    </div>
  );
}
