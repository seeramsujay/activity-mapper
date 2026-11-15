.PHONY: lint format test build clean help

help: ## Show help for each target
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

lint: ## Run Kotlin linter (ktlint)
	ktlint "app/src/**/*.kt"

format: ## Auto-format Kotlin files using ktlint
	ktlint --format "app/src/**/*.kt"

test: ## Run JVM unit tests
	./gradlew testDebugUnitTest

build: ## Build debug APK
	./gradlew assembleDebug

clean: ## Clean build cache
	./gradlew clean
