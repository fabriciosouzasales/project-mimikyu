// Project Mimikyu — Edge Function: import-card-assets
// Storage Service — CONFIRMADO DEPLOYADO e CONCLUÍDO no Sprint B3.20, junto
// com index.ts v2.3.0 (ver docs/06-pipeline-importacao.md, "Sprint B3.20").
//
// Extraído de dentro de index.ts nesta revisão — refatoração mínima e
// deliberada, aprovada por Fabrício antes de escalar de um teste controlado
// (1 carta) para o processamento em lote (188 cartas da ME1): download da
// imagem, cálculo de checksum SHA-256, montagem do caminho no Storage e
// upload passam a viver aqui; `index.ts` volta a ter responsabilidade única
// de orquestrar (Convenção #6).
//
// Caminho de Storage inclui o idioma (`me1/en/001.webp`) desde esta revisão,
// para não colidir com uma futura importação em `pt-BR` da mesma carta.

type DownloadedImage = {
  sourceUrl: string;
  buffer: ArrayBuffer;
  mimeType: string;
  fileExtension: string;
  fileSizeBytes: number;
  checksumSha256: string;
};

type UploadImageParams = {
  supabase: any;
  bucketCode: string;
  storagePath: string;
  image: DownloadedImage;
};

export async function calculateSha256(
  arrayBuffer: ArrayBuffer,
): Promise<string> {
  const hashBuffer = await crypto.subtle.digest(
    "SHA-256",
    arrayBuffer,
  );

  return Array.from(new Uint8Array(hashBuffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function resolveFileExtension(mimeType: string): string {
  switch (mimeType) {
    case "image/jpeg":
      return "jpg";
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    default:
      return "bin";
  }
}

/**
 * A URL retornada pela TCGdex é uma URL-base; o sufixo /high.webp seleciona
 * a imagem em alta resolução no formato WebP.
 */
export function buildTcgdexHighImageUrl(
  baseImageUrl: string,
): string {
  return `${baseImageUrl}/high.webp`;
}

export function buildCardStoragePath(
  cardSetCode: string,
  collectorNumber: string,
  languageCode: string,
  fileExtension: string,
): string {
  return [
    cardSetCode.toLowerCase(),
    languageCode,
    `${collectorNumber}.${fileExtension}`,
  ].join("/");
}

export async function downloadImage(
  sourceUrl: string,
): Promise<DownloadedImage> {
  const response = await fetch(sourceUrl);

  if (!response.ok) {
    throw new Error(
      `IMAGE_DOWNLOAD_FAILED: ${response.status} ${response.statusText}`,
    );
  }

  const buffer = await response.arrayBuffer();

  if (buffer.byteLength === 0) {
    throw new Error("IMAGE_DOWNLOAD_EMPTY");
  }

  const mimeType =
    response.headers.get("content-type")
      ?.split(";")[0]
      ?.trim() || "application/octet-stream";
  const fileExtension = resolveFileExtension(mimeType);

  if (fileExtension === "bin") {
    throw new Error(
      `IMAGE_MIME_TYPE_NOT_SUPPORTED: ${mimeType}`,
    );
  }

  const checksumSha256 = await calculateSha256(buffer);

  return {
    sourceUrl,
    buffer,
    mimeType,
    fileExtension,
    fileSizeBytes: buffer.byteLength,
    checksumSha256,
  };
}

export async function uploadImage({
  supabase,
  bucketCode,
  storagePath,
  image,
}: UploadImageParams) {
  const { error } = await supabase.storage
    .from(bucketCode)
    .upload(
      storagePath,
      image.buffer,
      {
        contentType: image.mimeType,
        cacheControl: "3600",
        upsert: true,
      },
    );

  if (error) {
    console.error(
      "STORAGE UPLOAD ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `STORAGE_UPLOAD_FAILED: ${error.message}`,
    );
  }

  const { data } = supabase.storage
    .from(bucketCode)
    .getPublicUrl(storagePath);

  return {
    storagePath,
    publicUrl: data.publicUrl,
  };
}
