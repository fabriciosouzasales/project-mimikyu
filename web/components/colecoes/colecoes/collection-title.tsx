import acervoStyles from "../acervo/acervo.module.css";
import { ArchivedBadge } from "./collection-lifecycle";
import styles from "./colecoes.module.css";

/**
 * Título da coleção na página. UX-06 (decisão de Fabrício, 2026-10-19): a
 * edição de nome e código saiu da página — mora em Ajustes → Identidade
 * (`collection-identity-settings.tsx`), junto com a imagem e a cor do
 * fichário. Aqui só o nome, em destaque.
 */
export function CollectionTitle({ name, archived = false }: { name: string; archived?: boolean }) {
  return (
    <div className={styles.titleRow}>
      <h1 className={acervoStyles.title}>{name}</h1>
      {/* V1-04: estado arquivado junto ao título, sem faixa nem aviso no corpo. */}
      {archived ? <ArchivedBadge /> : null}
    </div>
  );
}
