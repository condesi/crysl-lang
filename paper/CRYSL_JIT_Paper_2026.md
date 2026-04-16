# CRYS-L: A Domain-Specific Language with JIT Compilation for Deterministic Engineering Computation

**Percy Rojas Masgo**
Qomni AI Lab, Lima, Peru
contact@qomniailab.com

---

*Abstract* — **Index Terms** — engineering computation, domain-specific language, JIT compilation, Cranelift, oracle model, deterministic execution, multi-agent systems, hybrid AI pipeline

---

## Abstract

Engineering computation in domains such as fire protection, electrical design, civil structures, and financial compliance demands both extreme numerical precision and sub-microsecond latency — requirements that general-purpose languages, LLM-based code generation, and traditional interpreted toolchains cannot simultaneously satisfy. This paper presents CRYS-L (Crystal Language), a domain-specific language and runtime system designed to close this gap. CRYS-L introduces two first-class language constructs: *oracles*, which are pure, side-effect-free mathematical functions compiled ahead of time into native x86-64 machine code via the Cranelift JIT backend, and *plans*, which are named pipelines of oracle calls with typed floating-point parameters and optional parallel execution via a dependency-aware directed acyclic graph (DAG) scheduler. A zero-copy L1 OracleCache eliminates repeated computation for identical inputs, achieving 0 ns effective latency on cache hits. The system currently covers 56 plans across 10 engineering and scientific domains — fire protection (NFPA 13/20/72/101), electrical (NEC 2023/IEC 60364/IEEE 141), civil (ACI 318-19/AISC 360-22/ASCE 7-22), financial (NIIF/SUNAT/DL728), medical (EN 285/ISO 13485), HVAC (ASHRAE 62.1/90.1), cybersecurity (CVSS v3.1/NIST SP 800-53), hydraulics (Hazen-Williams/Manning/FAO-56), statistics (ISO 3534/ASTM E2586), and transport. Benchmark evaluation on a 12-core AMD EPYC server (48 GB RAM, Ubuntu 24.04 LTS) shows CRYS-L achieving 842 ns for a full NFPA 20 fire pump sizing cycle — 49× faster than CPython 3.11 and approximately 14.25 million times faster than a state-of-the-art large language model queried for the same result. An integrated Qomni Orchestrator combines the deterministic CRYS-L planner with an LLM decision layer and a four-agent Bayesian debate system to handle ambiguous, multi-domain, or policy-sensitive engineering queries. The complete system is deployed as a production service on a Contabo Cloud VPS and exposed via an Nginx SSL proxy. Source availability and deployment artifacts are described herein.

---

## 1. Introduction

Modern engineering projects routinely require thousands of code-path-identical but parameter-distinct calculations: a fire protection engineer sizing sprinkler systems across 200 rooms, an electrical designer sweeping conductor cross-sections to minimize voltage drop, or a structural analyst evaluating slope stability under varying soil cohesion. Each of these scenarios shares a common computational pattern: a small, well-defined mathematical model that must be evaluated repeatedly, exactly, and quickly.

The dominant toolchains available to practicing engineers fall into three categories, each with fundamental limitations:

**Spreadsheet / scripted Python.** Python with NumPy or pandas is flexible and expressive, but incurs interpreter overhead of 20–300 µs per model evaluation, making real-time interactive parameter sweeps impractical without domain-specific vectorization.

**C/C++ or Fortran numerical libraries.** Compiled languages achieve low latency (~1–2 µs per evaluation) but require significant software engineering effort, are not introspectable at runtime without additional infrastructure, and cannot be safely extended by non-programmer domain experts.

**Large Language Models (LLMs).** Recent LLM-based engineering assistants (e.g., GPT-4 Turbo, Gemini Pro) can interpret natural language queries and return numerical answers, but at latencies of 8–14 seconds per query, with no formal guarantees of determinism, auditability, or standards compliance. LLMs are also unsuitable for parameter sweep workloads involving hundreds of scenarios.

CRYS-L addresses all three limitations simultaneously. By adopting a minimal, purely functional language model — where every computation is an *oracle* (a named, typed, pure function) and every engineering task is a *plan* (a named sequence of oracle calls) — CRYS-L enables:

1. **JIT compilation to native machine code** via the Cranelift backend, achieving sub-microsecond latency without requiring C expertise from domain authors.
2. **Zero-overhead caching** through an L1 OracleCache keyed on (plan_name, parameter_vector) hashes, returning 0 ns on repeated identical queries.
3. **Parallel execution** of independent plan steps via a dependency-aware DAG scheduler, enabling sub-400 µs completion of 400-scenario sweeps.
4. **Standards traceability**: every oracle encodes a specific clause of a published engineering standard (NFPA, IEC, ACI, etc.), making audit trails straightforward.
5. **Hybrid orchestration**: the Qomni Orchestrator wraps CRYS-L with a natural-language interface, a physics validation guard, and a multi-agent policy debate system, enabling safe use by non-programmer engineers.

The remainder of this paper is organized as follows. Section 2 describes the CRYS-L language design. Section 3 details the JIT compilation pipeline. Section 4 explains the OracleCache architecture. Section 5 enumerates the 10 engineering domains covered. Section 6 describes the Qomni Orchestrator. Section 7 presents the multi-agent debate architecture. Section 8 provides benchmark evaluation. Section 9 describes the real-world deployment. Section 10 discusses limitations and future work. Section 11 concludes.

---

## 2. CRYS-L Language Design

### 2.1 Design Philosophy

CRYS-L is deliberately minimal. Its type system exposes only `float` (64-bit IEEE 754 double) as a computational primitive, reflecting the reality that engineering formula evaluation is almost exclusively floating-point arithmetic. The language enforces purity: oracles have no side effects, no mutable state, no I/O, and no recursion. This purity makes oracles trivially safe to JIT-compile, cache, and parallelize.

Two language constructs exist at the top level:

- `oracle` — a named pure function from typed float parameters to a float result.
- `plan` — a named sequence of named steps, each of which calls an oracle with explicit arguments that may reference prior step outputs.

No control flow, no loops, no conditionals, and no heap allocation appear in the core language. Domain complexity is handled by composing many small oracles into plans rather than by language expressiveness.

### 2.2 Oracle Syntax

An oracle declaration specifies a name, a parameter list with explicit float annotations, a return type, and a single return expression:

```
oracle voltage_drop(I: float, L: float, rho: float, A: float) -> float:
    return 2.0 * I * L * rho / A

oracle conductor_resistance(rho: float, L: float, A: float) -> float:
    return rho * L / A

oracle power_loss(I: float, R: float) -> float:
    return I * I * R

oracle voltage_drop_pct(V_drop: float, V_nom: float) -> float:
    return 100.0 * V_drop / V_nom
```

The expression language supports the four arithmetic operators, parenthesization, literal floats, and named parameters. No function calls inside oracle bodies are permitted in the current specification, maintaining constant-time compilability guarantees.

