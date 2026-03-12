#!/bin/bash
# Minimal build: only compile the TF op files.
# All Riegeli core symbols (record reader, chunks, compression) come from
# libtensorflow_framework.so.2, which bundles the entire Riegeli library.
set -e

TF_DIR="/home/kevin/workspace/kd_chess/.venv/lib/python3.12/site-packages/tensorflow"
TF_INC="$TF_DIR/include"
RIEGELI_DIR="/home/kevin/workspace/riegeli"

OUTDIR="$RIEGELI_DIR/build_manual/obj"
mkdir -p "$OUTDIR"

CXX=g++
CXXFLAGS=(
    -std=c++17
    -O2
    -DNDEBUG
    -fPIC
    -D_GLIBCXX_USE_CXX11_ABI=1
    -DEIGEN_MAX_ALIGN_BYTES=64
    -isystem "$TF_INC"
    -I "$RIEGELI_DIR"
    -I "$RIEGELI_DIR/build_manual"
)

echo "=== Compiling 3 files ==="

$CXX "${CXXFLAGS[@]}" -c riegeli/tensorflow/io/file_reader.cc \
    -o "$OUTDIR/file_reader.o" && echo "  OK: file_reader.cc"

$CXX "${CXXFLAGS[@]}" -c riegeli/tensorflow/kernels/riegeli_dataset_ops.cc \
    -o "$OUTDIR/riegeli_dataset_ops_kernel.o" && echo "  OK: riegeli_dataset_ops.cc (kernel)"

$CXX "${CXXFLAGS[@]}" -c riegeli/tensorflow/ops/riegeli_dataset_ops.cc \
    -o "$OUTDIR/riegeli_dataset_ops_reg.o" && echo "  OK: riegeli_dataset_ops.cc (registration)"

echo "=== Linking ==="
$CXX -shared -o "$OUTDIR/../_riegeli_dataset_ops.so" \
    "$OUTDIR/file_reader.o" \
    "$OUTDIR/riegeli_dataset_ops_kernel.o" \
    "$OUTDIR/riegeli_dataset_ops_reg.o" \
    -L"$TF_DIR" -l:libtensorflow_framework.so.2

echo "=== Done ==="
ls -la "$OUTDIR/../_riegeli_dataset_ops.so"
