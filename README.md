# FastAPI CI/CD — two ways

One FastAPI app, two complete pipelines wired up side by side:

| | CI (validate PRs) | CD (ship on merge) | Registry | Runs on |
|---|---|---|---|---|
| **Way 1 — GitHub** | GitHub Actions (`.github/workflows/ci.yml`) | GitHub Actions (`.github/workflows/cd.yml`) | GHCR (`ghcr.io`) | anywhere you run the image |
| **Way 2 — GCP** | Cloud Build (`cloudbuild.ci.yaml`) | Cloud Build (`cloudbuild.yaml`) | Artifact Registry | Cloud Run |

The app, tests, and Dockerfile are **shared** — only the pipeline differs.

---

## The mental model (read this once)

- **CI = "does this change pass?"** You open **one** PR from your branch. Every
  push to that branch re-runs CI (lint + tests) on that PR. A PR is **not**
  created on every push — it's opened once, then updated.
- **CD = "ship it."** Runs only *after* the PR is approved, CI is green, and the
  branch is **merged to `main`**. That merge is the trigger that rebuilds the
  image and deploys.

```
feature branch ──push──▶ PR opened ──push,push…──▶ CI runs each time
                                          │
                          approve + CI green
                                          │
                                          ▼
                                   merge to main ──▶ CD builds image ──▶ deploys
```

---

## 0. Project layout

```
fastapi-cicd/
├── app/main.py               # the API you edit
├── tests/test_main.py        # what CI runs
├── requirements.txt          # runtime deps (go into the image)
├── requirements-dev.txt      # + pytest / httpx / ruff for CI
├── Dockerfile                # listens on $PORT (Cloud Run friendly)
├── Makefile                  # make test / run / docker-build ...
├── .github/workflows/
│   ├── ci.yml                # WAY 1 - CI
│   └── cd.yml                # WAY 1 - CD -> GHCR
├── cloudbuild.ci.yaml        # WAY 2 - CI
├── cloudbuild.yaml           # WAY 2 - CD -> Cloud Run
└── gcp/setup.sh              # WAY 2 - one-time infra setup
```

---

## 1. Run & test locally first (do this before anything else)

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt

