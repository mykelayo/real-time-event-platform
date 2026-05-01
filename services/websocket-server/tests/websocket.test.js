const WebSocket = require("ws");
const { broadcast } = require("../src/websocket");

function makeMockWss(clients) {
  return { clients: new Set(clients) };
}

function makeMockClient(readyState) {
  return { readyState, send: jest.fn() };
}

test("broadcast sends only to OPEN clients", () => {
  const open    = makeMockClient(WebSocket.OPEN);    
  const closed  = makeMockClient(WebSocket.CLOSED);  
  const wss     = makeMockWss([open, closed]);

  broadcast(wss, { type: "event_counts", data: { click: 5 } });

  expect(open.send).toHaveBeenCalledTimes(1);
  expect(closed.send).not.toHaveBeenCalled();
});

test("broadcast serialises payload to a JSON string", () => {
  const client  = makeMockClient(WebSocket.OPEN);
  const wss     = makeMockWss([client]);
  const payload = { type: "event_counts", data: { purchase: 12 } };

  broadcast(wss, payload);

  const raw = client.send.mock.calls[0][0];
  expect(typeof raw).toBe("string");
  expect(JSON.parse(raw)).toEqual(payload);
});

test("broadcast sends nothing when no clients are connected", () => {
  const wss = makeMockWss([]);
  expect(() => broadcast(wss, { type: "event_counts", data: {} })).not.toThrow();
});

test("broadcast sends to multiple OPEN clients", () => {
  const a   = makeMockClient(WebSocket.OPEN);
  const b   = makeMockClient(WebSocket.OPEN);
  const wss = makeMockWss([a, b]);

  broadcast(wss, { type: "event_counts", data: { logout: 3 } });

  expect(a.send).toHaveBeenCalledTimes(1);
  expect(b.send).toHaveBeenCalledTimes(1);

  expect(a.send.mock.calls[0][0]).toBe(b.send.mock.calls[0][0]);
});

test("broadcast skips CONNECTING clients", () => {
  const connecting = makeMockClient(WebSocket.CONNECTING); 
  const wss        = makeMockWss([connecting]);

  broadcast(wss, { type: "event_counts", data: {} });

  expect(connecting.send).not.toHaveBeenCalled();
});