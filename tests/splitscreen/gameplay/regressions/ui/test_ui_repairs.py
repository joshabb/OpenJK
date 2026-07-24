#!/usr/bin/env python3
"""Static regressions for split-screen UI ownership and setup persistence."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[5]
UI_MAIN = (ROOT / "codemp/ui/ui_main.c").read_text(encoding="utf-8")
START_MENU = (
    ROOT / "assets/splitscreen/base/ui/jamp/splitscreen_start.menu"
).read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    match = re.search(rf"\b{name}\s*\([^)]*\)\s*\{{", source)
    if not match:
        raise AssertionError(f"function not found: {name}")
    start = match.end()
    depth = 1
    cursor = start
    while depth and cursor < len(source):
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    if depth:
        raise AssertionError(f"unterminated function: {name}")
    return source[start : cursor - 1]


class ModalOwnershipTests(unittest.TestCase):
    def test_top_menu_is_painted_only_for_active_owner(self) -> None:
        body = function_body(UI_MAIN, "UI_PaintSplitScreenIngameMenus")
        owner_guard = body.find("if ( player != activeTarget )")
        paint = body.find("Menu_Paint( ingameMenu, qtrue )")
        self.assertGreaterEqual(owner_guard, 0)
        self.assertGreater(paint, owner_guard)

    def test_stock_modal_top_bar_is_not_duplicated_into_other_panes(self) -> None:
        body = function_body(UI_MAIN, "UI_PaintSplitScreenStockMenu")
        self.assertRegex(
            body,
            r"if \( ingameMenu && player == activeTarget \) \{"
            r"[\s\S]*?Menu_Paint\( ingameMenu, qtrue \);",
        )

    def test_modal_paints_remain_viewport_scoped(self) -> None:
        for name in (
            "UI_PaintSplitScreenIngameMenus",
            "UI_PaintSplitScreenStockMenu",
            "UI_PaintSplitScreenPlayerSetup",
        ):
            body = function_body(UI_MAIN, name)
            self.assertIn("UI_PushViewportTransform(", body, name)
            self.assertIn("UI_PopViewportTransform()", body, name)


class SetupPersistenceTests(unittest.TestCase):
    def test_stock_visibility_groups_are_recomputed_for_every_player_pane(self) -> None:
        body = function_body(UI_MAIN, "UI_PrepareSplitScreenStockPlayerMenu")
        self.assertIn("UpdateForceStatus()", body)

    def test_opening_start_menu_does_not_reset_saved_choices(self) -> None:
        on_open = re.search(r"onOpen\s*\{(?P<body>[^}]*)\}", START_MENU)
        self.assertIsNotNone(on_open)
        body = on_open.group("body")
        self.assertNotIn("setcvar ui_splitScreenPlayerCount", body)
        self.assertNotIn("setcvar ui_splitScreenSessionType", body)
        self.assertIn("RefreshSplitScreenPlayerCount", body)
        self.assertIn("RefreshSplitScreenSessionType", body)

    def test_count_buttons_use_validated_ui_script(self) -> None:
        for count in (2, 3, 4):
            self.assertIn(
                f"uiScript SplitScreenSelectPlayerCount {count}",
                START_MENU,
            )


if __name__ == "__main__":
    unittest.main()
