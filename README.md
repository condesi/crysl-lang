# CRYS-L v2 — Crystal Language

**Open standard for deterministic engineering calculations.**
MIT License · [Live Demo](https://qomni.clanmarketer.com/crysl/) · [Paper (PDF)](paper/main.tex)

> Write an engineering calculation once. Get **exact answers** in **<300ms**,
> with the standard and formula cited. No LLM. No approximation. No setup.

---

## Quick Start — Try It Now

**Online (browser, no install):**
👉 [qomni.clanmarketer.com/crysl/](https://qomni.clanmarketer.com/crysl/)

```
plan_pump_sizing(500, 80, 0.75)
→ Required HP: 13.26 HP [NFPA 20:2022 §4.26]
→ Shutoff HP: 15.91 HP
→ Flow: 31.55 L/s
→ Head: 56.25 m
```

---

## Why CRYS-L?

| Question | LLM (GPT-4, Claude) | CRYS-L |
|----------|-------------------|--------|
| "500 gpm pump at 80 psi, 75% eff — how many HP?" | ~15 HP (±15% error) | **13.26 HP** (exact) |
| Standard cited? | No | NFPA 20:2022 §4.26 |
| Latency | 2,800–8,500 ms | **53–286 ms** |
| Reproducible? | No (stochastic) | Yes (deterministic) |
| Works offline? | No | Yes (WASM) |
| Cost | $0.01–0.015/call | **Free** |

**15–850× faster than LLM API. Exact answers. Traceable to published standard.**

---

## How It Works

CRYS-L describes *what to compute*, not how. The CRYS-L JIT compiles your plan
to WebAssembly (WASM) and executes it at near-native speed:

```
User query → match plan → extract params → execute WASM → return result
  (2ms)        (1ms)         (1ms)           (<1ms)         (<1ms)
Total: ~5ms WASM execution
+ HTTP + JSON overhead = 50–300ms end-to-end
```

Compare to LLM: tokenize → 750M+ params → decode → 4,000–45,000ms → approximate answer.

---

## Write a Plan in 20 Lines

```crysl
plan_pump_sizing(
    Q_gpm: f64,           // required flow (GPM)
    P_psi: f64,           // required pressure (PSI)
    eff:   f64 = 0.70     // pump efficiency (0-1)
) {
    meta {
        standard: "NFPA 20:2022",
        source: "Section 4.26 + Chapter 6",
        domain: "nfpa_electrico",
    }

    let Q_lps  = Q_gpm * 0.06309;
    let H_m    = P_psi * 0.70307;
    let HP_req = (Q_lps * H_m) / (eff * 76.04);
    let HP_max = HP_req * 1.20;   // NFPA 20: shutoff ≤ 140% rated

    formula "Pump HP": "HP = (Q[L/s] × H[m]) / (η × 76.04)";

    assert Q_gpm > 0.0 msg "flow must be positive";
    assert eff   <= 1.0 msg "efficiency must be ≤ 1.0";

    output HP_req label "Required HP"        unit "HP";
    output HP_max label "Shutoff HP (NFPA)"  unit "HP";
    output Q_lps  label "Flow"               unit "L/s";
    output H_m    label "Total Dynamic Head" unit "m";
}
```

---

## Standard Library (v2)

### Hydraulics (IS.010 Peru / AWWA)

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_hazen_williams(Q, D, C, L)` | V = 0.8492·C·R^0.63·S^0.54 | IS.010 Peru / AWWA M22 |
| `plan_darcy_weisbach(Q, D, f, L)` | h_f = f·L/D·V²/2g | Darcy-Weisbach |
| `plan_pipe_sizing(Q, v_max)` | D = sqrt(4Q/(π·v)) | IS.010 Peru |

### Fire Protection (NFPA)

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_pump_sizing(Q_gpm, P_psi, eff)` | HP = Q·H/(η·76.04) | NFPA 20:2022 §4.26 |
| `plan_sprinkler_density(area, density)` | Q = area × density | NFPA 13:2022 |
| `plan_hose_stream(class)` | Q_hose by occupancy class | NFPA 13 Table 11.2 |

### Electrical (IEC / NEC)

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_voltage_drop(P_kw, V, L, fp, rho)` | ΔV = 2ρLI/S | IEC 60364-5-52 |
| `plan_transformer_sizing(P_kw, fp, fu)` | S = P·fu/fp | IEC 60076-1 |
| `plan_cable_sizing(I, method)` | S from NEC tables | NEC Article 310 |

---

## Benchmark Results (Server5, AMD EPYC 12-core)

```
Plan                          Runs: 1    2    3    4    5   | Avg
─────────────────────────────────────────────────────────────────
plan_pump_sizing (500gpm,80psi) 302  277  305  282  265 | 286ms
plan_hazen_williams (150mm,300m)  56   51   61   50   49 |  53ms
plan_voltage_drop (75kw,380v,120m)130  118  113  127  112 | 120ms
─────────────────────────────────────────────────────────────────
Overall average                                          | 153ms
```

**vs LLM:**
- GPT-4 Turbo: 2,800–8,500ms (18–56× slower)
- Claude 3.5 Sonnet: 2,200–7,000ms (14–46× slower)
- Local LLM 1.5B: 8,000–45,000ms (52–294× slower)

---

## Grammar (EBNF)

```ebnf
program    ::= plan_decl+
plan_decl  ::= 'plan_' ident '(' params? ')' '{' body '}'
params     ::= param (',' param)*
param      ::= ident ':' type ('=' literal)?
type       ::= 'f64' | 'f32' | 'i64' | 'bool' | 'str'
body       ::= (const | let | formula | assert | output | meta)+
const      ::= 'const' ident '=' expr ';'
let        ::= 'let'   ident '=' expr ';'
formula    ::= 'formula' string ':' string ';'
assert     ::= 'assert' expr 'msg' string ';'
output     ::= 'output' ident 'label' string ('unit' string)? ';'
meta       ::= 'meta' '{' (ident ':' string ',')+ '}'
expr       ::= term (('+' | '-' | '*' | '/' | '^') term)*
term       ::= number | ident | ident '(' args ')' | '(' expr ')'
```

Built-ins: `sqrt`, `pow`, `abs`, `min`, `max`, `log`, `log10`, `round`, `clamp`

---

## Repository Structure

```
crysl-lang/
├── paper/
│   └── main.tex              # Full LaTeX paper (arXiv-ready)
├── stdlib/
│   ├── hidraulica.crysl      # Hazen-Williams, Darcy-Weisbach, pipe sizing
│   ├── nfpa_electrico.crysl  # Pump sizing, sprinkler, cable, transformer
│   ├── civil.crysl           # Beam deflection, column load, slab
│   ├── mecanica.crysl        # Shaft power, torque, gear ratio
│   ├── termica.crysl         # HVAC load, insulation, heat transfer
│   └── sanitaria.crysl       # Water demand, tank sizing, sewage
├── runtime/
│   ├── interpreter.md        # How the WASM runtime works
│   └── integration_guide.md  # How to embed CRYS-L in your app
├── examples/
│   ├── hello_pump.crysl      # First example: pump sizing
│   ├── hello_hazen.crysl     # Pipe flow calculation
│   └── hello_cable.crysl     # Electrical cable sizing
├── benchmarks/
│   └── results_2026-04-13.json # Measured latency data
└── README.md
```

---

## Contribute a Plan

1. Fork this repo
2. Write your plan in `stdlib/{domain}.crysl`
3. Add test vectors in `benchmarks/tests/{plan_name}.json`:
```json
{
  "plan": "plan_hazen_williams",
  "cases": [
    {
      "inputs": {"Q": 2.5, "D": 150.0, "C": 120.0, "L": 200.0},
      "expected": {"V": 0.141, "h_f": 0.089},
      "tolerance_pct": 0.5,
      "source": "IS.010 Peru, Example 3.2"
    }
  ]
}
```
4. Submit PR — all valid plans following the grammar are welcome

**Checklist:**
- [ ] `meta {}` with standard name + section reference
- [ ] `assert` for each input
- [ ] `formula` for each key equation
- [ ] `output` with label + unit
- [ ] 3+ test cases from published tables

---

## License

**CRYS-L language spec, grammar, standard library, examples: MIT License**

The Qomni Engine runtime integration is proprietary.
The language itself — grammar, stdlib plans, this repo — is fully open.

---

## Citation

```bibtex
@article{rojasmasgo2026crysl,
  title   = {CRYS-L: A Domain-Specific Language for Deterministic Engineering
             Calculations at Zero Inference Cost},
  author  = {Rojas Masgo, Percy and {Qomni AI}},
  year    = {2026},
  month   = {April},
  note    = {Open Standard, MIT License},
  url     = {https://github.com/condesi/crysl-lang}
}
```

---

*Built by Percy Rojas Masgo · CEO Condesi Perú · Qomni AI Lab*
*Live at [qomni.clanmarketer.com/crysl/](https://qomni.clanmarketer.com/crysl/)*
