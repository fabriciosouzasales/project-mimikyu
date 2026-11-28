"""V1-13 · Etapa 7 — gera os manifestos do executor v1.4 (abertura e fechamento) com os sha256 dos arquivos.

Executar a partir desta pasta: python build_g5.py
"""
import hashlib
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
REL = r"database\proposals\2026-11-27-v1-13-g5-barrier-open"

MANIFESTS = {
    "G5_OPEN_MANIFEST.txt": [
        ("G5_OPEN_PRE_readonly.sql", "gate"),
        ("G5_BARRIER_OPEN.sql", "write"),
        ("G5_OPEN_POST_readonly.sql", "gate"),
    ],
    "G5_CLOSE_MANIFEST.txt": [
        ("G5_CLOSE_PRE_readonly.sql", "gate"),
        ("G5_BARRIER_CLOSE.sql", "write"),
        ("G5_CLOSE_POST_readonly.sql", "gate"),
    ],
}


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render(steps) -> str:
    lines = ["# V1-13 · etapa 7 — manifesto do executor por arquivo (STD-005 §3, v1.4). passo|arquivo|sha256|modo"]
    for i, (name, mode) in enumerate(steps, start=1):
        lines.append(f"{i}|{REL}\\{name}|{sha(HERE / name)}|{mode}")
    return "\n".join(lines) + "\n"


def main() -> None:
    for manifest, steps in MANIFESTS.items():
        text = render(steps)
        (HERE / manifest).write_text(text, encoding="utf-8", newline="\n")
        print(f"{manifest}: sha256={sha(HERE / manifest)}")
        for name, _ in steps:
            print(f"  {name}: {sha(HERE / name)}")


if __name__ == "__main__":
    main()
