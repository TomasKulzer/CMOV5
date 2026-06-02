#!/usr/bin/env python3
import os
import re
import csv
from statistics import median
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


# -----------------------------
# Bandwidths to compare
# -----------------------------
BANDWIDTHS = ["20", "100"]   # filenames end with _20 and _100


# -----------------------------
# File builders
# -----------------------------
def build_throughput_files() -> Dict[str, Dict[str, Dict[str, str]]]:
    """
    Returns:
        {bandwidth: {link_type: {UE: filepath}}}
    """
    files = {}
    for bw in BANDWIDTHS:
        files[bw] = {
            "UDP DL": {
                "UE1": f"throughput_udp_dl_ue1_{bw}.csv",
                "UE2": f"throughput_udp_dl_ue2_{bw}.csv",
            },
            "UDP UL": {
                "UE1": f"throughput_udp_ul_ue1_{bw}.csv",
                "UE2": f"throughput_udp_ul_ue2_{bw}.csv",
            },
            "TCP DL": {
                "UE1": f"throughput_tcp_dl_ue1_{bw}.csv",
                "UE2": f"throughput_tcp_dl_ue2_{bw}.csv",
            },
            "TCP UL": {
                "UE1": f"throughput_tcp_ul_ue1_{bw}.csv",
                "UE2": f"throughput_tcp_ul_ue2_{bw}.csv",
            },
        }
    return files


def build_rtt_files() -> Dict[str, Dict[str, Dict[str, str]]]:
    """
    Returns:
        {bandwidth: {direction: {UE: filepath}}}
    """
    files = {}
    for bw in BANDWIDTHS:
        files[bw] = {
            "DL": {
                "UE1": f"rtt_dl_ue1_{bw}.txt",
                "UE2": f"rtt_dl_ue2_{bw}.txt",
            },
            "UL": {
                "UE1": f"rtt_ul_ue1_{bw}.txt",
                "UE2": f"rtt_ul_ue2_{bw}.txt",
            },
        }
    return files


# -----------------------------
# Helpers
# -----------------------------
INTERVAL_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*$")
RTT_RE = re.compile(r"time[=<]\s*([0-9]*\.?[0-9]+)\s*ms", re.IGNORECASE)


def check_file(path: str) -> None:
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing file: {path}")
    if os.path.getsize(path) == 0:
        raise ValueError(f"Empty file: {path}")


def parse_iperf_csv(path: str) -> pd.DataFrame:
    """
    Parse iPerf CSV robustly.
    - ignores text lines / prompts / malformed rows
    - interval in column 6 (index 6)
    - bandwidth in column 8 (index 8)
    - removes summary row(s)
    """
    check_file(path)

    rows: List[Tuple[float, float, float]] = []

    with open(path, "r", newline="", encoding="utf-8", errors="ignore") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 9:
                continue

            interval_text = row[6].strip()
            bw_text = row[8].strip()

            m = INTERVAL_RE.match(interval_text)
            if not m:
                continue

            try:
                start = float(m.group(1))
                end = float(m.group(2))
                bandwidth_bps = float(bw_text)
            except ValueError:
                continue

            rows.append((start, end, bandwidth_bps))

    if not rows:
        raise ValueError(f"No valid throughput data found in: {path}")

    df = pd.DataFrame(rows, columns=["start_s", "end_s", "bandwidth_bps"])

    # Remove likely summary rows (much wider than normal intervals)
    widths = df["end_s"] - df["start_s"]
    typical_width = float(median(widths)) if len(widths) else 0.0
    if typical_width > 0:
        df = df[widths <= 1.5 * typical_width].copy()

    if df.empty:
        raise ValueError(f"Only summary or invalid rows remained after cleaning: {path}")

    df["throughput_mbps"] = df["bandwidth_bps"] / 1e6
    df = df.sort_values(["start_s", "end_s"]).reset_index(drop=True)
    return df[["start_s", "end_s", "throughput_mbps"]]


def parse_ping_txt(path: str) -> pd.DataFrame:
    """
    Extract RTT values from ping logs using 'time=XX ms'.
    """
    check_file(path)

    rtts_ms: List[float] = []

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            m = RTT_RE.search(line)
            if m:
                try:
                    rtts_ms.append(float(m.group(1)))
                except ValueError:
                    continue

    if not rtts_ms:
        raise ValueError(f"No RTT values found in: {path}")

    return pd.DataFrame(
        {
            "sample": np.arange(1, len(rtts_ms) + 1),
            "rtt_ms": rtts_ms,
        }
    )


# -----------------------------
# Plotting
# -----------------------------
def plot_throughput(throughput_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]]) -> None:
    """
    2x2: UDP DL, UDP UL, TCP DL, TCP UL
    Each subplot overlays UE1/UE2 for both bandwidths (20 and 100).
    """
    fig, axes = plt.subplots(2, 2, figsize=(15, 9), constrained_layout=True)
    axes = axes.flatten()

    plot_order = ["UDP DL", "UDP UL", "TCP DL", "TCP UL"]
    style_map = {
        "20": {"linestyle": "--", "marker": "o"},
        "100": {"linestyle": "-", "marker": "s"},
    }

    for ax, link_type in zip(axes, plot_order):
        for bw in BANDWIDTHS:
            for ue in ["UE1", "UE2"]:
                df = throughput_data.get(bw, {}).get(link_type, {}).get(ue, pd.DataFrame())
                if df.empty:
                    continue
                label = f"{ue} - {bw} MHz"
                ax.plot(
                    df["end_s"],
                    df["throughput_mbps"],
                    linewidth=1.8,
                    markersize=4,
                    label=label,
                    **style_map[bw],
                )

        ax.set_title(link_type)
        ax.set_xlabel("Time (s)")
        ax.set_ylabel("Throughput (Mbps)")
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=9)

    fig.suptitle("5G OAI Testbed Throughput Comparison (20 MHz vs 100 MHz)", fontsize=16)
    plt.show()


