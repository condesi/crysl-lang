# QOMN — Language Originality Statement

**QOMN is an entirely original language created by Percy Rojas Masgo.**

---

## Language Design

The QOMN grammar, syntax, keywords, and runtime model are original works
designed from scratch by Percy Rojas Masgo (Condesi Perú / Qomni AI Lab)
in 2025–2026.

The following syntactic constructs are **unique to QOMN** and do not
exist in any other language or DSL:

| Construct | Example | Originality |
|-----------|---------|-------------|
| Plan declaration | `plan_pump_sizing(Q: f64) { }` | Original |
| Named formula | `formula "HP": "Q*H/(eta*76)";` | Original |
| Assert with message | `assert Q > 0.0 msg "flow must be positive";` | Original |
| Annotated output | `output HP label "Required HP" unit "HP";` | Original |
| Metadata block | `meta { standard: "NFPA 20:2022", ... }` | Original |

No part of the grammar or syntax was copied or derived from any
other language, DSL, library, or software project.

---

## Name

**"QOMN"** (hyphenated) does not exist as a name for any other
language, DSL, library, or software project.

> **Important disambiguation:**
> "CrySL" (no hyphen, different capitalization) is an unrelated academic DSL
> for cryptographic API specification (ECOOP 2018, Fraunhofer / TU Darmstadt,
> Mira Mezini et al.). It specifies correct usage of Java crypto APIs.
> QOMN has **no relationship** to CrySL: different domain (engineering
> calculations vs. Java security), different syntax, different purpose,
> different implementation, different community.

---

## Code Independence — QOMN Does Not Use Code from Other Languages

QOMN is a self-contained language. It does **not** use, embed, or execute
code written in any other programming language. Specifically:

- **No Rust code inside .qomn files.** QOMN is not a macro system or
  extension of Rust, Python, C, or any other language.
- **No Python, JavaScript, or shell code embedded.** QOMN plans are
  evaluated by the QOMN runtime only.
- **No third-party compiler framework used.** The QOMN JIT compiler and
  WASM runtime are original — not based on LLVM, GCC, Cranelift, or any
  existing compiler backend.
- **No code borrowed from other DSLs.** The `.qomn` plan format was designed
  independently; it does not reuse parsers, grammars, or AST definitions from
  any other tool.

### On common keywords (`let`, `const`, `f64`)

QOMN uses a small set of generic keywords common to many languages:
`let`, `const`. These are universal programming concepts, not owned or
copyrighted by any language. The type name `f64` (64-bit float) is a
mathematical/hardware concept — it is not code from Rust or any other language.

No source code from Rust, Python, JavaScript, C, or any other language
was copied, adapted, or used to create QOMN or its standard library.

### What is entirely original in QOMN

| Element | Status |
|---------|--------|
| `plan_name(...) { }` block | **Original — unique to QOMN** |
| `formula "name": "expr" ;` | **Original — unique to QOMN** |
| `assert expr msg "text" ;` | **Original — unique to QOMN** |
| `output id label "..." unit "..." ;` | **Original — unique to QOMN** |
| `meta { standard: ..., source: ..., domain: ... }` | **Original — unique to QOMN** |
| QOMN grammar (EBNF) | **Original — designed by Percy Rojas Masgo** |
| QOMN JIT compiler | **Original — no third-party compiler framework** |
| QOMN WASM runtime | **Original — no third-party runtime used** |
| stdlib `.qomn` plans | **Original — QOMN code only** |

All code in this repository is original:

- **stdlib/*.qomn** — original QOMN implementations by Percy Rojas Masgo.
  Engineering formulas are mathematical laws in the public domain.

- **Compiler / WASM runtime** — original implementation. Not derived from
  LLVM, GCC, or any other compiler infrastructure.

- **examples/** — original annotated examples by Percy Rojas Masgo.

---

## Engineering Standards

Standard references in this repo (NFPA 20, IEC 60364, ACI 318-19, IS.010,
etc.) appear by **name and section number only**. This is consistent with
academic citation practice. No text has been copied verbatim from any
copyrighted standard document.

The formulas themselves are mathematical/physical laws and are not subject
to copyright protection.

---

## Copyright

```
Copyright (c) 2026 Percy Rojas Masgo — Condesi Perú / Qomni AI Lab
All original content in this repository. MIT License.
```

QOMN is released as an open standard under MIT to benefit the global
engineering and developer community. Attribution to Percy Rojas Masgo
as the language creator is appreciated in derived works.
