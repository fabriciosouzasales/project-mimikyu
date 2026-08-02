import { ImagePlus } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarImagensView } from "@/components/catalogo/importar-imagens-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetImagensById, getCardSetsForImportacaoImagens } from "@/lib/catalogo/queries";

/** Idiomas suportados pelo pipeline de imagens (2026-08-02) — mesmo domínio aceito por `admin_start_asset_import_run()` v1.3 (Query 2092) para os dois únicos idiomas com cobertura real na TCGdex hoje (ver Sprint B3.23/B3.24). */
const SUPPORTED_LANGUAGE_CODES = ["en", "pt-BR"] as const;
type SupportedLanguageCode = (typeof SUPPORTED_LANGUAGE_CODES)[number];

function resolveLanguageCode(value: string | undefined): SupportedLanguageCode {
  return (SUPPORTED_LANGUAGE_CODES as readonly string[]).includes(value ?? "")
    ? (value as SupportedLanguageCode)
    : "en";
}

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
 *
 * `?idioma=` (2026-08-02, suporte EN + PT-BR — Fabrício escolheu
 * explicitamente "Os dois idiomas" em vez de trocar o padrão para só
 * PT-BR): decide qual idioma a tela mostra — Coleções pendentes, indicador
 * "Sem Imagens" e a própria importação disparada são todos filtrados/abertos
 * nesse idioma. DEFAULT `"en"` quando ausente/inválido (mesmo default de
 * `admin_start_asset_import_run()` v1.3) — preserva o comportamento anterior
 * para quem chegar sem o parâmetro.
 */
export default async function ImportarImagensPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSetId?: string; idioma?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Importar Imagens", ImagePlus);
  if (denied) return denied;

  const { cardSetId, idioma } = await searchParams;
  const languageCode = resolveLanguageCode(idioma);

  const cardSets = await getCardSetsForImportacaoImagens(supabase, languageCode);
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
    ? (cardSets.find((cardSet) => cardSet.id === cardSetId) ??
      (await getCardSetImagensById(supabase, cardSetId, languageCode)))
    : null;

  return (
    <AppShell title="Importar Imagens" icon={ImagePlus}>
      <PageContainer>
        {/*
          `key={selectedCardSet?.id}` — mesmo motivo de `ImportarCartasPage`
          (ver comentário lá): trocar de Coleção pelo combobox só atualiza
          `?cardSetId=`, o que não remonta `ImportarImagensView` sozinho
          (mesma árvore de componente cliente); a `key` força o remount e
          zera o estado de progresso da Coleção anterior. Idioma incluído na
          key (2026-08-02) pelo mesmo motivo — trocar `?idioma=` também deve
          zerar o progresso visível, nunca misturar o resultado de um idioma
          com o seletor do outro.
        */}
        <ImportarImagensView
          key={`${languageCode}:${selectedCardSet?.id ?? "none"}`}
          cardSets={cardSets}
          colecoesPendentes={colecoesPendentes}
          cartasSemImagem={cartasSemImagem}
          selectedCardSet={selectedCardSet}
          languageCode={languageCode}
        />
      </PageContainer>
    </AppShell>
  );
}
