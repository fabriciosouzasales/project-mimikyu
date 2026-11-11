"use client";

import { Check } from "lucide-react";
import { useEffect } from "react";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import type { PokedexPosition } from "@/lib/colecoes/pokedex";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import {
  POKEDEX_CHECKLIST_TITLE,
  POKEDEX_MISSING_TITLE,
  POKEDEX_REPORT_NOTES,
  type MissingGroup,
  type PokedexSpeciesReport,
  generationLabel,
  missingStateText,
  nationalNumberText,
  speciesCountText,
} from "@/lib/reports/pokedex-species-report";
import { PrintImageGate } from "./print-image-gate";
import { releasePrintJpegs } from "./print-jpeg-images";
import styles from "./pokedex-species-report.module.css";

export { POKEDEX_CHECKLIST_TITLE, POKEDEX_MISSING_TITLE };

const N = new Intl.NumberFormat("pt-BR");
/** Artes carregadas de imediato na tela; as demais sob demanda (o Imprimir prepara todas antes). */
const EAGER = 40;

export type PokedexSheetMode = "checklist" | "missing";

/**
 * F2-2 (D7 §4q) — folha do "Checklist da Pokédex" e das "Espécies faltantes". Mesma folha, cabeçalho
 * e rodapé dos relatórios homologados (`RelatorioFolha`), com a ARTE DA ESPÉCIE como elemento visual —
 * o que distingue estes relatórios dos checklists de cartas. Só apresenta o que o núcleo entregou
 * (`pokedex-species-report.ts`): espécies do objetivo (gerações escolhidas), atendimento canônico e o
 * estado do acervo da 5204. Unidade sempre "espécie".
 *
 * - Checklist: uma seção por geração (nome, atendidas/total, %), espécies em ordem nacional; atendida =
 *   arte em cor + selo dourado; pendente = arte em cinza esmaecida + anel vazio (legível sem cor).
 * - Faltantes: três grupos — disponíveis para vincular, em outras coleções, sem exemplar no acervo —
 *   cada espécie com número, nome e situação; soma dos grupos = pendentes.
 * - Impressão A4: cabeçalho institucional repetido (`<thead>`), indicadores na 1ª folha, grade fixa de
 *   10 colunas, espécie nunca partida; artes convertidas em JPEG no Imprimir (PDF leve).
 */
export function PokedexSpeciesSheet({
  mode,
  collectionName,
  report,
  issuedAt,
}: {
  mode: PokedexSheetMode;
  collectionName: string;
  report: PokedexSpeciesReport;
  issuedAt: string;
}) {
  useEffect(() => releasePrintJpegs, []);
  const generationsText = report.generations.length === 1 ? generationLabel(report.generations[0]!) : `${N.format(report.generations.length)} gerações`;
  const title = mode === "checklist" ? POKEDEX_CHECKLIST_TITLE : POKEDEX_MISSING_TITLE;

  return (
    <RelatorioFolha>
      <div className="px-4 sm:px-6 print:px-0" data-pokedex-report="">
        <table className="w-full" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>
          <thead>
            <tr>
              <th className="p-0 text-left font-normal">
                <div className="-mx-4 sm:-mx-6 print:mx-0">
                  <RelatorioCabecalho
                    ajusteCelular
                    titulo={title}
                    identificacaoColecao={collectionName}
                    subtitulo={`Pokédex · ${speciesCountText(report.total)} no objetivo · ${generationsText} · Emitido em ${issuedAt}`}
                  />
                </div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td className="p-0 align-top">
                {mode === "checklist" ? <ChecklistBody report={report} /> : <MissingBody report={report} />}
                <ul className="mt-4 space-y-0.5 border-t border-neutral-200 py-2 text-[9px] leading-snug text-neutral-500" style={{ breakInside: "avoid" }}>
                  {POKEDEX_REPORT_NOTES.map((note) => (
                    <li key={note}>{note}</li>
                  ))}
                  {mode === "missing" ? <li>&ldquo;Sem exemplar no acervo&rdquo; diz respeito ao seu acervo — não significa que não exista carta da espécie.</li> : null}
                </ul>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <RelatorioRodape />
    </RelatorioFolha>
  );
}

function ChecklistBody({ report }: { report: PokedexSpeciesReport }) {
  if (report.total === 0) return <StateMessage title="O objetivo desta Pokédex não tem espécies." text="Escolha gerações nos Ajustes da coleção para montar o checklist. Nada foi alterado." />;
  let index = 0;
  return (
    <>
      <section aria-label="Indicadores da Pokédex" className="grid grid-cols-2 gap-2 pb-4 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
        <Indicator label="Completude" value={report.percentText} note={`${N.format(report.satisfied)} de ${speciesCountText(report.total)}`} emphasis />
        <Indicator label="Espécies no objetivo" value={N.format(report.total)} note="gerações escolhidas" />
        <Indicator label="Atendidas" value={N.format(report.satisfied)} note="com exemplar vinculado" />
        <Indicator label="Pendentes" value={N.format(report.missing)} note={report.missing === 0 ? "Pokédex completa" : "ainda sem exemplar vinculado"} />
      </section>
      <PrintImageGate>
        {report.generations.map((g) => {
          const start = index;
          index += g.species.length;
          return (
            <section key={g.code} className={styles.group} aria-label={generationLabel(g)}>
              <header className={styles.groupHead}>
                <h3 className={styles.groupTitle}>{generationLabel(g)}</h3>
                <span className={styles.groupMeta}>
                  {N.format(g.satisfied)} de {speciesCountText(g.species.length)}
                </span>
              </header>
              <ol className={styles.grid}>
                {g.species.map((p, i) => (
                  <SpeciesTile key={p.positionId} position={p} eager={start + i < EAGER} variant="checklist" />
                ))}
              </ol>
            </section>
          );
        })}
      </PrintImageGate>
      <Legend />
    </>
  );
}

