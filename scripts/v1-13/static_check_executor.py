#!/usr/bin/env python3
"""
V1-13 — verificação ESTÁTICA do executor por arquivo (Invoke-ReviewedSql.ps1, STD-005 §3).
Sem PowerShell: prova só propriedades do TEXTO. Não substitui o -Simular no Windows.

    python3 -I -B scripts/v1-13/static_check_executor.py
"""
import os
import re
import sys

PS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Invoke-ReviewedSql.ps1")
raw = open(PS, "rb").read()
t = raw.decode("utf-8-sig")
code = re.sub(r"<#.*?#>", "", t, flags=re.S)
code = "\n".join(l for l in code.splitlines() if not l.strip().startswith("#"))
R = []


def check(cid, ok, d):
    R.append((cid, bool(ok), d))


i_sim = code.index("if ($Simular) {")
first_db = code.index("'db', 'query'")
check("E1", i_sim < first_db and "exit 0 }" in code[i_sim:i_sim + 200] and code.count("'db', 'query'") == 1,
      "-Simular sai antes da única chamada `db query` (nenhuma conexão ao banco)")
i_hash = code.index("SHA-256 divergente")
check("E2", i_hash < i_sim and "Sha $abs" in code and "if ((Sha $p.caminho) -ne $p.sha256)" in code,
      "SHA-256 de cada arquivo conferido antes de conectar e de novo imediatamente antes de cada passo")
check("E3", "ShaManifestoEsperado -ne $ShaManifesto" in code and code.index("ShaManifestoEsperado -ne $ShaManifesto") < first_db,
      "fora da simulação exige o sha256 auditado do manifesto")
check("E4", "linked-project.json aponta para outro projeto" in code and "versão da CLI inesperada" in code
      and "\"executor = $($p.Value) (esperado $Papel)\"" in code,
      "destino (ref), versão da CLI e papel executor (via gate) conferidos")
check("E5", "toda escrita precisa de um gate (PRE) antes" in code and "if (-not $g.ok) {" in code and "break" in code[code.index("if (-not $g.ok) {"):code.index("if (-not $g.ok) {") + 120],
      "gate reprovado interrompe antes da escrita; manifesto sem PRE antes da escrita é recusado")
check("E6", re.search(r"\b(while|do)\s*[{(]", code) is None and code.count("foreach ($p in $passos)") == 1
      and "SUPABASE_API_MAX_RETRIES = '0'" in code and "Start-Sleep" not in code,
      "sem laço de repetição; CLI sem retentativas")
check("E7", "--debug" not in code and "SUPABASE_DB_PASSWORD" in code and "password" not in code.lower().replace("supabase_db_password", "").replace("pgpassword", ""),
      "sem --debug; recusa variáveis de senha; nenhuma credencial no script")
check("E8", "Read-Host" in code and "-cne $esperado" in code and "trava existente" in code,
      "confirmação digitada exata e trava por manifesto (nova tentativa = nova autorização)")
check("E9", re.search(r"barrier|v1_13_barrier|TEST", code) is None or "barreira = $($p.Value)" in code,
      "não altera a barreira nem ativa TEST (só lê o resultado do gate)")

# Codificação (lição do -Simular de 2026-11-27): o Windows PowerShell 5.1 lê arquivo sem BOM como
# Windows-1252; "—" (E2 80 94) vira "â€”", e 0x94 = ” é aspa para o PowerShell → string cortada.
check("E10", raw.startswith(b"\xef\xbb\xbf"), "arquivo em UTF-8 COM BOM (lido como UTF-8 pelo PowerShell 5.1)")
check("E11", not any(c in t for c in "\u201c\u201d\u2018\u2019"),
      "nenhuma aspa tipográfica no texto (o PowerShell as trata como delimitadores mesmo em UTF-8)")
cp = raw[3:].decode("cp1252", errors="replace") if raw.startswith(b"\xef\xbb\xbf") else raw.decode("cp1252", errors="replace")
check("E12", raw.startswith(b"\xef\xbb\xbf") or not any(c in cp for c in "\u201c\u201d\u2018\u2019"),
      "sem BOM, a leitura Windows-1252 não criaria aspas espúrias (redundante com E10)")

