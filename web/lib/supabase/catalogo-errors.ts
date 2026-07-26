/**
 * Traduz as mensagens RAISE EXCEPTION das funções administrativas do
 * Catálogo Editorial — Escrita e Ingestão (ADR-023) para o texto exibido ao
 * usuário. Diferente de `admin-errors.ts` (ADR-021, match exato de sentença),
 * estas funções seguem o padrão `CODIGO_EM_MAIUSCULAS: texto legível.`
 * (mesmo estilo de `internal.write_card()`), então a tradução extrai o texto
 * após o primeiro `: ` em vez de mapear frase a frase — um único helper serve
 * todas as funções futuras do módulo (Game, Expansion, Card Set, Card) sem
 * precisar listar cada código manualmente.
 */
export function traduzirErroCatalogo(message: string): string {
  const match = message.match(/^[A-Z][A-Z0-9_]*:\s*(.+)$/);

  if (match && match[1]) {
    return match[1];
  }

  return "Não foi possível concluir a ação. Tente novamente em instantes.";
}
