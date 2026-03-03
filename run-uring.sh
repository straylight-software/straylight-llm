#!/usr/bin/env bash
# Run straylight-llm with io_uring backend
#
# Environment variables required:
#   ANTHROPIC_API_KEY  - Your Anthropic API key
#   BASETEN_API_KEY    - Your Baseten API key (optional)
#   OPENROUTER_API_KEY - Your OpenRouter API key (optional)
#   VENICE_API_KEY     - Your Venice API key (optional)
#
# Usage:
#   USE_URING=1 ./run-uring.sh       # Single-core io_uring
#   USE_URING_MC=1 ./run-uring.sh    # Multi-core io_uring (SO_REUSEPORT)
#
# Note: Ensure API keys are set in environment or .env file, never in this script.

set -euo pipefail

# Default to single-core io_uring if not specified
: "${USE_URING:=1}"
export USE_URING

# Find the binary
BINARY="./gateway/dist-newstyle/build/x86_64-linux/ghc-9.12.2/straylight-llm-0.1.0.0/x/straylight-llm/build/straylight-llm/straylight-llm"

if [[ ! -x "$BINARY" ]]; then
	echo "Binary not found. Building..."
	nix develop --command bash -c "cd gateway && cabal build"
fi

exec "$BINARY"
