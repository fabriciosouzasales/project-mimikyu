import { notFound } from "next/navigation";
import { AlertTriangle, Boxes, ClipboardList, CreditCard, FileUp, History, Image as ImageIcon, Layers3 } from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { CardSetCartasGrid } from "@/components/catalogo/card-set-cartas-grid";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { SetTypeTag } from "@/components/catalogo/set-type-tag";
import { StateBadge } from "@/components/catalogo/state-badge";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { Button } from "@/components/ui/button";
import { formatNumber } from "@/lib/utils";
import { getCardSetByCode, getCartasCompletas } from "@/lib/catalogo/queries";

/** Mesmo mapa de `visao-geral-stats.tsx` (não exportado de lá) — nome de exibição por código de idioma. */
const LANGUAGE_DISPLAY_NAME: Record<string, string> = {
  en: "Inglês",
  "pt-BR": "Português",
};

/**
 * Bandeira por código de idioma — pedido de Fabrício (2026-08-08) para as
 * barras de "Cobertura por idioma". Emoji Unicode, não uma lib de bandeiras
 * nova (nenhuma existia no projeto até agora — `LanguageToggle`/
 * `ImageLanguageToggle`, em `importar-imagens-view.tsx`/`cartas-gallery.tsx`,
 * já usavam só texto "EN"/"PT", nunca ícone) — dispensa dependência nova
 * para só dois idiomas suportados hoje. `en` mapeado para 🇺🇸 (Estados
 * Unidos), convenção mais comum para "inglês" quando uma única bandeira
 * precisa representar o idioma, não uma região específica; `🌐` genérico
 * cobre qualquer `language.code` futuro sem bandeira mapeada ainda.
 */
const LANGUAGE_FLAG: Record<string, string> = {
  en: "🇺🇸",
  "pt-BR": "🇧🇷",
};

/**
 * "94 cartas (86 base + 8 secretas)" — mesma fórmula de `formatCardSetTotals()`
 * em `cartas-gallery.tsx` (não exportada de lá, duplicada aqui: é uma
 * function pura de duas linhas, menor risco que acoplar este hub a um
 * arquivo de página não relacionado). Secretas = `totalSetSize - baseSetSize`.
 */
function formatCardSetTotals(baseSetSize: number, totalSetSize: number): string {
  const secretas = totalSetSize - baseSetSize;
  if (secretas <= 0) return `${totalSetSize} carta${totalSetSize === 1 ? "" : "s"}`;
  return `${totalSetSize} cartas (${baseSetSize} base + ${secretas} secreta${secretas === 1 ? "" : "s"})`;
}

/**
 * Hub operacional de um Card Set (`/catalogo/card-sets/{code}`) — escopo V1
 * aprovado por Fabrício em 2026-08-08, depois de uma avaliação de
 * viabilidade prévia confirmando que nenhuma tabela/view nova era
 * necessária (toda a modelagem já existia em `catalog_card_set_metrics` /
 * `catalog_card_set_image_coverage` / `card_set.base_set_size` — só não
 * estava exposta por Card Set individual em nenhum tipo de retorno; ver
 * `CardSetDetail`/`getCardSetByCode` em `queries.ts`). Substitui o detalhe
 * mínimo introduzido em 2026-08-08 (revisão 6 da Visão Geral), que só
 * repetia o resumo já visível na tabela de Coleções e tinha um placeholder
 * "Detalhe completo em construção".
 *
 * Revisão de layout (2026-08-08, mesmo dia, rodada seguinte — 6 ajustes
 * pedidos por Fabrício sobre a primeira versão):
 *
 * 1. Logo maior (`h-20 w-32`, era `h-10 w-16`) — mais evidente no cabeçalho.
 * 2. Identificação ao lado da logo virou três linhas fixas: Código - Nome
 *    da Coleção + Tipo; Código - Nome da Expansão; Nome do Jogo. Data de
 *    lançamento saiu do cabeçalho (não fazia parte das três linhas
 *    pedidas) e não foi realocada — informação descartada deliberadamente
 *    nesta rodada, não um esquecimento.
 * 3 e 5. O bloco "Cobertura e pendências" (antes uma `Panel` própria, seção
 *    3) deixou de existir como seção separada — sua informação (cartas
 *    pendentes de cadastro + cobertura por idioma) migrou para dentro do
 *    "Estado do Set", no lugar exato de onde saiu "Logo: Cadastrada"
 *    (informação redundante com a própria logo grande já visível no
 *    cabeçalho).
 * 4. Clique na imagem de uma carta agora amplia com o mesmo efeito de
 *    `/catalogo/cartas` (View Transitions API — a miniatura do grid morfa
 *    até virar a imagem ampliada) — ver `CardSetCartasGrid`.
 * 6. Painel "Ações" (`Panel` branca com título) removido — os três botões
 *    de ação contextual passaram a ficar soltos no rodapé da página, sem
 *    superfície/card ao redor.
 *
 * Refinamentos de fechamento (2026-08-08, mesmo dia, "V1 aprovada
 * conceitualmente... apenas mais estes refinamentos antes do fechamento"):
 *
 * 1. "Cards pendentes" → "Cartas pendentes" (rótulo, sem mudança de dado).
 * 2. Ações contextuais (Importar Cards/Imagens, Histórico) saíram do
 *    rodapé solto e foram para uma linha `flex justify-end` logo acima do
 *    Panel "Cartas da Coleção" — mesmo padrão já usado em
 *    `cartas-gallery.tsx` ("Nova Carta"/"Importar Cartas" acima do Card de
 *    conteúdo, nunca depois dele).
 * 3. Link "Ver em Cartas" removido de `CardSetCartasGrid` — as ações
 *    contextuais do item 2 já cobrem a navegação relevante.
 * 4. Barras de "Cobertura por idioma" ampliadas (`w-28`→`w-40`, barra
 *    `h-1.5`→`h-2`, textos um degrau maior) sem alterar a largura do
 *    painel — só a proporção que a seção ocupa nele.
 *
 * Duas seções na versão atual: Estado do Set (identidade + métricas +
 * cobertura/pendências) e Cartas da Coleção (ações contextuais acima dela).
 */
