import os, time, logging
from flask import Flask, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
START_TIME = time.time()

ENV_ID   = os.environ.get("ENV_ID", "unknown")
ENV_NAME = os.environ.get("ENV_NAME", "unnamed")

@app.route("/health")
def health():
    return jsonify({
        "status": "ok",
        "env_id": ENV_ID,
        "env_name": ENV_NAME,
        "uptime_seconds": round(time.time() - START_TIME, 1)
    }), 200

@app.route("/")
def index():
    return jsonify({
        "message": f"Hello from sandbox env '{ENV_NAME}'",
        "env_id": ENV_ID
    }), 200

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
