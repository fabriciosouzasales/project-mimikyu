// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/fs-snapshot-store.ts
// Implementação real do SnapshotStore sobre o filesystem local — nunca
// implantado no Supabase (script standalone, Seção 15 do contrato: "Ferramenta
// administrativa: script Deno standalone (fora do banco)"). Cache local
// sanitizado e determinístico: grava exatamente o snapshot serializado
// deterministicamente (snapshot.ts), sem nenhum campo adicional (timestamps de
// request, headers, etc.) — nada aqui é enviado a nenhum lugar além do disco
// local do administrador.

import type { PlannedSnapshotRecord, SnapshotStore } from "./types.ts";

// REVISION-03 (Bloco 4, Snapshot Integrity) — forma canônica de run_code
// (docs/06a-pokemon-catalog-sourcing.md): "RUN-" + 8 dígitos de data (YYYYMMDD)
// + "-" + sequência de no mínimo 8 dígitos. Validado ANTES de qualquer acesso
// a filesystem (tanto em save() quanto em load()) — nunca depois de já ter
// tocado em `Deno.mkdir`/`Deno.writeTextFile`/`Deno.readTextFile`.
export const RUN_CODE_PATTERN = /^RUN-[0-9]{8}-[0-9]{8,}$/;

// Defesa contra path traversal (Bloco 4): mesmo que um run_code batesse
// acidentalmente com o regex acima por composição externa incomum, o valor
// nunca deve conter separador de diretório nem segmento "..". A checagem do
// regex já torna isso estruturalmente impossível (só dígitos e hífens são
// aceitos), mas a validação abaixo é uma segunda camada explícita e
// independente — nunca confia apenas na forma para descartar traversal.
//
// Exportada como função PURA (sem tocar em nenhuma API de filesystem) para
// que a suíte offline (pokemon-catalog-sourcing.test.ts) possa exercitar
// todos os casos de regex/traversal sem precisar de Deno.mkdir/writeTextFile/
// readTextFile reais — só save()/load() abaixo tocam o disco.
export function isSafeRunCode(runCode: string): boolean {
  if (!RUN_CODE_PATTERN.test(runCode)) return false;
  if (runCode.includes("/") || runCode.includes("\\") || runCode.includes("..")) {
    return false;
  }
  return true;
}

function assertSafeRunCode(runCode: string): void {
  if (!isSafeRunCode(runCode)) {
    throw new Error(
      `RUN_CODE_INVALIDO: "${runCode}" não corresponde ao padrão canônico ` +
        `^RUN-[0-9]{8}-[0-9]{8,}$ ou contém sequência incompatível com nome ` +
        `de arquivo seguro (separador de diretório ou "..").`,
    );
  }
}

// Grava o ENVELOPE completo (run_id/run_code/snapshot_hash/plan_outcome/
// snapshot) — nunca só o snapshot cru — para que o arquivo em disco amarre
// inequivocamente o preflight, e o resultado do PLAN que o originou, ao
// snapshot persistido (ver types.ts). O snapshot interno já chega aqui na
// ordenação determinística de snapshot.ts; o envelope em si é construído
// sempre com a mesma ordem de campos, então a serialização também é estável
// para o mesmo estado.
export function buildFsSnapshotStore(directory: string): SnapshotStore {
  return {
    async save(record) {
      assertSafeRunCode(record.runCode);
      await Deno.mkdir(directory, { recursive: true });
      const path = `${directory}/${record.runCode}.snapshot.json`;
      await Deno.writeTextFile(path, JSON.stringify(record));
      return path;
    },
    async load(runCode): Promise<PlannedSnapshotRecord | null> {
      assertSafeRunCode(runCode);
      const path = `${directory}/${runCode}.snapshot.json`;
      try {
        const text = await Deno.readTextFile(path);
        return JSON.parse(text) as PlannedSnapshotRecord;
      } catch (error) {
        if (error instanceof Deno.errors.NotFound) return null;
        throw error;
      }
    },
  };
}
