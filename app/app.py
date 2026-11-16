"""SIS 3 orders API: a tiny HTTP service that runs on ECS Fargate behind an ALB.

GET  /          -> service info (version = image tag)
GET  /health    -> 200, used by the ALB health check (does not touch AWS)
POST /payments  -> publishes a PaymentReceived domain event to SNS, returns 202
"""
import json
import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

PORT = int(os.environ.get("PORT", "8080"))
VERSION = os.environ.get("APP_VERSION", "dev")
TOPIC_ARN = os.environ.get("TOPIC_ARN", "")
STARTED = time.time()

# credentials come from the ECS task role automatically - no keys in the image
sns = boto3.client("sns") if TOPIC_ARN else None


def log(**fields):
    print(json.dumps(fields), flush=True)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        elif self.path == "/":
            self._send(200, {
                "service": "sis3-orders-api",
                "version": VERSION,
                "host": os.uname().nodename,
                "uptime_s": round(time.time() - STARTED),
            })
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/payments":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payment = json.loads(self.rfile.read(length) or b"{}")
            for field in ("paymentId", "account", "amount"):
                if field not in payment:
                    self._send(400, {"error": f"missing field: {field}"})
                    return
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"error": "body must be JSON"})
            return

        if sns is None:
            self._send(503, {"error": "TOPIC_ARN is not configured"})
            return

        resp = sns.publish(TopicArn=TOPIC_ARN, Message=json.dumps(payment))
        log(event="PaymentReceived published", paymentId=payment["paymentId"],
            snsMessageId=resp["MessageId"])
        self._send(202, {"published": True, "paymentId": payment["paymentId"],
                         "snsMessageId": resp["MessageId"]})

    def log_message(self, fmt, *args):
        # one JSON line per request to stdout -> CloudWatch Logs
        log(method=self.command, path=self.path,
            status=args[1] if len(args) > 1 else None)


def shutdown(signum, frame):
    log(event="SIGTERM received, shutting down")
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, shutdown)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    log(event="started", port=PORT, version=VERSION)
    server.serve_forever()
