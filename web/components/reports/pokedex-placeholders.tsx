import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import {
  GRID_MM,
  MMKYU_PUBLIC_URL,
  OPENING_PAGES,
  PLACEHOLDER_MM,
  PLACEHOLDERS_PER_SHEET,
  POKEDEX_PLACEHOLDERS_TITLE,
  type Placeholder,
  type PlaceholderKit,
  type PlaceholderSheet,
  brandHost,
  coverFanItems,
  displayUrl,
  placeholderNameSize,
  placeholderNumber,
  printRangeExample,
  sheetCountText,
  sheetHeaderText,
  speciesCountLabel,
} from "@/lib/reports/pokedex-placeholders";
import { encodeQr, qrSvgPath } from "@/lib/reports/qr-code";
import { CoverField, HatchMark, PageField, ZigzagRule } from "./booklet-brand";
import { PrintImageGate } from "./print-image-gate";
import styles from "./pokedex-placeholders.module.css";

/** Placeholders com a arte carregada já na abertura (as primeiras folhas); o resto sob demanda. */
const EAGER = PLACEHOLDERS_PER_SHEET * 2;

/**
 * Placeholders da Pokédex (D7 §4q) — kit de fichário: capa + orientações + folhas A4 recortáveis de 3 × 3
 * placeholders de 63 × 88 mm, um por espécie do objetivo, em ordem nacional (folha N = página N do
 * fichário de 9 bolsos). Peça editorial, não relatório analítico: sem tabela, sem status, sem números
 * de completude. A marca entra em camadas — rabisco MMKYU como marca d'água atrás da arte, hachura e
 * zigue-zague dourados, assinatura discreta em cada placeholder, capa e rodapé da folha.
 */
export function PokedexPlaceholders({
  collectionName,
  kit,
  issuedAt,
  publicUrl = MMKYU_PUBLIC_URL,
}: {
  collectionName: string;
  kit: PlaceholderKit;
  issuedAt: string;
  /** Endereço oficial para a página de orientações; padrão = `MMKYU_PUBLIC_URL` (sem endereço → sem URL nem QR). */
  publicUrl?: string | null;
}) {
  const host = brandHost(process.env.NEXT_PUBLIC_SITE_URL);
  return (
    <PrintImageGate>
      <div className={styles.kit} data-pokedex-placeholders="">
        <Cover collectionName={collectionName} kit={kit} issuedAt={issuedAt} />
        <Guide kit={kit} publicUrl={publicUrl} />
        {kit.sheets.map((sheet) => (
          <Sheet key={sheet.index} sheet={sheet} total={kit.sheets.length} collectionName={collectionName} host={host} />
        ))}
      </div>
    </PrintImageGate>
  );
}

function Cover({ collectionName, kit, issuedAt }: { collectionName: string; kit: PlaceholderKit; issuedAt: string }) {
  const fan = coverFanItems(kit);
  return (
    <section className={styles.sheet} aria-label={`${POKEDEX_PLACEHOLDERS_TITLE} — capa`} data-opening-page="cover">
      <div className={styles.page}>
        <CoverField className={styles.field} />
        <div className={styles.topbar}>
          {/* eslint-disable-next-line @next/next/no-img-element -- asset estático local da marca, mesmo padrão do Caderno */}
          <img src="/brand/logo-full-light.png" alt="MMKYU Collector" className={styles.logo} />
          <span className={styles.kicker}>
            <HatchMark />
            Kit de fichário
          </span>
        </div>
        <h2 className={styles.coverTitle}>
          <span>Placeholders</span>
          <span>
            da <em>Pokédex</em>
          </span>
        </h2>
        <ZigzagRule className={styles.coverRule} />
        {fan.length > 0 ? (
          <div className={styles.fan} aria-hidden="true">
            {fan.map((item, slot) => (
              <ul key={item.positionId} className={styles.fanCard} data-slot={fan.length === 1 ? 1 : fan.length === 2 ? slot * 2 : slot}>
                <PlaceholderCard item={item} eager />
              </ul>
            ))}
          </div>
        ) : null}
        <div className={styles.coverInfo}>
          <p className={styles.coverCollection}>{collectionName}</p>
          <p className={styles.coverScope}>{kit.scope}</p>
          <p className={styles.coverCount}>
            <strong>
              {speciesCountLabel(kit.species)} · {sheetCountText(kit.sheets.length)} recortáveis
            </strong>
            {PLACEHOLDERS_PER_SHEET} cartões de {PLACEHOLDER_MM.width} × {PLACEHOLDER_MM.height} mm por folha
          </p>
        </div>
        <div className={styles.pageFoot}>
          <span>
            <strong>Um kit MMKYU Collector</strong>
            <br />
            Gerado em {issuedAt}
          </span>
          <span className={styles.legal}>{LEGAL_NOTE}</span>
        </div>
      </div>
    </section>
  );
}