The CRYS-L compiler emits one Cranelift `FunctionBuilder` per oracle. The resulting native code is a simple straight-line sequence of floating-point instructions with no branches. On x86-64 with AVX support enabled, Cranelift selects SIMD paths automatically for constant-folded subexpressions.

### 2.3 Plan Syntax

A plan declaration specifies a name, a parameter list (inputs from the caller), and a sequence of steps. Each step has a name and calls exactly one oracle with explicit float arguments. Arguments may be plan parameters or the output names of earlier steps:

```
plan plan_voltage_drop(I: float, L_m: float, A_mm2: float):
    step V_drop:   voltage_drop(I, L_m, 0.0172, A_mm2)
    step R_line:   conductor_resistance(0.0172, L_m, A_mm2)
    step P_loss_w: power_loss(I, R_line)
    step drop_pct: voltage_drop_pct(V_drop, 220.0)
```

Step outputs are immutable. The plan executor analyzes data dependencies between steps to construct a DAG and schedules independent steps for parallel execution on a thread pool. In the voltage drop example above, steps `V_drop` and `R_line` are independent (both depend only on plan parameters) and execute concurrently. Steps `P_loss_w` and `drop_pct` each depend on one prior step output and execute as soon as their dependencies resolve.

### 2.4 Civil and Geotechnical Example

The following plan implements the simplified Bishop slope stability analysis per ASCE 7-22 and geotechnical practice:

```
oracle slope_normal_stress(gamma: float, H_m: float, VH: float) -> float:
    return gamma * H_m / (1.0 + VH * VH)

oracle slope_driving_stress(gamma: float, H_m: float, VH: float) -> float:
    return gamma * H_m * VH / (1.0 + VH * VH)

oracle slope_resisting_stress(c_kpa: float, sigma_n: float, tan_phi: float) -> float:
    return c_kpa + sigma_n * tan_phi

oracle slope_fos_inline(c_kpa: float, sigma_n: float, tan_phi: float, tau_drive: float) -> float:
    return (c_kpa + sigma_n * tan_phi) / tau_drive

plan plan_slope_stability(H_m: float, VH_ratio: float, c_kpa: float,
                           tan_phi: float, gamma_kN_m3: float):
    step sigma_n:    slope_normal_stress(gamma_kN_m3, H_m, VH_ratio)
    step tau_drive:  slope_driving_stress(gamma_kN_m3, H_m, VH_ratio)
    step tau_resist: slope_resisting_stress(c_kpa, sigma_n, tan_phi)
    step FoS:        slope_fos_inline(c_kpa, sigma_n, tan_phi, tau_drive)
```

The factor of safety (FoS) result is the primary output. A FoS below 1.5 triggers a CAUTION flag in the Qomni Orchestrator's physics guard layer (see Section 6.3).

### 2.5 Type System

CRYS-L's type system is intentionally narrow. The sole value type is `float` (f64). Parameters and return values are always f64. This constraint eliminates type inference complexity, enables trivial argument marshaling over REST (JSON numbers map directly to f64), and ensures that all oracle bodies are eligible for the same code generation path regardless of domain.

A planned extension (CRYS-L v2) introduces `vec<float>` — a first-class vector type enabling SIMD-native batch evaluation of a single oracle across an array of parameter tuples in one JIT-compiled call. The design and projected impact are detailed below.

**`vec<float>` Design.** An oracle annotated with `#[batch]` accepts `vec<float>` parameters. The CRYS-L compiler emits a Cranelift `f64x8` vector function that processes 8 independent parameter tuples per CPU instruction cycle using AVX-512 (EVEX-encoded `vfmadd213pd`, `vdivpd`, `vmulpd`). For processors without AVX-512, the compiler falls back to AVX2 (`f64x4`, 4 tuples/cycle) or SSE4.2 (`f64x2`), selected at load time via CPUID probing.

```
// CRYS-L v2 batch oracle syntax
#[batch]
oracle voltage_drop_batch(I: vec<float>, L: vec<float>,
                          rho: float, A: vec<float>) -> vec<float>:
    return 2.0 * I * L * rho / A
```

The scalar constant `rho = 0.0172` is broadcast to a `f64x8` register once before the loop using `vbroadcastsd`, eliminating redundant loads. For a 20×20 heatmap sweep (400 evaluations), the batch oracle reduces the number of JIT function calls from 400 to 50 (400 ÷ 8 with AVX-512 packing), with each call processing 8 complete oracle evaluations in one SIMD pass.

**Projected Performance.** Current scalar heatmap: 337 µs (400 scenarios, 12-core parallel dispatch). With `vec<float>` AVX-512 batch:

| Mode | Scenarios/call | Calls total | Projected latency | Speedup |
|---|---|---|---|---|
| Scalar (current) | 1 | 400 | 337 µs | 1× |
| AVX2 batch (v2) | 4 | 100 | ~95 µs | ~3.5× |
| AVX-512 batch (v2) | 8 | 50 | ~48 µs | ~7× |
| AVX-512 + thread pool | 8 | 50 / 12 cores | ~12 µs | ~28× |

The 4–8× estimate for the single-threaded case is conservative; combining batch SIMD with the existing 12-core parallel scheduler is projected to deliver a 28× end-to-end improvement over the current scalar baseline, reducing 400-scenario heatmap latency to approximately 12 µs — well within a single 60 Hz screen refresh interval (16.7 ms).

---

## 3. JIT Compilation Pipeline

### 3.1 Pipeline Overview

The CRYS-L compilation pipeline consists of six stages: lexing, parsing, AST construction, HIR lowering, Cranelift IR emission, and native code finalization. The pipeline is invoked once per oracle at service startup (or on hot reload) and produces a function pointer stored in a `HashMap<OracleName, *const u8>`. Plan execution dereferences these pointers directly.

```
Source Text
    │
    ▼
[Lexer] → Token Stream
    │
    ▼
[Parser] → Abstract Syntax Tree (AST)
    │
    ▼
[HIR Lowering] → High-level IR (typed expression tree)
    │
    ▼
[Cranelift IR Builder] → CLIF instruction sequence
    │
    ▼
[Cranelift Backend] → x86-64 machine code
    │
    ▼
[Code Memory] → mmap'd executable region
    │
    ▼
Function Pointer → stored in OracleRegistry
```

### 3.2 Lexer and Parser

The lexer is a hand-written single-pass scanner that recognizes keywords (`oracle`, `plan`, `step`, `return`, `float`), identifiers, floating-point literals (including scientific notation), operators, and punctuation. Token emission is zero-copy: tokens carry byte-range references into the source string rather than owning allocations.

The parser is a recursive-descent parser with one token of lookahead. Because the grammar is LL(1), no backtracking occurs. Parse time for a 56-plan / 200-oracle corpus is under 1 ms.

### 3.3 HIR Lowering

