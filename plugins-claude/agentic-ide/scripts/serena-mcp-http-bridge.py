# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "mcp>=1.26,<2",
# ]
# ///
"""Bridge one MCP stdio connection to one Streamable HTTP connection."""

from __future__ import annotations

import argparse
from urllib.parse import urlsplit

import anyio
from anyio.abc import ObjectReceiveStream, ObjectSendStream
from mcp.client.session import ClientSession
from mcp.client.streamable_http import streamable_http_client
from mcp.server.stdio import stdio_server
from mcp.shared.message import SessionMessage
from mcp.types import ErrorData, JSONRPCError, JSONRPCMessage, JSONRPCRequest


def endpoint(value: str) -> str:
    """Accept only the local endpoint constructed by the shell supervisor."""
    parsed = urlsplit(value)
    try:
        port = parsed.port
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"invalid backend port: {error}") from error

    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path != "/mcp"
        or parsed.query
        or parsed.fragment
        or port is None
        or not 1024 <= port <= 65535
    ):
        raise argparse.ArgumentTypeError(
            "backend URL must be http://127.0.0.1:<port>/mcp"
        )
    return value


async def check_backend(url: str) -> None:
    """Perform a complete MCP handshake before declaring the backend ready."""
    async with streamable_http_client(url, terminate_on_close=False) as (reader, writer, _):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            await session.send_ping()


async def relay_client_messages(
    reader: ObjectReceiveStream[SessionMessage | Exception],
    writer: ObjectSendStream[SessionMessage],
    cancel_scope: anyio.CancelScope,
    initialization_request_id: list[object | None],
    initialization_response: anyio.Event,
    stdio_writer: ObjectSendStream[SessionMessage],
) -> None:
    """Serialize the MCP handshake until the HTTP transport receives a session ID."""
    try:
        async with reader:
            async for message in reader:
                if isinstance(message, Exception):
                    raise message
                root = message.message.root
                if isinstance(root, JSONRPCRequest) and root.method == "server/discover":
                    # Copilot uses this modern-protocol probe before falling back
                    # to Serena's initialization-based protocol.
                    await stdio_writer.send(
                        SessionMessage(
                            JSONRPCMessage(
                                JSONRPCError(
                                    jsonrpc="2.0",
                                    id=root.id,
                                    error=ErrorData(
                                        code=-32601,
                                        message="Method not found",
                                    ),
                                )
                            )
                        )
                    )
                    continue
                if isinstance(root, JSONRPCRequest) and root.method == "initialize":
                    initialization_request_id[0] = root.id
                elif (
                    getattr(root, "method", None) == "notifications/initialized"
                    and initialization_request_id[0] is not None
                ):
                    await initialization_response.wait()
                await writer.send(message)
    finally:
        await writer.aclose()
        cancel_scope.cancel()


async def relay_server_messages(
    reader: ObjectReceiveStream[SessionMessage | Exception],
    writer: ObjectSendStream[SessionMessage],
    cancel_scope: anyio.CancelScope,
    initialization_request_id: list[object | None],
    initialization_response: anyio.Event,
) -> None:
    """Return backend messages and release the initialized notification after init."""
    try:
        async with reader:
            async for message in reader:
                if isinstance(message, Exception):
                    raise message
                await writer.send(message)
                if (
                    initialization_request_id[0] is not None
                    and getattr(message.message.root, "id", None)
                    == initialization_request_id[0]
                ):
                    initialization_response.set()
    finally:
        await writer.aclose()
        cancel_scope.cancel()


async def bridge(url: str) -> None:
    async with stdio_server() as (stdio_reader, stdio_writer):
        # Serena owns project and LSP lifetime at the backend level. Sending
        # DELETE when one Copilot client exits would shut that shared state down.
        async with streamable_http_client(
            url, terminate_on_close=False
        ) as (http_reader, http_writer, _):
            initialization_request_id: list[object | None] = [None]
            initialization_response = anyio.Event()
            async with anyio.create_task_group() as task_group:
                task_group.start_soon(
                    relay_client_messages,
                    stdio_reader,
                    http_writer,
                    task_group.cancel_scope,
                    initialization_request_id,
                    initialization_response,
                    stdio_writer,
                )
                task_group.start_soon(
                    relay_server_messages,
                    http_reader,
                    stdio_writer,
                    task_group.cancel_scope,
                    initialization_request_id,
                    initialization_response,
                )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, type=endpoint)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the backend with an MCP initialize and ping exchange",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    anyio.run(check_backend if args.check else bridge, args.url)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
