# 授权隔离与外部操作交接

授权隔离把“Claude 生成内容”和“宿主执行外部操作”拆成两个边界：

- Claude 只能访问本次工作副本、交换目录和经中继的 Claude 网络路径。
- Claude 不读取 Git remote、SSH key、GitHub token、Notion token、Cookie 或其他宿主凭据。
- Claude 把外部操作写成 JSON 清单和同目录交付文件。
- Routekeeper 校验并在界面中展示实际交付数据，等待用户确认。
- 宿主侧执行保存文件或应用 Git 补丁；不会自动提交或推送。

## 交接目录

每个沙箱会话会在用户选择的交换目录下准备：

```text
$ISOLATION_EXCHANGE/.routekeeper-actions/
```

清单必须是该目录的直接子文件，payload 也必须是同目录内的普通文件。符号链接、路径穿越、绝对路径、URL、凭据标记以及超限文件会被拒绝。

Routekeeper 在扫描时把 payload 读入内存并计算 SHA256。用户审阅和宿主执行使用这份冻结数据；即使 Claude 随后修改交换目录中的文件，也不会改变已经加载的待确认内容。

## 清单格式

```json
{
  "schemaVersion": 1,
  "requestID": "6F3D94B8-52AB-4CF5-BD79-DAC1B1B97D9B",
  "kind": "file.export",
  "title": "交付审阅后的文档",
  "summary": "保存一份 Markdown 文档到宿主选择的位置。",
  "payload": "reviewed.md",
  "suggestedName": "reviewed.md"
}
```

## 当前操作类型

### `file.export`

- 用户在宿主侧选择保存位置。
- Routekeeper 原子写入经过审阅的 payload。
- 适用于 Notion 草稿、Markdown、JSON、图片和其他交付文件。
- 当前不会直接调用 Notion API，也不会把 Notion token 交给 Claude。

### `git.applyPatch`

- payload 必须是 `.patch` 或 `.diff`。
- 用户选择一个宿主 Git 仓库。
- Routekeeper 先执行 `git apply --check`，通过后才执行 `git apply`。
- 使用 `--no-unsafe-paths`，并拒绝尝试修改 `.git` 元数据的补丁。
- 改动保持未暂存状态；Routekeeper 不会 commit、push、读取 remote 或使用 Git 凭据。

## 安全边界

授权隔离可以避免 Claude 获得宿主 Git 和外部服务凭据，但不能阻止已经进入 Claude 上下文的正文内容被发送给 Anthropic。用户仍需在批准前检查实际操作目标和 payload。

该功能也不等价于系统级防火墙。其他应用和宿主浏览器不受 Claude 进程沙箱限制。
