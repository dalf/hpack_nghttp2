import os
import json

from hpack.hpack import (
    Encoder, Decoder
)

def load_cases():
    raw_story_files = (
        (os.path.join('test/test_fixtures/raw-data', name), name)
        for name in os.listdir('test/test_fixtures/raw-data')
    )
    cases = []
    for source, outname in raw_story_files:
        with open(source, 'rb') as f:
            indata = json.load(f)
            for case in indata['cases']:
                correct_headers = [
                    (item[0], item[1])
                    for header in case['headers']
                    for item in header.items()
                ]
                cases.append(correct_headers)
    return cases

cases = load_cases()
e = Encoder()
encoded_cases = [e.encode(headers) for headers in cases]

class TestHpackEncoder:
    def test_encode(self, benchmark):
        e = Encoder()
        def f():
            for headers in cases:
                e.encode(headers)

        benchmark(f)


class TestHpackDecoder:
    def test_decode(self, benchmark):
        d = Decoder()
        def f():
            for data in encoded_cases:
                d.decode(data)

        benchmark(f)
