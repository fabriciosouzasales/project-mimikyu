import { Check } from "lucide-react";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import styles from "./binder-cover.module.css";

/**
 * Capa do fichário de uma coleção (MY-COLLECTIONS-LIBRARY-VISUAL-02).
 *
 * Objeto, não card: caixa 3D real (face + lombada do zíper) com
 * `perspective` + `preserve-3d` — mesma técnica aprovada no Binder fechado,
 * nunca perspectiva pintada à mão. A cor (acabamento) é parte da identidade
 * da coleção; a placa central traz a identidade do Set: o logo quando a
 * sessão pode lê-lo, senão nome e código do Set gravados na placa.
 * Nunca a imagem de uma carta.
 *
 * Server Component puro: sem estado nem JS no cliente. Movimento (inclinação
 * no hover/foco) só com transform, desligado em prefers-reduced-motion.
 */
export function BinderCover({
  finish,
  setName,
  setCode,
  logoUrl,
  fallbackTitle,
  complete,
  size = "shelf",
  priority = false,
}: {
  finish: BinderFinish;
  setName: string | null;
  setCode: string | null;
  logoUrl: string | null;
  /** Título da placa quando a coleção não tem Set (coleção livre). */
  fallbackTitle: string;
  complete: boolean;
  size?: "shelf" | "compact";
  priority?: boolean;
}) {
  const code = setCode?.toUpperCase() ?? null;
  return (
    <div className={styles.stage} data-size={size} aria-hidden="true">
      <div className={styles.scene}>
        <div className={styles.object} data-finish={finish}>
          <div className={styles.face}>
            <span className={styles.grain} />
            <span className={styles.stitch} />
            <div className={styles.plate} data-kind={logoUrl ? "logo" : "type"}>
              {logoUrl ? (
                // eslint-disable-next-line @next/next/no-img-element -- URL assinada do Storage (1 h), já no tamanho do logo
                <img
                  src={logoUrl}
                  alt=""
                  className={styles.logo}
                  loading={priority ? "eager" : "lazy"}
                  decoding="async"
                  draggable={false}
                />
              ) : (
                <span className={styles.plateType}>
                  <span className={styles.plateTitle}>{setName ?? fallbackTitle}</span>
                  {code ? <span className={styles.plateCode}>{code}</span> : null}
                </span>
              )}
            </div>
            {logoUrl && code ? <span className={styles.foilCode}>{code}</span> : null}
            {complete ? (
              <span className={styles.seal}>
                <Check className="h-3.5 w-3.5" strokeWidth={3} />
              </span>
            ) : null}
            <span className={styles.mark}>MMKYU</span>
          </div>
          <div className={styles.edge}>
            <span className={styles.zipper} />
          </div>
        </div>
      </div>
      <span className={styles.floor} />
    </div>
  );
}
