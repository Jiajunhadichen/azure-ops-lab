// Example values only. Copy to main.local.bicepparam (git-ignored) and put real values there.
using 'main.bicep'

param adminSourceIp = '203.0.113.10/32' // documentation range, replace with your IP
param sshPublicKey = 'ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY'
param owner = 'hadi'
param expires = '2026-12-06'
param keepalive = false
param useNatGateway = false
