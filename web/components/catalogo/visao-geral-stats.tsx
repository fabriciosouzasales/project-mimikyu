import { AlertTriangle, CreditCard, Image, Layers } from "lucide-react";
import Link from "next/link";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { EstadoDoCatalogo as EstadoDoCatalogoData } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/** Nome de exibição por código de idioma — sem lista de idiomas própria aqui, cai no próprio código se não reconhecido (extensível sem alteração de código, mesmo espírito de catalog_card_set_image_coverage). */
const LANGUAGE_DISPLAY_NAME: Record<string, string> = {
  en: "Inglês",
  "pt-BR": "Português",
};

/** Pluraliza um substantivo simples (sem irregularidades) para as contagens de "Saúde do catálogo". */
function pluralizar(quantidade: number, singular: string, plural: string): string {
  return quantidade === 1 ? singular : plural;
}

/**
 * Indicadores da Visão Geral — migrados para o padrão introduzido em Jogos
 * (2026-07-31, aprovado por Fabrício). Substitui `EstadoDoCatalogo`, que
 * usava um grid de 4 divs com borda direto (sem `StatCard`/ícone) — ver
 * `estado-do-catalogo.tsx` (não removido, mesma prática de manter código
 * substituído sem uso até decisão explícita de limpeza).
 *
 * Ajuste do mesmo dia (pedido de Fabrício): sequência reordenada — Card
 * Sets, Cartas catalogadas, Cobertura de imagens, Pendências (era Card
 * Sets, Cobertura, Cartas, Pendências); Cobertura de imagens agora em %
 * (era "6/7"); Pendências ganha `tone="danger"` (ícone vermelho), única
 * exceção ao selo uniforme dos outros três cartões.
 *
 * Reorganização 2026-08-08 (Sprint Gerencial 1, segunda rodada — a primeira
 * tentativa somou 8 StatCards extras e ficou visualmente carregada,
 * feedback direto de Fabrício com esboço anexado):
 *
 * - Linha principal continua com só 4 StatCards. "Pendências" trocou de
 *   métrica: era `execucoesComPendencia` (asset_import_run != COMPLETED,
 *   57 na produção real — número ruidoso, acumula CANCELLED e falhas
 *   antigas já superadas por nova tentativa, não diz "precisa de atenção
 *   agora"); agora é `importacoesAguardandoRevisaoOuErro`
 *   (catalog_import_job em STAGED/CONFIRMING/COMPLETED_WITH_ERRORS/FAILED,
 *   9 na mesma produção) — só estados realmente acionáveis do pipeline de
 *   Cards. O número antigo não desaparece do sistema, só deixa de ser
 *   headline aqui — continua em /catalogo/importacoes. Label "Cobertura de
 *   imagens" encurtado para "Cobertura" (mesmo dado, sem mudança de
 *   critério).
 * - "Cobertura por idioma" deixou de ser uma StatCard por idioma e virou UM
 *   card compacto (`Panel`), com uma barra horizontal por idioma ativo —
 *   mesma informação (`estado.coberturaPorIdioma`, dinâmica, sem hardcode),
 *   muito menos área.
 * - "Pendências do catálogo" (4 StatCards) virou "Saúde do catálogo", uma
 *   linha de texto compacta com só as três lacunas ESTRUTURAIS (Coleções/
 *   Cartas/Imagens pendentes — `catalog_card_set_metrics`, Query
 *   2123/2124). Importações aguardando NÃO é repetida aqui — já é o
 *   headline da StatCard "Pendências" acima (ajuste explícito de
 *   Fabrício, para não duplicar o mesmo número em dois lugares).
 *
 * Drill-down (2026-08-08, mesmo dia — desenho apresentado e aprovado por
 * Fabrício antes desta implementação): "Coleções"→`/catalogo/card-sets`,
 * "Cartas catalogadas"→`/catalogo/cartas`, "Cobertura"→
 * `/catalogo/importar-imagens` (destinos gerais, sem filtro — nenhuma das
 * três telas tem um parâmetro de "pendência" próprio hoje). "Pendências"→
 * `/catalogo/importacoes?atencao=1` (único com filtro real, pré-requisito
 * explícito: a extensão de `/catalogo/importacoes` para incluir
 * `catalog_import_job`, implementada antes desta rodada). Cada linha de
 * "Cobertura por idioma" linka para `/catalogo/importar-imagens?idioma=
 * {code}` — mesmo parâmetro que a própria tela já usa para filtrar Coleções
 * pendentes por idioma (ver `importar-imagens/page.tsx`). Os três segmentos
 * de "Saúde do catálogo" linkam para a tela onde a lacuna correspondente é
 * resolvida: Coleções pendentes→`/catalogo/card-sets`, Cartas pendentes→
 * `/catalogo/importar-cartas`, Imagens pendentes→`/catalogo/importar-imagens`
 * (também sem filtro — mesmo motivo das StatCards principais).
 *
 * Ajuste do mesmo dia (aprovação do layout acima, antes do drill-down):
 * removida a legenda solta "N Coleções com imagens pendentes" que ficava
 * entre a linha principal e o card de Cobertura por idioma — essa
 * informação já pertence semanticamente a "Saúde do catálogo" (coleções
 * pendentes), não precisa de uma segunda linha isolada logo acima.
 */
