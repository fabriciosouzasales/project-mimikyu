import Link from "next/link";
import { AlertTriangle, ArrowLeft, Info, Trophy } from "lucide-react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Button } from "@/components/ui/button";
import { formatCount } from "@/lib/colecoes/acervo";
import { COLECOES_PATH, collectionKindLabel, missingCount, progressBarPercent, progressPercentText } from "@/lib/colecoes/colecoes";
import type { CollectionSummary } from "@/lib/colecoes/colecoes-queries";
import { COLLECTION_MANAGE_ENABLED } from "@/lib/colecoes/collection-manage";
import { FREE_COVER_CODE_ENABLED, FREE_COVER_UPLOAD_ENABLED } from "@/lib/colecoes/free-collection";
import {
  type GenerationOption,
  type PokedexFilter,
  type PokedexPositionsPage,
  POKEDEX_COLLECTION_ENABLED,
  currentSelection,
  generationNumeral,
  generationTitle,
  pokedexHref,
  selectionLabel,
} from "@/lib/colecoes/pokedex";
import acervoStyles from "../acervo/acervo.module.css";
import { BinderCover } from "./binder-cover";
import heroStyles from "./collection-hero.module.css";
import { CollectionSettingsButton } from "./collection-manage";
import manageStyles from "./collection-manage.module.css";
import { CollectionTitle } from "./collection-title";
import { CoverFinishPicker } from "./cover-finish-picker";
import { CoverLogoTrigger } from "./cover-logo-uploader";
import { PokedexBulkLauncher } from "./pokedex-bulk-link";
import { PokedexGrid } from "./pokedex-grid";
import styles from "./colecoes.module.css";
import pkxStyles from "./pokedex.module.css";

/**
 * Coleção "Completar a Pokédex" (PKX-02), Server Component.
 *
 * - Progresso: só o canônico — total/conquistadas da coleção vêm de R1
 *   (`collection_completion_summary`, 5102) e, por geração, da 5201. Nada é
 *   recontado aqui.
 * - Grade: 5204 paginada no servidor, ordem nacional, filtros Todas / Tenho /
 *   Faltam e por geração (na URL), "Mostrar mais" incremental.
 * - Ajustes: identidade, gerações (5203) e Onde guardo.
 * - Vínculo de cartas (PKX-03, atrás de POKEDEX_COLLECTION_ENABLED e só com
 *   a coleção ativa): painel por Pokémon na grade (5208–5210 + 6124/6125/5047)
 *   e "Completar com o acervo" em lote (5211 + 5046).
 */
