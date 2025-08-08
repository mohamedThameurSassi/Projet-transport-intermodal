#!/usr/bin/env bash
# Load test script for car-walk and transit routes
# Generates 1000 requests (750 car-walk, 250 transit), computes average response time per route type
# and samples server memory (max RSS) while running.

set -euo pipefail

BASE_URL=${BASE_URL:-"http://localhost:8080"}
CAR_ENDPOINT="$BASE_URL/route/car-walk"
TRANSIT_ENDPOINT="$BASE_URL/route/transit"
CAR_REQUESTS=${CAR_REQUESTS:-750}
TRANSIT_REQUESTS=${TRANSIT_REQUESTS:-250}
CONCURRENCY=${CONCURRENCY:-20}
WALK_MINUTES=${WALK_MINUTES:-20}

# Bounding box (example: Montreal area) - adjust as needed
LAT_MIN=45.40
LAT_MAX=45.60
LON_MIN=-73.75
LON_MAX=-73.45

WORKDIR=$(mktemp -d -t route_loadtest_XXXX)
CAR_PAYLOAD_DIR="$WORKDIR/car_payloads"
TRANSIT_PAYLOAD_DIR="$WORKDIR/transit_payloads"
mkdir -p "$CAR_PAYLOAD_DIR" "$TRANSIT_PAYLOAD_DIR"
CAR_TIMES="$WORKDIR/car_times.txt"
TRANSIT_TIMES="$WORKDIR/transit_times.txt"
MEM_SAMPLES="$WORKDIR/mem_samples.csv"
SUMMARY_FILE="$WORKDIR/summary.txt"

random_coord() {
  # Fast: uses bash $RANDOM (0..32767); combine two draws for more granularity
  local min=$1 max=$2
  local r1=$RANDOM r2=$RANDOM
  # scale: (r1*32768 + r2) / 1073741823 ≈ [0,1)
  local denom=$((32768*32768-1))
  local numer=$((r1*32768 + r2))
  awk -v min="$min" -v max="$max" -v n="$numer" -v d="$denom" 'BEGIN{
     val = min + (max-min)*(n/d);
     printf "%.6f", val
  }'
}

