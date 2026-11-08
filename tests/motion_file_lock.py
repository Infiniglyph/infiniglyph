"""Exercise the live worker against real Windows IPC file-sharing conflicts."""
import ctypes
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(sys.platform == "win32", "Windows file-sharing regression")
class MotionFileLockTest(unittest.TestCase):
    def test_request_and_response_locks_are_retried(self):
        root = Path(__file__).resolve().parents[1]
        rag_root = root.parent / "rag"
        if not (rag_root / "context_builder.py").is_file():
            rag_root = root / "vendor" / "ted_rag"
        cache = root / ".godot" / "ipc-verification"
        cache.mkdir(parents=True, exist_ok=True)
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.CreateFileW.restype = ctypes.c_void_p
        kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32,
            ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32,
            ctypes.c_uint32, ctypes.c_void_p]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        with tempfile.TemporaryDirectory(dir=cache) as folder:
            session = Path(folder)
            request = session / "request.json"
            response = session / "response.json"

            def send(identifier):
                payload = json.dumps({"id": identifier, "context": {
                    "speed": 1, "boost": 1, "grounded": True}})
                deadline = time.monotonic() + 3
                while True:
                    try:
                        request.write_text(payload, encoding="utf-8")
                        return
                    except PermissionError:
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(0.025)

            def await_reply(identifier):
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    self.assertIsNone(worker.poll(), "Live worker terminated")
                    try:
                        reply = json.loads(response.read_text(encoding="utf-8"))
                        if reply["id"] == identifier:
                            self.assertEqual(reply["profiles"][0]["id"], "sprint")
                            return
                    except (FileNotFoundError, PermissionError, json.JSONDecodeError):
                        pass
                    time.sleep(0.025)
                self.fail("Worker did not return the new pose after unlocking")

            send(1)
            worker = subprocess.Popen([sys.executable,
                str(root / "tools" / "motion_retrieval.py"),
                "--session", str(session), "--corpus",
                str(root / "data" / "motion_constraints.json"),
                "--rag-root", str(rag_root)],
                creationflags=subprocess.CREATE_NO_WINDOW,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                await_reply(1)
                for path, identifier in [(request, 2), (response, 3)]:
                    handle = kernel.CreateFileW(str(path), 0x80000000, 0,
                        None, 3, 0, None)
                    self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
                    try:
                        if path == response:
                            send(identifier)
                        time.sleep(0.25)
                        self.assertIsNone(worker.poll(),
                            "Worker stopped during an exclusive file lock")
                    finally:
                        kernel.CloseHandle(handle)
                    if path == request:
                        send(identifier)
                    await_reply(identifier)
            finally:
                (session / "stop").touch()
                worker.communicate(timeout=3)


if __name__ == "__main__":
    unittest.main()
