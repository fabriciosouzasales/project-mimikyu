"use client";

import { CompleteShelfLandingPage } from "@designcodeio/threeui/components/CompleteShelfLandingPage";
import "@designcodeio/threeui/style.css";
import "./proof.css";

/**
 * FASE 1 — PROVA DE FIDELIDADE (pedido de Fabrício, 2026-08-29).
 *
 * Renderiza o componente `CompleteShelfLandingPage` do pacote oficial
 * `@designcodeio/threeui` (ThreeUI, por Meng To / Design+Code) EXATAMENTE
 * como fornecido — sem nenhuma adaptação MMKYU. Objetivo único desta rota:
 * provar que conseguimos rodar, dentro deste projeto, a experiência
 * authored pelo ThreeUI, antes de decidir qualquer adaptação futura.
 *
 * Fase 0 (fontes oficiais verificadas antes desta implementação):
 *  - Pacote `@designcodeio/threeui@1.1.0` confirmado no registro público do
 *    npm (mantenedor `mengto`, licença MIT, proveniência via GitHub
 *    Actions/OIDC) — https://registry.npmjs.org/@designcodeio/threeui
 *  - `CompleteShelfLandingPage` confirmado como export real do pacote
 *    (`lib-dist/index.d.ts` e `lib-dist/index.js`), reexportado de
 *    `src/shaders/landing-pages/LandingPages.tsx` no repositório oficial
 *    https://github.com/MengTo/threeui.
 *  - Bundle de origem registrado `complete-shelf-landing-page.json`
 *    (https://threeui.com/source-code/complete-shelf-landing-page.json)
 *    conferido contra os 3 SHA-256 informados por Fabrício — os três batem
 *    exatamente com o bundle real hospedado em threeui.com:
 *    `LandingPages.tsx` (d34af7b5…4f5), `complete-shelf-v2.html`
 *    (606f200f…198e) e `threeui.css` (efe44471…ccf).
 *  - Contrato de props confirmado lendo o código-fonte real do componente
 *    (não documentação/descrição): `CompleteShelfLandingPage` aceita
 *    `LandingPageProps & PageTypographyProps` (headingFont, bodyFont,
 *    headingWeight, bodyWeight, headingSize, bodySize,
 *    headingLetterSpacing, primaryColor, entre outros) e renderiza, via
 *    iframe sandboxed, `sourceUrl="/landing-pages/complete-shelf-v2.html"`.
 *  - Achado não-óbvio, verificado e não uma divergência de fonte: o título
 *    real exibido dentro do iframe é "Working Volumes — Seven Tools for
 *    Making", não "Complete Shelf" — "Complete Shelf" é apenas o nome
 *    interno/slug do componente no código-fonte oficial; o copy do
 *    produto é "Working Volumes". Confirmado lendo `LandingPages.tsx`
 *    diretamente, não por suposição.
 *
 * Nada aqui foi recriado a partir de screenshot, aparência, nome de
 * arquivo ou interpretação própria — o import e as props abaixo são
 * exatamente os fornecidos por Fabrício, consumindo o pacote publicado
 * oficial sem modificação.
 *
 * PENDÊNCIA DE AMBIENTE (fora do alcance deste sandbox): o sandbox de
 * execução do agente não tem acesso a `registry.npmjs.org` (mesma
 * limitação já registrada para build/lint em memória do projeto) — não
 * foi possível rodar `npm install` aqui. Fabrício precisa instalar o
 * pacote e copiar o asset HTML canônico (~900 KB) para
 * `public/landing-pages/` localmente antes de abrir esta rota — comandos
 * no relatório desta rodada.
 *
 * IMPORT VIA SUBPATH, NÃO PELO BARREL (2026-08-29, diagnosticado em
 * produção local por Fabrício): importar de `@designcodeio/threeui`
 * (barrel `index.js`) carrega TODOS os componentes do pacote, incluindo
 * `Gallery.js` — não usado por esta prova — que referencia `sRGBEncoding`,
 * constante removida do `three` no r162 (deprecada no r152). Como o
 * `three` instalado localmente (peer dependency, `>=0.149 <1`) resolve
 * para a versão mais recente disponível, o build quebrava com
 * "'sRGBEncoding' is not exported from 'three'" mesmo sem essa rota usar
 * Gallery. O próprio pacote expõe subpaths por componente
 * (`exports["./components/*"]` → `lib-dist/package-components/*.js`,
 * confirmado lendo `node_modules/@designcodeio/threeui/package.json`);
 * importar por `@designcodeio/threeui/components/CompleteShelfLandingPage`
 * evita o barrel. Cadeia de dependências desse caminho, confirmada lendo
 * o `lib-dist` compilado: `CompleteShelfLandingPage.js` →
 * `shaders/landing-pages/LandingPages.js` → `pageTypography.js` +
 * `pageRecipes.js` — nenhum desses toca Three.js (o Three.js só existe
 * dentro do HTML sandboxed carregado via iframe). `next.config.ts` ganhou
 * um ajuste de webpack separado (rule `THREEUI-PROOF-01`) para um erro de
 * schema do Asset Modules Plugin encontrado antes deste — não removido,
 * pois é uma correção de compatibilidade legítima e inofensiva ao resto
 * do projeto, mesmo não sendo mais estritamente necessária para este
 * import específico.
 */
export function Scene() {
  return (
    <div className="shader-frame">
      <CompleteShelfLandingPage
        headingFont="iowan-old-style"
        bodyFont="inter"
        headingWeight="400"
        bodyWeight="400"
        primaryColor="#c87046"
        headingSize={60}
        bodySize={12}
        headingLetterSpacing={-0.055}
      />
    </div>
  );
}
