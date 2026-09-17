import { existsSync } from "node:fs"
import { join } from "node:path"
import { spawn, spawnSync } from "node:child_process"

function runHook(projectRoot, name, values = {}) {
  const extension = name === "validate-commit-msg" ? ".py" : ".sh"
  const script = join(projectRoot, ".agents", "hooks", `${name}${extension}`)
  if (!existsSync(script)) return { status: 0, stdout: "", stderr: "" }
  const result = spawnSync(script, [], {
    cwd: projectRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      AGENT_PROJECT_DIR: projectRoot,
      AGENT_REMOTE: process.env.AGENT_REMOTE ?? "false",
      AGENT_ENV_FILE: process.env.AGENT_ENV_FILE ?? "",
      AGENT_SESSION_ID: values.sessionID ?? "session",
      AGENT_TOOL_NAME: values.toolName ?? "",
      AGENT_COMMAND: values.command ?? "",
      AGENT_FILE_PATH: values.filePath ?? "",
    },
  })
  return { status: result.status ?? 1, stdout: result.stdout ?? "", stderr: result.stderr ?? "" }
}

export const AgentHooks = async ({ directory, worktree }) => {
  const projectRoot = worktree || directory
  return {
    event: async ({ event }) => {
      if (event.type !== "session.created") return
      const script = join(projectRoot, ".agents", "hooks", "session-start.sh")
      if (!existsSync(script)) return
      const child = spawn(script, [], {
        cwd: projectRoot,
        detached: true,
        stdio: "ignore",
        env: {
          ...process.env,
          AGENT_PROJECT_DIR: projectRoot,
          AGENT_REMOTE: process.env.AGENT_REMOTE ?? "false",
          AGENT_ENV_FILE: process.env.AGENT_ENV_FILE ?? "",
          AGENT_SESSION_ID: event.properties.info.id,
        },
      })
      child.unref()
    },
    "experimental.chat.system.transform": async (_input, output) => {
      const result = runHook(projectRoot, "platform-guidance")
      if (result.stdout.trim()) output.system.push(result.stdout.trim())
    },
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return
      const result = runHook(projectRoot, "validate-commit-msg", {
        sessionID: input.sessionID,
        toolName: input.tool,
        command: output.args.command ?? "",
      })
      if (result.status !== 0) {
        throw new Error(result.stderr.trim() || "Commit message rejected by repository policy.")
      }
    },
  }
}
