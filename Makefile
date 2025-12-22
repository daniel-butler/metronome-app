.PHONY: test test-unit test-ui clean help

# Default simulator
SIMULATOR ?= iPhone 17
SCHEME = MetronomeApp
DESTINATION = 'platform=iOS Simulator,name=$(SIMULATOR)'
PROJECT_DIR = MetronomeApp

help:
	@echo "Metronome App - Make Commands"
	@echo ""
	@echo "Available commands:"
	@echo "  make test        - Run both unit and UI tests"
	@echo "  make test-unit   - Run unit tests only"
	@echo "  make test-ui     - Run UI tests only"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make help        - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  SIMULATOR=<name> - Specify simulator (default: iPhone 17)"
	@echo ""
	@echo "Example:"
	@echo "  make test SIMULATOR='iPhone 17 Pro'"

test: test-unit test-ui

test-unit:
	@echo "Running unit tests on $(SIMULATOR)..."
	@cd $(PROJECT_DIR) && xcodebuild test \
		-scheme $(SCHEME) \
		-destination $(DESTINATION) \
		-only-testing:MetronomeAppTests \
		| xcpretty || cd $(PROJECT_DIR) && xcodebuild test \
		-scheme $(SCHEME) \
		-destination $(DESTINATION) \
		-only-testing:MetronomeAppTests

test-ui:
	@echo "Running UI tests on $(SIMULATOR)..."
	@cd $(PROJECT_DIR) && xcodebuild test \
		-scheme $(SCHEME) \
		-destination $(DESTINATION) \
		-only-testing:MetronomeAppUITests \
		| xcpretty || cd $(PROJECT_DIR) && xcodebuild test \
		-scheme $(SCHEME) \
		-destination $(DESTINATION) \
		-only-testing:MetronomeAppUITests

clean:
	@echo "Cleaning build artifacts..."
	@cd $(PROJECT_DIR) && xcodebuild clean -scheme $(SCHEME)
	@rm -rf ~/Library/Developer/Xcode/DerivedData/MetronomeApp-*
	@echo "Clean complete!"
