#!/usr/bin/env python3
"""Verificação estática da sonda E2 (E2_probe_readonly.ps1 v1.1).

Não executa PowerShell nem conecta em banco. Analisa o texto do script:
  P-0  estrutura léxica (aspas, here-strings, comentários, (), {}, []) balanceada — NÃO é o parser do PowerShell
  P-1  psql por caminho explícito (padrão PostgreSQL 17), sem PATH/Get-Command
  P-2  SSL verify-full obrigatório; nenhum 'require'/'prefer'/'disable'
  P-3  ambiente herdado descartado no processo filho (PG*, PSQLRC), pgpass/cert de cliente neutralizados
  P-4  sessão do PowerShell intocada: nenhum $env: atribuído/removido; senha via prompt do psql (-W), sem PGPASSWORD
  P-5  únicas instruções ao banco: os SELECTs de $Queries (e sessão forçada a somente leitura)
  P-6  checagens de PID, usuário, banco, porta, versão, encoding, SSL, ledger e fingerprint presentes
  P-7  caminhos de erro: códigos 90/91/92/93/10 e nenhuma repetição (sem laço em torno do psql)
Inclui mutações negativas: cada uma precisa ser detectada.
Uso: python3 static_check_e2_probe.py   (código 0 = PASS)
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = (HERE / "E2_probe_readonly.ps1").read_text(encoding="utf-8")


def lex_ps(text):
    """Remove comentários e conteúdo de strings; devolve (código, lista_de_strings) ou levanta ValueError."""
    i, n, out, strings = 0, len(text), [], []
    while i < n:
        c = text[i]
        if text.startswith("<#", i):
            j = text.find("#>", i + 2)
            if j < 0:
                raise ValueError("comentário de bloco sem fechamento")
            i = j + 2
        elif c == "#":
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("@'", i) or text.startswith('@"', i):
            q = text[i + 1]
            j = text.find("\n" + q + "@", i + 2)
            if j < 0:
                raise ValueError("here-string sem fechamento")
            strings.append(text[i + 2:j])
            out.append(" ''S'' ")
            i = j + 3
        elif c == "'":
            j = i + 1
            while j < n:
                if text[j] == "'" and j + 1 < n and text[j + 1] == "'":
                    j += 2
                elif text[j] == "'":
                    break
                else:
                    j += 1
            if j >= n:
                raise ValueError(f"string simples sem fechamento na posição {i}")
            strings.append(text[i + 1:j])
            out.append(" ''S'' ")
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n:
                if text[j] == "`":
                    j += 2
                elif text[j] == '"' and j + 1 < n and text[j + 1] == '"':
                    j += 2
                elif text[j] == '"':
                    break
                else:
                    j += 1
            if j >= n:
                raise ValueError(f"string dupla sem fechamento na posição {i}")
            strings.append(text[i + 1:j])
            out.append(' "S" ')
            i = j + 1
        else:
            out.append(c)
            i += 1
    code = "".join(out)
    for o, cl in ("()", "{}", "[]"):
        depth = 0
        for ch in code:
            depth += (ch == o) - (ch == cl)
            if depth < 0:
                raise ValueError(f"'{cl}' sem abertura")
        if depth != 0:
            raise ValueError(f"'{o}{cl}' desbalanceado ({depth})")
    return code, strings


def violations(text):
    v = []
    try:
        code, strings = lex_ps(text)
    except ValueError as e:
        return [f"P-0 {e}"]
    low = text.lower()
    # P-1
    if "[string] $psqlpath = 'c:\\program files\\postgresql\\17\\bin\\psql.exe'" not in low:
        v.append("P-1 caminho padrão do psql 17 ausente")
    if re.search(r"get-command\s+psql|&\s*psql\b|filepath\s+'psql'|=\s*'psql'", low):
        v.append("P-1 psql resolvido pelo PATH")
    if "test-path -literalpath $psqlpath -pathtype leaf" not in low or "-ne 'psql.exe'" not in low:
        v.append("P-1 psql.exe não validado")
    # P-2
    if "['pgsslmode'] = 'verify-full'" not in low or not re.search(r"\[parameter\(mandatory = \$true\)\] \[string\] \$sslrootcert", low):
        v.append("P-2 verify-full/certificado obrigatório ausente")
    if re.search(r"'(require|prefer|allow|disable)'", low):
        v.append("P-2 modo SSL mais fraco presente")
    if "test-path -literalpath $sslrootcert -pathtype leaf" not in low:
        v.append("P-2 certificado não verificado antes da conexão")
    # P-3
    if "psi.environmentvariables.remove($name)" not in low or "^(?i)(pg.*|psqlrc" not in low:
        v.append("P-3 ambiente herdado não descartado no processo filho")
    for k in ("pgpassfile", "pgsslcert", "pgsslkey"):
        if f"['{k}'] = $nofile" not in low:
            v.append(f"P-3 {k} não neutralizado")
    # P-4
    if re.search(r"\$env:", code, re.I):
        v.append("P-4 a sessão do PowerShell é alterada ($env:)")
    if re.search(r"remove-item\s+(env:|\"?env:)", low):
        v.append("P-4 Remove-Item em Env:")
    if "['pgpassword']" in low or "read-host" in low or "securestring" in low:
        v.append("P-4 senha manipulada pelo PowerShell (deve ser o prompt do psql)")
    if "'-w'" not in low:
        v.append("P-4 psql sem -W (prompt de senha)")
    # P-5
    qblock = re.search(r"\$Queries = @\((.*?)\n\)", text, re.S)
    queries = re.findall(r'"([^"]*)"', qblock.group(1)) if qblock else []
    if len(queries) != 3 or not all(q.lower().startswith("select ") for q in queries):
        v.append("P-5 $Queries deve ter exatamente 3 SELECTs")
    bad = r"\b(insert|update|delete|merge|create|alter|drop|truncate|grant|revoke|copy|call|do|set|reset|begin|commit|rollback|vacuum|analyze|lock|listen|notify|execute|prepare)\b"
    if any(re.search(bad, q, re.I) or ";" in q for q in queries):
        v.append("P-5 consulta com palavra de escrita/controle ou ';'")
    if "['pgoptions'] = '-c default_transaction_read_only=on'" not in low:
        v.append("P-5 sessão não forçada a somente leitura")
    if "foreach ($q in $queries) { $argparts += @('-c', $q) }" not in low:
        v.append("P-5 argumentos -c não vêm só de $Queries")
    if re.search(r"'-f'|'--file|'-c',\s*[\"'](?!\$)|\\\\i", text):   # '-F' (separador) é permitido; '-f' (arquivo) não
        v.append("P-5 arquivo/comando extra passado ao psql")
    # P-6
    for key in ("mesmo_pid", "usuario_postgres", "banco_postgres", "porta_5432", "servidor_17",
                "client_encoding_utf8", "somente_leitura", "ssl_ativo", "ledger_5266", "fingerprint_live"):
        if f"$checks['{key}']" not in low:
            v.append(f"P-6 checagem ausente: {key}")
    # P-7
    for c in ("stop-probe 90", "stop-probe 91", "stop-probe 92", "stop-probe 93", "exit 10"):
        if c not in low:
            v.append(f"P-7 caminho de erro ausente: {c}")
    if low.count("::start($psi)") != 1 or re.search(r"\b(while|do\s*\{|until)\b", code, re.I):
        v.append("P-7 o psql deve ser iniciado uma única vez, sem laço")
    return v


results = []
pv = violations(SRC)
results.append(("E2P.0", not pv, "sonda v1.1 conforme P-0..P-7" + (f" {pv}" if pv else "")))
MUT = {
    "volta ao PATH": SRC.replace("$psi.FileName = $PsqlPath", "$psi.FileName = 'psql'"),
    "fallback require": SRC.replace("$psi.EnvironmentVariables['PGSSLMODE'] = 'verify-full'", "$psi.EnvironmentVariables['PGSSLMODE'] = 'require'"),
    "certificado opcional": SRC.replace("[Parameter(Mandatory = $true)] [string] $SslRootCert,", "[string] $SslRootCert = '',"),
    "não descarta herdadas": SRC.replace("    $psi.EnvironmentVariables.Remove($name)\n", ""),
    "pgpass não neutralizado": SRC.replace("$psi.EnvironmentVariables['PGPASSFILE'] = $noFile", "# sem pgpassfile"),
    "altera sessão": SRC.replace("$psi.UseShellExecute = $false", "$psi.UseShellExecute = $false\n$env:PGHOST = $PgHost"),
    "senha pelo PowerShell": SRC.replace("$psi.EnvironmentVariables['PGCONNECT_TIMEOUT'] = '10'", "$psi.EnvironmentVariables['PGCONNECT_TIMEOUT'] = '10'\n$psi.EnvironmentVariables['PGPASSWORD'] = (Read-Host 'x')"),
    "consulta de escrita": SRC.replace("\"select 'S3', pg_backend_pid(),", "\"update public.collection set name = name where false; select 'S3', pg_backend_pid(),"),
    "sem somente leitura": SRC.replace("'-c default_transaction_read_only=on'", "''"),
    "sem checagem de pid": SRC.replace("$checks['mesmo_pid']", "$checks['outro']"),
    "repetição": SRC.replace("$proc.WaitForExit()", "while (-not $proc.HasExited) { Start-Sleep 1 }\n$proc.WaitForExit()"),
    "arquivo extra (-f)": SRC.replace("'-v', 'VERBOSITY=verbose')", "'-v', 'VERBOSITY=verbose', '-f', 'x.sql')"),
    "string sem fechamento": SRC.replace("'^select\\s'", "'^select\\s", 1),
}
for k, t in MUT.items():
    results.append(("E2P.M", bool(violations(t)), f"mutação detectada — {k}"))

w = max(len(c) for c, _, _ in results)
fails = 0
for cid, ok, d in results:
    fails += 0 if ok else 1
    print(f"{cid:<{w}}  {'PASS' if ok else 'FAIL'}  {d}")
print(f"{'GATE':<{w}}  {'PASS' if fails == 0 else 'FAIL'}  {len(results) - fails}/{len(results)} PASS")
sys.exit(0 if fails == 0 else 1)
