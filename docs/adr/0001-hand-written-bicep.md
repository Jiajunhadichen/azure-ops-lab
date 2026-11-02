# ADR 0001: Write infrastructure in hand-written Bicep

- Status: Proposed
- Date: 2026-10-12 (revised 2026-10-18: AVM changed from "use where it fits" to "reference only", to match the code)

## Context
The lab has to be created and destroyed with one command, many times, so it must be described as code.
I am preparing for AZ-104, which tests ARM templates and Bicep, not Terraform.
I must be able to explain every property I deploy, in an interview and in the exam.

## Decision
- Use Bicep for all infrastructure in `infra/`.
- Write resources by hand, in small local modules (`infra/modules/`).
- Use Azure Verified Modules (AVM) only as a reference for sensible defaults, not as dependencies.

## Consequences
- Good: same language as the exam; `bicep build`, lint and `what-if` give fast feedback before anything is deployed.
- Good: every property in the templates is one I chose and can explain; no external module versions to track.
- Bad: I have to look up secure defaults myself (AVM would bring many of them for free), so reviews must check them.
- Bad: Bicep is Azure-only, so this repo shows nothing about multi-cloud tools.

## Alternatives considered
- AVM modules from the public Bicep registry: Microsoft-maintained defaults, but each module has many parameters and hides what is deployed. The first draft of this ADR chose them; the templates never used them.
- Terraform: widely used in job ads, but not tested on AZ-104 and needs a remote state file to manage.
- Raw ARM JSON: what the portal exports, but hard to read and review.
- Portal clicks only: fine for learning, but not repeatable and leaves no history.
