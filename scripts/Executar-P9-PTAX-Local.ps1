<#
Project Mimikyu - Local runner for Incremento P9 (PTAX FX Rate Ingestion)
File: scripts/Executar-P9-PTAX-Local.ps1

Objective: orchestrate locally, on Fabricio's machine, the execution of
scripts/sync-ptax-fx-rate.ts - the only place authorized to run the real pilot,
since the agent sandbox has no Deno runtime available and no network route to
olinda.bcb.gov.br (proxy blocked by allowlist).

This is an OPERATIONAL script, same precedent as scripts/Executar-P8-JustTCG-Local.ps1
- it is not normative documentation under docs/, and must not be read as part of the
Pricing domain model. It does not change the database, migrations, documentation, or
the logic of scripts/sync-ptax-fx-rate.ts - it only calls the existing script, with
the correct credentials and the minimum Deno permissions, then produces a sanitized
summary of the execution. The connector's own hardcoded pilot window
(PILOT_DATA_INICIAL="08-10-2026", PILOT_DATA_FINAL="08-17-2026") is left untouched by
this runner - this script does not pass date arguments to the connector (it accepts
none), it only documents the expected window below so its own validation messages can
name dates without guessing.

Unlike the P8 runner, no admin UUID (--confirmed-by) is collected or passed - the
pricing_fx_rate table has no such column and the connector accepts no such flag.

Expected pilot window, informational only (mirrors the constants hardcoded inside
sync-ptax-fx-rate.ts as of this writing - if those constants ever change, this runner
must be updated together, there is no way to derive this automatically without
touching the connector, which is out of scope here):
  PILOT_DATA_INICIAL = 08-10-2026 (Monday)
  PILOT_DATA_FINAL   = 08-17-2026 (Monday, following week)
  Expected business dates returned by BCB inside this window (6): 2026-08-10,
  2026-08-11, 2026-08-12, 2026-08-13, 2026-08-14, 2026-08-17.
  Expected absent dates (weekend, no PTAX published): 2026-08-15 (Saturday),
  2026-08-16 (Sunday).

Deno permissions granted, always the minimum list for each step (never a bare
`--allow-env` or `--allow-net`):
  - --fixture-check: `--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY` - main() in
    the connector reads both variables unconditionally (Deno.env.get) to decide
    whether to run the real pilot or fall back to --fixture-check, even when
    --fixture-check is explicitly requested - so this permission is required even
    though no credential value is read yet (nothing is set in the environment at this
    point). No `--allow-net` is granted here - runFixtureCheck() makes no network call.
  - Real pilot: `--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY` (the only two
    variables requireEnv() reads inside runRealPilot()) and
    `--allow-net=olinda.bcb.gov.br,<supabase-host>` - olinda.bcb.gov.br is the fixed
    host of BCB_PTAX_API_BASE in sync-ptax-fx-rate.ts (the BCB Olinda PTAX API is
    public, no API key exists or is requested); <supabase-host> is extracted and
    validated (HTTPS required) from the real SUPABASE_URL value only after the
    operator types it in - never a hardcoded domain, never a bare --allow-net.

Flow, in the required order:
  1. Resolve the repository root robustly (falls back to searching upward for
     CLAUDE.md + scripts\sync-ptax-fx-rate.ts if $PSScriptRoot/$MyInvocation are
     unavailable or point somewhere unexpected).
  2. Validate the presence of Deno on PATH.
  3. Run --fixture-check (offline, no network, no write) BEFORE asking for any real
     credential - if it fails, abort without ever requesting a secret.
  4. Only then request SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY safely
     (Read-Host -AsSecureString, never echoed on screen, never written to a file).
  5. Ask for explicit confirmation before writing for real to production Supabase.
  6. Read pricing_fx_rate for the pilot window BEFORE running anything (baseline) -
     read-only, never deletes/recreates existing rows. Used to compute exactly how
     many of the six expected business dates are still missing, so the first real
     run's "written" count can be checked against a real expectation instead of a
     hardcoded "6" (pre-existing correct data from an earlier attempt is accepted,
     not overwritten or duplicated).
  7. Run the real pilot a first time against the fixed window - expects `written` to
     equal exactly the number of dates that were missing from the baseline.
  8. Run the real pilot a SECOND time, same window - same idempotency (real
     ON CONFLICT DO NOTHING at the database level, via upsert + ignoreDuplicates in
     the connector, corrected 2026-08-17) - expects `written = 0` unconditionally
     (everything should already exist after run 1).
  9. After baseline, run 1, and run 2, read back pricing_fx_rate for the pilot window
     (read-only REST call to PostgREST, no INSERT/UPDATE/DELETE) to prove, with real
     data, that the six expected business dates are present with a rate each, that
     2026-08-15/2026-08-16 are absent, that there is no duplicate row per date, and
     that the row count does not grow between run 1 and run 2.
  10. Remove the two sensitive environment variables from the current process at the
      end, always (try/finally - even if something fails in the middle).
  11. Write only a sanitized summary (.md) to a folder OUTSIDE the Git repository
      ($env:TEMP by default) - never inside project-mimikyu, eliminating any risk of
      accidentally committing test residue.