export function PokedexCollectionView({
  collection,
  filter,
  generation,
  positions,
  options,
  coverLogoUrl = null,
  userId = null,
}: {
  collection: CollectionSummary;
  filter: PokedexFilter;
  generation: string | null;
  /** `null` = leitura falhou. */
  positions: PokedexPositionsPage | null;
  /** 5201 com a coleção. `null` = leitura falhou (filtro por geração some). */
  options: GenerationOption[] | null;
  /** URL assinada da imagem da capa (5176–5178/5206); `null` = placa tipográfica. */
  coverLogoUrl?: string | null;
  /** Dono da sessão — pasta do envio da capa; `null` = envio indisponível. */
  userId?: string | null;
}) {
  const active = collection.lifecycleStatus === "ACTIVE";
  const canManage = COLLECTION_MANAGE_ENABLED && active;
  // Capa e código próprios, como na Coleção livre (5178/5180 ampliados pela 5206/5207).
  const coverUpload = FREE_COVER_UPLOAD_ENABLED && POKEDEX_COLLECTION_ENABLED && active && userId !== null;
  const codeEditable = FREE_COVER_CODE_ENABLED && POKEDEX_COLLECTION_ENABLED;
  // Vincular cartas (PKX-03): mesma flag da Pokédex, só em coleção ativa.
  const linkable = POKEDEX_COLLECTION_ENABLED && active;
  const total = collection.totalPositions;
  const owned = collection.satisfiedPositions;
  const missing = missingCount(owned, total);

  const selected = options ? options.filter((option) => option.selected === true) : [];
  const generationOption = generation ? selected.find((option) => option.code === generation) ?? null : null;
  // Contagens das abas: da coleção inteira ou, com geração escolhida, da própria geração (5201).
  const scopeTotal = generationOption ? generationOption.speciesCount : total;
  const scopeOwned = generationOption ? Math.min(generationOption.satisfied ?? 0, generationOption.speciesCount) : owned;
  const segments: { key: PokedexFilter; label: string; count: number }[] = [
    { key: "todas", label: "Todas", count: scopeTotal },
    { key: "tenho", label: "Tenho", count: scopeOwned },
    { key: "faltam", label: "Faltam", count: missingCount(scopeOwned, scopeTotal) },
  ];
  const segment = segments.find((item) => item.key === filter);
  const scopeText = options ? selectionLabel(currentSelection(options), options) : null;
  const gridLabel = `Pokémon — ${segment?.label ?? "Todas"}${generationOption ? `, ${generationTitle(generationOption.code)}` : ""}`;

  const cover = (
    <BinderCover
      finish={collection.finish}
      setName={null}
      setCode={collection.coverCode}
      logoUrl={coverLogoUrl}
      fallbackTitle={collection.name}
      complete={collection.isComplete}
      size="compact"
      emblem="pokedex"
      priority
    />
  );

  return (
    <div className={acervoStyles.root}>
      <header className={`${acervoStyles.hero} ${heroStyles.hero}`}>
        <div className={acervoStyles.stageGlow} aria-hidden="true" />
        <Pokeball className={pkxStyles.heroEmblem} strokeWidth={0.6} aria-hidden="true" />
        <div className={manageStyles.heroBar}>
          <Link href={COLECOES_PATH} className={styles.backLink}>
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Minhas coleções
          </Link>
          {canManage ? (
            <CollectionSettingsButton
              collectionId={collection.id}
              collectionName={collection.name}
              kind="pokedex"
              identity={{
                name: collection.name,
                finish: collection.finish,
                finishEditable: collection.finishEditable,
                coverCode: codeEditable ? collection.coverCode : undefined,
                hasCoverImage: coverUpload ? collection.coverLogoPath !== null : undefined,
              }}
            />
          ) : null}
        </div>
        <div className={heroStyles.stage}>
          <div className={heroStyles.text}>
            <div className={heroStyles.identity}>
              <div className={heroStyles.identityCover}>
                {coverUpload && userId ? (
                  <CoverLogoTrigger collectionId={collection.id} userId={userId} hasLogo={collection.coverLogoPath !== null}>
                    {cover}
                  </CoverLogoTrigger>
                ) : (
                  cover
                )}
              </div>
              <div className={heroStyles.identityText}>
                <div className={heroStyles.title}>
                  <CollectionTitle
                    collectionId={collection.id}
                    name={collection.name}
                    editable={active}
                    coverCode={codeEditable ? collection.coverCode : undefined}
                  />
                </div>
                <p className={heroStyles.setLine}>
                  <span>
                    {collectionKindLabel(collection.completionPolicy)}
                    {!active ? " · Arquivada" : null}
                  </span>
                </p>
                {scopeText ? (
                  <p className={pkxStyles.scopeLine}>
                    Pokédex Nacional · <strong>{scopeText}</strong>
                  </p>
                ) : null}
                {collection.finishEditable && active ? (
                  <CoverFinishPicker collectionId={collection.id} value={collection.finish} />
                ) : null}
              </div>
            </div>

            <section className={heroStyles.progress} aria-label="Progresso da Pokédex">
              <div className={styles.progressFigure}>
                <span className={heroStyles.progressBig}>{formatCount(owned)}</span>
                <span className={styles.progressOf}>de {formatCount(total)}</span>
                <span className={styles.progressPct}>{collection.isComplete ? "100%" : progressPercentText(owned, total)}</span>
              </div>
              <div
                className={`${styles.track} ${heroStyles.track}`}
                role="progressbar"
                aria-valuemin={0}
                aria-valuemax={total}
                aria-valuenow={owned}
                aria-valuetext={`${formatCount(owned)} de ${formatCount(total)} Pokémon conquistados`}
              >
                <div className={collection.isComplete ? `${styles.fill} ${styles.fillComplete}` : styles.fill} style={{ width: `${progressBarPercent(owned, total)}%` }} />
              </div>
              <div className={styles.progressFoot}>
                {collection.isComplete ? (
                  <span className={styles.completeNote}>
                    <Trophy className="h-4 w-4" aria-hidden="true" />
                    Pokédex completa
                  </span>
                ) : (
                  <span>
                    Faltam <strong>{formatCount(missing)}</strong> Pokémon
                  </span>
                )}
                <span>
                  <strong>{formatCount(collection.copiesCount)}</strong> {collection.copiesCount === 1 ? "carta" : "cartas"} na coleção
                </span>
              </div>
            </section>
          </div>
        </div>
      </header>

      <section className={heroStyles.gallery} aria-labelledby="pokedex-especies">
        <div className={heroStyles.galleryHead}>
          <div className={heroStyles.galleryHeadText}>
            <h2 id="pokedex-especies" className={heroStyles.galleryTitle}>
              Pokémon da Pokédex
            </h2>
            {positions !== null ? (
              <p className={heroStyles.galleryMeta}>
                {segment?.label}
                {generationOption ? ` · ${generationTitle(generationOption.code)}` : ""} · {formatCount(positions.total)}{" "}
                Pokémon
              </p>
            ) : null}
          </div>
          <div className={heroStyles.galleryTools}>
            {linkable && !collection.isComplete ? (
              <PokedexBulkLauncher collectionId={collection.id} generation={generationOption?.code ?? null} />
            ) : null}
            <nav className={styles.filterTabs} aria-label="Mostrar Pokémon">
              {segments.map((item) => (
                <Link
                  key={item.key}
                  href={pokedexHref(collection.id, item.key, generationOption?.code ?? null)}
                  scroll={false}
                  className={styles.filterTab}
                  aria-current={item.key === filter ? "page" : undefined}
                >
                  {item.label}
                  <span className={styles.filterTabCount}>{formatCount(item.count)}</span>
                </Link>
              ))}
            </nav>
          </div>
        </div>

        {selected.length > 1 ? (
          <nav className={pkxStyles.genRail} aria-label="Filtrar por geração">
            <Link
              href={pokedexHref(collection.id, filter, null)}
              scroll={false}
              className={pkxStyles.genChip}
              aria-current={generationOption === null ? "page" : undefined}
            >
              <span className={pkxStyles.genChipTitle}>Todas</span>
              <span className={pkxStyles.genChipMeta}>
                {formatCount(owned)}/{formatCount(total)}
              </span>
            </Link>
            {selected.map((option) => {
              const got = Math.min(option.satisfied ?? 0, option.speciesCount);
              return (
                <Link
                  key={option.code}
                  href={pokedexHref(collection.id, filter, option.code)}
                  scroll={false}
                  className={pkxStyles.genChip}
                  aria-current={generationOption?.code === option.code ? "page" : undefined}
                  aria-label={`${generationTitle(option.code)}${option.region ? `, ${option.region}` : ""}: ${formatCount(got)} de ${formatCount(option.speciesCount)} Pokémon`}
                >
                  <span className={pkxStyles.genChipTitle}>
                    Ger. {generationNumeral(option.code)}
                    {option.region ? <span className="font-normal text-muted-foreground"> · {option.region}</span> : null}
                  </span>
                  <span className={pkxStyles.genChipMeta} aria-hidden="true">
                    {formatCount(got)}/{formatCount(option.speciesCount)}
                  </span>
                  <span className={pkxStyles.genChipTrack} aria-hidden="true">
                    <span
                      className={pkxStyles.genChipFill}
                      style={{ width: `${progressBarPercent(got, option.speciesCount)}%` }}
                    />
                  </span>
                </Link>
              );
            })}
          </nav>
        ) : null}

        {generation && !generationOption && options !== null ? (
          <p className={pkxStyles.notice} role="status">
            <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            Essa geração não faz parte desta Pokédex. Inclua-a em Ajustes, se quiser.
          </p>
        ) : null}

        {positions === null ? (
          <ReadError retryHref={pokedexHref(collection.id, filter, generation)} />
        ) : positions.items.length === 0 ? (
          <Empty filter={filter} collection={collection} hasGeneration={generation !== null} collectionId={collection.id} />
        ) : (
          <PokedexGrid
            collectionId={collection.id}
            filter={filter}
            generation={generationOption?.code ?? null}
            initial={positions.items}
            total={positions.total}
            label={gridLabel}
            linkable={linkable}
          />
        )}
      </section>
    </div>
  );
}

