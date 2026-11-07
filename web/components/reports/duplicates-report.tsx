import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural } from "@/lib/reports/acervo-reports";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import { valueShareText } from "@/lib/reports/acervo-value";
import {
  type DuplicateLine,
  type DuplicateSet,
  type DuplicatesReport,
  duplicateCollectorText,
  duplicateFlags,
  duplicateAdditionalLocationsText,
  duplicateVariantText,
  duplicatesCountNote,
  duplicatesCoverageNote,
  duplicatesSetLine,
  duplicatesSummaryLine,
  duplicatesValueText,
} from "@/lib/reports/duplicates";
import { topObservedText } from "@/lib/reports/top-cards";
import { PrintImageGate } from "./print-image-gate";

/**
 * V1-14 R1-G — folha "Cartas repetidas" (relatório 07 do Meu acervo). Mesma folha institucional dos
 * demais relatórios (rodapé de impressão institucional pela casca em toda página). Cabeçalho
 * institucional e indicadores só no início (1ª página) → um grupo por Card Set (identificação,
 * itens, adicionais e subtotal) → uma linha por grupo variante + idioma com 2+ exemplares (carta:
 * nome, variante · idioma, onde estão as cópias ADICIONAIS) → total e nota metodológica. Nas
 * páginas seguintes, o `<thead>` repete só a identificação curta "Cartas repetidas · Meu acervo" e
 * os títulos das colunas; linhas indivisíveis; Sets curtos não se partem.
 *
 * Miniaturas 24 × 34 na tela e na impressão: imediatas até `EAGER_IMAGES_MAX` linhas; acima disso,
 * sob demanda na tela e preparadas pelo botão Imprimir (`PrintImageGate`/`preparePrintImages`) —
 * nunca impressas como quadro vazio por carregamento pendente.
 */
const COLUMNS = 5;
const KEEP_TOGETHER_LINES = 12;
export const EAGER_IMAGES_MAX = 300;

