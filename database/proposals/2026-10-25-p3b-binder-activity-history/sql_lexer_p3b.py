#!/usr/bin/env python3
"""Lexer mínimo de SQL do PostgreSQL para as verificações estáticas da P3-B.

NÃO é um parser: não valida gramática nem semântica. Só reconhece a estrutura
léxica necessária para separar statements de nível superior com segurança:
comentários de linha (--) e de bloco (/* */, aninhados), strings ('…' com ''),
strings de escape (E'…' com \\), identificadores entre aspas ("…") e strings
com delimitador dólar ($tag$…$tag$). Erros léxicos (string, comentário ou
dólar sem fechamento) levantam LexError.

API:
  split_statements(sql) -> list[Statement]   # statements de nível superior
  Statement.text  -> texto exato do statement (sem o ';' final, sem espaços nas pontas)
  Statement.code  -> texto com comentários removidos e strings/dólares substituídos por marcadores
  Statement.words -> palavras-chave/identificadores em minúsculas, fora de strings e comentários
  dollar_bodies(sql) -> list[(tag, corpo)] de nível superior
"""
import re

_DOLLAR = re.compile(r"\$([A-Za-z_][A-Za-z_0-9]*)?\$")


class LexError(Exception):
    pass


class Statement:
    def __init__(self, text, code):
        self.text = text
        self.code = code
        self.words = [w.lower() for w in re.findall(r"[A-Za-z_][A-Za-z_0-9]*", code)]

    def head(self, n=3):
        return " ".join(self.words[:n])


def _scan(sql):
    """Gera (tipo, texto) com tipo em: code, comment, string, dollar, ident, semi."""
    i, n = 0, len(sql)
    buf = []
    while i < n:
        c = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ""
        if c == "-" and nxt == "-":
            j = sql.find("\n", i)
            j = n if j < 0 else j
            if buf:
                yield "code", "".join(buf); buf = []
            yield "comment", sql[i:j]
            i = j
        elif c == "/" and nxt == "*":
            depth, j = 1, i + 2
            while j < n and depth:
                if sql.startswith("/*", j):
                    depth += 1; j += 2
                elif sql.startswith("*/", j):
                    depth -= 1; j += 2
                else:
                    j += 1
            if depth:
                raise LexError(f"comentário de bloco sem fechamento na posição {i}")
            if buf:
                yield "code", "".join(buf); buf = []
            yield "comment", sql[i:j]
            i = j
        elif c in "eE" and nxt == "'" and not (buf and re.match(r"[A-Za-z_0-9]", buf[-1])):
            j = i + 2
            while j < n:
                if sql[j] == "\\":
                    j += 2
                elif sql[j] == "'" and j + 1 < n and sql[j + 1] == "'":
                    j += 2
                elif sql[j] == "'":
                    break
                else:
                    j += 1
            if j >= n:
                raise LexError(f"string E'' sem fechamento na posição {i}")
            if buf:
                yield "code", "".join(buf); buf = []
            yield "string", sql[i:j + 1]
            i = j + 1
        elif c == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'" and j + 1 < n and sql[j + 1] == "'":
                    j += 2
                elif sql[j] == "'":
                    break
                else:
                    j += 1
            if j >= n:
                raise LexError(f"string sem fechamento na posição {i}")
            if buf:
                yield "code", "".join(buf); buf = []
            yield "string", sql[i:j + 1]
            i = j + 1
        elif c == '"':
            j = sql.find('"', i + 1)
            while j >= 0 and j + 1 < n and sql[j + 1] == '"':
                j = sql.find('"', j + 2)
            if j < 0:
                raise LexError(f"identificador entre aspas sem fechamento na posição {i}")
            if buf:
                yield "code", "".join(buf); buf = []
            yield "ident", sql[i:j + 1]
            i = j + 1
        elif c == "$" and not (buf and re.match(r"[A-Za-z_0-9]", buf[-1])):
            m = _DOLLAR.match(sql, i)
            if not m:
                buf.append(c); i += 1
                continue
            tag = m.group(0)
            j = sql.find(tag, m.end())
            if j < 0:
                raise LexError(f"delimitador {tag} sem fechamento na posição {i}")
            if buf:
                yield "code", "".join(buf); buf = []
            yield "dollar", sql[i:j + len(tag)]
            i = j + len(tag)
        elif c == ";":
            if buf:
                yield "code", "".join(buf); buf = []
            yield "semi", ";"
            i += 1
        else:
            buf.append(c); i += 1
    if buf:
        yield "code", "".join(buf)


def split_statements(sql):
    out, raw, code = [], [], []
    for kind, txt in _scan(sql):
        if kind == "semi":
            t = "".join(raw).strip()
            if t:
                out.append(Statement(_strip_leading_comments(t), "".join(code)))
            elif "".join(code).strip():
                raise LexError("statement vazio com código")
            raw, code = [], []
            continue
        raw.append(txt)
        if kind == "code":
            code.append(txt)
        elif kind in ("string", "dollar", "ident"):
            code.append(" __LIT__ ")
    rest_code = "".join(code).strip()
    if rest_code:
        raise LexError("texto após o último ';' não termina em ';': " + rest_code[:60])
    return out


def _strip_leading_comments(t):
    while True:
        t = t.lstrip()
        if t.startswith("--"):
            j = t.find("\n")
            t = "" if j < 0 else t[j + 1:]
        elif t.startswith("/*"):
            depth, j = 1, 2
            while j < len(t) and depth:
                if t.startswith("/*", j):
                    depth += 1; j += 2
                elif t.startswith("*/", j):
                    depth -= 1; j += 2
                else:
                    j += 1
            t = t[j:]
        else:
            return t


def dollar_body(stmt_text):
    """Corpo do primeiro literal dólar do statement (ex.: DO $x$ … $x$)."""
    for kind, txt in _scan(stmt_text):
        if kind == "dollar":
            tag = _DOLLAR.match(txt).group(0)
            return txt[len(tag):-len(tag)]
    return None