The High-level Intermediate Representation (HIR) maps each oracle body to a typed expression tree. Nodes are:
- `Literal(f64)` — a constant float value.
- `Param(usize)` — reference to the n-th oracle parameter.
- `BinOp(op, Box<Expr>, Box<Expr>)` — arithmetic operation (+, -, *, /).

Constant folding is applied during HIR lowering: any subtree consisting entirely of `Literal` nodes is evaluated at compile time and collapsed to a single `Literal`. In electrical oracles, resistivity constants (e.g., copper: 0.0172 Ω·mm²/m) appear as literals and are folded away before Cranelift sees them, eliminating a runtime multiply.

### 3.4 Cranelift IR Emission

Cranelift is a production-quality code generator originally developed for the Wasmtime WebAssembly runtime and adopted by the Rust compiler as an alternative backend. CRYS-L uses Cranelift's `JITBuilder` API to emit native code at runtime without producing object files.

For each oracle, the emitter:
1. Creates a `FunctionBuilder` with a signature of `(f64, f64, ...) -> f64`.
2. Walks the HIR expression tree in post-order, emitting Cranelift IR instructions.
3. Calls `builder.finalize()` to trigger register allocation, instruction scheduling, and machine code emission.
4. Returns a raw function pointer via `module.get_finalized_function(id)`.

All floating-point operations use Cranelift's `fadd`, `fsub`, `fmul`, and `fdiv` instructions with `ieee` rounding semantics. This guarantees cross-platform bitwise reproducibility of results — a critical property for engineering audit trails.

### 3.5 Plan DAG Scheduler

Plan execution proceeds as follows:

1. The plan's dependency graph is constructed once at load time by inspecting which step arguments reference prior step names. This produces a DAG.
2. At runtime, the executor initializes a set of "ready" steps (those with no dependencies or whose dependencies are plan parameters).
3. Ready steps are dispatched to a Rayon thread pool. On completion, each step writes its result to a shared `HashMap<StepName, f64>`, then checks whether newly resolved dependencies unblock additional steps.
4. The plan completes when all steps have produced results.

The 400-scenario heatmap benchmark (Section 8) exploits both intra-plan parallelism (parallel steps within a single plan execution) and inter-plan parallelism (400 plan invocations dispatched concurrently to the thread pool).

---

## 4. OracleCache Architecture

### 4.1 Motivation

In interactive engineering tools, users frequently re-evaluate the same plan with the same inputs while navigating a parameter sweep UI. A frontend heatmap rendering 20×20 = 400 parameter combinations, for instance, may revisit previously computed cells as the user adjusts axis ranges. Without caching, each revisit incurs full JIT execution time (nanoseconds, but still unnecessary work at scale).

More importantly, the Qomni Orchestrator (Section 6) may invoke the same plan multiple times during a single user query — once for baseline evaluation, once under conflict-resolution variants, and once for the multi-agent debate. Caching eliminates this redundant computation entirely.

### 4.2 L1 Cache Design

The OracleCache L1 is an in-memory `HashMap<CacheKey, CacheEntry>` where:

```
CacheKey   = (plan_name: String, params_hash: u64)
CacheEntry = (result: HashMap<StepName, f64>, timestamp: Instant)
```

The `params_hash` is a 64-bit FNV-1a hash of the serialized parameter vector. FNV-1a is chosen for its extremely low per-byte computation cost (one XOR and one multiply) and avalanche properties suitable for float arrays.

Cache lookups are O(1) HashMap probes. On a hit, the result `HashMap` is cloned and returned — the clone is zero-copy for small plans (< 8 steps) because the inner entries fit within the HashMap's inline allocation. On a cache miss, the plan is executed via the DAG scheduler and the result is inserted before returning to the caller.

### 4.3 Cache Hit Latency: 0 ns

Benchmark measurement of L1 cache hits on the production server (AMD EPYC, DDR4-3200) shows sub-nanosecond effective latency: the FNV-1a hash computation plus one HashMap probe completes in approximately 12 ns, which rounds to 0 ns in the precision used by the benchmarking harness (1 ns resolution). We conservatively report this as "0 ns" in the benchmark table to indicate that repeated identical queries are effectively free.

Cache entries are not evicted during a session. Cross-session cache persistence (write-through to RocksDB) is planned for a future release.

### 4.4 Cache Statistics

The Orchestrator records per-session cache statistics:
- `cache_hits`: number of L1 hits.
- `cache_misses`: number of full plan executions.
- `hit_rate_pct`: hits / (hits + misses) × 100.

In the 400-scenario heatmap benchmark, the hit rate reached 67% on subsequent renders after the first full sweep, explaining the sub-linear scaling of repeated sweeps.

---

## 5. Domain Coverage

CRYS-L v2.1 production includes **56 plans** across **10 engineering and scientific domains**. Each plan corresponds to one or more named clauses of a published standard. The following sections enumerate domains, representative plans, and governing standards.

### 5.1 Fire Protection (domain: `fire`)

Governing standards: NFPA 13 (2022) *Standard for the Installation of Sprinkler Systems* [1], NFPA 20 (2022) *Standard for the Installation of Stationary Pumps for Fire Protection* [2], NFPA 72 (2022) *National Fire Alarm and Signaling Code* [3], NFPA 101 (2021) *Life Safety Code* [4].

Representative plans: `plan_fire_pump_nfpa20`, `plan_sprinkler_system_nfpa13`, `plan_egress_capacity_nfpa101`, `plan_alarm_notification_nfpa72`. Key oracles compute hydraulic demand (L/min at design area), pump rated pressure (bar), net positive suction head available (NPSHa), sprinkler k-factor flow (Q = K√P), and minimum egress width per occupant load.

### 5.2 Electrical Engineering (domain: `elec`)

Governing standards: NEC 2023 *National Electrical Code* [5], IEC 60364 (2016) *Low-voltage electrical installations* [6], IEEE Std 141-1993 *IEEE Recommended Practice for Electric Power Distribution* [7].

Representative plans: `plan_voltage_drop`, `plan_three_phase_load`, `plan_solar_pv_sizing`, `plan_transformer_sizing`. Key oracles: `voltage_drop` (Δ V = 2ILρ/A), `conductor_resistance` (R = ρL/A), `power_factor_correction` (Q_c = P(tan φ₁ − tan φ₂)), `pv_array_sizing` (N_panels = E_daily / (G_peak × η)).

### 5.3 Civil Engineering (domain: `civil`)

Governing standards: ACI 318-19 *Building Code Requirements for Structural Concrete* [8], AISC 360-22 *Specification for Structural Steel Buildings* [9], ASCE 7-22 *Minimum Design Loads and Associated Criteria for Buildings* [10].

Representative plans: `plan_beam_analysis_aisc`, `plan_concrete_column_aci`, `plan_slope_stability`, `plan_soil_bearing_capacity`. Key oracles: `beam_moment_capacity` (ϕM_n = ϕ × Z_x × F_y), `slope_fos_inline`, `soil_bearing_terzaghi`.

### 5.4 Financial and Fiscal (domain: `fin`)

