-- Lua.lua
-- 系统信息桥接表盘
-- 将 /proc/ 数据写入快应用共享目录

local TARGET_DIR = '/data/quickapp/files/com.liangyi.lua.sync/'
local isRunning = false
local sysTimer = nil
local statusBuffer = {}

-- ====== UI ======

local root = lvgl.Object(nil, {
    w = lvgl.HOR_RES(),
    h = lvgl.VER_RES(),
    align = lvgl.ALIGN.CENTER,
    border_width = 0,
    bg_color = '#000000',
})
root:clear_flag(lvgl.FLAG.SCROLLABLE)

local terminal = lvgl.Textarea(root, {
    w = lvgl.HOR_RES() - 10,
    h = lvgl.VER_RES() - 80,
    x = 5,
    y = 5,
    text = '',
    bg_color = '#000000',
    font_size = 18,
    text_color = '#00ff00',
    border_width = 0
})

local controlPanel = lvgl.Object(root, {
    x = 0,
    y = lvgl.VER_RES() - 70,
    w = lvgl.HOR_RES(),
    h = 70,
    bg_color = '#111111',
    border_width = 0
})
controlPanel:clear_flag(lvgl.FLAG.SCROLLABLE)

local startStopBtn = lvgl.Label(controlPanel, {
    x = 20,
    y = 5,
    w = 120,
    h = 45,
    text = "START",
    radius = 5,
    border_width = 1,
    border_color = '#00ff00',
    bg_color = '#004400',
    font_size = 32,
    text_color = '#00ff00'
})
startStopBtn:add_flag(lvgl.FLAG.CLICKABLE)

local clearBtn = lvgl.Label(controlPanel, {
    x = 160,
    y = 5,
    w = 120,
    h = 45,
    text = "CLEAR",
    radius = 5,
    border_width = 1,
    border_color = '#ffaa00',
    bg_color = '#443300',
    font_size = 32,
    text_color = '#ffaa00'
})
clearBtn:add_flag(lvgl.FLAG.CLICKABLE)

-- ====== 工具函数 ======