# Prova negativa (Test-InvokeReviewedSql.ps1, roda no Windows): cobertura dos cenários exigidos.
TP = os.path.join(os.path.dirname(PS), "Test-InvokeReviewedSql.ps1")
traw = open(TP, "rb").read()
tt = traw.decode("utf-8-sig")
need = ["controle", "pre_booleano_falso", "pre_json_invalido", "pre_sem_criterio", "barreira_open", "identidades_teste",
        "executor_errado", "hash_divergente", "migration_falha", "post_md5_divergente", "gate_com_escrita",
        "escritor_adicional", "escritor_ausente", "inventario_vazio", "campo_ausente", "sobrecarga", "sem_expectativas", "expectativa_hash"]
check("E13", traw.startswith(b"\xef\xbb\xbf") and all(c < 128 for c in traw[3:]) and all(f"nome = '{n}'" in tt for n in need)
      and "qjfutqujxrbzgrtkpgkg" not in tt and "$REF = 'aaaaaaaaaaaaaaaaaaaa'" in tt
      and "$env:PATH = \"$bin;$oldPath\"" in tt and "INCONCLUSIVO" in tt and "-notmatch \"--remote=$REF\"" in tt,
      "prova negativa: 18 cenários (controle + 17), projeto fictício, CLI falsa à frente no PATH, alvo conferido, controle obrigatório")
check("E14", "try { $rows = @((ConvertFrom-Json" in code and "gate sem critério booleano" in code
      and "} catch {\n  $registro.resultado = \"STOP: exceção no executor" in code,
      "resposta inválida e gate sem critério viram STOP registrado; exceção no laço vira STOP com run.json")

# Causa do controle INCONCLUSIVO (Windows, 2026-11-27): Start-Process -PassThru + WaitForExit(timeout)
# sem obter o handle → ExitCode $null; $null -ne 0 era verdadeiro (critério negativo vazio).
check("E15", "$null = $proc.Handle" in tt and tt.index("$null = $proc.Handle") < tt.index("$proc.WaitForExit(180000)")
      and "$code = $proc.ExitCode" in tt and "$r.exit -ne" not in tt
      and tt.count("($r.exit -eq 2)") == 3 and "($r.exit -eq 0)" in tt and "($r.exit -eq 1)" in tt
      and "if ($null -eq $r.exit) {" in tt and "$inconclusivo++" in tt and "if ($inconclusivo) {" in tt,
      "harness: handle obtido antes da espera; códigos exatos (0 controle, 2 STOP, 1 hash); código nulo → INCONCLUSIVO, nunca PASS")
check("E16", "LastWriteTimeUtc -ge $s.inicio" in tt and "$runs.Count -eq 1" in tt and "($res -like 'PASS*')" in tt
      and tt.count("($res -like 'STOP*')") == 3 and "$runs.Count -eq 0" in tt and "$emOrdem" in tt,
      "harness: lê só o run.json desta execução (diretório novo, gravado após o início); exige PASS/STOP no run.json e ordem das chamadas")

# Causa do STOP no LIVE (2026-11-27): --read-only troca o papel da sessão para supabase_read_only_user;
# o PRE precisa rodar no papel da escrita. v1.3: gate sem --read-only + conteúdo SELECT único conferido.
i_ro = code.index("function Test-ReadOnlySql")
check("E17", "if ($p.modo -eq 'read') { $cliArgs += '--read-only' } else { $cliArgs += '--yes' }" in code
      and code.count("$cliArgs += '--read-only'") == 1 and code.count("$cliArgs += '--yes'") == 1
      and "if ($c[3] -ne 'write' -and -not (Test-ReadOnlySql $abs))" in code
      and code.index("Test-ReadOnlySql $abs") < code.index("'--version'") < first_db
      and all(w in code[i_ro:i_ro + 1500] for w in ("insert|update|delete", "set_config|nextval", "'^(?i)select\\b'", "-ne 1", "-match '\\$'")),
      "gate e write com --yes no papel da escrita; --read-only só no modo read; gate/read = SELECT único sem escrita, conferido antes de qualquer conexão")
check("E18", "$papel" in tt and "--read-only" in tt and "-and $papel" in tt and "'STOP_RO'" in tt,
      "harness: PRE/POST sem --read-only e migration com --yes exigidos em todo cenário; gate com escrita → STOP antes de conectar")

