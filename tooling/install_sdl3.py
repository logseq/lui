"""Build a checksum-pinned SDL3 runtime for development and CI."""

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

VERSION = "3.4.18"
SHA256 = "9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3"
URL = f"https://github.com/libsdl-org/SDL/releases/download/release-{VERSION}/SDL3-{VERSION}.tar.gz"


def install(prefix):
    prefix = prefix.resolve()
    with tempfile.TemporaryDirectory(prefix="sdl3-build-") as temporary:
        root = Path(temporary)
        archive = root / "SDL3.tar.gz"
        urllib.request.urlretrieve(URL, archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
            raise ValueError("SDL3 archive checksum mismatch")
        with tarfile.open(archive) as source:
            source.extractall(root, filter="data")
        build = root / "build"
        subprocess.run(["cmake", "-S", str(root / f"SDL3-{VERSION}"), "-B", str(build),
                        f"-DCMAKE_INSTALL_PREFIX={prefix}", "-DCMAKE_BUILD_TYPE=Release",
                        "-DSDL_SHARED=ON", "-DSDL_STATIC=OFF", "-DSDL_TESTS=OFF",
                        "-DSDL_TEST_LIBRARY=OFF"], check=True)
        subprocess.run(["cmake", "--build", str(build), "--config", "Release", "--parallel", "2"], check=True)
        subprocess.run(["cmake", "--install", str(build), "--config", "Release"], check=True)
    filename = "bin/SDL3.dll" if sys.platform == "win32" else (
        "lib/libSDL3.dylib" if sys.platform == "darwin" else "lib/libSDL3.so.0")
    library = prefix / filename
    if not library.is_file():
        raise FileNotFoundError(library)
    return library


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prefix", type=Path)
    parser.add_argument("--github-env", action="store_true")
    options = parser.parse_args()
    library = install(options.prefix)
    print(library)
    if options.github_env:
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
            output.write(f"SDL3_LIBRARY={library}\n")
            prefix = options.prefix.resolve()
            output.write(f"PKG_CONFIG_PATH={prefix / 'lib/pkgconfig'}{os.pathsep}{os.environ.get('PKG_CONFIG_PATH', '')}\n")
            if sys.platform == "linux":
                output.write(f"LD_LIBRARY_PATH={prefix / 'lib'}{os.pathsep}{os.environ.get('LD_LIBRARY_PATH', '')}\n")
