import type { CSSProperties } from "react";
import { MmkyuWordmark } from "./wordmark";

/**
 * Capa fechada do BINDER-NAV-01 — Rodada 8 (2026-08-28), refinamento pedido
 * por Fabrício a partir de fotos reais de um binder PRETO com zíper
 * (referência mais recente, substituindo a referência marrom/couro usada
 * nas Rodadas 1-7). Cópia local, NÃO edição de `binder-spike/binder-cover.tsx`
 * — aquele componente continua servindo Binder-First/BINDER-VIS-02 e os
 * spikes de motion encerrados exatamente como estava (isolamento
 * experimental total, mesmo padrão já aplicado a todo o resto de
 * `binder-nav-01/`).
 *
 * Mudanças pedidas explicitamente por Fabrício nesta rodada:
 *  1. Preto/grafite muito escuro (não mais o marrom `LEATHER_HUE=26` do
 *     Binder-First) — `BLACK_HUE` quase acromático.
 *  2. Removido o escudo central (glifo SVG) — substituído por wordmark
 *     tipográfico "MMKYU" discreto, debossed, canto inferior esquerdo.
 *  3. Removido o bolso frontal — não existe na referência preta.
 *  4. Zíper/puxador recoloridos para metal escuro/grafite (antes dourado).
 *  5. Cantos mais arredondados, costura periférica mais discreta.
 * O glow/halo dourado ambiente foi tratado em `binder-nav-view.tsx`, não
 * aqui — é um efeito de palco atrás do objeto, não da capa em si.
 *
 * TENTATIVAS DE 3/4 EM "2D FORJADO" (2026-08-29, REVERTIDAS/ABANDONADAS) —
 * três rodadas seguidas tentando simular perspectiva de 3/4 com gradientes e
 * `clip-path` calculados à mão (v1: duas caixas com borda própria cada —
 * "ficou muito feio", emenda visível; v2: superfície única com overlay
 * translúcido — "não gostei do resultado", leu como plano achatado; v3:
 * dois trapézios com `clip-path` compartilhando fundo — REJEITADA com
 * veemência: "Esse foi o horroroso resultado", triângulos pretos nos
 * cantos onde o trapézio não cobria a "espessura traseira" por baixo).
 * Diagnóstico correto, confirmado por pesquisa externa (ver skill
 * `product-mockup` instalada em 2026-08-29, `github.com/ArnavPuri/
 * designskills`): perspectiva forjada com `clip-path`/gradiente não tem
 * geometria real por trás — é ilusão pintada à mão, e qualquer
 * desalinhamento entre as coordenadas escolhidas manualmente vira um
 * artefato visível. A técnica correta é 3D real do CSS.
 *
 * RODADA 9 — 3D REAL (2026-08-29) — reconstrução total a partir de 3 fotos
 * de referência do produto físico (preto, vermelho+preto, amarelo+preto,
 * mesmo modelo de fichário com zíper) e da skill `product-mockup` recém-
 * instalada. Abandona de vez `clip-path`/trapézio: agora são duas FACES
 * REAIS em 3D (`perspective` no elemento pai + `transform-style:
 * preserve-3d` + `rotateY` no objeto + `translateZ`/`translateX` por face,
 * exatamente o padrão "Packaging Visualization (3D Box)" da skill), então:
 *  - o navegador calcula a projeção de verdade — não há trapézio calculado
 *    à mão, logo não há como duas coordenadas desalinharem e abrir um
 *    triângulo preto como na v3;
 *  - como a rotação é só em Y (sem tilt em X), topo e base das duas faces
 *    permanecem perfeitamente retos e alinhados — a causa exata dos
 *    triângulos da v3 (arestas de topo/base inclinadas de forma
 *    independente em cada elemento) deixou de existir;
 *  - as referências novas mostram que o binder NÃO tem uma lombada larga
 *    separada à esquerda (diferença das Rodadas 1-8: aqui é só CAPA
 *    FRONTAL + FAIXA DE PROFUNDIDADE à direita, onde mora o zíper) — a
 *    borda esquerda da capa frontal é só uma curva sutil (`box-shadow`),
 *    não um painel próprio; isso também remove de vez a classe de bug
 *    "emenda lombada×capa" que gerou 3 correções nas rodadas anteriores;
 *  - cor continua 100% parametrizada por `BLACK_HUE` — as duas faces usam
 *    a MESMA função de textura com lightness diferente (capa mais clara,
 *    já que é a face principal que pega luz; profundidade mais escura,
 *    face lateral em sombra), o mesmo princípio de `color-mix()` por face
 *    que a skill usa, sem precisar de uma variável de cor por face.
 *  - `BLACK_HUE`, `blackLeatherSurface()` e `darkZipperTeeth()` continuam
 *    EXPORTADOS COM O MESMO NOME/ASSINATURA e SEM NENHUMA MUDANÇA DE
 *    COMPORTAMENTO — `binder-pages-nav.tsx` os usa para a MOLDURA do
 *    binder ABERTO ("não alterar o estado aberto", pedido explícito desta
 *    rodada). A textura nova (mais "tecido sintético/nylon", pedido desta
 *    rodada) vive em `closedCoverWeave()`, uma função LOCAL, não exportada,
 *    usada só pelas duas faces da capa fechada — isolamento total entre os
 *    dois estados, igual ao padrão já usado no resto de `binder-nav-01/`.
 */

