import type { ProxyOptions } from "vite";

/**
 * Custom vite config overrides for the QwenPaw fork.
 * Keep this file small — it is the only part of the build config
 * that differs from upstream, so it is easy to maintain across rebases.
 */

export function getCustomProxy(
  env: Record<string, string>,
): Record<string, string | ProxyOptions> | undefined {
  const apiBaseUrl = env.VITE_API_BASE_URL ?? "";
  const devApiProxyTarget =
    env.VITE_DEV_API_PROXY_TARGET ?? "http://127.0.0.1:8088";

  return apiBaseUrl === ""
    ? {
        "/api": {
          target: devApiProxyTarget,
          changeOrigin: true,
        },
      }
    : undefined;
}
