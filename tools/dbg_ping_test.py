import socket

try:
    s = socket.create_connection(("127.0.0.1", 4370), timeout=5)
    print("connected")
    s.sendall(b'{"id":1,"cmd":"ping"}\n')
    s.settimeout(8)
    try:
        data = s.recv(4096)
        print("recv:", data[:300])
    except socket.timeout:
        print("recv timeout (no data in 8s)")
    s.close()
except Exception as e:
    print("ERR:", type(e).__name__, e)
