#!/usr/bin/env python3
import argparse
import csv
import os
import re
from pathlib import Path
from statistics import median
from typing import Dict, List, Tuple

import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


# -----------------------------
# File lists
# -----------------------------
THROUGHPUT_FILES = {
    "UDP DL": {
        "UE1": "task4_udp_dl_ue1_100.csv",
        "UE2": "task4_udp_dl_ue2_100.csv",
    },
    "UDP UL": {
        "UE1": "task4_udp_ul_ue1_100.csv",
        "UE2": "task4_udp_ul_ue2_100.csv",
    },
    "TCP DL": {
        "UE1": "task4_tcp_dl_ue1_100.csv",
        "UE2": "task4_tcp_dl_ue2_100.csv",
    },
    "TCP UL": {
        "UE1": "task4_tcp_ul_ue1_100.csv",
        "UE2": "task4_tcp_ul_ue2_100.csv",
    },
}

RTT_FILES = {
    "DL": {
        "UE1": "rtt_dl_ue1_100.txt",
        "UE2": "rtt_dl_ue2_100.txt",
    },
    "UL": {
        "UE1": "rtt_ul_ue1_100.txt",
        "UE2": "rtt_ul_ue2_100.txt",
    },
}


# -----------------------------
# Plot styling
# -----------------------------
UE_STYLES = {
    "UE1": {"color": "#2563eb", "marker": "o"},
    "UE2": {"color": "#f97316", "marker": "s"},
}


def apply_plot_style() -> None:
    plt.rcParams.update(
        {
            "figure.facecolor": "#ffffff",
            "axes.facecolor": "#f8fafc",
            "axes.edgecolor": "#cbd5e1",
            "axes.labelcolor": "#0f172a",
            "xtick.color": "#0f172a",
            "ytick.color": "#0f172a",
            "grid.color": "#e2e8f0",
            "grid.linestyle": "-",
            "grid.linewidth": 0.8,
            "axes.titleweight": "bold",
            "axes.titlepad": 10,
            "legend.frameon": True,
            "legend.framealpha": 0.9,
            "legend.facecolor": "#ffffff",
            "legend.edgecolor": "#e2e8f0",
            "font.size": 11,
        }
    )


# -----------------------------
# Helpers
# -----------------------------
INTERVAL_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*$")
RTT_RE = re.compile(r"time[=<]\s*([0-9]*\.?[0-9]+)\s*ms", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plot throughput and RTT for Topic 4 experiments."
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path.cwd(),
        help="Directory containing the CSV/TXT data files.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path.cwd() / "plots",
        help="Directory where plots will be saved.",
    )
    parser.add_argument(
        "--no-show",
        action="store_true",
        help="Skip displaying plot windows (useful on servers).",
    )
    return parser.parse_args()


def check_file(path: str) -> None:
    """Raise a clear error if a file is missing or empty."""
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing file: {path}")
    if os.path.getsize(path) == 0:
        raise ValueError(f"Empty file: {path}")


def parse_iperf_csv(path: str) -> pd.DataFrame:
    """
    Parse an iPerf CSV file robustly.
    - Ignores text lines / prompts / malformed rows
    - Uses interval in column 6 (index 6)
    - Uses bandwidth in column 8 (index 8)
    - Skips summary rows (usually the wide interval spanning the whole test)
    """
    check_file(path)

    rows: List[Tuple[float, float, float]] = []  # start, end, bandwidth_bps

    with open(path, "r", newline="", encoding="utf-8", errors="ignore") as f:
        reader = csv.reader(f)
        for row in reader:
            # Need at least 9 columns for TCP, 14 for UDP.
            if len(row) < 9:
                continue

            interval_text = row[6].strip() if len(row) > 6 else ""
            bw_text = row[8].strip() if len(row) > 8 else ""

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

    # Remove likely summary rows:
    # The summary row typically spans the full test window (wider than normal intervals).
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
    Parse standard ping output and extract RTT values from 'time=XX ms'.
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
                    pass

    if not rtts_ms:
        raise ValueError(f"No RTT values found in: {path}")

    return pd.DataFrame(
        {
            "sample": np.arange(1, len(rtts_ms) + 1),
            "rtt_ms": rtts_ms,
        }
    )