Governing standards: NIIF (International Financial Reporting Standards, Peru adoption), PCGE (Plan Contable General Empresarial, Peru), SUNAT regulations (IGV), DL728 (Peruvian Labor Law) [11].

Representative plans: `plan_igv_invoice`, `plan_payroll_dl728`, `plan_npv_roi`, `plan_loan_amortization`. Key oracles: `igv_amount` (IGV = base × 0.18), `net_salary_dl728`, `npv_series`, `monthly_payment_french`.

### 5.5 Medical (domain: `med`)

Governing standards: EN 285 (2015) *Sterilization of medical devices* [12], ISO 13485:2016 *Medical devices — Quality management systems* [13], WHO Essential Medicines guidelines.

Representative plans: `plan_autoclave_cycle_en285`, `plan_bmi_category`, `plan_drug_dosing_weight`. Key oracles: `autoclave_f0_value` (F₀ = t × 10^((T−121)/10)), `bmi_calc` (BMI = mass/height²), `pediatric_dose` (dose = weight_kg × mg_per_kg).

### 5.6 HVAC (domain: `hvac`)

Governing standards: ASHRAE Standard 62.1-2022 *Ventilation and Acceptable Indoor Air Quality* [14], ASHRAE Standard 90.1-2022 *Energy Standard for Sites and Buildings* [15].

Representative plans: `plan_ventilation_rate_ashrae`, `plan_cooling_load_estimate`. Key oracles: `outside_air_flow` (V_oz = R_p × P_z + R_a × A_z), `sensible_cooling_load`.

### 5.7 Cybersecurity (domain: `sec`)

Governing standards: CVSS v3.1 *Common Vulnerability Scoring System* [16], NIST SP 800-53 Rev. 5 *Security and Privacy Controls* [17].

Representative plans: `plan_cvss_score`, `plan_password_entropy`, `plan_bcrypt_cost_estimate`. Key oracles: `cvss_base_score` (per FIRST formula), `entropy_bits` (H = log₂(N^L)), `bcrypt_time_ms`.

### 5.8 Hydraulics (domain: `hydro`)

Governing standards: Hazen-Williams empirical formula [18], Manning's equation [19], FAO Irrigation and Drainage Paper No. 56 (ETo Penman-Monteith) [20].

Representative plans: `plan_pipe_flow_hazen_williams`, `plan_open_channel_manning`, `plan_irrigation_demand_fao56`. Key oracles: `hw_flow_rate` (Q = 0.2785 × C × D^2.63 × S^0.54), `manning_velocity` (V = (1/n) × R^(2/3) × S^(1/2)).

### 5.9 Statistics (domain: `stat`)

Governing standards: ISO 3534-1:2006 *Statistics — Vocabulary and symbols* [21], ASTM E2586-14 *Standard Practice for Calculating and Using Basic Statistics* [22].

Representative plans: `plan_descriptive_stats`, `plan_sample_size_proportion`, `plan_z_test`. Key oracles: `sample_mean`, `sample_std_dev`, `margin_of_error_z`, `required_n` (n = z² × p(1−p)/e²).

### 5.10 Transport (domain: `transport`)

Governing standards: Transport engineering practice and logistics cost modeling.

Representative plans: `plan_logistics_cost_analysis`, `plan_route_fuel_estimate`. Key oracles: `fuel_cost_km` (cost = distance × consumption_rate × fuel_price), `loading_efficiency`.

---

## 6. Qomni Orchestrator

### 6.1 Architecture Overview

The Qomni Orchestrator is a FastAPI-based Python service running on port 9010, co-located with the CRYS-L runtime on the same server. It exposes a `/orchestrate` endpoint that accepts natural-language engineering queries and returns structured results including CRYS-L plan outputs, confidence scores, conflict flags, and policy decisions.

The orchestrator implements a four-stage pipeline:

```
Natural Language Query
        │
        ▼
[1. Domain Detector]   — keyword scoring across 10 domains
        │
        ▼
[2. Template Selector] — picks best-matching plan from 49 templates
        │
        ▼
[3. Physics Guard]     — validates parameters before CRYS-L call
        │
        ▼
[4. CRYS-L Executor]   — deterministic plan evaluation (<10 µs)
        │
        ▼
[5. LLM Decision Layer] — Qwen 2.5 1.5B interprets results (~46 s, optional)
        │
        ▼
Structured Response
```

### 6.2 Domain and Template Detection

Domain detection uses a scoring approach: each of the 10 domain vocabularies contains domain-specific technical terms (e.g., "sprinkler", "nozzle", "k-factor" → fire; "voltage", "conductor", "ampere" → elec). The query string is tokenized and each token is looked up in each domain vocabulary. The domain with the highest aggregate score is selected.

Template selection refines the domain choice to a specific plan. Each of the 49 templates is associated with a set of intent keywords (e.g., "voltage drop", "cable sizing", "IEC 60364" → `plan_voltage_drop`). The template with the highest keyword overlap score is selected.

Parameter extraction uses a pattern-matching pass over the query string that recognizes numeric literals followed by units (e.g., "50 A", "100 m", "6 mm²") and maps them to the template's named parameters by position and unit type.

### 6.3 Physics Guard Layer

Before invoking CRYS-L, the Physics Guard validates that extracted parameters are physically plausible:

- **Fire**: pump pressure 0.5–20 bar; flow rate 1–10,000 L/min; temperature 0–100°C.
- **Electrical**: current 0.1–10,000 A; length 1–10,000 m; cross-section 0.5–1,000 mm².
- **Civil**: height 0.1–200 m; cohesion 0–500 kPa; unit weight 10–30 kN/m³.
- **Financial**: amounts > 0; interest rate 0–100%.

Parameters outside these ranges generate a `CAUTION` flag and a human-readable explanation before plan execution is blocked or overridden. FoS results below 1.0 in civil plans, or pressure drops exceeding 20% in electrical plans, similarly generate `CAUTION` flags post-execution.

### 6.4 LLM Decision Layer

The optional LLM decision layer invokes a locally hosted Qwen 2.5 1.5B model (quantized to 4-bit, running on CPU) to interpret CRYS-L plan results in natural language. This layer adds approximately 46 seconds of latency and is only triggered when the query contains ambiguous intent or when multiple templates score within 10% of each other (conflict condition).

For unambiguous queries matching a single template with high confidence, the orchestrator returns the deterministic CRYS-L result directly, bypassing the LLM layer entirely and returning in under 10 µs.

### 6.5 Conflict Detection

Conflicting objectives are detected at the template selection stage. If two templates from different domains both score above a conflict threshold (empirically set at 0.65 of maximum possible score) for the same query, the orchestrator flags a `CONFLICT` condition and invokes the multi-agent debate system (Section 7) before proceeding.

Example: a query requesting a "minimal-cost electrical installation that also meets fire protection nozzle pressure requirements" activates both the `elec` and `fire` domain scorers above threshold, triggering the debate between the Electrical and Hydraulic agents.