function Empty({
  filter,
  collection,
  hasGeneration,
  collectionId,
}: {
  filter: PokedexFilter;
  collection: CollectionSummary;
  hasGeneration: boolean;
  collectionId: string;
}) {
  if (filter === "faltam") {
    return (
      <section className={acervoStyles.state} aria-labelledby="pokedex-completa">
        <div className={acervoStyles.stateIcon} aria-hidden="true">
          <Trophy className="h-6 w-6" />
        </div>
        <h2 id="pokedex-completa" className={acervoStyles.stateTitle}>
          {hasGeneration ? "Geração completa" : "Não falta nenhum Pokémon"}
        </h2>
        <p className={acervoStyles.stateText}>
          {hasGeneration ? "Cada Pokémon desta geração já tem uma carta na coleção." : `${collection.name} está completa — uma carta de cada Pokémon.`}
        </p>
      </section>
    );
  }
  if (filter === "tenho") {
    return (
      <section className={acervoStyles.state} aria-labelledby="pokedex-vazia">
        <div className={acervoStyles.stateIcon} aria-hidden="true">
          <Pokeball className="h-6 w-6" />
        </div>
        <h2 id="pokedex-vazia" className={acervoStyles.stateTitle}>
          Nenhum Pokémon conquistado ainda
        </h2>
        <p className={acervoStyles.stateText}>
          Cada Pokémon conquistado aparece aqui com a carta que o representa. Em “Todas”, os marcados “No seu acervo” são os que
          você já tem ao alcance.
        </p>
        <Button asChild variant="outline" className={acervoStyles.stateAction}>
          <Link href={pokedexHref(collectionId, "todas", null)}>Ver todos os Pokémon</Link>
        </Button>
      </section>
    );
  }
  return (
    <section className={acervoStyles.state} aria-labelledby="pokedex-sem-especies">
      <h2 id="pokedex-sem-especies" className={acervoStyles.stateTitle}>
        Nenhum Pokémon para mostrar
      </h2>
      <p className={acervoStyles.stateText}>As gerações desta Pokédex podem ter mudado. Volte ao início da coleção.</p>
      <Button asChild variant="outline" className={acervoStyles.stateAction}>
        <Link href={pokedexHref(collectionId, "todas", null)}>Ver a coleção</Link>
      </Button>
    </section>
  );
}

function ReadError({ retryHref }: { retryHref: string }) {
  return (
    <section className={acervoStyles.state} role="alert" aria-labelledby="pokedex-erro">
      <div className={`${acervoStyles.stateIcon} ${acervoStyles.stateIconDanger}`} aria-hidden="true">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h2 id="pokedex-erro" className={acervoStyles.stateTitle}>
        Não conseguimos carregar os Pokémon
      </h2>
      <p className={acervoStyles.stateText}>Nada foi perdido. Tente novamente em instantes.</p>
      <Button asChild className={acervoStyles.stateAction}>
        <Link href={retryHref} prefetch={false}>
          Tentar novamente
        </Link>
      </Button>
    </section>
  );
}
