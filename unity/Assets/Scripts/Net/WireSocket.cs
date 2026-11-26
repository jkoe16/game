using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using UnityEngine;

namespace PartyWorld.Net
{
    /// <summary>
    /// 바이너리 웹소켓. 웹(WebGL)에서는 브라우저 WebSocket(PartyWebSocket.jslib), 에디터·PC 에서는 .NET ClientWebSocket.
    /// 메인 스레드에서 매 프레임 TryReceive 로 꺼내 쓴다.
    /// </summary>
    public abstract class WireSocket
    {
        public const int Connecting = 0, Open = 1, Closing = 2, Closed = 3;

        public abstract int State { get; }
        public abstract bool TryReceive(out byte[] msg);
        public abstract void Send(byte[] data);
        public abstract void Close();

        public static WireSocket Connect(string url)
        {
#if UNITY_WEBGL && !UNITY_EDITOR
            return new BrowserSocket(url);
#else
            return new DotNetSocket(url);
#endif
        }
    }

#if UNITY_WEBGL && !UNITY_EDITOR
    class BrowserSocket : WireSocket
    {
        [DllImport("__Internal")] static extern int PwWsOpen(string url);
        [DllImport("__Internal")] static extern int PwWsState(int id);
        [DllImport("__Internal")] static extern int PwWsNextLength(int id);
        [DllImport("__Internal")] static extern int PwWsReceive(int id, byte[] buf, int len);
        [DllImport("__Internal")] static extern int PwWsSend(int id, byte[] buf, int len);
        [DllImport("__Internal")] static extern void PwWsClose(int id);

        int _id;

        public BrowserSocket(string url) { _id = PwWsOpen(url); }

        public override int State => _id > 0 ? PwWsState(_id) : Closed;

        public override bool TryReceive(out byte[] msg)
        {
            msg = null;
            if (_id <= 0) return false;
            int n = PwWsNextLength(_id);
            if (n < 0) return false;
            msg = new byte[n];
            if (n > 0) PwWsReceive(_id, msg, n);
            else PwWsReceive(_id, new byte[1], 0);
            return true;
        }

        public override void Send(byte[] data)
        {
            if (_id > 0 && data.Length > 0) PwWsSend(_id, data, data.Length);
        }

        public override void Close()
        {
            if (_id > 0) PwWsClose(_id);
            _id = 0;
        }
    }
#else
    class DotNetSocket : WireSocket
    {
        readonly System.Net.WebSockets.ClientWebSocket _ws = new System.Net.WebSockets.ClientWebSocket();
        readonly ConcurrentQueue<byte[]> _in = new ConcurrentQueue<byte[]>();
        readonly System.Collections.Concurrent.BlockingCollection<byte[]> _out = new System.Collections.Concurrent.BlockingCollection<byte[]>();
        readonly System.Threading.CancellationTokenSource _cts = new System.Threading.CancellationTokenSource();
        volatile bool _failed;

        public DotNetSocket(string url)
        {
            Run(url);
        }

        async void Run(string url)
        {
            try
            {
                await _ws.ConnectAsync(new Uri(url), _cts.Token);
                SendLoop();
                var buf = new byte[1 << 16];
                var ms = new System.IO.MemoryStream();
                while (_ws.State == System.Net.WebSockets.WebSocketState.Open)
                {
                    var r = await _ws.ReceiveAsync(new ArraySegment<byte>(buf), _cts.Token);
                    if (r.MessageType == System.Net.WebSockets.WebSocketMessageType.Close) break;
                    ms.Write(buf, 0, r.Count);
                    if (r.EndOfMessage)
                    {
                        _in.Enqueue(ms.ToArray());
                        ms.SetLength(0);
                    }
                }
            }
            catch (Exception) { }
            _failed = true;
        }

        async void SendLoop()
        {
            try
            {
                while (!_cts.IsCancellationRequested)
                {
                    byte[] d;
                    while (!_out.TryTake(out d)) await System.Threading.Tasks.Task.Delay(2, _cts.Token);
                    await _ws.SendAsync(new ArraySegment<byte>(d), System.Net.WebSockets.WebSocketMessageType.Binary, true, _cts.Token);
                }
            }
            catch (Exception) { _failed = true; }
        }

        public override int State
        {
            get
            {
                if (_failed) return Closed;
                switch (_ws.State)
                {
                    case System.Net.WebSockets.WebSocketState.None:
                    case System.Net.WebSockets.WebSocketState.Connecting: return Connecting;
                    case System.Net.WebSockets.WebSocketState.Open: return Open;
                    case System.Net.WebSockets.WebSocketState.CloseSent:
                    case System.Net.WebSockets.WebSocketState.CloseReceived: return Closing;
                    default: return Closed;
                }
            }
        }

        public override bool TryReceive(out byte[] msg) => _in.TryDequeue(out msg);

        public override void Send(byte[] data)
        {
            if (!_failed) _out.Add(data);
        }

        public override void Close()
        {
            try
            {
                if (_ws.State == System.Net.WebSockets.WebSocketState.Open)
                    _ws.CloseOutputAsync(System.Net.WebSockets.WebSocketCloseStatus.NormalClosure, "", System.Threading.CancellationToken.None);
            }
            catch (Exception) { }
            _cts.Cancel();
            _failed = true;
        }
    }
#endif
}