const LEGAL_NOTE =
  "Utilitário independente de organização de coleções — não é produto oficial nem afiliado à The Pokémon Company. Pokémon e os nomes das espécies são marcas de seus respectivos titulares. Material para uso pessoal.";

/** Funcionalidades já disponíveis no MMKYU Collector (nada futuro). */
const FEATURES: ReadonlyArray<{ title: string; text: string }> = [
  { title: "Coleções organizadas", text: "Set, Master Set, Pokédex ou coleção livre, cada uma com o seu fichário digital." },
  { title: "Pokédex por gerações", text: "Escolha as gerações e acompanhe espécie por espécie, de Kanto a Paldea." },
  { title: "Espécies faltantes", text: "Veja o que falta e se já existe um exemplar no seu acervo para completar." },
  { title: "Acervo físico", text: "Cada carta que você tem, com idioma, cópias e a coleção onde ela está." },
  { title: "Relatórios", text: "Checklist, composição e valor estimado da coleção, prontos para imprimir." },
];

function Guide({ kit, publicUrl }: { kit: PlaceholderKit; publicUrl: string | null }) {
  const range = printRangeExample(kit);
  const qr = publicUrl ? encodeQr(publicUrl) : null;
  return (
    <section className={styles.sheet} aria-label={`${POKEDEX_PLACEHOLDERS_TITLE} — como usar`} data-opening-page="guide">
      <div className={styles.page}>
        <PageField className={styles.field} variant={1} />
        <div className={styles.topbar}>
          {/* eslint-disable-next-line @next/next/no-img-element -- asset estático local da marca */}
          <img src="/brand/logo-full-light.png" alt="MMKYU Collector" className={styles.logo} />
          <span className={styles.kicker}>
            <HatchMark />
            Antes de começar
          </span>
        </div>

        <h2 className={styles.guideTitle}>Como usar os placeholders</h2>
        <p className={styles.guideLead}>
          Cada placeholder guarda o lugar de uma espécie no fichário, na ordem da Pokédex Nacional. Quando a carta chegar, ela ocupa o espaço que já estava
          esperando por ela.
        </p>

        <ol className={styles.howGrid}>
          <li className={styles.how}>
            <HowPrint />
            <span className={styles.howNo}>1</span>
            <p className={styles.howTitle}>Imprima em A4, escala 100%</p>
            <p className={styles.howText}>Use “tamanho real” e desmarque “ajustar à página”.</p>
          </li>
          <li className={styles.how}>
            <HowCut />
            <span className={styles.howNo}>2</span>
            <p className={styles.howTitle}>Recorte pelas marcações</p>
            <p className={styles.howText}>Siga as linhas tracejadas; um corte separa dois cartões vizinhos.</p>
          </li>
          <li className={styles.how}>
            <HowPocket />
            <span className={styles.howNo}>3</span>
            <p className={styles.howTitle}>Coloque no bolso certo</p>
            <p className={styles.howText}>A Folha N corresponde à página N de um fichário de 9 bolsos.</p>
          </li>
          <li className={styles.how}>
            <HowSwap />
            <span className={styles.howNo}>4</span>
            <p className={styles.howTitle}>Troque pela carta</p>
            <p className={styles.howText}>Quando a espécie entrar na coleção, a carta assume o lugar do placeholder.</p>
          </li>
        </ol>

        <dl className={styles.facts}>
          <div className={styles.fact}>
            <dt>Tamanho</dt>
            <dd>
              <strong>
                {PLACEHOLDER_MM.width} × {PLACEHOLDER_MM.height} mm
              </strong>
              O tamanho nominal de uma carta.
            </dd>
          </div>
          <div className={styles.fact}>
            <dt>Por folha</dt>
            <dd>
              <strong>{PLACEHOLDERS_PER_SHEET} posições</strong>
              3 × 3, como uma página de fichário.
            </dd>
          </div>
          <div className={styles.fact}>
            <dt>Imprima só o que precisa</dt>
            <dd>
              <strong>Folha N = pág. N + {OPENING_PAGES}</strong>
              {range ? `Ex.: páginas ${range.pages} imprimem ${range.sheets}. ` : ""}Capa e orientações são opcionais.
            </dd>
          </div>
        </dl>

        <div className={styles.discover}>
          <div>
            <span className={styles.kicker}>
              <HatchMark />
              Feito pelo MMKYU Collector
            </span>
            <h3 className={styles.discoverTitle}>Descubra o MMKYU Collector</h3>
            <p className={styles.discoverLead}>Uma plataforma para organizar coleções de Pokémon TCG — do fichário de papel ao acervo digital.</p>
          </div>
          <ul className={styles.features}>
            {FEATURES.map((f) => (
              <li key={f.title} className={styles.feature}>
                <HatchMark />
                <span>
                  <b>{f.title}.</b> {f.text}
                </span>
              </li>
            ))}
          </ul>
        </div>

        <div className={styles.cta}>
          <div className={styles.ctaText}>
            <p className={styles.ctaLine}>
              Seu fichário começa no papel.
              <span>Sua coleção continua no MMKYU.</span>
            </p>
            <p className={styles.ctaNote}>{publicUrl ? "Conheça o MMKYU Collector e organize a sua coleção." : "MMKYU Collector · organização de coleções de Pokémon TCG."}</p>
          </div>
          {publicUrl && qr ? (
            <div className={styles.access} data-access="qr">
              <svg className={styles.qr} viewBox={`0 0 ${qr.size + 8} ${qr.size + 8}`} role="img" aria-label={`QR Code para ${displayUrl(publicUrl)}`} shapeRendering="crispEdges">
                <rect width={qr.size + 8} height={qr.size + 8} fill="#ffffff" />
                <path d={qrSvgPath(qr)} fill="#16130f" />
              </svg>
              <span className={styles.accessText}>
                Conheça o MMKYU Collector
                <strong>{displayUrl(publicUrl)}</strong>
              </span>
            </div>
          ) : (
            <div className={styles.access} data-access="brand">
              {/* eslint-disable-next-line @next/next/no-img-element -- asset estático local da marca */}
              <img src="/brand/logo-full-light.png" alt="" className={styles.accessMark} />
            </div>
          )}
        </div>

        <div className={styles.pageFoot}>
          <span>
            <strong>MMKYU Collector</strong>
          </span>
          <span className={styles.legal}>{LEGAL_NOTE}</span>
        </div>
      </div>
    </section>
  );
}