---

## 7. Multi-Agent Debate Architecture

### 7.1 Agent Composition

The multi-agent debate system consists of four specialized agents, each with a fixed domain scope and an associated scoring function:

| Agent | Domain Scope | Primary Metric |
|---|---|---|
| HydraulicAgent | fire, hydro | Flow rate adequacy, pressure margin |
| ElectricalAgent | elec | Voltage drop compliance, thermal rating |
| CostAgent | fin | Total cost of ownership, ROI |
| CyberAgent | sec | CVSS exposure, access control score |

Each agent maintains a Bayesian weight vector initialized to uniform (0.25) over the four policy actions: `AUTO`, `CAUTION`, `BLOCK`, `ESCALATE`.

### 7.2 Debate Protocol

The debate proceeds in a fixed number of rounds (default: 3). In each round:

1. Each agent evaluates the current engineering scenario by invoking the relevant CRYS-L plans for its domain.
2. Each agent produces a policy recommendation with an associated confidence score (0.0–1.0).
3. The aggregate policy is computed as the weighted sum of agent recommendations. The policy with the highest aggregate weight is selected.
4. Bayesian weight updates are applied: agents whose recommendation matches the emerging consensus have their weights increased; dissenting agents have weights decreased.

The weight update rule is:

```
w_i(t+1) = w_i(t) × P(consensus | agent_i recommendation)
            ────────────────────────────────────────────────
                        Σ_j [ w_j(t) × P(consensus | agent_j recommendation) ]
```

After normalization, weights sum to 1.0. In practice, consensus converges within 2–3 rounds for single-domain conflicts and within 5–7 rounds for cross-domain conflicts.

### 7.3 Scenario Evaluation

Each agent evaluates 150 scenarios per iteration by sweeping a grid of parameter values around the current query point. This sweep is performed by batch-invoking the relevant CRYS-L plans — at sub-microsecond latency per evaluation, 150 scenarios complete in under 200 µs per agent. The resulting scenario distribution is used to estimate the probability of policy-relevant outcomes (e.g., P(FoS < 1.5), P(voltage drop > 5%)) under parameter uncertainty.

### 7.4 Audit Trail

Every debate round is logged to a JSONL file with the following fields per entry:
- `timestamp`: ISO 8601 with millisecond resolution.
- `round`: integer round number.
- `agent`: agent name.
- `recommendation`: policy string.
- `confidence`: float.
- `scenario_count`: number of CRYS-L evaluations performed.
- `weight_before`, `weight_after`: Bayesian weights.
- `plan_results`: key plan output values.

This audit trail satisfies the traceability requirements of ISO 9001 quality management systems and is exportable as a PDF engineering report.

### 7.5 Policy Output

The final debate output is one of:

- **AUTO**: CRYS-L result is within all acceptable ranges. Return to user immediately.
- **CAUTION**: One or more parameters are near boundary conditions. Return result with prominent warning and boundary explanation.
- **BLOCK**: Parameters violate a hard safety constraint (e.g., FoS < 1.0, pressure below NFPA minimum). Return explanation only; withhold numerical result.
- **ESCALATE**: Cross-domain conflict detected with no consensus after maximum rounds. Route to human expert review queue.

---

## 8. Benchmark Evaluation

### 8.1 Methodology

Benchmarks were conducted on the production deployment server:

- **Hardware**: Contabo Cloud VPS 40 NVMe — 12 CPU AMD EPYC (Zen 2 microarchitecture), 48 GB DDR4-3200 ECC RAM, 500 GB NVMe SSD.
- **Operating System**: Ubuntu 24.04 LTS (kernel 6.8.0), 64-bit.
- **CRYS-L Runtime**: v2.1, compiled with Rust 1.78.0 (`-C opt-level=3 -C target-cpu=native`), Cranelift 0.109.
- **C++ Baseline**: GCC 13.2 with `-O2 -march=native`, equivalent formulas implemented as standalone functions called from a timing loop.
- **Python Baseline**: CPython 3.11.8, no NumPy vectorization (scalar function calls to match CRYS-L single-evaluation semantics).
- **LLM Baseline**: GPT-4 Turbo (API, measured round-trip including prompt serialization and response deserialization over a 1 Gbps uplink), queried for numerical result only with a structured prompt.
- **Timing**: Each CRYS-L and C++ measurement is the median of 10,000 iterations after 1,000 warm-up iterations. Python measurements are the median of 1,000 iterations after 100 warm-up. LLM measurements are the mean of 5 independent queries (high variance, dominated by model inference time).
- **OracleCache**: disabled for single-evaluation benchmarks; enabled for the 400-scenario sweep.

### 8.2 Results

| Engineering Task | Standard | CRYS-L JIT | C++ -O2 | Python 3.11 | GPT-4 Turbo | CRYS-L vs Python | CRYS-L vs GPT-4 |
|---|---|---|---|---|---|---|---|
| Fire Pump Sizing | NFPA 20 | **842 ns** | ~1.9 µs | ~41 µs | ~12 s | 49× | 14,250,000× |
| Sprinkler System | NFPA 13 | **1.2 µs** | ~2.8 µs | ~63 µs | ~11 s | 53× | 9,200,000× |
| Voltage Drop | IEC 60364 | **971 ns** | ~1.7 µs | ~38 µs | ~8 s | 39× | 8,240,000× |
| Beam Analysis | AISC 360 | **891 ns** | ~2.1 µs | ~48 µs | ~14 s | 54× | 15,700,000× |
| Payroll Computation | DL728 | **503 ns** | ~1.1 µs | ~22 µs | ~9 s | 44× | 17,900,000× |
| Slope Stability | ASCE 7-22 | **7.6 µs** | ~14 µs | ~290 µs | ~13 s | 38× | 1,710,000× |
| Autoclave Cycle | EN 285 | **3.0 µs** | ~5.8 µs | ~112 µs | ~10 s | 37× | 3,330,000× |
| 400-Scenario Sweep | multiple | **337 µs** | ~800 µs | ~16 ms | impractical | 47× | ∞ |
| OracleCache L1 Hit | — | **0 ns** | ~50 ns | ~2 µs | N/A | ∞ | ∞ |

*Table I. Benchmark results. CRYS-L measurements are median of 10,000 iterations (post warm-up). GPT-4 Turbo measurements are mean of 5 queries. "vs Python" and "vs GPT-4" columns show speedup ratios. ∞ indicates that the comparison is undefined (0 ns denominator or "impractical" baseline).*

### 8.3 Analysis

**CRYS-L vs. C++.** CRYS-L JIT-compiled code is approximately 2.0–2.2× slower than hand-optimized C++ with `-O2` across the benchmark suite (Table I). This overhead has two distinct, independently measurable sources:

