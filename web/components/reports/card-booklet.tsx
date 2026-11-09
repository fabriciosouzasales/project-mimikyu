"use client";

import { Check } from "lucide-react";
import { type CSSProperties, useEffect } from "react";
import { RaritySymbol } from "@/components/catalogo/rarity-symbol";
import { cardFrontUrl } from "@/lib/colecoes/acervo";
import { progressPercent } from "@/lib/colecoes/colecoes";
import {
  CARD_BOOKLET_INTRO,
  type BookletCard,
  type BookletPage,
  type BookletReport,
  bookletCardAria,
  bookletNumberText,
  bookletRangeText,
  bookletStatusText,
} from "@/lib/reports/card-booklet";
import type { CardBookletCollection } from "@/lib/reports/card-booklet-queries";
import type { ChecklistKind } from "@/lib/reports/collection-checklist";
import { ClosingField, CoverField, HatchMark, PageField, ZigzagRule } from "./booklet-brand";
import { releaseBookletPrintImages } from "./booklet-print-images";
import styles from "./card-booklet.module.css";
import { PrintImageGate } from "./print-image-gate";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const N = new Intl.NumberFormat("pt-BR");
/** Cartas da 1ª página de cartas carregam de imediato; as demais sob demanda (a impressão prepara todas antes). */
const EAGER_CARDS = 10;

/**
 * Caderno de Cartas da Coleção (D7 §4p) — peça editorial do Card Set inteiro: capa, abertura (como
 * ler + raridades + resumo), páginas de cartas na ordem da coleção (20 por página no A4) e
 * encerramento. A posse é um selo discreto no canto da carta; o Set é o protagonista. Mesma
 * estrutura na tela (folhas responsivas, tema claro e escuro) e no papel (A4, margem desenhada).
 */
export function CardBooklet({
  collection,
  kind,
  report,
  logoUrl,
  issuedOn,
}: {
  collection: CardBookletCollection;
  kind: ChecklistKind;
  report: BookletReport;
  logoUrl: string | null;
  issuedOn: string;
}) {
  const setName = collection.cardSetName ?? collection.name;
  const setCode = collection.cardSetCode ?? "";
  const kindText = kind === "MASTER_SET" ? "Master Set" : "Set padrão";
  const context = { setName, setCode, collectionName: collection.name, totalPages: report.totalPages };
  useEffect(() => releaseBookletPrintImages, []);

  return (
    <div className={styles.booklet} data-card-booklet="">
      <PrintImageGate>
        <Cover setName={setName} setCode={setCode} logoUrl={logoUrl} collectionName={collection.name} kindText={kindText} report={report} issuedOn={issuedOn} />
        <Opening kind={kind} kindText={kindText} collectionName={collection.name} report={report} context={context} />
        {report.pages.map((page, index) => (
          <CardsPage key={page.pageNumber} page={page} kind={kind} eager={index === 0} context={context} />
        ))}
        <Closing kindText={kindText} report={report} issuedOn={issuedOn} context={context} />
      </PrintImageGate>
    </div>
  );
}

type PageContext = { setName: string; setCode: string; collectionName: string; totalPages: number };

function BrandLogo() {
  return (
    <>
      {/* eslint-disable-next-line @next/next/no-img-element -- asset estático local, padrão das folhas impressas */}
      <img src="/brand/logo-full-light.png" alt="MMKYU" className={`${styles.brandLogo} ${styles.brandLogoLight}`} />
      {/* eslint-disable-next-line @next/next/no-img-element -- variante para o papel escuro do tema escuro */}
      <img src="/brand/logo-full-dark.png" alt="" aria-hidden="true" className={`${styles.brandLogo} ${styles.brandLogoDark}`} />
    </>
  );
}

