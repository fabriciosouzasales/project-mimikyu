import { ImagePlus } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarImagensView } from "@/components/catalogo/importar-imagens-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetImagensById, getCardSetsForImportacaoImagens } from "@/lib/catalogo/queries";

/**
 * Substitui o stub `ComingSoonPage` (2026-08-01) por uma tela real
 * (2026-08-02) — pedido explícito de Fabrício depois de ficar sem como
 * retomar a importação de imagens de uma Coleção grande que teve a Edge
 * Function interrompida por timeout (SV4/Fenda Paradoxal — ver Query 2092
 * v1.2, `05-modelo-de-dados.md` revisão `1.33`): o seletor de `Importar
 * Cartas` só lista Coleções sem carta nenhuma, então uma Coleção que já tem
 * Cards mas ainda tem imagens pendentes fica sem tela para retomar.
 *
 * `?cardSetId=` resolve a Coleção selecionada a partir da URL, mesmo padrão
 * de `/catalogo/importar-cartas` — sem `?jobId=`/`?fonte=` aqui, não há job
 * de cartas nem fonte alternativa (PDF) neste fluxo, só a imagem via TCGdex.
 */
export default async function ImportarImagensPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSetId?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Importar Imagens", ImagePlus);
  if (denied) return denied;

  const { cardSetId } = await searchParams;

  const cardSets = await getCardSetsForImportacaoImagens(supabase);
  const colecoesPendentes = cardSets.length;
  const cartasSemImagem = cardSets.reduce((sum, cardSet) => sum + cardSet.imagesPendentes, 0);
  // Bug real corrigido (2026-08-02): antes, `selectedCardSet` só olhava
  // `cardSets` (a lista filtrada por `imagesPendentes > 0`) — assim que uma
  // importação terminava com sucesso e a Coleção saía dessa lista,
  // `selectedCardSet` virava `null` e a `key={selectedCardSet?.id}` de
  // `ImportarImagensView` forçava um remount que apagava o resultado final
  // ainda visível na tela (reportado por Fabrício: a tela voltava para
  // "Selecione uma Coleção..." "apesar de ter concluído"). Fallback via
  // `getCardSetImagensById` (sem o filtro de pendentes) resolve a Coleção
  // mesmo depois de concluída — `cardSets` (as OPÇÕES do combobox) continua
  // filtrado normalmente, então ela não volta a ser oferecida de novo.
  const selectedCardSet = cardSetId
    ? (cardSets.find((cardSet) => cardSet.id === cardSetId) ?? (await getCardSetImagensById(supabase, cardSetId)))
    : null;

  return (
    <AppShell title="Importar Imagens" icon={ImagePlus}>
      <PageContainer>
        {/*
          `key={selectedCardSet?.id}` — mesmo motivo de `ImportarCartasPage`
          (ver comentário lá): trocar de Coleção pelo combobox só atualiza
          `?cardSetId=`, o que não remonta `ImportarImagensView` sozinho
          (mesma árvore de componente cliente); a `key` força o remount e
          zera o estado de progresso da Coleção anterior.
        */}
        <ImportarImagensView
          key={selectedCardSet?.id ?? "none"}
          cardSets={cardSets}
          colecoesPendentes={colecoesPendentes}
          cartasSemImagem={cartasSemImagem}
          selectedCardSet={selectedCardSet}
        />
      </PageContainer>
    </AppShell>
  );
}
