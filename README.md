# QF

A GitHub Actions job runner for long CPU jobs, with encrypted payloads and self-continuing runs.

- `.github/workflows/run-job.yml` — decrypts a payload from `jobs/`, runs it under a time budget, saves a
  checkpoint and dispatches its own successor run until the payload reports completion (`docs/JOB_CONTRACT.md`).
- `.github/workflows/selftest.yml` — checks the runner, the crypto round trip and the run chain.
- `tools/qfcrypt.sh`, `tools/qfjob.sh` — encryption and payload packing / result fetching helpers.
- `jobs/` — encrypted payloads; `results/` — encrypted outputs committed back by the runner.

Payloads and results are encrypted with gpg (AES-256); the key is the repository secret `QF_ACTION_KEY`.
