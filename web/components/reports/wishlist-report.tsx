import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { DataTableHeadCell, DataTableHeadRow } from "@/components/ui/data-table";
import { acervoReport, formatCount, plural } from "@/lib/reports/acervo-reports";
import { formatBrl } from "@/lib/reports/acervo-set-inventory";
import {
  type WishReportLine,
  type WishReportSet,
  type WishlistReport,
  wishCollectorText,
  wishCoverageText,
  wishOwnershipText,
  wishValueText,
  wishVariantText,
  wishedAtText,
  wishlistSummaryLine,
} from "@/lib/reports/wishlist-report";

/**
 * V1-14 R1-E — folha "Minha Lista de Desejos" (relatório 05 do Meu acervo). Mesma folha
 * institucional de "Minhas favoritas" (`RelatorioFolha` + `RelatorioCabecalho` + `RelatorioRodape`;
 * tela = impressão, com miniatura da carta). Indicadores → um grupo por Card Set → uma linha por
 * DESEJO (variante + idioma) → referência pendente, referência de toda a lista e nota
 * metodológica. Sem quantidade, prioridade, preço-alvo, ranking nem relação com coleções.
 *
 * Cabeçalho, indicadores e títulos das colunas no `<thead>` (repetem em toda folha impressa);
 * cada Card Set é um `<tbody>` (título preso às linhas; grupos curtos não se partem).
 */
const COLUMNS = 5;
const KEEP_TOGETHER_LINES = 12;
/** Teto de miniaturas carregadas de imediato (tela e impressão) — o mesmo de Minhas favoritas. */
export const EAGER_IMAGES_MAX = 300;

