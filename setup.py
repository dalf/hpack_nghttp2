#!/usr/bin/env python3

import os
import re

from setuptools import setup, find_packages, Extension
from Cython.Build import cythonize

PROJECT_ROOT = os.path.dirname(__file__)

with open(os.path.join(PROJECT_ROOT, 'README.rst')) as file_:
    long_description = file_.read()

version_regex = r'__version__ = ["\']([^"\']*)["\']'
with open(os.path.join(PROJECT_ROOT, 'src/hpack/__init__.py')) as file_:
    text = file_.read()
    match = re.search(version_regex, text)
    if match:
        version = match.group(1)
    else:
        raise RuntimeError("No version number found!")

extensions = [
    Extension(
        'hpack.nghttp2', 
        ['src/hpack/nghttp2.pyx'], 
        libraries=['nghttp2']
    )
]

setup(
    name='hpack',
    version=version,
    description='HPACK header compression using nghttp2',
    long_description=long_description,
    long_description_content_type='text/x-rst',
    author='Alexandre Flament',
    author_email='alex.andre@al-f.net',
    url='https://github.com/dalf/hpack_nghttp2',
    packages=find_packages(where="src"),
    package_data={'hpack': []},
    package_dir={'': 'src'},
    python_requires='>=3.6.1',
    setup_requires=['cython'],
    ext_modules=cythonize(extensions, language_level = "3"),
    license='MIT License',
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: Implementation :: CPython',
    ],
)