def plot_rtt(rtt_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]]) -> None:
    """
    1x2: DL RTT, UL RTT
    Each subplot overlays UE1/UE2 for both bandwidths (20 and 100).
    """
    fig, axes = plt.subplots(1, 2, figsize=(15, 5), constrained_layout=True)

    style_map = {
        "20": {"linestyle": "--", "marker": "o"},
        "100": {"linestyle": "-", "marker": "s"},
    }

    for ax, direction in zip(axes, ["DL", "UL"]):
        for bw in BANDWIDTHS:
            for ue in ["UE1", "UE2"]:
                df = rtt_data.get(bw, {}).get(direction, {}).get(ue, pd.DataFrame())
                if df.empty:
                    continue
                label = f"{ue} - {bw} MHz"
                ax.plot(
                    df["sample"],
                    df["rtt_ms"],
                    linewidth=1.8,
                    markersize=4,
                    label=label,
                    **style_map[bw],
                )

        ax.set_title(f"{direction} RTT")
        ax.set_xlabel("Ping sample")
        ax.set_ylabel("RTT (ms)")
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=9)

    fig.suptitle("5G OAI Testbed RTT Comparison (20 MHz vs 100 MHz)", fontsize=16)
    plt.show()


# -----------------------------
# Summaries
# -----------------------------
def summarize_throughput(throughput_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]]) -> pd.DataFrame:
    records = []
    for bw, link_dict in throughput_data.items():
        for link_type, ue_map in link_dict.items():
            for ue, df in ue_map.items():
                if df.empty:
                    continue
                records.append(
                    {
                        "Bandwidth (MHz)": bw,
                        "Type": link_type,
                        "UE": ue,
                        "Mean Mbps": df["throughput_mbps"].mean(),
                        "Min Mbps": df["throughput_mbps"].min(),
                        "Max Mbps": df["throughput_mbps"].max(),
                    }
                )
    return pd.DataFrame(records)


def summarize_rtt(rtt_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]]) -> pd.DataFrame:
    records = []
    for bw, dir_dict in rtt_data.items():
        for direction, ue_map in dir_dict.items():
            for ue, df in ue_map.items():
                if df.empty:
                    continue
                records.append(
                    {
                        "Bandwidth (MHz)": bw,
                        "Direction": direction,
                        "UE": ue,
                        "Mean RTT (ms)": df["rtt_ms"].mean(),
                        "Min RTT (ms)": df["rtt_ms"].min(),
                        "Max RTT (ms)": df["rtt_ms"].max(),
                    }
                )
    return pd.DataFrame(records)


# -----------------------------
# Main
# -----------------------------
def main() -> None:
    throughput_files = build_throughput_files()
    rtt_files = build_rtt_files()

    throughput_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]] = {}
    rtt_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]] = {}

    # Load throughput files
    for bw, link_dict in throughput_files.items():
        throughput_data[bw] = {}
        for link_type, ue_map in link_dict.items():
            throughput_data[bw][link_type] = {}
            for ue, path in ue_map.items():
                try:
                    throughput_data[bw][link_type][ue] = parse_iperf_csv(path)
                except Exception as e:
                    print(f"[Throughput {bw} MHz] {path}: {e}")
                    throughput_data[bw][link_type][ue] = pd.DataFrame(
                        columns=["start_s", "end_s", "throughput_mbps"]
                    )

    # Load RTT files
    for bw, dir_dict in rtt_files.items():
        rtt_data[bw] = {}
        for direction, ue_map in dir_dict.items():
            rtt_data[bw][direction] = {}
            for ue, path in ue_map.items():
                try:
                    rtt_data[bw][direction][ue] = parse_ping_txt(path)
                except Exception as e:
                    print(f"[RTT {bw} MHz] {path}: {e}")
                    rtt_data[bw][direction][ue] = pd.DataFrame(columns=["sample", "rtt_ms"])

    # Plot only if at least one dataset exists
    any_thr = any(
        not df.empty
        for bw_dict in throughput_data.values()
        for link_dict in bw_dict.values()
        for df in link_dict.values()
    )
    any_rtt = any(
        not df.empty
        for bw_dict in rtt_data.values()
        for dir_dict in bw_dict.values()
        for df in dir_dict.values()
    )

    if any_thr:
        plot_throughput(throughput_data)
    else:
        print("No valid throughput data available to plot.")

    if any_rtt:
        plot_rtt(rtt_data)
    else:
        print("No valid RTT data available to plot.")

    thr_summary = summarize_throughput(throughput_data)
    rtt_summary = summarize_rtt(rtt_data)

    print("\n=== Throughput Summary (higher is better) ===")
    if thr_summary.empty:
        print("No throughput summary available.")
    else:
        print(thr_summary.to_string(index=False))

    print("\n=== RTT Summary (lower is better) ===")
    if rtt_summary.empty:
        print("No RTT summary available.")
    else:
        print(rtt_summary.to_string(index=False))


if __name__ == "__main__":
    main()