/**
 * Rodapé compartilhado por todos os relatórios imprimíveis da Central de
 * Relatórios (2026-08-09) — mesma extração de baseline visual do Checklist
 * por Coleção. Só a data de geração; nenhum dado sensível.
 *
 * "Gerado por Mimikyu" → "Gerado por MMKYU Collector" (2026-08-09, mesmo
 * dia, rodada seguinte) — pedido explícito de Fabrício, nome de marca
 * voltado ao usuário final, distinto do nome interno do projeto.
 *
 * Fixado no rodapé físico de cada folha impressa (`print:fixed
 * print:inset-x-0 print:bottom-0`) — pedido explícito de Fabrício para o
 * texto nunca aparecer "no meio da página" quando o conteúdo do relatório
 * ocupa menos de uma folha inteira. Fora do fluxo normal só em impressão
 * (`position: fixed` é a única ferramenta nativa para ancorar algo no
 * rodapé físico de CADA página impressa — ao contrário do cabeçalho, que
 * usa `<thead>`, não existe equivalente de `<tfoot>` que "empurre" para o
 * fim físico da folha quando o conteúdo é curto; `<tfoot>` só repete logo
 * após a última linha de conteúdo daquela página, não no rodapé físico).
 * Na tela, o rodapé continua no fluxo normal, ao final da folha.
 */
export function RelatorioRodape() {
  return (
    <p className="px-6 pb-6 pt-4 text-center text-[8px] text-neutral-400 print:fixed print:inset-x-0 print:bottom-0 print:bg-white print:px-0 print:pb-2">
      Gerado por MMKYU Collector em {new Date().toLocaleDateString("pt-BR")}
    </p>
  );
}
