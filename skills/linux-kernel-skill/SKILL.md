---
name: linux-kernel-skill
description: Use when designing, reviewing, or implementing Linux-kernel-specific diagnostics and chaos experiments, including kernel OOPS triage, dmesg/journal evidence, panic/oops safety, debug loops, fault-injection prerequisites, kernel capability inventory, and dedicated-validation-only kernel fault experiments.
---

# Linux Kernel Skill

Design kernel experiments as guarded diagnostics first. Treat any action that can trigger an OOPS, panic, sysrq, debugfs fault, eBPF program, device-mapper fault, filesystem remount, time source change, entropy depletion, or syscall error path as dedicated-validation-only until inventory and rollback evidence prove it is safe.

## Core Workflow

1. Inventory the target before proposing a fault: kernel version, distro, architecture, virtualization/container status, cgroup scope, loaded modules, lockdown/SELinux/AppArmor status, debugfs, tracefs, eBPF support, device-mapper support, filesystem type, time sync, RNG/entropy state, firewall backend, and control-path network interfaces.
2. Define the smallest observable kernel fault. Prefer preflight-only checks, synthetic probes, and read-only trace evidence before changing kernel state.
3. State the hypothesis around system behavior, not just kernel behavior: service survives, control path remains reachable, error handling is explicit, and recovery evidence is captured.
4. Add abort conditions for kernel taint, OOPS/panic signals, hung tasks, control-path loss, filesystem errors, entropy starvation beyond floor, or rollback failure.
5. Require rollback and post-rollback evidence. If rollback cannot be proven, mark the experiment lab-only and not generally available.

## OOPS And Debug Loop

- Capture `dmesg --ctime --level=emerg,alert,crit,err,warn`, `journalctl -k`, kernel taint, last boot ID, and module list before and after every kernel experiment.
- Parse OOPS evidence for timestamp, task, CPU, PID, taint flags, faulting instruction pointer, call trace, module list, and RIP/PC symbol when available.
- Never classify an experiment as passed when new OOPS, WARN splats, hung-task reports, RCU stalls, blocked tasks, or kernel taint appeared during the window unless the experiment explicitly validates that condition in an isolated lab.
- Run a debug loop: reproduce on a dedicated target, reduce the trigger, collect kernel logs and config, verify rollback, then widen only one parameter at a time.
- Preserve the pre-fault and post-fault boot/session identity so reports can distinguish new kernel evidence from stale logs.

## Experiment Requirements

| Area | Require |
| --- | --- |
| Capability | `CAP_SYS_ADMIN`, `CAP_BPF`, `CAP_NET_ADMIN`, debugfs, tracefs, or dm support must be explicit and tied to the module. |
| Scope | Single host, single cgroup, single interface, single device, or single process tree by default. Broad host scope needs explicit confirmation. |
| Safety | Dedicated target, bounded duration, dry-run/preflight mode, and control-path protection. |
| Evidence | Kernel log delta, taint delta, module/tool versions, selected scope, applied state, rollback state, and service health. |
| Rollback | Remove qdisc/rules/maps/modules/mount changes and verify state returned to baseline. |

## Fault Families

- **Kernel OOPS guardrail**: read-only OOPS detection and gating. Use to prove the target is clean before other faults.
- **Debugfs fault injection**: lab-only; require supported kernel config, debugfs mounted read/write, exact target, and rollback.
- **eBPF observation/injection**: prefer observation first. Injection requires verifier success, map/program cleanup, pinned object cleanup, and capability inventory.
- **Device mapper delay/error**: require device identity, filesystem type, mount status, and explicit rollback path.
- **Filesystem remount**: lab-only unless read-only remount and rollback have been tested on disposable filesystems.
- **Syscall/process fault**: require process/cgroup scope and an allowlist. Never target init, sshd, Ops Agent, database primary, or control-plane daemons by default.

## Output Checklist

For each kernel experiment, include:

- `requires_profile_types: ["ops_agent"]`.
- `remote_ops.result_schema` that names a kernel-specific evidence envelope.
- `guardrails` with `dedicated-validation-only`, `preflight-default`, `kernel-log-delta`, `control-path-protected`, and `rollback-verified`.
- Config for `preflight_only`, `confirm`, `lab_mode`, `duration_seconds`, and exact scope.
- Probes for baseline kernel health, control-path reachability, and post-run kernel log delta.
- Curated measurements for `kernel_taint_delta`, `oops_count_delta`, `warn_count_delta`, `hung_task_delta`, and rollback status.

## References

- Read `references/kernel-guidance.md` for condensed source-derived guidance from the referenced Linux OOPS and kernel debug material.
