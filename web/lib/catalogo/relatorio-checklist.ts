/**
 * Regra de colunas do checklist impresso — padrão único do sistema (Central de Relatórios do
 * Catálogo Editorial e Checklist de completude das Coleções): `ceil(itens / 46)`, com piso 2 e
 * teto 4. Conjuntos maiores que 4 × 46 continuam em mais de uma folha A4 (aceito).
 */
export const CHECKLIST_MIN_COLUNAS_A4 = 2;
export const CHECKLIST_MAX_COLUNAS_A4 = 4;
export const CHECKLIST_ROWS_POR_COLUNA_A4 = 46;

export function checklistColunasA4(total: number): number {
  return Math.min(CHECKLIST_MAX_COLUNAS_A4, Math.max(CHECKLIST_MIN_COLUNAS_A4, Math.ceil(total / CHECKLIST_ROWS_POR_COLUNA_A4)));
}

/**
 * Linhas por coluna em CADA folha (paginação explícita). Cada folha leva o cabeçalho, a legenda e
 * o rodapé com paginação. Orçamento da área útil impressa (A4 − margens de 10 mm = 277 mm):
 * medido na folha real do ME5 (49 linhas de ≈4,3 mm com 2 px de respiro deixavam ≈21 mm livres
 * entre a legenda e o rodapé), o respiro passou a 2,5 px (+≈0,26 mm por linha): 50 linhas somam
 * ≈13 mm a mais e ainda sobram ≈8 mm. 48 linhas de 4,9 mm estouravam a folha (o rodapé
 * caía numa página em branco). Com 50, um Set de até 200 posições cabe numa folha só.
 * Independe da régua de colunas (`CHECKLIST_ROWS_POR_COLUNA_A4`), que continua 46.
 */
export const CHECKLIST_LINHAS_POR_FOLHA_A4 = 50;

export type ChecklistPaginaA4 = { inicio: number; tamanho: number; linhas: number };

/**
 * Paginação do checklist: cada folha é um bloco próprio, preenchido em ordem coluna-major DENTRO
 * da folha — a continuação de uma coluna nunca migra para a folha seguinte. As folhas são
 * preenchidas por completo (colunas × 50) antes de abrir a próxima; só a última fica parcial
 * (194 em 4 colunas → uma folha; 203 → 200 + 3).
 */
export function checklistPaginasA4(total: number): { colunas: number; paginas: ChecklistPaginaA4[] } {
  const colunas = checklistColunasA4(total);
  if (total <= 0) return { colunas, paginas: [] };
  const capacidade = colunas * CHECKLIST_LINHAS_POR_FOLHA_A4;
  const paginas: ChecklistPaginaA4[] = [];
  for (let inicio = 0; inicio < total; inicio += capacidade) {
    const tamanho = Math.min(capacidade, total - inicio);
    paginas.push({ inicio, tamanho, linhas: Math.ceil(tamanho / colunas) });
  }
  return { colunas, paginas };
}
