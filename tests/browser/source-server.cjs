'use strict';

const http = require('node:http');

const source = `const std = @import("std");

pub fn main() void {
    std.debug.print("highlighted attachment\\n", .{});
}
`;

let sourceRequests = 0;
let sourceAccept = '';

const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  if (url.pathname === '/requests') {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ count: sourceRequests, accept: sourceAccept }));
    return;
  }
  if (url.pathname !== '/sample.zig') {
    response.writeHead(404, { 'Content-Type': 'text/plain' });
    response.end('not found');
    return;
  }

  sourceRequests += 1;
  sourceAccept = request.headers.accept || '';

  response.writeHead(200, {
    'Cache-Control': 'no-store',
    'Content-Disposition': 'attachment; filename="sample.zig"',
    'Content-Type': 'application/octet-stream',
  });
  response.end(source);
});

server.listen(0, '127.0.0.1', () => {
  process.stdout.write(`${server.address().port}\n`);
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
