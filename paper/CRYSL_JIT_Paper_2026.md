# QOMN: A Domain-Specific Language with JIT Compilation for Deterministic Engineering Computation

**Percy Rojas Masgo**
Qomni AI Lab, Lima, Peru
contact@qomniailab.com

---

*Abstract* — **Index Terms** — engineering computation, domain-specific language, JIT compilation, Cranelift, deterministic execution, AOT compilation, register ABI, simulation engine, hybrid AI pipeline

---

## Abstract

Engineering computation in domains such as fire protection, electrical design, civil structures, and financial compliance demands both numerical precision and extremely low execution latency. This paper presents QOMN (QOMN Language), a domain-specific language and runtime system designed for deterministic engineering execution rather than probabilistic inference. QOMN plans compile to native x86-64 machine code and execute through two measured fast paths on Server5 (KVM AMD EPYC, Ubuntu 24.04 LTS, 2026-04-16): a standard AOT path at **7.83 ns** for `plan_pump_sizing`, and an optimized L4 Register ABI hot path at **5.37 ns** for the same plan. The QOMN simulation engine sustains **13.0 million scenarios per second** on the same KVM host with physics validation and Pareto ranking enabled. This corresponds to an approximately **1.53 billion×** speedup over a 12,000 ms GPT-4-class API response for the same deterministic engineering result. Bare-metal projection for the simulation engine is approximately **25–35 million scenarios per second** on AVX-512 capable hardware. An integrated Qomni Orchestrator combines deterministic QOMN execution with LLM interpretation for ambiguous or policy-sensitive queries. The complete system is deployed as a production service and exposed through an HTTP API.

---

## 1. Introduction

Modern engineering projects routinely require thousands of code-path-identical but parameter-distinct calculations: a fire protection engineer sizing sprinkler systems across 200 rooms, an electrical designer sweeping conductor cross-sections to minimize voltage drop, or a structural analyst evaluating beam or slope models under varying inputs. Each of these scenarios shares a common computational pattern: a small, well-defined mathematical model that must be evaluated repeatedly, exactly, and quickly.

The dominant toolchains available to practicing engineers fall into three categories, each with fundamental limitations:

**Spreadsheet / scripted Python.** Python with NumPy or pandas is flexible and expressive, but incurs interpreter overhead in the tens to hundreds of microseconds per model evaluation, making large parameter sweeps impractical without special vectorization.

**C/C++ or Fortran numerical libraries.** Compiled languages achieve low latency, but require significant software engineering effort, are not intrinsically traceable to published standards, and are difficult for non-programmer domain experts to extend.

**Large Language Models (LLMs).** LLM-based engineering assistants can interpret natural-language queries and return numerical answers, but commonly operate at seconds-scale latency and provide no formal guarantee of determinism, auditability, or standards compliance.

QOMN addresses all three limitations simultaneously. By adopting a minimal deterministic language model — where every computation is a traceable plan over explicit formulas — QOMN enables:

1. **Native execution at nanosecond scale** on the hot path via compiled x86-64 machine code.
2. **Low-overhead caching** through FNV-1a parameter hashing with measured probe cost around **12 ns**.
3. **Continuous simulation** at **13.0M scenarios/sec** on KVM with validation and Pareto ranking enabled.
4. **Standards traceability**: every plan can encode a specific clause of a published engineering standard.
5. **Hybrid orchestration**: the Qomni layer adds natural-language handling and explanation while QOMN executes exact calculations.

The remainder of this paper is organized as follows. Section 2 describes the QOMN language design. Section 3 details the compilation and execution pipeline. Section 4 explains the cache architecture. Section 5 enumerates the engineering domains covered. Section 6 describes the Qomni Orchestrator. Section 7 presents the benchmark evaluation. Section 8 discusses deployment and future work.

---

## 2. QOMN Language Design

### 2.1 Design Philosophy

QOMN is deliberately minimal. Its core value type is floating-point numeric data, reflecting the reality that engineering formula evaluation is dominated by deterministic arithmetic. The language enforces purity: no side effects, no mutable external state, no I/O, and no recursion in the core plan model. This purity makes plans safe to compile, cache, benchmark, and reproduce.

Two conceptual layers exist:

