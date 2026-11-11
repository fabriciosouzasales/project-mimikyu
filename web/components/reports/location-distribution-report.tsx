import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { formatCount, plural } from "@/lib/reports/acervo-reports";
import {
  LOCATION_DISTRIBUTION_TITLE,
  type LocationDistributionReport,
  locationDistributionSummaryLine,
} from "@/lib/reports/location-distribution";

/**
 * V1-14 — bloco Locais — "Distribuição do Acervo por Local" (Quantidade de
 * Exemplares por Local; D7 §4s). Folha institucional dos relatórios
 * (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`; papel branco
 * também no tema escuro; A4 retrato). Três níveis de leitura:
 *
 * 1. resumo — exemplares físicos, com local definido, sem localização e
 *    organização do acervo (uma casa decimal);
 * 2. por tipo de armazenamento — locais, exemplares e % do acervo, com "Sem
 *    localização" separado dos recipientes e a linha de total;
 * 3. por local — TODOS os locais (vazios com 0 e 0,0%), maior quantidade
 *    primeiro; barra de comparação relativa ao maior local (a folha diz isso) e
 *    % sempre sobre o acervo físico total.
 *
 * Impressão: o cabeçalho institucional repete em toda folha (`<thead>` da
 * tabela externa); cada tabela repete os títulos das colunas ao continuar;
 * linha nunca dividida (regra global `.relatorio-folha tr`). Sem capacidade,
 * bolsos ou ocupação (relatório 3).
 */
