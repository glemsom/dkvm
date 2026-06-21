# Networking

DKVM provides three networking modes for different use cases. Bridge mode is
the default and recommended for production use.

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

## 3. Port Forwarding

Port forwarding exposes guest services on the host network.

### Forwarding to DKVM Host

If the DKVM host is on the LAN (bridge mode), its IP is on `br0`.
Forwarding to a guest on the bridge requires no extra setup — the guest has its
own LAN IP. Just connect directly:

```bash
ssh root@<guest-ip>
```

### Forwarding Through the Host (User-Mode)

In user-mode networking, use QEMU `hostfwd` rules:

```bash
# Forward host port 2222 to guest port 22
hostfwd=tcp::2222-:22

# Forward host port 8080 to guest port 80
hostfwd=tcp::8080-:80
```

### Firewall / Network Segment Considerations

If the DKVM host sits behind a firewall or on an isolated network segment, ensure:

- The LAN router gives DHCP leases to the bridge interface.
- Inbound traffic to forwarded ports is allowed.
- The bridge has `STP` disabled (already the default in `answer.txt`) to avoid
  forwarding delays.

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
