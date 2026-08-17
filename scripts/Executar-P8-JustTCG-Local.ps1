<#
Project Mimikyu - Runner local do Incremento P8 (Conector JustTCG e Piloto Controlado)
Arquivo: scripts/Executar-P8-JustTCG-Local.ps1

Objetivo: orquestrar localmente, na maquina de Fabricio, a execucao de
scripts/sync-justtcg-pricing.ts - o unico lugar autorizado a rodar o piloto real,
ja que o sandbox do agente nao tem o runtime Deno disponivel (deno.land/npm:deno
fora da allowlist de rede do sandbox).

Este e um script OPERACIONAL, mesmo padrao de Executar-ProvaJustTCG-Fase-A-B.ps1 (a
prova tecnica original) - nao e documentacao normativa de docs/, nao deve ser lido
como parte do modelo do dominio Pricing. Nao altera banco, migrations, documentacao
nem a logica de scripts/sync-justtcg-pricing.ts - so chama o script ja existente,
com as credenciais certas e nas permissoes Deno minimas, e produz um resumo
sanitizado da execucao.

Permissoes Deno concedidas, sempre a lista minima possivel para cada etapa (nunca
`--allow-env`/`--allow-net` genericos):
  - --fixture-check: `--allow-env=JUSTTCG_API_KEY` - e a unica variavel que o
    proprio conector le antes de decidir o modo (`Deno.env.get("JUSTTCG_API_KEY")`
    em main()); a validacao offline em si (runFixtureCheck()) nao toca nenhuma
    variavel de ambiente nem faz rede, entao nenhum `--allow-net` e concedido aqui.
  - Piloto real: `--allow-env=JUSTTCG_API_KEY,SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY`
    (as tres, e so as tres, exigidas por requireEnv() dentro de runRealPilot()) e
    `--allow-net=api.justtcg.com,<host>` - `api.justtcg.com` e o host fixo de
    JUSTTCG_API_BASE em sync-justtcg-pricing.ts; `<host>` e extraido e validado do
    valor real de SUPABASE_URL (precisa ser HTTPS) so depois de o operador digita-lo
    - nunca um dominio hardcoded, nunca `--allow-net` sem lista.

Fluxo, na ordem exigida:
  1. Valida a presenca do Deno no PATH.
  2. Coleta e valida o formato do UUID de admin_user (--confirmed-by) - nao e
     segredo, so identificador, por isso e pedido cedo (falha rapido em caso de
     erro de digitacao, sem nunca ter chegado perto de uma credencial real).
  3. Roda --fixture-check (offline, sem rede, sem escrita) ANTES de pedir qualquer
     credencial real - se falhar, aborta sem nunca ter solicitado segredo nenhum.
  4. So entao solicita JUSTTCG_API_KEY / SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
     de forma segura (Read-Host -AsSecureString, nunca ecoadas na tela nem gravadas
     em arquivo).
  5. Pede confirmacao explicita antes de escrever de verdade no Supabase de producao.
  6. Roda o piloto real uma primeira vez.
  7. Roda o piloto real uma SEGUNDA vez, com os mesmos parametros - mesma
     idempotencia (ON CONFLICT DO NOTHING) que o conector ja implementa - e compara
     os dois resumos JSON impressos pelo script para comprovar que a reexecucao nao
     altera nada, nao duplica nada e nao gera erro novo.
  8. Remove as tres variaveis de ambiente sensiveis do processo atual ao final,
     sempre (try/finally - mesmo se algo falhar no meio).
  9. Grava so um resumo sanitizado (.md) em uma pasta FORA do repositorio Git
     ($env:TEMP por padrao) - nunca dentro de project-mimikyu, para eliminar
     qualquer risco de commit acidental de residuo de teste.

Uso:
  # Fluxo completo (fixture-check + piloto real x2), solicita tudo interativamente:
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P8-JustTCG-Local.ps1

  # So valida offline, sem nunca pedir credencial real (util para revalidar a logica
  # depois de qualquer atualizacao do proprio script sync-justtcg-pricing.ts):
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P8-JustTCG-Local.ps1 -FixtureOnly

  # UUID do admin ja conhecido, evita a pergunta interativa correspondente:
  powershell -ExecutionPolicy Bypass -File .\scripts\Executar-P8-JustTCG-Local.ps1 -ConfirmedBy "00000000-0000-0000-0000-000000000000"

