import { BookOpen, ClipboardList } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RaritySymbol } from "@/components/catalogo/rarity-symbol";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { ChecklistCaixaVazia, ChecklistLinhaBase, RelatorioChecklistFolhas } from "@/components/catalogo/relatorio-checklist-tabela";
import { RelatorioColecaoSeletor } from "@/components/catalogo/relatorio-colecao-seletor";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import type { CartaCompletaRow } from "@/lib/catalogo/queries";
import { getCardSetByCode, getCardSetsForCartas, getCartasCompletas } from "@/lib/catalogo/queries";

/**
 * Relatório "Checklist por Coleção" (Central de Relatórios) — tratamento
 * diferenciado a partir de feedback de Fabrício (2026-08-09, modelo oficial
 * anexado, "Lista de cartas" do Pokémon Estampas Ilustradas): é o relatório
 * de maior valor para colecionadores e, futuramente, o primeiro a que
 * usuários comuns (não-admin) terão acesso — sem política de acesso ainda
 * (explicitamente adiado por Fabrício, "não se preocupe em implementar
 * política de acesso agora").
 *
 * Layout inspirado no modelo anexado, mas com marca própria (nunca logos ou
 * texto do modelo de referência, só a estrutura funcional: cabeçalho com
 * logo, lista em colunas com checkbox, legenda de raridade no rodapé) —
 * "folha" branca de largura A4 (`max-w-[210mm]`), pensada para caber numa
 * única página impressa (`@page { size: A4 }`, `globals.css`). Checkbox
 * ANTES do número (pedido explícito de Fabrício, ao contrário do modelo
 * anexado, que mostra número antes do checkbox) — desenhado em CSS
 * (`border`), não caractere Unicode, para imprimir de forma consistente
 * entre navegadores/impressoras.
 *
 * Só Cartas ativas (`getCartasCompletas` sem `incluirInativas`) — um
 * checklist para colecionador não deve listar cartas removidas do checklist
 * oficial por correção de dado; por isso também não existe mais coluna de
 * status "Cadastrada" (removida a pedido de Fabrício, "informação
 * desnecessária" neste contexto).
 *
 * Histórico de ajustes, todos no mesmo dia (2026-08-09), a partir de
 * capturas de tela reais: título movido para dentro do cabeçalho entre as
 * duas logos, renomeado de "Checklist da Coleção" para "Lista de
 * Verificação"; zebra striping (branco/`#F7F5ED`) por linha, com
 * `print-color-adjust: exact` explícito; contagem de colunas deixou de ser
 * fixa (era `columns-3`) e passou a ter um teto (`MAX_COLUNAS_A4 = 4`) com
 * piso `MIN_COLUNAS_A4 = 2` — Coleções grandes o bastante para exigir mais
 * colunas que o teto passam a imprimir em mais de uma folha A4, aceito
 * explicitamente por Fabrício; subtítulo empilhado sob o título, dentro do
 * cabeçalho; espaço entre colunas reduzido de `1.5rem` para `0.5rem`; lista
 * trocada de CSS multi-coluna (`column-count`) para uma tabela HTML real
 * (`<table>`/`<thead>`/`<tbody>`, preenchida em ordem coluna-major), porque
 * `<thead>` repete nativamente o cabeçalho em toda página impressa, ao
 * contrário de `position: fixed` (inconsistente entre navegadores).
 *
 * Aprovado por Fabrício (2026-08-09): "Checklist por Coleção aprovado.
 * Visualmente excelente." — vira a baseline visual dos outros 5 relatórios
 * da Central (cabeçalho, identidade Mimikyu, identificação da Coleção,
 * tipografia, margens, tratamento de impressão). `RelatorioFolha`,
 * `RelatorioCabecalho` e `RelatorioRodape` extraídos desta página para
 * `components/catalogo/` e reaplicados nos outros 5 relatórios — este
 * arquivo passou a importá-los em vez de manter sua própria cópia local.
 * Dois ajustes finais nesta mesma rodada: subtítulo reescrito para evitar
 * associar o relatório a posse registrada ("Use as caixas abaixo para sua
 * conferência...", não "que você já possui") — o domínio ainda é o Catálogo
 * Editorial, não uma coleção pessoal do usuário; título de volta a 18px em
 * negrito (era 16px/semibold, reduzido numa rodada anterior junto com o
 * resto da tipografia).
 *
 * Cabeçalho reorganizado em 3 linhas, mesmo dia, rodada seguinte
 * (`RelatorioCabecalho`, prop `identificacaoColecao`): identificação da
 * Coleção (`${code} · ${name}`) em destaque na linha 1, nome fixo do
 * relatório ("Lista de Verificação de Cartas") na linha 2, subtítulo na
 * linha 3 — antes o código/nome da Coleção vinha concatenado dentro do
 * próprio título ("Lista de Verificação — ME4 · Caos Ascendente"), truncando
 * cedo demais em Coleções com nome longo.
 */