export function VisaoGeralStats({ estado }: { estado: EstadoDoCatalogoData }) {
  const coberturaPercentual =
    estado.cardSetsCatalogados > 0
      ? Math.round((estado.cardSetsComImagensCompletas / estado.cardSetsCatalogados) * 100)
      : 0;

  return (
    <div className="space-y-3">
      <StatsRow>
        <StatCard
          label="Coleções"
          value={formatNumber(estado.cardSetsCatalogados)}
          caption="coleções catalogadas"
          icon={Layers}
          href="/catalogo/card-sets"
        />
        <StatCard
          label="Cartas catalogadas"
          value={formatNumber(estado.cartasCatalogadas)}
          caption="cartas no catálogo"
          icon={CreditCard}
          href="/catalogo/cartas"
        />
        <StatCard
          label="Cobertura"
          value={`${coberturaPercentual}%`}
          caption="com imagens completas"
          icon={Image}
          href="/catalogo/importar-imagens"
        />
        <StatCard
          label="Pendências"
          value={formatNumber(estado.importacoesAguardandoRevisaoOuErro)}
          caption="aguardando revisão ou erro"
          icon={AlertTriangle}
          tone="danger"
          href="/catalogo/importacoes?atencao=1"
        />
      </StatsRow>

      {estado.coberturaPorIdioma.length > 0 && (
        <Panel className="max-w-md">
          <PanelHeader>
            <PanelTitle>Cobertura por idioma</PanelTitle>
          </PanelHeader>
          <PanelContent className="space-y-2.5">
            {estado.coberturaPorIdioma.map((cobertura) => {
              const percentual =
                estado.cartasCatalogadas > 0
                  ? Math.round((cobertura.cardsComImagem / estado.cartasCatalogadas) * 100)
                  : 0;
              return (
                <Link
                  key={cobertura.languageCode}
                  href={`/catalogo/importar-imagens?idioma=${encodeURIComponent(cobertura.languageCode)}`}
                  className="block space-y-1 rounded-md -mx-1 px-1 py-0.5 transition-colors hover:bg-surface-muted"
                >
                  <div className="flex items-center justify-between text-xs">
                    <span className="font-medium text-foreground">
                      {LANGUAGE_DISPLAY_NAME[cobertura.languageCode] ?? cobertura.languageCode}
                    </span>
                    <span className="tabular-nums text-muted-foreground">
                      {percentual}% · {formatNumber(cobertura.cardsComImagem)}/{formatNumber(estado.cartasCatalogadas)}
                    </span>
                  </div>
                  <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
                    <div className="h-full rounded-full bg-primary" style={{ width: `${percentual}%` }} />
                  </div>
                </Link>
              );
            })}
          </PanelContent>
        </Panel>
      )}

      <div className="space-y-1">
        <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Saúde do catálogo</p>
        <p className="text-xs text-muted-foreground">
          <Link href="/catalogo/card-sets" className="hover:text-foreground hover:underline">
            {formatNumber(estado.cardSetsComPendencia)}{" "}
            {pluralizar(estado.cardSetsComPendencia, "coleção pendente", "coleções pendentes")}
          </Link>
          {" · "}
          <Link href="/catalogo/importar-cartas" className="hover:text-foreground hover:underline">
            {formatNumber(estado.cartasPendentes)}{" "}
            {pluralizar(estado.cartasPendentes, "carta pendente", "cartas pendentes")}
          </Link>
          {" · "}
          <Link href="/catalogo/importar-imagens" className="hover:text-foreground hover:underline">
            {formatNumber(estado.imagensPendentes)}{" "}
            {pluralizar(estado.imagensPendentes, "imagem pendente", "imagens pendentes")}
          </Link>
        </p>
      </div>
    </div>
  );
}
