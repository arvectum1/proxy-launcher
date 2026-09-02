"""Extract the exact Inno Setup 6.7.1 child runtime from a sealed setup.

Ported from jrsoftware/issrc is-6_7_1 (cfdf48923178df4b4f040e038b423aa555a61ffc),
Projects/Src/Shared.Struct.pas, Compiler.SetupCompiler.pas and
Compression.Base.pas. Inno Setup is licensed under the Inno Setup License.
"""
import argparse, hashlib, json, lzma, struct, sys, zlib
from pathlib import Path
import pefile

TABLE_ID = b"rDlPtS\xcd\xe6\xd7\x7b\x0b\x2a"
TABLE_VERSION = 2
RCDATA = 10
RESOURCE_ID = 11111

def fail(message): raise ValueError(message)
def crc32(data): return zlib.crc32(data) & 0xffffffff

def parse_table(data, file_size):
    if len(data) != 64: fail("SetupLdr offset table is not 64 bytes")
    ident, version, total, offexe, usize, crcexe, off0, off1, padding, tablecrc = struct.unpack("<12sIqqIiqqII", data)
    if ident != TABLE_ID or version != TABLE_VERSION: fail("unsupported Inno SetupLdr table identity/version")
    if crc32(data[:60]) != tablecrc: fail("SetupLdr offset table CRC mismatch")
    if total <= 0 or total > file_size: fail("invalid SetupLdr total size")
    if offexe < 0 or offexe >= file_size or off0 < 0 or off0 >= file_size or off1 < 0 or off1 > file_size: fail("invalid SetupLdr offset")
    if usize <= 0: fail("invalid uncompressed Setup runtime size")
    return dict(total_size=total, offset_exe=offexe, uncompressed_size_exe=usize, crc_exe=crcexe & 0xffffffff, offset_0=off0, offset_1=off1, reserved_padding=padding, table_crc=tablecrc)

def resource_table(path, raw):
    pe = pefile.PE(str(path), fast_load=False)
    found = []
    for entry in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if entry.id != RCDATA: continue
        for name in entry.directory.entries:
            if name.id != RESOURCE_ID: continue
            for lang in name.directory.entries:
                offset, size = lang.data.struct.OffsetToData, lang.data.struct.Size
                found.append(pe.get_data(offset, size))
    if len(found) != 1: fail("expected exactly one RT_RCDATA/11111 table resource")
    return found[0]

def compressed_stream(raw, offset):
    if offset + 13 > len(raw): fail("truncated compressed-block header")
    header_crc, stored, compressed = struct.unpack_from("<IqB", raw, offset)
    header = raw[offset + 4:offset + 13]
    if crc32(header) != header_crc: fail("compressed-block header CRC mismatch")
    if stored <= 0 or not compressed: fail("unsupported compressed block")
    end = offset + 13 + stored
    if end > len(raw): fail("compressed block exceeds sealed setup")
    pos, chunks, stream = offset + 13, 0, bytearray()
    while pos < end:
        if end - pos < 4: fail("truncated compressed chunk CRC")
        expected = struct.unpack_from("<I", raw, pos)[0]; pos += 4
        length = min(4096, end - pos)
        if length <= 0: fail("empty compressed chunk")
        chunk = raw[pos:pos + length]; pos += length
        if crc32(chunk) != expected: fail("compressed chunk CRC mismatch")
        stream.extend(chunk); chunks += 1
    if pos != end: fail("compressed block boundary mismatch")
    return bytes(stream), stored, chunks

def decode_props(props):
    if len(props) != 5: fail("truncated LZMA1 properties")
    value = props[0]; lc = value % 9; value //= 9; lp = value % 5; pb = value // 5
    if pb > 4: fail("unsupported LZMA1 property byte")
    dictionary = struct.unpack("<I", props[1:])[0]
    if dictionary == 0: fail("invalid LZMA1 dictionary")
    return lc, lp, pb, dictionary

def transform_calls(buf, encode=False, addr_offset=0):
    data = bytearray(buf)
    i = 0
    while i < len(data) - 4:
        if data[i] in (0xe8, 0xe9):
            i += 1
            if data[i + 3] in (0, 255):
                addr = (addr_offset + i + 4) & 0xffffff
                rel = data[i] | data[i + 1] << 8 | data[i + 2] << 16
                if not encode: rel = (rel - addr) & 0xffffffff
                if rel & 0x800000: data[i + 3] ^= 0xff
                if encode: rel = (rel + addr) & 0xffffffff
                data[i:i + 3] = bytes((rel & 0xff, (rel >> 8) & 0xff, (rel >> 16) & 0xff))
            i += 4
        else:
            i += 1
    return bytes(data)

def extract(path):
    raw = Path(path).read_bytes()
    if raw[:2] != b"MZ": fail("sealed setup is not a PE image")
    table = parse_table(resource_table(path, raw), len(raw))
    stream, stored, chunks = compressed_stream(raw, table["offset_exe"])
    lc, lp, pb, dictionary = decode_props(stream[:5])
    try: transformed = lzma.decompress(stream[5:], format=lzma.FORMAT_RAW, filters=[{"id": lzma.FILTER_LZMA1, "lc":lc, "lp":lp, "pb":pb, "dict_size":dictionary}])
    except lzma.LZMAError as exc: fail("LZMA1 decompression failed: " + str(exc))
    if len(transformed) != table["uncompressed_size_exe"]: fail("LZMA1 output size mismatch")
    runtime = transform_calls(transformed, False, 0)
    if crc32(runtime) != table["crc_exe"]: fail("derived runtime CRCEXE mismatch")
    if runtime[:2] != b"MZ" or struct.unpack_from("<I", runtime, 0x3c)[0] + 4 > len(runtime) or runtime[struct.unpack_from("<I", runtime, 0x3c)[0]:][:4] != b"PE\0\0": fail("derived runtime is not a valid PE image")
    return runtime, dict(**table, compressed_block_stored_size=stored, compressed_block_chunk_count=chunks, lzma_lc=lc, lzma_lp=lp, lzma_pb=pb, lzma_dict_size=dictionary)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("setup"); parser.add_argument("output"); parser.add_argument("--evidence", required=True); args = parser.parse_args()
    runtime, evidence = extract(args.setup); Path(args.output).write_bytes(runtime)
    evidence.update(sealed_setup_size=Path(args.setup).stat().st_size, sealed_setup_sha256=hashlib.sha256(Path(args.setup).read_bytes()).hexdigest(), derived_runtime_size=len(runtime), derived_runtime_sha256=hashlib.sha256(runtime).hexdigest(), derived_runtime_crc32=f"{crc32(runtime):08x}")
    Path(args.evidence).write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