local function readFile(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local c = f:read('*all')
    f:close()
    return c
end

local function addLog(line)
    table.insert(statusBuffer, 1, line)
    while #statusBuffer > 20 do table.remove(statusBuffer) end
    local t = "=== SysInfo Bridge ===\nStatus: " .. (isRunning and "RUNNING" or "STOPPED") .. "\n" .. string.rep("-", 28) .. "\n"
    for i = 1, #statusBuffer do t = t .. statusBuffer[i] .. "\n" end
    terminal:set { text = t }
end

-- ====== /proc/ 采集 ======

local function readCpuLoad()
    local c = readFile('/proc/cpuload')
    if not c then return '0%' end
    local val = c:match('([%d%.]+)')
    if not val then return '0%' end
    local pct = math.floor(tonumber(val) or 0)
    return tostring(math.min(pct, 100)) .. '%'
end

local function readCpuInfo()
    local c = readFile('/proc/cpuinfo')
    if not c then return 'N/A' end
    c = c:gsub('^%s+', ''):gsub('%s+$', '')
    -- 在字段间插入换行：按已知字段名拆分（英文名→中文名）
    local fieldNames = {'processor', 'BogoMIPS', 'cpu MHz', 'Features', 'model name',
                        'CPU architecture', 'CPU implementer', 'CPU variant', 'CPU part', 'CPU revision'}
    local cnNames = {
        processor = '处理器', BogoMIPS = 'BogoMIPS', ['cpu MHz'] = '主频',
        Features = '特性', ['model name'] = '型号名称',
        ['CPU architecture'] = 'CPU 架构', ['CPU implementer'] = 'CPU 实现者',
        ['CPU variant'] = 'CPU 变体', ['CPU part'] = 'CPU 部分',
        ['CPU revision'] = 'CPU 修订版'
    }
    local result = {}
    local pos = 1
    while pos <= #c do
        local found = false
        for _, name in ipairs(fieldNames) do
            local startPos = c:find(name .. '%s*:', pos)
            if startPos and startPos == pos then
                local nextPos = #c + 1
                for _, n2 in ipairs(fieldNames) do
                    if n2 ~= name then
                        local p = c:find(n2 .. '%s*:', startPos + #name)
                        if p and p < nextPos then nextPos = p end
                    end
                end
                local val = c:sub(startPos + #name + 1, nextPos - 1)
                val = val:gsub('^%s*:%s*', ''):gsub('^%s+', ''):gsub('%s+$', '')
                local displayName = cnNames[name] or name
                result[#result+1] = displayName .. ': ' .. val
                pos = nextPos
                found = true
                break
            end
        end
        if not found then
            local nl = c:find('\n', pos)
            if nl then
                result[#result+1] = c:sub(pos, nl-1)
                pos = nl + 1
            else
                result[#result+1] = c:sub(pos)
                break
            end
        end
    end
    return table.concat(result, '\n')
end

local function readCpuFreq()
    local c = readFile('/proc/cpuinfo')
    if not c then return 'N/A' end
    local mhz = c:match('cpu MHz%s*:%s*([%d%.]+)')
    if mhz then return math.floor(tonumber(mhz)) .. ' MHz' end
    return 'N/A'
end

local function readMemInfo()
    local c = readFile('/proc/meminfo')
    if not c then return {} end
    local result = {}
    for label, total, used, free in c:gmatch('([%w_]+):%s*(%d+)%s+(%d+)%s+(%d+)') do
        result[label] = { total = tonumber(total), used = tonumber(used), free = tonumber(free) }
    end
    return result
end

local function readVersion()
    local c = readFile('/proc/version')
    return c and c:match('[^\n]+') or 'N/A'
end



-- ====== JSON 序列化 ======

local function jsonEncode(val)
    local t = type(val)
    if t == 'string' then
        return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
    elseif t == 'number' then
        if val == math.floor(val) then return string.format('%d', val) end
        return string.format('%g', val)
    elseif t == 'boolean' then return tostring(val)
    elseif t == 'nil' then return 'null'
    elseif t == 'table' then
        local parts = {}
        local maxNum, count = 0, 0
        for k in pairs(val) do
            count = count + 1
            if type(k) == 'number' and k > maxNum then maxNum = k end
        end
        if maxNum == count then
            for i = 1, count do parts[#parts+1] = jsonEncode(val[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            local keys = {}
            for k in pairs(val) do keys[#keys+1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                parts[#parts+1] = jsonEncode(k) .. ':' .. jsonEncode(val[k])
            end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    return 'null'
end

-- ====== 写文件（临时文件 + 重命名，原子写入）======

local writeSeq = 0

local function writeJsonToFile(filename, data)
    data.seq = writeSeq
    writeSeq = writeSeq + 1
    local json = jsonEncode(data)
    local tmp = TARGET_DIR .. '.' .. filename .. '.tmp'
    local path = TARGET_DIR .. filename

    os.execute('mkdir -p ' .. TARGET_DIR)
    local f = io.open(tmp, 'w')
    if not f then return false end
    f:write(json)
    f:close()
    os.remove(path)
    os.execute('mv "' .. tmp .. '" "' .. path .. '"')
    return true
end

-- ====== 采集与写入 ======

local function collect()
    local memInfo = readMemInfo()
    local ts = os.date('%H:%M:%S')

    local sysInfo = {
        timestamp = ts,
        cpu = { load = readCpuLoad(), info = readCpuInfo(), freq = readCpuFreq() },
        memory = {},
        version = readVersion()
    }

    -- 各内存区域 + 合计
    local totalAll, usedAll, freeAll = 0, 0, 0
    for label, data in pairs(memInfo) do
        local t = math.floor(data.total / 1048576 * 100) / 100
        local u = math.floor(data.used / 1048576 * 100) / 100
        local f = math.floor(data.free / 1048576 * 100) / 100
        sysInfo.memory[label] = { total_mb = t, used_mb = u, free_mb = f }
        totalAll = totalAll + data.total
        usedAll = usedAll + data.used
        freeAll = freeAll + data.free
    end
    sysInfo.memory.total = {
        total_mb = math.floor(totalAll / 1048576 * 100) / 100,
        used_mb = math.floor(usedAll / 1048576 * 100) / 100,
        free_mb = math.floor(freeAll / 1048576 * 100) / 100
    }

    local ok = writeJsonToFile('system_info.json', sysInfo)
    if ok then
        addLog('[' .. ts .. '] system_info.json written')
    else
        addLog('[' .. ts .. '] FAILED write system_info.json')
    end
end

-- ====== 启动/停止 ======

local function startService()
    if isRunning then return end
    isRunning = true

    -- 创建目标目录
    os.execute('mkdir -p ' .. TARGET_DIR)

    local interval = 1000

    addLog('Target: ' .. TARGET_DIR)
    addLog('Interval: ' .. interval .. ' ms')
    addLog('>>> Service Started')

    collect()

    sysTimer = lvgl.Timer({
        period = interval,
        repeat_count = -1,
        cb = function() collect() end
    })
    sysTimer:resume()

    startStopBtn:set { text = "STOP", bg_color = '#440000', border_color = '#ff0000', text_color = '#ff0000' }
end

local function stopService()
    if not isRunning then return end
    isRunning = false
    if sysTimer then sysTimer:pause() end
    addLog('>>> Service Stopped')
    startStopBtn:set { text = "START", bg_color = '#004400', border_color = '#00ff00', text_color = '#00ff00' }
end

local function clearLog()
    statusBuffer = {}
    local t = "=== SysInfo Bridge ===\nStatus: " .. (isRunning and "RUNNING" or "STOPPED") .. "\n" .. string.rep("-", 28) .. "\n"
    terminal:set { text = t }
end

-- ====== 按钮事件 ======

startStopBtn:onevent(lvgl.EVENT.CLICKED, function()
    if isRunning then stopService() else startService() end
end)

clearBtn:onevent(lvgl.EVENT.CLICKED, function()
    clearLog()
end)

-- ====== 初始状态 ======

terminal:set { text = "=== SysInfo Bridge ===\nStatus: STOPPED\n\nPress START to begin\ncollecting system info\nand writing to shared dir." }