export const BLACK_HUE = 30; // leve calor neutro — evita ler como preto 100% chapado/plástico

// Exportados para reuso em `binder-pages-nav.tsx` — a moldura interna (borda,
// zíper, puxador) do binder ABERTO precisa da MESMA paleta preta da capa
// fechada. Mantidos exatamente como estavam: mudar esta função mudaria
// também o binder aberto, fora do escopo desta rodada.
export function blackLeatherSurface() {
  return [
    "repeating-linear-gradient(115deg, hsl(0 0% 100% / 0.025) 0px, hsl(0 0% 100% / 0.025) 1px, transparent 1px, transparent 2.5px)",
    "repeating-linear-gradient(25deg, hsl(0 0% 0% / 0.05) 0px, hsl(0 0% 0% / 0.05) 1px, transparent 1px, transparent 3px)",
    "linear-gradient(125deg, hsl(0 0% 100% / 0.05) 0%, transparent 26%)",
    `linear-gradient(155deg, hsl(${BLACK_HUE} 6% 13%) 0%, hsl(${BLACK_HUE} 5% 8%) 55%, hsl(${BLACK_HUE} 6% 4%) 100%)`,
  ].join(", ");
}

export function darkZipperTeeth(vertical: boolean) {
  const angle = vertical ? "180deg" : "90deg";
  return `repeating-linear-gradient(${angle}, hsl(0 0% 42%) 0px, hsl(0 0% 42%) 1.5px, hsl(0 0% 10%) 1.5px, hsl(0 0% 10%) 3px)`;
}

// Textura LOCAL da capa fechada — trama fina cruzada, lendo mais como tecido
// sintético/nylon do que o grão de couro de `blackLeatherSurface()`.
// NÃO exportada de propósito: só as duas faces 3D abaixo usam isto, o
// binder aberto continua com `blackLeatherSurface()` inalterada.
//
// RODADA 11 (2026-08-29) — a Rodada 10 superestimou o pedido de "trama mais
// visível": o resultado leu como um padrão gráfico repetido (Fabrício:
// "aspecto renderizado/estilizado", "carbon-like", "brilho artificial"),
// exatamente o oposto de "tecido sintético premium discreto e realista"
// pedido agora. Correção, não reversão pura: mantém ALGUMA textura (não pode
// virar capa lisa chapada, outro item explícito do pedido), mas derruba a
// opacidade das listras cruzadas para quase imperceptível (~0.02, pitch de
// 1px) e troca o ângulo 45/135 (crosshatch simétrico = exatamente a
// assinatura visual de fibra de carbono) por 23/157 — permanece uma leve
// textura de fundo, não um padrão que o olho reconhece como estampa. A sheen
// de luz também deixou de ser uma faixa diagonal difusa (lia como reflexo
// artificial) e virou um radial suave ancorado no canto superior esquerdo,
// como luz de estúdio incidindo sobre tecido fosco, não brilho de verniz.
function closedCoverWeave(lightness: [number, number, number]) {
  return [
    "radial-gradient(135% 90% at 20% 6%, hsl(0 0% 100% / 0.05) 0%, transparent 46%)",
    "repeating-linear-gradient(23deg, hsl(0 0% 100% / 0.018) 0px, hsl(0 0% 100% / 0.018) 1px, transparent 1px, transparent 2px)",
    "repeating-linear-gradient(157deg, hsl(0 0% 0% / 0.03) 0px, hsl(0 0% 0% / 0.03) 1px, transparent 1px, transparent 2px)",
    `linear-gradient(150deg, hsl(${BLACK_HUE} 6% ${lightness[0]}%) 0%, hsl(${BLACK_HUE} 5% ${lightness[1]}%) 55%, hsl(${BLACK_HUE} 6% ${lightness[2]}%) 100%)`,
  ].join(", ");
}

