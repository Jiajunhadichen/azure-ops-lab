# ADR 0002: Give each VM a Standard public IP for outbound access; keep NAT Gateway as an option

- Status: Proposed
- Date: 2026-10-12

## Context
Microsoft is retiring default outbound access. For virtual networks created with API versions released after 2026-03-31, subnets are private by default, and a VM needs an explicit outbound method (NAT Gateway, Standard Load Balancer outbound rules, a Standard public IP, or a firewall/NVA with a route table).
Source: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access
Both lab VMs need outbound internet to install packages and send monitoring data. Cost must stay low.

## Decision
- Each VM gets its own Standard public IP.
- The NSG allows inbound traffic only from my own IP address (SSH to both VMs, HTTP to the web VM). Everything else inbound is denied.
- SSH uses keys only, no passwords.
- A NAT Gateway is available behind a parameter (`useNatGateway`, default `false`). When it is on, the VMs have no public IPs.

## Consequences
- Good: cheapest explicit outbound method for two VMs (estimated cost per month: __, to check in the Azure pricing calculator).
- Good: easy to explain and to troubleshoot with NSG effective rules.
- Bad: the VMs are reachable from the internet on their public IPs; the NSG rule restricted to my IP is the only guard, so a mistake in that rule exposes SSH.
- Bad: my home IP can change, which breaks access until I update the parameter.

## Alternatives considered
- NAT Gateway for the whole subnet: cleaner design with no inbound exposure, but billed per hour and per GB; more than this lab needs by default.
- Standard Load Balancer outbound rules: needs a load balancer, which this lab leaves out to save cost.
- Azure Firewall or an NVA: far too expensive for a lab and out of scope.
