import type { MenuProps } from "antd";

export type HeaderLinkKey = "changelog" | "docs" | "faq" | "github";

export interface ProductProfile {
  appName: string;
  defaultRoute: string;
  redirectHiddenRoutes: boolean;
  hiddenRoutes: readonly string[];
  logos: {
    light: string;
    dark: string;
    avatar: string;
  };
  chat: {
    assistantName: string;
  };
  headerLinks: Record<HeaderLinkKey, boolean>;
  updateCheck: {
    enabled: boolean;
  };
  modelProviders: {
    allowedProviderIds: readonly string[];
    allowedProviderIdPrefixes: readonly string[];
    allowCustomProviders: boolean;
  };
  theme: {
    colorPrimary: string;
  };
}

export const productProfile: ProductProfile = {
  appName: "萝卜头",
  defaultRoute: "/chat",
  redirectHiddenRoutes: true,
  hiddenRoutes: ["/debug", "/plugin-manager", "/voice-transcription"],
  logos: {
    light: "/logo-light.svg",
    dark: "/logo-dark.svg",
    avatar: "/logo-mark.svg",
  },
  chat: {
    assistantName: "萝卜头",
  },
  headerLinks: {
    changelog: false,
    docs: false,
    faq: false,
    github: false,
  },
  updateCheck: {
    enabled: false,
  },
  modelProviders: {
    allowedProviderIds: [
      "deepseek",
      "zhipu-intl",
      "zhipu-intl-codingplan",
      "kimi-cn",
      "kimi-intl",
      "minimax-cn",
      "minimax",
    ],
    allowedProviderIdPrefixes: [],
    allowCustomProviders: true,
  },
  theme: {
    colorPrimary: "#FF7F16",
  },
};

export function normalizeRoutePath(path: string): string {
  const pathname = path.split(/[?#]/)[0] || "/";
  const withSlash = pathname.startsWith("/") ? pathname : `/${pathname}`;
  return withSlash.length > 1 ? withSlash.replace(/\/+$/, "") : withSlash;
}

export function isRouteHidden(path?: string | null): boolean {
  if (!path) return false;
  const normalizedPath = normalizeRoutePath(path);
  return productProfile.hiddenRoutes
    .map(normalizeRoutePath)
    .includes(normalizedPath);
}

export function isRouteKeyHidden(
  key: string,
  keyToPath: Record<string, string>,
): boolean {
  const path = keyToPath[key];
  return path ? isRouteHidden(path) : false;
}

export function filterVisibleRoutes<T extends { path: string }>(
  routes: readonly T[],
): T[] {
  return routes.filter((route) => !isRouteHidden(route.path));
}

export function isModelProviderVisible(provider: {
  id: string;
  is_custom?: boolean;
}): boolean {
  if (productProfile.modelProviders.allowCustomProviders && provider.is_custom) {
    return true;
  }
  if (productProfile.modelProviders.allowedProviderIds.includes(provider.id)) {
    return true;
  }
  return productProfile.modelProviders.allowedProviderIdPrefixes.some((prefix) =>
    provider.id.startsWith(prefix),
  );
}

export function filterMenuItems(
  items: MenuProps["items"],
  keyToPath: Record<string, string>,
): MenuProps["items"] {
  if (!items) return items;

  return items
    .map((item) => {
      if (!item || typeof item !== "object") return item;

      const key =
        "key" in item && item.key !== undefined && item.key !== null
          ? String(item.key)
          : "";
      if (key && isRouteKeyHidden(key, keyToPath)) {
        return null;
      }

      const itemWithChildren = item as typeof item & {
        children?: MenuProps["items"];
      };
      if (Array.isArray(itemWithChildren.children)) {
        const children = filterMenuItems(itemWithChildren.children, keyToPath);
        if (!children || children.length === 0) {
          return null;
        }
        return { ...item, children };
      }

      return item;
    })
    .filter(Boolean) as MenuProps["items"];
}