function Cover({
  setName,
  setCode,
  logoUrl,
  collectionName,
  kindText,
  report,
  issuedOn,
}: {
  setName: string;
  setCode: string;
  logoUrl: string | null;
  collectionName: string;
  kindText: string;
  report: BookletReport;
  issuedOn: string;
}) {
  const percent = progressPercent(report.satisfied, report.positions);
  return (
    <section className={`${styles.page} ${styles.cover}`} aria-label={`Capa do Caderno de Cartas — ${setName}`}>
      <CoverField className={styles.field} />
      <div className={styles.pageInner}>
        <div className={styles.coverTop}>
          <BrandLogo />
          <span className={styles.eyebrow}>Caderno de Cartas</span>
        </div>

        <div className={styles.coverCenter}>
          {logoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element -- logo assinado do Card Set (bucket privado), mesmo padrão dos relatórios
            <img src={logoUrl} alt={`Logo de ${setName}`} className={styles.setLogo} />
          ) : (
            <span className={styles.monogram} aria-hidden="true">
              {setCode}
            </span>
          )}
          <p className={styles.kicker}>
            <HatchMark className={styles.kickerMark} />
            {setCode ? `${setCode} · ` : ""}
            {N.format(report.cards.length)} cartas
          </p>
          <h1 className={styles.coverTitle}>{setName}</h1>
          <p className={styles.coverSubtitle}>O guia visual do Set, carta por carta, na ordem da coleção.</p>
          <div className={styles.coverMeta}>
            <span className={`${styles.chip} ${styles.chipGold}`}>{kindText}</span>
            <span className={styles.chip}>Coleção · {collectionName}</span>
          </div>
        </div>

        <div className={styles.coverBottom}>
          <div className={styles.coverFacts}>
            <span>
              Edição de <strong>{issuedOn}</strong>
            </span>
            <span>
              {N.format(report.rarities.length)} {report.rarities.length === 1 ? "raridade" : "raridades"} · {N.format(report.totalPages)} páginas
            </span>
          </div>
          <div
            className={styles.seal}
            style={{ "--p": percent } as CSSProperties}
            role="img"
            aria-label={`Coleção: ${report.percentText} completa, ${N.format(report.satisfied)} de ${N.format(report.positions)} posições`}
          >
            <span className={styles.sealText}>
              <span className={styles.sealValue}>{report.percentText}</span>
              <span className={styles.sealLabel}>completa</span>
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}

function OwnedMark() {
  return (
    <span className={`${styles.mark} ${styles.markOwned}`} aria-hidden="true">
      <Check strokeWidth={3.25} />
    </span>
  );
}

function StatusMark({ status }: { status: BookletCard["status"] }) {
  if (status === "owned") return <OwnedMark />;
  if (status === "partial") return <span className={`${styles.mark} ${styles.markPartial}`} aria-hidden="true" />;
  if (status === "missing") return <span className={`${styles.mark} ${styles.markMissing}`} aria-hidden="true" />;
  return null;
}

function LegendSample({ status }: { status: BookletCard["status"] }) {
  return (
    <span style={{ position: "relative", width: "1.15rem", height: "1.15rem", flex: "none" }}>
      <span style={{ position: "absolute", inset: 0 }}>
        <StatusMark status={status} />
      </span>
    </span>
  );
}

