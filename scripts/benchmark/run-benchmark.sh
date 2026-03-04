#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                        // straylight-llm //
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#     "The sky above the port was the color of television,
#      tuned to a dead channel."
#
#                                                               — Neuromancer
#
# Run straylight-llm benchmarks.
#
# Usage:
#   ./scripts/benchmark/run-benchmark.sh              # Full benchmark suite
#   ./scripts/benchmark/run-benchmark.sh quick        # Quick smoke test
#   ./scripts/benchmark/run-benchmark.sh stress       # Stress test only
#   ./scripts/benchmark/run-benchmark.sh cache        # Cache performance test
#
# Environment:
#   BASE_URL              Gateway URL (default: http://localhost:8080)
#   OPENROUTER_API_KEY    API key for OpenRouter
#   MODEL                 Model to test (default: google/gemini-2.0-flash-001)
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="${BASE_URL:-http://localhost:8080}"
MODEL="${MODEL:-google/gemini-2.0-flash-001}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                                              // straylight-llm benchmark //"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

# ════════════════════════════════════════════════════════════════════════════════
#                                                              // prerequisites
# ════════════════════════════════════════════════════════════════════════════════

check_prereqs() {
	local missing=()

	if ! command -v curl &>/dev/null; then
		missing+=("curl")
	fi

	if ! command -v jq &>/dev/null; then
		missing+=("jq")
	fi

	# k6 is optional but recommended
	if ! command -v k6 &>/dev/null; then
		echo -e "${YELLOW}Warning: k6 not found. Install with: brew install k6 / nix-shell -p k6${NC}"
		echo -e "${YELLOW}Falling back to curl-based benchmarks${NC}"
		HAS_K6=false
	else
		HAS_K6=true
	fi

	# hey is optional
	if ! command -v hey &>/dev/null; then
		HAS_HEY=false
	else
		HAS_HEY=true
	fi

	if [ ${#missing[@]} -ne 0 ]; then
		echo -e "${RED}Error: Missing required tools: ${missing[*]}${NC}"
		exit 1
	fi
}

# ════════════════════════════════════════════════════════════════════════════════
#                                                                 // health check
# ════════════════════════════════════════════════════════════════════════════════

health_check() {
	echo -e "${BLUE}Checking gateway health...${NC}"

	if ! curl -sf "${BASE_URL}/health" >/dev/null 2>&1; then
		echo -e "${RED}Error: Gateway not responding at ${BASE_URL}${NC}"
		echo "Make sure the gateway is running:"
		echo "  nix run .#straylight-llm"
		echo "  # or"
		echo "  docker run -p 8080:8080 ghcr.io/justinfleek/straylight-llm:latest"
		exit 1
	fi

	echo -e "${GREEN}Gateway healthy at ${BASE_URL}${NC}"
}

# ════════════════════════════════════════════════════════════════════════════════
#                                                              // curl benchmarks
# ════════════════════════════════════════════════════════════════════════════════

curl_latency_test() {
	local name="$1"
	local payload="$2"
	local count="${3:-10}"

	echo -e "\n${BLUE}Running: ${name} (${count} requests)${NC}"

	local total=0
	local min=999999
	local max=0
	local errors=0

	for i in $(seq 1 "$count"); do
		local start end duration
		start=$(date +%s%3N)

		local response
		response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/chat/completions" \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer ${OPENROUTER_API_KEY:-}" \
			-d "$payload" 2>/dev/null) || true

		end=$(date +%s%3N)
		duration=$((end - start))

		local http_code
		http_code=$(echo "$response" | tail -1)

		if [ "$http_code" = "200" ]; then
			total=$((total + duration))
			[ "$duration" -lt "$min" ] && min=$duration
			[ "$duration" -gt "$max" ] && max=$duration
			echo -ne "\r  Request $i/$count: ${duration}ms"
		else
			errors=$((errors + 1))
			echo -ne "\r  Request $i/$count: ERROR ($http_code)"
		fi
	done

	echo ""

	local success=$((count - errors))
	if [ "$success" -gt 0 ]; then
		local avg=$((total / success))
		echo -e "  ${GREEN}Results:${NC} avg=${avg}ms min=${min}ms max=${max}ms errors=${errors}/${count}"
	else
		echo -e "  ${RED}All requests failed${NC}"
	fi
}

run_curl_benchmarks() {
	echo -e "\n${BLUE}═══ Curl-based Latency Tests ═══${NC}"

	# Simple request
	curl_latency_test "Simple chat (varied)" \
		'{"model":"'"$MODEL"'","messages":[{"role":"user","content":"Say hi"}],"max_tokens":10}' \
		5

	# Cacheable request (temperature=0)
	curl_latency_test "Cacheable request (should hit cache after first)" \
		'{"model":"'"$MODEL"'","messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":10,"temperature":0}' \
		5

	# Longer response
	curl_latency_test "Longer response (50 tokens)" \
		'{"model":"'"$MODEL"'","messages":[{"role":"user","content":"Explain REST APIs briefly"}],"max_tokens":50}' \
		3
}

# ════════════════════════════════════════════════════════════════════════════════
#                                                                // hey benchmarks
# ════════════════════════════════════════════════════════════════════════════════

run_hey_benchmarks() {
	if [ "$HAS_HEY" = false ]; then
		echo -e "${YELLOW}Skipping hey benchmarks (hey not installed)${NC}"
		return
	fi

	echo -e "\n${BLUE}═══ Hey Load Tests ═══${NC}"

	# Warm up
	echo -e "\n${BLUE}Warming up (10 requests)...${NC}"
	hey -n 10 -c 2 -m POST \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${OPENROUTER_API_KEY:-}" \
		-d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"Hi"}],"max_tokens":5}' \
		"${BASE_URL}/v1/chat/completions" >/dev/null 2>&1 || true

	# Concurrency test
	echo -e "\n${BLUE}Concurrency test (50 requests, 10 concurrent)...${NC}"
	hey -n 50 -c 10 -m POST \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${OPENROUTER_API_KEY:-}" \
		-d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"Hi"}],"max_tokens":5}' \
		"${BASE_URL}/v1/chat/completions" 2>&1 | grep -E "(Requests/sec|Latency|Status)"

	# Health endpoint stress test
	echo -e "\n${BLUE}Health endpoint stress (1000 requests, 100 concurrent)...${NC}"
	hey -n 1000 -c 100 "${BASE_URL}/health" 2>&1 | grep -E "(Requests/sec|Latency|Status)"
}

# ════════════════════════════════════════════════════════════════════════════════
#                                                                 // k6 benchmarks
# ════════════════════════════════════════════════════════════════════════════════

run_k6_benchmarks() {
	if [ "$HAS_K6" = false ]; then
		echo -e "${YELLOW}Skipping k6 benchmarks (k6 not installed)${NC}"
		return
	fi

	local scenario="${1:-smoke}"

	echo -e "\n${BLUE}═══ K6 Load Tests (${scenario}) ═══${NC}"

	case "$scenario" in
	smoke)
		k6 run --vus 2 --duration 10s \
			-e "BASE_URL=${BASE_URL}" \
			-e "MODEL=${MODEL}" \
			-e "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}" \
			-e "SCENARIO=mixed" \
			"$SCRIPT_DIR/k6-load-test.js"
		;;
	load)
		k6 run \
			-e "BASE_URL=${BASE_URL}" \
			-e "MODEL=${MODEL}" \
			-e "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}" \
			"$SCRIPT_DIR/k6-load-test.js"
		;;
	cache)
		k6 run --vus 10 --duration 30s \
			-e "BASE_URL=${BASE_URL}" \
			-e "MODEL=${MODEL}" \
			-e "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}" \
			-e "SCENARIO=cache" \
			"$SCRIPT_DIR/k6-load-test.js"
		;;
	*)
		echo -e "${RED}Unknown scenario: ${scenario}${NC}"
		exit 1
		;;
	esac
}

