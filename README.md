# vps-f3-test-app

Disposable application used only to validate the VPS deploy pipeline
(phase F3): GitHub Actions builds and tests the image, publishes it to GHCR,
records provenance, and — after a manual approval in the `production`
environment — asks the VPS deploy gateway to run `deploy <sha> <digest>`.

It is **not** a product and has no domain. Endpoints: `/` (version) and
`/healthz`. The container healthcheck runs `/app -healthcheck`.
