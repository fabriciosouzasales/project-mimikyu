import Link from "next/link";
import { formatCount } from "@/lib/colecoes/acervo";
import { type HeroCardSource, missingCount } from "@/lib/colecoes/colecoes";
import type { MasterSetPositionsPage } from "@/lib/colecoes/master-set";
import type { PokedexPositionsPage } from "@/lib/colecoes/pokedex";
import { type SharedModalityFilter, sharedModalityHref } from "@/lib/colecoes/shared-modalities";
import { type SharedCollection, sharedCollectionHref } from "@/lib/colecoes/sharing";
import { MasterSetGallery } from "../colecoes/master-set-gallery";
import heroStyles from "../colecoes/collection-hero.module.css";
import styles from "../colecoes/colecoes.module.css";
import { SharedPokedexGrid } from "./shared-pokedex-grid";

/** `data = null` = a leitura falhou (erro ou formato); a página só monta isto quando a leitura respondeu. */
export type SharedModality =
  | { kind: "MASTER_SET"; filter: SharedModalityFilter; page: number; data: MasterSetPositionsPage | null }
  | { kind: "POKEDEX"; filter: SharedModalityFilter; data: PokedexPositionsPage | null };

/**
 * V1-13 · E3-6 — Master Set e Pokédex do participante (EDITOR e VIEWER), só
 * leitura. Mesmas abas Todas · Tenho · Faltam da grade do Set (contagens do
 * progresso da 5312) e as MESMAS grades do titular (`MasterSetGallery`,
 * `PokedexGrid`) sem gerenciar exemplares, sem preços, Favoritos, Lista de
 * desejos, "No seu acervo" ou quantidade de exemplares.
 */
/** `editPokedex` (F3-2): configuração D1 + EDITOR + coleção ativa, decidido no servidor; só mostra o painel — não autoriza. */
export function SharedModalityGallery({ collection, modality, editPokedex = false }: { collection: SharedCollection; modality: SharedModality; editPokedex?: boolean }) {
  const base = sharedCollectionHref(collection.collectionId);
  const total = collection.progress?.total ?? 0;
  const owned = collection.progress?.satisfied ?? 0;
  const master = modality.kind === "MASTER_SET";
  const segments: { key: SharedModalityFilter; label: string; count: number }[] = [
    { key: "todas", label: "Todas", count: total },
    { key: "tenho", label: master ? "Tenho" : "Capturados", count: owned },
    { key: "faltam", label: "Faltam", count: missingCount(owned, total) },
  ];
  const current = segments.find((s) => s.key === modality.filter);
  const shown = modality.data?.total ?? 0;
  const noun = master ? (shown === 1 ? "posição" : "posições") : "Pokémon";
  const title = master ? "Posições do Master Set" : "Pokédex da coleção";

  return (
    <section className={heroStyles.gallery} aria-labelledby="compartilhada-cartas">
      <div className={heroStyles.galleryHead}>
        <div className={heroStyles.galleryHeadText}>
          <h2 id="compartilhada-cartas" className={heroStyles.galleryTitle}>
            {title}
          </h2>
          {modality.data ? (
            <p className={heroStyles.galleryMeta}>
              {current?.label} · {formatCount(shown)} {noun}
            </p>
          ) : null}
        </div>
        <div className={heroStyles.galleryTools}>
          <nav className={styles.filterTabs} aria-label={master ? "Mostrar posições" : "Mostrar Pokémon"}>
            {segments.map((segment) => (
              <Link
                key={segment.key}
                href={sharedModalityHref(base, segment.key)}
                scroll={false}
                className={styles.filterTab}
                aria-current={segment.key === modality.filter ? "page" : undefined}
              >
                {segment.label}
                <span className={styles.filterTabCount}>{formatCount(segment.count)}</span>
              </Link>
            ))}
          </nav>
        </div>
      </div>

      {modality.kind === "MASTER_SET" ? (
        <MasterSetGallery
          collectionId={collection.collectionId}
          collectionName={collection.name}
          filter={modality.filter}
          page={modality.page}
          positions={modality.data}
          outOfScopeCount={null}
          setCode={collection.cardSetCode}
          manageable={false}
          hrefFor={(filter, page) => sharedModalityHref(base, filter, page)}
          showQuantities={false}
        />
      ) : modality.data === null ? (
        <p className="py-12 text-center text-sm text-muted-foreground" role="alert">
          Não conseguimos carregar os Pokémon agora.{" "}
          <Link href={sharedModalityHref(base, modality.filter)} className="underline underline-offset-2" prefetch={false}>
            Tentar de novo
          </Link>
        </p>
      ) : modality.data.items.length === 0 ? (
        <p className="py-12 text-center text-sm text-muted-foreground">
          {modality.filter === "faltam" ? "Nenhum Pokémon faltando — esta Pokédex está completa." : "Nenhum Pokémon capturado nesta coleção ainda."}
        </p>
      ) : (
        <SharedPokedexGrid
          collectionId={collection.collectionId}
          filter={modality.filter}
          initial={modality.data.items}
          total={modality.data.total}
          label={`Pokédex — ${current?.label ?? "Todas"}`}
          editable={editPokedex}
        />
      )}
    </section>
  );
}

/** Fontes do leque/fundo do hero: só o que a leitura já trouxe e está na coleção. */
export function sharedModalityHero(modality: SharedModality): HeroCardSource[] {
  if (!modality.data) return [];
  if (modality.kind === "MASTER_SET") {
    return modality.data.items
      .filter((p) => p.isSatisfied)
      .map((p) => ({ cardId: p.key, cardName: p.cardName, collectorNumber: p.collectorNumber, collectorTotal: p.collectorTotal, imagePath: p.imagePath, isSatisfied: true }));
  }
  return modality.data.items.flatMap((p) =>
    p.isSatisfied && p.representative?.imagePath
      ? [{ cardId: p.positionId, cardName: p.representative.cardName, collectorNumber: p.representative.collectorNumber ?? "", collectorTotal: null, imagePath: p.representative.imagePath, isSatisfied: true }]
      : [],
  );
}