random_pair_json() {
  local lat1 lon1 lat2 lon2
  lat1=$(random_coord $LAT_MIN $LAT_MAX)
  lon1=$(random_coord $LON_MIN $LON_MAX)
  for attempt in {1..50}; do
    lat2=$(random_coord $LAT_MIN $LAT_MAX)
    lon2=$(random_coord $LON_MIN $LON_MAX)
    dlat=$(awk -v a="$lat1" -v b="$lat2" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
    dlon=$(awk -v a="$lon1" -v b="$lon2" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
    absd=$(awk -v x="$dlat" -v y="$dlon" 'BEGIN{print x+y}')
    pass=$(awk -v v="$absd" 'BEGIN{if(v>0.002)print 1; else print 0}')
    [ "$pass" -eq 1 ] && break
    if [ "$attempt" -eq 50 ]; then
      break
    fi
  done
  cat <<EOF
{"startLat":$lat1,"startLon":$lon1,"endLat":$lat2,"endLon":$lon2,"walkDurationMins":$WALK_MINUTES}
EOF
}

echo "Generating payloads..." >&2
for ((i=1;i<=CAR_REQUESTS;i++)); do
  random_pair_json > "$CAR_PAYLOAD_DIR/$i.json"
done
for ((i=1;i<=TRANSIT_REQUESTS;i++)); do
  random_pair_json > "$TRANSIT_PAYLOAD_DIR/$i.json"
done

# Try to find running server PID for memory sampling
SERVER_PID="${SERVER_PID:-}" # allow user to preset
if [ -z "$SERVER_PID" ]; then
  # Grep for process named 'health-route-server' (adjust if different)
  SERVER_PID=$(pgrep -f 'health-route-server' || true)
fi

if [ -n "$SERVER_PID" ]; then
  echo "timestamp_ms,rss_kb" > "$MEM_SAMPLES"
  ( echo "Sampling memory usage for PID $SERVER_PID" >&2
    while kill -0 "$SERVER_PID" 2>/dev/null; do
      if date +%s%3N >/dev/null 2>&1; then
        ts=$(date +%s%3N)
      else
        ts=$(($(date +%s)*1000))
      fi
      rss=$(ps -o rss= -p "$SERVER_PID" | tr -d ' ' || echo 0)
      echo "$ts,$rss" >> "$MEM_SAMPLES"
      sleep 0.25
    done ) &
  MEM_SAMPLER_PID=$!
else
  echo "WARNING: Could not determine server PID. Memory sampling disabled." >&2
  MEM_SAMPLER_PID=""
fi

perform_batch() {
  local endpoint=$1
  local dir=$2
  local times_file=$3
  local label=$4
  local count=0
  echo "Starting $label requests to $endpoint" >&2
  for f in "$dir"/*.json; do
    (
      t=$(curl -s -o /dev/null -w '%{time_total}' -H 'Content-Type: application/json' -X POST --data-binary "@${f}" "$endpoint" || echo 0)
      echo "$t" >> "$times_file"
    ) &
    count=$((count+1))
    if [ $count -ge $CONCURRENCY ]; then
      wait
      count=0
    fi
  done
  wait
  echo "Completed $label batch" >&2
}

START_EPOCH=$(date +%s)
perform_batch "$CAR_ENDPOINT" "$CAR_PAYLOAD_DIR" "$CAR_TIMES" "car-walk ($CAR_REQUESTS)"
perform_batch "$TRANSIT_ENDPOINT" "$TRANSIT_PAYLOAD_DIR" "$TRANSIT_TIMES" "transit ($TRANSIT_REQUESTS)"
END_EPOCH=$(date +%s)
TOTAL_DURATION=$((END_EPOCH-START_EPOCH))

if [ -n "${MEM_SAMPLER_PID}" ]; then
  kill "$MEM_SAMPLER_PID" 2>/dev/null || true
fi

calc_avg() {
  local file=$1
  awk '{sum+=$1; n+=1} END{if(n>0) printf "%.4f", sum/n; else print "0"}' "$file"
}
calc_p95() {
  local file=$1
  sort -n "$file" | awk 'BEGIN{p=0.95} {a[NR]=$1} END{if(NR==0){print 0; exit} idx=int(p*NR); if(idx<1)idx=1; if(idx>NR)idx=NR; printf "%.4f", a[idx]}'
}

CAR_AVG=$(calc_avg "$CAR_TIMES")
TRANSIT_AVG=$(calc_avg "$TRANSIT_TIMES")
CAR_P95=$(calc_p95 "$CAR_TIMES")
TRANSIT_P95=$(calc_p95 "$TRANSIT_TIMES")

if [ -f "$MEM_SAMPLES" ]; then
  MAX_RSS_KB=$(awk -F',' 'NR>1{if($2>m)m=$2} END{print m+0}' "$MEM_SAMPLES")
else
  MAX_RSS_KB=0
fi

{
  echo "=== Load Test Summary ==="
  echo "Base URL: $BASE_URL"
  echo "Car-walk requests: $CAR_REQUESTS"
  echo "Transit requests: $TRANSIT_REQUESTS"
  echo "Concurrency: $CONCURRENCY"
  echo "Total wall time (s): $TOTAL_DURATION"
  echo "Car-walk avg response (s): $CAR_AVG"
  echo "Car-walk p95 response (s): $CAR_P95"
  echo "Transit avg response (s): $TRANSIT_AVG"
  echo "Transit p95 response (s): $TRANSIT_P95"
  echo "Max RSS observed (KB): $MAX_RSS_KB"
  if [ "$MAX_RSS_KB" != "0" ]; then
    echo "Max RSS observed (MB): $(awk -v k=$MAX_RSS_KB 'BEGIN{printf "%.2f", k/1024}')"
  fi
  echo "Working directory (artifacts): $WORKDIR"
  echo "Car timing samples: $CAR_TIMES"
  echo "Transit timing samples: $TRANSIT_TIMES"
  if [ -f "$MEM_SAMPLES" ]; then
    echo "Memory samples: $MEM_SAMPLES"
  fi
} | tee "$SUMMARY_FILE"

cat <<NOTE
NOTE:
- RSS values are approximate (resident set size) sampled every 250ms.
- Average and p95 are based on curl's total transaction time.
- Adjust CONCURRENCY, bounding box, and request counts via environment vars.
- Artifacts retained in: $WORKDIR
NOTE