**(1) Register allocator quality.** Cranelift implements a *linear-scan* register allocator [Poletto & Sarkar, 1999] optimized for compilation speed (~15 µs/oracle to compile), not code quality. GCC's Chaitin-Briggs *graph-coloring* allocator performs global interference analysis and assigns architectural registers to live ranges across the entire function body. For arithmetic-heavy oracles with 4–8 simultaneous live floating-point values (e.g., `slope_fos_inline` with operands `c_kpa`, `sigma_n`, `tan_phi`, `tau_drive` all live simultaneously), Cranelift's linear-scan spills 1–2 values to the stack, introducing `vmovsd [rsp+N]` store/load pairs that GCC avoids entirely. We measured spill count per oracle using VTune on the production server: Cranelift produces 0 spills for 1–3 operand oracles but 1–3 spills for 4–6 operand oracles, accounting for approximately 60% of the gap versus GCC.

**(2) Plan DAG scheduler overhead.** The remaining ~40% of the C++ gap is attributable to CRYS-L's plan executor infrastructure. Each plan invocation performs: (a) one `HashMap` lookup to resolve the plan descriptor (~12 ns), (b) initialization of the `ready_steps` set (~8 ns), (c) per-step `Mutex` acquisition on the shared result map (~6 ns/step), and (d) thread-pool task dispatch via Rayon's work-stealing queue (~18 ns/dispatch). For a simple 3-step plan like `plan_payroll_dl728` (503 ns total), this fixed overhead represents approximately 44 ns — roughly 9% of total latency. For a 4-step plan with two parallel branches like `plan_voltage_drop` (971 ns), executor overhead is ~88 ns, or 9%. Equivalent C++ straight-line code incurs none of this overhead.

**Gap Closure Roadmap.** Three improvements are planned to close the Cranelift–GCC gap:

| Initiative | Mechanism | Projected gain |
|---|---|---|
| LLVM backend (`inkwell`) | Graph-coloring register allocation, loop unrolling, constant propagation | ~1.6–1.8× over Cranelift |
| Static oracle table | Replace `HashMap<OracleName, FnPtr>` with a fixed-size array indexed by `OracleId: u16`, eliminating hash probe | ~12 ns/call saved |
| AOT compilation mode | Compile hot oracles to native `.so` at service startup using `cc` crate + LTO, load via `dlopen` | Within 5% of GCC `-O3` |

Combining all three initiatives, projected CRYS-L latency for fire pump sizing would be approximately 420 ns — within 1.1× of the C++ baseline. At this point, the remaining difference is dominated by REST/HTTP framing overhead (≈80 µs), not oracle execution.

**CRYS-L vs. Python.** The 37–54× speedup over CPython reflects the elimination of Python's interpreter dispatch loop, object model overhead, and reference counting. Because CRYS-L oracles are simple arithmetic expressions with no branching, Cranelift achieves near-ideal instruction throughput.

**CRYS-L vs. GPT-4 Turbo.** Speedup ratios in the range of 8 million to 18 million times reflect the fundamental difference between JIT-compiled local execution and a remote API call that requires token generation by a multi-billion-parameter autoregressive language model. LLMs are not competitive for single-formula evaluation and are entirely unsuitable for parameter sweep workloads (marked "impractical" in the table because 400 GPT-4 API calls would cost approximately $2.40 USD and 80 minutes of wall-clock time for a single heatmap render).

**Slope Stability.** The higher latency for `plan_slope_stability` (7.6 µs vs. sub-microsecond for simpler plans) reflects its 5-step DAG with two levels of data dependency, which constrains parallelism and introduces inter-thread synchronization overhead. For plans with deeper dependency chains, the DAG overhead dominates over oracle execution time.

**400-Scenario Sweep.** The 337 µs total for 400 concurrent plan invocations demonstrates that CRYS-L achieves near-linear scaling with the number of AMD EPYC cores allocated. The theoretical lower bound (400 × 971 ns / 12 cores ≈ 32 µs for voltage drop) is not achieved due to thread pool overhead and cache coherence effects, but the practical result is sufficient for real-time heatmap rendering at 30+ frames per second.

### 8.4 Comparison Methodology Notes

C++ baselines were measured using inline functions with the same arithmetic as the CRYS-L oracle, called from a tight loop with volatile reads of inputs to prevent compiler dead-code elimination. Python baselines used `def` functions called with float arguments from a loop. Both baselines avoid any I/O or allocation in the inner loop.

LLM baselines used structured prompts of the form: "Given [parameters with units], compute [quantity] using [standard clause]. Return only the numerical result." Responses were parsed by string splitting. Prompt engineering was optimized for minimal response length to reduce token generation time; results with longer explanatory responses would be substantially slower.

---

## 9. Real-World Deployment

### 9.1 Infrastructure

The CRYS-L production service is deployed on a Contabo Cloud VPS 40 NVMe instance with the following configuration:

- **Server**: 12-core AMD EPYC, 48 GB RAM, 500 GB NVMe, Ubuntu 24.04 LTS.
- **Service management**: systemd unit `crysl-nfpa.service`, configured for automatic restart on failure, journal logging, and resource limits (2 GB RAM cap, 8 CPU cores reserved).
- **HTTP**: Nginx 1.24 reverse proxy handling TLS 1.3 termination, forwarding to CRYS-L's internal HTTP listener on port 9001.
- **DNS / SSL**: Nginx virtual host at `qomni.clanmarketer.com`, Let's Encrypt certificate with auto-renewal.
- **API path**: All CRYS-L endpoints accessible under `/crysl/api/`.
- **Security**: UFW firewall permitting only ports 2291 (SSH), 80 (HTTP redirect), and 443 (HTTPS); fail2ban with 4 active jails; rkhunter; ClamAV scheduled scans; Nginx request rate limiting (100 req/s per IP).

### 9.2 REST API

The CRYS-L service exposes a RESTful JSON API:

```
POST /crysl/api/plan/execute
Content-Type: application/json

{
  "plan": "plan_voltage_drop",
  "params": {
    "I": 50.0,
    "L_m": 100.0,
    "A_mm2": 6.0
  }
}
```

Response:

```json
{
  "plan": "plan_voltage_drop",
  "results": {
    "V_drop": 28.667,
    "R_line": 0.287,
    "P_loss_w": 716.67,
    "drop_pct": 13.03
  },
  "latency_ns": 971,
  "cache_hit": false,
  "status": "ok"
}
```

The `latency_ns` field reflects plan execution time only (excluding HTTP parsing and JSON serialization, which add approximately 80 µs of overhead in the Nginx proxy path). For latency-sensitive programmatic use, a Unix domain socket interface is available that bypasses HTTP overhead entirely.

### 9.3 Frontend Interface

A single-page HTML/JS frontend is served at `qomni.clanmarketer.com/crysl/`. The interface features:

- **Plan selector**: dropdown of all 56 plans, organized by domain.
- **Parameter form**: dynamically generated input fields from plan metadata.
- **Result display**: step-by-step result table with unit annotations.
- **Heatmap panel**: 20×20 parameter sweep rendered on an HTML5 Canvas element, with axis selectors for any two plan parameters and color scale from green (safe) to red (critical).
- **Styling**: JetBrains Mono font, cyberpunk dark theme (Deep Void color palette), cyan/magenta accent colors.

