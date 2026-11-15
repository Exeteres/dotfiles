# Empirical example (2026-11-15)

One TypeScript/Nuxt workspace, matching source/lockfile and Bun 1.3.13:
local Ryzen 7 8845HS / 32 GB versus remote Icelake / 8 vCPU / 32 GiB.
These observations are not universal defaults or hardware performance promises.

- Local production builds: 62–109s; remote: 61–67s.
- Same frontend edit: remote build 61.3s + ordinary delta sync 28.6s;
  local rebuild 109.4s in that trial, but substantially faster in earlier trials.
- Reverse edit + checksum-selected sync: build 61.1s + transfer 18.4s.
  Seven selected files instead of 699, 1.18 MB received.
- Cold artifact download: 99.8s / 8.36 MB. Unchanged sync: 3.3s.
  Neither is a changed-build daily cost.
- Assembled output with stable local workspace dependencies passed API smoke and
  real-browser verification of both added and removed frontend markers.
- Local/remote backend test batches were about 9s. Remote dev backend started
  in about 12s but its tunneled frontend failed a 180s browser load check.

Lesson: prefer offloading independent CPU work and checksum-selected artifacts,
not assuming remote interactive dev or a faster single build. Measure on the
current project/host/network. Never retain project-specific credentials or state
as part of this generic skill.