/* Ilustrações dos passos — traço fino (tinta) + um acento dourado; viewBox em mm (40 × 27). */
const LINE = { fill: "none", stroke: "currentColor", strokeWidth: 0.45, strokeLinecap: "round", strokeLinejoin: "round" } as const;
const GOLD = { fill: "none", stroke: "var(--ph-gold)", strokeWidth: 0.7, strokeLinecap: "round", strokeLinejoin: "round" } as const;

function MiniGrid({ x, y, w, h, highlight }: { x: number; y: number; w: number; h: number; highlight?: number }) {
  const cw = w / 3;
  const ch = h / 3;
  return (
    <g>
      {Array.from({ length: 9 }, (_, i) => (
        <rect key={i} x={x + (i % 3) * cw + 0.5} y={y + Math.floor(i / 3) * ch + 0.5} width={cw - 1} height={ch - 1} rx={0.6} {...(i === highlight ? GOLD : LINE)} strokeWidth={i === highlight ? 0.6 : 0.3} />
      ))}
    </g>
  );
}

function HowPrint() {
  return (
    <svg className={styles.howArt} viewBox="0 0 40 27" aria-hidden="true" focusable="false">
      <rect x={4} y={1.5} width={17.5} height={24} rx={0.8} {...LINE} />
      <MiniGrid x={6} y={4} w={13.5} h={19} />
      <text x={24.5} y={12} fontSize={5.2} fontWeight={800} fill="currentColor" fontFamily="var(--font-heading)">
        100%
      </text>
      <text x={24.6} y={16.6} fontSize={2.6} fill="var(--ph-muted)">
        tamanho real
      </text>
      <path d="M24.8 19.6h11" {...GOLD} />
    </svg>
  );
}

