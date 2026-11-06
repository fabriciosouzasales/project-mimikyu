import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural } from "@/lib/reports/acervo-reports";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import {
  type FavoriteReportSet,
  type FavoritesReport,
  collectorText,
  favoritedAtText,
  favoritesCoverageText,
  favoritesOwnedText,
  favoritesSummaryLine,
} from "@/lib/reports/favorites-report";

/**
 * V1-14 R1-D — folha "Minhas favoritas" (relatório 04 do Meu acervo). Mesma folha institucional dos
 * relatórios R1-B/R1-C (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`; tela =
 * impressão, com miniatura da carta). Indicadores → um grupo por Card Set (nome, pt-BR) → uma linha por carta
 * favorita (número, nome, referência NM, exemplares no acervo, data em que foi favoritada) →
 * soma das referências e nota metodológica. Sem variante nem idioma: a unidade é a carta.
 *
 * Cabeçalho, indicadores e títulos das colunas no `<thead>` (repetem em toda folha impressa);
 * cada Card Set é um `<tbody>` (título preso às linhas; grupos curtos não se partem).
 */
const COLUMNS = 5;
const KEEP_TOGETHER_LINES = 12;
/** Teto de miniaturas carregadas de imediato (tela e impressão). */
export const EAGER_IMAGES_MAX = 300;