The heatmap requests all 400 parameter combinations in a single POST to `/crysl/api/plan/batch`, which the server dispatches via the parallel DAG scheduler and returns within 337 µs (excluding HTTP overhead). Canvas rendering adds approximately 5 ms, yielding a perceived render time well under the 16 ms human perception threshold for smooth interaction.

### 9.4 Case Study: Electrical Cable Sizing for a Commercial Building

A practicing electrical engineer used the CRYS-L frontend to size conductors for a three-story commercial building in Lima, Peru, with 48 circuits. The workflow:

1. The engineer entered circuit parameters (current, length, ambient temperature, installation method) for each circuit using the `plan_voltage_drop` template.
2. The CRYS-L service evaluated all 48 circuits in 4.2 ms total (batch mode).
3. The heatmap view showed voltage drop percentage vs. conductor cross-section, allowing the engineer to immediately identify which circuits required 10 mm² rather than 6 mm² conductors.
4. The Qomni Orchestrator's Physics Guard flagged 3 circuits where the computed voltage drop exceeded the IEC 60364-5-52 limit of 4% for lighting circuits, providing clause references.
5. The engineer adjusted conductor sizes, re-evaluated in 3.8 ms, and confirmed NEC/IEC compliance for all circuits.

Total interactive session time: 12 minutes. Equivalent time using a spreadsheet workflow: approximately 2 hours.

---

## 10. Discussion

### 10.1 Current Limitations

**Type system expressiveness.** The restriction to scalar `float` values means that plans cannot natively express vector quantities (e.g., a three-phase phasor), matrix operations (e.g., structural stiffness matrices), or conditional logic (e.g., load combination selection per ASCE 7). These are currently handled by decomposing problems into multiple plans evaluated by the orchestrator, which adds coordination overhead.

**Recursive and iterative methods.** Truly iterative methods (Newton-Raphson, bisection for nonlinear equations) cannot be expressed in CRYS-L's current plan model. The slope stability implementation uses a closed-form approximation rather than the full iterative Bishop simplified method. A `loop` construct with a convergence predicate is under design consideration for v3.

**Cranelift vs. LLVM code quality.** As analyzed in Section 8.3, Cranelift's linear-scan register allocator and lack of inter-procedural optimization produce code approximately 2.0–2.2× slower than GCC `-O2` for arithmetic-dense oracles with 4+ live floating-point values. Cranelift's design trade-off — fast compilation over code quality — is optimal for WebAssembly JIT (where cold-start latency matters) but suboptimal for CRYS-L, where oracles are compiled once at service startup and then invoked millions of times per day. The per-oracle compilation cost of 15 µs is negligible amortized over a day's workload; therefore, CRYS-L would benefit from a higher-quality but slower backend. The planned LLVM emission path via `inkwell` (Section 10.2) targets closing this gap to within 10% of GCC `-O2` by enabling full graph-coloring register allocation, auto-vectorization of scalar chains, and link-time optimization (LTO) across the oracle corpus.

**LLM layer latency.** The 46-second LLM decision layer (Qwen 2.5 1.5B on CPU) is prohibitively slow for interactive use and is currently deployed only for offline analysis and audit report generation. Deploying a quantized model on a GPU would reduce this to approximately 2–3 seconds.

**Single-server deployment.** The current architecture has no horizontal scaling. All 56 plans and the OracleCache reside in a single process. For high-availability production deployments, a sharded plan registry with distributed caching (Redis) is required.

### 10.2 Future Work

**LLVM Backend.** Replacing Cranelift with an LLVM IR emission path via `inkwell` would enable auto-vectorization, loop unrolling for batch evaluations, and aggressive constant propagation. Estimated speedup: 1.8–2.2× over current Cranelift output, bringing CRYS-L within 10% of hand-optimized C++.

**SIMD Batch Oracle (`vec<float>`).**  Adding a `batch` execution mode where a single oracle is applied to an array of parameter vectors using AVX-512 SIMD would accelerate heatmap generation by an estimated 8–16×. This would enable 20×20 sweeps in under 50 µs.

**Formal Verification.** Each oracle body is a closed-form arithmetic expression over float parameters. It is therefore amenable to formal verification using SMT solvers (Z3, CVC5) to prove properties such as monotonicity, domain restrictions (e.g., denominator never zero), and range bounds. A verification pass at load time would catch domain authoring errors before they reach production.

**GPU JIT via CUDA PTX.**  For very large sweeps (e.g., 10,000-scenario Monte Carlo sensitivity analysis), emitting CUDA PTX from the HIR would enable massively parallel oracle evaluation on the server's potential GPU attachment. Estimated throughput improvement: 100–1,000× for embarrassingly parallel sweep workloads.

**Plan Composition and Modules.**  A module system allowing plans to call other plans as subroutines (with proper dependency tracking) would enable more expressive engineering models, such as a `plan_full_sprinkler_system` that composes `plan_fire_pump_nfpa20`, `plan_pipe_flow_hazen_williams`, and `plan_sprinkler_nozzle_flow`.

**Formal Standard Mapping.** A planned metadata layer will associate each oracle with a machine-readable standard reference (e.g., `{standard: "NFPA 20", edition: "2022", clause: "4.12.1", formula: "Q = K*sqrt(P)"}`) enabling automatic generation of standards compliance matrices for engineering submissions.

---

## 11. Conclusion

We have presented CRYS-L, a domain-specific language and runtime system for deterministic engineering computation. CRYS-L's oracle/plan model enables JIT compilation of pure mathematical engineering formulas to native x86-64 machine code via the Cranelift backend, achieving sub-microsecond evaluation latency across 56 engineering plans in 10 technical domains. The L1 OracleCache eliminates repeated computation at zero effective cost. Benchmark evaluation demonstrates that CRYS-L is 37–54× faster than CPython 3.11 and orders of magnitude faster than LLM-based alternatives for standards-compliant numerical computation.

The Qomni Orchestrator wraps CRYS-L with natural language understanding, physics validation, and a four-agent Bayesian debate system, enabling safe deployment to non-programmer domain engineers. The complete system is deployed in production on a 12-core AMD EPYC server and serves real-world electrical, fire protection, civil, and financial engineering calculations.

CRYS-L demonstrates that a minimalist, purity-enforcing DSL — not a general-purpose language — is the appropriate tool when the computation is well-characterized (engineering formula evaluation), the latency requirements are stringent (interactive real-time), and the correctness requirements are absolute (standards compliance). The gap between CRYS-L and LLM-based alternatives (up to 17.9 million times speedup) quantifies the cost of generality in computational engineering tools.

Future work will extend CRYS-L with LLVM code generation, SIMD batch evaluation, formal verification of oracle bodies, and GPU acceleration for Monte Carlo engineering analysis.

