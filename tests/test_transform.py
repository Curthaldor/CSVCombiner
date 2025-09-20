from csv_combiner.transform import parse_chip_data, normalize_mac, apply_transformations


def test_parse_chip_data():
    s = "ABC-123 something_DEF-45 other_GHI-9 more"
    a = parse_chip_data(s)
    assert isinstance(a, list)
    assert a[0].startswith("ABC")
    assert len(a) == 3


def test_normalize_mac():
    assert normalize_mac("AA:BB:CC:DD:EE:FF") == "AABBCCDDEEFF"
    assert normalize_mac("AA;BB; CC ; DD") == "AABBCCDD"
    assert normalize_mac("") == ""


def test_apply_transformations_adds_source_and_chipdata():
    rows = [{"MAC Addr": "aa:bb:cc", "Chip Data (All)": "X-1 Y-2 Z-3", "Error Code": "E"}]
    out = apply_transformations(iter(rows), "20250101.csv")
    assert len(out) == 1
    r = out[0]
    assert r["SourceFile"] == "20250101.csv"
    assert "ChipData0" in r and "ChipData1" in r and "ChipData2" in r
    assert r["MAC Addr"] == "AABBCC" or r["MAC Addr"] == "aabbcc"
