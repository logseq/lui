#!/usr/bin/env python3
"""Minimal RFC 6455 echo server (stdlib only) for lui_plugin_websocket
tests. Handshakes, then: text/binary frames are echoed back with the
same opcode, pings get pongs, close gets an echo close and hangup."""
import base64
import hashlib
import socket
import struct
import sys
import threading

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def recv_exact(c, n):
    b = b""
    while len(b) < n:
        d = c.recv(n - len(b))
        if not d:
            raise EOFError
        b += d
    return b


def send_frame(c, opcode, data):
    hdr = bytes([0x80 | opcode])
    n = len(data)
    if n < 126:
        hdr += bytes([n])
    elif n < 65536:
        hdr += bytes([126]) + struct.pack(">H", n)
    else:
        hdr += bytes([127]) + struct.pack(">Q", n)
    c.sendall(hdr + data)


def handle(c):
    try:
        req = b""
        while b"\r\n\r\n" not in req:
            d = c.recv(4096)
            if not d:
                c.close()
                return
            req += d
        head = req.split(b"\r\n\r\n")[0].decode("latin-1")
        key = ""
        for line in head.split("\r\n")[1:]:
            k, _, v = line.partition(":")
            if k.strip().lower() == "sec-websocket-key":
                key = v.strip()
        accept = base64.b64encode(
            hashlib.sha1(key.encode() + GUID).digest()
        ).decode()
        c.sendall(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                "Sec-WebSocket-Accept: %s\r\n\r\n" % accept
            ).encode()
        )
        while True:
            h = recv_exact(c, 2)
            b0, b1 = h[0], h[1]
            op = b0 & 0x0F
            masked = b1 & 0x80
            ln = b1 & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", recv_exact(c, 2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", recv_exact(c, 8))[0]
            mask = recv_exact(c, 4) if masked else b""
            data = recv_exact(c, ln) if ln else b""
            if masked:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if op == 0x8:
                send_frame(c, 0x8, data)
                break
            if op == 0x9:
                send_frame(c, 0xA, data)
                continue
            send_frame(c, op, data)
    except (EOFError, OSError):
        pass
    finally:
        c.close()


if __name__ == "__main__":
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", int(sys.argv[1])))
    srv.listen(8)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()
