# Contributing to CRYS-L

CRYS-L is an open standard for deterministic engineering calculations.
We welcome contributions from engineers, developers, and researchers worldwide.

## What to Contribute

- **New `plan_*` declarations** for any engineering domain
- **Corrections** to existing formulas (with standard citation)
- **Test vectors** for existing plans
- **Translations** of comments/labels to other languages
- **Documentation** improvements

## What NOT to Contribute

- Source code of the Qomni Engine (proprietary — use the open runtime instead)
- Plans without a published standard citation
- Plans that produce non-deterministic results

---

## Step-by-Step: Adding a New Plan

### 1. Choose your domain

| Domain | File |
|--------|------|
| Hydraulics | `stdlib/hidraulica.crysl` |
| Fire protection + electrical | `stdlib/nfpa_electrico.crysl` |
| Structural / civil | `stdlib/civil.crysl` |
| Mechanical | `stdlib/mecanica.crysl` |
| Thermal / HVAC | `stdlib/termica.crysl` |
| Sanitary / plumbing | `stdlib/sanitaria.crysl` |
| New domain | Create `stdlib/{domain}.crysl` |

### 2. Write the plan

```crysl
plan_{domain}_{calculation}(
    param1: f64,           // description (unit)
    param2: f64 = default  // description with default
) {
    meta {
        standard: "Full standard name and year",
        source:   "Section / table reference",
        domain:   "{domain}",
        version:  "2.0",
    }

    // constants
    const K = 1.234;

    // intermediate variables
    let result = param1 * K / param2;

    // named formula (required — helps users verify)
    formula "Formula name": "result = param1 × K / param2";

    // assertions for all inputs (required — at least one per param)
    assert param1 > 0.0  msg "param1 must be positive";
    assert param2 > 0.0  msg "param2 must be positive";

    // outputs (at least one required)
    output result  label "Human-readable label"  unit "unit_symbol";
}
```

### 3. Add test vectors

Create `tests/{plan_name}.json`:

```json
{
  "plan": "plan_{domain}_{calculation}",
  "cases": [
    {
      "inputs": { "param1": 100.0, "param2": 5.0 },
      "expected": { "result": 24.68 },
      "tolerance": 0.01,
      "source": "Standard name, Example X.Y"
    }
  ]
}
```

### 4. Validate

```bash
# Validate syntax
cargo run --bin crysl-validate -- stdlib/your_domain.crysl

# Run test vectors
cargo test --test plan_tests -- plan_your_plan_name

# Run all tests
cargo test
```

### 5. Submit Pull Request

- Title: `feat(stdlib): add plan_{domain}_{calc} — {Standard name}`
- Description: include the formula, standard citation, and at least one worked example
- All CI checks must pass

---

## Standards We Accept

| Category | Accepted standards |
|----------|--------------------|
| Fire protection | NFPA 13, 20, 25, 72 |
| Electrical | IEC 60364, NEC 2023, IEC 60076 |
| Hydraulics | AWWA, ISO 4427, IS.010 Peru |
| Civil/structural | ACI 318, NTE Peru, Eurocodes, AISC |
| Mechanical | ISO 6336, ASME B31 |
| Thermal | ASHRAE 90.1, ISO 6946 |
| Sanitary | IS.010, IS.020 Peru, EN 806 |

If your standard is not listed, open an issue first to discuss.

---

## Code of Conduct

- Be accurate: all formulas must match the cited standard exactly
- Be clear: variable names should be self-documenting
- Be complete: every input needs an assertion, every plan needs a formula declaration
- Be cited: no plan without a published, verifiable source

Questions? Open a GitHub Issue or Discussion.
