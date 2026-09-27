.PHONY: install run test lint docker-build docker-run act-ci clean

install:      ## install dev + runtime deps
	pip install -r requirements-dev.txt

run:          ## run the API locally with reload on :8000
	uvicorn app.main:app --reload --port 8000

test:         ## run the test suite (what CI runs)
	pytest -v

lint:         ## run the linter (what CI runs)
	ruff check .

docker-build: ## build the production image
	docker build -t demo-api:local .

docker-run:   ## run the image; maps localhost:8000 -> container :8080
	docker run --rm -p 8000:8080 demo-api:local

act-ci:       ## run the GitHub CI workflow locally (needs nektos/act + docker)
	act pull_request

clean:
	rm -rf .pytest_cache .ruff_cache __pycache__ app/__pycache__ tests/__pycache__
