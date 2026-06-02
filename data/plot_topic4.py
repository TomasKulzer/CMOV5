#!/usr/bin/env python3
"""Plot Topic 4 throughput CSV exports.

The CSV files in this folder are iperf-style exports without headers. This
script reads the per-interval throughput, groups the files by TCP/UDP and
DL/UL, and generates a 2x2 comparison figure.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt


@dataclass(frozen=True)
class SeriesMeta:
	protocol: str
	direction: str
	ue: str
	bandwidth: str

	@property
	def label(self) -> str:
		return f"UE {self.ue} | {self.bandwidth} MHz"


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(
		description="Plot throughput CSV files for Topic 4 experiments."
	)
	parser.add_argument(
		"--data-dir",
		type=Path,
		default=Path(__file__).resolve().parent,
		help="Directory containing the CSV files.",
	)
	parser.add_argument(
		"--output",
		type=Path,
		default=Path(__file__).with_name("topic4_throughput.png"),
		help="Output image path.",
	)
	parser.add_argument(
		"--show",
		action="store_true",
		help="Display the figure after saving it.",
	)
	return parser.parse_args()


def file_metadata(path: Path) -> SeriesMeta | None:
	parts = path.stem.split("_")
	if len(parts) != 5:
		return None

	metric, protocol, direction, ue_part, bandwidth = parts
	if metric != "throughput":
		return None
	if protocol not in {"tcp", "udp"}:
		return None
	if direction not in {"dl", "ul"}:
		return None
	if not ue_part.startswith("ue"):
		return None

	return SeriesMeta(
		protocol=protocol,
		direction=direction,
		ue=ue_part.removeprefix("ue"),
		bandwidth=bandwidth,
	)


def parse_throughput_csv(path: Path) -> tuple[list[float], list[float]]:
	samples: list[tuple[float, float, float]] = []
	durations: list[float] = []

	with path.open(newline="", encoding="utf-8") as handle:
		reader = csv.reader(handle)
		for row in reader:
			if len(row) < 8:
				continue

			interval = row[6].strip()
			bytes_text = row[7].strip()

			try:
				start_text, end_text = interval.split("-", 1)
				start = float(start_text)
				end = float(end_text)
				duration = end - start
				bytes_tx = float(bytes_text)
			except ValueError:
				continue

			if duration <= 0:
				continue

			samples.append((start, end, bytes_tx))
			durations.append(duration)

	if not samples:
		return [], []

	sorted_durations = sorted(durations)
	mid = len(sorted_durations) // 2
	if len(sorted_durations) % 2 == 0:
		median = (sorted_durations[mid - 1] + sorted_durations[mid]) / 2.0
	else:
		median = sorted_durations[mid]

	if median <= 0:
		median = 1.0

	max_duration = median * 1.5
	if max_duration < median:
		max_duration = median

	times: list[float] = []
	throughput_mbps: list[float] = []

	for start, end, bytes_tx in samples:
		duration = end - start
		if duration > max_duration:
			continue
		midpoint = start + duration / 2.0
		throughput = (bytes_tx * 8.0) / duration / 1_000_000.0
		times.append(midpoint)
		throughput_mbps.append(throughput)

	return times, throughput_mbps


def discover_series(data_dir: Path) -> dict[tuple[str, str], list[tuple[SeriesMeta, Path]]]:
	series: dict[tuple[str, str], list[tuple[SeriesMeta, Path]]] = {
		("tcp", "dl"): [],
		("tcp", "ul"): [],
		("udp", "dl"): [],
		("udp", "ul"): [],
	}

	for path in sorted(data_dir.glob("throughput_*.csv")):
		meta = file_metadata(path)
		if meta is None:
			continue
		series[(meta.protocol, meta.direction)].append((meta, path))

	for key in series:
		series[key].sort(key=lambda item: (item[0].bandwidth, item[0].ue, item[1].name))

	return series


def plot_panel(ax: plt.Axes, title: str, entries: list[tuple[SeriesMeta, Path]]) -> None:
	for meta, path in entries:
		times, values = parse_throughput_csv(path)
		if not times:
			continue
		ax.plot(times, values, linewidth=1.8, label=meta.label)

	ax.set_title(title)
	ax.set_xlabel("Time (s)")
	ax.set_ylabel("Throughput (Mbps)")
	ax.grid(True, alpha=0.3)
	if entries:
		ax.legend(fontsize=9)


def main() -> int:
	args = parse_args()
	series = discover_series(args.data_dir)

	if not any(series.values()):
		raise SystemExit(f"No throughput CSV files found in {args.data_dir}")

	fig, axes = plt.subplots(2, 2, figsize=(15, 10), sharex=True, sharey=True)
	panels = [
		("TCP downlink", series[("tcp", "dl")]),
		("TCP uplink", series[("tcp", "ul")]),
		("UDP downlink", series[("udp", "dl")]),
		("UDP uplink", series[("udp", "ul")]),
	]

	for ax, (title, entries) in zip(axes.flat, panels, strict=True):
		plot_panel(ax, title, entries)

	fig.suptitle("Topic 4 Throughput Comparison", fontsize=16, fontweight="bold")
	fig.tight_layout(rect=(0, 0, 1, 0.96))
	args.output.parent.mkdir(parents=True, exist_ok=True)
	fig.savefig(args.output, dpi=200, bbox_inches="tight")
	print(f"Saved plot to {args.output}")

	if args.show:
		plt.show()

	return 0


if __name__ == "__main__":
	raise SystemExit(main())