- **Plan language** — the open user-facing DSL used to define engineering calculations.
- **Execution runtime** — the native compilation and dispatch engine used by QOMN and Qomni.

### 2.2 Plan Syntax

A plan declaration specifies a name, typed parameters, metadata, intermediate expressions, formulas, assertions, and outputs.

```qomn
plan_pump_sizing(
    Q_gpm: f64,
    P_psi: f64,
    eff:   f64 = 0.70
) {
    meta {
        standard: "NFPA 20:2022",
        source: "Section 4.26 + Chapter 6",
        domain: "fire",
    }
    let Q_lps  = Q_gpm * 0.06309;
    let H_m    = P_psi * 0.70307;
    let HP_req = (Q_lps * H_m) / (eff * 76.04);
    let HP_max = HP_req * 1.40;

    formula "Pump HP": "HP = (Q[L/s] × H[m]) / (η × 76.04)";
    assert Q_gpm > 0.0 msg "flow must be positive";
    assert eff   <= 1.0 msg "efficiency must be ≤ 1.0";

    return { HP_req: HP_req, HP_max: HP_max, Q_lps: Q_lps, H_m: H_m };
}
```

The language is designed to be readable by engineers while remaining easy to parse and compile.

---

## 3. Compilation and Execution Pipeline

### 3.1 Pipeline Overview

The QOMN execution path consists of:

```
Source Text
    │
    ▼
[Lexer]
    │
    ▼
[Parser]
    │
    ▼
[Typed IR / lowering]
    │
    ▼
[Native code generation]
    │
    ▼
[AOT / Register-ABI dispatch]
    │
    ▼
[Plan result]
```

### 3.2 Execution Modes

The measured runtime currently exposes two performance-relevant execution modes for selected hot plans:

- **Standard AOT path** — measured at **7.83 ns** for `plan_pump_sizing`
- **L4 Register ABI hot path** — measured at **5.37 ns** for `plan_pump_sizing`

Additional measured hot-path latencies on Server5 KVM (2026-04-16):

| Plan | L4 Register ABI latency |
|---|---:|
| `plan_pump_sizing` | **5.37 ns** |
| `plan_sprinkler_system` | **9.67 ns** |
| `plan_beam_analysis` | **10.69 ns** |

These measurements exclude TCP, HTTP parsing, JSON serialization, and routing overhead.

### 3.3 HTTP/API Overhead

When invoked through the public API, loopback latency is dominated by transport and parsing overhead rather than arithmetic execution. Measured HTTP loopback overhead is approximately **2–4 ms** on Server5.

### 3.4 OracleCache

QOMN uses FNV-1a hashing over input parameters to detect repeated calls. The measured cache probe cost on Server5 KVM is approximately **12 ns**. Earlier drafts rounded this to “0 ns effective latency”; the current measured number is preferred for technical accuracy.

---

## 4. Simulation Engine

The QOMN simulation engine extends single-plan execution into a continuous scenario-evaluation loop with:

- structure-of-arrays execution layout,
- physics validation,
- admissibility filtering,
- Pareto frontier ranking.

### 4.1 Measured Throughput

Measured on Server5 KVM AMD EPYC (2026-04-16):

- **Throughput:** **13.0 million scenarios/sec**
- **Valid fraction:** **72.1%**
- **Pareto size:** **507**

These are the current authoritative v2.3 RC numbers.

### 4.2 Earlier Claims and Methodology Correction

Earlier internal paper drafts referenced **86.4M scenarios/sec**, but that figure came from an earlier raw-kernel methodology without the same Pareto and validation path. It should not be treated as the official current benchmark.

### 4.3 Bare-Metal Estimate

On AVX-512 capable bare-metal hardware, projected simulation throughput is approximately **25–35M scenarios/sec**, or about **2–3×** the measured KVM figure.

---

## 5. Domain Coverage

QOMN currently covers multiple deterministic engineering domains including fire protection, hydraulics, electrical, civil/structural, financial, medical, statistics, transport, sanitary systems, mechanical systems, and thermal/HVAC models. The focus is not breadth for its own sake, but providing auditable deterministic execution for repeated engineering workloads.

---

## 6. Qomni Orchestrator

