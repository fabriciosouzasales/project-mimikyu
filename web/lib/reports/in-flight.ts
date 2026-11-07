/**
 * V1-14 R1-G — uma leitura por vez: enquanto uma chamada equivalente estiver em andamento, quem
 * pedir de novo recebe a MESMA operação (ex.: o efeito de carga rodando duas vezes no React Strict
 * Mode). Nada fica guardado depois que ela termina — sucesso ou falha —, então cada nova abertura
 * do relatório lê de novo (sem cache persistente).
 */
export function shareInFlight<T>(run: () => Promise<T>): () => Promise<T> {
  let current: Promise<T> | null = null;
  return () => {
    if (current) return current;
    const operation = run().finally(() => {
      if (current === operation) current = null;
    });
    current = operation;
    return operation;
  };
}