function MissingBody({ report }: { report: PokedexSpeciesReport }) {
  if (report.total === 0) return <StateMessage title="O objetivo desta Pokédex não tem espécies." text="Escolha gerações nos Ajustes da coleção. Nada foi alterado." />;
  if (report.missing === 0 && report.complete)
    return <StateMessage title="Pokédex completa." text={`Todas as ${speciesCountText(report.total)} do objetivo estão atendidas nesta coleção.`} />;
  const [available, elsewhere, notFound] = report.missingGroups as [MissingGroup, MissingGroup, MissingGroup];
  let index = 0;
  return (
    <>
      <section aria-label="Indicadores das espécies faltantes" className="grid grid-cols-2 gap-2 pb-4 pt-1 sm:grid-cols-4 print:grid-cols-4" style={{ breakInside: "avoid" }}>
        <Indicator label="Faltantes" value={N.format(report.missing)} note={`de ${speciesCountText(report.total)} · ${report.percentText} completa`} emphasis />
        <Indicator label="Disponíveis para vincular" value={N.format(available.species.length)} note="exemplar livre no acervo" />
        <Indicator label="Em outras coleções" value={N.format(elsewhere.species.length)} note="depende de reorganizar" />
        <Indicator label="Sem exemplar no acervo" value={N.format(notFound.species.length)} note="falta obter um exemplar" />
      </section>
      <PrintImageGate>
        {report.missingGroups.map((g) => {
          if (g.species.length === 0) return null;
          const start = index;
          index += g.species.length;
          return (
            <section key={g.key} className={styles.group} aria-label={g.title} data-missing-group={g.key}>
              <header className={styles.groupHead}>
                <h3 className={styles.groupTitle}>{g.title}</h3>
                <span className={styles.groupMeta}>{speciesCountText(g.species.length)}</span>
              </header>
              <p className={styles.groupHint}>{g.hint}</p>
              <ol className={styles.grid}>
                {g.species.map((p, i) => (
                  <SpeciesTile key={p.positionId} position={p} eager={start + i < EAGER} variant="missing" />
                ))}
              </ol>
            </section>
          );
        })}
      </PrintImageGate>
    </>
  );
}

function SpeciesTile({ position, eager, variant }: { position: PokedexPosition; eager: boolean; variant: "checklist" | "missing" }) {
  const src = speciesArtworkUrl(position.artworkPath);
  const done = position.isSatisfied;
  const status = variant === "checklist" ? (done ? "atendida" : "pendente") : missingStateText(position);
  return (
    <li className={styles.tile} data-pending={variant === "checklist" && !done ? "" : undefined} aria-label={`${nationalNumberText(position.number)} ${position.speciesName}: ${status}`}>
      <div className={styles.art} aria-hidden="true">
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- arte pública da espécie (bucket próprio), padrão da página Pokédex
          <img src={src} alt="" width={120} height={120} loading={eager ? "eager" : "lazy"} decoding="async" data-print-jpeg-species="" />
        ) : (
          <span className={styles.noArt}>{nationalNumberText(position.number)}</span>
        )}
        {variant === "checklist" ? (
          <span className={styles.mark} data-done={done ? "" : undefined}>
            {done ? <Check strokeWidth={3.25} /> : null}
          </span>
        ) : null}
      </div>
      <span className={styles.number} aria-hidden="true">
        {nationalNumberText(position.number)}
      </span>
      <span className={styles.name} title={position.speciesName} aria-hidden="true">
        {position.speciesName}
      </span>
      {variant === "missing" ? (
        <span className={styles.state} data-state={position.state} aria-hidden="true">
          {missingStateText(position)}
        </span>
      ) : null}
    </li>
  );
}

function Legend() {
  return (
    <p className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-1 text-[10px] text-neutral-600 print:text-[8.5px]" style={{ breakInside: "avoid" }}>
      <span className="inline-flex items-center gap-1.5">
        <span className={`${styles.legendMark} ${styles.legendDone}`} aria-hidden="true">
          <Check strokeWidth={3.25} />
        </span>
        Atendida (arte em cor)
      </span>
      <span className="inline-flex items-center gap-1.5">
        <span className={styles.legendMark} aria-hidden="true" />
        Pendente (arte em cinza)
      </span>
    </p>
  );
}

function StateMessage({ title, text }: { title: string; text: string }) {
  return (
    <div className="my-6 rounded-lg border border-dashed border-neutral-300 px-6 py-8 text-center" role="status">
      <p className="text-sm font-semibold text-neutral-900">{title}</p>
      <p className="mt-2 text-xs text-neutral-600">{text}</p>
    </div>
  );
}

function Indicator({ label, value, note, emphasis = false }: { label: string; value: string; note?: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border border-neutral-200 px-3 py-2 ${emphasis ? "border-l-4 border-l-primary" : ""}`}>
      <p className="text-[9px] font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="font-heading text-base font-bold tabular-nums text-neutral-900">{value}</p>
      {note ? <p className="text-[9px] leading-snug text-neutral-500">{note}</p> : null}
    </div>
  );
}