// Geometria da cena 3D real (Rodada 9). `DEPTH_CQW` é a espessura da faixa
// de profundidade em `cqw` (1cqw = 1% da largura do container mais próximo
// com `container-type`, ver `stageStyle` abaixo) — escala junto com o
// binder em vez de ficar em px fixo, sem precisar de JS/ResizeObserver.
// `ROTATE_DEG` é sutil de propósito: nas 3 fotos de referência o binder
// está quase de frente, só o suficiente para revelar a faixa de
// profundidade e o zíper à direita.
// Correção de geometria (mesma Rodada 9, mesmo dia) — com `ROTATE_DEG=-13`
// e `DEPTH_CQW=12` a faixa de profundidade ficou correta na ANCORAGEM (sem
// vão, ver correção anterior) mas quase invisível: uma face girada 90° em
// torno de si mesma (para encarar o lado) e depois só mais 13° pelo objeto
// como um todo fica a ~77° de distância de encarar a câmera — o fator de
// encurtamento visual de uma face nesse ângulo é `sin(13°) ≈ 0.225`, ou
// seja, ela aparece ~4,4× mais estreita do que a largura real. Isso é
// matemática de projeção 3D, não um bug de posicionamento: qualquer objeto
// real fotografado quase de frente (rotação pequena) mostra só uma lasca
// da face lateral. As fotos de referência mostram uma faixa de
// profundidade claramente larga — ou seja, elas foram fotografadas com uma
// rotação bem maior do que 13°. Fix: `ROTATE_DEG` sobe para -28° (ainda
// lê como "quase de frente", mas o suficiente para `sin(28°) ≈ 0.469`, o
// dobro de visibilidade) e `DEPTH_CQW` sobe para 20 (era 12) para a faixa
// projetada ficar em ~9-10% da largura da capa frontal, batendo com a
// proporção observada nas referências.
const DEPTH_CQW = 20;
const ROTATE_DEG = -28;
const RADIUS_PX = 20;
// Largura local da fatia da "traseira" (RODADA 13) — pequena de propósito,
// já que ela é só uma lasca visível além da faixa do zíper (ver comentário
// completo junto à face em `BinderCoverClosed`). Ao contrário das Rodadas
// 11/12 (uma face solta empurrada em Z, sem aresta compartilhada — daí o
// vão visível), esta nasce ENCOSTADA na aresta da própria faixa do zíper
// pela mesma técnica de aninhamento/`transform-origin` já usada ali.
const BACK_CQW = 8;
// RODADA 14 (2026-08-29, tentativa REVERTIDA): diagnóstico correto de que
// um canto arredondado de um lado da emenda encontrando um canto reto do
// outro sempre deixa um entalhe — mas a correção testada (zerar os dois
// lados de TODA emenda interna, deixando curva só nas 2 extremidades
// externas do objeto inteiro) foi longe demais: Fabrício reportou o
// resultado como "parecendo uma caixa", cantos sem curvatura nenhuma.
// RODADA 15 (correta): o problema nunca foi "ter curva na emenda" — foi
// MISMATCH de raio entre os dois lados da mesma emenda. A correção é usar
// este MESMO raio nos dois lados de cada emenda interna (canto direito da
// capa E canto esquerdo da faixa usam `DEPTH_RADIUS_PX`; canto direito da
// faixa E canto esquerdo da traseira também usam `DEPTH_RADIUS_PX`), para
// a curva continuar sem saltar para um canto reto. Só o canto esquerdo da
// capa (extremidade externa de verdade, sem vizinho) e o canto direito da
// traseira (idem, outra ponta da cadeia) ficam de fora dessa regra — o
// primeiro usa o raio grande `RADIUS_PX`, o segundo reusa este mesmo
// `DEPTH_RADIUS_PX` por proporção (lasca fina, raio grande ficaria
// desproporcional).
// RODADA 16 (2026-08-29, tentativa REVERTIDA): tentei 15px + sombras de
// contato mais fracas (0.55/0.6→0.3) pra resolver "zíper parecendo solto"
// e "traseira separada". Fabrício reportou o resultado como AINDA MAIS
// distante do esperado — pior que a Rodada 15, não melhor. Revertido sem
// adivinhar um quarto valor às cegas: neste ambiente eu não consigo
// renderizar/ver o resultado real (sandbox sem `npm run dev` funcional),
// só itero por descrição/screenshot que o Fabrício manda depois. Duas
// hipóteses foram registradas na hora, mas a primeira partia de uma
// premissa de geometria ERRADA (corrigida na Rodada 17 abaixo).
// RODADA 17 (2026-08-29): revendo o código, a "faixa-visual" (wrapper de
// profundidade) NÃO é ~20cqw menos o espaço da traseira — ela ocupa os
// `DEPTH_CQW` (20cqw) inteiros via `absolute inset-0`; a traseira
// (`BACK_CQW`=8cqw) é uma faixa IRMÃ, adicional, plugada em `left: 100%`
// depois dela, não um recorte por dentro dela. Ou seja, a hipótese de
// "pílula/cápsula" da Rodada 16 (raio perto da metade da largura) partia
// de uma largura efetiva incorreta — com 20cqw inteiros, 15px está longe
// de metade da largura na maioria dos tamanhos de palco, então
// provavelmente não foi essa a causa da piora. Fabrício pediu para
// priorizar especificamente a curva do zíper nesta rodada (não a
// separação capa↔traseira). Para isolar a variável depois do reverte
// bagunçado da Rodada 16 (raio + sombra ao mesmo tempo), esta rodada
// muda SÓ o raio — sombras e cores continuam idênticas à Rodada 15 — e
// sobe de forma mais comedida (9→12, não 9→15 de novo) para testar um
// incremento menor antes de repetir um salto já reportado como pior.
const DEPTH_RADIUS_PX = 12;

