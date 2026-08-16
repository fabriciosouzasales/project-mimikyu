import type { ReactNode } from "react";

/**
 * "Folha" A4 compartilhada por todos os relatórios imprimíveis da Central de
 * Relatórios (2026-08-09) — extraída do Checklist por Coleção depois de
 * Fabrício aprovar seu resultado visual e pedir que ele vire a baseline dos
 * outros 5 relatórios ("cabeçalho, identidade MMKYU, identificação da
 * Coleção, tipografia, margens e tratamento de impressão"). Fundo branco
 * fixo (não os tokens de tema do app — uma folha impressa não muda com dark
 * mode), largura A4 mesmo na tela (`max-w-[210mm]`, sensação de papel antes
 * de imprimir), sem borda/sombra na impressão. `print-color-adjust: exact`
 * (e o prefixo `-webkit-`) é obrigatório para qualquer relatório que use cor
 * de fundo (zebra striping, faixas, etc.) — a maioria dos navegadores omite
 * cor de fundo ao imprimir por padrão (economia de tinta).
 *
 * Classe `relatorio-folha` (2026-08-16) — hook para as regras de segurança
 * de paginação de impressão em `app/globals.css` (linha nunca dividida nem
 * ocultada em quebra de página; espaço reservado para o rodapé fixo em toda
 * página, não só na última). Ver comentário completo lá — a causa raiz e a
 * correção vivem juntas, perto do `@page` já existente.
 */
export function RelatorioFolha({ children }: { children: ReactNode }) {
  return (
    <div
      className="relatorio-folha mx-auto w-full max-w-[210mm] rounded-lg border border-border bg-white text-neutral-900 shadow-panel print:max-w-none print:rounded-none print:border-none print:shadow-none"
      style={{ WebkitPrintColorAdjust: "exact", printColorAdjust: "exact" }}
    >
      {children}
    </div>
  );
}
