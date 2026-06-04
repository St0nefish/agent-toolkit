import path from "node:path";

import {
    parseWorktreePorcelain,
    pathExists,
    repoWorktreeBaseDir,
    runGit,
} from "./git.mjs";

async function readDirtyCount(cwd) {
    const statusResult = await runGit(["status", "--porcelain"], { cwd });
    if (!statusResult.ok) {
        return null;
    }

    const lines = statusResult.stdout ? statusResult.stdout.split("\n").filter(Boolean) : [];
    return lines.length;
}

export async function getWorktreeStatus({ cwd } = {}) {
    const gitRootResult = await runGit(["rev-parse", "--show-toplevel"], { cwd });
    if (!gitRootResult.ok) {
        return {
            ok: false,
            error: gitRootResult.stderr || "Not inside a git repository.",
        };
    }

    const currentPath = gitRootResult.stdout.trim();
    const branchResult = await runGit(["branch", "--show-current"], { cwd: currentPath });
    const listResult = await runGit(["worktree", "list", "--porcelain"], { cwd: currentPath });

    if (!listResult.ok) {
        return {
            ok: false,
            error: listResult.stderr || "Unable to read git worktree state.",
        };
    }

    const records = parseWorktreePorcelain(listResult.stdout);
    const mainRepoRoot = records[0]?.path || currentPath;
    const currentCheckoutType = currentPath === mainRepoRoot ? "main" : "linked";

    const worktrees = [];
    for (const record of records) {
        const exists = await pathExists(record.path);
        const dirtyCount = exists ? await readDirtyCount(record.path) : null;
        worktrees.push({
            path: record.path,
            branch: record.branch || "unknown",
            head: record.head || "unknown",
            exists,
            dirtyCount,
            status: !exists ? "missing" : dirtyCount === 0 ? "clean" : `${dirtyCount} modified`,
            isMain: record.path === mainRepoRoot,
            isCurrent: record.path === currentPath,
        });
    }

    const currentEntry =
        worktrees.find((entry) => entry.path === currentPath) ||
        {
            path: currentPath,
            branch: branchResult.stdout.trim() || "detached",
            head: "unknown",
            exists: true,
            dirtyCount: await readDirtyCount(currentPath),
            status: "unknown",
            isMain: currentCheckoutType === "main",
            isCurrent: true,
        };

    return {
        ok: true,
        cwd: currentPath,
        currentCheckoutType,
        currentBranch: branchResult.stdout.trim() || currentEntry.branch,
        mainRepoRoot,
        worktreeBaseDir: repoWorktreeBaseDir(mainRepoRoot),
        currentCheckout: currentEntry,
        activeLinkedWorktreeCount: worktrees.filter((entry) => !entry.isMain).length,
        linkedWorktrees: worktrees.filter((entry) => !entry.isMain),
        worktrees,
        isInRepoManagedWorktree:
            currentCheckoutType === "linked" && currentPath.startsWith(`${repoWorktreeBaseDir(mainRepoRoot)}${path.sep}`),
    };
}

export function formatStatusForLlm(status) {
    if (!status.ok) {
        return `Git worktree status unavailable: ${status.error}`;
    }

    const lines = [
        `Current checkout: ${status.cwd}`,
        `Checkout type: ${status.currentCheckoutType}`,
        `Current branch: ${status.currentBranch || "detached"}`,
        `Main repo root: ${status.mainRepoRoot}`,
        `Worktree base dir: ${status.worktreeBaseDir}`,
        `Active linked worktrees: ${status.activeLinkedWorktreeCount}`,
        `Current checkout status: ${status.currentCheckout.status}`,
    ];

    if (status.linkedWorktrees.length === 0) {
        lines.push("Linked worktrees: none");
    } else {
        lines.push("Linked worktrees:");
        for (const worktree of status.linkedWorktrees) {
            lines.push(`- ${worktree.path} :: ${worktree.branch} :: ${worktree.status}`);
        }
    }

    lines.push("State JSON:");
    lines.push(JSON.stringify(status, null, 2));
    return lines.join("\n");
}
