import type { ReactNode } from "react";
import { checklistPaginasA4 } from "@/lib/catalogo/relatorio-checklist";

/**
 * Checklist em colunas — padrão único dos relatórios "lista de verificação" do sistema
 * (extraído sem mudança visual da "Lista de Verificação de Cartas" da Central de Relatórios do
 * Catálogo Editorial, aprovada por Fabrício em 2026-08-09, e reaplicado no Checklist de
 * completude das Coleções, V1-14 R1-A).
 *
 * - Colunas: `ceil(itens / 46)`, com piso 2 e teto 4.
 * - Paginação explícita (`checklistPaginasA4`): cada página é uma FOLHA A4 própria — na tela,
 *   folhas separadas (nunca uma quebra no meio de uma folha); na impressão, uma página física por
 *   folha. Ordem coluna-major DENTRO da folha: a continuação de uma coluna nunca migra para a
 *   folha seguinte. Folhas preenchidas por completo; só a última fica parcial.
 * - Toda folha leva o cabeçalho, a legenda e o rodapé no fluxo ("Gerado por MMKYU Collector em
 *   …" ao centro, "Página X de Y" à direita), ancorado no pé da folha.
 */
/** Linha padrão do checklist: caixa | número | nome | marcador final (raridade, acabamento…). */
export function ChecklistLinhaBase({
  index,
  caixa,
  numero,
  nome,
  final,
}: {
  index: number;
  caixa: ReactNode;
  numero: string;
  nome: string;
  final?: ReactNode;
}) {
  return (
    <div
      className="flex items-center gap-1.5 rounded-sm px-1 py-[2.5px] text-[10px] leading-tight"
      style={{ backgroundColor: index % 2 === 0 ? "#FFFFFF" : "#F7F5ED" }}
    >
      {caixa}
      <span className="w-6 shrink-0 tabular-nums text-neutral-500">{numero}</span>
      <span className="min-w-0 flex-1 truncate text-neutral-900" title={nome}>
        {nome}
      </span>
      {final}
    </div>
  );
}

/** Caixa vazia do checklist (desenhada em CSS para imprimir igual em qualquer navegador). */
export function ChecklistCaixaVazia() {
  return <span className="h-3 w-3 shrink-0 border border-neutral-900" aria-hidden="true" />;
}

export function RelatorioChecklistFolhas<T>({
  itens,
  cabecalho,
  legenda,
  geradoEm,
  renderLinha,
}: {
  itens: readonly T[];
  /** Cabeçalho do relatório (normalmente `RelatorioCabecalho`), repetido em toda folha. */
  cabecalho: ReactNode;
  /** Legenda, repetida em toda folha logo após as linhas. */
  legenda?: ReactNode;
  /** Data exibida no rodapé (padrão: hoje, pt-BR). */
  geradoEm?: string;
  renderLinha: (item: T, index: number) => ReactNode;
}) {
  const { colunas, paginas } = checklistPaginasA4(itens.length);
  const data = geradoEm ?? new Date().toLocaleDateString("pt-BR");
  return (
    <div className="space-y-6 print:space-y-0">
      {paginas.map((pagina, paginaIndex) => {
        const ultima = paginaIndex === paginas.length - 1;
        return (
          <section
            key={pagina.inicio}
            data-checklist-folha={paginaIndex + 1}
            aria-label={`Página ${paginaIndex + 1} de ${paginas.length}`}
            className="relatorio-folha mx-auto flex min-h-[297mm] w-full max-w-[210mm] flex-col rounded-lg border border-border bg-white text-neutral-900 shadow-panel print:min-h-[275mm] print:max-w-none print:rounded-none print:border-none print:shadow-none"
            style={{
              WebkitPrintColorAdjust: "exact",
              printColorAdjust: "exact",
              breakInside: "avoid",
              breakAfter: ultima ? "auto" : "page",
            }}
          >
            {cabecalho}
            <table className="w-full px-6 print:px-0" style={{ tableLayout: "fixed", borderCollapse: "separate", borderSpacing: "8px 0" }}>
              <tbody>
                {Array.from({ length: pagina.linhas }).map((_, linha) => (
                  <tr key={linha}>
                    {Array.from({ length: colunas }).map((_, coluna) => {
                      const local = coluna * pagina.linhas + linha;
                      const index = pagina.inicio + local;
                      const item = local < pagina.tamanho ? itens[index] : undefined;
                      return (
                        <td key={coluna} className="p-0 align-top">
                          {item !== undefined ? renderLinha(item, index) : null}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
            {legenda ? <div className="px-6 print:px-0">{legenda}</div> : null}
            <div data-checklist-rodape="" className="mt-auto grid grid-cols-[1fr_auto_1fr] items-center gap-4 px-6 pb-6 pt-4 text-[8px] text-neutral-400 print:px-0 print:pb-0">
              <span aria-hidden="true" />
              <span>Gerado por MMKYU Collector em {data}</span>
              <span className="text-right tabular-nums">
                Página {paginaIndex + 1} de {paginas.length}
              </span>
            </div>
          </section>
        );
      })}
    </div>
  );
}
