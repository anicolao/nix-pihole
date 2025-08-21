# Proposal: Lightweight Integration Testing for Pi-hole on SBCs

## 1. Introduction

To validate the DHCP and DNS filtering capabilities of our Pi-hole project on resource-constrained Single Board Computers (SBCs), a robust integration test is required. Full virtualization is too heavyweight for these systems. This document proposes a lightweight, isolated testing methodology using **Linux network namespaces**.

---

## 2. Concept: A "Network in a Box" 📦

This approach creates a self-contained, virtual network entirely within the SBC's Linux kernel. It uses three core components:

* **Network Namespaces:** Isolated network stacks that act as virtual "rooms" for our server and client processes.
* **Virtual Ethernet (`veth`) Pairs:** Virtual "network cables" that connect these rooms.
* **Linux Bridge:** A virtual "network switch" that links all the cables together into a single LAN.

This allows us to simulate a real-world network with a DHCP/DNS server and clients without affecting the host system's network or requiring heavy virtualization.

---

## 3. Proposed Architecture

The test environment will consist of a Linux bridge (`br-test`) connecting two network namespaces: one for the Pi-hole server (`ns-pihole`) and one for a test client (`ns-client`).

[Image of a network namespace diagram]

```
                 ┌───────────────────┐
                 │   SBC Host System │
                 │ ┌─────────────────┐ │
                 │ │ Virtual Switch  │ │
                 │ │    (br-test)    │ │
                 │ └───────┬─────────┘ │
                 │         │           │
           (veth-pihole-br)│           │(veth-client-br)
                         ┌─┴─┐       ┌─┴─┐
           "Virtual       │ │       │ │      "Virtual
            Cables"      └─┬─┘       └─┬─┘       Cables"
                         ┌─▼─┐       ┌─▼─┐
            (veth-pihole-ns)│           │(veth-client-ns)
                 │ ┌─────────────────┐ │ ┌─────────────────┐ │
                 │ │ ns-pihole       │ │ │ ns-client       │ │
                 │ │ (DHCP/DNS Server) │ │ │ (DHCP/DNS Client) │ │
                 │ └─────────────────┘ │ └─────────────────┘ │
                 └───────────────────┘
```

---

## 4. Implementation Plan

The entire test environment can be created and torn down with a script executing the following steps.

### Step 1: Create the Virtual Switch (Bridge)
```shell
# Create the bridge device
sudo ip link add br-test type bridge

# Bring the bridge online
sudo ip link set br-test up
```

### Step 2: Create and Configure the Pi-hole Namespace
```shell
# Create the namespace
sudo ip netns add ns-pihole

# Create the virtual cable (veth pair)
sudo ip link add veth-pihole-ns type veth peer name veth-pihole-br

# "Plug" one end into the switch and the other into the namespace
sudo ip link set veth-pihole-br master br-test
sudo ip link set veth-pihole-ns netns ns-pihole

# Configure the network inside the namespace and start services
sudo ip netns exec ns-pihole bash <<EOF
  ip addr add 192.168.100.1/24 dev veth-pihole-ns
  ip link set veth-pihole-ns up
  ip link set lo up

  # Placeholder for starting Pi-hole services
  # pihole-FTL &
EOF
```

### Step 3: Create and Configure the Client Namespace
```shell
# Create the namespace
sudo ip netns add ns-client

# Create the virtual cable (veth pair)
sudo ip link add v-eth-client type veth peer name v-eth-client-br

# "Plug" one end into the switch and the other into the namespace
sudo ip link set v-eth-client-br master br-test
sudo ip link set v-eth-client netns ns-client
```

---

## 5. Validation and Testing

With the environment running, validation will be performed by executing commands inside the client namespace.

```shell
sudo ip netns exec ns-client bash <<EOF
  # Bring the client interface up
  ip link set v-eth-client up

  # 1. Test