// RODADA 22 (2026-08-29). Fabrício, comparando com o modelo 3D de
// referência que ele mesmo montou (`binder-3d.html`, Three.js): "a parte
// frontal da capa não avança em relação a parte do zíper, como faz bem a
// capa traseira". No modelo dele isso é geometria real: a capa é uma
// almofada abaulada (`pillowCapGeo`/`DOME`) que fica por CIMA de um canal
// de zíper recuado (`wallGeo` com inset `REC`) — a capa literalmente
// avança/sobra sobre o canal. Aqui a capa e a faixa do zíper sempre
// estiveram na MESMA profundidade Z na emenda (união "por construção",
// sem vão, mas também sem NENHUM degrau) — por isso a faixa nunca lia como
// recuada em relação à capa, só como uma virada de 90° no mesmo nível. A
// traseira, em contraste, já tinha esse efeito "de graça": por estar
// aninhada mais um nível abaixo (90°+90° = voltada pra trás) com uma
// largura (`BACK_CQW`) bem menor que a espessura total (`DEPTH_CQW`), a
// combinação de rotações + posição já produzia um recuo real perceptível.
// Fix: em vez de mexer na relação faixa↔traseira (que já está certa),
// recuo SÓ na relação capa↔faixa — um `translateZ` aplicado a um wrapper
// extra por FORA da rotação em Y da faixa (não dentro dela). Isso importa:
// um `translateZ` aplicado DEPOIS que o elemento já girou 90° em Y não
// desloca mais em profundidade de verdade — os eixos giraram junto, então
// viraria um deslocamento lateral, não um recuo (conferido por álgebra de
// matrizes antes de aplicar, não só por tentativa). Por isso o recuo entra
// num wrapper novo, ENVOLVENDO o wrapper de rotação existente (que
// continua fazendo exatamente o que já fazia, só que agora recebe esse
// recuo herdado do pai) — a faixa, a `EmendaCurva` faixa↔traseira e a
// própria traseira migram juntas para trás como um bloco só, preservando
// intacta a relação interna faixa↔traseira que já funcionava bem. A
// `EmendaCurva` capa↔faixa (que fica FORA deste wrapper, na mesma
// profundidade da capa) não precisa mudar de lugar — ao ficar parada
// enquanto a faixa recua atrás dela, ela passa a fazer o papel da aba que
// avança sobre o canal recuado, exatamente o efeito pedido.
const ADVANCE_CQW = 1.4;

const stageStyle: CSSProperties = {
  width: "clamp(240px, min(80vw, 58dvh), 480px)",
  // 26cm × 35cm — proporção física real do binder (referência técnica de
  // dimensões aprovada por Fabrício: "Seguir a referência à risca").
  aspectRatio: "26 / 35",
  // Habilita as unidades `cqw` usadas abaixo (perspective/translateZ/
  // translateX) — precisam ser um comprimento de verdade, `%` não é válido
  // em `translateZ`.
  containerType: "inline-size",
};

