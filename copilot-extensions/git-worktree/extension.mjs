import path from "node:path";
import { fileURLToPath } from "node:url";

import { joinSession } from "@github/copilot-sdk/extension";

import { normalizeCwd, runWorktreeScript, summarizeCommandFailure } from "./lib/git.mjs";
import { formatStatusForLlm, getWorktreeStatus } from "./lib/status.mjs";
import { formatSuggestionForLlm, suggestWorktree } from "./lib/suggest.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const scriptsDir = path.join(__dirname, "scripts");
const sessionState = {
    cwd: process.cwd(),
};

function resolveCwd(inputCwd) {
    return normalizeCwd(inputCwd || sessionState.cwd);
}

async function handleCreate({ branchName, fromBranch, cwd }) {
    const runResult = await runWorktreeScript(
        path.join(scriptsDir, "worktree-create.sh"),
        fromBranch ? [branchName, "--from", fromBranch] : [branchName],
        { cwd: resolveCwd(cwd) },
    );

    if (!runResult.ok) {
        return summarizeCommandFailure("git worktree create", runResult);
    }

    const status = await getWorktreeStatus({ cwd: resolveCwd(cwd) });
    const created = status.ok
        ? status.linkedWorktrees.find((worktree) => worktree.branch === branchName)
        : null;

    return [
        `Created linked worktree for branch ${branchName}.`,
        created ? `Path: ${created.path}` : null,
        runResult.stdout || null,
    ]
        .filter(Boolean)
        .join("\n");
}

async function handleRemove({ target, deleteBranch, force, cwd }) {
    const args = [target];
    if (deleteBranch) {
        args.push("--delete-branch");
    }
    if (force) {
        args.push("--force");
    }

    const runResult = await runWorktreeScript(path.join(scriptsDir, "worktree-remove.sh"), args, {
        cwd: resolveCwd(cwd),
    });

    if (!runResult.ok) {
        return summarizeCommandFailure("git worktree remove", runResult);
    }

    return runResult.stdout || `Removed worktree target ${target}.`;
}

await joinSession({
    hooks: {
        onPreToolUse: async (input) => {
            if (input.toolName?.startsWith("sf_git_worktree_")) {
                return { permissionDecision: "allow" };
            }
        },
    },
    tools: [
        {
            name: "sf_git_worktree_status",
            description:
                "Inspect git worktree state for the current repository: current checkout type, branch, main repo root, worktree base dir, linked worktrees, and dirty state.",
            parameters: {
                type: "object",
                properties: {
                    cwd: {
                        type: "string",
                        description:
                            "Optional working directory to inspect. Defaults to the session checkout path captured when the extension loaded.",
                    },
                },
            },
            handler: async ({ cwd } = {}) => {
                const status = await getWorktreeStatus({ cwd: resolveCwd(cwd) });
                if (!status.ok) {
                    return {
                        textResultForLlm: `Git worktree status unavailable: ${status.error}`,
                        resultType: "failure",
                    };
                }
                return formatStatusForLlm(status);
            },
        },
        {
            name: "sf_git_worktree_create",
            description:
                "Create a linked git worktree under .github/worktrees/<slug> for parallel work. Supports optional fromBranch. Use for create worktree / parallel checkout requests.",
            parameters: {
                type: "object",
                properties: {
                    branchName: {
                        type: "string",
                        description: "Branch to check out in the new linked worktree.",
                    },
                    fromBranch: {
                        type: "string",
                        description: "Optional base branch when creating a brand-new branch.",
                    },
                    cwd: {
                        type: "string",
                        description: "Optional working directory inside the target repository.",
                    },
                },
                required: ["branchName"],
            },
            handler: async (args) => handleCreate(args),
        },
        {
            name: "sf_git_worktree_remove",
            description:
                "Remove a linked git worktree by slug or absolute path. Supports deleteBranch and force. Use for remove worktree / clean up worktree requests.",
            parameters: {
                type: "object",
                properties: {
                    target: {
                        type: "string",
                        description: "Worktree slug under .github/worktrees or an absolute worktree path.",
                    },
                    deleteBranch: {
                        type: "boolean",
                        description: "Also delete the worktree branch with git branch -d after removal.",
                    },
                    force: {
                        type: "boolean",
                        description: "Force removal when the worktree has uncommitted changes.",
                    },
                    cwd: {
                        type: "string",
                        description: "Optional working directory inside the target repository.",
                    },
                },
                required: ["target"],
            },
            handler: async (args) => handleRemove(args),
        },
        {
            name: "sf_git_worktree_suggest",
            description:
                "Suggest whether a task should run in a separate git worktree. Use when the user wants parallel or isolated work, or when current changes look unrelated.",
            parameters: {
                type: "object",
                properties: {
                    prompt: {
                        type: "string",
                        description: "Short description of the work being considered for parallel execution.",
                    },
                    branchNameHint: {
                        type: "string",
                        description: "Optional branch name to prefer if the tool recommends a worktree.",
                    },
                    cwd: {
                        type: "string",
                        description: "Optional working directory inside the target repository.",
                    },
                },
                required: ["prompt"],
            },
            handler: async ({ prompt, branchNameHint, cwd }) => {
                const status = await getWorktreeStatus({ cwd: resolveCwd(cwd) });
                if (!status.ok) {
                    return {
                        textResultForLlm: `Cannot evaluate worktree suggestion outside a git repository: ${status.error}`,
                        resultType: "failure",
                    };
                }

                const suggestion = suggestWorktree({
                    prompt,
                    status,
                    branchNameHint,
                });

                return formatSuggestionForLlm(suggestion, status);
            },
        },
    ],
});
