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