# ════════════════════════════════════════════════════════════════════════════════
#                                                               // cache test
# ════════════════════════════════════════════════════════════════════════════════

run_cache_test() {
	echo -e "\n${BLUE}═══ Cache Performance Test ═══${NC}"

	local payload='{"model":"'"$MODEL"'","messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":10,"temperature":0}'

	# First request (cold)
	echo -e "\n${BLUE}Cold request (cache miss expected)...${NC}"
	local start end cold_time
	start=$(date +%s%3N)
	curl -s -X POST "${BASE_URL}/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${OPENROUTER_API_KEY:-}" \
		-d "$payload" >/dev/null
	end=$(date +%s%3N)
	cold_time=$((end - start))
	echo -e "  Cold: ${cold_time}ms"

	# Second request (should be cached)
	echo -e "\n${BLUE}Warm request (cache hit expected)...${NC}"
	start=$(date +%s%3N)
	curl -s -X POST "${BASE_URL}/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${OPENROUTER_API_KEY:-}" \
		-d "$payload" >/dev/null
	end=$(date +%s%3N)
	local warm_time=$((end - start))
	echo -e "  Warm: ${warm_time}ms"

	# Calculate speedup
	if [ "$warm_time" -gt 0 ]; then
		local speedup=$((cold_time / warm_time))
		echo -e "\n${GREEN}Cache speedup: ${speedup}x (${cold_time}ms -> ${warm_time}ms)${NC}"
	fi

	# Multiple cached requests
	echo -e "\n${BLUE}10 cached requests...${NC}"
	local total=0
	for i in $(seq 1 10); do
		start=$(date +%s%3N)
		curl -s -X POST "${BASE_URL}/v1/chat/completions" \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer ${OPENROUTER_API_KEY:-}" \
			-d "$payload" >/dev/null
		end=$(date +%s%3N)
		total=$((total + end - start))
	done
	local avg=$((total / 10))
	echo -e "  Average cached latency: ${avg}ms"
}

# ════════════════════════════════════════════════════════════════════════════════
#                                                                      // main
# ════════════════════════════════════════════════════════════════════════════════

main() {
	check_prereqs
	health_check

	local mode="${1:-full}"

	case "$mode" in
	quick | smoke)
		run_curl_benchmarks
		if [ "$HAS_K6" = true ]; then
			run_k6_benchmarks smoke
		fi
		;;
	cache)
		run_cache_test
		;;
	stress)
		if [ "$HAS_K6" = true ]; then
			run_k6_benchmarks load
		else
			echo -e "${RED}k6 required for stress tests${NC}"
			exit 1
		fi
		;;
	full)
		run_curl_benchmarks
		run_cache_test
		run_hey_benchmarks
		if [ "$HAS_K6" = true ]; then
			run_k6_benchmarks smoke
		fi
		;;
	*)
		echo "Usage: $0 [quick|cache|stress|full]"
		exit 1
		;;
	esac

	echo -e "\n${GREEN}Benchmark complete!${NC}"
}

main "$@"
