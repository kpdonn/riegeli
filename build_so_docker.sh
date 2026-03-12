#!/bin/bash
# Build _riegeli_dataset_ops.so inside a Docker container.
# Downloads third-party deps directly (no Bazel needed).
# Usage: RIEGELI_DIR=/path/to/riegeli TF_DIR=/path/to/tensorflow bash build_so_docker.sh
set -e

: "${RIEGELI_DIR:?Set RIEGELI_DIR to the riegeli source root}"
: "${TF_DIR:?Set TF_DIR to the tensorflow package directory}"

# Source files use relative paths — must run from the riegeli root
cd "$RIEGELI_DIR"

TF_INC="$TF_DIR/include"
GEN="$RIEGELI_DIR/build_manual"
OUTDIR="$RIEGELI_DIR/build_manual/obj"
DEPDIR="$RIEGELI_DIR/build_manual/deps"
mkdir -p "$OUTDIR" "$DEPDIR"

# --- Download third-party sources (matching versions from WORKSPACE) ---
fetch_dep() {
    local name="$1" url="$2" strip="$3" sha="$4"
    if [ -d "$DEPDIR/$name" ]; then return; fi
    echo "Fetching $name..."
    local tmp="$DEPDIR/${name}.archive"
    curl -sL "$url" -o "$tmp"
    mkdir -p "$DEPDIR/$name"
    if [[ "$url" == *.tar.gz ]]; then
        tar xzf "$tmp" --strip-components=1 -C "$DEPDIR/$name"
    else
        # zip
        unzip -q "$tmp" -d "$DEPDIR/${name}_tmp"
        mv "$DEPDIR/${name}_tmp"/$strip/* "$DEPDIR/$name"/
        rm -rf "$DEPDIR/${name}_tmp"
    fi
    rm -f "$tmp"
}

fetch_dep highwayhash \
    "https://github.com/google/highwayhash/archive/276dd7b4b6d330e4734b756e97ccfb1b69cc2e12.zip" \
    "highwayhash-276dd7b4b6d330e4734b756e97ccfb1b69cc2e12" \
    "cf891e024699c82aabce528a024adbe16e529f2b4e57f954455e0bf53efae585"

fetch_dep brotli \
    "https://github.com/google/brotli/archive/3914999fcc1fda92e750ef9190aa6db9bf7bdb07.zip" \
    "brotli-3914999fcc1fda92e750ef9190aa6db9bf7bdb07" \
    "84a9a68ada813a59db94d83ea10c54155f1d34399baf377842ff3ab9b3b3256e"

fetch_dep zstd \
    "https://github.com/facebook/zstd/archive/v1.4.5.zip" \
    "zstd-1.4.5" \
    "b6c537b53356a3af3ca3e621457751fa9a6ba96daf3aebb3526ae0f610863532"

fetch_dep snappy \
    "https://github.com/google/snappy/archive/1.2.0.zip" \
    "snappy-1.2.0" \
    "7ee7540b23ae04df961af24309a55484e7016106e979f83323536a1322cedf1b"

# snappy needs a generated config header — create a minimal one
if [ ! -f "$DEPDIR/snappy/snappy-stubs-public.h" ]; then
    cat > "$DEPDIR/snappy/snappy-stubs-public.h" <<'SNAPPY_EOF'
#ifndef THIRD_PARTY_SNAPPY_OPENSOURCE_SNAPPY_STUBS_PUBLIC_H_
#define THIRD_PARTY_SNAPPY_OPENSOURCE_SNAPPY_STUBS_PUBLIC_H_
#include <cstddef>
#include <cstdint>
#define SNAPPY_MAJOR 1
#define SNAPPY_MINOR 2
#define SNAPPY_PATCHLEVEL 0
#define SNAPPY_VERSION ((SNAPPY_MAJOR << 16) | (SNAPPY_MINOR << 8) | SNAPPY_PATCHLEVEL)
namespace snappy {
  using int32 = std::int32_t;
  using int64 = std::int64_t;
  using uint32 = std::uint32_t;
  using uint64 = std::uint64_t;
  using string = std::string;
}
#endif
SNAPPY_EOF
fi

EXT="$DEPDIR"

# --- Compiler flags ---
CXX=g++
CXXFLAGS=(
    -std=c++17
    -O2
    -DNDEBUG
    -fPIC
    -D_GLIBCXX_USE_CXX11_ABI=1
    -DEIGEN_MAX_ALIGN_BYTES=64
    -fvisibility=hidden
    -isystem "$TF_INC"
    -I "$RIEGELI_DIR"
    -I "$GEN"
    -I "$EXT/highwayhash"
    -I "$EXT/brotli/c/include"
    -I "$EXT/zstd/lib"
    -I "$EXT/snappy"
)

echo "=== Compiling ==="

RIEGELI_SRCS=(
    riegeli/base/assert.cc
    riegeli/base/background_cleaning.cc
    riegeli/base/buffer.cc
    riegeli/base/chain.cc
    riegeli/base/cord_utils.cc
    riegeli/base/errno_mapping.cc
    riegeli/base/memory_estimator.cc
    riegeli/base/object.cc
    riegeli/base/parallelism.cc
    riegeli/base/recycling_pool.cc
    riegeli/base/shared_buffer.cc
    riegeli/base/sized_shared_buffer.cc
    riegeli/base/status.cc
    riegeli/base/string_utils.cc
    riegeli/base/zeros.cc
    riegeli/brotli/brotli_allocator.cc
    riegeli/brotli/brotli_dictionary.cc
    riegeli/brotli/brotli_reader.cc
    riegeli/bytes/array_backward_writer.cc
    riegeli/bytes/backward_writer.cc
    riegeli/bytes/buffer_options.cc
    riegeli/bytes/buffered_reader.cc
    riegeli/bytes/chain_backward_writer.cc
    riegeli/bytes/chain_reader.cc
    riegeli/bytes/chain_writer.cc
    riegeli/bytes/cord_reader.cc
    riegeli/bytes/limiting_backward_writer.cc
    riegeli/bytes/limiting_reader.cc
    riegeli/bytes/pullable_reader.cc
    riegeli/bytes/pushable_backward_writer.cc
    riegeli/bytes/reader.cc
    riegeli/bytes/restricted_chain_writer.cc
    riegeli/bytes/string_reader.cc
    riegeli/bytes/string_writer.cc
    riegeli/bytes/write_int_internal.cc
    riegeli/bytes/writer.cc
    riegeli/chunk_encoding/chunk.cc
    riegeli/chunk_encoding/chunk_decoder.cc
    riegeli/chunk_encoding/decompressor.cc
    riegeli/chunk_encoding/field_projection.cc
    riegeli/chunk_encoding/hash.cc
    riegeli/chunk_encoding/simple_decoder.cc
    riegeli/chunk_encoding/transpose_decoder.cc
    riegeli/messages/message_parse.cc
    riegeli/messages/message_wire_format.cc
    riegeli/ordered_varint/ordered_varint_reading.cc
    riegeli/ordered_varint/ordered_varint_writing.cc
    riegeli/records/chunk_reader.cc
    riegeli/records/record_position.cc
    riegeli/records/record_reader.cc
    riegeli/records/skipped_region.cc
    riegeli/snappy/snappy_reader.cc
    riegeli/snappy/snappy_streams.cc
    riegeli/tensorflow/io/file_reader.cc
    riegeli/tensorflow/kernels/riegeli_dataset_ops.cc
    riegeli/tensorflow/ops/riegeli_dataset_ops.cc
    riegeli/varint/varint_reading.cc
    riegeli/zstd/zstd_dictionary.cc
    riegeli/zstd/zstd_reader.cc
)

THIRDPARTY_SRCS=(
    "$EXT/highwayhash/highwayhash/sip_hash.cc"
    "$EXT/highwayhash/highwayhash/arch_specific.cc"
    "$EXT/highwayhash/highwayhash/instruction_sets.cc"
    "$EXT/highwayhash/highwayhash/nanobenchmark.cc"
    "$EXT/highwayhash/highwayhash/os_specific.cc"
    "$EXT/snappy/snappy.cc"
    "$EXT/snappy/snappy-sinksource.cc"
)

HH_SSE41_SRCS=("$EXT/highwayhash/highwayhash/hh_sse41.cc")
HH_AVX2_SRCS=("$EXT/highwayhash/highwayhash/hh_avx2.cc")

BROTLI_C_SRCS=(
    "$EXT/brotli/c/common/constants.c"
    "$EXT/brotli/c/common/context.c"
    "$EXT/brotli/c/common/dictionary.c"
    "$EXT/brotli/c/common/platform.c"
    "$EXT/brotli/c/common/shared_dictionary.c"
    "$EXT/brotli/c/common/transform.c"
    "$EXT/brotli/c/dec/bit_reader.c"
    "$EXT/brotli/c/dec/decode.c"
    "$EXT/brotli/c/dec/huffman.c"
    "$EXT/brotli/c/dec/state.c"
    "$EXT/brotli/c/enc/backward_references.c"
    "$EXT/brotli/c/enc/backward_references_hq.c"
    "$EXT/brotli/c/enc/bit_cost.c"
    "$EXT/brotli/c/enc/block_splitter.c"
    "$EXT/brotli/c/enc/brotli_bit_stream.c"
    "$EXT/brotli/c/enc/cluster.c"
    "$EXT/brotli/c/enc/command.c"
    "$EXT/brotli/c/enc/compound_dictionary.c"
    "$EXT/brotli/c/enc/compress_fragment.c"
    "$EXT/brotli/c/enc/compress_fragment_two_pass.c"
    "$EXT/brotli/c/enc/dictionary_hash.c"
    "$EXT/brotli/c/enc/encode.c"
    "$EXT/brotli/c/enc/encoder_dict.c"
    "$EXT/brotli/c/enc/entropy_encode.c"
    "$EXT/brotli/c/enc/fast_log.c"
    "$EXT/brotli/c/enc/histogram.c"
    "$EXT/brotli/c/enc/literal_cost.c"
    "$EXT/brotli/c/enc/memory.c"
    "$EXT/brotli/c/enc/metablock.c"
    "$EXT/brotli/c/enc/static_dict.c"
    "$EXT/brotli/c/enc/utf8_util.c"
)

ZSTD_DIR="$EXT/zstd/lib"
ZSTD_C_SRCS=(
    "$ZSTD_DIR/common/debug.c"
    "$ZSTD_DIR/common/entropy_common.c"
    "$ZSTD_DIR/common/error_private.c"
    "$ZSTD_DIR/common/fse_decompress.c"
    "$ZSTD_DIR/common/pool.c"
    "$ZSTD_DIR/common/threading.c"
    "$ZSTD_DIR/common/xxhash.c"
    "$ZSTD_DIR/common/zstd_common.c"
    "$ZSTD_DIR/compress/fse_compress.c"
    "$ZSTD_DIR/compress/hist.c"
    "$ZSTD_DIR/compress/huf_compress.c"
    "$ZSTD_DIR/compress/zstd_compress.c"
    "$ZSTD_DIR/compress/zstd_compress_literals.c"
    "$ZSTD_DIR/compress/zstd_compress_sequences.c"
    "$ZSTD_DIR/compress/zstd_compress_superblock.c"
    "$ZSTD_DIR/compress/zstd_double_fast.c"
    "$ZSTD_DIR/compress/zstd_fast.c"
    "$ZSTD_DIR/compress/zstd_lazy.c"
    "$ZSTD_DIR/compress/zstd_ldm.c"
    "$ZSTD_DIR/compress/zstd_opt.c"
    "$ZSTD_DIR/compress/zstdmt_compress.c"
    "$ZSTD_DIR/decompress/huf_decompress.c"
    "$ZSTD_DIR/decompress/zstd_ddict.c"
    "$ZSTD_DIR/decompress/zstd_decompress.c"
    "$ZSTD_DIR/decompress/zstd_decompress_block.c"
)

ZSTD_CFLAGS=(-I "$ZSTD_DIR" -I "$ZSTD_DIR/common" -DZSTD_MULTITHREAD -DXXH_NAMESPACE=ZSTD_)

FAILDIR=$(mktemp -d)

compile_cc() {
    local src="$1"
    shift
    local obj="$OUTDIR/$(echo "$src" | tr '/.' '__').o"
    if $CXX "${CXXFLAGS[@]}" "$@" -c "$src" -o "$obj" 2>&1; then
        echo "  OK: $(basename $src)"
    else
        echo "  FAIL: $src"
        touch "$FAILDIR/failed"
    fi
}

compile_c() {
    local src="$1"
    shift
    local obj="$OUTDIR/$(echo "$src" | tr '/.' '__').o"
    if gcc -O2 -fPIC -DNDEBUG -fvisibility=hidden "$@" -c "$src" -o "$obj" 2>&1; then
        echo "  OK: $(basename $src)"
    else
        echo "  FAIL: $src"
        touch "$FAILDIR/failed"
    fi
}

# Compile C++ sources in parallel
for src in "${RIEGELI_SRCS[@]}" "${THIRDPARTY_SRCS[@]}"; do
    compile_cc "$src" &
done

# highwayhash with ISA flags
for src in "${HH_SSE41_SRCS[@]}"; do
    compile_cc "$src" -msse4.1 &
done
for src in "${HH_AVX2_SRCS[@]}"; do
    compile_cc "$src" -mavx2 &
done

# C sources: brotli
for src in "${BROTLI_C_SRCS[@]}"; do
    compile_c "$src" -I "$EXT/brotli/c/include" &
done

# C sources: zstd
for src in "${ZSTD_C_SRCS[@]}"; do
    compile_c "$src" "${ZSTD_CFLAGS[@]}" &
done

echo "Waiting for compilations..."
wait

if [ -f "$FAILDIR/failed" ]; then
    echo "=== SOME COMPILATIONS FAILED ==="
    rm -rf "$FAILDIR"
    exit 1
fi
rm -rf "$FAILDIR"

echo "=== All compilations done ==="
echo "=== Linking ==="

OBJS=("$OUTDIR"/*.o)
$CXX -shared -o "$RIEGELI_DIR/build_manual/_riegeli_dataset_ops.so" "${OBJS[@]}" \
    -Wl,--version-script="$GEN/hide_all.lds" \
    -L"$TF_DIR" -l:libtensorflow_framework.so.2 \
    -static-libstdc++ -lpthread -lz

echo "=== Done ==="
ls -la "$RIEGELI_DIR/build_manual/_riegeli_dataset_ops.so"
