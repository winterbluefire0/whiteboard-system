"""Read status or one JPEG from the XIAO USB serial camera firmware."""
import argparse
import datetime
from pathlib import Path
import time

import serial
from serial.tools import list_ports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "photo"))
    parser.add_argument("--port", help="Serial device; auto-selected if exactly one Espressif board is connected")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    ports = [p.device for p in list_ports.comports() if p.vid == 0x303A]
    if not args.port and len(ports) != 1:
        parser.error("Specify --port; expected exactly one Espressif USB board")
    connection = serial.Serial()
    connection.port = args.port or ports[0]
    connection.baudrate = 115200
    connection.timeout = 0.5
    connection.write_timeout = 5
    connection.dtr = False
    connection.rts = False
    connection.open()
    try:
        connection.reset_input_buffer()
        connection.write((args.action.upper() + "\n").encode())
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            line = connection.readline()
            if not line:
                continue
            if args.action == "photo" and line.startswith(b"PHOTO_BEGIN "):
                size = int(line.split()[1])
                if not 4 <= size <= 4 * 1024 * 1024:
                    raise RuntimeError("Invalid JPEG size")
                data = bytearray()
                while len(data) < size and time.monotonic() < deadline:
                    data.extend(connection.read(min(4096, size - len(data))))
                if len(data) != size or data[:2] != b"\xff\xd8" or data[-2:] != b"\xff\xd9":
                    raise RuntimeError("Incomplete or invalid JPEG; capture not saved")
                trailer = connection.read_until(b"PHOTO_END\n")
                if not trailer.endswith(b"PHOTO_END\n"):
                    raise RuntimeError("Missing end marker; capture not saved")
                stamp = datetime.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S-%f")
                output = args.output or Path(__file__).parent / "captures" / f"camera-{stamp}.jpg"
                output.parent.mkdir(parents=True, exist_ok=True)
                with output.open("xb") as handle:
                    handle.write(data)
                print(f"Saved {len(data)} bytes: {output.resolve()}")
                return
            print(line.decode("utf-8", errors="replace").rstrip(), flush=True)
            if args.action == "status" and line.startswith(b"{"):
                return
            if b"PHOTO_ERROR" in line:
                raise RuntimeError(line.decode("utf-8", errors="replace").strip())
        raise RuntimeError("Timed out waiting for firmware response")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
