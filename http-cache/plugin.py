import os
from mitmproxy import http
from mitmproxy import ctx
from pathlib import Path

class CachePlugin:
    def __init__(self):
        pass
    def running(self):
        ctx.log.info("Cache plugin is running.")
        cache_env = os.getenv("FLOW_CACHE_PATH")
        if cache_env is None:
            ctx.log.warn("FLOW_CACHE_PATH environment variable is not set. No cache will be loaded.")
            return
        cache = Path(cache_env)
        if cache.exists():
            ctx.master.commands.call("replay.server.file", cache)

    def response(self, flow: http.HTTPFlow):
        if flow.is_replay is not None:
            return
        ctx.master.commands.call("replay.server.add", [flow])

addons = [CachePlugin()]