// Colunas (2–4, 46 linhas por coluna), ordem coluna-major e `<thead>` repetido vivem em
// `RelatorioChecklistTabela` — padrão único reaplicado no Checklist de completude das Coleções.
const TITULO = "Lista de Verificação de Cartas";
const SUBTITULO = "Use as caixas abaixo para sua conferência das Cartas desta Coleção.";

function ChecklistLinha({ carta, index }: { carta: CartaCompletaRow; index: number }) {
  return (
    <ChecklistLinhaBase
      index={index}
      caixa={<ChecklistCaixaVazia />}
      numero={carta.collectorNumber}
      nome={carta.name}
      final={<RaritySymbol symbolCode={carta.raritySymbolCode} />}
    />
  );
}

export default async function RelatorioChecklistPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSet?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const { cardSet: cardSetCode } = await searchParams;
  const [cardSets, cardSet] = await Promise.all([
    getCardSetsForCartas(supabase),
    cardSetCode ? getCardSetByCode(supabase, cardSetCode) : Promise.resolve(null),
  ]);
  const cartas = cardSet ? await getCartasCompletas(supabase, cardSet.id) : [];

  const raridadesUnicas = Array.from(
    new Map(cartas.map((carta) => [carta.rarityCode, carta])).values(),
  ).sort((a, b) => a.rarityDisplayOrder - b.rarityDisplayOrder);

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer width="wide">
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <ClipboardList className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Checklist{cardSet ? ` — ${cardSet.code} · ${cardSet.name}` : " por Coleção"}</PageTitle>
            </div>
            <PageDescription>Lista completa das Cartas da Coleção — pensada para imprimir e conferir sua coleção física.</PageDescription>
          </PageHeading>
          {cardSet && <RelatorioPrintButton />}
        </PageHeader>

        <RelatorioColecaoSeletor cardSets={cardSets} selectedCode={cardSetCode} basePath="/catalogo/relatorios/checklist" />

        {!cardSet ? (
          <Card density="compact">
            <CardContent density="compact" className="pt-4">
              <EmptyState title="Selecione uma Coleção" description="Escolha uma Coleção acima para gerar o checklist." />
            </CardContent>
          </Card>
        ) : (
          cartas.length === 0 ? (
            <RelatorioFolha>
              <RelatorioCabecalho
                titulo={TITULO}
                subtitulo={SUBTITULO}
                identificacaoColecao={`${cardSet.code} · ${cardSet.name}`}
                colecaoLogoUrl={cardSet.logoUrl}
              />
              <div className="px-6 print:px-0">
                <EmptyState title="Nenhuma Carta cadastrada nesta Coleção" />
              </div>
              <RelatorioRodape />
            </RelatorioFolha>
          ) : (
            <RelatorioChecklistFolhas
              itens={cartas}
              cabecalho={
                <RelatorioCabecalho
                  titulo={TITULO}
                  subtitulo={SUBTITULO}
                  identificacaoColecao={`${cardSet.code} · ${cardSet.name}`}
                  colecaoLogoUrl={cardSet.logoUrl}
                />
              }
              legenda={
                raridadesUnicas.length > 0 ? (
                  // Legenda em toda folha, logo após as linhas.
                  <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-neutral-200 py-3 text-[9px] text-neutral-500">
                    {raridadesUnicas.map((rarity) => (
                      <span key={rarity.rarityCode} className="inline-flex items-center gap-1">
                        <RaritySymbol symbolCode={rarity.raritySymbolCode} /> {rarity.rarityName}
                      </span>
                    ))}
                  </div>
                ) : null
              }
              renderLinha={(carta, index) => <ChecklistLinha carta={carta} index={index} />}
            />
          )
        )}
      </PageContainer>
    </AppShell>
  );
}