export function WishlistReportSheet({ report, issuedAt }: { report: WishlistReport; issuedAt: string }) {
  const entry = acervoReport("wishlist");
  const cabecalho = (
    <RelatorioCabecalho
      titulo={entry.title}
      identificacaoColecao="Lista de desejos"
      subtitulo={`${wishlistSummaryLine(report)} · Emitido em ${issuedAt}`}
    />
  );

  if (report.entryCount === 0) {
    return (
      <RelatorioFolha>
        {cabecalho}
        <div className="px-6 py-10 text-center print:px-0">
          <p className="text-sm font-semibold text-neutral-900">Sua lista de desejos está vazia.</p>
          <p className="mt-2 text-xs text-neutral-600">Toque no marcador de qualquer carta para guardar a variante que você quer conseguir.</p>
        </div>
        <RelatorioRodape />
      </RelatorioFolha>
    );
  }

  // Até EAGER_IMAGES_MAX desejos as miniaturas carregam de imediato, para a impressão sair completa
  // mesmo sem rolar a folha; acima disso, sob demanda (fallback explícito na nota metodológica).
  const eagerImages = report.entryCount <= EAGER_IMAGES_MAX;
  const pendingText = wishValueText(report.pending, formatBrl);
  const allText = wishValueText(report.all, formatBrl);

  return (
    <RelatorioFolha>
      <div className="px-6 print:px-0">
        <table className="w-full text-left text-[10px]" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <colgroup>
            <col style={{ width: "4.75rem" }} />
            <col />
            <col style={{ width: "6.25rem" }} />
            <col style={{ width: "7.75rem" }} />
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
                <section aria-label="Indicadores da lista de desejos" className="grid grid-cols-2 gap-2 sm:grid-cols-4 print:grid-cols-4">
                  <Indicator
                    label="Desejos"
                    value={formatCount(report.entryCount)}
                    note="Cartas na sua lista de desejos"
                  />
                  <Indicator
                    label="Pendentes"
                    value={`${formatCount(report.pendingCount)} de ${formatCount(report.entryCount)}`}
                    note="Não possui a variante desejada"
                  />
                  <Indicator label="Card Sets" value={formatCount(report.setCount)} note="Representados na lista" />
                  <Indicator label="Referência NM pendente" value={pendingText} note={wishCoverageText(report.pending)} emphasis />
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
                Situação no acervo
              </DataTableHeadCell>
              <DataTableHeadCell align="center" className="bg-neutral-50 px-2 last:pr-2">
                Desejado em
              </DataTableHeadCell>
            </DataTableHeadRow>
          </thead>
          {report.sets.map((set) => (
            <SetGroup key={set.code} set={set} eagerImages={eagerImages} />
          ))}
          <tbody>
            <tr className="border-t-2 border-neutral-300" style={{ breakInside: "avoid" }}>
              <td colSpan={2} className="py-1.5 pl-2 pr-2 font-semibold text-neutral-900">
                Referência NM pendente
                <span className="ml-1 font-normal text-neutral-500">· {wishCoverageText(report.pending)}</span>
              </td>
              <td className="px-2 py-1.5 text-center font-bold tabular-nums text-neutral-900">{pendingText}</td>
              <td className="px-2 py-1.5 text-center tabular-nums text-neutral-900">{plural(report.pendingCount, "pendente", "pendentes")}</td>
              <td className="px-2 py-1.5 text-center text-neutral-400">—</td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={2} className="py-1.5 pl-2 pr-2 text-neutral-700">
                Referência de toda a lista
                <span className="ml-1 text-neutral-500">· {wishCoverageText(report.all)}</span>
              </td>
              <td className="px-2 py-1.5 text-center font-semibold tabular-nums text-neutral-700">{allText}</td>
              <td className="px-2 py-1.5 text-center tabular-nums text-neutral-700">{plural(report.entryCount, "desejo", "desejos")}</td>
              <td className="px-2 py-1.5 text-center text-neutral-400">—</td>
            </tr>
            <tr style={{ breakInside: "avoid" }}>
              <td colSpan={COLUMNS} className="p-0">
                <ul className="mt-3 space-y-1 border-t border-neutral-200 py-3 text-[9px] leading-snug text-neutral-500">
                  <li>
                    Desejo = uma variante com um idioma (ou &ldquo;qualquer idioma&rdquo;); a mesma variante em dois idiomas são dois desejos. A lista não tem
                    quantidade, prioridade nem preço-alvo, e não depende das suas coleções.
                  </li>
                  <li>
                    Pendente = desejo cuja situação não é &ldquo;Já no acervo&rdquo; (inclui &ldquo;No acervo em outro idioma&rdquo; e &ldquo;Você tem
                    outra variante&rdquo;). A situação é calculada a partir do seu acervo físico, sem contar exemplares.
                  </li>
                  <li>
                    Referência NM = referência de mercado Near Mint da variante, em reais (valores em dólar pela PTAX da data da observação); desejos em
                    outro idioma usam a referência internacional. Cada variante distinta entra uma única vez nas somas, mesmo com mais de um idioma
                    desejado.
                  </li>
                  <li>
                    Variantes sem cotação ficam fora das somas (nunca contam como zero); &ldquo;Indisponível&rdquo; = preço que não pôde ser carregado
                    agora, e o total marcado &ldquo;(parcial)&rdquo; não é definitivo. A referência não é gasto realizado, orçamento nem preço de compra.
                  </li>
                  <li>Variante desativada no catálogo continua na lista, sinalizada.</li>
                  {eagerImages ? null : (
                    <li>
                      Lista com mais de {formatCount(EAGER_IMAGES_MAX)} desejos: as miniaturas carregam conforme a rolagem; as que não tiverem carregado
                      saem na impressão como um quadro vazio — o texto do relatório não é afetado.
                    </li>
                  )}
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

function SetGroup({ set, eagerImages }: { set: WishReportSet; eagerImages: boolean }) {
  return (
    <tbody style={{ breakInside: set.lines.length <= KEEP_TOGETHER_LINES ? "avoid" : "auto" }}>
      <tr style={{ breakInside: "avoid", breakAfter: "avoid" }}>
        <th colSpan={COLUMNS} scope="colgroup" className="pb-1 pl-2 pt-3 text-left text-[11px] font-semibold text-neutral-900">
          {set.name} <span className="whitespace-nowrap font-normal text-neutral-500">· {set.code} · {plural(set.lines.length, "desejo", "desejos")}</span>
        </th>
      </tr>
      {set.lines.map((line, index) => (
        <WishRow key={line.entryId} line={line} index={index} eagerImages={eagerImages} />
      ))}
    </tbody>
  );
}

function WishRow({ line, index, eagerImages }: { line: WishReportLine; index: number; eagerImages: boolean }) {
  const satisfied = !line.pending;
  return (
    <tr className="border-t border-neutral-100" style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED", breakInside: "avoid" }}>
      <td className="py-1 pl-2 pr-2 tabular-nums text-neutral-600">{wishCollectorText(line)}</td>
      <td className="py-1 pr-2 align-middle">
        <span className="flex items-center gap-2">
          {/* Miniatura na tela e na impressão (proporção da carta, 63:88; quadro vazio = sem imagem). */}
          <span aria-hidden="true" className="h-[34px] w-[24px] shrink-0 overflow-hidden rounded-[2px] border border-neutral-200 bg-neutral-100">
            {line.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element -- bucket público, sem otimizador de imagens configurado (mesma regra da Pesquisa)
              <img src={line.imageUrl} alt="" width={24} height={34} loading={eagerImages ? "eager" : "lazy"} decoding="async" className="h-full w-full object-cover" />
            ) : null}
          </span>
          <span className="min-w-0 leading-snug">
            <span className="block font-semibold text-neutral-900">{line.cardName}</span>
            <span className="block text-[9px] text-neutral-500">
              {wishVariantText(line)}
              {line.variantAvailable ? null : <span className="ml-1 font-medium text-neutral-700">· Indisponível no catálogo</span>}
            </span>
          </span>
        </span>
      </td>
      <td className="px-2 py-1 text-center tabular-nums text-neutral-900">
        {line.reference.kind === "priced" ? (
          formatBrl(line.reference.brl)
        ) : line.reference.kind === "unavailable" ? (
          <span className="italic text-neutral-500">Indisponível</span>
        ) : (
          <span className="text-neutral-400">Sem cotação</span>
        )}
      </td>
      <td className={`px-2 py-1 text-center ${satisfied ? "font-semibold text-neutral-900" : "text-neutral-600"}`}>{wishOwnershipText(line.ownership)}</td>
      <td className="px-2 py-1 text-center tabular-nums text-neutral-600">{wishedAtText(line.wishedAt)}</td>
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
