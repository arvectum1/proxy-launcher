import importlib.util
import struct
import zlib
from pathlib import Path

MODULE = Path(__file__).parents[1] / 'tools' / 'bootstrap' / 'apl-win-014' / 'extract_inno_6_7_1_runtime.py'
spec = importlib.util.spec_from_file_location('inno_runtime', MODULE)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


def table(**overrides):
    fields = [runtime.TABLE_ID, 2, 100, 20, 1000, 0x12345678, 10, 0, 0, 0]
    fields[1] = overrides.get('version', fields[1])
    fields[2] = overrides.get('total', fields[2])
    fields[3] = overrides.get('offset', fields[3])
    raw = struct.pack('<12sIqqIiqqII', *fields)
    return raw[:60] + struct.pack('<I', zlib.crc32(raw[:60]) & 0xffffffff)


def test_offset_table_accepts_exact_layout():
    parsed = runtime.parse_table(table(), 100)
    assert parsed['offset_exe'] == 20


def test_offset_table_rejects_bad_version_and_crc():
    for payload in (table(version=3), table()[:-1] + b'\0'):
        try:
            runtime.parse_table(payload, 100)
            assert False
        except ValueError:
            pass


def test_call_transform_round_trip():
    original = b'\x90\xe8\x01\x00\x00\x00\x90\xe9\xfc\xff\xff\xff'
    assert runtime.transform_calls(runtime.transform_calls(original, True), False) == original


def test_lzma_properties_reject_invalid_values():
    try:
        runtime.decode_props(b'\xff\0\0\0\0')
        assert False
    except ValueError:
        pass
