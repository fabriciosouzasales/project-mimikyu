/**
 * Geração visível na Pokédex Nacional (Pokédex P4c, 2026-10-14).
 *
 * Regra pura usada pela ilha cliente da régua fixa. A "linha de leitura" fica logo
 * abaixo da régua; a geração visível é a da seção que cruza essa linha.
 *
 * - Linha antes da primeira seção (topo da página, cabeçalho visível): a primeira
 *   seção — é a primeira geração que o usuário vê na galeria.
 * - Linha depois da última seção (fim da lista): a última seção.
 * - Linha no espaço entre duas seções: mantém a anterior (histerese). Assim o destaque
 *   não pisca nem some ao atravessar a fronteira; ele só muda quando a próxima seção
 *   de fato alcança a linha.
 * - Sem seções (pesquisa sem resultado): nenhuma.
 *
 * Coordenadas no mesmo referencial (ex.: `getBoundingClientRect`), seções em ordem.
 */

export type SectionBox = { code: string; top: number; bottom: number };

export function resolveVisibleGeneration(sections: SectionBox[], line: number, previous: string | null): string | null {
  const first = sections[0];
  const last = sections[sections.length - 1];
  if (!first || !last) return null;

  const crossing = sections.find((section) => section.top <= line && line < section.bottom);
  if (crossing) return crossing.code;

  if (line < first.top) return first.code;
  if (line >= last.bottom) return last.code;

  // No espaço entre seções: mantém a anterior se ela ainda existe; senão, a última já passada.
  if (previous !== null && sections.some((section) => section.code === previous)) return previous;
  let passed: SectionBox = first;
  for (const section of sections) {
    if (section.top <= line) passed = section;
  }
  return passed.code;
}