Nunca cole a JUSTTCG_API_KEY nem a SUPABASE_SERVICE_ROLE_KEY em chat, log ou issue -
so nos prompts seguros abertos por este script.
#>

[CmdletBinding()]
param(
    # Caminho do repositorio - por padrao, a pasta pai de scripts/ (onde este arquivo mora).
    # $PSScriptRoot fica vazio em alguns invocations do Windows PowerShell 5.1 com
    # "-File" e caminho relativo (bug conhecido da plataforma) - por isso ha fallback
    # para $MyInvocation.MyCommand.Path e, por ultimo, para o diretorio atual (assume
    # que o script foi chamado a partir da raiz do repositorio, como nos exemplos de uso).
    [string]$RepoRoot = $(
        if ($PSScriptRoot) {
            (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        } elseif ($MyInvocation.MyCommand.Path) {
            (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")).Path
        } else {
            (Get-Location).Path
        }
    ),

    # UUID de admin_user que vai "confirmar" os mappings resolvidos pelo piloto.
    # Se omitido, solicitado interativamente (nao e segredo - so identificador).
    [string]$ConfirmedBy,

    # Pasta onde o resumo sanitizado (.md) e gravado - fora do repositorio por padrao.
    [string]$OutputDir = (Join-Path $env:TEMP "project-mimikyu-p8-local-runs"),

    # Para no fixture-check, nunca solicita credencial real nem chega perto do Supabase.
    [switch]$FixtureOnly
)

$ErrorActionPreference = "Stop"

# O conector Deno imprime UTF-8 (acentos do pt-BR) no stdout. O console do Windows
# PowerShell 5.1 normalmente decodifica saida de processo externo usando a code page
# ANSI/OEM do sistema, nao UTF-8 - sem isso, texto acentuado vindo do Deno aparece
# ilegivel (mojibake) mesmo com o codigo de saida correto (0) e nada realmente errado
# na execucao. So afeta leitura na tela; nao altera nenhum dado gravado no Supabase
# nem o resumo sanitizado. Best-effort: se o host nao suportar a troca (ex.: saida
# redirecionada), segue sem travar o script.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    Write-Host "Aviso: nao foi possivel forcar UTF-8 no console - saida do Deno com acentos pode aparecer ilegivel, sem impacto funcional." -ForegroundColor DarkYellow
}

$TsScriptPath = Join-Path $RepoRoot "scripts\sync-justtcg-pricing.ts"

# Host fixo da API da JustTCG - mesmo valor de JUSTTCG_API_BASE em
# scripts/sync-justtcg-pricing.ts (https://api.justtcg.com/v1). Se o conector algum
# dia mudar de host, este runner precisa ser atualizado junto (nao ha como derivar
# isso automaticamente sem tocar a logica do conector, o que esta fora de escopo
# deste ajuste).
$JustTcgApiHost = "api.justtcg.com"

# ============================================================================
# 0. Sanitizacao defensiva - mesmo conjunto de padroes do proprio conector
#    (scripts/sync-justtcg-pricing.ts, funcao sanitize()), com um padrao a mais
#    (JWT do Supabase, formato "eyJ...") porque este runner tambem manipula a
#    Service Role Key, que o conector TS nunca precisa sanitizar sozinho (ele so
#    le a variavel de ambiente, nunca a imprime). Defesa em profundidade: mesmo
#    que algo inesperado vaze no stdout do processo Deno, este runner redige de
#    novo antes de exibir ou gravar qualquer coisa.
# ============================================================================

function Protect-SensitiveText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = $Text
    $t = $t -replace 'tcg_[A-Za-z0-9]+', '[REDACTED_JUSTTCG_KEY]'
    $t = $t -replace 'eyJ[A-Za-z0-9_\-\.]{20,}', '[REDACTED_SUPABASE_JWT]'
    $t = $t -replace '(?i)x-api-key\s*:\s*\S+', 'x-api-key: [REDACTED]'
    $t = $t -replace '(?i)authorization\s*:\s*\S+', 'authorization: [REDACTED]'
    $t = $t -replace '(?i)bearer\s+\S+', 'Bearer [REDACTED]'
    return $t
}

