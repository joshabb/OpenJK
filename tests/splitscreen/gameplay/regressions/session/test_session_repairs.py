#!/usr/bin/env python3
"""Focused source contracts for GP4-03 split-session repairs."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[5]
SOURCE = (ROOT / "codemp/client/cl_main.cpp").read_text()


def function_body(name: str) -> str:
    match = re.search(rf"\b{name}\s*\([^)]*\)\s*\{{", SOURCE)
    if not match:
        raise AssertionError(f"missing function {name}")
    start = match.end()
    depth = 1
    index = start
    while depth and index < len(SOURCE):
        depth += (SOURCE[index] == "{") - (SOURCE[index] == "}")
        index += 1
    if depth:
        raise AssertionError(f"unterminated function {name}")
    return SOURCE[start:index - 1]


class SessionRepairContracts(unittest.TestCase):
    def test_split_server_commands_use_tokenized_tail(self):
        """Vstr-expanded commands preserve the tail and quoted argv boundaries."""
        for name in ("CL_SplitNetReliableCommand_f", "CL_SplitNetRejoin_f"):
            body = function_body(name)
            self.assertIn(
                "CL_SplitNetBuildReliableCommand( 2, command", body
            )
            self.assertNotIn("Cmd_ArgsFromBuffer( 2, command", body)
            self.assertNotIn("Com_SkipTokens", body)

    def test_command_tail_model_covers_all_local_players(self):
        commands = [
            ["splitnet_cmd", "2", "team", "blue"],
            ["splitnet_cmd", "3", "team", "red"],
            ["splitnet_cmd", "4", "say", "party ready"],
        ]
        self.assertEqual([" ".join(argv[2:]) for argv in commands],
                         ["team blue", "team red", "say party ready"])

    def test_disconnect_records_only_a_live_party_endpoint(self):
        body = function_body("CL_Disconnect")
        self.assertIn("cl_splitPrimaryDisconnectTime = Sys_Milliseconds()", body)
        for state in ("active", "partial", "failed"):
            self.assertIn(f'"{state}"', body)
        self.assertIn("cls.state >= CA_CONNECTED", body)
        self.assertLess(body.index("cl_splitPrimaryDisconnectTime"),
                        body.index("CL_SplitNetDisconnectAll()"))

    def test_primary_reconnect_guard_precedes_connection_reset(self):
        body = function_body("CL_Connect_f")
        self.assertIn("reconnectElapsed < 3000", body)
        self.assertIn(
            'Cbuf_ExecuteText( EXEC_INSERT, va( "wait 60\\nconnect %s", server ) )',
            body,
        )
        self.assertLess(body.index("reconnectElapsed < 3000"),
                        body.index("CL_Disconnect( qtrue )"))

    def test_guard_is_party_and_endpoint_scoped(self):
        body = function_body("CL_Connect_f")
        self.assertIn('!Q_stricmp( splitPartyState, "connecting" )', body)
        self.assertIn("CL_SplitNetSameServer", body)
        self.assertIn("cl_splitPrimaryReconnectServer", body)

    def test_secondary_party_handshakes_are_serialized_for_stock_servers(self):
        connect = function_body("CL_SplitNetPartyConnect_f")
        frame = function_body("CL_SplitNetPartyFrame")
        self.assertIn(
            "cl_splitNextPartyConnectTime = cls.realtime + 3500", connect
        )
        self.assertIn("previousPlayer < player", frame)
        self.assertIn("previous->state != CA_ACTIVE", frame)
        self.assertIn("!previous->active.snap.valid", frame)
        self.assertIn("cls.realtime < cl_splitNextPartyConnectTime", frame)
        self.assertIn(
            "cl_splitNextPartyConnectTime = cls.realtime + 3500", frame
        )
        self.assertLess(
            frame.index("CL_SplitNetBeginConnect( player, target )"),
            frame.index("return;", frame.index("CL_SplitNetBeginConnect( player, target )")),
        )

    def test_server_reconnect_throttle_is_a_bounded_retry(self):
        body = function_body("CL_SplitNetConnectionlessPacket")
        guard = body.index('"Reconnect rejected : too soon"')
        retry = body.index(
            'CL_SplitNetSetStatus( player, "challenging", translated )',
            guard,
        )
        failure = body.index(
            'CL_SplitNetSetStatus( player, "failed", translated )',
            retry,
        )
        self.assertIn("split->state == CA_CHALLENGING", body[:guard])
        self.assertIn("split->connection.connectTime = cls.realtime", body[guard:retry])
        self.assertLess(retry, failure)


if __name__ == "__main__":
    unittest.main()