function Opening({
  kind,
  kindText,
  collectionName,
  report,
  context,
}: {
  kind: ChecklistKind;
  kindText: string;
  collectionName: string;
  report: BookletReport;
  context: PageContext;
}) {
  const master = kind === "MASTER_SET";
  return (
    <section className={`${styles.page} ${styles.opening}`} aria-labelledby="booklet-opening">
      <PageField className={styles.field} variant={1} />
      <div className={styles.pageInner}>
        <span className={styles.eyebrow}>Antes de começar</span>
        <h2 id="booklet-opening" className={styles.sectionTitle}>
          Como ler este caderno
        </h2>
        <p className={styles.lede}>{CARD_BOOKLET_INTRO}</p>
        <ZigzagRule className={styles.rule} />

        <div className={styles.openingGrid}>
          <div>
            <h3 className={styles.blockTitle}>Marcas da sua coleção</h3>
            <ul className={styles.legendList}>
              <li className={styles.legendItem}>
                <LegendSample status="owned" />
                <span>
                  {master ? "Completa" : "Obtida"}
                  <small>{master ? "todos os acabamentos do objetivo atendidos nesta coleção" : "ao menos um exemplar alocado nesta coleção"}</small>
                </span>
              </li>
              {master ? (
                <li className={styles.legendItem}>
                  <LegendSample status="partial" />
                  <span>
                    Parcial
                    <small>parte dos acabamentos do objetivo atendidos</small>
                  </span>
                </li>
              ) : null}
              <li className={styles.legendItem}>
                <LegendSample status="missing" />
                <span>
                  {master ? "Pendente" : "Falta"}
                  <small>{master ? "nenhum acabamento do objetivo atendido nesta coleção — você pode ter a carta em outro acabamento ou em outra coleção" : "sem exemplar alocado nesta coleção — pode estar no acervo ou em outra coleção"}</small>
                </span>
              </li>
              {report.outsideCards > 0 ? (
                <li className={styles.legendItem}>
                  <span style={{ width: "1.15rem", flex: "none" }} />
                  <span>
                    Sem marca
                    <small>carta sem posição no objetivo (acabamentos não adotados)</small>
                  </span>
                </li>
              ) : null}
            </ul>
            {master && report.finishLegend.length > 0 ? (
              <>
                <h3 className={styles.blockTitle} style={{ marginTop: "1.4rem" }}>
                  Acabamentos do objetivo
                </h3>
                <p className={styles.legendItem} style={{ gap: "0.5rem" }}>
                  <span className={`${styles.finish} ${styles.finishOwned}`}>HR</span>
                  <span className={styles.finish}>HR</span>
                  <small style={{ fontSize: "0.72rem", color: "var(--bk-muted)" }}>atendido · pendente</small>
                </p>
                <div className={styles.finishLegend}>
                  {report.finishLegend.map((f) => (
                    <span key={f.code}>
                      <b>{f.code}</b>
                      {f.label}
                    </span>
                  ))}
                </div>
              </>
            ) : null}
          </div>

          <div>
            <h3 className={styles.blockTitle}>Raridades do Set</h3>
            <ul className={styles.rarityList}>
              {report.rarities.map((r) => (
                <li key={r.code} className={styles.rarityItem}>
                  <span className={styles.raritySymbolCell}>{r.symbolCode ? <RaritySymbol symbolCode={r.symbolCode} className="h-2.5 w-2.5" /> : null}</span>
                  <span>{r.name}</span>
                  <span className={styles.rarityCount}>
                    {N.format(r.cards)} {r.cards === 1 ? "carta" : "cartas"}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className={styles.pushEnd} style={{ paddingTop: "1.75rem" }}>
          <h3 className={styles.blockTitle}>Este caderno</h3>
          <ul className={styles.factList}>
            <li className={styles.factItem}>
              <span>Coleção</span>
              <span>{collectionName}</span>
            </li>
            <li className={styles.factItem}>
              <span>Modalidade</span>
              <span>{kindText}</span>
            </li>
            <li className={styles.factItem}>
              <span>Cartas no Set</span>
              <span>{N.format(report.cards.length)}</span>
            </li>
            <li className={styles.factItem}>
              <span>{master ? "Posições obtidas (carta × acabamento)" : "Cartas obtidas"}</span>
              <span>
                {N.format(report.satisfied)} de {N.format(report.positions)}
              </span>
            </li>
          </ul>
          <PageFoot context={context} pageNumber={2} />
        </div>
      </div>
    </section>
  );
}

function PageFoot({ context, pageNumber }: { context: PageContext; pageNumber: number }) {
  return (
    <div className={styles.pageFoot}>
      <span>Caderno de Cartas · {context.collectionName}</span>
      <span>
        <b>{pageNumber}</b> / {context.totalPages}
      </span>
    </div>
  );
}

function CardsPage({ page, kind, eager, context }: { page: BookletPage; kind: ChecklistKind; eager: boolean; context: PageContext }) {
  return (
    <section className={`${styles.page} ${styles.cardsPage}`} aria-label={`${bookletRangeText(page)} — página ${page.pageNumber}`}>
      <PageField className={styles.field} variant={page.pageNumber} />
      <div className={styles.pageInner}>
        <header className={styles.running}>
          <span className={styles.runningSet}>
            <HatchMark className={styles.runningMark} />
            {context.setCode ? <strong>{context.setCode}</strong> : null}
            <span>{context.setName}</span>
          </span>
          <span className={styles.runningRange}>{bookletRangeText(page)}</span>
        </header>
        <ol className={styles.grid}>
          {page.cards.map((card, index) => (
            <CardTile key={card.cardId} card={card} kind={kind} eager={eager && index < EAGER_CARDS} />
          ))}
        </ol>
        <PageFoot context={context} pageNumber={page.pageNumber} />
      </div>
    </section>
  );
}

function CardTile({ card, kind, eager }: { card: BookletCard; kind: ChecklistKind; eager: boolean }) {
  const src = cardFrontUrl(SUPABASE_URL, card.imagePath);
  return (
    <li className={styles.tile} aria-label={bookletCardAria(card)}>
      <div className={styles.frame}>
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- imagem original do bucket público (sem transformação faturável), padrão dos relatórios
          <img src={src} alt="" width={63} height={88} loading={eager ? "eager" : "lazy"} decoding="async" className={styles.art} data-print-jpeg="" />
        ) : (
          <span className={styles.artEmpty}>{card.name}</span>
        )}
        <StatusMark status={card.status} />
      </div>
      <div className={styles.caption} aria-hidden="true">
        <span className={styles.captionTop}>
          <span>{bookletNumberText(card)}</span>
          {card.rarity?.symbolCode ? <RaritySymbol symbolCode={card.rarity.symbolCode} className="h-2 w-2" /> : null}
        </span>
        <span className={styles.name} title={card.name}>
          {card.name}
        </span>
        {kind === "MASTER_SET" && card.finishes.length > 0 ? (
          <span className={styles.finishes} title={bookletStatusText(card)}>
            {card.finishes.map((f) => (
              <span key={f.key} className={`${styles.finish} ${f.owned ? styles.finishOwned : ""}`}>
                {f.code ?? f.label}
              </span>
            ))}
          </span>
        ) : null}
      </div>
    </li>
  );
}

function Closing({ kindText, report, issuedOn, context }: { kindText: string; report: BookletReport; issuedOn: string; context: PageContext }) {
  return (
    <section className={`${styles.page} ${styles.closing}`} aria-labelledby="booklet-closing">
      <ClosingField className={styles.field} />
      <div className={styles.pageInner}>
        <span className={styles.eyebrow}>Encerramento</span>
        <div className={styles.closingCenter}>
          <h2 id="booklet-closing" className={styles.sectionTitle}>
            {context.setName}
          </h2>
          <p className={styles.lede} style={{ marginTop: "0.4rem" }}>
            {kindText} · Coleção {context.collectionName}
          </p>
          <ZigzagRule className={styles.rule} />
          <div className={styles.closingStats}>
            <Stat value={N.format(report.cards.length)} label="Cartas no Set" />
            <Stat value={N.format(report.positions)} label="Posições do objetivo" />
            <Stat value={N.format(report.satisfied)} label="Obtidas" />
            <Stat value={N.format(report.missing)} label="Faltam" />
          </div>
        </div>
        <div className={styles.signOff}>
          <BrandLogo />
          <span>
            Edição de {issuedOn} · <b style={{ fontVariantNumeric: "tabular-nums" }}>{report.closingPage}</b> / {report.totalPages}
          </span>
        </div>
      </div>
    </section>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div className={styles.stat}>
      <span className={styles.statValue}>{value}</span>
      <span className={styles.statLabel}>{label}</span>
    </div>
  );
}
