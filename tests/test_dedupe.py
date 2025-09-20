from csv_combiner.dedupe import remove_duplicates


def test_remove_duplicates_basic():
    data = [
        {"MAC Addr": "A", "Val": "1"},
        {"MAC Addr": "B", "Val": "2"},
        {"MAC Addr": "A", "Val": "3"},
    ]
    out = remove_duplicates(data, ["MAC Addr"])
    # keep last occurrence of A (Val=3)
    assert len(out) == 2
    # find A row
    arow = [r for r in out if r["MAC Addr"] == "A"][0]
    assert arow["Val"] == "3"


def test_remove_duplicates_multiple_keys():
    data = [
        {"A": "1", "B": "x"},
        {"A": "1", "B": "y"},
        {"A": "1", "B": "x"},
    ]
    out = remove_duplicates(data, ["A", "B"])
    assert len(out) == 2
    # last occurrence of (1,x) is the third row
    found = [r for r in out if r["A"] == "1" and r["B"] == "x"]
    assert found and found[0] == data[2]