def format_axes(ax: plt.Axes) -> None:
    ax.grid(True, alpha=0.6)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def plot_throughput(
    throughput_data: Dict[str, Dict[str, pd.DataFrame]],
    out_path: Path,
    show: bool,
) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True, sharex=True)
    axes = axes.flatten()

    plot_order = ["UDP DL", "UDP UL", "TCP DL", "TCP UL"]

    # Compute appropriate y-limits per group
    def compute_tcp_ylim(keys: List[str]) -> float:
        max_val = 0.0
        for key in keys:
            for ue in ["UE1", "UE2"]:
                df = throughput_data[key][ue]
                if not df.empty:
                    max_val = max(max_val, df["throughput_mbps"].max())
        return max_val * 1.15 if max_val > 0 else 10.0

    def compute_udp_ylim(keys: List[str]) -> Tuple[float, float]:
        min_val = float("inf")
        max_val = 0.0
        for key in keys:
            for ue in ["UE1", "UE2"]:
                df = throughput_data[key][ue]
                if not df.empty:
                    min_val = min(min_val, df["throughput_mbps"].min())
                    max_val = max(max_val, df["throughput_mbps"].max())
        if min_val == float("inf"):
            return 0.0, 10.0
        # Tight zoom around the data
        margin = max((max_val - min_val) * 0.5, 0.2)
        return max(0, min_val - margin), max_val + margin

    tcp_ylim_top = compute_tcp_ylim(["TCP DL", "TCP UL"])
    udp_ylim_bottom, udp_ylim_top = 10.45, 10.55

    for ax, key in zip(axes, plot_order, strict=True):
        for ue in ["UE1", "UE2"]:
            df = throughput_data[key][ue]
            if df.empty:
                continue
            x = df["end_s"]
            y = df["throughput_mbps"]
            style = UE_STYLES.get(ue, {})
            label = f"{ue} (mean {y.mean():.1f} Mbps)"
            ax.plot(
                x,
                y,
                linewidth=2.0,
                markersize=4,
                label=label,
                **style,
            )

        ax.set_title(key)
        ax.set_xlabel("Time (s)")
        ax.set_ylabel("Throughput (Mbps)")
        
        if "UDP" in key:
            ax.set_ylim(udp_ylim_bottom, udp_ylim_top)
        else:
            ax.set_ylim(bottom=0, top=tcp_ylim_top)
            
        format_axes(ax)
        handles, labels = ax.get_legend_handles_labels()
        if handles:
            ax.legend(loc="upper right")

    # Link y-axes within groups
    axes[1].sharey(axes[0])  # UDP UL shares with UDP DL
    axes[3].sharey(axes[2])  # TCP UL shares with TCP DL

    fig.suptitle("5G OAI Testbed Throughput", fontsize=16, fontweight="bold")
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    print(f"Saved throughput plot: {out_path}")
    if show:
        plt.show()
    plt.close(fig)


def plot_rtt(
    rtt_data: Dict[str, Dict[str, pd.DataFrame]],
    out_path: Path,
    show: bool,
) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(14, 5), constrained_layout=True, sharey=True)

    for ax, key in zip(axes, ["DL", "UL"], strict=True):
        for ue in ["UE1", "UE2"]:
            df = rtt_data[key][ue]
            if df.empty:
                continue
            style = UE_STYLES.get(ue, {})
            label = f"{ue} (mean {df['rtt_ms'].mean():.2f} ms)"
            ax.plot(
                df["sample"],
                df["rtt_ms"],
                linewidth=2.0,
                markersize=4,
                label=label,
                **style,
            )

        ax.set_title(f"{key} RTT")
        ax.set_xlabel("Ping sample")
        ax.set_ylabel("RTT (ms)")
        ax.set_ylim(bottom=0)
        format_axes(ax)
        handles, labels = ax.get_legend_handles_labels()
        if handles:
            ax.legend(loc="upper right")

    fig.suptitle("5G OAI Testbed RTT", fontsize=16, fontweight="bold")
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    print(f"Saved RTT plot: {out_path}")
    if show:
        plt.show()
    plt.close(fig)


