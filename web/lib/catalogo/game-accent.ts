/**
 * Cor-assinatura por Jogo (decisão de UX aprovada para a tela Catálogo,
 * 2026-07-31) — determinística a partir do código do Jogo, sem depender de
 * uma lista fixa de cores (novos Jogos podem ser cadastrados a qualquer
 * momento pela própria tela). Só o matiz varia; saturação e luminosidade
 * ficam fixas para funcionar como acento discreto em claro e escuro sem
 * precisar de um par de valores por tema.
 */
export function getGameAccentColor(gameCode: string): string {
  let hash = 0;
  for (let index = 0; index < gameCode.length; index += 1) {
    hash = (hash * 31 + gameCode.charCodeAt(index)) % 360;
  }
  const hue = Math.abs(hash);
  return `hsl(${hue} 55% 45%)`;
}
