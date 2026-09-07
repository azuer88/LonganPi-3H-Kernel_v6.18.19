#!/usr/bin/env python3
"""Monitor CPU temperature via libsensors and track the running max.

Uses `sensors -j` (lm-sensors CLI, JSON output) so it needs no extra Python
bindings beyond the `sensors` package already installed on the board.
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime


def read_sensors():
    out = subprocess.run(["sensors", "-j"], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def iter_temp_inputs(data):
    """Yield (chip, sub_label, value) for every *_input temperature reading."""
    for chip, features in data.items():
        if not isinstance(features, dict):
            continue
        for label, sub in features.items():
            if not isinstance(sub, dict):
                continue
            for key, value in sub.items():
                if key.endswith("_input"):
                    yield chip, label, value


def pick_sensor(data, preferred_substr=None):
    candidates = list(iter_temp_inputs(data))
    if not candidates:
        return None
    if preferred_substr:
        for chip, label, value in candidates:
            if preferred_substr.lower() in f"{chip}:{label}".lower():
                return chip, label
    return candidates[0][0], candidates[0][1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-i", "--interval", type=float, default=1.0,
                         help="Polling interval in seconds (default: 1.0)")
    parser.add_argument("-s", "--sensor", default="cpu_thermal",
                         help="Substring to match against 'chip:label' to pick a "
                              "specific sensor (default: 'cpu_thermal')")
    parser.add_argument("-l", "--list", action="store_true",
                         help="List all detected temperature sensors and exit.")
    parser.add_argument("--log-file", default=None,
                         help="Append every sample as 'timestamp,temp_c' CSV rows "
                              "to this file (created with a header if missing).")
    args = parser.parse_args()

    data = read_sensors()

    if args.list:
        for chip, label, value in iter_temp_inputs(data):
            print(f"{chip}:{label} -> {value:.1f} C")
        return

    picked = pick_sensor(data, args.sensor)
    if picked is None:
        print("No temperature sensors found via `sensors -j`.", file=sys.stderr)
        sys.exit(1)
    chip, label = picked
    print(f"Monitoring {chip}:{label} every {args.interval}s (Ctrl+C to stop)")

    log_fh = None
    if args.log_file:
        is_new = not os.path.exists(args.log_file) or os.path.getsize(args.log_file) == 0
        log_fh = open(args.log_file, "a", buffering=1)
        if is_new:
            log_fh.write("timestamp,temp_c\n")

    max_temp = float("-inf")
    max_time = None

    def report_and_exit(*_):
        if max_time is not None:
            print(f"\nMax temp: {max_temp:.1f} C at "
                  f"{max_time.strftime('%Y-%m-%d %H:%M:%S')}")
        else:
            print("\nNo samples recorded.")
        if log_fh is not None:
            log_fh.close()
        sys.exit(0)

    signal.signal(signal.SIGINT, report_and_exit)

    while True:
        data = read_sensors()
        temp = data[chip][label][f"{label}_input"]
        now = datetime.now()
        if temp > max_temp:
            max_temp = temp
            max_time = now
        if log_fh is not None:
            log_fh.write(f"{now.strftime('%Y-%m-%d %H:%M:%S')},{temp:.1f}\n")
        print(f"{now.strftime('%H:%M:%S')}  {temp:5.1f} C  "
              f"(max: {max_temp:5.1f} C)", end="\r", flush=True)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
