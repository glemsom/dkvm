# Networking

DKVM provides three networking modes for different use cases. Bridge mode is
the default and recommended for production use.

> **Terminology**: See [CONTEXT.md](../../CONTEXT.md) for definitions of
> "DKVMDATA", "Guest", "Host", "lbu", and other project terms.

## Prerequisites

Before configuring DKVM networking, ensure:

- **DKVM is installed and booting** — follow the
  [First-Boot Walkthrough](first-boot.md) if you have not done so yet.
- **A `DKVMDATA` partition is set up** — the DKVM Manager requires it to save
  VM configurations. See [Setting Up DKVMDATA](first-boot.md#3-setting-up-dkvdata).
- **Physical network** — an Ethernet cable connected to the host and a router
  that provides DHCP leases on the LAN.
- **Wireless note** — DKVM currently supports wired Ethernet only. Wi-Fi is not
  supported in this release.

## Mode Comparison

The three networking modes serve different use cases:

| Mode | Guest Reachable from LAN | Requires DHCP | Use Case |
|------|--------------------------|---------------|----------|
| Bridge (default) | ✅ Full LAN access | Yes | Production VMs needing full network presence |
| User-mode (NAT) | ❌ Isolated behind host | No (QEMU built-in) | Quick testing, development, isolated guests |
| Port forwarding | Via user-mode NAT only | Via user-mode NAT only | Exposing specific guest services (e.g., SSH) via hostfwd rules |

---

---

## 1. Bridge Mode (Default)

The DKVM host creates a bridge `br0` that binds to the physical Ethernet
interface (`eth0`). Guest VMs attached to this bridge receive LAN IPs via DHCP,
making them fully routable on the local network.

### How It Is Configured

The bridge is set up during the image build via `scripts/answer.txt`:

```bash
auto br0
iface br0 inet dhcp
    hostname dkvm
    bridge_ports eth0
    bridge_stp 0
```

- **`br0`** — the bridge interface.
- **`bridge_ports eth0`** — the physical NIC attached to the bridge.
- **`bridge_stp 0`** — Spanning Tree Protocol disabled (single-bridge, no loops).
- **DHCP** — the bridge acquires its own IP from the LAN router.

The DKVM host IP can be checked at runtime:

```bash
ip addr show br0
```

### Guest VM Networking in Bridge Mode

When you create a VM via DKVM Manager, it connects the guest to the bridge.
The guest's NIC appears as a port on `br0`. The guest gets its own LAN IP via
DHCP, just like any other machine on the network.

---

## 2. QEMU User-Mode Networking

User-mode networking is the QEMU default when no bridge is configured. It does
not require any host network configuration and works without root privileges,
but the guest is **not directly reachable** from the LAN — only outbound
connections and port forwarding work.

### How It Works

QEMU's built-in SLiRP stack provides NAT, DHCP, and DNS to the guest. The guest
is isolated behind the host's IP.

### DKVM Makefile `run` Target Example

The Makefile `run` target uses user-mode networking for smoke testing:

```makefile
	-netdev user,id=mynet0,hostfwd=tcp::2222-:22 \
	-device e1000,netdev=mynet0
```

This forwards host port **2222** to guest port **22** (SSH). To SSH into the
guest from the build host:

```bash
ssh -p 2222 root@localhost
```

### Use Cases

- **Testing** a built image without LAN access.
- **Isolated environments** where the guest only needs internet access via NAT.
- **Development** on a machine without a dedicated network to bridge.

---

## 3. Connecting to Guest Services

Two approaches exist depending on the networking mode.

### Via bridge (direct)

When the guest uses **bridge mode**, it has its own LAN IP. No port forwarding
is needed — connect directly from any machine on the same network:

```bash
ssh root@<guest-ip>
```

No extra QEMU configuration is required beyond attaching the guest NIC to `br0`
(as DKVM Manager does by default).

### Via user-mode NAT (port forwarding)

When the guest uses **user-mode networking**, it is isolated behind the host.
Expose guest services using QEMU `hostfwd` rules:

```bash
# Forward host port 2222 to guest port 22
hostfwd=tcp::2222-:22

# Forward host port 8080 to guest port 80
hostfwd=tcp::8080-:80
```

Apply these rules in the `-netdev` option of the QEMU command line. For example,
the DKVM Makefile `run` target forwards host port 2222 to guest SSH:

```makefile
-netdev user,id=mynet0,hostfwd=tcp::2222-:22 \
-device e1000,netdev=mynet0
```

Then SSH from the host:

```bash
ssh -p 2222 root@localhost
```

### Firewall and Network Segment Considerations

Regardless of the approach chosen, if the DKVM host sits behind a firewall or on
an isolated network segment:

- Ensure the LAN router gives DHCP leases to the bridge interface (bridge mode).
- Ensure inbound traffic to forwarded ports is allowed (user-mode NAT).
- Keep `STP` disabled on the bridge (already the default in `answer.txt`) to
  avoid forwarding delays.

---

## 4. Troubleshooting

### No DHCP Lease

- Verify the bridge interface exists:
  ```bash
  ip a show br0
  ```
- Check if `eth0` is linked to the bridge:
  ```bash
  bridge link show
  ```
- If `br0` has no IP, force a DHCP renewal:
  ```bash
  udhcpc -i br0
  ```
- Check the physical cable / link:
  ```bash
  ip link show eth0
  ```

### Bridge Not Created at Boot

- The bridge is configured in `/etc/network/interfaces` by the build process.
  If it is missing, check that the file contains the `br0` stanza (see
  [Bridge Mode](#1-bridge-mode-default) above).
- Verify OpenRC networking services are enabled:
  ```bash
  rc-service networking restart
  ```
- Check kernel module `bridge` is loaded:
  ```bash
  lsmod | grep bridge
  ```

### Guest Cannot Reach Network

- **In bridge mode**: ensure the guest NIC is attached to `br0`. Check
  `bridge link show` to see connected interfaces.
- **In user-mode**: no configuration needed — the guest gets NAT access by
  default. Verify with:
  ```bash
  ping 8.8.8.8
  ```
- If the guest has an IP but no internet, check DNS:
  ```bash
  cat /etc/resolv.conf
  ```
- If the guest has no IP at all, verify DHCP is running inside the guest.

### SSH Access Not Working

- Confirm the DKVM host IP:
  ```bash
  ip addr show br0
  ```
- Root SSH is enabled by default (`PermitRootLogin yes` in
  `/etc/ssh/sshd_config`).
- Test from another machine:
  ```bash
  ssh root@<dkvm-ip>
  ```
- Check `sshd` is running:
  ```bash
  rc-service sshd status
  ```

---

*Last updated: 2026-06-23*
