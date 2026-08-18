<#
Project Mimikyu - Local runner for the PTAX FX Rate connector (scripts/sync-ptax-fx-rate.ts)
File: scripts/Executar-P9-PTAX-Local.ps1

Objective: orchestrate locally, on Fabricio's machine, the execution of
scripts/sync-ptax-fx-rate.ts - the only place authorized to run a real PTAX sync,
since the agent sandbox has no Deno runtime available and no network route to
olinda.bcb.gov.br (proxy blocked by allowlist).

This is an OPERATIONAL script, same precedent as scripts/Executar-P8-JustTCG-Local.ps1
- it is not normative documentation under docs/, and must not be read as part of the
Pricing domain model. It does not change the database, migrations, documentation, or
the logic of scripts/sync-ptax-fx-rate.ts - it only calls the existing script, with
the correct credentials and the minimum Deno permissions, then produces a sanitized
summary of the execution.

Revised (Incremento P13.2, 2026-08-18): the connector was rewritten around a shared
core (supabase/functions/_shared/pricing-ptax/) and now has a different contract than
the one this runner was originally built against:
  - the default window is CALCULATED (10 civil dates ending "today" in
    America/Sao_Paulo), not the old hardcoded 2026-08-10..2026-08-17 pilot window;
  - a real write execution now requires --confirmed-by=<admin_user_uuid> (same
    precedent as the P8 JustTCG connector - validated against admin_user by
    validate_pricing_sync_run_confirmed_by());
  - --dry-run is a real connector flag now (never requires --confirmed-by, never
    writes to pricing_fx_rate nor to pricing_sync_run/pricing_sync_run_call);
  - --override-start=/--override-end= allow a controlled manual backfill window
    (both required together, max span mirrored below from MAX_OVERRIDE_WINDOW_DAYS).
This runner was updated in the same round to match - every hardcoded-window
assumption from the original P9 version (PILOT_DATA_INICIAL/PILOT_DATA_FINAL,
the fixed 6-business-dates/2-weekend-dates expectation, and the mandatory two-run
idempotency proof built on top of that fixed window) was removed. A single
invocation per runner run is now the norm; idempotency itself is still guaranteed
by the connector (ON CONFLICT DO NOTHING at the database level, confirmed in
Incremento P9) and is covered by the connector's own --fixture-check suite, not by
this runner re-proving it against a fixed window on every real call.

Deno permissions granted, always the minimum list for each step (never a bare
`--allow-env` or `--allow-net`):
  - --fixture-check: `--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY` - main() in
    the connector reads both variables unconditionally (Deno.env.get) to decide
    whether to run a real execution or fall back to --fixture-check, even when
    --fixture-check is explicitly requested - so this permission is required even
    though no credential value is read yet (nothing is set in the environment at this
    point). No `--allow-net` is granted here - runFixtureCheck() makes no network call.
  - Real execution (write or --dry-run): `--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY`
    and `--allow-net=olinda.bcb.gov.br,<supabase-host>` - olinda.bcb.gov.br is the
    fixed host of BCB_PTAX_API_BASE in the shared core (the BCB Olinda PTAX API is
    public, no API key exists or is requested); <supabase-host> is extracted and
    validated (HTTPS required) from the real SUPABASE_URL value only after the
    operator types it in - never a hardcoded domain, never a bare --allow-net. Even
    --dry-run needs --allow-net, because it still performs a real HTTP call to BCB -
    it only skips writing to Supabase.

Flow, in the required order:
  1. Resolve the repository root robustly (falls back to searching upward for
     CLAUDE.md + scripts\sync-ptax-fx-rate.ts if $PSScriptRoot/$MyInvocation are
     unavailable or point somewhere unexpected).
  2. Validate the presence of Deno on PATH.
  3. Run --fixture-check (offline, no network, no write) BEFORE asking for any real
     credential - if it fails, abort without ever requesting a secret.
  4. Only then request SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY safely
     (Read-Host -AsSecureString, never echoed on screen, never written to a file).
     Not requested at all if -FixtureOnly.
  5. Validate all connector-facing arguments BEFORE ever invoking Deno: -OverrideStart
     and -OverrideEnd must be given together (never just one), both must be valid
     YYYY-MM-DD civil dates, start must not be after end, and the span must not
     exceed the max override window mirrored below. -ConfirmedBy (required for any
     execution that is not -DryRun) must be a syntactically valid UUID. Any failure
     here aborts with a clear PowerShell-level message, before Deno is ever started -
     the connector itself would reject the same bad input, but only after already
     being launched.
  6. Ask for explicit confirmation before making a real HTTP call to BCB (both for a
     real write and for -DryRun - only the write-to-Supabase part changes, the BCB
     call itself always happens for both).
  7. Run the connector exactly once with the resolved arguments.
  8. Best-effort, read-only re-read of pricing_fx_rate for the resolved window
     afterwards (only when a real write execution was requested - skipped for
     -DryRun and for -FixtureOnly, since neither writes anything) - never
     inserts/updates/deletes, only used to let the operator see, with real data,
     what is present in that window. A missing date inside the window is NOT
     flagged as an error (weekend/holiday without a quote is expected).
  9. Remove the two sensitive environment variables from the current process at the
     end, always (try/finally - even if something fails in the middle).
  10. Write only a sanitized summary (.md) to a folder OUTSIDE the Git repository
      ($env:TEMP by default) - never inside project-mimikyu, eliminating any risk of
      accidentally committing test residue. SUPABASE_SERVICE_ROLE_KEY (or any other
      secret) is never written to this file, never printed to the console - only
      redacted output ever reaches Write-Host or the summary file.

