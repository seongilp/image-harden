from main import H


def test_handler_has_get():
    assert hasattr(H, "do_GET")