export default async function CardSetDetailPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const { denied, supabase } = await requireCatalogoAdmin(code, Boxes);
  if (denied) return denied;

  const cardSet = await getCardSetByCode(supabase, code);
  if (!cardSet) {
    notFound();
  }

  const cartas = await getCartasCompletas(supabase, cardSet.id, { incluirInativas: true });

  const semCartas = cardSet.cardsCatalogados === 0;
  const imagensCompletas = !semCartas && cardSet.cardsComImagem === cardSet.cardsCatalogados;
  const imagensTone = semCartas ? "muted" : imagensCompletas ? "success" : "warning";

  return (
    <AppShell title={cardSet.name} icon={Boxes}>
      <div className="mx-auto max-w-6xl space-y-4">
        <div className="flex items-center gap-4">
          {cardSet.logoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={cardSet.logoUrl} alt="" className="h-20 w-32 shrink-0 object-contain" />
          ) : (
            <Boxes className="h-8 w-8 shrink-0 text-muted-foreground" aria-hidden="true" />
          )}
          <div className="space-y-0.5">
            <div className="flex items-center gap-2">
              <h1 className="font-heading text-xl font-medium text-foreground">
                {cardSet.code} - {cardSet.name}
              </h1>
              <SetTypeTag setType={cardSet.setType} />
            </div>
            <p className="text-xs text-muted-foreground">
              {cardSet.expansionName
                ? cardSet.expansionCode
                  ? `${cardSet.expansionCode} - ${cardSet.expansionName}`
                  : cardSet.expansionName
                : "—"}
            </p>
            <p className="text-xs text-muted-foreground">{cardSet.gameName ?? "—"}</p>
          </div>
        </div>

        {/* Estado do Set — métricas + Cobertura/Pendências (migrada para cá, ver revisão acima) */}
        <Panel>
          <PanelHeader>
            <PanelTitle>Estado do Set</PanelTitle>
          </PanelHeader>
          <PanelContent className="flex flex-wrap items-start gap-x-8 gap-y-4 text-sm">
            <div>
              <p className="text-[11px] text-muted-foreground">Cartas totais</p>
              <p className="mt-0.5 text-foreground">{formatCardSetTotals(cardSet.baseSetSize, cardSet.totalSetSize)}</p>
            </div>
            <div className="text-center">
              <p className="text-[11px] text-muted-foreground">Cartas catalogadas</p>
              <p className="mt-0.5 text-foreground">
                {formatNumber(cardSet.cardsCatalogados)} de {formatNumber(cardSet.totalSetSize)}
              </p>
            </div>
            <div className="text-center">
              <p className="text-[11px] text-muted-foreground">Imagens</p>
              <p className="mt-0.5">
                <StateBadge tone={imagensTone}>
                  {!semCartas && !imagensCompletas && <AlertTriangle className="mr-1 h-2.5 w-2.5" aria-hidden="true" />}
                  {formatNumber(cardSet.cardsComImagem)} de {formatNumber(cardSet.cardsCatalogados)}
                </StateBadge>
              </p>
            </div>
            <div className="text-center">
              <p className="text-[11px] text-muted-foreground">Cartas pendentes</p>
              <p className="mt-0.5 text-foreground">
                {cardSet.cardsPendentes > 0 ? formatNumber(cardSet.cardsPendentes) : "Nenhum"}
              </p>
            </div>

            {/* Cobertura por idioma — ao lado de "Cartas pendentes", na mesma
                linha (pedido de Fabrício, 2026-08-08: "não quero uma segunda
                linha"). Barras ampliadas na revisão de fechamento (mesmo
                dia, rodada seguinte: "aumentar um pouco os gráficos... sem
                aumentar desnecessariamente o painel") — coluna de `w-28`
                para `w-40`, barra de `h-1.5` para `h-2`, textos um degrau
                maior (`text-[10px]`→`text-xs`, `text-[9px]`→`text-[11px]`) e
                mais respiro entre as duas (`gap-3`→`gap-6`); a largura total
                do painel não muda, só a proporção que esta seção ocupa nele.
                Ampliadas de novo em 2026-08-09 (achado de Fabrício em
                inspeção geral: "aumentar um pouco os gráficos... para
                ocuparmos melhor o espaço do card") — coluna de `w-40` para
                `w-56`, único ajuste desta rodada (altura da barra e textos
                mantidos da revisão anterior); o painel já tinha espaço
                horizontal sobrando à direita das duas barras em Coleções com
                só 2 idiomas, então alargar a coluna aproveita esse vão sem
                empurrar o painel para uma segunda linha. */}
            {cardSet.coberturaPorIdioma.length > 0 && (
              <div>
                <p className="text-[11px] text-muted-foreground">Cobertura por idioma</p>
                <div className="mt-1.5 flex gap-6">
                  {cardSet.coberturaPorIdioma.map((cobertura) => {
                    const percentual =
                      cardSet.cardsCatalogados > 0
                        ? Math.round((cobertura.cardsComImagem / cardSet.cardsCatalogados) * 100)
                        : 0;
                    return (
                      <Link
                        key={cobertura.languageCode}
                        href={`/catalogo/importar-imagens?cardSetId=${cardSet.id}&idioma=${encodeURIComponent(cobertura.languageCode)}`}
                        className="block w-56 space-y-1.5 rounded-md -mx-1 px-1 py-1 transition-colors hover:bg-surface-muted"
                      >
                        <div className="flex items-center justify-between text-xs">
                          <span className="flex items-center gap-1 font-medium text-foreground">
                            {LANGUAGE_DISPLAY_NAME[cobertura.languageCode] ?? cobertura.languageCode}
                            <span aria-hidden="true">{LANGUAGE_FLAG[cobertura.languageCode] ?? "🌐"}</span>
                          </span>
                          <span className="tabular-nums text-muted-foreground">{percentual}%</span>
                        </div>
                        <div className="h-2 w-full overflow-hidden rounded-full bg-surface-muted">
                          <div className="h-full rounded-full bg-primary" style={{ width: `${percentual}%` }} />
                        </div>
                        <p className="text-[11px] tabular-nums text-muted-foreground">
                          {formatNumber(cobertura.cardsComImagem)}/{formatNumber(cardSet.cardsCatalogados)}
                        </p>
                      </Link>
                    );
                  })}
                </div>
              </div>
            )}
          </PanelContent>
        </Panel>

        {/* Cartas da Coleção — ações contextuais no topo do bloco, mesmo
            padrão de "Nova Carta"/"Importar Cartas" em `cartas-gallery.tsx`
            (`flex justify-end` logo acima do Card/Panel de conteúdo, não
            depois da galeria). Pedido de Fabrício (2026-08-08, revisão de
            fechamento): "seguir o padrão de todas as outras páginas". */}
        <div className="space-y-2">
          <div className="flex flex-wrap justify-end gap-2">
            <Button asChild size="sm">
              <Link href={`/catalogo/importar-cartas?cardSetId=${cardSet.id}`}>
                <FileUp className="h-3.5 w-3.5" />
                Importar Cartas
              </Link>
            </Button>
            <Button asChild size="sm" variant="outline">
              <Link href={`/catalogo/importar-imagens?cardSetId=${cardSet.id}`}>
                <ImageIcon className="h-3.5 w-3.5" />
                Importar Imagens
              </Link>
            </Button>
            <Button asChild size="sm" variant="outline">
              <Link href={`/catalogo/importacoes?cardSet=${cardSet.code}`}>
                <History className="h-3.5 w-3.5" />
                Histórico de Importações
              </Link>
            </Button>
            <Button asChild size="sm" variant="outline">
              <Link href={`/catalogo/relatorios/checklist?cardSet=${cardSet.code}`}>
                <ClipboardList className="h-3.5 w-3.5" />
                Checklist
              </Link>
            </Button>
            <Button asChild size="sm" variant="outline">
              <Link href={`/catalogo/relatorios/resumo?cardSet=${cardSet.code}`}>
                <Layers3 className="h-3.5 w-3.5" />
                Resumo
              </Link>
            </Button>
          </div>

          <Panel>
            <PanelHeader>
              <div className="flex items-center gap-1.5">
                <CreditCard className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" />
                <PanelTitle>Cartas da Coleção</PanelTitle>
              </div>
            </PanelHeader>
            <PanelContent>
              <CardSetCartasGrid cartas={cartas} />
            </PanelContent>
          </Panel>
        </div>
      </div>
    </AppShell>
  );
}