Key format compatibility (2026-08-17, third round): the newer generation of Supabase
API keys (sb_secret_.../sb_publishable_...) is not a JWT and must be sent ONLY in the
"apikey" header for the read-only PostgREST validation call this runner makes -
sending it in "Authorization: Bearer" as well can be rejected by the gateway. Legacy
JWT-format keys (starting with "eyJ", three dot-separated segments) keep receiving both
headers, exactly as before - Get-CabecalhosSupabase() detects the format automatically,
no operator action required.

Usage:
  # Full flow (fixture-check + real pilot x2), asks for everything interactively:
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1

  # Offline validation only, never asks for a real credential (useful to revalidate
  # the logic after any update to sync-ptax-fx-rate.ts itself):
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1 -FixtureOnly

  # Repository root known in advance, skips the upward search:
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P9-PTAX-Local.ps1 -RepoRoot "C:\path\to\project-mimikyu"

Never paste SUPABASE_SERVICE_ROLE_KEY into chat, a log, or an issue - only into the
secure prompts opened by this script.
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
    # default, per requirement ("gravar resumo sanitizado somente em $env:TEMP").
    [string]$OutputDir = (Join-Path $env:TEMP "project-mimikyu-p9-local-runs"),

    # Stops at the fixture-check - never requests a real credential, never touches
    # the network, never comes close to the Supabase project.
    [switch]$FixtureOnly
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
# 1. Janela fixa do piloto - informativa, refletindo as constantes hardcoded no
#    proprio conector (sync-ptax-fx-rate.ts) - nunca passada como argumento, o
#    conector nao aceita parametro de data. Ver cabecalho deste arquivo.
# ============================================================================

$PilotDataInicial = "2026-08-10"
$PilotDataFinal   = "2026-08-17"
$ExpectedBusinessDates = @("2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14", "2026-08-17")
$ExpectedWeekendDates  = @("2026-08-15", "2026-08-16")
$ExpectedFromCurrency  = "USD"
$ExpectedToCurrency    = "BRL"
$ExpectedRateSourceCode = "BCB_PTAX"

$BcbApiHost = "olinda.bcb.gov.br"   # mesmo host de BCB_PTAX_API_BASE em sync-ptax-fx-rate.ts

# ============================================================================
# 2. Sanitizacao defensiva - mesmo espirito de Executar-P8-JustTCG-Local.ps1
#    (protege qualquer coisa impressa/gravada por este runner, mesmo nao havendo
#    credencial de terceiro como a JUSTTCG_API_KEY neste incremento).
# ============================================================================

function Protect-SensitiveText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = $Text
    $t = $t -replace 'eyJ[A-Za-z0-9_\-\.]{20,}', '[REDACTED_SUPABASE_JWT]'
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
# 4. Captura segura de credenciais - SecureString na entrada, nunca ecoadas, nunca
#    gravadas em arquivo. Limitacao honesta: uma vez convertida para string gerenciada
#    (necessario para virar variavel de ambiente do processo filho), o .NET nao
#    garante zeragem deterministica da memoria - limite conhecido da plataforma, nao
#    deste script. O SecureString original e descartado (.Dispose()) assim que a
#    conversao termina.
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
# nem uma faixa aberta). Exige HTTPS explicitamente (o proprio conector Deno tambem
# exige - a Service Role Key nunca deve trafegar em HTTP). Nunca imprime a
# SUPABASE_URL completa - so o hostname, que nao e sensivel.
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

