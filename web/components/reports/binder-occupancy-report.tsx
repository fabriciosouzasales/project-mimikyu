import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { formatCount, plural } from "@/lib/reports/acervo-reports";
import { BINDER_OCCUPANCY_TITLE, type BinderOccupancyReport, type BinderOccupancyRow, binderOccupancySummaryLine } from "@/lib/reports/binder-occupancy";

/**
 * V1-14 — bloco Locais — "Capacidade e Ocupação de Fichários" (D7 §4t). Folha
 * institucional dos relatórios (A4 retrato; papel branco também no tema
 * escuro). Três níveis:
 *
 * 1. resumo — fichários físicos, capacidade configurada conhecida, bolsos
 *    ocupados (com carta · elementos visuais), reservados vazios, livres e a
 *    ocupação consolidada ENTRE os fichários com capacidade configurada, com a
 *    faixa de estados dos bolsos;
 * 2. comparativo por fichário — configuração, capacidade, estados dos bolsos,
 *    ocupação (inteiro, a regra do painel do fichário) e exemplares fora de
 *    bolsos; sem fichário digital → "capacidade desconhecida", nunca 0;
 * 3. exceções — fichários sem estrutura de bolsos e exemplares fora de bolsos,
 *    em linguagem de colecionador.
 *
 * Capacidade configurada ≠ capacidade física; bolsos ≠ exemplares (a folha diz
 * isso). Impressão: cabeçalho repetido (`<thead>`), colunas repetidas por
 * tabela, linhas indivisíveis.
 */
const STATE_COLORS = {
  cards: "hsl(var(--primary))",
  visual: "hsl(var(--primary) / 0.5)",
  reserved: "#A3A3A3",
  free: "#E5E5E5",
} as const;

