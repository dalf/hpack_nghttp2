# nghttp2 - HTTP/2 C Library

# Copyright (c) 2013 Tatsuhiro Tsujikawa

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
from hpack cimport cnghttp2

from libc.stdlib cimport malloc, free
from libc.string cimport memcpy, memset
from libc.stdint cimport uint8_t, uint16_t, uint32_t, int32_t
import logging

from .exceptions import HPACKError, HPACKDecodingError


DEFAULT_HEADER_TABLE_SIZE = cnghttp2.NGHTTP2_DEFAULT_HEADER_TABLE_SIZE
DEFLATE_MAX_HEADER_TABLE_SIZE = 4096

HD_ENTRY_OVERHEAD = 32

class HDTableEntry:

    def __init__(self, name, namelen, value, valuelen):
        self.name = name
        self.namelen = namelen
        self.value = value
        self.valuelen = valuelen

    def space(self):
        return self.namelen + self.valuelen + HD_ENTRY_OVERHEAD

cdef class Entry:
    cdef public bytes name, value
    cdef public int flags

    def __init__(self, name, value, sentive):
        self.name = name
        self.value = value
        self.flags = cnghttp2.NGHTTP2_NV_FLAG_NO_INDEX if sentive else cnghttp2.NGHTTP2_NV_FLAG_NONE

cdef _get_pybytes(uint8_t *b, uint16_t blen):
    return b[:blen]

cdef class HDDeflater:
    '''Performs header compression. The constructor takes
    |hd_table_bufsize_max| parameter, which limits the usage of header
    table in the given amount of bytes. This is necessary because the
    header compressor and decompressor share the same amount of
    header table and the decompressor decides that number. The
    compressor may not want to use all header table size because of
    limited memory availability. In that case, the
    |hd_table_bufsize_max| can be used to cap the upper limit of table
    size whatever the header table size is chosen by the decompressor.
    The default value of |hd_table_bufsize_max| is 4096 bytes.

    The following example shows how to compress request header sets:

        import binascii, nghttp2

        deflater = nghttp2.HDDeflater()
        res = deflater.deflate([(b'foo', b'bar'),
                              (b'baz', b'buz')])
        print(binascii.b2a_hex(res))

    '''

    cdef cnghttp2.nghttp2_hd_deflater *_deflater

    def __cinit__(self, hd_table_bufsize_max = DEFLATE_MAX_HEADER_TABLE_SIZE):
        rv = cnghttp2.nghttp2_hd_deflate_new(&self._deflater,
                                             hd_table_bufsize_max)
        if rv != 0:
            # nghttp2_error.NGHTTP2_ERR_NOMEM : Out of memory
            raise RuntimeError(_strerror(rv))

    def __dealloc__(self):
        cnghttp2.nghttp2_hd_deflate_del(self._deflater)

    def deflate(self, headers):
        '''Compresses the |headers|. The |headers| must be sequence of tuple
        of name/value pair, which are sequence of bytes (not unicode
        string).

        This function returns the encoded header block in byte string.
        An exception will be raised on error.

        '''
        cdef cnghttp2.nghttp2_nv *nva = <cnghttp2.nghttp2_nv*>\
                                        malloc(sizeof(cnghttp2.nghttp2_nv)*\
                                        len(headers))
        cdef cnghttp2.nghttp2_nv *nvap = nva

        for entry in headers:
            nvap[0].name = entry.name
            nvap[0].namelen = len(entry.name)
            nvap[0].value = entry.value
            nvap[0].valuelen = len(entry.value)
            nvap[0].flags = entry.flags
            nvap += 1

        cdef size_t outcap = 0
        cdef ssize_t rv
        cdef uint8_t *out
        cdef size_t outlen

        outlen = cnghttp2.nghttp2_hd_deflate_bound(self._deflater,
                                                   nva, len(headers))

        out = <uint8_t*>malloc(outlen)

        rv = cnghttp2.nghttp2_hd_deflate_hd(self._deflater, out, outlen,
                                            nva, len(headers))
        free(nva)

        if rv < 0:
            free(out)
            raise HPACKError(_strerror(rv))

        cdef bytes res

        try:
            res = out[:rv]
        finally:
            free(out)

        return res

    def change_table_size(self, hd_table_bufsize_max):
        '''Changes header table size to |hd_table_bufsize_max| byte.

        An exception will be raised on error.

        '''
        cdef int rv
        rv = cnghttp2.nghttp2_hd_deflate_change_table_size(self._deflater,
                                                           hd_table_bufsize_max)
        if rv != 0:
            raise Exception(_strerror(rv))

    def get_hd_table(self):
        '''Returns copy of current dynamic header table.'''
        cdef size_t length = cnghttp2.nghttp2_hd_deflate_get_num_table_entries(
            self._deflater)
        cdef const cnghttp2.nghttp2_nv *nv
        res = []
        for i in range(62, length + 1):
            nv = cnghttp2.nghttp2_hd_deflate_get_table_entry(self._deflater, i)
            k = _get_pybytes(nv.name, nv.namelen)
            v = _get_pybytes(nv.value, nv.valuelen)
            res.append(HDTableEntry(k, nv.namelen, v, nv.valuelen))
        return res

