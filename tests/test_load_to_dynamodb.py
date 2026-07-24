"""Unit tests for the DynamoDB loader's float-to-Decimal coercion."""
from decimal import Decimal

import load_to_dynamodb as loader


def test_float_becomes_decimal():
    assert loader.decimalize(197662.68) == Decimal("197662.68")
    assert isinstance(loader.decimalize(1.0), Decimal)


def test_int_and_str_pass_through():
    assert loader.decimalize(342) == 342
    assert isinstance(loader.decimalize(342), int)
    assert loader.decimalize("romance") == "romance"


def test_nested_dict_and_list_are_converted():
    item = {"avg_ms": 219239.73, "ranks": [1, 2.0, 3], "meta": {"score": 0.5}}
    out = loader.decimalize(item)
    assert out["avg_ms"] == Decimal("219239.73")
    assert out["ranks"] == [1, Decimal("2.0"), 3]
    assert out["meta"]["score"] == Decimal("0.5")


def test_no_float_precision_drift():
    # Going via str(float) avoids the binary-float artefacts Decimal(float) shows.
    assert loader.decimalize(0.1) == Decimal("0.1")
