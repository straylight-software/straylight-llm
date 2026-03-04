#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                           // straylight-llm demo //
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Demo script showcasing straylight-llm gateway with io_uring backend
#
# Usage:
#   ./scripts/demo.sh              # Run demo
#   ./scripts/demo.sh --record     # Record with wf-recorder
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Config
GATEWAY_URL="http://localhost:8080"
DEMO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

print_banner() {
	echo -e "${CYAN}"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "                         // straylight-llm //"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo -e "${NC}"
	echo -e "${MAGENTA}  \"The sky above the port was the color of television,"
	echo -e "   tuned to a dead channel.\"${NC}"
	echo ""
	echo -e "  ${BOLD}OpenAI-compatible LLM gateway with io_uring, effect tracking,"
	echo -e "  discharge proofs, and provider fallback chain.${NC}"
	echo ""
}

print_section() {
	echo ""
	echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
	echo -e "${BLUE}  $1${NC}"
	echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
	echo ""
}

print_step() {
	echo -e "${GREEN}▶${NC} ${BOLD}$1${NC}"
}

print_result() {
	echo -e "${YELLOW}$1${NC}"
}

# Check if gateway is running
check_gateway() {
	print_step "Checking gateway health..."
	if curl -s "$GATEWAY_URL/health" >/dev/null 2>&1; then
		local health=$(curl -s "$GATEWAY_URL/health")
		echo -e "${GREEN}✓ Gateway is running${NC}"
		echo "$health" | jq -C '.' 2>/dev/null || echo "$health"
		return 0
	else
		echo -e "${RED}✗ Gateway not running at $GATEWAY_URL${NC}"
		return 1
	fi
}

# List available models
list_models() {
	print_section "Available Models"
	print_step "Fetching models from /v1/models..."

	local models=$(curl -s "$GATEWAY_URL/v1/models")
	local count=$(echo "$models" | jq '.data | length' 2>/dev/null || echo "?")

	echo -e "${GREEN}Found $count models${NC}"
	echo ""
	echo "$models" | jq -C '.data[:10] | .[] | {id, owned_by}' 2>/dev/null || echo "$models"

	if [ "$count" -gt 10 ]; then
		echo -e "${CYAN}... and $(($count - 10)) more${NC}"
	fi
}

# Send a chat completion request
send_chat() {
	local model="$1"
	local prompt="$2"
	local max_tokens="${3:-100}"

	print_step "Sending request to $model..."
	echo -e "${CYAN}Prompt: ${NC}$prompt"
	echo ""

	local start_time=$(date +%s%N)

	local response=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d "{
            \"model\": \"$model\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
            \"max_tokens\": $max_tokens
        }")

	local end_time=$(date +%s%N)
	local duration_ms=$(((end_time - start_time) / 1000000))

	# Check for error
	if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
		echo -e "${RED}Error:${NC}"
		echo "$response" | jq -C '.error' 2>/dev/null
		return 1
	fi

	# Extract response
	local content=$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null)
	local usage=$(echo "$response" | jq -C '.usage' 2>/dev/null)
	local request_id=$(echo "$response" | jq -r '.id' 2>/dev/null)

	echo -e "${GREEN}Response (${duration_ms}ms):${NC}"
	echo -e "${YELLOW}$content${NC}"
	echo ""
	echo -e "${CYAN}Usage:${NC} $usage"
	echo -e "${CYAN}Request ID:${NC} $request_id"

	# Try to fetch discharge proof
	if [ "$request_id" != "null" ] && [ -n "$request_id" ]; then
		echo ""
		print_step "Fetching discharge proof..."
		local proof=$(curl -s "$GATEWAY_URL/v1/proof/$request_id")
		if echo "$proof" | jq -e '.coeffect' >/dev/null 2>&1; then
			echo -e "${GREEN}✓ Discharge proof generated${NC}"
			echo "$proof" | jq -C '{coeffect: .coeffect, signature: .signature[:32], hash: .hash[:32]}' 2>/dev/null
		else
			echo -e "${YELLOW}Proof not found (may be cached)${NC}"
		fi
	fi
}

