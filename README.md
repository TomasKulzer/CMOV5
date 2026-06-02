# OAI 5G Lab — Experiment Runner

Scripts for the 5G OAI lab experiments.  


---

## Files

| File | Purpose | Run on |
|---|---|---|
| `config.sh` | Shared variables & helper functions (sourced by others) | — |
| `task1.sh` | Single UE ping test (UL + DL, 10 pings each) | gNB (tux12) |
| `task2.sh` | Multi-UE ping test (2 UEs, 10 pings each direction) | gNB (tux12) |
| `task3.sh` | Bandwidth reconfig to 100/20 MHz + RTT (60 pings each direction) | gNB (tux12) |
| `task4.sh` | iperf throughput (TCP & UDP, UL & DL, 60s each) | gNB (tux12) |
| `core_capture.sh` | tcpdump packet capture on the Core side | Core (tux22) |
| `initial_setup.sh` | One-time setup (routing, iptables, docker compose) | Both |
| `multi-ue.sh` | Network namespace creation/deletion | gNB (tux12) |

---

## Prerequisites

### Before first run (one-time setup)

**On the Core (tux22 — 10.227.20.82):**
```bash
cd ~/oai-cn5g
sudo docker compose down
sudo docker compose up -d
sudo docker exec oai-ext-dn ip route add 10.0.0.0/24 via 192.168.70.134
```

**On the gNB (tux12 — 10.227.20.72):**
```bash
cd ~
bash initial_setup.sh gnb
```

**Optional — password-less SSH (avoids password prompts during experiments):**
```bash
# On gNB:
ssh-keygen -t rsa               # press Enter for defaults
ssh-copy-id mobile@10.227.20.82
```
And on the Core (`sudo visudo` → add `mobile ALL=(ALL) NOPASSWD: ALL`).

### After every Core restart
```bash
cd ~/oai-cn5g
sudo docker compose down && sudo docker compose up -d
sudo docker exec oai-ext-dn ip route add 10.0.0.0/24 via 192.168.70.134
```
Do **NOT** run `bash initial_setup.sh core` after Docker is already running — it flushes iptables rules that Docker needs for forwarding.

### Copy scripts to remote machines
```bash
scp -r ~/lab5 mobile@10.227.20.72:~/
scp -r ~/lab5 mobile@10.227.20.82:~/
scp ~/lab5/multi-ue.sh mobile@10.227.20.72:~/multi-ue.sh
```

---

## Running the Experiments

### Task 1 — Single UE Connectivity (10 pings)

**Terminal 1 — Core:**
```bash
cd ~/lab5
bash core_capture.sh 1
```

**Terminal 2 — gNB:**
```bash
cd ~/lab5
bash task1.sh
```

#### Expected results
```
UE IP = 10.0.0.x
```
- Uplink: 10/10 packets received, 0% loss, RTT ~40–55 ms
- Downlink: 10/10 packets received, 0% loss, RTT ~40–55 ms
- Capture: `/tmp/dl-ul-pings-task1.pcap` (Core)

---

### Task 2 — Multi-UE Connectivity (10 pings × 2 UEs)

**Terminal 1 — Core:**
```bash
cd ~/lab5
bash core_capture.sh 2
```

**Terminal 2 — gNB:**
```bash
cd ~/lab5
bash task2.sh
```

#### Expected results
```
UE1 = 10.0.0.x    UE2 = 10.0.0.y
```
- Both UEs obtain distinct IPs on the `oaitun_ue1` interface
- Uplink: 10/10 each, 0% loss, RTT ~40–55 ms
- Downlink: 10/10 each, 0% loss, RTT ~40–55 ms
- Capture: `/tmp/dl-ul-pings-task2.pcap` (Core)

---

### Task 3 — Bandwidth Reconfiguration + RTT (60 pings × 2 UEs)

This reconfigures the gNB to 100 MHz (or 20 MHz) bandwidth at 3500 MHz, starts both UEs, then runs 60 pings in each direction.  
**Leaves the gNB and UEs running** so Task 4 can follow immediately.

**Terminal 1 — Core:**
```bash
cd ~/lab5
bash core_capture.sh 3
```

**Terminal 2 — gNB:**
```bash
cd ~/lab5
bash task3.sh 100
```
Use `100` for 100 MHz bandwidth. (20 MHz is also available but may not work in all OAI versions.)

