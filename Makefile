IMAGE ?= valheim-arm64:local
PLATFORM ?= linux/arm64

.PHONY: build validate

build:
	docker buildx build --platform "$(PLATFORM)" --tag "$(IMAGE)" --load .

validate:
	./scripts/validate.sh
