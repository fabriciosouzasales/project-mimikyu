"use client";

import { ClipboardList } from "lucide-react";
import { readLocationInventory } from "@/app/colecoes/locais/actions";
import { shareInFlight } from "@/lib/reports/in-flight";
import { LOCATION_INVENTORY_TITLE, buildLocationInventory, locationInventoryIncompleteText } from "@/lib/reports/location-inventory";
import { FitSheet } from "./fit-sheet";
import { LocationInventorySheet } from "./location-inventory-report";
import { type ReportSheetEntry, ReportSheetOverlay } from "./report-sheet-overlay";

type InventoryResult = Awaited<ReturnType<typeof readLocationInventory>>;

/** Uma leitura por local por vez; nada em cache depois. */
const inFlight = new Map<string, () => Promise<InventoryResult>>();
function readOnce(id: string): Promise<InventoryResult> {
  let shared = inFlight.get(id);
  if (!shared) {
    shared = shareInFlight(() => readLocationInventory({ id }));
    inFlight.set(id, shared);
  }
  return shared();
}

function unavailableSheet(title: string, text: string) {
  return (
    <div className="mx-auto max-w-[210mm] rounded-lg border border-border px-6 py-10 text-center print:hidden" role="status">
      <p className="text-sm font-semibold">{title}</p>
      <p className="mt-2 text-xs text-muted-foreground">{text}</p>
    </div>
  );
}

/** Resultado da leitura → entrada da casca (exportada para teste). Incompleto → impressão bloqueada. */
export function locationInventoryEntry(result: InventoryResult): ReportSheetEntry {
  if (result.ok) {
    const { location, read } = result.data;
    const report = buildLocationInventory({ items: read.items, readComplete: read.complete, locationCopies: location.cardCount });
    return {
      status: "ready",
      incomplete: locationInventoryIncompleteText(report.incompleteReason),
      // Celular: a folha A4 inteira cabe na largura da tela (escala só na tela; impressão intacta).
      sheet: (
        <FitSheet>
          <LocationInventorySheet locationName={location.name} kindLabel={location.kindLabel} report={report} issuedAt={result.issuedAt} />
        </FitSheet>
      ),
    };
  }
  if (result.reason === "error") return { status: "error" };
  return { status: "ready", incomplete: "Este local não está disponível.", sheet: unavailableSheet("Local não encontrado", "Ele pode ter sido excluído. Nada foi alterado.") };
}

/**
 * V1-14 — bloco Locais — "Inventário do Local" em SOBREPOSIÇÃO a Meus locais,
 * na casca única dos relatórios (acesso, foco, Esc, tela cheia, impressão A4
 * bloqueada quando incompleto). Somente leitura; só o titular (5219 + 5220).
 */
export function LocationInventoryOverlay({ locationId, onClose }: { locationId: string; onClose: () => void }) {
  return (
    <ReportSheetOverlay
      eyebrow={
        <>
          <ClipboardList aria-hidden="true" />
          Relatório do local
        </>
      }
      title={LOCATION_INVENTORY_TITLE}
      context="Local · todas as cartas guardadas aqui, por Card Set, para conferência"
      errorNote="Nada foi alterado no seu acervo."
      load={() => readOnce(locationId).then(locationInventoryEntry)}
      onClose={onClose}
    />
  );
}
