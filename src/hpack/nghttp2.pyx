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

from .struct import HeaderTuple
from .exceptions import HPACKError, HPACKDecodingError, InvalidTableSizeError, OversizedHeaderListError


DEFAULT_HEADER_TABLE_SIZE = cnghttp2.NGHTTP2_DEFAULT_HEADER_TABLE_SIZE
DEFLATE_MAX_HEADER_TABLE_SIZE = 4096
# We default the maximum header list we're willing to accept to 64kB. That's a
# lot of headers, but if applications want to raise it they can do.
DEFAULT_MAX_HEADER_LIST_SIZE = 2 ** 16

HD_ENTRY_OVERHEAD = 32


cdef class HDTableEntry:
    cdef public bytes name, value
    cdef public int flags

    def __cinit__(self, bytes name, bytes value, int flags):
        self.name = name
        self.value = value
        self.flags = flags

    def space(self):
        return len(self.name) + len(self.value) + HD_ENTRY_OVERHEAD


cdef HDTableEntry nv_to_hdtableentry(const cnghttp2.nghttp2_nv *nv):
    k = _get_pybytes(nv.name, nv.namelen)
    v = _get_pybytes(nv.value, nv.valuelen)
    return HDTableEntry(k, v, nv.flags)


cdef _strerror(int liberror_code):
    return cnghttp2.nghttp2_strerror(liberror_code).decode('utf-8')


cpdef bytes _to_bytes(string):
    """
    Convert string to bytes.
    """
    if not isinstance(string, (str, bytes)):
        string = str(string)

    return string if isinstance(string, bytes) else string.encode('utf-8')


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


cdef _get_tableentries(headers):
    # Turn the headers into a list of tuples if possible. This is the
    # natural way to interact with them in HPACK.
    if isinstance(headers, dict):
        headers = _dict_to_iterable(headers)

    params = []
    for header in headers:
        sensitive = False
        if isinstance(header, HeaderTuple):
            sensitive = not header.indexable
        elif len(header) > 2:
            sensitive = header[2]
        name = _to_bytes(header[0])
        value = _to_bytes(header[1])
        flags = cnghttp2.NGHTTP2_NV_FLAG_NO_INDEX if sensitive else cnghttp2.NGHTTP2_NV_FLAG_NONE
        params.append(HDTableEntry(name, value, flags))
    return params


cdef _get_pybytes(uint8_t *b, uint16_t blen):
    return b[:blen]


cdef table_entry_size(cnghttp2.nghttp2_nv nv):
    return HD_ENTRY_OVERHEAD + nv.namelen + nv.valuelen


cdef class Encoder:
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
        if rv == cnghttp2.nghttp2_error.NGHTTP2_ERR_NOMEM:
            raise MemoryError()
        if rv != 0:
            raise RuntimeError()

    def __dealloc__(self):
        cnghttp2.nghttp2_hd_deflate_del(self._deflater)

    def encode(self, headers, huffman=True):
        '''Compresses the |headers|. The |headers| must be sequence of tuple
        of name/value pair, which are sequence of bytes (not unicode
        string).

        This function returns the encoded header block in byte string.
        An exception will be raised on error.

        '''
        if not huffman:
            raise NotImplementedError('huffman=False is not implemented')

        headers = _get_tableentries(headers)

        #
        cdef cnghttp2.nghttp2_nv *nva = <cnghttp2.nghttp2_nv*>\
                                        malloc(sizeof(cnghttp2.nghttp2_nv)*\
                                        len(headers))
        cdef cnghttp2.nghttp2_nv *nvap = nva

        # Next, walk across the headers and turn them all into bytestrings.
        for e in headers:
            nvap[0].name = e.name
            nvap[0].namelen = len(e.name)
            nvap[0].value = e.value
            nvap[0].valuelen = len(e.value)
            nvap[0].flags = e.flags
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

    @property
    def header_table_size(self):
        return cnghttp2.nghttp2_hd_deflate_get_max_dynamic_table_size(self._deflater)


    @header_table_size.setter
    def header_table_size(self, hd_table_bufsize_max):
        """
        see https://nghttp2.org/documentation/nghttp2_hd_deflate_change_table_size.html :
        The deflater never uses more memory than max_deflate_dynamic_table_size bytes specified in
        nghttp2_hd_deflate_new(). Therefore, if settings_max_dynamic_table_size > max_deflate_dynamic_table_size,
        resulting maximum table size becomes max_deflate_dynamic_table_size.
        """
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
            res.append(nv_to_hdtableentry(nv))
        return res


cdef class Decoder:
    '''Performs header decompression.

    The following example shows how to compress request header sets:

        data = b'0082c5ad82bd0f000362617a0362757a'
        inflater = nghttp2.HDInflater()
        hdrs = inflater.inflate(data)
        print(hdrs)

    '''

    cdef cnghttp2.nghttp2_hd_inflater *_inflater
    cdef public int max_header_list_size
    cdef public int max_allowed_table_size

    def __init__(self, max_header_list_size = DEFAULT_MAX_HEADER_LIST_SIZE):
        rv = cnghttp2.nghttp2_hd_inflate_new(&self._inflater)
        if rv == cnghttp2.nghttp2_error.NGHTTP2_ERR_NOMEM:
            raise MemoryError()
        if rv != 0:
            raise RuntimeError()
        self.max_header_list_size = max_header_list_size
        self.max_allowed_table_size = self.header_table_size         

    def __dealloc__(self):
        cnghttp2.nghttp2_hd_inflate_del(self._inflater)

    def decode(self, data, raw=False):
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
            if table_entry_size(nv) > self.max_header_list_size:
                raise OversizedHeaderListError()

        cnghttp2.nghttp2_hd_inflate_end_headers(self._inflater)

        # decode
        if raw:
            return res
        try:
            return [HeaderTuple(n.decode('utf-8'), v.decode('utf-8')) for n, v in res]
        except UnicodeDecodeError:
            raise HPACKDecodingError("Unable to decode headers as UTF-8.")

    @property
    def header_table_size(self):
        return cnghttp2.nghttp2_hd_inflate_get_max_dynamic_table_size(self._inflater)

    @header_table_size.setter
    def header_table_size(self, hd_table_bufsize_max):
        cdef int rv
        rv = cnghttp2.nghttp2_hd_inflate_change_table_size(self._inflater,
                                                           hd_table_bufsize_max)
        if rv != 0:
            raise InvalidTableSizeError(_strerror(rv))

    def get_hd_table(self):
        '''Returns copy of current dynamic header table.'''
        cdef size_t length = cnghttp2.nghttp2_hd_inflate_get_num_table_entries(
            self._inflater)
        cdef const cnghttp2.nghttp2_nv *nv
        res = []
        for i in range(62, length + 1):
            nv = cnghttp2.nghttp2_hd_inflate_get_table_entry(self._inflater, i)
            res.append(nv_to_hdtableentry(nv))
        return res


def print_hd_table(hdtable):
    '''Convenient function to print |hdtable| to the standard output. This
    function does not work if header name/value cannot be decoded using
    UTF-8 encoding.

    s=N means the entry occupies N bytes in header table.

    '''
    idx = 0
    for entry in hdtable:
        idx += 1
        print('[{}] (s={}) {}: {} {}'\
              .format(idx, entry.space(),
                      entry.name.decode('utf-8'),
                      entry.value.decode('utf-8'),
                      entry.flags))
