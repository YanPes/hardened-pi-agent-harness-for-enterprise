import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { VERSION } from "@earendil-works/pi-coding-agent";

function getHeader(theme: Theme): string[] {
  const muted = (text: string) => theme.fg("muted", text);
  const dim = (text: string) => theme.fg("dim", text);

  return [
    `  ____         ___  _ `,
    ` / __/ __ ____/ _ \\(_)`,
    ` _\\ \\/ -_) __/ ___/ / `,
    `/___/\\__/\\__/_/  /_/`,
    "",
    `${muted(" Zero Trust AI Agent Harness")}${dim(` pi version: v${VERSION}`)}`,
  ];
}

export default function registerAsciiHeader(pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    if (!ctx.hasUI) {
      return;
    }

    ctx.ui.setHeader((_tui, theme) => {
      return {
        render(_width: number): string[] {
          return getHeader(theme);
        },
        invalidate() { },
      };
    });
  });

  pi.registerCommand("builtin-header", {
    description: "Restore built-in header",
    handler: async (_args, ctx) => {
      ctx.ui.setHeader(undefined);
      ctx.ui.notify("Built-in header restored", "info");
    },
  });
}
