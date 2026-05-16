from qwenpaw.cli.desktop_cmd import (
    DEFAULT_DESKTOP_TITLE,
    _desktop_window_title,
)


def test_desktop_window_title_defaults_to_qwenpaw(monkeypatch) -> None:
    monkeypatch.delenv("QWENPAW_DESKTOP_TITLE", raising=False)

    assert _desktop_window_title() == DEFAULT_DESKTOP_TITLE


def test_desktop_window_title_can_be_overridden(monkeypatch) -> None:
    monkeypatch.setenv("QWENPAW_DESKTOP_TITLE", "AI工作台")

    assert _desktop_window_title() == "AI工作台"
