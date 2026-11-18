# What remote development measurements tell us

Anonymized observations from several development sessions. These are illustrative
costs, not service levels or hardware rankings. No new experiments were run for
this summary. Raw project logs, resource identifiers and credential-bearing
evidence are intentionally omitted. Read `validation.md` for operational lessons.

## Paired build example

One TypeScript web workspace used matching source, lockfile and runtime on a
local 8-core/16-thread laptop and an 8-vCPU remote server, both with about 32 GiB
RAM. Only these trials had a corresponding local baseline:

| Work | Local | Remote |
| --- | ---: | ---: |
| Production builds, observed range | 62–109s | 61–67s |
| Same small frontend edit, rebuild | 109.4s | 61.3s |
| Backend test batch | about 9s | about 9s |

The changed build then needed 28.6s to synchronize output: about 89.9s total,
excluding source upload and validation. A separate reverse-edit build plus
checksum-selected transfer took 61.1s + 18.4s, selecting seven files rather than
699 and receiving about 1.18 MB. That was not a same-artifact A/B comparison of
rsync flags. Earlier local builds were faster than either remote end-to-end path;
there is no consistent latency win established here.

Stable matching local dependencies plus pulled output passed API and browser
checks, including verification of added and removed frontend markers. A remote
dev backend became ready in about 12s, but its tunneled frontend failed a 180s
browser-load check. Backend readiness alone did not validate interactive offload.

## Artifact shape matters

These are separate workloads and source states, not directly comparable trials.
MB below denotes approximate decimal bytes, not allocated disk usage.

| Artifact / transfer | Observation | Useful interpretation |
| --- | --- | --- |
| Web output, cold pull | 8.36 MB received in 99.8s | Provisioning cost, not daily delta cost |
| Same output, unchanged sync | 3.3s | No-op protocol/manifest cost, not a changed-build result |
| Portable library, initial pull | 1.10 MB logical size; 0.10 MB received in 2.0s | Compression can help text-like output |
| Library update, two files | 1.10 MB selected; 3.8 KB literal; 1.7 KB received + 8.2 KB sent in 1.5s | Existing local files can be an effective rsync basis |
| Small source-package update | 23.9 KB selected; 2.2 KB literal in 1.3s | Small deltas can be cheap; obsolete files were removed only in a marked scratch directory |
| OCI image archive, cold pull | 1.25 GB logical; 1.25 GB received in 398s | Already-compressed layers gained little from transport compression |
| Later OCI archive, changed pull | 1.25 GB selected; 329 MB matched, 924 MB literal; 922 MB received in 274s | An old archive was a poor enough basis that most bytes still transferred |

The later image build/export alone took about 337s. A transfer-path failure did
not invalidate that successful build: fixing the artifact directory was sufficient
to retry transfer. Consider running container tests remotely or evaluating
layer-aware image distribution before choosing whole-archive downloads; neither
alternative was benchmarked here.

Selected logical bytes, matched bytes, literal bytes, received bytes and total
bidirectional traffic are different measures. Protocol/checksum overhead can exceed
a tiny source delta. Do not label their ratios as compiler or network speedups.

## Unpaired provisioning and validation examples

Other sessions reported frozen dependency installs in roughly 12–23s and bootstrap
steps in roughly 4–8s. Typecheck batches took 53–93s with different scopes/caches;
production-build-plus-browser-test invocations took 86–134s. A mixed cached
build/typecheck/test batch took about 12s, with 11 of 18 tasks hitting cache.
These are not matched cache-on/off, revision-to-revision or local/remote results.
Do not combine their ranges into a single performance comparison.

Cold browser provisioning took about 894s and exited successfully **with the wrong
browser revision**. Installing the exact harness-compatible revision later took
22s. Installation exit status was not proof that tests could run; provisioning
cost must remain separate from warm iteration and actual validation.

Repeated image builds reduced one host's free disk from about 29 GiB to 10 GiB;
an owned builder reported about 6.9 GB reclaimable. These were historical readings,
not reserved capacity or permission to prune shared caches. Recheck capacity and
ownership before each large job.

## Decision rule

Prefer independent remote CPU work when freeing local resources is useful.
For latency, measure source sync + setup invalidation + work + artifact transfer +
assembly + validation, using repeated comparable trials. Prefer checksum-selected
portable deltas where practical; do not assume that OCI archives or interactive
dev loops have the same economics. Retest on the current project, host and network.