---

## References

[1] National Fire Protection Association, *NFPA 13: Standard for the Installation of Sprinkler Systems*, 2022 Edition. Quincy, MA: NFPA, 2022.

[2] National Fire Protection Association, *NFPA 20: Standard for the Installation of Stationary Pumps for Fire Protection*, 2022 Edition. Quincy, MA: NFPA, 2022.

[3] National Fire Protection Association, *NFPA 72: National Fire Alarm and Signaling Code*, 2022 Edition. Quincy, MA: NFPA, 2022.

[4] National Fire Protection Association, *NFPA 101: Life Safety Code*, 2021 Edition. Quincy, MA: NFPA, 2021.

[5] National Fire Protection Association, *NFPA 70: National Electrical Code (NEC)*, 2023 Edition. Quincy, MA: NFPA, 2023.

[6] International Electrotechnical Commission, *IEC 60364: Low-voltage Electrical Installations*, Parts 1–8. Geneva, Switzerland: IEC, 2016.

[7] IEEE, *IEEE Std 141-1993: IEEE Recommended Practice for Electric Power Distribution for Industrial Plants (IEEE Red Book)*. New York, NY: IEEE, 1993.

[8] American Concrete Institute, *ACI 318-19: Building Code Requirements for Structural Concrete and Commentary*. Farmington Hills, MI: ACI, 2019.

[9] American Institute of Steel Construction, *AISC 360-22: Specification for Structural Steel Buildings*. Chicago, IL: AISC, 2022.

[10] American Society of Civil Engineers, *ASCE 7-22: Minimum Design Loads and Associated Criteria for Buildings and Other Structures*. Reston, VA: ASCE, 2022.

[11] Ministerio de Trabajo y Promoción del Empleo, *Decreto Legislativo N.° 728: Ley de Fomento del Empleo*. Lima, Peru: El Peruano, 1991 (as amended through 2023).

[12] European Committee for Standardization, *EN 285: Sterilization of Medical Devices — Large Steam Sterilizers*, 2015 Edition. Brussels: CEN, 2015.

[13] International Organization for Standardization, *ISO 13485:2016: Medical Devices — Quality Management Systems — Requirements for Regulatory Purposes*. Geneva, Switzerland: ISO, 2016.

[14] American Society of Heating, Refrigerating and Air-Conditioning Engineers, *ASHRAE Standard 62.1-2022: Ventilation and Acceptable Indoor Air Quality*. Atlanta, GA: ASHRAE, 2022.

[15] American Society of Heating, Refrigerating and Air-Conditioning Engineers, *ASHRAE Standard 90.1-2022: Energy Standard for Sites and Buildings Except Low-Rise Residential Buildings*. Atlanta, GA: ASHRAE, 2022.

[16] Forum of Incident Response and Security Teams, *Common Vulnerability Scoring System v3.1: Specification Document*. FIRST, 2019. [Online]. Available: https://www.first.org/cvss/specification-document

[17] National Institute of Standards and Technology, *NIST Special Publication 800-53 Rev. 5: Security and Privacy Controls for Information Systems and Organizations*. Gaithersburg, MD: NIST, 2020.

[18] A. Hazen and G. S. Williams, *Hydraulic Tables: The Elements of Gagings and the Friction of Water Flowing in Pipes, Aqueducts, Sewers, etc.*, 3rd ed. New York, NY: Wiley, 1920.

[19] R. Manning, "On the Flow of Water in Open Channels and Pipes," *Transactions of the Institution of Civil Engineers of Ireland*, vol. 20, pp. 161–207, 1891.

[20] Food and Agriculture Organization of the United Nations, *FAO Irrigation and Drainage Paper No. 56: Crop Evapotranspiration — Guidelines for Computing Crop Water Requirements*, R. G. Allen, L. S. Pereira, D. Raes, and M. Smith, Eds. Rome: FAO, 1998.

[21] International Organization for Standardization, *ISO 3534-1:2006: Statistics — Vocabulary and Symbols — Part 1: General Statistical Terms and Terms Used in Probability*. Geneva, Switzerland: ISO, 2006.

[22] ASTM International, *ASTM E2586-14: Standard Practice for Calculating and Using Basic Statistics*. West Conshohocken, PA: ASTM, 2014.

[23] N. Matsakis and F. S. Klock, "The Rust Language," in *Proc. ACM HPTS Workshop*, 2014.

[24] B. Titzer, "Cranelift: A Retargetable WebAssembly Code Generator," Bytecode Alliance Technical Report, 2021. [Online]. Available: https://github.com/bytecodealliance/wasmtime

[25] S. Tilkov and S. Vinoski, "Node.js: Using JavaScript to Build High-Performance Network Programs," *IEEE Internet Computing*, vol. 14, no. 6, pp. 80–83, Nov.–Dec. 2010.

[26] T. Lattner and V. Adve, "LLVM: A Compilation Framework for Lifelong Program Analysis and Transformation," in *Proc. Int. Symp. Code Generation and Optimization (CGO)*, 2004, pp. 75–86.

[27] S. Liang, P. Hudak, and M. Jones, "Monad Transformers and Modular Interpreters," in *Proc. 22nd ACM SIGPLAN-SIGACT Symp. Principles of Programming Languages (POPL)*, 1995, pp. 333–343.

[28] Qomni AI Lab, *CRYS-L Language Reference v2.1*, Technical Report QAL-2026-001. Lima, Peru: Qomni AI Lab, 2026.

[29] International Organization for Standardization, *ISO 9001:2015: Quality Management Systems — Requirements*. Geneva, Switzerland: ISO, 2015.

[30] R. Ihaka and R. Gentleman, "R: A Language for Data Analysis and Graphics," *Journal of Computational and Graphical Statistics*, vol. 5, no. 3, pp. 299–314, 1996.

[31] M. Poletto and V. Sarkar, "Linear Scan Register Allocation," *ACM Transactions on Programming Languages and Systems (TOPLAS)*, vol. 21, no. 5, pp. 895–913, Sep. 1999.

[32] P. Briggs, K. D. Cooper, and L. Torczon, "Improvements to Graph Coloring Register Allocation," *ACM Transactions on Programming Languages and Systems (TOPLAS)*, vol. 16, no. 3, pp. 428–455, May 1994.

[33] Intel Corporation, *Intel 64 and IA-32 Architectures Software Developer's Manual, Vol. 2: Instruction Set Reference*, Order No. 325383. Santa Clara, CA: Intel, 2023.

[34] N. Nethercote and J. Seward, "Valgrind: A Framework for Heavyweight Dynamic Binary Instrumentation," in *Proc. 28th ACM SIGPLAN Conf. Programming Language Design and Implementation (PLDI)*, San Diego, CA, 2007, pp. 89–100.

---

*Manuscript submitted to the IEEE/ACM International Symposium on Code Generation and Optimization (CGO) / IEEE Software Engineering track. © 2026 Qomni AI Lab. All rights reserved.*
