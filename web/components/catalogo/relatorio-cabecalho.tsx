/**
 * Cabeçalho compartilhado por todos os relatórios imprimíveis da Central de
 * Relatórios (2026-08-09) — extraído do Checklist por Coleção depois de
 * Fabrício aprovar seu resultado visual e pedir que ele vire a baseline dos
 * outros 5 relatórios. Logo do Mimikyu sempre à esquerda; logo da Coleção
 * (`colecaoLogoUrl`) à direita só nos relatórios que mostram o dado de uma
 * única Coleção por vez (Checklist, Resumo) — nos 4 relatórios que cruzam
 * todas as Coleções, o espaço reservado vira um espaçador vazio do mesmo
 * tamanho, para o título continuar centralizado entre os dois lados.
 *
 * Título 18px em negrito (`text-lg font-bold`) — Fabrício pediu esse valor
 * de volta depois de uma rodada anterior tê-lo reduzido para 16px/semibold
 * junto com o resto da tipografia da folha; as demais fontes (subtítulo,
 * linhas, rodapé) permanecem no tamanho reduzido daquela rodada.
 *
 * `identificacaoColecao` (2026-08-09, mesma data, rodada seguinte) — Fabrício
 * pediu 3 linhas nos relatórios de uma Coleção só (Checklist, Resumo), a
 * partir de várias capturas de tela comparadas lado a lado: identificação da
 * Coleção (ex. "ME4 · Caos Ascendente") em destaque na linha 1 — é o que um
 * colecionador procura primeiro folheando várias folhas impressas — seguida
 * do nome fixo do relatório na linha 2 (menor, sem mais concatenar o código
 * da Coleção no título) e do subtítulo já existente na linha 3. Nos 4
 * relatórios que cruzam todas as Coleções, `identificacaoColecao` fica de
 * fora e o cabeçalho continua com as 2 linhas originais (título + subtítulo).
 *
 * `ajusteCelular` (2026-11-11, `CROSS-REPORT MOBILE RESPONSIVENESS
 * CORRECTION-01`) — opcional, só nos relatórios de Coleções com conteúdo
 * próprio para celular: abaixo de 640 px de TELA o cabeçalho empilha (marca,
 * textos, logo da Coleção) e os textos quebram linha em vez de truncar, para
 * caber na largura sem virar "P…". Em 640 px ou mais — e na impressão, cuja
 * largura de página fica acima disso — vale exatamente o cabeçalho de sempre.
 * Sem a prop (Catálogo, Pricing e demais), nada muda.
 */
export function RelatorioCabecalho({
  titulo,
  subtitulo,
  identificacaoColecao,
  colecaoLogoUrl = null,
  ajusteCelular = false,
}: {
  titulo: string;
  subtitulo: string;
  identificacaoColecao?: string;
  colecaoLogoUrl?: string | null;
  /** Empilha e quebra linha em telas estreitas (< 640 px); impressão e telas largas inalteradas. */
  ajusteCelular?: boolean;
}) {
  // Sem `ajusteCelular`: as classes de sempre. Com ela: as mesmas a partir de `sm`, e empilhado/quebrando abaixo.
  const linha = ajusteCelular ? "max-sm:whitespace-normal max-sm:[overflow-wrap:anywhere] sm:truncate" : "truncate";
  return (
    <div className={ajusteCelular ? "px-6 pb-3 pt-6 max-sm:px-4 print:px-0 print:pt-0" : "px-6 pb-3 pt-6 print:px-0 print:pt-0"}>
      <header
        className={
          ajusteCelular
            ? "flex items-center justify-between gap-4 border-b-4 border-primary pb-3 max-sm:flex-col max-sm:gap-2"
            : "flex items-center justify-between gap-4 border-b-4 border-primary pb-3"
        }
      >
        {/* eslint-disable-next-line @next/next/no-img-element -- asset estático local, mesmo padrão de <img> já usado para logos assinadas de Card Set */}
        <img src="/brand/logo-full-light.png" alt="Mimikyu" className="h-7 w-auto shrink-0 object-contain" />
        <div className={ajusteCelular ? "min-w-0 flex-1 px-2 text-center max-sm:w-full max-sm:flex-none" : "min-w-0 flex-1 px-2 text-center"}>
          {identificacaoColecao && (
            <p className={`${linha} font-heading text-lg font-bold text-neutral-900`}>{identificacaoColecao}</p>
          )}
          {identificacaoColecao ? (
            <p className={`${linha} text-sm font-medium text-neutral-600`}>{titulo}</p>
          ) : (
            <h2 className={`${linha} font-heading text-lg font-bold text-neutral-900`}>{titulo}</h2>
          )}
          <p className={`${linha} text-[9px] text-neutral-500`}>{subtitulo}</p>
        </div>
        {colecaoLogoUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- URL assinada do Storage
          <img src={colecaoLogoUrl} alt="" className="h-12 w-auto shrink-0 object-contain" />
        ) : (
          <span className={ajusteCelular ? "h-7 w-7 shrink-0 max-sm:hidden" : "h-7 w-7 shrink-0"} aria-hidden="true" />
        )}
      </header>
    </div>
  );
}
