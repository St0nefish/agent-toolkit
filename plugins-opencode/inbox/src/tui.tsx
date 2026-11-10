import { Plugin } from "@opencode/plugin/tui"
import { Inbox } from "./rpc.js"

// M0 scaffold: proves the RPC + TUI slot wiring end to end. M3 replaces this
// with the seeded signal, sidebar block, and triage panel.
export default Plugin.define({
  id: "agent-toolkit.inbox.tui",
  setup(context) {
    return context.ui.slot({
      append: "home.footer.status",
      render: () => {
        void context.client.rpc(Inbox)
        return null
      },
    })
  },
})
