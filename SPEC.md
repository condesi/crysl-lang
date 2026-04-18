# QOMN v2 — Language Specification

**Author:** Percy Rojas Masgo — Condesi Perú / Qomni AI Lab
**Version:** 2.2 · **License:** MIT · **Date:** April 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Lexical Structure](#2-lexical-structure)
3. [Type System](#3-type-system)
4. [Grammar (Full EBNF)](#4-grammar-full-ebnf)
5. [Constructs](#5-constructs)
   - [plan declaration](#51-plan-declaration)
   - [meta block](#52-meta-block)
   - [const declaration](#53-const-declaration)
   - [let declaration](#54-let-declaration)
   - [formula declaration](#55-formula-declaration)
   - [assert statement](#56-assert-statement)
   - [output statement](#57-output-statement)
6. [Expressions](#6-expressions)
7. [Built-In Functions](#7-built-in-functions)
8. [Execution Model](#8-execution-model)
9. [Error Handling](#9-error-handling)
10. [Response Format](#10-response-format)
11. [Versioning](#11-versioning)
12. [Compiler Architecture](#12-compiler-architecture)
13. [Development Tools](#13-development-tools)
14. [Changelog](#14-changelog)

---

## 1. Overview

QOMN (QOMN Language) is a **declarative domain-specific language** for
expressing deterministic engineering calculations as self-contained *plan programs*.

A QOMN program:
- Accepts typed numeric parameters
- Computes intermediate values via arithmetic expressions
- Validates inputs via assertions
- Declares named outputs with labels and units
- Embeds metadata (standard, source, domain) for traceability
- Compiles to WASM and executes deterministically — **no randomness, no LLM**

A single `.qomn` file may contain multiple `plan_*` declarations.

---

> ### Quick Start for Engineers (non-programmers)
>
> You do not need to know Rust, Python, or any programming language to write a QOMN plan.
> If you can write an engineering formula in a spreadsheet, you can write a QOMN plan.
>
> **Minimal viable plan — 10 lines with annotations:**
>
> ```qomn
> plan_pipe_velocity(            // 1. Name your calculation
>     Q_lps: f64,                // 2. Declare inputs with type (f64 = decimal number)
>     D_mm:  f64                 // 3. One input per line; add a comment explaining units
> ) {
>     meta {                     // 4. Required: cite the standard you are using
>         standard: "IS.010 Peru — Instalaciones Sanitarias",
>         source:   "IS.010:2006 §3",
>         domain:   "hidraulica",
>         version:  "2.2",
>     }
>     let D_m = D_mm / 1000.0;              // 5. Convert units (mm → m)
>     let A   = 3.14159 * D_m * D_m / 4.0; // 6. Compute intermediate values
>     let V   = Q_lps / (A * 1000.0);       // 7. Final result (m/s)
>     formula "Velocity": "V = Q / A";      // 8. Document the formula (required for PR)
>     assert Q_lps > 0.0 msg "flow must be positive";  // 9. Validate each input
>     assert D_mm  > 0.0 msg "diameter must be positive";
>     output V label "Flow velocity" unit "m/s";        // 10. Declare what to return
> }
> ```
>
> That is a complete, runnable QOMN plan. Send it to the API and receive an exact answer
> with the standard cited — no spreadsheet errors, no approximations.

---

---

## 2. Lexical Structure

### 2.1 Comments

Single-line only:
```
// This is a comment
```
Block comments are not supported.

### 2.2 Keywords

Reserved words that cannot be used as identifiers:

```
plan_   const   let   formula   assert   msg   output   label   unit
meta    true    false   version
```

> **Note:** `label`, `unit`, `msg`, and `version` are reserved to prevent ambiguity
> with the built-in keywords used in `output` and `meta` blocks.

### 2.3 Identifiers

```ebnf
identifier ::= [a-zA-Z][a-zA-Z0-9_]*
```

- Must start with a letter (uppercase or lowercase)
- May contain letters (any case), digits, and underscores
- Case-sensitive (`HP_req` and `hp_req` are distinct identifiers)
- Plan names must begin with `plan_`

**Valid:** `Q_gpm`, `h_loss`, `v_min`, `HP_req`, `plan_pump_sizing`, `RHO_CU`
**Invalid:** `2x` (digit start), `_var` (underscore start)

**String literals** support standard escape sequences:
- `\"` — double quote
- `\\` — backslash
- `\n` — newline
- `\t` — tab

Other escape sequences are not supported and will produce a parse error.

**Negative number literals** are not supported directly. Use unary minus:
`let x = -5.0;` where `-` is a unary operator applied to the literal `5.0`.

### 2.4 Literals

```ebnf
number     ::= [0-9]+ ('.' [0-9]+)?
string_lit ::= '"' [^"]* '"'
bool_lit   ::= 'true' | 'false'
```

Numbers are always parsed as `f64` unless context requires `i64`.
Scientific notation is not supported in v2 — use decimal form.

**Valid:** `0.06309`, `1000.0`, `76.04`, `0.0`
**Invalid:** `6.309e-2`, `1_000`

### 2.5 Operators

```
+   -   *   /   ^   %
```

Operator `^` is exponentiation (equivalent to `pow(x, n)`).
All operators are left-associative except `^` (right-associative).

### 2.6 Comparison Operators (assert only)

```
>   <   >=   <=   ==   !=
```

Comparison operators are valid only inside `assert` expressions.

### 2.7 Logical Operators (assert only)

```
&&   ||   !
```

---

## 3. Type System

QOMN v2 is **statically typed** with five value types:

| Type | Size | Range | Use |
|------|------|-------|-----|
| `f64` | 64-bit float | ±1.8×10³⁰⁸ | Default numeric type |
| `f32` | 32-bit float | ±3.4×10³⁸ | Reduced precision |
| `i64` | 64-bit integer | ±9.2×10¹⁸ | Integer counts |
| `bool` | 1-bit | true/false | Flags only |
| `str`  | UTF-8 string | — | Labels, messages |

**Rules:**
- All arithmetic is performed in `f64` precision
- Integer parameters are automatically promoted to `f64` in expressions
- `str` values cannot participate in arithmetic
- `bool` values resolve to `1.0` (true) or `0.0` (false) in arithmetic context

### 3.1 Type Coercion Rules

QOMN performs automatic (implicit) type coercion in the following cases:

**Automatic (safe) coercions:**

| From | To | Context |
|------|----|---------|
| `i64` | `f64` | Always safe; happens automatically in arithmetic |
| `bool` | `f64` | `true` = 1.0, `false` = 0.0 — enables branchless arithmetic |
| `f32` | `f64` | Automatic when mixing `f32` and `f64` in expressions |

**Mixed arithmetic promotion rules:**

```
i64  + f64  → f64
bool + f64  → f64
bool + i64  → f64   (both operands promoted)
str  + any  → TypeError (forbidden)
```

**Forbidden conversions (TypeError):**
- `str` cannot participate in any arithmetic expression
- There is no explicit casting syntax; use constants for unit conversions
- No implicit narrowing (f64 → i64 is never automatic)

### 3.2 String Type Rules

The `str` type is used exclusively for metadata, labels, messages, and formula documentation strings. It is not a general-purpose string type.

**Supported string operations:**
- **Comparison:** `==` and `!=` are supported for `str` in `assert` expressions
- **Concatenation:** NOT supported — use `label` and `formula` strings for composition
- **Arithmetic:** TypeError — `str` cannot participate in numeric expressions

**Where `str` appears:**
- `meta` block field values
- `formula` declaration name and expression strings
- `output` statement `label` and `unit` strings
- `assert` message after `msg`
- `str`-typed input parameters (for mode/type flags passed as metadata)

**Example:**
```qomn
plan_check_mode(mode: str = "strict") {
    meta { standard: "Internal", source: "§1", domain: "util", version: "2.2", }
    assert mode == "strict" || mode == "lenient" msg "mode must be strict or lenient";
    output mode label "Validation mode";
}
```

---

## 4. Grammar (Full EBNF)

```ebnf
program         ::= plan_decl+

plan_decl       ::= 'plan_' identifier '(' param_list? ')' '{' meta body_item* '}'
body_item       ::= const_decl | let_decl | formula | assert | output

param_list      ::= param (',' param)*
param           ::= identifier ':' type ('=' default)?
type            ::= 'f64' | 'f32' | 'i64' | 'bool' | 'str'
default         ::= literal

meta            ::= 'meta' '{' meta_field+ '}'
meta_field      ::= identifier ':' string_lit ','

const_decl      ::= 'const' identifier '=' expr ';'
let_decl        ::= 'let' identifier '=' expr ';'

formula         ::= 'formula' string_lit ':' string_lit ';'

assert          ::= 'assert' assert_expr 'msg' string_lit ';'
assert_expr     ::= or_expr
or_expr         ::= and_expr ('||' and_expr)*
and_expr        ::= not_expr ('&&' not_expr)*
not_expr        ::= '!' comp_expr | comp_expr
comp_expr       ::= arith_expr (cmp_op arith_expr)? | '(' assert_expr ')'

output          ::= 'output' identifier 'label' string_lit ('unit' string_lit)? ';'

expr            ::= term (arith_op term)*
term            ::= literal | identifier | call | '(' expr ')'
call            ::= identifier '(' expr_list? ')'
expr_list       ::= expr (',' expr)*

arith_op        ::= '+' | '-' | '*' | '/' | '^' | '%'
cmp_op          ::= '>' | '<' | '>=' | '<=' | '==' | '!='
log_op          ::= '&&' | '||'

literal         ::= number | string_lit | bool_lit
number          ::= [0-9]+ ('.' [0-9]+)?
string_lit      ::= '"' [^"]* '"'
bool_lit        ::= 'true' | 'false'

identifier      ::= [a-zA-Z][a-zA-Z0-9_]*
```

---

## 5. Constructs

### 5.1 Plan Declaration

```
plan_<name>(<params>) {
    <body>
}
```

A plan is the top-level compilation unit. Each plan is independently callable.
Plans cannot call other plans (no plan-to-plan invocation in v2).

**Naming convention:** `plan_{domain}_{calculation}`
Examples: `plan_pump_sizing`, `plan_hazen_williams`, `plan_beam_deflection`

**Parameters** are positional. When calling a plan, parameters may be passed
by position or by name (runtime-dependent).

Default values are evaluated at parse time. Defaults must be literals —
expressions are not allowed as defaults in v2.

**Parameter Ordering Rule:** Parameters with default values must appear after
all required (non-default) parameters. This is enforced at parse time.

```qomn
// VALID — required parameters first, then optional with defaults
plan_example(x: f64, y: f64, z: f64 = 1.0) { ... }

// INVALID — required parameter after optional parameter (parse error)
plan_bad(x: f64 = 1.0, y: f64) { ... }
```

**The `meta` block is REQUIRED** and must appear as the first item in the plan
body. A plan without a `meta` block will not parse. Only one `meta` block is
allowed per plan.

### 5.2 meta Block

```
meta {
    standard: "Full standard name and year",
    source:   "Section / table reference",
    domain:   "domain_name",
    version:  "2.0",
    note:     "Optional note",
}
```

**Required fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `standard` | Yes | Full name of the applicable standard |
| `source` | Yes | Specific section, table, or clause |
| `domain` | Yes | One of: hidraulica, nfpa_electrico, civil, mecanica, termica, sanitaria, electrical, financial, medical, statistics, transport |
| `version` | Yes | QOMN spec version string, e.g. `"2.2"` |
| `note` | No | Optional clarification |

**The `meta` block is REQUIRED** and must appear as the **first item** in the
plan body. A plan without a `meta` block is a parse error. Only one `meta`
block is allowed per plan. This constraint is enforced by the grammar:

```ebnf
plan_decl ::= 'plan_' identifier '(' param_list? ')' '{' meta body_item* '}'
body_item ::= const_decl | let_decl | formula | assert | output
```

The `meta` keyword is separate from `body_item` to make its required-and-first
position explicit in the grammar.

### 5.3 const Declaration

```
const IDENTIFIER = expr;
```

Declares a compile-time constant. By convention, constant names use
UPPER_SNAKE_CASE. Constants are evaluated before any `let` expression
and cannot reference `let` variables.

```qomn
const GPM_TO_LPS = 0.06309;
const PI         = 3.14159265358979;
const KPA_TO_M   = 0.10197;
```

**Variable Shadowing:** Names must be unique across parameters, `const`
declarations, and `let` declarations within a plan. A `const` or `let`
binding cannot shadow an input parameter or any prior declaration in the
same plan. Violation produces a parse error.

```qomn
// INVALID — shadowing parameter with let
plan_bad(x: f64) {
    let x = 2.0;   // parse error: 'x' already defined as parameter
    ...
}

// INVALID — shadowing const with let
plan_bad2(y: f64) {
    const A = 1.0;
    let A = 2.0;   // parse error: 'A' already defined as const
    ...
}
```

### 5.4 let Declaration

```
let identifier = expr;
```

Declares a computed intermediate value. `let` variables are evaluated in
declaration order. A `let` may reference previously declared `let` and
`const` values, and all input parameters.

```qomn
let Q_lps  = Q_gpm * GPM_TO_LPS;
let H_m    = P_psi * PSI_TO_M;
let HP_req = (Q_lps * H_m) / (eff * 76.04);
```

**Important:** `let` declarations are not reassignable. Each name may appear
only once on the left side of a `let` expression.

### 5.5 formula Declaration

```
formula "Human-readable name": "Mathematical expression as string";
```

Declares a named formula string for documentation and audit trail purposes.
The formula string is not evaluated — it is stored as metadata and returned
in the response alongside computed values.

```qomn
formula "Pump power":       "HP = (Q[L/s] × H[m]) / (η × 76.04)";
formula "NFPA shutoff":     "HP_shutoff ≤ 1.40 × HP_rated";
formula "Voltage drop":     "ΔV = 2·ρ·L·I / S";
```

At least one `formula` declaration is required per plan (stdlib requirement;
not enforced by the parser but required for PR acceptance).

### 5.6 assert Statement

```
assert <condition> msg "<message>";
```

Asserts that an input or computed value satisfies a condition. If the
assertion fails at runtime, execution halts and an error is returned with
the message string. No partial outputs are emitted.

```qomn
assert Q_gpm  > 0.0     msg "flow must be positive (GPM)";
assert eff    > 0.0     msg "efficiency must be > 0";
assert eff    <= 1.0    msg "efficiency must be ≤ 1.0";
assert Q_gpm  <= 5000.0 msg "flow exceeds NFPA 20 Table 4.26 max";
```

**Rules:**
- At least one `assert` per input parameter is required (stdlib requirement)
- Assertions may reference parameters, `const`, and `let` values
- Assertions are evaluated after all `let` values are computed
- Multiple assertions are evaluated in declaration order; first failure stops

**Compound assertions:**
```qomn
assert fp > 0.0 && fp <= 1.0 msg "power factor must be in (0, 1]";
```

**Logical operator precedence in assert expressions (high to low):**

| Priority | Operator | Description |
|----------|----------|-------------|
| 3 (highest) | `!` | Logical NOT (prefix unary) |
| 2 | `&&` | Logical AND |
| 1 (lowest) | `\|\|` | Logical OR |

Comparison operators (`>`, `<`, `>=`, `<=`, `==`, `!=`) are always evaluated
before any logical operator. Parentheses may be used to override precedence.

```qomn
// a > 0 is evaluated first, then negated, then ANDed with b < 10
assert !a > 0.0 && b < 10.0 msg "...";

// Explicit grouping for clarity:
assert !(a > 0.0) && (b < 10.0 || c == 0.0) msg "...";
```

### 5.7 output Statement

```
output <identifier> label "<label>" unit "<unit>";
output <identifier> label "<label>";
```

Declares a value to be included in the plan response. The identifier must
reference a previously declared `let` or `const` value, or an input parameter.

```qomn
output HP_req   label "Required HP"              unit "HP";
output HP_max   label "Max shutoff HP (NFPA 20)" unit "HP";
output Q_lps    label "Flow rate"                unit "L/s";
output H_m      label "Total Dynamic Head"       unit "m";
output drop_pct label "Voltage drop percentage"  unit "%";
```

**Unit conventions:**

| Quantity | Preferred unit |
|----------|---------------|
| Power | HP, kW, W |
| Flow | L/s, L/min, GPM, m³/h |
| Pressure | m, PSI, kPa, bar |
| Length | m, mm |
| Area | m², mm², cm² |
| Current | A |
| Voltage | V |
| Resistance | Ω, mm² (cross section) |
| Dimensionless | % |

---

## 6. Expressions

### 6.1 Arithmetic

Standard precedence (high to low):

| Precedence | Operators | Associativity |
|------------|-----------|---------------|
| 5 (highest) | Unary `-` | Prefix (right) |
| 4 | `^` | Right |
| 3 | `*`, `/`, `%` | Left |
| 2 | `+`, `-` (binary) | Left |
| 1 | Comparisons | Non-assoc |

**Unary minus and exponentiation:** Unary minus has higher precedence than
exponentiation. This follows the mathematical convention:

```
-2.0 ^ 2.0  =  -(2.0 ^ 2.0)  =  -4.0
```

This differs from some languages (e.g., Python, where `-2**2 = -4` by same
convention). To square a negative number, use parentheses: `(-2.0) ^ 2.0 = 4.0`.

```qomn
let x = 2.0 + 3.0 * 4.0;     // 14.0
let y = pow(2.0, 3.0);        // 8.0
let z = (2.0 + 3.0) * 4.0;   // 20.0
```

### 6.2 Division

Integer division is not supported. All division produces `f64`.
Division by zero produces a runtime error, not `NaN` or `Inf`.

### 6.3 Modulo

```qomn
let r = 10.0 % 3.0;   // 1.0
```

---

## 7. Built-In Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `sqrt(x)` | f64 → f64 | Square root. Error if x < 0 |
| `pow(x, n)` | f64, f64 → f64 | x raised to power n |
| `abs(x)` | f64 → f64 | Absolute value |
| `min(a, b)` | f64, f64 → f64 | Minimum of two values |
| `max(a, b)` | f64, f64 → f64 | Maximum of two values |
| `clamp(x, min_val, max_val)` | f64, f64, f64 → f64 | Clamp x to [min_val, max_val]. Equivalent to `max(min_val, min(x, max_val))` |
| `log(x)` | f64 → f64 | Natural logarithm. Error if x ≤ 0 |
| `log10(x)` | f64 → f64 | Base-10 logarithm. Error if x ≤ 0 |
| `round(x, n)` | f64, i64 → f64 | Round x to n decimal places |
| `floor(x)` | f64 → f64 | Floor (round down) |
| `ceil(x)` | f64 → f64 | Ceiling (round up) |
| `sin(x)` | f64 → f64 | Sine (radians) |
| `cos(x)` | f64 → f64 | Cosine (radians) |
| `tan(x)` | f64 → f64 | Tangent (radians) |
| `asin(x)` | f64 → f64 | Arcsine (radians). Error if \|x\| > 1 |
| `acos(x)` | f64 → f64 | Arccosine (radians). Error if \|x\| > 1 |
| `atan(x)` | f64 → f64 | Arctangent (radians) |
| `atan2(y, x)` | f64, f64 → f64 | Four-quadrant arctangent of y/x (radians) |
| `pi()` | → f64 | π = 3.14159265358979 |
| `e()` | → f64 | e = 2.71828182845905 |

### 7.1 Domain Constants

Common engineering constants used in the stdlib. Using these as named `const`
declarations (rather than bare literals) improves readability and traceability.

| Constant | Value | Meaning |
|----------|-------|---------|
| `76.04` | kgf·m/s | HP conversion: 1 metric HP = 76.04 kgf·m/s (fluid power) |
| `0.70307` | m/PSI | PSI to meters water column: 1 psi = 0.70307 m.c.a. |
| `0.06309` | L/s per GPM | GPM to L/s: 1 gpm = 0.06309 L/s |
| `0.0172` | Ω·mm²/m | Copper resistivity ρ at 20°C (IEC 60228) |

Example usage:
```qomn
const GPM_TO_LPS = 0.06309;   // 1 gpm = 0.06309 L/s
const PSI_TO_M   = 0.70307;   // 1 psi = 0.70307 m.c.a.
formula "HP conversion": "76.04 kgf·m/s = 1 HP (metric)";
```

---

## 8. Execution Model

### 8.1 Evaluation Order

For each plan invocation:

```
1. Bind input parameters (with defaults for omitted optional params)
2. Evaluate const declarations (in order)
3. Evaluate let declarations (in order, each may reference prior lets)
4. Evaluate assert conditions (in order; halt on first failure)
5. Collect output values
6. Return response
```

### 8.2 WASM Compilation

Each plan compiles to an independent WASM function. The compiler:
- Inlines all constants at compile time
- Generates typed local variables for each `let`
- Emits assertion checks as conditional traps
- Serializes outputs as a structured record

Compiled WASM modules are cached after the first call. Subsequent calls
with different inputs execute the cached module — no recompilation.

### 8.3 Determinism

QOMN execution is **strictly deterministic**:
- Same inputs always produce identical outputs (bit-for-bit)
- No random number generation
- No I/O, network calls, or filesystem access from within a plan
- No floating-point non-determinism: IEEE 754 double, round-to-nearest

---

## 9. Error Handling

### 9.1 Assertion Failure

```json
{
  "error": "assertion_failed",
  "plan": "plan_pump_sizing",
  "message": "flow exceeds NFPA 20 Table 4.26 max",
  "input": "Q_gpm",
  "value": 6000.0
}
```

### 9.2 Missing Required Parameter

```json
{
  "error": "missing_input",
  "plan": "plan_pump_sizing",
  "parameter": "Q_gpm"
}
```

### 9.3 Type Error

```json
{
  "error": "type_error",
  "plan": "plan_pump_sizing",
  "parameter": "eff",
  "expected": "f64",
  "received": "string"
}
```

### 9.4 Math Error

```json
{
  "error": "math_error",
  "plan": "plan_hazen_williams",
  "expression": "sqrt(area)",
  "reason": "sqrt of negative number",
  "value": -0.5
}
```

### 9.5 Plan Not Found

```json
{
  "error": "plan_not_found",
  "plan": "plan_nonexistent"
}
```

---

## 10. Response Format

A successful execution returns:

```json
{
  "plan": "plan_pump_sizing",
  "status": "ok",
  "outputs": {
    "HP_req": {
      "value": 18.04,
      "label": "Required HP",
      "unit": "HP"
    },
    "HP_max": {
      "value": 21.65,
      "label": "Max shutoff HP (NFPA 20)",
      "unit": "HP"
    }
  },
  "formulas": {
    "Pump power": "HP = (Q[L/s] × H[m]) / (η × 76.04)",
    "NFPA shutoff": "HP_shutoff ≤ 1.40 × HP_rated"
  },
  "meta": {
    "standard": "NFPA 20:2022 — Standard for Stationary Pumps",
    "source": "Section 4.26, Chapter 6, Annex A",
    "domain": "nfpa_electrico",
    "version": "2.0"
  },
  "execution_ms": 0.18,
  "assertions_passed": 5
}
```

---

## 11. Versioning

| Version | Key changes |
|---------|-------------|
| v1.0 | Initial: `plan_`, `let`, `output` |
| v2.0 | Added: `meta{}`, `assert...msg`, `formula`, `const`, default params, `unit` |
| v2.2 | Identifier grammar mixed-case; reserved words expanded; unary minus precedence; assert precedence formalized; clamp/atan/asin/acos added; meta required; type coercion rules; string type rules; shadowing forbidden; domain constants table; compiler architecture |

Future versions maintain backward compatibility — v1 plans are valid v2 plans.

---

## 12. Compiler Architecture

QOMN is compiled through a multi-stage pipeline:

### 12.1 Parser
- Strategy: **recursive descent**, single-pass
- Input: UTF-8 `.qomn` source text
- Output: HIR (High-level Intermediate Representation) — a typed AST

### 12.2 Intermediate Representation
- **HIR** → type-checked, named AST with resolved identifiers
- **Bytecode** → lowered, flattened instruction stream
- **Cranelift JIT** → native machine code via the Cranelift code generator

### 12.3 Runtime
- Target: Cranelift native ISA
- Optimizations: AVX2/FMA3 detected at startup; auto-vectorization for batch calls
- Memory: zero-allocation hot path (all stack-allocated per plan call)

### 12.4 OracleCache
- Hash function: **FNV-1a** (64-bit) over all input parameter values
- Cache hit cost: **0 ns** (single memory read from cache table)
- Cache miss: full JIT execution + cache store
- Cache is per-process; cleared on plan reload

---

## 13. Development Tools

Planned tooling for the QOMN ecosystem:

| Tool | Command | Status |
|------|---------|--------|
| Type/syntax checker | `qomn check <file.qomn>` | Planned |
| Code formatter | `qomn fmt <file.qomn>` | Planned |
| Interactive shell | `qomn repl` | Planned |
| Plan runner | `qomn run <plan> [args]` | Available (via REST API) |
| Benchmark harness | `qomn bench <plan>` | Available |

The `qomn check` tool will report:
- Parse errors (syntax)
- Type errors (e.g., `str` in arithmetic)
- Shadowing violations
- Missing `meta` block
- Optional: default-before-required parameter ordering

---

## 14. Changelog

### v2.2 (2026-04-16) — Specification Hardening

- **Fixed:** Identifier grammar now allows mixed case `[a-zA-Z][a-zA-Z0-9_]*`
- **Fixed:** Added `label`, `unit`, `msg`, `version` to reserved words list
- **Fixed:** Defined unary minus precedence (5) above exponentiation (4)
- **Fixed:** Formalized assert expression precedence (`!` > `&&` > `||`); added EBNF for `or_expr`, `and_expr`, `not_expr`, `comp_expr`
- **Added:** `clamp(x, min_val, max_val)` built-in function
- **Added:** `atan2(y, x)`, `asin(x)`, `acos(x)`, `atan(x)` inverse trig built-ins
- **Added:** `mecanica`, `termica`, `sanitaria` standard library domains
- **Clarified:** `meta` block is required and must be first in plan body; EBNF updated
- **Clarified:** Type coercion rules (`i64→f64`, `bool→f64`, `str` forbidden in arithmetic)
- **Clarified:** String type usage (metadata only; `==` and `!=` comparisons supported)
- **Clarified:** Variable shadowing is forbidden (parse error)
- **Clarified:** Required parameters must precede optional (defaulted) parameters
- **Added:** Domain constants table (76.04, 0.70307, 0.06309, 0.0172) in §7.1
- **Added:** Compiler architecture documentation (§12)
- **Added:** Development tools roadmap (§13)
- **Added:** Escape sequence documentation in §2.3
- **Added:** Negative literal clarification in §2.3

### v2.0 (2026-04-01) — Initial v2 Release
- Added: `meta{}`, `assert...msg`, `formula`, `const`, default params, `unit`

### v1.0 (2025-12-01) — Initial Release
- `plan_`, `let`, `output`

---

*QOMN v2.2 Specification — Copyright (c) 2026 Percy Rojas Masgo — MIT License*