export function BinderCoverClosed({ viewTransitionName }: { viewTransitionName?: string }) {
  return (
    <div className="relative" style={{ ...stageStyle, viewTransitionName }}>
      <div
        className="absolute inset-0"
        style={{ filter: "drop-shadow(0 34px 40px rgba(0,0,0,0.5)) drop-shadow(0 10px 14px rgba(0,0,0,0.35))" }}
      >
        {/* `perspective` no pai + `transform-style: preserve-3d` no objeto —
            3D real do CSS (padrão "Packaging Visualization" da skill
            `product-mockup`), não uma aproximação em 2D. */}
        <div className="absolute inset-0" style={{ perspective: "460cqw" }}>
          <div
            className="absolute inset-0"
            style={{ transformStyle: "preserve-3d", transform: `rotateY(${ROTATE_DEG}deg)` }}
          >
            {/* Capa frontal — face principal, pega mais luz (tom mais claro). */}
            <div
              className="absolute inset-0 overflow-hidden"
              style={{
                // RODADA 14 (tentativa, REVERTIDA): zerar os 2 lados de toda
                // emenda interna eliminou o entalhe, mas Fabrício reportou o
                // resultado como "parecendo uma caixa" — sem curva nenhuma
                // além dos 2 cantos externos, a silhueta lê como bloco
                // retangular, não como fichário. A instrução original dele
                // ("as extremidades do meio precisam ACOMPANHAR a curvatura
                // da capa") pedia para a faixa seguir a curva, não para a
                // capa perder a sua.
                // RODADA 15 (correta): o entalhe não vem de "ter curva na
                // emenda" — vem de um MISMATCH de raio entre os dois lados
                // da mesma emenda (um lado curva, o outro fica reto, sobra
                // triângulo). A correção é usar O MESMO raio dos dois lados
                // de cada emenda interna, para a curva continuar em vez de
                // saltar para um canto reto. Por isso o canto direito da
                // capa (emenda com a faixa) usa `DEPTH_RADIUS_PX` — o MESMO
                // valor que a faixa usa no seu canto esquerdo, mais abaixo
                // — e não mais 0. Só o canto esquerdo (extremidade externa
                // de verdade, sem vizinho) mantém o raio grande de destaque
                // (`RADIUS_PX`).
                borderTopLeftRadius: RADIUS_PX,
                borderBottomLeftRadius: RADIUS_PX,
                // RODADA 19 (2026-08-29, tentativa REVERTIDA em parte): com
                // acesso de tela ao vivo pela primeira vez, vi um vão
                // TRIANGULAR literal (cor de fundo aparecendo) na emenda —
                // causa geométrica real: dois retângulos 2D encostados com
                // raio no MESMO canto compartilhado (mesmo raio IGUAL nos
                // dois lados, premissa errada da Rodada 15) recuam do ponto
                // do canto ao mesmo tempo, sobra vão de até 2×raio. Zerar
                // os dois lados eliminava o vão mas Fabrício rejeitou o
                // resultado: "perdemos um requisito importante... não quero
                // parecendo um livro ou uma caixa" — cantos retos na emenda
                // leem como caixa mesmo sem vão nenhum.
                // RODADA 20: volta o raio aqui (curva real na emenda), e o
                // vão que isso reabre é coberto por uma peça extra —
                // `EmendaCurva` abaixo, um pedaço fino e arredondado que
                // fica bem em cima da linha da emenda, na MESMA profundidade
                // Z desta capa. Ver comentário completo junto a ela.
                borderTopRightRadius: DEPTH_RADIUS_PX,
                borderBottomRightRadius: DEPTH_RADIUS_PX,
                transform: `translateZ(${DEPTH_CQW / 2}cqw)`,
                backgroundImage: closedCoverWeave([15, 10, 6]),
                boxShadow: [
                  "inset 0 1px 0 hsl(0 0% 100% / 0.08)",
                  "inset 0 -3px 10px hsl(0 0% 0% / 0.5)",
                  // Curva sutil na borda esquerda — nas referências não há
                  // lombada separada, só um leve highlight sugerindo o
                  // material curvando (ver nota "RODADA 9" no topo).
                  "inset 2px 0 0 hsl(0 0% 100% / 0.05)",
                  // Sombra de contato onde a capa encontra a faixa de
                  // profundidade (aresta real em 3D, não mais um "vinco"
                  // pintado à mão sobre uma superfície plana). RODADA 16
                  // tentou suavizar (0.55→0.3) e o resultado ficou PIOR
                  // ("mais distante do esperado") — hipótese registrada
                  // junto a `DEPTH_RADIUS_PX`: essa sombra provavelmente é
                  // o que vende a ilusão de dobra contínua; suavizar
                  // demais deixa tudo mais chapado, não menos separado.
                  // Revertido ao valor original.
                  "inset -7px 0 10px -7px hsl(0 0% 0% / 0.55)",
                ].join(", "),
              }}
            >
              {/* Costura periférica — discreta. */}
              <div
                className="pointer-events-none absolute rounded-xl"
                style={{ inset: 9, border: "1.25px dashed hsl(0 0% 100% / 0.1)" }}
                aria-hidden
              />

              {/* Identidade — wordmark tipográfico, canto inferior esquerdo,
                  debossed/baixo contraste (não centralizado, sem escudo). */}
              <div className="absolute bottom-[7%] left-[9%]" aria-hidden>
                <MmkyuWordmark size="sm" tone={`hsl(${BLACK_HUE} 5% 24%)`} />
              </div>
            </div>

            {/* EmendaCurva (capa↔faixa) — RODADA 20 (2026-08-29), estilo
                RODADA 21 (2026-08-29). A capa e a faixa (abaixo) mantêm
                `DEPTH_RADIUS_PX` nos dois lados da emenda (curva real
                preservada — Rodada 19 zerava o raio pra eliminar o vão, mas
                isso lia como canto de livro e foi rejeitado). Esta peça
                tampa o vão triangular que esse raio duplo reabre: mesma
                largura/posição/Z da Rodada 20, mas agora estilizada como
                sulco/gutter físico em vez de "remendo" que tenta imitar a
                textura ao redor. Fabrício trouxe um modelo 3D real (Three.js,
                `binder-3d.html`) feito no Claude Design como referência: lá
                a emenda nunca tenta ser invisível — é um canal recuado de
                verdade (`wallGeo` com inset), e o que se vê na emenda é
                justamente esse sulco escuro, com uma aresta clara fina de
                cada lado onde a luz pega a borda arredondada. Reproduzindo
                esse resultado em 2D: duas camadas de gradiente por cima da
                textura-base — uma linha clara sutil bem na borda (imita a
                luz pegando o canto), e uma faixa escura concentrada no
                centro (o fundo do sulco) — em vez de uma única cor lisa
                tentando casar com os dois lados. */}
            <div
              className="pointer-events-none absolute inset-y-0"
              style={{
                left: `calc(100% - ${DEPTH_RADIUS_PX}px)`,
                width: DEPTH_RADIUS_PX * 2,
                borderRadius: DEPTH_RADIUS_PX,
                // RODADA 23 (2026-08-29): Fabrício reportou que a costura
                // vertical da capa (lado do zíper) sumiu, "como se a peça do
                // zíper estivesse por cima". Causa: esta peça e a capa
                // sempre estiveram na MESMA profundidade Z (DEPTH_CQW/2);
                // como ficam coplanares, o navegador desempata a pintura
                // pela ordem no DOM — e esta div vem depois da capa no JSX,
                // então pinta por cima dos últimos 12px da capa (mais do que
                // os 9px de inset da costura periférica), apagando o trecho
                // vertical da linha tracejada ali. Fix: recuar esta peça
                // 1px atrás da capa em Z. Isso não é visível como degrau
                // (1px é imperceptível na profundidade), mas é suficiente
                // para o navegador fazer compositing 3D real por
                // profundidade em vez de cair no desempate por ordem do
                // DOM — a capa (com a costura) passa a pintar na frente em
                // toda a área onde as duas se sobrepõem, e esta peça só
                // aparece exatamente no vão que ela existe pra tampar
                // (onde a curva da capa não cobre nada).
                transform: `translateZ(calc(${DEPTH_CQW / 2}cqw - 1px))`,
                backgroundImage: [
                  "linear-gradient(90deg, hsl(0 0% 100% / 0.08) 0%, transparent 22%, transparent 78%, hsl(0 0% 100% / 0.08) 100%)",
                  "linear-gradient(90deg, transparent 0%, hsl(0 0% 0% / 0.55) 38%, hsl(0 0% 0% / 0.78) 50%, hsl(0 0% 0% / 0.55) 62%, transparent 100%)",
                  closedCoverWeave([11, 7, 4]),
                ].join(", "),
                boxShadow: [
                  "inset 3px 0 5px hsl(0 0% 0% / 0.5)",
                  "inset -3px 0 5px hsl(0 0% 0% / 0.5)",
                ].join(", "),
              }}
              aria-hidden
            />

            {/* Faixa de profundidade — face lateral real em 3D (não
                clip-path), onde mora o zíper. Face em sombra, tom mais
                escuro.
                Nota de correção (mesma Rodada 9, mesmo dia): a primeira
                versão copiou a fórmula da skill ao pé da letra
                (`rotateY(90deg) translateZ(W) translateX(-D/2)` com
                `transform-origin` padrão no centro do próprio elemento) —
                Fabrício reportou o resultado como uma linha fina flutuando
                solta à direita, sem tocar a capa. Conferindo a matemática
                (rotação em torno do CENTRO do elemento, não da aresta),
                essa fórmula da skill realmente deixa um vão entre as duas
                faces — não é um erro de digitação nosso, a fórmula em si
                pressupõe outra convenção de origem. Fix: em vez de
                compensar com `translateZ`/`translateX` a partir do centro,
                a faixa nasce ENCOSTADA na capa em layout plano (`left:
                100%` do objeto, que tem a largura da capa) e gira em torno
                da própria ARESTA esquerda (`transformOrigin: "0% 50%"`) —
                como a aresta de rotação já é o ponto de encontro com a
                capa, `rotateY(90deg) translateX(-D/2)` (sem `translateZ`
                nenhum) basta para reencaixar a aresta girada exatamente
                onde a capa termina (conferido por conta própria ponto a
                ponto antes de aplicar, não só copiado da referência). */}
            <div
              className="absolute inset-y-0 left-full"
              style={{
                width: `${DEPTH_CQW}cqw`,
                // RODADA 22: recuo em Z por FORA da rotação — ver comentário
                // completo junto a `ADVANCE_CQW`. Este wrapper NÃO gira;
                // só empurra pra trás o wrapper de rotação logo abaixo.
                transform: `translateZ(-${ADVANCE_CQW}cqw)`,
                transformStyle: "preserve-3d",
              }}
            >
            <div
              className="absolute inset-0"
              style={{
                transformOrigin: "0% 50%",
                transform: `rotateY(90deg) translateX(-${DEPTH_CQW / 2}cqw)`,
                // RODADA 13 ("três peças soltas"): a traseira da Rodada 12
                // era uma face independente (cópia da capa só empurrada em
                // Z) — sem NENHUMA aresta compartilhada com esta faixa, seu
                // canto ficava flutuando a uma distância arbitrária daqui,
                // abrindo um vão visível (exatamente o que Fabrício reportou
                // como "três peças soltas"). Fix real: a traseira agora
                // NASCE ENCOSTADA na aresta DESTA faixa (mesmo truque
                // `left: 100%` + `transformOrigin: 0% 50%` que já uniu a
                // capa a esta faixa, aplicado de novo, um nível abaixo) e
                // herda esta rotação por estar aninhada aqui dentro
                // (`transform-style: preserve-3d` neste nível) — por
                // construção não pode sobrar vão, é a mesma técnica provada,
                // não uma cópia solta. Esta faixa deixou de ter
                // `overflow-hidden`/fundo/sombra própria: quem carrega isso
                // agora é o filho abaixo (`faixa-visual`), para a traseira
                // (irmã dele, não descendente) não ficar cortada pelo
                // overflow.
                transformStyle: "preserve-3d",
              }}
            >
              <div
                className="absolute inset-0 overflow-hidden"
                style={{
                  // RODADA 15: os 4 cantos usam `DEPTH_RADIUS_PX` — o MESMO
                  // valor usado no canto direito da capa (emenda à
                  // esquerda) e no canto esquerdo da traseira (emenda à
                  // direita, ver `back-panel` mais abaixo). Raio igual dos
                  // dois lados de cada emenda = a curva continua em vez de
                  // saltar pra um canto reto (isso é o que evita o
                  // entalhe); zerar os dois lados (Rodada 14) tirava o
                  // entalhe mas também tirava toda curvatura do objeto,
                  // lendo como caixa — o que Fabrício rejeitou.
                  // RODADA 19 (tentativa revertida): zero nos dois lados
                  // desta faixa evitava o vão mas lia como caixa — rejeitado
                  // por Fabrício. RODADA 20: raio de volta nos 4 cantos; o
                  // vão reaberto é coberto pelas peças `EmendaCurva` (ver
                  // comentário completo junto à peça entre capa e faixa,
                  // acima, e à peça entre faixa e traseira, abaixo).
                  borderTopLeftRadius: DEPTH_RADIUS_PX,
                  borderBottomLeftRadius: DEPTH_RADIUS_PX,
                  borderTopRightRadius: DEPTH_RADIUS_PX,
                  borderBottomRightRadius: DEPTH_RADIUS_PX,
                  // RODADA 18 (2026-08-29): depois de subir o raio (Rodada
                  // 17), Fabrício reportou "melhorou, mas o zíper não
                  // acompanha a curvatura da capa... fica solta". Causa
                  // provável, revendo `closedCoverWeave()`: o gradiente de
                  // luz embutido nela é `linear-gradient(150deg, ...)` —
                  // quase vertical (mais claro no topo, mais escuro embaixo),
                  // IGUAL nas 3 faces. Isso funciona pra capa (encarada de
                  // quase frente), mas não dá nenhuma pista de que ESTA
                  // faixa estreita está virando de lado — falta um gradiente
                  // HORIZONTAL (claro perto da emenda com a capa, escurecendo
                  // até a emenda com a traseira) pra ler como superfície
                  // curva se afastando da luz, não como painel chapado colado
                  // ao lado. Raio certo (Rodada 17) resolve a SILHUETA da
                  // curva; faltava o SOMBREAMENTO da curva — são pistas
                  // visuais diferentes. Adiciono essa camada extra por cima
                  // da textura existente (sem tocar raio/sombra de contato já
                  // validados) para não misturar duas variáveis de novo.
                  backgroundImage: [
                    "linear-gradient(90deg, hsl(0 0% 100% / 0.06) 0%, transparent 24%, transparent 60%, hsl(0 0% 0% / 0.42) 100%)",
                    closedCoverWeave([8, 5, 2]),
                  ].join(", "),
                  // RODADA 16 tentou reduzir esta sombra (0.55→0.3) e
                  // piorou a leitura geral — revertido ao valor original,
                  // ver hipótese junto a `DEPTH_RADIUS_PX`.
                  boxShadow: [
                    "inset 3px 0 6px hsl(0 0% 0% / 0.55)",
                    "inset -2px 0 0 hsl(0 0% 100% / 0.04)",
                  ].join(", "),
                }}
              >
              {/* Canal do zíper — sulco raso por baixo dos dentes.
                  RODADA 11: a Rodada 10 tinha adicionado listras diagonais
                  extra aqui para simular "franzido" — mas isso contribuiu
                  para a leitura de "padrão gráfico artificial" rejeitada
                  por Fabrício ("não usar textura chamativa"). Removido:
                  volta a ser só o gradiente de profundidade + inset shadow,
                  um canal embutido e discreto, sem textura própria — o
                  zíper e a costura ao lado já carregam o detalhe real. */}
              <div
                className="pointer-events-none absolute inset-y-[9%] left-1/2 w-[46%] -translate-x-1/2 rounded-full"
                style={{
                  boxShadow: "inset 2px 0 4px rgba(0,0,0,0.6), inset -1px 0 3px rgba(0,0,0,0.4)",
                  background: `linear-gradient(90deg, hsl(${BLACK_HUE} 6% 9%) 0%, hsl(${BLACK_HUE} 5% 3%) 55%, hsl(${BLACK_HUE} 6% 6%) 100%)`,
                }}
              />
              {/* Costura ladeando o canal — a foto em detalhe mostra pesponto
                  visível dos dois lados do zíper, não só na borda externa da
                  faixa. */}
              <div
                className="pointer-events-none absolute inset-y-[9%]"
                style={{ left: "27%", borderLeft: "1px dashed hsl(0 0% 100% / 0.12)" }}
                aria-hidden
              />
              <div
                className="pointer-events-none absolute inset-y-[9%]"
                style={{ right: "27%", borderLeft: "1px dashed hsl(0 0% 100% / 0.12)" }}
                aria-hidden
              />
              {/* Zíper — trilha vertical, correndo pela faixa de profundidade. */}
              <div
                className="pointer-events-none absolute inset-y-[10%] left-1/2 w-[12%] -translate-x-1/2 rounded-full"
                style={{ backgroundImage: darkZipperTeeth(true), boxShadow: "0 0 1px rgba(0,0,0,0.6)" }}
              />
              {/* Puxador — RODADA 10: a foto em detalhe mostra um puxador
                  compacto e alongado (não uma barra larga e achatada),
                  redesenhado como pill metálico com friso central sugerindo
                  a fita dobrada. Altura em `cqw` (não `px`) para escalar
                  junto com o binder, igual ao resto da geometria 3D. */}
              <div
                className="pointer-events-none absolute left-1/2 top-[7%] -translate-x-1/2 overflow-hidden rounded-full"
                style={{
                  width: "20%",
                  height: "2.6cqw",
                  background: "linear-gradient(180deg, hsl(0 0% 52%) 0%, hsl(0 0% 30%) 45%, hsl(0 0% 13%) 100%)",
                  boxShadow: [
                    "0 1.5px 3px rgba(0,0,0,0.6)",
                    "inset 0 1px 0 hsl(0 0% 100% / 0.25)",
                    "inset 0 -1px 1px hsl(0 0% 0% / 0.4)",
                  ].join(", "),
                }}
                aria-hidden
              >
                <div
                  className="absolute inset-y-0 left-1/2 w-px -translate-x-1/2"
                  style={{ background: "hsl(0 0% 0% / 0.35)" }}
                />
              </div>
              </div>

              {/* EmendaCurva (faixa↔traseira) — RODADA 20, mesma lógica da
                  peça capa↔faixa (ver comentário completo lá em cima). Fica
                  dentro deste MESMO wrapper (herda o `rotateY(90deg)` da
                  faixa, sem transform própria) — no plano da faixa/traseira,
                  não no da capa. Sem `translateZ` porque, dentro deste
                  wrapper, a faixa e a traseira já estão na mesma "página"
                  local (a traseira só recebe seu próprio giro por estar
                  aninhada mais um nível abaixo) — esta peça mora no MESMO
                  nível da faixa-visual, então basta acompanhar a largura
                  dela. */}
              {/* Estilo RODADA 21 (2026-08-29) — mesmo tratamento de
                  sulco/gutter da EmendaCurva capa↔faixa acima (ver comentário
                  completo lá), aplicado aqui com a paleta mais escura desta
                  profundidade (`closedCoverWeave([7, 5, 3])`). */}
              <div
                className="pointer-events-none absolute inset-y-0"
                style={{
                  left: `calc(100% - ${DEPTH_RADIUS_PX}px)`,
                  width: DEPTH_RADIUS_PX * 2,
                  borderRadius: DEPTH_RADIUS_PX,
                  backgroundImage: [
                    "linear-gradient(90deg, hsl(0 0% 100% / 0.08) 0%, transparent 22%, transparent 78%, hsl(0 0% 100% / 0.08) 100%)",
                    "linear-gradient(90deg, transparent 0%, hsl(0 0% 0% / 0.55) 38%, hsl(0 0% 0% / 0.78) 50%, hsl(0 0% 0% / 0.55) 62%, transparent 100%)",
                    closedCoverWeave([7, 5, 3]),
                  ].join(", "),
                  boxShadow: [
                    "inset 3px 0 5px hsl(0 0% 0% / 0.5)",
                    "inset -3px 0 5px hsl(0 0% 0% / 0.5)",
                  ].join(", "),
                }}
                aria-hidden
              />

              {/* Traseira — RODADA 13, refeita do zero. A Rodada 11/12 tinha
                  uma face "traseira" independente (mera cópia da capa
                  empurrada em Z), sem aresta compartilhada com nada — daí o
                  vão visível que Fabrício reportou como "três peças soltas".
                  Esta versão usa a MESMA técnica já comprovada duas vezes
                  nesta tela (capa→faixa do zíper): nasce ENCOSTADA na
                  aresta desta faixa (`left: 100%` do wrapper acima, que tem
                  a largura da faixa) e gira em torno da própria ARESTA
                  esquerda (`transformOrigin: "0% 50%"`) — por estar
                  ANINHADA dentro do wrapper com `transform-style:
                  preserve-3d`, herda a rotação da faixa automaticamente
                  (90° da faixa + mais 90° dela mesma = 180°, ou seja, essa
                  face acaba voltada para trás, exatamente o que uma
                  traseira real deveria ser). Sem vão possível por
                  construção — é encaixe de aresta, não posicionamento
                  calculado à mão.
                  RODADA 15: os 4 cantos usam `DEPTH_RADIUS_PX` — mesmo raio
                  do lado esquerdo da faixa do zíper (emenda) e mesmo raio
                  usado como extremidade externa real da cadeia (lado
                  direito). Raio igual dos dois lados de toda emenda é o que
                  faz a curva continuar sem entalhe (Rodada 14 zerava o lado
                  esquerdo pra evitar o entalhe, mas isso também matou a
                  curvatura visível do objeto inteiro — rejeitado por
                  Fabrício: "ficou parecendo uma caixa"). */}
              <div
                className="absolute inset-y-0 left-full overflow-hidden"
                style={{
                  width: `${BACK_CQW}cqw`,
                  // RODADA 20: canto esquerdo (emenda com a faixa) volta a
                  // ter `DEPTH_RADIUS_PX` — curva real na emenda. O vão
                  // triangular reaberto por isso é coberto pela segunda
                  // "EmendaCurva" (ver acima, entre faixa e traseira).
                  borderTopLeftRadius: DEPTH_RADIUS_PX,
                  borderBottomLeftRadius: DEPTH_RADIUS_PX,
                  borderTopRightRadius: DEPTH_RADIUS_PX,
                  borderBottomRightRadius: DEPTH_RADIUS_PX,
                  transformOrigin: "0% 50%",
                  transform: `rotateY(90deg) translateX(-${BACK_CQW / 2}cqw)`,
                  // RODADA 16 tentou aproximar o tom da faixa e suavizar a
                  // sombra — piorou a leitura geral, revertido aos valores
                  // originais (ver hipótese junto a `DEPTH_RADIUS_PX`).
                  backgroundImage: closedCoverWeave([5, 3, 1]),
                  boxShadow: "inset 4px 0 8px hsl(0 0% 0% / 0.6)",
                }}
                aria-hidden
              />
            </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
