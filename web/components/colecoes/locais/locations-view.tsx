import Link from "next/link";
import { ArrowRight, CircleCheck } from "lucide-react";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  LOCAIS_PATH,
  type StorageSummary,
  UNLOCATED_ACERVO_HREF,
  organizationShare,
  organizationShareText,
  organizeLabel,
} from "@/lib/colecoes/storage-locations";
import type { StorageOverview } from "@/lib/colecoes/storage-locations-queries";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { LocationsExplorer, LocationsNotice, LocationsProvider, NewLocationButton } from "./locations-manager";
import acervoStyles from "../acervo/acervo.module.css";
import colecoesStyles from "../colecoes/colecoes.module.css";
import regionStyles from "../colecoes/library-modes.module.css";
import styles from "./locais.module.css";

/**
 * Meus locais — Inventário dos locais físicos (STORAGE LOCATIONS CONCEPT B
 * IMPLEMENTATION-01, sobre REDESIGN-01 e WHERE-02/04/05). Server Component:
 * cabeçalho e o bloco de organização saem prontos do servidor; as facetas de
 * tipo, a busca, a ordem, a relação de locais e a consulta de um local são
 * interativas (`locations-manager.tsx`, nas folhas).
 *
 * Composição (Conceito B): cabeçalho editorial do módulo Coleções (o mesmo
 * palco de Meu acervo, Minhas coleções e Cartas favoritas — HEADER DESIGN
 * ALIGNMENT-01) sem painel de números (a organização mora na coluna lateral);
 * passagem para a área de trabalho pela região editorial comum; no desktop, coluna lateral
 * subordinada (organização do acervo + facetas de tipo) e área principal com a
 * busca, a ordem e o índice de locais em linhas; no celular, a coluna vira um
 * bloco acima da relação. Nenhum relatório de Locais é exposto antes de existir.
 */
export function LocationsView({ overview }: { overview: StorageOverview | null }) {
  if (!overview) {
    return (
      <div className={acervoStyles.root}>
        <Header />
        <div className={`${regionStyles.region} ${styles.workspace} ${styles.readError}`} role="alert">
          <InlineFeedback tone="error">
            Não conseguimos carregar seus locais agora. Nada foi alterado — tente novamente em instantes.
          </InlineFeedback>
          <Button asChild variant="outline" className="min-h-11">
            <a href={LOCAIS_PATH}>Tentar novamente</a>
          </Button>
        </div>
      </div>
    );
  }

  const { locations, summary, kinds } = overview;
  const empty = locations.length === 0;
  const organization = <Organization summary={summary} />;

  return (
    <LocationsProvider kinds={kinds} locations={locations}>
      <div className={acervoStyles.root}>
        <Header action={empty ? null : <NewLocationButton />} />
        {/* Passagem cabeçalho → área de trabalho: a mesma região editorial de Meu acervo e
            Minhas coleções (library-modes .region) — fio de borda a borda e marca dourada curta. */}
        <div className={`${regionStyles.region} ${styles.workspace}`}>
          <LocationsNotice />
          {empty ? (
            <div className={styles.layout}>
              <aside className={styles.side}>{organization}</aside>
              <EmptyLocations />
            </div>
          ) : (
            <LocationsExplorer locations={locations} kinds={kinds} totalCards={summary.totalCards} binders={overview.binders} organization={organization} />
          )}
        </div>
      </div>
    </LocationsProvider>
  );
}

/**
 * Cabeçalho editorial — o palco comum do módulo Coleções (`acervo .hero` +
 * `colecoes .libraryHero`: mesma escala de título, lede, luz estática e grafismo
 * de baixo contraste). Sem numeral nem painel de números: os indicadores ficam
 * só na coluna lateral. A ação principal na faixa do cabeçalho (`.heroRow`),
 * como "Nova coleção" e "Adicionar cartas".
 */
function Header({ action = null }: { action?: React.ReactNode }) {
  return (
    <header className={`${acervoStyles.hero} ${colecoesStyles.libraryHero} ${styles.hero}`}>
      <div className={acervoStyles.stageGlow} aria-hidden="true" />
      <HeroStorage />
      <div className={acervoStyles.heroContent}>
        <h1 className={acervoStyles.title}>Meus Locais de Armazenamento</h1>
        <p className={acervoStyles.lede}>Saiba onde estão suas cartas e acompanhe seus espaços de armazenamento.</p>
      </div>
      {action ? <div className={acervoStyles.heroRow}>{action}</div> : null}
    </header>
  );
}

/**
 * Grafismo do palco: os recipientes do Conceito B (storage-glyph) em traço
 * único, como textura — um ETB com a tampa erguida e as lombadas das cartas, um
 * fichário de frente com argolas e placa, um deck box e uma caixa longa deitada,
 * sobre a mesma linha de prateleira da estante de Minhas coleções. Mesma classe
 * de opacidade baixa (`heroShelf`), decorativo e fora da árvore acessível.
 */