export function LocationDistributionSheet({ report, issuedAt }: { report: LocationDistributionReport; issuedAt: string }) {
  const cabecalho = (
    <RelatorioCabecalho
      titulo={LOCATION_DISTRIBUTION_TITLE}
      identificacaoColecao="Meus Locais de Armazenamento"
      subtitulo={`${locationDistributionSummaryLine(report)} · Emitido em ${issuedAt}`}
    />
  );
  const emptyAcervo = report.totalCopies === 0;

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
                {/* Nível 1 — resumo executivo */}
                <section aria-label="Organização física do acervo" className="grid grid-cols-4 gap-2 pb-3 pt-1" style={{ breakInside: "avoid" }}>
                  <Indicator label="Exemplares físicos" value={formatCount(report.totalCopies)} note="Todo o acervo" emphasis />
                  <Indicator label="Com local definido" value={formatCount(report.locatedCopies)} note={plural(report.locations.length, "local cadastrado", "locais cadastrados")} />
                  <Indicator
                    label="Sem localização"
                    value={formatCount(report.unlocatedCopies)}
                    note={emptyAcervo ? "—" : `${report.unlocatedShare} do acervo`}
                    warn={report.unlocatedCopies > 0}
                  />
                  <Indicator label="Organização do acervo" value={report.organization} note={emptyAcervo ? "Acervo sem exemplares" : "Com local ÷ acervo físico"} />
                </section>

                {emptyAcervo ? (
                  <p className="mb-1 rounded-md border border-dashed border-neutral-300 px-4 py-3 text-center text-[11px] text-neutral-600" data-distribution-empty="">
                    Seu acervo ainda não tem exemplares físicos — não há percentuais a calcular.
                    {report.locations.length > 0 ? " Os locais cadastrados aparecem abaixo, todos com 0 exemplares." : ""}
                  </p>
                ) : null}

                {/* Nível 2 — por tipo de armazenamento */}
                {report.kinds.length > 0 || report.unlocatedCopies > 0 ? <KindTable report={report} /> : null}

                {/* Nível 3 — por local */}
                {report.locations.length > 0 ? (
                  <LocationTable report={report} />
                ) : (
                  <p className="mt-4 text-center text-[11px] text-neutral-600" data-distribution-no-locations="">
                    Nenhum local cadastrado ainda. Em Meus Locais de Armazenamento, crie um fichário, caixa ou ETB para começar.
                  </p>
                )}

                <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                  <li>Unidade = exemplar físico; cada exemplar está em no máximo um local ou em &ldquo;Sem localização&rdquo;. Total = com local + sem localização.</li>
                  <li>Todos os percentuais são sobre o acervo físico total, com uma casa decimal.</li>
                  {report.locations.length > 0 ? (
                    <li>A barra compara cada local com o local de maior quantidade; o percentual escrito é a participação no acervo.</li>
                  ) : null}
                  {report.emptyLocations > 0 ? (
                    <li>{plural(report.emptyLocations, "local cadastrado ainda está vazio", "locais cadastrados ainda estão vazios")} (0 exemplares).</li>
                  ) : null}
                  <li>Capacidade e ocupação de fichários não fazem parte deste relatório.</li>
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

function SectionTitle({ title, detail }: { title: string; detail: string }) {
  return (
    <span className="text-[11px] font-semibold text-neutral-900">
      {title}
      <span className="font-normal text-neutral-500"> · {detail}</span>
    </span>
  );
}

function KindTable({ report }: { report: LocationDistributionReport }) {
  return (
    <table className="mt-3 w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }} data-distribution-kinds="">
      <colgroup>
        <col />
        <col style={{ width: "4.5rem" }} />
        <col style={{ width: "5.5rem" }} />
        <col style={{ width: "5.5rem" }} />
      </colgroup>
      <thead>
        <tr style={{ breakAfter: "avoid" }}>
          <th colSpan={4} scope="colgroup" className="pb-1 pl-2 pt-1 text-left font-normal">
            <SectionTitle title="Por tipo de armazenamento" detail={plural(report.kinds.length, "tipo", "tipos")} />
          </th>
        </tr>
        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
          <DataTableHeadCell className="bg-neutral-50 pl-2">Tipo</DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Locais
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Exemplares
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 pr-2">
            % do acervo
          </DataTableHeadCell>
        </DataTableHeadRow>
      </thead>
      <tbody>
        {report.kinds.map((kind, index) => (
          <tr key={kind.code ?? "none"} className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
            <td className={`truncate py-1.5 pl-2 pr-2 font-semibold ${kind.code ? "text-neutral-900" : "italic text-neutral-700"}`}>{kind.label}</td>
            <td className="py-1.5 text-center tabular-nums text-neutral-700">{formatCount(kind.locations)}</td>
            <td className="py-1.5 text-center font-semibold tabular-nums text-neutral-900">{formatCount(kind.copies)}</td>
            <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">{kind.share}</td>
          </tr>
        ))}
        <tr className="border-t border-neutral-200" style={{ breakInside: "avoid" }}>
          <td className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">Com local definido</td>
          <td className="py-1.5 text-center tabular-nums text-neutral-700">{formatCount(report.locations.length)}</td>
          <td className="py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.locatedCopies)}</td>
          <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">{report.totalCopies > 0 ? report.organization : "—"}</td>
        </tr>
        {/* "Sem localização" não é recipiente: linha própria, separada e em itálico. */}
        <tr className="border-t border-dashed border-neutral-300" style={{ breakInside: "avoid" }} data-unlocated-row="">
          <td className="py-1.5 pl-2 pr-2 italic text-neutral-700">Sem localização</td>
          <td className="py-1.5 text-center text-neutral-400">—</td>
          <td className="py-1.5 text-center font-semibold tabular-nums text-neutral-900">{formatCount(report.unlocatedCopies)}</td>
          <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">{report.unlocatedShare}</td>
        </tr>
        <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
          <td className="py-1.5 pl-2 pr-2 font-bold text-neutral-900">Total do acervo físico</td>
          <td className="py-1.5 text-center text-neutral-400">—</td>
          <td className="py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.totalCopies)}</td>
          <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">{report.totalCopies > 0 ? "100,0%" : "—"}</td>
        </tr>
      </tbody>
    </table>
  );
}

function LocationTable({ report }: { report: LocationDistributionReport }) {
  return (
    <table className="mt-4 w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }} data-distribution-locations="">
      <colgroup>
        <col style={{ width: "4.75rem" }} />
        <col />
        <col style={{ width: "6.5rem" }} />
        <col style={{ width: "4.5rem" }} />
        <col style={{ width: "6.25rem" }} />
        <col style={{ width: "5.5rem" }} />
      </colgroup>
      <thead>
        <tr style={{ breakAfter: "avoid" }}>
          <th colSpan={6} scope="colgroup" className="pb-1 pl-2 pt-1 text-left font-normal">
            <SectionTitle title="Por local" detail={`${plural(report.locations.length, "local", "locais")}, do maior para o menor`} />
          </th>
        </tr>
        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
          <DataTableHeadCell className="bg-neutral-50 pl-2">Código</DataTableHeadCell>
          <DataTableHeadCell className="bg-neutral-50">Local</DataTableHeadCell>
          <DataTableHeadCell className="bg-neutral-50">Tipo</DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Exemplares
          </DataTableHeadCell>
          <DataTableHeadCell className="bg-neutral-50">
            <span className="sr-only">Comparação com o maior local</span>
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 pr-2">
            % do acervo
          </DataTableHeadCell>
        </DataTableHeadRow>
      </thead>
      <tbody>
        {report.locations.map((row, index) => (
          <tr key={row.id} className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
            <td className="truncate py-1.5 pl-2 pr-2 font-semibold tabular-nums text-neutral-700">{row.code ?? "—"}</td>
            <td className={`truncate py-1.5 pr-2 font-medium ${row.copies === 0 ? "text-neutral-500" : "text-neutral-900"}`}>{row.title}</td>
            <td className="truncate py-1.5 pr-2 text-neutral-700">{row.kindLabel}</td>
            <td className="py-1.5 text-center font-semibold tabular-nums text-neutral-900">{formatCount(row.copies)}</td>
            <td className="py-1.5 pr-3" aria-hidden="true">
              <span className="block h-1.5 rounded-full bg-neutral-100">
                {row.bar > 0 ? <span className="block h-full rounded-full bg-primary" style={{ width: `max(${row.bar}%, 2px)` }} /> : null}
              </span>
            </td>
            <td className="py-1.5 pr-2 text-center tabular-nums text-neutral-600">{row.share}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Indicator({ label, value, note, emphasis = false, warn = false }: { label: string; value: string; note: string; emphasis?: boolean; warn?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className={`font-heading text-base font-bold tabular-nums ${warn ? "text-amber-800" : "text-neutral-900"}`}>{value}</p>
      <p className="text-[9px] leading-snug text-neutral-500">{note}</p>
    </div>
  );
}
