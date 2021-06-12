# -*- coding: utf-8 -*-
"""
hyper/http20/hpack_compat
~~~~~~~~~~~~~~~~~~~~~~~~~
Provides an abstraction layer over two HPACK implementations.
Hyper has a pure-Python greenfield HPACK implementation that can be used on
all Python platforms. However, this implementation is both slower and more
memory-hungry than could be achieved with a C-language version. Additionally,
nghttp2's HPACK implementation currently achieves better compression ratios
than hyper's in almost all benchmarks.
For those who care about efficiency and speed in HPACK, hyper allows you to
use nghttp2's HPACK implementation instead of hyper's. This module detects
whether the nghttp2 bindings are installed, and if they are it wraps them in
a hyper-compatible API and uses them instead of its own. If not, it falls back
to hyper's built-in Python bindings.
"""

from .nghttp2 import (
    _to_bytes,  # for tests
    _dict_to_iterable,  # for tests
    Encoder,
    Decoder,
)
