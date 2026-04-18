# QOMN Runtime — Integration Guide

## Overview

The QOMN runtime executes `.qomn` plan files as deterministic WASM modules.
It is available in two forms:

| Runtime | Use case | Language |
|---------|----------|----------|
| **QOMN JIT (browser)** | Client-side, no server | JavaScript + WASM |
| **QOMN Evaluator (server)** | API endpoint, batch | Rust |

Both runtimes execute the same `.qomn` programs and produce identical results.

---

## Browser Integration (QOMN JIT)

### 1. Load the runtime

```html
<script src="https://qomni.clanmarketer.com/qomn/runtime.js"></script>
```

### 2. Execute a plan

```javascript
const result = await CrysL.execute("plan_pump_sizing", {
  Q_gpm: 750,
  P_psi: 100,
  eff: 0.70
});

console.log(result.HP_req);   // 18.04 (exact)
console.log(result.HP_max);   // 21.65
console.log(result.meta.standard);  // "NFPA 20:2022..."
```

### 3. Response format

```json
{
  "plan": "plan_pump_sizing",
  "outputs": {
    "HP_req":   { "value": 18.04, "label": "Required HP",              "unit": "HP" },
    "HP_max":   { "value": 21.65, "label": "Max shutoff HP (NFPA 20)", "unit": "HP" },
    "kW_motor": { "value": 13.45, "label": "Motor power",              "unit": "kW" },
    "Q_lps":    { "value": 47.32, "label": "Flow rate",                "unit": "L/s" },
    "H_m":      { "value": 70.31, "label": "Total Dynamic Head",       "unit": "m"  }
  },
  "meta": {
    "standard": "NFPA 20:2022 — Standard for the Installation of Stationary Pumps",
    "source": "Section 4.26, Chapter 6, Annex A",
    "domain": "nfpa_electrico",
    "version": "2.0"
  },
  "assertions_passed": true,
  "execution_ms": 0.18
}
```

---

## Server API (Qomni Engine — proprietary)

When embedded in the Qomni Engine, QOMN plans are triggered automatically
by the planner when a query matches a known domain + numeric pattern.

**You do not need to call QOMN plans directly** — the planner routes to them.

For direct HTTP access (if your Qomni instance is running):

```bash
curl -X POST https://your-qomni-host/qomn/execute \
  -H "Content-Type: application/json" \
  -d '{
    "plan": "plan_pump_sizing",
    "inputs": { "Q_gpm": 750, "P_psi": 100 }
  }'
```

---

## Rust Evaluator (Open Source)

For server-side integration without the full Qomni Engine:

```toml
# Cargo.toml
[dependencies]
qomn-eval = { git = "https://github.com/condesi/qomn-lang", path = "runtime/qomn-eval" }
```

```rust
use qomn_eval::{CrysLEval, PlanInputs};

let eval = CrysLEval::from_stdlib("nfpa_electrico")?;
let mut inputs = PlanInputs::new();
inputs.insert("Q_gpm", 750.0);
inputs.insert("P_psi", 100.0);

let result = eval.run("plan_pump_sizing", inputs)?;
println!("HP required: {}", result.get("HP_req").unwrap());
```

---

## Error Handling

QOMN runtime returns structured errors for assertion failures:

```json
{
  "error": "assertion_failed",
  "message": "flow exceeds 5000 GPM — verify NFPA 20 Table 4.26",
  "plan": "plan_pump_sizing",
  "input": "Q_gpm",
  "value": 6000.0
}
```

| Error code | Meaning |
|------------|---------|
| `assertion_failed` | Input outside valid range |
| `plan_not_found` | Plan name not in stdlib |
| `missing_input` | Required parameter not provided |
| `type_error` | Non-numeric value for f64 param |

---

## Adding Plans to the Runtime

1. Write your plan in `stdlib/{domain}.qomn`
2. Run the validator: `cargo run --bin qomn-validate -- stdlib/your_domain.qomn`
3. Run tests: `cargo test --test plan_tests`
4. Submit PR — all valid plans are automatically compiled to WASM and included

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full process.