export function FavoritesReportSheet({ report, issuedAt }: { report: FavoritesReport; issuedAt: string }) {
  const entry = acervoReport("favorites");
  const cabecalho = (
    <RelatorioCabecalho
      titulo={entry.title}
      identificacaoColecao="Cartas favoritas"
      subtitulo={`${favoritesSummaryLine(report)} · Emitido em ${issuedAt}`}
    />
  );

  if (report.favoriteCount === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0">
          <p className="text-sm font-semibold text-neutral-900">Você ainda não tem cartas favoritas.</p>
          <p className="mt-2 text-xs text-neutral-600">Toque no coração de qualquer carta para reuni-la aqui — vale também para cartas que você ainda não tem.</p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  // Até EAGER_IMAGES_MAX favoritas as miniaturas carregam de imediato, para a impressão sair completa
  // mesmo sem rolar a folha; acima disso, sob demanda (proteção de rede em listas grandes).
  const eagerImages = report.favoriteCount <= EAGER_IMAGES_MAX;
  const totalText = report.totalReferenceBrl === null ? "Sem cotação" : formatBrl(report.totalReferenceBrl);

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <colgroup>
            <col style={{ width: "4.75rem" }} />
            <col />
            <col style={{ width: "6.25rem" }} />
            <col style={{ width: "5.25rem" }} />
            <col style={{ width: "6.25rem" }} />
          </colgroup>
          <thead>
            <tr>
              <th colSpan={COLUMNS} className="p-0 font-normal">
                <div className="-mx-6 print:mx-0">{cabecalho}</div>
              </th>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <th colSpan={COLUMNS} className="p-0 pb-3 pt-1 text-left font-normal">
                <section aria-label="Indicadores das favoritas" className="grid grid-cols-2 gap-2 sm:grid-cols-4 print:grid-cols-4">
                  <Indicator label="Cartas favoritas" value={formatCount(report.favoriteCount)} note="Uma por carta, sem variante" emphasis />
                  <Indicator label="Card Sets" value={formatCount(report.setCount)} note="Representados nas favoritas" />
                  <Indicator label="No acervo" value={`${formatCount(report.ownedCount)} de ${formatCount(report.favoriteCount)}`} note={favoritesOwnedText(report)} />
                  <Indicator label="Soma das referências" value={totalText} note={favoritesCoverageText(report)} />
                </section>
              </th>
            </tr>
            <DataTableHeadRow className="border-neutral-200 text-neutral-500">
              <DataTableHeadCell className="bg-neutral-50 pl-2">Número</DataTableHeadCell>
              <DataTableHeadCell className="bg-neutral-50">Carta</DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                Referência NM
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2">
                No acervo
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2 last:pr-2">
                Favoritada em
              </DataTableHeadCell>
            </DataTableHeadRow>
          </thead>
          {report.sets.map((set) => (
            <SetGroup key={set.code} set={set} eagerImages={eagerImages} />
          ))}
          <tbody>
            <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
              <td colSpan={2} className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">
                Soma das referências
                <span className="ml-1 font-normal text-neutral-500">· {favoritesCoverageText(report)}</span>
              </td>
              <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{totalText}</td>
              <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{formatCount(report.ownedCount)}</td>
              <td className="px-2 py-1.5 text-center text-neutral-400">—</td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={COLUMNS} className="p-0">
                <ul className="mt-3 space-y-1 border-t border-neutral-200 py-3 text-[9px] leading-snug text-neutral-500">
                  <li>
                    Favorita é uma preferência por carta, independente de posse: pode estar ou não no seu acervo. Uma linha por carta, sem variante nem
                    idioma.
                  </li>
                  <li>
                    Referência NM = referência geral de mercado Near Mint da carta (impressão preferencial: Normal, depois Holofoil e as demais), em
                    reais (ou preço definido pela curadoria); valores em dólar convertidos pela PTAX da data da observação. Não é o preço de uma
                    variante possuída.
                  </li>
                  <li>
                    No acervo = exemplares físicos seus da carta, somando todas as variantes e idiomas; &ldquo;—&rdquo; quando você não possui
                    nenhum. A referência não é multiplicada pelos exemplares.
                  </li>
                  <li>
                    Soma das referências = uma referência por carta cotada; cartas sem cotação ficam fora (nunca contam como zero). Não representa
                    patrimônio físico nem valor de revenda.
                  </li>
                  <li>Só cartas ativas do catálogo; o favorito de uma carta desativada continua guardado, mas não aparece aqui.</li>
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

function SetGroup({ set, eagerImages }: { set: FavoriteReportSet; eagerImages: boolean }) {
  return (
    <tbody style={{ breakInside: set.cards.length <= KEEP_TOGETHER_LINES ? "avoid" : "auto" }}>
      <tr style={{ breakInside: "avoid", breakAfter: "avoid" }}>
        <th colSpan={COLUMNS} scope="colgroup" className="pb-1 pl-2 pt-3 text-left text-[11px] font-semibold text-neutral-900">
          {set.name} <span className="whitespace-nowrap font-normal text-neutral-500">· {set.code} · {plural(set.cards.length, "favorita", "favoritas")}</span>
        </th>
      </tr>
      {set.cards.map((card, index) => (
        <tr
          key={card.cardId}
          className="border-t border-neutral-100"
          style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}
        >
          <td className="py-1 pl-2 pr-2 tabular-nums text-neutral-600">{collectorText(card)}</td>
          <td className="py-1 pr-2 align-middle">
            <span className="flex items-center gap-2">
              {/* Miniatura na tela e na impressão (proporção da carta, 63:88; cor exata pela folha). */}
              <span aria-hidden="true" className="h-[34px] w-[24px] shrink-0 overflow-hidden rounded-[2px] bg-neutral-100">
                {card.imageUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador de imagens configurado (mesma regra da Pesquisa)
                  <img src={card.imageUrl} alt="" width={24} height={34} loading={eagerImages ? "eager" : "lazy"} decoding="async" className="h-full w-full object-cover" />
                ) : null}
              </span>
              <span className="font-semibold text-neutral-900">{card.name}</span>
            </span>
          </td>
          <td className="px-2 py-1 text-center tabular-nums text-neutral-900">
            {card.referenceBrl === null ? <span className="text-neutral-400">Sem cotação</span> : formatBrl(card.referenceBrl)}
          </td>
          <td className={`px-2 py-1 text-center tabular-nums ${card.ownedCopies > 0 ? "text-neutral-900" : "text-neutral-400"}`}>
            {card.ownedCopies > 0 ? formatCount(card.ownedCopies) : "—"}
          </td>
          <td className="px-2 py-1 text-center tabular-nums text-neutral-600">{favoritedAtText(card.favoritedAt)}</td>
        </tr>
      ))}
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