# ============================================================================
# 1. Deno - validacao de presenca antes de qualquer outra coisa
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
# 2. Captura segura de credenciais - SecureString na entrada, nunca ecoadas,
#    nunca gravadas em arquivo. Limitacao honesta: uma vez convertidas para
#    string gerenciada (necessario para virar variavel de ambiente do processo
#    filho), o .NET nao garante zeragem deterministica da memoria - este e um
#    limite conhecido da plataforma, nao deste script. O SecureString original
#    e descartado (.Dispose()) assim que a conversao termina.
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

# Extrai e valida o host do SUPABASE_URL informado - usado para restringir
# --allow-net ao minimo necessario (host real do projeto, nao um dominio generico
# *.supabase.co, e nao uma faixa aberta). Exige HTTPS explicitamente (o script Deno
# tambem exige - service_role key nunca deve trafegar em HTTP). Nunca imprime o
# SUPABASE_URL completo (pode conter credencial embutida em variacoes de config,
# ainda que o padrao oficial nao tenha) - so o hostname, que nao e sensivel.
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
    Remove-Item Env:\JUSTTCG_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\SUPABASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
}

# ============================================================================
# 3. Execucao de uma etapa Deno - captura tudo, redige, so entao exibe/retorna
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
# 4. Fluxo principal
# ============================================================================

Test-DenoPresente

if (-not (Test-Path $TsScriptPath)) {
    Write-Host "Nao encontrei $TsScriptPath - confirme -RepoRoot." -ForegroundColor Red
    exit 1
}

# UUID do admin, coletado e validado ANTES de qualquer segredo - nao e sensivel
# (so um identificador), e falhar aqui evita pedir credencial real a toa.
if (-not $FixtureOnly -and -not $ConfirmedBy) {
    $ConfirmedBy = Read-Host -Prompt "UUID do admin_user que confirma os mappings (--confirmed-by, usado so se o fixture-check passar)"
}
if (-not $FixtureOnly -and $ConfirmedBy -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    Write-Host "ConfirmedBy '$ConfirmedBy' nao parece um UUID valido - abortando antes de pedir qualquer credencial." -ForegroundColor Red
    exit 1
}

$resultados = [ordered]@{}
$script:exitCode = 0

