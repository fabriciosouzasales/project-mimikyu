import { ChevronDown } from "lucide-react";
import { StateGlyph } from "@/components/card/price-glyph";
import {
  type VariantPrice,
  compactPriceDetail,
  formatBrl,
  isPriceMuted,
  priceIndicator,
  priceState,
} from "@/lib/pricing/variant-pricing";
import styles from "./acervo.module.css";

/**
 * Etiqueta de preço sobre a arte da carta no Acervo (V1-09, REFINEMENT-06).
 * Mesma linguagem da etiqueta aprovada do fichário (chip escuro no canto
 * inferior esquerdo, ícone de estado quando não atual), na escala do cartão
 * do Acervo — sem alterar o fichário. Só visual: o cartão já é link e o
 * preço entra no nome acessível dele; não captura ponteiro e não cobre a
 * quantidade nem a marca de seleção (canto superior direito).
 * Sem preço: nada (D5).
 */
export function AcervoPriceTag({ price, now }: { price: VariantPrice | null | undefined; now: number }) {
  const state = priceState(price, now);
  const indicator = priceIndicator(state);
  if (!price || !indicator || price.brlAmount === null) return null;
  return (
    <span className={styles.priceTag} data-price-state={state} data-muted={isPriceMuted(state) || undefined} aria-hidden="true">
      {indicator.glyph !== "current" ? <StateGlyph indicator={indicator} className={styles.priceTagGlyph} /> : null}
      {formatBrl(price.brlAmount)}
    </span>
  );
}

/**
 * Preço de referência no detalhe do exemplar — composição compacta
 * (V1-09, REFINEMENT-06). Primeira camada: valor, acabamento ou "preço geral
 * da carta", fonte e atualização (estado desatualizado/sem data sempre
 * visível, com ícone e texto). Segunda camada em `<details>` nativo: abre
 * por clique, toque, Enter/Espaço e é anunciada como expansível por leitores
 * de tela — sem JavaScript e sem depender de hover.
 * `price === undefined`: a leitura falhou (diferente de "sem preço").
 */
export function AcervoPriceCompact({
  price,
  variantName,
  languageCode,
  now,
}: {
  price: VariantPrice | null | undefined;
  variantName: string | null;
  languageCode: string | null;
  now: number;
}) {
  const titleId = "acervo-preco-referencia";
  if (price === undefined) {
    return (
      <section className={styles.price} aria-labelledby={titleId}>
        <h3 id={titleId} className={styles.priceEyebrow}>
          Referência NM
        </h3>
        <p className={styles.priceEmpty}>Não foi possível carregar o preço de referência agora.</p>
      </section>
    );
  }
  const detail = compactPriceDetail(price, { variantName, languageCode, now });
  if (detail.amount === null || !detail.freshness) {
    return (
      <section className={styles.price} aria-labelledby={titleId} data-price-state={detail.state}>
        <h3 id={titleId} className={styles.priceEyebrow}>
          Referência NM
        </h3>
        <p className={styles.priceEmpty}>{detail.message}</p>
      </section>
    );
  }
  const indicator = priceIndicator(detail.state);
  return (
    <section className={styles.price} aria-labelledby={titleId} data-price-state={detail.state}>
      <h3 id={titleId} className={styles.priceEyebrow}>
        Referência NM
      </h3>
      <p className={styles.priceLine}>
        <span className={styles.priceAmount}>{detail.amount}</span>
        <span className={styles.priceFinish}>{detail.generalCardPrice ? "Preço geral da carta" : detail.finish}</span>
      </p>
      <p className={styles.priceMeta}>
        <span>{detail.source}</span>
        <span aria-hidden="true">·</span>
        <span className={styles.priceFresh} data-tone={detail.freshness.tone}>
          {indicator && detail.freshness.tone !== "current" ? <StateGlyph indicator={indicator} className={styles.priceFreshGlyph} /> : null}
          {detail.freshness.text}
        </span>
      </p>
      <details className={styles.priceMore}>
        <summary className={styles.priceMoreSummary}>
          <ChevronDown className={styles.priceMoreChevron} aria-hidden="true" />
          Detalhes do preço
        </summary>
        <div className={styles.priceMoreBody}>
          {detail.facts.length > 0 ? (
            <dl className={styles.priceFacts}>
              {detail.facts.map((fact) => (
                <div key={fact.label}>
                  <dt>{fact.label}</dt>
                  <dd>{fact.value}</dd>
                </div>
              ))}
            </dl>
          ) : null}
          <ul className={styles.priceNotes}>
            {detail.notes.map((note) => (
              <li key={note}>{note}</li>
            ))}
          </ul>
        </div>
      </details>
    </section>
  );
}
