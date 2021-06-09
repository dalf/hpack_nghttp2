Experimental Python hpack_ implementation using nghttp2_.

The API is nearly compatible with hpack_. (httpx runs without issues).

It requires Cython because nghttp2pyx_ requires some updates:

- to raise `hpack.exceptions.*` instead of a generic `Exception`
- to handle the sentive flag


How to install
--------------

::

  python -m pip install git+https://github.com/dalf/hpack_nghttp2.git

Warning: it will replace the existing the hpack module


Not implemented
---------------

- hpack.Decoder.max_header_list_size : the value is ignored
- hpack.Encoder.header_table_size : raise NotImplementedError
- hpack.exceptions.InvalidTableIndex : never raised
- hpack.exceptions.OversizedHeaderListError : never raised
- hpack.exceptions.InvalidTableSizeError : never raised


.. _hpack: https://github.com/python-hyper/hpack
.. _nghttp2: https://github.com/nghttp2/nghttp2
.. _nghttp2pyx: https://github.com/nghttp2/nghttp2/blob/master/python/nghttp2.pyx
