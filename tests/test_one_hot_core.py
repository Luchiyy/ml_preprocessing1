#!/usr/bin/env python3
"""Validate the actual C category-indexing kernel without PostgreSQL."""

import ctypes as C
from pathlib import Path
import random
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


class Reference(C.Structure):
    _fields_ = [("value", C.c_char_p), ("row", C.c_size_t)]


def main():
    with tempfile.TemporaryDirectory(prefix="ml_one_hot_test_") as tmp:
        library = Path(tmp) / "one_hot_core.so"
        subprocess.run([
            "cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-fPIC", "-shared",
            str(ROOT / "one_hot_core.c"), "-o", str(library)
        ], check=True)
        dll = C.CDLL(str(library))
        run = dll.ml_pg_one_hot_index
        run.argtypes = [C.POINTER(C.c_char_p), C.POINTER(C.c_bool), C.c_size_t,
                        C.POINTER(C.c_char_p), C.POINTER(Reference),
                        C.POINTER(C.c_int), C.c_void_p]
        run.restype = C.c_size_t

        def verify(values):
            count = len(values)
            encoded = [None if v is None else v.encode("utf-8") for v in values]
            data = (C.c_char_p * count)(*encoded)
            missing = (C.c_bool * count)(*[v is None for v in values])
            before = bytes(data), bytes(missing)
            categories = (C.c_char_p * count)()
            work = (Reference * count)()
            indexes = (C.c_int * count)()
            unique_count = run(data, missing, count, categories, work, indexes, None)
            expected_categories = sorted({v for v in encoded if v is not None})
            expected_indexes = [-1 if v is None else expected_categories.index(v) for v in encoded]
            assert unique_count == len(expected_categories)
            assert list(categories)[:unique_count] == expected_categories
            assert list(indexes) == expected_indexes
            assert (bytes(data), bytes(missing)) == before, "input changed"

        verify(["red", "blue", "red", None])
        verify([None, None])
        verify(["", "", None])
        verify(["2", "10", "2", "1"])
        verify(["a b", "a-b", "a_b", "a_b_2"])
        verify(["кот", "пёс", "кот", "😀", None])
        verify([])

        rng = random.Random(20261026)
        pool = ["", "red", "blue", "RED", "10", "2", "a b", "a-b", "a_b", "кот", "пёс", "😀", None]
        for _ in range(500):
            verify([rng.choice(pool) for _ in range(rng.randint(1, 300))])

    print("One-hot C core checks passed (500 random arrays and edge cases).")


if __name__ == "__main__":
    main()
