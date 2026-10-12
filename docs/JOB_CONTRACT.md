# QF job contract

A job is a directory, encrypted with `tools/qfcrypt.sh` and committed as `jobs/<job_id>.tar.gpg.b64`.
Inside the directory:

- `run.sh` — entry point, run with `bash run.sh` from the job directory (`work/` on the runner).
- `requirements.txt` — optional, installed with pip before `run.sh`.
- anything else the job needs (code, small data). Keep payloads small; pull large public data inside `run.sh`.

Runtime conventions (the runner enforces them):

- Write results to `out/`. Everything in `out/` is encrypted and uploaded as an artifact `out-<job_id>-hop<n>`,
  and also committed to `results/<job_id>/hop<n>.out.tar.gpg.b64` when the job's results total under 30 MB.
- Write checkpoints to `ckpt/`. If `ckpt/` is non-empty at start, you are being resumed: load it.
- Environment: `QF_JOB_ID`, `QF_HOP` (0, 1, 2, ...), `QF_TIME_BUDGET` (seconds for this hop).
- Stopping: `run.sh` is killed with SIGTERM when the time budget expires (SIGKILL 120 s later), and the job is
  treated as "continue". Save checkpoints periodically, or trap SIGTERM and save immediately.
- To hand off voluntarily, write your checkpoint, `touch ckpt/.continue`, and exit 0.
- Exit 0 without `ckpt/.continue` means "done" — no further hop. Non-zero exit without `.continue` means "failed".

Limits: one hop runs at most 350 min (GitHub's job limit is 6 h); default `time_budget` is 19200 s (5 h 20 min);
default `max_hops` is 12 (about 64 h of compute per job). Public repositories get unlimited Actions minutes on
standard runners (currently 4 vCPU, 16 GB RAM, no GPU).

Notes from runner tests (2026-10-12):

- `run.sh` must start the main process with `exec` (or run it in the background, `trap` TERM to forward the
  signal, and `wait` for it). `timeout` sends SIGTERM to the whole process group; a bash that merely runs a child
  process dies immediately on SIGTERM, `timeout` returns 124 at that instant, and the runner starts packaging
  `ckpt/` while the child is still writing its checkpoint. With `exec`, `timeout` waits for the main process to
  exit after it has saved; the exit code is still 124 and the status is still "continue".
- If the main process ignores SIGTERM, `timeout` sends SIGKILL 120 s later and returns 137; the runner then marks
  the hop "failed" and does not start the next hop (observed in run 38264098846, whose `run.sh` used `exec`). The
  misleading outcome appears only without `exec`: bash dies on SIGTERM, `timeout` returns 124 at that instant, the
  orphaned main process keeps writing, and the runner packages a half-written `ckpt/` and still reports "continue"
  (observed in run 38263105661). `exec` is therefore mandatory not only so that the hop ends cleanly, but because
  it lets a contract violation (not handling SIGTERM) be reported as "failed" instead of being masked as a
  successful hop. Checkpoints must be written atomically (temporary file, fsync, rename) so that a kill in the
  middle of a write leaves the previous checkpoint intact, and SIGTERM must be handled (set a flag, save at the
  next safe point, exit) so that the work since the last periodic checkpoint is not lost.

Log policy (2026-10-12):

- Nothing that `run.sh` prints appears in the public Actions log. The workflow records only counts: the number of
  files and kilobytes of the unpacked payload, and the number of lines and bytes of the run log. The complete
  stdout/stderr of `run.sh` is saved as `out/run_log.hop<n>.txt` inside the encrypted output of that hop.
- Debugging therefore means: fetch and decrypt the hop output (status file + `hop<n>.out.tar.gpg.b64`, or the
  `out-<job_id>-hop<n>` artifact), then read `out/run_log.hop<n>.txt`. A failed hop still packages its `out/`.
- Keep every name inside the payload (directories, files, job ids) neutral and free of project-specific words.
  Earlier versions of the workflow listed the unpacked payload in the public log; the listing is gone, but names
  should not depend on that.

Paired runs (2026-10-12):

- When several configurations are compared pairwise under one seed, all of them must run inside the same job and
  the same hop: the unit of work is "one seed x all configurations", not "one configuration x many seeds". Results
  written with `qf_runtime.writeResult` record `run_id`, `hostname`, `cpu_model`, the BLAS library, library versions,
  the backend platform version, thread environment variables and a `machine_fingerprint` (CPU model + binaries), so
  this can be checked from the result files alone: paired results must share `run_id` and `hostname`, have equal
  `machine_fingerprint`, and have `hops` == 1.
- A run that was cut by the time budget (rc 124) and finished in a later hop ran on more than one machine. Its result
  carries `cross_machine: true` and must not enter a paired comparison. Size paired jobs so that one hop finishes them.
- `run.sh` should start with a short speed probe. When the projected time does not fit the hop budget
  (`QF_TIME_BUDGET`), it writes `slow-machine` as the first line of `out/STATUS` (followed by one JSON line with the
  measured step time, the projected time and the budget) and exits with code 75 before doing real work. The runner
  reports the hop as failed and packages `out/`; the dispatcher re-dispatches under a new job id, which lands on
  another machine. The status string `slow-machine` and exit code 75 are shared by every tool that reads results.

Job ids and public names (2026-10-12):

- Job ids carry no meaning. A regular job id is `j` followed by the UTC time of dispatch as `YYMMDDhhmm` (10 digits),
  optionally followed by 2 or 4 more digits when several jobs are created at once (for example `j2610121640`,
  `j261012164001`). An infrastructure self-test uses `t` followed by the same digits (for example `t2610121750`).
  Older self-tests used plain words as ids; those are deprecated, and the packaging tool only accepts them with a
  warning. Everything else that appears on the public side derives from the id: payload files `jobs/<id>.tar.gpg.b64`,
  result files `results/<id>/...`, commit messages `jobs: add <id> [<id> ...]` and `results: <id> hop <n> (<status>)`,
  and the workflow inputs. No other words belong in file names or commit messages.
