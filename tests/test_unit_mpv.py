"""Unit tests for omarchy-mpv's pure logic.

The shipped CLI has no ``.py`` extension (it is installed as ``omarchy-mpv``),
so it is loaded with a SourceFileLoader rather than imported by name.

The IPC path is exercised against a **fake mpv socket server** (a threaded unix
socket), so the unit tests never require mpv to be installed.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import pathlib
import socket
import tempfile
import threading
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-mpv"

_loader = importlib.machinery.SourceFileLoader("omarchy_mpv", str(CLI))
_spec = importlib.util.spec_from_loader("omarchy_mpv", _loader)
mpv = importlib.util.module_from_spec(_spec)
_loader.exec_module(mpv)

SAMPLE = """\
mode = "dark"

# the accent
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
dark_background = "#080910"

background = "#0B0C16"
foreground = "#ddf7ff"
hyprland_active_border = "rgba(26a269ee) rgba(2ec27eee) 45deg"
"""

COLORS = {
    "mode": "dark",
    "accent": "#82FB9C",
    "selection": "#1f253a",
    "muted": "#2d3450",
    "dark_background": "#080910",
    "background": "#0B0C16",
    "foreground": "#ddf7ff",
}


class FakeMpv:
    """A minimal stand-in for a running mpv's JSON IPC socket."""

    def __init__(self, path, error=None):
        self.path = pathlib.Path(path)
        self.commands = []
        self.error = error
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.bind(str(self.path))
        self._sock.listen(8)
        self._sock.settimeout(0.2)
        self._stop = False
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    def _serve(self):
        while not self._stop:
            try:
                conn, _ = self._sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with conn:
                reader = conn.makefile("rb")
                line = reader.readline()
                if not line:
                    continue
                request = json.loads(line.decode())
                command = request["command"]
                self.commands.append(command)
                response = {"error": self.error or "success"}
                if self.error is None and command[0] == "get_property":
                    response["data"] = 42.0 if command[1] == "volume" else "fake-mpv"
                conn.sendall((json.dumps(response) + "\n").encode())

    def close(self):
        self._stop = True
        self._thread.join(timeout=2)
        self._sock.close()
        try:
            os.unlink(str(self.path))
        except OSError:
            pass


class ParseColors(unittest.TestCase):
    def test_basic_keys_and_values(self):
        colors = mpv.parse_colors(SAMPLE)
        self.assertEqual(colors["accent"], "#82FB9C")
        self.assertEqual(colors["background"], "#0B0C16")
        self.assertEqual(colors["mode"], "dark")

    def test_comments_and_blanks_skipped(self):
        colors = mpv.parse_colors("# a comment\n\n   \naccent = \"#fff\"\n")
        self.assertEqual(colors, {"accent": "#fff"})

    def test_comment_containing_equals_is_not_parsed(self):
        colors = mpv.parse_colors('# accent = "#fff"\naccent = "#000"\n')
        self.assertEqual(colors, {"accent": "#000"})

    def test_hex_colour_is_not_treated_as_a_comment(self):
        self.assertEqual(mpv.parse_colors("accent = \"#82FB9C\"\n")["accent"], "#82FB9C")

    def test_line_without_equals_is_skipped(self):
        self.assertEqual(mpv.parse_colors("garbage\naccent = \"#fff\"\n"), {"accent": "#fff"})

    def test_empty_key_is_skipped(self):
        self.assertEqual(mpv.parse_colors("= nope\naccent = \"#fff\"\n"), {"accent": "#fff"})

    def test_single_quotes_stripped(self):
        self.assertEqual(mpv.parse_colors("accent = '#fff'\n")["accent"], "#fff")

    def test_unquoted_value_kept(self):
        self.assertEqual(mpv.parse_colors("mode = dark\n")["mode"], "dark")