function HeroStorage() {
  return (
    <svg className={colecoesStyles.heroShelf} viewBox="0 0 520 300" fill="none" aria-hidden="true" focusable="false">
      <g stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" strokeLinecap="round">
        {/* prateleira */}
        <path d="M8 262h504" />
        <path d="M24 262v14M496 262v14" />
        {/* ETB: caixa, janela com lombadas e tampa erguida */}
        <rect x="30" y="150" width="150" height="112" rx="5" />
        <rect x="62" y="182" width="86" height="58" rx="4" />
        <path d="M76 192v38M88 188v46M100 192v38M112 188v46M124 192v38M136 188v46" />
        <g transform="rotate(-7 30 132)">
          <rect x="22" y="104" width="166" height="40" rx="5" />
          <path d="M22 132h166" strokeDasharray="3 5" />
        </g>
        {/* fichário de frente: lombada, argolas e placa */}
        <rect x="206" y="66" width="140" height="196" rx="10" />
        <rect x="206" y="66" width="26" height="196" rx="8" />
        <circle cx="219" cy="112" r="3" />
        <circle cx="219" cy="164" r="3" />
        <circle cx="219" cy="216" r="3" />
        <rect x="254" y="100" width="72" height="40" rx="5" />
        <path d="M266 114h48M266 126h30" />
        <rect x="244" y="80" width="92" height="168" rx="6" strokeDasharray="2 6" opacity="0.6" />
        {/* deck box: corpo, tampa e entalhe */}
        <rect x="364" y="150" width="58" height="112" rx="5" />
        <rect x="360" y="132" width="66" height="34" rx="5" />
        <rect x="384" y="160" width="18" height="10" rx="3" />
        {/* caixa longa deitada, com divisórias */}
        <rect x="436" y="198" width="76" height="64" rx="4" />
        <rect x="432" y="184" width="84" height="20" rx="4" />
        <path d="M458 204v58M490 204v58" strokeDasharray="4 5" />
      </g>
    </svg>
  );
}

/**
 * Organização do acervo (coluna lateral): percentual = com local ÷ no acervo,
 * as duas contagens da MESMA leitura (5219), truncado; acervo vazio sem
 * porcentagem. Pendência → "Organizar N exemplares" (Meu acervo `?local=sem`,
 * fluxo existente de seleção e movimentação, WHERE-05B).
 */
function Organization({ summary }: { summary: StorageSummary }) {
  const share = organizationShare(summary);
  const rows = [
    { key: "total", label: "Exemplares no acervo", value: summary.totalCards },
    { key: "located", label: "Com local definido", value: summary.locatedCards },
    { key: "unlocated", label: "Sem localização", value: summary.unlocatedCards, warn: summary.unlocatedCards > 0 },
    { key: "locations", label: "Locais cadastrados", value: summary.locationCount },
  ];
  return (
    <section className={styles.org} aria-labelledby="locais-organizacao">
      <p className={styles.orgTop}>
        <span id="locais-organizacao" className={styles.orgLabel}>
          Organização do acervo
        </span>
        <span className={styles.orgValue}>{organizationShareText(summary)}</span>
      </p>
      {share === null ? (
        <p className={styles.orgNote}>Seu acervo ainda não tem exemplares.</p>
      ) : (
        <div
          className={styles.bar}
          role="progressbar"
          aria-label="Exemplares com local definido"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={share}
          aria-valuetext={`${share}% — ${formatCount(summary.locatedCards)} de ${formatCount(summary.totalCards)} exemplares com local definido`}
        >
          <span className={styles.barFill} style={{ width: `${share}%` }} />
        </div>
      )}
      <dl className={styles.orgList}>
        {rows.map((row) => (
          <div key={row.key} className={styles.orgRow} data-warn={row.warn || undefined}>
            <dt>{row.label}</dt>
            <dd>{formatCount(row.value)}</dd>
          </div>
        ))}
      </dl>
      {summary.unlocatedCards > 0 ? (
        <Button asChild variant="outline" className="mt-3 min-h-11 w-full justify-between gap-1.5">
          <Link href={UNLOCATED_ACERVO_HREF}>
            {organizeLabel(summary.unlocatedCards)}
            <ArrowRight className="h-4 w-4" aria-hidden="true" />
          </Link>
        </Button>
      ) : summary.totalCards > 0 ? (
        <p className={styles.allSet}>
          <CircleCheck className="h-4 w-4" aria-hidden="true" />
          Todos os exemplares têm local definido.
        </p>
      ) : null}
    </section>
  );
}

function EmptyLocations() {
  return (
    <section className={styles.empty} aria-labelledby="locais-vazio">
      <svg className={styles.emptyArt} viewBox="0 0 240 180" fill="none" aria-hidden="true" focusable="false">
        <rect x="24" y="58" width="192" height="100" rx="14" stroke="currentColor" strokeWidth="2" strokeDasharray="6 6" />
        <path d="M24 86h192" stroke="currentColor" strokeWidth="2" strokeDasharray="6 6" />
        <rect x="74" y="22" width="44" height="60" rx="5" stroke="currentColor" strokeWidth="2" transform="rotate(-10 96 52)" />
        <rect x="104" y="18" width="44" height="60" rx="5" stroke="currentColor" strokeWidth="2" strokeDasharray="5 5" transform="rotate(8 126 48)" />
      </svg>
      <div>
        <h2 id="locais-vazio" className={styles.emptyTitle}>
          Onde ficam as suas cartas?
        </h2>
        <p className={styles.emptyText}>
          Cadastre os lugares reais onde você guarda cartas — um fichário, uma caixa, uma pasta, um deck box. O local é de cada carta
          física; criar um local não move nem coloca nenhuma carta nele.
        </p>
        <div className={styles.emptyAction}>
          <NewLocationButton label="Criar meu primeiro local" layout="empty" />
        </div>
      </div>
    </section>
  );
}
