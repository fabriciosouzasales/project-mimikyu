import { classifyFinish, finishLayerSpec, type FinishNumbering } from "@/lib/colecoes/card-finish";
import styles from "./acervo.module.css";

/**
 * Brilho do acabamento sobre a frente da carta (Meu acervo) —
 * MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01, protótipo aprovado em 1×.
 *
 * Componente de servidor, sem estado: decide pela função pura
 * `classifyFinish` (códigos estáveis da 5261/5262) e desenha no máximo um
 * grupo de camadas decorativas (`aria-hidden`). Padrão, especial, desconhecido
 * ou geometria incerta → nada é desenhado; a carta aparece como é e o chip
 * textual da variante continua sendo a informação.
 *
 * Duas camadas, linguagem do `HoloCard`:
 * - foil: arco-íris estático em `overlay` — visível em repouso, inclusive no
 *   celular e com movimento reduzido. Nenhuma animação contínua.
 * - sheen: o MESMO reflexo do `HoloCard` (`.holo-card__sheen`, globals.css),
 *   que só aparece no hover/foco e segue `--holo-x/--holo-y` gravados por
 *   `FinishPointer` (uma carta por vez).
 *
 * Recorte por contêiner com overflow (sem stacking context próprio), não por
 * clip-path nas camadas de tela cheia — no protótipo o clip-path deixava a
 * holográfica inteira esbranquiçada no hover.
 */
export function CardFinishLayers({
  variantTypeCode,
  rarityCode,
  numbering,
}: {
  variantTypeCode: string | null;
  rarityCode: string | null;
  /** Número e total do Set: carta secreta → brilho na carta toda. */
  numbering: FinishNumbering;
}) {
  const spec = finishLayerSpec(classifyFinish(variantTypeCode, rarityCode, numbering));
  if (!spec) return null;
  return (
    <span className={styles.finish} data-area={spec.area} data-tone={spec.tone} aria-hidden="true">
      <span className={styles.finishFoil} />
      <span className={`holo-card__sheen ${styles.finishSheen}`} />
    </span>
  );
}

/** Atributo para o contêiner da arte: liga o rastreio do ponteiro só onde há brilho. */
export function finishDataAttribute(
  variantTypeCode: string | null,
  rarityCode: string | null,
  numbering: FinishNumbering,
): { "data-finish"?: string } {
  const finish = classifyFinish(variantTypeCode, rarityCode, numbering);
  return finish.effect === "none" ? {} : { "data-finish": finish.effect };
}