#### Expected results
```
UE1 IP = 10.0.0.x    UE2 IP = 10.0.0.y
```
- 60/60 uplink packets, 0% loss, RTT ~44–55 ms
- 60/60 downlink packets, 0% loss, RTT ~44–55 ms
- Slightly lower RTT than 20 MHz configuration
- Capture: `/tmp/dl-ul-pings-task3.pcap` (Core)

#### Output files (saved to `~/` on gNB)
| File | Content |
|---|---|
| `rtt_ul_ue1_100.txt` | Uplink ping log (UE1 → ext-dn) |
| `rtt_ul_ue2_100.txt` | Uplink ping log (UE2 → ext-dn) |
| `rtt_dl_ue1_100.txt` | Downlink ping log (ext-dn → UE1) |
| `rtt_dl_ue2_100.txt` | Downlink ping log (ext-dn → UE2) |
| `/tmp/gnb_task3_full.log` | Full gNB startup log |
| `/tmp/gnb_task3_startup.log` | First 55 lines of gNB log |

---

### Task 4 — Throughput Measurement (iperf)

Run **after Task 3** while the gNB and UEs are still running.

Take the UE IPs printed by Task 3 and pass them as arguments:

```bash
cd ~/lab5
bash task4.sh 10.0.0.x 10.0.0.y 100
```

#### What it measures (for each UE)
1. **UDP Downlink** — iperf server on UE, client on ext-dn (10 Mbit/s, 60 s)
2. **UDP Uplink** — iperf server on ext-dn, client on UE (10 Mbit/s, 60 s)
3. **TCP Downlink** — iperf server on UE, client on ext-dn (60 s)
4. **TCP Uplink** — iperf server on ext-dn, client on UE (60 s)

#### Output files (saved to `~/` on gNB)
| File | Content |
|---|---|
| `throughput_udp_dl_ue1_100.csv` | UDP Downlink throughput (UE1) |
| `throughput_udp_ul_ue1_100.csv` | UDP Uplink throughput (UE1) |
| `throughput_tcp_dl_ue1_100.csv` | TCP Downlink throughput (UE1) |
| `throughput_tcp_ul_ue1_100.csv` | TCP Uplink throughput (UE1) |
| `throughput_udp_dl_ue2_100.csv` | UDP Downlink throughput (UE2) |
| `throughput_udp_ul_ue2_100.csv` | UDP Uplink throughput (UE2) |
| `throughput_tcp_dl_ue2_100.csv` | TCP Downlink throughput (UE2) |
| `throughput_tcp_ul_ue2_100.csv` | TCP Uplink throughput (UE2) |

#### Expected results (100 MHz)
- **UDP:** ~10 Mbit/s (capped by the `-b 10M` flag)
- **TCP:** ~20–30 Mbit/s (not artificially limited)
- UDP UL/DL should be similar; TCP may vary more

---

## Generating Plots

Copy the result files and run the plotter:

```bash
# Copy results from gNB to local
scp mobile@10.227.20.72:~/rtt_*_100.txt ~/lab5/plots-task34/
scp mobile@10.227.20.72:~/throughput_*_100.csv ~/lab5/plots-task34/

# Generate plots
cd ~/lab5/plots-task34
pip install numpy pandas matplotlib
python3 plotter.py
```

The plotter produces:
- **2×2 throughput plot:** UDP DL, UDP UL, TCP DL, TCP UL (UE1 + UE2 overlaid)
- **1×2 RTT plot:** DL RTT, UL RTT (UE1 + UE2 overlaid)
- **Summary tables** printed to terminal (mean/min/max throughput and RTT)

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| `oaitun_ue1` doesn't exist | UEs didn't attach to gNB in time | Increase `wait_for` times in the script, or check gNB log with `tmux attach -t gnb` |
| Downlink ping 100% loss | Missing route in `oai-ext-dn` or broken iptables | `sudo docker exec oai-ext-dn ip route add 10.0.0.0/24 via 192.168.70.134` |
| UE1/UE2 both get same IP | Namespace collision from a previous run | `sudo bash multi-ue.sh -d1 && sudo bash multi-ue.sh -d2` and re-run |
| iperf "Connection refused" | iperf server wasn't started in time | Check if the tmux `iperf` session is running (`tmux ls`) |
| Password prompts during script | SSH keys not set up | Run `ssh-copy-id mobile@10.227.20.82` on the gNB |

---

## Cleanup

After you're done, kill all sessions on the gNB:

```bash
tmux kill-server
sudo ip netns del ue1 2>/dev/null
sudo ip netns del ue2 2>/dev/null
sudo ip link del v-eth1 2>/dev/null
sudo ip link del v-eth2 2>/dev/null
```