function HowCut() {
  return (
    <svg className={styles.howArt} viewBox="0 0 40 27" aria-hidden="true" focusable="false">
      <rect x={11} y={2} width={15.5} height={21.6} rx={1.2} {...LINE} strokeDasharray="1.2 1" />
      <rect x={12.6} y={3.6} width={12.3} height={18.4} rx={0.9} {...LINE} strokeWidth={0.25} />
      <circle cx={18.8} cy={11.5} r={3.4} {...LINE} strokeWidth={0.3} />
      <g transform="translate(29 18) rotate(-35)">
        <circle cx={-2.2} cy={4.2} r={1.6} {...GOLD} />
        <circle cx={2.2} cy={4.2} r={1.6} {...GOLD} />
        <path d="M-1.4 2.8L1.6 -5.5M1.4 2.8L-1.6 -5.5" {...LINE} />
      </g>
    </svg>
  );
}

function HowPocket() {
  return (
    <svg className={styles.howArt} viewBox="0 0 40 27" aria-hidden="true" focusable="false">
      <rect x={8.5} y={1.5} width={23} height={24} rx={1} {...LINE} />
      <path d="M8.5 4v19" {...LINE} strokeWidth={0.25} strokeDasharray="0.6 0.8" />
      <MiniGrid x={10.5} y={3} w={19} h={21} highlight={4} />
      <path d="M20 0.6v3.4m-1.3-1.3L20 4l1.3-1.3" {...GOLD} />
    </svg>
  );
}

function HowSwap() {
  return (
    <svg className={styles.howArt} viewBox="0 0 40 27" aria-hidden="true" focusable="false">
      <rect x={4} y={4} width={13} height={18.2} rx={1} {...LINE} strokeDasharray="1.2 1" />
      <circle cx={10.5} cy={11} r={3} {...LINE} strokeWidth={0.3} />
      <path d="M7.5 17.5h6" {...LINE} strokeWidth={0.3} />
      <path d="M19 13h4.5m-1.5-1.6 1.6 1.6-1.6 1.6" {...GOLD} />
      <rect x={25.5} y={3} width={13} height={18.2} rx={1} {...LINE} />
      <rect x={27} y={4.6} width={10} height={8} rx={0.5} {...LINE} strokeWidth={0.3} />
      <path d="M27.2 15.2h7.2M27.2 17.4h5" {...LINE} strokeWidth={0.3} />
      <path d="M36.6 2.2l0.5 1.3 1.3 0.5-1.3 0.5-0.5 1.3-0.5-1.3-1.3-0.5 1.3-0.5z" fill="var(--ph-gold)" />
    </svg>
  );
}

function Sheet({ sheet, total, collectionName, host }: { sheet: PlaceholderSheet; total: number; collectionName: string; host: string | null }) {
  return (
    <section className={styles.sheet} aria-label={sheetHeaderText(sheet, total)} data-placeholder-sheet={sheet.index}>
      <CutMarks />
      <header className={styles.head}>
        <span>
          <b>{POKEDEX_PLACEHOLDERS_TITLE}</b> · {collectionName}
        </span>
        <span>{sheetHeaderText(sheet, total)}</span>
      </header>
      <ol className={styles.grid}>
        {sheet.items.map((item, i) => (
          <PlaceholderCard key={item.positionId} item={item} eager={(sheet.index - 1) * PLACEHOLDERS_PER_SHEET + i < EAGER} />
        ))}
      </ol>
      <footer className={styles.foot}>
        <span className={styles.brand}>
          <HatchMark />
          MMKYU Collector
        </span>
        <span>Recorte nas linhas tracejadas · {PLACEHOLDER_MM.width} × {PLACEHOLDER_MM.height} mm</span>
        <span>{host ?? `Página ${sheet.index} do fichário`}</span>
      </footer>
    </section>
  );
}

function PlaceholderCard({ item, eager }: { item: Placeholder; eager: boolean }) {
  const src = speciesArtworkUrl(item.artworkPath);
  return (
    <li className={styles.ph} aria-label={`${placeholderNumber(item.number)} ${item.name}`}>
      <div className={styles.phTop} aria-hidden="true">
        <span className={styles.phNumber}>{placeholderNumber(item.number)}</span>
        <span className={styles.phGen}>Ger. {item.generation}</span>
      </div>
      <div className={styles.stage} aria-hidden="true">
        <Ring />
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- arte pública da espécie (bucket próprio), padrão da página Pokédex
          <img className={styles.art} src={src} alt="" width={160} height={160} loading={eager ? "eager" : "lazy"} decoding="async" data-print-jpeg-species="" />
        ) : (
          <span className={styles.noArt}>{placeholderNumber(item.number)}</span>
        )}
      </div>
      <span className={styles.phName} data-size={placeholderNameSize(item.name)} aria-hidden="true">
        {item.name}
      </span>
      <ZigzagRule className={styles.zig} />
      <span className={styles.sign} aria-hidden="true">
        <HatchMark />
        MMKYU Collector
      </span>
    </li>
  );
}

