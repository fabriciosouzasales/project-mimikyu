import { Gem, Layers, Sparkles } from "lucide-react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { collectionKindBadge, collectionKindDetail } from "@/lib/colecoes/colecoes";
import styles from "./colecoes.module.css";

type KindSource = {
  cardSetName: string | null;
  cardSetCode: string | null;
  completionPolicy: string | null;
  coverCode?: string | null;
};

/**
 * Selo de tipo da coleção (UX-08): Set · Master Set · Pokédex · Livre, com o
 * ícone de cada um. Visual — o tipo por extenso já está no nome acessível do
 * link (`collectionSubtitle`).
 */
export function CollectionKindBadge({ policy }: { policy: string | null }) {
  const badge = collectionKindBadge(policy);
  if (!badge) return null;
  const Icon = badge.kind === "pokedex" ? Pokeball : badge.kind === "master" ? Gem : badge.kind === "free" ? Sparkles : Layers;
  return (
    <span className={styles.kindBadge} data-kind={badge.kind} aria-hidden="true">
      <Icon className={styles.kindBadgeIcon} strokeWidth={2} />
      {badge.label}
    </span>
  );
}

/** Linha "selo + detalhe" usada nos três modos da Biblioteca. */
export function CollectionKindLine({ collection }: { collection: KindSource }) {
  return (
    <>
      <CollectionKindBadge policy={collection.completionPolicy} />
      {collectionKindDetail(collection)}
    </>
  );
}
