# 小米手环9Pro 更多的设备信息

一个适用于小米手环9Pro的 **Lua 表盘 + 快应用** 联动工具，在手环上实时查看设备系统信息。

快应用多屏适配了小米手环9/10，lua表盘未适配，未测试是否能正常使用

## 功能

- **Lua 表盘采集 + 快应用展示**，手环本地运行
- **实时 CPU 折线图**，50 个采样点的柱状图
- **内存详情**，展示内存各区域及合计
- **设备信息**，读取所有快应用可读取的设备信息
- **CPU 信息**，显示 /proc/cpuinfo 全部字段（架构、主频、特性等）
- **信息汇总**，生成设备信息日志

## 项目结构

```
设备信息/
├── Lua_to_quickapp_lua/          ← Lua 表盘
│   ├── app/_lua/Lua/
│   │   └── Lua.lua               ← 采集核心（/proc/ 读取 + JSON 序列化）
│   └── Lua.fprj                  ← 表盘项目文件
│
└── Lua_to_quickapp_quickapp/     ← 快应用
    └── src/
        ├── manifest.json          ← 应用配置
        └── pages/
            ├── index/index.ux     ← 首页（所有数据卡片入口）
            ├── cpuchart/cpuchart.ux ← CPU 监控折线图
            ├── cpulog/cpulog.ux   ← CPU 信息详情
            ├── memory/memory.ux   ← 内存信息详情
            ├── datalog/datalog.ux ← 系统数据汇总
            ├── summary/summary.ux ← 设备信息汇总日志
            ├── info/info.ux       ← 设备 API 全字段
            ├── help/help.ux       ← 使用说明
            └── about/about.ux     ← 关于（全屏 about.png）
```

## 安装

### 1. 安装 Lua 表盘

1. 使用Easyface打开 `Lua_to_quickapp_lua/Lua.fprj`
2. 编译并安装二进制文件到手环
3. 在手环上运行该表盘
4. 点击 **START** 开始采集

### 2. 安装快应用

1. 使用 AIoT IDE 打开 `Lua_to_quickapp_quickapp/`
2. 编译打包并安装到手环

### 3. 使用

1. 在手环上运行 Lua 表盘，点击 START
2. 打开快应用，即可看到实时数据
3. 首次启动会蓝底高亮"使用说明"入口

### 4.资源
项目附小米手环9Pro文件结构
/proc中所有内容的输出

### 5.鸣谢
sf-yuzifu/daymatter (https://github.com/sf-yuzifu/daymatter/tree/watchface/band9pro)

-参考其 Lua 表盘与快应用通过文件系统共享数据的架构设计
