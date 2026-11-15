.PHONY: lint test build clean help

help: ## Show help for each target
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

lint: ## Run Kotlin & Android linters (ktlint + lint)
	./gradlew ktlintCheck
	./gradlew lintDebug

format: ## Auto-format Kotlin files using ktlint
	./gradlew ktlintFormat

test: ## Run JVM unit tests
	./gradlew testDebugUnitTest

build: ## Build debug APK
	./gradlew assembleDebug

clean: ## Clean build cache
	./gradlew clean