# Causa do INCONCLUSIVO da v1.3 (Windows, 2026-11-27): sob Set-StrictMode, ".Count" sobre o resultado
# escalar de um pipeline (um único item) lança PropertyNotFoundStrict. Todo ".Count" precisa estar sobre
# @(...), [regex]::Matches(...), Split(...) ou variável inicializada como coleção.
def _count_ok(src):
    bad = []
    for m in re.finditer(r"\.Count\b", src):
        i = m.start() - 1
        if src[i] == ")":
            depth, j = 0, i
            while j >= 0:
                depth += (src[j] == ")") - (src[j] == "(")
                if depth == 0:
                    break
                j -= 1
            pre = src[max(0, j - 20):j]
            if not (pre.endswith("@") or pre.endswith("Matches") or pre.endswith("Split")):
                bad.append(src[max(0, j - 20):m.end()])
        else:
            v = re.search(r"\$([A-Za-z_]\w*)$", src[:m.start()])
            if not v or not re.search(r"\$" + v.group(1) + r"\s*(=\s*@\(|=\s*\$[\w.]+\.Split\(|=\s*@\(\))", src):
                bad.append(src[max(0, m.start() - 25):m.end()])
    return bad
_bad = _count_ok(code)
check("E19", not _bad and "[regex]::Matches($s, ';').Count -ne 1" in code,
      "StrictMode: todo .Count do executor sobre coleção garantida (sem .Count de pipeline escalar)" + (f" — suspeitos: {_bad}" if _bad else ""))
_pm = re.search(r"\$prematuro = \$r\.out -match '([^']*)'", tt)
check("E20", "'SHA-256 divergente: pkg\\\\MIG\\.sql'" in tt and "'somente leitura: pkg\\\\PRE\\.sql'" in tt
      and _pm is not None and "PropertyNotFound" in _pm.group(1) and "RuntimeException" not in _pm.group(1)
      and "-and -not $prematuro" in tt and "diagnostico" in tt,
      "harness: STOP antecipado exige a mensagem exata do ponto testado; defeito de código (PropertyNotFound…) reprova, throw esperado não; FAIL mostra diagnóstico")

# Causa do STOP de 12:38Z: gate sem --yes nem --read-only → a CLI 3.2.0 (-o json) recusa ("Confirmation
# required … Nothing was changed"). A CLI falsa do harness passa a impor a mesma regra.
check("E21", "$depois = @($args | Select-Object -Skip ($q + 1))" in tt and "Confirmation required" in tt
      and "-not ($depois -contains '--yes') -and -not ($depois -contains '--read-only')" in tt
      and "'(PRE|POST|MIG)\\.sql' -and $_ -notmatch ' --yes$'" in tt,
      "harness: CLI falsa recusa db query sem --yes/--read-only (regra da CLI real); PRE/POST/MIG exigidos com --yes")

# v1.4 (decisão A): inventário de escritores é gate obrigatório, comparado com expectativas auditadas.
ig = code[code.index("function Test-Gate"):code.index("if ($PSVersionTable.PSVersion.Major")]
check("E22", "-match '^escritores_[a-z_]+$' -and $p.Name -notlike '*_md5'" in ig
      and "inventário sem expectativa auditada" in ig and "inventário ausente ou inválido" in ig
      and "diferente do esperado" in ig and "$a -cne $b" in ig and "Sort-Object -CaseSensitive" in ig
      and "inventário ausente: $($k.Name)" in ig and "if ($exigirInventario -and $null -ne $expect) {" in ig
      and "foreach ($k in @($expect.PSObject.Properties)) { if ($vistos -notcontains $k.Name)" in ig
      and "$g = Test-Gate $out $gateAnterior $Expect $primeiroGate" in code
      and "if ($ShaExpectativas -ne $ShaExpect)" in code and code.index("$ShaExpectativas -ne $ShaExpect") < first_db
      and "expectativas: nome repetido" in code and "expectativas vazias" in code,
      "inventário: chave sem expectativa, valor ausente/vazio, nome a mais/a menos/repetido → STOP; 1º gate exige todas as chaves esperadas; expectativas com sha256 auditado, validadas antes de conectar")
check("E23", tt.count("motivo = '") == 6 and "($r.out -match $c.motivo)" in tt and "'STOP_EXP'" in tt
      and "semExp = $true" in tt and "expShaErrada = $true" in tt and "-ShaExpectativas" in tt,
      "harness: 7 cenários de inventário exigem o motivo exato; sem expectativas → STOP; sha das expectativas errado → STOP antes de conectar")

fails = [r for r in R if not r[1]]
for cid, ok, d in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:3} {d}")
print(f"\nSTATIC CHECK EXECUTOR: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