export function DuplicatesSheet({ report, issuedAt }: { report: DuplicatesReport; issuedAt: string }) {
  const entry = acervoReport("duplicates");
  const cabecalho = (
    <RelatorioCabecalho titulo={entry.title} identificacaoColecao="Meu acervo" subtitulo={`${duplicatesSummaryLine(report)} · Emitido em ${issuedAt}`} />
  );

  if (report.repeatedGroups === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0">
          <p className="text-sm font-semibold text-neutral-900">Nenhuma carta repetida no seu acervo.</p>
          <p className="mt-2 text-xs text-neutral-600">Cada variante e idioma tem um único exemplar. Quando houver mais de um, ele aparece aqui.</p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  const partial = report.unavailableAdditional > 0;
  const totalText = duplicatesValueText(report.additionalBrl, partial, formatBrl);
  const eagerImages = report.repeatedGroups <= EAGER_IMAGES_MAX;

  return (
    <PrintImageGate>
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 print:px-0">
          <section aria-label="Indicadores das cartas repetidas" className="grid grid-cols-2 gap-2 pb-3 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
            <Indicator label="Itens repetidos" value={formatCount(report.repeatedGroups)} note={duplicatesCountNote(report)} />
            <Indicator label="Cópias adicionais" value={formatCount(report.additionalCopies)} emphasis />
            <Indicator label="Valor das adicionais" value={totalText} note={`${valueShareText(report.share)} do acervo cotado`} />
            <Indicator
              label="Cobertura de preços"
              value={`${formatCount(report.pricedAdditional)} / ${formatCount(report.additionalCopies)}`}
              note={duplicatesCoverageNote(report)}
            />
          </section>
          <table className="w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
            <colgroup>
              <col style={{ width: "4.75rem" }} />
              <col />
              <col style={{ width: "4.75rem" }} />
              <col style={{ width: "6.75rem" }} />
              <col style={{ width: "6rem" }} />
            </colgroup>
            <thead>
              {/* Só na impressão: identificação curta que se repete no topo de cada página (o cabeçalho completo fica na 1ª). */}
              <tr className="hidden print:table-row">
                <th colSpan={COLUMNS} className="pb-1 pl-2 text-left text-[9px] font-semibold uppercase tracking-wide text-neutral-500">
                  {entry.title} · Meu acervo
                </th>
              </tr>
              <DataTableHeadRow className="border-neutral-200 text-neutral-500">
                <DataTableHeadCell className="bg-neutral-50 pl-2">Número</DataTableHeadCell>
                <DataTableHeadCell className="bg-neutral-50">Carta</DataTableHeadCell>
                <DataTableHeadCell align="center" className="bg-neutral-50 px-1">
                  Cópias adicionais
                </DataTableHeadCell>
                <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                  Referência NM
                </DataTableHeadCell>
                <DataTableHeadCell align="center" className="bg-neutral-50 px-2 last:pr-2">
                  Valor das adicionais
                </DataTableHeadCell>
              </DataTableHeadRow>
            </thead>
            {report.sets.map((set) => (
              <SetGroup key={set.code} set={set} eagerImages={eagerImages} />
            ))}
            <tbody>
              <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
                <td colSpan={2} className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">
                  Total das cartas repetidas
                  <span className="ml-1 font-normal text-neutral-500">· {plural(report.repeatedGroups, "item", "itens")}</span>
                </td>
                <td className="px-1 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.additionalCopies)}</td>
                <td className="px-2 py-1.5 text-center text-neutral-400">—</td>
                <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{totalText}</td>
              </tr>
              <tr style={{ breakInside: "avoid" }}>
                <td colSpan={COLUMNS} className="p-0">
                  <ul className="mt-2 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500">
                    <li>
                      Todo o acervo físico, esteja o exemplar em uma coleção ou não. Repetido = mesma variante e idioma com dois ou mais exemplares;
                      variantes ou idiomas diferentes da mesma carta são itens distintos. Cópias adicionais = exemplares do item − 1: uma quantidade
                      calculada, sem apontar qual exemplar é &ldquo;o adicional&rdquo;; o total confere com as repetidas do resumo do acervo. Cópia
                      adicional é contagem: não indica disponibilidade para venda, troca ou reserva.
                    </li>
                    <li>
                      Locais: onde estão as cópias adicionais, por convenção do relatório (nada muda no acervo). Um exemplar de cada item é a
                      unidade de referência — de preferência um exemplar posicionado no fichário digital; sem nenhum posicionado, o primeiro
                      recipiente por nome; os demais são as adicionais, com a quantidade por recipiente e as páginas do fichário quando
                      conhecidas. Locais sem adicionais não aparecem; a soma é sempre o total de adicionais do item. &ldquo;Sem local
                      definido&rdquo;: exemplares sem recipiente; &ldquo;página não identificada&rdquo;: há adicionais no fichário da referência,
                      mas não é possível saber em qual página.
                    </li>
                    <li>
                      Valor das adicionais = referência de mercado Near Mint (NM) unitária × cópias adicionais (a primeira unidade não entra);
                      participação sobre a mesma base do Valor estimado total. Não considera a condição física do exemplar; não é avaliação nem preço de
                      venda. Dólar convertido pela PTAX da data da observação.
                    </li>
                    <li>
                      Sem cotação: o item continua listado, fora do valor (nunca zero). &ldquo;Preço geral da carta&rdquo;: a variante não tem cotação
                      própria · &ldquo;Desatualizada&rdquo;: observação com mais de 14 dias. Ordem: Card Sets do mais recente ao mais antigo; dentro do Set, número, variante e idioma.
                    </li>
                  </ul>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    </PrintImageGate>
  );
}

function SetGroup({ set, eagerImages }: { set: DuplicateSet; eagerImages: boolean }) {
  const subtotal = duplicatesValueText(set.subtotalBrl, set.partial, formatBrl);
  return (
    <tbody style={{ breakInside: set.lines.length <= KEEP_TOGETHER_LINES ? "avoid" : "auto" }}>
      <tr style={{ breakInside: "avoid", breakAfter: "avoid" }}>
        <th colSpan={COLUMNS} scope="colgroup" className="pb-1 pl-2 pr-2 pt-3 text-left text-[11px] font-semibold text-neutral-900">
          <span className="flex items-baseline justify-between gap-3">
            <span>
              {set.name} <span className="whitespace-nowrap font-normal text-neutral-500">· {set.code} · {duplicatesSetLine(set)}</span>
            </span>
            <span className="whitespace-nowrap tabular-nums">{subtotal}</span>
          </span>
        </th>
      </tr>
      {set.lines.map((line, index) => (
        <DuplicateRow key={`${line.cardVariantId}.${line.languageCode}`} line={line} index={index} eagerImages={eagerImages} />
      ))}
    </tbody>
  );
}

function DuplicateRow({ line, index, eagerImages }: { line: DuplicateLine; index: number; eagerImages: boolean }) {
  const flags = duplicateFlags(line);
  return (
    <tr className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
      <td className="py-1 pl-2 pr-2 tabular-nums text-neutral-600">{duplicateCollectorText(line)}</td>
      <td className="py-1 pr-2 align-middle">
        <span className="flex items-center gap-2">
          {/* Miniatura na tela e na impressão (proporção da carta, 63:88; quadro vazio = carta sem imagem). */}
          <span aria-hidden="true" className="h-[34px] w-[24px] shrink-0 overflow-hidden rounded-[2px] border border-neutral-200 bg-neutral-100">
            {line.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador de imagens configurado (mesma regra da Pesquisa)
              <img src={line.imageUrl} alt="" width={24} height={34} loading={eagerImages ? "eager" : "lazy"} decoding="async" className="h-full w-full object-cover" />
            ) : null}
          </span>
          <span className="min-w-0 leading-snug">
            <span className="block font-semibold text-neutral-900">{line.cardName}</span>
            <span className="block text-[9px] text-neutral-500">{duplicateVariantText(line)}</span>
            <span className="block text-[9px] text-neutral-600">{duplicateAdditionalLocationsText(line.additionalLocations)}</span>
          </span>
        </span>
      </td>
      <td className="px-1 py-1 text-center font-semibold tabular-nums text-neutral-900">{formatCount(line.additional)}</td>
      <td className="px-2 py-1 text-center align-middle">
        {line.reference.kind === "priced" ? (
          <>
            <span className="block tabular-nums text-neutral-900">{formatBrl(line.reference.unitBrl)}</span>
            <span className="block text-[8.5px] text-neutral-500">{topObservedText(line.reference)}</span>
            {flags.length > 0 ? <span className="block text-[8.5px] font-medium text-neutral-700">{flags.join(" · ")}</span> : null}
          </>
        ) : line.reference.kind === "unavailable" ? (
          <span className="italic text-neutral-500">Indisponível</span>
        ) : (
          <span className="text-neutral-400">Sem cotação</span>
        )}
      </td>
      <td className="px-2 py-1 text-center tabular-nums text-neutral-700">{line.additionalBrl === null ? <span className="text-neutral-400">—</span> : formatBrl(line.additionalBrl)}</td>
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
