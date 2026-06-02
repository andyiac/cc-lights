# Claude Code Status Light

macOS 状态栏四色状态灯 App，用于根据本地状态文件显示 Claude Code 当前状态。

## 状态

| 命令状态 | 颜色 | 含义 |
| --- | --- | --- |
| `working` | 蓝色 | Claude Code 正在自动执行任务 |
| `waiting` | 黄色 | 需要用户做决策 |
| `idle` | 绿色 | 空闲或上次任务完成 |
| `error` | 红色 | 执行失败或异常 |

## 运行

```bash
make run
```

## 打包为 macOS App

```bash
make bundle
open "dist/Claude Code Status Light.app"
```

如需安装到应用程序目录：

```bash
make install
```

## 更新状态

打包后会生成 `dist/cc-statusctl`，也可以用 `swift run cc-statusctl`：

```bash
swift run cc-statusctl working --task "编译 main.go"
swift run cc-statusctl waiting --message "需要确认危险操作"
swift run cc-statusctl error --message "构建失败"
swift run cc-statusctl reset
```

状态文件位置：

```bash
swift run cc-statusctl path
```