Key format compatibility (2026-08-17): the newer generation of Supabase API keys
(sb_secret_.../sb_publishable_...) is not a JWT and must be sent ONLY in the "apikey"
header for the read-only PostgREST validation call this runner makes - sending it in
"Authorization: Bearer" as well can be rejected by the gateway. Legacy JWT-format keys
(starting with "eyJ", three dot-separated segments) keep receiving both headers,
exactly as before - Get-CabecalhosSupabase() detects the format automatically, no
operator action required.

Note on accented characters in THIS file: deliberately avoided throughout (pt-BR
written without diacritics, e.g. "execucao" instead of "execucao" with a cedilla) -
long-standing convention of this specific runner to sidestep Windows PowerShell 5.1
source-encoding fragility. Regexes that parse the connector's own stdout (which DOES
use accented pt-BR, since it always runs under Deno/UTF-8) match on unaccented,
unambiguous substrings only (e.g. "recebidas do BCB:" rather than the accented
"Cotacoes recebidas do BCB:") - never a literal accented character inside this file.

Usage:
  # Full flow, default window (10 civil dates ending today, America/Sao_Paulo),
  # asks interactively for credentials and for the admin UUID (--confirmed-by):
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1

  # Same, but admin UUID given up front (skips the interactive prompt for it):
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1 -ConfirmedBy "11111111-1111-1111-1111-111111111111"

  # Dry-run: real HTTP call to BCB, nothing written to Supabase, no --confirmed-by
  # needed or asked for:
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1 -DryRun

  # Controlled manual backfill (both dates required together):
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1 -ConfirmedBy "11111111-1111-1111-1111-111111111111" -OverrideStart "2026-07-01" -OverrideEnd "2026-07-31"

  # Offline validation only, never asks for a real credential (useful to revalidate
  # the logic after any update to sync-ptax-fx-rate.ts or the shared core itself):
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1 -FixtureOnly

  # Repository root known in advance, skips the upward search:
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1 -RepoRoot "C:\path\to\project-mimikyu"

Never paste SUPABASE_SERVICE_ROLE_KEY into chat, a log, or an issue - only into the
secure prompt opened by this script. The admin UUID passed via -ConfirmedBy is not a
secret (it is a public foreign key value, same as any other primary key) and may be
typed directly as a parameter or at the plain (non-secure) prompt.
#>

