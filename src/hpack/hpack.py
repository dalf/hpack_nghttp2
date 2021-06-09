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
import logging

from . import nghttp2
from .struct import HeaderTuple

log = logging.getLogger(__name__)


def _dict_to_iterable(header_dict):
    """
    This converts a dictionary to an iterable of two-tuples. This is a
    HPACK-specific function because it pulls "special-headers" out first and
    then emits them.
    """
    assert isinstance(header_dict, dict)
    keys = sorted(
        header_dict.keys(),
        key=lambda k: not _to_bytes(k).startswith(b':')
    )
    for key in keys:
        yield key, header_dict[key]


def _to_bytes(string):
    """
    Convert string to bytes.
    """
    if not isinstance(string, (str, bytes)):
        string = str(string)

    return string if isinstance(string, bytes) else string.encode('utf-8')

class Encoder(object):
    """
    An HPACK encoder object. This object takes HTTP headers and emits
    encoded HTTP/2 header blocks.
    """
    def __init__(self):
        self._e = nghttp2.HDDeflater()

    @property
    def header_table_size(self):
        """
        Returns the header table size. For the moment this isn't
        useful, so we don't use it.
        """
        raise NotImplementedError()

    @header_table_size.setter
    def header_table_size(self, value):
        log.debug("Setting header table size to %d", value)
        self._e.change_table_size(value)

    def encode(self, headers, huffman=True):
        if not huffman:
            raise NotImplementedError('huffman=False is not implemented')

        # Turn the headers into a list of tuples if possible. This is the
        # natural way to interact with them in HPACK.
        if isinstance(headers, dict):
            headers = _dict_to_iterable(headers)

        # Next, walk across the headers and turn them all into bytestrings.
        params = []
        for header in headers:
            sensitive = False
            if isinstance(header, HeaderTuple):
                sensitive = not header.indexable
            elif len(header) > 2:
                sensitive = header[2]
            entry = nghttp2.Entry(_to_bytes(header[0]), _to_bytes(header[1]), sensitive)
            params.append(entry)

        # Now, let nghttp2 do its thing.
        header_block = self._e.deflate(params)

        return header_block

class Decoder(object):

    __slots__ = ('_d', 'max_header_list_size')

    """
    An HPACK decoder object.
    """
    def __init__(self):
        self._d = nghttp2.HDInflater()

    @property
    def header_table_size(self):
        raise self._d.get_table_size()

    @header_table_size.setter
    def header_table_size(self, value):
        log.debug("Setting header table size to %d", value)
        self._d.change_table_size(value)

    def decode(self, data, raw=False):
        """
        Takes an HPACK-encoded header block and decodes it into a header
        set.
        """
        headers = self._d.inflate(data)
        if raw:
            return headers
        return [HeaderTuple(n.decode('utf-8'), v.decode('utf-8')) for n, v in headers]