class NormalizeName(unittest.TestCase):
    def test_title_case_to_slug(self):
        self.assertEqual(mpv.normalize_name("Tokyo Night"), "tokyo-night")

    def test_strips_and_lowercases(self):
        self.assertEqual(mpv.normalize_name("  Hackerman  "), "hackerman")


class MvpColour(unittest.TestCase):
    def test_hex_passthrough(self):
        self.assertEqual(mpv.mpv_colour("#82FB9C"), "#82FB9C")

    def test_rgba_reduced_to_hex(self):
        self.assertEqual(mpv.mpv_colour("rgba(26a269ee)"), "#26a269")

    def test_rgba_with_alpha_zero(self):
        self.assertEqual(mpv.mpv_colour("rgba(2ec27e00)"), "#2ec27e")

    def test_short_hex_rejected(self):
        with self.assertRaises(ValueError):
            mpv.mpv_colour("#fff")

    def test_long_hex_rejected(self):
        # 8 characters: neither a #rrggbb nor a rgba() stop.
        with self.assertRaises(ValueError):
            mpv.mpv_colour("#82FB9C0")

    def test_garbage_rejected(self):
        with self.assertRaises(ValueError):
            mpv.mpv_colour("not-a-colour")

    def test_whitespace_stripped(self):
        self.assertEqual(mpv.mpv_colour("  #82FB9C  "), "#82FB9C")


class ThemePairs(unittest.TestCase):
    def test_uses_theme_colours(self):
        pairs = dict(mpv.theme_pairs(dict(COLORS)))
        self.assertEqual(pairs["sub-color"], "#ddf7ff")
        self.assertEqual(pairs["sub-outline-color"], "#0B0C16")
        self.assertEqual(pairs["osd-color"], "#ddf7ff")
        self.assertEqual(pairs["osd-selected-color"], "#82FB9C")
        self.assertEqual(pairs["background-color"], "#0B0C16")

    def test_dark_background_used_for_subtitle_backing(self):
        pairs = dict(mpv.theme_pairs(dict(COLORS)))
        self.assertEqual(pairs["sub-back-color"], "#080910")

    def test_dark_background_falls_back_to_background(self):
        colors = {k: v for k, v in COLORS.items() if k != "dark_background"}
        pairs = dict(mpv.theme_pairs(colors))
        self.assertEqual(pairs["sub-back-color"], "#0B0C16")

    def test_accent_drives_osd_selection(self):
        colors = dict(COLORS, accent="#abcdef")
        self.assertEqual(dict(mpv.theme_pairs(colors))["osd-selected-color"], "#abcdef")


class BuildConf(unittest.TestCase):
    def test_contains_theme_colours(self):
        conf = mpv.build_conf(dict(COLORS))
        for value in ("#ddf7ff", "#0B0C16", "#82FB9C", "#080910"):
            self.assertIn(value, conf)

    def test_subtitle_colour_line(self):
        self.assertIn('sub-color="#ddf7ff"', mpv.build_conf(dict(COLORS)))

    def test_osd_selection_line(self):
        self.assertIn('osd-selected-color="#82FB9C"', mpv.build_conf(dict(COLORS)))

    def test_ends_with_newline(self):
        self.assertTrue(mpv.build_conf(dict(COLORS)).endswith("\n"))

    def test_header_mentions_include(self):
        self.assertIn("include=", mpv.build_conf(dict(COLORS)))

    def test_sub_bold_enabled(self):
        self.assertIn("sub-bold=yes", mpv.build_conf(dict(COLORS)))


