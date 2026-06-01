# Kernel Guidance

Source basis: `https://github.com/intel/linux-kernel-oops`, `https://mcpmarket.com/tools/skills/kernel-debug-loop`, and `https://mcpmarket.com/tools/skills/linux-kernel-pro`.

Use this as condensed working guidance, not as a copy of the upstream material.

## Evidence To Capture

- Kernel version, config hints, architecture, virtualization/container mode.
- Kernel logs from `dmesg` and `journalctl -k`, with boot ID and time window.
- Taint state before and after the experiment.
- OOPS/WARN/hung-task/RCU-stall deltas.
- Module list and any module loaded/unloaded by the experiment.
- Scope and applied state: process/cgroup, interface, filesystem, device mapper device, eBPF program/map, debugfs knob, sysctl, or qdisc.
- Rollback and cleanup state.

## Safety Defaults

- Prefer read-only OOPS detection and preflight inventory.
- Keep actual fault triggers lab-only until rollback is proven on a disposable target.
- Require exact scope; broad host or kernel-global scope needs explicit confirm and lab mode.
- Abort on new kernel taint, OOPS, WARN splat, hung task, RCU stall, control-path loss, or rollback failure.
- Do not run kernel experiments without out-of-band recovery for dedicated-validation targets.

## Review Questions

- Can the experiment prove a clean kernel log before it starts?
- Does it separate stale boot logs from new experiment-window evidence?
- Can rollback be verified mechanically?
- Are control-plane services excluded?
- Is the failure realistic enough to justify kernel risk?
