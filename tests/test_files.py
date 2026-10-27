# python3 -m unittest discover -s tests -p "test_*.py"
#
# bin/hillchart-files: what it reads, what it refuses, and how it writes.
# The helper keeps to your home folder, so these tests stand in a fresh
# folder under ~/.cache for it and remove it afterwards.

import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import stat
import sys
import tempfile
import time
import unittest

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "hillchart-files")

# Loading the helper as a module must not leave a __pycache__ in the plugin.
sys.dont_write_bytecode = True

loader = importlib.machinery.SourceFileLoader("hillchart_files", HELPER)
spec = importlib.util.spec_from_loader("hillchart_files", loader)
files = importlib.util.module_from_spec(spec)
loader.exec_module(files)

DOC = json.dumps({"version": 1, "projects": [{"id": "a", "name": "Auth rewrite", "progress": 41}]}).encode()


class HelperTest(unittest.TestCase):
    def setUp(self):
        base = os.path.join(os.path.expanduser("~"), ".cache")
        self.home = tempfile.mkdtemp(prefix="hillchart-tests-", dir=base)
        self.real_home = files.home
        files.home = lambda: self.home
        self.data = os.path.join(self.home, ".local", "share", "hillchart", "projects.json")

    def tearDown(self):
        files.home = self.real_home
        shutil.rmtree(self.home)

    def put(self, data=DOC, mode=0o600):
        os.makedirs(os.path.dirname(self.data), mode=0o700, exist_ok=True)
        with open(self.data, "wb") as f:
            f.write(data)
        os.chmod(self.data, mode)

    # ---- reading

    def test_a_missing_file_is_missing_not_an_error(self):
        with self.assertRaises(files.Missing):
            files.read_projects(self.data)

    def test_reads_a_plain_file_of_yours(self):
        self.put()
        self.assertEqual(files.read_projects(self.data), DOC)

    def test_refuses_a_symbolic_link(self):
        self.put()
        link = os.path.join(os.path.dirname(self.data), "link.json")
        os.symlink(self.data, link)
        with self.assertRaisesRegex(files.Refused, "symbolic link"):
            files.read_projects(link)

    def test_refuses_a_linked_folder_on_the_way(self):
        self.put()
        os.symlink(os.path.dirname(self.data), os.path.join(self.home, "elsewhere"))
        with self.assertRaisesRegex(files.Refused, "not a real directory"):
            files.read_projects(os.path.join(self.home, "elsewhere", "projects.json"))

    def test_refuses_a_pipe_without_waiting_on_it(self):
        os.makedirs(os.path.dirname(self.data), mode=0o700)
        os.mkfifo(self.data, 0o600)
        started = time.monotonic()
        with self.assertRaisesRegex(files.Refused, "not a regular file"):
            files.read_projects(self.data)
        self.assertLess(time.monotonic() - started, 2)

    def test_refuses_a_file_others_can_write(self):
        self.put(mode=0o620)
        with self.assertRaisesRegex(files.Refused, "others can write"):
            files.read_projects(self.data)

    def test_refuses_a_folder_others_can_write(self):
        self.put()
        os.chmod(os.path.dirname(self.data), 0o770)
        with self.assertRaisesRegex(files.Refused, "others can write"):
            files.read_projects(self.data)

    def test_refuses_a_file_with_another_name(self):
        self.put()
        os.link(self.data, os.path.join(self.home, "second-name.json"))
        with self.assertRaisesRegex(files.Refused, "more than one link"):
            files.read_projects(self.data)

    def test_refuses_a_file_past_its_cap(self):
        self.put(b"{" + b" " * files.PROJECTS_CAP + b"}")
        with self.assertRaisesRegex(files.Refused, "bigger than"):
            files.read_projects(self.data)

    def test_keeps_to_your_home_folder(self):
        for path in ("/tmp/projects.json", "/etc/passwd", self.home + "/../x.json", "relative.json", self.home):
            with self.assertRaises(files.Refused, msg=path):
                files.read_projects(path)

    def test_reads_the_theme_colors(self):
        theme = os.path.join(self.home, files.THEME)
        os.makedirs(os.path.dirname(theme), mode=0o700)
        with open(theme, "w") as f:
            f.write('blue = "#7aa2f7"\n')
        os.chmod(theme, 0o644)
        self.assertEqual(files.read_theme(), b'blue = "#7aa2f7"\n')

    # ---- writing

    def test_writes_for_your_eyes_only(self):
        files.write_projects(self.data, DOC)
        self.assertEqual(files.read_projects(self.data), DOC)
        self.assertEqual(stat.S_IMODE(os.stat(self.data).st_mode), 0o600)
        folder = os.path.dirname(self.data)
        self.assertEqual(stat.S_IMODE(os.stat(folder).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(folder)).st_mode), 0o700)

    def test_replaces_atomically_and_leaves_no_temp_file(self):
        self.put(mode=0o644)
        files.write_projects(self.data, b'{"version": 1, "projects": []}')
        self.assertEqual(files.read_projects(self.data), b'{"version": 1, "projects": []}')
        self.assertEqual(stat.S_IMODE(os.stat(self.data).st_mode), 0o600, "the new file is yours only")
        self.assertEqual(sorted(os.listdir(os.path.dirname(self.data))), ["projects.json"])

    def test_refuses_anything_but_a_json_object(self):
        for data in (b"not json", b"[1, 2]", b"\xff\xfe", b'"text"'):
            with self.assertRaises(files.Refused, msg=data):
                files.write_projects(self.data, data)
        self.assertFalse(os.path.exists(self.data))

    def test_refuses_input_past_its_cap(self):
        with self.assertRaisesRegex(files.Refused, "bigger than"):
            files.write_projects(self.data, b"{" + b" " * files.PROJECTS_CAP + b"}")

    def test_never_writes_through_a_link(self):
        target = os.path.join(self.home, "target.json")
        with open(target, "wb") as f:
            f.write(b"keep")
        os.makedirs(os.path.dirname(self.data), mode=0o700)
        os.symlink(target, self.data)
        with self.assertRaisesRegex(files.Refused, "not a file of yours"):
            files.write_projects(self.data, DOC)
        with open(target, "rb") as f:
            self.assertEqual(f.read(), b"keep")

    def test_never_creates_folders_outside_your_home(self):
        with self.assertRaises(files.Refused):
            files.write_projects("/tmp/hillchart-should-not-exist/projects.json", DOC)
        self.assertFalse(os.path.exists("/tmp/hillchart-should-not-exist"))

    def test_clears_its_own_stale_temp_files_only(self):
        self.put()
        folder = os.path.dirname(self.data)
        stale = os.path.join(folder, ".projects.json.0123456789abcdef.tmp")
        fresh = os.path.join(folder, ".projects.json.fedcba9876543210.tmp")
        foreign = os.path.join(folder, "notes.tmp")
        for path in (stale, fresh, foreign):
            with open(path, "w") as f:
                f.write("x")
        old = time.time() - 600
        os.utime(stale, (old, old))
        os.utime(foreign, (old, old))
        files.write_projects(self.data, DOC)
        left = sorted(os.listdir(folder))
        self.assertNotIn(os.path.basename(stale), left)
        self.assertIn(os.path.basename(fresh), left, "a write in progress keeps its file")
        self.assertIn("notes.tmp", left, "files it didn't make stay")

    # ---- handing text to the shell

    def test_prints_plain_ascii(self):
        out = files.as_ascii("Café ✓".encode(), 100)
        out.decode("ascii")
        self.assertEqual(json.loads(out), "Café ✓")

    def test_exit_codes(self):
        self.put()
        real_stdout, real_stderr = sys.stdout, sys.stderr
        sys.stdout = io.TextIOWrapper(io.BytesIO())
        sys.stderr = io.StringIO()
        try:
            self.assertEqual(files.main(["x", "read", self.data]), 0)
            self.assertEqual(files.main(["x", "read", self.data + ".nope"]), 3)
            self.assertEqual(files.main(["x", "read", "/tmp/x.json"]), 4)
            self.assertEqual(files.main(["x"]), 2)
            self.assertEqual(files.main(["x", "theme", "extra"]), 2)
        finally:
            sys.stdout, sys.stderr = real_stdout, real_stderr


if __name__ == "__main__":
    unittest.main()
