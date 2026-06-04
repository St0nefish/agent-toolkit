import { slugFromBranchName } from "./git.mjs";

const EXPLICIT_WORKTREE_RE =
    /\b(worktree|in parallel|simultaneously|without touching(?: my)? current branch|clean checkout|isolated (?:checkout|environment)|separate branch|parallel checkout|background task|separate worktree)\b/i;
const ISSUE_SWITCH_RE = /\b(hotfix|urgent|another task|different task|separate issue|unrelated|while keeping)\b/i;
const BUG_RE = /\b(bug|fix|hotfix|regression|incident)\b/i;
const CHORE_RE = /\b(docs?|chore|cleanup|refactor|rename|reformat)\b/i;
const STOP_WORDS = new Set([
    "a",
    "an",
    "and",
    "for",
    "from",
    "in",
    "into",
    "my",
    "of",
    "on",
    "please",
    "the",
    "this",
    "to",
    "with",
]);

function tokenize(value) {
    return String(value || "")
        .toLowerCase()
        .split(/[^a-z0-9]+/)
        .filter((token) => token.length >= 3 && !STOP_WORDS.has(token));
}

export function promptHasExplicitWorktreeRequest(prompt) {
    return EXPLICIT_WORKTREE_RE.test(String(prompt || "").trim());
}

function promptLooksRelated(prompt, status) {
    const branchTokens = new Set(
        [status.currentBranch, ...status.linkedWorktrees.map((worktree) => worktree.branch)]
            .flatMap((branch) => tokenize(branch))
            .filter(Boolean),
    );

    if (branchTokens.size === 0) {
        return false;
    }

    return tokenize(prompt).some((token) => branchTokens.has(token));
}

export function recommendBranchName(prompt, branchNameHint) {
    if (branchNameHint) {
        return branchNameHint;
    }

    const tokens = tokenize(prompt).slice(0, 5);
    const slug = tokens.join("-") || "parallel-work";
    const prefix = BUG_RE.test(prompt) ? "bug" : CHORE_RE.test(prompt) ? "chore" : "wip";
    return `${prefix}-${slug}`;
}

export function suggestWorktree({ prompt, status, branchNameHint } = {}) {
    const request = String(prompt || "").trim();
    const explicit = promptHasExplicitWorktreeRequest(request);
    const issueSwitch = ISSUE_SWITCH_RE.test(request);
    const alreadyIsolated = status?.currentCheckoutType === "linked";
    const dirtyCount = status?.currentCheckout?.dirtyCount ?? 0;
    const related = status ? promptLooksRelated(request, status) : false;
    const shouldSuggest = !alreadyIsolated && (explicit || issueSwitch || (dirtyCount > 0 && !related));
    const recommendedBranch = recommendBranchName(request, branchNameHint);
    const recommendedSlug = slugFromBranchName(recommendedBranch) || "parallel-work";

    const reasons = [];
    if (explicit) {
        reasons.push("The prompt explicitly asks for isolated or parallel work.");
    }
    if (issueSwitch) {
        reasons.push("The prompt looks like a separate issue or urgent side task.");
    }
    if (dirtyCount > 0) {
        reasons.push(`The current checkout has ${dirtyCount} uncommitted change(s).`);
    }
    if (alreadyIsolated) {
        reasons.push("The session is already running inside a linked worktree.");
    }
    if (dirtyCount > 0 && !related) {
        reasons.push("The request does not obviously match the current branch name.");
    }

    return {
        shouldSuggest,
        explicit,
        alreadyIsolated,
        relatedToCurrentBranch: related,
        recommendedBranch,
        recommendedSlug,
        recommendedPath: status?.worktreeBaseDir
            ? `${status.worktreeBaseDir}/${recommendedSlug}`
            : `.github/worktrees/${recommendedSlug}`,
        reasons,
        commandExample: `git worktree add .github/worktrees/${recommendedSlug} -b ${recommendedBranch}`,
    };
}

export function formatSuggestionForLlm(suggestion, status) {
    const lines = [
        `Suggest worktree: ${suggestion.shouldSuggest ? "yes" : "no"}`,
        `Recommended branch: ${suggestion.recommendedBranch}`,
        `Recommended slug: ${suggestion.recommendedSlug}`,
        `Recommended path: ${suggestion.recommendedPath}`,
        `Command example: ${suggestion.commandExample}`,
    ];

    if (status?.ok) {
        lines.push(`Current branch: ${status.currentBranch}`);
        lines.push(`Current checkout type: ${status.currentCheckoutType}`);
        lines.push(`Active linked worktrees: ${status.activeLinkedWorktreeCount}`);
    }

    if (suggestion.reasons.length > 0) {
        lines.push("Reasons:");
        for (const reason of suggestion.reasons) {
            lines.push(`- ${reason}`);
        }
    }

    lines.push("Suggestion JSON:");
    lines.push(JSON.stringify(suggestion, null, 2));
    return lines.join("\n");
}
