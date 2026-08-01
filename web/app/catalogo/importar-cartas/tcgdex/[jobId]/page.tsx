import { redirect } from "next/navigation";

/**
 * Redirect puro (2026-08-01, terceira rodada de ajustes visuais da página
 * Importar Cartas) — esta rota mostrava `JobStatusView`/
 * `RevisaoImportacaoTable` para um job específico via `[jobId]` na URL.
 * O fluxo inteiro (Analisar → progresso → Revisão) passou a viver em
 * estado de componente cliente dentro de `/catalogo/importar-cartas`
 * (ver `importar-tcgdex-view.tsx`, hook `useAnalyzeJob`), sem navegar —
 * exatamente para resolver o problema que esta rota causava ("a tabela...
 * é carregada em uma nova página", relatado por Fabrício). `RevisaoImportacaoTable`
 * também ganhou uma prop `onRefresh` que só um componente cliente pode
 * fornecer, então esta rota (um Server Component) não tem mais como
 * renderizá-la sem duplicar aquele estado aqui — sem necessidade real,
 * já que nada mais linka para esta rota (grep confirmado em 2026-08-01).
 * Mantida só como redirect para não quebrar um favorito/link antigo,
 * mesmo padrão de `tcgdex/page.tsx`.
 */
export default async function ImportacaoTcgdexJobRedirectPage() {
  redirect("/catalogo/importar-cartas");
}
