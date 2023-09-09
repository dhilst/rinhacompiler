import os
from setuptools import setup
from Cython.Build import cythonize

files = ["_crinha.pyx"]

if os.path.exists("./_rinha_python_out.pyx"):
    files += ["_rinha_python_out.pyx"]

print(files)

setup(
    ext_modules=cythonize(files, annotate=True),
)
