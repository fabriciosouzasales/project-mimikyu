import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { formatCount, plural } from "@/lib/reports/acervo-reports";
import { COLLECTION_COMPOSITION_TITLE, type CollectionCompositionReport, type CompositionKind, compositionNotes } from "@/lib/reports/collection-composition";
import { type DistributionBand, type DistributionDimension, distributionBarPercent, distributionShareText } from "@/lib/reports/distribution";
import { SetComposition } from "./distribution-report";

const KIND_TEXT: Record<CompositionKind, string> = { POKEDEX: "Pokédex", FREE: "Coleção livre" };
const KEEP_TOGETHER_ROWS = 24;

/**
 * Cada perspectiva com um tom próprio na barra (legível também sem cor: o título da seção, a ordem e os
 * números dizem tudo). A faixa de maior concentração recebe o dourado MMKYU em todas.
 */
const SECTIONS = {
  set: { title: "Por Card Set", hint: "Do Set com mais exemplares para o com menos.", tone: "bg-neutral-500" },
  rarity: { title: "Por raridade", hint: "Na ordem oficial das raridades do catálogo.", tone: "bg-neutral-400" },
  language: { title: "Por idioma", hint: "Idioma registrado em cada exemplar.", tone: "bg-neutral-300" },
} as const;

/**
 * F2-3 (D7 §4q) — folha "Composição da coleção" (Pokédex e Coleção livre). Mesma folha institucional dos
 * relatórios contextuais (papel branco também no tema escuro; rodapé de impressão pela casca). Indicadores
 * (exemplares, Card Sets, raridades, idiomas) → resumo Top 10 + Demais (só com mais de 10 Sets, o mesmo da
 * R1-H) → três tabelas com a barra de participação FÍSICA integrada à linha (Faixa · Exemplares · %) →
 * notas. Sem valores, sem completude. Na impressão, o cabeçalho institucional repete em todas as folhas
 * (`<thead>` da tabela externa) e cada tabela repete título e colunas ao continuar.
 */
export function CollectionCompositionSheet({
  collectionName,
  kind,
  satisfiedSpecies,
  report,
  issuedAt,
}: {
  collectionName: string;
  kind: CompositionKind;
  satisfiedSpecies: number | null;
  report: CollectionCompositionReport;
  issuedAt: string;
}) {
  const cabecalho = (
    <RelatorioCabecalho
      titulo={COLLECTION_COMPOSITION_TITLE}
      identificacaoColecao={collectionName}
      subtitulo={`${KIND_TEXT[kind]} · ${plural(report.copies, "exemplar alocado", "exemplares alocados")} · Emitido em ${issuedAt}`}
    />
  );

  if (report.copies === 0 && report.complete) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0" data-composition-empty>
          <p className="text-sm font-semibold text-neutral-900">Esta coleção ainda não tem exemplares alocados.</p>
          <p className="mt-2 text-xs text-neutral-600">
            {kind === "POKEDEX"
              ? "Quando você vincular cartas às espécies, a composição por Set, raridade e idioma aparece aqui."
              : "Quando você adicionar cartas a esta coleção, a composição por Set, raridade e idioma aparece aqui."}
          </p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  const { distribution } = report;
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
                <section aria-label="Indicadores da composição" className="grid grid-cols-2 gap-2 pb-3 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
                  <Indicator label="Exemplares" value={formatCount(report.copies)} note={`em ${plural(report.items, "item", "itens")}`} emphasis />
                  <Indicator label="Card Sets" value={formatCount(report.sets)} note="representados" />
                  <Indicator label="Raridades" value={formatCount(report.rarities)} note="representadas" />
                  <Indicator label="Idiomas" value={formatCount(report.languages)} note="representados" />
                </section>

                <SetComposition report={distribution} />

                <ShareTable section="set" dimension={distribution.sets} />
                {distribution.rarities ? (
                  <ShareTable section="rarity" dimension={distribution.rarities} />
                ) : (
                  <section className="mt-4 rounded-md border border-neutral-200 px-3 py-3 text-[10px] text-neutral-600" style={{ breakInside: "avoid" }}>
                    <h3 className="text-[11px] font-semibold text-neutral-900">Por raridade</h3>
                    <p className="mt-1">O catálogo de raridades não pôde ser carregado agora; esta seção volta quando o relatório for aberto de novo.</p>
                  </section>
                )}
                <ShareTable section="language" dimension={distribution.languages} />

                <ul className="mt-3 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                  {compositionNotes(kind, satisfiedSpecies).map((note) => (
                    <li key={note}>{note}</li>
                  ))}
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

function ShareTable({ section, dimension }: { section: keyof typeof SECTIONS; dimension: DistributionDimension }) {
  const meta = SECTIONS[section];
  return (
    <table className="mt-4 w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }} data-composition-section={section}>
      <colgroup>
        <col />
        <col style={{ width: "5.5rem" }} />
        <col style={{ width: "4.25rem" }} />
      </colgroup>
      <thead>
        <tr style={{ breakAfter: "avoid" }}>
          <th colSpan={3} scope="colgroup" className="pb-1 pl-2 pt-1 text-left font-normal">
            <span className="text-[11px] font-semibold text-neutral-900">{meta.title}</span>
            <span className="text-neutral-500"> · {plural(dimension.bands.length, "faixa", "faixas")}</span>
            <span className="block text-[9px] text-neutral-500">{meta.hint}</span>
          </th>
        </tr>
        <DataTableHeadRow className="border-neutral-200 text-neutral-500">
          <DataTableHeadCell className="bg-neutral-50 pl-2">Faixa</DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-1">
            Exemplares
          </DataTableHeadCell>
          <DataTableHeadCell align="center" className="bg-neutral-50 px-1 last:pr-2" title="Participação nos exemplares desta coleção" aria-label="% dos exemplares da coleção">
            %
          </DataTableHeadCell>
        </DataTableHeadRow>
      </thead>
      <tbody style={{ breakInside: dimension.bands.length <= KEEP_TOGETHER_ROWS ? "avoid" : "auto" }}>
        {dimension.bands.map((band, index) => (
          <BandRow key={band.key} band={band} index={index} tone={meta.tone} />
        ))}
        <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
          <td className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">Total</td>
          <td className="px-1 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(dimension.copies)}</td>
          <td className="px-1 py-1.5 text-center font-bold tabular-nums text-neutral-900">{dimension.copies > 0 ? "100,0%" : "—"}</td>
        </tr>
      </tbody>
    </table>
  );
}

function BandRow({ band, index, tone }: { band: DistributionBand; index: number; tone: string }) {
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
          {bar > 0 ? <span className={`block h-full rounded-full ${band.top ? "bg-primary" : tone}`} style={{ width: `${bar}%` }} /> : null}
        </span>
      </td>
      <td className="px-1 py-1 text-center tabular-nums text-neutral-900">{formatCount(band.copies)}</td>
      <td className="px-1 py-1 text-center tabular-nums text-neutral-900">{distributionShareText(band.copiesShare)}</td>
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
