#!/usr/bin/env python3
"""Run the actual C numerical kernel without requiring a PostgreSQL server."""

import ctypes as C
import math
from pathlib import Path
import random
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="ml_standardize_test_") as tmp:
        library = Path(tmp) / "standardize_core.so"
        subprocess.run([
            "cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-fPIC", "-shared",
            str(ROOT / "standardize_core.c"), "-lm", "-o", str(library)
        ], check=True)
        dll = C.CDLL(str(library))
        run = dll.ml_pg_standardize_core
        dp = C.POINTER(C.c_double)
        run.argtypes = [dp, C.POINTER(C.c_bool), C.c_size_t, C.c_size_t,
                        dp, dp, dp, C.POINTER(C.c_size_t), C.c_void_p]
        run.restype = C.c_int

        def evaluate(matrix):
            rows, cols = len(matrix), len(matrix[0])
            flat = [v for row in matrix for v in row]
            data = (C.c_double * len(flat))(*[math.nan if v is None else v for v in flat])
            missing = (C.c_bool * len(flat))(*[v is None for v in flat])
            original = bytes(data), bytes(missing)
            out = (C.c_double * len(flat))()
            means = (C.c_double * cols)()
            stddevs = (C.c_double * cols)()
            bad = C.c_size_t()
            status = run(data, missing, rows, cols, out, means, stddevs, C.byref(bad), None)
            assert (bytes(data), bytes(missing)) == original, "input was modified"
            return status, list(out), list(means), list(stddevs), bad.value

        def verify(matrix):
            status, out, means, stddevs, _ = evaluate(matrix)
            assert status == 0, (status, matrix)
            cols = len(matrix[0])
            for col in range(cols):
                known = [row[col] for row in matrix if row[col] is not None]
                mean = math.fsum(known) / len(known)
                sigma = math.sqrt(math.fsum((v - mean) ** 2 for v in known) / len(known))
                assert math.isclose(means[col], mean, rel_tol=1e-12, abs_tol=1e-12)
                assert math.isclose(stddevs[col], sigma, rel_tol=1e-12, abs_tol=1e-12)
                z_known = []
                for row, original_row in enumerate(matrix):
                    z = out[row * cols + col]
                    if original_row[col] is None:
                        assert z == 0.0
                    else:
                        target = 0.0 if sigma == 0.0 else (original_row[col] - mean) / sigma
                        assert math.isclose(z, target, rel_tol=1e-11, abs_tol=1e-11)
                        z_known.append(z)
                if sigma != 0.0:
                    assert abs(math.fsum(z_known) / len(z_known)) < 1e-12
                    assert math.isclose(math.fsum(z*z for z in z_known) / len(z_known),
                                        1.0, rel_tol=1e-12, abs_tol=1e-12)

        verify([[1, 10], [2, 20], [3, 30], [None, 40]])
        verify([[5, None], [5, 7], [5, None]])
        verify([[8]])
        assert evaluate([[1, None], [2, None]])[::4] == (1, 1)
        assert evaluate([[math.nan]])[0] == 2
        assert evaluate([[math.inf]])[0] == 2
        assert evaluate([[-math.inf]])[0] == 2

        # These finite doubles would overflow a naive sum or squared deviation.
        status, out, means, stddevs, _ = evaluate([[-1e308], [1e308]])
        assert status == 0 and out == [-1.0, 1.0]
        assert means == [0.0] and stddevs == [1e308]
        status, out, means, stddevs, _ = evaluate([[1e100]] * 5000)
        assert status == 0 and all(z == 0 for z in out)
        assert means == [1e100] and stddevs == [0.0]

        rng = random.Random(20261026)
        for _ in range(300):
            rows, cols = rng.randint(1, 80), rng.randint(1, 7)
            matrix = [[None if rng.random() < .25 else rng.uniform(-100, 100)
                       for _ in range(cols)] for _ in range(rows)]
            for col in range(cols):
                if all(row[col] is None for row in matrix):
                    matrix[0][col] = rng.uniform(-100, 100)
            verify(matrix)

    print("Standardization C core checks passed (300 random matrices and edge cases).")


if __name__ == "__main__":
    main()
