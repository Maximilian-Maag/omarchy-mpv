"""Integration tests — the shipped CLI driven as a subprocess against a synthetic
Omarchy theme directory (never the user's real one) and a fake mpv IPC socket.
"""

import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-mpv"

THEME = """\
mode = "dark"

accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
dark_background = "#080910"
background = "#0B0C16"
foreground = "#ddf7ff"
"""


class FakeMpv:
    """A threaded stand-in for a running mpv JSON IPC socket."""

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
                line = conn.makefile("rb").readline()
                if not line:
                    continue
                command = json.loads(line.decode())["command"]
                self.commands.append(command)
                response = {"error": self.error or "success"}
                if self.error is None and command[0] == "get_property":
                    response["data"] = 30.0 if command[1] == "volume" else "fake-mpv"
                conn.sendall((json.dumps(response) + "\n").encode())

    def close(self):
        self._stop = True
        self._thread.join(timeout=2)
        self._sock.close()
        try:
            os.unlink(str(self.path))
        except OSError:
            pass


class CliIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name)
        self.state = self.base / "state"
        self.config = self.base / "config"
        theme = self.state / "omarchy/current/theme"
        theme.mkdir(parents=True)
        (theme / "colors.toml").write_text(THEME)
        self.env = dict(os.environ)
        self.env["XDG_STATE_HOME"] = str(self.state)
        self.env["XDG_CONFIG_HOME"] = str(self.config)
        self.env["XDG_RUNTIME_DIR"] = str(self.base / "run")
        self.env["HOME"] = str(self.base / "home")
        (self.base / "home").mkdir()

    def run_cli(self, *args, **kwargs):
        return subprocess.run([sys.executable, str(CLI), *args],
                              capture_output=True, text=True, env=self.env, **kwargs)

    def test_theme_writes_dedicated_conf(self):
        proc = self.run_cli("theme")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        conf = self.config / "mpv/omarchy-theme.conf"
        self.assertTrue(conf.is_file())
        text = conf.read_text()
        self.assertIn("#0B0C16", text)
        self.assertIn("#82FB9C", text)
        self.assertIn("#ddf7ff", text)
        self.assertIn("sub-color", text)
        self.assertIn("osd-selected-color", text)

    def test_theme_is_idempotent(self):
        self.assertEqual(self.run_cli("theme").returncode, 0)
        self.assertEqual(self.run_cli("theme").returncode, 0)

    def test_theme_does_not_touch_user_mpv_conf(self):
        user_conf = self.config / "mpv/mpv.conf"
        user_conf.parent.mkdir(parents=True)
        user_conf.write_text("# my precious config\nvo=gpu\n")
        self.run_cli("theme")
        self.assertEqual(user_conf.read_text(), "# my precious config\nvo=gpu\n")

    def test_theme_stdout_prints_conf(self):
        proc = self.run_cli("theme", "--stdout")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("sub-color=", proc.stdout)
        self.assertFalse((self.config / "mpv/omarchy-theme.conf").exists())

    def test_theme_without_applied_theme_fails(self):
        (self.state / "omarchy/current/theme/colors.toml").unlink()
        proc = self.run_cli("theme")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no applied theme", proc.stderr)

    def test_status_reports_applied_theme(self):
        proc = self.run_cli("status")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Maximilian-Maag.mpv", proc.stdout)
        self.assertIn("applied theme", proc.stdout)
        self.assertIn("keybinding", proc.stdout)
        self.assertIn("mpv", proc.stdout.lower())

    def test_bindings_wires_hyprland(self):
        hypr = self.config / "hypr"
        hypr.mkdir(parents=True)
        (hypr / "hyprland.lua").write_text("-- main config\n")
        proc = self.run_cli("bindings")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((hypr / "mpv-bindings.lua").is_file())
        self.assertIn('require("hypr.mpv-bindings")', (hypr / "hyprland.lua").read_text())

    def test_bindings_idempotent(self):
        hypr = self.config / "hypr"
        hypr.mkdir(parents=True)
        (hypr / "hyprland.lua").write_text("-- main\n")
        self.run_cli("bindings")
        self.run_cli("bindings")
        text = (hypr / "hyprland.lua").read_text()
        self.assertEqual(text.count('require("hypr.mpv-bindings")'), 1)

    def test_config_json_overrides_theme_conf_path(self):
        cfg = self.base / "mpv.json"
        cfg.write_text(json.dumps({"theme_conf_path": str(self.base / "elsewhere/theme.conf")}))
        proc = self.run_cli("--config", str(cfg), "theme")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((self.base / "elsewhere/theme.conf").is_file())

    def test_send_round_trips_through_a_real_socket(self):
        sock = self.base / "mpv.sock"
        server = FakeMpv(sock)
        self.addCleanup(server.close)
        proc = self.run_cli("--socket", str(sock), "send", "toggle")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(["cycle", "pause"], server.commands)

    def test_send_volume_reports_mpv_value(self):
        sock = self.base / "mpv.sock"
        server = FakeMpv(sock)
        self.addCleanup(server.close)
        proc = self.run_cli("--socket", str(sock), "send", "volume")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("30.0", proc.stdout)

    def test_send_without_a_running_mpv_is_a_clean_error(self):
        proc = self.run_cli("--socket", str(self.base / "absent.sock"), "send", "play")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no mpv IPC socket", proc.stderr)


if __name__ == "__main__":
    unittest.main()
