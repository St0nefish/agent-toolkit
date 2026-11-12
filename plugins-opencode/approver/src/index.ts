import { Plugin } from "@opencode/plugin"
import { registerPermissionHook } from "./hook.js"

export default Plugin.define({
	id: "agent-toolkit.approver",
	async setup(ctx) {
		const reg = await registerPermissionHook(ctx)
		return () => {
			void reg?.dispose?.()
		}
	},
})