[CmdletBinding()]
param(
    # Repository path - defaults to the parent folder of scripts\ (where this file
    # lives). $PSScriptRoot is empty in some Windows PowerShell 5.1 invocations with
    # "-File" and a relative path (known platform quirk) - hence the fallback chain
    # below, and a further upward search (see Resolve-RepoRootRobusto) if none of
    # these produce a folder that actually contains scripts\sync-ptax-fx-rate.ts.
    [string]$RepoRoot = $(
        if ($PSScriptRoot) {
            (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        } elseif ($MyInvocation.MyCommand.Path) {
            (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")).Path
        } else {
            (Get-Location).Path
        }
    ),

    # Folder where the sanitized summary (.md) is written - outside the repository by
    # default.
    [string]$OutputDir = (Join-Path $env:TEMP "project-mimikyu-p13-ptax-local-runs"),

    # Stops at the fixture-check - never requests a real credential, never touches
    # the network, never comes close to the Supabase project.
    [switch]$FixtureOnly,

    # Forwards --dry-run to the connector: real HTTP call to BCB, ZERO writes to
    # Supabase (neither pricing_fx_rate nor pricing_sync_run/pricing_sync_run_call).
    # Never requires -ConfirmedBy - if given anyway alongside -DryRun, it is ignored
    # (the connector's own contract never reads confirmedBy on the dry-run path).
    [switch]$DryRun,

    # Admin UUID forwarded as --confirmed-by=<value> - required for any execution
    # that is not -DryRun. If omitted here and a real write execution is requested,
    # the script prompts for it interactively (plain text - not a secret).
    [string]$ConfirmedBy,

    # Backfill window override - both required together (validated below), forwarded
    # as --override-start=/--override-end=. Omit both to use the connector's default
    # 10-date window ending today (America/Sao_Paulo).
    [string]$OverrideStart,
    [string]$OverrideEnd
)

$ErrorActionPreference = "Stop"

# The connector prints UTF-8 on stdout (accented pt-BR text in a few places). Windows
# PowerShell 5.1's console normally decodes external process output using the system
# ANSI/OEM code page, not UTF-8 - without this, accented text coming from Deno may show
# up as mojibake even though the exit code and everything actually written to Supabase
# is correct. This only affects on-screen readability, never any written data or the
# sanitized summary file. Best-effort: if the host cannot switch, keep going.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    Write-Host "Aviso: nao foi possivel forcar UTF-8 no console - saida do Deno com acentos pode aparecer ilegivel, sem impacto funcional." -ForegroundColor DarkYellow
}

# ============================================================================
# 0. Resolucao robusta da raiz do repositorio
# ============================================================================

function Resolve-RepoRootRobusto {
    param([Parameter(Mandatory)][string]$CandidatoInicial)

    $candidatoScript = Join-Path $CandidatoInicial "scripts\sync-ptax-fx-rate.ts"
    if (Test-Path $candidatoScript) {
        return (Resolve-Path $CandidatoInicial).Path
    }

    # Fallback: sobe a partir do diretorio atual procurando os dois marcadores juntos
    # (CLAUDE.md + scripts\sync-ptax-fx-rate.ts) - evita parar em uma pasta scripts\ de
    # outro projeto que por coincidencia tenha um arquivo de mesmo nome.
    $probe = Get-Item (Get-Location).Path
    for ($i = 0; $i -lt 12; $i++) {
        $candidatoClaudeMd = Join-Path $probe.FullName "CLAUDE.md"
        $candidatoScript2 = Join-Path $probe.FullName "scripts\sync-ptax-fx-rate.ts"
        if ((Test-Path $candidatoClaudeMd) -and (Test-Path $candidatoScript2)) {
            return $probe.FullName
        }
        if (-not $probe.PSIsContainer) { break }
        $parentPath = Split-Path -Parent $probe.FullName
        if ([string]::IsNullOrEmpty($parentPath) -or $parentPath -eq $probe.FullName) { break }
        $probe = Get-Item $parentPath
    }

    # Nenhum marcador encontrado - devolve o candidato original sem alteracao; a
    # checagem de Test-Path logo no fluxo principal vai reportar o erro com clareza.
    return $CandidatoInicial
}

$RepoRoot = Resolve-RepoRootRobusto -CandidatoInicial $RepoRoot
$TsScriptPath = Join-Path $RepoRoot "scripts\sync-ptax-fx-rate.ts"

# ============================================================================
# 1. Constantes fixas (identidade da fonte cambial, nao dependem da janela) e
#    parametro espelhado do nucleo compartilhado.
# ============================================================================

$ExpectedFromCurrency   = "USD"
$ExpectedToCurrency     = "BRL"
$ExpectedRateSourceCode = "BCB_PTAX"

$BcbApiHost = "olinda.bcb.gov.br"   # mesmo host de BCB_PTAX_API_BASE em url.ts

# Espelha MAX_OVERRIDE_WINDOW_DAYS em supabase/functions/_shared/pricing-ptax/period.ts
# - se aquele valor mudar, atualizar aqui tambem (nao ha como derivar isso sem tocar
# o Deno, fora do escopo deste runner PowerShell).
$MaxOverrideWindowDays = 90

# User-Agent explicito e nao-browser para as leituras PostgREST deste runner.
# Windows PowerShell 5.1 usa por padrao um User-Agent que se parece com o de um
# navegador, e o gateway do Supabase pode rejeitar chaves novas (sb_secret_*) nesse
# contexto mesmo com o header apikey correto - um User-Agent explicito evita isso.
$PtaxRunnerUserAgent = "project-mimikyu-p9-runner/1.0"

# ============================================================================
# 2. Sanitizacao defensiva
# ============================================================================

function Protect-SensitiveText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = $Text
    $t = $t -replace 'eyJ[A-Za-z0-9_\-\.]{20,}', '[REDACTED_SUPABASE_JWT]'
    $t = $t -replace 'sb_(secret|publishable)_[A-Za-z0-9_\-]+', '[REDACTED_SUPABASE_KEY]'
    $t = $t -replace '(?i)x-api-key\s*:\s*\S+', 'x-api-key: [REDACTED]'
    $t = $t -replace '(?i)authorization\s*:\s*\S+', 'authorization: [REDACTED]'
    $t = $t -replace '(?i)bearer\s+\S+', 'Bearer [REDACTED]'
    return $t
}

# ============================================================================
# 3. Deno - validacao de presenca antes de qualquer outra coisa
# ============================================================================

function Test-DenoPresente {
    $deno = Get-Command deno -ErrorAction SilentlyContinue
    if (-not $deno) {
        Write-Host "Deno nao encontrado no PATH." -ForegroundColor Red
        Write-Host "Instale em https://docs.deno.com/runtime/getting_started/installation/ e reabra o terminal antes de rodar este script novamente." -ForegroundColor Yellow
        exit 1
    }
    $versionLine = (& deno --version | Select-Object -First 1)
    Write-Host "Deno detectado: $versionLine" -ForegroundColor Green
}

# ============================================================================
# 4. Validacao de argumentos ANTES de chamar o Deno (UUID, datas, pareamento
#    start/end, janela maxima) - falha rapido, sem gastar uma unica chamada real.
# ============================================================================

