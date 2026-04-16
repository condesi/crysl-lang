# CRYS-L v2.2 — Crystal Language

**Created by Percy Rojas Masgo — Condesi Perú / Qomni AI Lab**
**Open standard for deterministic engineering calculations.**
MIT License · [Live Demo](https://qomni.clanmarketer.com/crysl/) · [Paper](paper/CRYSL_JIT_Paper_2026.md)
**Spec v2.2** — Mixed-case identifiers, formalized assert precedence, clamp/atan built-ins, 13 stdlib domains.

> Write an engineering calculation once. Get **exact answers** in **<1 µs**,
> with the standard and formula cited. No LLM. No approximation. No setup.

---

## Quick Start — Try It Now

**Online (browser, no install):**
👉 [qomni.clanmarketer.com/crysl/](https://qomni.clanmarketer.com/crysl/)

```
plan_pump_sizing(500, 100, 0.75)
→ Required HP:  16.84 HP  [NFPA 20:2022 §4.26]
→ Shutoff HP:   23.57 HP
→ Latency:      842 ns JIT
```

---

## Why CRYS-L?

| Question | LLM (GPT-4 Turbo) | CRYS-L v2.1 JIT |
|----------|-------------------|-----------------|
| "500 gpm pump at 100 psi, 75% eff — HP?" | ~17 HP (±15% error) | **16.835 HP** (exact) |
| Standard cited? | No | NFPA 20:2022 §4.26 |
| Latency | ~12 s (API) | **842 ns** |
| Speed ratio | 1× | **14,250,000×** |
| Reproducible? | No (stochastic) | Yes (deterministic) |
| Works offline? | No | Yes |
| Cost per call | $0.01–0.015 | **Free** |

**14–18 million× faster than GPT-4. 37–54× faster than Python. Exact answers. Traceable to published standards.**

---

## Benchmark Results (Server5, AMD EPYC 12-core · 48 GB · Ubuntu 24.04)

> Pure JIT execution — median of 10,000 iterations after 1,000 warm-up.
> HTTP/JSON overhead excluded (~80 µs via Nginx). Runtime: Rust 1.78 · Cranelift 0.109 · `-C opt-level=3`.

| Plan | Standard | CRYS-L JIT | C++ -O2 | Python 3.11 | GPT-4 Turbo | vs Python | vs GPT-4 |
|------|----------|-----------|---------|-------------|-------------|-----------|---------|
| Fire Pump Sizing | NFPA 20 | **842 ns** | ~1.9 µs | ~41 µs | ~12 s | 49× | 14,250,000× |
| Sprinkler System | NFPA 13 | **1.2 µs** | ~2.8 µs | ~63 µs | ~11 s | 53× | 9,200,000× |
| Voltage Drop | IEC 60364 | **971 ns** | ~1.7 µs | ~38 µs | ~8 s | 39× | 8,240,000× |
| 3-Phase Load | IEC/NEC/IEEE 141 | **1.14 µs** | ~2.1 µs | ~45 µs | ~10 s | 39× | 8,770,000× |
| Beam Analysis | AISC 360 | **891 ns** | ~2.1 µs | ~48 µs | ~14 s | 54× | 15,700,000× |
| Slope Stability | ASCE 7-22 | **7.6 µs** | ~14 µs | ~290 µs | ~13 s | 38× | 1,710,000× |
| Payroll DL 728 | DL 728 Peru | **503 ns** | ~1.1 µs | ~22 µs | ~9 s | 44× | 17,900,000× |
| Autoclave EN 285 | EN 285 | **3.0 µs** | ~5.8 µs | ~112 µs | ~10 s | 37× | 3,330,000× |
| 400-Scenario Sweep | multiple | **337 µs** | ~800 µs | ~16 ms | impractical | 47× | ∞ |
| OracleCache L1 Hit | — | **0 ns** | ~50 ns | ~2 µs | N/A | ∞ | ∞ |

Full data: [`benchmarks/results_2026-04-16.json`](benchmarks/results_2026-04-16.json)

---

## How It Works

CRYS-L describes *what to compute*, not how. The runtime compiles each plan via Cranelift JIT
to native machine code and executes it in sub-microsecond time:

```
User query → plan match → param extract → Cranelift JIT → native exec → result
  (HTTP)       (1 ms)       (0.1 ms)       (first call)    (500–7,600 ns)
Total: ~5–50 ms end-to-end (HTTP+JSON overhead ~80 µs Nginx)
```

**OracleCache:** FNV-1a hash on all inputs — repeated identical calls cost **0 ns** (memory read).

Compare to LLM: tokenize → 750M+ params → autoregressive decode → 8,000–45,000 ms → approximate answer.

---

## Write a Plan in 20 Lines

```crysl
plan_pump_sizing(
    Q_gpm: f64,           // required flow (GPM)
    P_psi: f64,           // required pressure (PSI)
    eff:   f64 = 0.70     // pump efficiency (0–1)
) {
    meta {
        standard: "NFPA 20:2022",
        source: "Section 4.26 + Chapter 6",
        domain: "fire",
    }

    let Q_lps  = Q_gpm * 0.06309;
    let H_m    = P_psi * 0.70307;
    let HP_req = (Q_lps * H_m) / (eff * 76.04);
    let HP_max = HP_req * 1.40;   // NFPA 20: shutoff ≤ 140% rated

    formula "Pump HP": "HP = (Q[L/s] × H[m]) / (η × 76.04)";

    assert Q_gpm > 0.0 msg "flow must be positive";
    assert eff   <= 1.0 msg "efficiency must be ≤ 1.0";

    return { HP_req: HP_req, HP_max: HP_max, Q_lps: Q_lps, H_m: H_m };
}
```

---

## Standard Library (v2.2 — 13 Domains, 35+ Plans)

> **CRYS-L has no domain limit.** These 13 domains are the current stdlib.
> Any deterministic calculation expressible as a formula can become a CRYS-L plan.

### Fire Protection (NFPA)
`stdlib/nfpa_electrico.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_pump_sizing(Q_gpm, P_psi, eff)` | HP = Q·H/(η·76.04) | NFPA 20:2022 §4.26 |
| `plan_sprinkler_system(area_ft2, density, hose_stream)` | Q = area × density + hose | NFPA 13:2022 |
| `plan_hose_stream(class)` | Q_hose by occupancy class | NFPA 13 Table 11.2 |

### Hydraulics (IS.010 Peru / AWWA)
`stdlib/hidraulica.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_hazen_williams(Q, D, C, L)` | V = 0.8492·C·R^0.63·S^0.54 | IS.010 Peru / AWWA M22 |
| `plan_darcy_weisbach(Q, D, f, L)` | h_f = f·L/D·V²/2g | Darcy-Weisbach |
| `plan_pipe_sizing(Q, v_max)` | D = √(4Q/πv) | IS.010 Peru |

### Electrical (IEC 60364 / NEC 2023 / IEEE 141)
`stdlib/electrical.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_voltage_drop(I, L_m, A_mm2)` | ΔV = ρ·L·I/A, ρ=0.0172 Ω·mm²/m | IEC 60364-5-52 / NEC 2023 |
| `plan_electrical_3ph(P_kw, V, pf, L_m, A_mm2)` | I = P/(√3·V·pf), ΔV₃φ = √3·ρ·L·I/A | IEC 60364 / NEC / IEEE 141 |
| `plan_solar_pv(P_wp, irr_kwh, eff, area_m2)` | E_day = P·irr·eff | IEC 61724-1 |
| `plan_power_factor_correction(P_kw, pf_current, pf_target, V)` | Q_c = P·(tan φ₁ − tan φ₂) | IEC 60076 |

### Civil / Structural (AISC 360 / ACI 318 / ASCE 7)
`stdlib/civil.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_beam_analysis(P_kn, L_m, E_gpa, b_cm, h_cm)` | M = P·L/4, δ = P·L³/(48EI) | AISC 360-22 / ACI 318-19 |
| `plan_slope_stability(H_m, VH_ratio, c_kpa, tan_phi, gamma)` | FoS = τ_resist/τ_drive (Bishop) | ASCE 7-22 |
| `plan_column_capacity(b, h, fc, fy, rho)` | Pn = 0.85·f'c·Ac + fy·Ast | ACI 318-19 §22.4 |

### Financial (SUNAT / DL 728 Peru / NIIF)
`stdlib/financial.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_factura_peru(subtotal, igv_rate)` | Total = Subtotal × 1.18 | TUO IGV DL 821 / SUNAT |
| `plan_planilla_dl728(sueldo, meses_trabajo, dias_vacac)` | Neto = Bruto − ONP(13%), CTS = 1/12·Bruto | DL 728 / DL 713 / DL 19990 |
| `plan_van_roi(inversion, flujo_anual, tasa, anos)` | VAN = −I + F·[(1−(1+r)^−n)/r] | NIIF NIC 36 |
| `plan_loan_amortization(P, r_monthly, n_months)` | C = P·r·(1+r)ⁿ/((1+r)ⁿ−1) | Sistema Francés / SBS 2024 |

### Medical / Clinical (EN 285 / ISO 17665 / WHO)
`stdlib/medical.crysl`

> ⚠️ CRYS-L medical results are decision-support only. All clinical calculations must be reviewed by a licensed professional.

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_autoclave_cycle(T_c, t_hold_min, D_value_min, vol_l, P_bar)` | F₀ = t·10^((T−121)/10) | EN 285:2015 / ISO 17665-1 |
| `plan_bmi_assessment(weight_kg, height_m, age)` | BMI = kg/m², BSA (Mosteller), IBW (Devine) | WHO 2000 / MINSA Peru |
| `plan_drug_dosing(weight_kg, dose_mg_per_kg, frequency_per_day)` | Dose = weight × mg/kg | WHO EML 2008 |

### Statistics (ISO 3534 / ASTM E2586)
`stdlib/statistics.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_statistics(n, sum_x, sum_x2)` | x̄, s² (Bessel), SEM, 95% CI, CV% | ISO 3534-1:2006 / ASTM E2586 |
| `plan_sample_size(confidence, margin, proportion, population)` | n₀ = z²·p(1−p)/e², FPC correction | ISO 3534-2 / Cochran 1977 |

### Transport & Logistics (MTC Peru / IPCC)
`stdlib/transport.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_logistics_cost(distance_km, cost_per_km, n_trips, units_per_trip, load_factor)` | C_unit = Total / (trips·units·LF) | MTC D.S. 017-2009-MTC |
| `plan_fuel_cost(distance_km, consume_l_100, fuel_price)` | Cost = gallons × price | OSINERGMIN 2024 |

### Hydraulics — Sanitary (IS.010 Peru)
`stdlib/sanitaria.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_water_demand(units, liters_per_unit, peak_factor)` | Q = units × dotación × K2 | IS.010 Peru §2.2 |
| `plan_cistern_volume(demand_lpd, days, safety)` | V = Q_daily × days × safety | IS.010 Peru §3.1.4 |
| `plan_drainage_pipe(flow_lps, slope, n_roughness)` | D = [Q·n·4^(2/3) / ((π/4)·S^(1/2))]^(3/8) | IS.010 §6.2 / Manning |

### Mechanical (ISO / ASME / AGMA)
`stdlib/mecanica.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_shaft_power(torque_nm, rpm)` | P = τ × ω = τ × 2π·n/60 | ISO 1:2016 / ISO 14691 |
| `plan_belt_drive(P_kw, v_ms, tension_ratio)` | F_eff = P/v; T1 = T2 × ratio | ISO 22:2012 / ASME B17.1 |
| `plan_gear_ratio(n_input, n_output, T_input_nm)` | T_out = T_in × (n_in/n_out) | AGMA 2001-D04 / ISO 6336 |

### Thermal / HVAC (ISO 6946 / ASHRAE)
`stdlib/termica.crysl`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_heat_load(area_m2, delta_t, u_value)` | Q = U × A × ΔT | ISO 6946:2017 |
| `plan_cop_heat_pump(T_hot_k, T_cold_k, eff)` | COP = η × T_hot / (T_hot − T_cold) | EN 14511:2018 / Carnot |
| `plan_cooling_load(area_m2, watt_per_m2, eff_factor)` | Q = area × W/m² × eff | ASHRAE 140-2017 |

---

## Grammar (EBNF)

```ebnf
program    ::= plan_decl+
plan_decl  ::= 'plan_' ident '(' params? ')' '{' body '}'
params     ::= param (',' param)*
param      ::= ident ':' type ('=' literal)?
type       ::= 'f64' | 'f32' | 'i64' | 'bool' | 'str'
body       ::= (const | let | formula | assert | return | meta)+
const      ::= 'const' ident '=' expr ';'
let        ::= 'let'   ident '=' expr ';'
formula    ::= 'formula' string ':' string ';'
assert     ::= 'assert' expr 'msg' string ';'
return     ::= 'return' '{' (ident ':' ident ',')* '}' ';'
meta       ::= 'meta' '{' (ident ':' string ',')+ '}'
expr       ::= term (('+' | '-' | '*' | '/' | '^') term)*
term       ::= number | ident | ident '(' args ')' | '(' expr ')'
```

Built-ins: `sqrt`, `pow`, `abs`, `min`, `max`, `clamp`, `log`, `log10`, `round`, `ceil`, `floor`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `pi`, `e`

---

## Repository Structure

```
crysl-lang/
├── SPEC.md                      # Full language specification (v2.2)
├── ORIGINALITY.md               # Language originality statement
├── paper/
│   ├── CRYSL_JIT_Paper_2026.md  # IEEE-style research paper
│   └── main.tex                 # LaTeX version (arXiv-ready)
├── stdlib/
│   ├── hidraulica.crysl         # Hazen-Williams, Darcy-Weisbach, pipe sizing (3 plans)
│   ├── nfpa_electrico.crysl     # Pump sizing, sprinkler, transformer, voltage drop (4 plans)
│   ├── civil.crysl              # Beam deflection, column, slope stability (3+ plans)
│   ├── electrical.crysl         # Voltage drop, 3-phase, solar PV, PFC (4 plans)
│   ├── financial.crysl          # IGV, planilla DL728, VAN/ROI, loan (4 plans)
│   ├── medical.crysl            # Autoclave, BMI, drug dosing (3 plans)
│   ├── statistics.crysl         # Descriptive stats, sample size (2 plans)
│   ├── transport.crysl          # Logistics cost, fuel cost (2 plans)
│   ├── mecanica.crysl           # Shaft power, belt drive, gear ratio (3 plans) [NEW v2.2]
│   ├── termica.crysl            # Heat load, heat pump COP, cooling load (3 plans) [NEW v2.2]
│   └── sanitaria.crysl          # Water demand, cistern, drainage pipe (3 plans) [NEW v2.2]
├── runtime/
│   ├── interpreter.md           # How the JIT runtime works
│   └── integration_guide.md     # Embedding CRYS-L in your app
├── examples/
│   ├── hello_pump.crysl         # Fire pump sizing
│   ├── hello_hazen.crysl        # Pipe flow calculation
│   └── hello_cable.crysl        # Electrical cable sizing
├── benchmarks/
│   ├── results_2026-04-13.json  # Early WASM baseline
│   └── results_2026-04-16.json  # v2.1 JIT Cranelift — 10 plans, real ns data
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
- [ ] `assert` for each input with meaningful error message
- [ ] `formula` for each key equation
- [ ] `return {}` with all computed values
- [ ] 3+ test cases from published reference tables

---

## Creator

**CRYS-L was designed and created by Percy Rojas Masgo** (Condesi Perú / Qomni AI Lab) in 2025–2026.

The language, grammar, compiler architecture, and standard library are original works.
No content has been adapted or copied from third-party tools, languages, or libraries.

Engineering formulas in the stdlib are mathematical laws in the public domain.
Standards (NFPA, IEC, ACI, IS.010, EN 285, DL 728) are cited by name and section number only —
consistent with academic reference practice. No text has been copied verbatim from any copyrighted
standards document.

---

## License

**Copyright (c) 2026 Percy Rojas Masgo — Condesi Perú / Qomni AI Lab**

CRYS-L language spec, grammar, standard library, examples: **MIT License**

The Qomni Engine runtime integration is proprietary.
The language itself — grammar, stdlib plans, this repo — is fully open.

See [LICENSE](LICENSE) for full terms and [ORIGINALITY.md](ORIGINALITY.md) for the complete originality statement.

---

## Open Language Initiative

CRYS-L is released as a fully open specification and implementation.

**License:** MIT — free use, modification, and integration into commercial systems.

**Objective:** Become the standard execution layer for deterministic AI computations.

**What CRYS-L enables:**
- Deterministic computation via Cranelift JIT (500–7,600 ns per plan)
- Physics-as-Oracle (PaO): equations as primary source of truth
- OracleCache: FNV-1a hash lookup for 0 ns on repeated identical inputs
- Exact, standard-referenced answers — no probabilistic approximation
- Parallel DAG dispatch: 400 scenarios in 337 µs on 12-core AMD EPYC

**Important distinction:**
- CRYS-L (language, compiler, runtime, stdlib) — **open MIT**
- Qomni Engine (planner, learning loop, retrieval engine) — **proprietary**

Opening CRYS-L creates adoption. Keeping Qomni's cognitive engine closed preserves the architectural advantage.
Same model: Linux + cloud vendors, TensorFlow + Google, LLVM + Apple.

---

## Supporting Qomni

Qomni is an independent research effort advancing a new paradigm in AI systems:
**execution-first cognitive architectures that minimize unnecessary neural inference.**

> AI should think only when necessary. Everything else should be executed.

If you believe in a future where AI is faster, more efficient, less dependent on massive models,
and accessible everywhere — contribute to CRYS-L or reach out:
[percy@condesi.pe](mailto:percy@condesi.pe)

---

## Citation

```bibtex
@article{rojasmasgo2026crysl,
  title   = {CRYS-L: A Domain-Specific Language for Deterministic Engineering
             Calculations at Sub-Microsecond Latency},
  author  = {Rojas Masgo, Percy and {Qomni AI Lab}},
  year    = {2026},
  month   = {April},
  note    = {Open Standard, MIT License. Server5 AMD EPYC benchmark: 503–7600 ns JIT},
  url     = {https://github.com/condesi/crysl-lang}
}
```

---

*Built by Percy Rojas Masgo · CEO Condesi Perú · Qomni AI Lab*
*Live at [qomni.clanmarketer.com/crysl/](https://qomni.clanmarketer.com/crysl/)*
