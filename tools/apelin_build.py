"""Only apelin_project_build invokes this rollback package producer."""
from pathlib import Path
from package_ci import package

VERSION = '0.2.1-rollback1'
ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    package(ROOT, ROOT / '.build/ci-artifacts/keyboard-glass-original-64e.zip', VERSION)