export function BinderOccupancySheet({ report, issuedAt }: { report: BinderOccupancyReport; issuedAt: string }) {
  const cabecalho = (
    <RelatorioCabecalho
      titulo={BINDER_OCCUPANCY_TITLE}
      identificacaoColecao="Meus Locais de Armazenamento"
      subtitulo={`${binderOccupancySummaryLine(report)} · Emitido em ${issuedAt}`}
    />
  );
  const outside = report.rows.filter((r) => r.state !== "unlinked" && (r.outsidePockets ?? 0) > 0);
  const unlinked = report.rows.filter((r) => r.state === "unlinked");
  const noPockets = report.rows.filter((r) => r.state === "no_pockets");

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
                {report.binders === 0 ? (
                  <div className="px-2 py-10 text-center" data-binders-empty="">
                    <p className="text-sm font-semibold text-neutral-900">Nenhum fichário físico cadastrado.</p>
                    <p className="mt-2 text-xs text-neutral-600">Em Meus Locais de Armazenamento, cadastre um local do tipo Fichário físico para acompanhar sua capacidade.</p>
                  </div>
                ) : (
                  <>
                    <Summary report={report} />
                    <BinderTable rows={report.rows} />
                    <Exceptions unlinked={unlinked} outside={outside} noPockets={noPockets} />
                  </>
                )}
                <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                  <li>Capacidade = bolsos configurados no fichário digital vinculado ao fichário físico (páginas × grade) — não é uma medição do fichário real.</li>
                  <li>
                    Cada bolso conta uma vez: com carta, com imagem ou em imagem de 2 bolsos (ocupados), reservado vazio ou livre. Reservado com carta conta como &ldquo;com
                    carta&rdquo;; bolso travado continua no seu estado.
                  </li>
                  <li>Ocupação = bolsos ocupados ÷ capacidade, em número inteiro, como no painel do fichário. A consolidada soma só os fichários com capacidade configurada.</li>
                  <li>Um bolso guarda um exemplar; exemplares do fichário que não estão em bolsos aparecem como &ldquo;fora de bolsos&rdquo; e não contam como ocupação.</li>
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

function Summary({ report }: { report: BinderOccupancyReport }) {
  const hasCapacity = report.capacity > 0;
  const segments = [
    { key: "cards", label: "Com carta", value: report.cards, color: STATE_COLORS.cards },
    { key: "visual", label: "Imagens e mesclagens", value: report.visual, color: STATE_COLORS.visual },
    { key: "reserved", label: "Reservados vazios", value: report.reservedEmpty, color: STATE_COLORS.reserved },
    { key: "free", label: "Livres", value: report.free, color: STATE_COLORS.free },
  ];
  return (
    <section aria-label="Resumo da capacidade dos fichários" style={{ breakInside: "avoid" }} className="pb-2 pt-1">
      <div className="grid grid-cols-4 gap-2">
        <Indicator label="Fichários físicos" value={formatCount(report.binders)} note={`${formatCount(report.configured)} com capacidade configurada`} emphasis />
        <Indicator
          label="Capacidade configurada"
          value={hasCapacity ? formatCount(report.capacity) : "—"}
          note={hasCapacity ? `bolsos em ${plural(report.configured, "fichário", "fichários")}` : "Nenhum fichário com bolsos configurados"}
        />
        <Indicator
          label="Bolsos ocupados"
          value={hasCapacity ? formatCount(report.occupied) : "—"}
          note={hasCapacity ? `${formatCount(report.cards)} com carta · ${formatCount(report.visual)} visuais` : "—"}
        />
        <Indicator
          label="Ocupação consolidada"
          value={report.percent === null ? "—" : `${report.percent}%`}
          note="Entre os fichários com capacidade configurada"
        />
      </div>
      {hasCapacity ? (
        <div className="mt-2 rounded-md border border-neutral-200 px-3 py-2" data-binder-states="">
          <div className="flex h-2 overflow-hidden rounded-full bg-neutral-100" aria-hidden="true">
            {segments.map((s) =>
              s.value > 0 ? <span key={s.key} className="block h-full" style={{ width: `${(s.value * 100) / report.capacity}%`, backgroundColor: s.color }} /> : null,
            )}
          </div>
          <ul className="mt-1.5 flex flex-wrap gap-x-4 gap-y-0.5 text-[9px] text-neutral-600">
            {segments.map((s) => (
              <li key={s.key} className="inline-flex items-center gap-1">
                <span aria-hidden="true" className="inline-block h-2 w-2 rounded-sm" style={{ backgroundColor: s.color }} />
                {s.label} <b className="tabular-nums text-neutral-900">{formatCount(s.value)}</b>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  );
}

function BinderTable({ rows }: { rows: BinderOccupancyRow[] }) {
  return (
    <table className="mt-3 w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }} data-binder-table="">
      <colgroup>
        <col />
        <col style={{ width: "5.75rem" }} />
        <col style={{ width: "4.75rem" }} />
        <col style={{ width: "3.5rem" }} />
        <col style={{ width: "3.75rem" }} />
        <col style={{ width: "5.25rem" }} />
        <col style={{ width: "3.75rem" }} />
        <col style={{ width: "4.5rem" }} />
        <col style={{ width: "4.25rem" }} />
      </colgroup>
      <thead>
        <tr style={{ breakAfter: "avoid" }}>
          <th colSpan={9} scope="colgroup" className="pb-1 pl-2 pt-1 text-left font-normal">
            <span className="text-[11px] font-semibold text-neutral-900">
              Por fichário
              <span className="font-normal text-neutral-500"> · bolsos do fichário digital vinculado</span>
            </span>
          </th>
        </tr>
        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
          <DataTableHeadCell className="bg-neutral-50 pl-2">Fichário</DataTableHeadCell>
          <DataTableHeadCell className="bg-neutral-50">Configuração</DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Capacidade
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Carta
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50" title="Bolsos com imagem ou em imagem de 2 bolsos">
            Visuais
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Reservados
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Livres
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50">
            Ocupação
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 pr-2" title="Exemplares do fichário físico que não estão em bolsos">
            Fora de bolsos
          </DataTableHeadCell>
        </DataTableHeadRow>
      </thead>
      <tbody>
        {rows.map((row, index) => (
          <tr key={row.id} className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
            <td className="py-1.5 pl-2 pr-2">
              <p className="truncate font-semibold text-neutral-900">
                {row.code ? <span className="tabular-nums text-neutral-600">{row.code} </span> : null}
                {row.title}
              </p>
              <p className="truncate text-[9px] text-neutral-500">{plural(row.storedCopies, "exemplar guardado", "exemplares guardados")}</p>
            </td>
            {row.state === "unlinked" ? (
              <>
                <td colSpan={7} className="py-1.5 pr-2 italic text-neutral-600">
                  Capacidade desconhecida — sem fichário digital vinculado
                </td>
                <td className="py-1.5 pr-2 text-center text-neutral-400">—</td>
              </>
            ) : (
              <>
                <td className="truncate py-1.5 pr-2 tabular-nums text-neutral-700">{row.configuration}</td>
                <td className="py-1.5 text-center font-semibold tabular-nums text-neutral-900">{formatCount(row.capacity ?? 0)}</td>
                <td className="py-1.5 text-center tabular-nums text-neutral-800">{formatCount(row.cards ?? 0)}</td>
                <td className="py-1.5 text-center tabular-nums text-neutral-700">{formatCount(row.visual ?? 0)}</td>
                <td className="py-1.5 text-center tabular-nums text-neutral-700">{formatCount(row.reservedEmpty ?? 0)}</td>
                <td className="py-1.5 text-center tabular-nums text-neutral-700">{formatCount(row.free ?? 0)}</td>
                <td className="py-1.5 text-center font-bold tabular-nums text-neutral-900">{row.percent === null ? <span className="font-normal italic text-neutral-500">sem bolsos</span> : `${row.percent}%`}</td>
                <td className={`py-1.5 pr-2 text-center tabular-nums ${(row.outsidePockets ?? 0) > 0 ? "font-semibold text-amber-800" : "text-neutral-500"}`}>
                  {formatCount(row.outsidePockets ?? 0)}
                </td>
              </>
            )}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Exceptions({ unlinked, outside, noPockets }: { unlinked: BinderOccupancyRow[]; outside: BinderOccupancyRow[]; noPockets: BinderOccupancyRow[] }) {
  const none = unlinked.length === 0 && outside.length === 0 && noPockets.length === 0;
  const name = (r: BinderOccupancyRow) => (r.code ? `${r.code} — ${r.title}` : r.title);
  return (
    <section aria-label="Exceções e qualidade da informação" className="mt-4" style={{ breakInside: "avoid" }} data-binder-exceptions="">
      <p className="pb-1 pl-2 text-[11px] font-semibold text-neutral-900">Exceções e qualidade da informação</p>
      {none ? (
        <p className="rounded-md border border-neutral-200 px-3 py-2 text-[10px] text-neutral-600">
          Todos os fichários físicos têm fichário digital com bolsos configurados, e todos os exemplares guardados neles estão em bolsos.
        </p>
      ) : (
        <div className="space-y-2">
          {unlinked.length > 0 ? (
            <Callout title={`Sem estrutura de bolsos · ${plural(unlinked.length, "fichário", "fichários")}`}>
              <p>Estes fichários ainda não têm uma estrutura digital de páginas e bolsos vinculada. Por isso, não é possível calcular sua capacidade ou ocupação.</p>
              <ul className="mt-1 space-y-0.5">
                {unlinked.map((r) => (
                  <li key={r.id} className="flex justify-between gap-3">
                    <span className="truncate text-neutral-900">{name(r)}</span>
                    <span className="shrink-0 tabular-nums">{plural(r.storedCopies, "exemplar em fichário sem estrutura de bolsos", "exemplares em fichário sem estrutura de bolsos")}</span>
                  </li>
                ))}
              </ul>
            </Callout>
          ) : null}
          {noPockets.length > 0 ? (
            <Callout title={`Fichário digital sem bolsos · ${plural(noPockets.length, "fichário", "fichários")}`}>
              <p>O fichário digital existe, mas ainda não tem páginas — não há bolsos para medir a ocupação.</p>
              <ul className="mt-1 space-y-0.5">
                {noPockets.map((r) => (
                  <li key={r.id} className="truncate text-neutral-900">
                    {name(r)}
                  </li>
                ))}
              </ul>
            </Callout>
          ) : null}
          {outside.length > 0 ? (
            <Callout title={`Exemplares fora de bolsos · ${plural(outside.reduce((n, r) => n + (r.outsidePockets ?? 0), 0), "exemplar", "exemplares")}`}>
              <p>Guardados no fichário físico, mas sem bolso no fichário digital. Não contam como ocupação.</p>
              <ul className="mt-1 space-y-0.5">
                {outside.map((r) => (
                  <li key={r.id} className="flex justify-between gap-3">
                    <span className="truncate text-neutral-900">{name(r)}</span>
                    <span className="shrink-0 tabular-nums">{plural(r.outsidePockets ?? 0, "exemplar fora de bolsos", "exemplares fora de bolsos")}</span>
                  </li>
                ))}
              </ul>
            </Callout>
          ) : null}
        </div>
      )}
    </section>
  );
}

function Callout({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-md border border-neutral-200 border-l-4 border-l-amber-500 px-3 py-2 text-[10px] leading-snug text-neutral-600" style={{ breakInside: "avoid" }}>
      <p className="mb-0.5 font-semibold text-neutral-900">{title}</p>
      {children}
    </div>
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
