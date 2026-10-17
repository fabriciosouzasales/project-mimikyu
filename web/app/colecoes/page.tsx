import { redirect } from "next/navigation";

/**
 * /colecoes — entrada do módulo Coleções. Nesta rodada só "Meu acervo" existe
 * (Minhas coleções e Onde guardo ficam para depois); o item de menu nunca leva
 * a uma tela vazia, então a raiz do módulo abre o acervo.
 */
export default function ColecoesIndexPage() {
  redirect("/colecoes/acervo");
}
