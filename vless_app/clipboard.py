import subprocess


def read_text() -> str:
    for cmd in (["xclip", "-selection", "clipboard", "-o"], ["xsel", "--clipboard", "--output"]):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except FileNotFoundError:
            continue
    raise RuntimeError("Не удалось прочитать буфер обмена. Установите xclip: sudo apt install xclip")