# Corrigido (2026-08-17, terceira rodada): a partir da nova geracao de chaves do
# Supabase (formato sb_secret_.../sb_publishable_..., que substitui o par
# anon/service_role em JWT), a chave deixa de ser um JWT valido - deve ir SOMENTE no
# header "apikey". Enviar "Authorization: Bearer <chave>" junto com uma chave nesse
# novo formato pode ser rejeitado pelo gateway (nao e um Bearer token valido - RFC 6750
# pressupoe um JWT ou token opaco reconhecido como tal, nao esse formato prefixado).
# JWT legado (comeca com "eyJ", tres segmentos separados por ponto - formato historico
# de anon/service_role) continua enviado nos dois headers, exatamente como antes -
# preserva compatibilidade retroativa sem exigir nenhuma acao do operador.
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
    # Formato nao reconhecido (nem sb_secret_/sb_publishable_, nem JWT de tres
    # segmentos) - trata como legado por seguranca (mesmo comportamento de sempre),
    # mas avisa, ja que pode ser um erro de digitacao na chave colada.
    Write-Host "Aviso: SUPABASE_SERVICE_ROLE_KEY nao bate com o formato novo (sb_secret_/sb_publishable_) nem com o formato JWT legado (eyJ...) - enviando como legado (apikey + Authorization: Bearer); confira se a chave foi colada corretamente." -ForegroundColor DarkYellow
    return @{
        "apikey"        = $ServiceRoleKey
        "Authorization" = "Bearer $ServiceRoleKey"
    }
}

# ============================================================================
# 5. Execucao de uma etapa Deno - captura tudo, redige, so entao exibe/retorna
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

