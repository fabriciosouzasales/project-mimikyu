import { redirect } from "next/navigation";

/**
 * /colecoes — entrada do módulo Coleções. Abre "Minhas coleções", primeiro item
 * de GERENCIAR (COLLECTIONS-NAVIGATION-UX-CORRECTION-01); o item de menu nunca
 * leva a uma tela vazia.
 */
export default function ColecoesIndexPage() {
  redirect("/colecoes/colecoes");
}
