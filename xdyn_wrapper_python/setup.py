import os
import re

from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext


class PrebuiltExtension(Extension):
    """An extension with no sources: zig produced the .so before setuptools was invoked."""

    def __init__(self, name):
        super().__init__(name, sources=[])


class UsePrebuilt(build_ext):
    """Deliberately a no-op, so build_ext finds the copied .so instead of compiling."""


version = os.environ.get("GIT_VERSION", "0.0.0")
if not re.match(r"[0-9]+\.[0-9]+\.*[0-9]*", version):
    print(f"GIT version is invalid: {version}")
    print("Setting version to 0.0.0 for wheel generation")
    version = "0.0.0"


setup(
    version=version,
    ext_modules=[PrebuiltExtension("xdyn")],
    cmdclass={"build_ext": UsePrebuilt},
    zip_safe=False,
)