/**
 * Palco da arte: anel fino dourado (um arco forte + o círculo suave) e o rabisco circular da marca
 * MMKYU como marca d'água muito leve. Só traço — sem preenchimento, pouca tinta.
 */
const SCRIBBLE = scribble(11);

function Ring() {
  return (
    <svg className={styles.ring} viewBox="-50 -50 100 100" aria-hidden="true" focusable="false">
      <path d={SCRIBBLE} transform="scale(46) rotate(-14)" fill="none" stroke="var(--ph-ink)" strokeOpacity="0.055" strokeWidth={0.022} strokeLinecap="round" strokeLinejoin="round" />
      <circle r="48" fill="none" stroke="var(--ph-gold-soft)" strokeWidth="0.8" />
      <circle r="48" fill="none" stroke="var(--ph-gold)" strokeWidth="1.3" strokeLinecap="round" strokeDasharray="70 232" transform="rotate(118)" />
    </svg>
  );
}

/** Rabisco circular determinístico (mesma gramática da marca decomposta do Caderno). */
function scribble(seed: number): string {
  let a = seed >>> 0;
  const r = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const f = (n: number) => Math.round(n * 1000) / 1000;
  let d = "";
  let cx = 0;
  let cy = 0;
  const steps = 5 * 28;
  for (let i = 0; i <= steps; i += 1) {
    const t = (i / 28) * Math.PI * 2;
    cx += (r() - 0.5) * 0.02;
    cy += (r() - 0.5) * 0.02;
    const radius = 0.7 + 0.22 * Math.sin(t * 0.21 + seed) + (r() - 0.5) * 0.06;
    d += `${i === 0 ? "M" : "L"}${f(cx + Math.cos(t) * radius * 0.94)} ${f(cy + Math.sin(t) * radius)}`;
  }
  return d;
}

/**
 * Linhas de corte: tracejado fino sobre as divisões da grade (um corte serve aos dois placeholders
 * vizinhos) e marcas de corte contínuas nas margens, alinhadas às mesmas linhas.
 */
function CutMarks() {
  const xs = [0, 1, 2, 3].map((i) => GRID_MM.left + i * PLACEHOLDER_MM.width);
  const ys = [0, 1, 2, 3].map((i) => GRID_MM.top + i * PLACEHOLDER_MM.height);
  const right = GRID_MM.left + GRID_MM.width;
  const bottom = GRID_MM.top + GRID_MM.height;
  const mark = 5;
  const gap = 1.5;
  return (
    <svg className={styles.layer} viewBox="0 0 210 297" preserveAspectRatio="none" aria-hidden="true" focusable="false">
      <g stroke="var(--ph-cut)" strokeWidth="0.2" strokeDasharray="1.4 1.2" fill="none">
        {xs.map((x) => (
          <line key={`v${x}`} x1={x} y1={GRID_MM.top} x2={x} y2={bottom} />
        ))}
        {ys.map((y) => (
          <line key={`h${y}`} x1={GRID_MM.left} y1={y} x2={right} y2={y} />
        ))}
      </g>
      <g stroke="var(--ph-muted)" strokeWidth="0.25" fill="none">
        {xs.map((x) => (
          <g key={`m${x}`}>
            <line x1={x} y1={GRID_MM.top - gap - mark} x2={x} y2={GRID_MM.top - gap} />
            <line x1={x} y1={bottom + gap} x2={x} y2={bottom + gap + mark} />
          </g>
        ))}
        {ys.map((y) => (
          <g key={`n${y}`}>
            <line x1={GRID_MM.left - gap - mark} y1={y} x2={GRID_MM.left - gap} y2={y} />
            <line x1={right + gap} y1={y} x2={right + gap + mark} y2={y} />
          </g>
        ))}
      </g>
    </svg>
  );
}
