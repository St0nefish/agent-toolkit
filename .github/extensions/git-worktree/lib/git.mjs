import { execFile } from "node:child_process";
import { access } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export const DEFAULT_WORKTREE_SUBDIR = path.join(".github", "worktrees");

export async function runCommand(file, args, { cwd } = {}) {
    try {
        const { stdout, stderr } = await execFileAsync(file, args, {
            cwd,
            env: {
                ...process.env,
                GIT_PAGER: "cat",
                PAGER: "cat",
            },
            maxBuffer: 8 * 1024 * 1024,
        });

        return {
            ok: true,
            code: 0,
            stdout: stdout.trimEnd(),
            stderr: stderr.trimEnd(),
        };
    } catch (error) {
        return {
            ok: false,
            code: Number.isInteger(error?.code) ? error.code : 1,
            stdout: String(error?.stdout ?? "").trimEnd(),
            stderr: String(error?.stderr ?? "").trimEnd(),
            message: error?.message ?? "Command failed",
        };
    }
}

export function normalizeCwd(cwd) {
    return cwd || process.cwd();
}

export async function runGit(args, { cwd } = {}) {
    return runCommand("git", args, { cwd: normalizeCwd(cwd) });
}

export async function runWorktreeScript(scriptPath, scriptArgs, { cwd } = {}) {
    return runCommand("bash", [scriptPath, ...scriptArgs], { cwd: normalizeCwd(cwd) });
}

export function slugFromBranchName(branchName) {
    return String(branchName || "")
        .replaceAll("/", "-")
        .replace(/[^a-zA-Z0-9._-]/g, "-")
        .replace(/-+/g, "-")
        .replace(/^-/, "")
        .replace(/-$/, "");
}

export function parseWorktreePorcelain(stdout) {
    const records = [];
    let current = null;

    for (const line of String(stdout || "").split("\n")) {
        if (!line.trim()) {
            if (current?.path) {
                records.push(current);
            }
            current = null;
            continue;
        }

        if (line.startsWith("worktree ")) {
            if (current?.path) {
                records.push(current);
            }
            current = { path: line.slice("worktree ".length) };
            continue;
        }

        if (!current) {
            continue;
        }

        if (line.startsWith("HEAD ")) {
            current.head = line.slice("HEAD ".length);
        } else if (line.startsWith("branch ")) {
            current.branch = line.slice("branch refs/heads/".length);
        } else if (line === "detached") {
            current.branch = "detached";
            current.detached = true;
        } else if (line.startsWith("locked")) {
            current.locked = true;
        } else if (line.startsWith("prunable")) {
            current.prunable = true;
        }
    }

    if (current?.path) {
        records.push(current);
    }

    return records;
}

export async function pathExists(targetPath) {
    try {
        await access(targetPath);
        return true;
    } catch {
        return false;
    }
}

export function repoWorktreeBaseDir(mainRepoRoot) {
    return path.join(mainRepoRoot, DEFAULT_WORKTREE_SUBDIR);
}

export function summarizeCommandFailure(label, result) {
    return {
        textResultForLlm: [
            `${label} failed with exit code ${result.code}.`,
            result.stderr || result.stdout || result.message,
        ]
            .filter(Boolean)
            .join("\n"),
        resultType: "failure",
    };
}
