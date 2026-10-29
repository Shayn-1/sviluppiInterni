# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Salesforce DX project for **SIAE** (Società Italiana degli Autori ed Editori), developed by NTT Data. It implements custom pricing logic and licensing calculations on top of Salesforce Revenue Cloud / Industries (RevSignaling, Context API).

- **Source API Version:** 66.0 (Winter '25)
- **Default org alias:** `SIAE_DEV`
- **Source root:** `force-app/main/default/`

## Common Commands

### Deploy / Retrieve metadata
```bash
# Deploy all metadata to default org
sf project deploy start --source-dir force-app

# Deploy a single file
sf project deploy start --source-file force-app/main/default/classes/SIAE_POSH_PricingMdAPlan.cls

# Retrieve from org
sf project retrieve start --source-dir force-app
```

### Apex & Anonymous Scripts
```bash
# Run anonymous Apex
sf apex run --file scripts/apex/hello.apex

# Run SOQL
sf data query --file scripts/soql/account.soql
```

### Testing
```bash
# Run all LWC unit tests
npm test

# Watch mode for LWC tests
npm run test:unit:watch

# Run with coverage
npm run test:unit:coverage

# Run a single LWC test file
npx sfdx-lwc-jest -- --testPathPattern="<componentName>"
```

### Linting & Formatting
```bash
# Lint LWC/Aura JS
npm run lint

# Format all supported files (write)
npm run prettier

# Verify formatting without writing
npm run prettier:verify
```

> **Pre-commit hook** runs `lint-staged` automatically: Prettier formats staged files, ESLint checks LWC/Aura JS, and `sfdx-lwc-jest` runs tests related to changed LWC files.

## Architecture

### Apex Class Naming Conventions
All classes follow the pattern `SIAE_<LAYER>_<FunctionalName>`:
- `SIAE_POSH_*` — Post/Pre Hook implementations (implement `RevSignaling.SignalingApexProcessor`)
- `SIAE_UTIL_*` — Pure utility/calculation classes (no DML, no callouts, stateless)
- `SIAE_DTO_*` — Data Transfer Objects (inner/standalone result/container classes)

### Pricing Engine (MdA — Music licensing)
The MdA pricing flow uses Salesforce Revenue Cloud's Context API (RevSignaling):

1. **`SIAE_POSH_PricingMdAPlan`** — Post-hook implementing `RevSignaling.SignalingApexProcessor`. Queries the transaction context for `SalesTransactionItem` and `SalesTransactionItemAttribute` nodes, builds maps of products/attributes, then calls downstream utilities. Large commented-out block inside `executeInternal()` represents in-progress development.

2. **`SIAE_UTIL_CalculateCommercialQuote`** — Calculates discounts and associative quotas (`SIAE_AccordoCommerciale__c`). Key map: `CodiceAccordoCommerciale|CodiceDiIncrocio (product Family)` → `SIAE_AccordoCommerciale__c`. Supports three quota logics: `QUOTA_UNITARIA`, `QUOTA_SU_NETTO_DDA`, `QUOTA_SU_NETTO_DDA_CON_MINIMO`.

3. **`SIAE_UTIL_PricingMdA`** — Stateless helpers for MdA pricing: seasonality coefficients, outdoor area surcharges, > 500 sqm surcharges, employee > 200 surcharges, TV > 40" surcharges. All driven by `SIAE_ConfigurazionePricing__c` custom settings.

4. **`SIAE_UTIL_ProcedurePlanOrchestrator`** — Simpler post-hook that writes `SalesTrxnItemDescription` back to context nodes.

### Pricing Engine (Diritti Connessi — Related rights)
Rule-based licensing engine for related/neighbouring rights:

1. **`SIAE_UTIL_DirittiConnessiEngine`** — Orchestrator. Loads `SIAE_DirittiConnessiConfig__mdt` by product code, then loads `SIAE_DirittiConnessiTariffa__c` (bracket tariffs) and `SIAE_DirittiConnessiRule__c` (evaluation rules), groups `OrderItemAttribute` by item, and calls the rule engine per item.

2. **`SIAE_UTIL_DirittiConnessiRuleEngine`** — Core rule evaluator. For each rule, checks condition (`conditionMatches`: ALWAYS / EQ / IN / LTE / GT / BETWEEN), resolves threshold value, looks up bracket tariff (`getRate` with overflow/extra handling), determines quantity, applies pricing action (`TARIFFA_BASE` / `MAGGIORAZIONE_PCT` / `MAGGIORAZIONE_FLAT` / `RIDUZIONE_PCT` / `RIDUZIONE_FLAT` / `MOLTIPLICATORE`). Returns `SIAE_DTO_DirittiConnessiResult.LicenzaDetail`.

### Key Custom Objects / Metadata
- `SIAE_AccordoCommerciale__c` — Commercial agreements; keyed by `CodiceAccordoCommerciale + CodiceDiIncrocio`
- `SIAE_ConfigurazionePricing__c` — Custom Settings driving MdA pricing coefficients and thresholds
- `SIAE_DirittiConnessiConfig__mdt` — Custom Metadata enabling calculation per product code
- `SIAE_DirittiConnessiTariffa__c` — Bracket tariff table (device type, from/to, amounts)
- `SIAE_DirittiConnessiRule__c` — Rule table with condition/action definitions

### Testability Pattern
`SIAE_POSH_PricingMdAPlan` uses an `IIndustriesContextAdapter` interface to wrap `Context.IndustriesContext`, enabling unit tests to mock context calls without a live org. Methods marked `@TestVisible` expose private logic for testing.

### `QueryAttribute.json`
Large JSON snapshot (~840 KB) of a real `SalesTransactionItemAttribute` context query result. Used as reference data for development and debugging of context-based hooks.
