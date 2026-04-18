#!/usr/bin/env bash
# QOMN v2.2 Reproducibility Benchmark
# Run on bare-metal or KVM and compare results
# Usage: ./repro.sh [--api-url URL]
set -euo pipefail

API="${1:-http://localhost:9001}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT="results_repro_${TIMESTAMP}.json"

echo "=== QOMN Reproducibility Benchmark v2.2 ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# 1. Hardware fingerprint
CPU_MODEL=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "unknown")
CPU_CORES=$(nproc 2>/dev/null || echo "?")
CPU_FREQ=$(grep 'cpu MHz' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "?")
L1D=$(grep -r 'size' /sys/devices/system/cpu/cpu0/cache/index0/ 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "?")
L2=$(grep -r 'size' /sys/devices/system/cpu/cpu0/cache/index2/ 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "?")
L3=$(grep -r 'size' /sys/devices/system/cpu/cpu0/cache/index3/ 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "?")
RAM_GB=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo "?")
AVX512=$(grep -c 'avx512f' /proc/cpuinfo 2>/dev/null && echo "yes" || echo "no")
AVX2=$(grep -c 'avx2' /proc/cpuinfo 2>/dev/null && echo "yes" || echo "no")
OS=$(uname -srm 2>/dev/null || echo "?")

echo "Hardware:"
echo "  CPU:    $CPU_MODEL"
echo "  Cores:  $CPU_CORES @ ${CPU_FREQ} MHz"
echo "  Cache:  L1d=$L1D  L2=$L2  L3=$L3"
echo "  RAM:    ${RAM_GB}GB"
echo "  AVX2:   $AVX2  AVX-512: $AVX512"
echo "  OS:     $OS"
echo ""

