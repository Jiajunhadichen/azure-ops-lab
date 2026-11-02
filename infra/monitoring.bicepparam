// The alert email comes from the ALERT_EMAIL environment variable, so it never lands in git.
using 'monitoring.bicep'

param alertEmail = readEnvironmentVariable('ALERT_EMAIL')
param owner = 'hadi'
param expires = '2026-12-31'
param keepalive = false
