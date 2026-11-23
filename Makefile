ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export PATH := $(HOME)/flutter/bin:$(HOME)/pg/bin:$(PATH)
export LD_LIBRARY_PATH := $(HOME)/pg/lib$(if $(LD_LIBRARY_PATH),:$(LD_LIBRARY_PATH))

.PHONY: doctor research-mh dev dev-stop build start check verify audit-data test-go test-dart miniapp-build miniapp-test miniapp-preview miniapp-upload

doctor:
	python3 tools/doctor.py

research-mh:
	python3 tools/content/build_fixtures.py
	cd services/api && go run ./cmd/mhbuddy pack
	python3 tools/research/research_mh.py

dev:
	bash tools/dev.sh start

dev-stop:
	bash tools/dev.sh stop

build:
	cd apps/web && flutter build web --release --pwa-strategy=none
	cd services/api && go build -o $(ROOT)/.run/mhbuddy ./cmd/mhbuddy

start:
	bash tools/dev.sh start

check:
	@test -n "$(TASK)" || (echo "usage: make check TASK=T00" && exit 2)
	@echo "task $(TASK)"
	@case "$(TASK)" in \
	  T00) $(MAKE) doctor research-mh && cd services/api && go test ./internal/contract ;; \
	  T01) cd packages/catalog && dart test ;; \
	  T02) cd services/api && go test ./internal/api ;; \
	  T03) cd apps/web && flutter test ;; \
	  T04) cd packages/builds && dart test ;; \
	  T05) cd packages/player_store && dart test ;; \
	  T06|T07|T08|T10) cd tests/acceptance && npm install --silent && npm test ;; \
	  T09) $(MAKE) audit-data ;; \
	  T11) echo "T11 needs the owner to Publish in Cursor Apps"; exit 2 ;; \
	  *) echo "unknown task $(TASK)"; exit 2 ;; \
	esac

test-go:
	cd services/api && go test ./...

test-dart:
	cd packages/catalog && dart test
	cd packages/builds && dart test
	cd packages/player_store && dart test
	cd apps/web && flutter test

verify: doctor research-mh test-go test-dart
	@echo "verify: contracts, Go API, catalog, solver, player store, Flutter locale tests"

audit-data:
	@echo "audit-data: no formal content manifest was provided"
	@echo "fixture packs are signed under content/fixtures/manifests and are not an accuracy audit"
	@exit 1

miniapp-build:
	node apps/miniapp/scripts/build.js

miniapp-test: miniapp-build
	node --test apps/miniapp/test/*.js

miniapp-preview:
	node apps/miniapp/scripts/upload.js preview

miniapp-upload:
	node apps/miniapp/scripts/upload.js upload