function Test-UuidValido {
    param([AllowEmptyString()][string]$Valor)
    if ([string]::IsNullOrWhiteSpace($Valor)) { return $false }
    return ($Valor -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
}

function Test-DataCivilValida {
    param([AllowEmptyString()][string]$Valor)
    if ([string]::IsNullOrWhiteSpace($Valor)) { return $false }
    if ($Valor -notmatch '^\d{4}-\d{2}-\d{2}$') { return $false }
    $parsed = [DateTime]::MinValue
    return [DateTime]::TryParseExact(
        $Valor, 'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

# Calcula a janela padrao (10 datas corridas terminando hoje, America/Sao_Paulo) para
# fins somente informativos deste runner - espelha resolveDefaultPeriod() em
# period.ts, nunca e o que decide a janela real (isso e sempre o proprio conector).
function Get-JanelaEsperada {
    param(
        [AllowNull()][string]$OverrideStart,
        [AllowNull()][string]$OverrideEnd
    )
    if ($OverrideStart -and $OverrideEnd) {
        return [PSCustomObject]@{ Inicio = $OverrideStart; Fim = $OverrideEnd }
    }
    try {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("E. South America Standard Time")
        $agoraSp = [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $tz)
    } catch {
        # Fallback: id de fuso do Windows ausente no host (raro) - Brasil nao observa
        # horario de verao desde 2019, entao offset fixo UTC-3 e equivalente na pratica.
        $agoraSp = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(-3))
    }
    $fim = $agoraSp.Date
    $inicio = $fim.AddDays(-9)
    return [PSCustomObject]@{ Inicio = $inicio.ToString('yyyy-MM-dd'); Fim = $fim.ToString('yyyy-MM-dd') }
}

# Valida toda a combinacao de argumentos relevante ANTES de qualquer chamada ao Deno.
# Lanca excecao (mensagem clara) no primeiro problema encontrado - o chamador decide
# o que fazer (aqui, sempre abortar).
function Confirm-ArgumentosConector {
    param(
        [bool]$DryRun,
        [AllowNull()][string]$ConfirmedBy,
        [AllowNull()][string]$OverrideStart,
        [AllowNull()][string]$OverrideEnd
    )

    $temInicio = -not [string]::IsNullOrWhiteSpace($OverrideStart)
    $temFim = -not [string]::IsNullOrWhiteSpace($OverrideEnd)

    if ($temInicio -ne $temFim) {
        throw "OverrideStart e OverrideEnd devem ser informados juntos (recebido so um dos dois) - sem ambos, omita os dois para usar a janela padrao de 10 datas."
    }

    if ($temInicio -and $temFim) {
        if (-not (Test-DataCivilValida $OverrideStart)) {
            throw "OverrideStart '$OverrideStart' nao e uma data civil valida no formato YYYY-MM-DD."
        }
        if (-not (Test-DataCivilValida $OverrideEnd)) {
            throw "OverrideEnd '$OverrideEnd' nao e uma data civil valida no formato YYYY-MM-DD."
        }
        $dtInicio = [DateTime]::ParseExact($OverrideStart, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $dtFim = [DateTime]::ParseExact($OverrideEnd, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($dtFim -lt $dtInicio) {
            throw "OverrideEnd ($OverrideEnd) nao pode ser anterior a OverrideStart ($OverrideStart)."
        }
        $spanDias = ([int]($dtFim - $dtInicio).Days) + 1
        if ($spanDias -gt $MaxOverrideWindowDays) {
            throw "Janela de override tem $spanDias data(s), acima do maximo permitido ($MaxOverrideWindowDays, espelhando MAX_OVERRIDE_WINDOW_DAYS em period.ts)."
        }
    }

    if (-not $DryRun) {
        if (-not (Test-UuidValido $ConfirmedBy)) {
            throw "ConfirmedBy ausente ou com formato invalido - execucao real (sem -DryRun) exige um UUID valido de admin_user (formato 8-4-4-4-12 hexadecimal)."
        }
    }
}

# ============================================================================
# 5. Captura segura de credenciais Supabase - SecureString na entrada, nunca
#    ecoadas, nunca gravadas em arquivo. Limitacao honesta: uma vez convertida
#    para string gerenciada (necessario para virar variavel de ambiente do
#    processo filho), o .NET nao garante zeragem deterministica da memoria -
#    limite conhecido da plataforma, nao deste script. O SecureString original e
#    descartado (.Dispose()) assim que a conversao termina.
# ============================================================================

function Read-SegredoComoTexto {
    param([Parameter(Mandatory)][string]$Prompt)
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $secure.Dispose()
    }
}

# Extrai e valida o host de SUPABASE_URL - usado para restringir --allow-net ao
# minimo necessario (host real do projeto, nunca um dominio generico *.supabase.co
# nem uma faixa aberta). Exige HTTPS explicitamente. Nunca imprime a SUPABASE_URL
# completa - so o hostname, que nao e sensivel.
function Get-SupabaseHostValidado {
    param([Parameter(Mandatory)][string]$SupabaseUrl)
    try {
        $uri = [System.Uri]$SupabaseUrl
    } catch {
        throw "SUPABASE_URL nao e uma URL valida - nao e possivel restringir --allow-net com seguranca."
    }
    if ($uri.Scheme -ne "https") {
        throw "SUPABASE_URL precisa ser HTTPS (recebido esquema '$($uri.Scheme)') - abortando antes de conceder qualquer --allow-net."
    }
    if ([string]::IsNullOrWhiteSpace($uri.Host) -or $uri.Host -notmatch '^[A-Za-z0-9.\-]+$') {
        throw "Host extraido de SUPABASE_URL tem formato inesperado - abortando antes de conceder qualquer --allow-net."
    }
    return $uri.Host
}

function Clear-CredenciaisDoAmbiente {
    Write-Host "`nRemovendo credenciais das variaveis de ambiente deste processo..." -ForegroundColor DarkGray
    Remove-Item Env:\SUPABASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
}

# A partir da nova geracao de chaves do Supabase (formato sb_secret_.../
# sb_publishable_..., que substitui o par anon/service_role em JWT), a chave deixa
# de ser um JWT valido - deve ir SOMENTE no header "apikey". Enviar "Authorization:
# Bearer <chave>" junto com uma chave nesse novo formato pode ser rejeitado pelo
# gateway. JWT legado (comeca com "eyJ", tres segmentos separados por ponto)
# continua enviado nos dois headers, exatamente como antes.
function Get-CabecalhosSupabase {
    param([Parameter(Mandatory)][string]$ServiceRoleKey)
    if ($ServiceRoleKey -match '^sb_(secret|publishable)_') {
        return @{ "apikey" = $ServiceRoleKey }
    }
    if ($ServiceRoleKey -match '^eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+$') {
        return @{
            "apikey"        = $ServiceRoleKey
            "Authorization" = "Bearer $ServiceRoleKey"
        }
    }
    Write-Host "Aviso: SUPABASE_SERVICE_ROLE_KEY nao bate com o formato novo (sb_secret_/sb_publishable_) nem com o formato JWT legado (eyJ...) - enviando como legado (apikey + Authorization: Bearer); confira se a chave foi colada corretamente." -ForegroundColor DarkYellow
    return @{
        "apikey"        = $ServiceRoleKey
        "Authorization" = "Bearer $ServiceRoleKey"
    }
}

# ============================================================================
# 6. Execucao de uma etapa Deno - captura tudo, redige, so entao exibe/retorna
# ============================================================================

function Invoke-EtapaDeno {
    param(
        [Parameter(Mandatory)][string[]]$DenoArgs,
        [Parameter(Mandatory)][string]$Rotulo
    )
    Write-Host "`n=== $Rotulo ===" -ForegroundColor Cyan
    Write-Host "Comando: deno $($DenoArgs -join ' ')" -ForegroundColor DarkGray

    $rawOutput = & deno @DenoArgs 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $cleanOutput = Protect-SensitiveText $rawOutput

    Write-Host $cleanOutput
    Write-Host "Codigo de saida: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

    return [PSCustomObject]@{
        Rotulo   = $Rotulo
        ExitCode = $exitCode
        Output   = $cleanOutput
    }
}

# Extrai o resultado estruturado impresso por runRealExecution() - "Periodo
# consultado: X a Y", "... recebidas do BCB: N" e o bloco JSON de result.counts
# (inserted/unchanged/divergent/invalid) logo em seguida. So existe quando o
# resultado NAO foi TECHNICAL_FAILURE/FUNCTIONAL_FAILURE (nesses casos o conector
# imprime so uma linha de erro e sai com codigo 1, sem JSON). Ancoras de regex
# deliberadamente sem acento (ver nota no cabecalho deste arquivo) - o texto real
# impresso pelo Deno tem acento, mas o trecho usado como ancora aqui nao precisa.
function Get-ResultadoExecucaoJson {
    param([string]$Texto)
    $periodoMatch = [regex]::Match($Texto, 'consultado:\s*(\d{4}-\d{2}-\d{2})\s*a\s*(\d{4}-\d{2}-\d{2})')
    $cotacoesMatch = [regex]::Match($Texto, 'recebidas do BCB:\s*(\d+)')
    $jsonMatch = [regex]::Match($Texto, 'recebidas do BCB:\s*\d+\s*\r?\n(\{[\s\S]*?\n\})')

    if (-not $periodoMatch.Success -or -not $jsonMatch.Success) { return $null }

    $counts = $null
    try { $counts = $jsonMatch.Groups[1].Value | ConvertFrom-Json } catch { return $null }

    return [PSCustomObject]@{
        PeriodoInicio     = $periodoMatch.Groups[1].Value
        PeriodoFim        = $periodoMatch.Groups[2].Value
        CotacoesRecebidas = [int]$cotacoesMatch.Groups[1].Value
        Counts            = $counts
    }
}

# ============================================================================
# 7. Leitura somente-leitura de pricing_fx_rate via PostgREST - nao insere, nao
#    altera, nao apaga nada; usada so para mostrar, com dado real, o que existe
#    para a janela que foi de fato usada na execucao.
# ============================================================================

function Get-PtaxRatesNaJanela {
    param(
        [Parameter(Mandatory)][string]$SupabaseUrl,
        [Parameter(Mandatory)][string]$ServiceRoleKey,
        [Parameter(Mandatory)][string]$DataInicial,
        [Parameter(Mandatory)][string]$DataFinal
    )
    $baseUrl = $SupabaseUrl.TrimEnd("/")
    $query = "from_currency=eq.$ExpectedFromCurrency" +
             "&to_currency=eq.$ExpectedToCurrency" +
             "&rate_source_code=eq.$ExpectedRateSourceCode" +
             "&rate_date=gte.$DataInicial" +
             "&rate_date=lte.$DataFinal" +
             "&select=rate_date,rate" +
             "&order=rate_date.asc"
    $uri = "$baseUrl/rest/v1/pricing_fx_rate?$query"
    $headers = Get-CabecalhosSupabase -ServiceRoleKey $ServiceRoleKey
    try {
        $rows = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -UserAgent $PtaxRunnerUserAgent -ErrorAction Stop
        if ($null -eq $rows) { return @() }
        return @($rows)
    } catch {
        $msg = Protect-SensitiveText $_.Exception.Message
        Write-Host "Falha ao ler pricing_fx_rate para conferencia (leitura, nao afeta a execucao em si): $msg" -ForegroundColor Yellow
        return $null
    }
}

# Mostra as linhas encontradas na janela - puramente informativo, nao compara
# contra nenhuma lista fixa de datas esperadas (a janela agora e dinamica, calculada
# pelo proprio conector). A unica invariante real verificada aqui e ausencia de
# duplicidade fisica por rate_date, que independe da janela.
function Show-JanelaPtax {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Rows,
        [Parameter(Mandatory)][string]$Rotulo,
        [Parameter(Mandatory)][string]$DataInicial,
        [Parameter(Mandatory)][string]$DataFinal
    )
    if ($null -eq $Rows) {
        Write-Host ("{0}: leitura falhou - ver aviso acima." -f $Rotulo) -ForegroundColor Yellow
        return
    }

    $linhas = @($Rows | Sort-Object { [string]$_.rate_date } | ForEach-Object {
        [PSCustomObject]@{ RateDate = [string]$_.rate_date; Rate = $_.rate }
    })
    $datasUnicas = @($linhas | ForEach-Object { $_.RateDate } | Sort-Object -Unique)
    $duplicidade = ($Rows.Count -ne $datasUnicas.Count)

    Write-Host ("{0}: {1} linha(s) na janela {2} a {3}" -f $Rotulo, $Rows.Count, $DataInicial, $DataFinal)
    foreach ($linha in $linhas) {
        Write-Host ("    {0} = {1}" -f $linha.RateDate, $linha.Rate) -ForegroundColor DarkGray
    }
    if ($Rows.Count -eq 0) {
        Write-Host "  Nenhuma linha na janela - normal se a janela cair inteira em fim de semana/feriado, ou se ainda nao houve execucao real para este periodo." -ForegroundColor DarkGray
    }
    if ($duplicidade) {
        Write-Host "  ERRO: duplicidade detectada (mais de uma linha fisica para a mesma rate_date)." -ForegroundColor Red
    } else {
        Write-Host "  Confirmado: zero duplicidade (no maximo uma linha por rate_date)." -ForegroundColor Green
    }
    Write-Host "  Nota: ausencia de linha para uma data especifica dentro da janela pode ser normal (fim de semana/feriado sem pregao BCB) - nao e, por si so, um erro." -ForegroundColor DarkGray
}

# ============================================================================
# 8. Fluxo principal
# ============================================================================

Test-DenoPresente

if (-not (Test-Path $TsScriptPath)) {
    Write-Host "Nao encontrei $TsScriptPath - use -RepoRoot para apontar a raiz correta do repositorio project-mimikyu (a busca automatica por CLAUDE.md + scripts\sync-ptax-fx-rate.ts tambem nao encontrou nada)." -ForegroundColor Red
    exit 1
}
Write-Host "Repositorio: $RepoRoot" -ForegroundColor DarkGray
Write-Host "Conector: $TsScriptPath" -ForegroundColor DarkGray

$resultados = [ordered]@{}
$script:exitCode = 0

# A partir daqui, credenciais reais podem entrar em $env: - try/finally garante que
# Clear-CredenciaisDoAmbiente roda sempre, mesmo em erro. Todo desvio de fluxo dentro
# deste bloco usa `return` (nunca `exit`), porque `exit` pode pular o `finally` em
# alguns hosts do PowerShell - `return` nao.
try {
    # --- Passo 1: fixture-check, sempre primeiro, sem nenhuma credencial real ---
    $fixture = Invoke-EtapaDeno -Rotulo "Passo 1 - Validacao offline (--fixture-check)" `
        -DenoArgs @("run", "--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY", $TsScriptPath, "--fixture-check")
    $resultados["fixture-check"] = $fixture

    if ($fixture.ExitCode -ne 0) {
        Write-Host "`nFixture-check FALHOU - abortando antes de solicitar qualquer credencial real." -ForegroundColor Red
        Write-Host "Corrija scripts/sync-ptax-fx-rate.ts (ou o nucleo compartilhado, ou reporte a divergencia) antes de tentar uma execucao real." -ForegroundColor Yellow
        $script:exitCode = 1
        return
    }

    Write-Host "`nFixture-check aprovado." -ForegroundColor Green

    if ($FixtureOnly) {
        Write-Host "`n-FixtureOnly ativo - encerrando aqui, execucao real nao solicitada nem executada." -ForegroundColor Yellow
        return
    }

    # --- Validacao de argumentos ANTES de pedir credenciais ou chamar o Deno de
    # verdade - falha rapido, nunca desperdica uma chamada real por causa de um UUID
    # ou uma data mal formatada. Se -ConfirmedBy nao foi passado como parametro e a
    # execucao nao e -DryRun, pede interativamente agora (nao e segredo, texto puro).
    if ((-not $DryRun) -and [string]::IsNullOrWhiteSpace($ConfirmedBy)) {
        Write-Host "`nExecucao real (sem -DryRun) requer o UUID de um administrador real (admin_user.id)." -ForegroundColor Cyan
        $ConfirmedBy = Read-Host "ConfirmedBy (admin_user_uuid)"
    }
    if ($DryRun -and (-not [string]::IsNullOrWhiteSpace($ConfirmedBy))) {
        Write-Host "Nota: -ConfirmedBy foi informado junto com -DryRun - sera ignorado (dry-run nunca abre pricing_sync_run, o conector nem le esse valor nesse modo)." -ForegroundColor DarkGray
    }

    try {
        Confirm-ArgumentosConector -DryRun:$DryRun -ConfirmedBy $ConfirmedBy -OverrideStart $OverrideStart -OverrideEnd $OverrideEnd
    } catch {
        Write-Host "`nValidacao de argumentos falhou ANTES de chamar o Deno: $($_.Exception.Message)" -ForegroundColor Red
        $script:exitCode = 1
        return
    }

    $janelaEsperada = Get-JanelaEsperada -OverrideStart $OverrideStart -OverrideEnd $OverrideEnd
    if ($OverrideStart -and $OverrideEnd) {
        Write-Host "Janela solicitada (override manual): $($janelaEsperada.Inicio) a $($janelaEsperada.Fim)" -ForegroundColor DarkGray
    } else {
        Write-Host "Janela padrao calculada por este runner (informativa - a janela real e sempre calculada pelo proprio conector no momento da execucao): $($janelaEsperada.Inicio) a $($janelaEsperada.Fim)" -ForegroundColor DarkGray
    }

    # --- Coleta segura de credenciais Supabase, so agora que sabemos que vale a pena pedir ---
    Write-Host "`n=== Credenciais Supabase (nunca exibidas na tela) ===" -ForegroundColor Cyan
    Write-Host "Nao ha API key do Banco Central - a API Olinda PTAX e publica e nao exige credencial. So o Supabase pede as duas abaixo." -ForegroundColor DarkGray
    $env:SUPABASE_URL              = Read-SegredoComoTexto -Prompt "SUPABASE_URL"
    $env:SUPABASE_SERVICE_ROLE_KEY = Read-SegredoComoTexto -Prompt "SUPABASE_SERVICE_ROLE_KEY"

    $supabaseHost = Get-SupabaseHostValidado -SupabaseUrl $env:SUPABASE_URL
    Write-Host "Host Supabase validado para --allow-net: $supabaseHost" -ForegroundColor DarkGray
    $allowNetExecucao = "--allow-net=$BcbApiHost,$supabaseHost"

    # --- Confirmacao explicita antes de qualquer chamada real ao BCB ---
    if ($DryRun) {
        Write-Host "`nModo -DryRun: sera feita uma chamada REAL de rede ao BCB (dados publicos de PTAX), mas NADA sera gravado no Supabase (nem pricing_fx_rate, nem pricing_sync_run/pricing_sync_run_call)." -ForegroundColor Yellow
    } else {
        Write-Host "`nEste passo grava de verdade em pricing_fx_rate no Supabase de PRODUCAO (append-only - divergencia nunca sobrescreve uma linha existente) e abre um pricing_sync_run real (run_type=FX_REFRESH, confirmed_by=$ConfirmedBy)." -ForegroundColor Yellow
    }
    $confirma = Read-Host "Confirma a execucao? (s/N)"
    if ($confirma -notin @("s", "S", "sim", "Sim", "SIM")) {
        Write-Host "Execucao cancelada pelo usuario - nada gravado, nenhuma chamada de rede feita." -ForegroundColor Yellow
        return
    }

    # --- Execucao unica do conector com os argumentos resolvidos e ja validados ---
    $denoArgs = @("run", $allowNetExecucao, "--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY", $TsScriptPath)
    if ($DryRun) { $denoArgs += "--dry-run" }
    if (-not $DryRun) { $denoArgs += "--confirmed-by=$ConfirmedBy" }
    if ($OverrideStart -and $OverrideEnd) {
        $denoArgs += "--override-start=$OverrideStart"
        $denoArgs += "--override-end=$OverrideEnd"
    }

    $rotuloExecucao = if ($DryRun) { "Passo 2 - Execucao real (dry-run, nada gravado)" } else { "Passo 2 - Execucao real (com escrita)" }
    $execucao = Invoke-EtapaDeno -Rotulo $rotuloExecucao -DenoArgs $denoArgs
    $resultados["execucao"] = $execucao

    if ($execucao.Output -match 'FX_REFRESH ativa') {
        Write-Host "`nConflito de execucao ativa detectado pelo proprio conector - outra execucao FX_REFRESH ja estava RECEIVED/PROCESSING, e a chamada ao BCB foi corretamente evitada (indice unico parcial, Query 3907)." -ForegroundColor Yellow
    }

    $resumo = Get-ResultadoExecucaoJson $execucao.Output
    if ($execucao.ExitCode -ne 0) {
        Write-Host "`nExecucao terminou com codigo de saida diferente de zero - ver saida acima para o detalhe (TECHNICAL_FAILURE/FUNCTIONAL_FAILURE, --confirmed-by ausente/invalido, ou conflito de execucao ativa)." -ForegroundColor Red
        $script:exitCode = 1
    } elseif ($resumo) {
        Write-Host "`n--- Resultado estruturado ---" -ForegroundColor Cyan
        Write-Host ("Periodo consultado: {0} a {1}" -f $resumo.PeriodoInicio, $resumo.PeriodoFim)
        Write-Host ("Cotacoes recebidas do BCB: {0}" -f $resumo.CotacoesRecebidas)
        Write-Host ("inserted={0} unchanged={1} divergent={2} invalid={3}" -f $resumo.Counts.inserted, $resumo.Counts.unchanged, $resumo.Counts.divergent, $resumo.Counts.invalid)
        if ($resumo.Counts.inserted -eq 0 -and $resumo.Counts.divergent -eq 0 -and $resumo.Counts.invalid -eq 0) {
            Write-Host "Nota: zero linha nova inserida nesta execucao - normal em uma reexecucao idempotente (tudo ja existia identico) ou se a janela cair majoritariamente em fim de semana/feriado. Isso NAO e um erro." -ForegroundColor DarkGray
        }
        if ($resumo.Counts.divergent -gt 0) {
            Write-Host "Nota: divergencia(s) detectada(s) - a taxa ja existente foi PRESERVADA, nunca sobrescrita. Ver detalhes na saida bruta acima. pricing_sync_run.status correspondente e COMPLETED_WITH_ERRORS, nao FAILED." -ForegroundColor Yellow
        }
        $resultados["resultado-estruturado"] = $resumo
    } else {
        Write-Host "`nNao foi possivel extrair o resultado estruturado da saida (formato inesperado) - revise a saida bruta acima manualmente." -ForegroundColor Yellow
    }

    # --- Leitura somente-leitura de conferencia, so para execucao real com escrita
    # (dry-run nao grava nada para conferir; fixture-check ja terminou o fluxo antes
    # daqui) ---
    if (-not $DryRun -and $execucao.ExitCode -eq 0) {
        $dataInicialConferencia = if ($resumo) { $resumo.PeriodoInicio } else { $janelaEsperada.Inicio }
        $dataFinalConferencia = if ($resumo) { $resumo.PeriodoFim } else { $janelaEsperada.Fim }
        Write-Host "`nLendo pricing_fx_rate (somente leitura) para conferencia da janela realmente usada..." -ForegroundColor DarkGray
        $rows = Get-PtaxRatesNaJanela -SupabaseUrl $env:SUPABASE_URL -ServiceRoleKey $env:SUPABASE_SERVICE_ROLE_KEY -DataInicial $dataInicialConferencia -DataFinal $dataFinalConferencia
        Show-JanelaPtax -Rows $rows -Rotulo "apos a execucao" -DataInicial $dataInicialConferencia -DataFinal $dataFinalConferencia
        $resultados["conferencia-pos-execucao"] = [PSCustomObject]@{ DataInicial = $dataInicialConferencia; DataFinal = $dataFinalConferencia; Linhas = $rows }
    }
}
finally {
    Clear-CredenciaisDoAmbiente

    # --- Resumo sanitizado, gravado FORA do repositorio Git, so em $env:TEMP ---
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $summaryFile = Join-Path $OutputDir ("ptax-run-summary-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

    $lines = @()
    $lines += "# Resumo sanitizado - execucao local do conector PTAX (scripts/sync-ptax-fx-rate.ts)"
    $lines += ""
    $lines += "Gerado em: $timestamp"
    $lines += ""
    $lines += "Este arquivo fica fora do repositorio Git ($OutputDir) e contem apenas texto ja redigido - nenhuma chave, JWT ou segredo foi gravado aqui."
    $lines += ""
    foreach ($chave in $resultados.Keys) {
        $item = $resultados[$chave]
        $lines += "## $chave"
        $lines += ""
        if ($item.PSObject.Properties.Name -contains "ExitCode") {
            $lines += "- Codigo de saida: $($item.ExitCode)"
            $lines += ""
            $lines += '```'
            $lines += $item.Output
            $lines += '```'
        } else {
            $lines += '```json'
            $lines += ($item | ConvertTo-Json -Depth 6)
            $lines += '```'
        }
        $lines += ""
    }
    $lines += "---"
    $lines += ""
    $lines += "Nenhum commit/push realizado por este runner. Nenhuma migration, documentacao, dado do conector JustTCG, ou logica de scripts/sync-ptax-fx-rate.ts foi alterada nesta execucao - so leituras/escritas em pricing_fx_rate/pricing_sync_run/pricing_sync_run_call feitas pelo proprio conector, mais leituras somente-leitura deste runner para conferencia."

    $lines -join "`r`n" | Set-Content -Path $summaryFile -Encoding UTF8
    Write-Host "`nResumo sanitizado gravado em: $summaryFile" -ForegroundColor Cyan
}

exit $script:exitCode