# 2. QOMN benchmark (via API)
echo "--- QOMN JIT (Cranelift + AVX2 + FMA) ---"
CRYSL_NS=$(curl -s -X POST "$API/plan/bench" \
  -H "Content-Type: application/json" \
  -d '{"plan":"plan_pump_sizing","params":{"Q_gpm":500,"P_psi":100,"eff":0.75},"runs":10000}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('median_ns', d.get('ns_per_call','?')))" 2>/dev/null || echo "?")
echo "  Median latency: ${CRYSL_NS} ns"

# 3. NumPy baseline
echo "--- NumPy 1.x (Python 3.x) ---"
NUMPY_NS=$(python3 - << 'PYEOF'
import time, statistics, sys
try:
    import numpy as np
    Q, P, E = 500.0, 100.0, 0.75
    def pump_numpy():
        # 0.06309 = GPM to L/s conversion factor (1 gpm = 0.06309 L/s)
        q_lps = np.float64(Q) * np.float64(0.06309)
        # 0.70307 = PSI to meters water column (1 psi = 0.70307 m.c.a.)
        h_m   = np.float64(P) * np.float64(0.70307)
        # 76.04 = HP conversion factor (76.04 kgf·m/s = 1 metric HP)
        hp    = (q_lps * h_m) / (np.float64(E) * np.float64(76.04))
        hp_max = hp * np.float64(1.40)
        shutoff = hp * np.float64(1.20)
        return hp, hp_max, q_lps, h_m, shutoff
    # Warmup
    for _ in range(1000): pump_numpy()
    times = []
    for _ in range(10000):
        t0 = time.perf_counter_ns()
        pump_numpy()
        times.append(time.perf_counter_ns() - t0)
    print(statistics.median(times))
except Exception as e:
    print(f"error: {e}", file=sys.stderr)
    print(-1)
PYEOF
)
echo "  Median latency: ${NUMPY_NS} ns"

# 4. Python scalar baseline
echo "--- Python 3 scalar (no NumPy) ---"
PY_NS=$(python3 - << 'PYEOF'
import time, statistics
Q, P, E = 500.0, 100.0, 0.75
def pump_py():
    # 0.06309 = GPM to L/s conversion factor (1 gpm = 0.06309 L/s)
    q = Q * 0.06309
    # 0.70307 = PSI to meters water column (1 psi = 0.70307 m.c.a.)
    h = P * 0.70307
    # 76.04 = HP conversion factor (76.04 kgf·m/s = 1 metric HP)
    hp = (q * h) / (E * 76.04)
    return hp, hp*1.40, q, h, hp*1.20
for _ in range(1000): pump_py()
times = [0]*10000
for i in range(10000):
    t0 = time.perf_counter_ns()
    pump_py()
    times[i] = time.perf_counter_ns() - t0
print(statistics.median(times))
PYEOF
)
echo "  Median latency: ${PY_NS} ns"

# 5. Rust scalar baseline (compile inline)
echo "--- Rust scalar (rustc -O3) ---"
RUST_SRC=$(mktemp /tmp/qomn_bench_XXXXXX.rs)
cat > "$RUST_SRC" << 'RSEOF'
use std::time::Instant;
fn pump_sizing(q_gpm: f64, p_psi: f64, eff: f64) -> (f64,f64,f64,f64,f64) {
    // 0.06309 = GPM to L/s conversion factor (1 gpm = 0.06309 L/s)
    let q = q_gpm * 0.06309;
    // 0.70307 = PSI to meters water column (1 psi = 0.70307 m.c.a.)
    let h = p_psi * 0.70307;
    // 76.04 = HP conversion factor (76.04 kgf·m/s = 1 metric HP)
    let hp = (q * h) / (eff * 76.04);
    (hp, hp*1.40, q, h, hp*1.20)
}
fn main() {
    let (q,p,e) = (500.0_f64, 100.0_f64, 0.75_f64);
    for _ in 0..1000 { let _ = pump_sizing(q,p,e); } // warmup
    let mut times = vec![0u64; 10000];
    for i in 0..10000 {
        let t0 = Instant::now();
        let _ = pump_sizing(q,p,e);
        times[i] = t0.elapsed().as_nanos() as u64;
    }
    times.sort();
    println!("{}", times[times.len()/2]);
}
RSEOF
RUST_BIN=$(mktemp /tmp/qomn_bench_XXXXXX)
if rustc -O -o "$RUST_BIN" "$RUST_SRC" 2>/dev/null; then
    RUST_NS=$("$RUST_BIN")
    echo "  Median latency: ${RUST_NS} ns"
else
    RUST_NS="N/A (rustc not found)"
    echo "  $RUST_NS"
fi
rm -f "$RUST_SRC" "$RUST_BIN"

# 6. C++ baseline
echo "--- C++ -O2 (g++) ---"
CPP_SRC=$(mktemp /tmp/qomn_bench_XXXXXX.cpp)
cat > "$CPP_SRC" << 'CPPEOF'
#include <iostream>
#include <vector>
#include <algorithm>
#include <chrono>
struct Result { double hp, hp_max, q_lps, h_m, hp_shut; };
__attribute__((noinline))
Result pump_sizing(double q_gpm, double p_psi, double eff) {
    // 0.06309 = GPM to L/s conversion factor (1 gpm = 0.06309 L/s)
    double q = q_gpm * 0.06309;
    // 0.70307 = PSI to meters water column (1 psi = 0.70307 m.c.a.)
    double h = p_psi * 0.70307;
    // 76.04 = HP conversion factor (76.04 kgf·m/s = 1 metric HP)
    double hp = (q * h) / (eff * 76.04);
    return {hp, hp*1.40, q, h, hp*1.20};
}
int main() {
    volatile double q=500.0, p=100.0, e=0.75;
    for(int i=0;i<1000;i++) { auto r=pump_sizing(q,p,e); (void)r; }
    std::vector<long long> times(10000);
    for(int i=0;i<10000;i++){
        auto t0=std::chrono::high_resolution_clock::now();
        auto r=pump_sizing(q,p,e); (void)r;
        auto t1=std::chrono::high_resolution_clock::now();
        times[i]=std::chrono::duration_cast<std::chrono::nanoseconds>(t1-t0).count();
    }
    std::sort(times.begin(),times.end());
    std::cout<<times[5000]<<std::endl;
}
CPPEOF
CPP_BIN=$(mktemp /tmp/qomn_bench_XXXXXX)
if g++ -O2 -o "$CPP_BIN" "$CPP_SRC" 2>/dev/null; then
    CPP_NS=$("$CPP_BIN")
    echo "  Median latency: ${CPP_NS} ns"
else
    CPP_NS="N/A (g++ not found)"
    echo "  $CPP_NS"
fi
rm -f "$CPP_SRC" "$CPP_BIN"

# 7. Summary table
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ QOMN v2.2 Reproducibility Benchmark — pump_sizing (N=10k)│"
echo "├────────────────────────┬──────────────────┬────────────────┤"
echo "│ Implementation         │ Median Latency   │ Speedup        │"
echo "├────────────────────────┼──────────────────┼────────────────┤"
printf "│ %-22s │ %16s │ %14s │\n" "QOMN JIT (AVX2+FMA)"  "${CRYSL_NS} ns"  "1.0× (baseline)"
printf "│ %-22s │ %16s │ %14s │\n" "Rust scalar (-O3)"       "${RUST_NS} ns"   ""
printf "│ %-22s │ %16s │ %14s │\n" "C++ -O2"                 "${CPP_NS} ns"    ""
printf "│ %-22s │ %16s │ %14s │\n" "NumPy (Python 3)"        "${NUMPY_NS} ns"  ""
printf "│ %-22s │ %16s │ %14s │\n" "Python 3 scalar"         "${PY_NS} ns"     ""
echo "└────────────────────────┴──────────────────┴────────────────┘"

# 8. Save JSON
cat > "$OUT" << JSONEOF
{
  "benchmark": "QOMN v2.2 Reproducibility",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "plan": "plan_pump_sizing",
  "params": {"Q_gpm": 500, "P_psi": 100, "eff": 0.75},
  "n_runs": 10000,
  "hardware": {
    "cpu": "$CPU_MODEL",
    "cores": $CPU_CORES,
    "freq_mhz": "$CPU_FREQ",
    "cache": {"l1d": "$L1D", "l2": "$L2", "l3": "$L3"},
    "ram_gb": "$RAM_GB",
    "avx2": "$AVX2",
    "avx512": "$AVX512",
    "os": "$OS"
  },
  "results_median_ns": {
    "qomn_jit_avx2": $CRYSL_NS,
    "rust_scalar_o3": "$RUST_NS",
    "cpp_o2": "$CPP_NS",
    "numpy": $NUMPY_NS,
    "python_scalar": $PY_NS
  }
}
JSONEOF
echo ""
echo "Results saved to: $OUT"
echo ""
echo "To reproduce: run this script on identical hardware (same CPU model + OS)"
echo "Expected variation: ±15% on same hardware, ±40% across different systems"
