# CRYS-L v2 — Language Specification

**Author:** Percy Rojas Masgo — Condesi Perú / Qomni AI Lab
**Version:** 2.0 · **License:** MIT · **Date:** April 2026

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

---

## 1. Overview

CRYS-L (Crystal Language) is a **declarative domain-specific language** for
expressing deterministic engineering calculations as self-contained *plan programs*.

A CRYS-L program:
- Accepts typed numeric parameters
- Computes intermediate values via arithmetic expressions
- Validates inputs via assertions
- Declares named outputs with labels and units
- Embeds metadata (standard, source, domain) for traceability
- Compiles to WASM and executes deterministically — **no randomness, no LLM**

A single `.crysl` file may contain multiple `plan_*` declarations.

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
meta    true    false
```

### 2.3 Identifiers

```ebnf
identifier ::= [a-z][a-z0-9_]*
```

- Must start with a lowercase letter
- May contain lowercase letters, digits, and underscores
- Case-sensitive
- Plan names must begin with `plan_`

**Valid:** `Q_gpm`, `h_loss`, `v_min`, `plan_pump_sizing`
**Invalid:** `Q`, `HP_req` (uppercase start), `2x` (digit start)

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

CRYS-L v2 is **statically typed** with five value types:

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

---

## 4. Grammar (Full EBNF)

```ebnf
program         ::= plan_decl+

plan_decl       ::= 'plan_' identifier '(' param_list? ')' '{' body '}'

param_list      ::= param (',' param)*
param           ::= identifier ':' type ('=' default)?
type            ::= 'f64' | 'f32' | 'i64' | 'bool' | 'str'
default         ::= literal

body            ::= body_item+
body_item       ::= meta | const_decl | let_decl | formula | assert | output

meta            ::= 'meta' '{' meta_field+ '}'
meta_field      ::= identifier ':' string_lit ','

const_decl      ::= 'const' identifier '=' expr ';'
let_decl        ::= 'let' identifier '=' expr ';'

formula         ::= 'formula' string_lit ':' string_lit ';'

assert          ::= 'assert' assert_expr 'msg' string_lit ';'
assert_expr     ::= expr cmp_op expr
                  | assert_expr log_op assert_expr
                  | '!' assert_expr
                  | '(' assert_expr ')'

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

identifier      ::= [a-z][a-z0-9_]*
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
| `domain` | Yes | One of: hidraulica, nfpa_electrico, civil, mecanica, termica, sanitaria |
| `version` | Yes | CRYS-L version: "2.0" |
| `note` | No | Optional clarification |

The `meta` block must appear before any `let`, `const`, `formula`, `assert`,
or `output` statements. Only one `meta` block is allowed per plan.

### 5.3 const Declaration

```
const IDENTIFIER = expr;
```

Declares a compile-time constant. By convention, constant names use
UPPER_SNAKE_CASE. Constants are evaluated before any `let` expression
and cannot reference `let` variables.

```crysl
const GPM_TO_LPS = 0.06309;
const PI         = 3.14159265358979;
const KPA_TO_M   = 0.10197;
```

### 5.4 let Declaration

```
let identifier = expr;
```

Declares a computed intermediate value. `let` variables are evaluated in
declaration order. A `let` may reference previously declared `let` and
`const` values, and all input parameters.

```crysl
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

```crysl
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

```crysl
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
```crysl
assert fp > 0.0 && fp <= 1.0 msg "power factor must be in (0, 1]";
```

### 5.7 output Statement

```
output <identifier> label "<label>" unit "<unit>";
output <identifier> label "<label>";
```

Declares a value to be included in the plan response. The identifier must
reference a previously declared `let` or `const` value, or an input parameter.

```crysl
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
| 4 | `^` | Right |
| 3 | `*`, `/`, `%` | Left |
| 2 | `+`, `-` | Left |
| 1 | Comparisons | Non-assoc |

```crysl
let x = 2.0 + 3.0 * 4.0;     // 14.0
let y = pow(2.0, 3.0);        // 8.0
let z = (2.0 + 3.0) * 4.0;   // 20.0
```

### 6.2 Division

Integer division is not supported. All division produces `f64`.
Division by zero produces a runtime error, not `NaN` or `Inf`.

### 6.3 Modulo

```crysl
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
| `log(x)` | f64 → f64 | Natural logarithm. Error if x ≤ 0 |
| `log10(x)` | f64 → f64 | Base-10 logarithm. Error if x ≤ 0 |
| `round(x, n)` | f64, i64 → f64 | Round x to n decimal places |
| `floor(x)` | f64 → f64 | Floor (round down) |
| `ceil(x)` | f64 → f64 | Ceiling (round up) |
| `sin(x)` | f64 → f64 | Sine (radians) |
| `cos(x)` | f64 → f64 | Cosine (radians) |
| `tan(x)` | f64 → f64 | Tangent (radians) |
| `pi()` | → f64 | π = 3.14159265358979 |
| `e()` | → f64 | e = 2.71828182845905 |

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

CRYS-L execution is **strictly deterministic**:
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

Future versions maintain backward compatibility — v1 plans are valid v2 plans.

---

*CRYS-L v2 Specification — Copyright (c) 2026 Percy Rojas Masgo — MIT License*