# Send streaming request
send_stream() {
	local model="$1"
	local prompt="$2"

	print_step "Streaming from $model..."
	echo -e "${CYAN}Prompt: ${NC}$prompt"
	echo ""

	echo -e "${GREEN}Response:${NC}"
	curl -s -N -X POST "$GATEWAY_URL/v1/chat/completions/stream" \
		-H "Content-Type: application/json" \
		-H "Accept: text/event-stream" \
		-d "{
            \"model\": \"$model\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
            \"max_tokens\": 100,
            \"stream\": true
        }" | while read -r line; do
		if [[ "$line" == data:* ]]; then
			local data="${line#data: }"
			if [ "$data" != "[DONE]" ]; then
				local delta=$(echo "$data" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
				if [ -n "$delta" ]; then
					echo -n -e "${YELLOW}$delta${NC}"
				fi
			fi
		fi
	done
	echo ""
}

# Show SSE events
show_events() {
	print_step "Listening to SSE events (5 seconds)..."
	timeout 5 curl -s -N "$GATEWAY_URL/v1/events" \
		-H "Accept: text/event-stream" | while read -r line; do
		if [[ "$line" == data:* ]]; then
			echo -e "${CYAN}Event:${NC} ${line#data: }"
		fi
	done || true
	echo ""
}

# Run benchmarks
run_benchmarks() {
	print_section "Quick Benchmark"

	print_step "Running 5 sequential requests..."

	local total_time=0
	for i in {1..5}; do
		local start=$(date +%s%N)
		curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
			-H "Content-Type: application/json" \
			-d '{
                "model": "claude-3-5-haiku-20241022",
                "messages": [{"role": "user", "content": "Say just the number '"$i"'"}],
                "max_tokens": 5
            }' >/dev/null
		local end=$(date +%s%N)
		local duration=$(((end - start) / 1000000))
		total_time=$((total_time + duration))
		echo -e "  Request $i: ${GREEN}${duration}ms${NC}"
	done

	local avg=$((total_time / 5))
	echo ""
	echo -e "${BOLD}Average latency: ${GREEN}${avg}ms${NC}"
}

# Main demo
main() {
	print_banner

	# Check if gateway is up
	if ! check_gateway; then
		echo ""
		echo -e "${YELLOW}Starting gateway with io_uring...${NC}"
		echo -e "${CYAN}Run in another terminal: USE_URING=1 ./run-uring.sh${NC}"
		exit 1
	fi

	# List models
	list_models

	# Demo: Fast model (Haiku)
	print_section "Demo 1: Fast Model (Claude 3.5 Haiku)"
	send_chat "claude-3-5-haiku-20241022" "What is 2+2? Answer in one word." 10

	# Demo: Capable model (Sonnet)
	print_section "Demo 2: Capable Model (Claude 3.5 Sonnet)"
	send_chat "claude-3-5-sonnet-20241022" "Explain io_uring in one sentence." 50

	# Demo: Streaming
	print_section "Demo 3: Streaming Response"
	send_stream "claude-3-5-haiku-20241022" "Count from 1 to 5, one number per line."

	# Demo: SSE Events
	print_section "Demo 4: Real-time SSE Events"
	show_events &
	local events_pid=$!
	# Send a request in background to generate events
	send_chat "claude-3-5-haiku-20241022" "Say hello" 5 >/dev/null 2>&1 &
	wait $events_pid 2>/dev/null || true

	# Quick benchmark
	run_benchmarks

	print_section "Demo Complete"
	echo -e "${GREEN}✓ straylight-llm gateway is working!${NC}"
	echo ""
	echo -e "  ${CYAN}Dashboard:${NC} http://localhost:8080"
	echo -e "  ${CYAN}Health:${NC} http://localhost:8080/health"
	echo -e "  ${CYAN}Models:${NC} http://localhost:8080/v1/models"
	echo -e "  ${CYAN}Events:${NC} http://localhost:8080/v1/events"
	echo ""
}

# Handle --record flag
if [ "${1:-}" == "--record" ]; then
	OUTPUT_FILE="$DEMO_DIR/demo-$(date +%Y%m%d-%H%M%S).mp4"
	echo -e "${CYAN}Recording to: $OUTPUT_FILE${NC}"
	echo -e "${YELLOW}Press Ctrl+C to stop recording${NC}"
	sleep 2

	# Start recording in background
	wf-recorder -f "$OUTPUT_FILE" &
	RECORDER_PID=$!

	# Run demo
	main

	# Stop recording
	sleep 2
	kill $RECORDER_PID 2>/dev/null || true

	echo ""
	echo -e "${GREEN}Recording saved to: $OUTPUT_FILE${NC}"
else
	main
fi