# A partir daqui, credenciais reais podem entrar em $env: - try/finally garante que
# Clear-CredenciaisDoAmbiente roda sempre, mesmo em erro. Todo desvio de fluxo dentro
# deste bloco usa `return` (nunca `exit`), porque `exit` pode pular o `finally` em
# alguns hosts do PowerShell - `return` nao.
try {
    # --- Passo 1: fixture-check, sempre primeiro, sem nenhuma credencial real ---
    # Permissao minima: so JUSTTCG_API_KEY (unica variavel que main() le antes de
    # decidir o modo) e nenhum --allow-net (runFixtureCheck() nao faz rede).
    $fixture = Invoke-EtapaDeno -Rotulo "Passo 1/3 - Validacao offline (--fixture-check)" `
        -DenoArgs @("run", "--allow-env=JUSTTCG_API_KEY", $TsScriptPath, "--fixture-check")
    $resultados["fixture-check"] = $fixture

    if ($fixture.ExitCode -ne 0) {
        Write-Host "`nFixture-check FALHOU - abortando antes de solicitar qualquer credencial real." -ForegroundColor Red
        Write-Host "Corrija scripts/sync-justtcg-pricing.ts (ou reporte a divergencia) antes de tentar o piloto real." -ForegroundColor Yellow
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
    $env:JUSTTCG_API_KEY          = Read-SegredoComoTexto -Prompt "JUSTTCG_API_KEY"
    $env:SUPABASE_URL             = Read-SegredoComoTexto -Prompt "SUPABASE_URL"
    $env:SUPABASE_SERVICE_ROLE_KEY = Read-SegredoComoTexto -Prompt "SUPABASE_SERVICE_ROLE_KEY"

    # Extrai so o hostname de SUPABASE_URL (valida HTTPS) para restringir --allow-net
    # ao minimo - nunca imprime a URL completa, so o host resultante (nao sensivel).
    $supabaseHost = Get-SupabaseHostValidado -SupabaseUrl $env:SUPABASE_URL
    Write-Host "Host Supabase validado para --allow-net: $supabaseHost" -ForegroundColor DarkGray
    $allowNetPiloto = "--allow-net=$JustTcgApiHost,$supabaseHost"

    # Confirmacao explicita antes de qualquer escrita real em producao.
    Write-Host "`nEste passo grava de verdade em pricing_set_mapping/pricing_card_mapping/pricing_product/pricing_observation/pricing_sync_run/pricing_sync_run_call no Supabase de PRODUCAO." -ForegroundColor Yellow
    $confirma = Read-Host "Confirma a execucao real? (s/N)"
    if ($confirma -notin @("s", "S", "sim", "Sim", "SIM")) {
        Write-Host "Execucao real cancelada pelo usuario - nada gravado." -ForegroundColor Yellow
        return
    }

    # --- Passo 2: piloto real, primeira execucao ---
    # Permissao minima: so as tres variaveis exigidas por requireEnv() e rede
    # restrita aos dois hosts realmente usados (JustTCG + o projeto Supabase real).
    $pilotoArgs = @(
        "run",
        $allowNetPiloto,
        "--allow-env=JUSTTCG_API_KEY,SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY",
        $TsScriptPath,
        "--confirmed-by=$ConfirmedBy"
    )
    $run1 = Invoke-EtapaDeno -Rotulo "Passo 2/3 - Piloto real, execucao 1" -DenoArgs $pilotoArgs
    $resultados["piloto-run-1"] = $run1

    if ($run1.ExitCode -ne 0) {
        Write-Host "`nExecucao 1 do piloto real terminou com erro - pulando a segunda execucao de idempotencia." -ForegroundColor Red
        $script:exitCode = 1
    } else {
        # --- Passo 3: piloto real, segunda execucao (comprova idempotencia) ---
        Write-Host "`nAguardando 3s antes da segunda execucao (mesma janela de cortesia do conector entre requisicoes)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 3
        $run2 = Invoke-EtapaDeno -Rotulo "Passo 3/3 - Piloto real, execucao 2 (prova de idempotencia)" -DenoArgs $pilotoArgs
        $resultados["piloto-run-2"] = $run2

        $summary1 = Get-ResumoPilotoJson $run1.Output
        $summary2 = Get-ResumoPilotoJson $run2.Output

        $semErros1 = ($run1.Output -notmatch "(?m)^Erros:")
        $semErros2 = ($run2.Output -notmatch "(?m)^Erros:")

        $idempotente = $false
        if ($summary1 -and $summary2) {
            $idempotente = (
                $summary1.status -eq "COMPLETED" -and $summary2.status -eq "COMPLETED" -and
                $summary1.setsResolved -eq $summary2.setsResolved -and
                $summary1.cardsResolved -eq $summary2.cardsResolved -and
                $summary1.productsWritten -eq $summary2.productsWritten -and
                $summary1.observationsWritten -eq $summary2.observationsWritten -and
                $semErros1 -and $semErros2
            )
        }

        $resultados["idempotencia"] = [PSCustomObject]@{
            Confirmada = $idempotente
            Resumo1    = $summary1
            Resumo2    = $summary2
        }

        if ($idempotente) {
            Write-Host "`nIdempotencia CONFIRMADA - execucao 2 reproduziu exatamente os mesmos contadores da execucao 1, status COMPLETED em ambas, nenhum erro em nenhuma das duas (ON CONFLICT DO NOTHING funcionando como esperado)." -ForegroundColor Green
        } else {
            Write-Host "`nIdempotencia NAO confirmada automaticamente - compare os dois resumos abaixo manualmente antes de considerar o piloto validado." -ForegroundColor Yellow
        }
    }
}
finally {
    Clear-CredenciaisDoAmbiente

    # --- Resumo sanitizado, gravado FORA do repositorio Git ---
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $summaryFile = Join-Path $OutputDir ("p8-run-summary-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

    $lines = @()
    $lines += "# Resumo sanitizado - execucao local do Incremento P8 (JustTCG)"
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
    $lines += "Nenhum commit/push realizado por este runner. Nenhuma migration, documentacao ou logica do conector foi alterada nesta execucao."

    $lines -join "`r`n" | Set-Content -Path $summaryFile -Encoding UTF8
    Write-Host "`nResumo sanitizado gravado em: $summaryFile" -ForegroundColor Cyan
}

exit $script:exitCode
