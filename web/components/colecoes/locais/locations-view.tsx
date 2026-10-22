import { formatCount } from "@/lib/colecoes/acervo";
import { LOCAIS_PATH, type StorageSummary } from "@/lib/colecoes/storage-locations";
import type { StorageOverview } from "@/lib/colecoes/storage-locations-queries";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { LocationGrid, LocationsNotice, LocationsProvider, NewLocationButton } from "./locations-manager";
import acervoStyles from "../acervo/acervo.module.css";
import regionStyles from "../colecoes/library-modes.module.css";
import styles from "./locais.module.css";

/**
 * Meus locais — composição da página (Server Component). Cabeçalho, números e
 * estados vazio/erro saem prontos do servidor; só a grade, os botões e os
 * painéis são interativos (`locations-manager.tsx`, nas folhas).
 *
 * Mesmo palco do Meu acervo (título, numeral de contorno, painel de números
 * com fio dourado) para a página parecer parte do mesmo lugar.
 *
 * Passagem cabeçalho → área de trabalho: a mesma região editorial de Minhas
 * coleções (`library-modes.module.css` `.region`) — fio de borda a borda, marca
 * dourada curta no início do conteúdo e superfície um tom mais clara que se
 * dissolve no workspace. Reutilizada, não copiada.
 */
export function LocationsView({ overview }: { overview: StorageOverview | null }) {
  if (!overview) {
    return (
      <div className={acervoStyles.root}>
        <LocationsHero summary={null} />
        <div className={regionStyles.region}>
          <div className={styles.readError} role="alert">
            <InlineFeedback tone="error">
              Não conseguimos carregar seus locais agora. Nada foi alterado — tente novamente em instantes.
            </InlineFeedback>
            <Button asChild variant="outline" className="min-h-11">
              <a href={LOCAIS_PATH}>Tentar novamente</a>
            </Button>
          </div>
        </div>
      </div>
    );
  }

  const { locations, summary, kinds } = overview;
  const empty = locations.length === 0;

  return (
    <LocationsProvider kinds={kinds} locations={locations}>
      <div className={acervoStyles.root}>
        <LocationsHero summary={summary} action={empty ? null : <NewLocationButton />} />

        <LocationsNotice />

        <div className={regionStyles.region}>
          {empty ? (
            <EmptyLocations />
          ) : (
            <section aria-labelledby="locais-lista">
              <div className={styles.listHead}>
                <h2 id="locais-lista" className={styles.listTitle} tabIndex={-1}>
                  Seus locais
                </h2>
                <p className={styles.listMeta}>
                  {locations.length === 1 ? "1 local" : `${formatCount(locations.length)} locais`} · em ordem alfabética
                </p>
              </div>
              <LocationGrid locations={locations} />
            </section>
          )}
        </div>
      </div>
    </LocationsProvider>
  );
}

function LocationsHero({ summary, action = null }: { summary: StorageSummary | null; action?: React.ReactNode }) {
  return (
    <header className={acervoStyles.hero}>
      <div className={acervoStyles.stageGlow} aria-hidden="true" />
      {summary && summary.locationCount > 0 ? (
        <span className={acervoStyles.numeral} aria-hidden="true">
          {formatCount(summary.locationCount)}
        </span>
      ) : null}
      <div className={acervoStyles.heroContent}>
        <h1 className={acervoStyles.title}>Meus locais</h1>
        <p className={acervoStyles.lede}>
          Os lugares reais onde você guarda suas cartas. <strong>Cada exemplar tem o seu local</strong> — o local padrão de uma
          coleção é só uma sugestão.
        </p>
      </div>
      {summary ? (
        <div className={acervoStyles.heroRow}>
          <SummaryLedger summary={summary} />
          {action}
        </div>
      ) : null}
    </header>
  );
}

function SummaryLedger({ summary }: { summary: StorageSummary }) {
  const items = [
    {
      key: "locations",
      value: summary.locationCount,
      name: summary.locationCount === 1 ? "local" : "locais",
      hint: "lugares cadastrados por você",
      lead: true,
    },
    {
      key: "located",
      value: summary.locatedCards,
      name: "com local definido",
      hint: "exemplares guardados em um local",
    },
    {
      key: "unlocated",
      value: summary.unlocatedCards,
      name: "sem localização definida",
      hint: "exemplares ainda sem local registrado",
    },
    {
      key: "total",
      value: summary.totalCards,
      name: summary.totalCards === 1 ? "exemplar no acervo" : "exemplares no acervo",
      hint: "todas as cartas físicas",
    },
  ];
  const quiet = summary.locationCount === 0;
  return (
    <dl
      className={quiet ? `${acervoStyles.ledger} ${acervoStyles.ledgerQuiet}` : acervoStyles.ledger}
      aria-label="Resumo dos locais"
    >
      {items.map((item) => (
        <div
          key={item.key}
          className={item.lead ? `${acervoStyles.ledgerItem} ${acervoStyles.ledgerLead}` : acervoStyles.ledgerItem}
        >
          <dt className={acervoStyles.ledgerLabel}>
            <span className={acervoStyles.ledgerName}>{item.name}</span>
            <span className={acervoStyles.ledgerHint}>{item.hint}</span>
          </dt>
          <dd className={acervoStyles.ledgerValue}>{formatCount(item.value)}</dd>
        </div>
      ))}
    </dl>
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
          <NewLocationButton label="Criar meu primeiro local" />
        </div>
      </div>
    </section>
  );
}
