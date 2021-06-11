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
from libc.stdint cimport uint8_t, uint16_t, uint32_t, int32_t

cdef extern from 'nghttp2/nghttp2.h':

    const size_t NGHTTP2_DEFAULT_HEADER_TABLE_SIZE

    ctypedef enum nghttp2_error:
        NGHTTP2_ERR_NOMEM
        NGHTTP2_ERR_DEFERRED

    ctypedef enum nghttp2_nv_flag:
        NGHTTP2_NV_FLAG_NONE
        NGHTTP2_NV_FLAG_NO_INDEX
        NGHTTP2_NV_FLAG_NO_COPY_NAME
        NGHTTP2_NV_FLAG_NO_COPY_VALUE

    ctypedef struct nghttp2_nv:
        uint8_t *name
        uint8_t *value
        uint16_t namelen
        uint16_t valuelen
        uint8_t flags

    const char* nghttp2_strerror(int lib_error_code)

    int nghttp2_hd_deflate_new(nghttp2_hd_deflater **deflater_ptr,
                               size_t deflate_hd_table_bufsize_max)

    void nghttp2_hd_deflate_del(nghttp2_hd_deflater *deflater)

    int nghttp2_hd_deflate_get_max_dynamic_table_size(nghttp2_hd_deflater *deflater)

    int nghttp2_hd_deflate_change_table_size(nghttp2_hd_deflater *deflater,
                                             size_t hd_table_bufsize_max)

    ssize_t nghttp2_hd_deflate_hd(nghttp2_hd_deflater *deflater,
                                  uint8_t *buf, size_t buflen,
                                  const nghttp2_nv *nva, size_t nvlen)

    size_t nghttp2_hd_deflate_bound(nghttp2_hd_deflater *deflater,
                                    const nghttp2_nv *nva, size_t nvlen)

    int nghttp2_hd_inflate_new(nghttp2_hd_inflater **inflater_ptr)

    void nghttp2_hd_inflate_del(nghttp2_hd_inflater *inflater)

    int nghttp2_hd_inflate_get_dynamic_table_size(nghttp2_hd_inflater *inflater)

    int nghttp2_hd_inflate_get_max_dynamic_table_size(nghttp2_hd_inflater *inflater)

    int nghttp2_hd_inflate_change_table_size(nghttp2_hd_inflater *inflater,
                                             size_t hd_table_bufsize_max)

    ssize_t nghttp2_hd_inflate_hd2(nghttp2_hd_inflater *inflater,
                                   nghttp2_nv *nv_out, int *inflate_flags,
                                   const uint8_t *input, size_t inlen,
                                   int in_final)

    int nghttp2_hd_inflate_end_headers(nghttp2_hd_inflater *inflater)

    ctypedef enum nghttp2_hd_inflate_flag:
        NGHTTP2_HD_INFLATE_EMIT
        NGHTTP2_HD_INFLATE_FINAL

    ctypedef struct nghttp2_hd_deflater:
        pass

    ctypedef struct nghttp2_hd_inflater:
        pass

    size_t nghttp2_hd_deflate_get_num_table_entries(nghttp2_hd_deflater *deflater)

    const nghttp2_nv * nghttp2_hd_deflate_get_table_entry(nghttp2_hd_deflater *deflater, size_t idx)

    size_t nghttp2_hd_inflate_get_num_table_entries(nghttp2_hd_inflater *inflater)

    const nghttp2_nv *nghttp2_hd_inflate_get_table_entry(nghttp2_hd_inflater *inflater, size_t idx)