make run        # -> http://localhost:8000/docs   (interactive Swagger UI)
make test       # pytest -v      (identical to what CI runs)
make lint       # ruff check .
```

Test the container the pipeline actually ships:

```bash
make docker-build            # docker build -t demo-api:local .
make docker-run              # maps localhost:8000 -> container's :8080
curl localhost:8000/health   # {"status":"ok"}
curl localhost:8000/version  # {"version":"1.0.0"}
```

### Run the GitHub workflow locally with `act` (optional but nice)

[`act`](https://github.com/nektos/act) executes your Actions YAML in Docker, so
you can validate CI without pushing:

```bash
# macOS: brew install act    (other OSes: see the act README)
act pull_request                 # runs ci.yml exactly like a PR would
```

> `act` mirrors CI (lint + test) well. It does **not** faithfully reproduce the
> CD push to GHCR (needs real credentials), so validate CI with `act` and check
> the image with plain `docker build`. Safe local loop: **`make test` →
> `make docker-build` → `act pull_request`**, then push.

---

## 2. The Git flow you'll actually do (both ways)

```bash
git checkout -b feature/add-price-filter
# ... edit app/main.py ...
git add -A
git commit -m "Add price filter endpoint"
git push -u origin feature/add-price-filter
```

Then on GitHub: **open a Pull Request** into `main`.

- The PR page shows a **Checks** section. That's CI running.
  - Way 1: the `CI` workflow (Actions tab).
  - Way 2: the `ci-pr` Cloud Build trigger (a check named like `ci-pr (PROJECT)`).
- Push more commits → the check re-runs automatically on the same PR.
- Get an approval, wait for the check to go ✅, then **Merge**.
- The merge to `main` fires **CD** and your change deploys.

Want to *watch it fail* first? Break a test (change an assert), push, and see
the PR check go red — that's CI doing its job.

---

## Way 1 — All GitHub (Actions + GHCR)

**Setup: essentially none.** Push the repo to GitHub and Actions runs on its own.

1. Create the repo and push:
   ```bash
   git init && git add -A && git commit -m "initial"
   git branch -M main
   git remote add origin https://github.com/YOUR_USER/fastapi-cicd.git
   git push -u origin main
   ```
2. Open a PR (as above). **`ci.yml`** runs lint + tests — watch it in the
   **Actions** tab or the PR's Checks section.
3. Merge to `main`. **`cd.yml`** builds the image and pushes it to
   `ghcr.io/YOUR_USER/fastapi-cicd`.
   - Uses the built-in `GITHUB_TOKEN` — **no secrets to configure.**
   - If the package is private, allow pulls under repo/org **Packages** settings.
4. Pull & run the shipped image anywhere Docker runs:
   ```bash
   docker pull ghcr.io/YOUR_USER/fastapi-cicd:latest
   docker run --rm -p 8000:8080 ghcr.io/YOUR_USER/fastapi-cicd:latest
   ```

To have CD also *run* the image on your own server, uncomment the SSH deploy
block at the bottom of `cd.yml` and add `SERVER_HOST`, `SERVER_USER`, `SSH_KEY`
as repo secrets (**Settings → Secrets and variables → Actions**).

---

## Way 2 — All GCP (Cloud Build + Artifact Registry + Cloud Run)

Here **Cloud Build** is the CI/CD engine (not Actions), and the app runs on
**Cloud Run**.

### One-time infra

```bash
gcloud auth login
PROJECT_ID=your-project-id ./gcp/setup.sh
```

That script enables the APIs, creates the Artifact Registry repo, and grants the
build service account the deploy roles (`run.admin`,
`iam.serviceAccountUser`, `artifactregistry.writer`).

### Connect GitHub + create the two triggers

1. **Connect the repo** (one-time OAuth, easiest in the console):
   **Cloud Build → Repositories → Connect repository → GitHub**.
2. Create the triggers (edit `--repo-owner` / `--repo-name`):
   ```bash
   # CI: validate every PR to main
   gcloud builds triggers create github \
     --name=ci-pr \
     --repo-owner=YOUR_GH_USER --repo-name=fastapi-cicd \
     --pull-request-pattern='^main$' \
     --build-config=cloudbuild.ci.yaml

   # CD: build + deploy on merge to main (deploys the commit SHA)
   gcloud builds triggers create github \
     --name=cd-main \
     --repo-owner=YOUR_GH_USER --repo-name=fastapi-cicd \
     --branch-pattern='^main$' \
     --build-config=cloudbuild.yaml \
     --substitutions='_TAG=$SHORT_SHA'
   ```
   > These are the classic GitHub-App (1st-gen) trigger commands. If you
   > connected the repo via Cloud Build's newer 2nd-gen (Developer Connect)
   > repositories, replace `--repo-owner/--repo-name` with
   > `--repository=<full resource name>` and add `--region`.

### What happens

- Open a PR → the **`ci-pr`** trigger runs `cloudbuild.ci.yaml` (lint + test).
  The result posts back to the PR as a check.
- Merge to `main` → the **`cd-main`** trigger runs `cloudbuild.yaml`:
  test → build → push to Artifact Registry → **deploy to Cloud Run**.
- Grab your live URL:
  ```bash
  gcloud run services describe demo-api --region=us-central1 \
    --format='value(status.url)'
  curl "$(gcloud run services describe demo-api --region=us-central1 --format='value(status.url)')/version"
  ```

### Deploy once by hand (no PR needed, to prove the plumbing)

```bash
gcloud builds submit --config=cloudbuild.yaml .
```

> **Auth note:** the service is deployed with `--allow-unauthenticated` so you
> can curl it. Remove that flag in `cloudbuild.yaml` to require IAM auth.

---

## 3. A concrete change to try end-to-end

Add a filter endpoint in `app/main.py`:

```python
@app.get("/items")
def list_items(max_price: float | None = None):
    items = [{"item_id": k, **v} for k, v in ITEMS.items()]
    if max_price is not None:
        items = [i for i in items if i["price"] <= max_price]
    return items
```

Add a test in `tests/test_main.py`:

```python
def test_list_items_filter():
    resp = client.get("/items", params={"max_price": 10})
    assert resp.status_code == 200
    assert [i["item_id"] for i in resp.json()] == [1]
```

Then:

```bash
make test                      # green locally
git checkout -b feature/list-items
git commit -am "Add /items list + price filter"
git push -u origin feature/list-items
# open PR  -> CI runs (Way 1: Actions | Way 2: Cloud Build)
# approve + green -> merge -> CD ships it
```

- **Way 1:** new image at `ghcr.io/YOUR_USER/fastapi-cicd:latest`.
- **Way 2:** Cloud Run rolls out the new revision; `/items?max_price=10` is live.

---

## Troubleshooting

- **`ModuleNotFoundError: httpx` in tests** — install dev deps:
  `pip install -r requirements-dev.txt` (httpx backs FastAPI's TestClient).
- **Way 1: `denied` pushing to GHCR** — the `cd.yml` job needs
  `permissions: packages: write` (already set). For a private package, check
  org/repo **Packages** visibility.
- **Way 2: build can't deploy (`PERMISSION_DENIED`)** — re-run `gcp/setup.sh`;
  the build service account needs `run.admin` + `iam.serviceAccountUser`.
- **Way 2: Cloud Run says "container failed to listen on PORT"** — the app must
  bind `$PORT`. The Dockerfile already does (`--port ${PORT}`, default 8080).
- **PR check never appears (Way 2)** — the GitHub repo isn't connected to Cloud
  Build yet, or the trigger's `--pull-request-pattern` doesn't match `main`.
