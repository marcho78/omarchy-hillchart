import QtQuick
import Quickshell
import Quickshell.Io

// Runs one command from an argument list, by absolute path and never through
// a shell, then reports once: finished(code, output).
//
// The command runs as the leader of its own process group (setsid), so a
// deadline, an output overrun or Hill Chart unloading ends it together with
// anything it started. Output is counted in bytes as it arrives, stdout and
// stderr together, and nothing past the budget is kept. The file helper
// prints plain ASCII, so its output can be taken in as it arrives.
//
// start(argv, input) hands the command `input` on stdin and closes it.
Item {
  id: run

  property int timeoutMs: 5000
  property int maxBytes: 64 * 1024
  readonly property bool running: proc.running

  // code: the command's exit status, or -1 when it was stopped (deadline or
  // overrun). output: stdout when it exited 0, else stderr or why it stopped.
  signal finished(int code, string output)

  property string _out: ""
  property string _err: ""
  property int _seen: 0
  property string _failed: ""
  property string _input: ""
  property bool _hasInput: false

  function start(argv, input) {
    if (proc.running) return false
    _out = ""
    _err = ""
    _seen = 0
    _failed = ""
    _hasInput = input !== undefined && input !== null
    _input = _hasInput ? String(input) : ""
    proc.stdinEnabled = _hasInput
    proc.command = ["/usr/bin/setsid", "--wait"].concat(argv)
    proc.running = true
    deadline.restart()
    return true
  }

  function _kill() {
    if (proc.processId > 0) Quickshell.execDetached(["/usr/bin/kill", "-KILL", "--", "-" + proc.processId])
  }

  function _fail(reason) {
    if (_failed) return
    _failed = reason
    _kill()
  }

  // The UTF-8 bytes `text` came from.
  function _bytes(text) {
    if (!/[^\u0000-\u007f]/.test(text)) return text.length
    var n = text.length
    for (let i = 0; i < text.length; i++) {
      let c = text.charCodeAt(i)
      if (c >= 0x80) n += c >= 0x800 && (c < 0xd800 || c > 0xdfff) ? 2 : 1
    }
    return n
  }

  function _take(data, isError) {
    if (_failed) return
    _seen += _bytes(data)
    if (_seen > maxBytes) {
      _fail("printed more than " + maxBytes + " bytes")
      return
    }
    if (isError) {
      if (_err.length < 2000) _err += data
    } else {
      _out += data
    }
  }

  Component.onDestruction: if (proc.running) _kill()

  Timer {
    id: deadline
    interval: run.timeoutMs
    onTriggered: run._fail("took longer than " + run.timeoutMs + "ms")
  }

  Process {
    id: proc
    onStarted: {
      if (!run._hasInput) return
      write(run._input)
      run._input = ""
      // Closes stdin: the command sees the end of its input.
      stdinEnabled = false
    }
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { run._take(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { run._take(data, true) }
    }
    onExited: function(exitCode) {
      deadline.stop()
      var code = run._failed ? -1 : exitCode
      var out = code === 0 ? run._out : (run._failed || run._err.trim() || ("exited with " + exitCode))
      run._out = ""
      run._err = ""
      run.finished(code, out)
    }
  }
}
