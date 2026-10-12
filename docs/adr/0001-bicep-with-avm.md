# ADR 0001: Write infrastructure in Bicep, using Azure Verified Modules where they fit

- Status: Proposed
- Date: 2026-10-12

## Context
The lab has to be created and destroyed with one command, many times, so it must be described as code.
I am preparing for AZ-104, which tests ARM templates and Bicep, not Terraform.
I want modules that follow Microsoft's own defaults instead of writing every resource from scratch.

## Decision
- Use Bicep for all infrastructure in `infra/`.
- Use Azure Verified Modules (AVM) from the public Bicep registry where a module exists and is simple enough for me to explain. Pin every module to an exact version.
- Write a resource by hand when the AVM module hides too much for me to explain it in an interview.

## Consequences
- Good: same language as the exam; `bicep build`, lint and `what-if` give fast feedback before anything is deployed.
- Good: pinned module versions make deployments repeatable.
- Bad: AVM modules have many parameters; I must read each one I use, or I cannot defend the defaults.
- Bad: Bicep is Azure-only, so this repo shows nothing about multi-cloud tools.

## Alternatives considered
- Terraform: widely used in job ads, but not tested on AZ-104 and needs a remote state file to manage.
- Raw ARM JSON: what the portal exports, but hard to read and review.
- Portal clicks only: fine for learning, but not repeatable and leaves no history.
