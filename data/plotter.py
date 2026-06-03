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
# Bandwidths to compare
# -----------------------------
BANDWIDTHS = ["20", "100"]

# 4 distinct series: one colour per (UE, bandwidth) combination
SERIES_STYLES = {
    ("UE1", "100"): {"color": "#2563eb", "marker": "o", "linestyle": "-"},   # blue solid
    ("UE2", "100"): {"color": "#f97316", "marker": "s", "linestyle": "-"},    # orange solid
    ("UE1", "20"):  {"color": "#16a34a", "marker": "D", "linestyle": "--"},   # green dashed
    ("UE2", "20"):  {"color": "#dc2626", "marker": "^", "linestyle": "--"},   # red dashed
}


# -----------------------------
# File builders
# -----------------------------
def build_throughput_files() -> Dict[str, Dict[str, Dict[str, str]]]:
    """Returns {bandwidth: {link_type: {UE: filename}}}."""
    files = {}
    for bw in BANDWIDTHS:
        files[bw] = {
            "UDP DL": {
                "UE1": f"task4_udp_dl_ue1_{bw}.csv",
                "UE2": f"task4_udp_dl_ue2_{bw}.csv",
            },
            "UDP UL": {
                "UE1": f"task4_udp_ul_ue1_{bw}.csv",
                "UE2": f"task4_udp_ul_ue2_{bw}.csv",
            },
            "TCP DL": {
                "UE1": f"task4_tcp_dl_ue1_{bw}.csv",
                "UE2": f"task4_tcp_dl_ue2_{bw}.csv",
            },
            "TCP UL": {
                "UE1": f"task4_tcp_ul_ue1_{bw}.csv",
                "UE2": f"task4_tcp_ul_ue2_{bw}.csv",
            },
        }
    return files


def build_rtt_files() -> Dict[str, Dict[str, Dict[str, str]]]:
    """Returns {bandwidth: {direction: {UE: filename}}}."""
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
# Plot styling
# -----------------------------
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
    throughput_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]],
    out_path: Path,
    show: bool,
) -> None:
    """2x2 plot: each subplot overlays UE1/UE2 for both bandwidths."""
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True, sharex=True)
    axes = axes.flatten()

    plot_order = ["UDP DL", "UDP UL", "TCP DL", "TCP UL"]

    for ax, key in zip(axes, plot_order, strict=True):
        for bw in BANDWIDTHS:
            for ue in ["UE1", "UE2"]:
                df = throughput_data.get(bw, {}).get(key, {}).get(ue, pd.DataFrame())
                if df.empty:
                    continue
                style = SERIES_STYLES.get((ue, bw), {})
                label = f"{ue} – {bw} MHz (mean {df['throughput_mbps'].mean():.1f} Mbps)"
                ax.plot(
                    df["end_s"],
                    df["throughput_mbps"],
                    linewidth=2.0,
                    markersize=4,
                    label=label,
                    **style,
                )

        ax.set_title(key)
        ax.set_xlabel("Time (s)")
        ax.set_ylabel("Throughput (Mbps)")
        format_axes(ax)
        handles, labels = ax.get_legend_handles_labels()
        if handles:
            ax.legend(loc="upper right", fontsize=8)

    fig.suptitle("5G OAI Testbed Throughput (20 MHz vs 100 MHz)", fontsize=16, fontweight="bold")
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    print(f"Saved throughput plot: {out_path}")
    if show:
        plt.show()
    plt.close(fig)


def plot_rtt(
    rtt_data: Dict[str, Dict[str, Dict[str, pd.DataFrame]]],
    out_path: Path,
    show: bool,
) -> None:
    """1x2 plot: each subplot overlays UE1/UE2 for both bandwidths."""
    fig, axes = plt.subplots(1, 2, figsize=(14, 5), constrained_layout=True, sharey=True)

    for ax, key in zip(axes, ["DL", "UL"], strict=True):
        for bw in BANDWIDTHS:
            for ue in ["UE1", "UE2"]:
                df = rtt_data.get(bw, {}).get(key, {}).get(ue, pd.DataFrame())
                if df.empty:
                    continue
                style = SERIES_STYLES.get((ue, bw), {})
                label = f"{ue} – {bw} MHz (mean {df['rtt_ms'].mean():.2f} ms)"
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
            ax.legend(loc="upper right", fontsize=8)

    fig.suptitle("5G OAI Testbed RTT (20 MHz vs 100 MHz)", fontsize=16, fontweight="bold")
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    print(f"Saved RTT plot: {out_path}")
    if show:
        plt.show()
    plt.close(fig)


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


def resolve_path(base_dir: Path, file_name: str) -> str:
    return str(base_dir / file_name)


def main() -> None:
    args = parse_args()
    apply_plot_style()
    show_plots = not args.no_show
    args.out_dir.mkdir(parents=True, exist_ok=True)

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
                    full_path = resolve_path(args.data_dir, path)
                    throughput_data[bw][link_type][ue] = parse_iperf_csv(full_path)
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
                    full_path = resolve_path(args.data_dir, path)
                    rtt_data[bw][direction][ue] = parse_ping_txt(full_path)
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
        plot_throughput(
            throughput_data,
            args.out_dir / "throughput.png",
            show_plots,
        )
    else:
        print("No valid throughput data available to plot.")

    if any_rtt:
        plot_rtt(
            rtt_data,
            args.out_dir / "rtt.png",
            show_plots,
        )
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