function Get-ResumoPilotoJson {
    param([string]$Texto)
    $match = [regex]::Match($Texto, '=== Resumo do piloto ===\s*(\{[\s\S]*?\n\})')
    if ($match.Success) {
        try { return $match.Groups[1].Value | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

# ============================================================================
# 6. Leitura somente-leitura de pricing_fx_rate via PostgREST - nao insere, nao
#    altera, nao apaga nada; usada so para comprovar, com dado real, quais
#    rate_date foram gravados na janela do piloto (as duas execucoes deste runner
#    ja usam a mesma janela fixa do proprio conector - ver secao 1, acima).
# ============================================================================

function Get-PtaxRatesNaJanela {
    param(
        [Parameter(Mandatory)][string]$SupabaseUrl,
        [Parameter(Mandatory)][string]$ServiceRoleKey
    )
    $baseUrl = $SupabaseUrl.TrimEnd("/")
    $query = "from_currency=eq.$ExpectedFromCurrency" +
             "&to_currency=eq.$ExpectedToCurrency" +
             "&rate_source_code=eq.$ExpectedRateSourceCode" +
             "&rate_date=gte.$PilotDataInicial" +
             "&rate_date=lte.$PilotDataFinal" +
             "&select=rate_date,rate" +
             "&order=rate_date.asc"
    $uri = "$baseUrl/rest/v1/pricing_fx_rate?$query"
    $headers = Get-CabecalhosSupabase -ServiceRoleKey $ServiceRoleKey
    try {
        $rows = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        if ($null -eq $rows) { return @() }
        return @($rows)
    } catch {
        $msg = Protect-SensitiveText $_.Exception.Message
        Write-Host "Falha ao ler pricing_fx_rate para validacao (leitura, nao afeta o piloto em si): $msg" -ForegroundColor Yellow
        return $null
    }
}

# Compara as linhas lidas do Supabase contra a janela esperada (secao 1, acima) -
# devolve um objeto com o resultado, nunca lanca excecao (falha de validacao aqui
# nunca deve derrubar o restante do fluxo do runner). Corrigido (2026-08-17, terceira
# rodada): agora tambem carrega as taxas (nao so as datas, para poder "confirmar
# fisicamente as 6 datas/taxas") e detecta duplicidade de forma explicita e nomeada -
# antes essa checagem era so um efeito colateral implicito de comparar TotalLinhas com
# 6 dentro de $pass, sem um sinal dedicado e claramente rotulado no relatorio.
function Test-JanelaPtax {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Rows,
        [Parameter(Mandatory)][string]$RotuloExecucao
    )
    if ($null -eq $Rows) {
        return [PSCustomObject]@{
            Rotulo                    = $RotuloExecucao
            LeituraOk                 = $false
            Pass                      = $false
            DatasEncontradas          = @()
            DatasFaltando             = $ExpectedBusinessDates
            DatasInesperadas          = @()
            DatasFimDeSemanaPresentes = @()
            DuplicidadeDetectada      = $false
            TotalLinhas               = 0
            Linhas                    = @()
        }
    }

    $datasEncontradas = @($Rows | ForEach-Object { [string]$_.rate_date } | Sort-Object -Unique)
    $datasFaltando = @($ExpectedBusinessDates | Where-Object { $datasEncontradas -notcontains $_ })
    $datasInesperadas = @($datasEncontradas | Where-Object { $ExpectedBusinessDates -notcontains $_ })
    $datasFimDeSemanaPresentes = @($ExpectedWeekendDates | Where-Object { $datasEncontradas -contains $_ })

    # Duplicidade real = mais de uma linha fisica para a mesma rate_date (nunca deveria
    # acontecer, dada a UNIQUE ja CONFIRMADO EXECUTADO na Query 3060 - checagem
    # explicita mesmo assim, por pedido: "confirme... zero duplicidade").
    $duplicidadeDetectada = ($Rows.Count -ne $datasEncontradas.Count)

    $pass = (
        $datasFaltando.Count -eq 0 -and
        $datasInesperadas.Count -eq 0 -and
        $datasFimDeSemanaPresentes.Count -eq 0 -and
        -not $duplicidadeDetectada -and
        $Rows.Count -eq $ExpectedBusinessDates.Count
    )

    $linhas = @($Rows | Sort-Object { [string]$_.rate_date } | ForEach-Object {
        [PSCustomObject]@{ RateDate = [string]$_.rate_date; Rate = $_.rate }
    })

    return [PSCustomObject]@{
        Rotulo                    = $RotuloExecucao
        LeituraOk                 = $true
        Pass                      = $pass
        DatasEncontradas          = $datasEncontradas
        DatasFaltando             = $datasFaltando
        DatasInesperadas          = $datasInesperadas
        DatasFimDeSemanaPresentes = $datasFimDeSemanaPresentes
        DuplicidadeDetectada      = $duplicidadeDetectada
        TotalLinhas               = $Rows.Count
        Linhas                    = $linhas
    }
}

# ============================================================================
# 7. Fluxo principal
# ============================================================================

Test-DenoPresente

if (-not (Test-Path $TsScriptPath)) {
    Write-Host "Nao encontrei $TsScriptPath - use -RepoRoot para apontar a raiz correta do repositorio project-mimikyu (a busca automatica por CLAUDE.md + scripts\sync-ptax-fx-rate.ts tambem nao encontrou nada)." -ForegroundColor Red
    exit 1
}
Write-Host "Repositorio: $RepoRoot" -ForegroundColor DarkGray
Write-Host "Conector: $TsScriptPath" -ForegroundColor DarkGray
Write-Host "Janela fixa do piloto (hardcoded no conector, informativa aqui): $PilotDataInicial a $PilotDataFinal" -ForegroundColor DarkGray
Write-Host "Datas uteis esperadas (6): $($ExpectedBusinessDates -join ', ')" -ForegroundColor DarkGray
Write-Host "Fim de semana esperado ausente (2): $($ExpectedWeekendDates -join ', ')" -ForegroundColor DarkGray

$resultados = [ordered]@{}
$script:exitCode = 0

# A partir daqui, credenciais reais podem entrar em $env: - try/finally garante que
# Clear-CredenciaisDoAmbiente roda sempre, mesmo em erro. Todo desvio de fluxo dentro
# deste bloco usa `return` (nunca `exit`), porque `exit` pode pular o `finally` em
# alguns hosts do PowerShell - `return` nao.
try {
    # --- Passo 1: fixture-check, sempre primeiro, sem nenhuma credencial real ---
    # Permissao minima: --allow-env com as duas variaveis que main() sempre le (mesmo
    # em modo --fixture-check, ver cabecalho deste arquivo) - nenhum valor real existe
    # ainda no ambiente, e nenhum --allow-net e concedido (runFixtureCheck() nao faz
    # rede).
    $fixture = Invoke-EtapaDeno -Rotulo "Passo 1/3 - Validacao offline (--fixture-check)" `
        -DenoArgs @("run", "--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY", $TsScriptPath, "--fixture-check")
    $resultados["fixture-check"] = $fixture

    if ($fixture.ExitCode -ne 0) {
        Write-Host "`nFixture-check FALHOU - abortando antes de solicitar qualquer credencial real." -ForegroundColor Red
        Write-Host "Corrija scripts/sync-ptax-fx-rate.ts (ou reporte a divergencia) antes de tentar o piloto real." -ForegroundColor Yellow
        $script:exitCode = 1
        return
    }

    Write-Host "`nFixture-check aprovado." -ForegroundColor Green

    if ($FixtureOnly) {
        Write-Host "`n-FixtureOnly ativo - encerrando aqui, piloto real nao solicitado nem executado." -ForegroundColor Yellow
        return
    }

    # --- Coleta segura de credenciais, so agora que sabemos que vale a pena pedir ---
    Write-Host "`n=== Credenciais para o piloto real (nunca exibidas na tela) ===" -ForegroundColor Cyan
    Write-Host "Nao ha API key do Banco Central - a API Olinda PTAX e publica e nao exige credencial. So o Supabase pede as duas abaixo." -ForegroundColor DarkGray
    $env:SUPABASE_URL              = Read-SegredoComoTexto -Prompt "SUPABASE_URL"
    $env:SUPABASE_SERVICE_ROLE_KEY = Read-SegredoComoTexto -Prompt "SUPABASE_SERVICE_ROLE_KEY"

    # Extrai so o hostname de SUPABASE_URL (valida HTTPS) para restringir --allow-net
    # ao minimo - nunca imprime a URL completa, so o host resultante (nao sensivel).
    $supabaseHost = Get-SupabaseHostValidado -SupabaseUrl $env:SUPABASE_URL
    Write-Host "Host Supabase validado para --allow-net: $supabaseHost" -ForegroundColor DarkGray
    $allowNetPiloto = "--allow-net=$BcbApiHost,$supabaseHost"

    # Confirmacao explicita antes de qualquer escrita real em producao.
    Write-Host "`nEste passo grava de verdade em pricing_fx_rate no Supabase de PRODUCAO (append-only, ON CONFLICT DO NOTHING - nunca sobrescreve, apaga nem recria uma linha existente)." -ForegroundColor Yellow
    $confirma = Read-Host "Confirma a execucao real? (s/N)"
    if ($confirma -notin @("s", "S", "sim", "Sim", "SIM")) {
        Write-Host "Execucao real cancelada pelo usuario - nada gravado." -ForegroundColor Yellow
        return
    }

    # --- Leitura da janela ANTES do piloto (baseline) ---
    # Nunca apaga nem recria nada - so leitura. Usada para (a) aceitar dados
    # preexistentes corretos em vez de presumir que a tabela comeca vazia, e (b)
    # calcular quantas linhas a execucao 1 DEVE escrever de novo (so as que faltam) -
    # a prova de "execucao 1 escreve so o que falta" fica sem sentido sem saber o que
    # ja existia antes de rodar.
    Write-Host "`nLendo pricing_fx_rate (somente leitura) ANTES do piloto, para estabelecer a base..." -ForegroundColor DarkGray
    $rowsBaseline = Get-PtaxRatesNaJanela -SupabaseUrl $env:SUPABASE_URL -ServiceRoleKey $env:SUPABASE_SERVICE_ROLE_KEY
    $janelaBaseline = Test-JanelaPtax -Rows $rowsBaseline -RotuloExecucao "antes do piloto (baseline)"
    $resultados["janela-antes-do-piloto"] = $janelaBaseline

    $datasFaltandoAntes = $ExpectedBusinessDates
    if ($janelaBaseline.LeituraOk) {
        $datasFaltandoAntes = @($ExpectedBusinessDates | Where-Object { $janelaBaseline.DatasEncontradas -notcontains $_ })
        $jaPresentes = $ExpectedBusinessDates.Count - $datasFaltandoAntes.Count
        Write-Host ("Baseline: {0} de {1} data(s) util(eis) ja presente(s) - faltam {2}: {3}" -f
            $jaPresentes, $ExpectedBusinessDates.Count, $datasFaltandoAntes.Count,
            $(if ($datasFaltandoAntes.Count -gt 0) { $datasFaltandoAntes -join ", " } else { "nenhuma" })) -ForegroundColor DarkGray
        if ($janelaBaseline.DuplicidadeDetectada) {
            Write-Host "AVISO: duplicidade ja presente na base ANTES desta execucao (nao introduzida por este runner) - este runner nunca apaga nem recria linhas, entao ela nao sera corrigida automaticamente; investigue manualmente se necessario." -ForegroundColor Yellow
        }
        if ($janelaBaseline.DatasFimDeSemanaPresentes.Count -gt 0) {
            Write-Host ("AVISO: linha(s) de fim de semana ja presente(s) na base ANTES desta execucao: {0} - nao introduzida por este runner, nao sera removida automaticamente." -f ($janelaBaseline.DatasFimDeSemanaPresentes -join ", ")) -ForegroundColor Yellow
        }
    } else {
        Write-Host "Nao foi possivel ler a baseline - a expectativa de 'written' na execucao 1 assume tabela vazia (pode nao bater se ja houver dado preexistente); revise manualmente se divergir." -ForegroundColor Yellow
    }
    $expectedWrittenRun1 = $datasFaltandoAntes.Count

    # --- Passo 2: piloto real, primeira execucao ---
    # Permissao minima: rede restrita aos dois hosts realmente usados (BCB Olinda +
    # o projeto Supabase real) e --allow-env com as duas variaveis exigidas por
    # requireEnv() dentro de runRealPilot().
    $pilotoArgs = @(
        "run",
        $allowNetPiloto,
        "--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY",
        $TsScriptPath
    )
    $run1 = Invoke-EtapaDeno -Rotulo "Passo 2/3 - Piloto real, execucao 1 (janela $PilotDataInicial a $PilotDataFinal)" -DenoArgs $pilotoArgs
    $resultados["piloto-run-1"] = $run1
    $summary1 = Get-ResumoPilotoJson $run1.Output

    # Prova de "execucao 1 escreve so o que falta": written precisa bater exatamente
    # com o numero de datas uteis que NAO estavam na baseline lida acima - nunca um
    # numero fixo hardcoded (a baseline pode ja ter 0, algumas, ou as 6 datas corretas
    # de uma rodada anterior; este runner nunca apaga/recria nada, entao a expectativa
    # tem que refletir o estado real observado antes de rodar).
    $run1EscreveuOEsperado = $false
    if ($summary1 -and $janelaBaseline.LeituraOk) {
        $run1EscreveuOEsperado = ($summary1.written -eq $expectedWrittenRun1)
        if ($run1EscreveuOEsperado) {
            Write-Host ("Execucao 1 escreveu exatamente as {0} linha(s) que faltavam (dados preexistentes, se houver, preservados como estavam - nao sobrescritos/recriados)." -f $expectedWrittenRun1) -ForegroundColor Green
        } else {
            Write-Host ("Execucao 1 escreveu {0} linha(s) novas, mas a leitura da baseline esperava {1} - revise manualmente (pode indicar duplicidade, falha parcial, ou mudanca de estado entre a leitura da baseline e a execucao)." -f $summary1.written, $expectedWrittenRun1) -ForegroundColor Yellow
            $script:exitCode = 1
        }
    } elseif ($summary1) {
        Write-Host "Baseline nao pode ser lida - pulando a comparacao exata de 'written' da execucao 1 (ver aviso acima)." -ForegroundColor Yellow
    }

    Write-Host "`nLendo pricing_fx_rate (somente leitura) para comprovar a janela apos a execucao 1..." -ForegroundColor DarkGray
    $rows1 = Get-PtaxRatesNaJanela -SupabaseUrl $env:SUPABASE_URL -ServiceRoleKey $env:SUPABASE_SERVICE_ROLE_KEY
    $janela1 = Test-JanelaPtax -Rows $rows1 -RotuloExecucao "apos execucao 1"
    $resultados["janela-apos-run-1"] = $janela1

    if ($run1.ExitCode -ne 0) {
        Write-Host "`nExecucao 1 do piloto real terminou com erro - pulando a segunda execucao de idempotencia." -ForegroundColor Red
        $script:exitCode = 1
    } else {
        # --- Passo 3: piloto real, segunda execucao (comprova idempotencia) ---
        Write-Host "`nAguardando 2s antes da segunda execucao (pausa de cortesia, nao exigida pelo conector - a API PTAX e publica e sem limite documentado)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
        $run2 = Invoke-EtapaDeno -Rotulo "Passo 3/3 - Piloto real, execucao 2 (prova de idempotencia, mesma janela $PilotDataInicial a $PilotDataFinal)" -DenoArgs $pilotoArgs
        $resultados["piloto-run-2"] = $run2
        $summary2 = Get-ResumoPilotoJson $run2.Output

        Write-Host "`nLendo pricing_fx_rate (somente leitura) para comprovar a janela apos a execucao 2..." -ForegroundColor DarkGray
        $rows2 = Get-PtaxRatesNaJanela -SupabaseUrl $env:SUPABASE_URL -ServiceRoleKey $env:SUPABASE_SERVICE_ROLE_KEY
        $janela2 = Test-JanelaPtax -Rows $rows2 -RotuloExecucao "apos execucao 2"
        $resultados["janela-apos-run-2"] = $janela2

        $semErros1 = ($run1.Output -notmatch "(?m)^Erros:")
        $semErros2 = ($run2.Output -notmatch "(?m)^Erros:")

        # Prova de idempotencia - distingue explicitamente "resolved" (todo item
        # processado, novo ou ja existente) de "written" (so inserts genuinamente
        # novos), mesma disciplina de telemetria de escrita do Incremento P8. A
        # segunda execucao precisa: terminar com codigo de saida 0, sem "Erros:",
        # resolver os mesmos 6 itens da primeira (mesmas cotacoes recebidas do BCB) e
        # gravar ZERO linhas novas (written=0) - nunca basta comparar contadores
        # cegamente, o requisito central e written=0 na segunda execucao.
        $idempotente = $false
        $mesmaContagemResolvida = $false
        if ($summary1 -and $summary2) {
            $mesmaContagemResolvida = ($summary1.resolved -eq $summary2.resolved)
            $idempotente = (
                $run1.ExitCode -eq 0 -and $run2.ExitCode -eq 0 -and
                $semErros1 -and $semErros2 -and
                $summary1.failed -eq 0 -and $summary2.failed -eq 0 -and
                $mesmaContagemResolvida -and
                $summary2.written -eq 0
            )
        }

        $janelaEstavel = (
            $janela1.LeituraOk -and $janela2.LeituraOk -and
            $janela1.TotalLinhas -eq $janela2.TotalLinhas -and
            $janela1.Pass -and $janela2.Pass
        )

        $resultados["idempotencia"] = [PSCustomObject]@{
            Confirmada            = $idempotente
            JanelaConfirmada      = $janelaEstavel
            Resumo1               = $summary1
            Resumo2               = $summary2
        }

        if (-not ($summary1 -and $summary2)) {
            Write-Host "`nNao foi possivel extrair o resumo JSON de uma das duas execucoes - compare a saida bruta acima manualmente." -ForegroundColor Yellow
            $script:exitCode = 1
        } else {
            Write-Host "`n--- Distincao resolvidas vs gravadas ---" -ForegroundColor Cyan
            Write-Host ("Execucao 1: resolved={0} written={1} failed={2} cotacoesRecebidas={3}" -f $summary1.resolved, $summary1.written, $summary1.failed, $summary1.cotacoesRecebidas)
            Write-Host ("Execucao 2: resolved={0} written={1} failed={2} cotacoesRecebidas={3}" -f $summary2.resolved, $summary2.written, $summary2.failed, $summary2.cotacoesRecebidas)

            if ($idempotente) {
                Write-Host "`nIdempotencia CONFIRMADA - as duas execucoes terminaram sem erro, resolveram a mesma quantidade de cotacoes, e a execucao 2 gravou ZERO linhas novas (written=0 - ON CONFLICT DO NOTHING confirmado por contagem real)." -ForegroundColor Green
            } else {
                Write-Host "`nIdempotencia NAO confirmada automaticamente - compare os dois resumos acima manualmente antes de considerar o piloto validado." -ForegroundColor Yellow
                $script:exitCode = 1
            }

            Write-Host "`n--- Janela PTAX (leitura direta de pricing_fx_rate) ---" -ForegroundColor Cyan
            foreach ($j in @($janelaBaseline, $janela1, $janela2)) {
                if (-not $j.LeituraOk) {
                    Write-Host ("{0}: leitura falhou - ver aviso acima." -f $j.Rotulo) -ForegroundColor Yellow
                    continue
                }
                Write-Host ("{0}: {1} linha(s)" -f $j.Rotulo, $j.TotalLinhas)
                foreach ($linha in $j.Linhas) {
                    Write-Host ("    {0} = {1}" -f $linha.RateDate, $linha.Rate) -ForegroundColor DarkGray
                }
                if ($j.DatasFaltando.Count -gt 0) {
                    Write-Host ("  Faltando dia(s) util(eis) esperado(s): {0}" -f ($j.DatasFaltando -join ", ")) -ForegroundColor Yellow
                }
                if ($j.DatasInesperadas.Count -gt 0) {
                    Write-Host ("  Data(s) fora da lista esperada de dias uteis: {0}" -f ($j.DatasInesperadas -join ", ")) -ForegroundColor Yellow
                }
                if ($j.DatasFimDeSemanaPresentes.Count -gt 0) {
                    Write-Host ("  ERRO: linha(s) de fim de semana encontrada(s): {0}" -f ($j.DatasFimDeSemanaPresentes -join ", ")) -ForegroundColor Red
                } else {
                    Write-Host "  Confirmado: nenhuma linha para 2026-08-15 (sabado) ou 2026-08-16 (domingo)." -ForegroundColor Green
                }
                if ($j.DuplicidadeDetectada) {
                    Write-Host "  ERRO: duplicidade detectada (mais de uma linha fisica para a mesma rate_date)." -ForegroundColor Red
                } else {
                    Write-Host "  Confirmado: zero duplicidade (uma linha por rate_date)." -ForegroundColor Green
                }
            }

            # Confirmacao final fisica das 6 datas/taxas, exigida pelo pedido - le a
            # janela2 (estado apos a segunda execucao, o mais recente e definitivo)
            # linha a linha, nunca so um agregado.
            if ($janela2.LeituraOk -and $janela2.Pass) {
                Write-Host "`n--- Confirmacao final: 6 datas/taxas (estado apos a execucao 2) ---" -ForegroundColor Cyan
                foreach ($linha in $janela2.Linhas) {
                    Write-Host ("  {0} -> venda {1}" -f $linha.RateDate, $linha.Rate) -ForegroundColor Green
                }
            }

            if ($janelaEstavel) {
                Write-Host "`nJanela PTAX CONFIRMADA - 6 datas uteis (2026-08-10 a 08-14 e 08-17) com taxa gravada cada, nenhuma linha de fim de semana, zero duplicidade, mesma contagem de linhas antes e depois da segunda execucao (nenhum crescimento na reexecucao)." -ForegroundColor Green
            } else {
                Write-Host "`nJanela PTAX NAO confirmada automaticamente - revise os detalhes acima." -ForegroundColor Yellow
                $script:exitCode = 1
            }

            if (-not $run1EscreveuOEsperado -and $janelaBaseline.LeituraOk) {
                Write-Host "`nNota: a execucao 1 nao escreveu exatamente o numero esperado de linhas novas (ver aviso acima) - revise antes de considerar o piloto totalmente validado, mesmo que a janela final esteja correta." -ForegroundColor Yellow
            }
        }
    }
}
finally {
    Clear-CredenciaisDoAmbiente

    # --- Resumo sanitizado, gravado FORA do repositorio Git, so em $env:TEMP ---
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $summaryFile = Join-Path $OutputDir ("p9-run-summary-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

    $lines = @()
    $lines += "# Resumo sanitizado - execucao local do Incremento P9 (PTAX)"
    $lines += ""
    $lines += "Gerado em: $timestamp"
    $lines += ""
    $lines += "Este arquivo fica fora do repositorio Git ($OutputDir) e contem apenas texto ja redigido - nenhuma chave, JWT ou segredo foi gravado aqui."
    $lines += ""
    $lines += "Janela fixa do piloto (hardcoded no conector): $PilotDataInicial a $PilotDataFinal"
    $lines += "Datas uteis esperadas: $($ExpectedBusinessDates -join ', ')"
    $lines += "Fim de semana esperado ausente: $($ExpectedWeekendDates -join ', ')"
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
    $lines += "Nenhum commit/push realizado por este runner. Nenhuma migration, documentacao, dado do conector JustTCG, ou logica de scripts/sync-ptax-fx-rate.ts foi alterada nesta execucao - so leituras/escritas em pricing_fx_rate feitas pelo proprio conector, mais leituras somente-leitura deste runner para validacao."

    $lines -join "`r`n" | Set-Content -Path $summaryFile -Encoding UTF8
    Write-Host "`nResumo sanitizado gravado em: $summaryFile" -ForegroundColor Cyan
}

exit $script:exitCode
