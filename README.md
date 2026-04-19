> ## 🗄️ ARCHIVED — This repository has been consolidated
>
> This repo (`crysl-lang`) is **read-only legacy**. The QOMN project has been
> consolidated into two active repositories. Please use those for any
> new development, issues, or contributions:
>
> - **Runtime and standard library:** [`github.com/condesi/qomn`](https://github.com/condesi/qomn)
>   — Rust source, Cranelift JIT backend, `.qomn` stdlib, tests, install script
> - **Academic paper and reproducibility artifact:** [`github.com/condesi/qomn-paper`](https://github.com/condesi/qomn-paper)
>   — LaTeX source, bibliography, reproducibility scripts, public preprint
>
> **Live demo (unchanged):** [desarrollador.xyz/benchmark.html](https://desarrollador.xyz/benchmark.html)
>
> Existing clones of this repo continue to work for historical reference.
> Existing external links (papers citing this URL, etc.) remain valid since
> GitHub preserves archived repositories indefinitely.
>
> — Percy Rojas Masgo, April 2026

---

# QOMN v2.3 — QOMN Language  *(archived)*

**Created by Percy Rojas Masgo — Condesi Perú / Qomni AI Lab**
**Open standard for deterministic engineering calculations.**
MIT License · [Live Demo](https://desarrollador.xyz/benchmark.html) · [Paper](paper/QOMN_JIT_Paper_2026.md)
**Spec v2.3 RC** — Cranelift native JIT, L4 Register ABI, OracleCache, simulation engine, 13 stdlib domains.

> Write an engineering calculation once. Get **exact answers** in **nanoseconds on the JIT hot path**,
> with the standard and formula cited. No LLM. No approximation. No setup.

---

## Quick Start — Try It Now

**Online (browser, no install):**
👉 [desarrollador.xyz/benchmark.html](https://desarrollador.xyz/benchmark.html)

```
plan_pump_sizing(500, 100, 0.75)
→ Required HP:  16.84 HP  [NFPA 20:2022 §4.26]
→ Shutoff HP:   23.57 HP
→ Latency:      5.37 ns JIT hot path (L4 Register ABI)
→ HTTP:         ~2–4 ms loopback/API path
```

---

## Why QOMN?

| Question | LLM (GPT-4 Turbo) | QOMN v2.3 JIT |
|----------|-------------------|-----------------|
| "500 gpm pump at 100 psi, 75% eff — HP?" | ~17 HP (approximate) | **16.835 HP** (deterministic) |
| Standard cited? | Not guaranteed | NFPA 20:2022 §4.26 |
| Hot-path latency | ~12 s API-class response | **5.37 ns** measured JIT hot path |
| API loopback latency | seconds | **~2–4 ms** TCP + HTTP parse overhead |
| Reproducible? | No (stochastic) | Yes (deterministic) |
| Works offline? | No | Yes |
| Cost per call | API/token cost | **Free local execution** |

**Measured on Server5 KVM AMD EPYC, 2026-04-16:** QOMN v2.3 L4 Register ABI executes selected engineering plans in **5.37–10.69 ns** on the JIT hot path. The simulation engine sustains **13.0M scenarios/sec** on the same KVM host.

---

## Benchmark Results (Server5, KVM AMD EPYC · 12-core · 48 GB · Ubuntu 24.04)

> Real measured numbers, 2026-04-16. JIT hot-path values use the L4 Register ABI and exclude HTTP/TCP overhead.
> API loopback adds approximately **2–4 ms** from TCP, HTTP parsing, JSON serialization, and routing.

| Workload | Measured Result | Notes |
|------|------:|------|
| Fire Pump Sizing | **5.37 ns** | JIT L4 Register ABI hot path |
| Sprinkler System | **9.67 ns** | JIT L4 Register ABI hot path |
| Beam Analysis | **10.69 ns** | JIT L4 Register ABI hot path |
| OracleCache | **~12 ns** | FNV-1a measured cache probe |
| Simulation Engine | **13.0M scenarios/sec** | KVM AMD EPYC, continuous SoA loop |
| Simulation valid fraction | **72.1%** | Physics validation enabled |
| Simulation Pareto size | **507** | Multi-objective Pareto frontier |
| HTTP Loopback | **~2–4 ms** | TCP + HTTP parse/API overhead |

Full data: [`benchmarks/results_2026-04-16.json`](benchmarks/results_2026-04-16.json)

---

## Paper-Grade Benchmarks

### Methodology

- Hardware: Server5 KVM AMD EPYC · 12 cores · 48GB RAM · Contabo VPS · Ubuntu 24.04 LTS
- Runtime: QOMN v2.3 RC · Rust release build · Cranelift native x86-64 JIT · L4 Register ABI
- Hot-path metric: measured nanoseconds, HTTP excluded
- API metric: measured HTTP loopback path, including TCP + HTTP parse overhead
- Simulation metric: continuous SoA AVX2 loop with physics validation and Pareto ranking

### Results

| Benchmark | Result |
|---|---:|
| `plan_pump_sizing` | **5.37 ns** |
| `plan_sprinkler_system` | **9.67 ns** |
| `plan_beam_analysis` | **10.69 ns** |
| OracleCache FNV-1a probe | **~12 ns** |
| Simulation throughput | **13.0M scenarios/sec** |
| Valid fraction | **72.1%** |
| Pareto frontier size | **507** |
| HTTP loopback | **~2–4 ms** |

> Note: older paper drafts referenced an **86.4M scenarios/sec** simulation figure from an earlier benchmark methodology. The current reproducible Server5 KVM measurement is **13.0M scenarios/sec** and should be treated as the authoritative v2.3 RC number.

### Why QOMN vs C++/Rust?

Pure C++/Rust achieve excellent raw arithmetic performance, but QOMN adds:
- **Standards traceability** — every formula cites NFPA/IEC/ISO
- **Physics validation** — inputs and outputs checked against domain bounds
- **Multi-objective optimization** — Pareto-ranked scenario sweeps
- **Domain constants** — documented engineering constants instead of hidden magic numbers
- **Autonomous simulation loop** — `POST /simulation/start` runs continuous validation/optimization

### Real Case: ACI Fire System Optimization

See [`examples/aci_optimizado_completo.qomn`](examples/aci_optimizado_completo.qomn) for a complete multi-plan optimization of a 5-floor office building fire suppression system with:
- NFPA 13-2022 sprinkler demand constraints
- NFPA 20-2022 pump selection rules
- Annual energy cost model
- Multi-objective Pareto: safety margin vs cost vs energy

Full baseline data: [`benchmarks/baseline_comparison_2026-04-16.json`](benchmarks/baseline_comparison_2026-04-16.json)

---

## How It Works

QOMN describes *what to compute*, not how. The runtime compiles each plan via Cranelift JIT
to native x86-64 machine code and executes the hot path through the L4 Register ABI:

```
User/API call → route → parse params → plan dispatch → JIT hot path → result
   HTTP         ms        µs-ms          ns-µs          5–11 ns      output
```

**OracleCache:** FNV-1a hash on all inputs — repeated identical calls measure approximately **12 ns** for cache probe/lookup on Server5 KVM.

Compare to LLM: tokenize → model inference → autoregressive decode → seconds → approximate answer.

---

## Write a Plan in 20 Lines

```qomn
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

## Standard Library (v2.3 — 13 Domains, 35+ Plans)

> **QOMN has no domain limit.** These 13 domains are the current stdlib.
> Any deterministic calculation expressible as a formula can become a QOMN plan.

### Fire Protection (NFPA)
`stdlib/nfpa_electrico.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_pump_sizing(Q_gpm, P_psi, eff)` | HP = Q·H/(η·76.04) | NFPA 20:2022 §4.26 |
| `plan_sprinkler_system(area_ft2, density, hose_stream)` | Q = area × density + hose | NFPA 13:2022 |
| `plan_hose_stream(class)` | Q_hose by occupancy class | NFPA 13 Table 11.2 |

### Hydraulics (IS.010 Peru / AWWA)
`stdlib/hidraulica.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_hazen_williams(Q, D, C, L)` | V = 0.8492·C·R^0.63·S^0.54 | IS.010 Peru / AWWA M22 |
| `plan_darcy_weisbach(Q, D, f, L)` | h_f = f·L/D·V²/2g | Darcy-Weisbach |
| `plan_pipe_sizing(Q, v_max)` | D = √(4Q/πv) | IS.010 Peru |

### Electrical (IEC 60364 / NEC 2023 / IEEE 141)
`stdlib/electrical.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_voltage_drop(I, L_m, A_mm2)` | ΔV = ρ·L·I/A, ρ=0.0172 Ω·mm²/m | IEC 60364-5-52 / NEC 2023 |
| `plan_electrical_3ph(P_kw, V, pf, L_m, A_mm2)` | I = P/(√3·V·pf), ΔV₃φ = √3·ρ·L·I/A | IEC 60364 / NEC / IEEE 141 |
| `plan_solar_pv(P_wp, irr_kwh, eff, area_m2)` | E_day = P·irr·eff | IEC 61724-1 |
| `plan_power_factor_correction(P_kw, pf_current, pf_target, V)` | Q_c = P·(tan φ₁ − tan φ₂) | IEC 60076 |

### Civil / Structural (AISC 360 / ACI 318 / ASCE 7)
`stdlib/civil.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_beam_analysis(P_kn, L_m, E_gpa, b_cm, h_cm)` | M = P·L/4, δ = P·L³/(48EI) | AISC 360-22 / ACI 318-19 |
| `plan_slope_stability(H_m, VH_ratio, c_kpa, tan_phi, gamma)` | FoS = τ_resist/τ_drive (Bishop) | ASCE 7-22 |
| `plan_column_capacity(b, h, fc, fy, rho)` | Pn = 0.85·f'c·Ac + fy·Ast | ACI 318-19 §22.4 |

### Financial (SUNAT / DL 728 Peru / NIIF)
`stdlib/financial.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_factura_peru(subtotal, igv_rate)` | Total = Subtotal × 1.18 | TUO IGV DL 821 / SUNAT |
| `plan_planilla_dl728(sueldo, meses_trabajo, dias_vacac)` | Neto = Bruto − ONP(13%), CTS = 1/12·Bruto | DL 728 / DL 713 / DL 19990 |
| `plan_van_roi(inversion, flujo_anual, tasa, anos)` | VAN = −I + F·[(1−(1+r)^−n)/r] | NIIF NIC 36 |
| `plan_loan_amortization(P, r_monthly, n_months)` | C = P·r·(1+r)ⁿ/((1+r)ⁿ−1) | Sistema Francés / SBS 2024 |

### Medical / Clinical (EN 285 / ISO 17665 / WHO)
`stdlib/medical.qomn`

> ⚠️ QOMN medical results are decision-support only. All clinical calculations must be reviewed by a licensed professional.

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_autoclave_cycle(T_c, t_hold_min, D_value_min, vol_l, P_bar)` | F₀ = t·10^((T−121)/10) | EN 285:2015 / ISO 17665-1 |
| `plan_bmi_assessment(weight_kg, height_m, age)` | BMI = kg/m², BSA (Mosteller), IBW (Devine) | WHO 2000 / MINSA Peru |
| `plan_drug_dosing(weight_kg, dose_mg_per_kg, frequency_per_day)` | Dose = weight × mg/kg | WHO EML 2008 |

### Statistics (ISO 3534 / ASTM E2586)
`stdlib/statistics.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_statistics(n, sum_x, sum_x2)` | x̄, s² (Bessel), SEM, 95% CI, CV% | ISO 3534-1:2006 / ASTM E2586 |
| `plan_sample_size(confidence, margin, proportion, population)` | n₀ = z²·p(1−p)/e², FPC correction | ISO 3534-2 / Cochran 1977 |

### Transport & Logistics (MTC Peru / IPCC)
`stdlib/transport.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_logistics_cost(distance_km, cost_per_km, n_trips, units_per_trip, load_factor)` | C_unit = Total / (trips·units·LF) | MTC D.S. 017-2009-MTC |
| `plan_fuel_cost(distance_km, consume_l_100, fuel_price)` | Cost = gallons × price | OSINERGMIN 2024 |

### Hydraulics — Sanitary (IS.010 Peru)
`stdlib/sanitaria.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_water_demand(units, liters_per_unit, peak_factor)` | Q = units × dotación × K2 | IS.010 Peru §2.2 |
| `plan_cistern_volume(demand_lpd, days, safety)` | V = Q_daily × days × safety | IS.010 Peru §3.1.4 |
| `plan_drainage_pipe(flow_lps, slope, n_roughness)` | D = [Q·n·4^(2/3) / ((π/4)·S^(1/2))]^(3/8) | IS.010 §6.2 / Manning |

### Mechanical (ISO / ASME / AGMA)
`stdlib/mecanica.qomn`

| Plan | Formula | Standard |
|------|---------|---------|
| `plan_shaft_power(torque_nm, rpm)` | P = τ × ω = τ × 2π·n/60 | ISO 1:2016 / ISO 14691 |
| `plan_belt_drive(P_kw, v_ms, tension_ratio)` | F_eff = P/v; T1 = T2 × ratio | ISO 22:2012 / ASME B17.1 |
| `plan_gear_ratio(n_input, n_output, T_input_nm)` | T_out = T_in × (n_in/n_out) | AGMA 2001-D04 / ISO 6336 |

### Thermal / HVAC (ISO 6946 / ASHRAE)
`stdlib/termica.qomn`

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
qomn-lang/
├── SPEC.md                      # Full language specification
├── ORIGINALITY.md               # Language originality statement
├── LIMITATIONS.md               # Known limitations and safety boundaries
├── CHANGELOG.md                 # Version history
├── ROADMAP.md                   # Future milestones
├── paper/
│   ├── CRYSL_JIT_Paper_2026.md  # IEEE-style research paper
│   └── main.tex                 # LaTeX version
├── stdlib/
│   ├── hidraulica.qomn
│   ├── nfpa_electrico.qomn
│   ├── civil.qomn
│   ├── electrical.qomn
│   ├── financial.qomn
│   ├── medical.qomn
│   ├── statistics.qomn
│   ├── transport.qomn
│   ├── mecanica.qomn
│   ├── termica.qomn
│   └── sanitaria.qomn
├── runtime/
│   ├── interpreter.md
│   └── integration_guide.md
├── examples/
│   ├── hello_pump.qomn
│   ├── hello_hazen.qomn
│   └── hello_cable.qomn
├── benchmarks/
│   └── results_2026-04-16.json  # v2.3 RC measured Server5 KVM data
└── README.md
```

---

## Contribute a Plan

1. Fork this repo
2. Write your plan in `stdlib/{domain}.qomn`
3. Add test vectors in `benchmarks/tests/{plan_name}.json`
4. Submit PR — all valid plans following the grammar are welcome

**Checklist:**
- [ ] `meta {}` with standard name + section reference
- [ ] `assert` for each input with meaningful error message
- [ ] `formula` for each key equation
- [ ] `return {}` or `output` with all computed values
- [ ] 3+ test cases from published reference tables

---

## Creator

**QOMN was designed and created by Percy Rojas Masgo** (Condesi Perú / Qomni AI Lab) in 2025–2026.

The language, grammar, compiler architecture, and standard library are original works.
No content has been adapted or copied from third-party tools, languages, or libraries.

Engineering formulas in the stdlib are mathematical laws in the public domain.
Standards (NFPA, IEC, ACI, IS.010, EN 285, DL 728) are cited by name and section number only —
consistent with academic reference practice. No text has been copied verbatim from any copyrighted
standards document.

---

## License

**Copyright (c) 2026 Percy Rojas Masgo — Condesi Perú / Qomni AI Lab**

QOMN language spec, grammar, standard library, examples: **MIT License**

The Qomni Engine runtime integration is proprietary.
The language itself — grammar, stdlib plans, this repo — is fully open.

See [LICENSE](LICENSE) for full terms and [ORIGINALITY.md](ORIGINALITY.md) for the complete originality statement.

---

## Open Language Initiative

QOMN is released as a fully open specification and implementation.

**License:** MIT — free use, modification, and integration into commercial systems.

**Objective:** Become the standard execution layer for deterministic AI computations.

**What QOMN enables:**
- Deterministic computation via Cranelift native JIT and L4 Register ABI
- Physics-as-Oracle (PaO): equations as primary source of truth
- OracleCache: FNV-1a measured cache probe around ~12 ns on Server5 KVM
- Exact, standard-referenced answers — no probabilistic approximation
- Continuous simulation engine: 13.0M scenarios/sec measured on Server5 KVM

**Important distinction:**
- QOMN (language, compiler, runtime, stdlib) — **open MIT**
- Qomni Engine (planner, learning loop, retrieval engine) — **proprietary**

Opening QOMN creates adoption. Keeping Qomni's cognitive engine closed preserves the architectural advantage.
Same model: Linux + cloud vendors, TensorFlow + Google, LLVM + Apple.

---

## Supporting Qomni

Qomni is an independent research effort advancing a new paradigm in AI systems:
**execution-first cognitive architectures that minimize unnecessary neural inference.**

> AI should think only when necessary. Everything else should be executed.

If you believe in a future where AI is faster, more efficient, less dependent on massive models,
and accessible everywhere — contribute to QOMN or reach out:
[percy@condesi.pe](mailto:percy@condesi.pe)

---

## Citation

```bibtex
@article{rojasmasgo2026qomn,
  title   = {QOMN: A Domain-Specific Language for Deterministic Engineering
             Calculations at Nanosecond-Scale Latency},
  author  = {Rojas Masgo, Percy and {Qomni AI Lab}},
  year    = {2026},
  month   = {April},
  note    = {Open Standard, MIT License. Server5 KVM AMD EPYC benchmark: 5.37–10.69 ns JIT hot path; 13.0M scenarios/sec simulation engine},
  url     = {https://github.com/condesi/qomn-lang}
}
```

---

*Built by Percy Rojas Masgo · CEO Condesi Perú · Qomni AI Lab*
*Live at [desarrollador.xyz/benchmark.html](https://desarrollador.xyz/benchmark.html)*