def summarize_throughput(throughput_data: Dict[str, Dict[str, pd.DataFrame]]) -> pd.DataFrame:
    records = []
    for link_type, ue_map in throughput_data.items():
        for ue, df in ue_map.items():
            records.append(
                {
                    "Type": link_type,
                    "UE": ue,
                    "Mean Mbps": df["throughput_mbps"].mean(),
                    "Min Mbps": df["throughput_mbps"].min(),
                    "Max Mbps": df["throughput_mbps"].max(),
                }
            )
    return pd.DataFrame(records)


def summarize_rtt(rtt_data: Dict[str, Dict[str, pd.DataFrame]]) -> pd.DataFrame:
    records = []
    for direction, ue_map in rtt_data.items():
        for ue, df in ue_map.items():
            records.append(
                {
                    "Direction": direction,
                    "UE": ue,
                    "Mean RTT (ms)": df["rtt_ms"].mean(),
                    "Min RTT (ms)": df["rtt_ms"].min(),
                    "Max RTT (ms)": df["rtt_ms"].max(),
                }
            )
    return pd.DataFrame(records)


def resolve_path(base_dir: Path, file_name: str) -> str:
    return str(base_dir / file_name)


def main() -> None:
    args = parse_args()
    apply_plot_style()
    show_plots = not args.no_show
    args.out_dir.mkdir(parents=True, exist_ok=True)

    throughput_data: Dict[str, Dict[str, pd.DataFrame]] = {}
    rtt_data: Dict[str, Dict[str, pd.DataFrame]] = {}

    # Load throughput files
    for link_type, ue_map in THROUGHPUT_FILES.items():
        throughput_data[link_type] = {}
        for ue, path in ue_map.items():
            try:
                full_path = resolve_path(args.data_dir, path)
                throughput_data[link_type][ue] = parse_iperf_csv(full_path)
            except Exception as e:
                print(f"[Throughput] {path}: {e}")
                throughput_data[link_type][ue] = pd.DataFrame(
                    columns=["start_s", "end_s", "throughput_mbps"]
                )

    # Load RTT files
    for direction, ue_map in RTT_FILES.items():
        rtt_data[direction] = {}
        for ue, path in ue_map.items():
            try:
                full_path = resolve_path(args.data_dir, path)
                rtt_data[direction][ue] = parse_ping_txt(full_path)
            except Exception as e:
                print(f"[RTT] {path}: {e}")
                rtt_data[direction][ue] = pd.DataFrame(columns=["sample", "rtt_ms"])

    # Remove any completely empty datasets before plotting
    if all(df.empty for group in throughput_data.values() for df in group.values()):
        print("No valid throughput data available to plot.")
    else:
        plot_throughput(
            throughput_data,
            args.out_dir / "throughput.png",
            show_plots,
        )

    if all(df.empty for group in rtt_data.values() for df in group.values()):
        print("No valid RTT data available to plot.")
    else:
        plot_rtt(
            rtt_data,
            args.out_dir / "rtt.png",
            show_plots,
        )

    # Print simple assessment tables
    thr_summary = summarize_throughput(throughput_data).round(2)
    rtt_summary = summarize_rtt(rtt_data).round(2)

    print("\n=== Throughput Summary (higher is better) ===")
    print(thr_summary.to_string(index=False))

    print("\n=== RTT Summary (lower is better) ===")
    print(rtt_summary.to_string(index=False))


if __name__ == "__main__":
    main()