The Qomni Orchestrator wraps QOMN with natural-language interpretation, routing, and explanation. In this architecture:

- the LLM interprets the query,
- QOMN executes deterministic calculations,
- Qomni formats the result, rationale, and risk explanation.

This avoids using LLM inference for arithmetic that should be executed directly.

---

## 7. Benchmark Evaluation

### 7.1 Methodology

Benchmarks were conducted on:

- **Hardware:** Server5 KVM AMD EPYC · 12 cores · 48 GB RAM · Ubuntu 24.04 LTS
- **Runtime:** QOMN v2.3 RC · Rust release build · native x86-64 code generation
- **Measured values:** hot-path nanoseconds for selected plans, scenarios/sec for simulation engine, and HTTP loopback milliseconds for API path

### 7.2 Results Summary

| Metric | Measured value |
|---|---:|
| Standard AOT `plan_pump_sizing` | **7.83 ns** |
| L4 Register ABI `plan_pump_sizing` | **5.37 ns** |
| L4 Register ABI `plan_sprinkler_system` | **9.67 ns** |
| L4 Register ABI `plan_beam_analysis` | **10.69 ns** |
| OracleCache probe | **~12 ns** |
| Simulation throughput | **13.0M scenarios/sec** |
| Valid fraction | **72.1%** |
| Pareto size | **507** |
| HTTP loopback | **~2–4 ms** |

### 7.3 QOMN vs GPT-4-class API

Using the measured standard AOT result for `plan_pump_sizing`:

- GPT-4-class API latency assumption: **12,000 ms**
- QOMN standard AOT latency: **7.83 ns**

This yields an approximate speedup of:

**12,000 ms / 7.83 ns ≈ 1.53 billion×**

This ratio is the correct current order-of-magnitude comparison for the deterministic calculation itself, not the older 14.25 million× figure from earlier methodology.

---

## 8. Deployment and Discussion

QOMN is deployed as a production service behind an HTTP API. In practice, users experience milliseconds at the API layer while the core deterministic execution completes in nanoseconds. This separation is important:

- **Arithmetic cost:** nanoseconds
- **API cost:** milliseconds
- **Reasoning cost (LLM):** seconds

This makes QOMN suitable as the execution substrate for technical AI systems: the LLM decides *what* is being asked, and QOMN computes the answer exactly.

### 8.1 Current Limitations

- The public API path is dominated by transport and JSON overhead relative to arithmetic execution.
- Bare-metal benchmarks remain projected rather than directly published for the current v2.3 RC release.
- Some older docs and paper drafts may still contain v2.1-era measurements and should be considered deprecated.

### 8.2 Future Work

- Wider AOT coverage across stdlib plans
- SIMD batch language support
- bounded convergence constructs
- matrix/vector support
- LLVM backend
- portable WASM target
- REPL and developer tooling

---

## Conclusion

QOMN demonstrates that deterministic engineering computations should be executed, not inferred. On current measured Server5 KVM hardware, QOMN achieves:

- **7.83 ns** standard AOT for `plan_pump_sizing`
- **5.37 ns** L4 Register ABI hot-path execution
- **13.0M scenarios/sec** with validation and Pareto ranking
- **~2–4 ms** HTTP loopback latency
- **~1.53 billion×** speedup over a 12,000 ms GPT-4-class API call for the same deterministic result

These numbers make QOMN a strong execution layer for hybrid AI systems where exact calculations must be fast, reproducible, and standards-traceable.

---

## References

[1] National Fire Protection Association, *NFPA 13: Standard for the Installation of Sprinkler Systems*, 2022 Edition.

[2] National Fire Protection Association, *NFPA 20: Standard for the Installation of Stationary Pumps for Fire Protection*, 2022 Edition.

[3] International Electrotechnical Commission, *IEC 60364: Low-voltage Electrical Installations*.

[4] American Institute of Steel Construction, *AISC 360-22: Specification for Structural Steel Buildings*.

[5] Qomni AI Lab, *QOMN Benchmark Notes*, Server5 KVM measurements, 2026-04-16.

---

*Manuscript updated to reflect v2.3 RC measured numbers. Older v2.1 benchmark claims are deprecated where they conflict with the current methodology.*