cdef class HDInflater:
    '''Performs header decompression.

    The following example shows how to compress request header sets:

        data = b'0082c5ad82bd0f000362617a0362757a'
        inflater = nghttp2.HDInflater()
        hdrs = inflater.inflate(data)
        print(hdrs)

    '''

    cdef cnghttp2.nghttp2_hd_inflater *_inflater

    def __cinit__(self):
        rv = cnghttp2.nghttp2_hd_inflate_new(&self._inflater)
        if rv != 0:
            # nghttp2_error.NGHTTP2_ERR_NOMEM : Out of memory
            raise RuntimeError(_strerror(rv))

    def __dealloc__(self):
        cnghttp2.nghttp2_hd_inflate_del(self._inflater)

    def inflate(self, data):
        '''Decompresses the compressed header block |data|. The |data| must be
        byte string (not unicode string).

        '''
        cdef cnghttp2.nghttp2_nv nv
        cdef int inflate_flags
        cdef ssize_t rv
        cdef uint8_t *buf = data
        cdef size_t buflen = len(data)
        res = []
        while True:
            inflate_flags = 0
            rv = cnghttp2.nghttp2_hd_inflate_hd2(self._inflater, &nv,
                                                 &inflate_flags,
                                                 buf, buflen, 1)
            if rv < 0:
                raise HPACKDecodingError(_strerror(rv))
            buf += rv
            buflen -= rv
            if inflate_flags & cnghttp2.NGHTTP2_HD_INFLATE_EMIT:
                # may throw
                res.append((nv.name[:nv.namelen], nv.value[:nv.valuelen]))
            if inflate_flags & cnghttp2.NGHTTP2_HD_INFLATE_FINAL:
                break

        cnghttp2.nghttp2_hd_inflate_end_headers(self._inflater)
        return res

    def get_table_size(self):
        return cnghttp2.nghttp2_hd_inflate_get_max_dynamic_table_size(self._inflater)

    def change_table_size(self, hd_table_bufsize_max):
        '''Changes header table size to |hd_table_bufsize_max| byte.

        An exception will be raised on error.

        '''
        cdef int rv
        rv = cnghttp2.nghttp2_hd_inflate_change_table_size(self._inflater,
                                                           hd_table_bufsize_max)
        if rv != 0:
            raise Exception(_strerror(rv))

    def get_hd_table(self):
        '''Returns copy of current dynamic header table.'''
        cdef size_t length = cnghttp2.nghttp2_hd_inflate_get_num_table_entries(
            self._inflater)
        cdef const cnghttp2.nghttp2_nv *nv
        res = []
        for i in range(62, length + 1):
            nv = cnghttp2.nghttp2_hd_inflate_get_table_entry(self._inflater, i)
            k = _get_pybytes(nv.name, nv.namelen)
            v = _get_pybytes(nv.value, nv.valuelen)
            res.append(HDTableEntry(k, nv.namelen, v, nv.valuelen))
        return res

cdef _strerror(int liberror_code):
    return cnghttp2.nghttp2_strerror(liberror_code).decode('utf-8')

def print_hd_table(hdtable):
    '''Convenient function to print |hdtable| to the standard output. This
    function does not work if header name/value cannot be decoded using
    UTF-8 encoding.

    s=N means the entry occupies N bytes in header table.

    '''
    idx = 0
    for entry in hdtable:
        idx += 1
        print('[{}] (s={}) {}: {}'\
              .format(idx, entry.space(),
                      entry.name.decode('utf-8'),
                      entry.value.decode('utf-8')))