class ResolveThemeName(unittest.TestCase):
    def _theme(self, root, name, body):
        d = root / name
        d.mkdir()
        (d / "colors.toml").write_text(body)
        return d

    def test_matches_colour_set(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            self._theme(root, "nord", "accent = \"#88c0d0\"\nbackground = \"#2e3440\"\n")
            self._theme(root, "gruvbox", "accent = \"#d79921\"\nbackground = \"#282828\"\n")
            colors = {"accent": "#d79921", "background": "#282828"}
            self.assertEqual(mpv.resolve_theme_name(colors, [root / "nord", root / "gruvbox"]),
                             "gruvbox")

    def test_no_match_returns_empty(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            self._theme(root, "nord", "accent = \"#88c0d0\"\n")
            self.assertEqual(mpv.resolve_theme_name({"accent": "#000000"}, [root / "nord"]), "")

    def test_missing_colors_file_skipped(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            (root / "empty").mkdir()
            self.assertEqual(mpv.resolve_theme_name({"a": "b"}, [root / "empty"]), "")


class ConfigAndPaths(unittest.TestCase):
    def test_default_theme_conf_path(self):
        self.assertEqual(mpv.theme_conf_path({}),
                         mpv.config_home() / "mpv/omarchy-theme.conf")

    def test_theme_conf_path_override_tilde(self):
        cfg = {"theme_conf_path": "~/.config/mpv/custom.conf"}
        self.assertEqual(mpv.theme_conf_path(cfg),
                         pathlib.Path(os.path.expanduser("~/.config/mpv/custom.conf")))

    def test_theme_conf_path_override_absolute(self):
        cfg = {"theme_conf_path": "/tmp/omarchy-mpv-test/theme.conf"}
        self.assertEqual(mpv.theme_conf_path(cfg),
                         pathlib.Path("/tmp/omarchy-mpv-test/theme.conf"))

    def test_default_socket_path_under_runtime(self):
        self.assertEqual(mpv.socket_path({}), mpv.runtime_dir() / "omarchy-mpv.sock")

    def test_socket_path_override_absolute(self):
        self.assertEqual(mpv.socket_path({}, "/tmp/omarchy-mpv-test.sock"),
                         pathlib.Path("/tmp/omarchy-mpv-test.sock"))

    def test_socket_path_config_absolute(self):
        cfg = {"socket_path": "/run/user/1000/mpv.sock"}
        self.assertEqual(mpv.socket_path(cfg), pathlib.Path("/run/user/1000/mpv.sock"))

    def test_load_config_reads_file(self):
        with tempfile.TemporaryDirectory() as t:
            p = pathlib.Path(t) / "mpv.json"
            p.write_text(json.dumps({"keybinding": "SUPER + X"}))
            cfg = mpv.load_config(p)
            self.assertEqual(cfg["keybinding"], "SUPER + X")
            self.assertIn("theme_conf_path", cfg)

    def test_load_config_missing_file_uses_defaults(self):
        cfg = mpv.load_config(pathlib.Path("/nonexistent/mpv.json"))
        self.assertEqual(cfg["theme_conf_path"], mpv.DEFAULT_CONFIG["theme_conf_path"])

    def test_load_config_invalid_json_uses_defaults(self):
        with tempfile.TemporaryDirectory() as t:
            p = pathlib.Path(t) / "mpv.json"
            p.write_text("{ not json")
            self.assertEqual(mpv.load_config(p)["keybinding"],
                             mpv.DEFAULT_CONFIG["keybinding"])

    def test_state_home_env(self):
        old = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = "/tmp/state-xyz"
        try:
            self.assertEqual(mpv.state_home(), pathlib.Path("/tmp/state-xyz"))
        finally:
            os.environ.pop("XDG_STATE_HOME", None)
            if old is not None:
                os.environ["XDG_STATE_HOME"] = old

    def test_config_home_env(self):
        old = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = "/tmp/config-xyz"
        try:
            self.assertEqual(mpv.config_home(), pathlib.Path("/tmp/config-xyz"))
        finally:
            os.environ.pop("XDG_CONFIG_HOME", None)
            if old is not None:
                os.environ["XDG_CONFIG_HOME"] = old

    def test_runtime_dir_env(self):
        old = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = "/tmp/runtime-xyz"
        try:
            self.assertEqual(mpv.runtime_dir(), pathlib.Path("/tmp/runtime-xyz"))
        finally:
            os.environ.pop("XDG_RUNTIME_DIR", None)
            if old is not None:
                os.environ["XDG_RUNTIME_DIR"] = old

    def test_colors_path_under_state_home(self):
        old = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = "/tmp/state-xyz"
        try:
            self.assertEqual(mpv.theme_colors_path(),
                             pathlib.Path("/tmp/state-xyz/omarchy/current/theme/colors.toml"))
        finally:
            os.environ.pop("XDG_STATE_HOME", None)
            if old is not None:
                os.environ["XDG_STATE_HOME"] = old

    def test_plugin_dir_is_repo_root(self):
        self.assertEqual(mpv.plugin_dir(), ROOT)


class ResolveCommand(unittest.TestCase):
    def test_play_sets_pause_false(self):
        self.assertEqual(mpv.resolve_command("play"), ["set_property", "pause", False])

    def test_pause_sets_pause_true(self):
        self.assertEqual(mpv.resolve_command("pause"), ["set_property", "pause", True])

    def test_toggle_cycles_pause(self):
        self.assertEqual(mpv.resolve_command("toggle"), ["cycle", "pause"])

    def test_next(self):
        self.assertEqual(mpv.resolve_command("next"), ["playlist-next"])

    def test_prev(self):
        self.assertEqual(mpv.resolve_command("prev"), ["playlist-prev"])

    def test_stop(self):
        self.assertEqual(mpv.resolve_command("stop"), ["stop"])

    def test_mute(self):
        self.assertEqual(mpv.resolve_command("mute"), ["cycle", "mute"])

    def test_volume_get(self):
        self.assertEqual(mpv.resolve_command("volume"), ["get_property", "volume"])

    def test_volume_set(self):
        self.assertEqual(mpv.resolve_command("volume", "42"), ["set_property", "volume", 42.0])

    def test_volume_up(self):
        self.assertEqual(mpv.resolve_command("volume-up"), ["add", "volume", mpv.VOLUME_STEP])

    def test_volume_down(self):
        self.assertEqual(mpv.resolve_command("volume-down"), ["add", "volume", -mpv.VOLUME_STEP])

    def test_unknown_returns_none(self):
        self.assertIsNone(mpv.resolve_command("frobnicate"))


class Ipc(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.sock = pathlib.Path(self.tmp.name) / "mpv.sock"

    def test_request_round_trip(self):
        server = FakeMpv(self.sock)
        self.addCleanup(server.close)
        response = mpv.ipc_request(self.sock, ["get_property", "volume"])
        self.assertEqual(response["error"], "success")
        self.assertEqual(response["data"], 42.0)
        self.assertEqual(server.commands, [["get_property", "volume"]])

    def test_socket_reachable_true(self):
        server = FakeMpv(self.sock)
        self.addCleanup(server.close)
        self.assertTrue(mpv.socket_reachable(self.sock))

    def test_socket_reachable_false_when_missing(self):
        self.assertFalse(mpv.socket_reachable(self.sock))


class Commands(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = pathlib.Path(self.tmp.name)
        self.state = base / "state"
        self.config = base / "config"
        self.sock = base / "mpv.sock"
        theme = self.state / "omarchy/current/theme"
        theme.mkdir(parents=True)
        (theme / "colors.toml").write_text(SAMPLE)
        self._env = {k: os.environ.get(k) for k in
                     ("XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR")}
        os.environ["XDG_STATE_HOME"] = str(self.state)
        os.environ["XDG_CONFIG_HOME"] = str(self.config)
        os.environ["XDG_RUNTIME_DIR"] = str(base / "run")
        self.addCleanup(self._restore)

    def _restore(self):
        for k, v in self._env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def run_cli(self, *argv):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            rc = mpv.main(list(argv))
        return rc, buf.getvalue()

    def test_theme_writes_conf(self):
        rc, _ = self.run_cli("theme")
        self.assertEqual(rc, 0)
        out = mpv.theme_conf_path()
        self.assertTrue(out.is_file())
        self.assertIn("#82FB9C", out.read_text())

    def test_theme_stdout_does_not_write(self):
        rc, text = self.run_cli("theme", "--stdout")
        self.assertEqual(rc, 0)
        self.assertIn("sub-color=", text)
        self.assertFalse(mpv.theme_conf_path().exists())

    def test_theme_missing_theme_returns_1(self):
        (self.state / "omarchy/current/theme/colors.toml").unlink()
        rc, _ = self.run_cli("theme")
        self.assertEqual(rc, 1)

    def test_theme_live_without_socket_succeeds(self):
        rc, _ = self.run_cli("theme", "--live")
        self.assertEqual(rc, 0)
        self.assertTrue(mpv.theme_conf_path().is_file())

    def test_theme_live_applies_when_running(self):
        server = FakeMpv(self.sock)
        self.addCleanup(server.close)
        rc, text = self.run_cli("--socket", str(self.sock), "theme", "--live")
        self.assertEqual(rc, 0)
        self.assertIn("applied theme live", text)
        self.assertIn(["set_property", "sub-color", "#ddf7ff"], server.commands)

    def test_status_runs(self):
        rc, text = self.run_cli("status")
        self.assertEqual(rc, 0)
        self.assertIn("Maximilian-Maag.mpv", text)
        self.assertIn("applied theme", text)
        self.assertIn("socket", text)

    def test_bindings_installs_module(self):
        rc, _ = self.run_cli("bindings")
        self.assertEqual(rc, 0)
        dest = self.config / "hypr/mpv-bindings.lua"
        self.assertTrue(dest.is_file())
        self.assertIn("o.bind", dest.read_text())


class SendCommand(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = pathlib.Path(self.tmp.name)
        self.sock = base / "mpv.sock"
        self._env = {k: os.environ.get(k) for k in
                     ("XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR")}
        os.environ["XDG_STATE_HOME"] = str(base / "state")
        os.environ["XDG_CONFIG_HOME"] = str(base / "config")
        os.environ["XDG_RUNTIME_DIR"] = str(base / "run")
        self.addCleanup(self._restore)

    def _restore(self):
        for k, v in self._env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def run_cli(self, *argv):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            rc = mpv.main(list(argv))
        return rc, buf.getvalue()

    def _server(self, error=None):
        server = FakeMpv(self.sock, error=error)
        self.addCleanup(server.close)
        return server

    def test_send_play(self):
        server = self._server()
        rc, _ = self.run_cli("--socket", str(self.sock), "send", "play")
        self.assertEqual(rc, 0)
        self.assertIn(["set_property", "pause", False], server.commands)

    def test_send_pause(self):
        server = self._server()
        rc, _ = self.run_cli("--socket", str(self.sock), "send", "pause")
        self.assertEqual(rc, 0)
        self.assertIn(["set_property", "pause", True], server.commands)

    def test_send_toggle(self):
        server = self._server()
        rc, _ = self.run_cli("--socket", str(self.sock), "send", "toggle")
        self.assertEqual(rc, 0)
        self.assertIn(["cycle", "pause"], server.commands)

    def test_send_next(self):
        server = self._server()
        rc, _ = self.run_cli("--socket", str(self.sock), "send", "next")
        self.assertEqual(rc, 0)
        self.assertIn(["playlist-next"], server.commands)

    def test_send_volume_set(self):
        server = self._server()
        rc, _ = self.run_cli("--socket", str(self.sock), "send", "volume", "55")
        self.assertEqual(rc, 0)
        self.assertIn(["set_property", "volume", 55.0], server.commands)

    def test_send_volume_get_prints_value(self):
        self._server()
        rc, text = self.run_cli("--socket", str(self.sock), "send", "volume")
        self.assertEqual(rc, 0)
        self.assertIn("42.0", text)

    def test_send_non_volume_prints_nothing(self):
        # Kills the `and` -> `or` mutation on the volume-get print guard.
        self._server()
        rc, text = self.run_cli("--socket", str(self.sock), "send", "play")
        self.assertEqual(rc, 0)
        self.assertNotIn("42.0", text)
        self.assertNotIn("None", text)

    def test_send_unknown_command_returns_2(self):
        self._server()
        rc, text = self.run_cli("--socket", str(self.sock), "send", "frobnicate")
        self.assertEqual(rc, 2)
        self.assertIn("unknown command", text)

    def test_send_without_socket_returns_1(self):
        rc, text = self.run_cli("--socket", str(self.sock), "send", "play")
        self.assertEqual(rc, 1)
        self.assertIn("no mpv IPC socket", text)

    def test_send_mpv_error_returns_1(self):
        self._server(error="error running command")
        rc, text = self.run_cli("--socket", str(self.sock), "send", "next")
        self.assertEqual(rc, 1)
        self.assertIn("rejected", text)


class VersionAndLive(unittest.TestCase):
    def test_mpv_version_returns_a_string(self):
        self.assertIsInstance(mpv.mpv_version(), str)

    def test_apply_live_without_socket_returns_false(self):
        with tempfile.TemporaryDirectory() as t:
            cfg = {"socket_path": str(pathlib.Path(t) / "nope.sock")}
            self.assertFalse(mpv.apply_live(cfg, dict(COLORS)))

    def test_apply_live_with_socket_returns_true(self):
        with tempfile.TemporaryDirectory() as t:
            sock = pathlib.Path(t) / "mpv.sock"
            server = FakeMpv(sock)
            self.addCleanup(server.close)
            cfg = {"socket_path": str(sock)}
            self.assertTrue(mpv.apply_live(cfg, dict(COLORS)))
            self.assertIn(["set_property", "osd-color", "#ddf7ff"], server.commands)


if __name__ == "__main__":
    unittest.main()


class UncoveredBranchTests(unittest.TestCase):
    """Tests added after mutation testing found survivable mutants in these paths
    (VOLUME_STEP, mpv_version's first-line pick, ipc_request's default timeout,
    and the two `return False` failure branches)."""

    def test_volume_step_is_plus_or_minus_five(self):
        self.assertEqual(mpv.resolve_command("volume-up"), ["add", "volume", mpv.VOLUME_STEP])
        self.assertEqual(mpv.resolve_command("volume-down"), ["add", "volume", -mpv.VOLUME_STEP])
        self.assertEqual(mpv.VOLUME_STEP, 5)

    def test_mpv_version_takes_the_first_line(self):
        from unittest import mock
        fake = mock.Mock(returncode=0, stdout="mpv 9.9.9\nCopyright somebody\n")
        with mock.patch.object(mpv.subprocess, "run", return_value=fake):
            self.assertEqual(mpv.mpv_version(), "mpv 9.9.9")

    def test_mpv_version_missing_binary(self):
        from unittest import mock
        with mock.patch.object(mpv.subprocess, "run", side_effect=OSError("no mpv")):
            self.assertEqual(mpv.mpv_version(), "not installed")

    def test_ipc_request_default_timeout_is_two_seconds(self):
        import inspect
        default = inspect.signature(mpv.ipc_request).parameters["timeout"].default
        self.assertEqual(default, 2.0)

    def test_socket_reachable_is_false_when_the_path_is_not_a_socket(self):
        with tempfile.TemporaryDirectory() as d:
            plain = pathlib.Path(d) / "not-a-socket"
            plain.write_text("i am a regular file")
            self.assertFalse(mpv.socket_reachable(plain))

    def test_apply_live_is_false_when_the_ipc_call_fails(self):
        from unittest import mock
        with mock.patch.object(mpv, "socket_reachable", return_value=True), \
             mock.patch.object(mpv, "ipc_request", side_effect=OSError("broken pipe")):
            colours = {"foreground": "#ffffff", "background": "#000000", "accent": "#123456"}
            self.assertFalse(mpv.apply_live({}, colours))
